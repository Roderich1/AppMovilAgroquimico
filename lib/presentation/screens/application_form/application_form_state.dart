import 'package:flutter/material.dart';

import '../../../domain/campaign_calendar.dart';
import '../../../domain/money.dart';
import '../../../domain/operation_mode.dart';
import '../../../domain/repository_types.dart' show ApplicationLotPreview;
import '../../widgets/common.dart';

/// Rótulo del selector de persona de la aplicación en inventario compartido
/// (decisión del autor, 2026-11-12). Es la persona cuyas existencias se
/// consumen y a quien se carga el uso: la responsable del chaco.
const applicationPersonLabel = '¿De quién son los productos?';

enum ApplicationStep { who, products, review }

typedef ApplicationCatalogs = ({
  List<Map<String, Object?>> people,
  List<Map<String, Object?>> farms,
  Map<String, Object?> campaign,

  /// Productos activos del catálogo, para explicar cuáles no tienen
  /// existencias de la persona (no sólo omitirlos de la lista).
  List<Map<String, Object?>> products,
});

const Object _absent = Object();

class ApplicationLineData {
  const ApplicationLineData({
    required this.id,
    required this.product,
    required this.quantityBase,
    this.doseText = '',
    this.cost = 0,
    this.showDetail = false,
  });

  /// Identificador estable (no la posición), para el dictado.
  final int id;
  final Map<String, Object?> product;
  final int quantityBase;
  final String doseText;
  final int cost;

  /// «Dosis y costo» abierto en la tarjeta (sólo presentación).
  final bool showDetail;

  /// Sufijo de las claves de la tarjeta: el producto, o el id si la línea
  /// dictada aún no tiene producto (dos así no comparten clave).
  String get keyId => product['product_id']?.toString() ?? 'voz-$id';

  String get unit => product['unit'] as String;
  int get available => product['available_base'] as int;

  ApplicationLineData copyWith({
    Map<String, Object?>? product,
    int? quantityBase,
    String? doseText,
    int? cost,
    bool? showDetail,
  }) => ApplicationLineData(
    id: id,
    product: product ?? this.product,
    quantityBase: quantityBase ?? this.quantityBase,
    doseText: doseText ?? this.doseText,
    cost: cost ?? this.cost,
    showDetail: showDetail ?? this.showDetail,
  );
}

class ApplicationFormState {
  const ApplicationFormState({
    required this.planId,
    this.catalogs,
    this.catalogsError,
    this.nextLineId = 1,
    this.lines = const [],
    this.stocks = const [],
    this.personId,
    this.farmId,
    this.step = ApplicationStep.who,
    required this.effectiveDay,
    this.areaText = '',
    this.areaSyncCounter = 0,
    this.notesText = '',
    this.areaError,
    this.dirty = false,
    this.saving = false,
    this.loadingStock = false,
    this.loadedMode,
    this.personalMode = false,
    this.ownerPersonId,
    this.lotPreview = const {},
    this.loadingPreview = false,
    this.showCostHelp = false,
    this.showVoice = false,
    this.voiceBanner = false,
    this.seenCompletions = 0,
  });

  factory ApplicationFormState.initial({required int? planId}) =>
      ApplicationFormState(
        planId: planId,
        effectiveDay: localDay(DateTime.now()),
      );

  final int? planId;
  final ApplicationCatalogs? catalogs;
  final Object? catalogsError;
  final int nextLineId;
  final List<ApplicationLineData> lines;
  final List<Map<String, Object?>> stocks;
  final int? personId;
  final int? farmId;
  final ApplicationStep step;
  final String effectiveDay;
  final String areaText;
  final int areaSyncCounter;
  final String notesText;
  final String? areaError;
  final bool dirty;
  final bool saving;
  final bool loadingStock;
  final OperationMode? loadedMode;
  final bool personalMode;
  final int? ownerPersonId;
  final Map<Object?, List<ApplicationLotPreview>> lotPreview;
  final bool loadingPreview;
  final bool showCostHelp;
  final bool showVoice;
  final bool voiceBanner;
  final int seenCompletions;

  int get stepNumber => switch (step) {
    ApplicationStep.who => 1,
    ApplicationStep.products => 2,
    ApplicationStep.review => 3,
  };

  bool get voiceStep => planId == null && step != ApplicationStep.review;

  int get areaM2 => ((tryParseDecimal(areaText) ?? 0) * 10000).round();

  List<Map<String, Object?>> get addableProducts => stocks
      .where(
        (p) =>
            !lines.any((line) => line.product['product_id'] == p['product_id']),
      )
      .toList();

  Map<String, Object?>? person(ApplicationCatalogs data) =>
      data.people.where((p) => p['id'] == personId).firstOrNull;

  Map<String, Object?>? farm(ApplicationCatalogs data) =>
      data.farms.where((f) => f['id'] == farmId).firstOrNull;

