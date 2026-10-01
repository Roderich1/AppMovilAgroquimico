import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_log.dart';
import 'data/installation_client_id_store.dart';
import 'services/auth/existing_session_providers.dart';
import 'services/auth/existing_session_startup.dart';
import 'services/auth/first_activation_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prepara el diagnóstico local antes de arrancar, para que cualquier fallo
  // durante el primer render quede registrado.
  await AppLog.init();
  // La identidad seudónima es auxiliar: una corrupción se registra sin
  // revelar su valor y no bloquea el dominio SQLite local.
  final identityStore = InstallationClientIdStore();
  final bootstrap = await bootstrapExistingSession(
    identityStore: identityStore,
  );
  AppLog.info('Estado de identidad: ${bootstrap.identity.status.name}');
  AppLog.info('Estado de vinculación local: ${bootstrap.session.name}');
  AppLog.info('Aplicación iniciada');
  runApp(
    ProviderScope(
      overrides: [
        installationIdentityProvider.overrideWithValue(bootstrap.identity),
        installationClientIdStoreProvider.overrideWithValue(identityStore),
        existingSessionStartupProvider.overrideWithValue(bootstrap.session),
      ],
      child: const AgroApp(),
    ),
  );
}
