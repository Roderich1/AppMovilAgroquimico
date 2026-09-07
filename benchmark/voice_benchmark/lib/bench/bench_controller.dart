import 'dart:async';

import 'package:flutter/foundation.dart';

import '../port/speech_transcription_port.dart';
import 'bench_export.dart';
import 'bench_result.dart';
import 'candidates.dart';
import 'corpus.dart';
import 'corpus_catalog.dart';

/// Datos del aparato donde corre la prueba.
final class DeviceInfo {
  const DeviceInfo({
    required this.device,
    required this.androidRelease,
    required this.androidSdk,
    required this.abi,
  });

  static const unknown = DeviceInfo(
    device: 'desconocido',
    androidRelease: 'desconocido',
    androidSdk: 0,
    abi: 'desconocida',
  );

  final String device;
  final String androidRelease;
  final int androidSdk;
  final String abi;
}

/// Conduce el corpus contra un [SpeechTranscriptionPort] y acumula mediciones.
///
/// No conoce SQLite, repositorios ni operaciones de negocio: recibe frases,
/// entrega texto y guarda tiempos. Su único efecto es una lista en memoria y,
/// cuando se exporta, un archivo de resultados.
///
/// ## Arranca sin corpus, y es a propósito
///
/// Antes recibía un `Corpus` ya construido y la pantalla nunca supo cuál era.
/// Así se midió C1 entero con el corpus de la Fase 0 creyendo estar en A–G.
/// Ahora recibe un [CorpusLoader] y **no hay corpus hasta que uno se carga y se
/// verifica**: sin eso, [canRun] es `false` y no se puede grabar.
class BenchController extends ChangeNotifier {
  BenchController({
    required SpeechTranscriptionPort port,
    required CorpusLoader loader,
    required this.appVersion,
    this.benchCommit = '',
    this.deviceInfo = DeviceInfo.unknown,
    this.memoryProbe,
    this.airplaneProbe,
  }) : _port = port,
       _loader = loader {
    _subscription = _port.events.listen(_onEvent);
  }

  final SpeechTranscriptionPort _port;
  final CorpusLoader _loader;
  final String appVersion;

  /// Commit del banco con el que se construyó este APK. Llega por
  /// `--dart-define`; vacío significa que nadie lo pasó, y así se exporta.
  final String benchCommit;

  final DeviceInfo deviceInfo;

  /// Lectura opcional de memoria del proceso. Si es `null` o devuelve `null`,
  /// la métrica queda sin medir y se exporta vacía.
  final Future<int?> Function()? memoryProbe;

  /// Lectura opcional del modo avión del sistema. Sirve para contrastar lo que
  /// el operador declaró; si es `null`, el contraste no se hace y el campo se
  /// exporta vacío en vez de dar por buena la declaración.
  final Future<bool?> Function()? airplaneProbe;

  StreamSubscription<TranscriptionEvent>? _subscription;

  bool? _systemAirplaneMode;

  // ------------------------------------------------------------------ estado

  LoadedCorpus? _activeCorpus;
  CorpusLoadFailure? _corpusFailure;
  BenchPartition _partition = BenchPartition.ajuste;
  int _index = 0;
  String _requestedLocale = 'es-BO';
  bool _airplaneMode = false;
  bool _includeTranscripts = true;

  TranscriptionAvailability? _availability;
  TranscriptionState _state = TranscriptionState.idle;
  String _partialText = '';
  String _finalText = '';
  String? _errorCode;
  String? _errorDetail;
  int? _partialLatencyMs;
  int? _finalLatencyMs;
  Stopwatch? _sessionClock;
  int? _audioDurationMs;
  final Map<String, int> _attempts = <String, int>{};
  final List<BenchResult> _results = <BenchResult>[];

  /// El corpus cargado y verificado, o `null` si no hay ninguno utilizable.
  ///
  /// La pantalla lee de aquí, nunca de lo que se pidió cargar: es lo que impide
  /// que el rótulo diga «híbrido A–G» mientras dentro hay otra cosa.
  LoadedCorpus? get activeCorpus => _activeCorpus;

  /// Por qué el último intento de cargar un corpus no sirvió.
  CorpusLoadFailure? get corpusFailure => _corpusFailure;

