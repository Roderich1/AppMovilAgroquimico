// Convocatorias de compra conjunta vistas por el agricultor (contrato E2 §4.2
// y §5). Sólo forma y validación: sin base de datos ni red.
//
// Lista cerrada en todos los niveles: una clave desconocida —por ejemplo,
// un dato de otro agricultor o un total institucional— rechaza la respuesta
// ENTERA, sin guardar nada parcial.
import 'dart:convert';

import 'operation_id.dart';

/// Versión del contrato de las rutas del agricultor que lee este teléfono
/// (E4 §3.3: acceso por rol y consentimiento `CONV-4`). Se pide con
/// [jointPurchaseContractHeader]; una respuesta con otra versión es una
/// incompatibilidad de versión («Actualice la aplicación», E4 §7.1), no un
/// fallo temporal.
///
/// Versión mínima compatible con el servidor de E4: la primera compilación
/// que lee el contrato 4 y abre la base con el esquema SQLite v20
/// (`AppDatabase.jointPurchaseRoleAccessSinceVersion`).
const int jointPurchaseContractVersion = 4;
const String jointPurchaseContractHeader = 'X-Joint-Purchase-Contract';

/// Versión vigente del texto de consentimiento de la participación (E4
/// §4.1). Aceptarla al participar por primera vez da el alcance
/// `ADMINISTRATION`; las operaciones preparadas antes con `CONV-1`, `CONV-2`
/// o `CONV-3` se envían tal como se guardaron y el sindicato las acepta con
/// el alcance de su texto, nunca como `CONV-4` (E4 §7.2).
const String jointPurchaseConsentVersion = 'CONV-4';

/// Texto exacto `CONV-4`, copiado byte a byte de
/// `E4_EJEMPLOS_RESPUESTAS.md` §0 (`CONSENT_V4_TEXT` del Backend). Si el
/// texto cambia, cambia la versión.
const String jointPurchaseConsentText =
    'Las personas de Administración habilitadas de su sindicato podrán ver su '
    'nombre y las cantidades que solicita para coordinar esta compra conjunta '
    'y su entrega. La Directiva podrá consultar los totales por producto, sin '
    'el detalle identificado de su participación. Los totales pueden '
    'mostrarse aunque participe una sola persona. Esta participación no '
    'genera una deuda.';

/// Ayuda exacta de `CONV-4` (`CONSENT_V4_HELP`, E4 §4.1): forma parte del
/// texto aceptado; si cambia, cambia la versión.
const String jointPurchaseConsentHelp =
    'Aunque el total no muestre nombres, con pocas participaciones podría '
    'deducirse cuánto solicitó una persona.';

/// Versión anterior (2026-11-12, P-C): sólo la llevan operaciones y
/// participaciones guardadas antes de E4.
const String jointPurchaseConsentV3Version = 'CONV-3';

/// Versión anterior (2026-11-11): su texto ya cubría a los colaboradores.
const String jointPurchaseConsentV2Version = 'CONV-2';

/// Alcance del consentimiento vigente según el servidor (E4 §4.2).
abstract final class JointPurchaseConsentScope {
  /// Anterior a E4 (`CONV-1`, `CONV-3` o una reducción): nadie ve el
  /// detalle identificado; no cubre los totales con pocas personas.
  static const responsibleOnly = 'RESPONSIBLE_ONLY';

  /// Anterior a E4 (`CONV-2` o una ampliación): ya no se puede obtener
  /// (`409 CONSENT_VERSION_RETIRED`); nadie ve el detalle identificado.
  static const collaborators = 'COLLABORATORS';

  /// `CONV-4`: la Administración habilitada ve el nombre y las cantidades;
  /// la Directiva, sólo los totales.
  static const administration = 'ADMINISTRATION';

  /// D-05: el agricultor retiró la autorización `CONV-4` sin retirar su
  /// participación. Nadie ve el detalle; los totales sí la cuentan.
  static const totalsOnly = 'TOTALS_ONLY';

  static const all = {
    responsibleOnly,
    collaborators,
    administration,
    totalsOnly,
  };

