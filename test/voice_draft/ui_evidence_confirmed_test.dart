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

  // Formulario único (2026-11-13, RF-41 y DAT-21): el borrador final se arma
  // con lo que tiene el formulario, con todo «a mano», y las líneas de cada
  // sombra se anotan con el id de la línea del formulario a la que fueron.
  group('evidencia desde el formulario', () {
    const campaign = CatalogEntry(id: 3, name: 'Campaña 1');
    const dictated = DraftField<SpokenDose>.resolved(
      SpokenDose(2000, SpokenUnit.liter),
      origin: FieldOrigin.voice,
    );

    VoicePlanDraft shadow(int key, DraftField<SpokenDose> dose) =>
        VoicePlanDraft(
          campaign: const DraftField.resolved(
            campaign,
            origin: FieldOrigin.preset,
          ),
          farm: const DraftField.resolved(farm, origin: FieldOrigin.voice),
          lines: [
            VoicePlanLine(
              key: key,
              product: const DraftField.resolved(
                product,
                origin: FieldOrigin.voice,
              ),
              dose: dose,
            ),
          ],
          nextLineKey: key + 1,
        );

    VoicePlanDraft form({required CatalogEntry farm, SpokenDose? dose}) =>
        VoicePlanDraft(
          campaign: formDraftField(campaign),
          farm: formDraftField(farm),
          area: formDraftField(10000),
          lines: [
            VoicePlanLine(
              key: 5,
              product: formDraftField(product),
              dose: formDraftField(dose),
            ),
          ],
          nextLineKey: 6,
        );

    test('lo que quedó como se dictó no es corrección, aunque se dijera en '
        'otra unidad; lo cambiado sí, con el valor del formulario', () {
      final trace = VoiceEvidenceTrace()
        ..voiceApplied(
          shadow(
            1,
            const DraftField.resolved(
              SpokenDose(500000, SpokenUnit.milliliter),
              origin: FieldOrigin.voice,
            ),
          ),
          lineKeys: {1: 5},
        );
      final entry = trace.finish(
        // 500 mL/ha escritos como 0,5 L/ha; el chaco, cambiado a mano.
        finalDraft: form(
          farm: other,
          dose: const SpokenDose(500, SpokenUnit.liter),
        ),
        outcome: VoiceEvidenceOutcome.confirmed,
        fromForm: true,
      );
      expect(
        entry.proposed.map((f) => f.path),
        containsAll(['line[5].product', 'line[5].dose']),
      );
      final kinds = {for (final c in entry.corrections) c.path: c.kind};
      // El área faltaba en la sombra (propuesta como faltante): escribirla
      // es un cambio, como en el borrador de voz.
      expect(kinds, {
        'farm': CorrectionKind.changed,
        'area': CorrectionKind.changed,
      });
      final confirmed = {for (final f in entry.confirmed!) f.path: f};
      expect(confirmed['farm']!.value, containsPair('id', other.id));
      expect(confirmed['farm']!.origin, FieldOrigin.manual.name);
      expect(confirmed['line[5].dose']!.value, {
        'thousandthsPerHa': 500000,
        'unit': 'milliliter',
      });
      expect(confirmed['line[5].dose']!.origin, FieldOrigin.voice.name);
      expect(confirmed['campaign']!.origin, FieldOrigin.preset.name);
    });

    test('un valor por revisar que se dejó igual queda reafirmado', () {
      final trace = VoiceEvidenceTrace()
        ..voiceApplied(
          shadow(1, dictated.markForReview('Se oyeron dos dosis distintas.')),
          lineKeys: {1: 5},
        );
      final entry = trace.finish(
        finalDraft: form(
          farm: farm,
          dose: const SpokenDose(2000, SpokenUnit.liter),
        ),
        outcome: VoiceEvidenceOutcome.confirmed,
        fromForm: true,
      );
      final kinds = {for (final c in entry.corrections) c.path: c.kind};
      expect(kinds['line[5].dose'], CorrectionKind.reaffirmed);
    });

    test('una línea de la sombra que no llegó al formulario no se anota, y '
        'un dictado que no oyó un campo no borra lo propuesto antes', () {
      final trace = VoiceEvidenceTrace()
        ..voiceApplied(shadow(1, dictated), lineKeys: {1: 5})
        ..voiceApplied(
          const VoicePlanDraft(
            campaign: DraftField.resolved(campaign, origin: FieldOrigin.preset),
            lines: [VoicePlanLine(key: 1)],
            nextLineKey: 2,
          ),
          lineKeys: const {},
        );
      final proposed = {
        for (final f
            in trace
                .finish(
                  finalDraft: form(
                    farm: farm,
                    dose: const SpokenDose(2000, SpokenUnit.liter),
                  ),
                  outcome: VoiceEvidenceOutcome.confirmed,
                  fromForm: true,
                )
                .proposed)
          f.path: f,
      };
      expect(proposed.keys, isNot(contains('line[1].product')));
      expect(proposed['farm']!.value, containsPair('id', farm.id));
      expect(proposed['line[5].dose']!.status, FieldStatus.resolved.name);
    });

    test('borrar la dosis en el formulario es un cambio a faltante', () {
      final trace = VoiceEvidenceTrace()
        ..voiceApplied(shadow(1, dictated), lineKeys: {1: 5});
      final entry = trace.finish(
        finalDraft: form(farm: farm),
        outcome: VoiceEvidenceOutcome.discarded,
        fromForm: true,
      );
      final kinds = {for (final c in entry.corrections) c.path: c.kind};
      expect(kinds['line[5].dose'], CorrectionKind.changed);
      expect(entry.confirmed, isNull);
    });
  });
}
