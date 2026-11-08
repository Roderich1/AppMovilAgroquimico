/// Evidencia de dictado con consentimiento para la evaluación de la voz
/// (F09-VOZ-13, MOB #167; RU-12, CU-16, RNF-14; RF-41 y DAT-21 según #167,
/// pendientes de confirmar en el Cap. III).
///
/// Por cada borrador de voz que termina (confirmado, descartado o fallido) se
/// puede guardar, **sólo si la persona dio su consentimiento explícito para
/// la evaluación**:
///
/// - la referencia de la ficha de dictado, si la hay;
/// - la transcripción de cada dictado aplicado al borrador;
/// - los campos tal como los propuso la voz, antes de corregir;
/// - las correcciones manuales, campo a campo;
/// - los campos confirmados (sólo si se confirmó);
/// - el resultado, el motor, el modelo y el commit, si se conocen.
///
/// **Nunca audio**: ni la interfaz ni la tabla tienen dónde ponerlo. Sin
/// consentimiento, nada se guarda. La evidencia no entra en el respaldo
/// privado (F08), no se restaura, no viaja por Sync v1 y no forma parte de
/// lo colectivo.
library;

/// Operación del borrador.
enum VoiceEvidenceKind {
  purchase('PURCHASE'),
  application('APPLICATION'),
  plan('PLAN');

  const VoiceEvidenceKind(this.code);
  final String code;

  static VoiceEvidenceKind fromCode(String code) =>
      values.firstWhere((kind) => kind.code == code);
}

/// Cómo terminó el borrador.
enum VoiceEvidenceOutcome {
  /// La persona confirmó y el caso de uso escribió.
  confirmed('CONFIRMED'),

  /// La persona canceló o salió sin confirmar.
  discarded('DISCARDED'),

  /// La persona confirmó pero la escritura falló.
  failed('FAILED');

  const VoiceEvidenceOutcome(this.code);
  final String code;

  static VoiceEvidenceOutcome fromCode(String code) =>
      values.firstWhere((outcome) => outcome.code == code);
}

/// Un campo del borrador en un momento dado, en forma serializable.
///
/// [path] identifica el campo dentro del borrador durante la sesión: por
/// ejemplo `supplier`, `line[2].product` o `line[2].quantity`. El número de
/// línea es la clave estable de la línea, no su posición.
final class EvidenceField {
  const EvidenceField({
    required this.path,
    required this.status,
    this.origin,
    this.value,
    this.heard,
    this.candidates = const [],
  });

  factory EvidenceField.fromJson(Map<String, Object?> json) => EvidenceField(
    path: json['path']! as String,
    status: json['status']! as String,
    origin: json['origin'] as String?,
    value: json['value'],
    heard: json['heard'] as String?,
    candidates: [
      for (final c in (json['candidates'] as List?) ?? const [])
        (c as Map).cast<String, Object?>(),
    ],
  );

  final String path;

  /// `resolved`, `ambiguous`, `missing` o `invalid` (como `FieldStatus`).
  final String status;

  /// `voice`, `manual`, `preset` (como `FieldOrigin`) o `derived` para un
  /// valor que el borrador deduce de otro (el dueño del chaco).
  final String? origin;

  /// Valor en forma JSON: un número, un texto o un mapa pequeño.
  final Object? value;

  /// Lo oído que originó el campo, si lo hay.
  final String? heard;

  /// Opciones de un campo ambiguo: `{id, name}`.
  final List<Map<String, Object?>> candidates;

  Map<String, Object?> toJson() => {
    'path': path,
    'status': status,
    if (origin != null) 'origin': origin,
    if (value != null) 'value': value,
    if (heard != null) 'heard': heard,
    if (candidates.isNotEmpty) 'candidates': candidates,
  };

  /// Mismo contenido (estado y valor), sin mirar el origen ni lo oído.
  bool sameContentAs(EvidenceField other) =>
      status == other.status && _deepEquals(value, other.value);
}

