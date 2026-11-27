import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/campaign_calendar.dart';
import '../../../domain/models.dart';
import '../../../domain/money.dart';
import '../../../domain/operation_mode.dart';
import '../../../domain/repository_types.dart'
    show repositoryMaxLotNumberLength;
import '../../widgets/common.dart';
import '../../widgets/mode_notice.dart' show modeChangedSince;

/// Cómo se asigna una línea en compartido. Nulo hasta que la persona elige:
/// ninguna de las dos opciones viene marcada.
enum AllocationMode {
  /// Toda la cantidad comprada para una persona, sin reteclearla.
  single,

  /// Varias personas, cada una con su parte; las partes suman la cantidad.
  split,
}

enum PurchaseStep { items, review }

/// Catálogos del formulario de compra.
typedef PurchaseCatalogs = ({
  List<Map<String, Object?>> suppliers,
  List<Map<String, Object?>> campaigns,
  List<Map<String, Object?>> products,
  List<Map<String, Object?>> people,
});

const Object _absent = Object();

class AllocationLineData {
  const AllocationLineData({
    required this.id,
    this.personId,
    this.quantityText = '',
    this.quantityError,
  });

  final int id;
  final int? personId;
  final String quantityText;

  /// Mensaje de formato de la cantidad (`parseNumericInput`), fijado al
  /// validar y borrado al editar el campo.
  final String? quantityError;

  AllocationLineData copyWith({
    Object? personId = _absent,
    String? quantityText,
    Object? quantityError = _absent,
  }) => AllocationLineData(
    id: id,
    personId: identical(personId, _absent) ? this.personId : personId as int?,
    quantityText: quantityText ?? this.quantityText,
    quantityError: identical(quantityError, _absent)
        ? this.quantityError
        : quantityError as String?,
  );
}

class PurchaseLineData {
  const PurchaseLineData({
    required this.id,
    this.productId,
    this.currency = CurrencyCode.bob,
    this.quantityText = '',
    this.priceText = '',
    this.fxText = '',
    this.expiryDay,
    this.lotNumberText = '',
    this.quantityError,
    this.priceError,
    this.fxError,
    this.allocationMode,
    this.singlePersonId,
    this.allocations = const [],
  });

  /// Identificador estable de la línea (no su posición): lo usa el dictado
  /// para saber qué línea completó o añadió.
  final int id;
  final int? productId;
  final CurrencyCode currency;
  final String quantityText;
  final String priceText;
  final String fxText;

  /// Vencimiento (día civil) y número de lote, opcionales (F04-AV, RF-42).
  /// Sin elegir: se guarda «sin fecha registrada», nunca una fecha supuesta.
  final String? expiryDay;
  final String lotNumberText;

  /// Mensajes de formato por campo, fijados al validar (B-11).
  final String? quantityError;
  final String? priceError;
  final String? fxError;

  /// Decisión explícita de destinatario (compartido). Nula hasta elegir.
  final AllocationMode? allocationMode;

  /// Destinatario único con «Toda para una persona». Sin valor por defecto.
  final int? singlePersonId;

  /// Filas de «Repartir entre varias». Vacía hasta que se elige repartir.
  final List<AllocationLineData> allocations;

  /// Número de lote sin espacios a los lados; vacío es «sin dato».
  String? get lotNumberValue {
    final text = lotNumberText.trim();
    return text.isEmpty ? null : text;
  }

  int get quantityBase {
    final value = tryParseBase(quantityText) ?? 0;
    return value > 0 ? value : 0;
  }

  int get priceMinor {
    final value = tryParseMinor(priceText) ?? 0;
    return value > 0 ? value : 0;
  }

