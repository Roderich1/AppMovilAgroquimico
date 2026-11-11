import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/sync/central_binding_store.dart';
import '../../data/sync/identification_request_store.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/sync/campaign_period_check.dart';
import '../../domain/sync/central_references.dart';
import '../../domain/sync/identification_view.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_access.dart';
import '../../services/sync/sync_api.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/identification_texts.dart';
import '../widgets/sync_status_banner.dart' show syncSummaryProvider;

class _LocalCatalog {
  const _LocalCatalog(
    this.campaigns,
    this.products,
    this.campaignBindings,
    this.productBindings,
    this.reviews,
    this.requests,
  );
  final List<Map<String, Object?>> campaigns;
  final List<Map<String, Object?>> products;
  final Map<int, CampaignBinding> campaignBindings;
  final Map<int, ProductBinding> productBindings;

  /// Solicitudes de identificación por producto local (E1).
  final Map<int, IdentificationRequest> requests;

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
    // Los productos y sus solicitudes de identificación en una sola
    // consulta, en lugar de `products()`: la pantalla no suma lecturas.
    final products = await ref
        .read(identificationRequestStoreProvider)
        .productsWithRequests();
    return _LocalCatalog(
      campaigns,
      [for (final item in products) item.product],
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
      {
        for (final item in products)
          if (item.request != null) item.request!.productId: item.request!,
      },
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
              '${pastEnd ? '\n\nAtención: ese fin ya pasó. Desde el día siguiente a ese fin, las compras y aplicaciones no tendrán campaña y se rechazarán hasta que cree y active la siguiente.' : ''}',
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
          _productDisabledReason(central, localBase),
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

  /// E1: pide al sindicato que identifique un producto local sin vínculo.
  /// El diálogo muestra exactamente lo que se enviará y, aparte, la casilla
  /// del consentimiento de la foto (`FOTO-1`), sólo si hay foto.
  Future<void> _requestIdentification(Map<String, Object?> product) async {
    final name = (product['name']! as String).trim();
    final ingredient = (product['active_ingredient'] as String?)?.trim();
    final hasPhoto = product['photo_sha256'] != null;
    var sharePhoto = false;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: const Text('Pedir identificación al sindicato'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Se enviará al sindicato sólo esto:'),
                    const SizedBox(height: 8),
                    Text('Nombre: $name'),
                    Text(
                      'Ingrediente activo: '
                      '${(ingredient?.isEmpty ?? true) ? 'sin dato' : ingredient}',
                    ),
                    Text('Unidad: ${product['unit']}'),
                    const SizedBox(height: 8),
                    const Text(
                      'No se envían compras, aplicaciones, cantidades ni '
                      'existencias. El vínculo lo confirma usted después.',
                    ),
                    if (hasPhoto) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        key: const Key('identification-share-photo'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: sharePhoto,
                        onChanged: (value) => setDialogState(() {
                          sharePhoto = value ?? false;
                        }),
                        title: const Text(
                          'Compartir también la foto de la etiqueta',
                        ),
                        subtitle: Text(photoConsentText(name)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Pedir identificación'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(identificationRequestStoreProvider)
          .create(
            productId: product['id']! as int,
            sharePhoto: hasPhoto && sharePhoto,
          );
      if (mounted) {
        showSuccess(
          context,
          'Solicitud guardada en el teléfono. Se enviará al sindicato.',
        );
      }
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    _reloadLocal();
  }

  /// «Enviar ahora»: verifica el acceso si hace falta y envía.
  Future<void> _sendIdentificationNow(IdentificationRequest request) async {
    setState(() {
      loading = true;
    });
    try {
      final report = await ref
          .read(syncControllerProvider.notifier)
          .sendIdentificationNow(request.requestId);
      if (mounted && report.authFailed) {
        showError(
          context,
          'El sindicato pidió verificar el acceso otra vez. La solicitud '
          'sigue guardada.',
        );
      } else if (mounted && report.ownerMismatch) {
        showError(
          context,
          'La cuenta en sesión no es la del titular: no se envió nada.',
        );
      }
    } on SyncAccessUnavailable catch (error) {
      if (mounted) showError(context, error.message);
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
    if (mounted) _reloadLocal();
  }

  /// E1-D4: el sindicato identificó el producto; el vínculo lo confirma el
  /// agricultor con el flujo de siempre. Nunca se vincula solo.
  Future<void> _bindIdentified(
    Map<String, Object?> product,
    IdentificationRequest request,
  ) async {
    final central = references?.product(request.serverProductRef!);
    final tenant = _tenant;
    if (central == null || tenant == null) {
      showError(context, 'Actualice las referencias del sindicato.');
      return;
    }
    if (!await _confirm(product['name']! as String, central.name)) return;
    try {
      await ref
          .read(centralBindingStoreProvider)
          .bindProduct(
            productId: product['id']! as int,
            central: central,
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

  /// Estado del vínculo en la fila: «vigente» o, si no lo está, el motivo.
  String _status(BindingStatus status, BindingInvalidReason? reason) =>
      status == BindingStatus.valid
      ? 'vigente'
      : 'Requiere atención: ${reason!.message}';

  /// Fila de una campaña vinculada: el vínculo, su estado y, si el período
  /// no cabe, el problema con los dos períodos, cuántos aportes lo usan y qué
  /// hacer (D-F04-C2). Todo en la fila afectada.
  String _describeCampaign(
    CampaignBinding b,
    CampaignPeriod local,
    CampaignBindingReview? review,
  ) {
    final central = b.centralPeriod;
    final problem = (b.invalidReason?.holdsQueue ?? false) || review != null
        ? CentralBindingStore.periodProblem(b, local)
        : null;
    return '${b.centralName}'
        '${central == null ? '' : ' (${central.describe})'} · '
        '${_status(b.status, b.invalidReason)}'
        '${problem == null ? '' : '\n$problem'}'
        '${review == null ? '' : '\nAceptados con este vínculo: ${review.acceptedContributions} · en cola, retenidos: ${review.heldIntentions}. Fije el fin previsto o corrija el vínculo; para retirar un total aceptado, use «Consumo para el sindicato» o «Necesidades».'}';
  }

  /// Fila de un producto vinculado. Si la unidad dejó de ser compatible, la
  /// fila dice las dos unidades.
  String _describeProduct(ProductBinding b, Map<String, Object?> product) {
    final unitDetail = b.invalidReason == BindingInvalidReason.notLinkable
        ? '\nUnidad del sindicato: ${b.centralUnit}; local: ${product['unit']}. '
              'No se convierte entre volumen y masa.'
        : '';
    return '${b.centralName} · ${_status(b.status, b.invalidReason)}'
        '$unitDetail';
  }

  /// Sin vínculo y con las referencias ya leídas: si ninguna opción del
  /// sindicato se puede elegir, por qué, en la fila (sin consultas: sólo las
  /// referencias en memoria). Null si hay alguna opción o no se leyeron.
  String? _noCompatibleCampaign(CampaignPeriod local) {
    final refs = references;
    if (refs == null) return null;
    if (refs.campaigns.any((c) => _disabledReason(local, c) == null)) {
      return null;
    }
    return refs.campaigns.isEmpty
        ? 'El sindicato no tiene campañas para elegir.'
        : 'Ninguna campaña del sindicato es compatible: o no admite aportes, '
              'o este período no cabe en el suyo. «Vincular…» muestra el '
              'motivo de cada una.';
  }

  String? _noCompatibleProduct(Map<String, Object?> product) {
    final refs = references;
    if (refs == null) return null;
    final reasons = [
      for (final central in refs.products)
        _productDisabledReason(
          central,
          BaseUnit.fromCode(product['base_unit']),
        ),
    ];
    if (reasons.any((reason) => reason == null)) return null;
    if (reasons.isEmpty) return 'El sindicato no tiene productos para elegir.';
    final distinct = [
      for (final reason in reasons.whereType<String>().toSet())
        reason[0].toLowerCase() + reason.substring(1),
    ];
    return 'Ningún producto del sindicato es compatible: '
        '${distinct.join('; ')}.';
  }

  /// Por qué no se puede elegir [central] para un producto local en
  /// [localBase]; null si se puede.
  String? _productDisabledReason(CentralProduct central, BaseUnit? localBase) =>
      !central.linkable
      ? 'Unidad central sin equivalencia L/KG'
      : !central.isActive
      ? 'Inactivo en el sindicato'
      : central.baseUnit != localBase
      ? 'Unidad distinta: no se convierte'
      : null;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Vincular con el sindicato',
    // Texto inicial corto (pedido del autor del 2026-11-05): lo que ayuda a
    // resolver un problema está en la fila afectada y en los diálogos.
    subtitle: 'Elija el equivalente del sindicato.',
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
                    'Pulse «Actualizar» para ver las opciones del sindicato.',
                  ),
                ),
              ),
            // Aviso breve; el detalle (los dos períodos, los aportes y qué
            // hacer) va en la fila de cada campaña afectada.
            if (data.reviews.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                key: const Key('period-review'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Requiere revisión: período de campaña'),
                  subtitle: Text(
                    '${data.reviews.map((review) => review.local.name).join(', ')}: '
                    'no se envían totales nuevos; lo aceptado se conserva y '
                    'lo que espera en la cola no se borra.',
                  ),
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
                    _productRow(product, data),
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
    final review = data.reviews
        .where((r) => r.binding.campaignId == local.id)
        .firstOrNull;
    final canSetEnd = local.status == 'ACTIVE' || local.status == 'PLANNED';
    final unboundDetail = binding == null ? _noCompatibleCampaign(local) : null;
    return ListTile(
      key: Key('campaign-binding-${local.id}'),
      title: Text('${local.name} (${local.describe})'),
      subtitle: Text(
        binding == null
            ? 'Requiere vinculación'
                  '${unboundDetail == null ? '' : '\n$unboundDetail'}'
            : _describeCampaign(binding, local, review),
      ),
      isThreeLine:
          (binding != null && (!binding.isValid || review != null)) ||
          unboundDetail != null,
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

  /// Fila de un producto: su vínculo y, si se pidió, la identificación al
  /// sindicato (E1) con sus estados, la nota del sindicato y las acciones.
  /// Sin solicitud, la fila es la de siempre.
  Widget _productRow(Map<String, Object?> product, _LocalCatalog data) {
    final id = product['id']! as int;
    final binding = data.productBindings[id];
    final request = data.requests[id];
    final unboundDetail = binding == null
        ? _noCompatibleProduct(product)
        : null;
    final linked = request == null ? null : identificationLinkedText(request);
    final status = Text(
      binding == null
          ? 'Requiere vinculación'
                '${unboundDetail == null ? '' : '\n$unboundDetail'}'
          : _describeProduct(binding, product),
    );
    return ListTile(
      key: Key('product-binding-$id'),
      title: Text('${product['name']} (${product['unit']})'),
      subtitle: request == null
          ? status
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                status,
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final text in identificationChips(request))
                      Chip(
                        label: Text(text),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
                if (request.sendStatus == IdentificationSendStatus.authPaused)
                  const Text(
                    'Envío pausado: el sindicato pidió verificar el acceso. '
                    'Pulse «Enviar ahora».',
                  ),
                if (request.serverNote != null)
                  Text('Nota del sindicato: ${request.serverNote}'),
                if (linked != null) Text(linked),
                if (request.photoSendStatus == IdentificationPhotoStatus.sent &&
                    product['photo_sha256'] != request.photoSha256Consented)
                  const Text(
                    'El sindicato conserva la foto anterior; la actual está '
                    'sólo en este teléfono.',
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (identificationCanSendNow(request))
                      TextButton.icon(
                        onPressed: loading
                            ? null
                            : () => _sendIdentificationNow(request),
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Enviar ahora'),
                      ),
                    if (linked != null && binding == null)
                      FilledButton.tonal(
                        onPressed: () => _bindIdentified(product, request),
                        child: const Text('Vincular'),
                      ),
                  ],
                ),
              ],
            ),
      isThreeLine: request != null,
      trailing: PopupMenuButton<String>(
        tooltip: 'Opciones de vínculo',
        onSelected: (value) => switch (value) {
          'bind' => _bindProduct(product),
          'identify' => _requestIdentification(product),
          _ => _unbind(
            product['name']! as String,
            () => ref.read(centralBindingStoreProvider).unbindProduct(id),
          ),
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'bind',
            child: Text(binding == null ? 'Vincular…' : 'Corregir vínculo…'),
          ),
          if (binding == null && request == null)
            const PopupMenuItem(
              value: 'identify',
              child: Text('Pedir identificación al sindicato'),
            ),
          if (binding != null)
            const PopupMenuItem(value: 'unbind', child: Text('Quitar vínculo')),
        ],
      ),
    );
  }
}
