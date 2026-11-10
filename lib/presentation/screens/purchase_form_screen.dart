import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../data/agro_repository.dart' show AgroRepository;
import '../../domain/models.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart' show expiryPickerRange;
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../operation_mode_controller.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import '../widgets/provider_payment_fields.dart';
import 'late_operations_screen.dart' show offerLateRegistration;
import '../widgets/mode_notice.dart';
import '../voice/voice_draft_widgets.dart' show voicePurchaseTurnHints;
import '../voice/voice_evidence_hook.dart';
import '../voice/voice_form_dictation.dart';
import '../voice/voice_purchase_port.dart';
import '../voice/voice_turn_experiment.dart' show VoiceSingleTranscriberPanel;
import '../../voice/port/voice_engine_diagnostics.dart'
    show voiceDiagnosticsBuild;
import '../../voice/session/voice_session_controller.dart';
import '../../voice/session/voice_session_state.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/numeric_review.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/purchase/purchase_interpreter.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_draft/text/units.dart' show CatalogUnit;
import '../../voice_evidence/voice_evidence.dart' show VoiceEvidenceOutcome;

part 'purchase_form_voice.dart';

/// Nueva compra en dos pasos (ajuste tras el piloto X01, 2026-10-25):
///
/// 1. **Proveedor y productos**: proveedor, fecha (hoy por defecto) y las
///    líneas con su cantidad, precio y, en compartido, su reparto explícito.
/// 2. **Revisión y pago**: lo que se va a guardar, la pregunta
///    «¿Ya pagaste al proveedor?» (sin respuesta por defecto) y, plegados,
///    factura, notas y campaña.
///
/// El pago al proveedor lo registra el titular vigente, en las dos
/// modalidades; no hay pagador que elegir. Con «Sí, pagué todo» el importe es
/// el total de la compra, y el medio y la fecha del pago se muestran y se
/// pueden corregir: el medio empieza en «Sin indicar» (explícito) y la fecha
/// en el día de la compra; nada se supone sin verse. Compra y pago se guardan
/// en una sola transacción (`confirmPurchase(paidInFull:)`).
///
/// Destinatario de cada línea (ajuste tras los pilotos X01 y X02, 2026-10-26):
/// en ambos pilotos las existencias quedaron a nombre de otra persona y en
/// X02 faltó el segundo producto. Ahora nada entra por quedar como única
/// opción: el producto se elige siempre (sin autoselección) y, en compartido,
/// cada línea pide una decisión explícita —«Toda para una persona» o
/// «Repartir entre varias»— sin opción marcada por defecto. Con una sola
/// persona la cantidad asignada se deriva de la cantidad comprada; el reparto
/// por filas sigue existiendo cuando se elige. El orden de las personas, su
/// rol o la última selección nunca deciden una asignación.
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key, this.voice = false});

  /// Abrir con el panel «Completar por voz» visible (atajo «Registrar por
  /// voz»). El micrófono no se abre solo: hay que pulsar «Hablar».
  final bool voice;

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

/// Cómo se asigna una línea en compartido. Nulo hasta que la persona elige:
/// ninguna de las dos opciones viene marcada.
enum _AllocationMode {
  /// Toda la cantidad comprada para una persona, sin reteclearla.
  single,

  /// Varias personas, cada una con su parte; las partes suman la cantidad.
  split,
}

class _AllocationEditor {
  int? personId;
  final quantity = TextEditingController();

  /// Mensaje de formato de la cantidad (`parseNumericInput`), fijado al
  /// validar y borrado al editar el campo.
  String? quantityError;
  void dispose() => quantity.dispose();
}

class _PurchaseLineEditor {
  _PurchaseLineEditor(this.id);

  /// Identificador estable de la línea (no su posición): lo usa el dictado
  /// para saber qué línea completó o añadió.
  final int id;
  int? productId;
  CurrencyCode currency = CurrencyCode.bob;
  final quantity = TextEditingController();
  final price = TextEditingController();
  final fx = TextEditingController();

  /// Vencimiento (día civil) y número de lote, opcionales (F04-AV, RF-42).
  /// Sin elegir: se guarda «sin fecha registrada», nunca una fecha supuesta.
  String? expiryDay;
  final lotNumber = TextEditingController();

  /// Número de lote sin espacios a los lados; vacío es «sin dato».
  String? get lotNumberValue {
    final text = lotNumber.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Mensajes de formato por campo, fijados al validar (B-11).
  String? quantityError;
  String? priceError;
  String? fxError;

  /// Decisión explícita de destinatario (compartido). Nula hasta elegir.
  _AllocationMode? allocationMode;

  /// Destinatario único con «Toda para una persona». Sin valor por defecto.
  int? singlePersonId;

  /// Filas de «Repartir entre varias». Vacía hasta que se elige repartir.
  final allocations = <_AllocationEditor>[];

  void clearErrors() {
    quantityError = null;
    priceError = null;
    fxError = null;
    for (final allocation in allocations) {
      allocation.quantityError = null;
    }
  }

  int get quantityBase {
    final value = tryParseBase(quantity.text) ?? 0;
    return value > 0 ? value : 0;
  }

  int get priceMinor {
    final value = tryParseMinor(price.text) ?? 0;
    return value > 0 ? value : 0;
  }

  int? get exchangeRateScaled => currency == CurrencyCode.usd
      ? (((tryParseDecimal(fx.text) ?? 0) > 0
                    ? (tryParseDecimal(fx.text) ?? 0)
                    : 0) *
                fxScale)
            .round()
      : null;
  int get unitBob => convertedUnitPriceBobMinor(priceMinor, exchangeRateScaled);
  int get subtotalBob => subtotalMinor(
    quantityBase: quantityBase,
    unitPriceMinor: priceMinor,
    fxScaled: exchangeRateScaled,
  );
  int get assignedBase => allocations.fold(
    0,
    (sum, allocation) => sum + (tryParseBase(allocation.quantity.text) ?? 0),
  );

  void dispose() {
    quantity.dispose();
    price.dispose();
    fx.dispose();
    lotNumber.dispose();
    for (final allocation in allocations) {
      allocation.dispose();
    }
  }
}

enum _PurchaseStep { items, review }

/// Catálogos del formulario y el contexto (modalidad y titular) con que se
/// cargaron.
typedef _PurchaseCatalogs = ({
  List<Map<String, Object?>> suppliers,
  List<Map<String, Object?>> campaigns,
  List<Map<String, Object?>> products,
  List<Map<String, Object?>> people,
});

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen>
    with WidgetsBindingObserver, VoiceEvidenceRecording<PurchaseFormScreen> {
  late Future<_PurchaseCatalogs> catalogs;
  final invoiceNumber = TextEditingController();
  final notes = TextEditingController();
  int _nextLineId = 2;
  final lines = <_PurchaseLineEditor>[_PurchaseLineEditor(1)];
  _PurchaseLineEditor _newLine() => _PurchaseLineEditor(_nextLineId++);

  /// «Completar por voz»: el dictado de esta compra (se crea al abrir el
  /// panel) y el puente con el formulario.
  VoiceFormDictation<VoicePurchaseDraft>? voice;
  late final _voiceTarget = _PurchaseVoice(this);
  bool showVoice = false;

  /// Lo que propuso el último dictado y si la compra se guardó (evidencia,
  /// sólo con consentimiento).
  VoicePurchaseDraft? _lastVoiceDraft;
  bool _voiceSaved = false;
  bool _voiceFailed = false;
  bool _observingSession = false;
  int? supplierId;
  int? campaignId;
  _PurchaseStep step = _PurchaseStep.items;

  /// Productos del catálogo cargado, para nombrar cada línea en los mensajes
  /// de validación («… de Glifosato» y no «… del producto 2»).
  List<Map<String, Object?>> products = const [];

  /// Día de la compra (#121): hoy por defecto, editable hacia atrás.
  String effectiveDay = localDay(DateTime.now());

  /// Respuesta a «¿Ya pagaste al proveedor?». Nula hasta que la persona
  /// elige: no se registra ningún pago por defecto.
  bool? paidInFull;

  /// Medio del pago si «Sí, pagué todo»: empieza en «Sin indicar», que se
  /// guarda tal cual (`UNSPECIFIED`); no se supone transferencia ni efectivo.
  PaymentMethod paymentMethod = PaymentMethod.unspecified;

  /// Día del pago elegido a mano; nulo = el día de la compra, que la pantalla
  /// muestra como tal («el día de la compra»).
  String? paymentDay;

  String get effectivePaymentDay => paymentDay ?? effectiveDay;

  /// Modalidad con la que se cargaron las personas (#26).
  OperationMode? loadedMode;

  /// Titular vigente, del vínculo real de la instalación. Paga al proveedor
  /// en las dos modalidades; en propio además recibe todo lo comprado.
  int? ownerPersonId;

  /// En inventario propio, el titular recibe todo lo comprado sin que se elija
  /// persona (#26). Nulo en compartido.
  int? personalOwnerId;
  XFile? invoiceImage;
  bool saving = false;
  bool dirty = false;

  void _markDirty() {
    setState(() => dirty = true);
    voice?.reconcile(_voiceTarget.snapshot());
  }

  /// Muestra el panel de voz (lo crea la primera vez). No abre el micrófono.
  void _openVoice() {
    voice ??= VoiceFormDictation<VoicePurchaseDraft>(
      session: VoiceSessionController(
        port: ref.read(purchaseSpeechPortFactoryProvider)(),
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
      voice!.session.setVocabularyHints(voicePurchaseTurnHints(catalog));
    }
    setState(() => showVoice = true);
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  void _voiceApplied(VoicePurchaseDraft shadow, String text) {
    _lastVoiceDraft = shadow;
    noteVoiceApplied(shadow, text);
  }

  /// `setState` para el puente de voz (`purchase_form_voice.dart`).
  void _voiceSetState(VoidCallback fn) => setState(fn);

  /// Día de la compra (#121): hoy por defecto; se puede elegir un día pasado.
  /// El selector no ofrece el futuro, y el repositorio lo rechaza también.
  /// Cancelar el selector no cambia nada del borrador.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startOfLocalDay(effectiveDay),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      effectiveDay = localDay(picked);
      dirty = true;
    });
  }

