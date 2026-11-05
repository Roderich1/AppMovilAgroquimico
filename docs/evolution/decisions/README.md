# Architectural Decision Records

Aquí viven sólo decisiones estructurales importantes. Una recomendación o candidato no es un
ADR aceptado.

## Estados

`Proposed`, `Accepted`, `Superseded`, `Rejected`.

## Cuándo crear uno

Backend/sync, identidad, voz local vs cloud, cifrado/persistencia, nueva plataforma,
observabilidad remota o cambio contable/arquitectónico difícil de revertir.

## Formato

`ADR-NNN-titulo-corto.md`: contexto, decisión, alternativas, consecuencias, seguridad/datos,
compatibilidad, rollback, evidencia y estado. Un ADR posterior puede reemplazar otro mediante
`Superseded by`, sin borrar el anterior.

## Aceptados

| ADR | Título | Alcance | Estado |
|---|---|---|---|
| [`ADR-001`](ADR-001-generacion-pdf-sin-dependencia.md) | Generar el PDF sin la dependencia `pdf` | `EVO-006` | `Accepted` |
| [`ADR-003`](ADR-003-typed-voice-interpretation.md) | Frontera tipada para interpretación de voz | `EVOLUTION-3` | `Accepted` |

## Propuestos

| ADR | Título | Alcance | Estado |
|---|---|---|---|
| [`ADR-002`](ADR-002-voice-transcription-engine.md) | Motor de transcripción tras benchmark | `EVO-009` | **`Accepted`** (2026-09-06) — Android `SpeechRecognizer`; Whisper como reserva no distribuida; gate Pixel 8 `WAIVED_BY_OWNER` |
| [`ADR-005`](ADR-005-local-voice-vosk-whisper.md) | Voz local: Vosk en vivo y segunda pasada whisper.cpp | `EVO-009` (#13, #165, #166) | **`Accepted` provisionalmente, sólo para la demostración** (2026-11-05). Whisper base y no small, por fluidez; quedan pendientes small, el teléfono y #12 |

Un ADR `Proposed` no autoriza la dependencia que evalúa. Al resolver ADR-002 deben registrarse
el benchmark, versiones y consecuencias; no se reescribe la evidencia anterior.
