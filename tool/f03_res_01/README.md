# F03-RES-01 (#71) — Procedimiento del ensayo en dispositivo

**Preparado, no ejecutado.** La ejecución física se coordina con Roderich. Se hace en una **app aislada** (`com.comunidad.agro.agroquimicos.f03res01`, «Agrocuentas F03-RES-01»), nunca en la app normal, que no se abre, desinstala ni modifica.

Casos de #71: D (refresh real), E-1 (desactivación de la cuenta), E-2 (revocación del registro de cliente) y reapertura sin red tras E. No incluye cambios de código; un defecto encontrado se registra en un issue aparte.

## Componentes

| Pieza | Valor preparado |
|---|---|
| Backend | Worktree desacoplado de `Agro_Sindicato_Backend-Web` en `d3911cea7c5a68decbb0ea0e970129efd553c38c`, compilado (`npm ci`, `prisma generate`, `build`, `build:seed`) |
| Base de datos | Contenedor efímero `agro_f03res01_pg` (postgres:16-alpine) en `127.0.0.1:55432`, volumen propio. No usa `agro_postgres` ni el puerto 5432 |
| API | `node dist/main.js` en `127.0.0.1:3100`, `NODE_ENV=production`, TTL por defecto (15m / 7d, sin acortar) |
| Observador | `observer.cjs` en `127.0.0.1:3101`: registra sólo hora, método, ruta (UUID enmascarados) y estado |
| HTTPS | Cloudflare quick tunnel → observador. `cloudflared` 2026.10.0, SHA-256 `86aee4017b26625cee8484c113558f48effa4cd47f7aa05fcf425604e5d2b23c`, igual al publicado en el release |
| Cuentas | Seed del Backend: Administrador `admin@agro.local`; agricultor D (D y E-1) `juan.perez@agro.local`; agricultor E2 `maria.choque@agro.local`. Se rotan las contraseñas de los 15 usuarios del seed; la del repositorio deja de servir |
| App aislada | `build_isolated_apk.sh` añade un sufijo y una etiqueta temporales (no se commitean) y compila con `--dart-define=AGRO_API_BASE_URL=<origen>` |

Secretos (contraseña de PostgreSQL, JWT y contraseñas de cuentas): sólo en variables de la shell que ejecuta `source secrets.sh`. Ningún script los imprime ni los escribe. Para teclear una contraseña en el teléfono, el operador la consulta en su terminal (`echo "$F03_FARMER_D_PASSWORD"`) y no la copia a la evidencia.

## 0. Antes de empezar

1. Docker Desktop activo. El POCO tiene depuración USB y «Instalar vía USB» permitido (MIUI rechazó instalaciones antes con `INSTALL_FAILED_USER_RESTRICTED`).
2. Decidir el SHA Mobile del ensayo. Preparado con `origin/main` `74003b12be6b640d5f9f24ed41e4b1bdc460e6ae`. El worktree Mobile desacoplado debe estar limpio.
3. En una sola shell (Git Bash):

```bash
export F03_BE_DIR=<ruta>/_wt/F03-RES-01-BE/Back
export F03_CLOUDFLARED=<ruta>/_wt/tools/cloudflared-2026.10.0/cloudflared-windows-amd64.exe
export F03_RUN_DIR=/c/Users/MSI/AppData/Local/Temp/agro_f03res01
cd tool/f03_res_01 && source ./config.sh && source ./secrets.sh
./up.sh && ./tunnel.sh && ./check.sh health
./build_isolated_apk.sh <ruta>/_wt/F03-RES-01-APK     # anotar SHA-256 de la APK
```

4. Datos del dispositivo: `adb shell getprop ro.product.model`, `ro.build.version.release`, `ro.build.version.sdk`.
5. Instalar **sólo** la app aislada: `adb install "$F03_RUN_DIR/agrocuentas-f03res01-debug.apk"`. Comprobar con `adb shell pm list packages | grep agroquimicos` que la normal sigue presente y que la aislada aparece aparte.

## 1. Activación y marcador

1. En la app aislada, activar con la cuenta D.
2. Crear un marcador SQLite conocido, por ejemplo la persona `MARCADOR-F03RES01`.
3. `./check.sh state D`. Esperado: sesión ACTIVE = 1, registro de cliente ACTIVE = 1.

## 2. Caso D — refresh real

1. Guardar la marca: `m=$(./check.sh mark)`.
2. Pulsar **una vez** «Verificar acceso en línea».
3. `./check.sh requests "$m"`. **PASS** sólo con exactamente `1 POST /api/v1/auth/v2/refresh 200` y ningún `POST /api/v1/auth/clients`.
4. `./check.sh state D`. Esperado: sesión ACTIVE; refresh tokens con una rotación más (`consumidos` +1). Validación del 2026-10-15: 1 login + 1 refresh por curl → `total=2, consumidos=1, revocados=1`.
5. En la app: estado remoto disponible y marcador presente. Los identificadores locales no se muestran; se comprueban según #71 sin publicar valores.
6. Ejecutar D una sola vez por sesión. Si el resultado es incierto, reactivar con una cuenta nueva, sin reintentar.

