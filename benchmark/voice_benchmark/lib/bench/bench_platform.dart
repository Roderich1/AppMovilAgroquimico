import 'package:flutter/services.dart';

import 'bench_controller.dart';

/// Servicios del aparato que el banco necesita y que **no** son transcripción:
/// identidad del equipo, memoria del proceso y carpeta de exportación.
///
/// Vive fuera de `SpeechTranscriptionPort` a propósito. El puerto es el contrato
/// que heredará `EVO-009`; meterle `getExternalFilesDir` lo ensuciaría con algo
/// que no tiene nada que ver con transcribir.
final class BenchPlatform {
  const BenchPlatform([this._channel = const MethodChannel(channelName)]);

  static const channelName = 'agro.voicebench/platform';

  final MethodChannel _channel;

  Future<DeviceInfo> deviceInfo() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
      if (map == null) return DeviceInfo.unknown;
      return DeviceInfo(
        device: map['device'] as String? ?? 'desconocido',
        androidRelease: map['androidRelease'] as String? ?? 'desconocido',
        androidSdk: map['androidSdk'] as int? ?? 0,
        abi: map['abi'] as String? ?? 'desconocida',
      );
    } on PlatformException {
      return DeviceInfo.unknown;
    } on MissingPluginException {
      return DeviceInfo.unknown;
    }
  }

  /// Memoria usada por el proceso, en bytes. `null` cuando no se puede leer: el
  /// informe debe decir `NOT_MEASURED`, no una cifra inventada.
  Future<int?> memoryBytes() async {
    try {
      final value = await _channel.invokeMethod<Object?>('memory');
      return value is int ? value : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Modo avión leído del sistema. `null` si no se pudo consultar.
  ///
  /// Existe para contrastar lo que el operador declara con lo que el teléfono
  /// dice. Sin esto, «funciona sin Internet» descansa en que nadie se olvide de
  /// apagar la radio.
  Future<bool?> systemAirplaneMode() async {
    try {
      final value = await _channel.invokeMethod<Object?>('airplaneMode');
      return value is bool ? value : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Carpeta donde dejar los archivos exportados, visible por USB/MTP.
  Future<String?> exportDirectory() async {
    try {
      return await _channel.invokeMethod<String>('exportDir');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
