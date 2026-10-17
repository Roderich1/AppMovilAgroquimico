import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/sync/central_binding_store.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/sync/campaign_period_check.dart';
import '../../domain/sync/central_references.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_access.dart';
import '../../services/sync/sync_api.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/sync_status_banner.dart' show syncSummaryProvider;

class _LocalCatalog {
  const _LocalCatalog(
    this.campaigns,
    this.products,
    this.campaignBindings,
    this.productBindings,
    this.reviews,
  );
  final List<Map<String, Object?>> campaigns;
  final List<Map<String, Object?>> products;
  final Map<int, CampaignBinding> campaignBindings;
  final Map<int, ProductBinding> productBindings;

  /// Vínculos de campaña que requieren revisión por su período (D-F04-C2).
  final List<CampaignBindingReview> reviews;
}

/// Vincular campañas y productos locales con el catálogo del sindicato
/// (F05-SYNC-08). Cada vínculo nace de una elección confirmada: nunca por
/// coincidencia de nombre. Sin conexión se conservan los vínculos existentes
/// y la base local sigue disponible.
///
/// D-F04-C2: el período local tiene que caber en el de la campaña central.
/// Un vínculo incompatible se rechaza con los dos períodos; si la campaña
/// local no tiene fin y la central sí, aquí mismo se fija el fin previsto,
/// sin cerrar la campaña.
class CentralBindingScreen extends ConsumerStatefulWidget {
  const CentralBindingScreen({super.key});
  @override
  ConsumerState<CentralBindingScreen> createState() =>
      _CentralBindingScreenState();
}

