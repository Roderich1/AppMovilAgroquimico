// Convocatorias de compra conjunta vistas por el agricultor (contrato E2 §4.2
// y §5). Sólo forma y validación: sin base de datos ni red.
//
// Lista cerrada en todos los niveles: una clave desconocida —por ejemplo,
// un dato de otro agricultor o un total institucional— rechaza la respuesta
// ENTERA, sin guardar nada parcial.
import 'dart:convert';

import 'operation_id.dart';

/// Versión vigente del texto de consentimiento de la participación (E2-D9,
/// §10.2). Las operaciones preparadas antes con `CONV-1` se envían tal como
/// se guardaron: el servidor sigue aceptándolas (sólo las ve la persona
/// responsable).
const String jointPurchaseConsentVersion = 'CONV-2';

/// Texto exacto `CONV-2` (E2 §10.2). Si el texto cambia, cambia la versión.
const String jointPurchaseConsentText =
    'La persona responsable de esta compra conjunta y quienes ella autorice '
    'para coordinarla podrán ver tu nombre y las cantidades que solicitas, '
    'para coordinar la compra y la entrega. Esta confirmación no genera una '
    'deuda.';

/// Versión anterior (E2-D9): sólo la llevan operaciones guardadas antes de
/// actualizar la aplicación. Nunca se ofrece para una confirmación nueva.
const String jointPurchaseLegacyConsentVersion = 'CONV-1';

/// Filtro de presentación (E2 §10.1 a): una convocatoria terminada hace más
/// de estos días se muestra en «Historial», no en la vista por defecto. No
/// decide qué guarda el teléfono ni qué conserva el servidor.
const int jointPurchaseRecentFinishedDays = 180;

/// Tamaño de página por defecto de `GET /me/joint-purchase-calls/history`
/// (E2 §10.1; el servidor admite 1..50).
const int jointPurchaseHistoryPageSize = 20;

/// Cursor opaco de la página de historial: sólo caracteres que viajan sin
/// ambigüedad en una consulta (base64/base64url y similares).
final RegExp jointPurchaseHistoryCursor = RegExp(
  r'^[A-Za-z0-9._~+/=-]{1,1024}$',
);

/// La respuesta del sindicato no respeta la lista cerrada del contrato E2
/// §4.2. Se rechaza entera.
class JointPurchaseFormatException implements Exception {
  const JointPurchaseFormatException();
  @override
  String toString() =>
      'La respuesta del sindicato sobre las compras conjuntas no tiene el '
      'formato esperado.';
}

/// Estados de una convocatoria que el agricultor puede ver (E2-D2; un
/// borrador nunca se sirve al agricultor).
abstract final class JointPurchaseCallStatus {
  static const open = 'OPEN';
  static const closed = 'CLOSED';
  static const cancelled = 'CANCELLED';
  static const all = {open, closed, cancelled};
}

/// Motivos de `409 CALL_NOT_OPEN` (E2-D11).
abstract final class CallNotOpenReason {
  static const deadlinePassed = 'DEADLINE_PASSED';
  static const closed = 'CLOSED';
  static const cancelled = 'CANCELLED';
  static const draft = 'DRAFT';
  static const all = {deadlinePassed, closed, cancelled, draft};
}

/// Un producto de la convocatoria (producto colectivo del tenant).
class JointPurchaseProduct {
  const JointPurchaseProduct({
    required this.productRef,
    required this.name,
    required this.unit,
    required this.baseUnit,
  });

  final String productRef;
  final String name;

  /// `L` o `KG`.
  final String unit;

  /// `ML` o `G`.
  final String baseUnit;

  Map<String, Object?> toJson() => {
    'product_ref': productRef,
    'name': name,
    'unit': unit,
    'base_unit': baseUnit,
  };

  static const _keys = {'product_ref', 'name', 'unit', 'base_unit'};

