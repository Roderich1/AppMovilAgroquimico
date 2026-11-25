import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../operation_mode_controller.dart';
import '../../voice/port/voice_engine_diagnostics.dart'
    show voiceDiagnosticsBuild;
import '../../voice/session/voice_session_controller.dart';
import '../../voice_draft/application/voice_application_draft.dart';
import '../../voice_evidence/voice_evidence.dart' show VoiceEvidenceOutcome;
import '../theme/agro_theme.dart';
import '../voice/voice_draft_gateway.dart' show voiceDraftGatewayProvider;
import '../voice/voice_draft_widgets.dart' show voiceDomainContextHints;
import '../voice/voice_evidence_hook.dart';
import '../voice/voice_form_dictation.dart';
import '../voice/voice_proposals_view.dart'
    show VoiceContextExperimentSwitch, VoicePolicyBSwitch, VoiceProposalsButton;
import '../widgets/agro_ui.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';
import '../../voice/voice_providers.dart' show speechPortFactoryProvider;
import 'application_form/application_form_notifier.dart';
import 'application_form/application_form_state.dart';
import 'application_form/application_form_voice_adapter.dart';
import 'application_form/application_products_step.dart';
import 'application_form/application_review_step.dart';
import 'application_form/application_who_step.dart';
import 'late_operations_screen.dart' show offerLateRegistration;

export 'application_form/application_form_state.dart'
    show applicationPersonLabel;

