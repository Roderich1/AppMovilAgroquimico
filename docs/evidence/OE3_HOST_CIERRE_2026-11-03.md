# OE3: pruebas HOST y correcciones documentales del cierre (2026-11-03)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-03 (UTC). Las comprobaciones del §1 corrieron de 15:58:30Z a 16:10:44Z y las del §2 hasta las 16:15Z; las horas exactas de cada ejecución van en su sección |
| Procedencia | **HOST** únicamente: Windows 11, Flutter 3.47.2 stable, `sqflite_common_ffi`. Nada de esta página es DEVICE ni EMULADOR |
| Rama | `test/oe3-host-cierre`, creada desde Mobile `origin/main` `5b5b318` |
| Último commit de código (pruebas) | `62df33602566bdf8e458148b5cf155923c278cfb`. Los commits posteriores sólo cambian `docs/`: `git diff --stat 62df336 HEAD -- lib test pubspec.yaml pubspec.lock` sale vacío |
| `lib/` | **Sin cambios** frente a `5b5b318`. Ninguna prueba reprodujo un defecto de la app |
| Fuente de las tareas | Inventario de OE3 del 2026-11-03, Backend PR #200 (`docs/evaluation/OE3_CIERRE_INVENTARIO_2026-11-03.md` en `docs/oe3-cierre-revision`, `5b6d84a`), §4 y §6 |

## 1. Comprobaciones globales sobre `62df336`

Ejecutadas una vez, en serie, sin otro proceso pesado en paralelo (2026-11-03, de 15:58:30Z a 16:10:44Z).

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 371 archivos, 0 cambiados; salida 0 |
| `flutter analyze` | «No issues found!»; salida 0 |
| `flutter test --reporter expanded` (suite completa) | **2249 pasan, 3 omitidas, 5 fallan**; salida 1 |

**Las 5 fallas no tocan nada de esta rama** (las pruebas nuevas son archivos aparte, cada uno en su isolate, y `lib/` no cambió). Son de tres archivos de pantalla:

| Archivo | Prueba | Fallo en la suite | El archivo solo, sobre el mismo código |
|---|---|---|---|
| `f03_access_recovery_app_test` | «restored elsewhere: another account stores nothing…» | `Expected: activated, Actual: restoredRequiresActivation`, y después `UnmountedRefException` | **3/3 pasan** (16:11Z) |
| `f10_x01_pago_revision_test` | (b) «Sí, pagué todo» con fecha de campaña cerrada | No encontró `late-explanation`; después, un tiempo de espera de 10 min | **3/3 pasan** (16:12Z) |
| | (c) pago posterior desde Compras | `'!inTest': is not true`, en cascada del anterior | |
| `f12_est_07_estimation_ui_test` | «con conexión: consulta FARMER…» | No encontró «Copia guardada en este teléfono.»; después, un tiempo de espera de 10 min | **4/4 pasan** (16:12Z) |
| | «un rechazo de política borra la copia…» | `'!inTest'`, en cascada | |

- **Lectura:** el patrón es el de una espera que no llega bajo la carga de la suite completa. Es como el de `f10_x01_pago_datos_test`, ya conocido. No se corrigieron, porque están fuera del alcance, y no se reintentó la suite completa.
- **Omisiones:** las 3 son de la suite existente; ninguna de esta rama. En el registro sólo aparece el motivo de una: «sin AGRO_E2E_BASE_URL (Backend local desechable)».
- **No se afirma** que fallen o pasen en `5b5b318`: allí no se ejecutaron hoy.

Las 20 pruebas nuevas se ejecutaron juntas sobre HEAD `46d09e5` (mismo código que `62df336`) a las 16:14:29Z: `flutter test test/oe3_auth_01_403_404_entorno_test.dart test/oe3_rec009_pago_guardas_test.dart test/oe3_f04_close_01_necesidad_futura_test.dart test/oe3_rec008_camara_doble_test.dart` → **20 pasan**. En la suite completa ninguna marcó error.

## 2. Por tarea

Antes de escribir cada prueba se buscó en `test/` si otra ya cubría el criterio (`grep` de los mensajes, los métodos y los tipos implicados).

### 2.1 #18 AUTH-01: 403, 404 y `AGRO_API_BASE_URL`