class _CentralBindingScreenState extends ConsumerState<CentralBindingScreen> {
  late Future<_LocalCatalog> local;
  CentralReferences? references;
  String? loadProblem;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    local = _readLocal();
  }

  Future<_LocalCatalog> _readLocal() async {
    final repository = ref.read(repositoryProvider);
    final bindings = ref.read(centralBindingStoreProvider);
    final campaigns = await repository.campaigns();
    final campaignBindings = await bindings.campaignBindings();
    return _LocalCatalog(
      campaigns,
      await repository.products(),
      {for (final b in campaignBindings) b.campaignId: b},
      {for (final b in await bindings.productBindings()) b.productId: b},
      await CentralBindingStore.reviewsFor(
        await ref.read(databaseProvider).database,
        bindings: campaignBindings,
        periods: {
          for (final row in campaigns)
            row['id']! as int: CampaignPeriod.fromRow(row),
        },
      ),
    );
  }

  void _reloadLocal() {
    final next = _readLocal();
    setState(() {
      local = next;
    });
    ref.invalidate(syncSummaryProvider);
  }

  Future<void> _loadReferences() async {
    setState(() {
      loading = true;
      loadProblem = null;
    });
    try {
      final loaded = await ref
          .read(syncControllerProvider.notifier)
          .loadReferences();
      if (!mounted) return;
      setState(() => references = loaded);
      _reloadLocal();
    } on SyncAccessUnavailable catch (error) {
      if (mounted) setState(() => loadProblem = error.message);
    } on SyncQueryException catch (error) {
      if (mounted) {
        setState(
          () => loadProblem = error.forbidden
              ? 'El sindicato no autorizó esta cuenta o este dispositivo.'
              : error.authRequired
              ? 'Se requiere volver a verificar el acceso en línea.'
              : 'No se pudieron leer las referencias del sindicato. '
                    'Los vínculos existentes se conservan.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => loadProblem = friendlyError(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _confirm(String local, String central, {String? note}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar vínculo'),
          content: Text(
            'Vincular «$local» de este teléfono con «$central» del sindicato. '
            'Sólo se enviarán totales con esa referencia.'
            '${note == null ? '' : '\n\n$note'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vincular'),
            ),
          ],
        ),
      ) ??
      false;

  Future<T?> _choose<T>(String title, List<(T, String, String?)> options) =>
      showDialog<T>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(title),
          children: [
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay opciones disponibles en el sindicato.'),
              ),
            for (final (value, label, disabledReason) in options)
              ListTile(
                enabled: disabledReason == null,
                title: Text(label),
                subtitle: disabledReason == null ? null : Text(disabledReason),
                onTap: () => Navigator.pop(dialogContext, value),
              ),
          ],
        ),
      );

  String? get _tenant =>
      ref.read(syncAccessHolderProvider).current?.scope.tenantId;

  /// Período central legible, o null si sus fechas no se pueden leer.
  CentralPeriod? _centralPeriod(CentralCampaign central) {
    try {
      return CentralPeriod.of(central);
    } on FormatException {
      return null;
    }
  }

  /// Por qué no se puede elegir [central] para [local]; null si se puede.
  String? _disabledReason(CampaignPeriod local, CentralCampaign central) {
    if (!central.acceptsContributions) return 'No admite nuevos aportes';
    final period = _centralPeriod(central);
    if (period == null) return 'Fechas ilegibles: actualice las referencias';
    final mismatch = periodMismatch(local, period);
    if (mismatch == null) return null;
    return periodMismatchMessage(
      localName: local.name,
      local: local,
      centralName: central.name,
      central: period,
      mismatch: mismatch,
    );
  }

  Future<void> _bindCampaign(Map<String, Object?> campaign) async {
    final refs = references;
    final tenant = _tenant;
    if (refs == null || tenant == null) {
      showError(context, 'Actualice primero las referencias del sindicato.');
      return;
    }
    final local = CampaignPeriod.fromRow(campaign);
    final chosen = await _choose<CentralCampaign>(
      'Campaña del sindicato (local: ${local.describe})',
      [
        for (final central in refs.campaigns)
          (
            central,
            '${central.name} · ${_centralPeriod(central)?.describe ?? 'fechas ilegibles'}',
            _disabledReason(local, central),
          ),
      ],
    );
    if (chosen == null || !mounted) return;
    final period = _centralPeriod(chosen);
    if (!await _confirm(
      local.name,
      chosen.name,
      note: period == null
          ? null
          : 'Períodos: «${local.name}» ${local.describe}; «${chosen.name}» '
                '${period.describe}.',
    )) {
      return;
    }
    try {
      await ref
          .read(centralBindingStoreProvider)
          .bindCampaign(
            campaignId: campaign['id']! as int,
            central: chosen,
            tenantId: tenant,
          );
      if (mounted) showSuccess(context, 'Campaña vinculada.');
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    _reloadLocal();
  }

  /// D-F04-C2: fin previsto de una campaña activa o planificada, sin cerrarla.
  /// El repositorio vuelve a validar (fin ≥ inicio, sin solapes, ningún
  /// registro fuera) y revisa el vínculo central.
  Future<void> _setEnd(Map<String, Object?> campaign) async {
    final local = CampaignPeriod.fromRow(campaign);
    final binding =
        (await ref.read(centralBindingStoreProvider).campaignBindings())
            .where((b) => b.campaignId == local.id)
            .firstOrNull;
    if (!mounted) return;
    final centralEnd = binding?.centralEndDay;
    final initial = startOfLocalDay(
      local.endDay ?? centralEnd ?? localDay(DateTime.now()),
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: startOfLocalDay(local.startDay),
      lastDate: DateTime(2100),
      helpText:
          'Fin previsto de «${local.name}»'
          '${centralEnd == null ? '' : ' (sindicato: hasta el ${displayDay(centralEnd)})'}',
    );
    if (picked == null || !mounted) return;
    final pickedDay = localDay(picked);
    // Un fin ya pasado en la campaña activa deja los días siguientes sin
    // campaña: las compras y aplicaciones nuevas se rechazarán hasta que se
    // cree y active la siguiente (revisión de A sobre #116). Se advierte
    // antes de confirmar; el repositorio lo admite porque no rompe ninguna
    // invariante.
    final pastEnd =
        local.status == 'ACTIVE' &&
        pickedDay.compareTo(localDay(DateTime.now())) < 0;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Fijar fin previsto'),
            content: Text(
              '«${local.name}» pasará a ir del ${displayDay(local.startDay)} '
              'al ${displayDay(pickedDay)}. La campaña no se cierra ni '
              'cambia de estado; sólo se fija su período. Se rechaza si deja '
              'fuera algún registro o solapa otra campaña.'
              '${pastEnd ? '\n\nAtención: ese fin ya pasó. Desde hoy, las compras y aplicaciones nuevas no tendrán campaña y se rechazarán hasta que cree y active la siguiente.' : ''}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Fijar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref.read(repositoryProvider).setCampaignEnd(local.id, end: picked);
      if (mounted) showSuccess(context, 'Fin previsto fijado.');
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    _reloadLocal();
  }

  Future<void> _bindProduct(Map<String, Object?> product) async {
    final refs = references;
    final tenant = _tenant;
    if (refs == null || tenant == null) {
      showError(context, 'Actualice primero las referencias del sindicato.');
      return;
    }
    final localBase = BaseUnit.fromCode(product['base_unit']);
    final chosen = await _choose<CentralProduct>('Producto del sindicato', [
      for (final central in refs.products)
        (
          central,
          '${central.name} (${central.unit})',
          !central.linkable
              ? 'Unidad central sin equivalencia L/KG'
              : !central.isActive
              ? 'Inactivo en el sindicato'
              : central.baseUnit != localBase
              ? 'Unidad distinta: no se convierte'
              : null,
        ),
    ]);
    if (chosen == null || !mounted) return;
    if (!await _confirm(product['name']! as String, chosen.name)) return;
    try {
      await ref
          .read(centralBindingStoreProvider)
          .bindProduct(
            productId: product['id']! as int,
            central: chosen,
            tenantId: tenant,
          );
      if (mounted) showSuccess(context, 'Producto vinculado.');
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    _reloadLocal();
  }

  Future<void> _unbind(String label, Future<void> Function() action) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Quitar vínculo',
      detail:
          'Se quita el vínculo de «$label» con el sindicato. No se borra '
          'ninguna operación local.',
      confirmLabel: 'Quitar',
    );
    if (!confirmed) return;
    try {
      await action();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    _reloadLocal();
  }

  String _status(BindingStatus status, BindingInvalidReason? reason) =>
      status == BindingStatus.valid
      ? 'vigente'
      : 'inválido: ${reason!.message}';

  String _describeCampaign(CampaignBinding b, CampaignPeriod local) {
    final central = b.centralPeriod;
    final problem = (b.invalidReason?.holdsQueue ?? false)
        ? CentralBindingStore.periodProblem(b, local)
        : null;
    return '${b.centralName}'
        '${central == null ? '' : ' (${central.describe})'} · '
        '${_status(b.status, b.invalidReason)}'
        '${problem == null ? '' : '\n$problem'}';
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Vincular con el sindicato',
    subtitle:
        'Elija el equivalente del sindicato para cada campaña y producto. '
        'Nada se vincula por nombre. El período de la campaña local tiene que '
        'caber en el de la campaña del sindicato.',
    // Etiqueta corta: en una cabecera de móvil un botón ancho deja sin
    // espacio al título y al subtítulo.
    action: FilledButton.tonalIcon(
      onPressed: loading ? null : _loadReferences,
      icon: const Icon(Icons.cloud_download_outlined),
      label: const Text('Actualizar'),
    ),
    child: FutureBuilder<_LocalCatalog>(
      future: local,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading) const LinearProgressIndicator(),
            if (loadProblem != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(loadProblem!),
                ),
              ),
            if (references == null && loadProblem == null)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text(
                    'Actualice las referencias para vincular o revisar los '
                    'vínculos con el sindicato.',
                  ),
                ),
              ),
            if (data.reviews.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                key: const Key('period-review'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.event_busy_outlined),
                      title: Text('Requiere revisión: período de campaña'),
                      subtitle: Text(
                        'Estos vínculos no publican totales nuevos. Lo ya '
                        'aceptado por el sindicato se conserva tal cual y lo '
                        'que espera en la cola no se envía ni se borra. Fije '
                        'el fin previsto, corrija el vínculo o retire el total '
                        'desde «Consumo para el sindicato» o «Necesidades».',
                      ),
                    ),
                    for (final review in data.reviews)
                      ListTile(
                        title: Text(review.local.name),
                        subtitle: Text(
                          '${CentralBindingStore.periodProblem(review.binding, review.local) ?? ''}\n'
                          'Aportes aceptados con este vínculo: '
                          '${review.acceptedContributions} · en cola, '
                          'retenidos: ${review.heldIntentions}',
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Campañas', style: Theme.of(context).textTheme.titleMedium),
            Card(
              child: Column(
                children: [
                  for (final campaign in data.campaigns)
                    _campaignRow(campaign, data),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Productos', style: Theme.of(context).textTheme.titleMedium),
            Card(
              child: Column(
                children: [
                  for (final product in data.products)
                    _row(
                      label: '${product['name']} (${product['unit']})',
                      binding: data.productBindings[product['id']],
                      describe: (b) =>
                          '${b.centralName} · ${_status(b.status, b.invalidReason)}',
                      onBind: () => _bindProduct(product),
                      onUnbind: () => _unbind(
                        product['name']! as String,
                        () => ref
                            .read(centralBindingStoreProvider)
                            .unbindProduct(product['id']! as int),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _campaignRow(Map<String, Object?> campaign, _LocalCatalog data) {
    final local = CampaignPeriod.fromRow(campaign);
    final binding = data.campaignBindings[local.id];
    final canSetEnd = local.status == 'ACTIVE' || local.status == 'PLANNED';
    return ListTile(
      key: Key('campaign-binding-${local.id}'),
      title: Text('${local.name} (${local.describe})'),
      subtitle: Text(
        binding == null
            ? 'Requiere vinculación'
            : _describeCampaign(binding, local),
      ),
      isThreeLine: binding != null && !binding.isValid,
      trailing: PopupMenuButton<String>(
        tooltip: 'Opciones de vínculo',
        onSelected: (value) => switch (value) {
          'bind' => _bindCampaign(campaign),
          'end' => _setEnd(campaign),
          _ => _unbind(
            local.name,
            () =>
                ref.read(centralBindingStoreProvider).unbindCampaign(local.id),
          ),
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'bind',
            child: Text(binding == null ? 'Vincular…' : 'Corregir vínculo…'),
          ),
          if (canSetEnd)
            const PopupMenuItem(
              value: 'end',
              child: Text('Fijar fin previsto…'),
            ),
          if (binding != null)
            const PopupMenuItem(value: 'unbind', child: Text('Quitar vínculo')),
        ],
      ),
    );
  }

  Widget _row<B>({
    required String label,
    required B? binding,
    required String Function(B binding) describe,
    required VoidCallback onBind,
    required VoidCallback onUnbind,
  }) => ListTile(
    title: Text(label),
    subtitle: Text(
      binding == null ? 'Requiere vinculación' : describe(binding),
    ),
    trailing: PopupMenuButton<String>(
      tooltip: 'Opciones de vínculo',
      onSelected: (value) => value == 'bind' ? onBind() : onUnbind(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'bind',
          child: Text(binding == null ? 'Vincular…' : 'Corregir vínculo…'),
        ),
        if (binding != null)
          const PopupMenuItem(value: 'unbind', child: Text('Quitar vínculo')),
      ],
    ),
  );
}
