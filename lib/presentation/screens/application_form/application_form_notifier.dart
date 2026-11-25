import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../domain/campaign_calendar.dart';
import '../../../domain/models.dart';
import '../../../domain/money.dart';
import '../../../domain/operation_mode.dart';
import '../../../domain/person_roles.dart';
import '../../../domain/repository_exceptions.dart';
import '../../../domain/repository_types.dart' show ApplicationLotPreview;
import '../../voice/voice_form_dictation.dart';
import '../../widgets/common.dart';
import 'application_form_state.dart';

enum ApplicationSaveStatus { confirmed, lateCaptured, aborted, validationError }

typedef ApplicationSaveResult = ({
  ApplicationSaveStatus status,
  String? errorMessage,
  Object? error,
});

typedef LateApplicationOffer = Future<bool> Function(
  ApplicationDraft application,
  Object error,
);

class ApplicationFormNotifier extends Notifier<ApplicationFormState> {
  ApplicationFormNotifier(this.planId);

  final int? planId;
  int _catalogGeneration = 0;
  int _stockGeneration = 0;
  int _previewRequest = 0;

  @override
  ApplicationFormState build() {
    Future.microtask(loadCatalogs);
    return ApplicationFormState.initial(planId: planId);
  }

  Future<void> loadCatalogs() async {
    final generation = ++_catalogGeneration;
    try {
      final repo = ref.read(repositoryProvider);
      final active = await repo.activeCampaign();
      if (active == null) {
        throw BusinessRuleException(
          'Active una campaña antes de registrar aplicaciones.',
        );
      }
      final applicatorRead = await repo.peopleAndContextFor(
        PersonPurpose.applicator,
      );
      final people = applicatorRead.people;
      final operating = applicatorRead.context;
      final personalMode =
          operating.mode == OperationMode.personal &&
          operating.ownerPersonId != null;
      final applicators = {for (final person in people) person['id']};
      final read = await Future.wait([repo.farms(), repo.products()]);
      final result = (
        people: people,
        farms: [
          for (final farm in read[0])
            if (applicators.contains(farm['owner_person_id'])) farm,
        ],
        campaign: active,
        products: read[1],
      );

      int? personId;
      int? farmId;
      var areaText = '';
      var stocks = const <Map<String, Object?>>[];
      final loadedLines = <ApplicationLineData>[];
      var nextLineId = 1;

      if (planId != null) {
        final plan = await repo.planForApplication(planId!);
        if (plan.isEmpty) throw BusinessRuleException('El plan no existe.');
        if (plan.first['campaign_id'] != active['id']) {
          throw BusinessRuleException(
            'El plan no pertenece a la campaña activa.',
          );
        }
        personId = plan.first['person_id'] as int;
        farmId = plan.first['farm_id'] as int;
        areaText = areaInput(plan.first['area_m2'] as int);
        stocks = await repo.availableProductsForOwner(personId);
        for (final item in plan) {
          final stock =
              stocks
                  .where((row) => row['product_id'] == item['product_id'])
                  .firstOrNull ??
              <String, Object?>{
                'product_id': item['product_id'],
                'product_name': item['product_name'],
                'unit': item['unit'],
                'available_base': 0,
                'lot_count': 0,
                'next_fifo_cost_minor': 0,
              };
          final cost = await repo.estimateFifoCost(
            personId: personId,
            productId: item['product_id'] as int,
            quantityBase: item['required_quantity_base'] as int,
          );
          loadedLines.add(
            ApplicationLineData(
              id: nextLineId++,
              product: stock,
              quantityBase: item['required_quantity_base'] as int,
              doseText: formatForInput(
                (item['dose_base_per_ha'] as int) / 1000,
              ),
              cost: cost,
            ),
          );
        }
      } else if (personalMode) {
        personId = operating.ownerPersonId;
        stocks = await repo.availableProductsForOwner(personId!);
      }

      if (!ref.mounted || generation != _catalogGeneration) return;
      state = state.copyWith(
        catalogs: result,
        catalogsError: null,
        loadedMode: operating.mode,
        personalMode: personalMode,
        ownerPersonId: operating.ownerPersonId,
        personId: personId,
        farmId: farmId,
        areaText: areaText,
        areaSyncCounter: areaText.isNotEmpty
            ? state.areaSyncCounter + 1
            : state.areaSyncCounter,
        stocks: stocks,
        lines: loadedLines,
        nextLineId: nextLineId,
      );
    } catch (error) {
      if (!ref.mounted || generation != _catalogGeneration) return;
      state = state.copyWith(catalogsError: error);
    }
  }

