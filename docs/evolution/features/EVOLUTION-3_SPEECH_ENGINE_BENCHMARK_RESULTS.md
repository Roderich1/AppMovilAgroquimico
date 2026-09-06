# EVOLUTION-3 — Resultados del benchmark de motores de voz

## Estado

`WAITING_FOR_OWNER_DEVICE_TESTS`

La Fase 0 dejó construido y verificado el banco de pruebas, el corpus y las
herramientas de análisis. **Falta la parte que sólo puede hacerse con teléfonos
reales**, que ejecutará el propietario siguiendo
`EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md`.

`ADR-002` permanece `Proposed`. No hay ganador, no hay candidato descartado y no
se recomienda ningún motor todavía.

## Identidad

| Elemento | Valor |
|---|---|
| SHA base | `0189faa17dbe78672881d3ec86614667bacbe907` |
| Rama | `evolution/evolution-3-voice-benchmark` |
| Diferencia con `00_EVOLUTION_INDEX` | El índice analizó `2fd0ccb`; `main` avanzó a `0189faa`, que es el merge del PR #6 con la documentación de EVOLUTION-3. Sólo documentación entre ambos |
| Corpus | versión `1.0.0`, 100 muestras |
| whisper.cpp | commit `52a939a2a762224e255d366c1182b2af4dd1a032` |

## Entorno

| Elemento | Valor |
|---|---|
| Flutter / Dart | `3.47.2` / `3.13.2` |
| Java local | Temurin `21.0.10` (CI usa `17`) |
| Gradle / AGP / Kotlin | `9.3.1` / `9.1.0` / `2.4.0` |
| NDK / CMake | `28.2.13676358` / `3.22.1` |
| compileSdk / minSdk / targetSdk | `36` / `24` / `36` (banco: `minSdk 33`) |
| Sistema | Windows 11 |

## Baseline antes de tocar nada

Todos los gates verdes sobre `0189faa`, antes de cualquier cambio.

| Gate | Resultado | Tiempo |
|---|---|--:|
| `flutter pub get` | correcto | 2 s |
| `dart format --set-exit-if-changed lib test` | 0 cambios sobre 86 archivos | 1 s |
| `flutter analyze` | 0 issues | 57 s |
| `flutter test` | **460/460** | 60 s |
| `flutter build apk --release` | **61,1 MB** (64.027.725 B) | 23 s |
| Árbol de trabajo | limpio | — |

Precondiciones comprobadas: EVOLUTION-2 en `VERIFIED`,
`EVOLUTION-2_FINAL_VERIFICATION.md` presente, `ADR-002` en `Proposed`, `ADR-003`
en `Accepted`, `EVO-009/010/017/018/019` en `APPROVED`, `EVO-020` en `DEFERRED`,
y ninguna implementación de voz previa en `lib/` ni en `pubspec.yaml`.

## Candidatos

### Candidato A — reconocimiento de Android

`android.speech.SpeechRecognizer`, con `createOnDeviceSpeechRecognizer` cuando el
aparato lo ofrece. Sin dependencias de pub, sin modelo propio.

### Candidato B — `whisper.cpp`

Compilado desde fuente en el commit fijado, con modelos multilingües cuantizados
`tiny` y `base` (`q5_1`), a través de un puente JNI propio.

**No se usó ningún wrapper de Flutter de terceros.** No hizo falta: el puente son
~130 líneas de C y ~40 de Kotlin en este repositorio. Eso evita depender de un
paquete que podría quedar abandonado (`RISK-013`) y hace que el escape hatch sea
borrar una carpeta. El detalle de licencias, versiones y hashes está en
`benchmark/voice_benchmark/THIRD_PARTY.md`.

## Metodología

1. Un puerto único, `SpeechTranscriptionPort`, con dos adaptadores nativos y un
   fake determinista. El ciclo de vida vive en una clase base compartida, así que
   doble inicio, timeout, cancelación y liberación del micrófono se comportan
   igual en los tres.
2. Tres APK, uno por motor, con `applicationId` distinto para poder tenerlos
   instalados a la vez. Cada uno compila **sólo** su motor.
