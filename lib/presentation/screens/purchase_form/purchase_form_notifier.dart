import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../local_data_providers.dart' show repositoryProvider;
import '../../../domain/campaign_calendar.dart';
import '../../../domain/models.dart';
import '../../../domain/money.dart';
import '../../../domain/operation_mode.dart';
import '../../../domain/person_roles.dart';
import '../../../domain/repository_types.dart'
    show repositoryLotNumberLengthError;
import '../../voice/voice_form_dictation.dart';
import '../../widgets/common.dart';
import 'purchase_form_state.dart';

enum PurchaseSaveStatus { confirmed, lateCaptured, aborted, validationError }

typedef PurchaseSaveResult = ({
  PurchaseSaveStatus status,
  String? errorMessage,
  Object? error,
});

typedef LatePurchaseOffer = Future<bool> Function(
  PurchaseDraft draft,
  Object error,
  bool paid,
);

class PurchaseFormNotifier extends Notifier<PurchaseFormState> {
  int _catalogGeneration = 0;

  @override
  PurchaseFormState build() {
    Future.microtask(loadCatalogs);
    return PurchaseFormState.initial();
  }

  Future<void> loadCatalogs() async {
    final generation = ++_catalogGeneration;
    try {
      final repo = ref.read(repositoryProvider);
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
      if (!ref.mounted || generation != _catalogGeneration) return;
      final active = result[1].where((row) => row['status'] == 'ACTIVE');
      final loaded = (
        suppliers: result[0],
        campaigns: result[1],
        products: result[2],
        people: result[3],
      );
      state = state.copyWith(
        catalogs: loaded,
        catalogsError: null,
        campaignId: active.isEmpty ? null : active.first['id'] as int,
        loadedMode: operating.mode,
        ownerPersonId: operating.ownerPersonId,
        personalOwnerId: operating.mode == OperationMode.personal
            ? operating.ownerPersonId
            : null,
      );
    } catch (error) {
      if (!ref.mounted || generation != _catalogGeneration) return;
      state = state.copyWith(catalogsError: error);
    }
  }

  Future<PurchaseCatalogs?> reloadCatalogs({bool people = false}) async {
    final current = state.catalogs;
    if (current == null) return null;
    final repo = ref.read(repositoryProvider);
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
    if (!ref.mounted) return next;
    state = state.copyWith(catalogs: next);
    return next;
  }

  void setSupplier(int? value) {
    final suppliers = state.catalogs?.suppliers ?? const [];
    final autoSelected =
        state.supplierId == null &&
        suppliers.length == 1 &&
        value == suppliers.single['id'];
    state = state.copyWith(
      supplierId: value,
      dirty: autoSelected ? state.dirty : true,
    );
  }

  void setEffectiveDay(String day) {
    state = state.copyWith(effectiveDay: day, dirty: true);
  }

  void setCampaignId(int? value) {
    state = state.copyWith(campaignId: value, dirty: true);
  }

  void setPaidInFull(bool value) {
    state = state.copyWith(paidInFull: value, dirty: true);
  }

  void setPaymentMethod(PaymentMethod method) {
    state = state.copyWith(paymentMethod: method, dirty: true);
  }

  void setPaymentDay(String? day) {
    state = state.copyWith(paymentDay: day, dirty: true);
  }

  void setInvoiceNumber(String text) {
    state = state.copyWith(invoiceNumber: text, dirty: true, lineProblem: null);
  }

  void setNotes(String text) {
    state = state.copyWith(notes: text, dirty: true, lineProblem: null);
  }

  void setInvoiceImage(XFile image) {
    state = state.copyWith(invoiceImage: image, dirty: true);
  }

  void clearDirty() {
    state = state.copyWith(dirty: false);
  }

  void openVoicePanel() {
    state = state.copyWith(
      showVoice: true,
      voiceBanner: false,
      editingLineId: null,
    );
  }

  void hideVoicePanel() {
    state = state.copyWith(showVoice: false);
  }

  void dismissVoiceBanner() {
    state = state.copyWith(voiceBanner: false);
  }

  void syncVoiceCompletion(int completions) {
    if (completions == state.seenCompletions) return;
    state = state.copyWith(
      seenCompletions: completions,
      showVoice: false,
      voiceBanner: true,
    );
  }

  void openLine(int id) {
    state = state.copyWith(editingLineId: id, lineProblem: null);
  }

  void closeLine() {
    state = state.copyWith(editingLineId: null, lineProblem: null);
  }

