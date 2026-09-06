# Agrocuentas — Índice de evolución

## Propósito

`docs/evolution/` gobierna las capacidades que se incorporen después de la baseline congelada
`v1.0.0-base-stable`. No reemplaza `docs/00_INDEX.md` ni reescribe la evidencia histórica de
estabilización.

## Orden de lectura

1. `01_EVOLUTION_VISION.md`
2. `02_CURRENT_BASELINE.md`
3. `03_EVOLUTION_PRINCIPLES.md`
4. `04_TARGET_ARCHITECTURE.md`
5. `05_CAPABILITY_MAP.md`
6. `06_EVOLUTION_ROADMAP.md`
7. Estrategias `07` a `12`
8. Gobierno `13` a `17`
9. `18_SOURCE_UPDATE_POLICY.md`
10. Specs analizadas en `features/`
11. Plantillas en `templates/`

## Clasificación

| Tipo | Documentos | Autoridad |
|---|---|---|
| Contrato de partida | `02` | Normativo para toda evolución |
| Principios y arquitectura | `03`, `04` | Normativos una vez aprobada una feature |
| Estrategias | `07`–`12` | Normativas cuando el cambio toca esa materia |
| Planificación | `05`, `06`, `16` | Viva; no convierte propuestas en compromisos |
| Control | `13`–`15`, `17` | Normativo para trazabilidad y cierre |
| Fuentes de ChatGPT | `18` | Normativo para mantener contexto vigente |
| Features | `features/` | Specs; su estado controla si autorizan implementación |
| Plantillas | `templates/` | Punto de partida; se adapta sin eliminar controles aplicables |
| Decisiones | `decisions/` | Sólo ADR aceptados; su estado manda sobre recomendaciones |

## Regla de precedencia

Ante contradicciones: código de la rama analizada → tests → `docs/46_BASELINE_FINAL_FREEZE.md`
→ trazabilidad final → documentación funcional → documentación histórica. Un ADR `Accepted`
posterior puede reemplazar una decisión futura, pero nunca reescribe la baseline histórica.

## Actualización mínima por evolución

- Al analizar: `05`, `06`, `14` y `16`.
- Al aprobar: spec de feature, riesgos, dependencias y ADR si la decisión es estructural.
- Al implementar: plan, trazabilidad y migración si aplica.
- Al verificar: `15`, `16`, `17` y estado corriente de Sources.
- Al liberar: `10`, changelog/release y nuevo SHA; `02` permanece como contrato de v1.0.0.

## Estado de este paquete

Creado contra `main` = `f4c6510438991f4948fda921eec7c67fe2a2acc2`. En esta fase sólo
se añadió documentación; ninguna propuesta está `APPROVED`.
