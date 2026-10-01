import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NeverCommit implements SecureSessionCommitPort {
  @override
  Future<void> commitAndVerify(SessionCommitCandidate candidate) async =>
      throw StateError('Activation is not submitted in this test');
}

void main() {
  sqfliteFfiInit();

  for (final state in ExistingSessionStartupState.values) {
    testWidgets('$state keeps SQLite working and makes no HTTP request', (
      tester,
    ) async {
      var httpCalls = 0;
      final client = MockClient((http.Request request) async {
        httpCalls++;
        return http.Response('', 500);
      });
      addTearDown(client.close);
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = AgroRepository(database);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            existingSessionStartupProvider.overrideWithValue(state),
            authHttpTransportProvider.overrideWithValue(client),
            secureSessionCommitProvider.overrideWithValue(_NeverCommit()),
          ],
          child: const AgroApp(),
        ),
      );
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(DashboardScreen).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final id = await tester.runAsync(
        () => repository.addPerson(
          name: 'Persona local',
          role: PersonRole.family,
        ),
      );
      expect(id, greaterThan(0));
      final rows = await tester.runAsync(
        () async => (await database.database).query(
          'persons',
          where: 'id = ?',
          whereArgs: [id],
        ),
      );
      expect(rows, hasLength(1));
      expect(rows!.single['name'], 'Persona local');
      expect(httpCalls, 0);

      if (state == ExistingSessionStartupState.noLocalSession) {
        expect(find.byKey(const Key('open-first-activation')), findsOneWidget);
        expect(find.byKey(const Key('local-session-status')), findsNothing);
      } else {
        expect(find.byKey(const Key('open-first-activation')), findsNothing);
        expect(find.byKey(const Key('local-session-status')), findsOneWidget);
        expect(find.text(state.safeMessage!), findsOneWidget);
      }

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DashboardScreen)),
      );
      container.read(routerProvider).go('/activar');
      await tester.pumpAndSettle();
      if (state == ExistingSessionStartupState.noLocalSession) {
        expect(find.byKey(const Key('activation-submit')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('activation-submit')), findsNothing);
        expect(
          find.byKey(const Key('existing-session-blocks-activation')),
          findsOneWidget,
        );
      }
      expect(httpCalls, 0);
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join(' ');
      for (final secret in [
        'refreshToken',
        'registrationId',
        'accountId',
        'memberId',
        'tenantId',
        'sessionId',
        'installationClientId',
        'StoredSession',
      ]) {
        expect(visibleText, isNot(contains(secret)));
      }
    });
  }
}
