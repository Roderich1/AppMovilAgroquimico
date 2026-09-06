# Agrocuentas — Índice de evolución

## Propósito

`docs/evolution/` gobierna las capacidades incorporadas después de la baseline congelada
`v1.0.0-base-stable`. No reemplaza `docs/00_INDEX.md` ni reescribe evidencia histórica.

## Identidad de estado

| Elemento | Valor |
|---|---|
| Baseline funcional inmutable | `f4c6510438991f4948fda921eec7c67fe2a2acc2` |
| Tag | `v1.0.0-base-stable` |
| Fundación documental en `main` | `bdd7b82f3e06d9943749a571284db8f94194c3b3` |
| Diferencia funcional entre ambos | Ninguna; el commit posterior sólo añade documentación |

## Dos niveles de identificadores

- `EVOLUTION-N`: etapa del roadmap que agrupa capacidades relacionadas.
- `EVO-NNN`: ítem único y estable del backlog.

No son intercambiables. `EVOLUTION-2` agrupa `EVO-004`, `EVO-005` y `EVO-006`.
`EVOLUTION-3` implementará únicamente `EVO-009`.

## Orden de lectura

1. `01_EVOLUTION_VISION.md`
2. `02_CURRENT_BASELINE.md`
3. `03_EVOLUTION_PRINCIPLES.md`
4. `04_TARGET_ARCHITECTURE.md`
5. `05_CAPABILITY_MAP.md`
6. `06_EVOLUTION_ROADMAP.md`
7. Estrategias `07` a `12`
8. Gobierno `13` a `18`
9. Specs y planes en `features/`
10. Plantillas en `templates/`
11. ADR aceptados en `decisions/`

## Registro de features

| Alcance | IDs | Documento | Estado |
|---|---|---|---|
| Compartir backup | `EVO-001` | `features/EVO-001_SHARE_BACKUP_SPEC.md` | `DEFERRED` |
| Typed reads + reportes | `EVO-004/005/006` | `features/EVOLUTION-2_TYPED_READS_AND_REPORT_EXPORT_SPEC.md` | `IN_PROGRESS` |
| Plan de EVOLUTION-2 | `EVO-004/005/006` | `features/EVOLUTION-2_IMPLEMENTATION_PLAN.md` | `IN_PROGRESS` |
| Trazabilidad de EVOLUTION-2 | `EVO-004/005/006` | `features/EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md` | `IN_PROGRESS`, gates pendientes declarados |
| Voz segura | `EVO-009` | `features/EVO-009_SAFE_VOICE_SPEC.md` | `APPROVED`, depende de EVOLUTION-2 verificada |
| Plan de voz segura | `EVO-009` | `features/EVO-009_SAFE_VOICE_IMPLEMENTATION_PLAN.md` | `APPROVED`, no iniciar todavía |

Los documentos `FINAL_VERIFICATION` sólo se crean después de implementar y reunir evidencia
real de tests, CI y dispositivo. Su ausencia antes de esa fase es correcta.

`EVOLUTION-2` está implementada en `evolution/evolution-2-typed-reports`, con los cuatro gates
locales en verde y el CI del SHA final `2b40955` en verde (run `34014442336`). Sigue en
`IN_PROGRESS` y sin `EVOLUTION-2_FINAL_VERIFICATION.md` porque falta la verificación en
Pixel 8, detallada en la trazabilidad, §8.

## Precedencia

Ante contradicciones: código de la rama analizada → tests → `docs/46_BASELINE_FINAL_FREEZE.md`
→ documentación final de evolución → documentación funcional → documentación histórica.

## Decisión vigente del propietario

1. Implementar primero `EVOLUTION-2` (`EVO-004`, `EVO-005`, `EVO-006`).
2. Integrarla únicamente con gates verdes y evidencia honesta.
3. Implementar después `EVOLUTION-3`, limitada a `EVO-009`.
4. `EVO-010`, comandos de voz, permanece `DEFERRED` y fuera de alcance.

