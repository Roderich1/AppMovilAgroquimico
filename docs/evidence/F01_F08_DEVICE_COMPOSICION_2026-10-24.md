# DEVICE de la composición F01–F08 (2026-10-24)

Ensayo físico **sintético**, en un entorno desechable. Lo operó la sesión A, la única que tocó el teléfono. No hay datos reales, no se aprueba ningún gate y el ensayo no es de Roderich ni del tutor.

Protocolo: `_briefs/PROTOCOLO_DEVICE_F01_F08_2026-10-24.md` (no versionado).

## Identidad

| Pieza | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G, modelo `22101320G`, serial `cc14247a`, Android 12 (API 31), MIUI `V14.0.7.0.SMSMIXM`, zona `America/La_Paz` |
| Mobile | `comp/f01-f08-mob` `bfee4dc863dc212cf4103efd48d6b4707e2ec6a0`. Su árbol es igual al de `feat/f08-respaldo-cifrado` `84f9d82`, apilado sobre #143 `c100265`. CI run 40088291742: success |
| Backend | `comp/f01-f08-be` `fe0c26e04d17019a17c157dba09495c23a83f139`, compilado en local (`npm ci`, `prisma generate`, `build`, `build:seed`) |
| APK | `tool/f03_res_01/build_isolated_apk.sh` en un worktree desacoplado y limpio, debug, con el origen del túnel del día |
| | Paquete `com.comunidad.agro.agroquimicos.f01f08`, etiqueta «Agrocuentas F01-F08» (`aapt2 dump badging`); minSdk 24, targetSdk 36 |
| | SHA-256 `87d0f478a0cb86f8655696efc037d3e51c647c47c688b51a13a19f624eb35511`, igual al del `base.apk` instalado (`sha256sum` en el teléfono) |
| | Instalado el 2026-10-24 a las 07:28 (-04:00). Antes no existía. Se pasó de 25 a 26 paquetes `com.comunidad.agro*`; los demás no se tocaron |
| Entorno | PostgreSQL `agro_a_f01f08_pg` (127.0.0.1:55470), API en el 3140, observador en el 3141 y quick tunnel de `cloudflared` 2026.10.0 |
| | Variables: `BACKUP_REQUIRE_CLIENT_ENCRYPTION=true` y `COLLECTIVE_SEALING=enabled`, sólo en este entorno. Seed sintético con contraseñas efímeras |
| | Desmontado al terminar: sin contenedor ni volumen, y nada escucha en 3140, 3141 ni 55470 |

**Ajustes del teléfono.** Antes: `stay_on_while_plugged_in=0`, animaciones 1.0, sin modo avión, Wi‑Fi y datos activos. Durante el ensayo `stay_on` valió 3. Al terminar se dejaron los valores iniciales, se borró el único temporal propio en `/sdcard` y no se hizo ninguna otra limpieza.

## Resultados

| # | Caso | Resultado | Lo observado |
|---|---|---|---|
| D0 | Activación y titular | PASS | `login` 200, `clients` 201, `session/client` 201 y `me` 200. Titular «Juan Perez», modalidad propia, esquema 11 |
| D3a | PIN: acreditar al titular en línea para enrolarlo | **FAIL** | «Confirmar en línea» no envió ninguna petición (el observador no registró ninguna) y la pantalla mostró «No se pudo acreditar al titular en línea». Véase más abajo |
| D3b | Efecto del fallo D3a | **FAIL** | Tras D3a, Inicio mostraba «Se requiere volver a autenticar…», y la pantalla de reautenticación tampoco salía a la red. Reabrir la app lo recupera, porque el estado sólo estaba en memoria; «Verificar acceso en línea» hizo `refresh` 200 |
| D3c, D4, D5 (confirmación), D6 (ver y cambiar la clave) | Acciones que exigen el PIN | NOT_RUN | Bloqueadas por D3a: sin PIN enrolado no hay autorización |
| D6a | Ver la clave sin PIN | PASS | Niega la acción («Configure el PIN del titular primero») y no muestra la clave |
| D6b | FLAG_SECURE en la clave pendiente | PASS | `dumpsys window`: `fl=… SECURE` en la ventana de la app. `screencap` devolvió **0 bytes**. Fuera de la pantalla de la clave, el flag desaparece y `screencap` devuelve 10 368 016 bytes. Ninguna imagen con la clave se guardó |
| D6c | Anotar y confirmar la clave | PASS | La tercera clave generada (véase «Incidencias») se confirmó y pasó a activa |
| D7a | Subir respaldo cifrado | PASS | `POST /me/backups` 201 (8 KB, esquema 11). El objeto del servidor (7983 bytes) empieza por `AGROENC\0`, no contiene «SQLite format», el nombre del titular ni el de la campaña, y su entropía es de 7,978 bits/byte |
| D7b | Restaurar con la clave del llavero | PASS | Antes había 2 campañas (una creada después del respaldo). Se descarga con `GET …/content` 200 y se pide confirmación («descifrada y verificada»). Después queda 1 campaña, la del respaldo |
| D7c | Clave incorrecta, en una instalación sin la clave | PASS | `pm clear` sólo del paquete aislado, reactivación y titular nuevo. Con una clave señuelo bien formada (versión y checksum válidos, aleatoria): «La clave de recuperación no corresponde a esta copia. Sus datos actuales se conservan». La base no cambió, no se creó `previo/` y `files/remote_backups` quedó vacío |
| D7d | Cancelar | PASS | Sin cambios en la base |
| D7e | Pausa y liberación sin duplicación | NOT_RUN | No había Sync vinculado: no hay outbox que pausar |
| D8 | `.previo` tras restaurar | PASS | `databases/previo/copia.previo-…db` y `registro.json`, con `rw-------` del uid de la app. La entrada está `finalized`, y la copia previa conserva el estado anterior (2 campañas) |
| D9 | Reglas Android en el APK | PASS (inspección) | Véase la sección siguiente. **No es un Auto Backup ni un D2D ejecutados** |
| D1, D2 | Recuperar acceso con la misma cuenta y con otra cuenta | NOT_RUN | Exigen una sesión en cuarentena real, que no se provocó sin inyectar un fallo. La pantalla de D3b no sustituye este caso |
| D10 | Web: publicación, sellado e histórico | NOT_RUN | No se levantó la Web, para no alargar la sesión |

