# F10 — Copia previa a restaurar con la base en WAL (MOB #36)

**Origen:** Live. **Fecha real:** 2026-10-16 (America/La_Paz). **Gate relacionado:** Roderich1/Agro_Sindicato_Backend-Web#41 (GATE-F08), **Pending**. #36 sigue abierta: su cierre lo registra A tras la comprobación en el teléfono.

**Trazabilidad:** RF-27, RNF-10 y CU-15.

**Alcance:** pruebas de host (Windows 11, Flutter 3.47.2, `sqflite_common_ffi`). **No es una prueba DEVICE.** La comprobación focalizada en el POCO se pide a A en `ESTADO_C_BACKUP.md` (TURNO_POCO_SOLICITADO).

## Commits

| Commit | Contenido |
|---|---|
| `4f203c7` | Base: `main` Mobile tras el merge de #90 |
| `50d7dd7` | Regresión `test/f10_restore_wal_rollback_test.dart`: 4 pruebas, **en rojo sobre el código de `4f203c7`** |
| `b4017a1` | Corrección en `lib/data/backup_service.dart` y una quinta prueba, que usa el hook nuevo `afterSafetyCopy` |
| `ca74514` | Esta evidencia |
| `5a73bea` | Sexta prueba: la técnica para provocar en el teléfono un fallo después de sustituir. Generador `tool/f08_bkp/craft_negative.py` para el turno del POCO |
| `d1a6b34` | Evidencia de `5a73bea` |
| `3552397` | Revisión de A: séptima prueba, que cubre el `-wal` no vacío tras cerrar con un hook de pruebas `afterCheckpoint`; `busy` se lee por nombre; se retira un `expect` que no podía fallar |

## 1. Defecto

En `_restoreExclusively` (`backup_service.dart:912-915` en `4f203c7`), la copia `.previo` se tomaba con `current.copy(safetyCopy)` **antes** de `appDatabase.close()`. Se copiaba sólo el archivo principal.

En modo WAL, las transacciones confirmadas desde el último checkpoint viven en `-wal`, y el checkpoint que las integra en el archivo principal lo hace precisamente `close()`. Por tanto, la copia previa no las contenía.

Si la restauración fallaba después de sustituir la base, el rollback:
1. borraba `-wal` y `-shm`;
2. devolvía esa copia incompleta.

Las transacciones recientes se perdían sin aviso. También tras una restauración correcta, la copia «por si fue un error» que se ofrece al usuario estaba incompleta.

## 2. Regresión y rojo previo

`test/f10_restore_wal_rollback_test.dart` recorre el camino real: base en archivo, `BackupService`, `GuardedRestore`, controlador de acceso real y contenedor `.agrobackup` del mismo titular, con dos fotos (una de ellas pisa el nombre de una foto actual).

**Precondición, comprobada en cada prueba y no supuesta:**
- `PRAGMA journal_mode=WAL` y `PRAGMA wal_autocheckpoint=0`, seguidos de un checkpoint `TRUNCATE` inicial;
- transacción reciente: el producto «Reciente» y una compra con foto `factura_reciente.jpg`;
- `journal_mode` es `wal` y `-wal` tiene más de 0 bytes;
- una copia del archivo principal **sin** su `-wal` contiene «Actual» pero **no** «Reciente».

