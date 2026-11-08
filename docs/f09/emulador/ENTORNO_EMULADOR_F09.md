# F09: entorno del emulador para «AC F09» (2026-11-08)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08 (Bolivia, UTC−4) |
| Rama | `test/f09-emulador`, en `_wt/F09-EMU` (base `27e9a4e`). Sin push, sin PR |
| Procedencia | Análisis de código (HOST) + comprobación **preliminar** en el EMULADOR con la APK `fc6478d`, que **no** es la definitiva y no tiene origen del Central |
| Dispositivo | Emulador `Pixel_8` (`emulator-5554`), `sdk_gphone16k_x86_64`, API 36, TZ GMT |
| Central | DEMO: API `127.0.0.1:3330` (health 200), Web 5190 (200), PostgreSQL `127.0.0.1:15432`, contenedor `agro_demo_pg` (DEMO-BE `289b236`). No se reinició |

## 1. Acceso al backend para activar

### 1.1 Qué llama la activación

`FirstActivationCoordinator.activate` (`lib/services/auth/first_activation_coordinator.dart`):

| Línea | Petición |
|---|---|
| 272 | `POST /api/v1/auth/v2/login` |
| 291 | `POST /api/v1/auth/clients` (registro de la instalación) |
| 303 | `POST /api/v1/auth/v2/session/client` (vínculo sesión–instalación) |
| 318 | `GET /api/v1/auth/v2/me` |
| 456 | `POST /api/v1/auth/v2/logout` (sólo en la limpieza tras un fallo) |

Después, la configuración del titular y Sync piden `GET /api/v1/sync/v1/references`. Todas pasan por `ApiEndpointConfig` (`lib/services/auth/api_endpoint_config.dart`).

### 1.2 Conclusión: sin túnel no hay activación legítima

1. **El origen se compila y debe ser HTTPS.** `ApiEndpointConfig.fromEnvironment()` lee `AGRO_API_BASE_URL` al compilar (`api_endpoint_config.dart:42-49`). `_validate` rechaza todo lo que no sea `https` (`:89-101`). Sin origen válido, el proveedor devuelve `null` (`first_activation_providers.dart:37-44`). Entonces la activación termina en `configuration` antes de cualquier petición (`:110-114`), con el mensaje «La conexión segura todavía no está configurada.» (`first_activation_coordinator.dart:56-57`).
2. **`10.0.2.2` y `adb reverse` dan `http://`**, que se rechaza en el punto 1. Para que fueran HTTPS haría falta un servidor TLS local con un certificado para `10.0.2.2` o `localhost` que la app aceptara.
3. **La app sólo confía en las CA del sistema.**
   - El manifiesto no declara `networkSecurityConfig` ni `usesCleartextTraffic` (`android/app/src/main/AndroidManifest.xml:15-20`; `grep` sin resultados en `android/app/src`).
   - El cliente es `http.Client()` sin `badCertificateCallback` ni `SecurityContext` propio (`first_activation_providers.dart:46-50`; `grep` sin resultados en `lib`).
   - Las CA de usuario no sirven, y una CA de sistema exige root o `/system` escribible. Las dos cosas rebajan controles y están prohibidas.
4. **No hay en el proyecto ninguna configuración de desarrollo alternativa.** Se buscó sin resultados en `tool/`, `docs/`, `android/` y `lib/` de Mobile, y en `tool/` y `docs/` de DEMO-BE:
   - `adb reverse`, `10.0.2.2`, `mkcert`, `caddy` y `https.createServer`;
   - `network_security_config`, `cleartextTrafficPermitted`, `user-certificates` y `trust-anchors`.

   Todas las ejecuciones previas (F03-RES-01, DEMO, UX y VOZ) usaron el túnel.

**Por lo tanto, el túnel HTTPS temporal es imprescindible** para activar «AC F09». No se intentó ningún sustituto.

### 1.3 Qué hace `demo-mobile.sh tunnel`

- `_wt/DEMO-MOB/tool/demo/demo-mobile.sh` existe (DEMO-MOB `9470961`).
  - `tunnel` (`:34`) ejecuta `tool/f03_res_01/tunnel.sh`, que es idéntico al de F09.
  - Variables (`:22-23`): `F03_API_PORT=3330`, `F03_OBSERVER_PORT=3331` y `F03_RUN_DIR=%TEMP%\agro_demo_mob`.
- `tunnel.sh` hace lo siguiente:
  - Arranca `observer.cjs` en `127.0.0.1:3331`, que registra método, ruta y estado, y reenvía a 3330 (`:15-17`).
  - Abre un *quick tunnel* de `cloudflared` 2026.10.0 (`_wt/tools/cloudflared-2026.10.0/`) hacia 3331 (`:18-20`).
  - Guarda el origen en `%TEMP%\agro_demo_mob\origin` (`:28`), sin imprimirlo.
  - Espera un `health` 200 (`:29-35`).
- Estado hoy: los procesos del túnel y del observador anteriores están **muertos**.
  - El archivo `origin` (00:00 del 2026-11-08) es de esa sesión y no sirve.
  - `f09emu.sh compilar` se niega a usarlo si el túnel no está vivo.

