import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/bench_controller.dart';
import 'package:voice_benchmark/bench/bench_export.dart';
import 'package:voice_benchmark/bench/corpus.dart';
import 'package:voice_benchmark/port/fake_transcription_port.dart';
import 'package:voice_benchmark/port/speech_transcription_port.dart';

Corpus loadCorpus() =>
    Corpus.fromJsonString(File('assets/corpus.json').readAsStringSync());

void main() {
  late FakeSpeechTranscriptionPort port;
  late BenchController controller;

  setUp(() {
    port = FakeSpeechTranscriptionPort();
    controller = BenchController(
      port: port,
      corpus: loadCorpus(),
      appVersion: 'test',
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

  group('recorrido del corpus', () {
    test('empieza en la primera frase de ajuste', () {
      expect(controller.split, 'ajuste');
      expect(controller.position, 1);
      expect(controller.current!.id, 'AJ-001');
    });

    test('cambiar de corpus vuelve al principio del otro', () {
      controller.next();
      controller.setSplit('aceptacion');

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
      expect(result.engine, 'fake');
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
      final ownPort = FakeSpeechTranscriptionPort();
      final own = BenchController(
        port: ownPort,
        corpus: loadCorpus(),
        appVersion: 'test',
      );
      await own.start();
      own.dispose();
      await settle();

      expect(ownPort.calls, contains('dispose'));
      expect(ownPort.state, TranscriptionState.idle);
    });
  });
}
