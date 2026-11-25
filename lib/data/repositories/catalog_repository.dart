import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import '../../domain/models.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../app_database.dart';
import '../product_photo_storage.dart';
import '../sync/identification_request_store.dart'
    show IdentificationRequestStore;
import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';

/// Sub-repositorio de catálogos (personas, chacos, productos, proveedores),
/// perfiles y fotografías de etiqueta (E1).
class CatalogRepository {
  CatalogRepository(
    this._session, {
    Future<Directory> Function()? productPhotoDocuments,
  }) : _productPhotoDocuments = productPhotoDocuments;

  final RepositorySession _session;
  final Future<Directory> Function()? _productPhotoDocuments;

  Future<int> addPerson({
    required String name,
    required PersonRole role,
    SettlementPolicy? policy,
    String? phone,
  }) {
    final effective =
        policy ??
        switch (role) {
          PersonRole.admin => SettlementPolicy.manual,
          PersonRole.family => SettlementPolicy.byActualUsage,
          PersonRole.thirdParty => SettlementPolicy.byPurchaseAllocation,
        };
    return _session.write(
      (txn, _) => txn.insert('persons', {
        'name': name.trim(),
        'role': role.code,
        'settlement_policy': effective.code,
        'phone': phone,
        'created_at': _session.date(DateTime.now()),
      }),
    );
  }

  Future<int> addFarm({
    required int ownerId,
    required String name,
    required int areaM2,
    String? location,
  }) => _session.write((txn, context) {
    _session.requireOwnerInPersonal(context, [
      ownerId,
    ], 'En el modo individual los chacos pertenecen al titular.');
    return txn.insert('farms', {
      'owner_person_id': ownerId,
      'name': name.trim(),
      'area_m2': areaM2,
      'location': location,
    });
  });

  Future<int> addProduct({
    required String name,
    String? activeIngredient,
    String unit = 'L',
  }) => _session.write(
    (txn, _) => txn.insert('products', {
      'name': name.trim(),
      'active_ingredient': activeIngredient,
      'unit': unit,
      'base_unit': unit == 'L' ? 'ML' : 'G',
    }),
  );

  Future<int> addSupplier({
    required String name,
    String? phone,
    String? notes,
  }) => _session.write(
    (txn, _) => txn.insert('suppliers', {
      'name': name.trim(),
      'phone': phone,
      'notes': notes,
    }),
  );

  Future<List<Map<String, Object?>>> list(
    String table, {
    String? orderBy,
  }) async => (await _session.db).query(table, orderBy: orderBy ?? 'id DESC');

  Future<void> renameCatalog(String table, int id, String name) async {
    const allowed = {'persons', 'farms', 'products', 'suppliers', 'campaigns'};
    if (!allowed.contains(table)) throw ArgumentError('Catálogo no permitido.');
    if (name.trim().isEmpty) {
      throw BusinessRuleException('El nombre no puede estar vacío.');
    }
    await _session.write(
      (txn, _) => txn.update(
        table,
        {'name': name.trim()},
        where: 'id=?',
        whereArgs: [id],
      ),
    );
  }