  int? get exchangeRateScaled => currency == CurrencyCode.usd
      ? (((tryParseDecimal(fxText) ?? 0) > 0
                    ? (tryParseDecimal(fxText) ?? 0)
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
    (sum, allocation) => sum + (tryParseBase(allocation.quantityText) ?? 0),
  );

  bool isBlank({required bool touchedByVoice}) =>
      productId == null &&
      quantityText.trim().isEmpty &&
      priceText.trim().isEmpty &&
      fxText.trim().isEmpty &&
      currency == CurrencyCode.bob &&
      allocationMode == null &&
      expiryDay == null &&
      lotNumberText.trim().isEmpty &&
      !touchedByVoice;

  /// Valores canónicos de la línea para el dictado (`null` = vacío).
  Map<String, Object?> voiceFields(bool shared) {
    Object? canon(String text, int? Function(String) parse) {
      final t = text.trim();
      if (t.isEmpty) return null;
      return parse(t) ?? 'texto:$t';
    }

    final price = canon(priceText, tryParseMinor);
    return {
      'product': productId,
      'quantity': canon(quantityText, tryParseBase),
      'price': price,
      // La moneda viene puesta (BOB) en toda línea nueva: sólo cuenta como
      // dato cuando hay precio o cuando es otra (dólares elegidos a mano o
      // dictados con el precio por revisar). Así lo que puso la voz coincide
      // con lo que se ve y «Deshacer» puede devolverla (2026-11-12).
      'currency': price == null && currency == CurrencyCode.bob
          ? null
          : currency,
      'fx': currency == CurrencyCode.usd
          ? canon(fxText, (t) {
              final v = tryParseDecimal(t);
              return v == null ? null : (v * fxScale).round();
            })
          : null,
      if (shared)
        'recipient': switch (allocationMode) {
          null => null,
          AllocationMode.single => singlePersonId,
          AllocationMode.split => 'split',
        },
    };
  }

  PurchaseLineData clearErrors() => copyWith(
    quantityError: null,
    priceError: null,
    fxError: null,
    allocations: [
      for (final allocation in allocations)
        allocation.copyWith(quantityError: null),
    ],
  );

  PurchaseLineData copyWith({
    Object? productId = _absent,
    CurrencyCode? currency,
    String? quantityText,
    String? priceText,
    String? fxText,
    Object? expiryDay = _absent,
    String? lotNumberText,
    Object? quantityError = _absent,
    Object? priceError = _absent,
    Object? fxError = _absent,
    Object? allocationMode = _absent,
    Object? singlePersonId = _absent,
    List<AllocationLineData>? allocations,
  }) => PurchaseLineData(
    id: id,
    productId: identical(productId, _absent)
        ? this.productId
        : productId as int?,
    currency: currency ?? this.currency,
    quantityText: quantityText ?? this.quantityText,
    priceText: priceText ?? this.priceText,
    fxText: fxText ?? this.fxText,
    expiryDay: identical(expiryDay, _absent)
        ? this.expiryDay
        : expiryDay as String?,
    lotNumberText: lotNumberText ?? this.lotNumberText,
    quantityError: identical(quantityError, _absent)
        ? this.quantityError
        : quantityError as String?,
    priceError: identical(priceError, _absent)
        ? this.priceError
        : priceError as String?,
    fxError: identical(fxError, _absent) ? this.fxError : fxError as String?,
    allocationMode: identical(allocationMode, _absent)
        ? this.allocationMode
        : allocationMode as AllocationMode?,
    singlePersonId: identical(singlePersonId, _absent)
        ? this.singlePersonId
        : singlePersonId as int?,
    allocations: allocations ?? this.allocations,
  );
}

class PurchaseFormState {
  const PurchaseFormState({
    this.catalogs,
    this.catalogsError,
    this.nextLineId = 2,
    this.nextAllocationId = 1,
    this.lines = const [PurchaseLineData(id: 1)],
    this.invoiceNumber = '',
    this.notes = '',
    this.editingLineId,
    this.problemLineId,
    this.lineProblem,
    this.showVoice = false,
    this.voiceBanner = false,
    this.seenCompletions = 0,
    this.supplierId,
    this.campaignId,
    this.step = PurchaseStep.items,
    required this.effectiveDay,
    this.paidInFull,
    this.paymentMethod = PaymentMethod.unspecified,
    this.paymentDay,
    this.loadedMode,
    this.ownerPersonId,
    this.personalOwnerId,
    this.invoiceImage,
    this.saving = false,
    this.dirty = false,
  });

  factory PurchaseFormState.initial() =>
      PurchaseFormState(effectiveDay: localDay(DateTime.now()));

  final PurchaseCatalogs? catalogs;
  final Object? catalogsError;
  final int nextLineId;
  final int nextAllocationId;
  final List<PurchaseLineData> lines;
  final String invoiceNumber;
  final String notes;
  final int? editingLineId;
  final int? problemLineId;
  final String? lineProblem;
  final bool showVoice;
  final bool voiceBanner;
  final int seenCompletions;
  final int? supplierId;
  final int? campaignId;
  final PurchaseStep step;
  final String effectiveDay;
  final bool? paidInFull;
  final PaymentMethod paymentMethod;
  final String? paymentDay;
  final OperationMode? loadedMode;
  final int? ownerPersonId;
  final int? personalOwnerId;
  final XFile? invoiceImage;
  final bool saving;
  final bool dirty;

