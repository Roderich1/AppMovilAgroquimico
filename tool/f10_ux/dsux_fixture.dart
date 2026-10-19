// DS-UX Mobile: estado inicial de las sesiones de usabilidad F10 (RNF-07,
// protocolo §3.3–§3.4 con la precisión DS-UX de la v1.4).
//
// HERRAMIENTA DE EVALUACIÓN. No se compila dentro de la aplicación: `lib/` no
// la importa. La usan `seed_dsux_mobile.dart` (siembra), `oracle_dsux_mobile.dart`
// (lectura tras la sesión) y `test/f10_ux_dsux_fixture_test.dart`.
//
// Todo se escribe por las mismas vías que la aplicación: `AgroRepository`
// (campaña, chacos, persona, proveedor, productos y compras con sus reglas de
// fecha efectiva, campaña activa, titular y asignación) y `CentralBindingStore`
// (vínculos explícitos de campaña y productos, con la contención de período
// D-F04-C2). Ninguna inserción directa en tablas de negocio. Nada se publica por
// Sync: la siembra no crea intenciones y lo comprueba.
//
// La composición es fija (DS-UX-1). La semilla identifica la versión del
// dataset; no introduce ninguna elección aleatoria.

import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/sync/campaign_period_check.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String datasetVersion = 'DS-UX-1';
const int seed = 20261018;

const String campaignName = 'Verano Demo';
const String supplierName = 'Proveedor Demo';
const String northFarm = 'Norte';
const String southFarm = 'Sur';
const String relativeName = 'Familiar Demo';
const String glyphosate = 'Glifosato Demo';
const String bellator = 'Bellator';

/// Días respecto del día de la sesión (America/La_Paz).
const int campaignStartOffsetDays = -14;
const int openingPurchaseOffsetDays = -10;
const int campaignPlannedEndOffsetDays = 30;

/// Existencias iniciales en unidades base (mL), cada una con una compra
/// confirmada el día de sesión − 10, a las 09:00.
const Map<String, int> openingStockBase = {glyphosate: 5000, bellator: 1000};

/// Precio unitario (centavos de Bs por litro) de las compras iniciales.
const Map<String, int> openingUnitPriceMinor = {
  glyphosate: 4500,
  bellator: 18000,
};

/// Ejecución nominal de T1 y T2 (tarjetas §3.4): T1 compra 2 L de Glifosato
/// Demo y 500 mL de Bellator; T2 aplica 1 L y 200 mL en «Norte».
const Map<String, int> nominalT1PurchaseBase = {
  glyphosate: 2000,
  bellator: 500,
};
const Map<String, int> nominalT2ApplicationBase = {
  glyphosate: 1000,
  bellator: 200,
};

/// Saldo esperado tras T1 y T2 nominales: Glifosato Demo 6 L, Bellator 1,3 L.
Map<String, int> get nominalBalanceAfterT2 => {
  for (final product in openingStockBase.keys)
    product: expectedBalanceBase(
      openingBase: openingStockBase[product]!,
      savedPurchasesBase: nominalT1PurchaseBase[product]!,
      savedApplicationsBase: nominalT2ApplicationBase[product]!,
    ),
};

/// Oráculo de T3 (y de cualquier lectura de saldo): lo que la aplicación tiene
/// **guardado**, no lo que la tarjeta pedía. Si el participante guardó otra
/// cantidad en T1 o T2, el saldo correcto es el que resulta de lo guardado; el
/// error ya se registró en su tarea y no se corrige.
int expectedBalanceBase({
  required int openingBase,
  required int savedPurchasesBase,
  required int savedApplicationsBase,
}) => openingBase + savedPurchasesBase - savedApplicationsBase;

enum DsuxModality {
  propia(OperationMode.personal),
  compartida(OperationMode.shared);

  const DsuxModality(this.mode);
  final OperationMode mode;

