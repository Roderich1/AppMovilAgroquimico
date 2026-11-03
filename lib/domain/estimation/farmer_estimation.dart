// Estimación del consumo para el Agricultor (F12-EST-07-MOB, MOB #164;
// RF-39, RF-40, RN-30, DAT-20, INT-09 v1). Reglas puras, sin E/S.
//
// El teléfono no calcula nada: muestra lo que entrega el servicio con el
// perfil FARMER (sin línea base naive, cobertura ni serie) y lo guarda tal
// como llegó. Las cantidades son texto exacto en la unidad base (mL o g, hasta
// 6 decimales) y se presentan sin pasar por coma flotante. Una cifra ausente
// es una ausencia: nunca se muestra como cero ni se suma a la necesidad
// declarada o al inventario.

/// La respuesta no tiene la forma cerrada de INT-09 v1 para el perfil FARMER.
class FarmerEstimationFormatException implements Exception {
  const FarmerEstimationFormatException(this.reason);
  final String reason;
  @override
  String toString() => 'La estimación recibida no tiene el formato esperado.';
}

const _contractVersion = 1;
const _notice =
    'Referencia calculada a partir de cifras publicadas; no es una necesidad '
    'ni una propuesta, no se suma a ellas y puede no estar actualizada.';
const _statuses = {
  'ESTIMATED',
  'INSUFFICIENT_DATA',
  'INCOMPATIBLE_DATA',
  'CALCULATION_FAILED',
};
const _reasons = {
  'LAST_RELEVANT_CAMPAIGN_NOT_VERIFIED',
  'SPAN_TOO_SHORT',
  'NO_SERIES',
  'MIXED_UNITS',
  'NO_COMPARABLE_CAMPAIGNS',
  'COVERAGE_UNKNOWN',
  'CALCULATION_ERROR',
};
const _validities = {'NOT_USABLE', 'SUPERSEDED', 'OUTDATED', 'CURRENT'};
const _validityReasons = {
  'RUN_FAILED',
  'NO_FIGURE',
  'LATER_RUN',
  'SOURCES_CHANGED',
  'CLASSIFICATION_CORRECTED',
  'SOURCES_WITHDRAWN',
};
const _campaignStatuses = {'PLANIFICADA', 'ABIERTA', 'CERRADA', 'CANCELADA'};
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _quantity = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$');

/// Campaña objetivo (el período de la estimación).
class EstimationTarget {
  const EstimationTarget({
    required this.campaignRef,
    required this.name,
    required this.status,
    required this.startDate,
    required this.endDate,
  });

  final String campaignRef;
  final String name;
  final String status;
  final DateTime startDate;
  final DateTime? endDate;
}

/// Temporada institucional de comparabilidad.
class EstimationSeason {
  const EstimationSeason({
    required this.key,
    required this.definition,
    required this.durationDays,
  });

  final String key;
  final String definition;
  final int durationDays;
}

/// Resultado de un producto para el Agricultor. [validity] es la vigencia al
/// consultar (en `/results`) o al descargar (en la copia).
class FarmerResult {
  const FarmerResult({
    required this.productRef,
    required this.productName,
    required this.baseUnit,
    required this.presentationUnit,
    required this.status,
    required this.reasonCode,
    required this.generatedAt,
    required this.spanLength,
    required this.estimateBase,
    required this.validity,
    required this.validityReason,
  });

  final String productRef;
  final String productName;
  final String baseUnit;
  final String presentationUnit;
  final String status;
  final String? reasonCode;
  final DateTime generatedAt;
  final int? spanLength;

  /// Texto exacto en la unidad base, o null si no hay cifra.
  final String? estimateBase;
  final String validity;
  final String? validityReason;
}

/// Lo común a `/results` y a la copia: ámbito, objetivo, temporada y resultados.
class FarmerEstimation {
  const FarmerEstimation({
    required this.tenantRef,
    required this.target,
    required this.season,
    required this.results,
    required this.notice,
  });

