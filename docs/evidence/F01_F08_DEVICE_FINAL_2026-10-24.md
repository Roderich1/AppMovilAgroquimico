# Sesión DEVICE final F01–F08 sobre el código integrado (2026-10-24)

Ensayo físico **sintético** en un entorno desechable, autorizado por Roderich el 2026-10-24 como «única sesión final en el teléfono». Lo operó la sesión A, la única que tocó el teléfono. No hay datos reales, no se contactó a nadie, no se aprueba ningún gate y el ensayo no es de Roderich ni del tutor.

Casos pedidos:
- **A.** Reversión sin red.
- **B.** Operación tardía sin red.
- **C.** `CAMPAIGN_SEALED`.
- **D.** Respaldo cifrado por el teléfono → B2 real → instalación nueva con la clave conservada fuera de ella.

No se repiten los casos ya cubiertos por `F01_F08_DEVICE_COMPOSICION_2026-10-24.md` (rondas 1–3), ni las pruebas ro/nodel ni los ensayos del adaptador B2.

## Identidad

| Pieza | Valor |
|---|---|
| Fecha real | El 2026-10-24 de 20:35 a 21:46 en America/La_Paz (−04:00), que son las 00:35Z–01:46Z del **2026-10-25 UTC**. Las horas con `Z` de esta evidencia son de ese día UTC; las horas sin `Z`, del 24/10 local |
| Teléfono | POCO X5 Pro 5G, modelo `22101320G`, serial `cc14247a`, Android 12, zona `America/La_Paz` (`adb devices -l`, `getprop`) |
| Mobile | `main` `1d77c140d347210bf4f924b05f5f59f31e284738` (merge de #144), en un worktree desacoplado y limpio |
| APK | `tool/f03_res_01/build_isolated_apk.sh`, debug, con el origen del túnel del día |
| | Paquete nuevo `com.comunidad.agro.agroquimicos.f01f08fin`, etiqueta «Agrocuentas F01-F08 final» (`aapt2 dump badging`, build-tools 37.0.0); targetSdk 36 |
| | SHA-256 `eb3ca4ac0eca162a5f84a0d328bf3ec7cd61616b0de51528251916f2ec9a9d96`, igual al `base.apk` instalado (`sha256sum` en el teléfono) |
| | Instalado el 2026-10-24 a las 20:40 (−04:00). Antes no existía. Se pasó de 26 a 27 paquetes `com.comunidad.agro*`; los demás no se tocaron |
| Backend | `main` `4bcb1ea555ff86b3f784b28e25459e0d5ec80cce` (merge de #160), en un worktree desacoplado: `npm ci`, `prisma generate`, `build` y `build:seed`, sin `tsbuildinfo` previo |
| Entorno | PostgreSQL `agro_a_fin_pg` (127.0.0.1:55473), 13 migraciones aplicadas y seed sintético con contraseñas rotadas |
| | API en el 3150, con `NODE_ENV=development`, `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic`, `COLLECTIVE_SEALING=enabled`, `BACKUP_REQUIRE_CLIENT_ENCRYPTION=true` y `SYNC_V1_PRODUCTION_ADMISSION=enabled`, sólo en este entorno |
| | `development` porque en `production` el modo provisional se ignora y el sellado queda en `POLICY_PENDING`. Lo registró el log de la primera arrancada del arnés, en `production`: «COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic ignored in production…». Esa API se sustituyó antes de conectar el teléfono |
| | Observador `tool/f03_res_01/observer.cjs` de `main` (SHA-256 `d66ad024…1758`) en el 3151, y quick tunnel de `cloudflared` 2026.10.0 |
| Herramientas de A | Fuera del repositorio, en el scratchpad de la sesión A. Ninguna imprime ni escribe secretos: |
| | `fin_supervisor.sh`: mantiene los secretos efímeros en la memoria de su proceso para reiniciar la API sin cambiar los JWT |
| | `pin_holder.cjs`: PIN en memoria, en 127.0.0.1:3149 |
| | `key_holder.cjs`: clave de recuperación en memoria, en 127.0.0.1:3152 |
| | `fin_key_confirm.sh`, `fin_snapshot.sh` (base y fotos, por tabla), `central_state.sh` (filas y md5 de las tablas de sellado y Sync v1), `admin_open_campaign.cjs` y `seal_campaign.cjs` (API real como Administrador sintético) |

**Ajustes del teléfono.** Antes: `stay_on_while_plugged_in=0`, animaciones 1.0, sin modo avión, Wi‑Fi y datos activos. Durante el ensayo `stay_on` valió 3.

## Preparación (datos sintéticos)

- **Activación** con la cuenta D (`login` 200, `clients` 201, `session/client` 201, `me` 200), titular «Juan Perez» y modalidad propia.
- **PIN del titular:** «Confirmar en línea» con `login` 200 y `logout` 204, y después «PIN del titular configurado. Funciona sin conexión».
- **Central:** el Administrador sintético cerró «Campana Verano 2026» y abrió «Campana Invierno 2026» por la API real (200 y 200).
- **Campañas locales:**
  - «Pasada ensayo», del 01/09/2026 al 30/09/2026, **cerrada** desde el catálogo;
  - «Ensayo sync», desde el 01/10/2026 y con fin previsto el 30/11/2026, vinculada a «Campana Invierno 2026».
- **Producto** «Herbicida sync» (L), vinculado a «Glifosato 48 SL».
- **Proveedor** «Proveedor sintetico».
- **Dos facturas sintéticas** generadas en el PC:
  - `factura_sintetica_fin_1.jpg`, `9a8c82a7…2a78`;
  - `factura_sintetica_fin_2.jpg`, `57a647c8…207b`.

  Se copiaron a `/sdcard/Pictures/AgroEnsayoFin/` y se eligieron en el selector de fotos del sistema por su hora (20:38:25). El selector muestra también las fotos personales del teléfono: no se abrió ni se capturó ninguna.
- **Compras:**
  - compra 1, `FIN-001`: 20 L a 75 Bs/L, con la foto 1;
  - compra 2, `FIN-002`: 10 L a 80 Bs/L, con la foto 2.

  La app guardó las dos fotos en `app_flutter/invoices/`, recomprimidas por el selector (29 521 y 29 615 bytes).

## Resultados

### A. Reversión sin red

Modo avión (`airplane_mode_on=1`, «Active default network: none») desde las 01:01:43Z.

| # | Paso | Resultado | Lo observado |
|---|---|---|---|
| A1 | Revertir `FIN-002` con motivo y PIN, sin red | **PASS** | «¿Revertir esta compra?», motivo «Factura duplicada ensayo sin red» y después «Confirme con el PIN del titular». El PIN lo teclea `pin_holder` y «Autorizar» cierra el diálogo. La lista muestra «Revertida · Autorizada por el titular con el PIN de este teléfono · Factura duplicada ensayo sin red» |
| A2 | Actor y efectos en la base | **PASS** | Comparación por tablas antes y después (`fin_snapshot.sh`): sólo cambian `purchases` (la 2 pasa a `REVERSED`), `inventory_lots`, `inventory_movements` (+1), `reversal_audit` (+1) y `reversal_audit_effects` (+2) |
| | | | `reversal_audit`: `PURCHASE`, operación 2, el motivo, `actor_person_id=1`, `actor_binding_id=1`, Member y tenant de la cuenta D, `actor_method=LOCAL_PIN`, la referencia de enrolamiento y `recorded_at` 01:02:51Z |
| | | | Las fotos no cambian. Las tablas `sync_*` y la cola tampoco |
| A3 | Sin publicación privada a Central | **PASS** | Sin red, el observador no registró ninguna petición. Al volver la red (01:05:59Z) y pulsar «Sincronizar ahora»: sólo `POST /auth/v2/refresh` 200, la renovación de la sesión. Ningún `push`, «Todavía no hay nada que enviar al sindicato» y `outbox: sin filas` |

### B. Operación tardía sin red

Sin red durante B1–B3.

| # | Paso | Resultado | Lo observado |
|---|---|---|---|
| B1 | Compra `FIN-003` con fecha 15/09/2026 (campaña cerrada) | **PASS** | Diálogo «Fecha de una campaña cerrada»: «La fecha 15/09/2026 corresponde a la campaña cerrada «Pasada ensayo» (del 01/09/2026 al 30/09/2026)…». Motivo «Factura de septiembre encontrada tarde» y «Registrar para revisión» |
| B2 | **Aviso corregido** (`967006e`) | **PASS** | La lista de compras, leída 0,8 s después: «Guardada para revisión. Confírmela en «Operaciones tardías».». **No** anuncia una compra confirmada. La lista sigue con 2 compras |
| | | | En la base sólo cambia `late_operation_drafts` (0 → 1): sin compra, lote ni movimiento |
| B3 | Confirmar con el PIN, sin red, con doble toque en «Autorizar» | **PASS** | «Confirmar operación tardía» y el PIN. Después: «Confirmada en «Pasada ensayo». Es una corrección privada de una campaña cerrada: el consolidado del sindicato (sellado o no) no se actualiza con ella.» |
| | | | El borrador queda `CONFIRMED`, con `resolver_*` del titular, `resolver_method=LOCAL_PIN` y `result_operation_id=3` |
| B4 | Sin efectos duplicados | **PASS** | Exactamente +1 en `purchases` (la 3, del 15/09/2026, en «Pasada ensayo»), `purchase_items`, `purchase_allocations`, `inventory_lots` y `inventory_movements`. El doble toque no creó una segunda compra |
| B5 | Sin publicación | **PASS** | La misma comprobación de A3: sólo el `refresh` al volver la red; ningún `push` y la cola vacía |

### C. `CAMPAIGN_SEALED`

| # | Paso | Resultado | Lo observado |
|---|---|---|---|
| C1 | Declarar una necesidad en la campaña abierta | **PASS** | 30 L de «Herbicida sync» en «Ensayo sync»: `push` 200 y `ac9da368` en `ACKED` (aceptada a las 01:08:06.699Z), «Sincronizado» |
| C2 | Cerrar y sellar en Central | **PASS** | El Administrador sintético cierra «Campana Invierno 2026» (200, `CERRADA`) |
| | | | `GET …/seal`: `NOT_SEALED`, `can_seal true`, `blocked_by []`. `POST …/seal` con `review_ref` y confirmación: 200, `SEALED`, `created: true`, versión 1, `seal_ref` `f5811735-d2fc-4d56-8aeb-d9702de5d6e1`, `sealed_at` 01:08:51.123Z, rol `ADMINISTRADOR` |
| C3 | Corrección privada posterior: 45 L | **PASS** | «Sustituye el total anterior; no se suma». Un solo `push` 200 (01:09:40.970Z) |
| | | | `0cb4f25d` `SUPERSEDE`, predecesora `ac9da368`, en `REJECTED`, código `CAMPAIGN_SEALED`, **1 intento**. La necesidad queda «45 L · Rechazado (CAMPAIGN_SEALED)» |
| C4 | Reacción de Mobile y sin reintentos (ventana observada: unos 2 minutos, de 01:09:40Z a 01:11:48Z, con dos «Sincronizar ahora») | **PASS** | En Sincronización: «Sincronizado: 1 · Rechazado: 1» y «Necesidad declarada · Sustituir · 45 L Rechazado · CAMPAIGN_SEALED … Requiere intervención: Esta campaña está sellada en el sindicato: el histórico colectivo sellado no se actualiza con correcciones posteriores. Su registro privado se conserva.» |
| | | | Tras 60 s de espera y dos «Sincronizar ahora» (hasta las 01:11:48Z), el observador no registra ningún `push` más y el intento sigue en 1 |
| C5 | Histórico sellado intacto | **PASS** | `central_state.sh` al sellar y después de la corrección: `CollectiveSeal` (1 fila) y `CollectiveSealEntry` (1 fila) con el **mismo md5**; `SyncV1Contribution` igual (1 fila, el mismo md5) |
| | | | Sólo `SyncV1OperationJournal` pasa de 1 a 2: es el rechazo guardado, para que un reenvío obtenga la misma respuesta (`push-operation.use-case.ts`) |

### D. Respaldo cifrado por el teléfono → B2 real → instalación nueva

**Clave B2.** Una sola clave temporal, `agrocuentas-final-rw`, creada por Roderich en su propia ventana con `_wt/tools/secretos-b2/crear_clave_final_rw.ps1` (SHA-256 `154c5bcc…9766`, fuera del repositorio). Se guarda cifrada con DPAPI y nunca se mostró.
- `comprobar_b2.ps1` contra B2, a las 21:33 (−04:00): bucket permitido sólo `agro-backups-roderich`; capacidades `deleteFiles, listFiles, writeFiles, readFiles`; prefijo permitido `ensayo-f08-final-20261024/`; endpoint coincidente; sin avisos. Caducidad propia: 2026-10-27T01:29:58Z.
- No se usó la clave amplia de #149.
- La API se reinició a las 01:36:02Z con `BACKUP_STORAGE_PROVIDER=b2` y `BACKUP_S3_PREFIX=ensayo-f08-final-20261024/`. Las `BACKUP_S3_*` llegaron sólo al proceso de la API, con `con_b2.ps1`. Los JWT no cambiaron.
- Inventario del prefijo antes del ensayo, con `b2_final_prefix.cjs` y la misma clave: 0 versiones, 0 marcas y 0 multipartes.

| # | Paso | Resultado | Lo observado |
|---|---|---|---|
| D1 | Clave de recuperación | **PASS** | «Respaldo en la nube» › «Crear la clave». La ventana con la clave tenía `fl=… SECURE` |
| | | | `key_holder.cjs` la leyó del volcado de UI, la guardó **sólo en su memoria, fuera de la instalación**, y la tecleó en el campo de confirmación. Después aparecen «Ver la clave» y «Cambiar la clave» |
| | | | **Canal de accesibilidad.** La clave se leyó por el árbol de accesibilidad (`uiautomator`), el canal que Roderich aceptó el 2026-10-24 (F08-ADR-003 §0.3) |
| | | | El volcado se escribió en `/sdcard/a_k.xml`, se leyó por tubería (`adb exec-out cat`) dentro del proceso y se borró en el mismo comando (`finally`). No pasó por ningún archivo del PC |
| | | | Los volcados de navegación (`/sdcard/a_u.xml` y `/sdcard/f03_ui.xml`) siguieron el mismo camino, filtrados antes de mostrarse |
| D2 | Respaldo cifrado generado por el teléfono → B2 | **PASS** | Estado antes de subir guardado con `fin_snapshot.sh preD`: esquema 11, 32 tablas, 38 filas y 2 fotos. «Subir respaldo» › «Subir»: `POST /me/backups` 201 (01:36:43.993Z). La lista dice «Copia del 24/10/2026 21:36 22 KB · esquema 11 · cifrada con su clave actual» |
| | | | Backend (`BackupMetadata`): `AVAILABLE`, `formatVersion` 2, `schemaVersion` 11, 22 098 bytes, SHA-256 `6ec161c1b2a16df4080f29f88a8d5113a1219cb66a262a6a73c5711aca3342bd` |
| | | | B2: una sola versión, en `objects/f3e4c498-…`, de 22 098 bytes, con cabecera `AGROENC\0`, SSE `AES256`, sin «SQLite format» y con el **mismo SHA-256**. Ningún resto de staging ni de multiparte |
| D3 | Instalación nueva, sin la clave | **PASS** | `adb uninstall` del paquete aislado y la misma APK otra vez (SHA-256 `eb3ca4ac…`). uid nuevo (`u0_a375`; antes `u0_a264`); sólo `cache` y `code_cache`, sin `databases`, `shared_prefs` ni `app_flutter` |
| | | | Activación con la cuenta D (`login` 200, `clients` 201, `session/client` 201, `me` 200) y un titular nuevo |
| | | | La sección de respaldo dice «Antes de subir un respaldo hay que crear su clave de recuperación…»: **el llavero de la instalación nueva está vacío** y nada se recuperó de la anterior |
| D4 | Descarga y clave escrita | **PASS** | «Ver copias en el servidor»: «… cifrada; pedirá la clave de recuperación con que se subió». «Restaurar»: `GET …/content` 200 y el diálogo «Esta copia está cifrada con una clave que este teléfono no tiene. Escriba la clave de recuperación que anotó», con `SECURE` |
| | | | `key_holder` tecleó la clave conservada. «Descifrar»: «Copia del 24/10/2026 21:36 (22 KB), descifrada y verificada. Contiene la base de datos y 2 fotografía(s). La copia corresponde al titular de esta instalación. TODOS los datos actuales se reemplazarán… Los envíos al sindicato que traiga la copia quedarán pausados hasta que usted los libere en Sincronización.» |
| | | | «Restaurar» (01:41:11Z): «Copias previas a restauraciones · Del 24/10/2026 21:41 restauración terminada» |
| D5 | Datos y fotos antes y después | **PASS** | Se compararon `preD` (instalación anterior, antes de subir) y `postD` (instalación nueva, después de restaurar), fila a fila. **31 de 32 tablas idénticas.** Sólo cambia `app_settings.activated_installation_ref`: es el cambio previsto de instalación |
| | | | Las 2 fotos tienen el mismo nombre y el mismo SHA-256 (`73b6ad5c…` y `05224dac…`) |
| | | | En la app: «Campaña activa: Ensayo sync», «Compras 1.850,00 Bs» (1 500 + 350; la compra revertida no cuenta) y las tres compras con sus estados |

**Cambios previstos, separados de los datos:**
- **Instalación:** sólo `activated_installation_ref`.
- **Sesión:** es la de la activación nueva. Vive en el almacén seguro, no en SQLite, así que no entra en la comparación.
- **PIN:** no viaja en el respaldo.
  - «PIN del titular» pide de nuevo «Primero confirme la cuenta del titular en línea».
  - La reversión restaurada muestra «Autorizada por el titular con un PIN que ya no está configurado en este teléfono (anterior o de otra instalación) · Factura duplicada ensayo sin red».
- **Llavero:** después de restaurar hay una clave activa: aparecen «Ver la clave» y «Cambiar la clave». Que sea la escrita en D4 se deduce del código (`backup_keyring.dart`: sin una clave activa previa, la de la restauración pasa a activa). No se mostró, porque sin PIN no se puede.
- **Pausa de la cola:** no se produjo, porque la copia no traía envíos pendientes. Sus dos entradas ya eran terminales: `ac9da368` en `ACKED` y `0cb4f25d` en `REJECTED / CAMPAIGN_SEALED`, y siguen idénticas. La pausa y la liberación con un envío pendiente están en la ronda 3 de `F01_F08_DEVICE_COMPOSICION_2026-10-24.md` (D7e).
- **`.previo`:** una entrada `finalized` en `databases/previo/registro.json`, con `rw-------`. `files/remote_backups` queda vacío.

**Limpieza del ensayo:**
- **B2:** limpieza del prefijo con la misma clave (01:44Z). Antes: 1 versión. Después: 0 versiones, 0 marcas y 0 multipartes. No se tocó nada fuera de `ensayo-f08-final-20261024/`.
- **Revocación:** Roderich ejecutó en su propia ventana `revocar_clave_final_rw.ps1` (SHA-256 `ddacd495…5afa`), que exige la clave maestra.
  - **B2 confirmó la revocación.** La salida local que transmitió Roderich dice: «Revocada: agrocuentas-final-rw (2026-10-25T02:48:39Z)».
  - **Archivo local, comprobado aparte por A** (2026-10-25T02:53:30Z): `%LOCALAPPDATA%\Agrocuentas\secretos\final-rw.clixml` ya no existe. El script sólo lo borra si B2 confirma la revocación. La clave amplia `backblaze-b2.clixml` sigue sin tocar.
  - **No se probó ningún acceso posterior con la clave revocada.**
- **Teléfono:**
  - paquete `.f01f08fin` desinstalado; quedan 26 paquetes `com.comunidad.agro*`, como antes del ensayo;
  - las dos imágenes sintéticas, borradas (MediaStore: «No result found»);
  - ningún volcado de UI en `/sdcard`;
  - ajustes iniciales restaurados: `stay_on` 0, animaciones 1.0, sin modo avión, Wi‑Fi y datos activos.
- **Entorno:** con `down.sh` y `ctl_stop`: sin contenedor ni volumen y nada escucha en 3149–3152 ni en 55473. `key_holder` y `pin_holder` borraron de su memoria la clave y los PIN, y terminaron.
- **La clave de recuperación, los PIN y las contraseñas** no aparecen en ninguna salida, captura, log ni archivo. Las contraseñas fueron de un solo uso (`credential.sh`).

**Incidencia del operador.** Dos veces se abrió en el teléfono la app de Cámara del sistema:
- tras la reinstalación;
- después, por un toque sobre el dock del launcher cuando la app ya se había cerrado.

En las dos se salió con HOME, sin pulsar el obturador y sin capturas. `/sdcard/DCIM/Camera` no tiene ningún archivo posterior al 2026-10-21, comprobado sólo por la fecha. Desde entonces, antes de cada toque se comprueba que el foco es de la app.

**Registro del observador** (método, ruta y estado; sin cuerpos), de 00:37Z a 01:40Z: activación, `login`/`logout` del PIN, dos `refresh`, `references`, los dos `push` del caso C, `POST /me/backups` 201, `GET /me/backups` y `GET …/content` 200, y la activación de la instalación nueva. Ninguna otra petición.

## Límites

- Un único dispositivo, una única sesión y un solo operador, con datos sintéticos.
- La API corrió con `NODE_ENV=development` (véase «Identidad»).
- Sin red quiere decir modo avión: no se probaron una red degradada ni un corte a mitad de una petición.
- B3 probó un doble toque en «Autorizar». No es una prueba de concurrencia.
- **D se hizo en el mismo modelo de teléfono.** Una instalación nueva no es un teléfono de otro modelo: #151 ítem 7 y MOB #36 siguen pendientes.
- **La clave se conservó fuera de la instalación en la memoria de un proceso del PC, no en papel.** Comprobar con personas cómo anotan y guardan la clave sigue pendiente (F08-ADR-003 §0.4).
- **La pausa de la cola no se volvió a ejercitar en D** (véase D5).
- **D3 no ejecuta un Auto Backup ni un D2D.** `adb install` no restaura nada desde un transporte de Android, así que «nada se recuperó de la anterior» no prueba las reglas de respaldo de Android. Siguen sin ensayar (F08-ADR-003 §0.4).
- **Siguen abiertos del ADR §0.4**, porque D no los cubre: la rotación completada en DEVICE y el archivo alterado o truncado en DEVICE.
- La copia tenía 22 KB: no se midió el rendimiento del cifrado en el dispositivo, que sigue en NOT_MEASURED.
- Ningún caso declara cumplidos RF-03, RF-13, F07 ni F08 por sí solo: cada uno es un hueco de evidencia que se cubre.