  void openVoicePanel() {
    state = state.copyWith(showVoice: true, voiceBanner: false);
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

  void clearDirty() {
    state = state.copyWith(dirty: false);
  }

  void setEffectiveDay(String day) {
    state = state.copyWith(effectiveDay: day, dirty: true);
  }

  void setAreaText(String text) {
    state = state.copyWith(areaText: text, dirty: true, areaError: null);
  }

  void setNotesText(String text) {
    state = state.copyWith(notesText: text, dirty: true);
  }

  void toggleCostHelp() {
    state = state.copyWith(showCostHelp: !state.showCostHelp);
  }

  void toggleLineDetail(int lineId) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.id == lineId) l.copyWith(showDetail: !l.showDetail) else l,
      ],
    );
  }

  void setLineDose(int lineId, String doseText) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.id == lineId) l.copyWith(doseText: doseText) else l,
      ],
      dirty: true,
    );
  }

  Future<bool> selectPerson(Map<String, Object?>? person) async {
    final id = person?['id'] as int?;
    final stockGen = ++_stockGeneration;
    state = state.copyWith(
      personId: id,
      farmId: id != null ? null : state.farmId,
      loadingStock: id != null,
      stocks: const [],
      lines: const [],
      dirty: true,
    );
    if (id == null) return true;
    final result = await ref
        .read(repositoryProvider)
        .availableProductsForOwner(id);
    if (!ref.mounted || stockGen != _stockGeneration || state.personId != id) {
      return false;
    }
    state = state.copyWith(stocks: result, loadingStock: false);
    return true;
  }

  /// Selecciona chaco y sincroniza dueño/área; devuelve mensaje de error si el
  /// dueño del chaco no puede aplicar.
  Future<String?> selectFarm(Map<String, Object?>? farm) async {
    if (farm == null) {
      state = state.copyWith(farmId: null, dirty: true);
      return null;
    }
    final owner = farm['owner_person_id'] as int;
    final nextArea = areaInput(farm['area_m2'] as int);
    state = state.copyWith(
      areaText: nextArea,
      areaSyncCounter: state.areaSyncCounter + 1,
    );
    if (state.personId != owner) {
      final catalogsValue = state.catalogs;
      if (catalogsValue != null) {
        final ownerRow = catalogsValue.people
            .where((p) => p['id'] == owner)
            .firstOrNull;
        if (ownerRow == null) {
          return 'El dueño de este chaco no puede registrar aplicaciones.';
        }
        await selectPerson(ownerRow);
      }
    }
    if (!ref.mounted) return null;
    state = state.copyWith(farmId: farm['id'] as int, dirty: true);
    return null;
  }

  Future<void> _loadStocksForVoice(int owner) async {
    final stockGen = ++_stockGeneration;
    final result = await ref
        .read(repositoryProvider)
        .availableProductsForOwner(owner);
    if (!ref.mounted ||
        stockGen != _stockGeneration ||
        state.personId != owner) {
      return;
    }
    state = state.copyWith(stocks: result, loadingStock: false);
    await refreshVoiceLines();
  }

  Future<void> refreshVoiceLines() async {
    var updated = false;
    final nextLines = <ApplicationLineData>[];
    for (final line in state.lines) {
      final id = line.product['product_id'] as int?;
      if (id == null) {
        nextLines.add(line);
        continue;
      }
      final stock = state.stocks
          .where((r) => r['product_id'] == id)
          .firstOrNull;
      if (stock != null && !identical(stock, line.product)) {
        updated = true;
        nextLines.add(line.copyWith(product: stock));
      } else {
        nextLines.add(line);
      }
    }
    if (updated) {
      state = state.copyWith(lines: nextLines);
    }
    for (final line in state.lines) {
      final id = line.product['product_id'] as int?;
      if (id != null && line.quantityBase > 0) {
        await estimateLine(line.id);
      }
    }
  }

  Future<void> refreshStock() async {
    final id = state.personId;
    if (id == null) return;
    final stockGen = ++_stockGeneration;
    final repo = ref.read(repositoryProvider);
    state = state.copyWith(loadingStock: true);
    final fresh = await repo.availableProductsForOwner(id);
    final products = await repo.products();
    if (!ref.mounted || stockGen != _stockGeneration || state.personId != id) {
      return;
    }
    final current = state.catalogs;
    state = state.copyWith(
      stocks: fresh,
      loadingStock: false,
      lines: [
        for (final line in state.lines)
          line.copyWith(
            product:
                fresh
                    .where(
                      (row) => row['product_id'] == line.product['product_id'],
                    )
                    .firstOrNull ??
                {...line.product, 'available_base': 0},
          ),
      ],
      catalogs: current == null
          ? null
          : (
              people: current.people,
              farms: current.farms,
              campaign: current.campaign,
              products: products,
            ),
    );
    for (final line in List.of(state.lines)) {
      await estimateLine(line.id);
    }
  }

  Future<Map<String, Object?>?> reloadFarmsAfterCreate(int farmId) async {
    final current = state.catalogs;
    if (current == null) return null;
    final repo = ref.read(repositoryProvider);
    final applicators = {for (final person in current.people) person['id']};
    final farms = [
      for (final farm in await repo.farms())
        if (applicators.contains(farm['owner_person_id'])) farm,
    ];
    final next = (
      people: current.people,
      farms: farms,
      campaign: current.campaign,
      products: current.products,
    );
    if (!ref.mounted) return null;
    state = state.copyWith(catalogs: next);
    return farms.where((f) => f['id'] == farmId).firstOrNull;
  }

  Future<Map<String, Object?>?> reloadPeopleAfterCreate(int personId) async {
    final current = state.catalogs;
    if (current == null) return null;
    final repo = ref.read(repositoryProvider);
    final people = await repo.peopleFor(PersonPurpose.applicator);
    if (!ref.mounted) return null;
    state = state.copyWith(
      catalogs: (
        people: people,
        farms: current.farms,
        campaign: current.campaign,
        products: current.products,
      ),
    );
    return people.where((p) => p['id'] == personId).firstOrNull;
  }

  String? addLineFromSheet(Map<String, Object?> product, int quantityBase) {
    if (state.lines.any(
      (line) => line.product['product_id'] == product['product_id'],
    )) {
      return 'Ese producto ya está en la mezcla.';
    }
    final id = state.nextLineId;
    final line = ApplicationLineData(
      id: id,
      product: product,
      quantityBase: quantityBase,
    );
    state = state.copyWith(
      nextLineId: id + 1,
      lines: [...state.lines, line],
      dirty: true,
    );
    unawaited(estimateLine(id));
    return null;
  }

  void updateLineFromSheet(
    int lineId,
    Map<String, Object?> product,
    int quantityBase,
  ) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.id == lineId)
            l.copyWith(product: product, quantityBase: quantityBase)
          else
            l,
      ],
      dirty: true,
    );
    unawaited(estimateLine(lineId));
  }

  void removeLine(int lineId) {
    state = state.copyWith(
      lines: state.lines.where((l) => l.id != lineId).toList(),
      dirty: true,
    );
  }

  Future<void> estimateLine(int lineId) async {
    final line = state.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    final q = line.quantityBase;
    final personId = state.personId;
    final productId = line.product['product_id'] as int?;
    if (personId == null || q <= 0 || productId == null) {
      if (!ref.mounted) return;
      _setLineCost(lineId, 0);
      return;
    }
    final cost = await ref
        .read(repositoryProvider)
        .estimateFifoCost(
          personId: personId,
          productId: productId,
          quantityBase: q,
        );
    if (!ref.mounted) return;
    final latest = state.lines.where((l) => l.id == lineId).firstOrNull;
    if (latest != null && latest.quantityBase == q) {
      _setLineCost(lineId, cost);
    }
  }

  void _setLineCost(int lineId, int cost) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.id == lineId) l.copyWith(cost: cost) else l,
      ],
    );
  }

  String? _validateArea() {
    final parsed = parseNumericInput(state.areaText);
    if (parsed.status == NumericInputStatus.empty) {
      return 'Escriba el área tratada en hectáreas.';
    }
    if (!parsed.isValid) return parsed.message;
    if (parsed.value! <= 0) return 'El área tratada debe ser mayor que cero.';
    return null;
  }

  bool goBackStep() {
    switch (state.step) {
      case ApplicationStep.who:
        return false;
      case ApplicationStep.products:
        state = state.copyWith(step: ApplicationStep.who);
        return true;
      case ApplicationStep.review:
        state = state.copyWith(step: ApplicationStep.products);
        return true;
    }
  }

  ({bool ok, String? errorMessage}) tryContinue() {
    switch (state.step) {
      case ApplicationStep.who:
        if (state.personId == null || state.farmId == null) {
          return (
            ok: false,
            errorMessage: state.personalMode
                ? 'Elija el chaco donde aplicó.'
                : 'Elija la persona y el chaco donde aplicó.',
          );
        }
        final invalidArea = _validateArea();
        if (invalidArea != null) {
          state = state.copyWith(areaError: invalidArea);
          return const (ok: false, errorMessage: null);
        }
        state = state.copyWith(step: ApplicationStep.products);
        return const (ok: true, errorMessage: null);
      case ApplicationStep.products:
        if (state.lines.isEmpty) {
          return const (
            ok: false,
            errorMessage: 'Agregue al menos un producto a la mezcla.',
          );
        }
        if (state.lines.any((l) => l.product['product_id'] == null)) {
          return const (
            ok: false,
            errorMessage:
                'Elija el producto de cada línea (toque «Editar») o quite la '
                'línea.',
          );
        }
        state = state.copyWith(step: ApplicationStep.review);
        unawaited(loadLotPreview());
        return const (ok: true, errorMessage: null);
      case ApplicationStep.review:
        return const (ok: true, errorMessage: null);
    }
  }

  /// Lee los lotes FIFO previstos con guardia contra respuestas fuera de orden.
  Future<void> loadLotPreview() async {
    final id = state.personId;
    if (id == null) return;
    final request = ++_previewRequest;
    final appliedAt = effectiveInstantForDay(
      state.effectiveDay,
      DateTime.now(),
    );
    final wanted = [
      for (final line in state.lines)
        (id: line.product['product_id']! as int, quantity: line.quantityBase),
    ];
    state = state.copyWith(loadingPreview: true, lotPreview: const {});
    final repo = ref.read(repositoryProvider);
    final next = <Object?, List<ApplicationLotPreview>>{};
    try {
      final previews = await Future.wait([
        for (final item in wanted)
          repo.previewApplicationLots(
            personId: id,
            productId: item.id,
            quantityBase: item.quantity,
            appliedAt: appliedAt,
          ),
      ]);
      for (var i = 0; i < wanted.length; i++) {
        next[wanted[i].id] = previews[i];
      }
    } catch (_) {
      // Sin previsión no hay aviso; nada más cambia.
    }
    if (!ref.mounted || request != _previewRequest) return;
    state = state.copyWith(lotPreview: next, loadingPreview: false);
  }

  Future<ApplicationSaveResult> submit({
    required ApplicationCatalogs data,
    required LateApplicationOffer onLateOffer,
  }) async {
    if (state.saving) {
      return const (
        status: ApplicationSaveStatus.aborted,
        errorMessage: null,
        error: null,
      );
    }
    if (state.personId == null || state.farmId == null || state.lines.isEmpty) {
      return const (
        status: ApplicationSaveStatus.validationError,
        errorMessage: 'Elija persona, chaco y al menos un producto.',
        error: null,
      );
    }
    if (state.lines.any((l) => l.product['product_id'] == null)) {
      return const (
        status: ApplicationSaveStatus.validationError,
        errorMessage: 'Elija el producto de cada línea o quite la línea.',
        error: null,
      );
    }
    final drafts = <ApplicationLineDraft>[];
    for (final line in state.lines) {
      final real = line.quantityBase;
      final stock = line.product['available_base'] as int;
      if (real <= 0) {
        return (
          status: ApplicationSaveStatus.validationError,
          errorMessage:
              'Escriba la cantidad usada de ${line.product['product_name']}.',
          error: null,
        );
      }
      if (real > stock) {
        return (
          status: ApplicationSaveStatus.validationError,
          errorMessage:
              'No alcanza el ${line.product['product_name']}: hay '
              '${formatQuantity(stock, line.unit)} y escribió '
              '${formatQuantity(real, line.unit)}. Baje la cantidad o '
              'registre primero la compra.',
          error: null,
        );
      }
      final invalidDose = state.doseError(line);
      if (invalidDose != null) {
        return (
          status: ApplicationSaveStatus.validationError,
          errorMessage:
              'Dosis de ${line.product['product_name']}: $invalidDose',
          error: null,
        );
      }
      drafts.add(
        ApplicationLineDraft(
          productId: line.product['product_id'] as int,
          quantityBase: real,
          treatedAreaM2: state.areaM2,
          doseBasePerHa: tryParseBase(line.doseText),
          theoreticalQuantityBase: state.theoretical(line),
        ),
      );
    }
    state = state.copyWith(saving: true);
    final application = ApplicationDraft(
      personId: state.personId!,
      farmId: state.farmId!,
      campaignId: data.campaign['id'] as int,
      appliedAt: effectiveInstantForDay(state.effectiveDay, DateTime.now()),
      notes: state.notesText.trim(),
      treatedAreaM2: state.areaM2,
      planId: planId,
      lines: drafts,
    );
    try {
      await ref.read(repositoryProvider).confirmApplication(application);
      if (ref.mounted) state = state.copyWith(dirty: false);
      return const (
        status: ApplicationSaveStatus.confirmed,
        errorMessage: null,
        error: null,
      );
    } catch (error) {
      if (planId == null && await onLateOffer(application, error)) {
        if (ref.mounted) state = state.copyWith(dirty: false);
        return const (
          status: ApplicationSaveStatus.lateCaptured,
          errorMessage: null,
          error: null,
        );
      }
      if (ref.mounted) state = state.copyWith(saving: false);
      return (
        status: ApplicationSaveStatus.aborted,
        errorMessage: null,
        error: error,
      );
    }
  }

  // --- Dictado por voz ----------------------------------------------------

  void applyVoicePlan(MergePlan plan) {
    var working = state;
    for (final c in plan.changes) {
      working = _applySlotOnState(working, c.slot, c.after);
    }
    final lines = List.of(working.lines);
    var nextLineId = working.nextLineId;
    for (final n in plan.newLines) {
      var line = ApplicationLineData(
        id: n.line,
        product: working.productRow(n.values['product'] as int?),
        quantityBase: 0,
      );
      if (n.line >= nextLineId) nextLineId = n.line + 1;
      n.values.forEach((field, value) {
        line = _applySlotToLine(working, line, field, value);
      });
      lines.add(line);
    }
    state = working.copyWith(
      lines: lines,
      nextLineId: nextLineId,
      dirty: plan.changesNothing ? working.dirty : true,
    );
    unawaited(refreshVoiceLines());
  }

  void applyVoiceUndo(UndoPlan plan) {
    var working = state;
    for (final c in plan.restore) {
      working = _applySlotOnState(working, c.slot, c.after);
    }
    if (plan.removeLines.isNotEmpty) {
      final removed = plan.removeLines.toSet();
      working = working.copyWith(
        lines: working.lines.where((l) => !removed.contains(l.id)).toList(),
      );
    }
    state = working;
  }

  void setVoiceSlot(SlotRef slot, Object? value) {
    final next = _applySlotOnState(state, slot, value).copyWith(dirty: true);
    state = next;
    unawaited(refreshVoiceLines());
  }

  ApplicationFormState _applySlotOnState(
    ApplicationFormState current,
    SlotRef slot,
    Object? value,
  ) {
    if (slot.line == null) {
      switch (slot.field) {
        case 'farm':
          return _selectFarmForVoice(current, value as int?);
        case 'area':
          final nextArea = value == null ? '' : areaInput(value as int);
          return current.copyWith(
            areaText: nextArea,
            areaSyncCounter: current.areaSyncCounter + 1,
            areaError: null,
          );
      }
      return current;
    }
    final lines = [
      for (final line in current.lines)
        if (line.id == slot.line)
          _applySlotToLine(current, line, slot.field, value)
        else
          line,
    ];
    return current.copyWith(lines: lines);
  }

  ApplicationFormState _selectFarmForVoice(
    ApplicationFormState current,
    int? id,
  ) {
    final farm = current.catalogs?.farms
        .where((f) => f['id'] == id)
        .firstOrNull;
    if (farm == null) {
      return current.copyWith(farmId: null);
    }
    final owner = farm['owner_person_id'] as int;
    if (current.personId != owner) {
      final ownerRow = current.catalogs?.people
          .where((p) => p['id'] == owner)
          .firstOrNull;
      if (ownerRow == null) return current;
      final next = current.copyWith(
        personId: owner,
        farmId: farm['id'] as int,
        lines: const [],
        stocks: const [],
        loadingStock: true,
      );
      unawaited(_loadStocksForVoice(owner));
      return next;
    }
    return current.copyWith(farmId: farm['id'] as int);
  }

  ApplicationLineData _applySlotToLine(
    ApplicationFormState current,
    ApplicationLineData line,
    String field,
    Object? value,
  ) => switch (field) {
    'product' => line.copyWith(product: current.productRow(value as int?)),
    'quantity' => line.copyWith(quantityBase: (value as int?) ?? 0),
    _ => line,
  };
}

final applicationFormProvider = NotifierProvider.autoDispose
    .family<
      ApplicationFormNotifier,
      ApplicationFormState,
      ({Object route, int? planId})
    >((args) => ApplicationFormNotifier(args.planId));
