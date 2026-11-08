import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';
import 'ui_draft_harness.dart';

/// Presentación del borrador de compra por voz tras la prueba del autor en
/// el POCO (2026-11-08). Todo el texto «dictado» lo inyecta el puerto falso:
/// no es reconocimiento real. Datos sintéticos.
void main() {
  Future<void> seed(AgroRepository repo, Household h) async {
    await repo.addSupplier(name: 'Agro Norte');
  }

  group('cantidad, precio y tipo de cambio por revisar', () {
    /// Lo que dejará la voz cuando los dos reconocedores oigan cifras
    /// distintas en la cantidad, el precio y el tipo de cambio.
    VoicePurchaseDraft reviewDraft(VoiceCatalog catalog) {
      CatalogEntry named(List<CatalogEntry> list, String name) =>
          list.firstWhere((e) => e.name == name);
      return VoicePurchaseDraft.start(catalog).copyWith(
        supplier: DraftField.resolved(
          named(catalog.suppliers, 'Agro Norte'),
          origin: FieldOrigin.voice,
        ),
        recipient: DraftField.resolved(
          named(catalog.people, 'Hermana'),
          origin: FieldOrigin.voice,
        ),
        exchangeRate: const DraftField.toReview(
          6960000,
          message: 'Se oyeron dos tipos de cambio distintos.',
        ),
        lines: [
          VoicePurchaseLine(
            key: 1,
            product: DraftField.resolved(
              named(catalog.products, 'Glifosato'),
              origin: FieldOrigin.voice,
            ),
            quantity: const DraftField.toReview(
              SpokenQuantity(10000, SpokenUnit.liter),
              message: 'Se oyeron dos cantidades distintas.',
            ),
            price: const DraftField.toReview(
              SpokenPrice(5000, perUnit: CatalogUnit.liter),
              message: 'Se oyeron dos precios distintos.',
            ),
            currency: const DraftField.resolved(
              CurrencyCode.usd,
              origin: FieldOrigin.voice,
            ),
          ),
        ],
        nextLineKey: 2,
      );
    }

    testWidgets('se ven con su valor y bloquean; confirmar o corregir los '
        'resuelve y la compra escribe lo que se ve, una vez', (tester) async {
      final w = await pumpDraftScreen(
        tester,
        screen: VoicePurchaseDraftScreen(initialDraftForTest: reviewDraft),
        script: const [
          FakeTurn(segment: 'veinte litros de Glifosato', endsOnStop: true),
        ],
        seed: seed,
      );
      final before = await dump(tester, w.database);
      for (final id in ['cantidad-1', 'precio-1', 'tipo-cambio']) {
        expect(fieldState(tester, id), 'Revisar', reason: id);
        expect(find.byKey(Key('voz-confirmar-$id')), findsOneWidget);
      }
      expect(fieldText(tester, 'voz-cantidad-1'), '10');
      expect(fieldText(tester, 'voz-precio-1'), '50');
      expect(fieldText(tester, 'voz-tipo-cambio'), '6,96');
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-mensaje-precio-1'))).data,
        'Se oyeron dos precios distintos.',
      );
      // Un precio por revisar no ofrece además «Sí, es el precio por L».
      expect(find.byKey(const Key('voz-precio-por-unidad-1')), findsNothing);
      await tapKey(tester, 'voz-pago-no');
      expect(registerEnabled(tester), isFalse);

      // Confirmar el proveedor ya elegido no es corregirlo.
      await pick(tester, 'voz-borrador-proveedor', 'Agro Norte');
      expect(fieldState(tester, 'proveedor'), 'Confirmado');

      await tapKey(tester, 'voz-confirmar-cantidad-1');
      expect(fieldState(tester, 'cantidad-1'), 'Confirmado');
      await tester.enterText(find.byKey(const Key('voz-precio-1')), '55');
      await drain(tester);
      expect(fieldState(tester, 'precio-1'), 'Corregido a mano');
      expect(find.byKey(const Key('voz-confirmar-precio-1')), findsNothing);
      expect(registerEnabled(tester), isFalse);
      await tapKey(tester, 'voz-confirmar-tipo-cambio');
      expect(fieldState(tester, 'tipo-cambio'), 'Confirmado');
      expect(registerEnabled(tester), isTrue);

      // Texto inyectado posterior: no cambia lo confirmado ni lo corregido.
      await dictate(tester);
      expect(fieldText(tester, 'voz-cantidad-1'), '10');
      expect(fieldText(tester, 'voz-precio-1'), '55');
      expect(find.byKey(const Key('voz-como-corregir')), findsOneWidget);

      expect(await dump(tester, w.database), before);
      await doubleTapRegister(tester);
      expect(await rows(tester, w.database, 'purchases'), hasLength(1));
      final item = (await rows(tester, w.database, 'purchase_items')).single;
      expect(item['quantity_base'], 10000);
      expect(item['original_unit_price_minor'], 5500);
      expect(item['exchange_rate_scaled'], 6960000);
    });
  });

  group('lo dictado se ve normalizado', () {
    testWidgets('la cantidad con el producto aún sin elegir se ve «10», no '
        '«diez litros»', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compra de diez litros de Fungicida DEMO a 50 bolivianos el '
                'litro, proveedor Agro Norte, todo para Hermana',
            endsOnStop: true,
          ),
        ],
        seed: seed,
      );
      await dictate(tester);
      expect(fieldText(tester, 'voz-cantidad-1'), '10');
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-nota-cantidad-1'))).data,
        'En L; falta elegir el producto para comprobar su unidad.',
      );
      expect(find.textContaining('no coincide'), findsNothing);
      expect(registerEnabled(tester), isFalse);
    });

    testWidgets('«Sí, es el precio por L» confirma el precio sin presentarlo '
        'como corregido', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compra de diez litros de Glifosato a 50 bolivianos, '
                'proveedor Agro Norte, todo para Hermana',
            endsOnStop: true,
          ),
        ],
        seed: seed,
      );
      await dictate(tester);
      expect(fieldState(tester, 'precio-1'), 'Ambiguo: elija');
      expect(find.byKey(const Key('voz-confirmar-precio-1')), findsNothing);
      await tapKey(tester, 'voz-precio-por-unidad-1');
      expect(fieldState(tester, 'precio-1'), 'Confirmado');
      expect(fieldText(tester, 'voz-precio-1'), '50');
    });
  });
}
