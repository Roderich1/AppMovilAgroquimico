import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/sync/campaign_period_check.dart';
import '../../domain/sync/central_binding_models.dart';
import '../../domain/sync/central_references.dart';
import '../../domain/sync/identification_models.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_access.dart';
import '../../services/sync/sync_providers.dart';
import '../../services/sync/union_refresh.dart';
import '../widgets/agro_ui.dart';
import '../widgets/campaign_period_editor.dart';
import '../widgets/common.dart';
import '../widgets/identification_clarification_sheet.dart';
import '../widgets/identification_texts.dart';
import '../widgets/rdm_c_identification.dart';
import '../widgets/rdm_c_page.dart';
import '../widgets/sync_status_banner.dart' show syncSummaryProvider;
import '../widgets/union_updates.dart';

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
/// Si las fechas se pueden ajustar, el período y el vínculo se confirman juntos.
class CentralBindingScreen extends ConsumerStatefulWidget {
  const CentralBindingScreen({super.key});
  @override
  ConsumerState<CentralBindingScreen> createState() =>
      _CentralBindingScreenState();
}

class _CentralBindingScreenState extends ConsumerState<CentralBindingScreen> {
  late Future<_LocalCatalog> local;
  CentralReferences? get references =>
      ref.read(unionRefreshProvider)[UnionFeed.references]?.references;
  bool loading = false;
  _BindingTab tab = _BindingTab.products;

  @override
  void initState() {
    super.initState();
    local = _readLocal();
  }

