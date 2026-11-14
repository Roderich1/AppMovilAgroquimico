/// Incorporación de un dictado a un formulario normal (F09, formulario único).
///
/// El formulario es el único borrador de la operación. Un dictado no lo
/// escribe directamente: el intérprete de la operación produce una
/// [VoiceProposal] (lo que dijo ese dictado, y nada más) y [planVoiceMerge]
/// decide, campo a campo, qué se completa, qué se conserva, qué se pregunta y
/// qué se añade como línea nueva, comparando con dos fotos del formulario:
/// la de antes del turno ([FormSnapshot] `before`) y la de ahora (`now`).
///
/// Reglas (explícitas y probadas en `test/voice_draft/form_merge_test.dart`):
/// - Campo vacío y valor inequívoco → se completa y se marca «por voz».
/// - Campo con el mismo valor → se conserva, sin duplicar.
/// - Campo con otro valor → se pide elegir ([PendingChoice]); nunca se
///   sobrescribe solo.
/// - Valor ambiguo o por revisar → se pide revisar ([PendingReview]); el campo
///   no cambia hasta que la persona elige.
/// - Lo que el dictado no dijo → se conserva lo que había.
/// - Campo que la persona cambió mientras se procesaba el audio → gana la
///   persona ([MergePlan.keptEdited]).
/// - Una línea dictada con producto va a la primera línea completamente vacía
///   que ya existía o a una línea nueva, que se muestra como añadida.
/// - Una línea dictada sin producto completa la última línea si ésta tiene
///   producto y le falta alguno de esos datos; si no, va a una línea nueva.
/// - Producto repetido: nunca se suman ni se fusionan líneas por coincidir el
///   nombre; la línea nueva queda con el producto «por revisar».
/// - Un dictado sin nada aplicable (negación, intención de otra operación,
///   ruido) no cambia nada.
///
/// [planVoiceUndo] deshace sólo lo atribuible a un dictado: restaura cada
/// campo que sigue con el valor que puso la voz y quita las líneas que añadió
/// mientras nadie las haya tocado; lo editado después se conserva y se
/// informa.
library;

/// Clave de un campo: de la cabecera (`line == null`) o de una línea.
final class SlotRef {
  const SlotRef.header(this.field) : line = null;
  const SlotRef.line(int this.line, this.field);

  /// Identificador estable de la línea en el formulario (no su posición).
  final int? line;
  final String field;

  @override
  bool operator ==(Object other) =>
      other is SlotRef && other.line == line && other.field == field;

  @override
  int get hashCode => Object.hash(line, field);

  @override
  String toString() => line == null ? field : '$field@$line';
}

/// Una línea del formulario: identificador estable y valores canónicos de sus
/// campos (`null` = vacío).
final class LineSnapshot {
  const LineSnapshot(this.id, this.fields);
  final int id;
  final Map<String, Object?> fields;

  bool get isBlank => fields.values.every((v) => v == null);
}

/// Foto del formulario en valores canónicos comparables (`null` = vacío).
final class FormSnapshot {
  const FormSnapshot({this.header = const {}, this.lines = const []});
  final Map<String, Object?> header;
  final List<LineSnapshot> lines;