  /// Alcances anteriores a E4: la participación se puede revisar con
  /// «Revisar quién puede ver mi participación».
  static const legacy = {responsibleOnly, collaborators};

  /// Las decisiones que el teléfono prepara desde E4 (cola v20).
  static const decisions = {administration, totalsOnly};
}

/// Versión anterior (E2-D9): sólo la llevan operaciones guardadas antes de
/// actualizar la aplicación. Nunca se ofrece para una confirmación nueva.
const String jointPurchaseLegacyConsentVersion = 'CONV-1';

/// Alcance con que el sindicato crea una participación nueva según el texto
/// que aceptó (E4 §3.3 y §7.2): `CONV-4` → `ADMINISTRATION`; `CONV-2` →
/// `COLLABORATORS`; las demás → `RESPONSIBLE_ONLY`.
String initialConsentScope(String consentVersion) => switch (consentVersion) {
  jointPurchaseConsentVersion => JointPurchaseConsentScope.administration,
  jointPurchaseConsentV2Version => JointPurchaseConsentScope.collaborators,
  _ => JointPurchaseConsentScope.responsibleOnly,
};

/// Códigos de rechazo definitivos del agricultor añadidos o usados por E4
/// (§3.3, §4.2 y §7.2). Ninguno lleva datos de otras personas; repetir la
/// misma operación devuelve el mismo código, así que nunca se reintentan.
abstract final class JointPurchaseErrorCodes {
  static const consentVersionRetired = 'CONSENT_VERSION_RETIRED';
  static const appUpdateRequired = 'APP_UPDATE_REQUIRED';
  static const wideningNotAllowed = 'WIDENING_NOT_ALLOWED';
  static const participationRequired = 'PARTICIPATION_REQUIRED';
  static const definitive = {
    consentVersionRetired,
    appUpdateRequired,
    wideningNotAllowed,
  };
}

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

