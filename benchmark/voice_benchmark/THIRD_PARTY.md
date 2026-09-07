# Componentes de terceros del banco de pruebas

Todo lo que sigue vive **sólo** en `benchmark/voice_benchmark`. La aplicación
Agrocuentas no depende de nada de esta lista y su APK no cambió de tamaño al
incorporarla.

## whisper.cpp

| Campo | Valor |
|---|---|
| Proyecto | `ggml-org/whisper.cpp` |
| Commit fijado | `52a939a2a762224e255d366c1182b2af4dd1a032` (2026-09-04) |
| Versión declarada | ggml `0.23.0` |
| Licencia | MIT — © 2023-2026 The ggml authors |
| Uso | Compilado desde fuente por `tool/build_whisper_libs.sh` |
| Se versiona | No: el script lo obtiene del commit fijado |

### Código derivado

`android/app/src/whisperCommon/cpp/whisper_jni.c` y su `CMakeLists.txt` derivan
de `examples/whisper.android/lib/src/main/jni/whisper/` de ese repositorio, bajo
la misma licencia MIT.

**La diferencia no es cosmética.** El wrapper original fija
`params.language = "en"`. Medir español con la pista de idioma en inglés habría
falseado todo el benchmark, porque el modelo multilingüe se comporta distinto
según ese parámetro. En la versión propia el idioma es un argumento y queda
registrado en cada resultado.

Además se compila con `GGML_OPENMP=OFF`: con OpenMP activado, `libggml-base.so`
queda enlazada contra `libomp.so`, que el NDK no empaqueta, y la carga falla en
el teléfono con `dlopen failed: library "libomp.so" not found`. Se detectó
instalando el APK, no leyendo documentación.

### Librerías producidas

Compiladas con NDK `28.2.13676358`, `android-24`, `Release`, sin símbolos.

| ABI | `libwhisper_bench.so` | `libggml-base.so` | `libggml-cpu.so` | `libggml.so` | Total |
|---|--:|--:|--:|--:|--:|
| `arm64-v8a` | 1.047.328 | 1.157.608 | 873.760 | 123.344 | **3.202.040 B** |
| `armeabi-v7a` | 676.332 | 773.500 | 709.032 | 64.220 | **2.223.084 B** |
| `x86_64` | 1.062.400 | 1.132.880 | 1.049.720 | 120.632 | **3.365.632 B** |

Ninguna depende de `libc++_shared.so` ni de `libomp.so`: sólo de `libc`, `libm`,
`libdl`, `liblog` y `libandroid`. No hace falta empaquetar nada más.

## Modelos Whisper

| Campo | `tiny` | `base` |
|---|---|---|
| Archivo | `ggml-tiny-q5_1.bin` | `ggml-base-q5_1.bin` |
| Fuente | `huggingface.co/ggerganov/whisper.cpp` | igual |
| Tamaño | 32.152.673 B (30,7 MiB) | 59.707.625 B (56,9 MiB) |
| SHA-256 | `818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7` | `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898` |
| Cuantización | `q5_1` | `q5_1` |
| Multilingüe | Sí | Sí |
| Licencia | MIT (pesos de OpenAI Whisper); conversión ggml por whisper.cpp (MIT) | igual |
| Empaquetado | Asset del sabor `whisperTiny` | Asset del sabor `whisperBase` |
| Se versiona | No: lo baja `tool/fetch_whisper_models.sh` y verifica el hash | igual |

El modelo viaja **dentro del APK**: el teléfono no necesita Internet para
transcribir. También puede sustituirse sin recompilar dejando el archivo en
`<carpeta de la app>/models/<nombre>`, que tiene prioridad sobre el asset.

## Vosk (Fase 0-bis)

Incorporado para medir `ADR-004`. **Nada de esto entra en Agrocuentas**: vive sólo en este
banco y `ADR-004` sigue `Proposed`.

### Biblioteca

| Campo | Valor |
|---|---|
| Proyecto | `alphacep/vosk-api` |
| Licencia | Apache-2.0 (verificada en la API de GitHub) |
| Artefacto | `com.alphacephei:vosk-android:0.3.75` (Maven Central) |
| Publicado | 2025-12-08 |
| Tamaño del AAR | 13.472.638 B |
| SHA-256 del AAR | `ab2f8b91ac8051561aa325546b35fed9a68b36b8121bac5c6fb927525c4adfad` |
| SHA-1 publicado | `40764b038a882055e1a57c33136c86ab9b7db2ee` |
| `libvosk.so` arm64-v8a | 10.042.800 B |
| Se versiona | No: lo resuelve Gradle desde Maven Central |

