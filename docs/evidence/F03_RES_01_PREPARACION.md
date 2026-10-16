# F03-RES-01 (#71) — Preparación del entorno HTTPS controlado

Refs #71 y #23. Este registro documenta **sólo la preparación** del entorno, validada en el PC **sin teléfono**. No contiene resultados de dispositivo: los casos D, E-1, E-2 y la reapertura siguen sin ejecutar en el POCO (`NOT_MEASURED` hasta la ejecución coordinada con Roderich). El procedimiento está en `tool/f03_res_01/README.md`.

## Identidad

| Elemento | Valor |
|---|---|
| Fecha | 2026-10-15 |
| Ejecución | Comandos ejecutados con Claude Code en el entorno de desarrollo; sin revisión humana todavía |
| Backend | `d3911cea7c5a68decbb0ea0e970129efd553c38c` (worktree desacoplado, compilado) |
| Mobile (APK aislada) | `74003b12be6b640d5f9f24ed41e4b1bdc460e6ae` (worktree desacoplado) |
| Herramientas | Windows 11 Home 10.0.26200; Docker 29.4.0; Node 25.9.0; Flutter 3.47.2; curl de Git Bash (`/mingw64/bin/curl`) |
| cloudflared | 2026.10.0, SHA-256 `86aee4017b26625cee8484c113558f48effa4cd47f7aa05fcf425604e5d2b23c`, igual al publicado en el release `cloudflare/cloudflared` 2026.10.0 |

## Resultados de la validación

Las ejecuciones levantan PostgreSQL efímero, Backend, observador y túnel, y terminan con `down.sh`. Los secretos se generaron en la shell de cada ejecución y no se conservaron. No se imprimieron tokens, contraseñas ni el origen HTTPS.

### Ejecución 1 — arranque, HTTPS y login

| Paso | Resultado |
|---|---|
| `up.sh` | PostgreSQL listo en `127.0.0.1:55432`; 5 migraciones aplicadas; seed «12 agricultores, 14 productos, 72 lotes»; contraseñas rotadas en 15 usuarios (3 del ensayo con contraseña efímera); health local HTTP 200 |
| `tunnel.sh` | Origen HTTPS temporal; health por HTTPS 200 |
| `check.sh login D` | Login V2 BODY HTTP 200; claves `accessToken, context, contractVersion, refreshToken, refreshTransport, sessionExpiresAt`; logout 204 |

### Ejecución 2 — fallo observado en E-1 y E-2

`revoke.sh e1` y `e2` pasaban la cabecera `Authorization` con `curl -H @<(...)`. El curl de Git Bash respondió `option -H: error encountered when reading a file` y **no** envió las peticiones. Por eso la cuenta D siguió activa (`login` HTTP 200 tras el supuesto E-1). Se corrigió pasando la cabecera como configuración de curl por stdin (`-K -`), que tampoco la deja en los argumentos del proceso.

En esa misma ejecución, `build_isolated_apk.sh` sí compiló la APK aislada:

- paquete `com.comunidad.agro.agroquimicos.f03res01`;
- SHA-256 `2b4de584cceeddc96bdee7198dd49cc961a9663aa755a67eb093300a5676234a`;
- worktree Mobile limpio después.

Esa APK apuntaba a un origen ya cerrado y **no sirve** para el ensayo. En la ejecución hay que compilar otra con el origen nuevo.

### Ejecución 3 — E-1 y E-2 corregidos

| Paso | Resultado |
|---|---|
| `revoke.sh e1` | `PATCH /users/{id}/deactivate` HTTP 200. Estado D: usuario y Member inactivos |
| `check.sh login D` tras E-1 | HTTP 401 |
| Registro de cliente sintético de E2 por curl (sólo validación) | `POST /auth/clients` HTTP 201. `GET /auth/clients` devuelve un arreglo con `createdAt, lastSeenAt, registrationId, revokedAt, status` |
| `revoke.sh e2` | `POST /auth/clients/{id}/revoke` HTTP 201; 1 registro revocado. Estado E2: registro de cliente REVOKED = 1; sesiones REVOKED = 2 |
| `down.sh` | Contenedor y volumen eliminados; sin escucha en 3100; 0 procesos `cloudflared` |

