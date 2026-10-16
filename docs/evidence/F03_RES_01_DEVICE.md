# F03-RES-01 (#71) — Refresh real y revocación 401 en dispositivo

Refs #71 y GATE-F03 #23. Procedimiento en `tool/f03_res_01/README.md`; preparación en [F03_RES_01_PREPARACION](F03_RES_01_PREPARACION.md).

Sesión física ejecutada con Claude Code el **2026-10-15 entre las 21:07 y las 21:36 (America/La_Paz, UTC−4)**, autorizada por Roderich con una app aislada y datos sintéticos. En la misma sesión, y con el mismo entorno, se ejecutó después el E2E de D3 (`docs/evidence/F05_MOBILE_SYNC_DEVICE.md`, rama `feat/f05-outbox-sync-v1`). **Esta evidencia no resuelve GATE-F03 (#23)**, que sigue Pending hasta la revisión de Roderich.

## 1. Identidad

| Elemento | Valor |
| --- | --- |
| Dispositivo | POCO X5 Pro 5G, modelo `22101320G` (redwood), Android 12, API 31, MIUI `V14.0.7.0.SMSMIXM`, zona horaria America/La_Paz. No se publica el serial ADB |
| App | Copia aislada `com.comunidad.agro.agroquimicos.f03res01`, «Agrocuentas F03-RES-01», build debug. Antes de instalar se comprobó con `aapt dump badging` el paquete, la etiqueta, `debuggable` y el origen del día. La app normal `com.comunidad.agro.agroquimicos` (2026-09-24) siguió presente y sin cambios |
| Mobile | `94e7d240c61684dd1535de2f36b79ea0296d3cfc`, HEAD de PR MOB #80, en un worktree desacoplado y limpio. Incluye la política de activación (#76, vía `main` `3eecb2d`), así que se eligió el titular antes de crear el marcador. Las correcciones posteriores de la sesión (`023a47b`, `5027a35`) no tocan el código de autenticación |
| APK | SHA-256 `8fcff313934a1eb6eaad55883ee93e2a9a35254a0c60def7f81518c81c9e090e`. Cambios temporales, sin commitear: `applicationIdSuffix ".f03res01"` (debug), `android:label` y `--dart-define=AGRO_API_BASE_URL=<origen>`. Sin instrumentación de código |
| Backend | `Agro_Sindicato_Backend-Web` `c2acbd4cc6b51befec92dc6f5f9ad9ed059d8357` (PR BE #109; Auth V2 sin cambios respecto de `main`), `NODE_ENV=production`, TTL por defecto (15m / 7d) |
| Base | Contenedor efímero `agro_f03res01_pg` (`postgres:16-alpine`, `127.0.0.1:55432`), 6 migraciones con `prisma migrate deploy`, seed sintético y las contraseñas de los 15 usuarios rotadas |
| HTTPS | Cloudflare quick tunnel (`cloudflared` 2026.10.0, SHA-256 `86aee401…b23c`). Origen `HTTPS_EPHEMERAL_ORIGIN_REDACTED`, cerrado a las 22:24:45 |
| Cuentas | D y E-1: `juan.perez@agro.local`. E-2: `maria.choque@agro.local`. Acciones: `admin@agro.local`. Cada contraseña es nueva y de un solo uso (`credential.sh`); nunca se imprimió ni se escribió |

## 2. Método

- **Peticiones.** Un observador local entre el túnel y la API registra sólo hora, método, ruta (UUID enmascarados) y estado (`check.sh requests|timeline`).
- **Central.** Conteos de sesiones, refresh tokens y registros (`check.sh state`). Huellas de 12 hex (SHA-256) de sesión, registro, Member y tenant (`check.sh ids`).
- **Teléfono, sin valores** (`device.sh secure`), con `run-as` sobre la build debug:
  - el slot activo de la sesión cifrada A/B y el guard (`AgrocuentasSessionPointer`);
  - la huella del `client_id` de instalación;
  - la huella del texto cifrado de cada slot, nunca descifrado.
- **SQLite.** Copia temporal y consulta de sólo lectura del marcador y del titular, con huellas de Member y tenant.
- **Pantalla.** UI leída con `uiautomator`; capturas sin barra de estado.

## 3. Resultados

| Caso | Pasos | Observado | Resultado |
| --- | --- | --- | --- |
| Activación | Cuenta D y titular «Titular D F03»; marcador `MARCADOR-F03RES01` en Catálogos | A las 21:18:41: `POST auth/v2/login` 200, `POST auth/clients` 201, `POST auth/v2/session/client` 201 y `GET auth/v2/me` 200. Las huellas de Member y tenant del titular local coinciden con las de Central. Antes de D: sesión ACTIVE, refresh `total=1, consumidos=0`, registro ACTIVE, slot `a`, guard `clear` y marcador presente | Preparado |
| **D — refresh real** | Una pulsación de «Verificar acceso en línea» a las 21:22:19 | Exactamente **1** `POST /api/v1/auth/v2/refresh` **200** (21:22:23) y 0 `POST auth/clients`. Refresh tokens `total=2, consumidos=1, revocados=1`: hubo rotación. La sesión, el registro, el Member y el tenant tienen la misma huella, y la identidad de instalación es la misma (`3b2a1b64ec41`). En el teléfono, el slot pasa de `a` a **`b`** (commit cifrado en el otro slot; archivo modificado a las 21:22) y el guard sigue **`clear`**. Titular y marcador intactos. La app muestra «Acceso en línea verificado para esta sesión.» | **PASS** |
| **E-1 — desactivación** | El Administrador desactiva D (`credential.sh run ADMIN ./revoke.sh e1`); una pulsación de «Verificar acceso en línea» | Acción: `PATCH users/{id}/deactivate` **200**, con la sesión auxiliar cerrada (logout 204); usuario y Member inactivos. App: exactamente **1** `POST auth/v2/refresh` **401** (21:24:23), sin segundo refresh ni `POST auth/clients`. La sesión de Central no queda `COMPROMISED` y los refresh tokens no cambian: no hubo reutilización. Pantalla: «Volver a autenticar» y «Se requiere volver a autenticar para las funciones en línea. Sus datos locales siguen disponibles.». Guard **`quarantined`** (true). Dashboard y SQLite disponibles, marcador intacto. 0 peticiones en los 75 s siguientes con la app abierta | **PASS** |
| Reapertura sin red tras E-1 | `am force-stop` (0 procesos), modo avión y apertura como desde el launcher | Abren el Dashboard y SQLite, se ofrece «Volver a autenticar», el guard sigue `quarantined`, el marcador está intacto y no hubo peticiones. Además se encendió la red con la app abierta durante 80 s: 0 peticiones, guard sin cambio | **PASS** |
| **E-2 — revocación del registro propio** | Instalación nueva (sólo se desinstaló y reinstaló la copia aislada; identidad `71d26c3e2a8d`), cuenta E2 y su marcador. La propia cuenta revoca su registro (`credential.sh run E2 ./revoke.sh e2`); una pulsación | Acción: `POST auth/clients/{id}/revoke` **201** (1 registro), con la sesión auxiliar cerrada (204). Central: sesión de la app y registro REVOKED. App: exactamente **1** `POST auth/v2/refresh` **401** (21:32:38), sin segundo intento ni `registerClient`. Misma reacción que en E-1, guard `quarantined`, marcador intacto. 0 peticiones en 70 s | **PASS** |
| Reapertura sin red tras E-2 | Igual que tras E-1 | Dashboard, «Volver a autenticar», guard `quarantined`, marcador intacto, 0 peticiones. Con la red encendida durante 80 s: 0 peticiones | **PASS** |
| Logcat y registro propio | `logcat_scan.sh` tras E-1 (436 líneas) y tras E-2 (534 líneas), en memoria | JWT 0, UUID completos 0, nombres de campos sensibles (`refresh_token`, `accessToken`, `password`) 0, FATAL 0. `app_flutter/agrocuentas.log`: 7 líneas, 0 en todo. No se guardó ni publicó logcat crudo | **PASS** |

**Persistencia segura del refresh rotado (complemento, D3 sobre `023a47b`, cuenta `pedro.mamani`).** Tras un force-stop, la verificación explícita hizo un refresh 200 con el token guardado en la rotación anterior. Central no lo marcó como reutilizado (sesión sin `COMPROMISED`). No es el caso D de #71, pero muestra que el refresh rotado se conserva cifrado entre procesos.

## 4. Incidentes y hallazgos

- **Incidentes de tecleo, no son resultados de #71.**
  - El primer intento de activación de D no envió nada: la contraseña generada llevaba un `\r` (el `openssl` de Git Bash termina en CRLF) y Android no lo teclea. Se corrigió en `credential.sh` y `secrets.sh`.
  - En E2, el teclado autocorrigió el correo a «María.choque@…» y el login dio **401** porque la cuenta no existe. Un login 401 no sustituye el criterio de E-2: se reescribió el correo y se activó de nuevo.
- **Defectos del arnés corregidos durante la sesión** (no afectan a la app):
  - conversión de rutas de Git Bash en adb;
  - `ls -1` por `exec-out`;
  - URI de SQLite en Windows;
  - la huella del almacén cifrado: primero se hasheaba el archivo de claves y no los slots. Por eso no hay huellas por slot antes de D; el cambio de slot `a`→`b` y la hora del archivo acreditan la escritura.
- **Hallazgo de interfaz, anterior a #80 (F03).** Tras D, el Dashboard muestra a la vez «El estado en línea aún no fue verificado.» (estado de arranque, `existing_session_startup.dart:23`) y «Acceso en línea verificado para esta sesión.». No cambia ningún criterio de #71. Issue aparte [#83](https://github.com/Roderich1/AppMovilAgroquimico/issues/83), como pide #71 para cualquier defecto.

## 5. Capturas

Sanitizadas (sin barra de estado, sólo contenido sintético). Se conservan localmente, fuera de los worktrees, en `ProyectoAgro/_evidencias_locales/2026-10-15_E2E_F03RES01_D3/` (`SHA256SUMS.txt`), y no forman parte de este PR. Dos pares son idénticos porque la pantalla es la misma y la hora va en la barra recortada.

| Captura | SHA-256 |
| --- | --- |
| 71-00-inicio-sin-activar.png | `30c10f448bd2ceed6870afb513b03d828545a74ffed63284b0c0471833c2fa35` |
| 71-D-01-antes.png | `de73497dbb7feae180b38224f29e0d0e698eb3f9ec1d8c5a776cc46859dea3f6` |
| 71-D-02-despues.png | `80729db9f64aa14e04d33a1b1b5c5636bee6b468986b058abe792fc05fc95d26` |
| 71-E1-01-tras-401.png = 71-E2-01-tras-401.png | `1aa335cbe8293044f1c34f74ae5cc10ce95723d7e374481e86c7472d5a636742` |
| 71-E1-02-reapertura-sin-red.png = 71-E2-02-reapertura-sin-red.png | `cd49b4a603f03adc154769929c8a9eb44124d62e48c7d8739537efa02328e0cb` |
| 71-E2-00-activada.png | `157befde75a072bc7f6fd77c036ca1d434226813035b9c0ff93f4be4df7480f8` |

Registro del observador de toda la sesión (hora, método, ruta enmascarada, estado): `observador-peticiones.log`, SHA-256 `10067db607ebde12062ee82a4e30515c1a3a6cc03113d59782b28d5654137e5a`.

## 6. Estado al terminar

- El túnel, el observador y la API se detuvieron a las 22:24:45: 0 procesos `cloudflared` y nada escuchando en 3100 ni en 3101.
- El contenedor `agro_f03res01_pg` se conserva, sólo en `127.0.0.1`, para revisar Central. `down.sh` lo elimina junto con su volumen.
- En el teléfono las radios quedaron como al inicio (sin modo avión, Wi‑Fi y datos encendidos). `stay_on_while_plugged_in` vuelve a 0: durante la sesión estuvo en 2 y luego en 3.
- La copia aislada sigue instalada (con la cuenta S de D3) para revisión. Se quita con `adb uninstall com.comunidad.agro.agroquimicos.f03res01`.

## Addendum del 2026-10-16 — alcance del escaneo de logcat

Al revisar este documento frente al criterio de logcat de #71 («no contiene refresh tokens, JWT ni el UUID completo de instalación»), aparecieron tres límites del escaneo de la fila «Logcat y registro propio»:

- buscaba JWT y UUID, pero no valores opacos: el refresh token de Auth V2 es opaco (base64url), no un JWT;
- los nombres de campo se buscaban distinguiendo mayúsculas (`refresh_?token|accessToken|password`), sin `authorization` ni `bearer`;
- el buffer de 2 MiB pudo rotar entre pasos, y eso no se comprobó.

Por eso, para los procesos examinados en la sesión de #71, la ausencia de refresh tokens en logcat queda **NOT_MEASURED**. La fila original no se modifica; su PASS vale para JWT, UUID y los nombres que buscó.

**Complemento**, que no sustituye el criterio:

- La sesión física de D4 ([F06_D4_DEVICE](F06_D4_DEVICE.md)) usó otra copia aislada (`.f06d4`), compilada sobre la rama D4, que parte de Mobile `main` `99adac3`.
- Recorrió login, registro de cliente, enlace de sesión y un refresh 200.
- Usó un escaneo ampliado:
  - valores opacos de 43 o más caracteres;
  - nombres sin distinguir mayúsculas, incluidos `authorization` y `bearer`;
  - buffer de 16 MiB sin rotación;
  - control positivo.
- Resultado: 0 en todo (logcat 334 líneas; registro propio 10).
- **No** recorrió los caminos 401 de E-1 y E-2.

Para dar el criterio por medido en #71 falta repetir E-1 o E-2 con el escaneo ampliado, o que Roderich acepte este complemento como suficiente.

## Repetición de E-2 con escaneo ampliado (2026-10-16, 15:20–15:31 UTC)

Sesión breve y aislada de la sesión A, con autorización delegada. Mide en el camino 401 lo que el addendum anterior dejó NOT_MEASURED. Los datos y resultados anteriores se conservan sin cambios.

**Entorno nuevo**, para no tocar `agro_f03res01_pg`, `.f03res01` ni `.f06d4`:

| Elemento | Valor |
|---|---|
| Dispositivo | POCO X5 Pro 5G `22101320G`, Android 12 (API 31), MIUI `V14.0.7.0.SMSMIXM`, `America/La_Paz` |
| Copia aislada | Paquete nuevo `com.comunidad.agro.agroquimicos.f03e2b` («Agrocuentas F03-E2B»), depurable. APK sobre Mobile `55277847c1d39a63cc460d981bc5a6725a366968` (BASE_MOBILE_VALIDADA `caf158e` + corrección de #87; no cambia la autenticación ni el guard). SHA-256 `1cdc0cd4a3d99062f959550226596767c2dd616f62a8d79f46bc537fe2a0aef2` |
| Backend | `main` `063437d3ebe7f10110a5faaeee3f052e7d89d100`, `NODE_ENV=production`, **admisión de Sync v1 cerrada** (no hace falta para E-2) |
| Base | Contenedor nuevo `agro_a_e2_pg` (127.0.0.1:55445): 7 migraciones, seed y las 15 contraseñas rotadas |
| Herramientas | `tool/f03_res_01` en `a271c1e`: entorno configurable y escaneo de logcat ampliado |
| Transporte | Túnel HTTPS temporal (origen no publicado) hacia un observador de método, ruta y estado |
| Cuenta | `maria.choque@agro.local` (E2), con una contraseña de un solo uso tecleada sin mostrarse |

**Pasos y resultados:**

| Paso | Observado | Resultado |
|---|---|---|
| Activación y titular | Correo tecleado en minúsculas (también comprueba #87). Peticiones: `POST auth/v2/login` 200, `POST auth/clients` 201, `POST auth/v2/session/client` 201, `GET auth/v2/me` 200. Titular «Titular E2B», modo compartido. Marcador `MARCADOR-E2B` en Catálogos (SQLite: `activo=1`) | Preparado |
| Sesión existente válida antes de revocar | Una pulsación de «Verificar acceso en línea» a las 15:28:07: **1** `POST auth/v2/refresh` **200**. Slot `a` → `b` y guard `clear`. Central: sesión ACTIVE, refresh `total=2, consumidos=1, revocados=1`, registro ACTIVE. Pantalla: un solo mensaje, «Acceso en línea verificado para esta sesión.» | PASS |
| **E-2: la propia cuenta revoca su registro** | `credential.sh run E2 ./revoke.sh e2` a las 15:28:27: `POST auth/clients/{id}/revoke` **201**, 1 registro revocado; la sesión auxiliar se cerró (204). Central: registro REVOKED, sesiones REVOKED, refresh `revocados=3` | Acción hecha |
| **Refresh de la sesión revocada** | Una pulsación a las 15:28:31. Exactamente **1** `POST auth/v2/refresh` **401** (15:28:35), sin segundo refresh y sin `POST auth/clients`. Pantalla: «Se requiere volver a autenticar…» y «Volver a autenticar». Guard **`quarantined`**, slot `b` sin reescribir, marcador intacto. Sesiones `REVOKED`, ninguna `COMPROMISED`. 0 peticiones en los 60 s siguientes con la app abierta | **PASS** |
| Reapertura sin red | force-stop (0 procesos), modo avión y apertura a las 15:30:04. Inicio y «Volver a autenticar»; guard `quarantined`; marcador intacto; 0 peticiones. Con la red encendida y la app abierta, 0 peticiones en 65 s | **PASS** |
| **Logcat ampliado** | Buffer de 16 MiB desde las 15:23:47Z, antes de instalar. Líneas del UID de la copia entre 15:24:11Z y 15:30:11Z: 434. `logcat_scan.sh`: JWT 0, UUID completos 0, nombres sensibles 0, **valores opacos de 43+ caracteres 0**, **campos sin distinguir mayúsculas 0**, FATAL 0. Registro propio: 7 líneas, todo 0. Control positivo con valores sintéticos inventados: 1/1/1/3, lo esperado. No se guardó ni se publicó logcat crudo | **PASS** |

**Capturas.** Las revisó Claude Code: sólo el correo sintético y pantallas sin datos. No se versionan.

| Captura | SHA-256 |
|---|---|
| E2B-01-correo-minusculas | `e0b46fe7c92a4e0310837b311b8ed8146b5919a50812d1850bed4931a14c42e0` |
| E2B-02-verificado-antes | `69f4edec669d61b346c0bc757ce032008a91f9b2e51f61310c98f3aa1e9e09ba` |
| E2B-03-tras-401 | `dd03f5b69ede7b11d9c8540d1dfae3c92bc46920b9282f179e46acfb82aa114e` |
| E2B-04-reapertura-sin-red | `150945c39b27269f23f16d6f3f98b8e8cdb9ae14999c7699bfcbdb4c81082ac0` |

**Al terminar:**
- túnel, observador y API detenidos;
- `agro_a_e2_pg` detenido, con su volumen conservado (no se usó `down.sh`);
- en el teléfono, buffer de logcat devuelto a 2 MiB (Android descartó las líneas del buffer circular del sistema) y `stay_on_while_plugged_in` de nuevo en 0;
- la copia `.f03e2b` queda instalada y detenida;
- la app normal sin cambios (2026-09-24), y `.f03res01` y `.f06d4` siguen instaladas.

**Lo que esta repetición no cubre:**
- E-1 (desactivación por el Administrador) no se repitió con el escaneo ampliado;
- el escaneo de los procesos de la sesión del 2026-10-15 sigue NOT_MEASURED para refresh tokens opacos, porque su logcat no se conservó por diseño.

Con esta repetición, el camino 401 de una sesión existente revocada sí queda medido con el escaneo ampliado.

## 7. Revisiones

- Ejecución: Claude Code, 2026-10-15. Sin revisión humana todavía.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
- GATE-F03 (#23): **Pending**. Esta evidencia no lo cierra.