/// Nueva aplicación en tres pasos (ajuste tras el piloto X01, 2026-10-25).
class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key, this.planId, this.voice = false});
  final int? planId;

  /// Abrir con el panel «Completar por voz» visible (atajo «Registrar por
  /// voz»). El micrófono no se abre solo.
  final bool voice;

  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen>
    with WidgetsBindingObserver, VoiceEvidenceRecording<ApplicationFormScreen> {
  final _route = Object();

  NotifierProvider<ApplicationFormNotifier, ApplicationFormState>
  get _formProvider =>
      applicationFormProvider((route: _route, planId: widget.planId));

  final _controllers = ApplicationFormControllers();
  VoiceFormDictation<VoiceApplicationDraft>? _voice;
  bool _canReadRef = true;
  late ApplicationFormState _lastState = ApplicationFormState.initial(
    planId: widget.planId,
  );
  late final ApplicationFormVoiceAdapter _voiceTarget =
      ApplicationFormVoiceAdapter(
        readState: () => _canReadRef ? ref.read(_formProvider) : _lastState,
        readNotifier: () => ref.read(_formProvider.notifier),
        readVoice: () => _voice,
        loadVoiceCatalog: () =>
            ref.read(voiceDraftGatewayProvider).applicationCatalog(),
        onApplied: (shadow, text, lineIds) =>
            noteVoiceApplied(shadow, text, lineIds: lineIds),
        onOpenPlan: _openPlanFromVoice,
      );

  bool _voiceSaved = false;
  bool _voiceFailed = false;
  bool _observingSession = false;

  ApplicationFormNotifier get _notifier => ref.read(_formProvider.notifier);

  ApplicationFormState get _currentState => ref.read(_formProvider);

  void _openVoice() {
    _voice ??= VoiceFormDictation<VoiceApplicationDraft>(
      session: VoiceSessionController(
        port: ref.read(speechPortFactoryProvider)(),
      ),
      target: _voiceTarget,
    )..addListener(_onVoice);
    if (!_observingSession) {
      _observingSession = true;
      _voice!.session.addListener(
        () => observeVoiceSession(_voice!.session.snapshot),
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _notifier.openVoicePanel();
    unawaited(_loadVoiceCatalog());
  }

  Future<void> _loadVoiceCatalog() async {
    await _voiceTarget.loadCatalog();
    if (mounted) setState(() {});
  }

  void _onVoice() {
    if (!mounted) return;
    final v = _voice;
    if (v != null) _notifier.syncVoiceCompletion(v.completions);
  }

  Future<void> _openPlanFromVoice(int planId) async {
    if (_currentState.dirty &&
        !await confirmDestructiveAction(
          context,
          title: '¿Descartar cambios?',
          detail:
              'Lo cargado en esta aplicación no se guardó. Se abrirá el plan '
              'elegido con sus productos.',
          confirmLabel: 'Abrir el plan',
        )) {
      return;
    }
    if (!mounted) return;
    _notifier.clearDirty();
    context.pushReplacement('/aplicaciones/nueva?planId=$planId');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startOfLocalDay(_currentState.effectiveDay),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    _notifier.setEffectiveDay(localDay(picked));
  }

  Future<void> _selectPerson(Map<String, Object?>? person) async {
    final completed = await _notifier.selectPerson(person);
    if (completed && mounted) {
      _voice?.reconcile(_voiceTarget.snapshot());
    }
  }

  Future<void> _selectFarm(Map<String, Object?>? farm) async {
    final err = await _notifier.selectFarm(farm);
    if (!mounted) return;
    if (err != null) {
      showError(context, err);
      return;
    }
    _voice?.reconcile(_voiceTarget.snapshot());
  }

  Future<Map<String, Object?>?> _createFarm() async {
    final owner = _currentState.personId;
    if (owner == null) return null;
    final id = await createFarmFromDialog(
      context,
      ref.read(repositoryProvider),
      ownerId: owner,
    );
    if (id == null) return null;
    return _notifier.reloadFarmsAfterCreate(id);
  }

  Future<Map<String, Object?>?> _createPerson() async {
    final id = await createPersonFromDialog(
      context,
      ref.read(repositoryProvider),
      purpose: PersonPurpose.applicator,
    );
    if (id == null) return null;
    return _notifier.reloadPeopleAfterCreate(id);
  }

  Future<void> _registerPurchase() async {
    await context.push<bool>('/compras/nueva');
    if (!mounted) return;
    await _notifier.refreshStock();
  }

  Future<void> _addProduct() async {
    final result = await showModalBottomSheet<ApplicationLineInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          ApplicationProductSheet(options: _currentState.addableProducts),
    );
    if (result == null || !mounted) return;
    final error = _notifier.addLineFromSheet(
      result.product,
      result.quantityBase,
    );
    if (error != null) showError(context, error);
  }

  Future<void> _editLine(ApplicationLineData line) async {
    final addable = _currentState.addableProducts;
    final result = await showModalBottomSheet<ApplicationLineInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => line.product['product_id'] == null
          ? ApplicationProductSheet(
              options: addable,
              initialQuantityBase: line.quantityBase,
            )
          : ApplicationProductSheet(
              options: [line.product, ...addable],
              initial: ApplicationLineInput(line.product, line.quantityBase),
            ),
    );
    if (result == null || !mounted) return;
    _notifier.updateLineFromSheet(line.id, result.product, result.quantityBase);
    _voice?.reconcile(_voiceTarget.snapshot());
  }

  void _removeLine(ApplicationLineData line) {
    _voice?.lineRemoved(line.id);
    _notifier.removeLine(line.id);
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('La aplicación todavía no fue guardada.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _requestClose() async {
    if (!_currentState.dirty || await _confirmDiscard()) {
      if (mounted) {
        _notifier.clearDirty();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  void _back() {
    if (!_notifier.goBackStep()) {
      unawaited(_requestClose());
    }
  }

  void _continue() {
    final result = _notifier.tryContinue();
    if (!result.ok && result.errorMessage != null) {
      showError(context, result.errorMessage!);
    }
  }

  Future<void> _submit(ApplicationCatalogs data) async {
    final outcome = await _notifier.submit(
      data: data,
      onLateOffer: (application, error) {
        if (!mounted) return Future.value(false);
        return offerLateRegistration(
          context,
          error: error,
          what: 'esta aplicación',
          capture: (reason) => ref
              .read(repositoryProvider)
              .captureLateApplication(application, reason: reason),
        );
      },
    );
    if (!mounted) return;
    switch (outcome.status) {
      case ApplicationSaveStatus.confirmed:
        _voiceSaved = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
      case ApplicationSaveStatus.lateCaptured:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      case ApplicationSaveStatus.validationError:
        if (outcome.errorMessage != null) {
          showError(context, outcome.errorMessage!);
        }
      case ApplicationSaveStatus.aborted:
        if (outcome.error != null) {
          _voiceFailed = true;
          showError(context, outcome.error!);
        }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initVoiceEvidence();
    ref.listenManual(operationModeProvider, (_, next) {
      final loaded = _currentState.loadedMode;
      if (modeChangedSince(loaded, next) && (_voice?.busy ?? false)) {
        _voice!.cancel();
      }
    });
    if (widget.voice && widget.planId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openVoice();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _voice?.session.handleAppPaused();
  }

  @override
  void activate() {
    super.activate();
    _canReadRef = true;
  }

  @override
  void deactivate() {
    _canReadRef = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _canReadRef = false;
    WidgetsBinding.instance.removeObserver(this);
    if (_voiceTarget.catalog != null) {
      finishFormVoiceEvidence(
        formDraft: _voiceTarget.evidenceDraft,
        outcome: _voiceSaved
            ? VoiceEvidenceOutcome.confirmed
            : _voiceFailed
            ? VoiceEvidenceOutcome.failed
            : VoiceEvidenceOutcome.discarded,
      );
    }
    _voice?.removeListener(_onVoice);
    _voice?.release();
    _voice?.dispose();
    _controllers.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _formProvider;
    ref.listen(provider, (prev, next) {
      _lastState = next;
      if (prev?.catalogs == null && next.catalogs != null) {
        _controllers.syncInitial(next);
      } else if (prev?.areaSyncCounter != next.areaSyncCounter) {
        _controllers.syncArea(next.areaText);
      }
      _controllers.detachRemoved(next);
    });

    final state = ref.watch(provider);
    _lastState = state;
    final currentMode = ref.watch(operationModeProvider);
    return PopScope(
      canPop:
          !state.dirty && !state.saving && state.step == ApplicationStep.who,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !state.saving) _back();
      },
      child: Scaffold(
        bottomNavigationBar: _bottomBar(state, currentMode),
        body: SafeArea(child: _body(context, state, currentMode)),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ApplicationFormState state,
    OperationMode? currentMode,
  ) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _header(state),
    );
    if (state.catalogsError != null) {
      return Column(
        children: [
          header,
          Expanded(
            child: EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(state.catalogsError!),
            ),
          ),
        ],
      );
    }
    final data = state.catalogs;
    if (data == null) {
      return Column(
        children: [
          header,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    return Column(
      children: [
        header,
        Expanded(
          child: ListView(
            key: const Key('application-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (modeChangedSince(state.loadedMode, currentMode)) ...[
                const ModeChangedNotice(),
                const SizedBox(height: 12),
              ],
              ...switch (state.step) {
                ApplicationStep.who => buildApplicationWhoStep(
                  context,
                  state: state,
                  data: data,
                  areaController: _controllers.area,
                  voice: _voice,
                  onOpenVoice: _openVoice,
                  onDismissVoiceBanner: _notifier.dismissVoiceBanner,
                  onSelectPerson: _selectPerson,
                  onCreatePerson: _createPerson,
                  onSelectFarm: _selectFarm,
                  onCreateFarm: _createFarm,
                  onPickDate: _pickDate,
                  onAreaChanged: (text) {
                    _notifier.setAreaText(text);
                    _voice?.reconcile(_voiceTarget.snapshot());
                  },
                ),
                ApplicationStep.products => buildApplicationProductsStep(
                  context,
                  state: state,
                  data: data,
                  controllers: _controllers,
                  voice: _voice,
                  onOpenVoice: _openVoice,
                  onDismissVoiceBanner: _notifier.dismissVoiceBanner,
                  onRegisterPurchase: _registerPurchase,
                  onAddProduct: _addProduct,
                  onEditLine: _editLine,
                  onRemoveLine: _removeLine,
                  onToggleLineDetail: _notifier.toggleLineDetail,
                  onDoseChanged: _notifier.setLineDose,
                ),
                ApplicationStep.review => buildApplicationReviewStep(
                  context,
                  state: state,
                  data: data,
                  notesController: _controllers.notes,
                  onToggleCostHelp: _notifier.toggleCostHelp,
                  onNotesChanged: _notifier.setNotesText,
                ),
              },
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(ApplicationFormState state) {
    final campaign = state.catalogs?.campaign['name']?.toString();
    final first = state.step == ApplicationStep.who;
    final busy = _voice?.busy ?? false;
    return Column(
      children: [
        FlowTopBar(
          backKey: Key(first ? 'application-close' : 'application-back'),
          backTooltip: first
              ? 'Volver'
              : 'Volver al paso ${state.stepNumber - 1}',
          onBack: state.saving ? null : _back,
          label: first && campaign != null
              ? 'Paso 1 de 3 · $campaign'
              : 'Paso ${state.stepNumber} de 3',
          labelKey: const Key('application-step'),
          trailing: state.voiceStep
              ? CircleIconButton(
                  key: const Key('form-dictar'),
                  icon: state.showVoice ? Icons.mic : Icons.mic_none_outlined,
                  tooltip: state.showVoice
                      ? 'Ocultar el panel de voz'
                      : 'Completar por voz',
                  onPressed: state.saving
                      ? null
                      : state.showVoice
                      ? busy
                            ? null
                            : _notifier.hideVoicePanel
                      : _openVoice,
                )
              : null,
        ),
        const SizedBox(height: 12),
        StepProgress(step: state.stepNumber, total: 3),
      ],
    );
  }

  Widget _bottomBar(ApplicationFormState state, OperationMode? currentMode) {
    if (state.voiceStep && state.showVoice && _voice != null) {
      return VoiceFormPanel(
        dictation: _voice!,
        docked: true,
        listeningHint: 'Diga chaco, superficie, producto y cantidad',
        example: '«En el chaco Norte, tres hectáreas, dos litros de herbicida»',
        engineHint:
            'Hable por frases cortas y pulse «Terminar» al acabar. Lo dictado '
            'aparece en los pasos 1 y 2.',
        onClose: _notifier.hideVoicePanel,
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
    final voiceBlock = _voice?.blocksSave ?? false;
    final blocked =
        state.saving ||
        voiceBlock ||
        state.catalogs == null ||
        modeChangedSince(state.loadedMode, currentMode);
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
                    _voice!.saveBlockReason!,
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
        if (state.step == ApplicationStep.review)
          PrimaryActionButton(
            key: const Key('application-confirm'),
            label: state.saving ? 'Guardando…' : 'Confirmar aplicación',
            icon: Icons.check,
            iconFirst: true,
            busy: state.saving,
            onPressed: blocked ? null : () => _submit(state.catalogs!),
          )
        else
          PrimaryActionButton(
            key: const Key('application-continue'),
            label: 'Continuar',
            onPressed: blocked ? null : _continue,
          ),
      ],
    );
  }
}