  final String tenantRef;
  final EstimationTarget target;
  final EstimationSeason? season;
  final List<FarmerResult> results;
  final String notice;
}

/// `GET /estimation/results` con el perfil FARMER.
class FarmerResults extends FarmerEstimation {
  const FarmerResults({
    required super.tenantRef,
    required super.target,
    required super.season,
    required super.results,
    required super.notice,
    required this.evaluatedAt,
  });

  final DateTime evaluatedAt;

  static const _keys = {
    'contract_version',
    'profile',
    'scope',
    'target',
    'season',
    'evaluated_at',
    'results',
    'notice',
  };

  /// Sólo la forma exacta del perfil FARMER. Un perfil institucional, una
  /// clave de más (naive, cobertura, serie) o un tipo distinto se rechazan.
  factory FarmerResults.fromJson(Object? json) {
    final root = _object(json, _keys, 'raíz');
    _common(root);
    return FarmerResults(
      tenantRef: _scope(root['scope']),
      target: _target(root['target']),
      season: _season(root['season']),
      results: _results(root['results'], 'validity'),
      notice: root['notice'] as String,
      evaluatedAt: _instant(root['evaluated_at'], 'evaluated_at'),
    );
  }
}

/// `GET /estimation/download` con el perfil FARMER: la copia descargada.
class FarmerDownload extends FarmerEstimation {
  const FarmerDownload({
    required super.tenantRef,
    required super.target,
    required super.season,
    required super.results,
    required super.notice,
    required this.memberRef,
    required this.downloadedAt,
  });

  /// Member autenticado que la descargó (identidad propietaria).
  final String memberRef;

  /// Hora del servidor; decide el reemplazo (sólo por una posterior).
  final DateTime downloadedAt;

  static const _keys = {
    'contract_version',
    'kind',
    'profile',
    'scope',
    'subject',
    'downloaded_at',
    'target',
    'season',
    'results',
    'may_be_outdated',
    'notice',
    'storage',
  };

  factory FarmerDownload.fromJson(Object? json) {
    final root = _object(json, _keys, 'raíz');
    _common(root);
    if (root['kind'] != 'ESTIMATION_DOWNLOAD') _fail('kind');
    if (root['may_be_outdated'] != true) _fail('may_be_outdated');
    final subject = _object(root['subject'], {'member_ref', 'role'}, 'subject');
    final memberRef = _uuidOf(subject['member_ref'], 'subject.member_ref');
    if (subject['role'] != 'AGRICULTOR') _fail('subject.role');
    final storage = _object(root['storage'], {
      'backup',
      'discard_on',
      'replace_only_with',
    }, 'storage');
    final discardOn = storage['discard_on'];
    if (storage['backup'] != 'EXCLUDED_FROM_PRIVATE_BACKUP' ||
        storage['replace_only_with'] != 'NEWER_SAME_SUBJECT_AND_SCOPE' ||
        discardOn is! List ||
        discardOn.length != 2 ||
        !discardOn.contains('IDENTITY_CHANGE') ||
        !discardOn.contains('SIGN_OUT')) {
      _fail('storage');
    }
    return FarmerDownload(
      tenantRef: _scope(root['scope']),
      target: _target(root['target']),
      season: _season(root['season']),
      results: _results(root['results'], 'validity_at_download'),
      notice: root['notice'] as String,
      memberRef: memberRef,
      downloadedAt: _instant(root['downloaded_at'], 'downloaded_at'),
    );
  }
}

Never _fail(String reason) => throw FarmerEstimationFormatException(reason);

Map<String, Object?> _object(Object? value, Set<String> keys, String where) {
  if (value is! Map<String, Object?>) _fail(where);
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    _fail(where);
  }
  return value;
}

void _common(Map<String, Object?> root) {
  if (root['contract_version'] != _contractVersion) _fail('contract_version');
  if (root['profile'] != 'FARMER') _fail('profile');
  if (root['notice'] != _notice) _fail('notice');
}

