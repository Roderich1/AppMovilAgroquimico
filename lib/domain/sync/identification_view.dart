import 'operation_id.dart';

/// Versión del texto de consentimiento de la foto de la etiqueta (E1-D11).
const String photoConsentVersion = 'FOTO-1';

/// Texto `FOTO-1` del consentimiento de la foto (contrato E1 §5.2). Si el
/// texto cambia, cambia la versión.
String photoConsentText(String productName) =>
    'La foto de la etiqueta de «$productName» se enviará al sindicato para '
    'ayudar a identificar el producto. Podrá verla la directiva. Puede '
    'quitarla después desde este teléfono.';

/// La vista de una solicitud no respeta la lista cerrada del contrato E1
/// §4.1. Se rechaza entera: no se guarda nada parcial.
class IdentificationViewFormatException implements Exception {
  const IdentificationViewFormatException();
  @override
  String toString() =>
      'La respuesta del sindicato sobre la identificación no tiene el '
      'formato esperado.';
}

/// Resolución de una solicitud identificada (`status = LINKED`).
class IdentificationResolution {
  const IdentificationResolution({
    required this.kind,
    required this.productRef,
    required this.productName,
    required this.unit,
    required this.baseUnit,
    required this.isActive,
    required this.resolvedAt,
  });

  /// `LINKED_EXISTING` o `CREATED_PRODUCT`.
  final String kind;
  final String productRef;
  final String productName;
  final String unit;
  final String baseUnit;
  final bool isActive;
  final String resolvedAt;
}

/// Vista de una solicitud propia tal como la devuelve el sindicato
/// (`PUT /{request_id}`, elementos de `GET /`). Sólo lo que el teléfono
/// necesita conservar.
class IdentificationServerView {
  const IdentificationServerView({
    required this.requestId,
    required this.status,
    required this.unit,
    required this.photoState,
    required this.resolution,
    required this.pendingNote,
  });

  final String requestId;

  /// `PENDING` o `LINKED`.
  final String status;
  final String unit;

  /// `NONE`, `STORED` o `REMOVED`.
  final String photoState;
  final IdentificationResolution? resolution;
  final String? pendingNote;

  static const _rootKeys = {
    'contractVersion',
    'request_id',
    'status',
    'local_name',
    'active_ingredient',
    'unit',
    'base_unit',
    'received_at',
    'updated_at',
    'photo',
    'resolution',
    'pending_note',
  };
  static const _photoKeys = {'state', 'sha256', 'consent_version'};
  static const _resolutionKeys = {
    'kind',
    'product_ref',
    'product_name',
    'unit',
    'base_unit',
    'is_active',
    'resolved_at',
  };
  static const _noteKeys = {'text', 'at'};
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Acepta sólo la forma exacta: claves conocidas (`contractVersion` puede
  /// faltar en los elementos de la lista), tipos correctos y referencias
  /// canónicas. Una clave desconocida —por ejemplo, un dato institucional—
  /// rechaza la vista entera.
  factory IdentificationServerView.fromJson(Object? raw) {
    final json = _object(raw);
    _knownKeys(json, _rootKeys, optional: const {'contractVersion'});
    if (json.containsKey('contractVersion') && json['contractVersion'] != 1) {
      _invalid();
    }
    final requestId = json['request_id'];
    if (requestId is! String || !uuidV4Lowercase.hasMatch(requestId)) {
      _invalid();
    }
    final status = _oneOf(json['status'], const {'PENDING', 'LINKED'});
    final unit = _oneOf(json['unit'], const {'L', 'KG'});
    final baseUnit = _oneOf(json['base_unit'], const {'ML', 'G'});
    if ((unit == 'L') != (baseUnit == 'ML')) _invalid();
    _text(json['local_name']);
    _optionalText(json['active_ingredient']);
    _text(json['received_at']);
    _text(json['updated_at']);

    final photo = _object(json['photo']);
    _knownKeys(photo, _photoKeys);
    final photoState = _oneOf(photo['state'], const {
      'NONE',
      'STORED',
      'REMOVED',
    });
    final sha = photo['sha256'];
    if (sha != null && (sha is! String || !_sha256.hasMatch(sha))) _invalid();
    _optionalText(photo['consent_version']);

    IdentificationResolution? resolution;
    if (json['resolution'] != null) {
      final item = _object(json['resolution']);
      _knownKeys(item, _resolutionKeys);
      final ref = item['product_ref'];
      if (ref is! String || !canonicalUuid.hasMatch(ref)) _invalid();
      final isActive = item['is_active'];
      if (isActive is! bool) _invalid();
      resolution = IdentificationResolution(
        kind: _oneOf(item['kind'], const {
          'LINKED_EXISTING',
          'CREATED_PRODUCT',
        }),
        productRef: ref,
        productName: _text(item['product_name']),
        unit: _text(item['unit']),
        baseUnit: _text(item['base_unit']),
        isActive: isActive,
        resolvedAt: _text(item['resolved_at']),
      );
    }
    // Identificada si y sólo si trae resolución.
    if ((status == 'LINKED') != (resolution != null)) _invalid();

    String? note;
    if (json['pending_note'] != null) {
      final item = _object(json['pending_note']);
      _knownKeys(item, _noteKeys);
      note = _text(item['text']);
      _text(item['at']);
    }
    return IdentificationServerView(
      requestId: requestId,
      status: status,
      unit: unit,
      photoState: photoState,
      resolution: resolution,
      pendingNote: note,
    );
  }

  /// Lista de `GET /`: `{contractVersion: 1, requests: [...]}`.
  static List<IdentificationServerView> listFromJson(Object? raw) {
    final json = _object(raw);
    _knownKeys(json, const {'contractVersion', 'requests'});
    if (json['contractVersion'] != 1) _invalid();
    final requests = json['requests'];
    if (requests is! List<dynamic>) _invalid();
    return [
      for (final item in requests) IdentificationServerView.fromJson(item),
    ];
  }

  static Never _invalid() => throw const IdentificationViewFormatException();

  static Map<String, dynamic> _object(Object? value) =>
      value is Map<String, dynamic> ? value : _invalid();

  static void _knownKeys(
    Map<String, dynamic> json,
    Set<String> keys, {
    Set<String> optional = const {},
  }) {
    if (!keys.containsAll(json.keys)) _invalid();
    for (final key in keys.difference(optional)) {
      if (!json.containsKey(key)) _invalid();
    }
  }

  static String _text(Object? value) =>
      value is String && value.isNotEmpty ? value : _invalid();

  static String? _optionalText(Object? value) =>
      value == null ? null : _text(value);

  static String _oneOf(Object? value, Set<String> allowed) =>
      value is String && allowed.contains(value) ? value : _invalid();
}