  factory JointPurchaseProduct.fromJson(Object? raw) {
    final json = _object(raw);
    _knownKeys(json, _keys);
    final ref = json['product_ref'];
    if (ref is! String || !canonicalUuid.hasMatch(ref)) _invalid();
    final unit = _oneOf(json['unit'], const {'L', 'KG'});
    final baseUnit = _oneOf(json['base_unit'], const {'ML', 'G'});
    if ((unit == 'L') != (baseUnit == 'ML')) _invalid();
    return JointPurchaseProduct(
      productRef: ref,
      name: _text(json['name']),
      unit: unit,
      baseUnit: baseUnit,
    );
  }

  /// `products_json` local o `products` del servidor: lista no vacía, sin
  /// referencias repetidas.
  static List<JointPurchaseProduct> listFromJson(Object? raw) {
    if (raw is! List<dynamic> || raw.isEmpty) _invalid();
    final products = [
      for (final item in raw) JointPurchaseProduct.fromJson(item),
    ];
    if (products.map((p) => p.productRef).toSet().length != products.length) {
      _invalid();
    }
    return products;
  }

  static String encodeList(List<JointPurchaseProduct> products) =>
      jsonEncode([for (final product in products) product.toJson()]);
}

/// Estado de la participación propia según el servidor (E2-D8).
abstract final class JointPurchaseParticipationStatus {
  static const active = 'ACTIVE';
  static const withdrawn = 'WITHDRAWN';
}

/// La participación propia **aceptada por el servidor** (E2 §4.2, forma del
/// Backend `ParticipationView`): `{status, lines: [{product_ref, base_unit,
/// quantity_base}], last_sequence, last_operation_id, accepted_at, consent:
/// {version, accepted_at, received_at}}`. `quantity_base` es una cadena
/// decimal entera > 0 en la unidad base del producto, como Sync v1.
class JointPurchaseParticipation {
  const JointPurchaseParticipation({
    required this.status,
    required this.lines,
    required this.lineBaseUnits,
    required this.lastSequence,
    required this.lastOperationId,
    required this.acceptedAt,
    required this.consentVersion,
    required this.consentAcceptedAt,
    required this.consentReceivedAt,
  });

  final String status;

  /// product_ref → cantidad en unidad base (ML/G). Vacío si se retiró.
  final Map<String, int> lines;

  /// product_ref → `ML`/`G` de cada línea.
  final Map<String, String> lineBaseUnits;
  final int lastSequence;
  final String lastOperationId;
  final String acceptedAt;
  final String consentVersion;
  final String consentAcceptedAt;
  final String consentReceivedAt;

  bool get isActive => status == JointPurchaseParticipationStatus.active;

  Map<String, Object?> toJson() => {
    'status': status,
    'lines': [
      for (final entry in lines.entries)
        {
          'product_ref': entry.key,
          'base_unit': lineBaseUnits[entry.key],
          'quantity_base': '${entry.value}',
        },
    ],
    'last_sequence': lastSequence,
    'last_operation_id': lastOperationId,
    'accepted_at': acceptedAt,
    'consent': {
      'version': consentVersion,
      'accepted_at': consentAcceptedAt,
      'received_at': consentReceivedAt,
    },
  };

  String encode() => jsonEncode(toJson());

  static const _keys = {
    'status',
    'lines',
    'last_sequence',
    'last_operation_id',
    'accepted_at',
    'consent',
  };
  static const _lineKeys = {'product_ref', 'base_unit', 'quantity_base'};
  static const _consentKeys = {'version', 'accepted_at', 'received_at'};

