import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/agro_ui.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';
import '../voice/voice_draft_widgets.dart'
    show voiceDomainContextHints, voiceVocabularyHints;
import '../voice/voice_evidence_hook.dart';
import '../voice/voice_proposals_view.dart'
    show VoiceContextExperimentSwitch, VoicePolicyBSwitch, VoiceProposalsButton;
import '../../voice/port/voice_engine_diagnostics.dart'
    show voiceDiagnosticsBuild;
import '../voice/voice_form_dictation.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/session/voice_session_state.dart';
import '../../voice/voice_providers.dart' show speechPortFactoryProvider;
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/numeric_review.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/plan/plan_interpreter.dart';
import '../../voice_draft/plan/voice_plan_draft.dart';
import '../../voice_draft/text/units.dart';
import '../../voice_evidence/voice_evidence.dart' show VoiceEvidenceOutcome;

part 'plan_form_voice.dart';

typedef _PlanCatalogs = ({
  Map<String, Object?> campaign,
  List<Map<String, Object?>> farms,
  List<Map<String, Object?>> products,
});

class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen({super.key, this.voice = false});

  /// Abrir con el panel «Completar por voz» visible (atajo «Registrar por
  /// voz»). El micrófono no se abre solo.
  final bool voice;
  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen>
    with WidgetsBindingObserver, VoiceEvidenceRecording<PlanFormScreen> {
  late Future<_PlanCatalogs> future;
  int _nextLineId = 1;

  /// Chacos y productos cargados (para poner lo que se elige por voz).
  List<Map<String, Object?>> _farms = const [];
  List<Map<String, Object?>> _products = const [];

  /// «Completar por voz».
  VoiceFormDictation<VoicePlanDraft>? voice;
  late final _voiceTarget = _PlanVoice(this);
  bool showVoice = false;

  /// Aviso del último dictado arriba del formulario (el panel se cierra solo
  /// al terminar un dictado; lo dictado ya está en el formulario).
  bool _voiceBanner = false;
  int _seenCompletions = 0;
  VoicePlanDraft? _lastVoiceDraft;
  bool _voiceSaved = false;
  bool _voiceFailed = false;
  bool _observingSession = false;
  int? farmId;
  Map<String, Object?>? productToAdd;
  final area = TextEditingController();
  final lines = <_PlanLine>[];
  Map<int, int> ownerStock = {};
  bool dirty = false, saving = false;

  /// Modalidad con la que se cargaron los chacos (#26).
  OperationMode? loadedMode;

  /// Modo individual (rediseño, láminas I-23 e I-24): el formulario no habla
  /// de responsables, admite la fecha prevista y pasa por «Revise el plan»
  /// antes de guardar. En el modo con varias personas no cambia nada.
  bool get _personal => loadedMode == OperationMode.personal;

  /// Paso «Revise el plan» (sólo modo individual).
  bool reviewing = false;

  /// Fecha prevista `aaaa-mm-dd` (opcional; sólo modo individual). Ya existía
  /// en el modelo (`application_plans.planned_date`).
  String? plannedDay;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initVoiceEvidence();
    // Rediseño individual (2026-11-13): si la modalidad cambia con un
    // dictado en curso, se cancela; su resultado tardío no llega al
    // formulario (que además queda bloqueado por `ModeChangedNotice`).
    ref.listenManual(operationModeProvider, (_, next) {
      if (modeChangedSince(loadedMode, next) && (voice?.busy ?? false)) {
        voice!.cancel();
      }
    });
    future = _load();
    if (widget.voice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openVoice();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) voice?.session.handleAppPaused();
  }

  void _openVoice() {
    voice ??= VoiceFormDictation<VoicePlanDraft>(
      session: VoiceSessionController(
        port: ref.read(speechPortFactoryProvider)(),
      ),
      target: _voiceTarget,
    )..addListener(_onVoice);
    if (!_observingSession) {
      _observingSession = true;
      voice!.session.addListener(
        () => observeVoiceSession(voice!.session.snapshot),
      );
    }
    final catalog = _voiceTarget.catalog;
    if (catalog != null) {
      voice!.session.setVocabularyHints(voiceVocabularyHints(catalog));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      showVoice = true;
      _voiceBanner = false;
    });
  }

  /// Al terminar un dictado el panel se cierra y su resultado queda en el
  /// aviso de arriba.
  void _onVoice() {
    if (!mounted) return;
    final v = voice;
    setState(() {
      if (v != null && v.completions != _seenCompletions) {
        _seenCompletions = v.completions;
        showVoice = false;
        _voiceBanner = true;
      }
    });
  }

  void _voiceApplied(VoicePlanDraft shadow, String text) {
    _lastVoiceDraft = shadow;
    noteVoiceApplied(shadow, text);
  }

  void _voiceSetState(VoidCallback fn) => setState(fn);

  /// Tras una edición manual: lo pendiente de ese campo queda resuelto.
  void _edited() {
    setState(() => dirty = true);
    voice?.reconcile(_voiceTarget.snapshot());
  }

  /// Chaco puesto por voz: como elegirlo, pero sin pisar el área (que tiene
  /// su propia ranura en el dictado).
  void _selectFarmForVoice(Map<String, Object?>? farm) =>
      selectFarm(farm, prefillArea: false);

  Future<_PlanCatalogs> _load() async {
    final r = ref.read(repositoryProvider);
    final active = await r.activeCampaign();
    if (active == null)
      throw BusinessRuleException('Active una campaña antes de planificar.');
    // En propio sólo los chacos del titular; modalidad en la misma consulta.
    final farms = await r.farmsAndContext();
    loadedMode = farms.context.mode;
    final loaded = (
      campaign: active,
      farms: farms.farms,
      products: await r.products(),
    );
    _farms = loaded.farms;
    _products = loaded.products;
    _voiceTarget.updateCatalog(loaded);
    return loaded;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    finishVoiceEvidenceWith(
      finalDraft: _lastVoiceDraft,
      outcome: _voiceSaved
          ? VoiceEvidenceOutcome.confirmed
          : _voiceFailed
          ? VoiceEvidenceOutcome.failed
          : VoiceEvidenceOutcome.discarded,
    );
    voice?.removeListener(_onVoice);
    voice?.release();
    voice?.dispose();
    area.dispose();
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> selectFarm(
    Map<String, Object?>? farm, {
    bool prefillArea = true,
  }) async {
    setState(() {
      farmId = farm?['id'] as int?;
      dirty = true;
      ownerStock = {};
    });
    if (farm != null && prefillArea) {
      final hectares = (farm['area_m2'] as int) / 10000;
      // Convenio es-BO: el campo debe precargarse como el usuario podria
      // teclearlo (coma decimal), no como "80.0" (UIBUG-003).
      area.text = formatForInput(hectares, maxDecimals: 2);
    }
    if (prefillArea) voice?.reconcile(_voiceTarget.snapshot());
    if (farm == null) return;
    final rows = await ref
        .read(repositoryProvider)
        .personStockSummary(farm['owner_person_id'] as int);
    if (!mounted || farmId != farm['id']) return;
    setState(
      () => ownerStock = {
        for (final r in rows)
          r['product_id'] as int: r['available_base'] as int,
      },
    );
  }

  /// Tras crear un chaco o un producto desde su selector: se vuelven a leer
  /// sólo chacos y productos. Campaña, chaco elegido, área, líneas y dosis
  /// se conservan.
  Future<_PlanCatalogs> _reloadFarmsAndProducts() async {
    final r = ref.read(repositoryProvider);
    final current = await future;
    final farms = await r.farmsAndContext();
    final next = (
      campaign: current.campaign,
      farms: farms.farms,
      products: await r.products(),
    );
    _farms = next.farms;
    _products = next.products;
    _voiceTarget.updateCatalog(next);
    if (mounted) {
      setState(() {
        // `SynchronousFuture`: el `FutureBuilder` toma la lista nueva en la
        // misma reconstrucción. Con `Future.value` pasaba un fotograma con la
        // lista vieja, el selector no encontraba lo elegido y autoelegía la
        // única opción anterior encima de lo recién creado.
        future = SynchronousFuture(next);
      });
    }
    return next;
  }

  /// «Crear chaco»: el alta de Catálogos sobre el plan. Si se cancela o
  /// falla, el plan queda igual.
  Future<Map<String, Object?>?> _createFarm() async {
    final id = await createFarmFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id == null) return null;
    final next = await _reloadFarmsAndProducts();
    return next.farms.where((f) => f['id'] == id).firstOrNull;
  }

  /// «Crear producto»: igual que [_createFarm]. Lo creado queda elegido
  /// para agregarlo al plan.
  Future<Map<String, Object?>?> _createProduct() async {
    final id = await createProductFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id == null) return null;
    final next = await _reloadFarmsAndProducts();
    return next.products.where((p) => p['id'] == id).firstOrNull;
  }

  void add() {
    final p = productToAdd;
    if (p == null) return;
    if (lines.any((l) => l.product?['id'] == p['id'])) {
      showError(context, 'El producto ya está agregado.');
      return;
    }
    setState(() {
      lines.add(_PlanLine(_nextLineId++, p));
      productToAdd = null;
      dirty = true;
    });
  }

  int needed(_PlanLine l) =>
      ((tryParseDecimal(area.text) ?? 0) *
              (tryParseDecimal(l.dose.text) ?? 0) *
              1000)
          .round();
  Future<bool> discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('El plan todavía no fue guardado.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              // Criterio unico de accion destructiva, el mismo que usa
              // `confirmDestructiveAction` en las reversiones (UIBUG-033).
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> close() async {
    if (!dirty || await discard()) {
      if (mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  /// Las líneas del plan listas para guardar, o `null` tras avisar qué falta.
  List<PlanItemDraft>? _validItems() {
    // El mensaje unico mencionaba el chaco aunque ya estuviera elegido
    // (UIBUG-032): ahora dice exactamente que falta.
    if (farmId == null && lines.isEmpty) {
      showError(context, 'Seleccione el chaco y agregue al menos un producto.');
      return null;
    }
    if (farmId == null) {
      showError(context, 'Seleccione el chaco.');
      return null;
    }
    if (lines.isEmpty) {
      showError(context, 'Agregue al menos un producto al plan.');
      return null;
    }
    if (lines.any((l) => l.product == null)) {
      showError(context, 'Elija el producto de cada línea o quite la línea.');
      return null;
    }
    final items = <PlanItemDraft>[];
    for (final l in lines) {
      final d = tryParseBase(l.dose.text) ?? 0;
      if (d <= 0) {
        showError(context, 'Todas las dosis deben ser mayores a cero.');
        return null;
      }
      items.add(
        PlanItemDraft(productId: l.product!['id'] as int, doseBasePerHa: d),
      );
    }
    return items;
  }

  /// «Continuar» del modo individual: comprueba lo mismo que «Guardar plan»
  /// y muestra «Revise el plan» (lámina I-24). No guarda nada.
  void _toReview() {
    if (saving || _validItems() == null) return;
    if ((tryParseDecimal(area.text) ?? 0) <= 0) {
      showError(context, 'Escriba la superficie prevista.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      showVoice = false;
      reviewing = true;
    });
  }

  Future<void> _pickPlannedDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: plannedDay == null ? now : startOfLocalDay(plannedDay!),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Fecha prevista',
    );
    if (picked == null || !mounted) return;
    setState(() {
      plannedDay = localDay(picked);
      dirty = true;
    });
  }

  Future<void> submit(_PlanCatalogs data) async {
    // Un solo registro aunque se toque dos veces (el botón se deshabilita en
    // el siguiente fotograma).
    if (saving) return;
    final items = _validItems();
    if (items == null) return;
    setState(() => saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .addPlanMulti(
            farmId: farmId!,
            campaignId: data.campaign['id'] as int,
            areaM2: ((tryParseDecimal(area.text) ?? 0) * 10000).round(),
            items: items,
            // Sólo el modo individual la pide; sin ella, «sin fecha» como
            // hasta ahora.
            plannedDate: plannedDay == null
                ? null
                : startOfLocalDay(plannedDay!),
          );
      if (!mounted) return;
      _voiceSaved = true;
      // `saving` se queda en true hasta cerrar: un segundo toque no guarda
      // otro plan.
      setState(() => dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (mounted) {
        _voiceFailed = true;
        setState(() => saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving && !reviewing,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || saving) return;
      // Desde «Revise el plan», Atrás vuelve al formulario sin perder nada.
      if (reviewing) {
        setState(() => reviewing = false);
      } else {
        close();
      }
    },
    child: Scaffold(
      bottomNavigationBar: _bottomBar(),
      body: SafeArea(
        child: FutureBuilder<_PlanCatalogs>(
          future: future,
          builder: (context, s) {
            final header = Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _header(s.data?.campaign['name']?.toString()),
            );
            if (s.hasError) {
              return Column(
                children: [
                  header,
                  Expanded(
                    child: EmptyState(
                      icon: Icons.error_outline,
                      message: friendlyError(s.error!),
                    ),
                  ),
                ],
              );
            }
            if (!s.hasData) {
              return Column(
                children: [
                  header,
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }
            final d = s.data!;
            final farm = d.farms.where((f) => f['id'] == farmId).firstOrNull;
            final addable = d.products
                .where((p) => !lines.any((l) => l.product?['id'] == p['id']))
                .toList();
            if (reviewing) {
              return Column(
                children: [
                  header,
                  Expanded(child: _reviewList(farm)),
                ],
              );
            }
            return Column(
              children: [
                header,
                Expanded(
                  child: ListView(
                    key: const Key('plan-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (modeChangedSince(
                        loadedMode,
                        ref.watch(operationModeProvider),
                      )) ...[
                        const ModeChangedNotice(),
                        const SizedBox(height: 12),
                      ],
                      Semantics(
                        header: true,
                        child: const Text(
                          '¿Qué piensa aplicar?',
                          style: AgroText.h1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._voiceEntry(),
                      AgroGroup(
                        children: [
                          // Lo que falta se calcula con las existencias del
                          // responsable del chaco.
                          AdaptiveEntityPicker<Map<String, Object?>>(
                            rowStyle: true,
                            label: 'Chaco',
                            // Modo individual: todo es del titular; no se
                            // repite su nombre (lámina I-23).
                            hint: farm == null
                                ? null
                                : _personal
                                ? '${formatHectares(farm['area_m2'] as int)}'
                                      ' · se compara con sus existencias'
                                : '${farm['owner_name']} · se compara con '
                                      'sus existencias',
                            hintKey: const Key('plan-farm-owner'),
                            items: d.farms,
                            value: farm,
                            labelOf: (f) => f['name'] as String,
                            secondaryOf: (f) => _personal
                                ? formatHectares(f['area_m2'] as int)
                                : '${f['owner_name']} · '
                                      '${formatHectares(f['area_m2'] as int)}',
                            onChanged: selectFarm,
                            createLabel: 'Crear chaco',
                            onCreate: _createFarm,
                            badge: VoiceMarkBadge(
                              dictation: voice,
                              slot: const SlotRef.header('farm'),
                              current: farmId,
                            ),
                          ),
                          // Lámina I-23: fecha prevista, opcional.
                          if (_personal)
                            ValueRow(
                              key: const Key('plan-planned-date'),
                              label: 'Fecha prevista (opcional)',
                              value: plannedDay == null
                                  ? null
                                  : displayDay(plannedDay!),
                              placeholder: 'Sin fecha',
                              onTap: saving ? null : _pickPlannedDay,
                            ),
                        ],
                      ),
                      VoiceSlotMark(
                        dictation: voice,
                        slot: const SlotRef.header('farm'),
                        current: farmId,
                        currentDisplay: farm?['name']?.toString(),
                        showMark: false,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('plan-area'),
                        controller: area,
                        onChanged: (_) => _edited(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: AgroText.input,
                        decoration: InputDecoration(
                          labelText: _personal
                              ? 'Superficie prevista'
                              : 'Área planificada',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          suffixText: 'ha',
                          suffixStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.muted,
                          ),
                        ),
                      ),
                      VoiceSlotMark(
                        dictation: voice,
                        slot: const SlotRef.header('area'),
                        current: _PlanVoice._areaCanon(area.text),
                        currentDisplay: area.text,
                      ),
                      const SizedBox(height: 20),
                      Text('Productos (${lines.length})', style: AgroText.h2),
                      const SizedBox(height: 10),
                      for (final l in lines) _lineCard(l, addable),
                      // Elegir el producto y después «Agregar al plan»: dos
                      // actos explícitos, como hasta ahora.
                      Row(
                        children: [
                          Expanded(
                            child: AgroGroup(
                              children: [
                                AdaptiveEntityPicker<Map<String, Object?>>(
                                  rowStyle: true,
                                  label: 'Agregar producto',
                                  placeholder: farmId == null
                                      ? 'Elija primero el chaco'
                                      : 'Elegir',
                                  items: addable,
                                  value: productToAdd,
                                  labelOf: (p) => p['name'] as String,
                                  secondaryOf: (p) => p['unit'] as String,
                                  onChanged: (p) =>
                                      setState(() => productToAdd = p),
                                  // El producto a agregar se elige siempre,
                                  // aunque quede uno: con la autoselección el
                                  // único producto quedaba elegido al elegir
                                  // el chaco y podía pisar uno recién creado
                                  // (prueba (e) de ux_altas_en_contexto bajo
                                  // carga, 2026-11-05).
                                  autoSelectSingle: false,
                                  enabled: farmId != null,
                                  createLabel: 'Crear producto',
                                  onCreate: _createProduct,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Nombre accesible: sin él el lector de pantalla
                          // sólo anunciaba «botón» (2026-11-05).
                          IconButton.filled(
                            key: const Key('plan-add-line'),
                            tooltip: 'Agregar al plan',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(56, 56),
                              backgroundColor: AgroColors.ink,
                              foregroundColor: AgroColors.lime,
                            ),
                            onPressed: productToAdd == null ? null : add,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// Volver, «Nuevo plan · campaña» y el acceso a la voz.
  Widget _header(String? campaign) {
    final busy = voice?.busy ?? false;
    return FlowTopBar(
      backKey: Key(reviewing ? 'plan-back' : 'plan-close'),
      backTooltip: reviewing ? 'Volver al plan' : 'Volver',
      onBack: saving
          ? null
          : reviewing
          ? () => setState(() => reviewing = false)
          : close,
      label: campaign == null ? 'Nuevo plan' : 'Nuevo plan · $campaign',
      labelKey: const Key('plan-header'),
      // F09 (formulario único): la voz completa ESTE formulario. En «Revise
      // el plan» no se dicta: se vuelve al formulario.
      trailing: reviewing
          ? null
          : CircleIconButton(
              key: const Key('form-dictar'),
              icon: showVoice ? Icons.mic : Icons.mic_none_outlined,
              tooltip: showVoice
                  ? 'Ocultar el panel de voz'
                  : 'Completar por voz',
              onPressed: saving
                  ? null
                  : showVoice
                  ? busy
                        ? null
                        : () => setState(() => showVoice = false)
                  : _openVoice,
            ),
    );
  }

  /// «Revise el plan» (modo individual, lámina I-24): chaco, fecha y
  /// superficie previstas y lo «Previsto en planes» por producto, con lo que
  /// tiene. Un plan no descuenta existencias ni genera deuda: se dice.
  Widget _reviewList(Map<String, Object?>? farm) {
    final day = plannedDay == null
        ? 'Sin fecha prevista'
        : 'Previsto para el ${displayDay(plannedDay!)}';
    final areaM2 = ((tryParseDecimal(area.text) ?? 0) * 10000).round();
    return ListView(
      key: const Key('plan-review'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Semantics(
          header: true,
          child: const Text('Revise el plan', style: AgroText.h1),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  farm?['name']?.toString() ?? '',
                  key: const Key('plan-review-farm'),
                  style: AgroText.value,
                ),
                Text(
                  '$day · ${formatHectares(areaM2)}',
                  key: const Key('plan-review-when'),
                  style: AgroText.detail,
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AgroColors.line),
                const SizedBox(height: 10),
                const Text('PREVISTO EN PLANES', style: AgroText.label),
                const SizedBox(height: 4),
                for (final l in lines)
                  if (l.product case final product?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${product['name']} · '
                            '${formatQuantity(needed(l), product['unit'] as String)}',
                            key: Key('plan-review-line-${l.id}'),
                            style: AgroText.value,
                          ),
                          Text(
                            '${l.dose.text.trim()} ${product['unit']} por ha · '
                            'tiene ${formatQuantity(ownerStock[product['id']] ?? 0, product['unit'] as String)}',
                            style: AgroText.detail,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const NoticeBox(
          key: Key('plan-review-notice'),
          text:
              'Un plan no descuenta existencias ni registra una deuda. El '
              'producto sale del almacén cuando registre la aplicación.',
        ),
      ],
    );
  }

  /// Panel inferior: «Guardar plan» o el panel de voz, que ocupa su lugar
  /// mientras está abierto.
  Widget _bottomBar() {
    if (showVoice && voice != null) {
      return VoiceFormPanel(
        dictation: voice!,
        docked: true,
        // Modo individual: láminas I-13 e I-14.
        individualHint: _personal
            ? 'Diga chaco, superficie, producto y dosis'
            : null,
        example:
            '«Chaco Norte, tres hectáreas, fungicida a dos litros por '
            'hectárea»',
        engineHint:
            'Hable por frases cortas: chaco, área y la dosis por hectárea de '
            'cada producto. Pulse «Terminar» al acabar.',
        onClose: () => setState(() => showVoice = false),
        // Sólo en la compilación de diagnóstico: política B, comparar pistas
        // y lo que propuso cada motor (ruta por frases).
        diagnostics: voiceDiagnosticsBuild && _voiceTarget.catalog != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const VoicePolicyBSwitch(),
                  VoiceContextExperimentSwitch(
                    domainHints: () =>
                        voiceDomainContextHints(_voiceTarget.catalog!),
                  ),
                  VoiceProposalsButton(describe: (_) => const []),
                ],
              )
            : null,
      );
    }
    return FutureBuilder<_PlanCatalogs>(
      future: future,
      builder: (context, s) {
        final voiceBlock = voice?.blocksSave ?? false;
        return BottomPanel(
          children: [
            if (voiceBlock)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.rule, size: 18, color: AgroColors.caution),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        voice!.saveBlockReason!,
                        key: const Key('voz-bloqueo-guardar'),
                        style: AgroText.detail.copyWith(
                          color: AgroColors.warnInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Modo individual: primero «Revise el plan» (lámina I-24).
            if (_personal && !reviewing)
              PrimaryActionButton(
                key: const Key('plan-continue'),
                label: 'Continuar',
                onPressed:
                    saving ||
                        voiceBlock ||
                        !s.hasData ||
                        modeChangedSince(
                          loadedMode,
                          ref.watch(operationModeProvider),
                        )
                    ? null
                    : _toReview,
              )
            else
              PrimaryActionButton(
                key: const Key('plan-confirm'),
                label: saving ? 'Guardando…' : 'Guardar plan',
                icon: Icons.check,
                iconFirst: true,
                busy: saving,
                onPressed:
                    saving ||
                        voiceBlock ||
                        !s.hasData ||
                        modeChangedSince(
                          loadedMode,
                          ref.watch(operationModeProvider),
                        )
                    ? null
                    : () => submit(s.data!),
              ),
          ],
        );
      },
    );
  }

  /// El aviso del último dictado o el botón que abre el panel. Con el panel
  /// abierto no se muestra nada aquí (el panel va abajo).
  List<Widget> _voiceEntry() {
    if (showVoice) return const [];
    if (voice != null && _voiceBanner) {
      return [
        VoiceResultBanner(
          dictation: voice!,
          // Modo individual: lámina I-15.
          individual: _personal,
          onDictateMore: saving ? null : _openVoice,
          onDismiss: () => setState(() => _voiceBanner = false),
        ),
        const SizedBox(height: 12),
      ];
    }
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          key: const Key('plan-completar-voz'),
          icon: Icons.mic_none_outlined,
          label: 'Completar por voz',
          onPressed: saving ? null : _openVoice,
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  void _removeLine(_PlanLine l) {
    setState(() {
      lines.remove(l);
      voice?.lineRemoved(l.id);
      l.dispose();
      dirty = true;
    });
  }

  /// Tarjeta de un producto del plan: producto, dosis por hectárea, lo que
  /// necesita el área y si las existencias del responsable lo cubren.
  Widget _lineCard(_PlanLine l, List<Map<String, Object?>> addable) {
    final product = l.product;
    final unit = product?['unit'] as String?;
    final need = product == null ? 0 : needed(l);
    final stock = product == null ? 0 : ownerStock[product['id']] ?? 0;
    final missing = need > stock ? need - stock : 0;
    // Modo individual (lámina I-23): «Tiene 14 L · alcanza». Es una
    // comparación con lo que tiene, no una reserva.
    final (String badge, BadgeTone tone) = need <= 0
        ? ('Escriba la dosis', BadgeTone.neutral)
        : _personal
        ? missing == 0
              ? (
                  'Tiene ${formatQuantity(stock, unit!)} · alcanza',
                  BadgeTone.ok,
                )
              : (
                  'Tiene ${formatQuantity(stock, unit!)} · faltan '
                      '${formatQuantity(missing, unit)}',
                  BadgeTone.review,
                )
        : missing == 0
        ? ('Cubierto · hay ${formatQuantity(stock, unit!)}', BadgeTone.ok)
        : (
            'Falta comprar ${formatQuantity(missing, unit!)} · '
                'hay ${formatQuantity(stock, unit)}',
            BadgeTone.review,
          );
    return Card(
      key: Key('plan-line-${l.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: product == null
                      // Línea dictada con el producto por elegir (fuera del
                      // catálogo, ambiguo o repetido): se elige aquí.
                      ? AdaptiveEntityPicker<Map<String, Object?>>(
                          rowStyle: true,
                          label: 'Producto',
                          items: addable,
                          value: null,
                          labelOf: (p) => p['name'] as String,
                          secondaryOf: (p) => p['unit'] as String,
                          autoSelectSingle: false,
                          onChanged: (p) {
                            setState(() => l.product = p);
                            _edited();
                          },
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            product['name'] as String,
                            style: AgroText.value,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: 'Quitar producto',
                  color: AgroColors.muted,
                  onPressed: () => _removeLine(l),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            VoiceSlotMark(
              dictation: voice,
              slot: SlotRef.line(l.id, 'product'),
              current: product?['id'],
              currentDisplay: product?['name']?.toString(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: l.dose,
                      onChanged: (_) => _edited(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AgroText.input,
                      decoration: InputDecoration(
                        labelText: product == null
                            ? 'Dosis por hectárea'
                            : 'Dosis ($unit/ha)',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                    ),
                  ),
                  if (product != null) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _personal ? 'Cantidad prevista' : 'Necesita',
                          style: AgroText.label,
                        ),
                        Text(
                          formatQuantity(need, unit!),
                          key: Key('plan-line-need-${l.id}'),
                          style: AgroText.input,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            VoiceSlotMark(
              dictation: voice,
              slot: SlotRef.line(l.id, 'dose'),
              current: l.voiceFields()['dose'],
              currentDisplay: l.dose.text,
            ),
            if (voice?.touchesLine(l.id) ?? false) ...[
              if (product == null) const VoiceMissingMark(label: 'producto'),
              if (l.voiceFields()['dose'] == null)
                const VoiceMissingMark(label: 'dosis'),
            ],
            if (product != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(
                  key: Key('plan-line-coverage-${l.id}'),
                  label: badge,
                  tone: tone,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanLine {
  _PlanLine(this.id, this.product);

  /// Identificador estable (no la posición), para el dictado.
  final int id;

  /// Producto de la línea. Nulo sólo en una línea dictada cuyo producto
  /// queda por elegir; «Guardar planificación» no la acepta así.
  Map<String, Object?>? product;
  final dose = TextEditingController();
  void dispose() => dose.dispose();

  /// Valores canónicos para el dictado (`null` = vacío).
  Map<String, Object?> voiceFields() {
    final t = dose.text.trim();
    return {
      'product': product?['id'],
      'dose': t.isEmpty ? null : (tryParseBase(t) ?? 'texto:$t'),
    };
  }
}
