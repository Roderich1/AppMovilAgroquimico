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

## Evidencia de creación

Este conjunto se derivó de las fuentes del Proyecto ChatGPT, `main` y el tag congelado, los 46
documentos históricos, `lib/`, `test/`, configuración de plataforma y CI. La precedencia evita
promover cifras históricas (schema v4/v5, 91/170 tests o backup `.db`) a estado actual.
