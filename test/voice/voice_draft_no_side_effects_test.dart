import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_gateway.dart';
import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/plan/plan_interpreter.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';

/// GATE-F09 (#17): ningún resultado de voz, ninguna edición y ningún descarte
/// escriben en la base antes de la confirmación táctil, en las tres
/// operaciones. Se compara el volcado completo de **todas** las tablas.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late VoiceDraftGateway gateway;

  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final household = await seedHousehold(repo);
    await household.buy(household.titular, 5000);
    await repo.addSupplier(name: 'Agro Norte');
    gateway = VoiceDraftGateway(repo);
  });

  /// Dicta, añade un resultado tardío y luego cancela o libera.
  Future<void> noEffects(
    Future<dynamic> Function() open,
    void Function(dynamic) end,
  ) async {
    final db = await database.database;
    final before = await dumpTables(db);
    final dynamic controller = await open();
    end(controller);
    expect(await controller.confirm(), isNull);
    expect(controller.commitCalls, 0);
    expect(await dumpTables(db), before);
  }

  Future<dynamic> purchase() async {
    final catalog = await gateway.purchaseCatalog();
    final c = VoiceDraftController<VoicePurchaseDraft, int>(
      initial: VoicePurchaseDraft.start(catalog),
      commit: gateway.confirmPurchase,
    );
    for (final text in const [
      'compra de diez litros de Glifosato a 50 bolivianos el litro',
      'proveedor Agro Norte, todo para Hermana',
    ]) {
      c.applyVoice((d) {
        final r = interpretPurchase(text, d, catalog);
        return (r.draft, r.outcome);
      });
    }
    expect(c.canConfirm, isTrue);
    return c;
  }

  Future<dynamic> plan() async {
    final catalog = await gateway.planCatalog();
    final c = VoiceDraftController<VoicePlanDraft, int>(
      initial: VoicePlanDraft.start(catalog),
      commit: gateway.confirmPlan,
    );
    c.applyVoice((d) {
      final r = interpretPlan(
        'planificar el chaco titular con un litro por hectárea de Glifosato',
        d,
        catalog,
      );
      return (r.draft, r.outcome);
    });
    expect(c.canConfirm, isTrue);
    return c;
  }

  Future<dynamic> application() async {
    final catalog = await gateway.applicationCatalog();
    final c = VoiceDraftController<VoiceApplicationDraft, int>(
      initial: VoiceApplicationDraft.start(catalog),
      commit: gateway.confirmApplication,
    );
    c.applyVoice((d) {
      final r = interpretApplication(
        'apliqué dos litros de Glifosato en el chaco titular',
        d,
        catalog,
      );
      return (r.draft, r.outcome);
    });
    final owner = c.draft.person!.id;
    final stock = await gateway.availableStock(owner);
    c.editManually((d) => d.withStock(owner, stock));
    expect(c.canConfirm, isTrue);
    return c;
  }

  final operations = {
    'compra': purchase,
    'planificación': plan,
    'aplicación': application,
  };

  for (final entry in operations.entries) {
    group(entry.key, () {
      test('cancelar no escribe nada', () {
        return noEffects(entry.value, (c) => c.discard());
      });

      test('liberar la pantalla sin confirmar no escribe nada', () {
        return noEffects(entry.value, (c) => c.dispose());
      });

      test('un resultado de voz tras cancelar se descarta entero', () {
        return noEffects(entry.value, (c) {
          c.discard();
          expect(
            c.applyVoice((d) => throw StateError('no debe correr')),
            isFalse,
          );
          expect(c.ignoredVoicePatches, 1);
        });
      });
    });
  }
}
