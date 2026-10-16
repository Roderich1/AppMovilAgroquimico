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
| La copia previa no coincide (`b4017a1`) | El hook trunca la copia; el cotejo de SHA-256 la rechaza y no se sustituye nada. También se compara al reabrir desde disco |

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

El último caso muestra algo peor que una pérdida silenciosa. Con otra conexión abierta, el código anterior sustituía la base, borraba diarios en uso y, al deshacer, **no podía devolver** la copia previa.

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
| Sin el checkpoint previo; sólo cierre | Fallan «residuo WAL…» y «lector abierto» (2 fallos). Las dos primeras pruebas pasan, porque cerrar la última conexión ya hace el checkpoint: el cierre verificado por sí solo cubre la base abierta, pero no un `-wal` residual ni una conexión ajena |

## 5. Resultados

| Comando, sobre `b4017a1` | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test test/f10_restore_wal_rollback_test.dart` | 5/5 |
| Suites de respaldo y restauración: `f10_restore_wal_rollback`, `backup_service`, `backup_container`, `backup_android_semantics`, `backup_export_atomic`, `backup_restore_sha256`, `f04_restore_authorization`, `f04_restore_ownership_rules`, `f04_admin_owner_restore_ui` y `remote_backup_client` | **116/116** |
| `flutter test`, suite completa en solitario | **1035 pasan, 2 omitidas, 0 fallos** |

## 6. Límites

- **Sólo host.** No se sabe por estas pruebas si la base de la app en el POCO trabaja en WAL. En Android 9+, `SQLiteDatabase` aplica WAL de compatibilidad por defecto, pero no se midió. Se pide a A que lo registre en el turno (`PRAGMA journal_mode` y presencia de `-wal`).
- Un fallo **dentro** del rollback, como quedarse sin espacio al devolver la copia, no está cubierto por esta corrección. La copia previa verificada sigue en disco y su ruta se conserva.
- La prueba del lector abierto usa una segunda conexión del motor de host. En el teléfono, la app abre una sola conexión, así que ese caso representa un fallo del mecanismo, no un uso esperado.
