# Evidencia F05-SYNC-03 — Worker de retry/backoff y estados de sincronización

Issue [#31](https://github.com/Roderich1/AppMovilAgroquimico/issues/31). El detalle (tabla de respuestas, mutaciones y discrepancias) está en [F05_MOBILE_SYNC](../../evidence/F05_MOBILE_SYNC.md). Ejecutado con Claude Code el 2026-10-15 sobre `30c04b63a43dbd610414d81e58b2e5ad556a3dbe` (base `main` `3eecb2d`), en host y sin dispositivo: el transporte es un `MockClient`.

**IMPLEMENTATION_DECISION** (contrato F05 §11, Mobile #31):
- backoff exponencial con jitter completo;
- base 2 s, ×2 por intento, tope 15 min y mínimo 1 s;
- `max(backoff, Retry-After)`, con `Retry-After` en segundos o como fecha HTTP;
- presupuesto de 20 intentos por ciclo;
- el próximo intento se guarda en la base y sobrevive a reinicios.

| Criterio | Prueba (`test/sync_retry_worker_test.dart`) | Resultado |
| --- | --- | --- |
| Fallo temporal (sin red, timeout, 5xx): sigue pendiente, backoff creciente acotado y sin tocar los datos | «timeout», «error de red», «500», «503 cerrado», «429 con Retry-After», «backoff: crece, se acota…» | PASS |
| Autorización inválida: requiere intervención, sin bucle ni falso «sincronizado» | «401: vuelve a la cola, se descarta el token y no hay bucle»; «403: toda la cola del titular queda pausada» | PASS |
| Rechazo o conflicto: «rechazada» o «en conflicto», conservando la información local | «REJECTED: código visible, sin reintento…»; «400/413/415»; «CONFLICT: visible…» | PASS |
| Sólo una aceptación del servidor marca «sincronizada» | «APPLIED», «ALREADY_APPLIED»; «ACK incoherente (otro operationId, sin hora, vacío, 2xx genérico)» → `OUTCOME_UNKNOWN` | PASS |
| Respuesta perdida: reenvía la misma operación y no marca éxito antes de confirmar | «timeout: … envía exactamente lo mismo»; «cierre forzado durante el envío…»; `sync_simulated_central_test.dart` (ACK perdido tras el commit) | PASS |
| Estados distinguibles para el agricultor | `sync_screens_test.dart` «estado de sincronización: estados distinguibles…»; indicador en el shell | PASS |

Además: orden causal, sin acceso no hay llamadas de red, otra cuenta no publica, restauración pausada, versión incompatible (422) y una reencolada no se reescribe. Son mutaciones M01–M21 en F05_MOBILE_SYNC §3.

Comandos: `flutter test test/sync_retry_worker_test.dart` y `flutter test` (947/947).

El E2E en el POCO contra el Backend real queda **NOT_MEASURED**: un test automatizado no sustituye DEVICE.

**Dispositivo (2026-10-15).** En el POCO, contra el Backend real, se midió el reintento con el mismo ID tras `TIMEOUT` (respuesta perdida después del commit: ALREADY_APPLIED), tras `NETWORK` y tras un cierre forzado (C01–C04). No se midió la distribución del jitter. Ver [F05_MOBILE_SYNC_DEVICE](../../evidence/F05_MOBILE_SYNC_DEVICE.md) §3.2.
