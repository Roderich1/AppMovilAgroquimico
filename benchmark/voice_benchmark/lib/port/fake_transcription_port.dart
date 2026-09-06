import 'dart:async';

import 'base_transcription_port.dart';
import 'speech_transcription_port.dart';

/// Guion determinista para el fake.
///
/// Un escenario describe qué hará el "motor" sin depender de micrófono, red ni
/// hilo nativo. Es lo que permite probar permiso denegado, servicio ausente,
/// timeout, parciales y modo avión sin un teléfono delante.
final class FakeScenario {
  const FakeScenario({
    this.partials = const [],
    this.finalText,
    this.failWith,
    this.failDetail,
    this.availability,
    this.autoFinalize = true,
  });

  /// Parciales que se emitirán al iniciar, en orden.
  final List<String> partials;

  /// Resultado final que se emitirá al llamar `stop()`.
  final String? finalText;

  /// Si no es nulo, `start()` falla con este código en lugar de escuchar.
  final TranscriptionErrorCode? failWith;

  final String? failDetail;

  /// Respuesta fija de `checkAvailability`.
  final TranscriptionAvailability? availability;

  /// Si es `false`, `stop()` no emite final: simula un motor que se queda
  /// procesando (para probar el timeout de la interfaz).
  final bool autoFinalize;

  /// Motor sano con resultado en español.
  static const ok = FakeScenario(
    partials: ['registrar', 'registrar compra'],
    finalText: 'registrar compra de cincuenta litros',
  );

  /// El usuario negó el micrófono.
  static const permissionDenied = FakeScenario(
    failWith: TranscriptionErrorCode.permissionDenied,
  );

  /// No hay reconocedor en el aparato.
  static const serviceUnavailable = FakeScenario(
    failWith: TranscriptionErrorCode.serviceUnavailable,
  );

  /// Modo avión con un motor que necesitaba red.
  static const airplaneMode = FakeScenario(
    failWith: TranscriptionErrorCode.networkRequired,
    failDetail: 'no-network',
  );
}

/// Implementación determinista del puerto, sin plataforma.
///
/// Es la que exige `EVO-009` para los tests y la que `ADR-002` señala mientras
/// no haya motor elegido: la interfaz y el controlador se prueban contra este
/// fake, de modo que cambiar de motor no invalida la suite.
///
/// Además **registra** las llamadas recibidas, para poder afirmar en un test que
/// el micrófono se liberó y que no quedó una sesión abierta.
final class FakeSpeechTranscriptionPort extends BaseSpeechTranscriptionPort {
  FakeSpeechTranscriptionPort({this.scenario = FakeScenario.ok});

  FakeScenario scenario;

  /// Nombres de los métodos de motor invocados, en orden.
  final List<String> calls = <String>[];

  /// Cuántas veces se abrió realmente la captura.
  int get startCount => calls.where((c) => c == 'start').length;

  /// `true` si el motor no tiene el micrófono tomado.
  bool get microphoneReleased => !isSessionOpen;

  @override
  String get engineId => 'fake';

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async {
    calls.add('availability');
    return scenario.availability ??
        TranscriptionAvailability(
          available: true,
          onDeviceAvailable: true,
          requestedLocale: locale,
          effectiveLocale: locale,
          installedLocales: [locale],
          supportedLocales: [locale],
          engineName: 'fake',
          engineVersion: '1',
          requiresNetwork: false,
        );
  }

  @override
  Future<void> engineStart(TranscriptionRequest request) async {
    calls.add('start');
    final failure = scenario.failWith;
    if (failure != null) {
      emitFailure(failure, detail: scenario.failDetail);
      return;
    }
    emitState(TranscriptionState.listening);
    for (final partial in scenario.partials) {
      emitPartial(partial);
    }
  }

  @override
  Future<void> engineStop() async {
    calls.add('stop');
    if (!scenario.autoFinalize) return;
    emitFinal(scenario.finalText ?? '');
  }

  @override
  Future<void> engineCancel() async {
    calls.add('cancel');
  }

  @override
  Future<void> engineDispose() async {
    calls.add('dispose');
  }

  /// Simula que el sistema interrumpió la sesión (llamada entrante, pérdida de
  /// foco, pantalla bloqueada). El adaptador real recibe esto de la plataforma.
  void simulateInterruption() {
    emitFailure(
      TranscriptionErrorCode.engineFailure,
      detail: 'system-interruption',
    );
  }

  /// Simula que la app pasó a segundo plano: se cancela y se suelta el micrófono.
  Future<void> simulateBackground() => cancel();
}