  BenchPartition get partition => _partition;
  String get requestedLocale => _requestedLocale;
  bool get airplaneMode => _airplaneMode;
  bool get includeTranscripts => _includeTranscripts;
  TranscriptionAvailability? get availability => _availability;
  TranscriptionState get state => _state;
  String get partialText => _partialText;
  String get finalText => _finalText;
  String? get errorCode => _errorCode;
  String? get errorDetail => _errorDetail;
  int? get partialLatencyMs => _partialLatencyMs;
  int? get finalLatencyMs => _finalLatencyMs;
  int? get audioDurationMs => _audioDurationMs;
  List<BenchResult> get results => List.unmodifiable(_results);

  /// El candidato que corresponde al motor instalado.
  ///
  /// Sale de `engineId`, que viene del sabor compilado. `null` significa que
  /// este APK no es ninguno de los candidatos conocidos: se bloquea, porque una
  /// medición que no se puede nombrar no se puede colocar en ninguna columna.
  BenchCandidate? get candidate => CandidateRegistry.byEngineId(_port.engineId);

  /// Las frases de la partición activa. Es la **única** lista que se dicta, y
  /// la misma de la que sale [total].
  List<CorpusSample> get samples =>
      _activeCorpus?.samplesOf(_partition) ?? const <CorpusSample>[];

  /// Se puede grabar: hay corpus verificado, la partición tiene frases y el
  /// candidato está identificado.
  bool get canRun =>
      _activeCorpus != null && samples.isNotEmpty && candidate != null;

  /// Por qué no se puede grabar, en una frase para la pantalla.
  String? get blockedReason {
    if (_corpusFailure != null) return _corpusFailure!.diagnostic;
    if (_activeCorpus == null) {
      return 'Elija un corpus antes de grabar.';
    }
    if (samples.isEmpty) {
      return 'El corpus «${_activeCorpus!.descriptor.label}» no tiene frases '
          'en la partición «${_partition.label}».';
    }
    if (candidate == null) {
      return 'El motor «${_port.engineId}» no corresponde a ningún candidato '
          'registrado. No se puede etiquetar la medición.';
    }
    return null;
  }

  /// Modo avión según el sistema. `null` mientras no se haya podido consultar.
  bool? get systemAirplaneMode => _systemAirplaneMode;

  /// Lo declarado no coincide con lo que dice el teléfono.
  bool get airplaneModeMismatch =>
      _systemAirplaneMode != null && _systemAirplaneMode != _airplaneMode;

  CorpusSample? get current {
    final list = samples;
    if (list.isEmpty) return null;
    return list[_index.clamp(0, list.length - 1)];
  }

  /// Posición 1..N de la frase actual dentro de la partición.
  int get position => samples.isEmpty ? 0 : _index + 1;

  int get total => samples.length;

  /// Frases de la partición activa que ya tienen al menos una medición.
  int get measured {
    final ids = _results.map((r) => r.sampleId).toSet();
    return samples.where((s) => ids.contains(s.id)).length;
  }

  /// Motor y modelo tal como los reporta el adaptador.
  String get engineLabel {
    final a = _availability;
    if (a == null) return _port.engineId;
    final model = a.modelName;
    return model == null || model.isEmpty
        ? '${a.engineName} ${a.engineVersion}'.trim()
        : '${a.engineName} ${a.engineVersion} · $model'.trim();
  }

  // ------------------------------------------------------- corpus y partición

  /// Carga y verifica [descriptor].
  ///
  /// Si falla, **no queda ningún corpus activo**. Conservar el anterior sería
  /// la forma exacta de medir Fase 0 con el rótulo de A–G puesto; sustituirlo
  /// por el otro sería peor todavía, porque nadie lo pidió.
  Future<void> selectCorpus(CorpusDescriptor descriptor) async {
    try {
      final loaded = await _loader.load(descriptor);
      _activeCorpus = loaded;
      _corpusFailure = null;
    } on CorpusLoadFailure catch (failure) {
      _activeCorpus = null;
      _corpusFailure = failure;
    }
    _index = 0;
    _clearSampleState();
    notifyListeners();
  }