  Future<void> archiveCatalog(String table, int id) async {
    const activeTables = {'persons', 'farms', 'products', 'suppliers'};
    if (!activeTables.contains(table) && table != 'campaigns') {
      throw ArgumentError('Catálogo no permitido.');
    }
    await _session.write((txn, context) async {
      if (table == 'persons' && id == context.ownerPersonId) {
        throw BusinessRuleException(
          'El titular vinculado no se puede archivar.',
        );
      }
      await txn.update(
        table,
        activeTables.contains(table) ? {'active': 0} : {'status': 'CLOSED'},
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, Object?>>> people() async =>
      (await _session.db).query('persons', where: 'active=1', orderBy: 'name');

  /// Personas activas que pueden cumplir [purpose] según el titular y la
  /// modalidad (`person_roles.dart`). Una sola consulta: personas, modalidad
  /// y titular se leen juntos.
  Future<List<Map<String, Object?>>> peopleFor(PersonPurpose purpose) async =>
      (await peopleAndContextFor(purpose)).people;

  /// Como [peopleFor], y además la modalidad y el titular con que se
  /// filtró, para que el formulario sepa si debe ocultar la elección de
  /// persona (#26). Sigue siendo una sola consulta.
  Future<({List<Map<String, Object?>> people, WriteContext context})>
  peopleAndContextFor(PersonPurpose purpose) async {
    final rows = await (await _session.db).rawQuery(
      'SELECT ${RepositorySession.contextColumns}, p.* FROM (SELECT 1) '
      'LEFT JOIN persons p ON p.active=1 ORDER BY p.name',
      [AppDatabase.operationModeKey],
    );
    final mode = OperationMode.fromCode(rows.first['context_mode'] as String?);
    final owner = rows.first['context_owner'] as int?;
    return (
      people: eligiblePeople(
        [
          for (final row in rows)
            if (row['id'] != null) _stripContextColumns(row),
        ],
        purpose,
        ownerPersonId: owner,
        mode: mode,
      ),
      context: (mode: mode, ownerPersonId: owner),
    );
  }

  Future<List<Map<String, Object?>>> products() async =>
      (await _session.db).query('products', where: 'active=1', orderBy: 'name');

  Future<List<Map<String, Object?>>> suppliers() async => (await _session.db)
      .query('suppliers', where: 'active=1', orderBy: 'name');

  Future<List<Map<String, Object?>>> farms() async =>
      (await _session.db).rawQuery(
        'SELECT f.*, p.name owner_name FROM farms f JOIN persons p ON p.id=f.owner_person_id WHERE f.active=1 ORDER BY f.name',
      );

  /// Chacos que se pueden planificar o aplicar según la modalidad: en propio,
  /// sólo los del titular (#26). Una sola consulta con modalidad y titular.
  Future<({List<Map<String, Object?>> farms, WriteContext context})>
  farmsAndContext() async {
    final rows = await (await _session.db).rawQuery(
      'SELECT ${RepositorySession.contextColumns}, f.*, p.name owner_name FROM (SELECT 1) '
      'LEFT JOIN (farms f JOIN persons p ON p.id=f.owner_person_id) '
      'ON f.active=1 ORDER BY f.name',
      [AppDatabase.operationModeKey],
    );
    final mode = OperationMode.fromCode(rows.first['context_mode'] as String?);
    final owner = rows.first['context_owner'] as int?;
    return (
      farms: [
        for (final row in rows)
          if (row['id'] != null &&
              (mode != OperationMode.personal ||
                  row['owner_person_id'] == owner))
            _stripContextColumns(row),
      ],
      context: (mode: mode, ownerPersonId: owner),
    );
  }

  static Map<String, Object?> _stripContextColumns(Map<String, Object?> row) =>
      {
        for (final entry in row.entries)
          if (!entry.key.startsWith('context_')) entry.key: entry.value,
      };

  Future<List<Map<String, Object?>>> personProfiles() async =>
      (await _session.db).rawQuery('''SELECT p.*,
        COALESCE((SELECT SUM(f.area_m2) FROM farms f WHERE f.owner_person_id=p.id AND f.active=1),0) area_m2,
        COALESCE((SELECT SUM(t.amount_bob_minor_signed) FROM account_transactions t WHERE t.person_id=p.id),0) balance,
        COALESCE((SELECT COUNT(DISTINCT m.product_id) FROM inventory_movements m
          WHERE m.owner_person_id=p.id GROUP BY m.owner_person_id HAVING SUM(m.quantity_signed)<>0),0) stock_products
        FROM persons p WHERE p.active=1 ORDER BY p.name''');

  Future<Map<String, Object?>> personProfile(int personId) async {
    final rows = await (await _session.db).rawQuery(
      '''SELECT p.*,
      COALESCE((SELECT SUM(f.area_m2) FROM farms f WHERE f.owner_person_id=p.id AND f.active=1),0) area_m2,
      COALESCE((SELECT SUM(t.amount_bob_minor_signed) FROM account_transactions t WHERE t.person_id=p.id),0) balance
      FROM persons p WHERE p.id=?''',
      [personId],
    );
    if (rows.isEmpty) throw BusinessRuleException('La persona no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> farmsForPerson(int personId) async =>
      (await _session.db).query(
        'farms',
        where: 'owner_person_id=? AND active=1',
        whereArgs: [personId],
        orderBy: 'name',
      );

  Future<Map<String, Object?>> farmProfile(int farmId) async {
    final rows = await (await _session.db).rawQuery(
      '''SELECT f.*, p.name owner_name FROM farms f
      JOIN persons p ON p.id=f.owner_person_id WHERE f.id=?''',
      [farmId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El chaco no existe.');
    return rows.single;
  }

  /// Foto de la etiqueta de [productId] (E1-D10), o null si no tiene.
  /// [ProductPhoto.exists] es falso si la base la registra pero el archivo
  /// ya no está en el teléfono.
  Future<ProductPhoto?> productPhoto(int productId) async {
    final rows = await (await _session.db).query(
      'products',
      columns: ['photo_path', 'photo_sha256', 'photo_updated_at'],
      where: 'id=?',
      whereArgs: [productId],
    );
    if (rows.isEmpty) return null;
    final relative = rows.single['photo_path'] as String?;
    final sha = rows.single['photo_sha256'] as String?;
    if (relative == null || sha == null) return null;
    final file = productPhotoFile(await _photoDocuments(), relative);
    if (file == null) return null;
    return ProductPhoto(
      productId: productId,
      relativePath: relative,
      file: file,
      sha256: sha,
      updatedAt: rows.single['photo_updated_at'] as String?,
      exists: await file.exists(),
    );
  }

  /// Guarda como foto de la etiqueta de [productId] la imagen de
  /// [sourcePath], ya procesada: orientación aplicada, lado mayor ≤ 1600 px y
  /// JPEG sin metadatos. Reemplazar borra el archivo anterior.
  Future<ProductPhoto> setProductPhoto(
    int productId,
    String sourcePath, {
    bool? shareWithUnion,
  }) async {
    final processed = await _processPhotoFile(sourcePath);
    final documents = await _photoDocuments();
    final relative = productPhotoRelativePath(productId, processed.sha256);
    final target = productPhotoFile(documents, relative)!;
    String? previous;
    var wroteFile = false;
    try {
      await _session.write((txn, _) async {
        final rows = await txn.query(
          'products',
          columns: ['photo_path'],
          where: 'id=?',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
        previous = rows.single['photo_path'] as String?;
        await target.parent.create(recursive: true);
        await target.writeAsBytes(processed.bytes, flush: true);
        wroteFile = true;
        final now = _session.date(DateTime.now());
        await txn.update(
          'products',
          {
            'photo_path': relative,
            'photo_sha256': processed.sha256,
            'photo_updated_at': now,
          },
          where: 'id=?',
          whereArgs: [productId],
        );
        await IdentificationRequestStore.onPhotoReplaced(
          txn,
          productId,
          newSha: processed.sha256,
          share: shareWithUnion,
          now: now,
        );
      });
    } on Object {
      if (wroteFile && previous != relative) await _deleteQuietly(target);
      rethrow;
    }
    if (previous != null && previous != relative) {
      final old = productPhotoFile(documents, previous);
      if (old != null) await _deleteQuietly(old);
    }
    return (await productPhoto(productId))!;
  }

  Future<ProcessedLabelPhoto> _processPhotoFile(String sourcePath) async {
    try {
      return await compute(
        processLabelPhoto,
        await File(sourcePath).readAsBytes(),
      );
    } on LabelPhotoFormatException catch (error) {
      throw BusinessRuleException(error.toString());
    } on FileSystemException {
      throw BusinessRuleException(
        'No se pudo leer la foto elegida. Inténtelo otra vez.',
      );
    }
  }

  /// Quita la foto de la etiqueta de [productId]: borra el archivo y deja
  /// las columnas en NULL. Si la foto se había compartido con el sindicato,
  /// su retiro queda pendiente de envío (`REMOVE_PENDING`), en la misma
  /// transacción.
  Future<void> removeProductPhoto(int productId) async {
    String? previous;
    await _session.write((txn, _) async {
      final rows = await txn.query(
        'products',
        columns: ['photo_path'],
        where: 'id=?',
        whereArgs: [productId],
      );
      if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
      previous = rows.single['photo_path'] as String?;
      final now = _session.date(DateTime.now());
      await txn.update(
        'products',
        {'photo_path': null, 'photo_sha256': null, 'photo_updated_at': null},
        where: 'id=?',
        whereArgs: [productId],
      );
      await IdentificationRequestStore.onPhotoRemoved(txn, productId, now: now);
    });
    final file = productPhotoFile(await _photoDocuments(), previous);
    if (file != null) await _deleteQuietly(file);
  }

  Future<Directory> _photoDocuments() =>
      _productPhotoDocuments?.call() ?? resolveDocumentsDirectory();

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Limpieza: no cambia el resultado.
    }
  }
}