3. El mismo corpus y el mismo protocolo para todos.
4. Medición dentro de la aplicación, exportable a JSON/CSV.
5. Agregación en el repositorio con `tool/voice_benchmark/`, que nunca rellena un
   hueco.

### Qué mide el banco

| Métrica | Cómo |
|---|---|
| Exactitud de transcripción | Coincidencia exacta y WER, con números normalizados |
| Datos críticos | Si producto, cantidad, unidad, precio y moneda sobrevivieron |
| Latencia parcial | Desde `start()` hasta el primer texto parcial |
| Latencia final | **Desde que terminó el habla** hasta el resultado final |
| Duración del audio | Desde `start()` hasta que terminó el habla |
| Memoria | PSS total del proceso |
| Disponibilidad y locale | Lo que declara el motor, incluido el locale realmente usado |
| Modo avión | Marcado por quien ejecuta, en cada resultado |
| Errores | Código del puerto más el código nativo |

La latencia final se mide desde el fin del habla y no desde el inicio de la
sesión. Medirla desde el inicio daría el largo de la frase, no el trabajo del
motor; el plan de benchmark pide justamente "tras detener el habla". Este defecto
existió en la primera versión del banco y se corrigió tras verlo en el emulador:
latencia final `7012 ms` contra duración de audio `7013 ms`, que era el mismo
número dos veces.

## Corpus

100 muestras, en `benchmark/voice_benchmark/assets/corpus.json`.

| Reparto | Cantidad |
|---|--:|
| Ajuste | 40 |
| Aceptación | 60 |
| Compra | 49 |
| Aplicación de planificación | 20 |
| Pago | 20 |
| Fuera de alcance | 7 |
| Dos intenciones mezcladas | 4 |

Por resultado esperado: 61 `listo`, 14 `incompleto`, 14 `ambiguo`, 11
`rechazado`. Cubre 49 categorías, entre ellas los alias `germi cien` y `germi uno
cero cero`, `expansive`/`expansiv`, litros y kilos, precio unitario frente a
precio total, bolivianos y dólares, tipo de cambio, proveedor, propietario,
fechas, decimales, unidades incompatibles, homónimos, nombres parecidos, pausas,
autocorrecciones, habla rápida y ruido de campo.

Ninguna frase de aceptación aparece en ajuste; hay un test que lo comprueba y que
ya detectó una repetición durante la redacción.

### Privacidad del corpus

El corpus es **texto**. No contiene ni referencia grabaciones de personas reales.
Personas, proveedores y chacos son ficticios. No se guarda audio en ningún
momento, ni durante la prueba: el banco lo mantiene en memoria y lo descarta al
terminar la frase.

Las frases llevan ortografía española real —tildes y eñes— porque se leen en voz
alta y "campana" no es "campaña".

## Resultados medidos

### 1. Tamaño de las librerías nativas (arm64-v8a, sin símbolos)

| Librería | Bytes |
|---|--:|
| `libwhisper_bench.so` | 1.047.328 |
| `libggml-base.so` | 1.157.608 |
| `libggml-cpu.so` | 873.760 |
| `libggml.so` | 123.344 |
| **Total** | **3.202.040** |

`armeabi-v7a`: 2.223.084 B. `x86_64`: 3.365.632 B. Ninguna depende de
`libc++_shared.so` ni de `libomp.so`.

### 2. Modelos

| Modelo | Bytes | SHA-256 |
|---|--:|---|
| `ggml-tiny-q5_1.bin` | 32.152.673 | `81871056…69c3d7` |
| `ggml-base-q5_1.bin` | 59.707.625 | `422f1ae4…1a8898` |

### 3. Impacto real en el APK

Medido sobre los tres APK, que sólo difieren en el motor.

| APK | Bytes | Contra el de Android |
|---|--:|--:|
| Android | 17.394.904 | — |
| Whisper tiny | 58.458.420 | **+41.063.516 (+39,2 MiB)** |
| Whisper base | 86.013.372 | **+68.618.468 (+65,4 MiB)** |

Referencia: el APK de producción de Agrocuentas pesa 64.027.725 B, y **no cambió
ni un byte** al incorporar este trabajo.

