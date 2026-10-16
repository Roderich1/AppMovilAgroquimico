# F06 (D4) — Ruta física del consumo: agricultor 1 en el POCO

- **Fecha real:** 2026-10-16, de 04:39 a 04:47 UTC (00:39–00:47 en La Paz).
- **Ejecución:** Claude Code, con la autorización delegada de Roderich Rendón para este bloque. Usó una aplicación aislada y sólo datos sintéticos.
- **Revisiones:** las capturas las revisó Claude Code (revisión técnica automatizada del contenido). No consta inspección personal de Roderich ni revisión del tutor.

## Entorno

| Elemento | Valor |
|---|---|
| Dispositivo | POCO X5 Pro 5G `22101320G`, Android 12 (API 31), MIUI `V14.0.7.0.SMSMIXM`, zona `America/La_Paz` |
| Copia aislada | `com.comunidad.agro.agroquimicos.f06d4` («Agrocuentas F06-D4»), depurable, instalada el 2026-10-16 00:39:21 hora local. APK compilada sobre Mobile `5e7ed78470958df3c79ccd73fa6e25f39497b37c`. SHA-256 `31484f6e602aa273c19b62035ef7f52e809103d49a0b076018ad21e5e73680b2`. Sufijo, etiqueta y origen sólo en la compilación, no commiteados |
| No tocadas | La app normal (`firstInstallTime=lastUpdateTime=2026-09-24 13:04:32`, antes y después) y la copia `.f03res01` de #71, que sigue instalada con sus datos |
| Herramientas | `tool/f06_d4/` en `7be6aa0` (sólo corrige la ruta de la identidad de instalación respecto de `5e7ed78`) |
| Backend | `3c01a160713a7712e13608731df18f4ae4eb0790`. API local 3201, `NODE_ENV=development`, `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic`. Base desechable `agro_f06d4_poco` en el contenedor propio `agro_f06d4_pg` (no es `agro_f03res01_pg`) |
| Transporte | Túnel HTTPS temporal (Cloudflare quick tunnel) hacia un observador que registra sólo método, ruta y estado. Se abrió para esta sesión y se cerró al terminar; el origen no se publica |

## Datos locales

La base del teléfono se sembró en el host con `tool/f06_d4/seed_device_db_test.dart`:

- **Fuente:** las filas de F1 de [`F06_DATASET.csv`](F06_DATASET.csv), con el mismo helper que la reconciliación automatizada.
- **Titular:** vinculado al Member del agricultor 1 en `agro_f06d4_poco`.
- **Instalación:** la referencia de instalación es la de la propia copia. La app no trató la base como restaurada de otra instalación.
- **Vínculos:** las referencias de campaña y producto se leyeron en sólo lectura de esa base.
- **Copia al teléfono:** con `run-as`. SHA-256 idéntico en host y teléfono: `c144a6e187c1fae28d1cd4b13e3cf346724e1f9d4598a213bc4e21191d43db51`.

La vinculación por la interfaz y la declaración de necesidades ya se ejercitaron físicamente en D3 ([F05_MOBILE_SYNC_DEVICE](F05_MOBILE_SYNC_DEVICE.md)). Aquí sólo se ejercita la ruta nueva de D4.

## Pasos y resultados

| Hora UTC | Paso | Observado | Resultado |
|---|---|---|---|
| 04:39:32 | Primera apertura de la copia (antes de sembrar) | «Activar en línea»; crea su identidad de instalación | — |
| 04:40:37 | Siembra copiada; se abre la copia | Inicio con los datos sembrados; «La sesión no está disponible…» | PASS |
| 04:41:42 | Activación con el correo autocapitalizado por el teclado («Juan.perez…») | `POST /auth/v2/login 401`; «Revise el correo y la contraseña…» | Hallazgo (ver abajo) |
| 04:42:24 | Activación con el correo en minúsculas | login 200 → `POST /auth/clients` 201 → `POST /auth/v2/session/client` 201 → `GET /auth/v2/me` 200; «Cuenta vinculada en este dispositivo» | PASS |
| 04:42:48 | «Verificar acceso en línea» | `POST /auth/v2/refresh 200`. Inicio muestra a la vez «El estado en línea aún no fue verificado» y «Acceso en línea verificado para esta sesión» | PASS. Se reproduce el defecto conocido #83, corregido en el PR #84, que no está en esta compilación |
| 04:43:47 | Ciclo del worker | 3 × `POST /sync/v1/push 200`: las necesidades sembradas, ACKED al primer intento | PASS |
| 04:43–04:44 | «Consumo para el sindicato» | 6 totales «Nuevo: se publicará». La tabla de abajo coincide con la fila F1 del CSV. «No se incluyen 1 línea(s) de familiares o terceros» | PASS |
| 04:44:16 | «Publicar consumo al sindicato» → diálogo → «Publicar» | El diálogo lista los 6 totales y dice «Cada total sustituye al anterior; no se suma». Antes de confirmar no había filas nuevas en la outbox | PASS |
| 04:44:20–21 | Envío | 6 × `POST /sync/v1/push 200`; outbox 4–9 `CONSUMPTION_TOTAL PUBLISH` ACKED al primer intento. La pantalla pasa a «Sin cambios: Sincronizado» y el botón queda deshabilitado | PASS |