  /// [products] (product_ref → unidad base), si se da, limita las líneas a
  /// los productos de la convocatoria con su misma unidad base.
  factory JointPurchaseParticipation.fromJson(
    Object? raw, {
    Map<String, String>? products,
  }) {
    final json = _object(raw);
    _knownKeys(json, _keys);
    final status = _oneOf(json['status'], const {
      JointPurchaseParticipationStatus.active,
      JointPurchaseParticipationStatus.withdrawn,
    });
    final rawLines = json['lines'];
    if (rawLines is! List<dynamic>) _invalid();
    final lines = <String, int>{};
    final baseUnits = <String, String>{};
    for (final item in rawLines) {
      final line = _object(item);
      _knownKeys(line, _lineKeys);
      final ref = line['product_ref'];
      if (ref is! String || !canonicalUuid.hasMatch(ref)) _invalid();
      final baseUnit = _oneOf(line['base_unit'], const {'ML', 'G'});
      if (products != null && products[ref] != baseUnit) _invalid();
      if (lines.containsKey(ref)) _invalid();
      lines[ref] = parseQuantityBase(line['quantity_base']);
      baseUnits[ref] = baseUnit;
    }
    // Activa con líneas; retirada sin ninguna (E2-D8).
    if ((status == JointPurchaseParticipationStatus.active) == lines.isEmpty) {
      _invalid();
    }
    final sequence = json['last_sequence'];
    if (sequence is! int || sequence < 1) _invalid();
    final operationId = json['last_operation_id'];
    if (operationId is! String || !uuidV4Lowercase.hasMatch(operationId)) {
      _invalid();
    }
    final consent = _object(json['consent']);
    _knownKeys(consent, _consentKeys);
    return JointPurchaseParticipation(
      status: status,
      lines: lines,
      lineBaseUnits: baseUnits,
      lastSequence: sequence,
      lastOperationId: operationId,
      acceptedAt: _instant(json['accepted_at']),
      consentVersion: _text(consent['version']),
      consentAcceptedAt: _instant(consent['accepted_at']),
      consentReceivedAt: _instant(consent['received_at']),
    );
  }

  static JointPurchaseParticipation? decode(String? stored) => stored == null
      ? null
      : JointPurchaseParticipation.fromJson(jsonDecode(stored));
}

/// Una convocatoria de la lista del agricultor (`GET /me/joint-purchase-calls`,
/// forma del Backend `FarmerCallView`).
class JointPurchaseCallView {
  const JointPurchaseCallView({
    required this.callId,
    required this.name,
    required this.campaignRef,
    required this.campaignName,
    required this.status,
    required this.openedAt,
    required this.deadlineAt,
    required this.serverTime,
    required this.acceptsOperations,
    required this.responsibleName,
    required this.products,
    required this.participation,
    required this.closingIncluded,
    this.finishedAt,
  });

  final String callId;
  final String name;
  final String campaignRef;
  final String campaignName;
  final String status;
  final String? openedAt;
  final String deadlineAt;
  final String serverTime;

  /// `OPEN` y antes del plazo según la hora del servidor.
  final bool acceptsOperations;
  final String responsibleName;
  final List<JointPurchaseProduct> products;

  /// La participación propia vigente según el servidor; null si no hay.
  final JointPurchaseParticipation? participation;

  /// Sólo en `CLOSED`: si la propia participación entró al consolidado.
  final bool? closingIncluded;

  /// Fecha de término según el sindicato: `closed_at` en `CLOSED`,
  /// `cancelled_at` en `CANCELLED`; null en `OPEN` o si no la envió. Decide
  /// sólo el filtro de presentación (E2 §10.1 a).
  final String? finishedAt;

  bool get isFinished => status != JointPurchaseCallStatus.open;

  /// Lo que el teléfono guarda como «lo aceptado»: en `CLOSED`, la
  /// participación tal como entró al consolidado, o nada si no fue incluida
  /// (E2 §4.2).
  JointPurchaseParticipation? get acceptedForDisplay =>
      closingIncluded == false ? null : participation;

  static const _keys = {
    'call_id',
    'name',
    'status',
    'campaign',
    'opened_at',
    'deadline_at',
    'closed_at',
    'cancelled_at',
    'server_time',
    'accepts_operations',
    'responsible',
    'products',
    'participation',
    'closing',
  };
  static const _campaignKeys = {'campaign_ref', 'name'};
  static const _responsibleKeys = {'name'};
  static const _closingKeys = {'cutoff_at', 'closed_at', 'included', 'lines'};
  static const _closingLineKeys = {'product_ref', 'base_unit', 'quantity_base'};