**Comando mínimo para Roderich** (Git Bash, ventana abierta mientras dure la sesión):

```bash
bash /c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro/_wt/DEMO-MOB/tool/demo/demo-mobile.sh tunnel
```

Salida esperada: `Origen HTTPS temporal activo (valor en $F03_RUN_DIR/origin, no se publica): health HTTP 200`.

Comprobación sin publicar el origen:

```bash
bash /c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro/_wt/F09-EMU/tool/f09_emu/f09emu.sh estado
# → «túnel DEMO: proceso vivo; origen HTTPS (no se muestra) health HTTP 200»
```

Para cerrarlo: `demo-mobile.sh untunnel`. Cada túnel nuevo cambia el origen, y hay que **recompilar** la APK (el origen va dentro).

### 1.4 Activar frente a dictar

- **Con conexión:** sólo la activación (y la siembra, que usa `references`) necesitan el túnel y el Central.
- **Sin conexión:** el dictado es local: Vosk y whisper.cpp van dentro de la APK (`tool/voice_local/build_voice_apk.sh:43-44`). Tras activar y sembrar se puede cortar la red (`f09emu.sh red off`) para el recorrido de voz.
  - Esto afecta a **todo** el emulador: hay que coordinarlo.
  - Evita además que las operaciones de `.f09` se envíen por Sync al Central DEMO.

## 2. Entorno para la verificación final

### 2.1 Cuenta: `agricultor5` (Elena Condori, sintética)

- **Cuentas ya usadas:**
  - `agricultor1`: `.demo`, la guía DEMO.
  - `agricultor2`: «AC UX».
  - `agricultor6`: «AC VOZ».
- **Cuentas libres:**
  - `agricultor3` y `agricultor4` tienen historial de campañas (`demo-central.cjs:87`), y conviene no alterarlo.
  - `agricultor5` sólo tiene necesidades sembradas (`:94-95`).
- **El servidor admitiría varias instalaciones por cuenta.**
  - El registro es por `clientIdHash` (`Back/src/modules/iam/infrastructure/persistence/prisma-client-registration.repository.ts:35-75`), sin límite por persona.
  - El login crea una sesión nueva sin revocar las otras (`auth-v2.service.ts`, `login`).
  - Aun así, compartir cuenta mezclaría en el Central los datos de dos teléfonos. Por eso se propone una cuenta propia.
- **Rotar la contraseña no revoca sesiones** (`reset-user-password.use-case.ts:28-29`): `credential` y `references` no rompen otras instalaciones.
- **Credencial:** con el foco en «Contraseña», ejecutar `DEMO_PGPORT=15432 bash .../_wt/DEMO-BE/tool/demo/demo.sh credential agricultor5 emulator-5554`.
  - Comprueba que el campo enfocado es de contraseña antes de teclear (`demo-central.cjs:397-410`).
  - El correo es `agricultor5.demo@example.test`.

### 2.2 Siembra local

- **Precondiciones** de `seed_demo_mobile.dart`:
  - activación hecha;
  - titular creado desde la interfaz;
  - modo «Inventario compartido»;
  - copia sin sembrar.
- **Fecha:** `DEMO_DATE=2026-11-03`, la fecha de siembra del Central. Con la de hoy falla el período de la campaña.
- **Riesgo de esquema.**
  - `demo-mobile.sh seed-local` usa el código de DEMO-MOB, con el esquema **v13**.
  - La base de `.f09` es **v14**, con `voice_evidence` (comprobado: `user_version=14`).
  - Abrirla con v13 no está soportado: `AppDatabase` no tiene `onDowngrade`.
- **Solución:** `f09emu.sh sembrar [cuenta]` copia el mismo `seed_demo_mobile.dart` a `build/f09_emu/` (ignorado por git) y lo ejecuta con el **código F09**.
  - Comprobado en HOST el 2026-11-08: compila con F09 y se detiene en su precondición («Defina DEMO_DB»).
  - Guarda la base previa en `%TEMP%\agro_f09_emu\seed\agroquimicos_v2.db.antes`.
  - Rechaza `agricultor2` y `agricultor6`.

### 2.3 Audio sintético

- **`run_reference_check.sh` NO debe ejecutarse tal cual.**
  - Fija el paquete `.voz` (`:19`, `:36`).
  - Recompila e instala con `adb install -r` sobre «AC VOZ» (`:49`), lo que sustituiría su APK congelada `03124a0`.
- **Prueba instrumentada en `.f09`:** haría falta parametrizar el sufijo.
  - Esa APK no lleva origen. Si se instala sobre un `.f09` activado, lo deja sin origen.
  - Sólo tendría sentido **antes** de instalar la APK definitiva.
  - Mide el motor (Vosk + whisper con WAV a ritmo real), no la interfaz.
  - No se preparó la variante. Queda pendiente.
- **Recorrido por la interfaz:** la app lee el micrófono virtual (`AudioRecord`, `VOICE_RECOGNITION`), alimentado por la entrada del host (`hw.audioInput=yes`). Eso lo activa sólo Roderich.
- **Alternativa no verificada:** el emulador expone gRPC en el puerto 8554 con *token*, que **no se leyó**. Su API de inyección de audio podría alimentar ese micrófono con los WAV de `synth_reference_audio.ps1` sin usar el del host. Requiere un cliente gRPC y el *token* (secreto), así que necesita aprobación.

