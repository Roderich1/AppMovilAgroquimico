# Estrategia de observabilidad

## Tres capacidades distintas

| Capacidad | Propósito | Estado |
|---|---|---|
| Diagnóstico local | Investigar fallos sin red | Existe `AppLog`, mejorable |
| Crash reporting | Recibir excepciones remotas | No existe; decisión futura |
| Analytics | Entender uso/comportamiento | No existe; decisión futura |

No se introduce telemetría cloud implícitamente.

## Diagnóstico local objetivo

- Eventos con timestamp, severidad, subsistema, operación/trace ID y código estable.
- Sin fotos, audio, tokens ni datos personales innecesarios.
- Rotación/tamaño máximo y borrado controlado.
- Exportación explícita por el usuario, separada del backup operativo.
- Mensajes técnicos en log; mensajes seguros y accionables en UI.

## Eventos críticos sugeridos

Apertura/migración, backup/restore, fallo de integridad, operación transaccional fallida,
plugin no disponible y degradación de servicio externo. No registrar cada monto o fila.

## Servicios futuros

Crash reporting o analytics requiere ADR/decisión de producto, consentimiento cuando aplique,
política de retención y modo offline. Una caída de observabilidad nunca bloquea una operación.

## Correlación

Si voz/cloud se aprueba, usar un ID local efímero para enlazar captura → intención →
confirmación → resultado, sin convertir la transcripción completa en log permanente.
