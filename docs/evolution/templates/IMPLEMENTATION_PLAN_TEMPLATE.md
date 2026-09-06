# Implementation Plan — `<EVO-ID>`

## Inputs and guardrails

Spec/ADR aprobados, SHA base, invariantes y non-scope.

## Change inventory

| Batch | Objetivo | Archivos | Datos | Tests | Riesgo | Criterio de salida |
|---|---|---|---|---|---|---|
| 1 | Contrato/seam |  |  |  |  |  |

## Batch rules

Cada batch debe ser pequeño, revisable, verde y no dejar schema/código incompatibles. Orden
recomendado: tests de contrato → modelo/seam → datos/migración → caso de uso → UI → integración
de plataforma → documentación/evidencia.

## Migration plan

Versiones origen/destino, preflight, anomalías, equivalencia y restore.

## Manual/device verification

Dataset, Pixel 8, pasos, logs/capturas, accesibilidad y fallos inducidos seguros.

## PR strategy

Una feature/PR cuando sea revisable; separar refactor preparatorio si tiene valor propio. No
mezclar upgrades de dependencias. Requerir CI y revisión antes de merge.

## Rollback points

Por batch: cómo retirar código/config y recuperar datos sin downgrade SQLite destructivo.

## Documentation

Spec, backlog, riesgos, ADR, release y estado de Sources que se actualizan.