  /// `PROPIA` es el nombre de la app; `INDIVIDUAL` es el valor de la hoja de
  /// registro y de `participantes.csv` para la misma modalidad.
  static DsuxModality parse(String? value) => switch (value?.toUpperCase()) {
    'PROPIA' || 'INDIVIDUAL' => DsuxModality.propia,
    'COMPARTIDA' => DsuxModality.compartida,
    _ => throw DsuxRefused(
      'F10_UX_MODALIDAD debe ser PROPIA (o INDIVIDUAL) o COMPARTIDA '
      '(recibido: $value).',
    ),
  };
}

/// Negativa del generador: se lanza **antes** de escribir nada.
class DsuxRefused implements Exception {
  DsuxRefused(this.message);
  final String message;
  @override
  String toString() => 'DS-UX: $message';
}

/// Día civil `aaaa-mm-dd` desplazado [days] días.
String shiftDay(String day, int days) {
  final parts = day.split('-').map(int.parse).toList();
  return localDay(DateTime(parts[0], parts[1], parts[2] + days, 12));
}

DateTime _at(String day, int hour) {
  final parts = day.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], hour);
}

/// Lee `aaaa-mm-dd` y comprueba que es una fecha real.
String parseSessionDay(String? value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value ?? '');
  if (match == null) {
    throw DsuxRefused(
      'F10_UX_SESSION_DATE debe ser aaaa-mm-dd (recibido: $value).',
    );
  }
  final day = value!;
  if (shiftDay(day, 0) != day) {
    throw DsuxRefused('F10_UX_SESSION_DATE no es una fecha válida: $day.');
  }
  return day;
}

/// Lo que la siembra necesita de Central, ya validado.
class _CentralChoice {
  _CentralChoice(this.campaign, this.period, this.products);
  final CentralCampaign campaign;
  final CentralPeriod period;
  final Map<String, CentralProduct> products;
}

T _single<T>(Iterable<T> items, String what) {
  final list = items.toList();
  if (list.length != 1) {
    throw DsuxRefused(
      list.isEmpty
          ? 'las referencias de Central no tienen $what.'
          : 'las referencias de Central tienen ${list.length} candidatos para '
                '$what; debe haber exactamente uno.',
    );
  }
  return list.single;
}

_CentralChoice _chooseCentral(CentralReferences references) {
  final campaign = _single(
    references.campaigns.where(
      (c) => c.name == campaignName && c.acceptsContributions,
    ),
    'la campaña «$campaignName» abierta a aportes',
  );
  final CentralPeriod period;
  try {
    period = CentralPeriod.of(campaign);
  } on FormatException {
    throw DsuxRefused('las fechas de «$campaignName» en Central no se leen.');
  }
  final products = <String, CentralProduct>{
    for (final name in openingStockBase.keys)
      name: _single(
        references.products.where(
          (p) =>
              p.name == name &&
              p.isActive &&
              p.linkable &&
              p.baseUnit == BaseUnit.ml,
        ),
        'el producto activo «$name» en L',
      ),
  };
  return _CentralChoice(campaign, period, products);
}

/// Resultado de la siembra, para `DSUX_RESULT`.
typedef DsuxResult = Map<String, Object?>;

