# F09 / D-F04-C2 — Nota de cambio de dispositivo del ensayo físico (2026-10-17)

- **Qué es:** un cambio de **entorno** previo al ensayo, no un resultado. Se deja fechada antes de la primera toma y su SHA-256 se fija junto con las demás huellas (`fijado.json` del ensayo).
- **Fecha real:** 2026-10-17 (noche, America/La_Paz). Sesión A de Claude Code, por la delegación técnica de Roderich Rendón.
- **Instrucción que la motiva:** instrucción de Roderich del 2026-10-17 (noche), «Continúa la preparación y ejecución del ensayo F04-C2/F09 con la delegación vigente», puntos 2, 3 y 4: un único teléfono autorizado para el turno, registro de fabricante, modelo, Android/API y tipo de compilación, y nota fechada que cite el protocolo existente.
- **Protocolo que se conserva sin cambios:** [F09_VOZ_ENSAYO_FISICO_PLAN.md](../evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md) en el `main` Mobile `65f7cfc70d2dafc1c32da9a803fc55111c7a4c6e` (merge de MOB #116; CI 39081132396 SUCCESS), SHA-256 `bfbc8ee0db05989aa42ee4d77b972372181bab0ef26b0a8cfae51cad29257f75`. Esta nota no modifica D-F09-1…7 ni los escenarios V1–V19; sólo cambia el dispositivo en que se ejecutan.
- **Preparación vigente:** [F09_VOZ_ENSAYO_PREPARACION.md](../evolution/features/F09_VOZ_ENSAYO_PREPARACION.md) (MOB #114, `078d638`; actualización en MOB #117).

## 1. Dispositivo del ensayo

| Dato | Valor observado (`getprop` por adb, 2026-10-17) |
|---|---|
| Código de ensayo | **F09-ENS-01** |
| Fabricante | HONOR |
| Modelo | **JDY-LX3P** (`ro.build.display.id` JDY-L43P 10.0.0.181) |
| Android / API | **16 / 36** |
| Tipo de compilación | `user` |
| ABI | arm64-v8a |
| Zona horaria | America/La_Paz |
| Idioma del sistema | es-BO |
| Reconocedor de voz por defecto | Speech Services by Google (`com.google.android.tts`) |
| Estado adb | `device` (autorizado) |

El serial completo del teléfono se conserva **sólo** en las instrucciones locales de selección de la sesión A (cargador del entorno, fuera del repositorio) y en todos los comandos adb del ensayo se pasa explícitamente; no se añade a los registros versionados.

**Valores iniciales del teléfono registrados antes de tocar nada** (se restauran al terminar sólo si se cambian): `stay_on_while_plugged_in=0`, `screen_off_timeout=2147483647`, `screen_brightness_mode=0`, `font_scale=1.45`, `airplane_mode_on=0`, `wifi_on=1`, `location_mode=3`.

## 2. Qué cambia y qué no

- El protocolo de F09 nombraba al POCO X5 Pro como teléfono de la sesión A y al HONOR JDY-LX3P como `NOT_MEASURED` «si no está disponible» (D-F09-6). Por indicación de Roderich del 2026-10-17, el ensayo se ejecuta en **el teléfono nuevo conectado, que es un HONOR JDY-LX3P**. Por D-F09-6 el ensayo acredita **sólo ese modelo**; el POCO queda `NOT_MEASURED` para la voz en este turno. No se sustituye un teléfono por otro en silencio: este cambio queda aquí.
- Dos seriales no son prueba de dos modelos: el único modelo que este ensayo puede acreditar es el de la tabla anterior.
- Las evidencias ya cerradas en el POCO (F03, F04, F08, F10 y la primera tanda de #18) **conservan su dispositivo, su fecha y su SHA**. Este cambio no las reabre.
- En este teléfono no había ninguna copia aislada de Agrocuentas antes del ensayo: sólo la app normal (`com.comunidad.agro.agroquimicos`, que **no se toca**) y dos paquetes del banco de voz (`com.comunidad.agro.voicebench.*`, que tampoco se tocan). La copia del ensayo es `com.comunidad.agro.agroquimicos.f09voz` («Agrocuentas F09 voz»), nueva.
- Ninguna instalación hecha antes en el POCO se atribuye a este teléfono.

## 3. Base fijada para el ensayo

| Huella | Valor |
|---|---|
| `mobile_sha` | `65f7cfc70d2dafc1c32da9a803fc55111c7a4c6e` (árbol idéntico a `b22ceea`, HEAD de MOB #116) |
| `interpreter_tree` (`lib/voice_draft`) | `21c6704c4fd60bd3d07a7688a2fcc86f16bd25ca` |
| `protocol_sha256` | `bfbc8ee0db05989aa42ee4d77b972372181bab0ef26b0a8cfae51cad29257f75` |
| APK aislada | `com.comunidad.agro.agroquimicos.f09voz`, **debug**, SHA-256 `fe6878741e5321855c0a8eb397918bac408ce3e0165733d023309eef2db7ffb0`, compilada con `tool/f03_res_01/build_isolated_apk.sh` desde un worktree limpio en `65f7cfc`; `applicationId` comprobado con `aapt dump badging` antes de instalar |
| Backend del entorno aislado | `6e4a0e2ce8fb33ac3d6bf70e88cb6e60641456f0` (= `main` BE), 11 migraciones aplicadas, seed sintético con contraseñas rotadas; contenedor y volumen propios del ensayo; origen HTTPS temporal (Cloudflare quick tunnel, no se publica) |
| `set_sha256` (conjunto nuevo) | **pendiente**: lo escribe una persona fuera del repositorio; se fija antes de la primera toma de habla |

La huella de esta nota se calcula sobre el archivo tal como queda en el commit que la introduce y se anota en `fijado.json` y en la evidencia del ensayo.