  String get effectivePaymentDay => paymentDay ?? effectiveDay;

  int get totalBob => lines.fold(0, (sum, line) => sum + line.subtotalBob);

  PurchaseLineData? get editingLine =>
      lines.where((line) => line.id == editingLineId).firstOrNull;

  List<Map<String, Object?>> get products => catalogs?.products ?? const [];

  bool canCreatePeople(OperationMode? currentMode) =>
      loadedMode != null &&
      loadedMode != OperationMode.personal &&
      !modeChangedSince(loadedMode, currentMode);

  Map<String, Object?>? productOf(int? id) =>
      products.where((row) => row['id'] == id).firstOrNull;

  String productName(int? id) => productOf(id)?['name']?.toString() ?? '';

  String personName(int? id) =>
      catalogs?.people
          .where((person) => person['id'] == id)
          .firstOrNull?['name']
          ?.toString() ??
      '';

  String? ownerName() => catalogs?.people
      .where((row) => row['id'] == ownerPersonId)
      .firstOrNull?['name']
      ?.toString();

  /// Rótulo secundario de una persona: el titular se dice «Titular»; los
  /// demás, su rol («Familiar», «Tercero»). Nunca «Titular · Familiar».
  String personRole(Map<String, Object?> person) => personRoleLabel(
    person['role'],
    isOwner: ownerPersonId != null && person['id'] == ownerPersonId,
  );