### 4. Candidato A en el emulador — reconocimiento NO funcional

Medido con un spike descartable y reproducido después con el propio APK del
banco.

**Entorno, y sólo ese entorno:** `sdk_gphone16k_x86_64`, Android 16 / API 36,
x86_64, 4 núcleos, 2,5 GB RAM, imagen con Google Play, Android System
Intelligence `B.0.playstore.pixel6.738427685`, Google TTS
`googletts.google-speech-apk_20250804.02_p3.800153222`.

| Observación | Resultado |
|---|---|
| `isRecognitionAvailable` | `true` |
| `isOnDeviceRecognitionAvailable` | `true` |
| Servicios de reconocimiento | `com.google.android.as/…AiAiSpeechRecognitionService` y `com.google.android.tts/…GoogleTTSRecognitionService` |
| `installedOnDeviceLanguages` | **vacío** |
| `pendingOnDeviceLanguages` | `[en-US]` en el reconocedor por defecto; vacío en el on-device |
| `onlineLanguages` | vacío |
| `triggerModelDownload("es-ES")` | **ningún callback en 85 s**: ni `onScheduled`, ni `onSuccess`, ni `onError` |
| `startListening` | `ERROR_CLIENT (5)` en las 4 combinaciones probadas (on-device y por defecto × `es-ES` y `en-US`) |
| Causa en el log del sistema | `DeadObjectException: Transaction failed on small parcel; remote process probably died` |

**Estos resultados valen para esa imagen de emulador y nada más.** No se
generalizan a teléfonos Android: un Pixel 8 real con los idiomas descargados
puede comportarse de forma completamente distinta. Por eso la prueba de
dispositivo es obligatoria y no opcional.

### 5. Candidato A — dos hallazgos que NO dependen del emulador

Estos salen de la lista que declara el propio stack de reconocimiento de Google,
no de que el emulador funcione o no.

**`es-BO` no existe como idioma on-device.** Los únicos españoles ofrecidos son
`es-ES` y `es-US`. No hay `es-419` ni `es-MX`. `EVO-009` pide preferencia `es-BO`
"con fallback visible": el fallback no es una precaución, es el camino normal, y
la interfaz tiene que decirlo siempre.

Lista completa declarada: `en-US, de-DE, es-ES, fr-FR, it-IT, en-AU, en-GB,
en-IE, en-SG, ja-JP, de-AT, de-BE, de-CH, en-CA, en-IN, es-US, fr-BE, fr-CA,
fr-CH, hi-IN, id-ID, it-CH, ko-KR, pt-BR, th-TH, cmn-Hans-CN, cmn-Hant-TW,
pl-PL, ru-RU, tr-TR, vi-VN`.

**El reconocimiento on-device exige descargar el modelo del idioma.** Que la API
on-device exista no significa que pueda transcribir sin red: hace falta que el
idioma esté instalado. En una instalación nueva no lo está. Eso afecta
directamente la promesa offline-first del producto y es una decisión de producto,
no técnica.

El banco lo refleja: informa "funciona sin Internet" sólo si además hay un idioma
servible instalado, y deja el flag crudo de la API en el detalle.

### 6. Candidato B — el APK funciona, con dos defectos encontrados y corregidos

Verificado instalando el APK de Whisper tiny en el emulador (compilado para
x86_64 sólo para esa comprobación):

- `libwhisper_bench.so` carga correctamente;
- el modelo se copia desde los assets y se abre (32.152.673 B);
- `whisper_full` se ejecuta y devuelve texto;
- la aplicación informa "funciona sin Internet: sí", "necesita red: no";
- avisa del fallback `es-BO` → `es`.

Dos defectos reales aparecieron al hacerlo, no al leer documentación:

1. **`libomp.so` ausente.** Con OpenMP activado, `libggml-base.so` queda enlazada
   contra una librería que el NDK no empaqueta: `dlopen failed: library
   "libomp.so" not found`. Corregido compilando con `GGML_OPENMP=OFF`.
2. **ABI cruzada.** Empaquetar Whisper para tres ABIs mientras Flutter se compila
   para una sola hace que Android elija la ABI equivocada y no encuentre
   `libflutter.so`. Corregido derivando el filtro de ABI del `--target-platform`
   de Flutter, de modo que la combinación inválida ya no puede construirse.