**Por qué un artefacto y no un commit.** El resto del banco fija commits: `whisper.cpp` se
compila desde uno concreto. Con Vosk no se puede hacer lo mismo. Sus *releases* de GitHub
llegan a `v0.3.50` y sólo `v0.3.45` publicó un `.zip` para Android; el artefacto que la
distribución oficial mantiene vive en Maven Central y llega a `0.3.75`, **sin tag público
equivalente** (`https://api.github.com/repos/alphacep/vosk-api/git/ref/tags/v0.3.47` responde
`Not Found`). Compilar `vosk-api` desde fuente para Android arrastra Kaldi y OpenFST completos.
Lo que sí se puede fijar es versión exacta más SHA-256 del binario, que es lo que se hace.
Queda registrado como `RISK-033` y es decisión pendiente del propietario.

**Por qué `0.3.75` y no `0.3.47`.** Se midieron las cabeceras ELF de `jni/arm64-v8a/libvosk.so`
de ambas:

| Versión | `p_align` de los segmentos `LOAD` | Compatible con páginas de 16 KB |
|---|---|---|
| `0.3.75` | `16384` | **Sí** |
| `0.3.47` | `4096` | No |

Android 15 y posteriores admiten aparatos con páginas de 16 KB, donde una librería alineada a
4 KB **no carga**. El HONOR de esta fase usa páginas de 4096 —`getconf PAGE_SIZE`— así que allí
cualquiera de las dos funcionaría; elegir la alineada evita reproducir, en un aparato futuro,
exactamente la clase de fallo por incompatibilidad que abrió esta fase.

### Firma PGP: **no verificable**

Maven Central publica `.asc` para el AAR y el POM. Se intentó verificar y **no se pudo cerrar
la cadena de confianza**. Se registra tal cual, sin presentarla como comprobada:

| Dato | Valor |
|---|---|
| Firma creada | 2025-12-08 16:52:05 |
| Clave firmante | RSA `4A454BDCD9D47FE2` |
| Huella completa de esa subclave | `52D24C01CB76F44728F566A74A454BDCD9D47FE2` |
| Clave primaria | `BD81E366B50708218FABB1DEBBC8CD3EE461F718` — `Nickolay V. Shmyrev <nshmyrev@alphacephei.com>` |
| Origen de la clave | `keyserver.ubuntu.com`; tambien en `pgp.mit.edu` y `pgpkeys.eu`. `keys.openpgp.org` responde 404 |
| Resultado de `gpg --verify` | **`Can't check signature: No public key`** |

Dos motivos, ambos comprobados en el material publicado:

1. La clave primaria y su subclave **caducaron el 2023-11-07**, dos anos antes de la fecha de
   la firma.
2. La subclave `4A454BDCD9D47FE2` esta publicada como **`[E]`, solo cifrado**, no como clave de
   firma. `gpg` no la acepta para verificar y no existe otra copia con capacidad de firma en
   ninguno de los cuatro servidores consultados.

La identidad del firmante **es coherente** con el autor de Vosk, pero eso es una observacion,
no una verificacion criptografica. Lo que si queda comprobado es la integridad: el SHA-256 que
publica Maven Central coincide byte a byte con el calculado localmente. Va a `RISK-033`.

### Dependencia transitiva: JNA

Unica transitiva declarada por el POM, y con `<exclusions>` de `*:*`, de modo que no arrastra
nada mas.

| Campo | Valor |
|---|---|
| Coordenadas | `net.java.dev.jna:jna:5.18.1` (empaquetado `aar`) |
| Licencia | **LGPL-2.1-or-later O Apache-2.0**, a eleccion del consumidor segun el POM |
| Licencia elegida aqui | **Apache-2.0**, para no arrastrar las obligaciones de relinkeo de la LGPL |
| Tamano del AAR | 522.677 B |
| SHA-256 del AAR | `7f053e3ec99e14dd71259c82c1c8a02738d64a13c31226b2acc170f3060951e0` |
| Transitivas propias | Ninguna |
| ABIs con `.so` | `arm64-v8a`, `armeabi`, `armeabi-v7a`, `mips`, `mips64`, `x86`, `x86_64` |
| `libjnidispatch.so` arm64-v8a | 176.520 B |

Maven Central **no publica** `.sha256` para este artefacto (404); el hash de la tabla es el
calculado sobre la descarga y es el que fija la verificacion de dependencias de Gradle.

### Librerias nativas: 16 KB comprobados

