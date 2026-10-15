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
| `PRE-VOICE-xx` | `F09-VOZ-xx` |
| `GATE-PRE` | `GATE-F09` |
| `F09-BKP-04` | `F08-BKP-04` |
| `F09-BKP-05` | `F08-BKP-05` |

No existe `F09-VOZ-04`.

## Consecuencias

- Las referencias nuevas usan los códigos de la columna «Después».
- Los registros históricos fechados conservan los códigos con los que se escribieron.
- La trazabilidad de requisitos usa solo IDs del Cap. III v1.5 (p. ej. respaldo: RF-26,
  RF-27, RNF-10; voz: RF-28, RF-29).
