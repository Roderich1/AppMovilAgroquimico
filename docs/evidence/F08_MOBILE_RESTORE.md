# F08 — Respaldo local corregido, respaldo en la nube y restauración (MOB #35, #36)

**Origen:** Live. **Verificado:** 2026-10-16 (America/La_Paz). **Gate relacionado:** Roderich1/Agro_Sindicato_Backend-Web#41 (GATE-F08), **Pending**.

**Trazabilidad:** RF-26, RF-27, RNF-10, CU-14 y CU-15. También cierra la parte crítica pendiente de #55: el SHA-256 de la base.

## Commits

| Commit | Contenido |
|---|---|
| `6c6a1a2` | Corrección del respaldo local: SHA-256 de la base, validación y restauración sobre la misma copia, sólo fotos verificadas, exportación atómica y pausa dentro del tramo con rollback. |
| `e89d8b3` | Cliente remoto, servicio, pantalla «Respaldo en la nube» y liberación de lo restaurado sólo con verificación del titular. |
| `639e43e` | Merge de `main` `74d5539` (#88, #89). |
| `ac6da48`, `e7a0432` | Arnés del E2E en instalación limpia (`tool/f08_bkp/`). |
| `3668ad2` | Primera versión de esta evidencia. |
| `1663e92` | Correcciones de la revisión de A (M1–M5 y menores), descritas en §2b. |
| `f0f5227`, `2b3a0ce` | La comprobación previa verifica también la producción cerrada y el 415 sin eco en la API compilada. |
| `7021177` | Evidencia de la primera revisión. **Su CI falló en `dart format`**: dos líneas en blanco en `test/backup_export_atomic_test.dart`, así que no llegaron a correr el análisis ni los tests en ese HEAD. |
| `e5a1364` | Segunda revisión de A, descrita en §2c. |

Base: BASE_MOBILE_VALIDADA `caf158e0a0c8012082add22761ca9c6d56e6eb8f`, publicada por A tras resolver #86. La rama se creó desde ella.

## 1. Defectos locales corregidos primero

| Defecto | Corrección | Regresión |
|---|---|---|
| El manifiesto guardaba `database.sha256` pero la validación no lo contrastaba | Se comprueban tamaño y SHA-256 de `database.db` antes de abrirla. Un manifiesto sin esa descripción se rechaza. Se conservan las comprobaciones de fotos y ahora el SHA-256 de cada foto es obligatorio. | `test/backup_restore_sha256_test.dart` |
| `validate(path)` y `_extract(path)` eran dos lecturas distintas | Se valida y se restaura la **misma** extracción, o la misma copia privada en el formato `.db` histórico. | Ídem |
| La restauración copiaba cualquier archivo de `invoices/` del paquete | Sólo se copian las fotos descritas **y verificadas** en el manifiesto. Un nombre con ruta se rechaza. | Ídem |
| La exportación copiaba directamente al nombre definitivo | El paquete validado se copia a `.part` **en la carpeta de destino**. Se cotejan sus bytes, se fuerza a disco y se renombra; renombrar en el mismo directorio es atómico. Un fallo borra el parcial, y los parciales abandonados se descartan y nunca se listan. | Ídem |
| `pauseAfterRestore` se ejecutaba después del tramo con rollback | Pasa a `prepareRestored`, dentro del tramo que se deshace si falla. | `remote_backup_client_test.dart`: la cola ya está pausada dentro de la sustitución |

**Rojo antes de la corrección (reproducible, revisión M5).** La primera ejecución en rojo se hizo durante el desarrollo, sobre un estado sin commit, así que no se usa como evidencia. Se repitió de forma reproducible:

```text
git worktree add --detach <tmp> caf158e0a0c8012082add22761ca9c6d56e6eb8f
git show 1663e92:test/backup_restore_sha256_test.dart > <tmp>/test/backup_restore_sha256_test.dart
git show 1663e92:test/backup_container_support.dart   > <tmp>/test/backup_container_support.dart
cd <tmp> && flutter pub get && flutter test test/backup_restore_sha256_test.dart
-> exit 1; 6 fallos, 2 pasan:
  [E] una base alterada con SQL válido se rechaza al validar
  [E] restaurar una base alterada no toca la base ni las fotos actuales   (la base alterada se restauraba)
  [E] un manifiesto sin SHA-256 de la base se rechaza
  [E] un manifiesto sin descripción de la base se rechaza
  [E] un tamaño declarado distinto del real se rechaza
  [E] una fotografía no descrita en el manifiesto no se restaura          (se restauraban 2 en vez de 1)
```

Para que la prueba compile sobre la base, la exportación atómica, que necesita la API nueva, se separó en `test/backup_export_atomic_test.dart`.

**Después de la corrección**, sobre `1663e920f30b0504f0efceeb35f56da1c9c6f228`:

```text
flutter test test/backup_restore_sha256_test.dart test/backup_export_atomic_test.dart test/backup_container_test.dart test/backup_service_test.dart test/backup_android_semantics_test.dart test/f04_restore_authorization_test.dart test/f04_restore_ownership_rules_test.dart test/f04_admin_owner_restore_ui_test.dart test/remote_backup_client_test.dart
-> 00:16 +107: All tests passed!
```

Las manipulaciones son reales: se abre la base dentro del contenedor, se ejecuta un `UPDATE` con SQL, se comprueba `integrity_check = ok` y se vuelve a empaquetar.

Se ajustó una prueba existente, «esquema futuro», que reescribía la base sin actualizar el manifiesto. Ahora actualiza también el manifiesto, porque así es un respaldo coherente de una app más nueva. Así sigue probando el esquema y no el SHA-256.

## 2. Respaldo en la nube (#35) y restauración (#36)

- `RemoteBackupApi` sobre `/api/v1/me/backups`:
  - Subida y descarga en streaming.
  - La subida sólo cuenta si el servidor confirma el mismo SHA-256 y tamaño.
  - La descarga escribe en `.part`, coteja la cabecera, el tamaño y el SHA-256 con los metadatos y luego renombra. Si se corta o algo no coincide, no queda archivo.
  - Errores tipados sin cuerpos ni identificadores.
  - Rutas añadidas a la lista cerrada de `ApiEndpointConfig`, sólo con UUID v4.
- `RemoteBackupService`:
  - Subir: sólo si la cuenta en sesión es la del titular de la instalación.
  - Eliminar: sólo la copia remota.
  - Preparar: descarga a una carpeta **privada** de la app, verifica el **hash exterior**, aplica la **validación interna** del contenedor y lee el titular de la copia, sin modificar nada.
  - Restaurar: vuelve a comprobar el hash exterior y llama a `GuardedRestore`, que aplica la exclusión de escrituras, el titular, RESTORE_PAUSED y el recálculo de la autorización. La copia descargada se borra siempre.
- Pantalla «Respaldo en la nube», en Liquidación › Copias de seguridad: cada acción es explícita y pide confirmación. Nada se publica al sindicato.
- `releaseRestored` exige el **acceso verificado en línea de la cuenta del titular**. Antes liberaba también sin acceso vigente. Abrir la app no reenvía nada.

No se inventaron estados nuevos: se reutilizan `RESTORE_PAUSED`, `DatabaseReplacementGuard` y `recomputeAfterReplacement`. Las reglas de titular no cambian.

## 2b. Correcciones de la revisión de A (`1663e92`)

- **M1. Arnés.** `tool/f08_bkp/env.sh` asigna los valores sin condición. Si la shell ya tiene otro valor, por ejemplo la configuración de F03, aborta, para que `down.sh` nunca apunte a datos conservados. Se comprobó en tres casos:
  - shell limpia: se carga;
  - shell con `F03_PG_CONTAINER=agro_f03res01_pg`: aborta;
  - script hijo que vuelve a cargarlo: se carga.

  El README pide una shell nueva, cierra conservando el contenedor (decisión de A) e incluye la limpieza de imágenes e instantáneas.
- **M2.** Un 401 o 403 de la API de respaldos descarta el acceso en memoria, igual que Sync. La siguiente acción vuelve a verificarlo.
- **M3.** La pantalla en la nube muestra los avisos de la exportación (fotos que faltan) y de la restauración.
- **M4.** Cada operación tiene un plazo total de 5 min, el mismo que el `requestTimeout` del servidor. Al vencer, la petición **se aborta** (`AbortableRequest` y `AbortableStreamedRequest` de `package:http` 1.6), no sólo se deja de esperar. Si la subida termina sin una respuesta fiable, se lista el servidor y se reconoce la copia con el mismo SHA-256 antes de que el agricultor reintente, sin volver a enviarla.
- **Menores:**
  - los errores de escritura en el teléfono (`localStorage`) ya no se presentan como un fallo de SHA-256;
  - la carpeta privada se limpia antes de preparar una restauración;
  - el comentario de UIBUG-049 está al día.

## 2c. Segunda revisión de A (`e5a1364`)

- **Formato.** Corregido. Antes de publicar se ejecuta la misma comprobación que la CI: `dart format --output=none --set-exit-if-changed lib test`.
- **Plazo de la descarga.** El plazo total de 5 min de `7021177` interrumpía descargas válidas grandes en redes lentas. Ahora la descarga tiene:
  - un plazo **por inactividad** de 1 min sin recibir bytes;
  - un **tope total proporcional al tamaño declarado**: 5 min más el tamaño a 16 KiB/s, unos 128 kbit/s; con 100 MB, algo menos de dos horas.

  Ninguna espera es ilimitada y, al vencer, la petición se aborta. El aborto, el corte o la falta de respuesta se informan como **error de red**. Sólo una discrepancia real de tamaño o de SHA-256 se informa como integridad.
- **Cierre del arnés:**
  - `env.sh` valida todas las variables antes de exportar ninguna; ante un conflicto no cambia nada;
  - el nuevo `tool/f08_bkp/down.sh` carga `env.sh` y comprueba que el contenedor y el volumen son los de F08 antes de delegar;
  - el README advierte que nunca se use directamente el `down.sh` de F03.

  Comprobado: con un conflicto en una variable posterior no queda nada asignado, y con una shell de F03 el `down.sh` de F08 se niega.
- **Comprobación previa:** exige `BACKUP_STORAGE_DIR` en el modo normal.
- **Pruebas nuevas:**
  - una descarga lenta pero continua, más larga que el plazo de inactividad, termina;
  - una descarga detenida se aborta, con error de red y sin archivo;
  - una descarga que progresa pero supera el tope se aborta;
  - los avisos de la exportación llegan al resultado de la subida (M3, a nivel de servicio).
- **Sin cambiar:** la subida mantiene el plazo total de 5 min, el mismo corte que aplica el servidor (BE `F08_BACKUP.md`, limitación del plazo de subida).

## 3. Pruebas

`test/remote_backup_client_test.dart` tiene **25 casos**: los 20 iniciales y 5 de la revisión.
- Cancelación real al vencer el plazo, con un transporte que sólo termina si se aborta.
- Un 401 o 403 descarta el acceso en memoria; un 404 no.
- Respuesta de subida perdida: se lista, se reconoce el mismo SHA-256 y no hay un segundo POST.
- Sin red y sin copia en el servidor: se informa el error y no se da por subida.
- Una preparación interrumpida no deja restos en la carpeta privada. El transporte es un `MockClient` que imita el contrato BE #39. La base, el contenedor, `GuardedRestore`, el controlador de acceso y la outbox son reales.

- **Cliente:**
  - lista vacía;
  - cabeceras de subida, sin Member ni tenant;
  - subida no confirmada con otro SHA;
  - 401/403/404/409/413/422/500/503 y sin red;
  - rutas sólo con UUID v4;
  - descarga íntegra, alterada, con metadatos distintos, cortada y 404, sin que quede archivo;
  - eliminar no toca los respaldos locales.
- **Teléfono nuevo del mismo Member:** se compara **cada tabla** antes y después. Son iguales salvo:
  - `app_settings.activated_installation_ref`, que pasa a la instalación nueva;
  - `sync_outbox`: ACKED intacta y la intención enviada sin respuesta pasa a RESTORE_PAUSED, con el mismo `operation_id`, cantidad y causalidad;
  - `purchases.invoice_image_path`, reconstruida a la carpeta del teléfono.

  Las fotos son iguales en nombre y SHA-256. El acceso queda `activated` y se puede operar. La copia descargada se borra.
- **Copia de otro Member** (un servidor que la entregara por error): se rechaza al prepararla. La base queda igual y el acceso, `activated`.
- **Otro Member intenta subir los datos de este titular:** se rechaza sin ninguna petición.
- **Bytes alterados, corte o SHA de metadatos distinto:** no se restaura; la base, las fotos y el acceso quedan iguales; no quedan archivos.
- **Contenedor alterado por dentro** con hash exterior coherente: lo rechaza la validación interna («no coincide»).
- **Pausa antes de que nadie vea la base:** dentro de la sustitución ya hay `ACKED` + `RESTORE_PAUSED`.
  - Con acceso verificado, el worker (el ciclo que corre al abrir la app) envía **0** y hay **0 peticiones Sync**.
  - Sólo tras la liberación se reenvía **una vez** la misma intención (mismo `operationId`).
- **Liberar:** sin verificación en línea, libera 0; si la verificación es de otra cuenta, 0; con la cuenta del titular, 1.

El caso «otro Member» y el de «instalación nueva» reutilizan además las regresiones existentes de `f04_restore_authorization_test.dart`, todas en verde.

| Comando, sobre `e5a13649569aea579463c7bf151f8eb7cae7b9d0` (con `main` `74d5539` integrado) | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test` | **1030 pasan, 2 omitidas, 0 fallos** |
| Suites de respaldo y restauración (comando de §1) | **111/111** |

**Ejecución anterior con fallos.** Una ejecución de `flutter test` sobre el mismo HEAD, a la vez que las suites del Backend, dio **2 fallos** en `f04_activation_app_policy_test.dart` y `f04_admin_owner_restore_ui_test.dart`. En ambos casos fue `PathAccessException` al borrar un directorio temporal, porque otro proceso retenía un archivo (Windows). Repetidas solas pasaron (21/21), y la suite completa en solitario dio el resultado de la tabla. Se registra como fallo de entorno, no de código.

Sobre `1663e92`, primera revisión: `flutter test` 1026/2 y suites de respaldo 107/107.

## 4. Comprobaciones fuera del teléfono

- **API compilada.** `tool/f08_bkp/api_preflight.cjs` se ejecutó contra BE `15c8cf4`, con `node dist/main.js`, `NODE_ENV=production` y entorno efímero propio. Versión del script: MOB `2b3a0ce`, SHA-256 `3670d68cc05d69afb714936d2a4b5b4d3b4f9143b0702e4c2327f15f902ef7b6`.
  - Resultado: **todo PASS**, incluidos el 415 sin eco y la producción cerrada sin admisión (503).
  - El comando y la salida completos están en BE `docs/evidence/F08_BACKUP.md`.
- **Herramienta de comparación.** `tool/f08_bkp/snapshot.py` se probó con las bases reales que produce el caso «teléfono nuevo»:
  - salida PASS, con las tres transformaciones esperadas;
  - con una persona alterada a mano como control negativo, salida FAIL.

## 5. Dispositivo: NOT_MEASURED

El E2E en una instalación limpia del POCO **no se ejecutó en esta sesión**. Sólo A usa adb. El procedimiento está en `tool/f08_bkp/README.md`:
- paquete aislado nuevo `com.comunidad.agro.agroquimicos.f08bkp`;
- contenedor y puertos propios;
- 3 fotos de factura;
- una intención ACKED y otra PENDING;
- desinstalación y reinstalación **sólo** del paquete aislado;
- restauración, comparación de todas las tablas y fotos, ninguna petición Sync al restaurar ni al reabrir, y liberación con verificación.

La APK se compila al empezar el turno, porque lleva el origen HTTPS temporal. Su SHA-256 se registrará entonces.

**Alcance:** reinstalar en el mismo POCO prueba la recuperación en una instalación limpia. **No** demuestra un segundo modelo de teléfono.

Por eso #36 queda **abierta** (`Refs`, no `Closes`): su criterio exige evidencia DEVICE.

## 6. Limitaciones

- El SHA-256 del manifiesto detecta daño y alteración, pero no es una firma. Contra la sustitución de la copia remota protege el hash registrado por el servidor, que se coteja antes de restaurar.
- La copia remota no se cifra en el cliente, y el servidor no la cifra en reposo.
- No hay respaldo automático ni programado: cada acción es explícita.
- Si tras una subida incierta tampoco se puede listar (sin red), no se puede saber si la copia llegó. Un reintento del agricultor genera otro respaldo con otro SHA-256: puede quedar una copia más en el servidor, que ocupa cupo pero no sustituye ninguna.
- Cada subida a la nube exporta además un respaldo local en Descargas, y no se borra. Se acumulan como cualquier respaldo local; su limpieza queda para F10.
- Preexistentes, para F10:
  - la copia de seguridad previa se toma antes de `close()` con la base en WAL;
  - el ZIP se descomprime sin límite de tamaño.
- Retención y reconciliación (BKP-06, BE #40) quedan diferidas a F10.
