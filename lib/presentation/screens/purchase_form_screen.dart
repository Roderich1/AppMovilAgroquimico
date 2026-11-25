import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../operation_mode_controller.dart';
import '../../voice/port/voice_engine_diagnostics.dart'
    show voiceDiagnosticsBuild;
import '../../voice/session/voice_session_controller.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_evidence/voice_evidence.dart' show VoiceEvidenceOutcome;
import '../voice/voice_draft_widgets.dart' show voicePurchaseTurnHints;
import '../voice/voice_evidence_hook.dart';
import '../voice/voice_form_dictation.dart';
import '../voice/voice_purchase_port.dart';
import '../voice/voice_turn_experiment.dart' show VoiceSingleTranscriberPanel;
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';
import 'late_operations_screen.dart' show offerLateRegistration;
import 'purchase_form/purchase_form_notifier.dart';
import 'purchase_form/purchase_form_state.dart';
import 'purchase_form/purchase_form_voice_adapter.dart';
import 'purchase_form/purchase_items_step.dart';
import 'purchase_form/purchase_line_sheet.dart';
import 'purchase_form/purchase_review_step.dart';

export 'purchase_form/purchase_form_state.dart' show lotNumberCounter;

/// Nueva compra en dos pasos (ajuste tras el piloto X01, 2026-10-25):
///
/// 1. **Proveedor y productos**: proveedor, fecha (hoy por defecto) y las
///    líneas con su cantidad, precio y, en compartido, su reparto explícito.
/// 2. **Revisión y pago**: lo que se va a guardar, la pregunta
///    «¿Ya pagaste al proveedor?» (sin respuesta por defecto) y, plegados,
///    factura, notas y campaña.
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key, this.voice = false});

  /// Abrir con el panel «Completar por voz» visible (atajo «Registrar por
  /// voz»). El micrófono no se abre solo: hay que pulsar «Hablar».
  final bool voice;

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen>
    with WidgetsBindingObserver, VoiceEvidenceRecording<PurchaseFormScreen> {
  late final _formProvider = purchaseFormProvider(Object());
  final _controllers = PurchaseFormControllers();
  VoiceFormDictation<VoicePurchaseDraft>? _voice;
  bool _canReadRef = true;
  PurchaseFormState _lastState = PurchaseFormState.initial();
  late final PurchaseFormVoiceAdapter _voiceTarget = PurchaseFormVoiceAdapter(
    readState: () => _canReadRef ? ref.read(_formProvider) : _lastState,
    readNotifier: () => ref.read(_formProvider.notifier),
    readVoice: () => _voice,
    onApplied: (shadow, text, lineIds) =>
        noteVoiceApplied(shadow, text, lineIds: lineIds),
    onAfterStateSync: () {
      if (!mounted) return;
      _controllers.syncFromVoice(ref.read(_formProvider));
    },
  );

  bool _voiceSaved = false;
  bool _voiceFailed = false;
  bool _observingSession = false;

  PurchaseFormNotifier get _notifier => ref.read(_formProvider.notifier);

  void _onEdited() {
    _voice?.reconcile(_voiceTarget.snapshot());
  }

  void _openVoice() {
    _voice ??= VoiceFormDictation<VoicePurchaseDraft>(
      session: VoiceSessionController(
        port: ref.read(purchaseSpeechPortFactoryProvider)(),
      ),
      target: _voiceTarget,
    )..addListener(_onVoice);
    if (!_observingSession) {
      _observingSession = true;
      _voice!.session.addListener(
        () => observeVoiceSession(_voice!.session.snapshot),
      );
    }
    final catalog = _voiceTarget.catalog;
    if (catalog != null) {
      _voice!.session.setVocabularyHints(voicePurchaseTurnHints(catalog));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _notifier.openVoicePanel();
  }

  void _onVoice() {
    if (!mounted) return;
    final v = _voice;
    if (v != null) _notifier.syncVoiceCompletion(v.completions);
  }

  Future<void> _pickDate() async {
    final currentDay = ref.read(_formProvider).effectiveDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: startOfLocalDay(currentDay),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    _notifier.setEffectiveDay(localDay(picked));
  }

  Future<void> _close() async {
    if (ref.read(_formProvider).dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('La compra todavía no fue guardada.'),
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
      );
      if (discard != true) return;
    }
    if (!mounted) return;
    _notifier.clearDirty();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initVoiceEvidence();
    ref.listenManual(operationModeProvider, (_, next) {
      final loaded = ref.read(_formProvider).loadedMode;
      if (modeChangedSince(loaded, next) && (_voice?.busy ?? false)) {
        _voice!.cancel();
      }
    });
    if (widget.voice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openVoice();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _voice?.session.handleAppPaused();
  }

  Future<Map<String, Object?>?> _createSupplier() async {
    final id = await createSupplierFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id == null) return null;
    final next = await _notifier.reloadCatalogs();
    return next?.suppliers.where((row) => row['id'] == id).firstOrNull;
  }

  Future<Map<String, Object?>?> _createProduct() async {
    final id = await createProductFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id == null) return null;
    final next = await _notifier.reloadCatalogs();
    return next?.products.where((row) => row['id'] == id).firstOrNull;
  }

  Future<Map<String, Object?>?> _createPerson() async {
    final id = await createPersonFromDialog(
      context,
      ref.read(repositoryProvider),
      purpose: PersonPurpose.purchaseAllocation,
    );
    if (id == null) return null;
    final next = await _notifier.reloadCatalogs(people: true);
    return next?.people.where((row) => row['id'] == id).firstOrNull;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (!mounted || picked == null) return;
      _notifier.setInvoiceImage(picked);
    } catch (_) {
      if (mounted) {
        showError(
          context,
          'No se pudo adjuntar la factura. Revise los permisos.',
        );
      }
    }
  }

  void _openLine(int id) {
    FocusManager.instance.primaryFocus?.unfocus();
    _notifier.openLine(id);
  }

  void _closeLine() {
    FocusManager.instance.primaryFocus?.unfocus();
    _notifier.closeLine();
  }

  void _addLine() {
    final lines = ref.read(_formProvider).lines;
    final touched =
        lines.length == 1 && (_voice?.touchesLine(lines.single.id) ?? false);
    final blankSingle =
        lines.length == 1 && lines.single.isBlank(touchedByVoice: touched);
    if (!blankSingle) FocusManager.instance.primaryFocus?.unfocus();
    _notifier.addLine(touchedByVoice: touched);
  }

  void _appendLine() {
    FocusManager.instance.primaryFocus?.unfocus();
    _notifier.appendLine();
  }

  void _removeLine(PurchaseLineData line) {
    FocusManager.instance.primaryFocus?.unfocus();
    _voice?.lineRemoved(line.id);
    _notifier.removeLine(line.id);
  }

  void _goToReview() {
    final result = _notifier.tryGoToReview();
    if (!result.ok && result.errorMessage != null) {
      showError(context, result.errorMessage!);
    }
  }

  Future<void> _confirm() async {
    final outcome = await _notifier.confirmPurchase(
      onLateOffer: (draft, error, paid) {
        if (!mounted) return Future.value(false);
        return offerLateRegistration(
          context,
          error: error,
          what: 'esta compra',
          extraNote: paid
              ? 'El pago al proveedor no se guarda con la revisión. Si el '
                    'titular la confirma, anótelo después en Actividad › Lista '
                    'de compras, «Registrar pago al proveedor».'
              : null,
          capture: (reason) => ref
              .read(repositoryProvider)
              .captureLatePurchase(draft, reason: reason),
        );
      },
    );
    if (!mounted) return;
    switch (outcome.status) {
      case PurchaseSaveStatus.confirmed:
        _voiceSaved = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
      case PurchaseSaveStatus.lateCaptured:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      case PurchaseSaveStatus.validationError:
        if (outcome.errorMessage != null) {
          showError(context, outcome.errorMessage!);
        }
      case PurchaseSaveStatus.aborted:
        if (outcome.error != null) {
          _voiceFailed = true;
          showError(context, outcome.error!);
        }
    }
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
    ref.listen(_formProvider.select((s) => s.catalogs), (_, next) {
      if (next != null) {
        _voiceTarget.updateCatalog(next, state: ref.read(_formProvider));
      }
    });
    ref.listen(_formProvider, (_, next) {
      _lastState = next;
      _controllers.detachRemoved(next);
    });

    final state = ref.watch(_formProvider);
    _lastState = state;
    final currentMode = ref.watch(operationModeProvider);
    return PopScope(
      canPop:
          !state.dirty &&
          !state.saving &&
          state.step == PurchaseStep.items &&
          state.editingLineId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || state.saving) return;
        if (state.editingLineId != null) {
          _closeLine();
          return;
        }
        if (state.step == PurchaseStep.review) {
          _notifier.backToItems();
        } else {
          _close();
        }
      },
      child: Scaffold(
        bottomNavigationBar: _bottomBar(state, currentMode),
        body: _body(context, state, currentMode),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PurchaseFormState state,
    OperationMode? currentMode,
  ) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _header(state),
    );
    if (state.catalogsError != null) {
      return SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(state.catalogsError!),
              ),
            ),
          ],
        ),
      );
    }
    final data = state.catalogs;
    if (data == null) {
      return SafeArea(
        child: Column(
          children: [
            header,
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }
    final modeChanged = modeChangedSince(state.loadedMode, currentMode);
    final editing = state.editingLine;
    final sheetOpen = editing != null && state.step == PurchaseStep.items;
    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            key: const Key('purchase-page'),
            excluding: sheetOpen,
            child: ExcludeFocus(
              excluding: sheetOpen,
              child: IgnorePointer(
                ignoring: sheetOpen,
                child: SafeArea(
                  child: Column(
                    children: [
                      header,
                      Expanded(
                        child: ListView(
                          key: const Key('purchase-scroll'),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            if (modeChanged) ...[
                              const ModeChangedNotice(),
                              const SizedBox(height: 12),
                            ],
                            if (state.step == PurchaseStep.items)
                              ...buildPurchaseItemsStep(
                                state: state,
                                data: data,
                                voice: _voice,
                                onOpenVoice: _openVoice,
                                onDismissVoiceBanner:
                                    _notifier.dismissVoiceBanner,
                                onCreateSupplier: _createSupplier,
                                onSupplierChanged: (id) {
                                  _notifier.setSupplier(id);
                                  _onEdited();
                                },
                                onPickDate: _pickDate,
                                onOpenLine: _openLine,
                                onAddLine: _addLine,
                              )
                            else
                              ...buildPurchaseReviewStep(
                                context,
                                state: state,
                                data: data,
                                controllers: _controllers,
                                notifier: _notifier,
                                onPickImage: _pickImage,
                                onEdited: _onEdited,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (sheetOpen)
          Positioned.fill(
            child: PurchaseLineSheet(
              state: state,
              data: data,
              line: editing,
              index: state.lines.indexOf(editing),
              controllers: _controllers.line(editing),
              notifier: _notifier,
              voice: _voice,
              currentMode: currentMode,
              onCloseLine: _closeLine,
              onAppendLine: _appendLine,
              onOpenVoiceFromSheet: () {
                _closeLine();
                _openVoice();
              },
              onCreateProduct: _createProduct,
              onCreatePerson: _createPerson,
              onRemoveLine: () => _removeLine(editing),
              onEdited: _onEdited,
            ),
          ),
      ],
    );
  }

  Widget _header(PurchaseFormState state) {
    final review = state.step == PurchaseStep.review;
    final busy = _voice?.busy ?? false;
    final data = state.catalogs;
    final campaign = state.personalOwnerId == null || data == null
        ? null
        : data.campaigns
              .where((c) => c['id'] == state.campaignId)
              .map((c) => c['name']?.toString())
              .firstOrNull;
    return Column(
      children: [
        FlowTopBar(
          backKey: Key(review ? 'purchase-back' : 'purchase-close'),
          backTooltip: review ? 'Volver al paso 1' : 'Volver',
          onBack: state.saving
              ? null
              : review
              ? _notifier.backToItems
              : _close,
          label: campaign == null
              ? 'Paso ${review ? 2 : 1} de 2'
              : 'Paso ${review ? 2 : 1} de 2 · $campaign',
          labelKey: const Key('purchase-step'),
          trailing: CircleIconButton(
            key: const Key('form-dictar'),
            icon: state.showVoice && !review
                ? Icons.mic
                : Icons.mic_none_outlined,
            tooltip: state.showVoice && !review
                ? 'Ocultar el panel de voz'
                : 'Completar por voz',
            onPressed: state.saving
                ? null
                : review
                ? () {
                    _notifier.backToItems();
                    _openVoice();
                  }
                : state.showVoice
                ? busy
                      ? null
                      : _notifier.hideVoicePanel
                : _openVoice,
          ),
        ),
        const SizedBox(height: 12),
        StepProgress(step: review ? 2 : 1, total: 2),
      ],
    );
  }

  Widget? _bottomBar(PurchaseFormState state, OperationMode? currentMode) {
    final items = state.step == PurchaseStep.items;
    if (items && state.editingLineId != null) return null;
    if (items && state.showVoice && _voice != null) {
      return VoiceFormPanel(
        dictation: _voice!,
        docked: true,
        listeningHint: state.personalOwnerId != null
            ? 'Diga producto, cantidad y precio'
            : 'Diga producto, cantidad, precio y para quién',
        example: state.personalOwnerId != null
            ? '«Doce litros de herbicida a ciento dieciocho, de Agroinsumos»'
            : '«Doce litros de herbicida a ciento dieciocho, de Agroinsumos, '
                  'para Rosa»',
        onClose: _notifier.hideVoicePanel,
        diagnostics: voiceDiagnosticsBuild
            ? VoiceSingleTranscriberPanel(session: _voice!.session)
            : null,
      );
    }
    final voiceBlock = _voice?.blocksSave ?? false;
    final blocked =
        state.saving ||
        voiceBlock ||
        state.catalogs == null ||
        modeChangedSince(state.loadedMode, currentMode);
    if (items) {
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
          PurchaseItemsTotal(state: state, voice: _voice),
          const SizedBox(height: 12),
          PrimaryActionButton(
            key: const Key('purchase-continue'),
            label: 'Continuar',
            onPressed: blocked ? null : _goToReview,
          ),
        ],
      );
    }
    return BottomPanel(
      children: [
        PrimaryActionButton(
          key: const Key('purchase-confirm'),
          label: state.saving ? 'Guardando…' : 'Confirmar compra',
          icon: Icons.check,
          iconFirst: true,
          busy: state.saving,
          onPressed: blocked ? null : _confirm,
        ),
      ],
    );
  }
}
