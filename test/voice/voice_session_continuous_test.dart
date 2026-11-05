import 'dart:async';

import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice/session/voice_session_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puerto que escucha a través de las pausas, como el motor local (#165).
///
/// Los eventos los empuja la prueba: aquí se comprueba la política de la
/// sesión, no el reconocimiento.
final class _ContinuousPort implements SpeechTranscriptionPort {
  final events$ = StreamController<TranscriptionEvent>.broadcast();
  final requests = <TranscriptionRequest>[];
  bool open = false;

  @override
  String get engineId => 'continuo';
  @override
  bool get listensAcrossPauses => true;
  @override
  bool get isTurnOpen => open;
  @override
  Stream<TranscriptionEvent> get events => events$.stream;

  void emit(TranscriptionEvent e) => events$.add(e);

  void end(TranscriptionEndReason reason) {
    open = false;
    emit(TranscriptionTurnEnded(reason));
  }

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async =>
      const TranscriptionAvailability(
        recognizerAvailable: true,
        onDeviceApiReports: false,
        installedLocales: ['es'],
        supportedLocales: ['es'],
        reviewModel: 'whisper-base-q5_1',
      );

  @override
  Future<void> start(TranscriptionRequest request) async {
    requests.add(request);
    open = true;
    emit(const TranscriptionRouteInUse(TranscriptionEngineRoute.embedded));
    emit(const TranscriptionLocaleInUse('es'));
    emit(const TranscriptionStageChanged(TranscriptionStage.listening));
  }

  @override
  Future<void> stop() async =>
      emit(const TranscriptionStageChanged(TranscriptionStage.processing));

  @override
  Future<void> cancel() async {
    if (!open) return;
    emit(const TranscriptionCancelled());
    end(TranscriptionEndReason.cancelled);
  }

  @override
  Future<bool> openSystemSettings() async => false;
  @override
  Future<void> dispose() async => events$.close();
}

TranscriptionSegment seg(String text, int seq) =>
    TranscriptionSegment(text, elapsed: Duration.zero, sequence: seq);

void main() {
  late _ContinuousPort port;
  late VoiceSessionController session;

  void begin(FakeAsync async) {
    port = _ContinuousPort();
    session = VoiceSessionController(port: port);
    session.startListening();
    async.flushMicrotasks();
  }

  test('arranca con el motor local, en español y sin aviso de «otro idioma»', () {
    fakeAsync((async) {
      begin(async);
      final s = session.snapshot;
      expect(s.route, TranscriptionEngineRoute.embedded);
      expect(s.status, VoiceSessionStatus.listening);
      expect(s.localeInUse, 'es');
      expect(s.localeIsFallback, isFalse);
      session.dispose();
    });
  });

  test('un turno por sesión, con el plazo de la sesión, pistas y revisión', () {
    fakeAsync((async) {
      port = _ContinuousPort();
      session = VoiceSessionController(port: port)
        ..setVocabularyHints(['Glifosato', 'Ana Quispe']);
      session.startListening();
      async.flushMicrotasks();
      final r = port.requests.single;
      expect(r.maxTurnDuration, const Duration(minutes: 5));
      expect(r.hints, ['Glifosato', 'Ana Quispe']);
      expect(r.review, isTrue);
      session.dispose();
    });
  });

  test('varias frases en un turno: en orden, una vez cada una, parcial aparte', () {
    fakeAsync((async) {
      begin(async);
      port.emit(const TranscriptionPartial(
        'compré dos litros',
        elapsed: Duration.zero,
        reviewing: 1,
      ));
      async.flushMicrotasks();
      expect(session.snapshot.partialText, 'compré dos litros');
      expect(session.snapshot.reviewing, 1);
      expect(session.snapshot.committedText, isEmpty);

      port.emit(seg('Compré dos litros de glifosato.', 0));
      port.emit(seg('Compré dos litros de glifosato.', 0)); // repetida
      port.emit(seg('pagué cien bolivianos', 1));
      async.flushMicrotasks();
      expect(session.snapshot.committedText,
          'Compré dos litros de glifosato. pagué cien bolivianos');
      expect(session.snapshot.segmentCount, 2);
      // Sigue escuchando: una pausa no cierra el dictado.
      expect(session.snapshot.status, VoiceSessionStatus.listening);
      expect(port.requests, hasLength(1));
      session.dispose();
    });
  });

  test('una frase que llega después de editar se añade al final, sin reescribir', () {
    fakeAsync((async) {
      begin(async);
      port.emit(seg('sinco litros', 0));
      async.flushMicrotasks();
      session.editText('cinco litros de bellator');
      port.emit(seg('a cien bolivianos', 1));
      async.flushMicrotasks();
      expect(session.snapshot.committedText,
          'cinco litros de bellator a cien bolivianos');
      expect(session.snapshot.manuallyEdited, isTrue);
      session.dispose();
    });
  });

  test('detener entrega lo pendiente y deja el texto editable, sin reabrir', () {
    fakeAsync((async) {
      begin(async);
      session.stopListening();
      async.flushMicrotasks();
      port.emit(seg('dos litros', 0));
      port.end(TranscriptionEndReason.stoppedByUser);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      expect(session.snapshot.status, VoiceSessionStatus.preview);
      expect(session.snapshot.committedText, 'dos litros');
      expect(port.requests, hasLength(1));
      session.dispose();
    });
  });

  test('silencio largo o plazo: termina sin texto inventado y no reabre', () {
    fakeAsync((async) {
      begin(async);
      port.emit(const TranscriptionTimeout());
      port.end(TranscriptionEndReason.timeout);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(session.snapshot.status, VoiceSessionStatus.preview);
      expect(session.snapshot.committedText, isEmpty);
      expect(port.requests, hasLength(1));
      session.dispose();
    });
  });

  test('la revisión se puede desactivar para el siguiente dictado', () {
    fakeAsync((async) {
      begin(async);
      session.stopListening();
      port.end(TranscriptionEndReason.stoppedByUser);
      async.flushMicrotasks();
      session.setReviewEnabled(false);
      session.startListening();
      async.flushMicrotasks();
      expect(port.requests.last.review, isFalse);
      session.dispose();
    });
  });

  test('descartar conserva el motor local y no deja texto', () {
    fakeAsync((async) {
      begin(async);
      port.emit(seg('dos litros', 0));
      async.flushMicrotasks();
      session.discard();
      async.flushMicrotasks();
      expect(session.snapshot.committedText, isEmpty);
      expect(session.snapshot.route, TranscriptionEngineRoute.embedded);
      expect(port.isTurnOpen, isFalse);
      session.dispose();
    });
  });

  test('la duración máxima de sesión detiene (guarda lo dicho), no descarta', () {
    fakeAsync((async) {
      begin(async);
      port.emit(seg('dos litros', 0));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(session.snapshot.status, VoiceSessionStatus.stopping);
      expect(session.snapshot.committedText, 'dos litros');
      session.dispose();
    });
  });
}
