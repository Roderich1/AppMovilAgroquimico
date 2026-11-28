import 'package:sqflite/sqflite.dart'
    show Database, DatabaseException, DatabaseExecutor, Transaction;

import '../../domain/installation_access.dart' show OwnerScope;
import '../../domain/operation_mode.dart';
import '../../services/auth/local_owner_credential.dart';
import '../app_database.dart';
import '../app_log.dart';
import '../farmer_operation_gate.dart';
import '../operation_mode_store.dart';
import 'repository_exceptions.dart';
import 'repository_types.dart';

/// Infraestructura compartida de sesión, transacciones atómicas, autorización
/// del titular y guardas de modalidad/activación para los sub-repositorios.
class RepositorySession {
  RepositorySession(
    this.appDatabase, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    LocalOwnerCredential? Function()? ownerCredential,
  }) : _gate = gate,
       _ownerCredential = ownerCredential ?? _noCredential;

  final AppDatabase appDatabase;
  final FarmerOperationGate _gate;
  final LocalOwnerCredential? Function() _ownerCredential;

  static LocalOwnerCredential? _noCredential() => null;

  /// Modalidad y titular vigentes, en una sola consulta.
  static const contextColumns =
      '(SELECT value FROM app_settings WHERE key=?) context_mode, '
      '(SELECT person_id FROM owner_bindings WHERE ended_at IS NULL) '
      'context_owner';

  Future<Database> get db => appDatabase.database;

  String date(DateTime date) => date.toUtc().toIso8601String();

  void ensureGateAllowed() => _gate.ensureAllowed();

  LocalOwnerCredential? currentCredential() => _ownerCredential();

  /// Toda escritura del agricultor pasa por aquí: primero la política de
  /// activación y después, **dentro de la misma transacción que escribe**, la
  /// modalidad y el titular vigentes.
  Future<T> write<T>(
    Future<T> Function(Transaction txn, WriteContext context) body,
  ) => appDatabase.replacement.write(() async {
    _gate.ensureAllowed();
    return (await db).transaction(
      (txn) async => body(txn, await readWriteContext(txn)),
    );
  });

  /// Consume la autorización de una acción del titular dentro de la
  /// transacción que escribe, contra el vínculo y la credencial vigentes leídos
  /// justo antes.
  Future<T> writeAuthorized<T>(
    Future<T> Function(
      Transaction txn,
      Future<void> Function(OwnerAuthorization, AuthorizationPurpose, String)
      consume,
    )
    body,
  ) async {
    var consumed = false;
    try {
      return await write(
        (txn, _) => body(txn, (authorization, purpose, subjectRef) async {
          final current = await currentOwnerBinding(txn);
          consumeOwnerAuthorization(
            authorization,
            installation: _ownerCredential(),
            purpose: purpose,
            subjectRef: subjectRef,
            current: current,
            now: DateTime.now(),
          );
          consumed = true;
        }),
      );
    } catch (error, stack) {
      if (!consumed) rethrow;
      // Sólo el tipo y el código: el texto de SQLite puede llevar datos.
      AppLog.error(
        'Cambio autorizado no guardado tras consumir la '
        'autorización; causa: ${error.runtimeType}'
        '${error is DatabaseException ? ' (código ${error.getResultCode()})' : ''}',
        stackTrace: stack,
      );
      Error.throwWithStackTrace(AuthorizedChangeNotSaved(error), stack);
    }
  }

  Future<WriteContext> readWriteContext(DatabaseExecutor txn) async {
    final mode = await OperationModeStore(appDatabase).current(txn);
    final owner = await txn.query(
      'owner_bindings',
      columns: ['person_id'],
      where: 'ended_at IS NULL',
    );
    final ownerPersonId = owner.isEmpty
        ? null
        : owner.single['person_id'] as int;
    if (mode == OperationMode.personal && ownerPersonId == null) {
      throw PersonalModeRestrictionException(
        'El modo individual necesita un titular vinculado.',
      );
    }
    return (mode: mode, ownerPersonId: ownerPersonId);
  }

  /// Modalidad y titular vigentes, sólo para presentar opciones. Cada
  /// escritura los vuelve a leer dentro de su propia transacción.
  Future<WriteContext> operatingContext() async {
    final row = (await (await db).rawQuery('SELECT $contextColumns', [
      AppDatabase.operationModeKey,
    ])).single;
    return (
      mode: OperationMode.fromCode(row['context_mode'] as String?),
      ownerPersonId: row['context_owner'] as int?,
    );
  }

  /// En modo propio, la persona responsable sólo puede ser el titular.
  void requireOwnerInPersonal(
    WriteContext context,
    Iterable<int> personIds,
    String message,
  ) {
    if (context.mode != OperationMode.personal) return;
    if (personIds.any((id) => id != context.ownerPersonId)) {
      throw PersonalModeRestrictionException(message);
    }
  }

  /// Las transferencias entre responsables no existen en modo propio
  /// (RF-06: el modo compartido habilita responsables y transferencias).
  void rejectTransferInPersonal(WriteContext context) {
    if (context.mode == OperationMode.personal) {
      throw PersonalModeRestrictionException(
        'En el modo individual no hay transferencias entre responsables.',
      );
    }
  }

  Future<void> requireOwnerFarmInPersonal(
    DatabaseExecutor txn,
    WriteContext context,
    int farmId,
  ) async {
    if (context.mode != OperationMode.personal) return;
    final farm = await txn.query(
      'farms',
      columns: ['owner_person_id'],
      where: 'id=?',
      whereArgs: [farmId],
    );
    if (farm.isNotEmpty &&
        farm.single['owner_person_id'] != context.ownerPersonId) {
      throw PersonalModeRestrictionException(
        'En el modo individual sólo se usan los chacos del titular.',
      );
    }
  }

  /// El vínculo de titular vigente, leído en la transacción que escribe.
  Future<OwnerBindingContext?> currentOwnerBinding(DatabaseExecutor txn) async {
    final rows = await txn.query(
      'owner_bindings',
      columns: ['id', 'person_id', 'member_id', 'tenant_id'],
      where: 'ended_at IS NULL',
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return OwnerBindingContext(
      bindingId: row['id']! as int,
      personId: row['person_id']! as int,
      scope: OwnerScope(
        memberId: row['member_id']! as String,
        tenantId: row['tenant_id']! as String,
      ),
    );
  }
}
