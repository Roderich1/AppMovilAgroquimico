# F10 — Límites de recursos al abrir un contenedor de respaldo (MOB #36, #55)

**Origen:** Live. **Fecha real:** 2026-10-16 (America/La_Paz). **Gate relacionado:** Roderich1/Agro_Sindicato_Backend-Web#41 (GATE-F08), **Pending**.

**Trazabilidad:** RF-27, RNF-04, RNF-10 y CU-15.

**Alcance:** pruebas de host (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**

## Commits

| Commit | Contenido |
|---|---|
| `ca74514` | Base: rama del PR #91 (copia previa con WAL), apilada porque ambos cambian el constructor de `BackupService` |
| `ed42541` | `lib/data/backup_container_reader.dart`, su uso en `BackupService._extract` y 26 pruebas: `test/f10_backup_extract_limits_test.dart` y `test/support/raw_zip.dart` |

## 1. Implementación anterior

`_extract` usaba `ZipDecoder().decodeStream()` de `archive` 4.2.0 y, para cada entrada, `entry.readBytes()`.

Leyendo el código de la librería se ve que:
- `readBytes()` descomprime la entrada **entera en memoria**. Con deflate usa `ZLibDecoder().decodeBytes()` si los datos comprimidos ocupan menos de 500 MB.
- `writeContent()` tampoco escribe a medida que descomprime: el decodificador de `dart:io` acumula todos los fragmentos hasta cerrar y sólo entonces los entrega.
- Al decodificar el directorio, una entrada marcada como enlace simbólico de Unix se descomprime en memoria antes de que el código de la app vea nada.

Sólo se rechazaban los nombres que, normalizados, empezaban por `..` o eran absolutos. No había límite de tamaño, de número de entradas ni de forma.

**Medición sobre `ca74514`**, con una sonda temporal no publicada que llama a `BackupService(db).validate()` sobre una bomba de **305 987 bytes**: 300 MiB de ceros en deflate.

| Implementación | Tamaño declarado | Crecimiento del pico de memoria (`ProcessInfo.maxRss`) | Tiempo | Resultado |
|---|---|---|---|---|
| Anterior | 1000 bytes | **+903 MiB**; además escribió los 300 MiB en la carpeta temporal | 506 ms | Rechazada al final, porque el manifiesto no cuadraba |
| Lector acotado | 1000 bytes | +0 MiB | 22 ms | «El respaldo supera los límites de tamaño admitidos…» |
| Lector acotado | 300 MiB | +0 MiB | 12 ms | El mismo rechazo, antes de extraer |

La segunda fila de la implementación anterior no se midió de forma independiente: `maxRss` es el pico del proceso y ya estaba alto.

**Rojo de la suite nueva sobre `ca74514`.** Se ejecutaron los 24 casos que no dependen de la API nueva de límites, en una copia temporal no publicada de la suite:
- **21 fallos**;
- 3 pasan: `../`, `invoices/../../` y la ruta absoluta ya se rechazaban.

Los fallos, por causa:
- **Bombas (2):** las rechazaba tarde, por el SHA-256 de la base, tras expandirlas por completo.
- **Aceptadas como válidas (12):**
  - rutas con separador de Windows, con unidad, de más de un nivel, en una carpeta ajena o de un archivo ajeno;
  - las dos clases de entrada repetida;
  - el enlace simbólico;
  - el CRC del manifiesto que no coincide;
  - la expansión menor que la declarada;
  - la entrada guardada con un tamaño incoherente;
  - los marcadores ZIP64.
- **Excepción del sistema de archivos o del descompresor en vez de un rechazo controlado (4):** `invoices/..`, el carácter de control, el nombre largo y la entrada cifrada.
- **Rechazadas sólo por una comprobación posterior (3):** el deflate truncado y bzip2 por el SHA-256, y el archivo `PK` por la falta del manifiesto.

Los fallos de estos 3 casos y de los 4 anteriores son de diagnóstico, no de seguridad: el resultado final ya era un rechazo.

## 2. Lector acotado

`BackupContainerReader` lee sólo lo que escribe la aplicación (`ZipFileEncoder`) y no añade dependencias.

**Antes de extraer**, con el directorio central:
- tamaño del contenedor;
- número de entradas, también el que declara el registro de fin de directorio;
- tamaño declarado de cada entrada y su suma;
- límites de los datos de cada entrada;
- forma de los nombres: sólo `manifest.json`, `database.db`, `invoices/` e `invoices/<archivo>`, sin `\`, `:`, caracteres de control, `.`, `..` ni nombres de más de 255 bytes;
- sin entradas repetidas, tampoco si sólo difieren en mayúsculas;
- sin enlaces simbólicos, cifrado, ZIP64, varios discos ni métodos distintos de stored y deflate.

**Durante la extracción:** descomprime con `ZLibCodec(raw: true)` de `dart:io` por fragmentos de 64 KiB y cuenta los bytes **que realmente produce**. Corta en cuanto superan el tamaño declarado de la entrada, el límite por entrada o el total. No se fía de los metadatos.

**Al final de cada entrada:** exige que el tamaño y el CRC-32 coincidan con lo declarado.

Ante cualquier rechazo, `_extract` borra la carpeta temporal y lanza un `BackupException` con un mensaje presentable. Tanto `validate`, `inspectOwnership` como la restauración pasan por ella. El rechazo ocurre **antes** de preparar la sustitución, así que no se tocan la base, las fotos ni las copias previas.

**Límites por defecto** (`BackupExtractionLimits`, configurables al construir `BackupService`). Son técnicos, no una política institucional:

| Límite | Valor | Justificación |
|---|---|---|
| Entradas | 5002 | El manifiesto, la base y hasta 5000 fotos, una por compra |
| Por entrada | 256 MiB | La base más grande razonable. Las fotos se guardan a 1800 px y calidad 82 |
| Total expandido | 512 MiB | Lo que se escribe en la carpeta temporal antes de validar |
| Contenedor | 513 MiB | Un contenedor legítimo no ocupa más que su contenido más las cabeceras. El servidor admite además sólo hasta `BACKUP_MAX_BYTES`, 100 MiB por defecto |
| Nombre | 255 bytes | Máximo habitual de un nombre de archivo |

No cambian el formato del contenedor, el manifiesto ni el esquema.

## 3. Pruebas nuevas (26)

| Grupo | Casos |
|---|---|
| Bomba | Cabecera honesta (300 MiB): rechazo antes de extraer. Cabecera mentirosa (1000 bytes): corte durante la extracción y **pico de memoria por debajo de 128 MiB**. En ambos casos, base y fotos iguales y sin temporales, con la carpeta temporal redirigida mediante `IOOverrides` |
| Cerca del límite | Contenedor válido exportado por la app con 3 fotos y 5 entradas. Con los límites **exactos** se valida y se restaura (3 fotos). Con **uno menos** en entradas, por entrada, total o contenedor se rechaza sin tocar nada. Los límites por defecto admiten un contenedor normal |
| Rutas | 11 nombres peligrosos o ajenos, 2 tipos de entrada repetida y un enlace simbólico. Además se comprueba que no aparece nada fuera de la carpeta |
| Integridad | CRC, expansión menor que la declarada, entrada guardada con tamaño incoherente, deflate truncado, cifrado, bzip2, ZIP64 y un archivo que empieza por `PK` sin ser ZIP |

## 4. Resultados

| Comando, sobre el contenido de `ed42541` | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test test/f10_backup_extract_limits_test.dart` | 26/26 |
| Suites de respaldo existentes (`backup_service`, `backup_container`, `backup_android_semantics`, `backup_export_atomic`, `backup_restore_sha256`, `f04_restore_authorization`, `remote_backup_client` y `f10_restore_wal_rollback`) con el lector nuevo | 99/99 |
| `flutter test`, suite completa en solitario | **1061 pasan, 2 omitidas, 0 fallos** |

## 5. Límites

- **Sólo host.** En el teléfono no se ha probado una bomba ni un contenedor cerca del límite. El turno pedido a A cubre la ruta normal y los negativos factibles con la UI.
- La medición de memoria usa el pico del proceso de pruebas. Es un indicador, no un perfil de memoria del teléfono.
- No se comprueba el espacio libre antes de extraer. Si el almacenamiento se llena, la escritura falla, el error se informa y se borra lo extraído.
- La extracción sigue en el hilo de la interfaz, como antes. Lo acotan los límites, pero un contenedor legítimo grande puede detenerla unos segundos.
