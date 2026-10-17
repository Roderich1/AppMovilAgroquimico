/// Aplicación multiproducto por voz (#15), con el mismo patrón que la compra
/// y la planificación (#16).
///
/// Como en el formulario, el chaco fija quién aplica (su dueño) y de qué
/// inventario sale el producto. El stock posterior sólo se **proyecta** con
/// una lectura; «Registrar aplicación» llama una vez a
/// `confirmApplication()`, que hace FIFO, costo, movimientos y stock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/money.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/ui/voice_capture_screen.dart';
import '../../voice/voice_providers.dart';
import '../../voice_draft/application/application_interpreter.dart';
import '../../voice_draft/application/voice_application_draft.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/voice_draft_controller.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/text/units.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';
import 'voice_draft_gateway.dart';
import 'voice_draft_widgets.dart';

class VoiceApplicationDraftScreen extends ConsumerStatefulWidget {
  const VoiceApplicationDraftScreen({super.key, this.onOpenManualForm});

  /// Alternativa manual equivalente (formulario de aplicación).
  final VoidCallback? onOpenManualForm;

  @override
  ConsumerState<VoiceApplicationDraftScreen> createState() =>
      _VoiceApplicationDraftScreenState();
}

class _VoiceApplicationDraftScreenState
    extends ConsumerState<VoiceApplicationDraftScreen>
    with WidgetsBindingObserver {
  late final VoiceSessionController _session;
  late final VoiceDraftGateway _gateway;
  VoiceCatalog? _catalog;
  VoiceDraftController<VoiceApplicationDraft, int>? _draft;
  String? _loadError;

  final VoiceSegmentFeed _feed = VoiceSegmentFeed();
  final List<String> _applied = [];
  VoiceIntent? _otherIntent;
  int? _stockRequestedFor;
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gateway = ref.read(voiceDraftGatewayProvider);
    _session = VoiceSessionController(
      port: ref.read(speechPortFactoryProvider)(),
    );
    _session.addListener(_onSession);
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await _gateway.applicationCatalog();
      if (!mounted) return;
      final draft = VoiceDraftController<VoiceApplicationDraft, int>(
        initial: VoiceApplicationDraft.start(catalog),
        commit: _gateway.confirmApplication,
        describeError: friendlyError,
      )..addListener(_onDraft);
      setState(() {
        _catalog = catalog;
        _draft = draft;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = friendlyError(error));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    _session.dispose();
    _draft?.removeListener(_onDraft);
    _draft?.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _session.handleAppPaused();
  }

  void _onDraft() {
    if (!mounted) return;
    final d = _draft?.draft;
    if (d != null) {
      _sync('area', _areaText(d), d.area);
      for (final line in d.lines) {
        _sync('q${line.key}', _quantityText(line), line.quantity);
      }
      _loadStockIfNeeded(d);
    }
    setState(() {});
  }

  /// Lee el stock del dueño del chaco elegido. Si el chaco cambia mientras
  /// se lee, la lectura vieja se descarta (`withStock`).
  Future<void> _loadStockIfNeeded(VoiceApplicationDraft d) async {
    final owner = d.person?.id;
    if (owner == null || d.stockLoaded || _stockRequestedFor == owner) return;
    _stockRequestedFor = owner;
    try {
      final stock = await _gateway.availableStock(owner);
      if (!mounted) return;
      _draft?.editManually((c) => c.withStock(owner, stock));
    } catch (error) {
      if (mounted) setState(() => _loadError = friendlyError(error));
    } finally {
      if (_stockRequestedFor == owner) _stockRequestedFor = null;
    }
  }

  void _onSession() {
    if (!mounted) return;
    final draft = _draft;
    final catalog = _catalog;
    final fresh = _feed.take(
      _session.snapshot.committedText,
      ready: draft != null && catalog != null,
    );
    if (fresh != null) {
      VoiceIntent? other;
      final accepted = draft!.applyVoice((current) {
        final r = interpretApplication(fresh, current, catalog!);
        other = r.otherIntent;
        return (r.draft, r.outcome);
      });
      if (accepted) {
        _otherIntent = other;
        if (other == null) _applied.add(fresh);
      }
    }
    setState(() {});
  }

  TextEditingController _controller(String id, String value) =>
      _fields.putIfAbsent(id, () => TextEditingController(text: value));

  void _sync(String id, String value, DraftField<Object?> field) {
    final c = _fields[id];
    if (c == null || field.isManual) return;
    if (c.text != value) c.text = value;
  }

  /// Con 4 decimales de hectárea el texto es el área exacta en m² (M-1).
  static String _areaText(VoiceApplicationDraft d) => d.area.value == null
      ? (d.area.heard ?? '')
      : formatForInput(d.area.value! / 10000, maxDecimals: 4);

  static String _quantityText(VoiceApplicationLine line) =>
      line.quantityBase == null
      ? (line.quantity.heard ?? '')
      : formatForInput(line.quantityBase! / baseUnitsPerMajor);

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null || _visibleMismatches(draft.draft).isNotEmpty) return;
    final id = await draft.confirm();
    if (id == null || !mounted) return;
    await _session.discard();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Aplicación registrada (n.º $id).')));
    setState(() => _leaving = true);
    Navigator.of(context).maybePop(id);
  }

  Future<void> _cancel() async {
    _draft?.discard();
    await _session.discard();
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).maybePop();
  }

  bool _leaving = false;

  bool get _hasWork {
    final d = _draft?.draft;
    return _applied.isNotEmpty ||
        (d != null && (d.lines.isNotEmpty || d.farm.isResolved));
  }

  /// Pasar al formulario manual sustituye esta pantalla: con un borrador
  /// empezado se pregunta antes, y el borrador se descarta sin escribir.
  Future<void> _openManualForm() async {
    final open = widget.onOpenManualForm;
    if (open == null || _draft?.phase == DraftPhase.confirming) return;
    if (_hasWork &&
        !await confirmDestructiveAction(
          context,
          title: '¿Descartar el borrador?',
          detail: 'No se registró nada. Se abrirá el formulario manual vacío.',
          confirmLabel: 'Descartar y abrir el formulario',
        )) {
      return;
    }
    _draft?.discard();
    await _session.discard();
    if (!mounted) return;
    setState(() => _leaving = true);
    open();
  }

  Future<void> _onBack() async {
    if (_draft?.phase == DraftPhase.confirming) return;
    final discard = await confirmDestructiveAction(
      context,
      title: '¿Descartar el borrador?',
      detail:
          'No se registró ninguna aplicación. Lo dictado y lo corregido se '
          'pierden.',
      confirmLabel: 'Descartar',
    );
    if (discard && mounted) await _cancel();
  }

  /// Campos resueltos cuyo texto visible no dice lo mismo que el borrador:
  /// si hay alguno, no se confirma (mismo criterio que la compra).
  List<String> _visibleMismatches(VoiceApplicationDraft d) {
    final out = <String>[];
    final area = _fields['area'];
    if (area != null && d.area.isResolved) {
      final ha = tryParseDecimal(area.text);
      if ((ha == null ? null : (ha * 10000).round()) != d.area.value) {
        out.add('El área visible no coincide con el borrador.');
      }
    }
    for (var i = 0; i < d.lines.length; i++) {
      final l = d.lines[i];
      final c = _fields['q${l.key}'];
      if (c != null &&
          l.quantity.isResolved &&
          tryParseBase(c.text) != l.quantityBase) {
        out.add('Producto ${i + 1}: la cantidad visible no coincide.');
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final catalog = _catalog;
    final confirming = draft?.phase == DraftPhase.confirming;
    return PopScope(
      canPop: _leaving || (!confirming && !_hasWork),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: _buildPage(context, draft, catalog),
    );
  }

  Widget _buildPage(
    BuildContext context,
    VoiceDraftController<VoiceApplicationDraft, int>? draft,
    VoiceCatalog? catalog,
  ) {
    return PageFrame(
      title: 'Aplicación por voz',
      subtitle: 'Dicte lo aplicado, revíselo y regístrelo con un toque.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VoiceDraftNotice(
            confirmLabel: 'Registrar aplicación',
            catalogs: 'Los chacos y productos',
          ),
          const SizedBox(height: 12),
          VoiceListeningPanel(session: _session),
          const SizedBox(height: 12),
          if (_otherIntent != null)
            VoiceOtherIntentBanner(
              intent: _otherIntent!,
              current: 'aplicación',
            ),
          if (_applied.isNotEmpty) VoiceAppliedPanel(applied: _applied),
          const SizedBox(height: 12),
          if (_loadError != null)
            Text(_loadError!, key: const Key('voz-borrador-error-carga'))
          else if (draft == null || catalog == null)
            const Center(child: CircularProgressIndicator())
          else
            _buildDraft(context, draft, catalog),
          if (widget.onOpenManualForm != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('voz-borrador-manual'),
              onPressed: _openManualForm,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Usar el formulario manual'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDraft(
    BuildContext context,
    VoiceDraftController<VoiceApplicationDraft, int> controller,
    VoiceCatalog catalog,
  ) {
    final d = controller.draft;
    final editable = controller.phase == DraftPhase.editing;
    final theme = Theme.of(context);
    final mismatches = _visibleMismatches(d);
    // La modalidad cambió con la pantalla abierta: las opciones se leyeron
    // con la anterior. Como los formularios, se avisa y no se confirma.
    final modeChanged = modeChangedSince(
      catalog.loadedMode,
      ref.watch(operationModeProvider),
    );
    return Column(
      key: const Key('voz-borrador-aplicacion'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (modeChanged) ...[
          const ModeChangedNotice(),
          const SizedBox(height: 8),
        ],
        Text('Borrador', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        DraftFieldRow(
          label: 'Campaña',
          field: d.campaign,
          child: Text(d.campaign.value?.name ?? '—'),
        ),
        DraftFieldRow(
          label: 'Chaco',
          field: d.farm,
          child: CatalogEntryPicker(
            key: const Key('voz-borrador-chaco'),
            entries: catalog.farms,
            field: d.farm,
            enabled: editable,
            onPick: (entry) => controller.editManually(
              (c) => selectFarm(
                c.copyWith(
                  farm: DraftField.resolved(entry, origin: FieldOrigin.manual),
                ),
                catalog,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Aplica: ${d.person?.name ?? '— (lo fija el chaco)'}',
            key: const Key('voz-aplica'),
          ),
        ),
        DraftFieldRow(
          label: 'Área tratada (ha)',
          field: d.area,
          child: TextField(
            key: const Key('voz-area'),
            controller: _controller('area', _areaText(d)),
            enabled: editable,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) {
              final ha = tryParseDecimal(text);
              controller.editManually(
                (c) => c.copyWith(
                  area: ha == null || ha <= 0
                      ? const DraftField.invalid(
                          message: 'Escriba un área mayor a cero.',
                          origin: FieldOrigin.manual,
                        )
                      : DraftField.resolved(
                          (ha * 10000).round(),
                          origin: FieldOrigin.manual,
                        ),
                ),
              );
            },
          ),
        ),
        _planSection(controller, catalog, d, editable),
        for (var i = 0; i < d.lines.length; i++)
          _lineCard(context, controller, catalog, d, i, d.lines[i], editable),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('voz-agregar-linea'),
            onPressed: editable
                ? () => controller.editManually((c) => c.addEmptyLine())
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Añadir producto a mano'),
          ),
        ),
        if (controller.blockers.isNotEmpty || mismatches.isNotEmpty) ...[
          const SizedBox(height: 8),
          VoiceBlockersPanel(blockers: [...controller.blockers, ...mismatches]),
        ],
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.error!,
            key: const Key('voz-error-registro'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton(
              key: const Key('voz-cancelar'),
              onPressed: controller.phase == DraftPhase.confirming
                  ? null
                  : _cancel,
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              key: const Key('voz-registrar'),
              onPressed:
                  controller.canConfirm && mismatches.isEmpty && !modeChanged
                  ? _confirm
                  : null,
              icon: controller.phase == DraftPhase.confirming
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Registrar aplicación'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineCard(
    BuildContext context,
    VoiceDraftController<VoiceApplicationDraft, int> controller,
    VoiceCatalog catalog,
    VoiceApplicationDraft d,
    int index,
    VoiceApplicationLine line,
    bool editable,
  ) {
    final unit = line.product.value?.unit;
    final unitLabel = unit == CatalogUnit.kilogram ? 'KG' : 'L';
    final id = line.product.value?.id;
    final available = id == null || !d.stockLoaded ? null : (d.stock[id] ?? 0);
    final after = d.stockAfter(line);

    void update(VoiceApplicationLine Function(VoiceApplicationLine) change) =>
        controller.editManually((c) => c.updateLine(line.key, change));

    return Card(
      key: Key('voz-linea-${line.key}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Producto ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: Key('voz-quitar-${line.key}'),
                  tooltip: 'Quitar este producto',
                  onPressed: editable
                      ? () => controller.editManually(
                          (c) => c.removeLine(line.key),
                        )
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            DraftFieldRow(
              label: 'Producto',
              field: line.product,
              child: CatalogEntryPicker(
                key: Key('voz-producto-${line.key}'),
                entries: catalog.products,
                field: line.product,
                enabled: editable,
                onPick: (entry) => update(
                  (l) => l.copyWith(
                    product: DraftField.resolved(
                      entry,
                      origin: FieldOrigin.manual,
                    ),
                  ),
                ),
              ),
            ),
            DraftFieldRow(
              label: 'Cantidad aplicada ($unitLabel)',
              field: line.quantity,
              child: TextField(
                key: Key('voz-cantidad-${line.key}'),
                controller: _controller('q${line.key}', _quantityText(line)),
                enabled: editable,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (text) {
                  final base = tryParseBase(text);
                  update(
                    (l) => l.copyWith(
                      quantity: base == null || base <= 0
                          ? const DraftField.invalid(
                              message: 'Escriba una cantidad mayor a cero.',
                              origin: FieldOrigin.manual,
                            )
                          : DraftField.resolved(
                              SpokenAmount(
                                base,
                                l.product.value?.unit == CatalogUnit.kilogram
                                    ? SpokenUnit.kilogram
                                    : SpokenUnit.liter,
                              ),
                              origin: FieldOrigin.manual,
                            ),
                    ),
                  );
                },
              ),
            ),
            Text(
              available == null
                  ? 'Stock: se muestra al elegir el chaco y el producto.'
                  : after == null
                  ? 'Stock actual ${formatQuantity(available, unitLabel)}'
                  : 'Stock actual ${formatQuantity(available, unitLabel)} · '
                        'quedaría ${formatQuantity(after < 0 ? 0 : after, unitLabel)}'
                        '${after < 0 ? ' (insuficiente)' : ''}',
              key: Key('voz-stock-${line.key}'),
            ),
            if (line.fromPlan)
              Text(
                'Planeado ${formatQuantity(line.plannedBase!, unitLabel)}'
                '${line.differenceBase == null ? '' : ' · diferencia ${line.differenceBase! >= 0 ? '+' : '−'}${formatQuantity(line.differenceBase!.abs(), unitLabel)}'}',
                key: Key('voz-planeado-${line.key}'),
              ),
          ],
        ),
      ),
    );
  }

  /// Plan pendiente (D-F09-4): se ofrece si el chaco tiene planes pendientes
  /// de la campaña activa o si se pidió por voz. **Se elige siempre a mano**,
  /// aunque haya uno solo; nunca se elige solo.
  Widget _planSection(
    VoiceDraftController<VoiceApplicationDraft, int> controller,
    VoiceCatalog catalog,
    VoiceApplicationDraft d,
    bool editable,
  ) {
    final farm = d.farm.isResolved ? d.farm.value : null;
    final options = farm == null
        ? const <PendingPlan>[]
        : catalog.plansFor(farm.id, d.campaign.value?.id);
    if (d.plan == null && options.isEmpty) return const SizedBox.shrink();
    final picker = CatalogEntryPicker(
      key: const Key('voz-plan-elegir'),
      entries: [for (final o in options) o.entry],
      field: d.plan ?? const DraftField<CatalogEntry>.missing(),
      enabled: editable && options.isNotEmpty,
      onPick: (entry) =>
          controller.editManually((c) => selectPlan(c, entry.id, catalog)),
    );
    return Column(
      key: const Key('voz-plan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.plan == null) ...[
          // No se pidió: es opcional y no bloquea.
          Text(
            '${farm?.name ?? 'Este chaco'} tiene ${options.length} plan'
            '${options.length == 1 ? '' : 'es'} pendiente'
            '${options.length == 1 ? '' : 's'}. Puede aplicar uno en vez de '
            'una aplicación libre:',
          ),
          picker,
        ] else
          DraftFieldRow(label: 'Plan pendiente', field: d.plan!, child: picker),
        // Volver a una aplicación libre es siempre una acción de la persona,
        // también si no hay plan que elegir (EVO-018: la frase no se
        // convierte sola en una aplicación libre).
        if (d.plan != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('voz-plan-quitar'),
              onPressed: editable
                  ? () => controller.editManually(clearPlan)
                  : null,
              icon: const Icon(Icons.link_off),
              label: const Text('Quitar el plan (aplicación libre)'),
            ),
          ),
      ],
    );
  }
}