  Future<_LocalCatalog> _readLocal() async {
    final repository = ref.read(repositoryProvider);
    final bindings = ref.read(centralBindingGatewayProvider);
    final campaigns = await repository.campaigns();
    final campaignBindings = await bindings.campaignBindings();
    // Los productos y sus solicitudes de identificación en una sola
    // consulta, en lugar de `products()`: la pantalla no suma lecturas.
    final products = await ref
        .read(identificationGatewayProvider)
        .productsWithRequests();
    return _LocalCatalog(
      campaigns,
      [for (final item in products) item.product],
      {for (final b in campaignBindings) b.campaignId: b},
      {for (final b in await bindings.productBindings()) b.productId: b},
      await bindings.reviewsForCampaigns(
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

  Future<void> _loadReferences() => refreshUnionNow(context, ref, {
    UnionFeed.references,
    UnionFeed.identification,
  });

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

  Future<T?> _choose<T>(
    String title,
    List<(T, String, String?)> options, {
    required String emptyMessage,
  }) => showDialog<T>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(title),
      children: [
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(emptyMessage),
          ),
        for (final (value, label, action) in options)
          ListTile(
            title: Text(label),
            subtitle: action == null ? null : Text(action),
            onTap: () => Navigator.pop(dialogContext, value),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(options.isEmpty ? 'Cerrar' : 'Cancelar'),
            ),
          ),
        ),
      ],
    ),
  );

  Future<({CentralReferences references, VerifiedAccess access})?>
  _referencesForBinding() async {
    final holder = ref.read(syncAccessHolderProvider);
    final connected =
        !ref.read(unionAutoRefreshEnabledProvider) ||
        ref.read(unionConnectivityProvider).value != false;
    if (references == null || holder.forUnionReads == null) {
      await ref
          .read(unionRefreshProvider.notifier)
          .refresh(
            {UnionFeed.references},
            connected: connected,
            reconnect: true,
            inForeground: () =>
                mounted && (ModalRoute.isCurrentOf(context) ?? true),
          );
    }
    if (!mounted) return null;
    final cached = references;
    final access = holder.forUnionReads;
    if (cached != null && access != null)
      return (references: cached, access: access);
    final issue = ref.read(unionRefreshProvider)[UnionFeed.references]?.issue;
    showError(context, switch (issue) {
      UnionReadIssue.offline =>
        'Sin conexión. Vuelva a intentarlo al recuperar internet.',
      UnionReadIssue.access =>
        'Verifique el acceso al sindicato para vincular.',
      UnionReadIssue.incompatible =>
        'Actualice la aplicación para consultar al sindicato.',
      _ when !connected =>
        'Sin conexión. Vuelva a intentarlo al recuperar internet.',
      _ when access == null =>
        'Verifique el acceso al sindicato para vincular.',
      _ => 'No se pudieron consultar las referencias. Vuelva a intentarlo.',
    });
    return null;
  }

  bool _checkBindingScope(VerifiedAccess access) {
    final current = ref.read(syncAccessHolderProvider).forUnionReads;
    if (current?.scope == access.scope) return true;
    showError(
      context,
      'Verifique el acceso al sindicato y vuelva a elegir el vínculo.',
    );
    return false;
  }

  /// Período central legible, o null si sus fechas no se pueden leer.
  CentralPeriod? _centralPeriod(CentralCampaign central) {
    try {
      return CentralPeriod.of(central);
    } on FormatException {
      return null;
    }
  }

  Future<void> _bindCampaign(
    CampaignPeriod local,
    Iterable<CampaignBinding> bindings,
  ) async {
    final source = await _referencesForBinding();
    if (source == null || !mounted) return;
    final tenant = source.access.scope.tenantId;
    final takenRefs = {
      for (final binding in bindings)
        if (binding.campaignId != local.id && binding.tenantId == tenant)
          binding.campaignRef,
    };
    final gateway = ref.read(centralBindingGatewayProvider);
    final options = <(CentralCampaign, String, String?)>[];
    final proposals = <String, CampaignPeriod>{};
    String? blocked;
    for (final campaign in source.references.campaigns) {
      if (!campaign.acceptsContributions || takenRefs.contains(campaign.ref))
        continue;
      final period = _centralPeriod(campaign);
      if (period == null) continue;
      final label = '${campaign.name} · ${period.describe}';
      final mismatch = periodMismatch(local, period);
      if (mismatch == null) {
        options.add((campaign, label, null));
        continue;
      }
      final proposed = suggestedPeriodForBinding(local, period);
      if (proposed == null) {
        blocked ??=
            'El período de «${local.name}» no cabe en '
            '«${campaign.name}» (${period.describe}). Revise las fechas en Campañas.';
        continue;
      }
      final problem = await gateway.campaignAdjustmentProblem(local, proposed);
      if (!mounted) return;
      if (problem != null) {
        blocked = problem;
        continue;
      }
      proposals[campaign.ref] = proposed;
      options.add((
        campaign,
        label,
        mismatch == PeriodMismatch.openEndRequired
            ? 'Fijar fin previsto y vincular'
            : 'Ajustar fechas y vincular',
      ));
    }
    final chosen = await _choose<CentralCampaign>(
      'Campaña del sindicato',
      options,
      emptyMessage: blocked ?? _emptyCampaignPickerMessage(source.references),
    );
    if (chosen == null || !mounted) return;
    final period = _centralPeriod(chosen)!;
    final proposed = proposals[chosen.ref];
    CampaignPeriod? adjusted;
    if (proposed != null) {
      adjusted = await showCampaignPeriodEditor(
        context,
        local,
        proposed,
        central: period,
        centralName: chosen.name,
      );
      if (adjusted == null) return;
    } else if (!await _confirm(
      local.name,
      chosen.name,
      note:
          'Campaña local ${local.describe}. '
          'Ciclo del sindicato ${period.describe}.',
    )) {
      return;
    }
    if (!mounted || !_checkBindingScope(source.access)) return;
    final latest = references?.campaign(chosen.ref);
    if (latest == null) {
      showError(
        context,
        'La campaña del sindicato cambió. Abra el selector de nuevo.',
      );
      return;
    }
    try {
      await gateway.bindCampaign(
        campaignId: local.id,
        central: latest,
        tenantId: tenant,
        expectedPeriod: local,
        adjustedPeriod: adjusted,
      );
      if (mounted) showSuccess(context, 'Campaña vinculada.');
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) _reloadLocal();
  }

  Future<void> _editPeriod(
    CampaignPeriod campaign,
    String? preferredEnd,
  ) async {
    try {
      final changed = await editCampaignPeriodFlow(
        context,
        ref.read(repositoryProvider),
        campaign,
        preferredEnd: preferredEnd,
      );
      if (changed && mounted) _reloadLocal();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _bindProduct(
    Map<String, Object?> product,
    Iterable<ProductBinding> bindings,
  ) async {
    final source = await _referencesForBinding();
    if (source == null || !mounted) return;
    final id = product['id']! as int;
    final tenant = source.access.scope.tenantId;
    final takenRefs = {
      for (final binding in bindings)
        if (binding.productId != id && binding.tenantId == tenant)
          binding.productRef,
    };
    final localBase = BaseUnit.fromCode(product['base_unit']);
    final chosen = await _choose<CentralProduct>(
      'Producto del sindicato',
      [
        for (final central in source.references.products)
          if (_isCompatibleProduct(central, localBase) &&
              !takenRefs.contains(central.ref))
            (central, '${central.name} (${central.unit})', null),
      ],
      emptyMessage:
          'No hay productos disponibles con una unidad compatible. '
          'Puede pedir al sindicato que identifique este producto.',
    );
    if (chosen == null || !mounted) return;
    await _confirmProductBinding(product, chosen, source.access);
  }

  Future<void> _confirmProductBinding(
    Map<String, Object?> product,
    CentralProduct central,
    VerifiedAccess access,
  ) async {
    if (!await _confirm(product['name']! as String, central.name)) return;
    if (!mounted || !_checkBindingScope(access)) return;
    final latest = references?.product(central.ref);
    if (latest == null) {
      showError(
        context,
        'El producto del sindicato cambió. Abra el selector de nuevo.',
      );
      return;
    }
    try {
      await ref
          .read(centralBindingGatewayProvider)
          .bindProduct(
            productId: product['id']! as int,
            central: latest,
            tenantId: access.scope.tenantId,
          );
      if (mounted) showSuccess(context, 'Producto vinculado.');
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) _reloadLocal();
  }

  /// E1: pide al sindicato que identifique un producto local sin vínculo.
  /// El diálogo muestra exactamente lo que se enviará y, aparte, la casilla
  /// del consentimiento de la foto (`FOTO-1`), sólo si hay foto.
  Future<void> _requestIdentification(Map<String, Object?> product) async {
    final hasPhoto = product['photo_sha256'] != null;
    final answer = await showIdentificationRequestSheet(context, (
      productId: product['id']! as int,
      name: (product['name']! as String).trim(),
      ingredient: (product['active_ingredient'] as String?)?.trim(),
      unit: product['unit']! as String,
      hasPhoto: hasPhoto,
    ));
    if (answer == null || !mounted) return;
    try {
      await ref
          .read(identificationGatewayProvider)
          .create(
            productId: product['id']! as int,
            sharePhoto: hasPhoto && answer.sharePhoto,
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

  Future<void> _completeInformation(IdentificationRequest request) async {
    final answer = await showIdentificationClarification(context, request);
    if (!mounted || answer == null) return;
    try {
      await ref
          .read(identificationRequestStoreProvider)
          .queueClarification(
            requestId: request.requestId,
            noteAt: request.serverNoteAt!,
            name: answer.name,
            ingredient: answer.ingredient,
            authorizedPhotoPath: answer.photoPath,
          );
      if (mounted) await _sendClarification(request);
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _sendClarification(IdentificationRequest request) async {
    setState(() => loading = true);
    try {
      await ref
          .read(syncControllerProvider.notifier)
          .sendClarificationNow(request.requestId);
      if (!mounted) return;
      final latest = await ref
          .read(identificationRequestStoreProvider)
          .byId(request.requestId);
      if (!mounted) return;
      if (latest?.clarificationReply == null)
        showSuccess(context, 'El sindicato recibió su respuesta.');
    } on SyncAccessUnavailable {
      if (mounted)
        showSuccess(
          context,
          'Respuesta guardada en el teléfono. Queda pendiente de envío.',
        );
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() => loading = false);
        _reloadLocal();
      }
    }
  }

  Future<void> _removeSharedIdentificationPhoto(
    IdentificationRequest request,
  ) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Retirar foto compartida',
      detail: 'Se pedirá al sindicato que retire la foto de la etiqueta de esta solicitud.',
      confirmLabel: 'Retirar',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(identificationRequestStoreProvider)
          .requestSharedPhotoRemoval(request.requestId);
      if (mounted) await _sendIdentificationNow(request);
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
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
    final source = await _referencesForBinding();
    if (source == null || !mounted) return;
    final central = source.references.product(request.serverProductRef!);
    if (central == null) {
      showError(
        context,
        'El producto identificado no está disponible en el catálogo del sindicato.',
      );
      return;
    }
    await _confirmProductBinding(product, central, source.access);
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
        ? centralBindingPeriodProblem(b, local)
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

  String _emptyCampaignPickerMessage(CentralReferences refs) =>
      refs.campaigns.any((campaign) => campaign.acceptsContributions)
      ? 'No hay campañas disponibles para vincular.'
      : 'El sindicato no tiene campañas que admitan nuevos aportes.';

  /// Sin vínculo y con las referencias ya leídas: si ninguna opción del
  /// sindicato se puede elegir, por qué, en la fila (sin consultas: sólo las
  /// referencias en memoria). Null si hay alguna opción o no se leyeron.
  String? _noCompatibleCampaign(CampaignPeriod local) {
    final refs = references;
    if (refs == null) return null;
    final open = refs.campaigns.where(
      (campaign) => campaign.acceptsContributions,
    );
    if (open.isEmpty) return _emptyCampaignPickerMessage(refs);
    for (final campaign in open) {
      final period = _centralPeriod(campaign);
      if (period == null) continue;
      if (periodMismatch(local, period) == null ||
          suggestedPeriodForBinding(local, period) != null) {
        return null;
      }
    }
    return 'Revise las fechas de esta campaña y las opciones del sindicato.';
  }

  String? _noCompatibleProduct(Map<String, Object?> product) {
    final refs = references;
    if (refs == null) return null;
    final unit = BaseUnit.fromCode(product['base_unit']);
    return refs.products.any((central) => _isCompatibleProduct(central, unit))
        ? null
        : 'No hay productos activos con unidad compatible. Puede pedir identificación.';
  }

  bool _isCompatibleProduct(CentralProduct central, BaseUnit? localBase) =>
      localBase != null &&
      central.isActive &&
      central.linkable &&
      central.baseUnit == localBase;

  void _showCampaigns() => setState(() => tab = _BindingTab.campaigns);

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      unionRefreshProvider.select(
        (statuses) => statuses[UnionFeed.references] ?? emptyUnionRead,
      ),
    );
    ref.listen(identificationRevisionProvider, (_, _) => _reloadLocal());
    ref.listen(
      unionRefreshProvider.select(
        (statuses) => statuses[UnionFeed.references]?.lastRead,
      ),
      (_, _) => _reloadLocal(),
    );
    final noteIssue = ref.watch(
      unionRefreshProvider.select(
        (statuses) => statuses[UnionFeed.identification]?.issue,
      ),
    );
    return _page(status, noteIssue);
  }

  Widget _page(UnionReadStatus status, UnionReadIssue? noteIssue) => RdmCPage(
    title: 'Productos y campañas',
    // Texto inicial corto (pedido del autor del 2026-11-05): lo que ayuda a
    // resolver un problema está en la fila afectada y en los diálogos.
    subtitle: 'Elija el equivalente del sindicato.',
    action: RdmCHeaderAction(
      icon: Icons.sync,
      label:
          status.issue == UnionReadIssue.access ||
              noteIssue == UnionReadIssue.access
          ? 'Verificar acceso'
          : 'Actualizar',
      onPressed: loading || status.busy ? null : _loadReferences,
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
            if (loading || status.busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            const UnionUpdateStatus(feed: UnionFeed.references),
            if (noteIssue != null && noteIssue != status.issue)
              const UnionUpdateStatus(feed: UnionFeed.identification),
            if (references == null && status.issue == null && !status.busy)
              const NoticeBox(text: 'Todavía no hay referencias guardadas.'),
            // Aviso breve; el detalle (los dos períodos, los aportes y qué
            // hacer) va en la fila de cada campaña afectada.
            if (data.reviews.isNotEmpty) ...[
              NoticeBox(
                key: const Key('period-review'),
                tone: NoticeTone.warning,
                icon: Icons.event_busy_outlined,
                text:
                    'Requiere revisión: período de campaña. '
                    '${data.reviews.map((review) => review.local.name).join(', ')}: '
                    'no se envían totales nuevos; lo aceptado se conserva y '
                    'lo que espera en la cola no se borra.',
                action: tab == _BindingTab.campaigns
                    ? null
                    : TextButton(
                        onPressed: _showCampaigns,
                        child: const Text('Ver campañas'),
                      ),
              ),
              const SizedBox(height: 12),
            ],
            SegmentToggle<_BindingTab>(
              semanticLabel: 'Mostrar productos o campañas',
              selected: tab,
              onChanged: (value) => setState(() => tab = value),
              options: [
                ToggleOption(
                  _BindingTab.products,
                  'Productos · ${data.products.length}',
                  key: const Key('binding-tab-products'),
                ),
                ToggleOption(
                  _BindingTab.campaigns,
                  'Campañas · ${data.campaigns.length}',
                  key: const Key('binding-tab-campaigns'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (tab == _BindingTab.products)
              data.products.isEmpty
                  ? const RdmCEmpty(
                      message: 'Todavía no hay productos en este teléfono.',
                    )
                  : AgroGroup(
                      children: [
                        for (final product in data.products)
                          _productRow(product, data),
                      ],
                    )
            else
              data.campaigns.isEmpty
                  ? const RdmCEmpty(
                      message: 'Todavía no hay campañas en este teléfono.',
                    )
                  : AgroGroup(
                      children: [
                        for (final campaign in data.campaigns)
                          _campaignRow(campaign, data),
                      ],
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
    final canSetEnd = local.allowsPlannedEnd;
    final unboundDetail = binding == null ? _noCompatibleCampaign(local) : null;
    final status = binding == null
        ? 'Requiere vinculación'
              '${unboundDetail == null ? '' : '\n$unboundDetail'}'
        : _describeCampaign(binding, local, review);
    return RdmCRow(
      key: Key('campaign-binding-${local.id}'),
      title: '${local.name} (${local.describe})',
      detail: status,
      trailing: RdmCOptionsMenu(
        tooltip: 'Opciones de vínculo',
        onSelected: (value) => switch (value) {
          'bind' => _bindCampaign(local, data.campaignBindings.values),
          'end' => _editPeriod(local, binding?.centralEndDay),
          _ => _unbind(
            local.name,
            () => ref
                .read(centralBindingGatewayProvider)
                .unbindCampaign(local.id),
          ),
        },
        items: [
          PopupMenuItem(
            value: 'bind',
            child: Text(binding == null ? 'Vincular…' : 'Corregir vínculo…'),
          ),
          if (canSetEnd)
            const PopupMenuItem(value: 'end', child: Text('Editar período…')),
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
    final reply = request?.clarificationReply;
    final unboundDetail = binding == null
        ? _noCompatibleProduct(product)
        : null;
    final linked = request == null ? null : identificationLinkedText(request);
    final status = binding == null
        ? 'Requiere vinculación'
              '${unboundDetail == null ? '' : '\n$unboundDetail'}'
        : _describeProduct(binding, product);
    return RdmCRow(
      key: Key('product-binding-$id'),
      title: '${product['name']} (${product['unit']})',
      detail: status,
      badges: request == null
          ? const []
          : [
              for (final text in identificationChips(request))
                StatusBadge(label: text, tone: identificationChipTone(text)),
            ],
      notes: request == null
          ? const []
          : [
              if (request.sendStatus == IdentificationSendStatus.authPaused)
                'Envío pausado: el sindicato pidió verificar el acceso. '
                    'Pulse «Enviar ahora».',
              if (request.serverNote != null)
                'Nota del sindicato: ${request.serverNote}',
              if (reply != null) identificationClarificationStatus(reply),
              ?linked,
              if (request.photoSendStatus == IdentificationPhotoStatus.sent &&
                  product['photo_sha256'] != null &&
                  product['photo_sha256'] != request.photoSha256Consented)
                'El sindicato conserva la foto anterior; la actual está '
                    'sólo en este teléfono.',
            ],
      actions: request == null
          ? const []
          : [
              if (request.canCompleteInformation)
                FilledButton.tonal(
                  onPressed: loading
                      ? null
                      : () => _completeInformation(request),
                  child: const Text('Completar información'),
                ),
              if (reply != null &&
                  !reply.isTerminal &&
                  !request.canCompleteInformation)
                TextButton(
                  onPressed: loading ? null : () => _sendClarification(request),
                  child: const Text('Reintentar respuesta'),
                ),
              if (identificationCanSendNow(request))
                TextButton.icon(
                  onPressed: loading
                      ? null
                      : () => _sendIdentificationNow(request),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Enviar ahora'),
                ),
              if (request.photoSendStatus == IdentificationPhotoStatus.sent)
                TextButton(
                  onPressed: loading
                      ? null
                      : () => _removeSharedIdentificationPhoto(request),
                  child: const Text('Retirar foto compartida'),
                ),
              // E1-D4: el vínculo lo confirma el agricultor.
              if (linked != null && binding == null)
                FilledButton.tonal(
                  onPressed: () => _bindIdentified(product, request),
                  child: const Text('Vincular'),
                ),
            ],
      trailing: RdmCOptionsMenu(
        tooltip: 'Opciones de vínculo',
        onSelected: (value) => switch (value) {
          'bind' => _bindProduct(product, data.productBindings.values),
          'identify' => _requestIdentification(product),
          _ => _unbind(
            product['name']! as String,
            () => ref.read(centralBindingGatewayProvider).unbindProduct(id),
          ),
        },
        items: [
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

enum _BindingTab { products, campaigns }
