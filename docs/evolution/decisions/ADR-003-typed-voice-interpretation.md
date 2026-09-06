# ADR-003 — Frontera tipada para interpretación de voz

- Estado: `Accepted`.
- Fecha: 2026-09-06.

## Contexto

La transcripción puede equivocarse y las operaciones afectan inventario, FIFO y cuentas. Un
modelo, reglas o servicio externo no debe ejecutar SQL ni construir escrituras arbitrarias.

## Decisión

Toda interpretación produce una de un conjunto cerrado de intenciones y un borrador tipado con
estado por campo. Validadores deterministas aplican reglas de completitud, resolución y
dominio. La confirmación táctil convierte el draft válido al caso de uso existente.

El clasificador/extractor puede empezar con reglas y evolucionar a un enfoque híbrido detrás de
puertos. Cambiar el motor no cambia DTOs, validadores ni política de confirmación.

## Reglas no negociables

- No generar ni ejecutar SQL desde lenguaje natural.
- No permitir que STT/NLU importe repositorios de escritura.
- No autoelegir entidades críticas ambiguas.
- No usar confianza probabilística como validación de negocio.
- No persistir audio/transcripción por defecto.
- No ejecutar por confirmación de voz en EVOLUTION-3.

## Consecuencias

- Más tipos y adaptadores, a cambio de pruebas reproducibles y reemplazo del motor.
- Cada nueva intención requiere ID, spec, draft, validator y trazabilidad.
- Las consultas futuras reutilizan typed reads de EVOLUTION-2.
- Un LLM remoto, si se propone, requiere otro ADR de privacidad/seguridad y sigue sujeto a esta
  frontera.

