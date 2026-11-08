import 'dart:async';

import 'package:flutter/services.dart';

/// Una sola suscripción de Dart por canal de eventos nativo, compartida por
/// todos los adaptadores vivos de ese canal.
///
/// ## Por qué existe (#119)
///
/// `EventChannel.receiveBroadcastStream()` registra **un** manejador por nombre
/// de canal, y cancelar cualquiera de esas suscripciones lo borra para todas:
/// en Dart deja el canal sin manejador y en Kotlin pone `sink = null`.
///
/// Cada visita a una pantalla de voz crea su propio adaptador, y Flutter libera
/// la ruta anterior **al terminar su animación**, no al empujar la nueva. Si la
/// pantalla nueva ya se suscribió, la baja de la vieja la dejaba sorda: ningún
/// evento del motor llegaba y la sesión se quedaba en «Abriendo el micrófono».
///
/// Aquí la suscripción real se abre con el primer adaptador y se cierra con el
/// último. Cada adaptador recibe todos los eventos y descarta los que no son de
/// su turno por el número de turno, que es único en el proceso.
final class NativeEventHub {
  NativeEventHub._(this._channel);

  static final Map<String, NativeEventHub> _hubs = <String, NativeEventHub>{};

  final EventChannel _channel;
  final List<_HubListener> _listeners = <_HubListener>[];
  StreamSubscription<dynamic>? _subscription;

  /// Engancha [onEvent] y [onError] a los eventos de [channel].
  ///
  /// Devuelve la baja: hay que llamarla una vez al liberar el adaptador.
  static NativeEventLease attach(
    EventChannel channel, {
    required void Function(dynamic event) onEvent,
    required void Function(Object error) onError,
  }) {
    final hub = _hubs.putIfAbsent(
      channel.name,
      () => NativeEventHub._(channel),
    );
    final listener = _HubListener(onEvent, onError);
    hub._listeners.add(listener);
    hub._subscription ??= channel.receiveBroadcastStream().listen(
      hub._dispatch,
      onError: hub._dispatchError,
    );
    return NativeEventLease._(hub, listener);
  }

  /// Adaptadores enganchados a [channelName]. Sólo para pruebas.
  static int listenersOf(String channelName) =>
      _hubs[channelName]?._listeners.length ?? 0;

  void _dispatch(dynamic event) {
    for (final listener in List<_HubListener>.of(_listeners)) {
      listener.onEvent(event);
    }
  }

  void _dispatchError(Object error) {
    for (final listener in List<_HubListener>.of(_listeners)) {
      listener.onError(error);
    }
  }

  Future<void> _detach(_HubListener listener) async {
    if (!_listeners.remove(listener)) return;
    if (_listeners.isNotEmpty) return;
    final subscription = _subscription;
    _subscription = null;
    if (identical(_hubs[_channel.name], this)) _hubs.remove(_channel.name);
    await subscription?.cancel();
  }
}

/// La suscripción de un adaptador al canal compartido.
final class NativeEventLease {
  NativeEventLease._(this._hub, this._listener);

  final NativeEventHub _hub;
  final _HubListener _listener;

  /// Deja de recibir eventos. Idempotente. El canal real sólo se cierra cuando
  /// no queda ningún adaptador.
  Future<void> cancel() => _hub._detach(_listener);
}

final class _HubListener {
  _HubListener(this.onEvent, this.onError);

  final void Function(dynamic event) onEvent;
  final void Function(Object error) onError;
}
