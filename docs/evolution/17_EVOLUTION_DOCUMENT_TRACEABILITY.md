# Trazabilidad documental

| Documento | Propósito | Fuentes principales | Cuándo se actualiza | Owner lógico |
|---|---|---|---|---|
| 00 Index | Navegación/autoridad | paquete completo | Alta/baja de documento | Architecture |
| 01 Vision | Límites y resultado | contexto propietario | Cambio de visión | Product |
| 02 Baseline | Contrato v1.0.0 | código, tests, doc 46, GitHub | No reescribir; nueva baseline aparte | Release |
| 03 Principles | Guardrails | baseline/invariantes | Cambio de política | Architecture |
| 04 Target Architecture | Dirección incremental | `lib/`, auditorías | Boundary/ADR aceptado | Architecture |
| 05 Capability Map | Estado de capacidades | producto/código | Capacidad cambia de clase | Product/Architecture |
| 06 Roadmap | Orden por dependencia | mapa/riesgos | Repriorización aprobada | Product |
| 07 Data | Migración/backup | AppDatabase/tests | Cambio de persistencia | Data |
| 08 Testing | Evidencia por riesgo | test/CI/auditoría | Nueva clase de riesgo | QA |
| 09 Security | Activos y controles | manifest/storage/auditoría | Nueva superficie | Security |
| 10 Release | Versiones y gates | CI/pubspec/Android | Política/release | Release |
| 11 Observability | Logging/telemetría | AppLog | Nueva telemetría | Operations |
| 12 Debt | Clasificación/triggers | auditorías/código | Trigger o cierre | Architecture |
| 13 Traceability | IDs/cadena | prácticas del proyecto | Convención cambia | QA/Architecture |
| 14 Risks | Riesgo/mitigación | todo lo anterior | Cada análisis/cierre | Risk owner |
| 15 DoD | Cierre verificable | quality gates | Nuevo gate | QA/Release |
| 16 Backlog | Trabajo futuro | decisiones/specs | Todo cambio de estado | Product |
| 17 Traceability docs | Gobernar este paquete | índice/archivos | Alta/baja/owner | Architecture |
| 18 Source policy | Contexto ChatGPT | Sources/baselines | Evolución significativa | Documentation |
| features | Especificación por capacidad | backlog/decisiones | Ciclo de la feature | Feature owner |
| templates | Normalizar trabajo | estrategias/DoD | Control faltante repetido | Architecture/QA |
| decisions | Decisiones aceptadas | ADR | Decisión/supersession | Decision owner |

## Paquete EVOLUTION-3

| Documento | Propósito | Estado |
|---|---|---|
| `features/EVOLUTION-3_VOICE_VISION_AND_SCOPE.md` | Visión, alcance y orden aprobado | APPROVED |
| `features/EVOLUTION-2_FINAL_VERIFICATION.md` | Cierre aceptado de typed reads/reportes | VERIFIED |
| `features/EVO-009_SAFE_VOICE_SPEC.md` | Captura/transcripción segura | APPROVED |
| `features/EVO-010_TYPED_VOICE_INTERPRETATION_SPEC.md` | Intenciones, resolución y drafts | APPROVED |
| `features/EVO-017_VOICE_PURCHASE_DRAFT_SPEC.md` | Compra por voz | APPROVED |
| `features/EVO-018_VOICE_PLAN_APPLICATION_DRAFT_SPEC.md` | Aplicación planificada por voz | APPROVED |
| `features/EVO-019_VOICE_PAYMENT_DRAFT_SPEC.md` | Pago por voz | APPROVED |
| `features/EVO-020_VOICE_READ_QUERIES_SPEC.md` | Dirección futura de consultas | DEFERRED |
| `features/EVOLUTION-3_SECURITY_AND_CONFIRMATION_POLICY.md` | Privacidad y no autoejecución | APPROVED |
| `features/EVOLUTION-3_VOICE_GRAMMAR_AND_EXAMPLES.md` | Corpus y lenguaje funcional | APPROVED |
| `features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_PLAN.md` | Selección con evidencia | REQUIRED |
| `features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md` | Evidencia medida en teléfono real y lo que sigue sin medirse | MEASURED_ON_ONE_DEVICE |
| `features/EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md` | Cómo ejecuta el propietario la prueba en teléfonos | EJECUTADO en API 31; reutilizable como regresión |
| `features/EVOLUTION-3_OWNER_DEVICE_TEST_RESULTS_TEMPLATE.md` | Cómo devuelve el propietario los resultados | Plantilla |
| `features/EVOLUTION-3_IMPLEMENTATION_PLAN.md` | PRs, gates y secuencia | APPROVED |
| `features/EVOLUTION-3_TRACEABILITY_MATRIX.md` | Requisito a evidencia | APPROVED |
| `decisions/ADR-002-voice-transcription-engine.md` | Motor decidido, waiver del gate Pixel 8 y política productiva de `EVO-009` | **Accepted** |
| `decisions/ADR-003-typed-voice-interpretation.md` | Frontera segura | Accepted |