### Ejecución 4 — observador y conteo de refresh

| Paso | Resultado |
|---|---|
| Login + `POST /auth/v2/refresh` de D por curl (sólo validación) | Refresh HTTP 200. Estado D: sesión ACTIVE = 1; refresh tokens `total=2, consumidos=1, revocados=1` |
| `check.sh requests` desde la marca | `1 POST /api/v1/auth/v2/login 200` y `1 POST /api/v1/auth/v2/refresh 200` |
| E-1 y login posterior | 200 y 401 |
| `revoke.sh e2` sin registros | 0 revocados; `GET /auth/clients` 200 |
| `down.sh` | Túnel, observador y API detenidos; contenedor y volumen eliminados; sin escucha en 3100 ni 3101; 0 procesos `cloudflared` |

Resumen de peticiones de la ejecución 4, tal como lo registró el observador (método, ruta con UUID enmascarados, estado):

```text
      1 GET /api/v1/auth/clients 200
      2 GET /api/v1/health 200
      1 PATCH /api/v1/users/{id}/deactivate 200
      3 POST /api/v1/auth/v2/login 200
      1 POST /api/v1/auth/v2/login 401
      3 POST /api/v1/auth/v2/logout 204
      1 POST /api/v1/auth/v2/refresh 200
```

### Alcance de las ejecuciones 3 y 4 (aclaración del 2026-10-15)

En la ejecución 3, el «login D tras E-1: 401» es un **login nuevo**. Demuestra que la desactivación surte efecto, pero **no** es el 401 del refresh de una sesión existente que exige el caso E. Tampoco el 201 de la revocación demuestra el rechazo posterior: sólo confirma la acción administrativa.

### Ejecución 5: refresh 401 sobre sesiones existentes (servidor, sin túnel)

`up.sh` + `server_refresh_401_check.sh` + `down.sh`, contra `http://127.0.0.1:3100`, sin exponer la API. Las sesiones las crea curl, no la app.

| Paso | Resultado |
|---|---|
| E-1: refresh previo de la sesión existente de D | HTTP 200 |
| E-1: desactivación de D por el Administrador | HTTP 200 |
| E-1: refresh de **la misma sesión** tras E-1 | **HTTP 401** |
| Estado D | usuario y Member inactivos; la sesión sigue ACTIVE en la base (el rechazo viene de la cuenta inactiva); refresh tokens `total=2, consumidos=1, revocados=1` |
| E-2: sesión de E2 ligada a un registro de cliente | HTTP 201 |
| E-2: refresh previo de la sesión ligada | HTTP 200 |
| E-2: revocación del registro | HTTP 201 |
| E-2: refresh de **la misma sesión ligada** tras E-2 | **HTTP 401** |
| Estado E2 | sesión REVOKED = 1, registro de cliente REVOKED = 1, refresh tokens `total=2, consumidos=1, revocados=2` |
| `down.sh` | contenedor y volumen eliminados; sin escucha en 3100/3101; 0 procesos `cloudflared` |

Esto valida el comportamiento del servidor ante sesiones existentes. **No** acredita los casos D, E-1 ni E-2 de #71: falta la petición de refresh de la app en el teléfono y su reacción. Siguen `NOT_MEASURED`.

## Pendiente para la ejecución

- Compilar la APK aislada con el origen del día e instalarla junto a la app normal.
- Ejecutar D, E-1, E-2 y la reapertura en el POCO. Registrar los datos del dispositivo y cada caso como PASS, FAIL o NOT_MEASURED.
- Revisión de Roderich Rendón: pendiente. Revisión del tutor: se registra aparte en GOV-01.

**Ejecución (2026-10-15, 21:07–21:36).** D, E-1, E-2 y las reaperturas se ejecutaron en el POCO: [F03_RES_01_DEVICE](F03_RES_01_DEVICE.md).
