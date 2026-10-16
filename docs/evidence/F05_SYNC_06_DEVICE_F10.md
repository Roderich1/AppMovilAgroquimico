# F05-SYNC-06 (#18) — Primera tanda física en F10 (columna Mobile)

- **Fecha real:** 2026-10-16, de 20:08Z a 21:29Z (16:08–17:29 America/La_Paz).
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica, en el único teléfono disponible. Es una ejecución técnica automatizada: no hubo inspección personal de Roderich ni revisión del tutor.
- **Plan:** `docs/testing/F05_SYNC_06_PLAN_FISICO_F10.md` del Backend (BE #113), con el orden por riesgo pedido para F10: autorización 401/403, ACK inválido y conflicto/resolución. Restauración y recuperación (C35, C34) quedan para la tanda coordinada con la entrega de la sesión C.
- **#18 sigue abierto.** GATE-F05 sigue Pending. Cada fila se registra tal como salió, con la técnica usada.

## Entorno

| Elemento | Valor |
|---|---|
| Dispositivo | POCO X5 Pro 5G `22101320G`, Android 12 (API 31), MIUI `V14.0.7.0.SMSMIXM`, zona `America/La_Paz` |
| Mobile | `main` **`4f203c7da40097e837acff8a02fb19daa09a13c1`**, compilado sin cambios en tres copias aisladas **nuevas** con `build_isolated_apk.sh` (20:08–20:09Z): `.f10s18a` SHA-256 `2cf7689e86661649c7b5ca330d5ce91a33c2168948179135d528ac0185a59bd2`; `.f10s18b` `d4bd06cc0f89473baadb596e1b7c3763b87fc54822c72682e90a9a9797f32192`; `.f10s18c` `33af156767838694312c45b9af65256d998f9bdb6634bd82000675b8532dfae0`. La app normal (`firstInstallTime`/`lastUpdateTime` 2026-09-24 13:04:32), la demo y las copias `.f03res01`, `.f06d4`, `.f03e2b` y `.f08bkp` no se tocaron |
| Backend | `main` **`e02793809502b5da0b0638802f2fbec5be8c0f86`** (el integrado final), compilado desde limpio (`npm ci`, `prisma generate`, `build`, `build:seed`) y ejecutado con `node dist/main.js`, `NODE_ENV=production` |
| Base | Contenedor **nuevo** `agro_a_f10int_pg` (postgres:16-alpine, 127.0.0.1:55447, volumen `agro_a_f10int_pgdata`), base `agro_f10int`. Las 10 migraciones se aplicaron en orden a las 20:00:40Z (de `20260618010000_init_expanded_flow` a `20261016181000_f08_backup_metadata`). El entorno del turno 2 de F08 (`agro_c_f08e2e_pg`) se conserva sin cambios |
| Arnés | `tool/f03_res_01` y `tool/f10_s18` del commit **`63fcf659ca6a8b4fdddde52f3d0854a270ae0882`**. Se ejecutaron desde el árbol de trabajo antes de ese commit; el contenido commiteado es el mismo, con los finales de línea normalizados a LF por `.gitattributes` y el README ampliado |
| Accesos | Túnel HTTPS temporal (Cloudflare quick tunnel) → observador 3117 → API 3116. El origen no se publica |
| Cuentas | Sintéticas del seed: E2 `maria.choque@agro.local` (copia C), S `pedro.mamani@agro.local` (copias A y B), R `rosa.vargas@agro.local` (C38) y el Administrador (C22). Cada contraseña es de un solo uso (`credential.sh`); ninguna se imprimió ni se escribió |

**TTL del access token.** La API arrancó con `JWT_EXPIRES_IN=15m`. Para C24 se reinició **sólo la API** con `2m` (20:35:05Z) y se volvió a `15m` (20:56:28Z). Motivo: el cliente descarta su access a los 10 min (`SyncAccessHolder.lifetime`, `lib/services/sync/sync_access.dart:30-36`), antes de que Central lo rechace a los 15; sin un TTL de servidor más corto, un push nunca recibe el 401 de un token vencido (ver C24, variante natural). Los refresh tokens son opacos y se guardan como SHA-256 (`auth-v2.service.ts:468-470`), así que sobreviven al reinicio. En cada reinicio se generaron secretos nuevos sólo en el proceso; la clave de huella de Sync v1 cambió y, por eso, se comprobó antes que el journal no tenía operaciones sin finalizar (0).

**Técnicas de inyección** (sin cambiar el código de Mobile ni de Central):

| Técnica | Qué mide |
|---|---|
| Respuesta inyectada en el observador (`fault.sh`) | La **reacción del cliente** a un ACK inválido o a un 500. En las variantes «tras reenviar», Central procesó la petición real |
| Bloqueo y revocación por SQL (`decision_window.cjs`) | El push real del teléfono pasa el guard y espera dentro de la transacción de decisión; la revocación se confirma en esa espera |
| Revocación de una sesión por SQL (C38) | Equivale a cerrar la sesión de esa instalación; se revocaron también sus refresh tokens V2 |
| Acciones administrativas reales por la API | Desactivación de la cuenta (C22) y revocación de registros de cliente (C23) |
| Modo avión (`device.sh net off/on`) | Intenciones pendientes sin red |

## Resultados

| Caso | Mobile | Técnica | Observado (horas UTC; operaciones por sus 8 primeros hex) |
|---|---|---|---|
| **C24** access expirado | **PASS** | TTL de servidor 2m (ver arriba) y acciones explícitas en la UI | **Variante natural (TTL 15m), copia C:** el cliente descartó su access a los 10 min; al declarar `d31eabd3` (20:30:31) **no salió ninguna petición** en 2 min, la fila quedó `PENDING` con 0 intentos y el aviso «Verifique el acceso en línea para enviar. Sus datos siguen guardados.». «Sincronizar ahora» → 1 refresh 200 (20:32:49.241) y 1 push 200 del mismo ID → APPLIED, journal 1. **401 real (TTL 2m):** verificación 20:35:48; `e592dc20` declarado a las 20:38:09 → `push 401` (20:38:17.135) → `PENDING`, `AUTH_REQUIRED`, mismo ID. **Ninguna petición** hasta 20:42:13 (4 min) y aviso visible. «Sincronizar ahora» → 1 `refresh 200` (20:42:27.946) y 1 push 200 **del mismo ID** → APPLIED (journal 1). **Variante «Verificar acceso en línea»:** `58cd22de` → `push 401` (20:44:48.732); nada hasta 20:46:52; «Verificar acceso en línea» → `refresh 200` (20:46:58.985) y, en el siguiente ciclo automático, push 200 del mismo ID (20:47:32.461) → APPLIED. Ningún refresh ni push entre el 401 y la acción explícita |
| **C40** revocación dentro de la ventana de decisión | **PASS** | Bloqueo `FOR UPDATE` de las 2 sesiones ACTIVE de E2 y su registro (copia C y una sesión de la comprobación previa por API); revocación de las sesiones y sus refresh tokens en la misma transacción | Verificación 20:48:07.411 (antes de bloquear). `37ea2ff8` confirmado a las 20:48:44.405. El script vio el push **esperando en el `FOR SHARE` de la revalidación** a las 20:48:45.586 (`pg_stat_activity`, espera de tipo Lock), revocó y confirmó a las 20:48:45.599; Central respondió **`push 403`** a las 20:48:45.603. Sin journal para `37ea2ff8`; contribución sin cambio (head `58cd22de`, 18000 ML, secuencia 3). Fila `AUTH_PAUSED`, `AUTH_CONTEXT_FORBIDDEN`; ninguna petición hasta 20:50:52; pantalla «Pausado: autorización: 1». **Recuperación:** «Sincronizar ahora» → `refresh 401` (sesión revocada) → reautenticación con E2 (login 200, `session/client` 201 sobre el mismo registro, que seguía ACTIVE) → la fila siguió pausada sin acción → «Sincronizar ahora» → push 200 del mismo ID (20:54:57.986), APPLIED una vez (secuencia 4). Esto mide la ventana entre el guard y la decisión con una revocación de **sesión**; la parte «retener antes de Central» (C40a del plan) no se ejecutó porque no ejercita esa ventana |
| **C23** ClientRegistration revocado | **PASS** (pausa) / **NOT_MEASURED** (reanudar con un registro nuevo) | Revocación real por la API (`revoke.sh revoke-clients E2`) con la intención pendiente sin red | Verificación 20:56:48; modo avión; `0a9276db` quedó `OUTCOME_UNKNOWN`/`NETWORK`. Revocación de los 2 registros ACTIVE de E2 (20:57:49–50, `HTTP 201`, sesiones REVOKED). Red de nuevo → **`push 403`** (20:58:32.260) → `AUTH_PAUSED`, sin journal, ninguna petición hasta 21:00:38. **Reanudar en la misma instalación no es posible por diseño:** «Verificar acceso» → `refresh 401`; reautenticación con E2 → login 200, **`session/client` 404**, logout 204 y el mensaje «La vinculación de este dispositivo no fue aceptada. Se necesita revisión para usar funciones en línea.»; la intención sigue `AUTH_PAUSED`, sin pérdida. La revocación de un registro es irreversible para esa instalación (#71, E-2); «reactivar con un registro nuevo» exige otra instalación (y, para conservar la intención, una restauración), que no se ejecutó |
| **C22** cuenta y Member inactivos | **PASS** | Desactivación real por la API (`revoke.sh deactivate S`, Administrador) con la intención pendiente sin red | Copia B: verificación 21:24:43; modo avión; `cc82c105` `OUTCOME_UNKNOWN`. `PATCH users/{id}/deactivate` 200 (21:25:29): usuario y Member inactivos; las sesiones siguen ACTIVE en la base. Red de nuevo → **`push 403`** (21:26:29.941) `AUTH_CONTEXT_FORBIDDEN` → `AUTH_PAUSED`; sin journal; **ninguna petición** hasta 21:28:39; mensaje «El sindicato no autorizó esta cuenta o este dispositivo. Los envíos quedan pausados; nada se borró.». Tenant inactivo no se midió por separado |
| **C38** otra cuenta del mismo tenant al reautenticar | **PASS** | Revocación por SQL de la sesión de la copia A; reautenticación en la UI con la cuenta R | Copia A con `2afde3ba` (de S) pendiente sin red. Reabierta sin acceso: 0 peticiones en 75 s. «Verificar acceso» → `refresh 401`; reautenticación con **R** → login 200 (21:22:42.155) y **logout 204** inmediato (21:22:42.554): la app cerró esa sesión sin vincular el registro. **0 push**; la intención de S siguió con el mismo ID. Reautenticación con S → `session/client` 201 y «Sincronizar ahora» → push 200 del mismo ID (21:24:05.261), APPLIED una vez (secuencia 9). **Observación de UX:** la captura tomada después no muestra un mensaje que diga que la cuenta es otra; sólo el texto general «Verifique la misma cuenta…» |
| **C30** ACK 2xx incompleto o contradictorio | **PASS** | Respuesta inyectada **tras reenviar** a Central | Copia A. Tres variantes: ACK sin `serverAcceptedAt` (`7cbb93a6`, 21:03:39), `disposition` contradictoria (`3f164974`, 21:05:22) y `operationId` de otra operación (`4b1dc0ed`, 21:06:10). En las tres, Central aplicó la intención; el teléfono la dejó **`OUTCOME_UNKNOWN`/`INVALID_ACK`, nunca ACKED**, y el reintento del ciclo siguiente (21:04:35, 21:05:34, 21:06:35) recibió el resultado persistido (`ALREADY_APPLIED`, `ack.ts:108-120`) con la hora del commit original → ACKED. Journal 1 por operación |
| **C05** 500 antes del commit | **PASS** | Respuesta 500 inyectada **sin reenviar** | `bbd04444` → 500 (21:07:13.394) → `OUTCOME_UNKNOWN`/`HTTP_500`; journal 0 antes del reintento. Reintento (21:07:35) → APPLIED una vez (secuencia 4) |
| **C06** 500 con commit desconocido | **PASS** | Respuesta 500 inyectada **tras reenviar** | `b4cb97fe`: Central confirmó a las 21:08:11.989 y el teléfono recibió 500 → `OUTCOME_UNKNOWN`/`HTTP_500`. Reintento (21:08:35) → resultado persistido con la hora original → ACKED. Journal 1, secuencia sin cambio (5), sin duplicado |
| **C11** dos sucesores del mismo head | **PASS** | Dos copias aisladas de la misma cuenta S; la copia B obtuvo el head restaurando en la nube un respaldo de la copia A (F08) | A subió su respaldo (21:10:14, `POST /me/backups` 201); B, activada con S (registro nuevo), lo restauró (21:12:30, descarga 200, sin ningún push). Ambas con head `b4cb97fe`. A envió `aeb84660` (pred `b4cb97fe`) → APPLIED (21:14:09, secuencia 6). B envió `d1a7450d` (pred `b4cb97fe`) → **CONFLICT/CAUSAL_FORK** (21:15:17), disputa `113af354`, contribución CONTESTED sin cantidad. B muestra «Conflicto: decida usted» |
| **C15** referencia de reconciliación obsoleta | **PASS** | Diálogo de resolución abierto en B mientras A envía otro valor | B abrió «Resolver conflicto…» → `GET /operations/{id}` 200 (21:15:54; head `aeb84660`, disputa `113af354`). Con el diálogo abierto, A envió `5ddaa29e` → CONFLICT/CAUSAL_FORK y la disputa rotó a `0d951b1b` (`113af354` cerrada SUPERSEDED). B eligió «Enviar mi valor actual (16 L)» → `78204c96` con la referencia vieja → **CONFLICT/RECONCILIATION_STALE** (21:17:06); contribución intacta (CONTESTED, head `aeb84660`, secuencia 6, disputa `0d951b1b`) |
| **C14** resolución con head y referencia vigentes | **PASS** | UI de resolución | B volvió a resolver: `GET /operations/{id}` 200 (21:17:41) → `0d26d90c` (pred `aeb84660`, referencia `0d951b1b`) → **APPLIED** (21:17:51), disputa `0d951b1b` RESOLVED por `0d26d90c`; contribución ACTIVE 16000 ML, secuencia 7; B muestra «Sincronizado». A resolvió después su conflicto con la vista vigente: `b52b2e59` APPLIED (21:19:40, secuencia 8) |
| **C31** GET del dueño | **PASS** (en la resolución) | — | La app no consulta tras un ACK perdido (reenvía el envelope: C30, C06). El GET sólo se usa al resolver: 3 `GET /operations/{id}` 200 (21:15:54, 21:17:41, 21:19:29), sin efectos, y su vista guió la resolución |

**Logcat** (`logcat_scan.sh`, por copia, al terminar): JWT 0, UUID completos 0, contraseñas 0, campos sensibles 0, valores opacos de 43+ caracteres 0 y FATAL 0 en `.f10s18a`, `.f10s18b` y `.f10s18c`.

**Capturas** (sin barra de estado; se conservan en la carpeta del ensayo y no se publican):

| Captura | SHA-256 |
|---|---|
| `f10_c24_aviso_401.png` | `b26f9ef01e1649b4388f02f8b20ac022e0f51bf58dbcd5fa37be023b039b0ab1` |
| `f10_c40_pausa_403.png` | `61426015d3b9e19d8219f99e4e668613f8b6ba0e88a71222522b16f8b0b7908a` |
| `f10_c23_vinculacion_rechazada.png` | `d5ddbe56a6a21e3550f0a9270f25ff8f5de4108a052063a7f3ce5efacf58484b` |
| `f10_c11_conflicto_b.png` | `1790e8882ab72ba4cf75ad48e8ff17df2dc4a6238d5a68675751feb265697889` |
| `f10_c14_resuelto_b.png` | `3ea44c2065d56a837f2fb0cd7a38e63f9f0383cb121eede11dc5df0cd57b4289` |
| `f10_c38_otra_cuenta.png` | `fa8a23461d8d3fa3ca6881de934b0215caadb4c83b442b4fa65594354e2326e7` |
| `f10_c22_pausa.png` | `31f80bc14605e0fef5ee373749b8e0b510cacd4559ef41352d84c756a298137f` |

## Límites y observaciones

- **Un solo modelo de teléfono.** Las tres copias corren en el mismo POCO.
- **Respuestas inyectadas.** C30, C05 y C06 miden la reacción del cliente a un ACK o un 500 fabricados por el observador; no son decisiones de Central. En C30 y C06, Central sí procesó la petición real.
- **Revocaciones por SQL.** C40 y C38 revocan con SQL lo mismo que el servicio (sesión REVOKED y sus refresh tokens V2), para alcanzar la ventana o aislar una instalación. C22 y C23 usan las acciones reales de la API.
- **TTL de 2 min sólo para C24**, en este entorno desechable.
- **C23:** la reanudación con un registro nuevo queda NOT_MEASURED (requiere otra instalación).
- **Observaciones para F10 (no se corrigen aquí):**
  1. C38: al rechazar otra cuenta, la pantalla no dice por qué.
  2. C23: el mensaje de vinculación rechazada no indica que la instalación necesita restaurarse en otra; la intención pausada sólo puede recuperarse con un respaldo previo.
  3. «Verificar acceso en línea» no reanuda lo pausado por un 403 (C40, C38): hace falta «Sincronizar ahora». Ya figuraba en el plan (observación 2).

## Lo que no cubre esta tanda

- C35 y C34 (restauración sin prueba de propietario; IDs bajo otro Member): tanda de restauración, con la corrección del rollback WAL de la sesión C.
- Tanda 2 (C09, C10, C12, C13, C16–C21, C25–C29, C32, C33, C36, C37, C39): NOT_MEASURED.
- Las filas no medidas siguen NOT_MEASURED; ninguna pasa a PASS ni a N/A por falta de tiempo.
