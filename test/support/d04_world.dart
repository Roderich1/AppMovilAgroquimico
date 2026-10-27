// Datos comunes de los ejemplos D-04 (docs/architecture/
// D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md §3.0).
//
// Sólo usa API que ya existía en `ed9c55c` (alta de personas y campañas,
// `addAccountPayment` con `date` de prueba e inserciones directas de asientos)
// para que las pruebas que la usan puedan ejecutarse también sobre la base y
// demostrar que fallan allí.

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Importe como lo pinta la app, sin el espacio final: «81,00 Bs».
String bs(int minor) => formatBob(minor).trim();

/// Instante local de un día (y hora) de 2026: el día local es exacto en
/// cualquier zona horaria.
String at(int month, int day, [int hour = 0]) =>
    DateTime(2026, month, day, hour).toUtc().toIso8601String();

class D04World {
  D04World._(this.database, this.repo);

  final AppDatabase database;
  final AgroRepository repo;
  late final int verano;
  late final int invierno;
  late final int familiar;
  late final int tercero;
  late final int admin;

  /// «Verano 2026» del 01/01 al 30/06, CERRADA; «Invierno 2026» desde el
  /// 01/07, ACTIVA. Familiar Demo, Tercero Demo y un administrador.
  static Future<D04World> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final world = D04World._(database, AgroRepository(database));
    final repo = world.repo;
    world.familiar = await repo.addPerson(
      name: 'Familiar Demo',
      role: PersonRole.family,
    );
    world.tercero = await repo.addPerson(
      name: 'Tercero Demo',
      role: PersonRole.thirdParty,
    );
    world.admin = await repo.addPerson(
      name: 'Administrador',
      role: PersonRole.admin,
    );
    world.verano = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime(2026, 1, 1),
    );
    world.invierno = await repo.addCampaign(
      name: 'Invierno 2026',
      start: DateTime(2026, 7, 1),
    );
    await repo.activateCampaign(world.invierno, closeCurrent: true);
    return world;
  }

  Future<Database> get db => database.database;

  /// Cargo sembrado con su fecha y su campaña de origen.
  Future<int> charge(
    int person,
    int campaign,
    String date,
    int minor, {
    String type = 'USAGE_CHARGE',
  }) async => (await db).insert('account_transactions', {
    'person_id': person,
    'campaign_id': campaign,
    'transaction_date': date,
    'type': type,
    'amount_bob_minor_signed': minor,
    'reference_type': type == 'USAGE_CHARGE'
        ? 'APPLICATION'
        : 'PURCHASE_ALLOCATION',
    'reference_id': null,
  });

  /// Reversión de un cargo (RN-46): `CREDIT_ADJUSTMENT` con su campaña.
  Future<int> reverse(int chargeId, String date) async {
    final row = (await (await db).query(
      'account_transactions',
      where: 'id=?',
      whereArgs: [chargeId],
    )).single;
    return (await db).insert('account_transactions', {
      'person_id': row['person_id'],
      'campaign_id': row['campaign_id'],
      'transaction_date': date,
      'type': 'CREDIT_ADJUSTMENT',
      'amount_bob_minor_signed': -(row['amount_bob_minor_signed']! as int),
      'reference_type': 'APPLICATION_REVERSAL',
      'reversal_of_id': chargeId,
    });
  }

  /// Pago o adelanto por la ruta real (`addAccountPayment`), con fecha fija.
  Future<int> pay(
    int person,
    int minor, {
    int? campaign,
    required String date,
    bool advance = false,
  }) => repo.addAccountPayment(
    personId: person,
    campaignId: campaign,
    amountBobMinor: minor,
    advance: advance,
    date: DateTime.parse(date),
  );

  /// Pago histórico sin imputaciones (base anterior a v3) o con la imputación
  /// que guardó el código anterior.
  Future<int> rawPayment(
    int person,
    int minor, {
    int? campaign,
    required String date,
  }) async => (await db).insert('account_transactions', {
    'person_id': person,
    'campaign_id': campaign,
    'transaction_date': date,
    'type': 'PAYMENT',
    'amount_bob_minor_signed': -minor,
    'reference_type': 'PAYMENT',
  });

  Future<void> rawAllocation(int payment, int chargeId, int minor) async =>
      (await db).insert('payment_allocations', {
        'payment_transaction_id': payment,
        'charge_transaction_id': chargeId,
        'amount_bob_minor': minor,
      });

  /// Imputaciones de [payment] como `{cargo: importe}`.
  Future<Map<int, int>> allocationsOf(int payment) async => {
    for (final row in await (await db).query(
      'payment_allocations',
      where: 'payment_transaction_id=?',
      whereArgs: [payment],
      orderBy: 'id',
    ))
      row['charge_transaction_id']! as int: row['amount_bob_minor']! as int,
  };

  Future<void> close() => database.close();
}
