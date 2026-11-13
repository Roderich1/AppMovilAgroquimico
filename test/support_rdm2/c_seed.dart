// Ronda 2 del rediseño, sesión C: datos SINTÉTICOS para Personas (Cuentas y
// Costos), el estado de cuenta y los movimientos propios. Ningún nombre ni
// importe es real.
//
// Sobre el hogar activado del arnés de F04 (titular vinculado a `memberA`):
//  * titular «Rosa Vargas» (familiar, consumo propio en las dos campañas);
//  * «María Fernanda Quispe de los Ángeles Huanca» (familiar, nombre largo,
//    cargos en Verano y en Invierno, importes grandes);
//  * «Juan Mamani» (tercero, cargo por compra y un pago parcial);
//  * «José Luis Peña Núñez» (familiar, sin movimientos);
//  * «Carlos Administrador» (ADMIN, no participa en la liquidación);
//  * campañas «Verano 2026» (cerrada) e «Invierno 2026» (activa);
//  * un asiento HISTÓRICO de pago del titular, insertado como lo dejaba el
//    menú Q-2 antes del 2026-11-12, para ver cómo se sigue leyendo.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/f04_mode_fixtures.dart';
import '../support/f04_mode_ui_harness.dart';

const rdm2cOwnerName = 'Rosa Vargas';
const rdm2cLongName = 'María Fernanda Quispe de los Ángeles Huanca';
const rdm2cThirdName = 'Juan Mamani';
const rdm2cQuietName = 'José Luis Peña Núñez';
const rdm2cAdminName = 'Carlos Administrador';

class Rdm2cWorld {
  Rdm2cWorld(this.database, this.h);
  final AppDatabase database;
  final Household h;
  late int quiet;
  late int admin;
  late int verano;
  late int invierno;
  late int herbicida;
  late int historicalOwnPayment;

  AgroRepository get repo => h.repo;
  int get owner => h.titular;
  int get longName => h.relative;
  int get third => h.thirdParty;
}

Future<int> _buy(
  Household h, {
  required int campaign,
  required int person,
  required int product,
  required int quantity,
  required int priceMinor,
  required DateTime date,
}) => h.repo.confirmPurchase(
  PurchaseDraft(
    supplierId: h.supplier,
    campaignId: campaign,
    purchaseDate: date,
    items: [
      PurchaseItemDraft(
        productId: product,
        quantityBase: quantity,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: priceMinor,
        allocations: [AllocationDraft(personId: person, quantityBase: quantity)],
      ),
    ],
  ),
);

Future<void> _apply(
  Household h, {
  required int campaign,
  required int person,
  required int farm,
  required int product,
  required int quantity,
  required DateTime date,
}) => h.repo.confirmApplication(
  ApplicationDraft(
    personId: person,
    farmId: farm,
    campaignId: campaign,
    appliedAt: date,
    lines: [ApplicationLineDraft(productId: product, quantityBase: quantity)],
  ),
);

