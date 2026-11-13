import 'dart:io';
import 'dart:math' as math;

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
import '../theme/agro_theme.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/agro_ui.dart';
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

  /// Rediseño: aviso oscuro con el resultado del último dictado, cuando el
  /// panel ya se cerró solo; y cuántos dictados terminados se vieron.
  bool _voiceBanner = false;
  int _seenCompletions = 0;

  /// Línea abierta en la hoja «Producto n»; nula sin hoja.
  int? editingLineId;

  /// Línea del primer problema de validación (para abrir su hoja) y el
  /// mensaje, que se muestra dentro de la hoja: una barra flotante tapaba
  /// sus botones.
  int? _problemLineId;
  String? _lineProblem;

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
    setState(() {
      dirty = true;
      // El aviso de validación de la hoja era sobre lo que había: al editar
      // deja de valer (el error del campo también se borra).
      _lineProblem = null;
    });
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
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      showVoice = true;
      _voiceBanner = false;
      editingLineId = null;
    });
  }

  /// Al terminar un dictado el panel se cierra y su resultado queda en el
  /// aviso de arriba; lo dictado ya está en el formulario.
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
    // Repinta: muestra los errores de campo recién fijados o los borra. Si
    // el problema está en un producto, abre su hoja para verlo en el campo.
    final line = problem == null ? null : _problemLineId;
    setState(() {
      _lineProblem = line == null ? null : problem;
      if (line != null) editingLineId = line;
    });
    if (problem != null) {
      if (line == null) showError(context, problem);
      return false;
    }
    return true;
  }

  /// Primer problema del paso 1, en el orden en que se lee el formulario.
  /// Fija `*Error` en el campo cuyo texto no se puede interpretar.
  String? _firstProblem() {
    _problemLineId = null;
    if (supplierId == null) return 'Elija el proveedor.';
    if (lines.isEmpty) return 'Añada al menos un producto.';
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      _problemLineId = line.id;
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
    _problemLineId = null;
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
      showError(context, 'Indique si ya pagó al proveedor.');
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
                      'titular la confirma, anótelo después en Actividad › Lista '
                      'de compras, «Registrar pago al proveedor».'
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

  // --- Presentación (rediseño 2026-11-12) -----------------------------------
  //
  // Paso 1 «¿Qué compró?»: proveedor y fecha en filas, cada producto como una
  // tarjeta resumen y la hoja «Producto n» para editarlo. La hoja vive en la
  // misma página y edita la misma línea del borrador: cerrarla no descarta
  // nada. Paso 2 «Revise y confirme»: lo que se va a guardar, «¿Ya pagó al
  // proveedor?» y, plegados, factura, notas y campaña.

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        !dirty &&
        !saving &&
        step == _PurchaseStep.items &&
        editingLineId == null,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || saving) return;
      // Con la hoja de un producto abierta, Atrás la cierra; lo escrito ya
      // está en el borrador.
      if (editingLineId != null) {
        _closeLine();
        return;
      }
      // Desde la revisión, Atrás vuelve al paso 1 sin perder nada.
      if (step == _PurchaseStep.review) {
        _backToItems();
      } else {
        _close();
      }
    },
    child: Scaffold(
      bottomNavigationBar: _bottomBar(),
      // La página va dentro del área segura; la hoja de un producto, con su
      // velo, por encima de todo el cuerpo (también la franja de la barra de
      // estado), como una hoja modal.
      body: FutureBuilder<_PurchaseCatalogs>(
        future: catalogs,
        builder: (context, snapshot) {
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _header(),
          );
          // Sin esta rama, un fallo al cargar los catálogos dejaba el
          // formulario girando indefinidamente, sin explicación ni salida.
          if (snapshot.hasError) {
            return SafeArea(
              child: Column(
                children: [
                  header,
                  Expanded(
                    child: EmptyState(
                      icon: Icons.error_outline,
                      message: friendlyError(snapshot.error!),
                    ),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return SafeArea(
              child: Column(
                children: [
                  header,
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data!;
          final modeChanged = modeChangedSince(
            loadedMode,
            ref.watch(operationModeProvider),
          );
          final editing = _editingLine;
          final sheetOpen = editing != null && step == _PurchaseStep.items;
          // Con la hoja abierta, la página real sigue detrás, a la vista
          // bajo el velo y viva (el mismo borrador, el mismo
          // desplazamiento), pero inerte: ni toques, ni foco, ni lector de
          // pantalla llegan a ella. Los envoltorios están siempre, con la
          // hoja abierta o no, para que la página no se reconstruya desde
          // cero al abrirla o cerrarla.
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
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  24,
                                ),
                                children: [
                                  if (modeChanged) ...[
                                    const ModeChangedNotice(),
                                    const SizedBox(height: 12),
                                  ],
                                  if (step == _PurchaseStep.items)
                                    ..._itemsStep(context, data)
                                  else
                                    ..._reviewStep(context, data),
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
                Positioned.fill(child: _lineSheet(context, data, editing)),
            ],
          );
        },
      ),
    ),
  );

  _PurchaseLineEditor? get _editingLine =>
      lines.where((line) => line.id == editingLineId).firstOrNull;

  /// Volver, «Paso n de 2», el acceso a la voz y la barra de pasos.
  Widget _header() {
    final review = step == _PurchaseStep.review;
    final busy = voice?.busy ?? false;
    return Column(
      children: [
        FlowTopBar(
          backKey: Key(review ? 'purchase-back' : 'purchase-close'),
          backTooltip: review ? 'Volver al paso 1' : 'Volver',
          onBack: saving
              ? null
              : review
              ? _backToItems
              : _close,
          label: 'Paso ${review ? 2 : 1} de 2',
          labelKey: const Key('purchase-step'),
          // F09 (formulario único): la voz completa ESTE formulario; no abre
          // otra pantalla ni descarta nada. Desde la revisión vuelve al paso
          // 1 con el panel abierto.
          trailing: CircleIconButton(
            key: const Key('form-dictar'),
            icon: showVoice && !review ? Icons.mic : Icons.mic_none_outlined,
            tooltip: showVoice && !review
                ? 'Ocultar el panel de voz'
                : 'Completar por voz',
            onPressed: saving
                ? null
                : review
                ? () {
                    _backToItems();
                    _openVoice();
                  }
                : showVoice
                ? busy
                      ? null
                      : () => setState(() => showVoice = false)
                : _openVoice,
          ),
        ),
        const SizedBox(height: 12),
        StepProgress(step: review ? 2 : 1, total: 2),
      ],
    );
  }

  /// Panel inferior: total y «Continuar», «Confirmar compra» o el panel de
  /// voz. Con la hoja de un producto abierta no hay panel: la hoja tiene sus
  /// propios botones.
  Widget? _bottomBar() {
    final items = step == _PurchaseStep.items;
    if (items && editingLineId != null) return null;
    if (items && showVoice && voice != null) {
      return VoiceFormPanel(
        dictation: voice!,
        docked: true,
        example:
            '«Doce litros de herbicida a ciento dieciocho, de Agroinsumos, '
            'para Rosa»',
        onClose: () => setState(() => showVoice = false),
        // Sólo en la compilación de diagnóstico: modelo del próximo turno y
        // métricas sin texto.
        diagnostics: voiceDiagnosticsBuild
            ? VoiceSingleTranscriberPanel(session: voice!.session)
            : null,
      );
    }
    return FutureBuilder<_PurchaseCatalogs>(
      future: catalogs,
      builder: (context, snapshot) {
        final voiceBlock = voice?.blocksSave ?? false;
        final blocked =
            saving ||
            voiceBlock ||
            !snapshot.hasData ||
            modeChangedSince(loadedMode, ref.watch(operationModeProvider));
        if (items) {
          return BottomPanel(
            children: [
              if (voiceBlock)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.rule,
                        size: 18,
                        color: AgroColors.caution,
                      ),
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
              _itemsTotal(),
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
              label: saving ? 'Guardando…' : 'Confirmar compra',
              icon: Icons.check,
              iconFirst: true,
              busy: saving,
              onPressed: blocked ? null : () => _confirm(snapshot.data!),
            ),
          ],
        );
      },
    );
  }

  /// Total del paso 1. Mientras falte un dato de algún producto no se
  /// muestra un total que no lo es.
  Widget _itemsTotal() {
    const key = Key('purchase-items-total');
    final filled = lines.where((line) => !_isBlank(line)).toList();
    if (filled.isEmpty) {
      return const TotalLine(
        label: 'Total',
        amount: '—',
        muted: true,
        amountKey: key,
      );
    }
    final missing = filled.any((line) => line.priceMinor <= 0)
        ? 'un precio'
        : filled.any((line) => line.quantityBase <= 0)
        ? 'una cantidad'
        : filled.any(
            (line) =>
                line.currency == CurrencyCode.usd &&
                (line.exchangeRateScaled ?? 0) <= 0,
          )
        ? 'un tipo de cambio'
        : null;
    if (missing != null) {
      return TotalLine(
        label: 'Total · falta $missing',
        amount: '—',
        muted: true,
        amountKey: key,
      );
    }
    return TotalLine(
      label:
          'Total · ${filled.length} '
          '${filled.length == 1 ? 'producto' : 'productos'}',
      amount: formatBob(totalBob),
      amountKey: key,
    );
  }

  /// «Hoy, 12/11/2026» o la fecha a secas.
  static String _dayLabel(String day) => day == localDay(DateTime.now())
      ? 'Hoy, ${formatDate(day)}'
      : formatDate(day);

  String? _ownerName(_PurchaseCatalogs data) => data.people
      .where((row) => row['id'] == ownerPersonId)
      .firstOrNull?['name']
      ?.toString();

  /// Una línea sin ningún dato: ni producto, ni cantidad, ni precio, ni
  /// destinatario, ni lote.
  bool _isBlank(_PurchaseLineEditor line) =>
      line.productId == null &&
      line.quantity.text.trim().isEmpty &&
      line.price.text.trim().isEmpty &&
      line.fx.text.trim().isEmpty &&
      line.currency == CurrencyCode.bob &&
      line.allocationMode == null &&
      line.expiryDay == null &&
      line.lotNumber.text.trim().isEmpty &&
      !(voice?.touchesLine(line.id) ?? false);

  void _openLine(int id) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      editingLineId = id;
      _lineProblem = null;
    });
  }

  void _closeLine() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      editingLineId = null;
      _lineProblem = null;
    });
  }

  /// «Añadir producto»: abre la única línea si todavía está vacía; si no,
  /// añade una línea y la abre.
  void _addLine() {
    if (lines.length == 1 && _isBlank(lines.single)) {
      _openLine(lines.single.id);
      return;
    }
    _appendLine();
  }

  /// «Listo y añadir otro» y «Añadir otro producto».
  void _appendLine() {
    FocusManager.instance.primaryFocus?.unfocus();
    final line = _newLine();
    setState(() {
      lines.add(line);
      dirty = true;
      editingLineId = line.id;
      _lineProblem = null;
    });
  }

  void _removeLine(_PurchaseLineEditor line) {
    FocusManager.instance.primaryFocus?.unfocus();
    lines.remove(line);
    voice?.lineRemoved(line.id);
    setState(() {
      dirty = true;
      editingLineId = null;
    });
    // Sus campos siguen montados hasta el próximo fotograma.
    WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());
  }

  List<Widget> _itemsStep(BuildContext context, _PurchaseCatalogs data) {
    final supplierName = data.suppliers
        .where((row) => row['id'] == supplierId)
        .firstOrNull?['name']
        ?.toString();
    final onlyBlank = lines.length == 1 && _isBlank(lines.single);
    final filled = lines.where((line) => !_isBlank(line)).length;
    return [
      Semantics(
        header: true,
        child: const Text('¿Qué compró?', style: AgroText.h1),
      ),
      const SizedBox(height: 12),
      if (voice != null && _voiceBanner && !showVoice) ...[
        VoiceResultBanner(
          dictation: voice!,
          onDictateMore: saving ? null : _openVoice,
          onDismiss: () => setState(() => _voiceBanner = false),
        ),
        const SizedBox(height: 12),
      ] else if (!showVoice) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton(
            key: const Key('compra-completar-voz'),
            icon: Icons.mic_none_outlined,
            label: 'Completar por voz',
            onPressed: saving ? null : _openVoice,
          ),
        ),
        const SizedBox(height: 12),
      ],
      AgroGroup(
        children: [
          AdaptiveEntityPicker<Map<String, Object?>>(
            key: const Key('purchase-supplier'),
            rowStyle: true,
            label: 'Proveedor',
            items: data.suppliers,
            value: data.suppliers
                .where((row) => row['id'] == supplierId)
                .firstOrNull,
            labelOf: (row) => row['name']! as String,
            createLabel: 'Crear proveedor',
            onCreate: _createSupplier,
            badge: VoiceMarkBadge(
              dictation: voice,
              slot: const SlotRef.header('supplier'),
              current: supplierId,
            ),
            onChanged: (row) {
              final value = row?['id'] as int?;
              // El único proveedor se deja elegido como valor de referencia;
              // eso no es un cambio de la persona, así que Atrás no debe
              // preguntar «¿Descartar cambios?» (B-07).
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
          ValueRow(
            key: const Key('purchase-date'),
            label: 'Fecha de la compra',
            value: _dayLabel(effectiveDay),
            onTap: saving ? null : _pickDate,
          ),
        ],
      ),
      VoiceSlotMark(
        dictation: voice,
        slot: const SlotRef.header('supplier'),
        current: supplierId,
        currentDisplay: supplierName,
        showMark: false,
      ),
      const SizedBox(height: 8),
      SectionHeader(
        title: 'Productos de esta compra',
        trailing: filled == 0 ? null : '$filled',
      ),
      const SizedBox(height: 10),
      if (!onlyBlank)
        for (var index = 0; index < lines.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _lineCard(index, data),
          ),
      // «Añadir otro producto» agrega una **línea** a la compra; «Crear
      // producto», en el selector de cada línea, da de alta un producto del
      // catálogo (2026-11-05).
      DashedAddButton(
        key: const Key('purchase-add-line'),
        label: onlyBlank ? 'Añadir producto' : 'Añadir otro producto',
        onPressed: saving ? null : _addLine,
      ),
    ];
  }

  Map<String, Object?>? _productOf(_PurchaseCatalogs data, int? id) =>
      data.products.where((row) => row['id'] == id).firstOrNull;

  String _personName(_PurchaseCatalogs data, int? id) =>
      data.people
          .where((person) => person['id'] == id)
          .firstOrNull?['name']
          ?.toString() ??
      '';

  /// Precio de la línea en su moneda («118,00 Bs», «16,00 US$»).
  static String _priceText(_PurchaseLineEditor line) =>
      line.currency == CurrencyCode.usd
      ? formatUsd(line.priceMinor)
      : formatBob(line.priceMinor);

  /// Cómo va el destinatario de esta línea (UIBUG-039, pilotos X01/X02).
  ///
  /// Una línea vacía no se declara terminada: sólo cuando existen todos sus
  /// datos obligatorios. En compartido lo primero es la decisión explícita
  /// de destinatario; sin ella, «Pendiente de destinatario». La regla
  /// contable no cambia —la valida igual `_validateItems`—; cambia lo que la
  /// tarjeta declara.
  String _allocationStatus(_PurchaseLineEditor line, _PurchaseCatalogs data) {
    final unit = _productOf(data, line.productId)?['unit']?.toString() ?? '';
    if (personalOwnerId != null) {
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
        return 'Para: ${_personName(data, line.singlePersonId)}';
      case _AllocationMode.split:
        if (line.quantityBase <= 0) return 'Pendiente de cantidad';
        if (line.allocations.any((allocation) => allocation.personId == null)) {
          return 'Pendiente de persona';
        }
        final pending = line.quantityBase - line.assignedBase;
        if (pending > 0) {
          return 'Pendiente ${formatQuantity(pending, unit)}';
        }
        if (pending < 0) {
          return 'Excede en ${formatQuantity(-pending, unit)}';
        }
        return 'Repartida: ${line.allocations.map((a) => '${_personName(data, a.personId)} ${formatQuantity(tryParseBase(a.quantity.text) ?? 0, unit)}').join(' · ')}';
    }
  }

  static const _voiceLineFields = [
    'product',
    'quantity',
    'price',
    'currency',
    'fx',
    'recipient',
  ];

  /// Tarjeta resumen de una línea en el paso 1. Lo que la voz dejó por
  /// elegir o revisar se resuelve aquí mismo; «Escribir otro valor» abre la
  /// hoja del producto.
  Widget _lineCard(int index, _PurchaseCatalogs data) {
    final line = lines[index];
    final product = _productOf(data, line.productId);
    final unit = product?['unit']?.toString() ?? '';
    final shared = personalOwnerId == null;
    final fields = line.voiceFields(shared);
    final v = voice;
    final pending =
        v != null &&
        _voiceLineFields.any((field) {
          final slot = SlotRef.line(line.id, field);
          return v.choiceFor(slot) != null || v.reviewFor(slot) != null;
        });
    final byVoice =
        v != null &&
        fields.entries.any(
          (e) => v.markFor(SlotRef.line(line.id, e.key), e.value) != null,
        );
    final amounts = [
      if (line.quantityBase > 0) formatQuantity(line.quantityBase, unit),
      if (line.priceMinor > 0) _priceText(line),
    ].join(' × ');
    // Cantidad, persona y, si lo hay, el vencimiento. El número del envase
    // no: es un dato secundario que se ve en la hoja y en la revisión.
    final subtitle = [
      if (amounts.isNotEmpty) amounts,
      _allocationStatus(line, data),
      if (line.expiryDay != null) 'Vence el ${displayDay(line.expiryDay!)}',
    ].join(' · ');
    final complete =
        line.quantityBase > 0 &&
        line.priceMinor > 0 &&
        (line.currency == CurrencyCode.bob ||
            (line.exchangeRateScaled ?? 0) > 0);
    return ItemCard(
      key: Key('purchase-line-$index'),
      title: product?['name']?.toString() ?? 'Producto ${index + 1}',
      subtitle: product == null
          ? 'Falta elegir el producto · $subtitle'
          : subtitle,
      amount: complete ? formatBob(line.subtotalBob) : null,
      attention: pending,
      semanticsHint: 'Abrir para editar',
      badge: byVoice && !pending
          ? const StatusBadge(label: 'Por voz', tone: BadgeTone.voice)
          : null,
      onTap: saving ? null : () => _openLine(line.id),
      footer: [
        ..._missing(line, fields),
        for (final field in _voiceLineFields)
          VoiceSlotMark(
            dictation: v,
            slot: SlotRef.line(line.id, field),
            current: fields[field],
            currentDisplay: switch (field) {
              'product' => product?['name']?.toString(),
              'recipient' =>
                line.singlePersonId == null
                    ? null
                    : _personName(data, line.singlePersonId),
              'currency' => line.currency.name.toUpperCase(),
              'price' => line.price.text,
              'fx' => line.fx.text,
              _ => null,
            },
            showMark: false,
            writeOtherLabel: field == 'product' || field == 'recipient'
                ? 'Elegir otro'
                : 'Escribir otro valor',
            onWriteOther: saving ? null : () => _openLine(line.id),
          ),
      ],
    );
  }

  /// «Falta» de los datos obligatorios en una línea que tocó la voz.
  List<Widget> _missing(_PurchaseLineEditor line, Map<String, Object?> f) {
    final v = voice;
    if (v == null || !v.touchesLine(line.id)) return const [];
    return [
      if (f['product'] == null) const VoiceMissingMark(label: 'producto'),
      if (f['quantity'] == null) const VoiceMissingMark(label: 'cantidad'),
      if (f['price'] == null) const VoiceMissingMark(label: 'precio'),
    ];
  }

  /// Hoja «Producto n»: edita la línea en el borrador.
  Widget _lineSheet(
    BuildContext context,
    _PurchaseCatalogs data,
    _PurchaseLineEditor line,
  ) {
    final index = lines.indexOf(line);
    return InPageSheet(
      key: Key('purchase-line-sheet-$index'),
      title: 'Producto ${index + 1}',
      closeKey: const Key('purchase-line-close'),
      onClose: _closeLine,
      actions: [
        SecondaryActionButton(
          key: const Key('purchase-line-next'),
          label: 'Añadir otro',
          icon: Icons.add,
          onPressed: saving ? null : _appendLine,
        ),
        PrimaryActionButton(
          key: const Key('purchase-line-done'),
          label: 'Listo',
          icon: Icons.check,
          iconFirst: true,
          onPressed: _closeLine,
        ),
      ],
      children: _lineEditor(context, data, line, index),
    );
  }

  /// Marca de voz de un campo de la hoja. El producto ya lleva «Por voz» en
  /// su fila ([showMark] falso); en la hoja el campo está a la vista, así que
  /// no hace falta «Escribir otro valor»: se escribe en él.
  Widget _lineMark(
    _PurchaseLineEditor line,
    String field, {
    String? currentDisplay,
    bool showMark = true,
  }) => VoiceSlotMark(
    dictation: voice,
    slot: SlotRef.line(line.id, field),
    current: line.voiceFields(personalOwnerId == null)[field],
    currentDisplay: currentDisplay,
    showMark: showMark,
  );

  /// Rótulo secundario de una persona: el titular se dice «Titular»; los
  /// demás, su rol («Familiar», «Tercero»). Nunca «Titular · Familiar».
  String _personRole(Map<String, Object?> person) =>
      ownerPersonId != null && person['id'] == ownerPersonId
      ? 'Titular'
      : personRoleLabel(person['role']);

  List<Widget> _lineEditor(
    BuildContext context,
    _PurchaseCatalogs data,
    _PurchaseLineEditor line,
    int index,
  ) {
    final product = _productOf(data, line.productId);
    final unit = product?['unit']?.toString() ?? '';
    final hasProduct = unit.isNotEmpty;
    final usd = line.currency == CurrencyCode.usd;
    final usedProductIds = {
      for (final other in lines)
        if (!identical(other, line) && other.productId != null)
          other.productId!,
    };
    const suffixStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AgroColors.muted,
    );
    final quantity = TextField(
      key: Key('purchase-quantity-$index'),
      controller: line.quantity,
      onChanged: (_) {
        line.quantityError = null;
        _markDirty();
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AgroText.input,
      // "Cantidad comprada" y no "Cantidad" a secas: en «Repartir entre
      // varias» cada parte tiene su propio campo de cantidad (UIBUG-038).
      decoration: InputDecoration(
        labelText: 'Cantidad comprada',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixText: unit.isEmpty ? null : unit,
        suffixStyle: suffixStyle,
        errorText: line.quantityError,
        errorMaxLines: 4,
      ),
    );
    final price = TextField(
      key: Key('purchase-price-$index'),
      controller: line.price,
      onChanged: (_) {
        line.priceError = null;
        _markDirty();
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AgroText.input,
      // Sin producto elegido no hay unidad: «Precio por unidad» (UIBUG-037).
      decoration: InputDecoration(
        labelText: hasProduct ? 'Precio por $unit' : 'Precio por unidad',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixText: usd ? 'USD' : 'Bs',
        suffixStyle: suffixStyle,
        errorText: line.priceError,
        errorMaxLines: 4,
      ),
    );
    return [
      if (_lineProblem != null) ...[
        Semantics(
          liveRegion: true,
          child: NoticeBox(
            key: const Key('purchase-line-problem'),
            tone: NoticeTone.danger,
            text: _lineProblem!,
          ),
        ),
        const SizedBox(height: 12),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          key: const Key('purchase-line-voz'),
          icon: Icons.mic_none_outlined,
          label: 'Completar por voz',
          onPressed: saving
              ? null
              : () {
                  _closeLine();
                  _openVoice();
                },
        ),
      ),
      const SizedBox(height: 12),
      AgroGroup(
        children: [
          AdaptiveEntityPicker<Map<String, Object?>>(
            rowStyle: true,
            label: 'Producto',
            items: data.products
                .where(
                  (row) =>
                      !usedProductIds.contains(row['id']) ||
                      row['id'] == line.productId,
                )
                .toList(),
            value: product,
            labelOf: (row) => row['name']! as String,
            secondaryOf: (row) => row['unit']! as String,
            // Piloto X02: el último producto del catálogo entraba solo en la
            // última línea. El producto entra sólo al elegirlo (B-08).
            autoSelectSingle: false,
            badge: VoiceMarkBadge(
              dictation: voice,
              slot: SlotRef.line(line.id, 'product'),
              current: line.productId,
            ),
            onChanged: (row) {
              line.productId = row?['id'] as int?;
              _markDirty();
            },
            createLabel: 'Crear producto',
            onCreate: _createProduct,
          ),
        ],
      ),
      _lineMark(
        line,
        'product',
        currentDisplay: product?['name']?.toString(),
        showMark: false,
      ),
      const SizedBox(height: 12),
      // Lado a lado si caben con la letra actual; si no, uno debajo del otro
      // (UIBUG-040).
      LayoutBuilder(
        builder: (context, constraints) {
          // Lado a lado sólo si la etiqueta flotante más larga cabe entera en
          // media fila, medida con la letra y la escala reales (UIBUG-040).
          final floating =
              (Theme.of(context).textTheme.bodyLarge ??
                      const TextStyle(fontSize: 16))
                  .copyWith(fontSize: 12);
          final widest = [
            'Cantidad comprada',
            hasProduct ? 'Precio por $unit' : 'Precio por unidad',
          ].map((t) => measureText(context, t, floating)).fold(0.0, math.max);
          if (constraints.maxWidth >= 2 * (widest + 40) + 10) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: quantity),
                const SizedBox(width: 10),
                Expanded(child: price),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [quantity, const SizedBox(height: 10), price],
          );
        },
      ),
      _lineMark(line, 'quantity'),
      _lineMark(line, 'price', currentDisplay: line.price.text),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 168,
            child: SegmentToggle<CurrencyCode>(
              key: Key('purchase-currency-$index'),
              semanticLabel: 'Moneda',
              height: 44,
              options: [
                ToggleOption(
                  CurrencyCode.bob,
                  'BOB',
                  key: Key('purchase-currency-bob-$index'),
                ),
                ToggleOption(
                  CurrencyCode.usd,
                  'USD',
                  key: Key('purchase-currency-usd-$index'),
                ),
              ],
              selected: line.currency,
              onChanged: (value) {
                if (value == line.currency) return;
                line.currency = value;
                _markDirty();
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Subtotal', style: AgroText.detail),
              Text(
                formatBob(line.subtotalBob),
                key: Key('purchase-line-subtotal-$index'),
                style: AgroText.total.copyWith(fontSize: 24, height: 30 / 24),
              ),
            ],
          ),
        ],
      ),
      _lineMark(
        line,
        'currency',
        currentDisplay: line.currency.name.toUpperCase(),
      ),
      if (usd) ...[
        const SizedBox(height: 12),
        TextField(
          controller: line.fx,
          onChanged: (_) {
            line.fxError = null;
            _markDirty();
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'TC Bs/USD',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            errorText: line.fxError,
            errorMaxLines: 4,
          ),
        ),
        _lineMark(line, 'fx', currentDisplay: line.fx.text),
        if (hasProduct)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Costo en bolivianos: ${formatBob(line.unitBob)}/$unit',
              style: AgroText.detail,
            ),
          ),
      ],
      ..._missing(line, line.voiceFields(personalOwnerId == null)),
      const SizedBox(height: 16),
      // En propio la línea entera es del titular: no hay reparto (#26).
      if (personalOwnerId != null)
        NoticeBox(
          key: Key('purchase-personal-allocation-$index'),
          icon: Icons.person_outline,
          text:
              'Para el titular: '
              '${_ownerName(data) ?? 'Titular'}',
        )
      else ...[
        ..._recipientSection(data, line, index, unit),
        _lineMark(
          line,
          'recipient',
          currentDisplay: line.singlePersonId == null
              ? null
              : _personName(data, line.singlePersonId),
        ),
      ],
      const SizedBox(height: 12),
      // Vencimiento a la vista; el número del envase, aparte y plegado.
      AgroGroup(
        children: [
          _ExpiryRow(index: index, line: line, onChanged: _markDirty),
          _PackageDataSection(index: index, line: line, onChanged: _markDirty),
        ],
      ),
      if (lines.length > 1) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: Key('purchase-line-remove-$index'),
            onPressed: saving ? null : () => _removeLine(line),
            style: TextButton.styleFrom(foregroundColor: AgroColors.danger),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Quitar este producto'),
          ),
        ),
      ],
    ];
  }

  /// «¿Para quién es?» en compartido: dos opciones explícitas, ninguna
  /// marcada por defecto. El destinatario de las existencias no es el
  /// pagador (que siempre es el titular, en el paso 2).
  List<Widget> _recipientSection(
    _PurchaseCatalogs data,
    _PurchaseLineEditor line,
    int index,
    String unit,
  ) {
    final people = data.people;
    final canCreate = _canCreatePeople;
    return [
      const Text('¿Para quién es?', style: AgroText.question),
      const SizedBox(height: 8),
      SegmentToggle<_AllocationMode>(
        key: Key('purchase-alloc-mode-$index'),
        semanticLabel: 'Para quién es',
        options: [
          ToggleOption(
            _AllocationMode.single,
            'Una persona',
            key: Key('purchase-alloc-single-$index'),
          ),
          ToggleOption(
            _AllocationMode.split,
            'Repartir entre varias',
            key: Key('purchase-alloc-split-$index'),
          ),
        ],
        selected: line.allocationMode,
        onChanged: (mode) {
          // Volver a tocar la opción activa no borra nada.
          if (mode == line.allocationMode) return;
          if (mode == _AllocationMode.single) {
            line.allocationMode = _AllocationMode.single;
            // Cambiar de opción limpia la anterior: las filas del reparto no
            // se arrastran. Sus controladores se liberan después del
            // fotograma, cuando los campos que los usaban ya no existen.
            final discarded = List.of(line.allocations);
            line.allocations.clear();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              for (final allocation in discarded) {
                allocation.dispose();
              }
            });
          } else {
            line.allocationMode = _AllocationMode.split;
            // La persona única no se arrastra a una fila del reparto.
            line.singlePersonId = null;
            // Repartir es entre dos o más: dos filas vacías para empezar,
            // sin ninguna persona prellenada.
            while (line.allocations.length < 2) {
              line.allocations.add(_AllocationEditor());
            }
          }
          _markDirty();
        },
      ),
      const SizedBox(height: 10),
      switch (line.allocationMode) {
        null => Text(
          'Elija una opción para indicar a quién va este producto.',
          key: Key('purchase-alloc-pending-$index'),
          style: AgroText.detail,
        ),
        // Un destinatario: selector sin valor por defecto ni autoselección;
        // la cantidad asignada se deriva de «Cantidad comprada».
        _AllocationMode.single => AgroGroup(
          children: [
            AdaptiveEntityPicker<Map<String, Object?>>(
              rowStyle: true,
              label: 'Persona',
              displayLabel: line.quantityBase > 0
                  ? 'Recibe toda la cantidad: '
                        '${formatQuantity(line.quantityBase, unit)}'
                  : 'Persona que recibe',
              displayLabelKey: Key('purchase-alloc-derived-$index'),
              items: people,
              value: people
                  .where((person) => person['id'] == line.singlePersonId)
                  .firstOrNull,
              labelOf: (person) => person['name']! as String,
              secondaryOf: _personRole,
              autoSelectSingle: false,
              onChanged: (person) {
                line.singlePersonId = person?['id'] as int?;
                _markDirty();
              },
              createLabel: canCreate ? 'Agregar persona' : null,
              onCreate: canCreate ? _createPerson : null,
            ),
          ],
        ),
        // Reparto por filas: persona y cantidad por fila; las partes suman
        // la cantidad comprada (lo valida igual `_validateItems`).
        _AllocationMode.split => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < line.allocations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AllocationRow(
                  onRemove: line.allocations.length > 2
                      ? () {
                          final removed = line.allocations.removeAt(i);
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => removed.dispose(),
                          );
                          _markDirty();
                        }
                      : null,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AgroGroup(
                        children: [
                          AdaptiveEntityPicker<Map<String, Object?>>(
                            rowStyle: true,
                            label: 'Persona',
                            items: people,
                            value: people
                                .where(
                                  (person) =>
                                      person['id'] ==
                                      line.allocations[i].personId,
                                )
                                .firstOrNull,
                            labelOf: (person) => person['name']! as String,
                            secondaryOf: _personRole,
                            autoSelectSingle: false,
                            onChanged: (person) {
                              line.allocations[i].personId =
                                  person?['id'] as int?;
                              _markDirty();
                            },
                            createLabel: canCreate ? 'Agregar persona' : null,
                            onCreate: canCreate ? _createPerson : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: line.allocations[i].quantity,
                        onChanged: (_) {
                          line.allocations[i].quantityError = null;
                          _markDirty();
                        },
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // El campo dice qué es; la unidad acompaña como
                        // sufijo cuando se conoce (UIBUG-038).
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          suffixText: unit.isEmpty ? null : unit,
                          errorText: line.allocations[i].quantityError,
                          errorMaxLines: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  _allocationStatus(line, data),
                  key: Key('purchase-alloc-status-$index'),
                  style: AgroText.detail.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  key: Key('purchase-alloc-add-$index'),
                  onPressed: () {
                    line.allocations.add(_AllocationEditor());
                    _markDirty();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir persona'),
                ),
              ],
            ),
          ],
        ),
      },
    ];
  }

  List<Widget> _reviewStep(BuildContext context, _PurchaseCatalogs data) {
    final ownerName = _ownerName(data) ?? 'Titular';
    final supplierName =
        data.suppliers
            .where((row) => row['id'] == supplierId)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String personName(int? id) => _personName(data, id);
    String productName(int? id) =>
        _productOf(data, id)?['name']?.toString() ?? '';
    String productUnit(int? id) =>
        _productOf(data, id)?['unit']?.toString() ?? '';
    return [
      Semantics(
        header: true,
        child: const Text('Revise y confirme', style: AgroText.h1),
      ),
      const SizedBox(height: 12),
      // Por producto: nombre, cantidad, destinatario y subtotal, a la vista
      // antes de confirmar (pilotos X01/X02).
      Container(
        key: const Key('purchase-review'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AgroColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text(
                  supplierName,
                  key: const Key('purchase-review-supplier'),
                  style: AgroText.value,
                ),
                Text(
                  _dayLabel(effectiveDay),
                  key: const Key('purchase-review-date'),
                  style: AgroText.detail,
                ),
              ],
            ),
            const Divider(height: 24),
            for (var index = 0; index < lines.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AmountAside(
                  amount: formatBob(lines[index].subtotalBob),
                  amountKey: Key('purchase-review-subtotal-$index'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${productName(lines[index].productId)} · '
                        '${formatQuantity(lines[index].quantityBase, productUnit(lines[index].productId))}',
                        key: Key('purchase-review-line-$index'),
                        style: const TextStyle(
                          fontSize: 16,
                          height: 22 / 16,
                          fontWeight: FontWeight.w700,
                          color: AgroColors.ink,
                        ),
                      ),
                      Text(
                        _recipientSummary(
                          lines[index],
                          personName,
                          productUnit(lines[index].productId),
                          ownerName,
                        ),
                        key: Key('purchase-review-recipient-$index'),
                        style: AgroText.detail,
                      ),
                      if (_lotDataSummary(lines[index]) case final lot?)
                        Text(
                          lot,
                          key: Key('purchase-review-lot-$index'),
                          style: AgroText.detail,
                        ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 14),
            TotalLine(
              label:
                  'Total · ${lines.length} '
                  '${lines.length == 1 ? 'producto' : 'productos'}',
              amount: formatBob(totalBob),
              amountKey: const Key('purchase-total'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      // El total se dice una sola vez, arriba; aquí sólo la decisión de pago
      // (2026-11-05). «Sí, pagué todo» paga ese total.
      Semantics(
        header: true,
        child: const Text(
          '¿Ya pagó al proveedor?',
          key: Key('purchase-paid-question'),
          style: AgroText.h2,
        ),
      ),
      const SizedBox(height: 10),
      // Sin respuesta por defecto: la persona elige.
      ChoiceCards<bool>(
        key: const Key('purchase-paid-choice'),
        semanticLabel: 'Pago al proveedor',
        options: const [
          ChoiceCardOption(
            true,
            'Sí, pagué todo',
            Icons.payments_outlined,
            key: Key('purchase-paid-yes'),
          ),
          ChoiceCardOption(
            false,
            'Todavía no',
            Icons.schedule_outlined,
            key: Key('purchase-paid-no'),
          ),
        ],
        selected: paidInFull,
        onChanged: saving
            ? null
            : (value) => setState(() {
                paidInFull = value;
                dirty = true;
              }),
      ),
      const SizedBox(height: 12),
      switch (paidInFull) {
        // El pagador no se edita: es el titular del vínculo real. El medio y
        // la fecha sí se ven y se corrigen: no se guardan valores que la
        // persona no haya visto.
        true => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              key: const Key('purchase-payer-owner'),
              children: [
                const Icon(Icons.check_circle_outline, color: AgroColors.link),
                const SizedBox(width: 8),
                // Antes de guardar no hay ningún pago registrado: se dice
                // quién paga, como en el pago posterior (E-16).
                Expanded(
                  child: Text(
                    'Paga el titular: $ownerName',
                    style: AgroText.question.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
        false => const NoticeBox(
          key: Key('purchase-no-payment'),
          icon: Icons.schedule_outlined,
          text:
              'La compra queda sin pago. Puede anotarlo después en '
              'Operaciones, Compras.',
        ),
        null => const Text(
          'Elija una opción para poder confirmar.',
          key: Key('purchase-paid-pending'),
          style: AgroText.detail,
        ),
      },
      const SizedBox(height: 16),
      AgroGroup(
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('purchase-details'),
              tilePadding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
              shape: const Border(),
              collapsedShape: const Border(),
              iconColor: AgroColors.ink,
              collapsedIconColor: AgroColors.muted,
              title: const Text(
                'Factura, notas y campaña (opcional)',
                style: TextStyle(
                  fontSize: 15,
                  height: 20 / 15,
                  fontWeight: FontWeight.w500,
                  color: AgroColors.ink,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                TextField(
                  controller: invoiceNumber,
                  onChanged: (_) => _markDirty(),
                  decoration: const InputDecoration(
                    labelText: 'N.º de factura',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Cámara'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                    ),
                    if (invoiceImage != null)
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
                  data.campaigns
                      .where((row) => row['status'] == 'ACTIVE')
                      .toList(),
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
        ],
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

/// Vencimiento y número de lote del envase de una línea, en palabras, para
/// los resúmenes. Sólo lo que hay: la ausencia de un dato opcional no se
/// repite en cada línea («sin número de lote»), y el lote nunca se nombra
/// por su identificador interno. Nulo si no hay ninguno de los dos.
String? _lotDataSummary(_PurchaseLineEditor line) {
  final parts = [
    if (line.expiryDay != null) 'Vence el ${displayDay(line.expiryDay!)}',
    if (line.lotNumberValue != null) _packageLotText(line.lotNumberValue!),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// «Lote del envase GL-2611-07»: el número que escribió la persona, tal como
/// figura en el envase (el del fabricante), nunca uno generado.
String _packageLotText(String number) => 'Lote del envase $number';

/// Contador del número de lote en caracteres Unicode, como los cuenta el
/// repositorio.
String lotNumberCounter(String text) =>
    '${text.trim().runes.length}/${AgroRepository.maxLotNumberLength}';

/// Vencimiento de la línea (F04-AV, RF-42): opcional y a la vista. Sin
/// fecha, el lote se guarda «sin fecha registrada», como siempre.
class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({
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
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ValueRow(
          key: Key('purchase-expiry-$index'),
          label: 'Vencimiento (opcional)',
          value: line.expiryDay == null
              ? null
              : 'Vence el ${displayDay(line.expiryDay!)}',
          placeholder: 'Elegir fecha',
          trailing: const Icon(Icons.event_outlined, color: AgroColors.muted),
          onTap: () => _pickExpiry(context),
        ),
      ),
      if (line.expiryDay != null)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            key: Key('purchase-expiry-clear-$index'),
            tooltip: 'Quitar la fecha de vencimiento',
            onPressed: () {
              line.expiryDay = null;
              onChanged();
            },
            icon: const Icon(Icons.close),
          ),
        ),
    ],
  );
}

/// «Más datos del envase»: el número de lote que trae el envase (el del
/// fabricante), opcional y plegado. Lo escribe la persona tal como figura;
/// la aplicación nunca lo inventa, y el identificador interno del lote no se
/// muestra. Una compra sin él se registra igual que antes.
class _PackageDataSection extends StatelessWidget {
  const _PackageDataSection({
    required this.index,
    required this.line,
    required this.onChanged,
  });
  final int index;
  final _PurchaseLineEditor line;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final number = line.lotNumberValue;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('purchase-lot-data-$index'),
        // Con un número (o un error en él) se abre desplegada: lo escrito y
        // su aviso quedan a la vista al volver a la hoja.
        initiallyExpanded: line.lotNumber.text.trim().isNotEmpty,
        tilePadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: AgroColors.ink,
        collapsedIconColor: AgroColors.muted,
        // Arriba, sitio para el rótulo flotante del campo: el despliegue
        // recorta lo que sobresale.
        childrenPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        title: const Text(
          'Más datos del envase',
          style: TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w500,
            color: AgroColors.ink,
          ),
        ),
        subtitle: number == null
            ? null
            : Text(_packageLotText(number), style: AgroText.detail),
        children: [
          // Sin maxLength: lo pegado no se recorta; el exceso se señala y
          // bloquea la revisión (decisión del autor del 2026-11-01).
          TextField(
            key: Key('purchase-lot-number-$index'),
            controller: line.lotNumber,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'Número de lote del envase (opcional)',
              helperText:
                  'Tal como figura en el envase. Si no tiene, '
                  'déjelo vacío.',
              helperMaxLines: 3,
              counterText: lotNumberCounter(line.lotNumber.text),
              errorText: AgroRepository.lotNumberLengthError(
                line.lotNumber.text,
              ),
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
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
