import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prepara el diagnóstico local antes de arrancar, para que cualquier fallo
  // durante el primer render quede registrado.
  await AppLog.init();
  AppLog.info('Aplicación iniciada');
  runApp(const ProviderScope(child: AgroApp()));
}
