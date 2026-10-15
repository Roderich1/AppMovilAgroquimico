# ADR-002 — Renumeración de fases F08/F09

- **Estado:** Aceptada
- **Fecha:** 2026-10-15
- **Autor:** Roderich Rendón
- **ADR canónica:** [Agro_Sindicato_Backend-Web · docs/adr/ADR-002-renumeracion-fases.md](https://github.com/Roderich1/Agro_Sindicato_Backend-Web/blob/main/docs/adr/ADR-002-renumeracion-fases.md)

> Este archivo replica, para el repositorio móvil, la decisión de la ADR canónica del
> repositorio Backend-Web. No debe confundirse con
> [`docs/evolution/decisions/ADR-002-voice-transcription-engine.md`](../evolution/decisions/ADR-002-voice-transcription-engine.md),
> que es una decisión local distinta (motor de transcripción de voz) con la misma numeración.

## Contexto

El campo `Phase` del Project usaba `F08` para aportes, `F09` para respaldo y `PRE` para la
voz. Los aportes salen del alcance de la tesis, por lo que los códigos se reordenan para que
las fases en alcance queden consecutivas.

## Decisión

| Antes | Después | Contenido | Estado |
|---|---|---|---|
| F08 Aportes | (sin código F) | Aportes/cuotas del sindicato | Retirado del alcance de tesis (BE #30–#36 cerrados como not planned) |
| F09 Respaldo | F08 Respaldo privado | Backup remoto owner-scoped y restauración | En alcance PG 2026 |
| PRE Voz | F09 Voz (opcional) | Captura de voz → borrador sin efectos | En alcance PG 2026, prioridad reducida |
| F10, F11 | sin cambio | QA/evaluación; release y documentación | sin cambio |

## Equivalencias de identificadores

| Antes | Después |
|---|---|
| `F09-BKP-xx` (p. ej. `F09-BKP-04`, `F09-BKP-05`) | `F08-BKP-xx` |
| `GATE-F09` (respaldo) | `GATE-F08` |
| `PRE-VOICE-xx` | `F09-VOZ-xx` |
| `GATE-PRE` | `GATE-F09` |
| `F08-APO-xx` | `[RETIRADO][APO-xx]` |
| `GATE-F08` (aportes) | `[RETIRADO][GATE-APO]` |
| `PRE-VOICE/EVO` | `F09-VOZ/EVO` |
| Clase de retención `R_BACKUP_F09` | `R_BACKUP_F08` |

No existe `F09-VOZ-04`.

Un mismo código cambia de significado según la fecha: antes de 2026-10-15, `F08` y
`GATE-F08` se refieren a aportes y `F09`/`GATE-F09` a respaldo; desde esta fecha, `F08` es
respaldo y `F09` es voz. Ante una referencia ambigua en un documento anterior, prevalece su
fecha.

## Consecuencias

- Las referencias nuevas usan los códigos de la columna «Después».
- Los registros históricos fechados conservan los códigos con los que se escribieron.
- La trazabilidad de requisitos usa solo IDs del Cap. III v1.5: F08 Respaldo privado cubre
  RF-26, RF-27 y RNF-10 (CU-14, CU-15); F09 Voz cubre RF-28 y RF-29 (CU-16). El Cap. III v1.5
  no contiene requisitos de aportes.
