# OE3: segunda tanda en el POCO y comprobaciones de sesión (2026-11-03)

**Qué es.** La continuación de `OE3_DEVICE_POCO_2026-11-03.md`, en un Central nuevo, desechable y con datos sintéticos. Cubre:
- los decimales en las transferencias;
- las sesiones remanentes, contra la API real;
- la aplicación multiproducto en modo compartido sin red;
- las filas de BE #18 que necesitan transporte controlado, más C12, C13, C17 y C33.

**Qué no es.**
- No es una revisión del autor ni del tutor.
- No cambia ningún gate.
- No mide nada en el HONOR, que no estaba conectado.
- No usa B2 ni ningún otro almacenamiento remoto de respaldos.

## 1. Entorno

| Elemento | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G (`cc14247a`), Android 12. Sólo este modelo |
| APK | `.oe3`, profile arm64, de Mobile `35a077020cef0dec5d335344dc3ace714d08bf6a`. Es `main` `0752127` más `tool/`; `lib/` es idéntico a `0752127` y a `b7a9813`. SHA-256 `e0145b560c293d391abfea3b197e6707d24124841ef9f76aacfcb4a5bf76b3b6`, instalada a las 18:27:20Z |
| Aviso de la compilación | Terminó con `exit 1`, pero sólo por la comprobación final del árbol: dos archivos de `tool/` tenían fin de línea CRLF y el contenido era idéntico (`git diff --ignore-cr-at-eol` vacío). No entran en la APK |
| Backend | Código de `main` `5973b49` (worktree `_wt/F12-EST-08`). Central levantado a las 18:17:45Z, con secretos nuevos sólo en memoria |
| Observador | `tool/f03_res_01/observer.cjs` con los modos nuevos de §5. Registra estado, `outcome`/`code` y el prefijo de 8 del id; nunca cuerpos ni cabeceras |

## 2. Decimales en las transferencias

**Base común.** Misma persona (Ana, 6 L de Glifosato), mismo producto, misma unidad y mismas existencias; destino, Beto.

| Entrada | Regla vigente (`docs/44_NUMERIC_INPUT_SPEC.md`) | Interpretación | Resultado en `main` |
|---|---|---|---|
| «1,5» | Válida: coma decimal | 1,5 L → 1500 en unidad base (`tryParseBase`, ×1000) | Confirmación «Glifosato: 1,5 L». Guardado: `transfers.quantity_base` 1500, con `TRANSFER_OUT` −1500 y `TRANSFER_IN` +1500 (captura `D1_decimal_coma_confirmacion.png`) |
| «1.5» | `malformed`: grupo de miles de 1 dígito (§4) | `tryParseBase` da `null` y el producto no entra en la selección | No avanza. Aviso: «Seleccione origen, destino y al menos una cantidad válida.» Se ve en la captura inmediata `D1_decimal_punto_main.png` y queda en `agrocuentas.log` |

**Por qué no avanza.** `submit` sólo ve una selección vacía y muestra el aviso genérico. Ese aviso no explica el motivo, aunque origen y destino estén elegidos. **Defecto de mensaje confirmado**, en HOST y en DEVICE.

**Corrección de la observación anterior.** En la sesión anterior anoté «no muestra ningún mensaje». Fue un error de medición: la captura se tomó cuando el aviso, que dura unos 4 s, ya había desaparecido.

**Corrección propuesta:** Mobile PR #185, en borrador. Muestra el mensaje de la regla con el nombre del producto y deja la regla igual. Regresión en `test/oe3_transfer_decimal_test.dart`.

## 3. Sesiones remanentes

**Cómo se midió.** Contra la API real (`127.0.0.1:3320`), con un cliente scriptado (`tool/oe3/sessions_check.cjs`) que hace las mismas llamadas que la app. Tres estados distintos:
- **estado almacenado:** la fila `AuthSession`;
- **autorización efectiva:** la respuesta real a `me`, `refresh` y `push`;
- **limpieza:** el `logout` explícito.

Salida completa en `oe3_sessions_check_2026-11-03.txt`.

| Caso | Estado almacenado | Autorización efectiva |
|---|---|---|
| Sesión anterior S1 tras reautenticarse en la misma instalación (S2 vinculada al mismo registro, sin `logout` de S1, como hace la app) | ACTIVE y vinculada | `me` 200, `refresh` 200 y `push` 200 |
| Desactivación de la cuenta | S2 ACTIVE, con su refresh sin consumir | `me` 401, `push` 403, `refresh` 401 y `login` 401 |
| Reactivación de la cuenta | S2 ACTIVE | El access y el refresh anteriores vuelven a dar 200: la sesión revive |
| Sesión creada antes de un vínculo interrumpido (login más `auth/clients`, sin bind) | ACTIVE sin vincular; caduca a los 7 días, y el refresh no amplía `expiresAt` | `me` 200 y `refresh` 200; `push` y `references` 403 |
| Limpieza | `logout` 204 de S1, S2 y S3, que quedan REVOKED | — |

