import 'dart:async';

import 'package:flutter/services.dart';

import 'base_transcription_port.dart';
import 'speech_transcription_port.dart';

/// Adaptador sobre el motor nativo del sabor (`flavor`) instalado.
///
/// Un mismo canal sirve para los tres APK: el lado Android decide, en tiempo de
/// compilación, si detrás hay `SpeechRecognizer` o `whisper.cpp`. Dart no lo
/// sabe ni le importa; eso es justamente el escape hatch que pide `ADR-002`.
///
/// El canal transporta **texto y estados**, nunca audio. El audio no sale del
/// proceso nativo y no se guarda.
final class PlatformSpeechTranscriptionPort
    extends BaseSpeechTranscriptionPort {
  PlatformSpeechTranscriptionPort({MethodChannel? method, EventChannel? event})
    : _method = method ?? const MethodChannel(methodChannelName),
      _event = event ?? const EventChannel(eventChannelName) {
    _subscription = _event.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object e) => emitFailure(
        TranscriptionErrorCode.engineFailure,
        detail: e.runtimeType.toString(),
      ),
    );
  }

  static const methodChannelName = 'agro.voicebench/speech';
  static const eventChannelName = 'agro.voicebench/speech_events';

  final MethodChannel _method;
  final EventChannel _event;
  StreamSubscription<dynamic>? _subscription;

  String _engineId = 'unknown';

  @override
  String get engineId => _engineId;

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async {
    final raw = await _method.invokeMapMethod<String, Object?>('availability', {
      'locale': locale,
    });
    final map = raw ?? const <String, Object?>{};
    _engineId = (map['engineId'] as String?) ?? _engineId;
    return TranscriptionAvailability(
      available: map['available'] as bool? ?? false,
      onDeviceAvailable: map['onDeviceAvailable'] as bool? ?? false,
      requestedLocale: locale,
      effectiveLocale: map['effectiveLocale'] as String?,
      installedLocales: _strings(map['installedLocales']),
      supportedLocales: _strings(map['supportedLocales']),
      engineName: map['engineName'] as String? ?? '',
      engineVersion: map['engineVersion'] as String? ?? '',
      modelName: map['modelName'] as String?,
      requiresNetwork: map['requiresNetwork'] as bool? ?? true,
      detail: map['detail'] as String?,
    );
  }

  @override
  Future<void> engineStart(TranscriptionRequest request) async {
    await _method.invokeMethod<void>('start', {
      'locale': request.locale,
      'preferOffline': request.preferOffline,
      'partialResults': request.partialResults,
      'maxDurationMs': request.maxDuration.inMilliseconds,
    });
  }

  @override
  Future<void> engineStop() => _method.invokeMethod<void>('stop');

  @override
  Future<void> engineCancel() => _method.invokeMethod<void>('cancel');

  @override
  Future<void> engineDispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _method.invokeMethod<void>('dispose');
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = raw.cast<Object?, Object?>();
    switch (map['type'] as String?) {
      case 'partial':
        emitPartial(map['text'] as String? ?? '');
      case 'final':
        emitFinal(map['text'] as String? ?? '');
      case 'error':
        emitFailure(
          _codeFrom(map['code'] as String?),
          detail: map['detail'] as String?,
        );
      case 'state':
        final name = map['state'] as String?;
        for (final s in TranscriptionState.values) {
          if (s.name == name) emitState(s);
        }
    }
  }

  static TranscriptionErrorCode _codeFrom(String? name) {
    for (final code in TranscriptionErrorCode.values) {
      if (code.name == name) return code;
    }
    return TranscriptionErrorCode.engineFailure;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}