Ejecutado con `dart run tool/check_native_alignment.dart` sobre los dos AAR. Evidencia en
`artifacts/hybrid-bench/supply-chain/aar-alignment.json`.

| Libreria | ABI | Bytes | `p_align` | Veredicto |
|---|---|--:|--:|---|
| `libvosk.so` | `arm64-v8a` | 10.042.800 | 16384 | OK |
| `libvosk.so` | `x86_64` | 10.335.120 | 16384 | OK |
| `libvosk.so` | `armeabi-v7a` | 8.985.628 | 4096 | No aplica (32 bits) |
| `libvosk.so` | `x86` | 10.397.552 | 4096 | No aplica (32 bits) |
| `libjnidispatch.so` | `arm64-v8a` | 176.520 | 16384 | OK |
| `libjnidispatch.so` | `x86_64` | 126.912 | 16384 | OK |
| `libjnidispatch.so` | `mips64` | 150.256 | 16384 | OK |

El requisito de 16 KB se aplica **solo a las ABIs de 64 bits**: los aparatos con paginas de
16 KB no ejecutan codigo de 32 bits. Los APK de este banco se construyen `arm64-v8a` unicamente.

Esto comprueba el **ELF** y nada mas. Faltan, y no se sustituyen entre si, el alineamiento
dentro del ZIP (`zipalign -c -P 16 -v 4`) y la ejecucion real con `PAGE_SIZE=16384`.

### Modelo español

| Campo | Valor |
|---|---|
| Modelo | `vosk-model-small-es-0.42` |
| Fuente | `https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip` |
| Licencia | Apache 2.0 (declarada en la lista oficial) |
| Tamaño comprimido | 39.817.833 B (37,97 MiB) |
| Tamaño instalado | 60.286.598 B (57,49 MiB), 14 archivos |
| SHA-256 del zip | `09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f` |
| WER declarada | 16,02 (cv test) · 16,72 (mtedx test) · 11,21 (mls) |
| Se versiona | No: lo baja `tool/fetch_vosk_model.sh` y verifica el hash |

**No existe un modelo español de Vosk de 180 MB.** Comprobado en la lista oficial: sólo hay dos
modelos españoles, el móvil de 39 MB y `vosk-model-es-0.42` de 1,4 GB, orientado a servidor.
Los ~180 MB que circulaban corresponden a otra cosa: son el tamaño de `ggml-small-q5_1.bin`
(181,28 MiB), el modelo de Whisper.

## Modelo Whisper small (Fase 0-bis)

| Campo | Valor |
|---|---|
| Archivo | `ggml-small-q5_1.bin` |
| Fuente | `huggingface.co/ggerganov/whisper.cpp` |
| Tamaño | 190.085.487 B (181,28 MiB) |
| SHA-256 | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` |
| Cuantización | `q5_1` |
| Multilingüe | Sí |
| Licencia | MIT (pesos de OpenAI Whisper); conversión ggml por whisper.cpp (MIT) |
| Se versiona | No: lo baja `tool/fetch_whisper_models.sh` y verifica el hash |

El SHA-256 coincide con el `X-Linked-ETag` que publica Hugging Face para el objeto, así que la
verificación no depende de haber descargado bien una sola vez.

Se reutiliza **el mismo commit de `whisper.cpp`** que la Fase 0
(`52a939a2a762224e255d366c1182b2af4dd1a032`). Cambiarlo habría hecho que `base` y `small` no
fueran comparables entre sí ni con lo ya medido.

## Impacto real en el APK

Medido, no estimado: los tres APK salen del mismo código y sólo cambia el motor.

| APK | Tamaño | Diferencia contra el de Android |
|---|--:|--:|
| `voice-benchmark-android-arm64.apk` | 17.394.904 B | — (línea base) |
| `voice-benchmark-whisper-tiny-arm64.apk` | 58.458.420 B | **+41.063.516 B (+39,2 MiB)** |
| `voice-benchmark-whisper-base-arm64.apk` | 86.013.372 B | **+68.618.468 B (+65,4 MiB)** |

Ese sobrecosto es el que tendría que aceptar la distribución de Agrocuentas si
`ADR-002` eligiera Whisper con el modelo empaquetado. Hoy el APK de producción
pesa 64.027.725 B.

## Dependencias de pub

Ninguna añadida. El banco usa sólo `flutter`, `flutter_test` y `flutter_lints`,
igual que el proyecto. No hay wrapper de Flutter para voz en juego, de modo que
no hay repositorio de terceros que auditar por actividad, issues o abandono: el
puente es código propio de este repositorio, y ese es el escape hatch.