### 7. Candidato B — diferencia de fondo con el Candidato A

**Whisper no produce resultados parciales.** Transcribe una grabación completa;
no es un flujo. En esta integración se graba hasta `Detener` y recién entonces se
transcribe.

No es una limitación del banco: es cómo funciona el motor. Y tiene consecuencia
de producto directa, porque `EVOLUTION-3_VOICE_VISION_AND_SCOPE.md` describe una
experiencia donde la app "transcribe mientras escucha" y el plan de benchmark
fija como meta "actualización del draft en menos de 200 ms después de recibir
texto parcial". Con Whisper así integrado, esa meta no aplica: no hay parciales
que medir.

Alternativas, si `ADR-002` se inclinara por Whisper: aceptar una experiencia sin
texto en vivo, o implementar transcripción por trozos —que cuesta CPU y batería,
y habría que medir aparte—.

### 8. Riesgo observado: Whisper inventa texto sobre silencio

Al ejercitar el APK sin voz real, `whisper.cpp` devolvió `[Música]` en lugar de
un resultado vacío. Es un comportamiento conocido de Whisper: ante audio sin
habla produce tokens espurios.

Importa para `EVOLUTION-3` porque la política exige **cero falsa aceptación de
datos críticos**. Un motor que inventa texto sobre ruido no puede tratarse como
fuente confiable: refuerza que la frontera tipada de `ADR-003` es obligatoria y
que ningún borrador puede marcarse "listo" por el solo hecho de haber recibido
texto. Debe medirse explícitamente en el teléfono: grabar sin hablar y anotar qué
devuelve cada motor.

## Métricas todavía sin medir

| Métrica | Estado | Por qué |
|---|---|---|
| Exactitud de transcripción | `NOT_MEASURED` | Necesita voz real en un teléfono |
| Exactitud de datos críticos | `NOT_MEASURED` | Ídem |
| Latencia parcial p50/p95 | `NOT_MEASURED` | Ídem; en Whisper además no existe |
| Latencia final p50/p95 | `NOT_MEASURED` | Ídem |
| Memoria pico | `NOT_MEASURED` | El banco la exporta; falta ejecutarlo |
| CPU | `NOT_MEASURED` | Requiere el teléfono |
| Batería y temperatura | `NOT_MEASURED` | Requiere sesión sostenida real |
| Modo avión | `NOT_MEASURED` | El emulador no llega a transcribir |
| Lifecycle e interrupciones | `NOT_MEASURED` en dispositivo | Cubierto por tests contra el fake; falta el teléfono |
| Exactitud de intención | `NOT_MEASURED` | Es propiedad de `EVO-010`, que no existe |
| Draft completo | `NOT_MEASURED` | Ídem |
| **Falsa aceptación** | `NOT_MEASURED` | Se define sobre un borrador marcado "listo"; sin `EVO-010` no existe ese estado y medirla sobre texto crudo daría un número falso |

Estas tres últimas no son un olvido de la Fase 0: son deliberadamente ajenas a
ella. La Fase 0 decide el **transcriptor**; la falsa aceptación se decide en el
intérprete tipado.

## Limitaciones de esta fase

1. **No hubo ningún teléfono real.** El único aparato disponible fue un emulador
   x86_64. Todo lo medido sobre él vale para ese entorno.
2. **El reconocimiento del emulador está roto** (`DeadObjectException`), así que
   el Candidato A no pudo transcribir ni una frase.
3. **Whisper no pudo medirse en rendimiento.** El emulador es x86_64 sobre un
   procesador de escritorio; cualquier latencia o memoria de ahí sería engañosa
   para un teléfono ARM. Sólo se verificó que el motor carga y responde.
4. **No hay corpus de audio grabado.** No existen grabaciones autorizadas y no se
   generó audio sintético para reemplazarlas: un TTS leyendo frases perfectas
   infla la exactitud y no dice nada sobre ruido de campo ni acentos reales. El
   corpus es texto para leer en voz alta.
5. **Falta el equipo de gama baja**, que es el que decide si Whisper es viable.