  /// Vuelve a una selección guardada, verificándola otra vez.
  ///
  /// Restaurar no es dar por buena la selección anterior: el archivo pudo
  /// cambiar entre una corrida y otra, y ahí es donde una comparación se
  /// estropea sin que nadie lo note. Pasa por el mismo camino que
  /// [selectCorpus], con las mismas comprobaciones.
  Future<void> restoreSelection({
    required String corpusId,
    required String partitionId,
  }) async {
    final descriptor = CorpusCatalog.byId(corpusId);
    if (descriptor == null) {
      _activeCorpus = null;
      _corpusFailure = CorpusLoadFailure(
        kind: CorpusFailureKind.desconocido,
        assetPath: '',
        diagnostic:
            'No hay ningún corpus con el identificador «$corpusId». '
            'El banco no elige otro por su cuenta.',
        actual: corpusId,
      );
      notifyListeners();
      return;
    }
    final partition = BenchPartition.byId(partitionId);
    if (partition != null) _partition = partition;
    await selectCorpus(descriptor);
  }

  void setPartition(BenchPartition value) {
    if (_partition == value) return;
    _partition = value;
    _index = 0;
    _clearSampleState();
    notifyListeners();
  }

  // -------------------------------------------------------------- comandos

  Future<void> refreshAvailability() async {
    _availability = await _port.checkAvailability(_requestedLocale);
    _systemAirplaneMode = await airplaneProbe?.call();
    notifyListeners();
  }

  void setLocale(String value) {
    _requestedLocale = value;
    notifyListeners();
  }

  Future<void> setAirplaneMode(bool value) async {
    _airplaneMode = value;
    notifyListeners();
    // Se contrasta al momento de marcar, no sólo al exportar: descubrir a
    // posteriori que una tanda entera estaba mal etiquetada cuesta repetirla.
    _systemAirplaneMode = await airplaneProbe?.call();
    notifyListeners();
  }

  void setIncludeTranscripts(bool value) {
    _includeTranscripts = value;
    notifyListeners();
  }

  void next() {
    if (_index < samples.length - 1) {
      _index++;
      _clearSampleState();
      notifyListeners();
    }
  }

  void previous() {
    if (_index > 0) {
      _index--;
      _clearSampleState();
      notifyListeners();
    }
  }

  void jumpTo(int index) {
    if (samples.isEmpty) return;
    _index = index.clamp(0, samples.length - 1);
    _clearSampleState();
    notifyListeners();
  }

  /// Vuelve a dictar la frase actual. La medición anterior se conserva: el
  /// número de intento distingue las tomas.
  void repeat() {
    _clearSampleState();
    notifyListeners();
  }

  Future<void> start() async {
    if (!canRun) return;
    final sample = current;
    if (sample == null) return;
    _clearSampleState();
    _sessionClock = Stopwatch()..start();
    notifyListeners();
    await _port.start(
      TranscriptionRequest(
        locale: _requestedLocale,
        preferOffline: true,
        partialResults: true,
      ),
    );
  }

  Future<void> stop() {
    _markSpeechEnded();
    return _port.stop();
  }

  Future<void> cancel() => _port.cancel();

  /// Guarda la medición de la frase actual y avanza.
  ///
  /// Cada fila sale con la identidad entera de la corrida encima. Es lo que
  /// permite que el agregador se niegue a comparar dos corpus distintos, y lo
  /// que faltaba cuando C1 se midió sobre el corpus equivocado.
  Future<void> record({String? notes}) async {
    final sample = current;
    final corpus = _activeCorpus;
    if (sample == null || corpus == null) return;
    final attempt = (_attempts[sample.id] ?? 0) + 1;
    _attempts[sample.id] = attempt;
    final memory = await memoryProbe?.call();
    final systemAirplane = await airplaneProbe?.call();
    final candidate = this.candidate;
    _results.add(
      BenchResult(
        sampleId: sample.id,
        split: sample.split,
        partition: _partition.id,
        intent: sample.intent,
        expectedText: sample.text,
        obtainedText: _finalText.isEmpty ? null : _finalText,
        engine: _port.engineId,
        model: _availability?.modelName ?? '',
        corpusId: corpus.descriptor.id,
        corpusVersion: corpus.version,
        corpusDigest: corpus.digest,
        candidateId: candidate?.id ?? '',
        partialEngine: candidate?.partialEngine,
        finalEngine: candidate?.finalEngine ?? '',
        modelHashes: candidate?.modelHashes ?? const <String, String>{},
        benchCommit: benchCommit,
        abi: deviceInfo.abi,
        requestedLocale: _requestedLocale,
        effectiveLocale: _availability?.effectiveLocale,
        device: deviceInfo.device,
        androidRelease: deviceInfo.androidRelease,
        androidSdk: deviceInfo.androidSdk,
        airplaneMode: _airplaneMode,
        systemAirplaneMode: systemAirplane,
        startedAt: DateTime.now(),
        partialLatencyMs: _partialLatencyMs,
        finalLatencyMs: _finalLatencyMs,
        audioDurationMs: _audioDurationMs,
        memoryBytes: memory,
        errorCode: _errorCode,
        errorDetail: _errorDetail,
        attempt: attempt,
        notes: notes,
      ),
    );
    notifyListeners();
  }