  factory JointPurchaseCallView.fromJson(Object? raw) {
    final json = _object(raw);
    _knownKeys(json, _keys);
    final callId = json['call_id'];
    if (callId is! String || !uuidV4Lowercase.hasMatch(callId)) _invalid();
    final name = _text(json['name']);
    if (name.length > 120) _invalid();
    final status = _oneOf(json['status'], JointPurchaseCallStatus.all);
    final campaign = _object(json['campaign']);
    _knownKeys(campaign, _campaignKeys);
    final campaignRef = campaign['campaign_ref'];
    if (campaignRef is! String || !canonicalUuid.hasMatch(campaignRef)) {
      _invalid();
    }
    final responsible = _object(json['responsible']);
    _knownKeys(responsible, _responsibleKeys);
    final openedAt = _optionalInstant(json['opened_at']);
    // Abierta ⇒ con fecha de apertura (E2 §3).
    if (status == JointPurchaseCallStatus.open && openedAt == null) _invalid();
    final closedAt = _optionalInstant(json['closed_at']);
    final cancelledAt = _optionalInstant(json['cancelled_at']);
    final accepts = json['accepts_operations'];
    if (accepts is! bool) _invalid();
    if (accepts && status != JointPurchaseCallStatus.open) _invalid();
    final products = JointPurchaseProduct.listFromJson(json['products']);
    final baseUnits = {for (final p in products) p.productRef: p.baseUnit};
    final participation = json['participation'] == null
        ? null
        : JointPurchaseParticipation.fromJson(
            json['participation'],
            products: baseUnits,
          );
    bool? included;
    if (json['closing'] != null) {
      // El consolidado sólo existe en una convocatoria cerrada.
      if (status != JointPurchaseCallStatus.closed) _invalid();
      final closing = _object(json['closing']);
      _knownKeys(closing, _closingKeys);
      _instant(closing['cutoff_at']);
      _instant(closing['closed_at']);
      final flag = closing['included'];
      if (flag is! bool) _invalid();
      final lines = closing['lines'];
      if (lines is! List<dynamic> || flag == lines.isEmpty) _invalid();
      for (final item in lines) {
        final line = _object(item);
        _knownKeys(line, _closingLineKeys);
        final ref = line['product_ref'];
        if (ref is! String || baseUnits[ref] != line['base_unit']) _invalid();
        parseQuantityBase(line['quantity_base']);
      }
      included = flag;
    }
    return JointPurchaseCallView(
      callId: callId,
      name: name,
      campaignRef: campaignRef,
      campaignName: _text(campaign['name']),
      status: status,
      openedAt: openedAt,
      deadlineAt: _instant(json['deadline_at']),
      serverTime: _instant(json['server_time']),
      acceptsOperations: accepts,
      responsibleName: _text(responsible['name']),
      products: products,
      participation: participation,
      closingIncluded: included,
      finishedAt: switch (status) {
        JointPurchaseCallStatus.closed => closedAt,
        JointPurchaseCallStatus.cancelled => cancelledAt,
        _ => null,
      },
    );
  }

  /// La vista por defecto (`GET /me/joint-purchase-calls`), sólo las
  /// convocatorias. Ver [JointPurchaseCallList.fromJson].
  static List<JointPurchaseCallView> listFromJson(Object? raw) =>
      JointPurchaseCallList.fromJson(raw).calls;

  /// Convocatorias sin repetidas.
  static List<JointPurchaseCallView> _calls(Object? raw) {
    if (raw is! List<dynamic>) _invalid();
    final parsed = [
      for (final item in raw) JointPurchaseCallView.fromJson(item),
    ];
    if (parsed.map((c) => c.callId).toSet().length != parsed.length) {
      _invalid();
    }
    return parsed;
  }
}

/// Vista por defecto del agricultor (`GET /me/joint-purchase-calls`, E2
/// §4.2 y §10.1): `{contractVersion: 1, server_time, consent: {version,
/// text}, history: {older_count}, calls: [...]}`.
class JointPurchaseCallList {
  const JointPurchaseCallList({
    required this.serverTime,
    required this.olderCount,
    required this.calls,
  });

