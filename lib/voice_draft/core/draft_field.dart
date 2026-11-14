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

  /// El usuario dio por bueno, a mano, el valor que ya había (eligió en el
  /// selector la misma opción, o confirmó un valor por revisar) sin
  /// cambiarlo (POCO 2026-11-08: «Corregido a mano» sin haber corregido
  /// nada). Se protege igual que [manual]: la voz ya no lo cambia.
  confirmed,
}

final class DraftField<T> {
  const DraftField._({
    required this.status,
    this.value,
    this.origin,
    this.heard,
    this.candidates = const [],
    this.message,
  }) : review = false;

  const DraftField.missing({String? message, String? heard})
    : this._(status: FieldStatus.missing, message: message, heard: heard);

  const DraftField.resolved(
    T this.value, {
    required FieldOrigin this.origin,
    this.heard,
  }) : status = FieldStatus.resolved,
       candidates = const [],
       message = null,
       review = false;

  const DraftField.ambiguous({
    required this.candidates,
    required String this.heard,
    String? message,
    this.value,
  }) : status = FieldStatus.ambiguous,
       origin = FieldOrigin.voice,
       message = message,
       review = false;

  /// Un valor leído que **no se puede dar por bueno sin que la persona lo
  /// mire**: por ejemplo, una cifra en la que los dos reconocedores no
  /// coincidieron (POCO 2026-11-08). Conserva [value] para mostrarlo, pero
  /// bloquea la confirmación igual que un campo ambiguo hasta que la persona
  /// lo confirme o lo corrija ([confirmedByUser] o una edición manual).
  const DraftField.toReview(
    T this.value, {
    required String this.message,
    this.heard,
  }) : status = FieldStatus.ambiguous,
       origin = FieldOrigin.voice,
       candidates = const [],
       review = true;

  const DraftField.invalid({
    required String this.message,
    this.heard,
    this.value,
    this.origin = FieldOrigin.voice,
  }) : status = FieldStatus.invalid,
       candidates = const [],
       review = false;

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

  /// Pendiente de revisión ([DraftField.toReview]). Su estado es
  /// [FieldStatus.ambiguous]: bloquea igual, pero no hay opciones que elegir.
  final bool review;

  bool get isResolved => status == FieldStatus.resolved;

  /// Lo puso, corrigió o confirmó la persona: la voz ya no lo cambia.
  bool get isManual =>
      origin == FieldOrigin.manual || origin == FieldOrigin.confirmed;

  /// El mismo campo marcado para revisión, si su valor lo dio la voz. Lo que
  /// la persona puso o confirmó, lo propuesto y lo que no tiene valor resuelto
  /// quedan igual.
  DraftField<T> markForReview(String message) =>
      status == FieldStatus.resolved && origin == FieldOrigin.voice
      ? DraftField<T>.toReview(value as T, message: message, heard: heard)
      : this;

  /// La persona da por bueno el valor que se ve, sin cambiarlo. Sólo si hay
  /// un valor que confirmar.
  DraftField<T> confirmedByUser() => value == null
      ? this
      : DraftField<T>.resolved(
          value as T,
          origin: FieldOrigin.confirmed,
          heard: heard,
        );

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