  LineSnapshot? line(int id) {
    for (final l in lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Valor actual de [ref]; `(false, null)` si la línea ya no existe.
  (bool, Object?) valueOf(SlotRef ref) {
    if (ref.line == null) return (true, header[ref.field]);
    final l = line(ref.line!);
    return l == null ? (false, null) : (true, l.fields[ref.field]);
  }
}

/// Una opción para resolver una revisión.
final class ReviewOption {
  const ReviewOption(this.label, this.value, {this.enabled = true, this.hint});
  final String label;
  final Object? value;
  final bool enabled;

  /// Por qué la opción no está disponible todavía (p. ej. falta la cantidad).
  final String? hint;
}

/// El dictado dio algo que la persona debe revisar o elegir.
final class VoiceReview {
  const VoiceReview(this.message, {this.options = const []});
  final String message;
  final List<ReviewOption> options;
}

/// Lo que dijo el dictado para un campo.
final class ProposedValue {
  const ProposedValue(this.value, {required this.display, this.review})
    : assert(value != null || review != null);

  /// Valor canónico. `null` sólo si el campo queda por revisar sin valor.
  final Object? value;

  /// Cómo se muestra el valor propuesto («2 L», «Agro insumos DEMO»).
  final String display;

  /// No se aplica solo: la persona revisa o elige.
  final VoiceReview? review;

  bool get needsReview => review != null;
}

/// Una línea dictada. [anchor] es el campo que identifica la línea (el
/// producto); puede venir por revisar.
final class ProposedLine {
  const ProposedLine(this.fields, {this.anchor = 'product'});
  final Map<String, ProposedValue> fields;
  final String anchor;

  bool get hasAnchor => fields[anchor] != null;
}

/// Todo lo que dijo un dictado.
final class VoiceProposal {
  const VoiceProposal({
    this.header = const {},
    this.lines = const [],
    this.notices = const [],
  });
  final Map<String, ProposedValue> header;
  final List<ProposedLine> lines;

  /// Avisos del intérprete sin efecto en los campos (otra intención, precio
  /// sin línea clara…). Se muestran; no bloquean.
  final List<String> notices;

  bool get isEmpty => header.isEmpty && lines.isEmpty;
}

/// Un campo que el dictado completa.
final class FieldChange {
  const FieldChange(this.slot, this.before, this.after, this.display);
  final SlotRef slot;
  final Object? before;
  final Object? after;
  final String display;
}

/// Una línea que el dictado añade. [line] es su identificador nuevo (lo
/// asigna quien llama con `nextLineId`).
final class NewLine {
  const NewLine(this.line, this.values, {this.repeatOf});
  final int line;

  /// Valores que se ponen al crearla (sólo los inequívocos).
  final Map<String, Object?> values;

  /// Posición (1…n) de la línea que ya tenía el mismo producto, si lo hay.
  final int? repeatOf;
}

/// El dictado dio otro valor para un campo que ya tenía uno.
final class PendingChoice {
  const PendingChoice({
    required this.slot,
    required this.current,
    required this.proposed,
    required this.proposedDisplay,
  });
  final SlotRef slot;
  final Object? current;
  final Object? proposed;
  final String proposedDisplay;
}

/// El dictado dio un valor que no se aplica sin revisión.
final class PendingReview {
  const PendingReview({required this.slot, required this.review, this.display});
  final SlotRef slot;
  final VoiceReview review;

  /// Lo que se oyó, para mostrarlo junto a la pregunta.
  final String? display;
}

/// Resultado de [planVoiceMerge]: lo que el formulario debe aplicar.
final class MergePlan {
  const MergePlan({
    this.changes = const [],
    this.newLines = const [],
    this.choices = const [],
    this.reviews = const [],
    this.keptEdited = const [],
    this.unchanged = 0,
    this.notices = const [],
  });
  final List<FieldChange> changes;
  final List<NewLine> newLines;
  final List<PendingChoice> choices;
  final List<PendingReview> reviews;

  /// Campos que la persona editó durante el procesamiento: no se tocan.
  final List<SlotRef> keptEdited;

  /// Campos dictados que ya tenían ese mismo valor.
  final int unchanged;
  final List<String> notices;

  bool get changesNothing =>
      changes.isEmpty && newLines.isEmpty && choices.isEmpty && reviews.isEmpty;

  bool get hasPending => choices.isNotEmpty || reviews.isNotEmpty;
}

/// Decide cómo se incorpora [proposal] al formulario (ver reglas arriba).
///
/// [before] es la foto tomada al empezar el turno y [now] la actual. Las
/// líneas nuevas reciben identificadores desde [nextLineId].
MergePlan planVoiceMerge({
  required FormSnapshot before,
  required FormSnapshot now,
  required VoiceProposal proposal,
  required int nextLineId,
}) {
  final changes = <FieldChange>[];
  final newLines = <NewLine>[];
  final choices = <PendingChoice>[];
  final reviews = <PendingReview>[];
  final kept = <SlotRef>[];
  var unchanged = 0;
  var nextId = nextLineId;

  bool editedDuringTurn(SlotRef slot) {
    final (wasThere, was) = before.valueOf(slot);
    final (isThere, is_) = now.valueOf(slot);
    if (!wasThere) return isThere; // línea creada a mano durante el turno
    return !isThere || was != is_;
  }

  void field(SlotRef slot, ProposedValue p) {
    if (editedDuringTurn(slot)) {
      kept.add(slot);
      return;
    }
    final (_, current) = now.valueOf(slot);
    if (p.needsReview) {
      // Lo dudoso nunca cambia un campo; si coincide con lo que ya hay, no
      // hay nada que revisar.
      if (p.value != null && p.value == current) {
        unchanged++;
        return;
      }
      reviews.add(
        PendingReview(slot: slot, review: p.review!, display: p.display),
      );
      return;
    }
    if (current == null) {
      changes.add(FieldChange(slot, null, p.value, p.display));
    } else if (current == p.value) {
      unchanged++;
    } else {
      choices.add(
        PendingChoice(
          slot: slot,
          current: current,
          proposed: p.value,
          proposedDisplay: p.display,
        ),
      );
    }
  }

  proposal.header.forEach((name, p) => field(SlotRef.header(name), p));

  // Productos ya presentes (resueltos), por línea: para no repetirlos.
  final productLine = <Object, int>{};
  for (var i = 0; i < now.lines.length; i++) {
    final l = now.lines[i];
    for (final entry in l.fields.entries) {
      // Sólo el ancla de las líneas (el producto) identifica una línea.
      if (entry.key == 'product' && entry.value != null) {
        productLine.putIfAbsent(entry.value!, () => i + 1);
      }
    }
  }
  final usedBlank = <int>{};

  void newLine(ProposedLine pl) {
    final id = nextId++;
    final values = <String, Object?>{};
    int? repeatOf;
    for (final entry in pl.fields.entries) {
      final p = entry.value;
      final slot = SlotRef.line(id, entry.key);
      if (entry.key == pl.anchor && !p.needsReview && p.value != null) {
        final previous = productLine[p.value!];
        if (previous != null) {
          // Producto repetido: no se suma ni se fusiona; se pregunta.
          repeatOf = previous;
          reviews.add(
            PendingReview(
              slot: slot,
              display: p.display,
              review: VoiceReview(
                '«${p.display}» ya está en la línea $previous. Las líneas no '
                'se suman: elija otro producto, corrija la línea '
                '$previous o quite esta.',
              ),
            ),
          );
          continue;
        }
        productLine[p.value!] = now.lines.length + newLines.length + 1;
      }
      if (p.needsReview) {
        reviews.add(
          PendingReview(slot: slot, review: p.review!, display: p.display),
        );
      } else {
        values[entry.key] = p.value;
      }
    }
    newLines.add(NewLine(id, values, repeatOf: repeatOf));
  }

  for (final pl in proposal.lines) {
    if (pl.hasAnchor) {
      // La primera línea completamente vacía que ya existía antes del turno
      // (p. ej. la línea inicial del formulario) se usa; si no, una nueva.
      final blank = now.lines
          .where(
            (l) =>
                l.isBlank &&
                !usedBlank.contains(l.id) &&
                (before.line(l.id)?.isBlank ?? false),
          )
          .firstOrNull;
      final anchor = pl.fields[pl.anchor]!;
      final repeated =
          !anchor.needsReview &&
          anchor.value != null &&
          productLine.containsKey(anchor.value!);
      if (blank != null && !repeated) {
        usedBlank.add(blank.id);
        if (!anchor.needsReview && anchor.value != null) {
          productLine[anchor.value!] = now.lines.indexOf(blank) + 1;
        }
        pl.fields.forEach((name, p) => field(SlotRef.line(blank.id, name), p));
      } else {
        newLine(pl);
      }
      continue;
    }
    // Sin producto: completa la última línea si tiene producto y le falta
    // alguno de estos datos.
    final last = now.lines.lastOrNull;
    final fits =
        last != null &&
        !usedBlank.contains(last.id) &&
        last.fields[pl.anchor] != null &&
        pl.fields.keys.any((k) => last.fields[k] == null);
    if (fits) {
      pl.fields.forEach((name, p) => field(SlotRef.line(last.id, name), p));
    } else {
      newLine(pl);
    }
  }

  return MergePlan(
    changes: changes,
    newLines: newLines,
    choices: choices,
    reviews: reviews,
    keptEdited: kept,
    unchanged: unchanged,
    notices: proposal.notices,
  );
}

/// Lo que hizo un dictado, para poder deshacerlo.
final class DictationRecord {
  const DictationRecord({required this.changes, required this.createdLines});

  /// Campos que cambió (incluidas las elecciones que la persona hizo a favor
  /// del dictado).
  final List<FieldChange> changes;

  /// Líneas que añadió, con los valores con que quedaron al crearlas.
  final Map<int, Map<String, Object?>> createdLines;

  DictationRecord withChange(FieldChange change) => DictationRecord(
    changes: [...changes, change],
    createdLines: createdLines,
  );

  /// La línea [line] creada por el dictado, con [field] puesto a [value] por
  /// una elección hecha a su favor.
  DictationRecord withLineValue(int line, String field, Object? value) =>
      DictationRecord(
        changes: changes,
        createdLines: {
          ...createdLines,
          line: {...?createdLines[line], field: value},
        },
      );
}

/// Lo que hay que hacer para deshacer un dictado.
final class UndoPlan {
  const UndoPlan({
    this.restore = const [],
    this.removeLines = const [],
    this.keptEdited = const [],
  });

  /// Campos que vuelven a su valor anterior (`after` = el anterior).
  final List<FieldChange> restore;
  final List<int> removeLines;

  /// Lo que la persona cambió después del dictado: se conserva.
  final List<SlotRef> keptEdited;

  bool get nothingToUndo =>
      restore.isEmpty && removeLines.isEmpty && keptEdited.isEmpty;
}

/// Deshace [record] sobre [now] sin pisar lo editado después.
UndoPlan planVoiceUndo(DictationRecord record, FormSnapshot now) {
  final restore = <FieldChange>[];
  final remove = <int>[];
  final kept = <SlotRef>[];
  for (final c in record.changes) {
    if (c.slot.line != null && record.createdLines.containsKey(c.slot.line)) {
      continue; // se decide con la línea entera
    }
    final (exists, current) = now.valueOf(c.slot);
    if (!exists) continue; // la línea ya no está: nada que restaurar
    if (current == c.after) {
      restore.add(FieldChange(c.slot, c.after, c.before, ''));
    } else {
      kept.add(c.slot);
    }
  }
  record.createdLines.forEach((id, values) {
    final line = now.line(id);
    if (line == null) return; // ya la quitó la persona
    final untouched = line.fields.entries.every(
      (e) => e.value == values[e.key],
    );
    if (untouched) {
      remove.add(id);
    } else {
      kept.add(SlotRef.line(id, '*'));
    }
  });
  return UndoPlan(restore: restore, removeLines: remove, keptEdited: kept);
}
