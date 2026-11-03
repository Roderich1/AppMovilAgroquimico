# OE3: reintento tras RETRYABLE (análisis, 2026-11-03)

**Pregunta.** En la segunda tanda del POCO (`OE3_DEVICE_POCO_2_2026-11-03.md`, C28), una intención con ACK RETRYABLE/DEPENDENCY_PENDING/KEEP_FOR_RETRY no se reenvió sola en 40 s; el reenvío salió a los 73 s, al pulsar «Sincronizar ahora». ¿Es un incumplimiento?

**Respuesta: no.** Es el comportamiento diseñado, y los 40 s coinciden con la caducidad del acceso verificado. No se cambió ningún tiempo ni ninguna regla.

## Contrato

`docs/architecture/F05_SYNC_V1_RETRY_IDEMPOTENCY_MATRIX.md` (Backend), C28: RETRYABLE/DEPENDENCY_PENDING con KEEP_FOR_RETRY, y la acción «esperar ACK/GET del antecesor; no enviar el sucesor fuera de orden». **No fija un plazo de reintento.** Sólo C29 pide esperar `max(backoff + jitter, Retry-After)`.

## Mecanismo (Mobile `main` `279b46b`)

1. **`SyncWorker._handle`**, `AckOutcome.retryable`:
   - guarda `PENDING` con el código del ACK y `next_attempt_at = ahora + SyncBackoff.delay(attempts)`. Con 1 intento, el jitter está entre 0 y 2 s, con un mínimo de 1 s;
   - no detiene el ciclo: no hay `SyncBlocker`. El 429 y el 503, en cambio, devuelven `throttled`.
2. **`next_attempt_at` no programa ningún temporizador:** sólo excluye la intención de `sendable` hasta ese instante.
3. **Disparadores** (`SyncController`):
   - al iniciar o volver a primer plano;
   - tras encolar;
   - «Sincronizar ahora»;
   - un `Timer.periodic` de **1 minuto** mientras la app está en primer plano.
4. **Sin acceso verificado no hay red:** el ciclo no llama a Central y la verificación (refresh) es siempre una acción explícita (`SyncController` y `sync_access.dart`). El acceso verificado dura **10 minutos** (`SyncAccessHolder.lifetime`).

## Lo observado, explicado

| Hora (UTC) | Hecho |
|---|---|
| 18:57:28 | `refresh` 200: el acceso verificado vale hasta las 19:07:28 aproximadamente |
| 19:07:29 | Push con el RETRYABLE inyectado. La intención queda PENDING con `next_attempt_at` 19:07:29.5 |
| 19:07:29 a 19:08:42 | Los ticks periódicos encuentran el acceso caducado: por diseño, ninguna llamada de red |
| 19:08:42 | «Sincronizar ahora»: `refresh` 200 y push del mismo `operationId`, APPLIED (2 intentos) |
| 19:11:45 a 19:12:15 | Para comparar, un 503 inyectado con el acceso vigente (renovado a las 19:08:42) se reintentó solo a los 30 s, en el siguiente tick |

## Comportamiento esperado

Con un ACK RETRYABLE:
- la intención se conserva con el mismo contenido y el mismo id, sin reenvío fuera de orden;
- sale en el siguiente disparo posterior a `next_attempt_at`. Con la app en primer plano y el acceso verificado, eso ocurre a lo sumo en un minuto;
- si el acceso verificado caducó, sólo sale tras una verificación explícita («Sincronizar ahora» o «Verificar acceso en línea»).

**Límite:** con la app en segundo plano no se envía nada (no hay workers del sistema en v1).
