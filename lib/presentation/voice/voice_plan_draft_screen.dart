/// Planificación por voz (#14), con el mismo patrón que la compra (#16):
/// dictar, revisar, corregir y crear el plan con un toque.
///
/// El plan es el del dominio: chaco, campaña activa, área y dosis por
/// hectárea de cada producto. La cantidad necesaria se calcula como en el
/// formulario. Crear el plan no toca inventario ni necesidades.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/money.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/ui/voice_capture_screen.dart';
import '../../voice/voice_providers.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/voice_draft_controller.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/plan/plan_interpreter.dart';
import '../../voice_draft/plan/voice_plan_draft.dart';
import '../../voice_draft/text/units.dart';
import '../widgets/common.dart';
import 'voice_draft_gateway.dart';
import 'voice_draft_widgets.dart';

class VoicePlanDraftScreen extends ConsumerStatefulWidget {
  const VoicePlanDraftScreen({super.key, this.onOpenManualForm});

  /// Alternativa manual equivalente (formulario de planificación).
  final VoidCallback? onOpenManualForm;

  @override
  ConsumerState<VoicePlanDraftScreen> createState() =>
      _VoicePlanDraftScreenState();
}

class _VoicePlanDraftScreenState extends ConsumerState<VoicePlanDraftScreen>
    with WidgetsBindingObserver {
  late final VoiceSessionController _session;
  late final VoiceDraftGateway _gateway;
  VoiceCatalog? _catalog;
  VoiceDraftController<VoicePlanDraft, int>? _draft;
  String? _loadError;

  final VoiceSegmentFeed _feed = VoiceSegmentFeed();
  final List<String> _applied = [];
  VoiceIntent? _otherIntent;
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
      final catalog = await _gateway.planCatalog();
      if (!mounted) return;
      final draft = VoiceDraftController<VoicePlanDraft, int>(
        initial: VoicePlanDraft.start(catalog),
        commit: _gateway.confirmPlan,
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
        _sync('d${line.key}', _doseText(line), line.dose);
      }
    }
    setState(() {});
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
        final r = interpretPlan(fresh, current, catalog!);
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

  /// Con 4 decimales de hectárea el texto representa el área exacta en m²:
  /// con 2, un chaco de 12 345 m² se vería «1,23» y no coincidiría con lo
  /// que se escribe (revisión de A, M-1).
  static String _areaText(VoicePlanDraft d) => d.area.value == null
      ? (d.area.heard ?? '')
      : formatForInput(d.area.value! / 10000, maxDecimals: 4);

  static String _doseText(VoicePlanLine line) => line.doseBasePerHa == null
      ? (line.dose.heard ?? '')
      : formatForInput(line.doseBasePerHa! / baseUnitsPerMajor);

  /// Campos resueltos cuyo texto visible no dice lo mismo que el borrador:
  /// si hay alguno, no se confirma (mismo criterio que la compra).
  List<String> _visibleMismatches(VoicePlanDraft d) {
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
      final c = _fields['d${l.key}'];
      if (c != null &&
          l.dose.isResolved &&
          tryParseBase(c.text) != l.doseBasePerHa) {
        out.add('Producto ${i + 1}: la dosis visible no coincide.');
      }
    }
    return out;
  }

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null || _visibleMismatches(draft.draft).isNotEmpty) return;
    final id = await draft.confirm();
    if (id == null || !mounted) return;
    await _session.discard();
    if (!mounted) return;
    setState(() => _leaving = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Plan creado (n.º $id).')));
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

  Future<void> _onBack() async {
    if (_draft?.phase == DraftPhase.confirming) return;
    final discard = await confirmDestructiveAction(
      context,
      title: '¿Descartar el borrador?',
      detail: 'No se creó ningún plan. Lo dictado y lo corregido se pierden.',
      confirmLabel: 'Descartar',
    );
    if (discard && mounted) await _cancel();
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
    VoiceDraftController<VoicePlanDraft, int>? draft,
    VoiceCatalog? catalog,
  ) {
    return PageFrame(
      title: 'Planificación por voz',
      subtitle: 'Dicte el plan, revíselo y créelo con un toque.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VoiceDraftNotice(
            confirmLabel: 'Crear plan',
            catalogs: 'Los chacos y productos',
          ),
          const SizedBox(height: 12),
          VoiceListeningPanel(session: _session),
          const SizedBox(height: 12),
          if (_otherIntent != null)
            VoiceOtherIntentBanner(
              intent: _otherIntent!,
              current: 'planificación',
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
              onPressed: widget.onOpenManualForm,
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
    VoiceDraftController<VoicePlanDraft, int> controller,
    VoiceCatalog catalog,
  ) {
    final d = controller.draft;
    final editable = controller.phase == DraftPhase.editing;
    final theme = Theme.of(context);
    final mismatches = _visibleMismatches(d);
    return Column(
      key: const Key('voz-borrador-plan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              (c) => proposeFarmArea(
                c.copyWith(
                  farm: DraftField.resolved(entry, origin: FieldOrigin.manual),
                ),
              ),
            ),
          ),
        ),
        DraftFieldRow(
          label: 'Área (ha)',
          field: d.area,
          child: _numberField(
            id: 'area',
            key: const Key('voz-area'),
            value: _areaText(d),
            enabled: editable,
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
              onPressed: controller.canConfirm && mismatches.isEmpty
                  ? _confirm
                  : null,
              icon: controller.phase == DraftPhase.confirming
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Crear plan'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineCard(
    BuildContext context,
    VoiceDraftController<VoicePlanDraft, int> controller,
    VoiceCatalog catalog,
    VoicePlanDraft d,
    int index,
    VoicePlanLine line,
    bool editable,
  ) {
    final unit = line.product.value?.unit;
    final unitLabel = unit == CatalogUnit.kilogram ? 'KG' : 'L';
    final need = line.requiredBase(d.area.isResolved ? d.area.value : null);

    void update(VoicePlanLine Function(VoicePlanLine) change) =>
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
              label: 'Dosis ($unitLabel/ha)',
              field: line.dose,
              child: _numberField(
                id: 'd${line.key}',
                key: Key('voz-dosis-${line.key}'),
                value: _doseText(line),
                enabled: editable,
                onChanged: (text) {
                  final base = tryParseBase(text);
                  update(
                    (l) => l.copyWith(
                      dose: base == null || base <= 0
                          ? const DraftField.invalid(
                              message: 'Escriba una dosis mayor a cero.',
                              origin: FieldOrigin.manual,
                            )
                          : DraftField.resolved(
                              SpokenDose(
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
              need == null
                  ? 'Necesita: se calcula con el área y la dosis.'
                  : 'Necesita ${formatQuantity(need, unitLabel)}',
              key: Key('voz-necesita-${line.key}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required String id,
    required Key key,
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) => TextField(
    key: key,
    controller: _controller(id, value),
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: onChanged,
  );
}
