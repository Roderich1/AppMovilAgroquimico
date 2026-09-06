import 'package:agroquimicos/domain/read_models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compositor neutral (Lote D) y conversión exacta entero -> decimal.
///
/// El compositor es la única fuente de los cinco reportes, así que aquí se fija
/// qué columnas tiene cada uno, qué totales suma y qué hace cuando no hay
/// filas.
void main() {
  const composer = ReportComposer();
  final now = DateTime.utc(2026, 9, 6, 15, 30);

  group('decimalFromScaled', () {
    test('convierte centavos a decimal exacto', () {
      expect(decimalFromScaled(123456, 2), '1234,56');
      expect(decimalFromScaled(5, 2), '0,05');
      expect(decimalFromScaled(0, 2), '0,00');
    });

    test('conserva el signo negativo', () {
      expect(decimalFromScaled(-123456, 2), '-1234,56');
      expect(decimalFromScaled(-5, 2), '-0,05');
    });

    test('no escribe "-0,00" cuando el valor es cero', () {
      expect(decimalFromScaled(0, 2), '0,00');
    });

    test('agrupa los miles sólo cuando se pide', () {
      expect(decimalFromScaled(123456789, 2), '1234567,89');
      expect(decimalFromScaled(123456789, 2, grouped: true), '1.234.567,89');
      expect(decimalFromScaled(-123456789, 2, grouped: true), '-1.234.567,89');
    });

    test('recorta ceros finales cuando se pide', () {
      expect(decimalFromScaled(20000, 3, trimTrailingZeros: true), '20');
      expect(decimalFromScaled(20500, 3, trimTrailingZeros: true), '20,5');
      expect(decimalFromScaled(20505, 3, trimTrailingZeros: true), '20,505');
    });

    test('un importe enorme no pierde precisión', () {
      // 999.999.999.999 centavos = Bs 9.999.999.999,99. Con `double` el último
      // dígito no sobreviviría; con enteros sí.
      expect(
        decimalFromScaled(999999999999, 2, grouped: true),
        '9.999.999.999,99',
      );
    });
  });

  group('celdas', () {
    test('el importe usa dos decimales fijos', () {
      expect(const ReportMoney(100).csvText, '1,00');
      expect(const ReportMoney(100).displayText, '1,00');
    });

    test('la cantidad recorta ceros y no lleva unidad', () {
      expect(const ReportQuantity(20000).csvText, '20');
      expect(const ReportQuantity(1500).csvText, '1,5');
    });

    test('el área se expresa en hectáreas', () {
      // 100 000 m² son 10 ha exactas.
      expect(const ReportArea(100000).csvText, '10');
      expect(const ReportArea(15000).csvText, '1,5');
    });

    test('la fecha se presenta como dd/mm/aaaa', () {
      expect(
        const ReportDate('2026-03-01T00:00:00.000Z').csvText,
        '01/03/2026',
      );
    });

    test('una celda vacía no es un cero', () {
      expect(const ReportBlank().csvText, '');
      expect(const ReportBlank().displayText, '');
    });

    test('sólo los números se declaran numéricos', () {
      expect(const ReportMoney(1).isNumeric, isTrue);
      expect(const ReportQuantity(1).isNumeric, isTrue);
      expect(const ReportArea(1).isNumeric, isTrue);
      expect(const ReportCount(1).isNumeric, isTrue);
      expect(const ReportText('x').isNumeric, isFalse);
      expect(const ReportDate('2026-01-01').isNumeric, isFalse);
      expect(const ReportBlank().isNumeric, isFalse);
    });
  });

  group('ReportTable', () {
    test('rechaza una fila con un número de celdas distinto', () {
      expect(
        () => ReportTable(
          title: 'x',
          generatedAt: now,
          columns: const [ReportColumn('A'), ReportColumn('B')],
          rows: const [
            [ReportText('sola')],
          ],
        ),
        throwsA(isA<ReportCompositionException>()),
      );
    });

    test('rechaza un reporte sin columnas', () {
      expect(
        () => ReportTable(
          title: 'x',
          generatedAt: now,
          columns: const [],
          rows: const [],
        ),
        throwsA(isA<ReportCompositionException>()),
      );
    });
  });

  InventoryLineRead inventoryLine({
    required String name,
    required int available,
    required int committed,
    required int value,
    String unit = 'L',
  }) => InventoryLineRead(
    productId: 1,
    productName: name,
    unit: unit,
    purchasedBase: available + 1000,
    consumedBase: 1000,
    availableBase: available,
    committedBase: committed,
    projectedBase: available - committed,
    availableValueBobMinor: value,
    peopleCount: 1,
  );

  group('inventario', () {
    test('una fila por producto y el valor total sumado', () {
      final table = composer.inventory(
        generatedAt: now,
        lines: [
          inventoryLine(
            name: 'Glifosato',
            available: 15000,
            committed: 2000,
            value: 150000,
          ),
          inventoryLine(
            name: 'Paraquat',
            available: 10000,
            committed: 0,
            value: 50000,
            unit: 'KG',
          ),
        ],
      );
      expect(table.title, 'Inventario');
      expect(table.rows, hasLength(2));
      expect(table.columns.map((c) => c.header).toList(), [
        'Producto',
        'Unidad',
        'Físico',
        'Comprometido',
        'Proyectado',
        'Valor (Bs)',
      ]);
      // 150000 + 50000 = 200000 centavos.
      expect((table.totals.single.cell as ReportMoney).minor, 200000);
    });

    test('conserva el orden en que llegan las filas', () {
      final table = composer.inventory(
        generatedAt: now,
        lines: [
          inventoryLine(name: 'Zeta', available: 0, committed: 0, value: 0),
          inventoryLine(name: 'Alfa', available: 0, committed: 0, value: 0),
        ],
      );
      expect((table.rows[0][0] as ReportText).value, 'Zeta');
      expect((table.rows[1][0] as ReportText).value, 'Alfa');
    });

    test('un proyectado negativo se conserva con su signo', () {
      final table = composer.inventory(
        generatedAt: now,
        lines: [
          inventoryLine(
            name: 'Glifosato',
            available: 1000,
            committed: 4000,
            value: 0,
          ),
        ],
      );
      expect((table.rows.single[4] as ReportQuantity).base, -3000);
    });

    test('sin productos el reporte existe con cabeceras y total en cero', () {
      final table = composer.inventory(generatedAt: now, lines: const []);
      expect(table.isEmpty, isTrue);
      expect(table.columns, hasLength(6));
      expect((table.totals.single.cell as ReportMoney).minor, 0);
      expect(table.emptyMessage, isNotEmpty);
    });

    test('no admite filtro de campaña', () {
      expect(ReportKind.inventory.supportsCampaignFilter, isFalse);
    });
  });

  group('costo por producto', () {
    test('suma el costo total y declara la campaña', () {
      final table = composer.productCost(
        generatedAt: now,
        campaignName: 'Campaña 1',
        lines: const [
          ProductCostRead(
            productId: 1,
            productName: 'Glifosato',
            unit: 'L',
            quantityBase: 5000,
            totalCostBobMinor: 50000,
          ),
          ProductCostRead(
            productId: 2,
            productName: 'Paraquat',
            unit: 'KG',
            quantityBase: 0,
            totalCostBobMinor: 0,
          ),
        ],
      );
      expect(table.filters.single.value, 'Campaña 1');
      expect(table.rows, hasLength(2));
      expect((table.totals.single.cell as ReportMoney).minor, 50000);
      // Cantidad y unidad en columnas separadas (EVO-005-REQ-004).
      expect(table.columns[1].header, 'Cantidad');
      expect(table.columns[2].header, 'Unidad');
    });

    test('sin campaña el filtro dice "Todas las campañas"', () {
      final table = composer.productCost(generatedAt: now, lines: const []);
      expect(table.filters.single.value, 'Todas las campañas');
    });
  });

  group('costo por chaco', () {
    FarmCostRead farm(String name, int areaM2, int cost) => FarmCostRead(
      farmId: 1,
      farmName: name,
      ownerName: 'Ana',
      areaM2: areaM2,
      totalCostBobMinor: cost,
    );

    test('incluye costo por hectárea y suma el total', () {
      final table = composer.farmCost(
        generatedAt: now,
        campaignName: 'Campaña 1',
        lines: [farm('Chaco Uno', 100000, 50000), farm('Chaco Dos', 50000, 0)],
      );
      // 10 ha y Bs 500,00 -> Bs 50,00/ha.
      expect((table.rows[0][4] as ReportMoney).minor, 5000);
      expect((table.rows[1][4] as ReportMoney).minor, 0);
      expect((table.totals.single.cell as ReportMoney).minor, 50000);
    });

    test('un chaco sin superficie deja la celda vacía, no un cero', () {
      final table = composer.farmCost(
        generatedAt: now,
        lines: [farm('Anómalo', 0, 1000)],
      );
      expect(table.rows.single[4], isA<ReportBlank>());
    });

    test('un nombre largo viaja íntegro, sin recortar', () {
      final long = 'Chaco de la Comunidad San Juan de la Frontera Norte Alta';
      final table = composer.farmCost(
        generatedAt: now,
        lines: [farm(long, 100000, 0)],
      );
      expect((table.rows.single[0] as ReportText).value, long);
    });
  });

  group('resumen de campaña', () {
    const summary = CampaignSummaryRead(
      purchasesCount: 3,
      purchasesBobMinor: 250000,
      applicationsCount: 2,
      applicationsBobMinor: 50000,
      pendingPlans: 1,
      receivableBobMinor: 300000,
    );

    test('describe compras, aplicaciones, planes y cuentas', () {
      final table = composer.campaignSummary(
        summary: summary,
        campaignName: 'Campaña 1',
        generatedAt: now,
      );
      expect(table.rows, hasLength(4));
      expect((table.rows[0][1] as ReportCount).value, 3);
      expect((table.rows[0][2] as ReportMoney).minor, 250000);
      expect((table.rows[2][1] as ReportCount).value, 1);
      // Los planes pendientes no tienen importe, y el saldo no tiene cantidad.
      expect(table.rows[2][2], isA<ReportBlank>());
      expect(table.rows[3][1], isA<ReportBlank>());
    });

    test('la campaña es obligatoria y viaja como filtro', () {
      expect(ReportKind.campaignSummary.requiresCampaign, isTrue);
      final table = composer.campaignSummary(
        summary: summary,
        campaignName: 'Campaña 1',
        generatedAt: now,
      );
      expect(table.filters.single.value, 'Campaña 1');
    });

    test('los totales repiten los importes de la campaña', () {
      final table = composer.campaignSummary(
        summary: summary,
        campaignName: 'Campaña 1',
        generatedAt: now,
      );
      expect(table.totals.map((t) => (t.cell as ReportMoney).minor).toList(), [
        250000,
        50000,
        300000,
      ]);
    });
  });

  group('estado de cuenta', () {
    StatementEntryRead entry(
      int id,
      String date,
      int amount, {
      String? concept,
      String? farm,
    }) => StatementEntryRead(
      id: id,
      transactionDate: date,
      type: amount > 0 ? 'USAGE_CHARGE' : 'PAYMENT',
      amountBobMinorSigned: amount,
      campaignId: 1,
      concept: concept,
      farmName: farm,
      notes: null,
    );

    test('separa cargo, crédito y acumulado', () {
      final table = composer.accountStatement(
        personName: 'Ana Familiar',
        generatedAt: now,
        entries: [
          entry(
            1,
            '2026-02-01T00:00:00.000Z',
            50000,
            concept: 'Glifosato',
            farm: 'Chaco Uno',
          ),
          entry(2, '2026-03-01T00:00:00.000Z', -20000),
        ],
      );
      expect(table.rows, hasLength(2));
      // Cargo con su chaco, sin crédito.
      expect((table.rows[0][3] as ReportMoney).minor, 50000);
      expect(table.rows[0][4], isA<ReportBlank>());
      expect((table.rows[0][2] as ReportText).value, 'Chaco Uno');
      // Pago: sin cargo, con crédito en positivo.
      expect(table.rows[1][3], isA<ReportBlank>());
      expect((table.rows[1][4] as ReportMoney).minor, 20000);
      // Acumulado 50000 -> 30000.
      expect((table.rows[0][5] as ReportMoney).minor, 50000);
      expect((table.rows[1][5] as ReportMoney).minor, 30000);
    });

    test('los totales cuadran con el último acumulado', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        entries: [
          entry(1, '2026-02-01T00:00:00.000Z', 50000),
          entry(2, '2026-03-01T00:00:00.000Z', -20000),
        ],
      );
      final totals = table.totals.map((t) => (t.cell as ReportMoney).minor);
      expect(totals.toList(), [50000, 20000, 30000]);
    });

    test('con campaña añade el saldo inicial como primera fila', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        campaignName: 'Campaña 2',
        generatedAt: now,
        campaignBalance: const PersonCampaignBalanceRead(
          openingBalanceMinor: 30000,
          campaignChargesMinor: 10000,
          campaignPaymentsMinor: 0,
          totalBalanceMinor: 40000,
        ),
        entries: [entry(1, '2026-08-01T00:00:00.000Z', 10000)],
      );
      expect(table.rows, hasLength(2));
      expect(
        (table.rows[0][1] as ReportText).value,
        'Saldo inicial de campaña',
      );
      expect((table.rows[0][5] as ReportMoney).minor, 30000);
      // El acumulado del movimiento arranca del saldo inicial.
      expect((table.rows[1][5] as ReportMoney).minor, 40000);
    });

    test('sin movimientos el saldo final es el inicial', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        campaignBalance: const PersonCampaignBalanceRead(
          openingBalanceMinor: 30000,
          campaignChargesMinor: 0,
          campaignPaymentsMinor: 0,
          totalBalanceMinor: 30000,
        ),
        entries: const [],
      );
      expect((table.totals.last.cell as ReportMoney).minor, 30000);
    });

    test('sin movimientos ni campaña el reporte queda vacío y en cero', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        entries: const [],
      );
      expect(table.isEmpty, isTrue);
      expect(
        table.totals.every((t) => (t.cell as ReportMoney).minor == 0),
        isTrue,
      );
    });

    test('un concepto crudo se traduce; un chaco ausente queda vacío', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        entries: [
          entry(1, '2026-03-01T00:00:00.000Z', -20000, concept: 'PAYMENT'),
        ],
      );
      expect((table.rows.single[1] as ReportText).value, 'Pago');
      expect((table.rows.single[2] as ReportText).value, '');
    });

    test('una reversión aparece como crédito, no borra el cargo', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        entries: [
          entry(1, '2026-02-01T00:00:00.000Z', 50000),
          StatementEntryRead(
            id: 2,
            transactionDate: '2026-02-02T00:00:00.000Z',
            type: 'CREDIT_ADJUSTMENT',
            amountBobMinorSigned: -50000,
            campaignId: 1,
            concept: null,
            farmName: null,
            notes: null,
          ),
        ],
      );
      expect(table.rows, hasLength(2));
      expect((table.rows[1][4] as ReportMoney).minor, 50000);
      expect((table.rows[1][5] as ReportMoney).minor, 0);
    });

    test('un importe muy grande se conserva entero', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        entries: [entry(1, '2026-02-01T00:00:00.000Z', 999999999999)],
      );
      expect((table.totals.first.cell as ReportMoney).minor, 999999999999);
    });
  });

  group('ReportKind', () {
    test('cada reporte declara sus exigencias de filtro', () {
      expect(ReportKind.accountStatement.requiresPerson, isTrue);
      expect(ReportKind.inventory.requiresPerson, isFalse);
      expect(ReportKind.campaignSummary.requiresCampaign, isTrue);
      expect(ReportKind.farmCost.requiresCampaign, isFalse);
      expect(ReportKind.farmCost.supportsCampaignFilter, isTrue);
    });

    test('los nombres de archivo son distintos y sin acentos', () {
      final names = ReportKind.values.map((k) => k.fileBaseName).toSet();
      expect(names, hasLength(ReportKind.values.length));
      for (final name in names) {
        expect(name, matches(RegExp(r'^[a-z0-9-]+$')));
      }
    });
  });
}
