import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_log.dart';
import 'data/installation_client_id_store.dart';
import 'domain/installation_access.dart';
import 'installation_access.dart';
import 'presentation/voice/voice_evidence_hook.dart';
import 'presentation/voice/voice_quantity_facts.dart';
import 'presentation/widgets/sync_lifecycle.dart';
import 'services/auth/existing_session_providers.dart';
import 'services/auth/existing_session_startup.dart';
import 'services/auth/first_activation_providers.dart';
import 'voice/voice_providers.dart';

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
  // Referencia de un solo sentido de la instalación (no el identificador),
  // para distinguir esta instalación de una base restaurada en otra.
  final clientId = bootstrap.identity.isReady
      ? await identityStore.read()
      : null;
  final installationRef = clientId == null
      ? null
      : installationReference(clientId);
  AppLog.info('Aplicación iniciada');
  runApp(
    ProviderScope(
      overrides: [
        installationIdentityProvider.overrideWithValue(bootstrap.identity),
        installationClientIdStoreProvider.overrideWithValue(identityStore),
        existingSessionStartupProvider.overrideWithValue(bootstrap.session),
        startupSessionScopeProvider.overrideWithValue(bootstrap.scope),
        installationRefProvider.overrideWithValue(installationRef),
        // La revisión de voz local compara cantidades con el lector de la app.
        reviewFactsProvider.overrideWithValue(voiceQuantityFacts),
        reviewFieldFactsProvider.overrideWithValue(voiceFieldFacts),
        // Evidencia de dictado (#167): sólo en una compilación de
        // evaluación (AGRO_VOICE_EVIDENCE=true), y aun así sólo con
        // consentimiento vigente.
        ...voiceEvidenceOverrides(),
      ],
      child: const SyncLifecycle(child: AgroApp()),
    ),
  );
}
