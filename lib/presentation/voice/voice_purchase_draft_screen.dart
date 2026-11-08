/// Compra por voz: dictar, revisar, corregir y registrar con un toque (#11,
/// con el patrón común de #16).
///
/// - Lo dictado **provisional** se ve aparte (panel de escucha) y no cuenta.
/// - Cada segmento **cerrado** se interpreta y se aplica al borrador, y se
///   muestra como «aplicado».
/// - Cada campo indica si está resuelto, es ambiguo, falta o no es válido, y
///   se puede corregir a mano. Lo corregido a mano no lo cambia la voz.
/// - Los selectores son los del formulario (búsqueda y «Crear proveedor»,
///   «Crear producto», «Agregar persona»): el alta la pide la persona, se
///   abre sobre el borrador y lo creado queda elegido. La voz no crea nada.
/// - «¿Ya pagaste al proveedor?» se responde como en el formulario: sin
///   respuesta no se registra; con «Sí, pagué todo» la compra y su pago se
///   guardan juntos (`confirmPurchase(paidInFull:)`).
/// - «Registrar compra» sólo se habilita sin bloqueos y escribe una vez, con
///   el mismo caso de uso que el formulario manual.
/// - Cancelar o salir libera el micrófono y descarta el borrador sin escribir.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/campaign_calendar.dart' show localDay;
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/ui/voice_capture_screen.dart';
import '../../voice/voice_providers.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/numeric_review.dart';
import '../../voice_draft/core/voice_draft_controller.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/purchase/purchase_interpreter.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_draft/text/units.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';
import '../widgets/provider_payment_fields.dart';
import 'voice_draft_gateway.dart';
import 'voice_draft_widgets.dart';
import 'voice_evidence_hook.dart';

class VoicePurchaseDraftScreen extends ConsumerStatefulWidget {
  const VoicePurchaseDraftScreen({
    super.key,
    this.onOpenManualForm,
    this.initialDraftForTest,
  });

  /// Alternativa manual equivalente (formulario de compra). La conecta quien
  /// integra la ruta.
  final VoidCallback? onOpenManualForm;

  /// Sólo pruebas: borrador inicial en vez del vacío, para mostrar estados
  /// que aún no produce ningún intérprete (un valor por revisar).
  @visibleForTesting
  final VoicePurchaseDraft Function(VoiceCatalog catalog)? initialDraftForTest;

  @override
  ConsumerState<VoicePurchaseDraftScreen> createState() =>
      _VoicePurchaseDraftScreenState();
}