  Future<void> _close() async {
    if (dirty) {
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
              // Criterio unico de accion destructiva, el mismo que usa
              // `confirmDestructiveAction` en las reversiones (UIBUG-033).
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
    setState(() => dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initVoiceEvidence();
    catalogs = _loadCatalogs();
    if (widget.voice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openVoice();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // En segundo plano se libera el micrófono, como en el dictado de siempre.
    if (state != AppLifecycleState.resumed) voice?.session.handleAppPaused();
  }

  Future<_PurchaseCatalogs> _loadCatalogs() async {
    final repo = ref.read(repositoryProvider);
    // Asignación según rol privado, titular y modalidad: en modo propio sólo
    // el titular. La modalidad y el titular llegan en la misma consulta.
    // Todas las lecturas se lanzan juntas: una sola ida y vuelta a la base.
    final allocation = repo.peopleAndContextFor(
      PersonPurpose.purchaseAllocation,
    );
    final result = await Future.wait([
      repo.suppliers(),
      repo.campaigns(),
      repo.products(),
      allocation.then((value) => value.people),
    ]);
    final operating = (await allocation).context;
    final active = result[1].where((row) => row['status'] == 'ACTIVE');
    campaignId = active.isEmpty ? null : active.first['id'] as int;
    loadedMode = operating.mode;
    ownerPersonId = operating.ownerPersonId;
    personalOwnerId = operating.mode == OperationMode.personal
        ? operating.ownerPersonId
        : null;
    products = result[2];
    final loaded = (
      suppliers: result[0],
      campaigns: result[1],
      products: result[2],
      people: result[3],
    );
    _voiceTarget.updateCatalog(loaded);
    return loaded;
  }

  /// Tras crear un proveedor, un producto o una persona desde su selector:
  /// se vuelven a leer proveedores y productos y, con [people], las personas
  /// del reparto. Todo lo demás del borrador —fecha, líneas, cantidades,
  /// precios, reparto, factura, notas, campaña, modalidad cargada— se
  /// conserva.
  Future<_PurchaseCatalogs> _reloadCatalogs({bool people = false}) async {
    final repo = ref.read(repositoryProvider);
    final current = await catalogs;
    final fresh = await Future.wait([
      repo.suppliers(),
      repo.products(),
      if (people) repo.peopleFor(PersonPurpose.purchaseAllocation),
    ]);
    final next = (
      suppliers: fresh[0],
      campaigns: current.campaigns,
      products: fresh[1],
      people: people ? fresh[2] : current.people,
    );
    _voiceTarget.updateCatalog(next);
    if (mounted) {
      setState(() {
        products = next.products;
        // `SynchronousFuture`: el `FutureBuilder` toma la lista nueva en la
        // misma reconstrucción. Con `Future.value` pasaba un fotograma con la
        // lista vieja, el selector no encontraba lo elegido y autoelegía la
        // única opción anterior encima de lo recién creado.
        catalogs = SynchronousFuture(next);
      });
    }
    return next;
  }

  /// «Crear proveedor» del selector: el alta de Catálogos sobre el borrador.
  /// Si se cancela o falla, el borrador queda igual.
  Future<Map<String, Object?>?> _createSupplier() async {
    final id = await createSupplierFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id == null) return null;
    final next = await _reloadCatalogs();
    return next.suppliers.where((row) => row['id'] == id).firstOrNull;
  }

  /// «Crear producto» del selector de una línea. Igual que [_createSupplier].
  Future<Map<String, Object?>?> _createProduct() async {
    final id = await createProductFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id == null) return null;
    final next = await _reloadCatalogs();
    return next.products.where((row) => row['id'] == id).firstOrNull;
  }

  /// «Agregar persona» en el selector de persona del reparto («¿Para quién
  /// es?»): el alta de Catálogos, con su regla (sólo en compartido; la vuelve
  /// a comprobar `createPersonFromDialog`). Lo creado queda elegido en el
  /// selector desde el que se pidió; el resto del reparto no cambia.
  Future<Map<String, Object?>?> _createPerson() async {
    final id = await createPersonFromDialog(
      context,
      ref.read(repositoryProvider),
      purpose: PersonPurpose.purchaseAllocation,
    );
    if (id == null) return null;
    final next = await _reloadCatalogs(people: true);
    return next.people.where((row) => row['id'] == id).firstOrNull;
  }

  /// Si el formulario ofrece «Agregar persona»: sólo en inventario
  /// compartido, como en Catálogos (#26). En propio no hay reparto.
  bool get _canCreatePeople =>
      loadedMode != null &&
      loadedMode != OperationMode.personal &&
      !modeChangedSince(loadedMode, ref.read(operationModeProvider));

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
    // Salir libera el micrófono: nada de un dictado en curso se aplica.
    voice?.removeListener(_onVoice);
    voice?.release();
    voice?.dispose();
    invoiceNumber.dispose();
    notes.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  int get totalBob => lines.fold(0, (sum, line) => sum + line.subtotalBob);

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (!mounted || picked == null) return;
      setState(() {
        invoiceImage = picked;
        dirty = true;
      });
    } catch (error) {
      if (mounted)
        showError(
          context,
          'No se pudo adjuntar la factura. Revise los permisos.',
        );
    }
  }

  String _productName(int? id) =>
      products
          .where((row) => row['id'] == id)
          .firstOrNull?['name']
          ?.toString() ??
      '';

  /// Comprueba el paso 1 y explica qué falta y en qué producto. Devuelve
  /// `true` si se puede pasar a la revisión. Un número mal escrito deja su
  /// mensaje de formato en el propio campo (B-11) además del aviso.
  bool _validateItems() {
    for (final line in lines) {
      line.clearErrors();
    }
    final problem = _firstProblem();
    // Repinta: muestra los errores de campo recién fijados o los borra.
    setState(() {});
    if (problem != null) {
      showError(context, problem);
      return false;
    }
    return true;
  }

  /// Primer problema del paso 1, en el orden en que se lee el formulario.
  /// Fija `*Error` en el campo cuyo texto no se puede interpretar.
  String? _firstProblem() {
    if (supplierId == null) return 'Elige el proveedor.';
    if (lines.isEmpty) return 'Agrega al menos un producto.';
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.productId == null) {
        return 'Elija el producto de la línea ${index + 1}.';
      }
      final name = _productName(line.productId);

      final quantity = parseNumericInput(line.quantity.text);
      switch (quantity.status) {
        case NumericInputStatus.empty:
          return 'Escriba la cantidad comprada de $name.';
        case NumericInputStatus.ambiguous:
        case NumericInputStatus.malformed:
          line.quantityError = quantity.message;
          return 'Revise la cantidad comprada de $name.';
        case NumericInputStatus.valid:
          if (line.quantityBase <= 0) {
            return 'La cantidad comprada de $name debe ser mayor que cero.';
          }
      }

      final price = parseNumericInput(line.price.text);
      switch (price.status) {
        case NumericInputStatus.empty:
          return 'Escriba el precio de $name.';
        case NumericInputStatus.ambiguous:
        case NumericInputStatus.malformed:
          line.priceError = price.message;
          return 'Revise el precio de $name.';
        case NumericInputStatus.valid:
          if (line.priceMinor <= 0) {
            return 'El precio de $name debe ser mayor que cero.';
          }
      }

      if (line.currency == CurrencyCode.usd) {
        final fx = parseNumericInput(line.fx.text);
        switch (fx.status) {
          case NumericInputStatus.empty:
            return 'Escriba el tipo de cambio de $name.';
          case NumericInputStatus.ambiguous:
          case NumericInputStatus.malformed:
            line.fxError = fx.message;
            return 'Revise el tipo de cambio de $name.';
          case NumericInputStatus.valid:
            if ((line.exchangeRateScaled ?? 0) <= 0) {
              return 'El tipo de cambio de $name debe ser mayor que cero.';
            }
        }
      }

      // Número de lote: el exceso se señala, nunca se recorta.
      final lotError = AgroRepository.lotNumberLengthError(line.lotNumber.text);
      if (lotError != null) return '$name: $lotError';

      // En propio todo es del titular: no hay destinatario que comprobar.
      if (personalOwnerId != null) continue;
      switch (line.allocationMode) {
        case null:
          return 'Indique para quién es $name: toda para una persona o '
              'repartida entre varias.';
        case _AllocationMode.single:
          if (line.singlePersonId == null) {
            return 'Elija para quién es $name.';
          }
        case _AllocationMode.split:
          for (final allocation in line.allocations) {
            if (allocation.personId == null) {
              return 'Elija la persona de cada parte de $name.';
            }
            final part = parseNumericInput(allocation.quantity.text);
            switch (part.status) {
              case NumericInputStatus.empty:
                return 'Escriba la cantidad de cada parte de $name.';
              case NumericInputStatus.ambiguous:
              case NumericInputStatus.malformed:
                allocation.quantityError = part.message;
                return 'Revise las cantidades repartidas de $name.';
              case NumericInputStatus.valid:
                if ((part.value ?? 0) <= 0) {
                  return 'Cada parte de $name debe ser mayor que cero.';
                }
            }
          }
          // Repartir es entre personas distintas: la misma dos veces sería
          // una sola parte escrita en dos filas.
          final people = line.allocations.map((a) => a.personId).toList();
          if (people.toSet().length != people.length) {
            return 'La misma persona aparece dos veces en el reparto de '
                '$name.';
          }
          if (line.assignedBase != line.quantityBase) {
            return line.assignedBase > line.quantityBase
                ? 'Lo repartido supera la cantidad comprada de $name.'
                : 'Falta repartir parte de la cantidad de $name.';
          }
      }
    }
    return null;
  }

  /// Asignaciones explícitas de una línea ya validada, tal como las recibe
  /// `confirmPurchase` (su contrato no cambia). En propio, todo al titular;
  /// con una sola persona, la cantidad completa de la línea; repartida, cada
  /// fila con su parte.
  List<AllocationDraft> _allocationsOf(_PurchaseLineEditor line) {
    final owner = personalOwnerId;
    if (owner != null) {
      return [
        AllocationDraft(personId: owner, quantityBase: line.quantityBase),
      ];
    }
    return switch (line.allocationMode) {
      _AllocationMode.single => [
        AllocationDraft(
          personId: line.singlePersonId!,
          quantityBase: line.quantityBase,
        ),
      ],
      _AllocationMode.split => [
        for (final allocation in line.allocations)
          AllocationDraft(
            personId: allocation.personId!,
            quantityBase: tryParseBase(allocation.quantity.text) ?? 0,
          ),
      ],
      null => const [],
    };
  }

  void _goToReview() {
    if (!_validateItems()) return;
    setState(() => step = _PurchaseStep.review);
  }

  void _backToItems() => setState(() => step = _PurchaseStep.items);

  Future<void> _confirm(_PurchaseCatalogs data) async {
    if (saving) return;
    if (!_validateItems()) {
      setState(() => step = _PurchaseStep.items);
      return;
    }
    if (campaignId == null) {
      showError(
        context,
        'No hay una campaña activa. Actívala en Más, Administrar datos.',
      );
      return;
    }
    final paid = paidInFull;
    if (paid == null) {
      showError(context, 'Indica si ya pagaste al proveedor.');
      return;
    }
    if (paid && ownerPersonId == null) {
      showError(
        context,
        'No hay un titular vinculado: la compra no puede quedar pagada.',
      );
      return;
    }

    setState(() {
      saving = true;
    });
    final repo = ref.read(repositoryProvider);
    PurchaseDraft? draft;
    var done = false;
    try {
      final imagePath = invoiceImage == null
          ? null
          : await repo.storeInvoiceImage(invoiceImage!.path);
      draft = PurchaseDraft(
        supplierId: supplierId!,
        campaignId: campaignId!,
        // Hoy: el instante real. Otro día: su medianoche local (#121).
        purchaseDate: effectiveInstantForDay(effectiveDay, DateTime.now()),
        invoiceNumber: invoiceNumber.text.trim(),
        invoiceImagePath: imagePath,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        exchangeRateSource:
            lines.any((line) => line.currency == CurrencyCode.usd)
            ? ExchangeRateSource.agreedWithSupplier
            : null,
        items: [
          for (final line in lines)
            PurchaseItemDraft(
              productId: line.productId!,
              quantityBase: line.quantityBase,
              currency: line.currency,
              originalUnitPriceMinor: line.priceMinor,
              exchangeRateScaled: line.exchangeRateScaled,
              allocations: _allocationsOf(line),
              expiryDay: line.expiryDay,
              lotNumber: line.lotNumberValue,
            ),
        ],
      );
      // Compra y pago en una sola transacción: un fallo no deja una compra
      // guardada sin avisar, y reintentar no la duplica. Del pago van el
      // medio y el día que la pantalla mostró (hoy: el instante real).
      await repo.confirmPurchase(
        draft,
        paidInFull: paid
            ? ProviderPaymentDetails(
                method: paymentMethod,
                date: effectiveInstantForDay(
                  effectivePaymentDay,
                  DateTime.now(),
                ),
              )
            : null,
      );
      if (!mounted) return;
      // `saving` se queda en true hasta cerrar: si bajara aquí, el botón
      // volvería a habilitarse durante el fotograma previo al `pop` y un
      // segundo toque podría escribir otra compra (revisión cruzada X01).
      done = true;
      _voiceSaved = true;
      setState(() => dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (error) {
      if (!mounted) return;
      // RF-03: una fecha de una campaña cerrada se ofrece para revisión.
      final late = draft;
      final captured =
          late != null &&
          await offerLateRegistration(
            context,
            error: error,
            what: 'esta compra',
            // La revisión no guarda el pago, y confirmarla tampoco lo crea:
            // se dice en activa y con el camino para anotarlo después.
            extraNote: paid
                ? 'El pago al proveedor no se guarda con la revisión. Si el '
                      'titular la confirma, anótalo después en Operaciones, '
                      'Compras, «Registrar pago».'
                : null,
            capture: (reason) => repo.captureLatePurchase(late, reason: reason),
          );
      if (!mounted) return;
      if (captured) {
        done = true;
        setState(() => dirty = false);
        // Sólo quedó pendiente de revisión: false, para que la lista no
        // anuncie una operación confirmada (DEVICE del 2026-10-24).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      } else {
        _voiceFailed = true;
        showError(context, error);
      }
    } finally {
      if (mounted && !done) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving && step == _PurchaseStep.items,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || saving) return;
      // Desde la revisión, Atrás vuelve al paso 1 sin perder nada.
      if (step == _PurchaseStep.review) {
        _backToItems();
      } else {
        _close();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva compra'),
        actions: [
          // F09 (formulario único): la voz completa ESTE formulario; no
          // abre otra pantalla ni descarta nada.
          IconButton(
            key: const Key('form-dictar'),
            tooltip: showVoice
                ? 'Ocultar el panel de voz'
                : 'Completar por voz',
            icon: Icon(showVoice ? Icons.mic : Icons.mic_none_outlined),
            onPressed: saving || step != _PurchaseStep.items
                ? null
                : showVoice
                ? (voice?.busy ?? false)
                      ? null
                      : () => setState(() => showVoice = false)
                : _openVoice,
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: saving
              ? null
              : step == _PurchaseStep.review
              ? _backToItems
              : _close,
        ),
      ),
      // **#97 — la acción fuera de la barra superior.** Abajo y fija, como en
      // Aplicación y Planificación, el título cabe entero y la acción sigue
      // siempre visible y con su texto.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_PurchaseCatalogs>(
            future: catalogs,
            builder: (context, snapshot) {
              final voiceBlock = voice?.blocksSave ?? false;
              final blocked =
                  saving ||
                  voiceBlock ||
                  !snapshot.hasData ||
                  modeChangedSince(
                    loadedMode,
                    ref.watch(operationModeProvider),
                  );
              if (step == _PurchaseStep.items) {
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
                      key: const Key('purchase-continue'),
                      onPressed: blocked ? null : _goToReview,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Continuar'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('purchase-back'),
                    onPressed: saving ? null : _backToItems,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Atrás'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('purchase-confirm'),
                      onPressed: blocked
                          ? null
                          : () => _confirm(snapshot.data!),
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(saving ? 'Guardando…' : 'Confirmar compra'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: FutureBuilder<_PurchaseCatalogs>(
        future: catalogs,
        builder: (context, snapshot) {
          // Sin esta rama, un fallo al cargar los catálogos dejaba el
          // formulario girando indefinidamente, sin explicación ni salida.
          if (snapshot.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final modeChanged = modeChangedSince(
            loadedMode,
            ref.watch(operationModeProvider),
          );
          return SafeArea(
            child: ListView(
              // Este formulario está fuera del `ShellRoute` y no hereda su
              // `SafeArea` (UIBUG-064); la barra inferior ya reserva su alto.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (modeChanged) ...[
                  const ModeChangedNotice(),
                  const SizedBox(height: 12),
                ],
                _StepHeader(
                  key: const Key('purchase-step'),
                  step: step == _PurchaseStep.items ? 1 : 2,
                  total: 2,
                  title: step == _PurchaseStep.items
                      ? 'Proveedor y productos'
                      : 'Revisión y pago',
                ),
                const SizedBox(height: 12),
                if (step == _PurchaseStep.items)
                  ..._itemsStep(context, data)
                else
                  ..._reviewStep(context, data),
              ],
            ),
          );
        },
      ),
    ),
  );

  String? _ownerName(_PurchaseCatalogs data) => data.people
      .where((row) => row['id'] == ownerPersonId)
      .firstOrNull?['name']
      ?.toString();

  List<Widget> _itemsStep(BuildContext context, _PurchaseCatalogs data) {
    final ownerName = _ownerName(data);
    final supplierName = data.suppliers
        .where((row) => row['id'] == supplierId)
        .firstOrNull?['name']
        ?.toString();
    return [
      if (showVoice && voice != null) ...[
        VoiceFormPanel(
          dictation: voice!,
          engineHint:
              'Diga la compra completa —producto, cantidad, precio y '
              'proveedor— y pulse «Terminar». Lo reconocido aparece en los '
              'campos; nada se guarda solo.',
          onClose: () => setState(() => showVoice = false),
          // Sólo en la compilación de diagnóstico: modelo del próximo turno
          // y métricas sin texto.
          diagnostics: voiceDiagnosticsBuild
              ? VoiceSingleTranscriberPanel(session: voice!.session)
              : null,
        ),
        const SizedBox(height: 12),
      ] else ...[
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('compra-completar-voz'),
            onPressed: saving ? null : _openVoice,
            icon: const Icon(Icons.mic_none_outlined),
            label: const Text('Completar por voz'),
          ),
        ),
        const SizedBox(height: 8),
      ],
      _dropdown(
        'Proveedor',
        data.suppliers,
        supplierId,
        onCreate: _createSupplier,
        (value) {
          // El único proveedor se deja elegido como valor de referencia; eso no
          // es un cambio de la persona, así que Atrás no debe preguntar
          // «¿Descartar cambios?» (B-07).
          final autoSelected =
              supplierId == null &&
              data.suppliers.length == 1 &&
              value == data.suppliers.single['id'];
          setState(() {
            supplierId = value;
            if (!autoSelected) dirty = true;
          });
          voice?.reconcile(_voiceTarget.snapshot());
        },
      ),
      VoiceSlotMark(
        dictation: voice,
        slot: const SlotRef.header('supplier'),
        current: supplierId,
        currentDisplay: supplierName,
      ),
      const SizedBox(height: 10),
      ListTile(
        key: const Key('purchase-date'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined),
        title: const Text('Fecha de la compra'),
        subtitle: Text(
          '${formatDate(effectiveDay)}'
          '${effectiveDay == localDay(DateTime.now()) ? ' (hoy)' : ''}',
        ),
        trailing: const Text('Cambiar'),
        onTap: saving ? null : _pickDate,
      ),
      const SizedBox(height: 12),
      // Título y acción en un `Wrap`, no en una fila: con la fuente al 130 %
      // en 360 dp el título se partía en «Producto / s (1)» (#129).
      // «Añadir otro producto» agrega una **línea** a la compra; «Crear
      // producto», en el selector de cada línea, da de alta un producto del
      // catálogo. Antes las dos acciones se llamaban casi igual
      // («Agregar producto»/«Crear producto») (2026-11-05).
      SectionHeading(
        title: 'Productos (${lines.length})',
        action: FilledButton.tonalIcon(
          key: const Key('purchase-add-line'),
          onPressed: () {
            setState(() {
              lines.add(_newLine());
              dirty = true;
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Añadir otro producto'),
        ),
      ),
      const SizedBox(height: 8),
      for (var index = 0; index < lines.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LineCard(
            key: ObjectKey(lines[index]),
            index: index,
            line: lines[index],
            products: data.products,
            people: data.people,
            ownerPersonId: ownerPersonId,
            personalOwnerName: personalOwnerId == null
                ? null
                : ownerName ?? 'Titular',
            usedProductIds: {
              for (final other in lines)
                if (!identical(other, lines[index]) && other.productId != null)
                  other.productId!,
            },
            onChanged: _markDirty,
            onCreateProduct: _createProduct,
            onCreatePerson: _canCreatePeople ? _createPerson : null,
            voice: voice,
            shared: personalOwnerId == null,
            onRemove: lines.length == 1
                ? null
                : () {
                    final removed = lines.removeAt(index);
                    voice?.lineRemoved(removed.id);
                    removed.dispose();
                    setState(() => dirty = true);
                  },
          ),
        ),
    ];
  }

  List<Widget> _reviewStep(BuildContext context, _PurchaseCatalogs data) {
    final theme = Theme.of(context);
    final ownerName = _ownerName(data) ?? 'Titular';
    final supplierName =
        data.suppliers
            .where((row) => row['id'] == supplierId)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String personName(int? id) =>
        data.people
            .where((row) => row['id'] == id)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String productName(int? id) =>
        data.products
            .where((row) => row['id'] == id)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String productUnit(int? id) =>
        data.products
            .where((row) => row['id'] == id)
            .firstOrNull?['unit']
            ?.toString() ??
        '';
    return [
      _Section(
        key: const Key('purchase-review'),
        title: 'Lo que se va a guardar',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reviewRow(Icons.storefront_outlined, 'Proveedor', supplierName),
            _reviewRow(
              Icons.event_outlined,
              'Fecha',
              '${formatDate(effectiveDay)}'
                  '${effectiveDay == localDay(DateTime.now()) ? ' (hoy)' : ''}',
            ),
            const Divider(height: 20),
            // Por producto: nombre, cantidad, subtotal y destinatario, en una
            // sola línea legible antes de confirmar (pilotos X01/X02).
            for (var index = 0; index < lines.length; index++) ...[
              Text(
                '${productName(lines[index].productId)} · '
                '${formatQuantity(lines[index].quantityBase, productUnit(lines[index].productId))} · '
                '${formatBob(lines[index].subtotalBob)} · '
                '${_recipientSummary(lines[index], personName, productUnit(lines[index].productId), ownerName)}',
                key: Key('purchase-review-line-$index'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (lines[index].expiryDay != null ||
                  lines[index].lotNumberValue != null)
                Text(
                  _lotDataSummary(lines[index]),
                  key: Key('purchase-review-lot-$index'),
                ),
              const SizedBox(height: 8),
            ],
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL COMPRA',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatBob(totalBob),
                  key: const Key('purchase-total'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // El total se dice una sola vez, arriba («TOTAL COMPRA»); aquí sólo la
      // decisión de pago (2026-11-05). «Sí, pagué todo» paga ese total.
      _Section(
        key: const Key('purchase-paid-question'),
        title: '¿Ya pagaste al proveedor?',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sin respuesta por defecto: la persona elige. `SegmentedButton`
            // admite la selección vacía y muestra la elegida.
            SegmentedButton<bool>(
              key: const Key('purchase-paid-choice'),
              emptySelectionAllowed: true,
              showSelectedIcon: true,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Sí, pagué todo', key: Key('purchase-paid-yes')),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.schedule_outlined),
                  label: Text('No, todavía no', key: Key('purchase-paid-no')),
                ),
              ],
              selected: {?paidInFull},
              onSelectionChanged: saving
                  ? null
                  : (selection) => setState(() {
                      paidInFull = selection.isEmpty ? null : selection.single;
                      dirty = true;
                    }),
            ),
            const SizedBox(height: 10),
            switch (paidInFull) {
              // El pagador no se edita: es el titular del vínculo real. El
              // medio y la fecha sí se ven y se corrigen: no se guardan
              // valores que la persona no haya visto.
              true => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    key: const Key('purchase-payer-owner'),
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      // Antes de guardar no hay ningún pago registrado: se
                      // dice quién paga, como en el pago posterior (E-16).
                      Expanded(child: Text('Paga el titular: $ownerName')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ProviderPaymentFields(
                    method: paymentMethod,
                    onMethodChanged: (value) => setState(() {
                      paymentMethod = value;
                      dirty = true;
                    }),
                    day: effectivePaymentDay,
                    dayHint: effectivePaymentDay == localDay(DateTime.now())
                        ? ' (hoy)'
                        : paymentDay == null
                        ? ' (el día de la compra)'
                        : '',
                    onDayChanged: (value) => setState(() {
                      paymentDay = value;
                      dirty = true;
                    }),
                    enabled: !saving,
                  ),
                ],
              ),
              false => const Text(
                'La compra queda sin pago. Puedes anotarlo después en '
                'Operaciones, Compras.',
                key: Key('purchase-no-payment'),
              ),
              null => Text(
                'Elige una opción para poder confirmar.',
                key: const Key('purchase-paid-pending'),
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            },
          ],
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ExpansionTile(
          key: const Key('purchase-details'),
          title: const Text('Factura, notas y campaña (opcional)'),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            TextField(
              controller: invoiceNumber,
              onChanged: (_) => _markDirty(),
              decoration: const InputDecoration(labelText: 'N.º de factura'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cámara'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                ),
                if (invoiceImage != null) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(invoiceImage!.path),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              onChanged: (_) => _markDirty(),
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
            const SizedBox(height: 10),
            _dropdown(
              'Campaña',
              data.campaigns.where((row) => row['status'] == 'ACTIVE').toList(),
              campaignId,
              (value) {
                setState(() {
                  campaignId = value;
                  dirty = true;
                });
              },
            ),
          ],
        ),
      ),
    ];
  }

  /// «Para: X» o «Repartida: A 1 L · B 1 L» para la revisión. En propio,
  /// «Para: titular».
  String _recipientSummary(
    _PurchaseLineEditor line,
    String Function(int?) personName,
    String unit,
    String ownerName,
  ) {
    if (personalOwnerId != null) return 'Para: $ownerName';
    return switch (line.allocationMode) {
      _AllocationMode.single => 'Para: ${personName(line.singlePersonId)}',
      _AllocationMode.split =>
        'Repartida: ${line.allocations.map((a) => '${personName(a.personId)} ${formatQuantity(tryParseBase(a.quantity.text) ?? 0, unit)}').join(' · ')}',
      null => 'Pendiente de destinatario',
    };
  }

  Widget _reviewRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text('$label: '),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _dropdown(
    String label,
    List<Map<String, Object?>> rows,
    int? value,
    ValueChanged<int?> changed, {
    Future<Map<String, Object?>?> Function()? onCreate,
  }) {
    final selected = rows.where((row) => row['id'] == value).firstOrNull;
    return AdaptiveEntityPicker<Map<String, Object?>>(
      label: label,
      items: rows,
      value: selected,
      labelOf: (row) => row['name']! as String,
      onChanged: (row) => changed(row?['id'] as int?),
      createLabel: onCreate == null ? null : 'Crear ${label.toLowerCase()}',
      onCreate: onCreate,
    );
  }
}

/// «Paso n de m · título», en una línea que crece con la fuente.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
  });
  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'Paso $step de $total · $title',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Dos campos lado a lado si caben; apilados si no (UIBUG-040).
///
/// El umbral es el ancho por debajo del cual media fila deja de bastar para el
/// contenido real del formulario: un nombre de proveedor o de campaña del
/// dataset, o una etiqueta como "Cantidad comprada". Comprimir dos campos hasta
/// que su texto se recorta es peor que apilarlos.
class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  static const double minWidth = 420;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < minWidth
        ? Column(children: [first, const SizedBox(height: 10), second])
        : Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 10),
              Expanded(child: second),
            ],
          ),
  );
}

