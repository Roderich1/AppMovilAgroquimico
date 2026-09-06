# Feature Evolution Spec — `<EVO-ID> <Nombre>`

## Identity

| Campo | Valor |
|---|---|
| Feature ID | `EVO-___` |
| Owner decision | fecha/evidencia o `PENDING` |
| Status | `PROPOSED` |
| Target release | sin fecha inventada |
| Owners lógicos | Product / Domain / Data / QA / Security |

## Problem

Problema observable, usuario afectado y evidencia. No describir primero la solución.

## User Value

Resultado medible para el usuario.

## Scope

- Incluido.

## Non-Scope

- Excluido explícitamente.

## User Flows

Precondición → pasos → resultado; incluir cancelar, reintentar y volver atrás.

## Functional Requirements

| ID | Requisito | Prioridad | Evidencia |
|---|---|---|---|
| `EVO-___-REQ-01` |  |  |  |

## Business Rules

Reglas existentes que se preservan y reglas nuevas con ID.

## Data Changes

Tablas/columnas/índices/volumen/anomalías. Escribir `None` si no aplica.

## Architecture

Componentes y boundaries; justificar interfaces nuevas.

## Interfaces

Comandos, queries, DTOs, plugins o endpoints; errores y versionado.

## UI/UX

Estados loading/empty/error/success/disabled, accesibilidad, teclado, scroll y back.

## Error Handling

Fallo → mensaje → efectos → reintento/recuperación.

## Security

Activos, permisos, threat changes, secretos, retención y consentimiento.

## Offline Behaviour

Qué funciona sin red y cómo se degrada.

## Backup Impact

Compatibilidad de exportación/restauración y matriz de versiones.

## Migration

`MIG-*`, forward path, anomalías, equivalencia y preflight.

## Tests

Happy, invalid, boundary, atomicity, failure, recovery, regression y volumen.

## Device Verification

Entorno, escenarios, evidencia y criterios.

## Telemetry/Logging

Eventos locales/remotos, campos permitidos y redacción.

## Risks

`RISK-*`, probabilidad, impacto, mitigación y residual.

## Rollback

Código, datos, configuración y servicio externo.

## Traceability

REQ/BR/ADR/MIG → cambio → test → CI/device → docs.

## Acceptance Criteria

- [ ] Dado/cuando/entonces verificable.

## Definition of Done

Aplicar `../15_DEFINITION_OF_DONE.md` y listar excepciones aprobadas.
