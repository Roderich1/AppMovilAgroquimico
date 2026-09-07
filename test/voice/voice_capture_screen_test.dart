import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/ui/voice_capture_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_speech_transcription_port.dart';

/// Pantalla de voz de `EVO-009`.
///
/// Cubre lo que un usuario ve y toca: la entrada desde Operaciones, el
/// indicador de micrófono, la vista previa editable, seguir hablando, descartar,
/// el idioma realmente utilizado, los avisos honestos sobre el modo sin conexión
/// y los casos incómodos —permiso denegado, texto largo, horizontal, fuente al
/// 130 % y teclado abierto—.
void main() {
  sqfliteFfiInit();

  late FakeSpeechTranscriptionPort port;

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<FakeTurn>? script,
    bool repeatLast = true,
    TranscriptionAvailability? availability,
    Size size = const Size(420, 900),
    double textScale = 1,
  }) async {
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: repeatLast);
    if (availability != null) port.availability = availability;

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          speechPortFactoryProvider.overrideWith(
            (ref) =>
                () => port,
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const Scaffold(body: VoiceCaptureScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Deja correr los turnos encadenados sin depender de `pumpAndSettle`, que no
  /// converge mientras la sesión sigue reabriendo el micrófono.
  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    // `ensureVisible` programa el desplazamiento pero NO lo aplica: sin este
    // `pump` el botón sigue fuera de la ventana y el toque cae al vacío.
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    // Un toque que no acierta debe romper la prueba, no avisar por consola: si
    // no, un botón inalcanzable pasaría por «no hizo nada».
    WidgetController.hitTestWarningShouldBeFatal = true;
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  group('entrada desde Operaciones', () {
    /// El dashboard encadena consultas reales y mantiene indicadores animados,
    /// así que `pumpAndSettle` nunca converge y bombear sin tiempo real deja las
    /// consultas sin resolver. Se usa el mismo drenaje que `navigation_test`.
    Future<void> settleApp(WidgetTester tester, {int frames = 20}) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      for (var frame = 0; frame < frames; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('la tarjeta existe, se entiende y abre la pantalla', (
      tester,
    ) async {
      final repo = (await tester.runAsync(() async {
        final database = AppDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        addTearDown(database.close);
        final created = AgroRepository(database);
        await created.addPerson(name: 'José', role: PersonRole.family);
        return created;
      }))!;

      final fake = FakeSpeechTranscriptionPort();
      addTearDown(fake.dispose);

      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            speechPortFactoryProvider.overrideWith(
              (ref) =>
                  () => fake,
            ),
          ],
          child: const AgroApp(),
        ),
      );
      await settleApp(tester);

      await tester.tap(find.text('Operaciones').last);
      await settleApp(tester);

      expect(find.text(voiceEntryTitle), findsOneWidget);

      await tester.tap(find.text(voiceEntryTitle));
      await settleApp(tester);

      expect(find.byKey(const Key('voz-boton-microfono')), findsOneWidget);
      // Atrás debe poder volver: la pantalla se alcanzó apilando.
      expect(find.byTooltip('Volver'), findsOneWidget);
    });
  });

  group('estado del micrófono', () {
    testWidgets('empieza listo y sin indicador de micrófono abierto', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.textContaining('Listo para empezar'), findsOneWidget);
      expect(find.byKey(const Key('voz-indicador-activo')), findsNothing);
    });

    testWidgets('al hablar muestra el indicador visible de micrófono', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [
          const FakeTurn(partials: ['hola'], endsOnStop: true),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));

      expect(find.byKey(const Key('voz-indicador-activo')), findsOneWidget);
      expect(find.textContaining('Escuchando'), findsWidgets);
      expect(port.microphoneOpen, isTrue);
    });

    testWidgets('el parcial se muestra aparte del texto de sesión', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [
          const FakeTurn(partials: ['cincuenta litros'], endsOnStop: true),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));

      expect(find.byKey(const Key('voz-parcial')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('voz-parcial')),
          matching: find.text('cincuenta litros'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('detener cierra el turno y deja el texto en el campo', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [const FakeTurn(segment: 'cincuenta litros', endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voz-campo-editable')))
            .controller
            ?.text,
        'cincuenta litros',
      );
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('vista previa y edición', () {
    testWidgets('el texto dictado se puede corregir a mano', (tester) async {
      await pumpScreen(
        tester,
        script: [const FakeTurn(segment: 'sinco litros', endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));

      await tester.enterText(
        find.byKey(const Key('voz-campo-editable')),
        'cinco litros',
      );
      await settle(tester);

      expect(find.textContaining('editado a mano'), findsOneWidget);
    });

    testWidgets('seguir hablando añade al final sin borrar la corrección', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(segment: 'sinco litros', endsOnStop: true),
          FakeTurn(segment: 'de bellator', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));

      await tester.enterText(
        find.byKey(const Key('voz-campo-editable')),
        'cinco litros',
      );
      await settle(tester);

      await tap(tester, const Key('voz-seguir'));
      await tap(tester, const Key('voz-detener'));

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voz-campo-editable')))
            .controller
            ?.text,
        'cinco litros de bellator',
      );
    });

    testWidgets('usar este texto entrega y avisa que no registró nada', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [const FakeTurn(segment: 'cincuenta litros', endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));
      await tap(tester, const Key('voz-usar'));

      expect(find.byKey(const Key('voz-entregado')), findsOneWidget);
      expect(
        find.textContaining('No se registró ninguna compra'),
        findsWidgets,
      );
    });

    testWidgets('usar este texto está deshabilitado sin texto', (tester) async {
      await pumpScreen(tester);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('voz-usar')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('descartar vacía el campo y deja la sesión limpia', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [const FakeTurn(segment: 'algo dictado', endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));
      await tap(tester, const Key('voz-descartar'));

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voz-campo-editable')))
            .controller
            ?.text,
        isEmpty,
      );
      expect(find.textContaining('Sesión descartada'), findsOneWidget);
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('idioma y modo sin conexión', () {
    testWidgets('muestra siempre el idioma pedido y el utilizado', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(acceptsLocale: 'es-PE', segment: 'ok', endsOnStop: true),
        ],
      );
      expect(find.textContaining('Idioma solicitado: es-US'), findsOneWidget);
      expect(
        find.textContaining('Idioma utilizado: todavía no se sabe'),
        findsOneWidget,
      );

      await tap(tester, const Key('voz-boton-microfono'));

      expect(find.textContaining('Idioma utilizado: es-PE'), findsOneWidget);
      expect(find.textContaining('no tiene es-US'), findsOneWidget);
    });

    testWidgets('no promete funcionar sin conexión sin haberlo comprobado', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(
        find.textContaining('Todavía no se ha comprobado que funcione sin'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Modo avión: no se pudo comprobar'),
        findsOneWidget,
      );
    });

    testWidgets('dice que no puede consultar los idiomas instalados', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        availability: const TranscriptionAvailability(
          recognizerAvailable: true,
          onDeviceApiReports: false,
          localeSupportKnown: false,
        ),
      );
      await tap(tester, const Key('voz-boton-microfono'));

      expect(
        find.textContaining('no permite consultar qué idiomas'),
        findsOneWidget,
      );
    });

    testWidgets('sólo afirma el modo sin conexión tras comprobarlo', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [const FakeTurn(segment: 'dictado', endsOnStop: true)],
        availability: const TranscriptionAvailability(
          recognizerAvailable: true,
          onDeviceApiReports: false,
          airplaneMode: AirplaneMode.on,
        ),
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));

      expect(
        find.textContaining('se transcribió con el modo avión activado'),
        findsOneWidget,
      );
    });
  });

  group('errores accionables', () {
    testWidgets('permiso denegado explica la salida y deja escribir', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(failWith: TranscriptionErrorCode.permissionDenied),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));

      expect(find.byKey(const Key('voz-error')), findsOneWidget);
      expect(find.textContaining('Sin permiso de micrófono'), findsOneWidget);

      // El ingreso manual sigue disponible: la aplicación no queda bloqueada.
      await tester.enterText(
        find.byKey(const Key('voz-campo-editable')),
        'lo escribo a mano',
      );
      await settle(tester);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('voz-usar')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('denegación permanente ofrece abrir los ajustes', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            failWith: TranscriptionErrorCode.permissionPermanentlyDenied,
          ),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));

      expect(find.byKey(const Key('voz-abrir-ajustes')), findsOneWidget);
      await tap(tester, const Key('voz-abrir-ajustes'));
      expect(port.openSettingsCalls, 1);
    });

    testWidgets('sin reconocedor no bloquea la pantalla', (tester) async {
      await pumpScreen(
        tester,
        availability: const TranscriptionAvailability.none(
          detail: 'isRecognitionAvailable=false',
        ),
      );
      await tap(tester, const Key('voz-boton-microfono'));

      expect(
        find.textContaining('no ofrece reconocimiento de voz'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('voz-campo-editable')), findsOneWidget);
    });

    testWidgets('sin español disponible lo dice y no descarga nada', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(failWith: TranscriptionErrorCode.localeUnavailable),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await settle(tester, frames: 30);

      // Agotado el español del reconocedor local, la pantalla lo dice y ofrece
      // el servicio del sistema (`DEFECTO-004`). Lo que no hace, en ningún
      // camino, es descargar un modelo por su cuenta.
      expect(find.textContaining('no tiene ningún español'), findsOneWidget);
      expect(find.byKey(const Key('voz-fallback-motor')), findsOneWidget);
      expect(
        find.textContaining('no descarga nada por su cuenta'),
        findsOneWidget,
      );
    });

    testWidgets('DEFECTO-002: no afirma escuchar en un idioma que falló', (
      tester,
    ) async {
      // El HONOR JDY-LX3P anunció «listo para escuchar» en es-MX y a
      // continuación devolvió el error 12. La pantalla llegó a decir «Sin
      // español disponible» y «Se está escuchando en es-MX» a la vez.
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            failWith: TranscriptionErrorCode.localeUnavailable,
            failDetail: 'android-error-12',
            announcesLocaleBeforeFailing: true,
          ),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await settle(tester, frames: 40);

      expect(find.textContaining('no tiene ningún español'), findsOneWidget);
      expect(
        find.textContaining('Se está escuchando en'),
        findsNothing,
        reason: 'ninguno funcionó: no puede afirmar que escucha en uno',
      );
      expect(
        find.textContaining('Idioma utilizado: todavía no se sabe'),
        findsOneWidget,
      );
    });

    testWidgets('OBSERVACIÓN-003: enseña por dónde va el recorrido', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            failWith: TranscriptionErrorCode.localeUnavailable,
            announcesLocaleBeforeFailing: true,
            delay: Duration(milliseconds: 80),
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('voz-boton-microfono')));
      await settle(tester, frames: 8);

      expect(find.byKey(const Key('voz-buscando-idioma')), findsOneWidget);
      await settle(tester, frames: 120);
    });

    testWidgets('el diagnóstico muestra código, no la frase dictada', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            failWith: TranscriptionErrorCode.clientError,
            failDetail: 'android-error-5',
          ),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      // El backoff acotado espera 400 ms y 800 ms antes del tercer turno.
      await settle(tester, frames: 150);

      expect(find.textContaining('Código: clientError'), findsOneWidget);
    });
  });

  group('accesibilidad y diseño', () {
    testWidgets('no desborda con la fuente al 130 %', (tester) async {
      await pumpScreen(tester, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('voz-boton-microfono')), findsOneWidget);
    });

    testWidgets('no desborda en horizontal', (tester) async {
      await pumpScreen(tester, size: const Size(900, 420));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('voz-campo-editable')), findsOneWidget);
    });

    testWidgets('no desborda en horizontal con la fuente al 130 %', (
      tester,
    ) async {
      await pumpScreen(tester, size: const Size(900, 420), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un texto muy largo se puede desplazar sin romper nada', (
      tester,
    ) async {
      final long = List.filled(60, 'cincuenta litros de producto').join(' ');
      await pumpScreen(
        tester,
        script: [FakeTurn(segment: long, endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-detener'));

      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el aviso de privacidad se puede desplazar', (tester) async {
      await pumpScreen(tester, size: const Size(420, 560));
      expect(find.textContaining('Antes de empezar'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el teclado abierto el contenido sigue accesible', (
      tester,
    ) async {
      port = FakeSpeechTranscriptionPort();
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            speechPortFactoryProvider.overrideWith(
              (ref) =>
                  () => port,
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              // Teclado ocupando la mitad inferior.
              data: const MediaQueryData(
                viewInsets: EdgeInsets.only(bottom: 380),
              ),
              child: const Scaffold(body: VoiceCaptureScreen()),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('voz-usar')));
      expect(find.byKey(const Key('voz-usar')), findsOneWidget);
    });

    testWidgets('durante una transición no hay doble acción posible', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: [const FakeTurn(segment: 'x', endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));

      // Con el micrófono abierto, `Seguir hablando` no puede abrir otro turno.
      final seguir = tester.widget<FilledButton>(
        find.byKey(const Key('voz-seguir')),
      );
      expect(seguir.onPressed, isNull);
      expect(port.startRequests, hasLength(1));
    });
  });

  group('salir de la pantalla', () {
    testWidgets('navegar atrás libera el micrófono', (tester) async {
      await pumpScreen(
        tester,
        script: [
          const FakeTurn(partials: ['hola'], endsOnStop: true),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      expect(port.microphoneOpen, isTrue);

      // Se sustituye el árbol: equivale a abandonar la pantalla.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await settle(tester);

      expect(port.microphoneReleased, isTrue);
      expect(port.calls, contains('cancel'));
    });
  });

  group('DEFECTO-004: elegir el reconocedor del sistema', () {
    /// El HONOR: el reconocedor on-device existe pero no tiene ningún español.
    const honor = FakeTurn(
      acceptsRoute: TranscriptionEngineRoute.systemDefault,
      failDetail: 'android-error-12',
      segment: 'cincuenta litros de bellator',
      endsOnStop: true,
    );

    testWidgets('el proveedor utilizado se ve desde el primer turno', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(acceptsLocale: 'es-US', segment: 'ok', endsOnStop: true),
        ],
      );
      expect(
        find.textContaining('Reconocedor: todavía no se sabe'),
        findsOneWidget,
      );

      await tap(tester, const Key('voz-boton-microfono'));

      expect(
        find.textContaining('Reconocedor: reconocimiento local del teléfono'),
        findsOneWidget,
      );
    });

    testWidgets('agotado el español local, se pregunta antes de cambiar', (
      tester,
    ) async {
      await pumpScreen(tester, script: const [honor]);
      await tap(tester, const Key('voz-boton-microfono'));
      await settle(tester, frames: 40);

      expect(find.byKey(const Key('voz-fallback-motor')), findsOneWidget);
      // Lo que el propietario tiene que poder decidir con conocimiento.
      expect(find.textContaining('no tiene ningún español'), findsWidgets);
      expect(
        find.textContaining('servicio de reconocimiento del teléfono'),
        findsOneWidget,
      );
      expect(find.textContaining('sin conexión'), findsWidgets);
      expect(find.textContaining('podría usar Internet'), findsOneWidget);
      expect(
        find.byKey(const Key('voz-usar-servicio-sistema')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('voz-continuar-escribiendo')),
        findsOneWidget,
      );
    });

    testWidgets('aceptar identifica el camino como servicio del sistema', (
      tester,
    ) async {
      await pumpScreen(tester, script: const [honor]);
      await tap(tester, const Key('voz-boton-microfono'));
      await settle(tester, frames: 40);

      await tap(tester, const Key('voz-usar-servicio-sistema'));
      await settle(tester, frames: 20);

      expect(
        find.textContaining(
          'Reconocedor: Servicio del sistema — preferencia sin conexión',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('voz-fallback-motor')), findsNothing);
      expect(
        find.textContaining('se transcribió con el modo avión'),
        findsNothing,
        reason: 'pedir sin conexión no es haberlo comprobado',
      );
    });

    testWidgets('rechazar deja escribir y no vuelve a preguntar', (
      tester,
    ) async {
      await pumpScreen(tester, script: const [honor]);
      await tap(tester, const Key('voz-boton-microfono'));
      await settle(tester, frames: 40);

      await tap(tester, const Key('voz-continuar-escribiendo'));

      expect(find.byKey(const Key('voz-fallback-motor')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('voz-campo-editable')),
        'diez litros de bellator',
      );
      await tester.pump();
      expect(find.text('diez litros de bellator'), findsOneWidget);
    });

    testWidgets('un permiso denegado no ofrece cambiar de reconocedor', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(failWith: TranscriptionErrorCode.permissionDenied),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await settle(tester, frames: 20);

      expect(find.byKey(const Key('voz-fallback-motor')), findsNothing);
    });
  });
}
