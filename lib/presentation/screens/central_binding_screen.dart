import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/sync/central_binding_store.dart';
import '../../domain/sync/central_references.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_access.dart';
import '../../services/sync/sync_api.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';

class _LocalCatalog {
  const _LocalCatalog(
    this.campaigns,
    this.products,
    this.campaignBindings,
    this.productBindings,
  );
  final List<Map<String, Object?>> campaigns;
  final List<Map<String, Object?>> products;
  final Map<int, CampaignBinding> campaignBindings;
  final Map<int, ProductBinding> productBindings;
}

/// Vincular campañas y productos locales con el catálogo del sindicato
/// (F05-SYNC-08). Cada vínculo nace de una elección confirmada: nunca por
/// coincidencia de nombre. Sin conexión se conservan los vínculos existentes
/// y la base local sigue disponible.
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
    return _LocalCatalog(
      await repository.campaigns(),
      await repository.products(),
      {for (final b in await bindings.campaignBindings()) b.campaignId: b},
      {for (final b in await bindings.productBindings()) b.productId: b},
    );
  }

  void _reloadLocal() {
    final next = _readLocal();
    setState(() {
      local = next;
    });
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

  Future<bool> _confirm(String local, String central) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar vínculo'),
          content: Text(
            'Vincular «$local» de este teléfono con «$central» del sindicato. '
            'Sólo se enviarán totales con esa referencia.',
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

  Future<void> _bindCampaign(Map<String, Object?> campaign) async {
    final refs = references;
    final tenant = _tenant;
    if (refs == null || tenant == null) {
      showError(context, 'Actualice primero las referencias del sindicato.');
      return;
    }
    final chosen = await _choose<CentralCampaign>('Campaña del sindicato', [
      for (final central in refs.campaigns)
        (
          central,
          central.name,
          central.acceptsContributions ? null : 'No admite nuevos aportes',
        ),
    ]);
    if (chosen == null || !mounted) return;
    if (!await _confirm(campaign['name']! as String, chosen.name)) return;
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

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Vincular con el sindicato',
    subtitle:
        'Elija el equivalente del sindicato para cada campaña y producto. '
        'Nada se vincula por nombre.',
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
            const SizedBox(height: 12),
            Text('Campañas', style: Theme.of(context).textTheme.titleMedium),
            Card(
              child: Column(
                children: [
                  for (final campaign in data.campaigns)
                    _row(
                      label: campaign['name']! as String,
                      binding: data.campaignBindings[campaign['id']],
                      describe: (b) =>
                          '${b.centralName} · ${_status(b.status, b.invalidReason)}',
                      onBind: () => _bindCampaign(campaign),
                      onUnbind: () => _unbind(
                        campaign['name']! as String,
                        () => ref
                            .read(centralBindingStoreProvider)
                            .unbindCampaign(campaign['id']! as int),
                      ),
                    ),
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