## Paquete de la Fase 0-bis (motor híbrido local)

Incorporado el 2026-09-07 tras el gate físico en HONOR API 36 (`RISK-029`). No sustituye
nada del paquete anterior: `ADR-002` y sus resultados siguen siendo evidencia válida.

| Documento | Propósito | Estado |
|---|---|---|
| `decisions/ADR-004-hybrid-embedded-voice-engine.md` | Motor local propio, independiente de los modelos del fabricante | **Proposed** |
| `features/EVOLUTION-3_HYBRID_ENGINE_BENCHMARK_PLAN.md` | Cómo se mide el híbrido y contra qué | PROPOSED |
| `features/EVOLUTION-3_MODEL_DISTRIBUTION_SECURITY_SPEC.md` | Manifest, instalación atómica, privacidad y supply chain de los modelos | PROPOSED |
| `features/EVOLUTION-3_HYBRID_ACCEPTANCE_MATRIX.md` | Umbrales y guardrails binarios por dispositivo | PENDING: ninguna métrica medida |
| `features/EVO-009_HYBRID_ENGINE_MIGRATION_PLAN.md` | Cómo pasaría `EVO-009` al híbrido sin perder lo hecho | PROPOSED, condicionado a `ADR-004` |
| `features/EVOLUTION-3_HYBRID_16KB_GATE_EVIDENCE.md` | Gate de páginas de 16 KB ejecutado de verdad, no sólo comprobado en el ELF | Ejecutado para C1 y C3; C4 pendiente |
| `features/EVOLUTION-3_HYBRID_OWNER_DEVICE_TEST_PLAN.md` | Cómo dictar el corpus A–G frase por frase, y qué no hacer | Listo para ejecutar |

`features/EVO-009_IMPLEMENTATION_TRACEABILITY.md` también debe recibir esta revisión, pero
vive únicamente en la PR #8, que está **congelada** durante la Fase 0-bis. Se actualiza en la
fase P3 del plan de migración, cuando esa rama vuelva a moverse.


## Herramientas de la Fase 0

No son documentos, pero forman parte de la trazabilidad del benchmark:

| Ruta | Qué es | Se borra |
|---|---|---|
| `benchmark/voice_benchmark/` | Banco de pruebas: puerto, dos motores, corpus y tres APK | Eliminando la carpeta |
| `benchmark/voice_benchmark/assets/corpus.json` | Corpus de 100 frases, ajuste y aceptación | Con la carpeta |
| `benchmark/voice_benchmark/THIRD_PARTY.md` | Licencias, versiones, hashes y tamaños medidos | Con la carpeta |
| `benchmark/voice_benchmark/tool/fetch_vosk_model.sh` | Descarga y verifica el modelo español de Vosk | Con la carpeta |
| `tool/voice_benchmark/` | Agregador de resultados y su informe comparativo | Eliminando la carpeta |
| `test/voice_benchmark_report_test.dart` | Pruebas del agregador, en la suite del proyecto | Con el agregador |
| `artifacts/voice-benchmark/results/` | Archivos exportados por el teléfono (no versionados) | Con la carpeta |

## Evidencia de creación

Este conjunto se derivó de las fuentes del Proyecto ChatGPT, `main` y el tag congelado, los 46
documentos históricos, `lib/`, `test/`, configuración de plataforma y CI. La precedencia evita
promover cifras históricas (schema v4/v5, 91/170 tests o backup `.db`) a estado actual.
