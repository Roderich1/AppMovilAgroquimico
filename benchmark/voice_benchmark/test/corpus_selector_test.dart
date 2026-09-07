import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/bench_controller.dart';
import 'package:voice_benchmark/bench/bench_export.dart';
import 'package:voice_benchmark/bench/candidates.dart';
import 'package:voice_benchmark/bench/corpus_catalog.dart';
import 'package:voice_benchmark/bench/sha256.dart';
import 'package:voice_benchmark/port/fake_transcription_port.dart';

/// Selector de corpus del banco híbrido.
///
/// ## Por qué existe este archivo
///
/// C1 se midió entero con el corpus de la Fase 0 mientras la pantalla decía
/// «Corpus: aceptación». Ese menú nunca eligió un corpus: elegía la partición,
/// y el archivo estaba fijado en `main.dart`. Nada falló, nada avisó, y los
/// números salieron con aspecto de comparables.
///
/// Un banco que puede medir el corpus equivocado sin decirlo no produce
/// mediciones: produce cifras. Por eso todo lo que sigue se comprueba antes de
/// dejar grabar, y por eso la pantalla no puede nombrar un corpus que no sea el
/// que se cargó y verificó byte a byte.
void main() {
  // ------------------------------------------------------------- utilidades

  /// Lector de assets de mentira: se le dice exactamente qué bytes tiene cada
  /// ruta. Un archivo ausente es una ruta que no está en el mapa.
  AssetBytesReader readerFor(Map<String, List<int>> files) => (path) async {
    final bytes = files[path];
    if (bytes == null) {
      throw FileSystemException('no existe en el paquete', path);
    }
    return Uint8List.fromList(bytes);
  };

  /// Lee los assets de verdad del banco.
  Future<Uint8List> realReader(String path) async =>
      File(path).readAsBytesSync();

  /// Un corpus mínimo válido, para poder romperlo de una cosa a la vez.
  Map<String, Object?> corpusBase() => <String, Object?>{
    'schemaVersion': 2,
    'corpusVersion': 'prueba-1.0.0',
    'locale': 'es-BO',
    'samples': <Object?>[
      {
        'id': 'PA-001',
        'split': 'ajuste',
        'intent': 'compra',
        'category': 'A',
        'text': 'Registrar compra de Bellator.',
        'expected': 'listo',
        'slots': {'producto': 'Bellator'},
        'conditions': <String>[],
        'tags': <String>[],
      },
      {
        'id': 'PC-001',
        'split': 'aceptacion',
        'intent': 'pago',
        'category': 'D',
        'text': 'Pago de doscientos bolivianos a Rosa.',
        'expected': 'listo',
        'slots': {'monto': '200'},
        'conditions': <String>[],
        'tags': <String>[],
      },
      {
        'id': 'PG-001',
        'split': 'aceptacion',
        'intent': 'fuera_de_alcance',
        'category': 'G',
        'text': '',
        'expected': 'rechazado',
        'slots': <String, Object?>{},
        'conditions': <String>['silencio_3s'],
        'tags': <String>[],
      },
    ],
  };

  /// Empaqueta un JSON y un descriptor cuyo digest **sí** coincide, para poder
  /// probar los defectos estructurales sin que el digest los tape antes.
  ({CorpusDescriptor descriptor, AssetBytesReader reader}) pack(
    Map<String, Object?> json, {
    String path = 'assets/prueba.json',
    String id = 'prueba',
    String? version,
  }) {
    final bytes = utf8.encode(const JsonEncoder().convert(json));
    return (
      descriptor: CorpusDescriptor(
        id: id,
        label: 'Corpus de prueba',
        assetPath: path,
        expectedVersion: version ?? json['corpusVersion']! as String,
        expectedDigest: sha256Hex(bytes),
      ),
      reader: readerFor({path: bytes}),
    );
  }

  Future<CorpusLoadFailure> failureOf(
    CorpusLoader loader,
    CorpusDescriptor descriptor,
  ) async {
    try {
      await loader.load(descriptor);
    } on CorpusLoadFailure catch (e) {
      return e;
    }
    fail('se esperaba que la carga fuera rechazada, y fue aceptada');
  }

  // ------------------------------------------------------- carga de Fase 0

  group('carga del corpus de la Fase 0', () {
    test('carga entero y con su identidad verificada', () async {
      final loaded = await CorpusLoader(realReader).load(CorpusCatalog.fase0);

      expect(loaded.descriptor.id, 'fase0');
      expect(loaded.version, '1.0.0');
      expect(
        loaded.digest,
        '7a891fd1a6aa2d9c4f122cc79a9f7fac646ce52f634bc51dcc59a7c9683f6b6b',
      );
      expect(loaded.corpus.samples, hasLength(100));
    });

    test('sus particiones son 40 de ajuste y 60 de aceptación', () async {
      final loaded = await CorpusLoader(realReader).load(CorpusCatalog.fase0);

      expect(loaded.samplesOf(BenchPartition.ajuste), hasLength(40));
      expect(loaded.samplesOf(BenchPartition.aceptacion), hasLength(60));
    });

    test('no tiene partición sin habla, y eso se dice en vez de dar cero', () async {
      // La Fase 0 se escribió antes de que existiera la categoría G. Ofrecer la
      // partición vacía y dejar «grabar» produciría una tanda de cero muestras
      // que después aparecería como «sin falsas afirmaciones».
      final loaded = await CorpusLoader(realReader).load(CorpusCatalog.fase0);

      expect(loaded.samplesOf(BenchPartition.sinHabla), isEmpty);
      expect(loaded.hasPartition(BenchPartition.sinHabla), isFalse);
    });
  });

  // ------------------------------------------------------- carga del A–G

  group('carga del corpus híbrido A–G', () {
    test('carga entero y con su identidad verificada', () async {
      final loaded = await CorpusLoader(realReader)
          .load(CorpusCatalog.hibridoAG);

      expect(loaded.descriptor.id, 'hibrido-ag');
      expect(loaded.version, 'hybrid-1.0.0');
      expect(
        loaded.digest,
        '52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0',
      );
      expect(loaded.corpus.samples, hasLength(54));
    });

    test('están las siete categorías del plan', () async {
      final loaded = await CorpusLoader(realReader)
          .load(CorpusCatalog.hibridoAG);

      for (final categoria in const ['A', 'B', 'C', 'D', 'E', 'F', 'G']) {
        expect(loaded.corpus.byCategory(categoria), isNotEmpty);
      }
    });
  });

  // ----------------------------------------------------- las particiones

  group('selección de partición', () {
    late LoadedCorpus hibrido;

    setUp(() async {
      hibrido = await CorpusLoader(realReader).load(CorpusCatalog.hibridoAG);
    });

    test('las tres particiones son disjuntas y suman el corpus entero', () {
      final ajuste = hibrido
          .samplesOf(BenchPartition.ajuste)
          .map((s) => s.id)
          .toSet();
      final aceptacion = hibrido
          .samplesOf(BenchPartition.aceptacion)
          .map((s) => s.id)
          .toSet();
      final sinHabla = hibrido
          .samplesOf(BenchPartition.sinHabla)
          .map((s) => s.id)
          .toSet();

      expect(ajuste.intersection(aceptacion), isEmpty);
      expect(ajuste.intersection(sinHabla), isEmpty);
      expect(aceptacion.intersection(sinHabla), isEmpty);
      expect(
        ajuste.length + aceptacion.length + sinHabla.length,
        hibrido.corpus.samples.length,
        reason: 'ninguna frase puede quedarse fuera ni medirse dos veces',
      );
    });

    test('sin habla junta las de los dos conjuntos, y sólo ésas', () {
      final sinHabla = hibrido.samplesOf(BenchPartition.sinHabla);

      expect(sinHabla, hasLength(8));
      expect(sinHabla.every((s) => s.isNonSpeech), isTrue);
      expect(
        sinHabla.map((s) => s.split).toSet(),
        containsAll(<String>['ajuste', 'aceptacion']),
      );
    });

    test('ajuste y aceptación no contienen ninguna muestra sin habla', () {
      // Si estuvieran en las dos partes, dictar el corpus completo las mediría
      // dos veces y el guardrail de no-habla contaría el doble de muestras de
      // las que hubo.
      expect(
        hibrido.samplesOf(BenchPartition.ajuste).any((s) => s.isNonSpeech),
        isFalse,
      );
      expect(
        hibrido.samplesOf(BenchPartition.aceptacion).any((s) => s.isNonSpeech),
        isFalse,
      );
    });
  });

  // --------------------------------------------------- verificación del archivo

  group('el archivo tiene que ser exactamente el fijado', () {
    test('digest correcto: la carga pasa', () async {
      final p = pack(corpusBase());
      final loaded = await CorpusLoader(p.reader).load(p.descriptor);

      expect(loaded.digest, p.descriptor.expectedDigest);
    });

    test('digest incorrecto: se bloquea y se dicen los dos valores', () async {
      final json = corpusBase();
      final bytes = utf8.encode(const JsonEncoder().convert(json));
      final descriptor = CorpusDescriptor(
        id: 'prueba',
        label: 'Corpus de prueba',
        assetPath: 'assets/prueba.json',
        expectedVersion: 'prueba-1.0.0',
        expectedDigest: 'a' * 64,
      );

      final failure = await failureOf(
        CorpusLoader(readerFor({'assets/prueba.json': bytes})),
        descriptor,
      );

      expect(failure.kind, CorpusFailureKind.digestDistinto);
      expect(failure.expected, 'a' * 64);
      expect(failure.actual, sha256Hex(bytes));
      expect(failure.diagnostic, contains('assets/prueba.json'));
    });

    test('archivo ausente: se bloquea y se nombra la ruta', () async {
      final failure = await failureOf(
        CorpusLoader(readerFor(const {})),
        CorpusCatalog.hibridoAG,
      );

      expect(failure.kind, CorpusFailureKind.ausente);
      expect(failure.diagnostic, contains(CorpusCatalog.hibridoAG.assetPath));
    });

    test('archivo vacío: no se confunde con un corpus sin frases', () async {
      final failure = await failureOf(
        CorpusLoader(readerFor({'assets/prueba.json': const <int>[]})),
        CorpusDescriptor(
          id: 'prueba',
          label: 'Corpus de prueba',
          assetPath: 'assets/prueba.json',
          expectedVersion: 'prueba-1.0.0',
          expectedDigest: 'b' * 64,
        ),
      );

      expect(failure.kind, CorpusFailureKind.vacio);
    });

    test('archivo corrupto: JSON roto se rechaza como ilegible', () async {
      final bytes = utf8.encode('{"corpusVersion": "prueba-1.0.0", "samp');
      final failure = await failureOf(
        CorpusLoader(readerFor({'assets/prueba.json': bytes})),
        CorpusDescriptor(
          id: 'prueba',
          label: 'Corpus de prueba',
          assetPath: 'assets/prueba.json',
          expectedVersion: 'prueba-1.0.0',
          expectedDigest: sha256Hex(bytes),
        ),
      );

      expect(failure.kind, CorpusFailureKind.ilegible);
    });

    test('corpus sin ninguna frase se rechaza', () async {
      final json = corpusBase()..['samples'] = <Object?>[];
      final p = pack(json);

      expect(
        (await failureOf(CorpusLoader(p.reader), p.descriptor)).kind,
        CorpusFailureKind.sinMuestras,
      );
    });

    test(
      'versión distinta de la fijada se rechaza aunque el JSON sea válido',
      () async {
        final json = corpusBase()..['corpusVersion'] = 'prueba-9.9.9';
        final p = pack(json, version: 'prueba-1.0.0');

        final failure = await failureOf(CorpusLoader(p.reader), p.descriptor);
        expect(failure.kind, CorpusFailureKind.versionDistinta);
        expect(failure.actual, 'prueba-9.9.9');
      },
    );
  });

  // ------------------------------------------------------------- duplicados

  group('duplicados', () {
    test('identificador repetido dentro de una partición', () async {
      final json = corpusBase();
      (json['samples']! as List).add({
        'id': 'PA-001',
        'split': 'ajuste',
        'intent': 'compra',
        'category': 'A',
        'text': 'Otra frase distinta.',
        'expected': 'listo',
        'slots': <String, Object?>{},
        'conditions': <String>[],
        'tags': <String>[],
      });
      final p = pack(json);

      final failure = await failureOf(CorpusLoader(p.reader), p.descriptor);
      expect(failure.kind, CorpusFailureKind.idDuplicado);
      expect(failure.diagnostic, contains('PA-001'));
    });

    test('frase repetida dentro de la misma partición, normalizando', () async {
      // «Registrar compra de Bellator.» y «REGISTRAR  COMPRA DE BELLATOR»
      // son la misma frase dictada: contarla dos veces infla la muestra.
      final json = corpusBase();
      (json['samples']! as List).add({
        'id': 'PA-002',
        'split': 'ajuste',
        'intent': 'compra',
        'category': 'A',
        'text': 'REGISTRAR  COMPRA DE BELLATOR',
        'expected': 'listo',
        'slots': <String, Object?>{},
        'conditions': <String>[],
        'tags': <String>[],
      });
      final p = pack(json);

      final failure = await failureOf(CorpusLoader(p.reader), p.descriptor);
      expect(failure.kind, CorpusFailureKind.fraseDuplicada);
      expect(failure.diagnostic, contains('PA-002'));
    });

    test(
      'la misma frase en ajuste y en aceptación contamina la medición',
      () async {
        final json = corpusBase();
        (json['samples']! as List).add({
          'id': 'PC-002',
          'split': 'aceptacion',
          'intent': 'compra',
          'category': 'A',
          'text': 'Registrar compra de Bellator.',
          'expected': 'listo',
          'slots': <String, Object?>{},
          'conditions': <String>[],
          'tags': <String>[],
        });
        final p = pack(json);

        final failure = await failureOf(CorpusLoader(p.reader), p.descriptor);
        expect(
          failure.kind,
          CorpusFailureKind.contaminacionEntreParticiones,
          reason: 'afinar con una frase y evaluarse con ella mide el ajuste',
        );
        expect(failure.diagnostic, contains('PC-002'));
      },
    );

    test('la misma frase con otras condiciones no es un duplicado', () async {
      // El corpus de la Fase 0 lo hace a propósito: `AC-046` en silencio y
      // `AC-055` con ruido de campo son la misma frase medida en dos entornos.
      // Rechazarlo obligaría a tocar un corpus ya medido para satisfacer a una
      // guarda, que es exactamente lo contrario de lo que la guarda protege.
      final json = corpusBase();
      (json['samples']! as List).add({
        'id': 'PA-003',
        'split': 'ajuste',
        'intent': 'compra',
        'category': 'A',
        'text': 'Registrar compra de Bellator.',
        'expected': 'listo',
        'slots': <String, Object?>{},
        'conditions': <String>['ruido_tractor'],
        'tags': <String>[],
      });
      final p = pack(json);

      final loaded = await CorpusLoader(p.reader).load(p.descriptor);
      expect(loaded.samplesOf(BenchPartition.ajuste), hasLength(2));
    });

    test('la misma frase y las mismas condiciones sí lo es', () async {
      final json = corpusBase();
      (json['samples']! as List).add({
        'id': 'PA-004',
        'split': 'ajuste',
        'intent': 'compra',
        'category': 'A',
        'text': 'Registrar compra de Bellator.',
        'expected': 'listo',
        'slots': <String, Object?>{},
        'conditions': <String>[],
        'tags': <String>[],
      });
      final p = pack(json);

      expect(
        (await failureOf(CorpusLoader(p.reader), p.descriptor)).kind,
        CorpusFailureKind.fraseDuplicada,
      );
    });

    test('los dos corpus versionados pasan las tres comprobaciones', () async {
      // Es la guarda de verdad: si alguien edita un corpus e introduce un
      // duplicado, esto falla antes de que nadie dicte nada.
      await CorpusLoader(realReader).load(CorpusCatalog.fase0);
      await CorpusLoader(realReader).load(CorpusCatalog.hibridoAG);
    });
  });

  // --------------------------------------------------- el controlador

  group('el banco no deja medir sin identidad completa', () {
    late FakeSpeechTranscriptionPort port;

    // El motor es uno registrado a propósito: estas pruebas miran si el
    // *corpus* deja grabar, y un `engineId` sin candidato bloquearía por otra
    // razón y taparía lo que se quiere comprobar.
    BenchController controllerWith(AssetBytesReader reader) => BenchController(
      port: port,
      loader: CorpusLoader(reader),
      appVersion: 'test',
      benchCommit: 'c0ffee1',
      deviceInfo: const DeviceInfo(
        device: 'Equipo de prueba',
        androidRelease: '16',
        androidSdk: 36,
        abi: 'arm64-v8a',
      ),
    );

    setUp(
      () => port = FakeSpeechTranscriptionPort(engineId: 'vosk-small-es-0.42'),
    );

    test('arranca sin corpus y sin permitir grabar', () {
      final c = controllerWith(realReader);
      addTearDown(c.dispose);

      expect(c.activeCorpus, isNull);
      expect(c.canRun, isFalse);
      expect(c.corpusFailure, isNull);
    });

    test('elegir el híbrido carga el híbrido y lo dice', () async {
      final c = controllerWith(realReader);
      addTearDown(c.dispose);

      await c.selectCorpus(CorpusCatalog.hibridoAG);

      expect(c.activeCorpus!.descriptor.id, 'hibrido-ag');
      expect(c.canRun, isTrue);
    });

    test('la pantalla nunca nombra un corpus que no se cargó', () async {
      // El defecto original, exactamente: el rótulo venía de lo pedido y el
      // contenido de otro archivo.
      final c = controllerWith(realReader);
      addTearDown(c.dispose);
      await c.selectCorpus(CorpusCatalog.fase0);

      // Ahora el híbrido desaparece del paquete.
      final roto = BenchController(
        port: FakeSpeechTranscriptionPort(engineId: 'vosk-small-es-0.42'),
        loader: CorpusLoader(readerFor(const {})),
        appVersion: 'test',
        benchCommit: 'c0ffee1',
      );
      addTearDown(roto.dispose);
      await roto.selectCorpus(CorpusCatalog.hibridoAG);

      expect(roto.activeCorpus, isNull, reason: 'no hay corpus que nombrar');
      expect(roto.canRun, isFalse);
      expect(roto.corpusFailure!.kind, CorpusFailureKind.ausente);
    });

    test('un fallo no sustituye en silencio por el otro corpus', () async {
      final c = controllerWith(realReader);
      addTearDown(c.dispose);
      await c.selectCorpus(CorpusCatalog.fase0);
      expect(c.activeCorpus!.descriptor.id, 'fase0');

      // El híbrido está, pero con otros bytes que los fijados.
      final manipulado = utf8.encode(const JsonEncoder().convert(corpusBase()));
      final c2 = BenchController(
        port: FakeSpeechTranscriptionPort(engineId: 'vosk-small-es-0.42'),
        loader: CorpusLoader(
          readerFor({CorpusCatalog.hibridoAG.assetPath: manipulado}),
        ),
        appVersion: 'test',
        benchCommit: 'c0ffee1',
      );
      addTearDown(c2.dispose);
      await c2.selectCorpus(CorpusCatalog.fase0);
      await c2.selectCorpus(CorpusCatalog.hibridoAG);

      expect(c2.corpusFailure!.kind, CorpusFailureKind.digestDistinto);
      expect(c2.canRun, isFalse);
      expect(
        c2.activeCorpus,
        isNull,
        reason: 'quedarse con el anterior dejaría medir Fase 0 creyendo A–G',
      );
    });

    test(
      'elegir una partición que el corpus no tiene bloquea la grabación',
      () async {
        final c = controllerWith(realReader);
        addTearDown(c.dispose);
        await c.selectCorpus(CorpusCatalog.fase0);

        c.setPartition(BenchPartition.sinHabla);

        expect(c.canRun, isFalse);
        expect(c.total, 0);
      },
    );

    test(
      'el número que muestra la pantalla es el que se va a dictar',
      () async {
        final c = controllerWith(realReader);
        addTearDown(c.dispose);
        await c.selectCorpus(CorpusCatalog.hibridoAG);

        c.setPartition(BenchPartition.aceptacion);
        expect(c.total, c.samples.length);
        expect(c.total, 25);

        c.setPartition(BenchPartition.sinHabla);
        expect(c.total, c.samples.length);
        expect(c.total, 8);
      },
    );

    test('cambiar de corpus reinicia la posición, no la arrastra', () async {
      final c = controllerWith(realReader);
      addTearDown(c.dispose);
      await c.selectCorpus(CorpusCatalog.fase0);
      c.setPartition(BenchPartition.aceptacion);
      c.jumpTo(45);

      await c.selectCorpus(CorpusCatalog.hibridoAG);

      expect(c.position, 1);
      expect(c.current!.id, c.samples.first.id);
    });
  });

  // ------------------------------------------------- restauración

  group('restaurar una selección guardada', () {
    late FakeSpeechTranscriptionPort port;

    setUp(() => port = FakeSpeechTranscriptionPort());

    test('restaura corpus y partición sin tocar el contenido', () async {
      final c = BenchController(
        port: port,
        loader: CorpusLoader(realReader),
        appVersion: 'test',
        benchCommit: 'c0ffee1',
      );
      addTearDown(c.dispose);

      await c.restoreSelection(corpusId: 'hibrido-ag', partitionId: 'ajuste');

      expect(c.activeCorpus!.descriptor.id, 'hibrido-ag');
      expect(c.partition, BenchPartition.ajuste);
      expect(
        c.activeCorpus!.digest,
        '52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0',
        reason: 'restaurar vuelve a verificar; no da por bueno lo guardado',
      );
      expect(c.total, 21);
    });

    test('restaurar un corpus cuyo archivo cambió se rechaza', () async {
      final manipulado = utf8.encode(const JsonEncoder().convert(corpusBase()));
      final c = BenchController(
        port: port,
        loader: CorpusLoader(
          readerFor({CorpusCatalog.hibridoAG.assetPath: manipulado}),
        ),
        appVersion: 'test',
        benchCommit: 'c0ffee1',
      );
      addTearDown(c.dispose);

      await c.restoreSelection(
        corpusId: 'hibrido-ag',
        partitionId: 'aceptacion',
      );

      expect(c.activeCorpus, isNull);
      expect(c.corpusFailure!.kind, CorpusFailureKind.digestDistinto);
    });

    test(
      'restaurar un identificador desconocido no elige uno por su cuenta',
      () async {
        final c = BenchController(
          port: port,
          loader: CorpusLoader(realReader),
          appVersion: 'test',
          benchCommit: 'c0ffee1',
        );
        addTearDown(c.dispose);

        await c.restoreSelection(corpusId: 'el-que-sea', partitionId: 'ajuste');

        expect(c.activeCorpus, isNull);
        expect(c.corpusFailure!.kind, CorpusFailureKind.desconocido);
      },
    );
  });

  // ------------------------------------------------------------ candidatos

  group('el candidato y su modelo se identifican, no se suponen', () {
    test('cada sabor del banco tiene un candidato registrado', () {
      for (final engineId in const [
        'android-speech',
        'vosk-small-es-0.42',
        'whisper-tiny-q5_1',
        'whisper-base-q5_1',
        'whisper-small-q5_1',
        'hybrid-vosk-whisper-small',
      ]) {
        expect(
          CandidateRegistry.byEngineId(engineId),
          isNotNull,
          reason: 'el sabor $engineId mediría sin poder decir qué candidato es',
        );
      }
    });

    test('C1 es Vosk aislado: mismo motor en parcial y en final', () {
      final c1 = CandidateRegistry.byEngineId('vosk-small-es-0.42')!;

      expect(c1.id, 'C1');
      expect(c1.partialEngine, 'vosk-small-es-0.42');
      expect(c1.finalEngine, 'vosk-small-es-0.42');
      expect(c1.modelHashes.keys, contains('vosk-model-small-es-0.42'));
    });

    test('C3 es Whisper small y no promete parciales', () {
      final c3 = CandidateRegistry.byEngineId('whisper-small-q5_1')!;

      expect(c3.id, 'C3');
      expect(c3.partialEngine, isNull);
      expect(c3.finalEngine, 'whisper-small-q5_1');
      expect(
        c3.modelHashes['ggml-small-q5_1.bin'],
        'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
      );
    });

    test('C4 combina los dos motores y lleva los dos modelos', () {
      final c4 = CandidateRegistry.byEngineId('hybrid-vosk-whisper-small')!;

      expect(c4.id, 'C4');
      expect(c4.partialEngine, 'vosk-small-es-0.42');
      expect(c4.finalEngine, 'whisper-small-q5_1');
      expect(c4.modelHashes, hasLength(2));
    });

    test('un motor no registrado no se inventa un candidato', () {
      expect(CandidateRegistry.byEngineId('motor-que-no-existe'), isNull);
    });

    test('los hashes del registro son los que verifican los scripts', () {
      // Si alguien sube de modelo y toca sólo el script, o sólo el registro, la
      // exportación diría un hash y el APK llevaría otro.
      final scripts = <String>[
        File('tool/fetch_whisper_models.sh').readAsStringSync(),
        File('tool/fetch_vosk_model.sh').readAsStringSync(),
      ].join('\n');

      for (final candidate in CandidateRegistry.all) {
        candidate.modelHashes.forEach((model, hash) {
          expect(
            scripts,
            contains(hash),
            reason: '$model: el registro dice $hash y ningún script lo baja',
          );
        });
      }
    });

    test('el banco no deja grabar con un candidato sin identificar', () async {
      final c = BenchController(
        port: FakeSpeechTranscriptionPort(engineId: 'motor-desconocido'),
        loader: CorpusLoader(realReader),
        appVersion: 'test',
        benchCommit: 'c0ffee1',
      );
      addTearDown(c.dispose);
      await c.selectCorpus(CorpusCatalog.hibridoAG);

      expect(c.candidate, isNull);
      expect(c.canRun, isFalse);
    });
  });

  // ------------------------------------------------------------ exportación

  group('cada resultado exportado lleva la identidad entera', () {
    late BenchController c;

    setUp(() async {
      c = BenchController(
        port: FakeSpeechTranscriptionPort(engineId: 'vosk-small-es-0.42'),
        loader: CorpusLoader(realReader),
        appVersion: 'test',
        benchCommit: 'c0ffee1',
        deviceInfo: const DeviceInfo(
          device: 'HONOR JDY-LX3P',
          androidRelease: '16',
          androidSdk: 36,
          abi: 'arm64-v8a',
        ),
        airplaneProbe: () async => true,
      );
      addTearDown(c.dispose);
      await c.selectCorpus(CorpusCatalog.hibridoAG);
      c.setPartition(BenchPartition.ajuste);
      await c.setAirplaneMode(true);
      await c.record();
    });

    test('los dieciséis campos de identidad están y son los verdaderos', () {
      final json = c.results.single.toJson();

      expect(json['corpusId'], 'hibrido-ag');
      expect(json['corpusVersion'], 'hybrid-1.0.0');
      expect(
        json['corpusDigest'],
        '52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0',
      );
      expect(json['partition'], 'ajuste');
      expect(json['split'], 'ajuste');
      expect(json['candidateId'], 'C1');
      expect(json['partialEngine'], 'vosk-small-es-0.42');
      expect(json['finalEngine'], 'vosk-small-es-0.42');
      expect(
        json['modelHashes'],
        containsPair(
          'vosk-model-small-es-0.42',
          '09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f',
        ),
      );
      expect(json['benchCommit'], 'c0ffee1');
      expect(json['device'], 'HONOR JDY-LX3P');
      expect(json['androidSdk'], 36);
      expect(json['abi'], 'arm64-v8a');
      expect(json['startedAt'], isNotNull);
      expect(json['airplaneMode'], isTrue);
      expect(
        json['systemAirplaneMode'],
        isTrue,
        reason:
            'el modo avión que se registra es el observado, no el declarado',
      );
    });

    test(
      'el modo avión observado se registra aunque contradiga lo declarado',
      () async {
        final otro = BenchController(
          port: FakeSpeechTranscriptionPort(engineId: 'vosk-small-es-0.42'),
          loader: CorpusLoader(realReader),
          appVersion: 'test',
          benchCommit: 'c0ffee1',
          airplaneProbe: () async => false,
        );
        addTearDown(otro.dispose);
        await otro.selectCorpus(CorpusCatalog.hibridoAG);
        await otro.setAirplaneMode(true);
        await otro.record();

        final json = otro.results.single.toJson();
        expect(json['airplaneMode'], isTrue);
        expect(json['systemAirplaneMode'], isFalse);
      },
    );

    test(
      'la tanda entera repite la identidad, y el CSV la lleva en columnas',
      () {
        final run = c.buildRun();

        expect(run.corpusId, 'hibrido-ag');
        expect(run.corpusDigest, hasLength(64));
        expect(run.candidateId, 'C1');
        expect(run.benchCommit, 'c0ffee1');

        for (final columna in const [
          'corpusId',
          'corpusVersion',
          'corpusDigest',
          'partition',
          'candidateId',
          'partialEngine',
          'finalEngine',
          'benchCommit',
          'abi',
        ]) {
          expect(BenchExportColumns.csv, contains(columna));
        }
      },
    );

    test('quitar las transcripciones no quita la identidad', () {
      c.setIncludeTranscripts(false);
      final json = c.buildRun().toJson();
      final primero = (json['results']! as List).first as Map<String, Object?>;

      expect(primero['obtainedText'], isNull);
      expect(primero['corpusDigest'], hasLength(64));
      expect(primero['candidateId'], 'C1');
    });
  });
}