**Contrato vigente.**
- **Access token:** se revalida en cada petición contra la sesión, el Member, el usuario, el tenant y el registro (`CurrentAuthContextResolver`; F02-IAM-04).
- **Desactivación:** debe impedir nuevos refresh mientras dure (F02 §F), y lo hace. **No exige revocar las sesiones.**
- **Sync:** exige una sesión vinculada a un registro ACTIVE (matriz F05, C22/C23), y así ocurre.
- **Reautenticación:** Mobile decide expresamente no limpiar el refresh antiguo tras un commit nuevo (`F03_MOB_AUTH_05_REFRESH_RECOVERY.md`), porque el guard impide reutilizarlo en el teléfono.

**Resultado.** **No hay incumplimiento del contrato escrito.** Queda una diferencia que decide el autor: la sesión anterior a la reautenticación no es una fila muerta, sino una credencial válida en el servidor durante su vigencia (hasta 7 días). Su refresh sigue en el slot inactivo cifrado del teléfono.

**Opciones de corrección,** sin aplicar:
- un `logout` *best-effort* de la sesión anterior tras el commit, que el diseño de Mobile rechazó por la exposición en memoria;
- o que Central revoque las otras sesiones del mismo registro al vincular una nueva.

No se revocó nada y no cambia el acceso sin red.

## 4. Aplicación multiproducto en modo compartido sin red (E-F04-2)

**Pasos.**
1. A las 18:42:22Z, modo avión.
2. Aplicación de Beto en «Chaco Sur» (3 ha): Glifosato 2 L (había 5,5 L; quedan 3,5) y Atrazina 1,5 L (había 5 L; quedan 3,5).
3. Resumen: 200 + 120 = 320 Bs, «Se cargará a Beto Sintetico: 320,00 Bs» (`E_F04_2_resumen_sin_red.png`).

**Resultado.**
- **Base local:** 1 aplicación con 2 productos; `APPLICATION_OUT` −2000 y −1500; `USAGE_CHARGE` de Beto 32000.
- **Persistencia:** tras `force-stop` y reapertura sin red, la aplicación sigue en la lista.
- **Red:** 0 peticiones en todo el tramo.

**PASS.** La excepción E-F04-2 deja de hacer falta.

## 5. Filas de transporte controlado (BE #18) en el teléfono

**Qué parte es real y cuál controlada.**
- **Controlado:** lo que llega a Central. El observador altera, retiene, duplica o reenvía el envío del teléfono, o agota el límite.
- **Real:** la decisión de Central y la reacción del teléfono.
- **Inyectado:** sólo C28 y el 503 de C29. Esas respuestas no salen de Central.
- **Otra instalación:** en C12, C13 y C33 la otra rama la produce `tool/oe3/central_push.cjs`, una instalación scriptada del mismo Member con un registro propio y contra la API real.

Antes del teléfono, `tool/oe3/harness_selftest.cjs` comprobó cada modo contra la API real (`oe3_harness_selftest_2026-11-03.txt`).