  final String serverTime;

  /// Convocatorias terminadas **anteriores** a la ventana de recientes en
  /// las que el agricultor tiene participación (sólo un recuento propio).
  final int olderCount;
  final List<JointPurchaseCallView> calls;

  static const _rootKeys = {
    'contractVersion',
    'server_time',
    'consent',
    'history',
    'calls',
  };

  /// Lista cerrada en la raíz (todas las claves obligatorias). El
  /// consentimiento que anuncia el servidor debe ser exactamente el `CONV-2`
  /// de este teléfono: si cambió, la aplicación tiene que actualizarse antes
  /// de pedir uno nuevo (E2 §10.2).
  factory JointPurchaseCallList.fromJson(Object? raw) {
    final json = _object(raw);
    _knownKeys(json, _rootKeys);
    if (json['contractVersion'] != 1) _invalid();
    final serverTime = _instant(json['server_time']);
    final consent = _object(json['consent']);
    _knownKeys(consent, const {'version', 'text'});
    if (consent['version'] != jointPurchaseConsentVersion ||
        consent['text'] != jointPurchaseConsentText) {
      _invalid();
    }
    final history = _object(json['history']);
    _knownKeys(history, const {'older_count'});
    final olderCount = history['older_count'];
    if (olderCount is! int || olderCount < 0) _invalid();
    return JointPurchaseCallList(
      serverTime: serverTime,
      olderCount: olderCount,
      calls: JointPurchaseCallView._calls(json['calls']),
    );
  }
}

/// Una página de `GET /me/joint-purchase-calls/history` (E2 §10.1):
/// `{contractVersion: 1, server_time, calls: [...], next_cursor}`. Con el
/// mismo rigor que la vista por defecto y, además, sólo convocatorias
/// terminadas (`CLOSED`/`CANCELLED`) con su fecha de término y con
/// participación propia.
class JointPurchaseHistoryPage {
  const JointPurchaseHistoryPage({
    required this.serverTime,
    required this.calls,
    required this.nextCursor,
  });

  final String serverTime;
  final List<JointPurchaseCallView> calls;

  /// Opaco; null si no hay más páginas.
  final String? nextCursor;

  static const _rootKeys = {
    'contractVersion',
    'server_time',
    'calls',
    'next_cursor',
    'consent',
  };

  /// [limit], si se da, es el pedido: una página más larga se rechaza.
  /// `consent`, si viene (el servidor lo envía como en la lista), debe ser
  /// exactamente el vigente de este teléfono.
  factory JointPurchaseHistoryPage.fromJson(Object? raw, {int? limit}) {
    final json = _object(raw);
    _knownKeys(json, _rootKeys, optional: const {'consent'});
    if (json['contractVersion'] != 1) _invalid();
    if (json.containsKey('consent')) {
      final consent = _object(json['consent']);
      _knownKeys(consent, const {'version', 'text'});
      if (consent['version'] != jointPurchaseConsentVersion ||
          consent['text'] != jointPurchaseConsentText) {
        _invalid();
      }
    }
    final serverTime = _instant(json['server_time']);
    final calls = JointPurchaseCallView._calls(json['calls']);
    for (final call in calls) {
      // El historial nunca incluye convocatorias abiertas, y sólo las
      // terminadas con participación propia.
      if (!call.isFinished ||
          call.finishedAt == null ||
          call.participation == null) {
        _invalid();
      }
    }
    if (limit != null && calls.length > limit) _invalid();
    final cursor = json['next_cursor'];
    if (cursor != null &&
        (cursor is! String ||
            !jointPurchaseHistoryCursor.hasMatch(cursor) ||
            calls.isEmpty)) {
      _invalid();
    }
    return JointPurchaseHistoryPage(
      serverTime: serverTime,
      calls: calls,
      nextCursor: cursor as String?,
    );
  }
}

