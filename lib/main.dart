import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_log.dart';
import 'data/installation_client_id_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prepara el diagnóstico local antes de arrancar, para que cualquier fallo
  // durante el primer render quede registrado.
  await AppLog.init();
  // Se crea una identidad seudónima por instalación sin registrarla todavía
  // en red. Nunca se imprime el valor ni se guarda dentro de SQLite.
  await InstallationClientIdStore().getOrCreate();
  AppLog.info('Aplicación iniciada');
  runApp(const ProviderScope(child: AgroApp()));
}