/// Siembra DS-UX sobre una copia **recién activada** de `.f10ux`.
///
/// Comprueba todo antes de escribir: base sin negocio previo, titular
/// vinculado y su tenant, modalidad igual a [modality], referencias centrales
/// únicas y período local contenido en el central, y fechas no futuras
/// respecto de [now]. Si algo no cumple, lanza [DsuxRefused] sin tocar la base.
Future<DsuxResult> seedDsux({
  required AppDatabase database,
  required String sessionDay,
  required DsuxModality modality,
  required CentralReferences references,
  DateTime Function() now = DateTime.now,
}) async {
  final db = await database.database;
  final repo = AgroRepository(database);
  Future<int> count(String sql, [List<Object?> args = const []]) async =>
      ((await db.rawQuery(sql, args)).first.values.first as int?) ?? 0;

  // 1. Base recién activada: sin negocio, sin vínculos, sin necesidades.
  for (final table in [
    'products',
    'suppliers',
    'campaigns',
    'farms',
    'purchases',
    'applications',
    'application_plans',
    'transfers',
    'declared_needs',
    'campaign_bindings',
    'product_bindings',
  ]) {
    if (await count('SELECT COUNT(*) FROM $table') != 0) {
      throw DsuxRefused(
        '$table ya tiene filas: DS-UX sólo va sobre una copia recién '
        'activada (reinstale `.f10ux` y active de nuevo).',
      );
    }
  }
  if (await count('SELECT COUNT(*) FROM persons') != 1) {
    throw DsuxRefused('la copia debe tener sólo el titular creado al activar.');
  }
  final context = await repo.operatingContext();
  final owner = context.ownerPersonId;
  if (owner == null) throw DsuxRefused('la copia no tiene titular vinculado.');
  final ownerRows = await db.query(
    'owner_bindings',
    columns: ['tenant_id'],
    where: 'ended_at IS NULL',
  );
  if (ownerRows.length != 1) {
    throw DsuxRefused('la copia no tiene un único vínculo de titular vigente.');
  }
  final tenantId = ownerRows.single['tenant_id']! as String;
  if (context.mode != modality.mode) {
    throw DsuxRefused(
      'la copia está en modalidad ${context.mode.code} y se pidió '
      '${modality.name.toUpperCase()}: la modalidad se elige al activar, '
      'no la cambia el generador.',
    );
  }

  // 2. Fechas: campaña de sesión − 14 a sesión + 30 (o el fin central, si es
  //    anterior), compra inicial en sesión − 10 a las 09:00.
  final startDay = shiftDay(sessionDay, campaignStartOffsetDays);
  final purchaseDay = shiftDay(sessionDay, openingPurchaseOffsetDays);
  final today = localDay(now());
  if (purchaseDay.compareTo(today) > 0) {
    throw DsuxRefused(
      'la compra inicial (${displayDay(purchaseDay)}) sería futura: la '
      'siembra se hace como mucho 10 días antes de la sesión.',
    );
  }
  if (sessionDay.compareTo(today) < 0) {
    throw DsuxRefused('el día de sesión (${displayDay(sessionDay)}) ya pasó.');
  }

  // 3. Central: una campaña y dos productos, y período contenido.
  final central = _chooseCentral(references);
  var endDay = shiftDay(sessionDay, campaignPlannedEndOffsetDays);
  final centralEnd = central.period.endDay;
  if (centralEnd != null && centralEnd.compareTo(endDay) < 0) {
    endDay = centralEnd;
  }
  if (endDay.compareTo(sessionDay) < 0) {
    throw DsuxRefused(
      '«$campaignName» de Central termina el ${displayDay(centralEnd!)}, '
      'antes del día de sesión.',
    );
  }
  final localPeriod = CampaignPeriod(
    id: -1,
    name: campaignName,
    status: 'ACTIVE',
    startDay: startDay,
    endDay: endDay,
  );
  final mismatch = periodMismatch(localPeriod, central.period);
  if (mismatch != null) {
    throw DsuxRefused(
      '${periodMismatchMessage(localName: campaignName, local: localPeriod, centralName: central.campaign.name, central: central.period, mismatch: mismatch)} '
      'Central debe publicar «$campaignName» desde el ${displayDay(startDay)} '
      'como tarde.',
    );
  }

  final outboxBefore = await count('SELECT COUNT(*) FROM sync_outbox');
  final outboxMaxBefore = await count(
    'SELECT COALESCE(MAX(rowid), 0) FROM sync_outbox',
  );

  // 4. Escritura, por las vías de la aplicación.
  final campaignId = await repo.addCampaign(
    name: campaignName,
    start: _at(startDay, 0),
    end: _at(endDay, 0),
  );
  final farms = {
    northFarm: await repo.addFarm(
      ownerId: owner,
      name: northFarm,
      areaM2: 10000,
    ),
    southFarm: await repo.addFarm(
      ownerId: owner,
      name: southFarm,
      areaM2: 8000,
    ),
  };
  final relative = modality == DsuxModality.compartida
      ? await repo.addPerson(name: relativeName, role: PersonRole.family)
      : null;
  final supplierId = await repo.addSupplier(name: supplierName);
  final productIds = <String, int>{
    for (final name in openingStockBase.keys)
      name: await repo.addProduct(name: name, unit: 'L'),
  };
  var invoice = 0;
  for (final name in openingStockBase.keys) {
    invoice++;
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierId,
        campaignId: campaignId,
        purchaseDate: _at(purchaseDay, 9),
        invoiceNumber: 'DSUX-INI-$invoice',
        items: [
          PurchaseItemDraft(
            productId: productIds[name]!,
            quantityBase: openingStockBase[name]!,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: openingUnitPriceMinor[name]!,
            allocations: [
              AllocationDraft(
                personId: owner,
                quantityBase: openingStockBase[name]!,
              ),
            ],
          ),
        ],
      ),
    );
  }
  final bindings = CentralBindingStore(database);
  await bindings.bindCampaign(
    campaignId: campaignId,
    central: central.campaign,
    tenantId: tenantId,
  );
  for (final name in openingStockBase.keys) {
    await bindings.bindProduct(
      productId: productIds[name]!,
      central: central.products[name]!,
      tenantId: tenantId,
    );
  }

  // 5. Invariantes.
  final balances = <String, int>{
    for (final name in openingStockBase.keys)
      name: await count(
        'SELECT COALESCE(SUM(quantity_signed), 0) FROM inventory_movements '
        'WHERE product_id = ?',
        [productIds[name]],
      ),
  };
  final campaign = (await db.query(
    'campaigns',
    where: 'id = ?',
    whereArgs: [campaignId],
  )).single;
  final integrity = (await db.rawQuery('PRAGMA integrity_check'))
      .first
      .values
      .first;
  final result = <String, Object?>{
    'dataset': datasetVersion,
    'seed': seed,
    'session_day': sessionDay,
    'modality': modality.name.toUpperCase(),
    'operation_mode': context.mode.code,
    'campaign': {
      'name': campaign['name'],
      'status': campaign['status'],
      'start_day': localDay(DateTime.parse(campaign['start_date']! as String)),
      'end_day': localDay(DateTime.parse(campaign['end_date']! as String)),
      'binding': await _bindingStatus(
        db,
        'campaign_bindings',
        'campaign_id',
        campaignId,
      ),
      'central_period': central.period.describe,
    },
    'farms': farms.keys.toList(),
    'persons': await count('SELECT COUNT(*) FROM persons'),
    'relative': relative == null ? null : relativeName,
    'supplier': supplierName,
    'products': {
      for (final name in openingStockBase.keys)
        name: {
          'balance_base': balances[name],
          'binding': await _bindingStatus(
            db,
            'product_bindings',
            'product_id',
            productIds[name]!,
          ),
        },
    },
    'purchases': await count('SELECT COUNT(*) FROM purchases'),
    'opening_purchase_day': purchaseDay,
    'declared_needs': await count('SELECT COUNT(*) FROM declared_needs'),
    'sync_outbox_before': outboxBefore,
    'sync_outbox_after': await count('SELECT COUNT(*) FROM sync_outbox'),
    'sync_outbox_max_rowid_after': await count(
      'SELECT COALESCE(MAX(rowid), 0) FROM sync_outbox',
    ),
    'sync_outbox_max_rowid_before': outboxMaxBefore,
    'nominal_after_t2_base': nominalBalanceAfterT2,
    'integrity_check': integrity,
  };
  return result;
}

