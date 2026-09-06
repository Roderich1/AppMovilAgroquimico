import 'package:agroquimicos/domain/read_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mappers de EVO-004: fila válida, nulo permitido, columna ausente y tipo
/// inválido.
///
/// El objetivo de estos tests es que un alias renombrado o una columna que
/// cambia de tipo se detecten **en el mapper**, con la consulta y la columna
/// nombradas, y no como un `_TypeError` dentro de un widget
/// (`EVO-004-REQ-006`).
void main() {
  group('RowReader', () {
    const reader = RowReader({
      'entero': 7,
      'entero_nulo': null,
      'texto': 'hola',
      'texto_nulo': null,
      'confundido': 'no soy un entero',
    }, 'consultaDePrueba');

    test('lee un entero y un texto presentes', () {
      expect(reader.requireInt('entero'), 7);
      expect(reader.requireString('texto'), 'hola');
    });

    test('acepta nulo donde el contrato lo permite', () {
      expect(reader.optionalInt('entero_nulo'), isNull);
      expect(reader.optionalString('texto_nulo'), isNull);
    });

    test('una columna ausente falla nombrando consulta y columna', () {
      expect(
        () => reader.requireInt('no_existe'),
        throwsA(
          isA<RowMappingException>()
              .having((e) => e.source, 'source', 'consultaDePrueba')
              .having((e) => e.column, 'column', 'no_existe')
              .having(
                (e) => e.message,
                'message',
                contains('no trae esa columna'),
              ),
        ),
      );
    });

    test('una columna ausente también falla en los lectores opcionales', () {
      // Opcional significa "puede venir nula", no "puede no venir": si el alias
      // desaparece de la consulta hay que enterarse igual.
      expect(
        () => reader.optionalInt('no_existe'),
        throwsA(isA<RowMappingException>()),
      );
      expect(
        () => reader.optionalString('no_existe'),
        throwsA(isA<RowMappingException>()),
      );
    });

    test('un nulo donde se exige valor falla', () {
      expect(
        () => reader.requireInt('entero_nulo'),
        throwsA(
          isA<RowMappingException>().having(
            (e) => e.message,
            'message',
            contains('llegó nulo'),
          ),
        ),
      );
      expect(
        () => reader.requireString('texto_nulo'),
        throwsA(isA<RowMappingException>()),
      );
    });

    test('un tipo inválido falla nombrando el tipo recibido', () {
      expect(
        () => reader.requireInt('confundido'),
        throwsA(
          isA<RowMappingException>().having(
            (e) => e.message,
            'message',
            contains('String'),
          ),
        ),
      );
    });

    test('el mensaje no incluye el valor de la celda', () {
      // Un importe, un nombre o un teléfono no pueden acabar en un mensaje de
      // error visible (09_SECURITY_AND_PRIVACY).
      try {
        reader.requireInt('confundido');
        fail('debía fallar');
      } on RowMappingException catch (error) {
        expect(error.message, isNot(contains('no soy un entero')));
      }
    });
  });

  group('CampaignRead', () {
    Map<String, Object?> row() => {
      'id': 3,
      'name': 'Campaña 2026',
      'start_date': '2026-01-01T00:00:00.000Z',
      'end_date': null,
      'status': 'ACTIVE',
    };

    test('mapea una fila válida con end_date nulo', () {
      final campaign = CampaignRead.fromRow(row());
      expect(campaign.id, 3);
      expect(campaign.name, 'Campaña 2026');
      expect(campaign.endDate, isNull);
      expect(campaign.isActive, isTrue);
    });

    test('un nombre nulo falla en el mapper', () {
      expect(
        () => CampaignRead.fromRow(row()..['name'] = null),
        throwsA(
          isA<RowMappingException>()
              .having((e) => e.source, 'source', 'campaigns')
              .having((e) => e.column, 'column', 'name'),
        ),
      );
    });

    test('un id de tipo inválido falla en el mapper', () {
      expect(
        () => CampaignRead.fromRow(row()..['id'] = '3'),
        throwsA(isA<RowMappingException>()),
      );
    });
  });

  group('InventoryLineRead', () {
    Map<String, Object?> row() => {
      'product_id': 1,
      'product_name': 'Glifosato',
      'unit': 'L',
      'purchased_base': 20000,
      'consumed_base': 5000,
      'available_base': 15000,
      'committed_base': 2000,
      'projected_base': 13000,
      'available_value_bob_minor': 150000,
      'people_count': 2,
    };

    test('mapea una fila válida conservando los enteros', () {
      final line = InventoryLineRead.fromRow(row());
      expect(line.availableBase, 15000);
      expect(line.committedBase, 2000);
      expect(line.projectedBase, 13000);
      expect(line.availableValueBobMinor, 150000);
    });

    test('acepta un proyectado negativo', () {
      final line = InventoryLineRead.fromRow(row()..['projected_base'] = -500);
      expect(line.projectedBase, -500);
    });

    test('un alias ausente falla nombrando la consulta', () {
      final broken = row()..remove('committed_base');
      expect(
        () => InventoryLineRead.fromRow(broken),
        throwsA(
          isA<RowMappingException>()
              .having((e) => e.source, 'source', 'inventorySummary')
              .having((e) => e.column, 'column', 'committed_base'),
        ),
      );
    });
  });

  group('FarmCostRead', () {
    Map<String, Object?> row() => {
      'id': 4,
      'name': 'Chaco Grande',
      'owner_name': 'Ana',
      'area_m2': 100000,
      'total_cost_bob_minor': 50000,
    };

    test('calcula el costo por hectárea con enteros', () {
      // 10 ha y Bs 500,00 -> Bs 50,00/ha = 5000 centavos.
      expect(FarmCostRead.fromRow(row()).costPerHectareMinor, 5000);
    });

    test('redondea a la mitad hacia arriba, como la pantalla', () {
      // 3 ha (30 000 m²) y 10 centavos -> 10 × 10000 / 30000 = 3,33 -> 3.
      final farm = FarmCostRead.fromRow(
        row()
          ..['area_m2'] = 30000
          ..['total_cost_bob_minor'] = 10,
      );
      expect(farm.costPerHectareMinor, 3);
    });

    test('un área no positiva no revienta: devuelve nulo', () {
      // El esquema declara CHECK(area_m2 > 0); la guarda protege al reporte de
      // una base antigua anómala en vez de propagar un ArgumentError.
      expect(
        FarmCostRead.fromRow(row()..['area_m2'] = 0).costPerHectareMinor,
        isNull,
      );
    });

    test('un chaco sin aplicaciones vale cero por hectárea', () {
      expect(
        FarmCostRead.fromRow(row()..['total_cost_bob_minor'] = 0)
            .costPerHectareMinor,
        0,
      );
    });
  });

  group('StatementEntryRead', () {
    Map<String, Object?> row() => {
      'id': 9,
      'transaction_date': '2026-03-01T00:00:00.000Z',
      'type': 'PAYMENT',
      'amount_bob_minor_signed': -20000,
      'campaign_id': null,
      'concept': null,
      'farm_name': null,
      'notes': null,
    };

    test('acepta campaña, concepto, chaco y notas nulos', () {
      final entry = StatementEntryRead.fromRow(row());
      expect(entry.campaignId, isNull);
      expect(entry.concept, isNull);
      expect(entry.farmName, isNull);
      expect(entry.notes, isNull);
    });

    test('separa cargo y crédito sin perder el signo', () {
      final payment = StatementEntryRead.fromRow(row());
      expect(payment.chargeMinor, 0);
      expect(payment.creditMinor, 20000);

      final charge = StatementEntryRead.fromRow(
        row()..['amount_bob_minor_signed'] = 50000,
      );
      expect(charge.chargeMinor, 50000);
      expect(charge.creditMinor, 0);
    });

    test('un importe de tipo inválido falla en el mapper', () {
      expect(
        () => StatementEntryRead.fromRow(
          row()..['amount_bob_minor_signed'] = '−20000',
        ),
        throwsA(
          isA<RowMappingException>().having(
            (e) => e.column,
            'column',
            'amount_bob_minor_signed',
          ),
        ),
      );
    });
  });

  group('StatementLine.runningBalance', () {
    StatementEntryRead entry(int id, int amount) => StatementEntryRead(
      id: id,
      transactionDate: '2026-0$id-01T00:00:00.000Z',
      type: amount > 0 ? 'USAGE_CHARGE' : 'PAYMENT',
      amountBobMinorSigned: amount,
      campaignId: 1,
      concept: null,
      farmName: null,
      notes: null,
    );

    test('acumula desde cero en el orden recibido', () {
      final lines = StatementLine.runningBalance([
        entry(1, 50000),
        entry(2, -20000),
        entry(3, 5000),
      ]);
      expect(lines.map((l) => l.balanceMinor).toList(), [50000, 30000, 35000]);
    });

    test('arranca del saldo inicial cuando hay campaña', () {
      final lines = StatementLine.runningBalance([
        entry(1, 10000),
      ], openingMinor: 30000);
      expect(lines.single.balanceMinor, 40000);
    });

    test('sin movimientos no produce líneas', () {
      expect(StatementLine.runningBalance(const []), isEmpty);
    });
  });
}