  void addLine({required bool touchedByVoice}) {
    if (state.lines.length == 1 &&
        state.lines.single.isBlank(touchedByVoice: touchedByVoice)) {
      openLine(state.lines.single.id);
      return;
    }
    appendLine();
  }

  void appendLine() {
    final id = state.nextLineId;
    state = state.copyWith(
      nextLineId: id + 1,
      lines: [
        ...state.lines,
        PurchaseLineData(id: id),
      ],
      dirty: true,
      editingLineId: id,
      lineProblem: null,
    );
  }

  void removeLine(int id) {
    final remaining = state.lines.where((l) => l.id != id).toList();
    state = state.copyWith(
      lines: remaining,
      dirty: true,
      editingLineId: null,
      lineProblem: null,
    );
  }

  void _updateLine(
    int lineId,
    PurchaseLineData Function(PurchaseLineData line) transform, {
    bool dirty = true,
  }) {
    state = state.copyWith(
      lines: [
        for (final line in state.lines)
          if (line.id == lineId) transform(line) else line,
      ],
      dirty: dirty ? true : state.dirty,
      lineProblem: dirty ? null : state.lineProblem,
    );
  }

  void setLineProduct(int lineId, int? productId) {
    _updateLine(lineId, (l) => l.copyWith(productId: productId));
  }

  void setLineQuantity(int lineId, String text) {
    _updateLine(
      lineId,
      (l) => l.copyWith(quantityText: text, quantityError: null),
    );
  }

  void setLinePrice(int lineId, String text) {
    _updateLine(lineId, (l) => l.copyWith(priceText: text, priceError: null));
  }

  void setLineCurrency(int lineId, CurrencyCode currency) {
    _updateLine(lineId, (l) => l.copyWith(currency: currency));
  }

  void setLineFx(int lineId, String text) {
    _updateLine(lineId, (l) => l.copyWith(fxText: text, fxError: null));
  }

  void setLineExpiry(int lineId, String? day) {
    _updateLine(lineId, (l) => l.copyWith(expiryDay: day));
  }

  void setLineLotNumber(int lineId, String text) {
    _updateLine(lineId, (l) => l.copyWith(lotNumberText: text));
  }

  void setLineAllocationMode(int lineId, AllocationMode mode) {
    final current = state.lines.where((l) => l.id == lineId).firstOrNull;
    if (current == null || current.allocationMode == mode) return;
    if (mode == AllocationMode.single) {
      _updateLine(
        lineId,
        (l) => l.copyWith(
          allocationMode: AllocationMode.single,
          allocations: const [],
        ),
      );
      return;
    }
    var allocId = state.nextAllocationId;
    final nextAllocs = List.of(current.allocations);
    while (nextAllocs.length < 2) {
      nextAllocs.add(AllocationLineData(id: allocId++));
    }
    state = state.copyWith(
      nextAllocationId: allocId,
      lines: [
        for (final line in state.lines)
          if (line.id == lineId)
            line.copyWith(
              allocationMode: AllocationMode.split,
              singlePersonId: null,
              allocations: nextAllocs,
            )
          else
            line,
      ],
      dirty: true,
      lineProblem: null,
    );
  }

  void setLineSinglePerson(int lineId, int? personId) {
    _updateLine(lineId, (l) => l.copyWith(singlePersonId: personId));
  }

  void addAllocationRow(int lineId) {
    final allocId = state.nextAllocationId;
    state = state.copyWith(
      nextAllocationId: allocId + 1,
      lines: [
        for (final line in state.lines)
          if (line.id == lineId)
            line.copyWith(
              allocations: [
                ...line.allocations,
                AllocationLineData(id: allocId),
              ],
            )
          else
            line,
      ],
      dirty: true,
      lineProblem: null,
    );
  }

  void removeAllocationRow(int lineId, int allocId) {
    _updateLine(
      lineId,
      (l) => l.copyWith(
        allocations: l.allocations.where((a) => a.id != allocId).toList(),
      ),
    );
  }

  void setAllocationPerson(int lineId, int allocId, int? personId) {
    _updateLine(
      lineId,
      (l) => l.copyWith(
        allocations: [
          for (final a in l.allocations)
            if (a.id == allocId) a.copyWith(personId: personId) else a,
        ],
      ),
    );
  }

  void setAllocationQuantity(int lineId, int allocId, String text) {
    _updateLine(
      lineId,
      (l) => l.copyWith(
        allocations: [
          for (final a in l.allocations)
            if (a.id == allocId)
              a.copyWith(quantityText: text, quantityError: null)
            else
              a,
        ],
      ),
    );
  }

  void backToItems() {
    state = state.copyWith(step: PurchaseStep.items);
  }