  PurchaseFormState copyWith({
    Object? catalogs = _absent,
    Object? catalogsError = _absent,
    int? nextLineId,
    int? nextAllocationId,
    List<PurchaseLineData>? lines,
    String? invoiceNumber,
    String? notes,
    Object? editingLineId = _absent,
    Object? problemLineId = _absent,
    Object? lineProblem = _absent,
    bool? showVoice,
    bool? voiceBanner,
    int? seenCompletions,
    Object? supplierId = _absent,
    Object? campaignId = _absent,
    PurchaseStep? step,
    String? effectiveDay,
    Object? paidInFull = _absent,
    PaymentMethod? paymentMethod,
    Object? paymentDay = _absent,
    Object? loadedMode = _absent,
    Object? ownerPersonId = _absent,
    Object? personalOwnerId = _absent,
    Object? invoiceImage = _absent,
    bool? saving,
    bool? dirty,
  }) => PurchaseFormState(
    catalogs: identical(catalogs, _absent)
        ? this.catalogs
        : catalogs as PurchaseCatalogs?,
    catalogsError: identical(catalogsError, _absent)
        ? this.catalogsError
        : catalogsError,
    nextLineId: nextLineId ?? this.nextLineId,
    nextAllocationId: nextAllocationId ?? this.nextAllocationId,
    lines: lines ?? this.lines,
    invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    notes: notes ?? this.notes,
    editingLineId: identical(editingLineId, _absent)
        ? this.editingLineId
        : editingLineId as int?,
    problemLineId: identical(problemLineId, _absent)
        ? this.problemLineId
        : problemLineId as int?,
    lineProblem: identical(lineProblem, _absent)
        ? this.lineProblem
        : lineProblem as String?,
    showVoice: showVoice ?? this.showVoice,
    voiceBanner: voiceBanner ?? this.voiceBanner,
    seenCompletions: seenCompletions ?? this.seenCompletions,
    supplierId: identical(supplierId, _absent)
        ? this.supplierId
        : supplierId as int?,
    campaignId: identical(campaignId, _absent)
        ? this.campaignId
        : campaignId as int?,
    step: step ?? this.step,
    effectiveDay: effectiveDay ?? this.effectiveDay,
    paidInFull: identical(paidInFull, _absent)
        ? this.paidInFull
        : paidInFull as bool?,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    paymentDay: identical(paymentDay, _absent)
        ? this.paymentDay
        : paymentDay as String?,
    loadedMode: identical(loadedMode, _absent)
        ? this.loadedMode
        : loadedMode as OperationMode?,
    ownerPersonId: identical(ownerPersonId, _absent)
        ? this.ownerPersonId
        : ownerPersonId as int?,
    personalOwnerId: identical(personalOwnerId, _absent)
        ? this.personalOwnerId
        : personalOwnerId as int?,
    invoiceImage: identical(invoiceImage, _absent)
        ? this.invoiceImage
        : invoiceImage as XFile?,
    saving: saving ?? this.saving,
    dirty: dirty ?? this.dirty,
  );
}

/// «Hoy, 12/11/2026» o la fecha a secas.
String purchaseDayLabel(String day) => day == localDay(DateTime.now())
    ? 'Hoy, ${formatDate(day)}'
    : formatDate(day);

/// Vencimiento y número de lote del envase de una línea, en palabras, para
/// los resúmenes.
String? lotDataSummary(PurchaseLineData line) {
  final parts = [
    if (line.expiryDay != null) 'Vence el ${displayDay(line.expiryDay!)}',
    if (line.lotNumberValue != null) packageLotText(line.lotNumberValue!),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// «Lote del fabricante: GL-2611-07»: el número que escribió la persona, tal
/// como figura en el envase (el del fabricante), nunca uno generado.
String packageLotText(String number) => 'Lote del fabricante: $number';

/// Contador del número de lote en caracteres Unicode, como los cuenta el
/// repositorio.
String lotNumberCounter(String text) =>
    '${text.trim().runes.length}/$repositoryMaxLotNumberLength';

/// Controladores de los campos de texto de una línea de compra.
class PurchaseLineControllers {
  PurchaseLineControllers({
    String quantity = '',
    String price = '',
    String fx = '',
    String lotNumber = '',
  }) : quantity = TextEditingController(text: quantity),
       price = TextEditingController(text: price),
       fx = TextEditingController(text: fx),
       lotNumber = TextEditingController(text: lotNumber);

  final TextEditingController quantity;
  final TextEditingController price;
  final TextEditingController fx;
  final TextEditingController lotNumber;
  final Map<int, TextEditingController> _allocations = {};

  TextEditingController allocationQuantity(int allocId, String initialText) =>
      _allocations.putIfAbsent(
        allocId,
        () => TextEditingController(text: initialText),
      );

  List<TextEditingController> detachRemovedAllocations(Set<int> activeIds) {
    final removed = <TextEditingController>[];
    _allocations.removeWhere((id, controller) {
      if (activeIds.contains(id)) return false;
      removed.add(controller);
      return true;
    });
    return removed;
  }

  void dispose() {
    quantity.dispose();
    price.dispose();
    fx.dispose();
    lotNumber.dispose();
    for (final controller in _allocations.values) {
      controller.dispose();
    }
    _allocations.clear();
  }
}

/// Dueño único de todos los [TextEditingController] del formulario para
/// garantizar su liberación sincronizada en `dispose` y tras eliminar filas.
class PurchaseFormControllers {
  final invoiceNumber = TextEditingController();
  final notes = TextEditingController();
  final Map<int, PurchaseLineControllers> _lines = {};
  final List<TextEditingController> _pendingDispose = [];

  PurchaseLineControllers line(PurchaseLineData data) => _lines.putIfAbsent(
    data.id,
    () => PurchaseLineControllers(
      quantity: data.quantityText,
      price: data.priceText,
      fx: data.fxText,
      lotNumber: data.lotNumberText,
    ),
  );

  void syncFromVoice(PurchaseFormState state) {
    detachRemoved(state);
    for (final item in state.lines) {
      final ctrl = line(item);
      if (ctrl.quantity.text != item.quantityText) {
        ctrl.quantity.text = item.quantityText;
      }
      if (ctrl.price.text != item.priceText) {
        ctrl.price.text = item.priceText;
      }
      if (ctrl.fx.text != item.fxText) {
        ctrl.fx.text = item.fxText;
      }
    }
  }

  void detachRemoved(PurchaseFormState state) {
    final lineIds = {for (final l in state.lines) l.id};
    final removedLines = <PurchaseLineControllers>[];
    _lines.removeWhere((id, ctrl) {
      if (lineIds.contains(id)) return false;
      removedLines.add(ctrl);
      return true;
    });
    var queued = removedLines.isNotEmpty;
    for (final item in state.lines) {
      final ctrl = _lines[item.id];
      if (ctrl == null) continue;
      final allocIds = {for (final a in item.allocations) a.id};
      final detached = ctrl.detachRemovedAllocations(allocIds);
      if (detached.isNotEmpty) {
        _pendingDispose.addAll(detached);
        queued = true;
      }
    }
    for (final ctrl in removedLines) {
      ctrl.dispose();
    }
    if (queued && _pendingDispose.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => disposePending());
    }
  }

  void disposePending() {
    for (final controller in _pendingDispose) {
      controller.dispose();
    }
    _pendingDispose.clear();
  }

  void disposeAll() {
    invoiceNumber.dispose();
    notes.dispose();
    for (final ctrl in _lines.values) {
      ctrl.dispose();
    }
    _lines.clear();
    disposePending();
  }
}