  /// Borra todas las mediciones acumuladas.
  void clearResults() {
    _results.clear();
    _attempts.clear();
    notifyListeners();
  }

  /// Arma la tanda exportable, respetando la decisión sobre transcripciones.
  BenchRun buildRun({String? notes}) {
    final corpus = _activeCorpus;
    final candidate = this.candidate;
    final run = BenchRun(
      engine: _port.engineId,
      model: _availability?.modelName ?? '',
      device: deviceInfo.device,
      androidRelease: deviceInfo.androidRelease,
      androidSdk: deviceInfo.androidSdk,
      abi: deviceInfo.abi,
      corpusId: corpus?.descriptor.id ?? '',
      corpusVersion: corpus?.version ?? '',
      corpusDigest: corpus?.digest ?? '',
      partition: _partition.id,
      candidateId: candidate?.id ?? '',
      partialEngine: candidate?.partialEngine,
      finalEngine: candidate?.finalEngine ?? '',
      modelHashes: candidate?.modelHashes ?? const <String, String>{},
      benchCommit: benchCommit,
      appVersion: appVersion,
      notes: notes,
      results: List.of(_results),
    );
    return _includeTranscripts ? run : run.withoutTranscripts();
  }

  // -------------------------------------------------------------- interno

  void _clearSampleState() {
    _partialText = '';
    _finalText = '';
    _errorCode = null;
    _errorDetail = null;
    _partialLatencyMs = null;
    _finalLatencyMs = null;
    _audioDurationMs = null;
    _sessionClock = null;
  }

  /// Momento en que el habla terminó: o el usuario tocó "Detener", o el motor
  /// detectó el final por su cuenta y pasó a `processing`.
  ///
  /// A partir de aquí se cuenta la latencia del resultado final, que es lo que
  /// el plan de benchmark define ("tras detener el habla") y lo único que el
  /// usuario percibe como espera. Medirla desde el inicio de la sesión daría el
  /// largo de la frase, no el trabajo del motor.
  void _markSpeechEnded() {
    final clock = _sessionClock;
    if (clock == null || _audioDurationMs != null) return;
    _audioDurationMs = clock.elapsedMilliseconds;
  }

  void _onEvent(TranscriptionEvent event) {
    switch (event) {
      case TranscriptionStateChanged(:final state):
        _state = state;
        if (state == TranscriptionState.processing) _markSpeechEnded();
      case TranscriptionPartial(:final text, :final elapsed):
        _partialText = text;
        _partialLatencyMs ??= elapsed.inMilliseconds;
      case TranscriptionFinal(:final text, :final elapsed):
        _finalText = text;
        _markSpeechEnded();
        // `elapsed` viene medido desde `start()`; restar el audio deja el tiempo
        // que tardó el motor en responder.
        _finalLatencyMs = elapsed.inMilliseconds - (_audioDurationMs ?? 0);
        _sessionClock?.stop();
      case TranscriptionFailed(:final code, :final detail):
        _errorCode = code.name;
        _errorDetail = detail;
        _markSpeechEnded();
        _sessionClock?.stop();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    // Soltar el micrófono es obligatorio al salir de la pantalla.
    unawaited(_port.dispose());
    super.dispose();
  }
}
