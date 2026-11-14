import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del **controlador del borrador** (F09, 2026-11-10) con las formas
/// de `compra_formas_transcritas_test.dart`: lo que el intérprete propone
/// entra al borrador, y un borrador incompleto o con un importe por
/// confirmar **no se puede registrar** (nunca se llama a la escritura). Las
/// frases son escritas y sintéticas.
void main() {
  const herbicida = CatalogEntry(
    id: 1,
    name: 'Herbicida DEMO',
    unit: CatalogUnit.liter,
  );
  const fungicida = CatalogEntry(
    id: 2,
    name: 'Fungicida DEMO',
    unit: CatalogUnit.liter,
  );
  const catalog = VoiceCatalog(
    products: [herbicida, fungicida],
    suppliers: [],
    people: [],
  );

  late int writes;

  VoiceDraftController<VoicePurchaseDraft, int> controller() {
    writes = 0;
    return VoiceDraftController<VoicePurchaseDraft, int>(
      initial: VoicePurchaseDraft.start(catalog),
      commit: (draft) async {
        writes++;
        return 1;
      },
    );
  }

  void say(VoiceDraftController<VoicePurchaseDraft, int> c, String text) {
    c.applyVoice((current) {
      final r = interpretPurchase(text, current, catalog);
      return (r.draft, r.outcome);
    });
  }

  test('«Hoy compré fungicida demo»: una línea incompleta que no se puede '
      'registrar', () async {
    final c = controller();
    say(c, 'Hoy compré fungicida demo');
    expect(c.draft.lines, hasLength(1));
    expect(c.draft.lines.single.product.value, fungicida);
    expect(c.blockers, contains('Línea 1: falta cantidad.'));
    expect(c.canConfirm, isFalse);
    expect(await c.confirm(), isNull);
    expect(writes, 0);
  });

  test('«con un total de cien bolivianos»: el importe pendiente bloquea el '
      'registro hasta que la persona lo reparte', () {
    final c = controller();
    say(c, 'Compré dos litros de Fungicida DEMO con un total de 100Bs');
    final line = c.draft.lines.single;
    expect(line.price.status, FieldStatus.ambiguous);
    expect(c.blockers.where((b) => b.contains('precio')), isNotEmpty);
    c.editManually(
      (d) => d.updateLine(line.key, (l) => l.priceFromLineTotal()),
    );
    final after = c.draft.lines.single;
    expect(after.unitPriceMinor, 5000);
    expect(after.price.origin, FieldOrigin.confirmed, reason: 'intervención');
    expect(c.blockers.where((b) => b.contains('precio')), isEmpty);
  });

  test('total global de varias líneas: ninguna línea queda con precio y no '
      'se puede registrar', () async {
    final c = controller();
    say(
      c,
      'Compré dos litros de Fungicida DEMO y tres litros de Herbicida DEMO en '
      'un total de doscientos cincuenta bolivianos',
    );
    expect(c.draft.lines, hasLength(2));
    expect(c.draft.lines.every((l) => !l.price.isResolved), isTrue);
    expect(c.canConfirm, isFalse);
    expect(await c.confirm(), isNull);
    expect(writes, 0);
  });

  test('«1,500 bolivianos» (ambiguo) no se registra', () {
    final c = controller();
    say(c, 'Compré dos litros de Fungicida DEMO a 1,500 bolivianos el litro');
    expect(c.draft.lines.single.price.isResolved, isFalse);
    expect(c.canConfirm, isFalse);
  });

  test('negación e intención futura: el borrador no cambia', () {
    final c = controller();
    say(c, 'No compré dos litros de fungicida demo');
    say(c, 'Quiero comprar fungicida demo');
    expect(c.draft.lines, isEmpty);
    expect(c.canConfirm, isFalse);
  });

  test('lo corregido a mano no lo cambia un dictado posterior', () {
    final c = controller();
    say(c, 'Compré fungicida demo');
    final key = c.draft.lines.single.key;
    c.editManually(
      (d) => d.updateLine(
        key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenQuantity(3000, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      ),
    );
    say(c, 'Compré dos litros de fungicida demo');
    final quantities = c.draft.lines.map((l) => l.quantityBase).toList();
    expect(quantities.first, 3000, reason: 'la línea corregida no cambia');
  });
}