**Totales de la vista previa:**

| Campaña | Producto | Total |
|---|---|---|
| verano F06 | Belator | 4 L |
| verano F06 | Glifosato F06 | 4 L |
| verano F06 | Urea F06 | 12 KG |
| invierno F06 | Belator | 1,2 L |
| invierno F06 | Bellator | 0,8 L |
| invierno F06 | Mancozeb F06 | 3 KG |

**Central contra el oráculo:**

- Comando: `tool/f06_d4/device.sh central`.
- Volcado de sólo lectura de `agro_f06d4_poco`, comparado con las filas F1 de [`F06_EXPECTED_CONTRIBUTIONS.csv`](F06_EXPECTED_CONTRIBUTIONS.csv).
- Resultado: `Central: obtenidas=9 esperadas=9 faltan=0 sobran=0` y `CENTRAL COINCIDE CON EL ORÁCULO`.
- El journal de esa base tiene 9 operaciones.

## Registro de la app (addendum de #71)

- **Captura de logcat:**
  - el buffer se amplió a 16 MiB al empezar, para que no rotara;
  - la primera línea del UID de la copia (04:39:32Z) coincide con el inicio de la captura;
  - la última es de 04:42:25Z; después no hubo más líneas de ese UID.
- **Escaneo en memoria:**
  - patrones: JWT, UUID, valores opacos base64url de 43 caracteres o más (refresh tokens) y nombres de campos sensibles sin distinguir mayúsculas;
  - logcat: `líneas=334 JWT=0 UUID=0 opacos43=0 campos=0 FATAL=0`;
  - registro propio: `líneas=10`, todo 0.
- **Control positivo** con valores sintéticos inventados: los patrones detectan 1/1/1/3, lo esperado.
- No se guardó ni se publicó logcat crudo.
- **Alcance:** cubre login, registro de cliente y un refresh 200. No cubre los caminos 401 de E-1 y E-2 de #71.

## Ajustes del teléfono

- `stay_on_while_plugged_in`: de 0 a 2 durante la sesión; vuelve a 0.
- Buffer de logcat: de 2 MiB a 16 MiB; vuelve a 2 MiB. Al reducirlo, Android descartó las líneas que había en ese buffer circular del sistema; no hay datos de usuario afectados.
- La copia `.f06d4` queda instalada y detenida.

## Capturas

Sólo con datos sintéticos; no se versionan. SHA-256:

| Captura | SHA-256 |
|---|---|
| D4-01-inicio-sembrado | `1157530bfa3ea87129f7c0418797b21a68824499543e9841fe5ac973cef11bf0` |
| D4-02-activada | `f64067204bfa39c2088eb966ee7d784e66bec29a38d2b19f325d74d786c9bd9b` |
| D4-03-acceso-verificado | `089d90de0683ff89f45372a546dee7d63b3e0c0f83eac9b2a53afec8c4f7aadf` |
| D4-04-sincronizacion | `195e55773d531ecf4676694d889533fe19b7771510830d4480dd513f3fef78ed` |
| D4-05-vista-previa | `692298ea97a02068a9c90526d295ef9d0173dda534b2d5930ab707c1b83952cf` |
| D4-06-confirmacion | `68517e7a231ac68443937271630b5f73debe673e98ed4eddd09dde090f462050` |
| D4-07-publicado | `c0bfaecb5c81c8fbbca8742df41db10f6981fe93727c3a34851513ae415612ca` |

## Hallazgos

1. **Correo autocapitalizado en la activación.**
   - El teclado puso en mayúscula la primera letra del correo y el login respondió 401. El mensaje no orienta sobre la causa.
   - En la sesión de #71 ya ocurrió lo mismo con otra cuenta ([F03_RES_01_DEVICE](F03_RES_01_DEVICE.md) §4).
   - O el campo debe desactivar la capitalización, o el correo debe normalizarse.
   - Se registra como hallazgo; no se corrige en este bloque.
2. **Mensaje de sincronización desfasado.** En la pantalla de sincronización se vio «Verifique el acceso en línea para enviar» después de verificar el acceso. Un momento después el worker envió las necesidades. Es un hallazgo menor: no se reprodujo ni se investigó.
3. **Defecto #83.** Se reprodujo el doble mensaje de estado; la corrección está en el PR #84, aún sin fusionar.

## Qué no prueba esta sesión

- **Reversión en el teléfono.** No se ejercitó en el teléfono; la reversión, el familiar y la cancelación se verifican con la reconciliación automatizada contra Central (`Agro_Sindicato_Backend-Web/docs/evidence/F06_RECONCILIATION.md`; artefactos en [`F06_RUN_20261016/`](F06_RUN_20261016/)).
- **Reenvíos.** Tampoco se ejercitaron en el teléfono; la pérdida de ACK en dispositivo se probó en D3.
- **Necesidades declaradas.** No miden nada nuevo de D4: se publicaron porque estaban en la base sembrada, y su ruta física es la de D3.
