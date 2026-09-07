import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bench/bench_controller.dart';
import 'bench/bench_platform.dart';
import 'bench/corpus_catalog.dart';
import 'port/platform_transcription_port.dart';
import 'ui/bench_screen.dart';

/// Banco de pruebas de motores de voz para EVOLUTION-3.
///
/// **No es la aplicación Agrocuentas.** Es un spike descartable cuyo único
/// objetivo es medir motores de transcripción sobre teléfonos reales. No importa
/// nada del paquete `agroquimicos`, no abre SQLite, no escribe negocio y no
/// comparte `applicationId` con el producto: los sabores se instalan al lado de
/// la app sin tocarla.
///
/// ## Aquí ya no se elige el corpus
///
/// Antes esta función leía `assets/corpus.json` y se lo entregaba al
/// controlador. La pantalla mostraba un menú rotulado «Corpus» que en realidad
/// elegía la partición, y no había forma de saber desde el teléfono qué archivo
/// se estaba dictando. C1 se midió entero así.
///
/// Ahora arranca **sin corpus**: quien opera el banco elige uno, se verifica su
/// digest y sólo entonces se puede grabar.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const platform = BenchPlatform();
  final device = await platform.deviceInfo();

  final port = PlatformSpeechTranscriptionPort();
  final controller = BenchController(
    port: port,
    loader: const CorpusLoader(_loadAssetBytes),
    appVersion: '1.0.0',
    // Lo pasa la línea de construcción:
    //   flutter build apk --dart-define=BENCH_COMMIT=$(git rev-parse HEAD)
    // Vacío significa que nadie lo pasó, y así se exporta: es mejor una
    // casilla vacía que un commit inventado.
    benchCommit: const String.fromEnvironment('BENCH_COMMIT'),
    deviceInfo: device,
    memoryProbe: platform.memoryBytes,
    airplaneProbe: platform.systemAirplaneMode,
  );

  runApp(BenchApp(controller: controller, platform: platform));
}

/// Lee los bytes crudos del asset, no su texto.
///
/// El digest tiene que salir de los mismos bytes que hay en el archivo del
/// repositorio. Decodificar primero a `String` y volver a codificar dejaría el
/// resultado a merced de la normalización, y el número dejaría de poder
/// comprobarse con `sha256sum`.
Future<Uint8List> _loadAssetBytes(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class BenchApp extends StatelessWidget {
  const BenchApp({required this.controller, required this.platform, super.key});

  final BenchController controller;
  final BenchPlatform platform;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Banco de voz',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF35693E)),
      useMaterial3: true,
    ),
    home: BenchScreen(controller: controller, platform: platform),
  );
}
