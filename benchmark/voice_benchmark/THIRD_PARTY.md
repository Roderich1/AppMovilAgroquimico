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
