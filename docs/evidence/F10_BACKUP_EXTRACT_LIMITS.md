# F10 — Límites de recursos al abrir un contenedor de respaldo (MOB #36, #55)

**Origen:** Live. **Fecha real:** 2026-10-16 (America/La_Paz). **Gate relacionado:** Roderich1/Agro_Sindicato_Backend-Web#41 (GATE-F08), **Pending**.

**Trazabilidad:** RF-27, RNF-04, RNF-10 y CU-15.

**Alcance:** pruebas de host (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.** Todos los resultados de §4 se midieron sobre el HEAD de código **`ca7e387`**.

## Commits

| Commit | Contenido |
|---|---|
| `ca74514` | Base: rama del PR #91 (copia previa con WAL), apilada porque ambos cambian el constructor de `BackupService` |
| `ed42541` | Primera versión: `lib/data/backup_container_reader.dart`, su uso en `BackupService._extract` y 26 pruebas |
| `b701804`, `2fe80a3` | Evidencia de la primera versión y merge de #91 (`d1a6b34`) |
| `f211ea0` | Revisión de A: límite propio del manifiesto, extracción asíncrona, cierre del descompresor al rechazar y límites por defecto reducidos. Dos pruebas nuevas |
| `ca7e387` | Merge de #91 (`698bc6f`). El conflicto en el constructor de `BackupService` se resolvió conservando `afterCheckpoint` y `extractionLimits` |

## 1. Implementación anterior (`ca74514`)

`_extract` usaba `ZipDecoder().decodeStream()` de `archive` 4.2.0 y, para cada entrada, `entry.readBytes()`.

Leyendo el código de la librería se ve que:
- `readBytes()` descomprime la entrada **entera en memoria**. Con deflate usa `ZLibDecoder().decodeBytes()` si los datos comprimidos ocupan menos de 500 MB.
- `writeContent()` tampoco escribe a medida que descomprime: el decodificador de `dart:io` acumula todos los fragmentos hasta cerrar y sólo entonces los entrega.
- Al decodificar el directorio, una entrada marcada como enlace simbólico de Unix se descomprime en memoria antes de que el código de la app vea nada.

Sólo se rechazaban los nombres que, normalizados, empezaban por `..` o eran absolutos. No había límite de tamaño, de número de entradas ni de forma.

**Rojo de los 24 casos de la primera versión sobre `ca74514`**, en una copia temporal no publicada de la suite:
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

## 2. Defectos de la primera versión, hallados en la revisión de A (`2fe80a3`)

1. **El manifiesto sólo tenía el límite general por entrada.** `manifest.json` se lee entero con `readAsString` y `jsonDecode`.
   - Lo reproducido por A: un contenedor de 204 004 bytes con un manifiesto honesto de 200 MiB subía el pico unos 657 MiB, y con 256 MiB, unos 903 MiB.
   - **Rojo propio sobre el lector de `2fe80a3`:** un contenedor de 65 459 bytes con un manifiesto honesto de 64 MiB y CRC correcto subió el pico **157 MiB**. Se rechazó sólo después, por «manifiesto dañado».
2. **El descompresor no se cerraba** si se rechazaba a mitad.
3. **Extracción síncrona en el hilo de la interfaz.** Con una entrada de 48 MiB poco comprimible, la pausa más larga del bucle de eventos fue de **176 ms de 184 ms** de extracción, sobre el lector de `2fe80a3`. Con el límite total de entonces, 512 MiB, un contenedor de menos de 1 MB podía bloquear el hilo mientras escribía cientos de MiB: un ANR posible en un teléfono lento.
4. La evidencia anterior se midió sobre `ed42541`, no sobre el HEAD. Esta versión se mide sobre `ca7e387`.

## 3. Lector acotado (versión final)

`BackupContainerReader` lee sólo lo que escribe la aplicación (`ZipFileEncoder`) y no añade dependencias.

**Antes de extraer**, con el directorio central:
- tamaño del contenedor;
- número de entradas, también el que declara el registro de fin de directorio;
- tamaño declarado de cada entrada frente a **su** límite (el del manifiesto o el general) y la suma;
- límites de los datos de cada entrada;
- forma de los nombres: sólo `manifest.json`, `database.db`, `invoices/` e `invoices/<archivo>`, sin `\`, `:`, caracteres de control, `.`, `..` ni nombres de más de 255 bytes;
- sin entradas repetidas, tampoco si sólo difieren en mayúsculas;
- sin enlaces simbólicos, cifrado, ZIP64, varios discos ni métodos distintos de stored y deflate.

**Durante la extracción**, que es **asíncrona**:
- lee pasos de 8 KiB comprimidos;
- descomprime cada paso con `ZLibCodec(raw: true)` de `dart:io`;
- cuenta los bytes **que realmente produce** y corta en cuanto superan el tamaño declarado de la entrada, su límite o el total;
- escribe lo ya comprobado con escrituras asíncronas.

Entre paso y paso, el hilo de la interfaz atiende otros eventos. Si se rechaza a mitad, el descompresor se cierra igualmente.

**Al final de cada entrada:** exige que el tamaño y el CRC-32 coincidan con lo declarado.

Ante cualquier rechazo, `_extract` borra la carpeta temporal y lanza un `BackupException` con un mensaje presentable. Tanto `validate`, `inspectOwnership` como la restauración pasan por ella. El rechazo ocurre **antes** de preparar la sustitución, así que no se tocan la base, las fotos ni las copias previas.

**Límites por defecto** (`BackupExtractionLimits`, configurables al construir `BackupService`). Son técnicos, no una política institucional:

| Límite | Valor | Justificación |
|---|---|---|
| Entradas | 5002 | El manifiesto, la base y hasta 5000 fotos, una por compra |
| Manifiesto | **4 MiB** | Se lee entero en memoria. Cada foto ocupa en él menos de 600 bytes (nombre de hasta 255, SHA-256, tamaño y compras), así que 5000 caben en unos 3 MB |
| Por entrada | **128 MiB** | Los datos de varios años de un hogar ocupan pocos MB. Las fotos se guardan a 1800 px y calidad 82 |
| Total expandido | **256 MiB** | Lo que se escribe en la carpeta temporal antes de validar. El servidor admite contenedores de hasta `BACKUP_MAX_BYTES` (100 MiB por defecto) y las fotos no se comprimen, así que un contenedor legítimo se expande poco |
| Contenedor | **257 MiB** | Un contenedor legítimo no ocupa más que su contenido más las cabeceras |
| Nombre | 255 bytes | Máximo habitual de un nombre de archivo |

No cambian el formato del contenedor, el manifiesto ni el esquema.

## 4. Resultados sobre `ca7e387`

**Medición** con una sonda temporal no publicada que llama a `BackupService(db).validate()`, en un proceso por caso:

| Caso | Contenedor | Crecimiento del pico de memoria | Tiempo | Resultado |
|---|---|---|---|---|
| Bomba de 300 MiB de ceros que declara 1000 bytes | 305 987 B | +0 MiB | 51 ms | «El respaldo supera los límites de tamaño admitidos…» |
| La misma bomba declarando 300 MiB | 305 987 B | +0 MiB | 35 ms | El mismo rechazo, antes de extraer |
| Manifiesto honesto de 64 MiB | 65 459 B | +0 MiB | 41 ms | El mismo rechazo, antes de extraer |

Como referencia, la implementación de `ca74514` con la primera bomba creció **+903 MiB**, tardó 506 ms y escribió 300 MiB en temporales.

**Pruebas (28):**

| Grupo | Casos |
|---|---|
| Bomba | Cabecera honesta (300 MiB): rechazo antes de extraer. Cabecera mentirosa (1000 bytes): corte durante la extracción y **pico por debajo de 128 MiB**. En ambos casos, base y fotos iguales y sin temporales, con la carpeta temporal redirigida mediante `IOOverrides` |
| Manifiesto y hilo | Manifiesto honesto de 64 MiB por debajo del límite general: rechazo antes de extraer y pico por debajo de 32 MiB. **Ninguna pausa del hilo ocupa más de un cuarto** de la extracción de una entrada de 48 MiB. Medido en 3 ejecuciones: pausa más larga de 3-4 ms en 230 ms. **Ambas pruebas en rojo sobre el lector de `2fe80a3`** (pausa de 176 ms en 184) |
| Cerca del límite | Contenedor válido exportado por la app con 3 fotos y 5 entradas. Con los límites **exactos**, incluido el del manifiesto, se valida y se restaura (3 fotos). Con **uno menos** en entradas, manifiesto, por entrada, total o contenedor se rechaza sin tocar nada. Los límites por defecto admiten un contenedor normal |
| Rutas | 11 nombres peligrosos o ajenos, 2 tipos de entrada repetida y un enlace simbólico. Además se comprueba que no aparece nada fuera de la carpeta |
| Integridad | CRC, expansión menor que la declarada, entrada guardada con tamaño incoherente, deflate truncado, cifrado, bzip2, ZIP64 y un archivo que empieza por `PK` sin ser ZIP |

| Comando, sobre `ca7e387` | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test test/f10_backup_extract_limits_test.dart` | 28/28 |
| Suites de respaldo y restauración, las de #91 más esta | **146/146** |
| `flutter test`, suite completa en solitario | **1065 pasan, 2 omitidas, 0 fallos** |

## 5. Límites

- **Sólo host.** En el teléfono no se ha probado una bomba ni un contenedor cerca del límite. El turno pedido a A cubre la ruta normal y los negativos factibles con la UI, incluida la variante `F10-bomba`.
- La medición de memoria usa el pico del proceso de pruebas, y la de las pausas, un temporizador de 1 ms en el host. Son indicadores, no un perfil del teléfono.
- No se comprueba el espacio libre antes de extraer. Si el almacenamiento se llena, la escritura falla, el error se informa y se borra lo extraído.
- Un contenedor legítimo grande sigue tardando lo que tarda escribir su contenido. Ahora lo hace sin bloquear el hilo, y nunca más de 256 MiB con los límites por defecto.
