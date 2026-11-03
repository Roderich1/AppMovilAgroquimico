// F12-EST-07-MOB (MOB #164): la estimación dentro de Inventario, con la app
// real (router, base en archivo y control de acceso). Sin conexión: la copia
// con sus fechas, vigencia al descargar y aviso, o «sin copia descargada»;
// con conexión: consulta, descarga y rechazo.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/estimation_copy_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/estimation/farmer_estimation.dart';
import 'package:agroquimicos/presentation/screens/estimation_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support/f12_estimation_fixtures.dart';

Future<void> _saveCopy(WidgetTester tester, AppDatabase database) async {
  await tester.runAsync(() async {
    final binding = (await OwnerBindingStore(database).activeBinding())!;
    final store = EstimationCopyStore(database);
    final grant = await store.grant(
      EstimationIdentity(
        memberId: memberA.memberId,
        tenantId: memberA.tenantId,
        bindingId: binding.id,
      ),
    );
    final json = farmerDownloadJson();
    await store.save(grant, FarmerDownload.fromJson(json), json);
  });
}

Future<void> _openEstimation(WidgetTester tester, ProviderContainer c) async {
  c.read(routerProvider).go('/inventario');
  await settle(tester);
  await tester.tap(find.byKey(const Key('inventory-estimation-entry')));
  await settle(tester);
}

Future<int> _rows(WidgetTester tester, AppDatabase database) async =>
    (await tester.runAsync(
      () async => (await database.database).query('estimation_copies'),
    ))!.length;

/// Central simulado: referencias, resultados y descarga del perfil FARMER.
MockClient _central({int resultsStatus = 200}) => MockClient((request) async {
  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );
  return switch (request.url.path) {
    '/api/v1/sync/v1/references' => json({
      'contractVersion': 1,
      'campaigns': [
        {
          'campaign_ref': campaignWinter,
          'name': 'Objetivo sintético invierno 2019',
          'status': 'PLANIFICADA',
          'start_date': '2019-09-01',
          'end_date': null,
          'accepts_contributions': false,
        },
      ],
      'products': [],
    }),
    '/api/v1/estimation/results' =>
      resultsStatus == 200
          ? json(farmerResultsJson())
          : json({
              'statusCode': resultsStatus,
              'message': 'POLICY_PENDING',
              'error': 'Conflict',
            }, resultsStatus),
    '/api/v1/estimation/download' => json(farmerDownloadJson()),
    _ => json({'statusCode': 404, 'message': 'x', 'error': 'x'}, 404),
  };
});

List<Override> _online(MockClient client) => [
  apiEndpointConfigProvider.overrideWithValue(
    ApiEndpointConfig(Uri.parse('https://sindicato.example')),
  ),
  authHttpTransportProvider.overrideWithValue(client),
  syncAccessHolderProvider.overrideWithValue(
    SyncAccessHolder()
      ..accept('token-sintetico', memberA.memberId, memberA.tenantId),
  ),
];