| Fila | Montaje | Central (real) | Teléfono | Resultado |
|---|---|---|---|---|
| C07 | `drop-push-response`, y el reintento con `mutate reorder` | ALREADY_APPLIED/OK | ACKED, con la hora de aceptación original | **PASS** |
| C08 | `drop-push-response`, y el reintento con `mutate quantity-plus-one` | REJECTED/IDEMPOTENCY_MISMATCH; el original queda ACTIVE con 12 000 | REJECTED terminal (MOVE_TO_TERMINAL_FAILURE). Pantalla: «… este envío no se aplicó» | **PASS** según el contrato. Observación 1 |
| C09 | `concurrent 3` | APPLIED, ALREADY_APPLIED y ALREADY_APPLIED; 1 journal | ACKED | **PASS**. El primer intento dio CONFLICT por la observación 1 |
| C21 | `mutate quantity-overflow` | REJECTED/QUANTITY_INVALID | REJECTED terminal | **PASS**. Observación 2. El máximo exacto no se midió en DEVICE |
| C25 | `mutate version-2` | 422 CONTRACT_VERSION_MISMATCH | VERSION_MISMATCH: pausa los envíos y lo dice en pantalla. Los cambios siguientes quedan PENDING. «Reintentar con esta versión» reenvía el mismo envelope | **PASS** (`C25_*.png`). Observación 3 |
| C26 | `mutate extra-payload` | 400 FIELD_NOT_ALLOWED | FAILED terminal | **PASS** |
| C27 | `mutate unknown-predecessor` | REJECTED/INVALID_PREDECESSOR | REJECTED terminal | **PASS** |
| C37 | `mutate quantity-text:01`, aplicado al envelope reanudado de C25 | 400 INVALID_REQUEST | FAILED terminal | **PASS** |
| C28 | `inject-ack RETRYABLE DEPENDENCY_PENDING KEEP_FOR_RETRY` (**inyectada**) | — | PENDING, conservada. No se reenvió sola en 40 s; con «Sincronizar ahora», el mismo id dio APPLIED (2 intentos) | **PASS** con la respuesta inyectada. Observación 4 |
| C29, 429 | `burst 25` | 429 RATE_LIMITED **real**, `Retry-After` 60 | `next_attempt_at` +60 s. «Sincronizar ahora» a los 33 s: 0 envíos; tras el plazo, APPLIED | **PASS** |
| C29, 503 | `inject-status 503 TEMPORARILY_UNAVAILABLE` (**inyectada**) | — | PENDING; reintento automático a los 30 s y APPLIED | **PASS** con la respuesta inyectada |
| C32 | `get-unknown` al pulsar «Resolver conflicto…» | 404 OPERATION_NOT_FOUND real | La intención sigue en CONFLICT y no se reenvía nada. **Defecto:** el aviso muestra `SyncQueryException(404, OPERATION_NOT_FOUND)` (`C32_aviso_recorte.png`) | Tratamiento **PASS**; mensaje corregido en el PR #186 |
| C12 | Ver C12 y C13 | ALREADY_APPLIED; contribución CANCELLED, sin cantidad | ACKED | **PASS** |
| C13 | Ver C12 y C13 | CONFLICT/CANCELLED_PREDECESSOR; el tombstone se mantiene | CONFLICT, para que la persona decida | **PASS** (`C12_C13_resultado.png`) |
| C33 | Ver C33 | REJECTED/CAUSAL_FENCED; la resolución sigue ACTIVE (34 000) | REJECTED terminal | **PASS** (`C33_cercada.png`) |
| C17 | Resolución con la respuesta retenida; el Administrador cierra la campaña antes del reintento | ALREADY_APPLIED/OK | ACKED, con la hora original | **PASS** |
| C39 | — | — | — | **No medido en DEVICE.** Central no reabre una campaña cerrada (`POST …/open` da 400), y la app nunca reenvía una intención REJECTED, que es terminal: no hay respuesta que el cliente reciba. Queda acreditada en Central (columna A) |

**C12 y C13, paso a paso.**
1. Respuesta de X retenida, y modo avión: X queda OUTCOME_UNKNOWN, aunque Central lo aplicó.
2. Sin red, Z, con X como antecesor.
3. Exportación del respaldo sin red.
4. Borrado de los datos internos y nueva activación.
5. La otra instalación envía un CANCEL sobre X: APPLIED.
6. Restauración, y «Liberar».

**C33, paso a paso.**
1. W, con base en la cabeza `ee0e3f9b`, se retiene sin reenviar y con modo avión. Central no lo recibe (0 en el journal).
2. La otra instalación aplica `b8c01fda`, sucesor de `ee0e3f9b`.
3. La otra instalación envía otro sucesor de `ee0e3f9b`: CONFLICT/CAUSAL_FORK.
4. La otra instalación resuelve con SUPERSEDE y la referencia: APPLIED, cercado hasta la secuencia 13.
5. El teléfono envía W.

**C33, medición previa.** La resolución que el teléfono hizo antes ya había cercado la rama anterior. Un sucesor tardío de `42abf1a2` enviado por la otra instalación recibió REJECTED/CAUSAL_FENCED.

**Comportamiento visto.** Con un conflicto sin resolver, «Cambiar cantidad…» no crea un sucesor. La contribución queda detenida (`sync_outbox_store.dart`), así que el teléfono sólo puede enviar un sucesor tardío si ese sucesor ya había salido antes de que se cercara la rama.

### Observaciones (no son defectos confirmados)

1. **C08: divergencia local.** Con el contenido alterado en tránsito, el teléfono marca la intención como «no se aplicó», aunque Central conserve aplicado su contenido original. El cambio local siguiente se apoya en la última intención aceptada que el teléfono conoce, y por eso se bifurca (CONFLICT). La app nunca cambia el contenido de una intención enviada, así que esto sólo pasa si el cuerpo se altera en tránsito.
2. **C21: texto engañoso.** QUANTITY_INVALID está en la familia «referencias», y la pantalla dice «El sindicato no reconoce el producto o la campaña…». Sólo se alcanza alterando el envío.
3. **C25: botón tapado.** El botón flotante «Nuevo» tapa «Reintentar con esta versión» en la posición inicial, y hay que desplazar la pantalla. Es el mismo solapamiento ya registrado para el HONOR.
4. **C28: sin reintento automático.** Tras RETRYABLE/DEPENDENCY_PENDING no hubo reintento automático en 40 s, mientras que tras el 503 sí lo hubo a los 30 s. El contrato pide conservar la intención y no fija el ritmo.