- **Antes:**
  - ninguna prueba de `AuthV2Api` cubría 403 ni 404;
  - `grep -rn "AuthApiErrorKind.forbidden\|AuthApiErrorKind.notFound" test` no da nada;
  - el mapeo sólo se probaba sobre `login`;
  - ninguna prueba llamaba a `ApiEndpointConfig.fromEnvironment`.
- **Nuevo:** `test/oe3_auth_01_403_404_entorno_test.dart`.
  - Grupo «#18: 403 y 404», 12 casos: 403 → `forbidden` y 404 → `notFound` en las seis operaciones (`login`, `registerClient`, `bindSessionClient`, `currentContext`, `refresh`, `logout`). Cada caso exige un solo envío y un error sin cuerpo, origen, tokens ni contraseña.
  - Grupo «#18: AGRO_API_BASE_URL», 1 caso que comprueba lo compilado en cada ejecución.
- **`AGRO_API_BASE_URL` es una constante de compilación** (`String.fromEnvironment`). Una prueba no puede cambiarla mientras corre. Por eso la expectativa se declara con `OE3_ENV_EXPECT`, y un valor desconocido falla:

| Ejecución | Comando | Resultado |
|---|---|---|
| Ausente (suite y CI) | `flutter test test/oe3_auth_01_403_404_entorno_test.dart` | 13 pasan. `fromEnvironment` lanza `configuration`; `apiEndpointConfigProvider` da `null`; `authHttpClientProvider` lanza `ProviderException` con `configuration` dentro |
| Válida | `… --dart-define=AGRO_API_BASE_URL=https://api.example.test:8443 --dart-define=OE3_ENV_EXPECT=valid` | 13 pasan. El origen es el compilado y la ruta resuelve |
| Inválida | `… --dart-define=AGRO_API_BASE_URL=http://api.example.test --dart-define=OE3_ENV_EXPECT=invalid` | 13 pasan. Rechazo `configuration`, sin el valor en el mensaje |
| No analizable | `… "--dart-define=AGRO_API_BASE_URL=https://[" --dart-define=OE3_ENV_EXPECT=unparsable` | 13 pasan. `Uri.tryParse` da `null`: es la otra rama |

