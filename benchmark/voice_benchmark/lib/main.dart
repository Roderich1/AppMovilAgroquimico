import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bench/bench_controller.dart';
import 'bench/bench_platform.dart';
import 'bench/corpus.dart';
import 'port/platform_transcription_port.dart';
import 'ui/bench_screen.dart';

/// Banco de pruebas de motores de voz para EVOLUTION-3 Fase 0.
///
/// **No es la aplicación Agrocuentas.** Es un spike descartable cuyo único
/// objetivo es medir motores de transcripción sobre teléfonos reales. No importa
/// nada del paquete `agroquimicos`, no abre SQLite, no escribe negocio y no
/// comparte `applicationId` con el producto: los tres sabores se instalan al
/// lado de la app sin tocarla.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final source = await rootBundle.loadString('assets/corpus.json');
  final corpus = Corpus.fromJsonString(source);

  const platform = BenchPlatform();
  final device = await platform.deviceInfo();

  final port = PlatformSpeechTranscriptionPort();
  final controller = BenchController(
    port: port,
    corpus: corpus,
    appVersion: '1.0.0',
    deviceInfo: device,
    memoryProbe: platform.memoryBytes,
  );

  runApp(BenchApp(controller: controller, platform: platform));
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
