/// Proveedores de la evidencia de dictado (F09-VOZ-13, MOB #167).
///
/// - [voiceEvidenceStoreProvider]: el almacén SQLite, para gestionar el
///   consentimiento, leer la evidencia y borrarla.
/// - [voiceEvidenceSinkProvider]: el sumidero que usan las pantallas al
///   terminar un borrador. **Por defecto es nulo** y no guarda nada. Para
///   recoger evidencia en una compilación de evaluación, se sobrescribe con
///   [voiceEvidenceStoreProvider]; aun así, sin consentimiento vigente el
///   almacén no guarda nada.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart' show databaseProvider;
import 'voice_evidence.dart';
import 'voice_evidence_store.dart';

final voiceEvidenceStoreProvider = Provider<VoiceEvidenceStore>(
  (ref) => VoiceEvidenceStore(ref.watch(databaseProvider)),
);

final voiceEvidenceSinkProvider = Provider<VoiceEvidenceSink>(
  (ref) => const NullVoiceEvidenceSink(),
);

/// Sobrescritura para activar la recogida (con consentimiento) en la app:
/// `ProviderScope(overrides: [recordVoiceEvidenceOverride], …)`.
final recordVoiceEvidenceOverride = voiceEvidenceSinkProvider.overrideWith(
  (ref) => ref.watch(voiceEvidenceStoreProvider),
);