  /// Fila de existencias del producto para una línea (voz / plan).
  Map<String, Object?> productRow(int? productId) {
    if (productId == null) {
      return const {
        'product_id': null,
        'product_name': 'Producto por elegir',
        'unit': '',
        'available_base': 0,
        'lot_count': 0,
        'next_fifo_cost_minor': 0,
      };
    }
    final stock = stocks.where((r) => r['product_id'] == productId).firstOrNull;
    if (stock != null) return stock;
    final product = catalogs?.products
        .where((p) => p['id'] == productId)
        .firstOrNull;
    return {
      'product_id': productId,
      'product_name': product?['name'] ?? 'Producto',
      'unit': product?['unit'] ?? '',
      'available_base': 0,
      'lot_count': 0,
      'next_fifo_cost_minor': 0,
    };
  }

  int? theoretical(ApplicationLineData line) {
    final dose = tryParseBase(line.doseText);
    if (dose == null) return null;
    return divideRoundedHalfUp(areaM2 * dose, 10000);
  }

  String? doseError(ApplicationLineData line) =>
      parseNumericInput(line.doseText).message;

  ApplicationFormState copyWith({
    Object? catalogs = _absent,
    Object? catalogsError = _absent,
    int? nextLineId,
    List<ApplicationLineData>? lines,
    List<Map<String, Object?>>? stocks,
    Object? personId = _absent,
    Object? farmId = _absent,
    ApplicationStep? step,
    String? effectiveDay,
    String? areaText,
    int? areaSyncCounter,
    String? notesText,
    Object? areaError = _absent,
    bool? dirty,
    bool? saving,
    bool? loadingStock,
    Object? loadedMode = _absent,
    bool? personalMode,
    Object? ownerPersonId = _absent,
    Map<Object?, List<ApplicationLotPreview>>? lotPreview,
    bool? loadingPreview,
    bool? showCostHelp,
    bool? showVoice,
    bool? voiceBanner,
    int? seenCompletions,
  }) => ApplicationFormState(
    planId: planId,
    catalogs: identical(catalogs, _absent)
        ? this.catalogs
        : catalogs as ApplicationCatalogs?,
    catalogsError: identical(catalogsError, _absent)
        ? this.catalogsError
        : catalogsError,
    nextLineId: nextLineId ?? this.nextLineId,
    lines: lines ?? this.lines,
    stocks: stocks ?? this.stocks,
    personId: identical(personId, _absent) ? this.personId : personId as int?,
    farmId: identical(farmId, _absent) ? this.farmId : farmId as int?,
    step: step ?? this.step,
    effectiveDay: effectiveDay ?? this.effectiveDay,
    areaText: areaText ?? this.areaText,
    areaSyncCounter: areaSyncCounter ?? this.areaSyncCounter,
    notesText: notesText ?? this.notesText,
    areaError: identical(areaError, _absent)
        ? this.areaError
        : areaError as String?,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    loadingStock: loadingStock ?? this.loadingStock,
    loadedMode: identical(loadedMode, _absent)
        ? this.loadedMode
        : loadedMode as OperationMode?,
    personalMode: personalMode ?? this.personalMode,
    ownerPersonId: identical(ownerPersonId, _absent)
        ? this.ownerPersonId
        : ownerPersonId as int?,
    lotPreview: lotPreview ?? this.lotPreview,
    loadingPreview: loadingPreview ?? this.loadingPreview,
    showCostHelp: showCostHelp ?? this.showCostHelp,
    showVoice: showVoice ?? this.showVoice,
    voiceBanner: voiceBanner ?? this.voiceBanner,
    seenCompletions: seenCompletions ?? this.seenCompletions,
  );
}

/// Área en m² escrita en hectáreas para el campo editable. Un entero de m²
/// tiene a lo sumo cuatro decimales en hectáreas, así que con cuatro el texto
/// es exacto.
String areaInput(int areaM2) => formatForInput(areaM2 / 10000, maxDecimals: 4);

/// «Hoy, 12/11/2026» o la fecha a secas.
String applicationDayLabel(String day) => day == localDay(DateTime.now())
    ? 'Hoy, ${formatDate(day)}'
    : formatDate(day);

/// Dueño de los [TextEditingController] de área, notas y dosis por línea.
class ApplicationFormControllers {
  final area = TextEditingController();
  final notes = TextEditingController();
  final Map<int, TextEditingController> _doses = {};
  final List<TextEditingController> _pendingDispose = [];

  TextEditingController doseFor(ApplicationLineData line) => _doses.putIfAbsent(
    line.id,
    () => TextEditingController(text: line.doseText),
  );

  void syncArea(String text) {
    if (area.text != text) area.text = text;
  }

  void syncInitial(ApplicationFormState state) {
    syncArea(state.areaText);
    for (final line in state.lines) {
      final ctrl = doseFor(line);
      if (ctrl.text != line.doseText) ctrl.text = line.doseText;
    }
  }

  void detachRemoved(ApplicationFormState state) {
    final activeIds = {for (final l in state.lines) l.id};
    final removed = <TextEditingController>[];
    _doses.removeWhere((id, controller) {
      if (activeIds.contains(id)) return false;
      removed.add(controller);
      return true;
    });
    if (removed.isNotEmpty) {
      _pendingDispose.addAll(removed);
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
    area.dispose();
    notes.dispose();
    for (final controller in _doses.values) {
      controller.dispose();
    }
    _doses.clear();
    disposePending();
  }
}
