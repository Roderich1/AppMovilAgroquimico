import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_log.dart';
import 'data/installation_identity_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prepara el diagnóstico local antes de arrancar, para que cualquier fallo
  // durante el primer render quede registrado.
  await AppLog.init();
  // La identidad seudónima es auxiliar: una corrupción se registra sin
  // revelar su valor y no bloquea el dominio SQLite local.
  final identity = await bootstrapWithInstallationIdentity(
    continueStartup: () {
      AppLog.info('Aplicación iniciada');
      runApp(const ProviderScope(child: AgroApp()));
    },
  );
  AppLog.info('Estado de identidad: ${identity.status.name}');
}
