// Decisión E del autor (cierre, 2026-11-13): «Sesión caducada y decisiones
// pendientes». Con una decisión sobre quién ve sus datos (E4 §4.2, cola
// `joint_purchase_access_ops`) guardada en el teléfono y la sesión en línea
// caducada:
//   (1) el detalle dice que la decisión todavía no se envió;
//   (2) hay un camino para recuperar la sesión y enviarla («Enviar ahora»
//       verifica el acceso; si el sindicato pide volver a autenticar, el
//       aviso lleva a la pantalla existente `/reauth`);
//   (3) nada se muestra como aplicado antes del acuse del sindicato;
//   (4) una reducción a TOTALS_ONLY sin acuse deja a la vista el alcance
//       aplicado (el sindicato manda) y no amplía nada.
// Sin red real: sindicato sintético con MockClient; datos sintéticos.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/presentation/screens/joint_purchase_detail_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:agroquimicos/services/sync/joint_purchase_api.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

/// Sesión remota sintética: sin acceso en memoria (caducado). Verificar en
/// línea renueva el acceso sólo si [refreshWorks]; si no, el sindicato pide
/// volver a autenticar. Volver a autenticar deja el acceso vigente.
class _ExpiredRemote extends RemoteSessionController {
  static bool refreshWorks = false;

  @override
  RemoteSessionState build() =>
      const RemoteSessionState(RemoteSessionPhase.idle);

  void _grant() => ref
      .read(syncAccessHolderProvider)
      .accept('token-sintetico', memberA.memberId, memberA.tenantId);

  @override
  Future<RemoteSessionState> verifyOnline() async {
    if (refreshWorks) {
      _grant();
      return state = const RemoteSessionState(
        RemoteSessionPhase.remoteAvailable,
      );
    }
    return state = const RemoteSessionState(
      RemoteSessionPhase.requiresReauthentication,
    );
  }

  @override
  Future<RemoteSessionState> reauthenticate({
    required String email,
    required String password,
  }) async {
    _grant();
    return state = const RemoteSessionState(RemoteSessionPhase.remoteAvailable);
  }
}

const _pendingRetract =
    'Pendiente de envío: retirar la autorización. Hasta que el sindicato la '
    'reciba, no está aplicada y rige lo que se indica arriba.';
