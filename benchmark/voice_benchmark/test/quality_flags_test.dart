import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/bench_controller.dart';
import 'package:voice_benchmark/bench/bench_export.dart';
import 'package:voice_benchmark/bench/corpus_catalog.dart';
import 'package:voice_benchmark/port/fake_transcription_port.dart';
import 'package:voice_benchmark/port/platform_transcription_port.dart';
import 'package:voice_benchmark/port/speech_transcription_port.dart';

/// Las marcas de sospecha tienen que llegar hasta el archivo exportado.
///
/// ## Lo que se vio en el emulador de 16 KB
///
/// C3, con `ggml-small-q5_1`, sobre 5177 ms de silencio devolvió `[MÚSICA]` y
/// la pantalla lo mostró como resultado final, sin una sola advertencia. Es
/// `RISK-026` otra vez, el defecto por el que `ADR-002` eligió Android sobre
/// Whisper, y el modelo `small` **no lo arregla**.
///
/// El motor sí lo había detectado: `WhisperSession` marcó
/// `possibleHallucination` y `SpeechBridge` mandó el aviso por el canal. Lo que
/// faltaba estaba en Dart, que no leía ese evento. La marca existía, se
/// probaba, y se perdía en el último tramo.
///
/// Importa porque el guardrail binario de la matriz de aceptación —«cero texto
/// aceptado sobre no-habla»— se cuenta sobre el archivo exportado. Sin la
/// marca, `[MÚSICA]` entra ahí como una transcripción cualquiera y el guardrail
/// da por bueno justo lo que existe para impedir.
void main() {
  Future<Uint8List> readAsset(String path) async =>
      File(path).readAsBytesSync();

  group('el puerto de plataforma lee el aviso del motor', () {
    late List<TranscriptionEvent> events;
    late PlatformSpeechTranscriptionPort port;
    late void Function(Object payload) emitNative;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      final controller = StreamController<Object?>.broadcast();
      emitNative = controller.add;

      port = PlatformSpeechTranscriptionPort(
        method: const MethodChannel('prueba/metodo'),
        event: _FakeEventChannel(controller.stream),
      );
      events = <TranscriptionEvent>[];
      port.events.listen(events.add);
      addTearDown(controller.close);
    });

    test('un aviso con marcas produce un evento de calidad', () async {
      emitNative(<Object?, Object?>{
        'type': 'hybrid',
        'source': 'whisper',
        'whisperText': '[MÚSICA]',
        'flags': <String>['possibleHallucination'],
        'whisperElapsedMs': 15166,
        'audioMs': 5177,
        'realTimeFactor': 2.93,
      });
      await Future<void>.delayed(Duration.zero);

      final quality = events.whereType<TranscriptionQuality>().single;
      expect(quality.flags, ['possibleHallucination']);
      expect(quality.source, 'whisper');
      expect(quality.audioMs, 5177);
    });

    test('un aviso sin marcas no inventa ninguna', () async {
      emitNative(<Object?, Object?>{
        'type': 'hybrid',
        'source': 'whisper',
        'flags': <String>[],
      });
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<TranscriptionQuality>().single.flags, isEmpty);
    });

    test('el aviso no se confunde con un resultado final', () async {
      emitNative(<Object?, Object?>{
        'type': 'hybrid',
        'whisperText': '[MÚSICA]',
        'flags': <String>['possibleHallucination'],
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        events.whereType<TranscriptionFinal>(),
        isEmpty,
        reason: 'el texto lo entrega el evento final, no el aviso',
      );
    });
  });

  group('el banco registra la marca y la exporta', () {
    late FakeSpeechTranscriptionPort port;
    late BenchController c;

    setUp(() async {
      port = FakeSpeechTranscriptionPort(engineId: 'whisper-small-q5_1');
      c = BenchController(
        port: port,
        loader: CorpusLoader(readAsset),
        appVersion: 'test',
        benchCommit: 'prueba',
      );
      addTearDown(c.dispose);
      await c.selectCorpus(CorpusCatalog.hibridoAG);
    });

    test('sin marcas la lista queda vacía, no nula', () async {
      await c.record();
      expect(c.results.single.qualityFlags, isEmpty);
    });

    test('la marca del motor llega al resultado guardado', () async {
      port.emitQualityForTest(const ['possibleHallucination']);
      await Future<void>.delayed(Duration.zero);
      await c.record();

      expect(c.results.single.qualityFlags, ['possibleHallucination']);
    });

    test('la marca no se arrastra a la frase siguiente', () async {
      // Sería el peor de los dos errores: marcar como sospechosa una frase que
      // el motor transcribió bien, y dejar de creer en el aviso.
      port.emitQualityForTest(const ['possibleHallucination']);
      await Future<void>.delayed(Duration.zero);
      await c.record();
      c.next();
      await c.record();

      expect(c.results.first.qualityFlags, ['possibleHallucination']);
      expect(c.results.last.qualityFlags, isEmpty);
    });

    test('el JSON exportado lleva la marca junto al texto', () async {
      port.emitQualityForTest(const ['possibleHallucination']);
      await Future<void>.delayed(Duration.zero);
      await c.record();

      final json = jsonDecode(
        BenchExport.toJsonString(c.buildRun()),
      ) as Map<String, Object?>;
      final row = (json['results']! as List).single as Map<String, Object?>;
      expect(row['qualityFlags'], ['possibleHallucination']);
    });

    test('el CSV tiene su columna y el agregador la espera', () async {
      port.emitQualityForTest(const ['degenerateRepetition']);
      await Future<void>.delayed(Duration.zero);
      await c.record();

      expect(BenchExportColumns.csv, contains('qualityFlags'));
      expect(BenchExport.toCsv(c.buildRun()), contains('degenerateRepetition'));
    });

    test('quitar las transcripciones no quita las marcas', () async {
      // El texto puede llevar datos reales; la marca es un código y no.
      // Además, sin ella la fila redactada parecería una transcripción sana.
      port.emitQualityForTest(const ['possibleHallucination']);
      await Future<void>.delayed(Duration.zero);
      await c.record();
      c.setIncludeTranscripts(false);

      final row = c.buildRun().results.single;
      expect(row.obtainedText, isNull);
      expect(row.qualityFlags, ['possibleHallucination']);
    });

    test('la pantalla puede saber que hay que revisar', () async {
      expect(c.qualityFlags, isEmpty);
      port.emitQualityForTest(const ['possibleHallucination']);
      await Future<void>.delayed(Duration.zero);

      expect(c.qualityFlags, ['possibleHallucination']);
    });
  });
}

/// Canal de eventos de mentira: entrega lo que le pasemos, sin plataforma.
final class _FakeEventChannel extends EventChannel {
  _FakeEventChannel(this._stream) : super('prueba/eventos');

  final Stream<Object?> _stream;

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) => _stream;
}
