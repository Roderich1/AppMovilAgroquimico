import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Android no confirmó la protección de la pantalla: lo sensible no se
/// muestra.
class ScreenSecureUnavailable implements Exception {
  const ScreenSecureUnavailable();

  String get message =>
      'No se pudo proteger la pantalla contra capturas, así que la clave no '
      'se muestra. Inténtelo otra vez.';

  @override
  String toString() => message;
}

/// FLAG_SECURE de Android mientras se muestra, se confirma o se escribe la
/// clave de recuperación (F08-ADR-003 §3.4): sin capturas ni grabación de
/// pantalla, y con la miniatura de recientes en blanco también en segundo
/// plano.
///
/// Cada pantalla o diálogo sensible toma su [ScreenSecureLease] y la marca se
/// quita sólo al devolver el último: cerrar uno no desprotege otro que siga
/// abierto. [acquire] termina cuando Android ya aplicó la marca, así que quien
/// lo espera antes de pintar lo sensible no deja un primer fotograma sin
/// proteger. Si Android no la confirma, [acquire] falla y no se muestra nada.
/// Si lo que falla es quitarla, la pantalla sigue protegida, que es lo seguro.
class ScreenSecure {
  ScreenSecure({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel(channelName),
      _enabled = enabled ?? (!kIsWeb && Platform.isAndroid);

  static const channelName = 'agrocuentas/screen_secure';

  final MethodChannel _channel;
  final bool _enabled;
  int _holders = 0;
  bool _applied = false;
  Future<void> _tail = Future<void>.value();

  /// Pantallas y diálogos que la necesitan ahora.
  int get holders => _holders;

  Future<ScreenSecureLease> acquire() async {
    _holders++;
    try {
      await _sync();
      if (_enabled && !_applied) throw const ScreenSecureUnavailable();
    } on Object {
      _holders--;
      rethrow;
    }
    return ScreenSecureLease._(this);
  }

  Future<void> _release() {
    _holders--;
    return _sync();
  }

  /// Las llamadas al canal van de una en una, en el orden pedido.
  Future<void> _sync() {
    final next = _tail.then((_) => _apply());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _apply() async {
    if (!_enabled) return;
    final wanted = _holders > 0;
    if (wanted == _applied) return;
    bool? applied;
    try {
      applied = await _channel.invokeMethod<bool>('setSecure', {
        'secure': wanted,
      });
    } on Object {
      if (wanted) throw const ScreenSecureUnavailable();
      return;
    }
    if (applied == wanted) {
      _applied = wanted;
    } else if (wanted) {
      throw const ScreenSecureUnavailable();
    }
  }
}

/// Una pantalla o un diálogo que necesita la protección. [release] se puede
/// llamar más de una vez: sólo cuenta la primera.
class ScreenSecureLease {
  ScreenSecureLease._(this._owner);

  ScreenSecure? _owner;

  Future<void> release() {
    final owner = _owner;
    _owner = null;
    return owner?._release() ?? Future<void>.value();
  }
}

/// Una sola cuenta para toda la aplicación.
final screenSecureProvider = Provider<ScreenSecure>((_) => ScreenSecure());
