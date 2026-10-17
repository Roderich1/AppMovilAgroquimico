# F09-VOZ-02 — Arquitectura ASR seleccionada y congelada (#13)

- **Origen:** Reconstructed para la decisión (ADR-002 se aceptó el 2026-09-06) y Live para su verificación (2026-10-17, America/La_Paz).
- **Commit verificado:** `7593222` (rama `feat/f09-borrador-aplicacion`, la cima de la pila F09 #99 → #100 → #101 → #104). Base: main `ce5678f`.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). Las mediciones de motor que se citan son las del teléfono que registra ADR-002. **No hubo ninguna medición nueva.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #13. GATE-F09 (#17) sigue Pending.

## 1. Decisión vigente: no se reabre

Fuente: `docs/evolution/decisions/ADR-002-voice-transcription-engine.md`, estado `Accepted`, con los resultados de `docs/evolution/features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md`.

| Elemento | Valor |
|---|---|
| Motor productivo | Android `SpeechRecognizer`, detrás de `SpeechTranscriptionPort` (`lib/voice/port/`) |
| Reserva técnica | whisper.cpp (tiny y base `q5_1`), medida y construible en `benchmark/`. **No se distribuye** en el APK: la guarda «no se empaqueta Whisper ni ningún modelo» lo comprueba en `test/voice/voice_architecture_guard_test.dart` |
| Servicio remoto | Ninguno propio. El reconocedor del sistema puede usar la red: la interfaz lo avisa y pide consentimiento antes de cambiar a él (decisión pendiente D-F09-7) |
| Búsqueda de motores | **No se abrió ninguna nueva** (encargo F09 §3) |

## 2. Métricas por candidato (medidas por el propietario, 2026-09-06)

Teléfono: POCO X5 Pro 5G, Android 12 / API 31, en modo avión verificado. Corpus de **ajuste** completo.

| Criterio | Android | Whisper tiny | Whisper base |
|---|--:|--:|--:|
| Datos críticos correctos | 81,1 % | 57,6 % | 66,3 % |
| WER mediana | 0,167 | 0,385 | 0,300 |
| Afirma texto sobre silencio | No | Sí (`[MÚSICA]`) | `NOT_MEASURED` |
| Memoria pico | 158 MiB | 276 MiB | 328 MiB |
| Peso añadido al APK | 0 B | +41 063 516 B | +68 618 468 B |
| Latencia tras detener, p50 | 17 ms | 1228 ms | 2944 ms |
| Productos reconocidos | 5/17 | 3/16 | 3/17 |

**No medido (`NOT_MEASURED`, se conserva así):**
- falsa aceptación;
- CPU, batería y temperatura atribuidas al motor;
- silencio en Whisper base;
- ciclo de vida en el dispositivo, fuera del gate de EVO-009.

La elección **no se apoya** en ninguna preferencia no medida por Whisper o Vosk.

## 3. Dispositivos y versiones Android realmente probados

| Aparato | Qué se probó | Evidencia |
|---|---|---|
| POCO X5 Pro 5G, API 31 | Banco de motores, corpus de ajuste | ADR-002 y `EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md` |
| HONOR JDY-LX3P, API 36 | Gate físico de la captura de EVO-009 (defectos 001–005) y la revisión del locale solicitado (`es-US`) | Mensajes de los commits `ce4d1bc` y `534d6b0` del PR #8, y la revisión de ADR-002 incluida en la reconciliación (PR #99). **No hay archivo en `docs/evidence/`**; es antecedente |
| Pixel 8 / API 36 | **No ejecutado:** `WAIVED_BY_OWNER — residual compatibility risk accepted` | ADR-002 |

**Limitaciones aceptadas en ADR-002, que siguen vigentes:**
- `es-BO` no existe: no se promete;
- el modo sin conexión depende del paquete de idioma y se comprueba intentando transcribir;
- las API de disponibilidad no son garantía;
- el comportamiento depende del fabricante y de la versión;
- los productos se reconocen mal y se resuelven contra el catálogo, no en el motor.

## 4. La voz sólo produce borradores, con alternativa manual

| Condición de #13 | Dónde se cumple |
|---|---|
| Un resultado de transcripción, final o tardío, es sólo un borrador y no crea compra, aplicación ni necesidad sin confirmación | Núcleo #16 (`lib/voice_draft/core/`); `test/voice/voice_draft_no_side_effects_test.dart` y `F09-VOZ-08_flujo_borrador_voz.md` |
| Con la voz no disponible o fallando, hay una alternativa manual equivalente | Los formularios no cambian. Las pantallas de borrador confirman con el mismo caso de uso, con equivalencia de filas probada (`F09-VOZ-05.md`, `F09-VOZ-06_…` y `F09-VOZ-07_…`). El enlace desde la pantalla de voz al formulario se conecta con la integración del shell, todavía pendiente |
| Los resultados negativos y no medidos se conservan | §2 y §3 de este archivo; ADR-002 no se modifica más allá de la revisión de locale ya decidida en el PR #8 |

## 5. Pruebas sobre `7593222`

| Comando | Resultado |
|---|---|
| `flutter test test/voice_benchmark_report_test.dart` | 48 pasan |
| `cd benchmark/voice_benchmark && flutter pub get && flutter test` (incluye `speech_transcription_port_test.dart`, `bench_controller_test.dart` y `corpus_and_isolation_test.dart`) | 56 pasan |
| `flutter test test/voice/voice_architecture_guard_test.dart` (dentro de la suite completa de `7593222`: 1356 pasan, 2 omitidas) | pasa |

## 6. Límites

- Esta evidencia **no aporta mediciones nuevas** del motor. Un ensayo con dictado real está planificado en `docs/evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md` y no se ha ejecutado.
- El banco (`tool/voice_benchmark`) tiene su propio normalizador de números para medir WER. La app usa el suyo (`lib/voice_draft/text/`), porque la guarda de arquitectura prohíbe que la app dependa del banco. Son independientes a propósito.
