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
