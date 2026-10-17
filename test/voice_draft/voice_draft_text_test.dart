import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/interpretation/voice_intent.dart';
import 'package:agroquimicos/voice_draft/text/normalize.dart';
import 'package:agroquimicos/voice_draft/text/spanish_numbers.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Texto dictado → números, unidades, nombres e intención (EVO-010).
///
/// Las frases son de las pruebas o de la partición `ajuste` del corpus. La
/// partición `aceptacion` no se usa aquí.
void main() {
  int? number(String text) {
    final words = tokenize(text);
    return readNumberAt(words, 0)?.thousandths;
  }

  group('números dichos con palabras', () {
    test('enteros simples y compuestos', () {
      expect(number('cincuenta'), 50000);
      expect(number('doce'), 12000);
      expect(number('ciento ochenta y seis'), 186000);
      expect(number('dos mil setecientos'), 2700000);
      expect(number('mil quinientos'), 1500000);
      expect(number('setenta y cinco'), 75000);
      expect(number('veintidós'), 22000);
    });

    test('medios y decimales dichos', () {
      expect(number('medio'), 500);
      expect(number('uno y medio'), 1500);
      expect(number('cinco coma cinco'), 5500);
    });

    test('cifras con el parser central es-BO, sin double', () {
      expect(number('50'), 50000);
      expect(number('1,5'), 1500);
      expect(number('1.500'), 1500000);
    });

    test('una cifra ambigua se marca inválida en lugar de adivinar', () {
      final n = readNumberAt(tokenize('1,500'), 0)!;
      expect(n.isValid, isFalse);
      expect(n.invalidMessage, isNotNull);
    });

    test('dos números dichos seguidos no se suman («uno cinco»)', () {
      final words = tokenize('uno cinco litros');
      final first = readNumberAt(words, 0)!;
      expect(first.thousandths, 1000);
      expect(first.end, 1);
      expect(number('cinco tres'), 5000);
      expect(number('veinte cinco'), 20000);
      expect(number('cien doscientos'), 100000);
      expect(number('dos mil tres mil'), 2003000);
    });

    test('la «y» sólo une decenas con unidades', () {
      final words = tokenize('cincuenta litros y doce kilos');
      final first = readNumberAt(words, 0)!;
      expect(first.thousandths, 50000);
      expect(first.end, 1);
    });
  });

  group('unidades', () {
    test('litros y kilos van a unidad base entera', () {
      expect(unitWord('litros')!.toBase(50000), 50000); // 50 L = 50 000 ML
      expect(unitWord('mililitros')!.toBase(500000), 500); // 500 ML
      expect(unitWord('kilos')!.toBase(12000), 12000); // 12 KG = 12 000 G
      expect(unitWord('gramos')!.toBase(250000), 250);
    });

    test('una fracción de ML o G no es una cantidad válida', () {
      expect(unitWord('mililitros')!.toBase(1500), isNull); // 1,5 ML
    });

    test('monedas', () {
      expect(currencyWord('bolivianos'), isNotNull);
      expect(currencyWord('dolares'), isNotNull);
      expect(currencyWord('pesos'), isNull);
    });
  });

  group('nombres contra el catálogo existente', () {
    const catalog = [
      CatalogEntry(id: 1, name: 'Germi-100'),
      CatalogEntry(id: 2, name: 'Bellator'),
      CatalogEntry(id: 3, name: 'Belator'),
      CatalogEntry(id: 4, name: 'Mancozeb 80'),
      CatalogEntry(id: 5, name: 'Expansive'),
    ];

    test('coincidencia canónica exacta: tildes, guiones y números dichos', () {
      final r = resolveName('germi cien', catalog);
      expect(r.state, ResolutionState.resolved);
      expect(r.entry!.id, 1);
      expect(resolveName('EXPANSIVE', catalog).entry!.id, 5);
      expect(resolveName('mancozeb ochenta', catalog).entry!.id, 4);
    });

    test('una aproximación se propone, nunca se elige sola', () {
      final r = resolveName('expansiv', catalog);
      expect(r.state, ResolutionState.ambiguous);
      expect(r.candidates.map((e) => e.id), [5]);
    });

    test('nombres parecidos quedan ambiguos con todas sus opciones', () {
      final r = resolveName('belatorr', catalog);
      expect(r.state, ResolutionState.ambiguous);
      expect(r.candidates.map((e) => e.id).toSet(), {2, 3});
    });

    test('homónimos exactos no se resuelven solos', () {
      final r = resolveName('jose', const [
        CatalogEntry(id: 1, name: 'José'),
        CatalogEntry(id: 2, name: 'Jose'),
      ]);
      expect(r.state, ResolutionState.ambiguous);
      expect(r.candidates, hasLength(2));
    });

    test('lo que no se parece a nada queda faltante, con lo oído', () {
      final r = resolveName('paraquat', catalog);
      expect(r.state, ResolutionState.missing);
      expect(r.heard, 'paraquat');
    });
  });

  group('intención', () {
    VoiceIntent intent(String text) => classifyIntent(tokenize(text));

    test('conjunto cerrado', () {
      expect(
        intent('Quiero registrar compra de cincuenta litros'),
        VoiceIntent.purchase,
      );
      expect(intent('planificar el chaco norte'), VoiceIntent.plan);
      expect(intent('apliqué dos litros en el chaco'), VoiceIntent.application);
      expect(
        intent('quiero aplicar la planificación del chaco Limoncitos'),
        VoiceIntent.application,
      );
    });

    test('pagos y consultas no preparan borrador (fuera de F09)', () {
      expect(intent('pago de quinientos a Juan'), VoiceIntent.unsupported);
      expect(intent('cuánto tengo de Bellator'), VoiceIntent.unsupported);
    });

    test('dos operaciones en una frase es ambiguo', () {
      expect(intent('compré glifosato y lo apliqué'), VoiceIntent.ambiguous);
    });

    test('sin palabra clave no se inventa una intención', () {
      expect(intent('cincuenta litros de Bellator'), VoiceIntent.none);
    });
  });
}
