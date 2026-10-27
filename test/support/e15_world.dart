// Datos de los ejemplos E-15 (docs/architecture/
// D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md parte B): los de D-04 más un
// titular vinculado en `owner_bindings`, con compras y aplicaciones reales
// para que el consumo propio sea el costo FIFO que escribe la app.
//
// Sólo usa API que ya existía en el HEAD de D-04, para que
// `e15_consumo_propio_base_test.dart` compile allí y falle por aserción.

import 'package:agroquimicos/domain/models.dart';

import 'd04_world.dart';

class E15World {
  E15World._(this.w);

  final D04World w;
  late final int titular;
  late final int supplier;
  late final int chacoNorte;
  late final int chacoFamiliar;
  final Map<String, int> products = {};

  /// [titularRole] y [titularPolicy] permiten las bases E15-02a/b.
  static Future<E15World> create({
    PersonRole titularRole = PersonRole.family,
    SettlementPolicy? titularPolicy,
    bool bind = true,
  }) async {
    final world = E15World._(await D04World.create());
    final repo = world.w.repo;
    world.titular = await repo.addPerson(
      name: 'Titular',
      role: titularRole,
      policy: titularPolicy,
    );
    if (bind) await world.bindOwner(world.titular, at(1, 1));
    world.supplier = await repo.addSupplier(name: 'Proveedor');
    world.chacoNorte = await repo.addFarm(
      ownerId: world.titular,
      name: 'Chaco Norte',
      areaM2: 10000,
    );
    world.chacoFamiliar = await repo.addFarm(
      ownerId: world.w.familiar,
      name: 'Chaco Familiar',
      areaM2: 10000,
    );
    for (final name in ['Glifosato', 'Bellator', 'Cipermetrina']) {
      world.products[name] = await repo.addProduct(name: name);
    }
    return world;
  }

  /// Vínculo de titular insertado como lo deja la activación.
  Future<int> bindOwner(int person, String boundAt) async =>
      (await w.db).insert('owner_bindings', {
        'person_id': person,
        'member_id': 'member-e15',
        'tenant_id': 'tenant-e15',
        'owner_role':
            (await (await w.db).query(
                  'persons',
                  columns: ['role'],
                  where: 'id=?',
                  whereArgs: [person],
                )).single['role'] ==
                'ADMIN'
            ? 'ADMIN'
            : 'FAMILY',
        'bound_at': boundAt,
      });

  /// Cambio de titular (`changeOwner`): cierra el vínculo vigente y abre otro.
  Future<void> changeOwner(int newPerson, String at) async {
    final db = await w.db;
    await db.update('owner_bindings', {
      'ended_at': at,
      'end_reason': 'OWNER_CHANGED',
    }, where: 'ended_at IS NULL');
    await bindOwner(newPerson, at);
  }

  /// Compra en Invierno asignada a [person]: [liters] a [priceMinor] Bs/L.
  Future<void> buy(
    int person,
    String product,
    int quantityBase,
    int priceMinor, {
    DateTime? date,
  }) => w.repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: w.invierno,
      purchaseDate: date ?? DateTime(2026, 7, 1),
      items: [
        PurchaseItemDraft(
          productId: products[product]!,
          quantityBase: quantityBase,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: priceMinor,
          allocations: [
            AllocationDraft(personId: person, quantityBase: quantityBase),
          ],
        ),
      ],
    ),
  );

  /// Aplicación en Invierno con costo FIFO real.
  Future<int> apply(
    int person,
    int farm,
    DateTime day,
    Map<String, int> lines,
  ) => w.repo.confirmApplication(
    ApplicationDraft(
      personId: person,
      farmId: farm,
      campaignId: w.invierno,
      appliedAt: day,
      lines: [
        for (final line in lines.entries)
          ApplicationLineDraft(
            productId: products[line.key]!,
            quantityBase: line.value,
          ),
      ],
    ),
  );

  /// E15-01: el titular aplica Glifosato 1 L (45) y Bellator 0,2 L (36) el
  /// 20/10; el familiar, Cipermetrina 0,25 L (20) el 18/10.
  Future<int> seedE1501() async {
    await buy(titular, 'Glifosato', 1000, 4500);
    await buy(titular, 'Bellator', 200, 18000);
    await buy(w.familiar, 'Cipermetrina', 250, 8000);
    await apply(w.familiar, chacoFamiliar, DateTime(2026, 10, 18), {
      'Cipermetrina': 250,
    });
    return apply(titular, chacoNorte, DateTime(2026, 10, 20), {
      'Glifosato': 1000,
      'Bellator': 200,
    });
  }

  Future<void> close() => w.close();
}
