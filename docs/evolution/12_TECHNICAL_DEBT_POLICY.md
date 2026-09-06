# Política de deuda técnica

## Clases

| Clase | Acción |
|---|---|
| BLOCKING | Resolver antes de la feature que vuelve insegura |
| OPPORTUNISTIC | Resolver sólo en el área tocada |
| DEFERRED | Registrar trigger; no distraer el roadmap |
| INTENTIONAL | Decisión consciente con razón y fecha de revisión |

## Registro inicial

| Deuda | Clase | Trigger |
|---|---|---|
| Lecturas `Map<String,Object?>` | OPPORTUNISTIC | Nueva UI/exportación sobre esa query |
| `AgroRepository` grande | OPPORTUNISTIC | Nueva responsabilidad o conflicto frecuente |
| Motor FIFO dentro del repositorio | BLOCKING para nuevo consumidor | Otra feature mueve/consume stock |
| `FutureBuilder` en widgets stateless | DEFERRED | Recargas dobles o costo medido |
| Naming histórico `agroquimicos` | INTENTIONAL | Preparación de distribución/branding |
| Campos legacy en `transfers` | DEFERRED | Nueva query o migración de transferencias |
| Estado simple con Riverpod sólo DI | INTENTIONAL | Estado reactivo transversal demostrado |
| iOS/web no verificados | INTENTIONAL | Decisión de soportar otra plataforma |
| Dependencias potencialmente sin uso | DEFERRED | Mantenimiento programado de paquetes |
| `main` sin protección | BLOCKING para trabajo colaborativo | Antes de integrar evoluciones concurrentes |

## Reglas

- No convertir auditorías históricas en backlog vigente sin comprobar código actual.
- No mezclar limpieza amplia con una feature salvo bloqueo real.
- Toda deuda tiene evidencia, impacto, trigger y criterio de cierre.
- Borrar código legacy sólo tras buscar consumidores y conservar regresión.
- Actualizar clasificación cuando el contexto cambie.