- **Lo que sigue sin poder probarse en HOST:**
  - el valor que lleva compilado una APK concreta (la ausencia en el teléfono está en #19 DEVICE-B);
  - el permiso `INTERNET` y el build release dentro de la suite.
- **Sigue pendiente:** el mapeo de 400/401/409/429/500 en las cinco operaciones distintas de `login`.

### 2.2 #45 REC-009: pago que supera el saldo y compra revertida

- **Antes:** `grep -rn "supera el saldo\|no está activa" test` no da nada. Las pruebas de pago existentes (`f10_x01_pago_datos_test`, `f10_x01_pagador_titular_test`, `f04_repository_guards_test`) cubren la fecha futura y el pagador, no estas dos guardas.
- **Nuevo:** `test/oe3_rec009_pago_guardas_test.dart`, con dos pruebas. Usa una compra en compartida con un tercero que lleva cargo en `account_transactions`.
  - «un pago que supera el saldo se rechaza sin tocar compras, pagos ni cuentas internas; el que lo deja en cero se acepta»: un pago mayor que el total; un centavo más del saldo después de un pago parcial; el saldo exacto, que sí entra; y uno más con la compra saldada.
  - «una compra revertida no admite pagos, aunque su saldo pagado haya vuelto a cero; nada cambia»: 1, 500 y el total después de revertir una compra con un pago; y una compra revertida sin pagos.
- **En cada rechazo:** `dumpTables` es idéntico fila por fila en todas las tablas, cuentas internas incluidas, y `settlements()` también.

### 2.3 #122 F04-CLOSE-01: necesidad fechada después de hoy

- **Antes:** `f04_campaign_effective_date_test` («el alta y el cierre tampoco dejan fuera una necesidad declarada ni sus versiones») lo prueba con fechas **pasadas**. `F04_REPETICION_DEVICE.md` §4 declaraba la deducción y la falta de prueba de la retirada.
- **Nuevo:** `test/oe3_f04_close_01_necesidad_futura_test.dart`, con dos pruebas.
  - Por `DeclaredNeedStore.declare` (el selector de la pantalla llega hasta 2100):
    - una necesidad declarada con fecha de hoy + 5 días, y otra retirada (versión `CANCELLED`) con esa fecha;
    - `closeCampaign` se rechaza sin fin, con fin hoy (el mensaje nombra el día futuro) y con fin en ese día («no puede ser posterior»);
    - todas las tablas iguales; la campaña sigue `ACTIVE` sin `end_date`.
  - Sólo la tabla de versiones: una versión `CANCELLED` fechada en hoy + 3, sobre una necesidad del 15/10, también impide cerrar.
- **Sigue siendo sólo HOST.** Lo que el inventario deja también sólo en HOST para #122 (cancelar o rechazar, el vínculo central) no cambia.

### 2.4 #44 REC-008: camino de la cámara con un doble

- **Antes:** `rec_008_invoice_viewer_test` prueba `storeInvoiceImage` y el visor, y declara la cámara fuera de su alcance. `grep -rn "ImagePicker\|ImageSource" test` no da nada.
- **Nuevo:** `test/oe3_rec008_camara_doble_test.dart`, con tres pruebas de widget sobre `AgroApp` completa.
  - El doble, `_CameraDouble`, extiende `ImagePickerPlatform`. **Es un doble de prueba, no una cámara física.**
  - «cámara (doble): pide ImageSource.camera, muestra la miniatura y al confirmar copia la foto a invoices/ con sus bytes»: `imageQuality` 82 y `maxWidth` 1800; `invoice_image_path` en `<documentos>/invoices/invoice_<µs>.png`, con los mismos bytes del PNG sintético.
  - «cámara cancelada (doble devuelve null): no se adjunta nada y la compra se guarda sin foto».
  - «permiso de cámara negado (doble lanza PlatformException): se avisa y la compra se guarda sin foto»: «No se pudo adjuntar la factura. Revise los permisos.», sin el detalle interno de la excepción.
- **Espera:** el final del guardado se espera con `waitUntil(...)`, que falla con diagnóstico; no hay esperas fijas.
- **Lo que no prueba el doble:** el permiso real de Android, el intent de captura, la recodificación del JPEG por el sistema ni un modelo de teléfono. En ningún teléfono se usó la cámara.

### 2.5 #83 F03-BUG-01: repetición con SHA registrado

- **Prueba existente**, sin cambios: `test/remote_session_screen_test.dart`, grupo «un solo mensaje de estado de acceso (#83)».
- **Ejecución:** 2026-11-03 a las 16:12:50Z, sobre HEAD `46d09e5`, con el mismo `lib/` y `test/` que `62df336`. Comando: `flutter test test/remote_session_screen_test.dart --reporter expanded`.
- **Resultado:** **11/11 pasan**, entre ellas los cuatro casos del grupo #83: arranque sin verificar, verificación correcta, reautenticación requerida tras un 401 y reapertura con el guard en cuarentena.
- **Lo que no cambia:** la evidencia original (`F03_BUG_01.md`, SHA inferido `1d3ef90`) conserva su fecha. Esta ejecución no se le reatribuye.

### 2.6 Documentación (commits sólo de `docs/`)

| Tarea | Archivo | Qué |
|---|---|---|
| a | `docs/13_LOCAL_STORAGE.md` | Notas del 2026-11-03 en el Resumen y junto al §3.1 y su diagrama. El respaldo vigente `.agrobackup` incluye las fotografías: comprobado en `backup_service.dart` y `backup_encryption.dart`, en `backup_container_test`, `f08_late_draft_photos_test`, `F08_MOBILE_RESTORE.md` §5 y el caso D de `F01_F08_DEVICE_FINAL_2026-10-24.md`. El texto histórico se conserva |
| b | `docs/evidence/REC_CONCILIACION_2026-10-19.md` (#44 y #55) | El caso C de `F10_RESTORE_DEVICE.md` es una **base** alterada. La foto alterada o ausente es sólo HOST (comentario 6258688375 de #36). También son sólo HOST las rutas reconstruidas en otra carpeta: el caso A es la ruta de código modificada y en F08 §5 la carpeta coincidía |
| c | `docs/evidence/F03_AUTH_INDICE_EVIDENCIA_2026-11-03.md` | Índice de #18–#22: caso → evidencia → SHA → procedencia → pendiente o NOT_MEASURED, con las pruebas nuevas de §2.1 |
| d | `docs/evidence/F04_GATE_DECISION_PROPUESTA.md` | Anexo fechado: P9 no es una transferencia. La transferencia tiene HOST y EMULADOR (`e5ba07c` en Bloque 2, D-07; `1027cd4` en UX-C1, reversión), y **ningún DEVICE**. El texto original queda visible |
| e | El mismo anexo, más notas en `F04_REPETICION_DEVICE.md`, `F04_FECHA_EFECTIVA_Y_CIERRE.md`, `F04_ACTIVACION_ANTICIPADA.md`, `F04_CAMPANA_FECHA_EFECTIVA.md` y `gate-f04-modo-propio-compartido.md` | D-F04-C1 superado. HOST en `F03_F04_RECUPERAR_ACCESO_RF13_RF03_HOST.md` (2026-10-23, `04162ff`); DEVICE en B1–B3 de `F01_F08_DEVICE_FINAL_2026-10-24.md` (POCO, `1d77c14`) |
| f | `docs/adr/F08-ADR-003-respaldo-cifrado-y-previo.md` §0.4 | Precisión fechada: el caso D cubrió la copia cifrada por el teléfono a través de B2 y la restauración con la clave correcta en una instalación nueva. La clave la tecleó un proceso, no una persona. Siguen pendientes la clave escrita a mano y otro modelo |

En `docs/architecture/` no hay ninguna mención de «D-F04-C1» (búsqueda del 2026-11-03).

## 3. Mutaciones

Cada guarda se rompió de forma temporal con `sed`, se ejecutó la prueba y se restauró con `git checkout`. Después de cada una, `git diff` del archivo sale vacío y su SHA-256 es igual al de antes. Ninguna mutación se commiteó.

| # | Archivo y cambio temporal | Prueba ejecutada | Resultado |
|---|---|---|---|
| M1 | `auth_v2_api.dart`: `403 => forbidden` → `403 => server` | `oe3_auth_01…` | **+7 −6**: fallan los seis casos 403 |
| M2 | `auth_v2_api.dart`: `404 => notFound` → `404 => server` | ídem | **+7 −6**: fallan los seis casos 404 |
| M3 | `api_endpoint_config.dart`: la clave pasa a `'AGRO_API_URL'` | ídem, con la variante `valid` | **+12 −1**: falla la de entorno |
| M4 | `api_endpoint_config.dart`: `Uri.tryParse(value) ?? Uri.parse('https://fallback.example.test')` | ídem, con la variante `unparsable` | **+12 −1** |
| M5 | `agro_repository.dart:1308`: `paid + amountBobMinor > total` → `paid > total` | `oe3_rec009…` | **+1 −1**: falla la de saldo |
| M6 | `agro_repository.dart:1284`: la consulta de la compra pierde `AND reversed_at IS NULL` | ídem | **+1 −1**: falla la de compra revertida |
| M7 | `agro_repository.dart:759`: `if (false && last != null …)` en `closeCampaign` | `oe3_f04_close_01…` | **+0 −2** |
| M8 | `agro_repository.dart:493`: versiones excluidas (`… AND 0`) en `_lastOperationDay` | ídem | **+1 −1**: falla «sólo la versión» |
| M9 | `agro_repository.dart:493`: sólo versiones `ACTIVE` | ídem | **+1 −1**: la retirada cuenta |
| M10 | `purchase_form_screen.dart`: el botón «Cámara» pide `ImageSource.gallery` | `oe3_rec008…` | **+0 −3** |
| M11 | `purchase_form_screen.dart`: se guarda `invoiceImage!.path` sin `storeInvoiceImage` | ídem | **+2 −1**: falla la de copia a `invoices/` |
| M12 | `purchase_form_screen.dart`: `invoiceImage = null` en lugar de la foto elegida | ídem | **+2 −1** |
| M13 | `dashboard_screen.dart:564` (#83): sin el mensaje remoto | `remote_session_screen_test` | **+8 −3**: dos del grupo #83 y «missing HTTPS configuration…» |
| M14 | `dashboard_screen.dart:569` (#83): sin la rama del guard en cuarentena | ídem | **+10 −1**: «reapertura con el guard en cuarentena» |

**Lo que las mutaciones no cubren:**
- en #45, la parte «tablas idénticas» no tiene una mutación propia, porque la transacción deshace cualquier escritura previa al rechazo;
- en la ruta de la cámara, el texto exacto del aviso de permiso.

## 4. Límites

- Todo es HOST. Ningún resultado de esta página se presenta como DEVICE ni EMULADOR.
- La cámara se simuló con un doble.
- `AGRO_API_BASE_URL` se probó con las variantes compiladas en estas ejecuciones, no con una APK.
- No se cambiaron campos del Project ni issues. Las decisiones del inventario de OE3 (§7) siguen siendo del autor.