| Prueba | Qué comprueba |
|---|---|
| Fallo después de empezar la sustitución | `afterReplace` confirma que la base y la foto ya son las del respaldo y entonces falla. Tras el rollback, todas las tablas (volcado completo) y todas las fotos (SHA-256 por archivo) son las previas, incluida la transacción reciente. La autorización recalculada queda `activated`. Se repite la comparación al **reabrir desde disco** con otra instancia |
| Restauración correcta | La copia `.previo` que se entrega contiene la transacción reciente |
| Residuo `-wal` de un cierre abrupto, con la base sin abrir | Archivo principal y `-wal` copiados con la conexión abierta, como los deja un proceso terminado. El rollback no pierde nada |
| La preparación falla (lector abierto) | Otra conexión mantiene una transacción de lectura. El checkpoint `TRUNCATE` devuelve busy y la restauración se rechaza con «No se pudo consolidar…» **sin cerrar ni sustituir**: datos y fotos iguales, sin copias a medias ni carpeta `invoices.previo-*`, acceso `activated`, y la app sigue escribiendo |
| El `-wal` no queda vacío tras cerrar (`3552397`) | Con el hook `afterCheckpoint`, otra conexión escribe después del checkpoint y antes del cierre. Al cerrar la conexión de la app, esa transacción sigue en `-wal`. Resultado: «No se pudo cerrar la base de forma consistente…», sin copia previa ni sustitución, y la fila de la otra conexión se conserva |
| La copia previa no coincide (`b4017a1`) | El hook trunca la copia; el cotejo de SHA-256 la rechaza y no se sustituye nada. También se compara al reabrir desde disco |
| Copia coherente sin `sync_outbox` (`5a73bea`) | Sin hooks de prueba: el manifiesto se recalcula, así que la copia pasa la validación y el titular. Falla al pausar la outbox con la base y las fotos ya sustituidas. El rollback conserva todo, incluida la transacción reciente, también al reabrir. **Rojo con el servicio de `4f203c7`** (pierde filas: `inventory_lots`) y verde con la corrección. Es la técnica que se propone para el teléfono |

**Rojo sobre el código de `4f203c7`**, con las 4 primeras pruebas y el comando `flutter test test/f10_restore_wal_rollback_test.dart`, el 2026-10-16:

```
fallo después de empezar la sustitución … [E]
  Expected: contains 'Reciente'
    Actual: Set:['Glifosato', 'Actual']
  la transacción reciente sobrevive al rollback
restauración correcta: la copia previa contiene la transacción reciente [E]
  Which: at location ['inventory_lots'][2] is [ … ] which shorter than expected
residuo WAL de un cierre abrupto … [E]
  Which: at location ['inventory_lots'][2] is [ … ] which shorter than expected
el checkpoint no puede completarse (lector abierto) … [E]
  Expected: throws <BackupException> with `message`: contains 'consolidar'
     Which: threw PathExistsException: Cannot copy file to '…\agro.db' (OS Error: … errno = 183)
00:02 +0 -4: Some tests failed.
```

El último caso falló en el host con `PathExistsException` (errno 183). **Eso es propio de Windows**: el host bloquea los archivos abiertos por la otra conexión, y en Android no ocurriría. Allí, el código anterior habría sobrescrito la base y borrado los diarios sin error, con la misma pérdida silenciosa que en los otros casos. Lo que demuestra este rojo es que el código anterior no rechazaba la preparación; no demuestra un modo de fallo propio de Android.

## 3. Corrección (`b4017a1`)

Nuevo `_secureCurrentDatabase`. Se ejecuta en exclusiva (`DatabaseReplacementGuard.replace`, sin escrituras en curso ni nuevas) y **antes de sustituir nada**:

1. Abre la base si no lo estaba. Abrirla integra el `-wal` que haya dejado un cierre abrupto.
2. Ejecuta un checkpoint `TRUNCATE` con `_consolidateForCopy`, el mismo de la exportación, con `rawQuery` por UIBUG-001. Falla si SQLite responde busy.
3. Cierra la base y comprueba que `-wal` no existe o está vacío. Si no, rechaza.
4. Copia el archivo principal a `.part`, lo fuerza a disco, coteja su tamaño y su SHA-256 con la base cerrada y sólo entonces lo renombra a `.previo-…db`.

Si la preparación falla, se borran la copia a medias, el `.part`, la carpeta `invoices.previo-*` y la extracción, y se relanza el error. El reemplazo no empieza: la base actual y sus diarios no se tocan. Si falló en los pasos 3 o 4, la base queda cerrada y se reabre en el siguiente acceso. `GuardedRestore` recalcula la autorización igualmente.

Después, el borrado de `-wal` y `-shm` antes de copiar la base restaurada sólo afecta a diarios ya vacíos, cuyo contenido está en la copia previa verificada. El rollback no cambia: cierra la base restaurada, descarta sus diarios y devuelve la copia previa, que ahora está completa.

**Sin cambios:** `GuardedRestore`, el recálculo de la autorización tras sustituir o deshacer, `RESTORE_PAUSED` dentro del tramo con rollback, el formato del contenedor y el esquema (sigue en 9).