## 3. Caso E-1 — desactivación por el Administrador

> **Criterio de PASS (E-1 y E-2).** Lo que cuenta es el **401 del refresh de la sesión existente de la app** (`POST /api/v1/auth/v2/refresh 401` en `check.sh requests`) y la reacción de la app: cuarentena, sin segundo intento, sin `registerClient`, SQLite intacto.
>
> Lo siguiente **no** sustituye ese criterio:
> - el `HTTP 200` de `revoke.sh e1` y el `HTTP 201` de `revoke.sh e2`, que sólo confirman la acción administrativa;
> - un **login** 401 de `check.sh login`, que es otra petición y otra sesión.

1. `m=$(./check.sh mark)`; `./revoke.sh e1`. Esperado: `HTTP 200`.
2. En la app: «Verificar acceso en línea».
3. `./check.sh requests "$m"`. Esperado: un `POST /api/v1/auth/v2/refresh 401` y ningún segundo refresh ni `POST /api/v1/auth/clients`.
4. `./check.sh state D`: la sesión no debe quedar `COMPROMISED`; si quedara así, indicaría reutilización del refresh antiguo.
5. App: `requiresReauthentication` y guard en cuarentena; Dashboard y SQLite disponibles, marcador intacto.

## 4. Reapertura sin red tras E

1. `adb shell am force-stop com.comunidad.agro.agroquimicos.f03res01`.
2. Radios apagadas. Reabrir.
3. Esperado: guard en cuarentena; Dashboard y SQLite abren; se ofrece reautenticación. `./check.sh requests` sin peticiones nuevas de autenticación al arrancar.

## 5. Caso E-2 — revocación del registro de cliente propio

1. `adb uninstall com.comunidad.agro.agroquimicos.f03res01`. **Sólo** el paquete aislado.
2. Reinstalar la misma APK; así obtiene un `installationClientId` nuevo.
3. Activar con la cuenta E2 y crear el marcador.
4. `m=$(./check.sh mark)`; `./revoke.sh e2`. Esperado: `HTTP 201` y `registros ACTIVE revocados: 1`. La revocación es irreversible para esa instalación.
5. En la app: «Verificar acceso en línea». Mismas comprobaciones que E-1 (401, sin segundo intento ni `registerClient`, marcador intacto).
6. Repetir la reapertura sin red (paso 4).

## Validación de servidor previa (opcional, sin teléfono ni túnel)

`./up.sh && ./server_refresh_401_check.sh && ./down.sh`

Comprueba contra la API local (sin exponerla) que una sesión **existente** creada por curl:
- recibe refresh 200 antes de E-1 y 401 después;
- ligada a un registro de cliente, recibe refresh 200 antes de E-2 y 401 después.

Valida el lado del servidor; **no** sustituye el ensayo en el teléfono. Resultado del 2026-10-15 en `docs/evidence/F03_RES_01_PREPARACION.md`.

## Nota sobre el SHA Mobile

Si el ensayo usa un Mobile que ya incluye la política de activación (#76, PR #77/#78), después de activar hay que elegir el titular antes de crear el marcador. Anotar en la evidencia qué SHA se usó y si incluía esa política.

## 6. Logcat y cierre

- Tras cada caso, `./logcat_scan.sh`. Revisa en memoria el logcat del UID de la app aislada e imprime sólo conteos (JWT, UUID completos, contraseñas del ensayo, FATAL). No se guarda ni se publica logcat crudo.
- Cierre:
  - `./down.sh`, que elimina sólo el contenedor y el volumen del ensayo y detiene túnel, observador y API;
  - `adb uninstall com.comunidad.agro.agroquimicos.f03res01`;
  - restaurar las radios;
  - confirmar que la app normal sigue instalada y sin tocar.
- Evidencia: `docs/evidence/F03_RES_01_DEVICE.md`, con:
  - modelo, versión de Android y nivel de API;
  - SHAs de Mobile y Backend, SHA-256 de la APK y fecha real;
  - tabla D / E-1 / E-2 / reapertura con PASS, FAIL o NOT_MEASURED y su causa;
  - salida de `check.sh requests` y `check.sh state`;
  - SHA-256 de las capturas sanitizadas.
  - El origen HTTPS se registra como `HTTPS_EPHEMERAL_ORIGIN_REDACTED`.

## Riesgos del entorno

- **El quick tunnel es público mientras está abierto.** Mitigaciones: contraseñas rotadas; base y datos sintéticos; abrirlo sólo durante el ensayo; `down.sh` al terminar.
- El Backend limita a 20 peticiones por minuto por origen. Con el túnel, todas las peticiones comparten ese límite: evitar `curl` repetidos durante los casos.
- La API no confía en proxies (`trust proxy` no está configurado). No afecta a los casos, pero los límites por IP no distinguen clientes.
