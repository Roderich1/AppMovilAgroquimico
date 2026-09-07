import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/bench_controller.dart';
import 'package:voice_benchmark/bench/bench_export.dart';
import 'package:voice_benchmark/bench/corpus_catalog.dart';
import 'package:voice_benchmark/port/fake_transcription_port.dart';
import 'package:voice_benchmark/port/speech_transcription_port.dart';

Future<Uint8List> readAsset(String path) async => File(path).readAsBytesSync();

/// El banco arranca sin corpus a propósito, así que cada controlador de prueba
/// elige uno explícitamente. Se usa el de la Fase 0 porque estas pruebas miran
/// el recorrido y la exportación, no el contenido del corpus.
Future<BenchController> phase0Controller(
  FakeSpeechTranscriptionPort port, {
  DeviceInfo deviceInfo = DeviceInfo.unknown,
  Future<bool?> Function()? airplaneProbe,
}) async {
  final controller = BenchController(
    port: port,
    loader: const CorpusLoader(readAsset),
    appVersion: 'test',
    benchCommit: 'prueba',
    deviceInfo: deviceInfo,
    airplaneProbe: airplaneProbe,
  );
  await controller.selectCorpus(CorpusCatalog.fase0);
  return controller;
}

void main() {
  late FakeSpeechTranscriptionPort port;
  late BenchController controller;

  setUp(() async {
    // El motor que dice ser el fake tiene que estar en el registro de
    // candidatos: el banco no deja grabar con uno sin identificar, y estas
    // pruebas sí graban.
    port = FakeSpeechTranscriptionPort(engineId: 'vosk-small-es-0.42');
    controller = await phase0Controller(
      port,
      deviceInfo: const DeviceInfo(
        device: 'Equipo de prueba',
        androidRelease: '16',
        androidSdk: 36,
        abi: 'arm64-v8a',
      ),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('modo avión declarado frente al del sistema', () {
    Future<BenchController> withProbe(bool? system) =>
        phase0Controller(port, airplaneProbe: () async => system);

    test('avisa cuando se declara modo avión y la radio sigue viva', () async {
      // Es el caso que se dio en el POCO X5 Pro: el interruptor decia offline y
      // el Wi-Fi estuvo encendido toda la tanda. Sin este contraste, 43 tomas
      // con red habrian sostenido un "funciona sin Internet" falso en ADR-002.
      final c = await withProbe(false);
      await c.setAirplaneMode(true);

      expect(c.airplaneModeMismatch, isTrue);
      c.dispose();
    });

    test('sin discrepancia cuando ambos coinciden', () async {
      final c = await withProbe(true);
      await c.setAirplaneMode(true);

      expect(c.airplaneModeMismatch, isFalse);
      c.dispose();
    });

    test('sin lectura del sistema no se inventa una discrepancia', () async {
      final c = await withProbe(null);
      await c.setAirplaneMode(true);

      expect(c.systemAirplaneMode, isNull);
      expect(c.airplaneModeMismatch, isFalse);
      c.dispose();
    });

    test(
      'la medición guarda lo que dijo el sistema, no lo declarado',
      () async {
        final c = await withProbe(false);
        await c.setAirplaneMode(true);
        await c.start();
        await c.stop();
        await settle();
        await c.record();

        final result = c.results.single;
        expect(result.airplaneMode, isTrue);
        expect(result.systemAirplaneMode, isFalse);
        expect(result.airplaneModeMismatch, isTrue);
        expect(BenchExport.toCsv(c.buildRun()), contains('systemAirplaneMode'));
        c.dispose();
      },
    );
  });

  group('recorrido del corpus', () {
    test('empieza en la primera frase de ajuste', () {
      expect(controller.partition, BenchPartition.ajuste);
      expect(controller.position, 1);
      expect(controller.current!.id, 'AJ-001');
    });

    test('cambiar de corpus vuelve al principio del otro', () {
      controller.next();
      controller.setPartition(BenchPartition.aceptacion);

      expect(controller.position, 1);
      expect(controller.current!.split, 'aceptacion');
    });

    test('no se pasa del final ni del principio', () {
      controller.jumpTo(999);
      final last = controller.position;
      controller.next();
      expect(controller.position, last);

      controller.jumpTo(-5);
      controller.previous();
      expect(controller.position, 1);
    });
  });

  group('medición', () {
    test('guarda latencias, motor, dispositivo y modo avión', () async {
      controller.setAirplaneMode(true);
      await controller.refreshAvailability();
      await controller.start();
      await settle();
      await controller.stop();
      await settle();
      await controller.record(notes: 'sin ruido');

      final result = controller.results.single;
      expect(result.sampleId, 'AJ-001');
      expect(result.engine, 'vosk-small-es-0.42');
      expect(result.candidateId, 'C1');
      expect(result.corpusId, 'fase0');
      expect(result.corpusDigest, hasLength(64));
      expect(result.device, 'Equipo de prueba');
      expect(result.androidSdk, 36);
      expect(result.airplaneMode, isTrue);
      expect(result.notes, 'sin ruido');
      expect(result.obtainedText, 'registrar compra de cincuenta litros');
      expect(result.partialLatencyMs, isNotNull);
      expect(result.finalLatencyMs, isNotNull);
      expect(result.audioDurationMs, isNotNull);
    });

    test('la latencia final se cuenta desde que terminó el habla', () async {
      await controller.start();
      await settle();
      await controller.stop();
      await settle();

      // El fake responde de inmediato al detener: el trabajo del motor es
      // practicamente cero, aunque la sesion haya durado mas.
      expect(controller.finalLatencyMs, lessThanOrEqualTo(50));
      expect(controller.audioDurationMs, isNotNull);
    });

    test(
      'sin sonda de memoria la métrica queda sin medir, no en cero',
      () async {
        await controller.start();
        await controller.stop();
        await settle();
        await controller.record();

        expect(controller.results.single.memoryBytes, isNull);
      },
    );

    test('un fallo se guarda con su código y sin texto', () async {
      port.scenario = FakeScenario.permissionDenied;
      await controller.start();
      await settle();
      await controller.record();

      final result = controller.results.single;
      expect(result.errorCode, 'permissionDenied');
      expect(result.obtainedText, isNull);
      expect(result.succeeded, isFalse);
    });

    test(
      'repetir una frase conserva la toma anterior y numera el intento',
      () async {
        await controller.start();
        await controller.stop();
        await settle();
        await controller.record();

        controller.repeat();
        await controller.start();
        await controller.stop();
        await settle();
        await controller.record();

        expect(controller.results.map((r) => r.attempt), [1, 2]);
        expect(controller.results.map((r) => r.sampleId), ['AJ-001', 'AJ-001']);
      },
    );

    test('las frases medidas se cuentan una sola vez', () async {
      await controller.start();
      await controller.stop();
      await settle();
      await controller.record();
      await controller.record();

      expect(controller.results, hasLength(2));
      expect(controller.measured, 1);
    });
  });

  group('exportación', () {
    Future<void> measureOne() async {
      await controller.start();
      await controller.stop();
      await settle();
      await controller.record();
    }

    test('el JSON lleva identidad del equipo, corpus y resultados', () async {
      await measureOne();
      final json = jsonDecode(
        BenchExport.toJsonString(controller.buildRun()),
      ) as Map<String, Object?>;

      expect(json['schema'], 'evolution-3-voice-benchmark');
      expect(json['device'], 'Equipo de prueba');
      expect(json['abi'], 'arm64-v8a');
      expect(json['corpusVersion'], isNotEmpty);
      expect((json['results']! as List), hasLength(1));
    });

    test('al excluir transcripciones el texto no sale del teléfono', () async {
      await measureOne();
      controller.setIncludeTranscripts(false);
      final run = controller.buildRun();

      expect(run.results.single.obtainedText, isNull);
      expect(run.results.single.transcriptRedacted, isTrue);
      expect(
        BenchExport.toJsonString(run),
        isNot(contains('cincuenta litros')),
      );
    });

    test('el CSV conserva la cabecera acordada con el agregador', () async {
      await measureOne();
      final csv = BenchExport.toCsv(controller.buildRun());

      expect(csv.split('\n').first, BenchExport.csvHeader.join(','));
    });

    test('borrar mediciones vacía la tanda', () async {
      await measureOne();
      controller.clearResults();

      expect(controller.results, isEmpty);
      expect(controller.buildRun().results, isEmpty);
    });
  });

  group('aislamiento del negocio', () {
    test('medir no toca nada fuera de memoria', () async {
      await controller.start();
      await controller.stop();
      await settle();
      await controller.record();

      // El fake registra cada llamada que el controlador hace al motor. Si algún
      // día apareciera una llamada de dominio, tendría que pasar por aquí.
      expect(
        port.calls.toSet(),
        everyElement(
          isIn(<String>{'availability', 'start', 'stop', 'cancel', 'dispose'}),
        ),
      );
    });

    test('dispose del controlador libera el micrófono', () async {
      // Controlador propio: este caso lo libera él mismo y el `tearDown` no debe
      // volver a liberar el compartido.
      final ownPort = FakeSpeechTranscriptionPort(
        engineId: 'vosk-small-es-0.42',
      );
      final own = await phase0Controller(ownPort);
      await own.start();
      own.dispose();
      await settle();

      expect(ownPort.calls, contains('dispose'));
      expect(ownPort.state, TranscriptionState.idle);
    });
  });
}