**Mecanismo elegido y descartado:**
- Checkpoint `TRUNCATE`, cierre y copia del archivo cerrado, con verificación: es lo que ya usaba la exportación y lo admite el SQLite de cualquier Android.
- **No se usó `VACUUM INTO`.** Exige SQLite 3.27 y Android 9 trae SQLite 3.22; `sqflite` usa el SQLite del sistema.

## 4. Mutaciones

| Mutación sobre `b4017a1` | Resultado |
|---|---|
| Sin cotejar el SHA-256 de la copia previa | Falla «la copia previa no coincide…» (1 fallo, 4 pasan) |
| Sin comprobar que `-wal` quedó vacío tras cerrar (`3552397`) | Falla «el -wal no queda vacío tras cerrar…» (1 fallo, 6 pasan) |
| Sin el checkpoint previo; sólo cierre | Fallan «residuo WAL…» y «lector abierto» (2 fallos). Las dos primeras pruebas pasan, porque cerrar la última conexión ya hace el checkpoint: el cierre verificado por sí solo cubre la base abierta, pero no un `-wal` residual ni una conexión ajena |

## 5. Resultados

| Comando, sobre `b4017a1` | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test test/f10_restore_wal_rollback_test.dart` | 5/5 en `b4017a1`; 6/6 en `5a73bea`; **7/7 en `3552397`** |
| Suites de respaldo y restauración: `f10_restore_wal_rollback`, `backup_service`, `backup_container`, `backup_android_semantics`, `backup_export_atomic`, `backup_restore_sha256`, `f04_restore_authorization`, `f04_restore_ownership_rules`, `f04_admin_owner_restore_ui` y `remote_backup_client` | 116/116 en `b4017a1`; **118/118 en `3552397`** |
| `flutter test`, suite completa en solitario | 1035/2 en `b4017a1`; **1037 pasan, 2 omitidas, 0 fallos en `3552397`**. `flutter analyze` limpio |

## 6. Generador de variantes para el teléfono (`5a73bea`)

`python -I -X utf8 tool/f08_bkp/craft_negative.py <origen.agrobackup> <salida>` parte de una copia exportada por la propia app. Escribe, con el prefijo que la app lista:
- `F10-alterada`: un byte de la base cambiado y el manifiesto intacto;
- `F10-ajena`: el vínculo activo apunta a otro Member, con el manifiesto recalculado;
- `F10-fallo_tras_sustituir`: la base sin `sync_outbox`, con el manifiesto recalculado;
- `F10-bomba`: unos 300 KB que se expanden a 300 MiB y declaran 1000 bytes.

**Comprobado en host el 2026-10-16** con `BackupService`, con #91 y #92 aplicados, contra una base actual:

| Variante | Resultado |
|---|---|
| Origen | Válido, titular `aaaaaaaa…` |
| Alterada | No válida: «no coincide con su manifiesto (SHA-256)» |
| Ajena | Válida, titular `bbbbbbbb…`; la restauración se rechaza por titular |
| Fallo tras sustituir | Válida; la restauración falla con «no such table» al pausar |
| Bomba | No válida: «supera los límites» (requiere #92) |

En los cinco casos la base actual quedó intacta.

## 7. Límites

- **Sólo host.** No se sabe por estas pruebas si la base de la app en el POCO trabaja en WAL. En Android 9+, `SQLiteDatabase` aplica WAL de compatibilidad por defecto, pero no se midió. Se pide a A que lo registre en el turno (`PRAGMA journal_mode` y presencia de `-wal`).
- Un fallo **dentro** del rollback, como quedarse sin espacio al devolver la copia, no está cubierto por esta corrección. La copia previa verificada sigue en disco, junto a la base, como `<base>.previo-<fecha>.db`. Pero **la excepción no informa su ruta**: habría que localizarla en la carpeta de la base.
- El caso del `-wal` no vacío se provoca con un hook de pruebas, porque la app usa una sola conexión. Representa un fallo del mecanismo, no un uso esperado.
- La prueba del lector abierto usa una segunda conexión del motor de host. En el teléfono, la app abre una sola conexión, así que ese caso representa un fallo del mecanismo, no un uso esperado.