String _uuidOf(Object? value, String where) {
  if (value is! String || !_uuid.hasMatch(value)) _fail(where);
  return value;
}

String _scope(Object? value) =>
    _uuidOf(_object(value, {'tenant_ref'}, 'scope')['tenant_ref'], 'scope');

DateTime _instant(Object? value, String where) {
  if (value is! String) _fail(where);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) _fail(where);
  return parsed;
}

EstimationTarget _target(Object? value) {
  final target = _object(value, {
    'campaign_ref',
    'name',
    'status',
    'start_date',
    'end_date',
  }, 'target');
  final name = target['name'];
  final status = target['status'];
  if (name is! String ||
      status is! String ||
      !_campaignStatuses.contains(status)) {
    _fail('target');
  }
  return EstimationTarget(
    campaignRef: _uuidOf(target['campaign_ref'], 'target.campaign_ref'),
    name: name,
    status: status,
    startDate: _instant(target['start_date'], 'target.start_date'),
    endDate: target['end_date'] == null
        ? null
        : _instant(target['end_date'], 'target.end_date'),
  );
}

EstimationSeason? _season(Object? value) {
  if (value == null) return null;
  final season = _object(value, {
    'season_ref',
    'key',
    'definition',
    'duration_days',
  }, 'season');
  _uuidOf(season['season_ref'], 'season.season_ref');
  final key = season['key'];
  final definition = season['definition'];
  final days = season['duration_days'];
  if (key is! String || definition is! String || days is! int || days < 1) {
    _fail('season');
  }
  return EstimationSeason(key: key, definition: definition, durationDays: days);
}

List<FarmerResult> _results(Object? value, String validityKey) {
  if (value is! List) _fail('results');
  const common = {
    'product',
    'base_unit',
    'presentation_unit',
    'status',
    'reason_code',
    'method',
    'run_ref',
    'generated_at',
    'span_length',
    'estimate_base',
    'validity_reason',
  };
  return [
    for (final item in value)
      _result(_object(item, {...common, validityKey}, 'result'), validityKey),
  ];
}

FarmerResult _result(Map<String, Object?> row, String validityKey) {
  final product = _object(row['product'], {'product_ref', 'name'}, 'product');
  final name = product['name'];
  final baseUnit = row['base_unit'];
  final presentation = row['presentation_unit'];
  final status = row['status'];
  final reason = row['reason_code'];
  final span = row['span_length'];
  final estimate = row['estimate_base'];
  final validity = row[validityKey];
  final validityReason = row['validity_reason'];
  if (name is! String ||
      !((baseUnit == 'ML' && presentation == 'L') ||
          (baseUnit == 'G' && presentation == 'KG')) ||
      status is! String ||
      !_statuses.contains(status) ||
      (reason != null && (reason is! String || !_reasons.contains(reason))) ||
      row['method'] != 'SES_NAIVE' ||
      (span != null && (span is! int || span < 1)) ||
      (estimate != null &&
          (estimate is! String || !_quantity.hasMatch(estimate))) ||
      validity is! String ||
      !_validities.contains(validity) ||
      (validityReason != null &&
          (validityReason is! String ||
              !_validityReasons.contains(validityReason)))) {
    _fail('result');
  }
  // Una cifra sólo acompaña a un resultado estimado.
  if (estimate != null && status != 'ESTIMATED') _fail('result.estimate');
  _uuidOf(row['run_ref'], 'result.run_ref');
  return FarmerResult(
    productRef: _uuidOf(product['product_ref'], 'product.product_ref'),
    productName: name,
    baseUnit: baseUnit as String,
    presentationUnit: presentation as String,
    status: status,
    reasonCode: reason as String?,
    generatedAt: _instant(row['generated_at'], 'result.generated_at'),
    spanLength: span as int?,
    estimateBase: estimate as String?,
    validity: validity,
    validityReason: validityReason as String?,
  );
}