  /// Comprueba el paso 1 y devuelve el primer problema, si existe.
  ({bool valid, int? problemLineId, String? message}) validateItems() {
    final updatedLines = [for (final l in state.lines) l.clearErrors()];
    final check = _findFirstProblem(updatedLines);
    final problemLine = check.problem == null ? null : check.lineId;
    state = state.copyWith(
      lines: updatedLines,
      problemLineId: problemLine,
      lineProblem: problemLine == null ? null : check.problem,
      editingLineId: problemLine ?? state.editingLineId,
    );
    if (check.problem != null) {
      return (valid: false, problemLineId: problemLine, message: check.problem);
    }
    return const (valid: true, problemLineId: null, message: null);
  }

  ({String? problem, int? lineId}) _findFirstProblem(
    List<PurchaseLineData> lines,
  ) {
    if (state.supplierId == null) {
      return (problem: 'Elija el proveedor.', lineId: null);
    }
    if (lines.isEmpty) {
      return (problem: 'Añada al menos un producto.', lineId: null);
    }
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.productId == null) {
        return (
          problem: 'Elija el producto de la línea ${index + 1}.',
          lineId: line.id,
        );
      }
      final name = state.productName(line.productId);
      final lineResult = _validateLineNumbers(line, name);
      if (lineResult.problem != null) {
        lines[index] = lineResult.line;
        return (problem: lineResult.problem, lineId: line.id);
      }
      final lotError = repositoryLotNumberLengthError(line.lotNumberText);
      if (lotError != null) {
        return (problem: '$name: $lotError', lineId: line.id);
      }
      if (state.personalOwnerId != null) continue;
      final allocResult = _validateAllocations(line, name);
      if (allocResult.problem != null) {
        lines[index] = allocResult.line;
        return (problem: allocResult.problem, lineId: line.id);
      }
    }
    return const (problem: null, lineId: null);
  }

  ({PurchaseLineData line, String? problem}) _validateLineNumbers(
    PurchaseLineData line,
    String name,
  ) {
    final quantity = parseNumericInput(line.quantityText);
    switch (quantity.status) {
      case NumericInputStatus.empty:
        return (line: line, problem: 'Escriba la cantidad comprada de $name.');
      case NumericInputStatus.ambiguous:
      case NumericInputStatus.malformed:
        return (
          line: line.copyWith(quantityError: quantity.message),
          problem: 'Revise la cantidad comprada de $name.',
        );
      case NumericInputStatus.valid:
        if (line.quantityBase <= 0) {
          return (
            line: line,
            problem: 'La cantidad comprada de $name debe ser mayor que cero.',
          );
        }
    }

    final price = parseNumericInput(line.priceText);
    switch (price.status) {
      case NumericInputStatus.empty:
        return (line: line, problem: 'Escriba el precio de $name.');
      case NumericInputStatus.ambiguous:
      case NumericInputStatus.malformed:
        return (
          line: line.copyWith(priceError: price.message),
          problem: 'Revise el precio de $name.',
        );
      case NumericInputStatus.valid:
        if (line.priceMinor <= 0) {
          return (
            line: line,
            problem: 'El precio de $name debe ser mayor que cero.',
          );
        }
    }

    if (line.currency == CurrencyCode.usd) {
      final fx = parseNumericInput(line.fxText);
      switch (fx.status) {
        case NumericInputStatus.empty:
          return (line: line, problem: 'Escriba el tipo de cambio de $name.');
        case NumericInputStatus.ambiguous:
        case NumericInputStatus.malformed:
          return (
            line: line.copyWith(fxError: fx.message),
            problem: 'Revise el tipo de cambio de $name.',
          );
        case NumericInputStatus.valid:
          if ((line.exchangeRateScaled ?? 0) <= 0) {
            return (
              line: line,
              problem: 'El tipo de cambio de $name debe ser mayor que cero.',
            );
          }
      }
    }
    return (line: line, problem: null);
  }

  ({PurchaseLineData line, String? problem}) _validateAllocations(
    PurchaseLineData line,
    String name,
  ) {
    switch (line.allocationMode) {
      case null:
        return (
          line: line,
          problem:
              'Indique para quién es $name: toda para una persona o '
              'repartida entre varias.',
        );
      case AllocationMode.single:
        if (line.singlePersonId == null) {
          return (line: line, problem: 'Elija para quién es $name.');
        }
      case AllocationMode.split:
        final allocs = List.of(line.allocations);
        for (var i = 0; i < allocs.length; i++) {
          final allocation = allocs[i];
          if (allocation.personId == null) {
            return (
              line: line,
              problem: 'Elija la persona de cada parte de $name.',
            );
          }
          final part = parseNumericInput(allocation.quantityText);
          switch (part.status) {
            case NumericInputStatus.empty:
              return (
                line: line,
                problem: 'Escriba la cantidad de cada parte de $name.',
              );
            case NumericInputStatus.ambiguous:
            case NumericInputStatus.malformed:
              allocs[i] = allocation.copyWith(quantityError: part.message);
              return (
                line: line.copyWith(allocations: allocs),
                problem: 'Revise las cantidades repartidas de $name.',
              );
            case NumericInputStatus.valid:
              if ((part.value ?? 0) <= 0) {
                return (
                  line: line,
                  problem: 'Cada parte de $name debe ser mayor que cero.',
                );
              }
          }
        }
        final people = allocs.map((a) => a.personId).toList();
        if (people.toSet().length != people.length) {
          return (
            line: line,
            problem:
                'La misma persona aparece dos veces en el reparto de $name.',
          );
        }
        if (line.assignedBase != line.quantityBase) {
          return (
            line: line,
            problem: line.assignedBase > line.quantityBase
                ? 'Lo repartido supera la cantidad comprada de $name.'
                : 'Falta repartir parte de la cantidad de $name.',
          );
        }
    }
    return (line: line, problem: null);
  }

  ({bool ok, String? errorMessage}) tryGoToReview() {
    final result = validateItems();
    if (!result.valid) {
      return (
        ok: false,
        errorMessage: result.problemLineId == null ? result.message : null,
      );
    }
    state = state.copyWith(step: PurchaseStep.review);
    return const (ok: true, errorMessage: null);
  }

  List<AllocationDraft> _allocationsOf(PurchaseLineData line) {
    final owner = state.personalOwnerId;
    if (owner != null) {
      return [
        AllocationDraft(personId: owner, quantityBase: line.quantityBase),
      ];
    }
    return switch (line.allocationMode) {
      AllocationMode.single => [
        AllocationDraft(
          personId: line.singlePersonId!,
          quantityBase: line.quantityBase,
        ),
      ],
      AllocationMode.split => [
        for (final allocation in line.allocations)
          AllocationDraft(
            personId: allocation.personId!,
            quantityBase: tryParseBase(allocation.quantityText) ?? 0,
          ),
      ],
      null => const [],
    };
  }

  Future<PurchaseSaveResult> confirmPurchase({
    required LatePurchaseOffer onLateOffer,
  }) async {
    if (state.saving) {
      return const (
        status: PurchaseSaveStatus.aborted,
        errorMessage: null,
        error: null,
      );
    }
    final check = validateItems();
    if (!check.valid) {
      state = state.copyWith(step: PurchaseStep.items);
      return (
        status: PurchaseSaveStatus.validationError,
        errorMessage: check.problemLineId == null ? check.message : null,
        error: null,
      );
    }
    if (state.campaignId == null) {
      return const (
        status: PurchaseSaveStatus.validationError,
        errorMessage:
            'No hay una campaña activa. Actívela en Inicio › Ajustes y datos › '
            'Campañas.',
        error: null,
      );
    }
    final paid = state.paidInFull;
    if (paid == null) {
      return const (
        status: PurchaseSaveStatus.validationError,
        errorMessage: 'Indique si ya pagó al proveedor.',
        error: null,
      );
    }
    if (paid && state.ownerPersonId == null) {
      return const (
        status: PurchaseSaveStatus.validationError,
        errorMessage:
            'No hay un titular vinculado: la compra no puede quedar pagada.',
        error: null,
      );
    }

    state = state.copyWith(saving: true);
    final repo = ref.read(repositoryProvider);
    PurchaseDraft? draft;
    var done = false;
    try {
      final imagePath = state.invoiceImage == null
          ? null
          : await repo.storeInvoiceImage(state.invoiceImage!.path);
      draft = PurchaseDraft(
        supplierId: state.supplierId!,
        campaignId: state.campaignId!,
        purchaseDate: effectiveInstantForDay(
          state.effectiveDay,
          DateTime.now(),
        ),
        invoiceNumber: state.invoiceNumber.trim(),
        invoiceImagePath: imagePath,
        notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        exchangeRateSource:
            state.lines.any((line) => line.currency == CurrencyCode.usd)
            ? ExchangeRateSource.agreedWithSupplier
            : null,
        items: [
          for (final line in state.lines)
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
      await repo.confirmPurchase(
        draft,
        paidInFull: paid
            ? ProviderPaymentDetails(
                method: state.paymentMethod,
                date: effectiveInstantForDay(
                  state.effectivePaymentDay,
                  DateTime.now(),
                ),
              )
            : null,
      );
      done = true;
      if (ref.mounted) state = state.copyWith(dirty: false);
      return const (
        status: PurchaseSaveStatus.confirmed,
        errorMessage: null,
        error: null,
      );
    } catch (error) {
      final late = draft;
      if (late != null && await onLateOffer(late, error, paid)) {
        done = true;
        if (ref.mounted) state = state.copyWith(dirty: false);
        return const (
          status: PurchaseSaveStatus.lateCaptured,
          errorMessage: null,
          error: null,
        );
      }
      return (
        status: PurchaseSaveStatus.aborted,
        errorMessage: null,
        error: error,
      );
    } finally {
      if (ref.mounted && !done) {
        state = state.copyWith(saving: false);
      }
    }
  }

  // --- Dictado por voz ----------------------------------------------------

  void applyVoicePlan(MergePlan plan) {
    final lines = List.of(state.lines);
    var supplierId = state.supplierId;
    var nextLineId = state.nextLineId;

    void applySlot(SlotRef slot, Object? value) {
      if (slot.line == null) {
        if (slot.field == 'supplier') supplierId = value as int?;
        return;
      }
      final idx = lines.indexWhere((l) => l.id == slot.line);
      if (idx >= 0) {
        lines[idx] = _applySlotToLine(lines[idx], slot.field, value);
      }
    }

    for (final c in plan.changes) {
      applySlot(c.slot, c.after);
    }
    for (final n in plan.newLines) {
      var line = PurchaseLineData(id: n.line);
      if (n.line >= nextLineId) nextLineId = n.line + 1;
      n.values.forEach((field, value) {
        line = _applySlotToLine(line, field, value);
      });
      lines.add(line);
    }
    state = state.copyWith(
      supplierId: supplierId,
      nextLineId: nextLineId,
      lines: lines,
      dirty: plan.changesNothing ? state.dirty : true,
    );
  }

  void applyVoiceUndo(UndoPlan plan) {
    var lines = List.of(state.lines);
    var supplierId = state.supplierId;
    var nextLineId = state.nextLineId;

    for (final c in plan.restore) {
      if (c.slot.line == null) {
        if (c.slot.field == 'supplier') supplierId = c.after as int?;
      } else {
        final idx = lines.indexWhere((l) => l.id == c.slot.line);
        if (idx >= 0) {
          lines[idx] = _applySlotToLine(lines[idx], c.slot.field, c.after);
        }
      }
    }
    if (plan.removeLines.isNotEmpty) {
      final removed = plan.removeLines.toSet();
      lines = lines.where((l) => !removed.contains(l.id)).toList();
    }
    if (lines.isEmpty) {
      lines.add(PurchaseLineData(id: nextLineId++));
    }
    state = state.copyWith(
      supplierId: supplierId,
      nextLineId: nextLineId,
      lines: lines,
    );
  }

  void setVoiceSlot(SlotRef slot, Object? value) {
    if (slot.line == null) {
      if (slot.field == 'supplier') {
        state = state.copyWith(supplierId: value as int?, dirty: true);
      }
      return;
    }
    _updateLine(
      slot.line!,
      (line) => _applySlotToLine(line, slot.field, value),
    );
  }

  PurchaseLineData _applySlotToLine(
    PurchaseLineData line,
    String field,
    Object? value,
  ) => switch (field) {
    'product' => line.copyWith(productId: value as int?),
    'quantity' => line.copyWith(
      quantityText: value == null
          ? ''
          : formatForInput((value as int) / baseUnitsPerMajor),
      quantityError: null,
    ),
    'price' => line.copyWith(
      priceText: value == null
          ? ''
          : formatForInput((value as int) / 100, maxDecimals: 2),
      priceError: null,
    ),
    'currency' => line.copyWith(
      currency: (value as CurrencyCode?) ?? CurrencyCode.bob,
    ),
    'fx' => line.copyWith(
      fxText: value == null
          ? ''
          : formatForInput((value as int) / fxScale, maxDecimals: 6),
      fxError: null,
    ),
    'recipient' =>
      value is int
          ? line.copyWith(
              allocationMode: AllocationMode.single,
              singlePersonId: value,
            )
          : value == null
          ? line.copyWith(allocationMode: null, singlePersonId: null)
          : line,
    _ => line,
  };
}

final purchaseFormProvider = NotifierProvider.autoDispose
    .family<PurchaseFormNotifier, PurchaseFormState, Object>(
      (_) => PurchaseFormNotifier(),
    );