## 6. No ejecutado y por qué

| Pendiente | Motivo |
|---|---|
| HONOR: #129 y la restauración entre modelos (#151 punto 7) | No estaba conectado (`adb devices`). No se sustituyó por el POCO |
| Restauración entre modelos con B2 | No hay credenciales. El punto 7 de #151 exige B2. **Para la prueba entre modelos no hacen falta credenciales nuevas**: ver «Vías para sacar el respaldo del POCO» |
| C21 máximo exacto; C19 «inexistente» y «de otro sindicato» | No se montaron en esta tanda |
| C39 en DEVICE | Ver §5 |
| Auto Backup, D2D, energía y reloj | No autorizados |

### Vías para sacar el respaldo del POCO

**Flujo de exportación existente.**
- **Código:** «Cuentas › Copias de seguridad › Exportar respaldo» llama a `BackupService.export()`, y `_publish` escribe en `getDownloadsDirectory()`.
- **Destino en Android:** la carpeta externa **propia de la app**: `/storage/emulated/0/Android/data/com.comunidad.agro.agroquimicos.oe3/files/Download/agroquimicos_backup_<fecha>.agrobackup`.
- **Permisos:** modo `-rw-------`, con propietario el uid de la app (`u0_a385` o `u0_a386`) y grupo `ext_data_rw`.

**Errores exactos de la primera sesión,** sin saltarse ningún permiso:
- `adb pull`: `remote open failed: Permission denied`.
- `adb shell run-as <paquete> cat /sdcard/Android/data/...`: `Permission denied`.
- `adb shell sha256sum …`: `Permission denied`.

Listar con `ls` sí funciona.

**Vías autorizadas de la propia app.** La app no tiene «Compartir» ni el selector de documentos del sistema para el respaldo: no usa `share_plus`, `file_picker` ni SAF. Las dos salidas son:
1. **La carpeta propia** de antes. Desde fuera de la app sólo se alcanza por MTP («Transferencia de archivos» en el aviso USB del teléfono), que es un paso humano y no se probó.
2. **«Respaldo en la nube»**: un contenedor cifrado con la clave de recuperación y subido a Central. En el Central desechable el proveedor sería `BACKUP_STORAGE_PROVIDER=disk`, una carpeta del propio Central, y **no es B2**. Esta sesión lo arrancó con `BACKUP_PRODUCTION_ADMISSION=disabled` y sin `BACKUP_STORAGE_DIR`, así que esta vía no se probó.

**Preparado para el HONOR.** La prueba entre modelos puede hacerse por la vía 2 sin credenciales nuevas, rotulada como «almacenamiento en disco del Central desechable, no B2»:
1. Central desechable con `BACKUP_STORAGE_PROVIDER=disk` y una carpeta temporal.
2. Subida desde el POCO.
3. Restauración en el HONOR con la clave de recuperación, tecleada en un solo proceso y sin mostrarla.
4. SHA-256 del contenedor cifrado en el disco del Central frente al que descarga el HONOR.

También puede hacerse por la vía 1, si el autor copia el archivo por MTP. En ninguno de los dos casos se acredita el punto de #151 que exige B2: **sólo B2 necesita credenciales.**

## 7. Cierre

- **Logcat** del uid de `.oe3`: 292 líneas, con 0 JWT, 0 valores opacos, 0 campos sensibles y 0 correos.
- **Teléfono:** `.oe3` desinstalado; quedan los otros 20 paquetes. Modo avión apagado, `font_scale` en 1,0 y `stay_on` en 3, como estaba.
- **Entorno:** túnel y observador cerrados, supervisor detenido y contenedor `--rm` eliminado. La API se detuvo **por PID y puerto, sin leer su línea de comandos**. Puertos 3320, 3321 y 55495 libres.

**Incidente anterior, verificado.** Los tres secretos que aparecieron en la salida de la sesión anterior los generaba `openssl rand` en el supervisor, sólo en memoria. Se compararon sin imprimirlos:
- con 75 661 archivos del clon Backend, el clon Mobile, `_wt/` y la carpeta del entorno;
- con las variables de entorno.

El resultado fue **0 coincidencias**. El segundo valor de `JWT_REFRESH_SECRET` que aparece en el registro de la sesión es un marcador de prueba, no un secreto. Eran exclusivos del entorno destruido, así que **no hay ninguna contención pendiente**.