Future<String?> _bindingStatus(
  DatabaseExecutor db,
  String table,
  String column,
  int id,
) async {
  final rows = await db.query(
    table,
    columns: ['status'],
    where: '$column = ?',
    whereArgs: [id],
  );
  return rows.isEmpty ? null : rows.single['status'] as String?;
}

/// Lectura tras la sesión (o tras T2, para auditar la hoja del facilitador):
/// saldo **guardado** de cada producto DS-UX, total y por persona, las
/// operaciones que lo explican y la necesidad declarada de T4. No escribe ni
/// corrige nada: abre [db] tal como está.
Future<Map<String, Object?>> dsuxOracle(DatabaseExecutor db) async {
  Future<int> count(String sql, [List<Object?> args = const []]) async =>
      ((await db.rawQuery(sql, args)).first.values.first as int?) ?? 0;
  final products = <String, Object?>{};
  for (final name in openingStockBase.keys) {
    final rows = await db.query(
      'products',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
    );
    if (rows.length != 1) {
      products[name] = {
        'error': 'producto ausente o repetido (${rows.length})',
      };
      continue;
    }
    final id = rows.single['id']! as int;
    final opening = await count(
      'SELECT COALESCE(SUM(pi.quantity_base), 0) FROM purchase_items pi '
      'JOIN purchases p ON p.id = pi.purchase_id '
      "WHERE pi.product_id = ? AND p.status = 'CONFIRMED' "
      "AND p.invoice_number LIKE 'DSUX-INI-%'",
      [id],
    );
    final purchases = await db.rawQuery(
      'SELECT p.id, p.purchase_date, p.status, pi.quantity_base '
      'FROM purchase_items pi JOIN purchases p ON p.id = pi.purchase_id '
      "WHERE pi.product_id = ? AND (p.invoice_number IS NULL "
      "OR p.invoice_number NOT LIKE 'DSUX-INI-%') ORDER BY p.id",
      [id],
    );
    final applications = await db.rawQuery(
      'SELECT a.id, a.applied_at, a.status, f.name AS farm, pe.name AS person, '
      'ai.quantity_base FROM application_items ai '
      'JOIN applications a ON a.id = ai.application_id '
      'JOIN farms f ON f.id = a.farm_id JOIN persons pe ON pe.id = a.person_id '
      'WHERE ai.product_id = ? ORDER BY a.id',
      [id],
    );
    int confirmed(List<Map<String, Object?>> rows) => rows
        .where((r) => r['status'] == 'CONFIRMED')
        .fold(0, (sum, r) => sum + (r['quantity_base']! as int));
    final balance = await count(
      'SELECT COALESCE(SUM(quantity_signed), 0) FROM inventory_movements '
      'WHERE product_id = ?',
      [id],
    );
    final expected = expectedBalanceBase(
      openingBase: opening,
      savedPurchasesBase: confirmed(purchases),
      savedApplicationsBase: confirmed(applications),
    );
    products[name] = {
      'opening_base': opening,
      'saved_purchases_base': confirmed(purchases),
      'saved_applications_base': confirmed(applications),
      'expected_balance_base': expected,
      'balance_base': balance,
      'consistent': expected == balance,
      'by_person_base': {
        for (final row in await db.rawQuery(
          'SELECT pe.name AS person, SUM(m.quantity_signed) AS s '
          'FROM inventory_movements m JOIN persons pe ON pe.id = m.owner_person_id '
          'WHERE m.product_id = ? GROUP BY pe.name ORDER BY pe.name',
          [id],
        ))
          row['person']! as String: row['s']! as int,
      },
      'purchases_after_seed': purchases,
      'applications': applications,
    };
  }
  final needs = await db.rawQuery(
    'SELECT p.name AS product, c.name AS campaign, n.status, n.quantity_base, '
    'n.current_version FROM declared_needs n '
    'JOIN products p ON p.id = n.product_id '
    'JOIN campaigns c ON c.id = n.campaign_id ORDER BY n.id',
  );
  return {
    'dataset': datasetVersion,
    'products': products,
    'declared_needs': needs,
    'sync_outbox_by_status': {
      for (final row in await db.rawQuery(
        'SELECT status, COUNT(*) AS n FROM sync_outbox GROUP BY status ORDER BY status',
      ))
        row['status']! as String: row['n']! as int,
    },
  };
}

/// Copia [path] (y su `-wal`, si existe) a un directorio temporal, la abre
/// sin migraciones y devuelve el oráculo. El archivo original no se abre.
Future<Map<String, Object?>> dsuxOracleFromFile(String path) async {
  final directory = await Directory.systemTemp.createTemp('dsux_oracle_');
  try {
    final copy = '${directory.path}${Platform.pathSeparator}copia.db';
    await File(path).copy(copy);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('$path$suffix');
      if (side.existsSync()) await side.copy('$copy$suffix');
    }
    final db = await databaseFactoryFfi.openDatabase(copy);
    try {
      return await dsuxOracle(db);
    } finally {
      await db.close();
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
