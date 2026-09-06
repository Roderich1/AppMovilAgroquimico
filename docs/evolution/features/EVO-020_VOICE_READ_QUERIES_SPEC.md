# EVO-020 — Consultas de sólo lectura por voz

## Estado

`DEFERRED`. Este documento preserva la dirección futura; no autoriza implementación dentro de
la primera entrega de `EVOLUTION-3`.

## Visión

Permitir consultas como:

> “Muéstrame todas las aplicaciones del chaco Limoncitos en la campaña 2026 y el gasto total.”

La respuesta debe abrir una vista existente o un resultado tipado, con filtros visibles y
posibilidad de corregirlos. La voz no genera SQL.

## Dependencias

- `EVOLUTION-2` como fuente de modelos tipados y compositores de reporte.
- `EVO-009` y `EVO-010` verificadas.
- Catálogo explícito de consultas permitidas y sus parámetros.
- Política de privacidad para resultados sensibles en pantalla o respuesta hablada.

## Arquitectura prevista

`VoiceReadIntent` → validador de filtros → typed read/query existente → view model → pantalla.

No se permite texto libre → SQL, acceso directo a `Database`, mutaciones, predicciones ni
respuesta inventada cuando no hay datos.

## Primer catálogo candidato

- Aplicaciones por campaña/chaco/fecha/producto.
- Gasto total por campaña/chaco/producto.
- Inventario por propietario/producto.
- Estado de cuenta por persona/campaña.
- Resumen de campaña y reportes ya soportados.

## Condición para aprobar

Definir prioridades con usuarios reales, métricas de exactitud, manejo de resultados grandes,
respuesta visual/sonora, permisos y una spec por familia de consulta.