/// Vencimiento y número de lote de una línea, en palabras.
String _lotDataSummary(_PurchaseLineEditor line) {
  final expiry = line.expiryDay == null
      ? 'Sin fecha de vencimiento'
      : 'Vence el ${displayDay(line.expiryDay!)}';
  final lot = line.lotNumberValue == null
      ? 'sin número de lote'
      : 'lote ${line.lotNumberValue}';
  return '$expiry · $lot';
}

/// Vencimiento y número de lote de la línea (F04-AV, RF-42). Opcionales y
/// plegados: una compra sin estos datos se registra igual que antes.
/// Contador del número de lote en caracteres Unicode, como los cuenta el
/// repositorio.
String lotNumberCounter(String text) =>
    '${text.trim().runes.length}/${AgroRepository.maxLotNumberLength}';

class _LotDataSection extends StatelessWidget {
  const _LotDataSection({
    required this.index,
    required this.line,
    required this.onChanged,
  });
  final int index;
  final _PurchaseLineEditor line;
  final VoidCallback onChanged;

  Future<void> _pickExpiry(BuildContext context) async {
    final now = DateTime.now();
    final current = line.expiryDay == null
        ? null
        : startOfLocalDay(line.expiryDay!);
    final range = expiryPickerRange(current, now);
    final picked = await showDatePicker(
      context: context,
      initialDate: range.initial,
      firstDate: range.first,
      lastDate: range.last,
      helpText: 'Fecha de vencimiento',
    );
    if (picked == null) return;
    line.expiryDay = localDay(picked);
    onChanged();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: Key('purchase-lot-data-$index'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    title: const Text('Vencimiento y número de lote (opcional)'),
    subtitle: Text(
      line.expiryDay == null && line.lotNumberValue == null
          ? 'Sin datos: el lote quedará «sin fecha registrada».'
          : _lotDataSummary(line),
    ),
    children: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: Key('purchase-expiry-$index'),
              onPressed: () => _pickExpiry(context),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                line.expiryDay == null
                    ? 'Elegir fecha de vencimiento'
                    : 'Vence el ${displayDay(line.expiryDay!)}',
              ),
            ),
          ),
          if (line.expiryDay != null)
            IconButton(
              key: Key('purchase-expiry-clear-$index'),
              tooltip: 'Quitar la fecha de vencimiento',
              onPressed: () {
                line.expiryDay = null;
                onChanged();
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      const SizedBox(height: 10),
      // Sin maxLength: lo pegado no se recorta; el exceso se señala y
      // bloquea la revisión (decisión del autor del 2026-11-01).
      TextField(
        key: Key('purchase-lot-number-$index'),
        controller: line.lotNumber,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: 'Número de lote (opcional)',
          helperText: 'Como figura en el envase.',
          counterText: lotNumberCounter(line.lotNumber.text),
          errorText: AgroRepository.lotNumberLengthError(line.lotNumber.text),
          errorMaxLines: 3,
        ),
      ),
    ],
  );
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.index,
    required this.line,
    required this.products,
    required this.people,
    required this.usedProductIds,
    required this.onChanged,
    this.ownerPersonId,
    this.onRemove,
    this.personalOwnerName,
    this.onCreateProduct,
    this.onCreatePerson,
    this.voice,
    this.shared = true,
  });
  final int index;
  final _PurchaseLineEditor line;

  /// Dictado del formulario (marcas «Por voz», «Revisar», «Elegir»).
  final VoiceFormDictation<dynamic>? voice;
  final bool shared;

  Widget _mark(String field, {String? currentDisplay}) => VoiceSlotMark(
    dictation: voice,
    slot: SlotRef.line(line.id, field),
    current: line.voiceFields(shared)[field],
    currentDisplay: currentDisplay,
  );

  /// «Falta» de los datos obligatorios en una línea que tocó la voz.
  List<Widget> _missing() {
    final v = voice;
    if (v == null || !v.touchesLine(line.id)) return const [];
    final f = line.voiceFields(shared);
    return [
      if (f['product'] == null) const VoiceMissingMark(label: 'producto'),
      if (f['quantity'] == null) const VoiceMissingMark(label: 'cantidad'),
      if (f['price'] == null) const VoiceMissingMark(label: 'precio'),
    ];
  }

  final List<Map<String, Object?>> products, people;

  /// Titular vigente (de `owner_bindings`), para rotularlo «Titular» en la
  /// lista de personas en vez de con su rol privado (E-14).
  final int? ownerPersonId;

  /// En inventario propio, el titular que recibe la línea entera (#26).
  final String? personalOwnerName;
  final Set<int> usedProductIds;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  /// «Crear producto» en el selector; lo creado queda elegido en esta línea.
  final Future<Map<String, Object?>?> Function()? onCreateProduct;

  /// «Agregar persona» en los selectores de persona del reparto; nulo si
  /// las reglas vigentes no permiten crear personas (inventario propio).
  final Future<Map<String, Object?>?> Function()? onCreatePerson;

  Map<String, Object?>? get selectedProduct {
    for (final product in products) {
      if (product['id'] == line.productId) return product;
    }
    return null;
  }

  String _personName(int? id) =>
      people
          .where((person) => person['id'] == id)
          .firstOrNull?['name']
          ?.toString() ??
      '';

  /// Rótulo secundario de una persona: el titular se dice «Titular»; los
  /// demás, su rol («Familiar», «Tercero»). Nunca «Titular · Familiar».
  String _personRole(Map<String, Object?> person) =>
      ownerPersonId != null && person['id'] == ownerPersonId
      ? 'Titular'
      : personRoleLabel(person['role']);

  /// Cómo va el destinatario de esta línea (UIBUG-039, pilotos X01/X02).
  ///
  /// Una línea vacía no se declara terminada: sólo cuando existen todos sus
  /// datos obligatorios. En compartido lo primero es la decisión explícita
  /// de destinatario; sin ella, «Pendiente de destinatario». La regla
  /// contable no cambia —la valida igual `_validateItems`—; cambia lo que la
  /// tarjeta declara.
  String get _allocationStatus {
    if (personalOwnerName != null) {
      return line.quantityBase <= 0
          ? 'Pendiente de cantidad'
          : 'Para el titular';
    }
    switch (line.allocationMode) {
      case null:
        return 'Pendiente de destinatario';
      case _AllocationMode.single:
        if (line.singlePersonId == null) return 'Pendiente de destinatario';
        if (line.quantityBase <= 0) return 'Pendiente de cantidad';
        return 'Para: ${_personName(line.singlePersonId)}';
      case _AllocationMode.split:
        if (line.quantityBase <= 0) return 'Pendiente de cantidad';
        if (line.allocations.any((allocation) => allocation.personId == null)) {
          return 'Pendiente de persona';
        }
        final pending = line.quantityBase - line.assignedBase;
        if (pending > 0) {
          return 'Pendiente ${formatQuantity(pending, _unit)}';
        }
        if (pending < 0) {
          return 'Excede en ${formatQuantity(-pending, _unit)}';
        }
        return 'Repartida: ${line.allocations.map((a) => '${_personName(a.personId)} ${formatQuantity(tryParseBase(a.quantity.text) ?? 0, _unit)}').join(' · ')}';
    }
  }

  String get _unit => selectedProduct?['unit']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final unit = _unit;
    final hasProduct = unit.isNotEmpty;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          selectedProduct?['name']?.toString() ?? 'Seleccione producto',
        ),
        subtitle: Text(
          '${formatQuantity(line.quantityBase, unit)} · '
          '${formatBob(line.subtotalBob)} · $_allocationStatus',
        ),
        trailing: onRemove == null
            ? null
            : IconButton(
                tooltip: 'Quitar producto',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
        // El relleno superior era 0, así que la etiqueta flotante del primer
        // campo ("Producto") se dibujaba encima de la cabecera de la tarjeta y
        // aparecía recortada (UIBUG-041). Se corrige en el contenedor —la
        // causa— y no desplazando ese texto en concreto: cualquier campo que
        // llegue a ser el primero hereda el arreglo.
        childrenPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        children: [
          AdaptiveEntityPicker<Map<String, Object?>>(
            label: 'Producto',
            items: products
                .where(
                  (product) =>
                      !usedProductIds.contains(product['id']) ||
                      product['id'] == line.productId,
                )
                .toList(),
            value: selectedProduct,
            labelOf: (product) => product['name']! as String,
            secondaryOf: (product) => product['unit']! as String,
            // Piloto X02: el último producto del catálogo entraba solo en la
            // última línea. El producto entra sólo al elegirlo, aunque quede
            // uno (B-08).
            autoSelectSingle: false,
            onChanged: (product) {
              line.productId = product?['id'] as int?;
              onChanged();
            },
            createLabel: onCreateProduct == null ? null : 'Crear producto',
            onCreate: onCreateProduct,
          ),
          _mark(
            'product',
            currentDisplay: selectedProduct?['name']?.toString(),
          ),
          const SizedBox(height: 10),
          // Apilados en ancho de móvil: media fila recortaba la etiqueta a
          // "Cantidad compr…" (UIBUG-040).
          _ResponsivePair(
            first: TextField(
              controller: line.quantity,
              onChanged: (_) {
                line.quantityError = null;
                onChanged();
              },
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // "Cantidad comprada" y no "Cantidad" a secas: la tarjeta
              // tiene un segundo campo de cantidad por cada asignación, y
              // dos etiquetas idénticas en la misma tarjeta obligarían a
              // deducir cuál es cuál (UIBUG-038).
              decoration: InputDecoration(
                labelText: 'Cantidad comprada',
                suffixText: unit.isEmpty ? null : unit,
                errorText: line.quantityError,
                errorMaxLines: 4,
              ),
            ),
            second: DropdownButtonFormField<CurrencyCode>(
              // La clave sigue al valor: si la voz cambia la moneda, el
              // selector la muestra (su `initialValue` sólo cuenta al crearlo).
              key: ValueKey(
                'purchase-currency-${line.id}-${line.currency.name}',
              ),
              initialValue: line.currency,
              decoration: const InputDecoration(labelText: 'Moneda'),
              items: const [
                DropdownMenuItem(value: CurrencyCode.bob, child: Text('BOB')),
                DropdownMenuItem(value: CurrencyCode.usd, child: Text('USD')),
              ],
              onChanged: (value) {
                line.currency = value!;
                onChanged();
              },
            ),
          ),
          _mark('quantity'),
          _mark('currency', currentDisplay: line.currency.name.toUpperCase()),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.price,
                  onChanged: (_) {
                    line.priceError = null;
                    onChanged();
                  },
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // Sin producto elegido la etiqueta terminaba en una barra
                  // huérfana: "Precio BOB/" (UIBUG-037). Mientras no haya
                  // unidad se dice en palabras; en cuanto la hay se vuelve a
                  // la forma corta "Precio BOB/L".
                  decoration: InputDecoration(
                    labelText: hasProduct
                        ? 'Precio ${line.currency == CurrencyCode.usd ? 'USD' : 'BOB'}/$unit'
                        : 'Precio por unidad',
                    errorText: line.priceError,
                    errorMaxLines: 4,
                  ),
                ),
              ),
              if (line.currency == CurrencyCode.usd) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.fx,
                    onChanged: (_) {
                      line.fxError = null;
                      onChanged();
                    },
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'TC Bs/USD',
                      errorText: line.fxError,
                      errorMaxLines: 4,
                    ),
                  ),
                ),
              ],
            ],
          ),
          _mark('price', currentDisplay: line.price.text),
          _mark('fx', currentDisplay: line.fx.text),
          ..._missing(),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            // "Costo 0,00 Bs /" sin unidad tampoco significaba nada
            // (UIBUG-037): hasta elegir producto sólo se muestra el subtotal.
            child: Text(
              hasProduct
                  ? 'Costo ${formatBob(line.unitBob)}/$unit · Subtotal ${formatBob(line.subtotalBob)}'
                  : 'Subtotal ${formatBob(line.subtotalBob)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          _LotDataSection(index: index, line: line, onChanged: onChanged),
          const Divider(height: 24),
          // En propio la línea entera es del titular: no hay reparto (#26).
          if (personalOwnerName != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Para el titular: $personalOwnerName',
                key: Key('purchase-personal-allocation-$index'),
              ),
            )
          else ...[
            ..._recipientSection(context, unit),
            _mark(
              'recipient',
              currentDisplay: line.singlePersonId == null
                  ? null
                  : _personName(line.singlePersonId),
            ),
          ],
        ],
      ),
    );
  }

  /// «¿Para quién es?» en compartido: dos opciones explícitas, ninguna
  /// marcada por defecto. El destinatario de las existencias no es el
  /// pagador (que siempre es el titular, en el paso 2).
  List<Widget> _recipientSection(BuildContext context, String unit) {
    final theme = Theme.of(context);
    return [
      const Text(
        '¿Para quién es?',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      // Chips en `Wrap`: con fuente ampliada pasan a otra línea en vez de
      // recortarse (como «¿Cómo pagaste?»).
      Wrap(
        key: Key('purchase-alloc-mode-$index'),
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            key: Key('purchase-alloc-single-$index'),
            label: const Text('Toda para una persona'),
            selected: line.allocationMode == _AllocationMode.single,
            onSelected: (selected) {
              // Volver a tocar la opción activa no borra nada.
              if (!selected || line.allocationMode == _AllocationMode.single) {
                return;
              }
              line.allocationMode = _AllocationMode.single;
              // Cambiar de opción limpia la anterior: las filas del reparto
              // no se arrastran. Sus controladores se liberan después del
              // fotograma, cuando los campos que los usaban ya no existen.
              final discarded = List.of(line.allocations);
              line.allocations.clear();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                for (final allocation in discarded) {
                  allocation.dispose();
                }
              });
              onChanged();
            },
          ),
          ChoiceChip(
            key: Key('purchase-alloc-split-$index'),
            label: const Text('Repartir entre varias'),
            selected: line.allocationMode == _AllocationMode.split,
            onSelected: (selected) {
              if (!selected || line.allocationMode == _AllocationMode.split) {
                return;
              }
              line.allocationMode = _AllocationMode.split;
              // La persona única no se arrastra a una fila del reparto.
              line.singlePersonId = null;
              // Repartir es entre dos o más: dos filas vacías para empezar,
              // sin ninguna persona prellenada.
              while (line.allocations.length < 2) {
                line.allocations.add(_AllocationEditor());
              }
              onChanged();
            },
          ),
        ],
      ),
      const SizedBox(height: 8),
      switch (line.allocationMode) {
        null => Text(
          'Elija una opción para indicar a quién va este producto.',
          key: Key('purchase-alloc-pending-$index'),
          style: TextStyle(color: theme.colorScheme.outline),
        ),
        _AllocationMode.single => _singleRecipient(theme, unit),
        _AllocationMode.split => _splitRecipients(unit),
      },
    ];
  }

  /// Un destinatario: selector sin valor por defecto ni autoselección; la
  /// cantidad asignada se deriva de «Cantidad comprada», no se teclea.
  Widget _singleRecipient(ThemeData theme, String unit) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdaptiveEntityPicker<Map<String, Object?>>(
        label: 'Persona',
        items: people,
        value: people
            .where((person) => person['id'] == line.singlePersonId)
            .firstOrNull,
        labelOf: (person) => person['name']! as String,
        secondaryOf: _personRole,
        autoSelectSingle: false,
        onChanged: (person) {
          line.singlePersonId = person?['id'] as int?;
          onChanged();
        },
        createLabel: onCreatePerson == null ? null : 'Agregar persona',
        onCreate: onCreatePerson,
      ),
      if (line.singlePersonId != null) ...[
        const SizedBox(height: 6),
        Text(
          'Recibe toda la cantidad comprada: '
          '${formatQuantity(line.quantityBase, unit)}.',
          key: Key('purchase-alloc-derived-$index'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    ],
  );

  /// Reparto por filas: persona y cantidad por fila; las partes suman la
  /// cantidad comprada (lo valida igual `_validateItems`).
  Widget _splitRecipients(String unit) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () {
            line.allocations.add(_AllocationEditor());
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Persona'),
        ),
      ),
      for (
        var allocationIndex = 0;
        allocationIndex < line.allocations.length;
        allocationIndex++
      )
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // **#97.** Persona y cantidad compartían una fila 3:2 y, con la
          // fuente al 130 %, el nombre se truncaba («Titular F1…»). Si
          // no caben con holgura, la persona va arriba a todo el ancho.
          child: _AllocationRow(
            onRemove: line.allocations.length > 2
                ? () {
                    line.allocations.removeAt(allocationIndex).dispose();
                    onChanged();
                  }
                : null,
            children: [
              Expanded(
                flex: 3,
                child: AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Persona',
                  items: people,
                  value: people
                      .where(
                        (person) =>
                            person['id'] ==
                            line.allocations[allocationIndex].personId,
                      )
                      .firstOrNull,
                  labelOf: (person) => person['name']! as String,
                  secondaryOf: _personRole,
                  autoSelectSingle: false,
                  onChanged: (person) {
                    line.allocations[allocationIndex].personId =
                        person?['id'] as int?;
                    onChanged();
                  },
                  createLabel: onCreatePerson == null
                      ? null
                      : 'Agregar persona',
                  onCreate: onCreatePerson,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: line.allocations[allocationIndex].quantity,
                  onChanged: (_) {
                    line.allocations[allocationIndex].quantityError = null;
                    onChanged();
                  },
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // La etiqueta era la unidad a secas, y sin producto
                  // elegido quedaba vacía: un recuadro sin nombre junto a
                  // un selector de persona (UIBUG-038). Ahora el campo
                  // dice qué es, y la unidad acompaña como sufijo cuando
                  // se conoce.
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    suffixText: unit.isEmpty ? null : unit,
                    errorText: line.allocations[allocationIndex].quantityError,
                    errorMaxLines: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Fila de una asignación: persona (flex 3) y cantidad (flex 2) cuando caben;
/// si no, la persona arriba a todo el ancho y la cantidad debajo (#97).
class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.children, this.onRemove});

  /// `[Expanded(persona), SizedBox, Expanded(cantidad)]`.
  final List<Widget> children;
  final VoidCallback? onRemove;

  /// Ancho a partir del cual persona y cantidad caben en una fila sin
  /// truncar un nombre habitual, también con la fuente al 130 %.
  static const double rowMinWidth = 480;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove == null
        ? null
        : IconButton(
            tooltip: 'Quitar asignación',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          );
    final person = (children.first as Expanded).child;
    final quantity = (children.last as Expanded).child;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= rowMinWidth
          ? Row(children: [...children, ?remove])
          : Column(
              children: [
                person,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: quantity),
                    ?remove,
                  ],
                ),
              ],
            ),
    );
  }
}