/// N7 (E2 §10.6): el sindicato habla otra versión del contrato o publica
/// otro texto de consentimiento que este teléfono no conoce. No es un fallo
/// temporal: hay que actualizar la aplicación. Se rechaza entera, como
/// cualquier respuesta fuera de contrato.
class JointPurchaseVersionException extends JointPurchaseFormatException {
  const JointPurchaseVersionException();
  @override
  String toString() =>
      'El sindicato usa una versión de las compras conjuntas que esta '
      'aplicación no conoce.';
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
    required this.consentScope,
    required this.consentScopeVersion,
    required this.consentScopeSequence,
    this.consentScopeDecidedAt,
    this.consentScopeReceivedAt,
    this.responsibleAuthorized,
    this.responsibleAuthorizationVersion,
  });

  final String status;

  /// product_ref → cantidad en unidad base (ML/G). Vacío si se retiró.
  final Map<String, int> lines;

  /// product_ref → `ML`/`G` de cada línea.
  final Map<String, String> lineBaseUnits;
  final int lastSequence;
  final String lastOperationId;
  final String acceptedAt;

  /// Texto aceptado al participar por primera vez (nunca se reescribe).
  final String consentVersion;
  final String consentAcceptedAt;
  final String consentReceivedAt;

  /// E2 §10.6: alcance vigente en el servidor, la versión citada por la
  /// decisión que lo fijó y su orden (0 = la aceptación inicial). Una copia
  /// guardada antes de §10.6 no lo trae: se deduce de su texto (`CONV-2`
  /// cubría a los colaboradores; `CONV-1`, no).
  final String consentScope;
  final String consentScopeVersion;
  final int consentScopeSequence;
  final String? consentScopeDecidedAt;
  final String? consentScopeReceivedAt;

  /// P-A C1 (E2 §12), **sólo historia**: lo que dijo el contrato 3 sobre la
  /// autorización de la persona responsable, en copias guardadas antes de
  /// E4. Desde E4 no decide quién ve nada (E4 §6.3) y el contrato 4 ya no lo
  /// envía; se conserva para no perder lo guardado.
  final bool? responsibleAuthorized;
  final int? responsibleAuthorizationVersion;

  bool get isActive => status == JointPurchaseParticipationStatus.active;

  /// E4 §4.2: la Administración habilitada ve el nombre y las cantidades.
  bool get coversDetail =>
      consentScope == JointPurchaseConsentScope.administration;

  /// Alcance anterior a E4: nadie ve el detalle identificado hasta que el
  /// agricultor revise quién puede ver su participación.
  bool get hasLegacyScope =>
      JointPurchaseConsentScope.legacy.contains(consentScope);

  /// La misma participación con el alcance de [other] (para no perder una
  /// decisión más nueva al adoptar una respuesta de cantidades más nueva).
  JointPurchaseParticipation withScopeOf(JointPurchaseParticipation other) =>
      JointPurchaseParticipation(
        status: status,
        lines: lines,
        lineBaseUnits: lineBaseUnits,
        lastSequence: lastSequence,
        lastOperationId: lastOperationId,
        acceptedAt: acceptedAt,
        consentVersion: consentVersion,
        consentAcceptedAt: consentAcceptedAt,
        consentReceivedAt: consentReceivedAt,
        consentScope: other.consentScope,
        consentScopeVersion: other.consentScopeVersion,
        consentScopeSequence: other.consentScopeSequence,
        consentScopeDecidedAt: other.consentScopeDecidedAt,
        consentScopeReceivedAt: other.consentScopeReceivedAt,
        // Historia de P-A (contrato 3): si [other] no la trae (contrato 4),
        // se conserva la guardada.
        responsibleAuthorized:
            other.responsibleAuthorized ?? responsibleAuthorized,
        responsibleAuthorizationVersion: other.responsibleAuthorized != null
            ? other.responsibleAuthorizationVersion
            : responsibleAuthorizationVersion,
      );

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
    'consent_scope': {
      'scope': consentScope,
      'version': consentScopeVersion,
      'decided_at': consentScopeDecidedAt,
      'received_at': consentScopeReceivedAt,
      'sequence': consentScopeSequence,
    },
    if (responsibleAuthorized != null)
      'responsible_authorization': {
        'authorized': responsibleAuthorized,
        'version': responsibleAuthorizationVersion,
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
  static const _scopeKeys = {
    'scope',
    'version',
    'decided_at',
    'received_at',
    'sequence',
  };

  /// [products] (product_ref → unidad base), si se da, limita las líneas a
  /// los productos de la convocatoria con su misma unidad base.
  ///
  /// [stored]: una copia guardada en el teléfono, que puede traer
  /// `responsible_authorization` (contrato 3, historia). En una respuesta
  /// del sindicato (contrato 4) esa clave ya no existe y se rechaza, como
  /// cualquier clave desconocida.
  factory JointPurchaseParticipation.fromJson(
    Object? raw, {
    Map<String, String>? products,
    bool stored = false,
  }) {
    final json = _object(raw);
    _knownKeys(
      json,
      {..._keys, 'consent_scope', if (stored) 'responsible_authorization'},
      optional: const {'consent_scope', 'responsible_authorization'},
    );
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
    final consentVersion = _text(consent['version']);
    final consentAcceptedAt = _instant(consent['accepted_at']);
    final consentReceivedAt = _instant(consent['received_at']);
    final String scope;
    final String scopeVersion;
    final int scopeSequence;
    String? scopeDecidedAt;
    String? scopeReceivedAt;
    if (json['consent_scope'] == null) {
      // Copia anterior a §10.6: el alcance de su texto, orden 0.
      scope = initialConsentScope(consentVersion);
      scopeVersion = consentVersion;
      scopeSequence = 0;
    } else {
      final scoped = _object(json['consent_scope']);
      _knownKeys(scoped, _scopeKeys);
      scope = _oneOf(scoped['scope'], JointPurchaseConsentScope.all);
      scopeVersion = _text(scoped['version']);
      final order = scoped['sequence'];
      if (order is! int || order < 0) _invalid();
      scopeSequence = order;
      scopeDecidedAt = _optionalInstant(scoped['decided_at']);
      scopeReceivedAt = _optionalInstant(scoped['received_at']);
    }
    bool? authorized;
    int? authorizedVersion;
    if (json['responsible_authorization'] != null) {
      final authorization = _object(json['responsible_authorization']);
      _knownKeys(authorization, const {'authorized', 'version'});
      final flag = authorization['authorized'];
      final version = authorization['version'];
      if (flag is! bool) _invalid();
      if (version != null && (version is! int || version < 1)) _invalid();
      // Autorizada exige una versión concreta.
      if (flag && version == null) _invalid();
      authorized = flag;
      authorizedVersion = version as int?;
    }
    return JointPurchaseParticipation(
      status: status,
      lines: lines,
      lineBaseUnits: baseUnits,
      lastSequence: sequence,
      lastOperationId: operationId,
      acceptedAt: _instant(json['accepted_at']),
      consentVersion: consentVersion,
      consentAcceptedAt: consentAcceptedAt,
      consentReceivedAt: consentReceivedAt,
      consentScope: scope,
      consentScopeVersion: scopeVersion,
      consentScopeSequence: scopeSequence,
      consentScopeDecidedAt: scopeDecidedAt,
      consentScopeReceivedAt: scopeReceivedAt,
      responsibleAuthorized: authorized,
      responsibleAuthorizationVersion: authorizedVersion,
    );
  }

  static JointPurchaseParticipation? decode(String? stored) => stored == null
      ? null
      : JointPurchaseParticipation.fromJson(jsonDecode(stored), stored: true);
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

  /// Contrato 4 (E4 §3.3): sólo el nombre de quien coordina, sin versión de
  /// la responsabilidad (la responsabilidad ya no decide el acceso).
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
/// §4.2, §10.1 y E4 §3.3): `{contractVersion: 4, server_time, consent:
/// {version, text, help}, history: {older_count}, calls: [...]}`.
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
  /// consentimiento que anuncia el servidor debe ser exactamente el `CONV-4`
  /// de este teléfono, con su ayuda: si cambió, la aplicación tiene que
  /// actualizarse antes de pedir uno nuevo (E2 §10.2, E4 §4.1).
  factory JointPurchaseCallList.fromJson(Object? raw) {
    final json = _object(raw);
    _requireContract(json);
    _knownKeys(json, _rootKeys);
    final serverTime = _instant(json['server_time']);
    _requireConsent(json['consent']);
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
    _requireContract(json);
    _knownKeys(json, _rootKeys, optional: const {'consent'});
    if (json.containsKey('consent')) _requireConsent(json['consent']);
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
  if (json.containsKey('contractVersion')) _requireContract(json);
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
    this.responsibleVersion,
  });

  final String errorCode;
  final String? reason;
  final JointPurchaseParticipation? participation;

  /// P-A: la versión vigente de la responsabilidad (`RESPONSIBLE_CHANGED`,
  /// `AUTHORIZATION_REQUIRED`).
  final int? responsibleVersion;

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
        case 'RESPONSIBLE_CHANGED':
        case 'AUTHORIZATION_REQUIRED':
          _knownKeys(
            json,
            const {
              'contractVersion',
              'errorCode',
              'responsible_version',
              'participation',
            },
            optional: const {'contractVersion', 'participation'},
          );
          final version = json['responsible_version'];
          if (version is! int || version < 1) _invalid();
          return JointPurchaseErrorBody(
            errorCode: code,
            responsibleVersion: version,
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

/// N7: otra versión del contrato es una incompatibilidad de versión.
void _requireContract(Map<String, dynamic> json) {
  final version = json['contractVersion'];
  if (version is! int) _invalid();
  if (version != jointPurchaseContractVersion) {
    throw const JointPurchaseVersionException();
  }
}

/// El consentimiento publicado debe ser exactamente el vigente de este
/// teléfono (versión, texto y ayuda); otro texto, otra ayuda u otra versión
/// exigen actualizar la aplicación (N7, E4 §4.1).
void _requireConsent(Object? raw) {
  final consent = _object(raw);
  _knownKeys(consent, const {'version', 'text', 'help'});
  if (consent['version'] is! String ||
      consent['text'] is! String ||
      consent['help'] is! String) {
    _invalid();
  }
  if (consent['version'] != jointPurchaseConsentVersion ||
      consent['text'] != jointPurchaseConsentText ||
      consent['help'] != jointPurchaseConsentHelp) {
    throw const JointPurchaseVersionException();
  }
}

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
