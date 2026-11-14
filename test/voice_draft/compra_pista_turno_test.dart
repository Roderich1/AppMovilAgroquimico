import 'package:agroquimicos/presentation/voice/voice_draft_widgets.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/whole_turn_transcription_adapter.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pista del turno entero de la compra (F09, 2026-11-10): productos de la
/// cuenta, unidades, monedas y expresiones de precio. Nada más.
void main() {
  const poco = VoiceCatalog(
    products: [
      CatalogEntry(id: 1, name: 'Herbicida DEMO', unit: CatalogUnit.liter),
      CatalogEntry(id: 2, name: 'Fungicida DEMO', unit: CatalogUnit.liter),
      CatalogEntry(id: 3, name: 'Insecticida DEMO', unit: CatalogUnit.liter),
    ],
    suppliers: [CatalogEntry(id: 9, name: 'Agro insumos DEMO')],
    people: [CatalogEntry(id: 7, name: 'Rosa Mamani WT')],
    farms: [CatalogEntry(id: 5, name: 'Chaco de arriba')],
  );

  test('el catálogo del POCO da la pista candidata medida en HOST', () {
    expect(
      LocalSpeechTranscriptionAdapter.hintText(
        voicePurchaseTurnHints(poco),
        maxChars: WholeTurnTranscriptionAdapter.maxHintChars,
      ),
      'Herbicida DEMO, Fungicida DEMO, Insecticida DEMO, litro, litros, '
      'bolivianos, dólares, por litro, el litro, en total, por un total de.',
    );
  });

  test('sin proveedores, personas, chacos, cantidades ni precios', () {
    final hints = voicePurchaseTurnHints(poco).join(' | ');
    expect(hints, isNot(contains('Agro insumos')));
    expect(hints, isNot(contains('Rosa')));
    expect(hints, isNot(contains('Chaco')));
    expect(RegExp(r'\d').hasMatch(hints), isFalse);
  });

  test('las unidades y expresiones siguen a los productos del catálogo', () {
    const kilos = VoiceCatalog(
      products: [
        CatalogEntry(id: 1, name: 'Mancozeb', unit: CatalogUnit.kilogram),
      ],
      suppliers: [],
      people: [],
    );
    final hints = voicePurchaseTurnHints(kilos);
    expect(hints, containsAll(['kilo', 'kilos', 'por kilo', 'el kilo']));
    expect(hints, isNot(contains('litro')));
  });

  test('cada producto una vez, aunque se repita con otras mayúsculas', () {
    const repeated = VoiceCatalog(
      products: [
        CatalogEntry(id: 1, name: 'Fungicida DEMO', unit: CatalogUnit.liter),
        CatalogEntry(id: 2, name: 'fungicida demo', unit: CatalogUnit.liter),
      ],
      suppliers: [],
      people: [],
    );
    expect(
      voicePurchaseTurnHints(repeated)
          .where((h) => h.toLowerCase() == 'fungicida demo'),
      hasLength(1),
    );
  });
}