/// Una corrección manual de un campo propuesto por la voz.
enum CorrectionKind {
  /// La voz propuso un valor y quedó otro.
  changed('CHANGED'),

  /// La voz no propuso el campo y la persona lo completó a mano.
  added('ADDED'),

  /// La voz propuso el campo y la persona lo quitó (por ejemplo, la línea).
  removed('REMOVED'),

  /// La persona lo tocó a mano y dejó el mismo valor propuesto.
  reaffirmed('REAFFIRMED');

  const CorrectionKind(this.code);
  final String code;
}

final class EvidenceCorrection {
  const EvidenceCorrection({
    required this.path,
    required this.kind,
    this.proposed,
    this.finalField,
  });

  final String path;
  final CorrectionKind kind;
  final EvidenceField? proposed;
  final EvidenceField? finalField;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.code,
    if (proposed != null) 'proposed': proposed!.toJson(),
    if (finalField != null) 'final': finalField!.toJson(),
  };
}

/// Lo que se entrega al sumidero cuando un borrador termina.
final class VoiceEvidenceEntry {
  const VoiceEvidenceEntry({
    required this.kind,
    required this.outcome,
    required this.transcripts,
    required this.proposed,
    required this.corrections,
    this.confirmed,
    this.sheetRef,
    this.engine,
    this.model,
    this.appCommit,
    this.firstPartialMs,
    this.finalMs,
    this.dictationStartedAt,
  });

  final VoiceEvidenceKind kind;
  final VoiceEvidenceOutcome outcome;

  /// Texto final de cada dictado aplicado al borrador, en orden.
  final List<String> transcripts;

  /// Campos tal como los dejó la voz, antes de cualquier corrección.
  final List<EvidenceField> proposed;

  /// Diferencias entre lo propuesto y el borrador final.
  final List<EvidenceCorrection> corrections;

  /// Campos del borrador confirmado. Sólo con [VoiceEvidenceOutcome.confirmed].
  final List<EvidenceField>? confirmed;

  /// Referencia de la ficha de dictado de la evaluación, si la hay.
  final String? sheetRef;

  /// Motor (`local`, `android`), modelo y commit de la compilación, si se
  /// conocen. Nunca se suponen.
  final String? engine;
  final String? model;
  final String? appCommit;

  /// Tiempo hasta el primer texto parcial y hasta el texto final del primer
  /// dictado, en ms, si se midieron. `null` es NOT_MEASURED, no cero.
  final int? firstPartialMs;
  final int? finalMs;

  /// Cuándo empezó el primer dictado. Si el consentimiento vigente es
  /// posterior, no cubre este dictado y no se guarda.
  final DateTime? dictationStartedAt;
}

/// Resultado de entregar una entrada al sumidero.
enum VoiceEvidenceRecordResult {
  /// Guardada.
  stored,

  /// No hay consentimiento: no se guardó nada.
  noConsent,

  /// El consentimiento vigente se dio después de empezar el dictado.
  consentAfterDictation,

  /// La entrada no es coherente (por ejemplo, confirmados sin confirmar).
  rejected,

  /// No se pudo guardar. No se registra el contenido en ningún log.
  failed,
}

/// El punto donde la capa de presentación entrega la evidencia al terminar un
/// borrador de voz. **Nunca lanza**: la evidencia no puede romper la
/// confirmación ni el descarte.
abstract interface class VoiceEvidenceSink {
  Future<VoiceEvidenceRecordResult> record(VoiceEvidenceEntry entry);
}

/// Sumidero que no guarda nada. Es el valor por defecto.
final class NullVoiceEvidenceSink implements VoiceEvidenceSink {
  const NullVoiceEvidenceSink();

  @override
  Future<VoiceEvidenceRecordResult> record(VoiceEvidenceEntry entry) async =>
      VoiceEvidenceRecordResult.noConsent;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
