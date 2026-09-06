import 'dart:async';

import 'package:flutter/foundation.dart';

import '../port/speech_transcription_port.dart';
import 'bench_export.dart';
import 'bench_result.dart';
import 'corpus.dart';

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
class BenchController extends ChangeNotifier {
  BenchController({
    required SpeechTranscriptionPort port,
    required Corpus corpus,
    required this.appVersion,
    this.deviceInfo = DeviceInfo.unknown,
    this.memoryProbe,
  }) : _port = port,
       _corpus = corpus {
    _subscription = _port.events.listen(_onEvent);
  }

  final SpeechTranscriptionPort _port;
  final Corpus _corpus;
  final String appVersion;
  final DeviceInfo deviceInfo;

  /// Lectura opcional de memoria del proceso. Si es `null` o devuelve `null`,
  /// la métrica queda sin medir y se exporta vacía.
  final Future<int?> Function()? memoryProbe;

  StreamSubscription<TranscriptionEvent>? _subscription;

  // ------------------------------------------------------------------ estado

  String _split = 'ajuste';
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

  Corpus get corpus => _corpus;
  String get split => _split;
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

  List<CorpusSample> get samples => _corpus.bySplit(_split);

  CorpusSample? get current {
    final list = samples;
    if (list.isEmpty) return null;
    return list[_index.clamp(0, list.length - 1)];
  }

  /// Posición 1..N de la frase actual dentro del `split`.
  int get position => samples.isEmpty ? 0 : _index + 1;

  int get total => samples.length;

  /// Frases del `split` activo que ya tienen al menos una medición.
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

  // -------------------------------------------------------------- comandos

  Future<void> refreshAvailability() async {
    _availability = await _port.checkAvailability(_requestedLocale);
    notifyListeners();
  }

  void setSplit(String value) {
    if (_split == value) return;
    _split = value;
    _index = 0;
    _clearSampleState();
    notifyListeners();
  }

  void setLocale(String value) {
    _requestedLocale = value;
    notifyListeners();
  }

  void setAirplaneMode(bool value) {
    _airplaneMode = value;
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
  Future<void> record({String? notes}) async {
    final sample = current;
    if (sample == null) return;
    final attempt = (_attempts[sample.id] ?? 0) + 1;
    _attempts[sample.id] = attempt;
    final memory = await memoryProbe?.call();
    _results.add(
      BenchResult(
        sampleId: sample.id,
        split: sample.split,
        intent: sample.intent,
        expectedText: sample.text,
        obtainedText: _finalText.isEmpty ? null : _finalText,
        engine: _port.engineId,
        model: _availability?.modelName ?? '',
        requestedLocale: _requestedLocale,
        effectiveLocale: _availability?.effectiveLocale,
        device: deviceInfo.device,
        androidRelease: deviceInfo.androidRelease,
        androidSdk: deviceInfo.androidSdk,
        airplaneMode: _airplaneMode,
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
    final run = BenchRun(
      engine: _port.engineId,
      model: _availability?.modelName ?? '',
      device: deviceInfo.device,
      androidRelease: deviceInfo.androidRelease,
      androidSdk: deviceInfo.androidSdk,
      abi: deviceInfo.abi,
      corpusVersion: _corpus.corpusVersion,
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