/// Cantidad exacta para mostrar: en la unidad de presentación (L o kg) y en
/// la base (mL o g), con coma decimal y punto de miles (es-BO). Trabaja con
/// el texto y enteros: ningún paso por coma flotante.
class ExactQuantity {
  const ExactQuantity(this.presentation, this.base);
  final String presentation;
  final String base;
}

ExactQuantity formatExactQuantity(String baseText, String baseUnit) {
  if (!_quantity.hasMatch(baseText)) {
    throw const FarmerEstimationFormatException('quantity');
  }
  final parts = baseText.split('.');
  final fraction = (parts.length == 2 ? parts[1] : '').padRight(6, '0');
  // En millonésimas de la unidad base.
  final micro =
      BigInt.parse(parts[0]) * BigInt.from(1000000) + BigInt.parse(fraction);
  final (major, minor) = switch (baseUnit) {
    'ML' => ('L', 'mL'),
    'G' => ('kg', 'g'),
    _ => throw const FarmerEstimationFormatException('unit'),
  };
  // 1 L = 1000 mL: la presentación tiene 9 decimales posibles.
  return ExactQuantity(
    '${_decimal(micro, 9)} $major',
    '${_decimal(micro, 6)} $minor',
  );
}

String _decimal(BigInt scaled, int decimals) {
  final unit = BigInt.from(10).pow(decimals);
  final whole = scaled ~/ unit;
  var fraction = (scaled % unit).toString().padLeft(decimals, '0');
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return fraction.isEmpty ? grouped.toString() : '$grouped,$fraction';
}

/// Textos del resultado, los mismos que en la Web (F12-EST-06).
const estimationStatusText = <String, String>{
  'ESTIMATED': 'Estimado',
  'INSUFFICIENT_DATA': 'Datos insuficientes',
  'INCOMPATIBLE_DATA': 'Datos incompatibles',
  'CALCULATION_FAILED': 'Cálculo fallido',
};

const estimationReasonText = <String, String>{
  'LAST_RELEVANT_CAMPAIGN_NOT_VERIFIED': 'La campaña comparable inmediatamente anterior no tiene consumo comprobado.',
  'SPAN_TOO_SHORT': 'Hay menos de tres campañas comparables consecutivas con consumo comprobado.',
  'NO_SERIES': 'No hay serie de consumo de este producto.',
  'MIXED_UNITS': 'Las cifras selladas de este producto están en unidades distintas: masa y volumen no se mezclan.',
  'NO_COMPARABLE_CAMPAIGNS':
      'No hay campañas comparables anteriores con las que estimar.',
  'COVERAGE_UNKNOWN':
      'Alguna campaña del tramo no tiene la cobertura identificada.',
  'CALCULATION_ERROR': 'El cálculo de este producto falló.',
};

const estimationValidityText = <String, String>{
  'CURRENT': 'Vigente',
  'OUTDATED': 'Desactualizado',
  'SUPERSEDED': 'Sustituido',
  'NOT_USABLE': 'No utilizable',
};

const estimationValidityReasonText = <String, String>{
  'RUN_FAILED': 'La ejecución falló: no tiene cifras.',
  'NO_FIGURE': 'Este resultado no tiene cifra.',
  'LATER_RUN': 'Una ejecución calculada posterior lo reemplaza.',
  'SOURCES_CHANGED': 'Las cifras, las campañas o las asociaciones de la serie cambiaron desde el cálculo.',
  'CLASSIFICATION_CORRECTED':
      'Se corrigió la clasificación de una campaña que se usó.',
  'SOURCES_WITHDRAWN':
      'Una cifra que se usó ya no se divulga: la estimación no se muestra.',
};

/// Lo que se muestra en lugar de la cifra: nunca un cero.
String estimationFigureText(FarmerResult result) {
  final base = result.estimateBase;
  if (base != null) {
    final quantity = formatExactQuantity(base, result.baseUnit);
    return '${quantity.presentation} (${quantity.base})';
  }
  return result.validityReason == 'SOURCES_WITHDRAWN'
      ? 'Cifra retirada'
      : 'Sin cifra';
}
