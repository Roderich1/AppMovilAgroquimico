/// Un campo del borrador tipado (EVO-010 «Estados de resolución», #16).
library;

import '../catalog/voice_catalog.dart';

/// Estado de un campo. Sólo [resolved] deja confirmar.
enum FieldStatus { resolved, ambiguous, missing, invalid }

/// De dónde salió el valor.
enum FieldOrigin {
  /// Lo interpretó la voz.
  voice,

  /// Lo puso o corrigió el usuario. **Una edición manual no la sobrescribe la
  /// voz** (RF-29): un resultado tardío que alude al campo se descarta y se
  /// cuenta.
  manual,

  /// Valor propuesto y visible: la campaña activa, la fecha de hoy o el
  /// titular en PERSONAL. Se puede cambiar por voz o a mano.
  preset,
}

final class DraftField<T> {
  const DraftField._({
    required this.status,
    this.value,
    this.origin,
    this.heard,
    this.candidates = const [],
    this.message,
  });

  const DraftField.missing({String? message, String? heard})
    : this._(status: FieldStatus.missing, message: message, heard: heard);

  const DraftField.resolved(
    T this.value, {
    required FieldOrigin this.origin,
    this.heard,
  }) : status = FieldStatus.resolved,
       candidates = const [],
       message = null;

  const DraftField.ambiguous({
    required this.candidates,
    required String this.heard,
    String? message,
    this.value,
  }) : status = FieldStatus.ambiguous,
       origin = FieldOrigin.voice,
       message = message;

  const DraftField.invalid({
    required String this.message,
    this.heard,
    this.value,
    this.origin = FieldOrigin.voice,
  }) : status = FieldStatus.invalid,
       candidates = const [];

  final FieldStatus status;

  /// Valor resuelto. En un campo ambiguo puede llevar la lectura propuesta
  /// (por ejemplo, un precio que no se sabe si es unitario o total).
  final T? value;

  final FieldOrigin? origin;

  /// Texto oído que originó el campo, para mostrarlo durante la sesión.
  final String? heard;

  /// Opciones para elegir, en un campo ambiguo.
  final List<CatalogEntry> candidates;

  /// Explicación para el usuario.
  final String? message;

  bool get isResolved => status == FieldStatus.resolved;
  bool get isManual => origin == FieldOrigin.manual;

  /// Aplica un valor que llega por voz. Si el campo lo editó el usuario, se
  /// conserva el actual y se devuelve `null` para que el llamante cuente el
  /// descarte; si no, gana [incoming].
  DraftField<T>? mergeVoice(DraftField<T> incoming) =>
      isManual ? null : incoming;
}

/// Resultado de aplicar un parche de voz.
final class VoicePatchOutcome {
  const VoicePatchOutcome({this.applied = 0, this.keptManual = 0});

  /// Campos que cambió la voz.
  final int applied;

  /// Campos que la voz quería cambiar y no cambió porque el usuario los había
  /// editado.
  final int keptManual;

  VoicePatchOutcome operator +(VoicePatchOutcome other) => VoicePatchOutcome(
    applied: applied + other.applied,
    keptManual: keptManual + other.keptManual,
  );
}

/// Aplica [incoming] sobre [current] respetando la edición manual.
(DraftField<T>, VoicePatchOutcome) mergeField<T>(
  DraftField<T> current,
  DraftField<T>? incoming,
) {
  if (incoming == null) return (current, const VoicePatchOutcome());
  final merged = current.mergeVoice(incoming);
  if (merged == null) return (current, const VoicePatchOutcome(keptManual: 1));
  return (merged, const VoicePatchOutcome(applied: 1));
}
