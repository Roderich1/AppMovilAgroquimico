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

## Segunda ronda: composición con la corrección del PIN (2026-10-24, 09:40–10:10 -04:00)

Tras aprobarse los deltas D1 y D2, se repitió el ensayo con:
- **Mobile** `comp/f01-f08-mob` `f7fbfd71e6e7b6e24fdbae84d8befd4e95d4075f`. Su árbol es igual al de #144 `d6d9c8c`, que incluye `00cc67b` de #143. CI run 40097786748: success, 1808 pruebas pasan y 4 se omiten por diseño.
- **Backend** `comp/f01-f08-be` `d35cd25`. Respecto a `fe0c26e` sólo cambia un spec, así que el runtime es el mismo `dist`.
- **APK** `.f01f08`, SHA-256 `99e632eedb6ec8c784b5a851d5dc63aa141bc48a24467af7b62b39ad9d3add2f`, igual al instalado. Se instaló con `install -r` y después `pm clear` sólo del paquete aislado.
- **Entorno nuevo**: base vacía, mismo teléfono y mismo operador.

**Los PIN** no aparecieron en ningún comando ni salida. Los generó en memoria un proceso local (`127.0.0.1:3149`): uno inicial, uno para el restablecimiento y uno erróneo. Ese proceso sólo los teclea en el teléfono, y al terminar los borró y se detuvo.

| # | Caso | Resultado | Lo observado |
|---|---|---|---|
| D3a | Acreditar al titular y enrolar el PIN | **PASS** | `login` 200 y `logout` 204. Después «Guardar PIN» y «PIN del titular configurado. Funciona sin conexión» |
| D3b | Restablecer el PIN en línea | **PASS** | Otra vez `login` 200 y `logout` 204, y un PIN nuevo |
| D3c | PIN anterior tras el restablecimiento | **PASS** | «PIN incorrecto» al ver la clave; el nuevo sí la muestra. Una autorización emitida antes del restablecimiento y conservada no se puede provocar desde la UI: está cubierta en host (F03 §8) |
| D6d | Ver la clave con el PIN | **PASS** | Con un PIN erróneo: «PIN incorrecto». Con el correcto: la clave en una ventana con `fl=SECURE` y `screencap` de 0 bytes. Tras ir a Inicio y volver sigue protegida; al cerrar el diálogo, `SECURE` desaparece y la captura vuelve (10 368 016 bytes). La única línea con la clave quedó oculta por el filtro |
| D6e | Cambiar la clave con el PIN y cancelar | **PASS** | La pantalla de cambio, protegida, y «Cancelar el cambio (se mantiene la clave actual)». La copia subida antes sigue «cifrada con su clave actual» |
| D4a | Revertir una compra con motivo y PIN | **PASS** | La compra queda «Revertida · Autorizada por el titular con el PIN de este teléfono · <motivo>», también tras reabrir la app |
| | | | `reversal_audit`: `PURCHASE`, motivo, actor (persona, vínculo, Member y tenant), `actor_method=LOCAL_PIN` y la referencia del enrolamiento; 2 efectos y la compra en `REVERSED` |
| D4b | Doble reversión | **PASS (UI)** | La compra revertida ya no ofrece menú. El rechazo en el repositorio lo cubren las pruebas de host (`rec_050`) |
| D5a | Compra con fecha de una campaña cerrada | **PASS (datos)** / **FAIL (mensaje)** | Diálogo «Fecha de una campaña cerrada» con motivo, y «Registrar para revisión». En la base: un borrador `PURCHASE`, sin compra ni lote nuevos, y la lista «Pendiente de revisión: sin efectos todavía». **Pero** la lista de compras anunció «Compra multiproducto confirmada; lotes e inventario creados». Corregido en `967006e`, todavía sin publicar |
| D5b | Confirmar con el PIN | **PASS** | El borrador pasa a `CONFIRMED` con `LOCAL_PIN`; se crea la compra 2 en la campaña cerrada (05/10/2026, 1200 Bs). Ninguna petición a la red, así que no se publicó nada |
| D5c | Rechazar con el PIN | **PASS** | Segundo borrador (06/10/2026) en `REJECTED` y «Rechazada sin efectos». No se creó ninguna compra (siguen 2) |

**Siguen en NOT_RUN:**
- D1 y D2 (recuperar acceso con una cuarentena real);
- D7e (pausa y liberación, sin Sync vinculado);
- D10 (Web).

**Al terminar**, los ajustes del teléfono volvieron a sus valores iniciales y el entorno quedó desmontado (sin contenedor ni puertos 3140, 3141, 3149 o 55470), sin limpiezas generales.

## Tercera ronda: recuperar acceso con una cuarentena real, y pausa y liberación con Sync vinculada (2026-10-24, 16:58–17:21 -04:00)

Cierre técnico del bloque. Sólo se ejecutan los recorridos que seguían en NOT_RUN: D1/D2, con una cuarentena real, y D7e, la pausa y liberación. Lo demás se reutiliza de las rondas anteriores sobre el mismo código de esos frentes.