class _VoicePurchaseDraftScreenState
    extends ConsumerState<VoicePurchaseDraftScreen>
    with
        WidgetsBindingObserver,
        VoiceDraftExit<VoicePurchaseDraftScreen>,
        VoiceEvidenceRecording<VoicePurchaseDraftScreen> {
  late final VoiceSessionController _session;
  late final VoiceDraftGateway _gateway;
  VoiceCatalog? _catalog;
  VoiceDraftController<VoicePurchaseDraft, int>? _draft;
  String? _loadError;

  final VoiceSegmentFeed _feed = VoiceSegmentFeed();

  /// Persona dictada que se ignoró por estar en inventario propio.
  String? _ignoredRecipient;
  final List<VoiceHeardSegment> _heard = [];
  VoiceIntent? _otherIntent;

  /// Desacuerdos numéricos de la sesión ya aplicados al borrador.
  int _seenDisagreements = 0;

  /// Precio oído sin una línea clara a la que aplicarlo (último dictado).
  UnplacedPrice? _unplacedPrice;

  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gateway = ref.read(voiceDraftGatewayProvider);
    initVoiceEvidence();
    _session = VoiceSessionController(
      port: ref.read(speechPortFactoryProvider)(),
    );
    _session.addListener(_onSession);
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await _gateway.purchaseCatalog();
      if (!mounted) return;
      final draft = VoiceDraftController<VoicePurchaseDraft, int>(
        initial:
            widget.initialDraftForTest?.call(catalog) ??
            VoicePurchaseDraft.start(catalog),
        commit: _gateway.confirmPurchase,
        describeError: friendlyError,
      )..addListener(_onDraft);
      // Los nombres del catálogo orientan la segunda pasada local; no
      // restringen lo que se dicta ni convierten nada en esos nombres.
      _session.setVocabularyHints(voiceVocabularyHints(catalog));
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
    // Salir libera el micrófono y descarta el borrador: no se escribe nada.
    _session.dispose();
    // Una sola entrada de evidencia por borrador, sea cual sea la salida.
    finishVoiceEvidence(_draft);
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
    _syncFields();
    setState(() {});
  }

  /// Refleja en los campos de texto los valores que cambió la voz. Un campo
  /// corregido a mano no se toca: lo que el usuario escribió se queda.
  void _syncFields() {
    final draft = _draft?.draft;
    if (draft == null) return;
    _sync('fx', _fxText(draft), draft.exchangeRate);
    for (final line in draft.lines) {
      _sync('q${line.key}', _quantityText(line), line.quantity);
      _sync('p${line.key}', _priceText(line), line.price);
    }
  }

  static String _fxText(VoicePurchaseDraft d) => d.exchangeRate.value == null
      ? ''
      : formatForInput(d.exchangeRate.value! / fxScale, maxDecimals: 6);

  /// Campos cuyo texto visible no dice lo mismo que el borrador. Si hay
  /// alguno, no se confirma: se escribiría algo distinto de lo que se ve
  /// (revisión de A, B-100-2).
  List<String> _visibleMismatches(VoicePurchaseDraft d) {
    final out = <String>[];
    // Sólo se comparan campos resueltos: los demás ya bloquean por sí mismos.
    bool differs(
      String id,
      DraftField<Object?> field,
      int? expected,
      int? Function(String) parse,
    ) {
      final c = _fields[id];
      if (c == null || !field.isResolved) return false;
      return parse(c.text) != expected;
    }

    if (d.lines.any((l) => l.currency.value == CurrencyCode.usd) &&
        differs(
          'fx',
          d.exchangeRate,
          d.exchangeRate.isResolved ? d.exchangeRate.value : null,
          (t) {
            final v = tryParseDecimal(t);
            return v == null ? null : (v * fxScale).round();
          },
        )) {
      out.add('El tipo de cambio visible no coincide con el borrador.');
    }
    for (var i = 0; i < d.lines.length; i++) {
      final l = d.lines[i];
      // La cantidad visible se compara con la leída; con el producto elegido
      // y de la misma unidad es `quantityBase`. Si no, la línea ya bloquea.
      if (differs(
        'q${l.key}',
        l.quantity,
        _spokenQuantityBase(l),
        tryParseBase,
      )) {
        out.add('Línea ${i + 1}: la cantidad visible no coincide.');
      }
      if (differs('p${l.key}', l.price, l.unitPriceMinor, tryParseMinor)) {
        out.add('Línea ${i + 1}: el precio visible no coincide.');
      }
    }
    return out;
  }

  /// Interpreta sólo lo cerrado y nuevo de la sesión. El texto provisional
  /// no se interpreta nunca.
  void _onSession() {
    if (!mounted) return;
    final snapshot = _session.snapshot;
    observeVoiceSession(snapshot);
    final draft = _draft;
    final catalog = _catalog;
    final ready = draft != null && catalog != null;
    final fresh = _feed.take(snapshot.committedText, ready: ready);
    // Desacuerdo numérico entre Vosk y la revisión (POCO 2026-11-08): el
    // contador sube en la misma notificación que el texto que lo trae. Los
    // campos numéricos que cambió ese texto quedan «por revisar». Si el
    // borrador aún carga, no se consume: se marca al tomar el texto.
    final disagreed = snapshot.numericDisagreements > _seenDisagreements;
    if (ready || snapshot.numericDisagreements < _seenDisagreements) {
      _seenDisagreements = snapshot.numericDisagreements;
    }
    if (fresh != null) {
      VoiceIntent? other;
      String? ignored;
      UnplacedPrice? unplaced;
      var outcome = const VoicePatchOutcome();
      final accepted = draft!.applyVoice((current) {
        final r = interpretPurchase(fresh, current, catalog!);
        other = r.otherIntent;
        ignored = r.ignoredRecipient;
        unplaced = r.unplacedPrice;
        outcome = r.outcome;
        final next = disagreed
            ? reviewPurchaseNumbers(
                current,
                r.draft,
                numericDisagreementMessage,
              )
            : r.draft;
        return (next, r.outcome);
      });
      if (accepted) {
        // Evidencia (#167): sólo se anota en memoria; se entrega al salir.
        noteVoiceApplied(draft.draft, fresh);
        _otherIntent = other;
        if (ignored != null) _ignoredRecipient = ignored;
        _unplacedPrice = other == null ? unplaced : null;
        if (other == null) _heard.add(VoiceHeardSegment.from(fresh, outcome));
      }
    }
    setState(() {});
  }

  TextEditingController _controller(String id, String value) =>
      _fields.putIfAbsent(id, () => TextEditingController(text: value));

  /// La cantidad leída, normalizada a L o KG, también con el producto aún
  /// por elegir o con el valor por revisar (POCO 2026-11-08).
  static String _quantityText(VoicePurchaseLine line) =>
      spokenAmountText(_spokenQuantityBase(line), line.quantity.heard);

  static int? _spokenQuantityBase(VoicePurchaseLine line) {
    final q = line.quantity.value;
    return q == null ? null : spokenBase(q.thousandths, q.unit);
  }

  static String _priceText(VoicePurchaseLine line) => line.price.value == null
      ? ''
      : formatForInput(line.price.value!.minorPerUnit / 100, maxDecimals: 2);

  void _sync(String id, String value, DraftField<Object?> field) {
    final c = _fields[id];
    if (c == null || field.isManual) return;
    if (c.text != value) c.text = value;
  }

  /// Registra una vez. Sólo la llamada que escribió sale, con el mensaje de
  /// éxito y sin preguntar nada (#120); si la escritura falla, no se sale y
  /// el borrador queda editable con el error a la vista.
  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null || _visibleMismatches(draft.draft).isNotEmpty) return;
    final id = await draft.confirm();
    if (id == null || !mounted) return;
    await _session.discard();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Compra registrada (n.º $id).')));
    leave(id);
  }

  Future<void> _cancel() async {
    _draft?.discard();
    await _session.discard();
    if (!mounted) return;
    leave();
  }

  /// Hay algo que se perdería al salir.
  bool get _hasWork {
    final d = _draft?.draft;
    return _heard.isNotEmpty ||
        (d != null &&
            (d.lines.isNotEmpty ||
                d.supplier.isResolved ||
                d.paidInFull != null));
  }

  /// Atrás con un borrador empezado pregunta antes de descartarlo; durante
  /// la escritura no se puede salir.
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
    markLeaving();
    open();
  }

  /// «Atrás» con un borrador en edición pregunta antes de descartarlo. Con
  /// el borrador ya registrado o descartado no pregunta: la salida ya está
  /// en curso (#120). Durante la escritura no se puede salir.
  Future<void> _onBack() async {
    if (!shouldAskBeforeDiscard(_draft?.phase)) return;
    final discard = await confirmDestructiveAction(
      context,
      title: '¿Descartar el borrador?',
      detail: 'No se registró nada. Lo dictado y lo corregido se pierden.',
      confirmLabel: 'Descartar',
    );
    if (discard && mounted) await _cancel();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final catalog = _catalog;
    return PopScope(
      canPop: canPopDraft(draft?.phase, hasWork: _hasWork),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: _buildPage(context, draft, catalog),
    );
  }

  Widget _buildPage(
    BuildContext context,
    VoiceDraftController<VoicePurchaseDraft, int>? draft,
    VoiceCatalog? catalog,
  ) {
    return PageFrame(
      title: 'Compra por voz',
      subtitle:
          'Dicte la compra, revise el borrador y regístrela con un toque.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VoiceDraftNotice(
            confirmLabel: 'Registrar compra',
            catalogs: 'Los productos, proveedores y personas',
            createInPicker: true,
          ),
          const SizedBox(height: 12),
          VoiceListeningPanel(session: _session),
          const SizedBox(height: 12),
          if (_otherIntent != null)
            VoiceOtherIntentBanner(intent: _otherIntent!, current: 'compra'),
          if (_unplacedPrice != null)
            Padding(
              key: const Key('voz-precio-sin-linea'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _unplacedPrice!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
              ),
            ),
          if (_heard.isNotEmpty)
            VoiceAppliedPanel(
              segments: _heard,
              correctionHint: voiceCorrectionHint(
                hasLines: draft?.draft.lines.isNotEmpty ?? false,
              ),
            ),
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
    VoiceDraftController<VoicePurchaseDraft, int> controller,
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
      key: const Key('voz-borrador-compra'),
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
        const Padding(
          key: Key('voz-fecha'),
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Fecha: hoy, con la hora en que confirme (como el formulario).',
          ),
        ),
        DraftFieldRow(
          label: 'Proveedor',
          labelInChild: true,
          id: 'proveedor',
          field: d.supplier,
          child: VoiceEntityPicker(
            key: const Key('voz-borrador-proveedor'),
            label: 'Proveedor',
            entries: catalog.suppliers,
            field: d.supplier,
            enabled: editable,
            createLabel: 'Crear proveedor',
            onCreate: _createSupplier,
            onPick: (entry) => controller.editManually(
              (c) => c.copyWith(supplier: pickEntry(c.supplier, entry)),
            ),
          ),
        ),
        if (catalog.personalOwner != null)
          Padding(
            key: const Key('voz-titular'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Inventario propio: la compra es de ${catalog.personalOwner!.name}'
              '${_ignoredRecipient == null ? '' : '. Se ignoró «$_ignoredRecipient»: aquí no se elige persona'}.',
            ),
          )
        else
          DraftFieldRow(
            label: 'Recibe la compra',
            labelInChild: true,
            id: 'persona',
            field: d.recipient,
            child: VoiceEntityPicker(
              key: const Key('voz-borrador-persona'),
              label: 'Recibe la compra',
              entries: catalog.people,
              field: d.recipient,
              enabled: editable,
              // Como el formulario: «Agregar persona» sólo en compartido y
              // con la modalidad con que se abrió la pantalla.
              createLabel: modeChanged ? null : 'Agregar persona',
              onCreate: modeChanged ? null : _createPerson,
              onPick: (entry) => controller.editManually(
                (c) => c.copyWith(recipient: pickEntry(c.recipient, entry)),
              ),
            ),
          ),
        for (var i = 0; i < d.lines.length; i++)
          _lineCard(context, controller, catalog, i, d.lines[i], editable),
        // El mismo texto que el formulario: «Añadir otro producto» agrega
        // una línea; «Crear producto», en el selector, da de alta uno nuevo.
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('voz-agregar-linea'),
            onPressed: editable
                ? () => controller.editManually((c) => c.addEmptyLine())
                : null,
            icon: const Icon(Icons.add),
            label: Text(
              d.lines.isEmpty ? 'Añadir producto' : 'Añadir otro producto',
            ),
          ),
        ),
        if (d.lines.any((l) => l.currency.value == CurrencyCode.usd))
          DraftFieldRow(
            label: 'Tipo de cambio (Bs por USD)',
            id: 'tipo-cambio',
            field: d.exchangeRate,
            onConfirmReview: editable
                ? () => controller.editManually(
                    (c) => c.copyWith(
                      exchangeRate: c.exchangeRate.confirmedByUser(),
                    ),
                  )
                : null,
            child: _numberField(
              id: 'fx',
              key: const Key('voz-tipo-cambio'),
              value: _fxText(d),
              field: d.exchangeRate,
              enabled: editable,
              onChanged: (text) {
                final parsed = tryParseDecimal(text);
                controller.editManually(
                  (c) => c.copyWith(
                    exchangeRate: parsed == null || parsed <= 0
                        ? const DraftField.invalid(
                            message: 'Escriba un tipo de cambio mayor a cero.',
                            origin: FieldOrigin.manual,
                          )
                        : DraftField.resolved(
                            (parsed * fxScale).round(),
                            origin: FieldOrigin.manual,
                          ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          d.totalBobMinor == null
              ? 'Total: se calcula cuando todas las líneas estén completas.'
              : 'Total calculado: ${formatBob(d.totalBobMinor!)}',
          key: const Key('voz-total'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        _paymentSection(context, controller, catalog, d, editable),
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
              label: const Text('Registrar compra'),
            ),
          ],
        ),
      ],
    );
  }

  /// «¿Ya pagaste al proveedor?», con las reglas del formulario (X01): sin
  /// respuesta por defecto y sin ella no se registra; paga el titular, sin
  /// elegir pagador; con «Sí, pagué todo» el importe es el total y el medio y
  /// la fecha se ven y se corrigen. Los textos son los del formulario.
  Widget _paymentSection(
    BuildContext context,
    VoiceDraftController<VoicePurchaseDraft, int> controller,
    VoiceCatalog catalog,
    VoicePurchaseDraft d,
    bool editable,
  ) {
    final theme = Theme.of(context);
    final today = localDay(DateTime.now());
    final day = d.paymentDay ?? today;
    return Container(
      key: const Key('voz-pago'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Ya pagaste al proveedor?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const Key('voz-pago-eleccion'),
            emptySelectionAllowed: true,
            showSelectedIcon: true,
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.payments_outlined),
                label: Text('Sí, pagué todo', key: Key('voz-pago-si')),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.schedule_outlined),
                label: Text('No, todavía no', key: Key('voz-pago-no')),
              ),
            ],
            selected: {?d.paidInFull},
            onSelectionChanged: editable
                ? (selection) => controller.editManually(
                    (c) => c.withPaidInFull(
                      selection.isEmpty ? null : selection.single,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          switch (d.paidInFull) {
            true => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  key: const Key('voz-pago-titular'),
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        catalog.holderName == null
                            ? 'No hay un titular vinculado: la compra no '
                                  'puede quedar pagada.'
                            : 'Paga el titular: ${catalog.holderName}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ProviderPaymentFields(
                  method: d.paymentMethod,
                  onMethodChanged: (value) => controller.editManually(
                    (c) => c.withPaymentMethod(value),
                  ),
                  day: day,
                  // La compra por voz es de hoy: su día es hoy.
                  dayHint: day == today ? ' (hoy)' : '',
                  onDayChanged: (value) =>
                      controller.editManually((c) => c.withPaymentDay(value)),
                  enabled: editable,
                ),
              ],
            ),
            false => const Text(
              'La compra queda sin pago. Puedes anotarlo después en '
              'Operaciones, Compras.',
              key: Key('voz-pago-pendiente-despues'),
            ),
            null => Text(
              'Elige una opción para poder confirmar.',
              key: const Key('voz-pago-sin-respuesta'),
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          },
        ],
      ),
    );
  }

  // ------------------------------------------- altas pedidas en un selector

  /// Tras un alta, la lista releída sustituye a la del catálogo y orienta
  /// también el reconocimiento. El borrador no cambia: lo creado lo deja
  /// elegido el selector, como una corrección a mano.
  CatalogEntry? _adopt(
    (List<CatalogEntry>, CatalogEntry)? created,
    VoiceCatalog Function(VoiceCatalog current, List<CatalogEntry> list) put,
  ) {
    final current = _catalog;
    if (created == null || current == null || !mounted) return null;
    final next = put(current, created.$1);
    _session.setVocabularyHints(voiceVocabularyHints(next));
    setState(() => _catalog = next);
    return created.$2;
  }

  Future<CatalogEntry?> _createSupplier() async => _adopt(
    await _gateway.createSupplier(context),
    (c, list) => c.copyWith(suppliers: list),
  );

  Future<CatalogEntry?> _createProduct() async => _adopt(
    await _gateway.createProduct(context),
    (c, list) => c.copyWith(products: list),
  );

  Future<CatalogEntry?> _createPerson() async => _adopt(
    await _gateway.createPurchasePerson(context),
    (c, list) => c.copyWith(people: list),
  );

  Widget _lineCard(
    BuildContext context,
    VoiceDraftController<VoicePurchaseDraft, int> controller,
    VoiceCatalog catalog,
    int index,
    VoicePurchaseLine line,
    bool editable,
  ) {
    final unitLabel = lineUnit(line.product, line.quantity.value?.unit).code;
    final check = unitCheck(
      product: line.product,
      spoken: line.quantity.value?.unit,
    );
    final qText = _quantityText(line);
    final pText = _priceText(line);

    void update(VoicePurchaseLine Function(VoicePurchaseLine) change) =>
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
                  // El mismo texto que la indicación «cómo corregir».
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
              labelInChild: true,
              id: 'producto-${line.key}',
              field: line.product,
              child: VoiceEntityPicker(
                key: Key('voz-producto-${line.key}'),
                label: 'Producto',
                showUnit: true,
                // Como el formulario: un producto ya elegido en otra línea no
                // se ofrece otra vez.
                entries: [
                  for (final p in catalog.products)
                    if (p.id == line.product.value?.id ||
                        !controller.draft.lines.any(
                          (other) =>
                              other.key != line.key &&
                              other.product.isResolved &&
                              other.product.value?.id == p.id,
                        ))
                      p,
                ],
                field: line.product,
                enabled: editable,
                createLabel: 'Crear producto',
                onCreate: _createProduct,
                onPick: (entry) => update(
                  (l) => l.copyWith(product: pickEntry(l.product, entry)),
                ),
              ),
            ),
            DraftFieldRow(
              label: 'Cantidad ($unitLabel)',
              id: 'cantidad-${line.key}',
              field: line.quantity,
              note: check.note,
              problem: check.problem,
              onConfirmReview: editable
                  ? () => update(
                      (l) => l.copyWith(quantity: l.quantity.confirmedByUser()),
                    )
                  : null,
              child: _numberField(
                id: 'q${line.key}',
                key: Key('voz-cantidad-${line.key}'),
                value: qText,
                field: line.quantity,
                enabled: editable,
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
                              SpokenQuantity(
                                base,
                                // La unidad que se ve junto al campo.
                                lineUnit(l.product, l.quantity.value?.unit) ==
                                        CatalogUnit.kilogram
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
            DraftFieldRow(
              label: 'Precio por $unitLabel',
              id: 'precio-${line.key}',
              field: line.price,
              onConfirmReview: editable
                  ? () => update(
                      (l) => l.copyWith(price: l.price.confirmedByUser()),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _numberField(
                    id: 'p${line.key}',
                    key: Key('voz-precio-${line.key}'),
                    value: pText,
                    field: line.price,
                    enabled: editable,
                    onChanged: (text) {
                      final minor = tryParseMinor(text);
                      update(
                        (l) => l.copyWith(
                          price: minor == null || minor <= 0
                              ? const DraftField.invalid(
                                  message: 'Escriba un precio mayor a cero.',
                                  origin: FieldOrigin.manual,
                                )
                              : DraftField.resolved(
                                  SpokenPrice(minor),
                                  origin: FieldOrigin.manual,
                                ),
                        ),
                      );
                    },
                  ),
                  // ¿Por unidad o total? Decir que sí es dar por bueno el
                  // precio que se ve: queda «Confirmado», como «Confirmar este
                  // valor» en un precio por revisar (que ya trae su botón).
                  if (line.price.status == FieldStatus.ambiguous &&
                      !line.price.review &&
                      line.price.value != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: Key('voz-precio-por-unidad-${line.key}'),
                        onPressed: editable
                            ? () => update(
                                (l) => l.copyWith(
                                  price: DraftField.resolved(
                                    SpokenPrice(l.price.value!.minorPerUnit),
                                    origin: FieldOrigin.confirmed,
                                    heard: l.price.heard,
                                  ),
                                ),
                              )
                            : null,
                        child: Text('Sí, es el precio por $unitLabel'),
                      ),
                    ),
                ],
              ),
            ),
            DraftFieldRow(
              label: 'Moneda',
              field: line.currency,
              child: SegmentedButton<CurrencyCode>(
                key: Key('voz-moneda-${line.key}'),
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: CurrencyCode.bob, label: Text('BOB')),
                  ButtonSegment(value: CurrencyCode.usd, label: Text('USD')),
                ],
                selected: {if (line.currency.isResolved) line.currency.value!},
                onSelectionChanged: editable
                    ? (selection) {
                        if (selection.isEmpty) return;
                        update(
                          (l) => l.copyWith(
                            currency: DraftField.resolved(
                              selection.single,
                              origin: FieldOrigin.manual,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
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
    required DraftField<Object?> field,
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