const _adminSees =
    'La Administración habilitada de su sindicato puede ver su nombre y sus '
    'cantidades. La Directiva sólo ve los totales por producto, sin su '
    'nombre.';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var round = 0; round < rounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  /// Detalle de una convocatoria con una participación aceptada con
  /// [scope], acceso en memoria caducado (vacío) y un sindicato sintético
  /// que acepta las decisiones y sirve la lista.
  Future<
    ({
      JointPurchaseStore store,
      ProviderContainer c,
      GoRouter router,
      List<http.Request> requests,
    })
  >
  pumpDetail(WidgetTester tester, {required String scope}) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(
      () => seedSyncFixture(path: inMemoryDatabasePath),
    ))!;
    final store = JointPurchaseStore(fixture.database);
    var accepted = participationJson(consentScope: scope);
    await tester.runAsync(
      () => seedCalls(store, memberA, [callJson(participation: accepted)]),
    );
    final requests = <http.Request>[];
    http.Response central(http.Request request) {
      if (request.method == 'GET') {
        return jsonResponse(listJson([callJson(participation: accepted)]), 200);
      }
      expect(request.url.path, endsWith('/participation/consent'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final consent = body['consent'] as Map<String, dynamic>;
      accepted = {
        ...accepted,
        'consent_scope': {
          'scope': body['scope'],
          'version': consent['version'],
          'decided_at': consent['decided_at'],
          'received_at': '2026-11-13T15:00:00.000Z',
          'sequence': body['sequence'],
        },
      };
      return jsonResponse({
        'outcome': 'ACCEPTED',
        'participation': accepted,
      }, 200);
    }

    final api = JointPurchaseApi(
      json: AuthHttpClient(
        config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
        client: MockClient((request) async {
          requests.add(request);
          return central(request);
        }),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        repositoryProvider.overrideWithValue(fixture.repo),
        declaredNeedStoreProvider.overrideWithValue(fixture.needs),
        centralBindingStoreProvider.overrideWithValue(fixture.bindings),
        syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
        jointPurchaseStoreProvider.overrideWithValue(store),
        jointPurchaseApiProvider.overrideWithValue(api),
        // Sesión caducada: ningún acceso verificado en memoria.
        syncAccessHolderProvider.overrideWithValue(SyncAccessHolder()),
        remoteSessionProvider.overrideWith(_ExpiredRemote.new),
      ],
    );
    addTearDown(container.dispose);
    // La ruta `/reauth` es la existente de la app; aquí basta saber que se
    // abre.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: JointPurchaseDetailScreen(callId: callId)),
        ),
        GoRoute(
          path: '/reauth',
          builder: (_, _) =>
              const Scaffold(body: Text('Pantalla Volver a autenticar')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    return (store: store, c: container, router: router, requests: requests);
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Future<void> retract(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('joint-access-retract')));
    await settle(tester, rounds: 2);
    await tester.tap(find.byKey(const Key('joint-access-retract-check')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('joint-access-retract-confirm')));
    await settle(tester);
  }

  Future<void> sendNow(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('joint-send-now')));
    await tester.tap(find.byKey(const Key('joint-send-now')));
    await settle(tester);
  }

  /// (3) y (4): mientras no hay acuse, lo vigente es lo aplicado.
  Future<void> expectStillAdministration(
    WidgetTester tester,
    JointPurchaseStore store,
  ) async {
    expect(text(tester, 'joint-consent-pending'), _pendingRetract);
    expect(text(tester, 'joint-who-can-see'), _adminSees);
    expect(find.textContaining('Usted retiró la autorización'), findsNothing);
    expect(find.textContaining('aplicada en el sindicato'), findsNothing);
    final call = (await tester.runAsync(() => store.call(callId)))!;
    expect(call.appliedScope, JointPurchaseConsentScope.administration);
    final ops = (await tester.runAsync(() => store.consentOps(callId)))!;
    // Una sola decisión, la reducción; ninguna ampliación añadida.
    expect(ops.map((op) => op.scope), [JointPurchaseConsentScope.totalsOnly]);
    expect(ops.single.isAwaitingSend, isTrue);
  }

  setUp(() => _ExpiredRemote.refreshWorks = false);

  testWidgets('reducir a TOTALS_ONLY con la sesión caducada: «pendiente, no '
      'aplicada», rige lo aplicado; «Enviar ahora» sin sesión no envía nada y '
      'lleva a volver a autenticar; después se envía y sólo con el acuse se '
      'muestra aplicada', (tester) async {
    final s = await pumpDetail(
      tester,
      scope: JointPurchaseConsentScope.administration,
    );
    await retract(tester);
    // (1) Guardada en el teléfono, no enviada (sin acceso, no hay red).
    expect(
      find.text(
        'Retirada guardada en el teléfono: pendiente de envío. Hasta que el '
        'sindicato la reciba, no está aplicada.',
      ),
      findsOneWidget,
    );
    expect(s.requests, isEmpty);
    await expectStillAdministration(tester, s.store);
    expect(find.text('Enviar ahora'), findsOneWidget);

    // «Enviar ahora»: el sindicato pide volver a autenticar. No se envía
    // nada, el aviso dice que lo pendiente no se envió y ofrece la pantalla
    // existente para volver a autenticar.
    await sendNow(tester);
    expect(s.requests, isEmpty);
    expect(
      find.textContaining(
        'Se requiere volver a autenticar para las funciones en línea.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Lo pendiente no se envió'), findsOneWidget);
    await expectStillAdministration(tester, s.store);
    final action = find.widgetWithText(SnackBarAction, 'Volver a autenticar');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await settle(tester, rounds: 3);
    expect(find.text('Pantalla Volver a autenticar'), findsOneWidget);

    // Volver a autenticar (lo que hace `/reauth`) y volver al detalle.
    await tester.runAsync(
      () => s.c
          .read(remoteSessionProvider.notifier)
          .reauthenticate(email: 'titular@example.invalid', password: 'x'),
    );
    s.router.pop();
    await settle(tester);
    await expectStillAdministration(tester, s.store);

    // (2) Ahora sí se envía; (3) sólo con el acuse se muestra aplicada.
    await sendNow(tester);
    final posted = s.requests.where((r) => r.method == 'POST').toList();
    expect(posted, hasLength(1));
    expect(
      (jsonDecode(posted.single.body) as Map<String, dynamic>)['scope'],
      JointPurchaseConsentScope.totalsOnly,
    );
    expect(find.byKey(const Key('joint-consent-pending')), findsNothing);
    expect(
      text(tester, 'joint-who-can-see'),
      startsWith('Usted retiró la autorización'),
    );
    expect(
      text(tester, 'joint-consent-result'),
      'Su última decisión sobre quién ve sus datos está aplicada en el '
      'sindicato.',
    );
    final call = (await tester.runAsync(() => s.store.call(callId)))!;
    expect(call.appliedScope, JointPurchaseConsentScope.totalsOnly);
  });

  testWidgets('acceso en memoria caducado con la sesión todavía renovable: '
      '«Enviar ahora» verifica el acceso y envía la decisión', (tester) async {
    _ExpiredRemote.refreshWorks = true;
    final s = await pumpDetail(
      tester,
      scope: JointPurchaseConsentScope.administration,
    );
    await retract(tester);
    expect(s.requests, isEmpty);
    await expectStillAdministration(tester, s.store);

    await sendNow(tester);
    expect(s.requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(
      text(tester, 'joint-who-can-see'),
      startsWith('Usted retiró la autorización'),
    );
    expect(find.byKey(const Key('joint-consent-pending')), findsNothing);
  });

  testWidgets('autorizar (ADMINISTRATION) con la sesión caducada: pendiente y '
      'no aplicada; lo vigente sigue siendo la autorización retirada', (
    tester,
  ) async {
    final s = await pumpDetail(
      tester,
      scope: JointPurchaseConsentScope.totalsOnly,
    );
    expect(
      text(tester, 'joint-who-can-see'),
      startsWith('Usted retiró la autorización'),
    );
    await tester.tap(find.byKey(const Key('joint-access-review')));
    await settle(tester, rounds: 2);
    await tester.tap(find.byKey(const Key('joint-access-review-check')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('joint-access-review-confirm')));
    await settle(tester);
    expect(s.requests, isEmpty);

    await sendNow(tester);
    expect(s.requests, isEmpty);
    expect(
      text(tester, 'joint-consent-pending'),
      'Pendiente de envío: autorizar a la Administración a ver su nombre y '
      'sus cantidades. Hasta que el sindicato la reciba, no está aplicada y '
      'rige lo que se indica arriba.',
    );
    // (3) La ampliación no se anuncia como vigente sin acuse.
    expect(
      text(tester, 'joint-who-can-see'),
      startsWith('Usted retiró la autorización'),
    );
    expect(find.text(_adminSees), findsNothing);
    final call = (await tester.runAsync(() => s.store.call(callId)))!;
    expect(call.appliedScope, JointPurchaseConsentScope.totalsOnly);
  });
}
