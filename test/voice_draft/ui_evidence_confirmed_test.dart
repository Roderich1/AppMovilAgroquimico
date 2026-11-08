import 'package:agroquimicos/presentation/voice/voice_draft_widgets.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:agroquimicos/voice_evidence/draft_snapshot.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Confirmado» frente a «Corregido a mano» (POCO 2026-11-08), en las piezas
/// sin pantalla: la elección en el selector y la evidencia. Datos sintéticos.
void main() {
  const farm = CatalogEntry(id: 1, name: 'Chaco Norte', areaM2: 10000);
  const other = CatalogEntry(id: 2, name: 'Chaco Sur', areaM2: 5000);
  const product = CatalogEntry(
    id: 7,
    name: 'Glifosato',
    unit: CatalogUnit.liter,
  );

  group('pickEntry', () {
    test('la misma opción dictada queda confirmada, sin cambiar el valor', () {
      const dictated = DraftField.resolved(farm, origin: FieldOrigin.voice);
      final picked = pickEntry(dictated, farm);
      expect(picked.origin, FieldOrigin.confirmed);
      expect(picked.value, farm);
      expect(picked.isManual, isTrue);
    });

    test('otra opción es una corrección a mano', () {
      const dictated = DraftField.resolved(farm, origin: FieldOrigin.voice);
      expect(pickEntry(dictated, other).origin, FieldOrigin.manual);
    });

    test('lo ya corregido a mano sigue así si se toca la misma opción', () {
      const manual = DraftField.resolved(farm, origin: FieldOrigin.manual);
      expect(identical(pickEntry(manual, farm), manual), isTrue);
    });

    test('elegir en un campo ambiguo o faltante es una corrección a mano', () {
      const ambiguous = DraftField<CatalogEntry>.ambiguous(
        candidates: [farm, other],
        heard: 'chaco',
      );
      expect(pickEntry(ambiguous, farm).origin, FieldOrigin.manual);
      expect(
        pickEntry(const DraftField<CatalogEntry>.missing(), farm).origin,
        FieldOrigin.manual,
      );
    });
  });

  group('evidencia', () {
    VoicePlanDraft draft(DraftField<SpokenDose> dose) => VoicePlanDraft(
      campaign: const DraftField.resolved(
        CatalogEntry(id: 3, name: 'Campaña 1'),
        origin: FieldOrigin.preset,
      ),
      farm: const DraftField.resolved(farm, origin: FieldOrigin.voice),
      area: const DraftField.resolved(10000, origin: FieldOrigin.preset),
      lines: [
        VoicePlanLine(
          key: 1,
          product: const DraftField.resolved(
            product,
            origin: FieldOrigin.voice,
          ),
          dose: dose,
        ),
      ],
      nextLineKey: 2,
    );

    const dictated = DraftField<SpokenDose>.resolved(
      SpokenDose(2000, SpokenUnit.liter),
      origin: FieldOrigin.voice,
    );

    test('confirmar un valor por revisar se anota como reafirmado, no como '
        'cambiado', () {
      final review = dictated.markForReview('Se oyeron dos dosis distintas.');
      final trace = VoiceEvidenceTrace()..voiceApplied(draft(review));
      final entry = trace.finish(
        finalDraft: draft(review.confirmedByUser()),
        outcome: VoiceEvidenceOutcome.confirmed,
      );
      final kinds = {for (final c in entry.corrections) c.path: c.kind};
      expect(kinds, {'line[1].dose': CorrectionKind.reaffirmed});
    });

    test('corregir el valor sí es un cambio', () {
      final review = dictated.markForReview('Se oyeron dos dosis distintas.');
      final trace = VoiceEvidenceTrace()..voiceApplied(draft(review));
      final entry = trace.finish(
        finalDraft: draft(
          const DraftField.resolved(
            SpokenDose(2500, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
        outcome: VoiceEvidenceOutcome.confirmed,
      );
      final kinds = {for (final c in entry.corrections) c.path: c.kind};
      expect(kinds, {'line[1].dose': CorrectionKind.changed});
    });

    test('un valor confirmado no cuenta como propuesta de un dictado '
        'posterior', () {
      final trace = VoiceEvidenceTrace()
        ..voiceApplied(draft(dictated))
        ..voiceApplied(draft(dictated.confirmedByUser()));
      final entry = trace.finish(
        finalDraft: draft(dictated.confirmedByUser()),
        outcome: VoiceEvidenceOutcome.confirmed,
      );
      final proposedDose = entry.proposed.singleWhere(
        (f) => f.path == 'line[1].dose',
      );
      expect(proposedDose.origin, FieldOrigin.voice.name);
    });
  });
}