/// Respuesta 2xx de `PUT …/participation` o `POST …/participation/withdraw`:
/// `{outcome: "ACCEPTED", participation}` (`contractVersion: 1` opcional).
/// [products]: product_ref → unidad base de la convocatoria.
JointPurchaseParticipation? parseAcceptedResponse(
  Object? raw,
  Map<String, String> products,
) {
  final json = _object(raw);
  _knownKeys(
    json,
    const {'contractVersion', 'outcome', 'participation'},
    optional: const {'contractVersion'},
  );
  if (json.containsKey('contractVersion') && json['contractVersion'] != 1) {
    _invalid();
  }
  if (json['outcome'] != 'ACCEPTED') _invalid();
  return json['participation'] == null
      ? null
      : JointPurchaseParticipation.fromJson(
          json['participation'],
          products: products,
        );
}

/// Cuerpo de un error del agricultor (E2 §4.2): `{errorCode}` y, según el
/// código, `reason` (`CALL_NOT_OPEN`) o `participation` (`STALE_SEQUENCE`).
class JointPurchaseErrorBody {
  const JointPurchaseErrorBody({
    required this.errorCode,
    this.reason,
    this.participation,
  });

  final String errorCode;
  final String? reason;
  final JointPurchaseParticipation? participation;

  static final _code = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

  /// Null si el cuerpo no tiene la forma esperada para su código.
  static JointPurchaseErrorBody? tryParse(
    Object? raw,
    Map<String, String> products,
  ) {
    try {
      final json = _object(raw);
      final code = json['errorCode'];
      if (code is! String || !_code.hasMatch(code)) _invalid();
      switch (code) {
        case 'CALL_NOT_OPEN':
          _knownKeys(
            json,
            const {'contractVersion', 'errorCode', 'reason'},
            optional: const {'contractVersion'},
          );
          return JointPurchaseErrorBody(
            errorCode: code,
            reason: _oneOf(json['reason'], CallNotOpenReason.all),
          );
        case 'STALE_SEQUENCE':
          _knownKeys(
            json,
            const {'contractVersion', 'errorCode', 'participation'},
            optional: const {'contractVersion'},
          );
          return JointPurchaseErrorBody(
            errorCode: code,
            participation: json['participation'] == null
                ? null
                : JointPurchaseParticipation.fromJson(
                    json['participation'],
                    products: products,
                  ),
          );
        default:
          return JointPurchaseErrorBody(errorCode: code);
      }
    } on JointPurchaseFormatException {
      return null;
    }
  }
}

/// `quantity_base` como cadena decimal entera > 0 sin ceros a la izquierda,
/// dentro del rango de un entero de 64 bits (como Sync v1).
int parseQuantityBase(Object? value) {
  if (value is! String || !_decimal.hasMatch(value)) _invalid();
  final parsed = BigInt.tryParse(value);
  if (parsed == null || parsed > _maxInt64) _invalid();
  return parsed.toInt();
}

final _decimal = RegExp(r'^[1-9][0-9]{0,18}$');
final _maxInt64 = BigInt.parse('9223372036854775807');

Never _invalid() => throw const JointPurchaseFormatException();

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : _invalid();

void _knownKeys(
  Map<String, dynamic> json,
  Set<String> keys, {
  Set<String> optional = const {},
}) {
  if (!keys.containsAll(json.keys)) _invalid();
  for (final key in keys.difference(optional)) {
    if (!json.containsKey(key)) _invalid();
  }
}

String _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : _invalid();

String _oneOf(Object? value, Set<String> allowed) =>
    value is String && allowed.contains(value) ? value : _invalid();

String? _optionalInstant(Object? value) =>
    value == null ? null : _instant(value);

/// Instante ISO-8601 con zona (`Z` u offset): se guarda normalizado en UTC
/// con el formato de Dart, para que las comparaciones de texto en SQLite
/// sean cronológicas.
String _instant(Object? value) {
  if (value is! String || !_zoned.hasMatch(value)) _invalid();
  final parsed = DateTime.tryParse(value);
  if (parsed == null) _invalid();
  return parsed.toUtc().toIso8601String();
}

final _zoned = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
);