void main() {
  sqfliteFfiInit();

  testWidgets(
    'sin conexión y con copia: fechas, período, vigencia al descargar, aviso y ausencias sin cifra',
    (tester) async {
      final seeded = await activatedHousehold(tester, 'est_ui_copia');
      await _saveCopy(tester, seeded.database);
      final transport = OfflineTransport();
      final c = await pumpModeApp(
        tester,
        seeded.database,
        transport: transport,
      );
      await _openEstimation(tester, c);

      expect(
        find.byKey(Key('estimation-copy-$campaignWinter')),
        findsOneWidget,
      );
      final banner = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('estimation-copy-banner')),
          matching: find.byType(Text),
        ),
      );
      expect(banner.data, contains('Descargada el '));
      expect(
        banner.data,
        contains('Vigente al descargar; puede haber cambiado'),
      );
      expect(
        find.textContaining(
          'Período objetivo: Objetivo sintético invierno 2019',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('estimation-figure-copy-Herbicida de ensayo'),
              ),
            )
            .data,
        '111 L (111.000 mL)',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('estimation-figure-copy-Fungicida de ensayo'),
              ),
            )
            .data,
        'Sin cifra',
      );
      expect(
        find.textContaining('Hay menos de tres campañas comparables'),
        findsOneWidget,
      );
      expect(find.text('Vigencia al descargar: Vigente'), findsOneWidget);
      expect(
        find.text('Vigencia actual: desconocida sin conexión'),
        findsNWidgets(2),
      );
      expect(find.textContaining('Generada el '), findsNWidgets(2));
      expect(find.text(estimationReferenceText), findsOneWidget);
      // Abrir la pantalla no consulta al servidor ni toca el inventario.
      expect(transport.requests, 0);
      expect(find.textContaining(' 0 L'), findsNothing);
    },
  );

  testWidgets('sin copia: «sin copia descargada» y ninguna cifra', (
    tester,
  ) async {
    final seeded = await activatedHousehold(tester, 'est_ui_sin');
    final c = await pumpModeApp(
      tester,
      seeded.database,
      transport: OfflineTransport(),
    );
    await _openEstimation(tester, c);
    expect(find.text(estimationNoCopyText), findsOneWidget);
    expect(find.byKey(const Key('estimation-copy-banner')), findsNothing);
    expect(find.textContaining(' L ('), findsNothing);
  });

  testWidgets(
    'con conexión: consulta FARMER, descarga y luego se lee la copia',
    (tester) async {
      final seeded = await activatedHousehold(tester, 'est_ui_online');
      final c = await pumpModeApp(
        tester,
        seeded.database,
        extraOverrides: _online(_central()),
      );
      await _openEstimation(tester, c);
      expect(find.text(estimationNoCopyText), findsOneWidget);

      await tester.tap(find.byKey(const Key('estimation-online')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('estimation-campaign')));
      await settle(tester);
      await tester.tap(find.text('Objetivo sintético invierno 2019').last);
      await settle(tester);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('estimation-figure-online-Herbicida de ensayo'),
              ),
            )
            .data,
        '111 L (111.000 mL)',
      );
      expect(find.text('Vigencia: Vigente'), findsOneWidget);
      // Sin naive ni cobertura en el perfil del Agricultor.
      expect(find.textContaining('naive'), findsNothing);
      expect(find.textContaining('cobertura'), findsNothing);
      expect(await _rows(tester, seeded.database), 0);

      await tester.ensureVisible(find.byKey(const Key('estimation-download')));
      await tester.tap(find.byKey(const Key('estimation-download')));
      await settle(tester);
      expect(find.text('Copia guardada en este teléfono.'), findsOneWidget);
      // La lista de copias se vuelve a leer después de guardar.
      final copyCard = find.byKey(
        Key('estimation-copy-$campaignWinter'),
        skipOffstage: false,
      );
      await waitFor(tester, copyCard);
      expect(copyCard, findsOneWidget);
      expect(await _rows(tester, seeded.database), 1);
    },
  );

  testWidgets(
    'un rechazo de política borra la copia y no la ofrece como alternativa',
    (tester) async {
      final seeded = await activatedHousehold(tester, 'est_ui_politica');
      await _saveCopy(tester, seeded.database);
      final c = await pumpModeApp(
        tester,
        seeded.database,
        extraOverrides: _online(_central(resultsStatus: 409)),
      );
      await _openEstimation(tester, c);
      expect(
        find.byKey(Key('estimation-copy-$campaignWinter')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('estimation-online')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('estimation-campaign')));
      await settle(tester);
      await tester.tap(find.text('Objetivo sintético invierno 2019').last);
      await settle(tester);
      expect(find.byKey(const Key('estimation-blocked')), findsOneWidget);
      expect(find.textContaining('política de divulgación'), findsOneWidget);
      expect(find.byKey(Key('estimation-copy-$campaignWinter')), findsNothing);
      expect(find.textContaining('111 L'), findsNothing);
      expect(await _rows(tester, seeded.database), 0);
    },
  );
}