## Comparación

Sólo con lo medido. Las columnas de exactitud y rendimiento quedan vacías a
propósito.

| Criterio | Candidato A (Android) | Candidato B (whisper.cpp) |
|---|---|---|
| Peso agregado al APK | **0 B** | +39,2 MiB (tiny) · +65,4 MiB (base) |
| Dependencias de terceros | ninguna | whisper.cpp (MIT) + modelo (MIT), compilado desde fuente |
| Necesita descarga previa | **Sí**, el modelo del idioma | No: el modelo viaja en el APK |
| Funciona sin red recién instalado | **No** (idiomas instalados: 0) | Sí |
| `es-BO` | **No existe**; cae a `es-ES` o `es-US` | Recibe `es` como pista de idioma |
| Resultados parciales | Sí | **No** |
| Reemplazable | Sí, detrás del puerto | Sí, detrás del puerto |
| Mantenimiento | Lo mantiene Google con el sistema | Commit fijado; actualizar es una decisión explícita |
| Exactitud | `NOT_MEASURED` | `NOT_MEASURED` |
| Latencia, memoria, CPU, batería | `NOT_MEASURED` | `NOT_MEASURED` |

## Recomendación

**Ninguna todavía.** Las dos columnas que deciden —exactitud en datos críticos y
comportamiento offline real— están sin medir en ambos candidatos.

Lo que sí puede afirmarse: los dos candidatos son **construibles, aislables y
reemplazables** detrás de `SpeechTranscriptionPort`, y ninguno obliga a un
servicio remoto.

## Evidencia de dispositivo

| Dispositivo | Estado |
|---|---|
| Emulador API 36 x86_64 | Ejecutado. Candidato A no funcional; Candidato B carga y responde |
| **Pixel 8 / Android 16 / API 36** | **GATE PENDIENTE** |
| **Android de gama media/baja** | **GATE PENDIENTE** |

Instrucciones exactas para ejecutarlos:
`EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md`. Plantilla de devolución:
`EVOLUTION-3_OWNER_DEVICE_TEST_RESULTS_TEMPLATE.md`.

### APK preparados

Compilados en release (firmados con la clave de depuración: instalables, no
publicables), `arm64-v8a`. Se entregan por ruta y hash, no por el repositorio.

| APK | Bytes | SHA-256 |
|---|--:|---|
| `voice-benchmark-android-arm64.apk` | 17.394.904 | `cc6542eb94ee49e59aa4e0fe8eaebd92c24a2d0df286ea45883e6e6df1962359` |
| `voice-benchmark-whisper-tiny-arm64.apk` | 58.458.420 | `48d1535f39fd1238ee0261dd6bab4b700c5a0c84c268ac35dfebd5c387322152` |
| `voice-benchmark-whisper-base-arm64.apk` | 86.013.372 | `9cbbcc9b80bdce17c7440715801824fbdcf968fcdc6c0b1fac5caaef61a40486` |

Ninguno requiere credenciales, servicio remoto ni cuenta. Ninguno declara el
permiso `INTERNET`, lo que puede verificarse en el manifiesto del APK instalado.

## Riesgos

| ID | Cómo queda |
|---|---|
| `RISK-010` voz interpreta mal | Abierto. Reforzado: Whisper inventó `[Música]` sobre silencio |
| `RISK-013` dependencia abandonada | Mitigado: sin wrapper de terceros; puente propio y commit fijado |
| `RISK-016` motor local degrada memoria/batería/latencia | **Abierto y sin medir.** Es el riesgo que el gate de dispositivo debe cerrar |
| `RISK-017` audio o transcripción se filtra | Mitigado en el banco: sin `INTERNET`, sin audio en disco, sin texto en logs, y opción de exportar sin transcripciones |
| Nuevo: offline no garantizado en Candidato A | Ver `RISK-023` |
| Nuevo: sin parciales en Candidato B | Ver `RISK-024` |

## Decisión

`ADR-002` permanece **`Proposed`**.

No se declara ganador, no se descarta ningún candidato y no se introduce ningún
servicio remoto. La decisión espera la evidencia de los teléfonos del
propietario.
