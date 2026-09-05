# UIBUG-001 - verificacion en Pixel 8

**Exportar backup falla siempre en Android**

Estado: `OPEN` -> `FIXED_NOT_DEVICE_VERIFIED` -> **`VERIFIED`**

## Entorno de verificacion

| | |
|---|---|
| **Fecha** | 2026-09-05 |
| **AVD** | `Pixel_8` (`emulator-5554`, `sdk_gphone16k_x86_64`) |
| **Android** | 16 (API 36) |
| **Resolucion** | 1080 x 2400 - 420 dpi - vertical |
| **Escala de fuente** | 1.0 |
| **Build mode** | `debug` (`app-debug.apk`) |
| **Dataset** | `36_UI_AUDIT_DATASET.md`, esquema v5, recargado con `bash tool/ui_audit_push.sh --apk` |
| **Lectura de base** | `bash tool/pull_device_db.sh` + consulta SQL local |

## Causa raiz corregida

`backup_service.dart:63` ejecutaba

```dart
await database.execute('PRAGMA wal_checkpoint(FULL)');
```

En Android `sqflite` mapea `Database.execute` a `SQLiteDatabase.execSQL`, que
**rechaza toda sentencia que devuelva filas**, y `wal_checkpoint` devuelve una
`(busy, log, checkpointed)`. Sobre `sqflite_common_ffi` (escritorio) `execute` si
las admite, de modo que la suite estaba verde mientras la funcion no habia
funcionado nunca en la plataforma real.

**Agravante encontrado al corregir**: `test/backup_service_test.dart` **nunca
llamaba a `export()`** — solo probaba `validate()` y `restore()`. La exportacion
no tenia ninguna cobertura, ni buena ni mala.

### Correccion aplicada

1. Los PRAGMA que devuelven filas pasan por **`rawQuery`**, no por `execute`.
2. El checkpoint **solo se hace si el diario es WAL**. Se comprueba antes con
   `PRAGMA journal_mode`. (En este dispositivo el modo real resulto ser
   `delete`, con lo que el checkpoint no era siquiera necesario: aun asi la
   sentencia rompia la exportacion.)
3. Se usa `wal_checkpoint(TRUNCATE)` en vez de `FULL`: hace lo mismo y ademas
   deja el `-wal` a cero, de modo que copiar el archivo principal basta.
4. **Se comprueba el resultado del checkpoint** (`busy != 0`) y se aborta con un
   mensaje claro en vez de escribir un respaldo incompleto en silencio.
5. **`export()` valida el archivo que acaba de escribir** con la propia
   `validate()`; si no es legible lo borra y lanza. Un archivo con nombre de
   respaldo en el que no se puede confiar es peor que ninguno.

Se descarto `VACUUM INTO` (que seria la operacion mas directa para una copia
consistente) porque **exige SQLite >= 3.27** y el `minSdk` del proyecto es **24**
(Android 7), cuyo SQLite del sistema es anterior: habria cambiado un fallo de
plataforma por otro en los dispositivos antiguos.

## Pasos ejecutados en el dispositivo

Criterio completo exigido, de principio a fin:

1. Cuentas -> icono de copias -> **Exportar backup**.
2. Comprobar que el archivo existe en el dispositivo.
3. **Modificar los datos**: registrar un pago de `2.750` a Jose Luis.
4. Cuentas -> icono de copias -> **Restaurar backup** -> elegir el archivo ->
   **Restaurar**.
5. Volver a leer la base del dispositivo.

## Resultado

### 1-2. Exportacion

Snackbar (ya no es el rojo de error):

    Backup guardado en /storage/emulated/0/Android/data/
    com.comunidad.agro.agroquimicos/files/Download/
    agroquimicos_backup_2026-09-05T18-50-27.260206.db

```
$ adb shell ls -la .../files/Download
-rw------- 1 u0_a225 ext_data_rw 196608 2026-09-05 18:50
   agroquimicos_backup_2026-09-05T18-50-27.260206.db
```

Captura: `after-exportar-backup.png`.

### 3. validate() OK

La lista de respaldos **encuentra el archivo** (antes siempre respondia *"No se
encontro ningun backup"*, porque nunca se habia escrito ninguno) y el dialogo de
confirmacion muestra **"Esquema version 5"**, que solo puede leerse abriendo y
validando el archivo.

Capturas: `after-backup-encontrado.png`, `after-validate-ok-esquema-v5.png`.

### 4-5. Ciclo completo de recuperacion

| Momento | `account_transactions` | Saldo de Jose Luis (minor) |
|---|---:|---:|
| Antes de exportar | 27 | 3005700 |
| Tras registrar el pago de 2.750 | **28** | **2730700** |
| **Tras restaurar el respaldo** | **27** | **3005700** |

**El estado anterior se recupero exactamente.** Captura: `after-restauracion.png`.

### Logs

Durante todo el ciclo, `logcat` no registro ninguna coincidencia con
`DatabaseException`, `wal_checkpoint`, `SQLiteDatabase query` ni `disposed`.

## Tests relacionados

- `test/backup_android_semantics_test.dart` (**nuevo**) - 3 tests que reproducen
  la restriccion de Android envolviendo la fabrica de escritorio: `execute`
  rechaza las sentencias que devuelven filas, igual que `execSQL`. Antes del fix
  los tres fallaban con el mensaje **literal** del dispositivo:

  ```
  DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be performed
  using SQLiteDatabase query or rawQuery methods only.) sql
  'PRAGMA wal_checkpoint(FULL)' args []
  ```

  Cubren: que `export()` no use una sentencia que Android rechace; que el
  respaldo exportado **valide y se restaure** devolviendo el estado anterior; y
  que una fila escrita **justo antes** de exportar aparezca en el respaldo
  (consistencia de la copia).
- `test/backup_service_test.dart` (existente) sigue verde, sin modificar.

Ver `before-red-test.txt` para la salida en rojo completa.

## Evidencia anterior

Ver `before-reference.txt`. Las capturas originales de la auditoria **no se han
borrado**: siguen en `artifacts/ui-audit/UI-10-liquidacion/`.
