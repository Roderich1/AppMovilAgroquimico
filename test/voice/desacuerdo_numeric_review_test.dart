import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/numeric_review.dart';
import 'package:agroquimicos/voice_draft/plan/plan_interpreter.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Campos numéricos por revisar tras un dictado con desacuerdo entre los dos
/// reconocedores (`numeric_review.dart`).
///
/// TEXTO INYECTADO, NO RECONOCIMIENTO REAL: los dictados son frases escritas
/// para la prueba y se interpretan con los intérpretes de la app; ningún
/// motor de voz interviene.
void main() {
  const msg = numericDisagreementMessage;
  const bellator = CatalogEntry(
    id: 1,
    name: 'Bellator',
    unit: CatalogUnit.liter,
  );
  const mancozeb = CatalogEntry(
    id: 2,
    name: 'Mancozeb',
    unit: CatalogUnit.kilogram,
  );
  const norte = CatalogEntry(id: 40, name: 'Norte', areaM2: 20000);
  const catalog = VoiceCatalog(
    products: [bellator, mancozeb],
    suppliers: [CatalogEntry(id: 10, name: 'Agro Norte')],
    people: [CatalogEntry(id: 20, name: 'Ana')],
    farms: [norte],
    farmOwners: {40: CatalogEntry(id: 20, name: 'Ana')},
    activeCampaign: CatalogEntry(id: 30, name: 'Verano 2026'),
  );

  bool inReview(DraftField<Object?> f) =>
      f.review && f.status == FieldStatus.ambiguous && f.message == msg;

  group('compra', () {
    VoicePurchaseDraft dictate(VoicePurchaseDraft d, String text) =>
        interpretPurchase(text, d, catalog).draft;

    test('marca cantidad, precio y moneda de la línea dictada; nada más', () {
      final before = VoicePurchaseDraft.start(catalog).withPaidInFull(false);
      final after = dictate(
        before,
        'compré dos litros de bellator a veinte bolivianos el litro, '
        'el proveedor es agro norte',
      );
      final reviewed = reviewPurchaseNumbers(before, after, msg);
      final line = reviewed.lines.single;
      expect(inReview(line.quantity), isTrue);
      expect(line.quantity.value, const SpokenQuantity(2000, SpokenUnit.liter));
      expect(inReview(line.price), isTrue);
      expect(line.price.value?.minorPerUnit, 2000);
      expect(inReview(line.currency), isTrue);
      expect(line.currency.value, CurrencyCode.bob);
      // No son cifras: quedan como las dejó el intérprete.
      expect(line.product.isResolved, isTrue);
      expect(reviewed.supplier.isResolved, isTrue);
      expect(reviewed.paidInFull, isFalse, reason: 'el pago no se toca');
      // Y bloquean la confirmación hasta que se resuelvan.
      expect(reviewed.blockers, isNotEmpty);
      expect(after.blockers.where((b) => b.contains('precio')), isEmpty);
    });

    test('sólo lo que cambió este dictado: lo de antes queda resuelto', () {
      final first = dictate(
        VoicePurchaseDraft.start(catalog),
        'compré dos litros de bellator',
      );
      // Repite la misma cantidad (ya estaba) y añade el precio.
      final after = dictate(
        first,
        'dos litros de bellator a veinte bolivianos el litro',
      );
      expect(after.lines, hasLength(1));
      final line = reviewPurchaseNumbers(first, after, msg).lines.single;
      expect(line.quantity.isResolved, isTrue, reason: 'llegó antes');
      expect(inReview(line.price), isTrue);
      expect(inReview(line.currency), isTrue);
    });

    test('el tipo de cambio dictado también', () {
      final before = VoicePurchaseDraft.start(catalog);
      final after = dictate(before, 'tipo de cambio seis coma nueve');
      final reviewed = reviewPurchaseNumbers(before, after, msg);
      expect(inReview(reviewed.exchangeRate), isTrue);
      expect(reviewed.exchangeRate.value, after.exchangeRate.value);
    });

    test('lo corregido o confirmado a mano no se toca, ni ante un resultado '
        'tardío con desacuerdo', () {
      final voice = dictate(
        VoicePurchaseDraft.start(catalog),
        'compré dos litros de bellator a veinte bolivianos el litro',
      );
      final key = voice.lines.single.key;
      final manual = voice.updateLine(
        key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenQuantity(3000, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
          price: l.price.confirmedByUser(),
        ),
      );
      // El resultado tardío vuelve a nombrar cantidad y precio.
      final after = dictate(
        manual,
        'bellator cinco litros a treinta bolivianos el litro',
      );
      final line = reviewPurchaseNumbers(manual, after, msg).lines.single;
      expect(line.quantity.isManual, isTrue);
      expect(line.quantity.value, const SpokenQuantity(3000, SpokenUnit.liter));
      expect(line.price.origin, FieldOrigin.confirmed);
      expect(line.price.value?.minorPerUnit, 2000);
    });

    test('un precio ya ambiguo sigue ambiguo con su propia pregunta', () {
      final before = VoicePurchaseDraft.start(catalog);
      // Sin «el litro»: el intérprete no sabe si es por litro o total.
      final after = dictate(before, 'compré dos litros de bellator a veinte');
      final line = reviewPurchaseNumbers(before, after, msg).lines.single;
      expect(line.price.status, FieldStatus.ambiguous);
      expect(line.price.review, isFalse);
      expect(line.price.message, after.lines.single.price.message);
      expect(inReview(line.quantity), isTrue);
    });

    test('sin cambios numéricos no marca nada', () {
      final before = dictate(
        VoicePurchaseDraft.start(catalog),
        'compré dos litros de bellator',
      );
      final after = dictate(before, 'el proveedor es agro norte');
      final reviewed = reviewPurchaseNumbers(before, after, msg);
      expect(reviewed.lines.single.quantity.isResolved, isTrue);
      expect(reviewed.supplier.isResolved, isTrue);
    });
  });

  group('aplicación', () {
    VoiceApplicationDraft dictate(VoiceApplicationDraft d, String text) =>
        interpretApplication(text, d, catalog).draft;

    test('marca el área dicha y la cantidad; no el chaco ni el producto', () {
      final before = VoiceApplicationDraft.start(catalog);
      final after = dictate(
        before,
        'apliqué dos litros de bellator en el chaco norte en una hectárea',
      );
      final reviewed = reviewApplicationNumbers(before, after, msg);
      expect(inReview(reviewed.area), isTrue);
      expect(reviewed.area.value, 10000);
      expect(inReview(reviewed.lines.single.quantity), isTrue);
      expect(reviewed.farm.isResolved, isTrue);
      expect(reviewed.lines.single.product.isResolved, isTrue);
    });

    test('el área propuesta por el chaco no es de voz: no se marca', () {
      final before = VoiceApplicationDraft.start(catalog);
      final after = dictate(
        before,
        'apliqué dos litros de bellator en el chaco norte',
      );
      expect(after.area.origin, FieldOrigin.preset);
      final reviewed = reviewApplicationNumbers(before, after, msg);
      expect(reviewed.area.isResolved, isTrue);
      expect(reviewed.area.origin, FieldOrigin.preset);
      expect(inReview(reviewed.lines.single.quantity), isTrue);
    });

    test('una cantidad manual se conserva', () {
      final voice = dictate(
        VoiceApplicationDraft.start(catalog),
        'apliqué dos litros de bellator',
      );
      final manual = voice.updateLine(
        voice.lines.single.key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenAmount(4000, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final after = dictate(
        manual,
        'de bellator en realidad usamos diez litros',
      );
      final line = reviewApplicationNumbers(manual, after, msg).lines.single;
      expect(line.quantity.isManual, isTrue);
      expect(line.quantity.value, const SpokenAmount(4000, SpokenUnit.liter));
    });
  });

  group('planificación', () {
    VoicePlanDraft dictate(VoicePlanDraft d, String text) =>
        interpretPlan(text, d, catalog).draft;

    test('marca el área y la dosis dictadas; no el chaco ni el producto', () {
      final before = VoicePlanDraft.start(catalog);
      final after = dictate(
        before,
        'planificar en el chaco norte en tres hectáreas dos litros por '
        'hectárea de bellator',
      );
      final reviewed = reviewPlanNumbers(before, after, msg);
      expect(inReview(reviewed.area), isTrue);
      expect(reviewed.area.value, 30000);
      final line = reviewed.lines.single;
      expect(inReview(line.dose), isTrue);
      expect(line.dose.value, const SpokenDose(2000, SpokenUnit.liter));
      expect(reviewed.farm.isResolved, isTrue);
      expect(line.product.isResolved, isTrue);
      expect(reviewed.blockers, isNotEmpty);
    });

    test('una dosis confirmada se conserva y la línea nueva se marca', () {
      final first = dictate(
        VoicePlanDraft.start(catalog),
        'planificar dos litros por hectárea de bellator',
      );
      final confirmed = first.updateLine(
        first.lines.single.key,
        (l) => l.copyWith(dose: l.dose.confirmedByUser()),
      );
      final after = dictate(
        confirmed,
        'tres litros por hectárea de bellator y un kilo por hectárea de '
        'mancozeb',
      );
      final reviewed = reviewPlanNumbers(confirmed, after, msg);
      expect(reviewed.lines, hasLength(2));
      expect(reviewed.lines.first.dose.origin, FieldOrigin.confirmed);
      expect(
        reviewed.lines.first.dose.value,
        const SpokenDose(2000, SpokenUnit.liter),
      );
      expect(inReview(reviewed.lines.last.dose), isTrue);
    });
  });
}