/// Siembra el mundo de la sesión C. [historicalOwnPayment] deja el asiento
/// histórico de pago del titular. Sin [withBalances] sólo hay personas,
/// chacos y campañas (sin compras, aplicaciones ni asientos): así se puede
/// pasar a inventario propio.
Future<Rdm2cWorld> seedRdm2cWorld(
  WidgetTester tester,
  String name, {
  bool historicalOwnPayment = true,
  bool withBalances = true,
}) async {
  final s = await activatedHousehold(tester, name);
  final w = Rdm2cWorld(s.database, s.household);
  await tester.runAsync(() async {
    final h = w.h;
    final repo = h.repo;
    final db = await s.database.database;
    await db.update(
      'persons',
      {'name': rdm2cOwnerName},
      where: 'id=?',
      whereArgs: [h.titular],
    );
    await db.update(
      'persons',
      {'name': rdm2cLongName},
      where: 'id=?',
      whereArgs: [h.relative],
    );
    await db.update(
      'persons',
      {'name': rdm2cThirdName},
      where: 'id=?',
      whereArgs: [h.thirdParty],
    );
    await db.update(
      'campaigns',
      {'name': 'Verano 2026'},
      where: 'id=?',
      whereArgs: [h.campaign],
    );
    w
      ..verano = h.campaign
      ..quiet = await repo.addPerson(
        name: rdm2cQuietName,
        role: PersonRole.family,
      )
      ..admin = await repo.addPerson(
        name: rdm2cAdminName,
        role: PersonRole.admin,
      )
      ..herbicida = await repo.addProduct(name: 'Herbicida selectivo');
    final thirdFarm = await repo.addFarm(
      ownerId: h.thirdParty,
      name: 'Chaco Río Grande de la Quebrada',
      areaM2: 25000,
    );
    if (!withBalances) {
      w.invierno = await repo.addCampaign(
        name: 'Invierno 2026',
        start: DateTime(2026, 7, 1),
      );
      await repo.activateCampaign(w.invierno, closeCurrent: true);
      return;
    }
    // Verano: compras y aplicaciones con importes grandes.
    await _buy(
      h,
      campaign: w.verano,
      person: h.relative,
      product: h.product,
      quantity: 150000,
      priceMinor: 11850,
      date: DateTime(2026, 1, 5),
    );
    await _buy(
      h,
      campaign: w.verano,
      person: h.titular,
      product: h.product,
      quantity: 20000,
      priceMinor: 11850,
      date: DateTime(2026, 1, 5),
    );
    await _buy(
      h,
      campaign: w.verano,
      person: h.thirdParty,
      product: w.herbicida,
      quantity: 8000,
      priceMinor: 15000,
      date: DateTime(2026, 1, 6),
    );
    await _apply(
      h,
      campaign: w.verano,
      person: h.relative,
      farm: h.relativeFarm,
      product: h.product,
      quantity: 90000,
      date: DateTime(2026, 2, 3),
    );
    await _apply(
      h,
      campaign: w.verano,
      person: h.titular,
      farm: h.titularFarm,
      product: h.product,
      quantity: 6000,
      date: DateTime(2026, 2, 4),
    );
    await _apply(
      h,
      campaign: w.verano,
      person: h.thirdParty,
      farm: thirdFarm,
      product: w.herbicida,
      quantity: 3000,
      date: DateTime(2026, 2, 6),
    );
    await repo.registerAccountPayment(
      personId: h.thirdParty,
      campaignId: w.verano,
      amountBobMinor: 50000,
      date: DateTime(2026, 3, 1),
    );
    // Invierno, activa desde el 01/07.
    w.invierno = await repo.addCampaign(
      name: 'Invierno 2026',
      start: DateTime(2026, 7, 1),
    );
    await repo.activateCampaign(w.invierno, closeCurrent: true);
    for (final (person, farm, quantity) in [
      (h.relative, h.relativeFarm, 30000),
      (h.titular, h.titularFarm, 8000),
    ]) {
      await _apply(
        h,
        campaign: w.invierno,
        person: person,
        farm: farm,
        product: h.product,
        quantity: quantity,
        date: DateTime(2026, 8, 10),
      );
    }
    await repo.registerAccountPayment(
      personId: h.relative,
      campaignId: w.invierno,
      amountBobMinor: 250000,
      date: DateTime(2026, 9, 1),
    );
    if (historicalOwnPayment) {
      // Como lo dejaba el menú Q-2 (pago propio del titular): un PAYMENT
      // negativo de la persona titular, sin imputación a ningún cargo.
      w.historicalOwnPayment = await db.insert('account_transactions', {
        'person_id': h.titular,
        'campaign_id': w.invierno,
        'transaction_date': DateTime(2026, 9, 2).toUtc().toIso8601String(),
        'type': 'PAYMENT',
        'amount_bob_minor_signed': -20000,
        'reference_type': 'PAYMENT',
        'notes': null,
      });
      // Imputado a su propio cargo de Invierno, como el asiento visto en el
      // emulador el 2026-11-12 («Imputado: Invierno 2026 …»).
      final ownCharge = (await db.query(
        'account_transactions',
        where: "person_id=? AND campaign_id=? AND type='USAGE_CHARGE'",
        whereArgs: [h.titular, w.invierno],
      )).single;
      await db.insert('payment_allocations', {
        'payment_transaction_id': w.historicalOwnPayment,
        'charge_transaction_id': ownCharge['id'],
        'amount_bob_minor': 20000,
      });
    }
  });
  return w;
}