| Pieza | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G, `22101320G`, serial `cc14247a` (`adb devices -l`) |
| Mobile | `comp/f01-f08-mob` `8b53ad81c136ab67c898aebdf3928efa0f29d6b0`: el árbol de #144 `22a32cb`, que contiene #143 `7f4536b` |
| APK | `.f01f08`, SHA-256 `0036d9332fca5fc564770bc7ec5aa24a9d5663cc6c5bef60383a67bf25761d39`, igual al `base.apk` instalado. Se instaló con `install -r` y después `pm clear` sólo del paquete aislado. Siguió habiendo 26 paquetes `com.comunidad.agro*` |
| Backend | `comp/f01-f08-be` `784958f`: el árbol de #163 `5cbf137`. `dist` se recompiló sobre ese SHA a las 16:55 |
| Observador | `tool/f03_res_01/observer.cjs` con el modo nuevo `drop-refresh-response`, SHA-256 `d66ad0245c9a4d7469058c75d68978b73df3663ef6d96879ae35f789c3e21758`. Retiene la respuesta de UN `POST /auth/v2/refresh` después de que Central lo procese. Es el mismo contenido que se usó en el ensayo, versionado en esta rama. Antes: `317d4b4d…ff98` |
| Campaña del sindicato | El Administrador sintético cerró «Campana Verano 2026» y abrió «Campana Invierno 2026» por la API real (`POST /campaigns/:id/close` y `/open`, ambos 200). Ninguna campaña sembrada admitía aportes el 24/10. Herramienta: `scratchpad A/dev/admin_open_campaign.cjs`, que no imprime token ni contraseña |

Preparación (datos sintéticos):
- activación con la cuenta D, titular «Juan Perez» y modalidad propia;
- campaña local «Ensayo sync», con fin previsto el 30/11, vinculada a «Campana Invierno 2026»;
- producto «Herbicida sync» (L) vinculado a «Glifosato 48 SL» (L→ML);
- tres declaraciones de necesidad:

| Op | Cantidad | Cómo se envió | Resultado |
|---|---|---|---|
| `1ebbffa7` | 25 L | Normal | ACK |
| `9aee51cc` | 40 L | Con `drop-push-response`: Central aplicó y la respuesta no llegó | El teléfono **reintentó solo** con el mismo `operationId` y Central lo deduplicó: ACK, 2 intentos, la misma hora de aceptación y **una sola entrada de journal** |
| `f0443cb9` | 55 L | Con `status-500-before`: no llegó a Central | Quedó `OUTCOME_UNKNOWN` |

Después:
- se creó la clave de respaldo, sin mostrarla, y se subió la copia de las 17:13 con `f0443cb9` todavía sin ACK;
- al quitar el fallo, «Sincronizar ahora» la envió: ACK a las 21:14:04Z;
- Central quedó con journal seq 1, 2 y 3, y la contribución vigente es `f0443cb9`, de 55 000 ML.

| # | Caso | Resultado | Lo observado |
|---|---|---|---|
| D7e-1 | Restaurar con una operación ya aceptada por Central | **PASS** | Al restaurar la copia de las 17:13, `f0443cb9` pasa a `RESTORE_PAUSED`. No se envía nada |
| D1a | Cuarentena real | **PASS** | «Verificar acceso en línea» con `drop-refresh-response`: Central respondió 200 al `refresh`, y el teléfono no recibió la respuesta (`RESPUESTA_RETENIDA`) |
| | | | Guard `en cuarentena=true`. La app indicó «El resultado remoto no puede confirmarse. No se reutilizará la credencial anterior», con el botón de reautenticar deshabilitado en ese estado. Al reabrir, «Se requiere volver a autenticar» |
| | | | El registro trae una línea `POST /sync/v1/push - RESPUESTA_CERRADA_A_LOS_30S`: es el cierre de esa misma respuesta retenida del `refresh`, porque la etiqueta del observador usa la ruta del push |
| D2a | Recuperar con otra identidad (cuenta E2) | **PASS** | `login` 200 y `logout` 204 del login nuevo. «Esa cuenta no es la vinculada a este teléfono». Guard sigue en cuarentena; titular, recuentos, vínculos y cola sin cambios |
| D1b | Recuperar con el mismo titular (D) | **PASS** | `login` 200, `session/client` 201 (mismo registro de cliente `cbaa69c7…`) y `me` 200. «Acceso en línea verificado». Guard en `false` y sesión en el slot b |
| | | | Comparado con el estado de antes (`device.sh db counts/owner/bindings/outbox`): sólo cambian el slot y la huella de la sesión cifrada. Titular, Member, tenant, los vínculos `VALID` y las 3 entradas de la cola son idénticos |
| | | | En Central siguen ACTIVE la sesión anterior y la nueva, con el mismo registro |
| D7e-2 | Recuperar acceso no libera la pausa | **PASS** | Tras D1b, `f0443cb9` sigue en `RESTORE_PAUSED`. «Sincronizar ahora» no envía ninguna petición y la mantiene en pausa |
| D7e-3 | Liberar explícitamente | **PASS** | «Liberar», y después «Liberar envíos restaurados»: **un solo** `POST /sync/v1/push` 200. `f0443cb9` en ACK, con 2 intentos y la hora de aceptación **original** (21:14:04Z) |
| | | | En Central (`check.sh sync D`) siguen 3 entradas de journal, una por operación, y la contribución en la secuencia 3 con 55 000 ML. **Sin duplicado** |

**Al terminar**, los ajustes volvieron a sus valores iniciales (`stay_on` 0, animaciones 1.0, sin modo avión, Wi‑Fi y datos activos) y el entorno quedó desmontado, sin contenedor ni puertos. Las contraseñas fueron de un solo uso, nunca hubo PIN en pantalla y la clave no se mostró.

**Límites:**
- La pausa y la liberación se probaron con declaraciones de necesidad. No se repitieron con consumo para el sindicato.
- La cuarentena se provocó con un fallo inyectado en el observador. Es una pérdida real de la respuesta en la red, no un fallo del servidor.
- La Web F07 queda en la evidencia del Backend (#162).