### D3a: causa y corrección

`ownerOnlineVerificationProvider` usaba `RemoteSessionController.reauthenticate`. Desde `1aa3b52` (2026-10-01), `reauthenticate` sólo recupera una sesión en cuarentena: si el guard no está en cuarentena, aborta antes del login y emite `requiresReauthentication`. Las pruebas de host inyectaban un `reauthenticate` simulado, así que no lo detectaban.

La corrección está en `feat/f03-recuperar-acceso` `96c1ad6`, **sin publicar**: su push queda fuera del lote autorizado y espera la aprobación de Roderich.
- `RemoteSessionCoordinator.confirmAccount` hace un login nuevo, lo valida contra la misma cuenta, Member y tenant, y lo cierra siempre con `logout`. No toca la sesión, el guard ni el estado. El login v2 del Backend no revoca otras sesiones, y `logout` sólo revoca la suya (`auth-v2.service.ts`).
- Pruebas:
  - `remote_session_coordinator_test`: 64 pasan, 9 de ellas nuevas;
  - `f03_owner_online_confirmation_test`: 2 nuevas, con el provider real. Con el cableado anterior falla (mutación);
  - `f03_local_owner_credential_test` (25), `remote_session_screen_test` (11), `f03_access_recovery_app_test` (3), `f04_rf13_reversal_audit_test` (17), `rec_050_reversal_rules_test` (6), `destructive_actions_test` (3) y `f04_rf03_late_operations_test` (13): todas pasan;
  - `flutter analyze`: sin avisos.
- Falta volver a ejecutar en el teléfono D3–D6 con un APK que incluya la corrección.

## D9: reglas empaquetadas (`aapt2` 2.20, build-tools 37.0.0)

- `dump xmltree AndroidManifest.xml`: `application` tiene `android:fullBackupContent=@0x7f0e0000` y `android:dataExtractionRules=@0x7f0e0001`.
  - No declara `android:allowBackup`, así que vale el valor por defecto: `dumpsys package` muestra `ALLOW_BACKUP`. La protección viene de las reglas, no de desactivar el respaldo.
- `dump resources` resuelve `0x7f0e0000` a `xml/backup_rules` y `0x7f0e0001` a `xml/data_extraction_rules`.
- `res/xml/backup_rules.xml` (Android ≤ 11) y las dos secciones de `data_extraction_rules.xml` (`cloud-backup` y `device-transfer`, Android 12+) excluyen lo mismo:
  - los dominios enteros `database`, `root`, `file`, `sharedpref` y `external`;
  - por nombre:
    - los tres archivos de cada almacén seguro (sesión, credencial del titular y llavero de respaldos);
    - `AgrocuentasSessionPointer.xml`;
    - `database/previo`;
    - `file/remote_backups`.
  - Ninguna regla `include`.
- No se excluyen los dominios `device_*` (almacenamiento cifrado por dispositivo). No se comprobó si la app escribe en ellos.

## Incidencias del operador

Al leer la UI con `uiautomator`, el filtro del operador no cubría dos formatos, y **dos claves de recuperación pendientes** (sintéticas, sin confirmar) quedaron en la salida de la sesión A:
- la primera, en el formato numerado «1. XXXX 2. …»;
- la segunda, en el campo de confirmación como una sola cadena.

Las dos se **descartaron** en la app («Descartar esta clave y no subir respaldos») antes de activarse. Ninguna cifró nada.

La tercera clave, la activa, nunca se mostró:
- se leyó del volcado de UI dentro de un solo proceso y se tecleó en el campo de confirmación;
- el script sólo imprime el progreso;
- el filtro ahora oculta cualquier cadena de 12 o más mayúsculas o dígitos y los grupos numerados.

Hallazgo de paso: FLAG_SECURE no impide que la accesibilidad (`uiautomator`) lea la clave. Era lo esperado, y no se declaraba lo contrario.

No se capturó ni registró ninguna contraseña ni PIN. Las contraseñas eran de un solo uso (`credential.sh`) y no hubo PIN.

## Límites

- Es un único dispositivo y una única sesión de un operador.
- No se ejecutaron un Auto Backup ni un D2D reales.
- B2 real (#151) no se usó: el almacenamiento era el disco del Backend desechable.
- RF-03, RF-13 y F08 **no** se declaran cumplidos por este ensayo.