## 3. Scripts (`tool/f09_emu/`)

`f09emu.sh` sólo actúa sobre `com.comunidad.agro.agroquimicos.f09`:
- no desinstala ni borra datos;
- verifica el primer plano antes de cada toque;
- omite el contenido de los campos de contraseña en los volcados de uiautomator, que se leen por `/dev/tty`, sin archivo.

`f09emu.py` es su ayudante de sólo lectura.

| Orden | Uso |
|---|---|
| `estado` | Emulador, paquete, primer plano, Central y túnel (sin el origen), red |
| `compilar <sha>` | APK `.f09` x86_64 profile con el origen del túnel **vivo**, `AGRO_VOICE_EVIDENCE=true` y `AGRO_APP_COMMIT`. Restaura gradle y el manifiesto |
| `instalar <apk>` | Comprueba con `aapt2` que es `.f09` y ejecuta `adb install -r` |
| `abrir`, `primer-plano`, `ui`, `tocar`, `esperar` | Navegación con guarda |
| `permiso <regex>` | Toca en el diálogo del sistema sólo si es de «AC F09» |
| `ir voz\|compra\|plan\|aplicacion` | Operaciones → Más → Registrar por voz → opción |
| `captura <nombre>` | PNG en `%TEMP%\agro_f09_emu\capturas` y su SHA-256 |
| `microfono` | Permiso, `appops`, entradas abiertas, grabaciones del uid, `hw.audioInput` |
| `base` | `user_version`, cuentas de compras, aplicaciones y planes (con ítems), `sync_outbox`, consentimiento, `voice_evidence` por tipo y resultado, `quick_check`. Sin transcripciones |
| `sembrar [cuenta]`, `red on\|off` | §2.2 y §1.4 |

**Secuencia prevista:**
1. Roderich abre el túnel.
2. `compilar <sha final>`.
3. `instalar`.
4. `abrir`.
5. Activar (`demo.sh credential agricultor5`).
6. Crear el titular en modo compartido.
7. `sembrar`.
8. `abrir`.
9. `base`.
10. `red off`.
11. `ir compra|plan|aplicacion`.
12. `microfono`, `captura` y `base` tras cada confirmación.

## 4. Comprobación preliminar (EMULADOR, APK `fc6478d`, no definitiva)

- **APK:** `%TEMP%\agro_f09\apk\agrocuentas-f09-fc6478d-x86_64-profile.apk`.
  - SHA-256 `46d5174ebd640f05efe0f03634c19e2c101c8cbb9b4f96fd23e198f4899eb427`.
  - `aapt2`: paquete `com.comunidad.agro.agroquimicos.f09`, etiqueta «AC F09», `x86_64`, permisos `INTERNET` y `RECORD_AUDIO`.
- **Instalación:** `adb install -r` → `Success`. No había `.f09` antes, y ningún otro paquete se tocó.
- **Pantalla inicial:** «Agrocuentas», «Active la aplicación en línea con su cuenta para empezar a registrar.» y el botón «Activar en línea».
  - Captura `prelim_fc6478d_01_inicio.png`, SHA-256 `9683b2c7f7367d4fcc08208de20f4b67f1c51de332aba3fd2a14f9999eeed04e`.
- **«Activar en línea»** abre «Activar cuenta / Primera activación / Vincule esta instalación con su cuenta para empezar a registrar. No se borra ningún dato.», con los campos «Correo» y «Contraseña» y los botones «Activar» y «Continuar».
  - Captura `prelim_fc6478d_02_activar.png`, SHA-256 `b12de521b6697de566ab344abc74890d56d3e612323addad4b733582ce69632c`.
  - **No se pulsó «Activar»:** sin origen, terminaría en «La conexión segura todavía no está configurada.» (§1.2). Ese mensaje no se observó en pantalla.
- **`microfono`:**
  - `RECORD_AUDIO granted=false`; `appops` `ignore`;
  - `Inputs (0)`; 0 grabaciones;
  - `hw.audioInput=yes`.
- **`base`:** `user_version=14`, todas las tablas en 0 (también `voice_evidence` y su consentimiento), `quick_check=ok`.
- **Guardas probadas:**
  - con «AC UX» en primer plano, `ui` y `primer-plano` se niegan;
  - `compilar` se niega sin túnel;
  - `sembrar agricultor2` se niega;
  - `ir compra` se detiene porque, sin activar, no hay «Operaciones».

## 5. Bloqueos

- **Túnel:** no hay activación, siembra, APK definitiva ni recorrido (§1.2).
- **Micrófono del host:** el recorrido por voz en la interfaz lo hace Roderich.
- **Audio sintético en la interfaz:** sin vía preparada (§2.3).
- **Ninguna acción denegada** en esta sesión.
- `.f09` (fc6478d) queda instalado y en primer plano en la pantalla de activación. El emulador estaba antes con «AC UX» en primer plano.
