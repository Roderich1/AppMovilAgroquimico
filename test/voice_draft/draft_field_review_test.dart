import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato común de la etapa de correcciones del POCO (2026-11-08): un valor
/// por revisar bloquea sin perder lo leído, y confirmar sin cambiar no se
/// presenta como una corrección.
void main() {
  group('DraftField por revisar', () {
    test(
      'un valor dictado marcado para revisión conserva el valor y bloquea',
      () {
        const dictated = DraftField<int>.resolved(
          5000,
          origin: FieldOrigin.voice,
        );
        final marked = dictated.markForReview('Revise la cifra.');
        expect(marked.review, isTrue);
        expect(marked.status, FieldStatus.ambiguous);
        expect(marked.isResolved, isFalse);
        expect(marked.value, 5000);
        expect(marked.candidates, isEmpty);
        expect(marked.message, 'Revise la cifra.');
      },
    );

    test('lo puesto, confirmado o propuesto no se marca', () {
      const manual = DraftField<int>.resolved(4, origin: FieldOrigin.manual);
      const confirmed = DraftField<int>.resolved(
        4,
        origin: FieldOrigin.confirmed,
      );
      const preset = DraftField<int>.resolved(4, origin: FieldOrigin.preset);
      const missing = DraftField<int>.missing();
      for (final f in [manual, confirmed, preset, missing]) {
        expect(identical(f.markForReview('x'), f), isTrue);
      }
    });

    test('confirmar el valor revisado lo resuelve como confirmado', () {
      final marked = const DraftField<int>.resolved(
        5000,
        origin: FieldOrigin.voice,
      ).markForReview('Revise la cifra.');
      final done = marked.confirmedByUser();
      expect(done.isResolved, isTrue);
      expect(done.value, 5000);
      expect(done.origin, FieldOrigin.confirmed);
      expect(done.review, isFalse);
    });

    test('sin valor no hay nada que confirmar', () {
      const missing = DraftField<int>.missing(message: 'Falta');
      expect(identical(missing.confirmedByUser(), missing), isTrue);
    });
  });

  group('confirmado frente a corregido', () {
    test('la voz no sobrescribe un valor confirmado', () {
      const confirmed = DraftField<int>.resolved(
        4,
        origin: FieldOrigin.confirmed,
      );
      expect(confirmed.isManual, isTrue);
      final (kept, outcome) = mergeField(
        confirmed,
        const DraftField<int>.resolved(9, origin: FieldOrigin.voice),
      );
      expect(kept.value, 4);
      expect(outcome.keptManual, 1);
    });
  });
}
