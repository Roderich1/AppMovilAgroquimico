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

Base: BASE_MOBILE_VALIDADA `caf158e0a0c8012082add22761ca9c6d56e6eb8f`, publicada por A tras resolver #86. La rama se creó desde ella.

## 1. Defectos locales corregidos primero

| Defecto | Corrección | Regresión |
|---|---|---|
| El manifiesto guardaba `database.sha256` pero la validación no lo contrastaba | Se comprueban tamaño y SHA-256 de `database.db` antes de abrirla. Un manifiesto sin esa descripción se rechaza. Se conservan las comprobaciones de fotos y ahora el SHA-256 de cada foto es obligatorio. | `test/backup_restore_sha256_test.dart` |
| `validate(path)` y `_extract(path)` eran dos lecturas distintas | Se valida y se restaura la **misma** extracción, o la misma copia privada en el formato `.db` histórico. | Ídem |
| La restauración copiaba cualquier archivo de `invoices/` del paquete | Sólo se copian las fotos descritas **y verificadas** en el manifiesto. Un nombre con ruta se rechaza. | Ídem |
| La exportación copiaba directamente al nombre definitivo | El paquete validado se copia a `.part` **en la carpeta de destino**. Se cotejan sus bytes, se fuerza a disco y se renombra; renombrar en el mismo directorio es atómico. Un fallo borra el parcial, y los parciales abandonados se descartan y nunca se listan. | Ídem |
| `pauseAfterRestore` se ejecutaba después del tramo con rollback | Pasa a `prepareRestored`, dentro del tramo que se deshace si falla. | `remote_backup_client_test.dart`: la cola ya está pausada dentro de la sustitución |

**Rojo antes de la corrección.** Se ejecutó sobre `caf158e` con sólo la exportación cambiada; la validación todavía era la original:
- `flutter test test/backup_restore_sha256_test.dart --name 'SHA-256 de la base'`: **5 fallos**. Entre ellos, `restaurar una base alterada…` terminó con la base alterada **restaurada**.
- La prueba de la foto intrusa también falló: se restauraban 2 fotos en vez de 1.

**Después de la corrección.** Las 82 pruebas de respaldo y restauración pasan. Las manipulaciones son reales: se abre la base dentro del contenedor, se ejecuta un `UPDATE` con SQL, se comprueba `integrity_check = ok` y se vuelve a empaquetar.

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

## 3. Pruebas

`test/remote_backup_client_test.dart` tiene **20 casos**. El transporte es un `MockClient` que imita el contrato BE #39. La base, el contenedor, `GuardedRestore`, el controlador de acceso y la outbox son reales.

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

| Comando, sobre el estado integrado (`e7a0432`, código igual al de `639e43e`) | Resultado |
|---|---|
| `flutter analyze` | Sin problemas |
| `flutter test` | **1021 pasan, 2 omitidas, 0 fallos** |
| `flutter test test/remote_backup_client_test.dart` | 20/20 |
| `flutter test test/backup_restore_sha256_test.dart test/backup_container_test.dart test/backup_service_test.dart test/backup_android_semantics_test.dart test/f04_restore_*` | 82/82 (antes del merge con `main`) |

## 4. Comprobaciones fuera del teléfono

- **API compilada.** `tool/f08_bkp/api_preflight.cjs` se ejecutó contra BE `feat/f08-backups` `9b0a2ba`, con `node dist/main.js`, `NODE_ENV=production` y entorno efímero propio. Resultado: **todo PASS**. Detalle en BE `docs/evidence/F08_BACKUP.md`.
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
- Retención y reconciliación (BKP-06, BE #40) quedan diferidas a F10.
