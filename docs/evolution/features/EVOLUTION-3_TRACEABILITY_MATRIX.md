# EVOLUTION-3 — Matriz de trazabilidad inicial

Estado documental: `APPROVED`; evidencia de implementación: pendiente.

| Requisito/capacidad | Diseño/autoridad | Evidencia mínima para cierre |
|---|---|---|
| Captura, permiso y lifecycle | `EVO-009`, ADR-002 | unit/widget/device, modo avión e interrupciones |
| Sesión continua y preview editable | `EVO-009` | corpus + widget + Pixel 8 |
| Intención y draft tipado | `EVO-010`, ADR-003 | corpus separado, unit y paridad |
| Ambigüedad bloqueante | `EVO-010`, política de confirmación | homónimos, aliases, baja confianza |
| Compra por voz | `EVO-017` | repository atomicity + paridad UI/inventario |
| Crear catálogo + compra atómica | `EVO-017` | fallo inducido en cada paso, base sin diff |
| Aplicar plan por voz | `EVO-018` | planes 0/1/N, FIFO, stock, one-shot |
| Pago por voz | `EVO-019` | saldos, excedente/adelanto, homónimos |
| Cero escritura preconfirmación | Política + todos los specs | spy/repository/database snapshot |
| Privacidad de audio/texto | Política + ADR-002 | inspección de storage/logs y lifecycle |
| Performance/offline | Plan de benchmark | resultados versionados en dos dispositivos |
| Motor de transcripción elegido | `ADR-002`, plan de benchmark | Banco construido y medido sin dispositivo; **falta** la evidencia de Pixel 8 y de un equipo de gama baja |
| Consultas futuras | `EVO-020` | No aplica; estado `DEFERRED` |

## Registro de implementación a completar por PR

| Feature | Rama | PR | SHA final | CI | Device | Estado |
|---|---|---|---|---|---|---|
| Fase 0 · benchmark | `evolution/evolution-3-voice-benchmark` | Ver informe de la rama | Ver informe de la rama | Ver informe de la rama | **Pendiente**: sólo emulador | `WAITING_FOR_OWNER_DEVICE_TESTS` |
| EVO-009 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-010 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-017 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-018 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-019 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |

No sustituir `Pendiente` por evidencia supuesta. Un merge sin run/dispositivo no completa la
fila.

La Fase 0 no implementa ninguna feature: construye el instrumento con el que se decide
`ADR-002`. Por eso aparece como fila propia y ningún `EVO-*` cambió de estado.

## Evidencia de la Fase 0

| Requisito de la fase | Dónde está |
|---|---|
| Puerto `SpeechTranscriptionPort` y su contrato | `benchmark/voice_benchmark/lib/port/` |
| Fake determinista | `benchmark/voice_benchmark/lib/port/fake_transcription_port.dart` |
| Adaptador del motor de Android | `benchmark/voice_benchmark/android/app/src/androidSpeech/` |
| Adaptador de `whisper.cpp` | `benchmark/voice_benchmark/android/app/src/whisperCommon/` |
| Corpus de 100 frases, ajuste y aceptación | `benchmark/voice_benchmark/assets/corpus.json` |
| Pruebas del puerto, ciclo de vida y privacidad | `benchmark/voice_benchmark/test/` |
| Agregador de resultados y sus pruebas | `tool/voice_benchmark/`, `test/voice_benchmark_report_test.dart` |
| Licencias, versiones, hashes y tamaños | `benchmark/voice_benchmark/THIRD_PARTY.md` |
| Resultados y limitaciones | `EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md` |
| Instrucciones para el propietario | `EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md` |
| Plantilla de devolución | `EVOLUTION-3_OWNER_DEVICE_TEST_RESULTS_TEMPLATE.md` |

