# Política de actualización de Sources de ChatGPT

## Regla principal

`02_STABLE_BASELINE.md` describe `v1.0.0-base-stable` y no debe editarse para fingir que la
baseline histórica cambió.

## Fuente nueva propuesta

Crear `07_CURRENT_EVOLUTION_STATUS.md` cuando la primera evolución llegue a `VERIFIED` o
cuando `main` deje de coincidir con la baseline. Debe incluir:

- fecha y SHA actual de `main`;
- última release/tag;
- versiones app/schema/backup;
- capacidades `APPROVED`, `IN_PROGRESS` y `VERIFIED`;
- nuevas invariantes y ADR aceptados;
- migraciones y compatibilidad;
- estado de tests/CI/dispositivo;
- riesgos/bloqueos actuales;
- enlace a las fuentes normativas del repositorio.

## Cadencia

Actualizar tras merge significativo o release, no por cada commit. Conservar snapshots
anteriores si representan una release. El índice de Sources debe distinguir: baseline
histórica, estado corriente y prompts/contratos de trabajo.

## Control de consistencia

Antes de publicar una Source: comprobar SHA/tag, no copiar estados históricos, validar IDs,
comparar schema/pubspec/backup format con código y enlazar el CI exacto.
