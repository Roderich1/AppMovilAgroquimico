import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/adaptive_entity_picker.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initVoiceEvidence();
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
    setState(() => showVoice = true);
  }

  void _onVoice() {
    if (mounted) setState(() {});
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

  Future<void> submit(_PlanCatalogs data) async {
    // Un solo registro aunque se toque dos veces (el botón se deshabilita en
    // el siguiente fotograma).
    if (saving) return;
    // El mensaje unico mencionaba el chaco aunque ya estuviera elegido
    // (UIBUG-032): ahora dice exactamente que falta.
    if (farmId == null && lines.isEmpty) {
      showError(context, 'Seleccione el chaco y agregue al menos un producto.');
      return;
    }
    if (farmId == null) {
      showError(context, 'Seleccione el chaco.');
      return;
    }
    if (lines.isEmpty) {
      showError(context, 'Agregue al menos un producto al plan.');
      return;
    }
    if (lines.any((l) => l.product == null)) {
      showError(context, 'Elija el producto de cada línea o quite la línea.');
      return;
    }
    final items = <PlanItemDraft>[];
    for (final l in lines) {
      final d = tryParseBase(l.dose.text) ?? 0;
      if (d <= 0) {
        showError(context, 'Todas las dosis deben ser mayores a cero.');
        return;
      }
      items.add(
        PlanItemDraft(productId: l.product!['id'] as int, doseBasePerHa: d),
      );
    }
    setState(() => saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .addPlanMulti(
            farmId: farmId!,
            campaignId: data.campaign['id'] as int,
            areaM2: ((tryParseDecimal(area.text) ?? 0) * 10000).round(),
            items: items,
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
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !saving) close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva planificación'),
        actions: [
          // F09 (formulario único): la voz completa ESTE formulario.
          IconButton(
            key: const Key('form-dictar'),
            tooltip: showVoice
                ? 'Ocultar el panel de voz'
                : 'Completar por voz',
            icon: Icon(showVoice ? Icons.mic : Icons.mic_none_outlined),
            onPressed: saving
                ? null
                : showVoice
                ? (voice?.busy ?? false)
                      ? null
                      : () => setState(() => showVoice = false)
                : _openVoice,
          ),
        ],
        leading: IconButton(
          onPressed: saving ? null : close,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_PlanCatalogs>(
            future: future,
            builder: (context, s) {
              final voiceBlock = voice?.blocksSave ?? false;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (voiceBlock)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        voice!.saveBlockReason!,
                        key: const Key('voz-bloqueo-guardar'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  FilledButton.icon(
                    key: const Key('plan-confirm'),
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
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar planificación'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: FutureBuilder<_PlanCatalogs>(
        future: future,
        builder: (context, s) {
          if (s.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(s.error!),
            );
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          final d = s.data!;
          final farm = d.farms.where((f) => f['id'] == farmId).firstOrNull;
          final addable = d.products
              .where((p) => !lines.any((l) => l.product?['id'] == p['id']))
              .toList();
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                if (modeChangedSince(
                  loadedMode,
                  ref.watch(operationModeProvider),
                )) ...[
                  const ModeChangedNotice(),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Campaña activa · ${d.campaign['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                if (showVoice && voice != null)
                  VoiceFormPanel(
                    dictation: voice!,
                    engineHint:
                        'Hable por frases cortas: chaco, área y la dosis por '
                        'hectárea de cada producto. Pulse «Terminar» al '
                        'acabar. Nada se guarda solo.',
                    onClose: () => setState(() => showVoice = false),
                    // Sólo en la compilación de diagnóstico: política B, comparar
                    // pistas y lo que propuso cada motor (ruta por frases).
                    diagnostics:
                        voiceDiagnosticsBuild && _voiceTarget.catalog != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const VoicePolicyBSwitch(),
                              VoiceContextExperimentSwitch(
                                domainHints: () => voiceDomainContextHints(
                                  _voiceTarget.catalog!,
                                ),
                              ),
                              VoiceProposalsButton(describe: (_) => const []),
                            ],
                          )
                        : null,
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('plan-completar-voz'),
                      onPressed: saving ? null : _openVoice,
                      icon: const Icon(Icons.mic_none_outlined),
                      label: const Text('Completar por voz'),
                    ),
                  ),
                const SizedBox(height: 16),
                AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Chaco',
                  items: d.farms,
                  value: farm,
                  labelOf: (f) => f['name'] as String,
                  secondaryOf: (f) =>
                      '${f['owner_name']} · ${formatHectares(f['area_m2'] as int)}',
                  onChanged: selectFarm,
                  createLabel: 'Crear chaco',
                  onCreate: _createFarm,
                ),
                VoiceSlotMark(
                  dictation: voice,
                  slot: const SlotRef.header('farm'),
                  current: farmId,
                  currentDisplay: farm?['name']?.toString(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: area,
                  onChanged: (_) => _edited(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Área planificada (ha)',
                  ),
                ),
                VoiceSlotMark(
                  dictation: voice,
                  slot: const SlotRef.header('area'),
                  current: _PlanVoice._areaCanon(area.text),
                  currentDisplay: area.text,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Productos (${lines.length})',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    // Nombre accesible: sin él el lector de pantalla sólo
                    // anunciaba «botón» (2026-11-05).
                    IconButton.filled(
                      tooltip: 'Agregar al plan',
                      onPressed: productToAdd == null ? null : add,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Agregar producto',
                  items: addable,
                  value: productToAdd,
                  labelOf: (p) => p['name'] as String,
                  secondaryOf: (p) => p['unit'] as String,
                  onChanged: (p) => setState(() => productToAdd = p),
                  // El producto a agregar se elige siempre, aunque quede uno:
                  // con la autoselección el único producto quedaba elegido al
                  // elegir el chaco y podía pisar uno recién creado (prueba
                  // (e) de ux_altas_en_contexto bajo carga, 2026-11-05).
                  autoSelectSingle: false,
                  enabled: farmId != null,
                  createLabel: 'Crear producto',
                  onCreate: _createProduct,
                ),
                // Sin el aviso «Agregue los productos…» con la lista vacía:
                // repetía lo que ya dicen «Productos (0)» y el selector
                // «Agregar producto» justo encima (2026-11-05).
                const SizedBox(height: 8),
                for (final l in lines)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: l.product == null
                          // Línea dictada con el producto por elegir (fuera
                          // del catálogo, ambiguo o repetido): se elige aquí.
                          ? AdaptiveEntityPicker<Map<String, Object?>>(
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
                          : Text(
                              l.product!['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VoiceSlotMark(
                            dictation: voice,
                            slot: SlotRef.line(l.id, 'product'),
                            current: l.product?['id'],
                            currentDisplay: l.product?['name']?.toString(),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: l.dose,
                            onChanged: (_) => _edited(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: l.product == null
                                  ? 'Dosis por hectárea'
                                  : 'Dosis (${l.product!['unit']}/ha)',
                              isDense: true,
                            ),
                          ),
                          VoiceSlotMark(
                            dictation: voice,
                            slot: SlotRef.line(l.id, 'dose'),
                            current: l.voiceFields()['dose'],
                            currentDisplay: l.dose.text,
                          ),
                          if (voice?.touchesLine(l.id) ?? false) ...[
                            if (l.product == null)
                              const VoiceMissingMark(label: 'producto'),
                            if (l.voiceFields()['dose'] == null)
                              const VoiceMissingMark(label: 'dosis'),
                          ],
                          const SizedBox(height: 6),
                          if (l.product != null)
                            Builder(
                              builder: (_) {
                                final unit = l.product!['unit'] as String;
                                final need = needed(l);
                                final stock = ownerStock[l.product!['id']] ?? 0;
                                final missing = need > stock ? need - stock : 0;
                                return Text(
                                  'Necesita ${formatQuantity(need, unit)} · stock ${formatQuantity(stock, unit)} · ${missing == 0 ? 'cubierto' : 'comprar ${formatQuantity(missing, unit)}'}',
                                );
                              },
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: 'Quitar producto',
                        onPressed: () {
                          setState(() {
                            lines.remove(l);
                            voice?.lineRemoved(l.id);
                            l.dispose();
                            dirty = true;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
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
