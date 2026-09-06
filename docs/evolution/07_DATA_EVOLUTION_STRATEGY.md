# Estrategia de evolución de datos

## Principio

Los datos del usuario sobreviven a las decisiones de arquitectura. Nunca se prescribe borrar
la base, reinstalar ni recrear tablas como migración de producción.

## Versionado SQLite

- Incrementar `AppDatabase.schemaVersion` sólo ante cambio real de esquema.
- Una versión tiene una ruta forward-only desde toda versión soportada.
- `onCreate(vN)` y `onUpgrade(vX→vN)` deben terminar en esquemas equivalentes.
- No reutilizar un número ni modificar retroactivamente una migración publicada.
- Constraints e índices que protegen invariantes forman parte del contrato, no de tuning.

## Diseño de migración

1. Inventariar volúmenes, nulos, duplicados y valores históricos.
2. Definir precondiciones, transformación y estado posterior.
3. Preferir añadir/copiar/verificar antes de retirar.
4. No descartar filas anómalas: conservarlas, registrar `MIG-*` y bloquear sólo la operación
   peligrosa. El patrón de `app_settings` usado en v5/v6 es la referencia.
5. Mantener claves foráneas y comprobar `PRAGMA foreign_key_check` e `integrity_check`.

## Pruebas obligatorias

- Base nueva en versión destino.
- Migración desde cada versión soportada o, como mínimo, cada salto con forma distinta.
- Equivalencia de tablas, columnas, índices, triggers y constraints relevantes.
- Dataset vacío, realista, voluminoso y anómalo.
- Reejecución/apertura posterior y operaciones críticas después de migrar.
- Backup previo, restore y migración en el mismo recorrido.

## Rendimiento

No agregar índices por intuición. Documentar consulta, cardinalidad y evidencia. Migraciones
pesadas deben tener fase de preparación, progreso visible o bloqueo controlado; hoy la apertura
es perezosa y una migración ocurre durante la primera carga.

## Backup

- Un cambio de schema no implica automáticamente cambiar el formato `.agrobackup`.
- Cambiar `backupFormatVersion` sólo si cambia el contenedor/manifest/semántica.
- El lector debe rechazar versiones desconocidas sin tocar datos.
- Mantener lectura legacy `.db` hasta una decisión explícita con plan de retiro.
- Toda restauración sigue siendo atómica respecto de DB + fotografías.

## Rollback operativo

SQLite no baja de versión. El rollback seguro es restaurar el conjunto respaldado antes del
cambio con una versión de app compatible. Por eso toda evolución irreversible declara:
versión mínima, preflight, copia, verificación y ruta de recuperación.
