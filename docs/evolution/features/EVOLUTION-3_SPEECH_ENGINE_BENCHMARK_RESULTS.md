# EVOLUTION-3 — Resultados del benchmark de motores de voz

## Estado

`MEASURED_ON_ONE_DEVICE` — `WAITING_FOR_OWNER_DECISION`

El propietario ejecutó el corpus de ajuste completo con los tres motores en un
teléfono real (POCO X5 Pro 5G, Android 12 / API 31) el 2026-09-06. Hay
exactitud, latencia, memoria y comportamiento offline medidos.

**El gate del Pixel 8 / API 36 sigue pendiente**, así que todo lo de aquí
describe un aparato de gama media con Android 12, no el universo de teléfonos.

`ADR-002` permanece `Proposed`: hay recomendación técnica, falta la decisión del
propietario.

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

## Resultados en teléfono real

### Dispositivo

| Campo | Valor |
|---|---|
| Marca y modelo | Xiaomi **POCO X5 Pro 5G** (`22101320G`, `redwood`) |
| SoC | Qualcomm **SM7325** (Snapdragon 7 Gen 1), 8 núcleos |
| ABI | `arm64-v8a` — físico, no emulado |
| Android | **12**, **API 31**, MIUI V140, parche 2023-03-01 |
| RAM | 7.363.124 kB (≈ 7,0 GiB) |
| Almacenamiento libre | 173 GB de 225 GB |
| Batería / temperatura | 58 % → 100 %, 31,0 °C → 33,0 °C durante toda la sesión |
| Fecha | 2026-09-06, 14:11–16:53 |

El aparato obligó a bajar el `minSdk` del banco de 33 a 31
(`INSTALL_FAILED_OLDER_SDK`). Sólo `checkRecognitionSupport` necesita API 33;
`createOnDeviceSpeechRecognizer` existe desde 31.

### Cómo se verificó el modo avión

El campo `airplaneMode` era una declaración del operador que nadie contrastaba.
La primera tanda «offline» resultó no serlo: el buffer de `logcat`, que abarca
desde las 14:13:55, contiene una sola transición de Wi-Fi —
`WifiController: DisabledState.enter()` a las **15:45:50** — dos minutos después
de exportar. Esas 43 tomas se descartaron como prueba offline.

Desde entonces el banco lee `Settings.Global.AIRPLANE_MODE_ON` y guarda
`systemAirplaneMode` junto a lo declarado. **Todas las tandas offline citadas
abajo tienen `airplaneMode = systemAirplaneMode = true`**, y el log confirma
cero transiciones de radio durante la sesión. El propietario comprobó además que
el navegador no cargaba ninguna búsqueda.

### Comparación — corpus de ajuste, los tres en modo avión verificado

| Métrica | **Android** | **Whisper tiny** | **Whisper base** |
|---|--:|--:|--:|
| Tomas | 45 | 44 | 43 |
| Con resultado | 42 | 40 | 42 |
| Exactitud literal | **26,2 %** | 12,5 % | 7,1 % |
| WER mediana | **0,167** | 0,385 | 0,300 |
| Datos críticos (agregador) | **64,4 %** | 31,3 % | 41,7 % |
| Datos críticos (por categoría) | **81,1 %** | 57,6 % | 66,3 % |
| Primer parcial p50 / p95 | **1741 / 2378 ms** | no existe | no existe |
| Final tras detener p50 / p95 | **17 / 46 ms** | 1228 / 9724 ms | 2944 / 3209 ms |
| Memoria pico | **158,2 MiB** | 275,8 MiB | 328,2 MiB |
| Peso añadido al APK | **0 B** | +41.063.516 B | +68.618.468 B |

Las dos filas de «datos críticos» miden lo mismo con reglas distintas: la del
agregador cuenta cada palabra crítica del corpus; la segunda agrupa por tipo de
dato. El orden entre motores es el mismo con ambas.

### Dónde se rompe cada motor

| Dato | Android | tiny | base |
|---|--:|--:|--:|
| Cantidades | **17/17** | 12/16 | 16/17 |
| Precio unitario | **8/8** | 6/8 | 6/8 |
| Precio total | **1/1** | 0/1 | 0/1 |
| Montos de pago | **6/7** | 2/7 | 5/7 |
| **Productos** | **5/17** | 3/16 | 3/17 |
| Personas | **4/7** | 3/7 | 4/7 |
| Unidades | 17/17 | 16/16 | 17/17 |
| Moneda | **13/15** | 6/15 | 7/15 |
| Chaco | **5/5** | 4/5 | **5/5** |

**Ningún motor reconoce los nombres de producto.** Paraquat, Mancozeb,
Lambdacialotrina, Germi-100 y Expansive fallan en los tres. Eso no lo arregla el
motor: lo arregla un diccionario contra los productos de la base local, que es
trabajo de `EVO-010`.

Errores numéricos de Whisper que Android no cometió:

| Frase | Dicho | tiny | base |
|---|---|---|---|
| `AJ-014` | dos mil setecientos | **2017, 100** | **17,200** |
| `AJ-003` | doscientos kilos | 200 kilos | **«Con preo, cientos kilos»** |
| `AJ-026` | José Luis · dos mil | **«Juan Luis de 2011»** | José Luis · 2000 |
| `AJ-039` | 20 litros · 48 · 80 | — | **«3.20 lítulos … 488»** |

«bolivianos» sale sistemáticamente de Whisper como *volvianos*, *volviendo* u
*olivinas*.

### Silencio: la diferencia que decide

| Motor | Audio | Resultado |
|---|--:|---|
| **Android** | 8737 ms · 8686 ms · 8686 ms (3 tomas) | `noMatch` (error 7), **ninguna palabra** |
| **Whisper tiny** | 3052 ms | **`[MÚSICA]`**, sin error |
| Whisper base | — | `NOT_MEASURED` |

Whisper devuelve texto inventado y lo marca como resultado válido. En un flujo
de voz que precarga un borrador, eso es exactamente el material de una falsa
aceptación. Android, ante la misma entrada, no afirma nada.

El silencio de Whisper base no se probó; se registra como `NOT_MEASURED` y no se
infiere del comportamiento de `tiny`.

### El idioma: `es-BO` no existe

| Locale | Respuesta de Android |
|---|---|
| `es-BO` | error **12** `LANGUAGE_NOT_SUPPORTED` — no existe para el reconocedor |
| `es-ES` | error **13** `LANGUAGE_UNAVAILABLE` — existe, no instalado en este aparato |
| `es-US` | **funciona** — es el único paquete presente |

La distinción entre 12 y 13 importa: `es-BO` no funcionará en ningún teléfono;
`es-ES` funcionaría si el usuario descarga el paquete. La aplicación tendrá que
usar el idioma que haya instalado y **no puede prometer español boliviano**.

### La API de disponibilidad miente en este aparato

`SpeechRecognizer.isOnDeviceRecognitionAvailable()` devuelve **`false`**, y sin
embargo las 45 tomas offline se transcribieron. El `logcat` muestra por qué:

```
SodaSpeechRecognizer: Audio process finished, transcription completed.
soda_async_impl.cc: SODA stopped processing audio, mics audio processed in millis: 5180
```

**SODA** es el reconocedor local de Google. Corrió íntegro en el teléfono, sin
red. Conclusión de diseño: `EVO-009` **no puede** usar esa API para decidir si
hay modo offline; hay que intentar la transcripción y observar el resultado.

Por debajo de API 33 tampoco se puede consultar qué idiomas hay instalados. El
banco lo informa como `localeSupportKnown = false` y la interfaz muestra
«SIN VERIFICAR» en vez de prometer o negar el modo offline.

### Repetibilidad

Las mismas 40 frases se dictaron dos veces con red. **Sólo el 33,3 % de las
transcripciones fue idéntica** (13 de 39). Los nombres de producto cambian entre
tomas —Paraquat dio *Paraguay* y *paraqua*; Mancozeb dio *mongosep* y
*mancosep*— y, más grave, `AJ-020` («no fueron **doce**») devolvió `12` en una
toma y `dos` en otra. Una cantidad que cambia entre tomas del mismo hablante no
se corrige con diccionarios: no hay forma de saber cuál lectura es la buena.

## Métricas todavía sin medir

| Métrica | Estado | Por qué |
|---|---|---|
| CPU por motor | `NOT_MEASURED` | No se instrumentó; MIUI bloquea la inyección de eventos y el muestreo quedó fuera del alcance de la sesión |
| Batería atribuida al motor | `NOT_MEASURED` | El teléfono estuvo cargando toda la sesión (58 % → 100 %) |
| Temperatura bajo carga sostenida | `NOT_MEASURED` | Se mantuvo en 33,0 °C, pero sin sesión larga dedicada |
| Silencio en Whisper base | `NOT_MEASURED` | No se ejecutó |
| Corpus de **aceptación** | `NOT_MEASURED` | Reservado; sólo se usó el de ajuste |
| Lifecycle e interrupciones en dispositivo | `NOT_MEASURED` | Cubierto por tests contra el fake; falta el teléfono |
| Pixel 8 / API 36 | `NOT_MEASURED` | Gate pendiente |
| Exactitud de intención | `NOT_MEASURED` | Es propiedad de `EVO-010`, que no existe |
| Draft completo | `NOT_MEASURED` | Ídem |
| **Falsa aceptación** | `NOT_MEASURED` | Se define sobre un borrador marcado "listo"; sin `EVO-010` no existe ese estado y medirla sobre texto crudo daría un número falso |

Las tres últimas no son un olvido: son ajenas a esta fase. La Fase 0 decide el
**transcriptor**; la falsa aceptación se decide en el intérprete tipado.

## Limitaciones de esta fase

1. **Un solo teléfono.** Gama media, Android 12, MIUI. El gate del Pixel 8 /
   API 36 sigue abierto, y con él la posibilidad de que Android 16 se comporte
   distinto — en particular, que `es-ES` sí esté instalado.
2. **Un solo hablante**, en interior y sin ruido de campo. El corpus tiene
   categoría `ruido_de_campo`, pero las condiciones acústicas no se variaron.
3. **Sólo el corpus de ajuste.** El de aceptación sigue intacto, que es
   justamente su función: no se afinó nada contra él.
4. **No hay corpus de audio grabado.** No existen grabaciones autorizadas y no se
   generó audio sintético para reemplazarlas: un TTS leyendo frases perfectas
   infla la exactitud y no dice nada sobre acentos reales.
5. **La primera tanda «offline» estaba mal etiquetada** y se descartó. Se
   conserva como evidencia de repetibilidad con red, no como prueba offline.

## Comparación de fondo

| Criterio | Candidato A (Android) | Candidato B (whisper.cpp) |
|---|---|---|
| Exactitud en datos críticos | **81,1 %** | 57,6 % (tiny) · 66,3 % (base) |
| Afirma texto sobre silencio | **No** (`noMatch`) | **Sí** (`[MÚSICA]`) |
| Funciona sin red | **Sí**, vía SODA | **Sí**, modelo en el APK |
| Peso agregado al APK | **0 B** | +39,2 MiB · +65,4 MiB |
| Memoria pico | **158 MiB** | 276 MiB · 328 MiB |
| Resultados parciales | **Sí**, ~1,7 s | **No** |
| Latencia tras detener | **17 ms** | 1,2 s · 2,9 s |
| Necesita paquete de idioma previo | **Sí** | No |
| `es-BO` | **No existe** | Recibe `es` como pista |
| Depende de Google | **Sí** (SODA / Servicios de voz) | **No** |
| Dependencias de terceros | ninguna | whisper.cpp (MIT) + modelo (MIT) |
| Mantenimiento | Lo mantiene Google con el sistema | Commit fijado; actualizar es decisión explícita |

## Recomendación

**Candidato A — el reconocimiento de Android — como motor primario**, por tres
razones en este orden:

1. **No inventa.** Es el criterio que la aplicación no puede negociar: un motor
   que produce `[MÚSICA]` sobre silencio puede producir un producto o un monto
   sobre ruido, y el usuario lo vería como dato propuesto.
2. **Acierta más donde importa**: 81,1 % contra 57,6 % / 66,3 % en datos
   críticos, con cantidades y precios perfectos en las 25 comprobaciones.
3. **No cuesta nada en distribución**: 0 bytes de APK y la mitad de memoria.

Whisper **no debe descartarse**: es el único que no depende de Google y el único
que garantiza offline sin paquete previo. Queda como reserva documentada para el
caso de un teléfono sin Servicios de Google, y `SpeechTranscriptionPort` permite
sustituirlo sin tocar el resto.

**Ninguno de los dos alcanza el listón de `EVO-009` por sí solo.** Con 5 de 17
productos correctos, la transcripción cruda no puede precargar un borrador de
compra. La conclusión operativa no es «elegir motor y seguir», es:

- el motor entrega **texto**, no datos;
- el reconocimiento de productos y personas se resuelve contra la base local en
  `EVO-010`, no en el motor;
- la frontera de confirmación de `ADR-003` deja de ser una precaución y pasa a
  ser el mecanismo que sostiene la corrección del flujo.

### Condiciones que deben acompañar a la elección

1. La app **no puede prometer `es-BO`**. Debe detectar el idioma disponible,
   usarlo y **mostrarlo** al usuario (`EVO-009-REQ-008`).
2. **No usar `isOnDeviceRecognitionAvailable()`** como garantía de offline:
   devuelve `false` en un aparato donde el modo offline funciona.
3. Si no hay ningún paquete de idioma instalado, el dictado **no está
   disponible**, y así debe decirse — nunca «funciona sin Internet».
4. Ningún dato crítico puede confirmarse sin revisión del usuario.

## Evidencia de dispositivo

| Dispositivo | Estado |
|---|---|
| Emulador API 36 x86_64 | Ejecutado. Candidato A no funcional; Candidato B carga y responde |
| **POCO X5 Pro 5G / Android 12 / API 31** | **EJECUTADO** — corpus de ajuste completo, tres motores, modo avión verificado |
| **Pixel 8 / Android 16 / API 36** | **GATE PENDIENTE** |

Archivos exportados por el teléfono, en `artifacts/voice-benchmark/results/`:

| Carpeta | Contenido |
|---|---|
| `android/` | 45 tomas offline, modo avión verificado |
| `android-con-red/` | 58 tomas con red, incluye los rechazos de `es-BO` y `es-ES` |
| `whisper-tiny/` | 43 tomas offline y la prueba de silencio |
| `whisper-base/` | 43 tomas offline |
| `etiqueta-incorrecta/` | 43 tomas declaradas offline que no lo eran |

### APK preparados

Compilados en release (firmados con la clave de depuración: instalables, no
publicables), `arm64-v8a`, `minSdk 31`.

| APK | Bytes | SHA-256 |
|---|--:|---|
| `voice-benchmark-android-arm64.apk` | 17.476.824 | `d104ded9a6390d119a8338ea2e14f4d7b8a902496777e476401668389fcd9fc5` |
| `voice-benchmark-whisper-tiny-arm64.apk` | 58.523.956 | `1ad0650c767f6720ac751999f483d95efb61cfb441d3e9f9d041421498ec7d02` |
| `voice-benchmark-whisper-base-arm64.apk` | 86.078.912 | `b6392d58cbd7bdde7cd71584f1a478d057bec92eef8e360f1d7faf5667bac28f` |

Ninguno requiere credenciales, servicio remoto ni cuenta. Ninguno declara el
permiso `INTERNET`; verificado en el aparato con `dumpsys package`: los tres
declaran únicamente `RECORD_AUDIO`.

## Riesgos

| ID | Cómo queda |
|---|---|
| `RISK-010` voz interpreta mal | **Abierto y agravado.** 5/17 productos correctos en el mejor motor, y una cantidad que cambió entre tomas del mismo audio |
| `RISK-013` dependencia abandonada | Mitigado: sin wrapper de terceros; puente propio y commit fijado |
| `RISK-016` motor local degrada memoria/batería/latencia | **Parcialmente cerrado.** Memoria y latencia medidas; CPU y batería siguen `NOT_MEASURED` |
| `RISK-017` audio o transcripción se filtra | Mitigado: sin `INTERNET`, sin audio en disco, sin texto en logs, opción de exportar sin transcripciones |
| `RISK-023` offline no garantizado en Candidato A | **Reformulado.** El modo offline funciona vía SODA, pero depende de un paquete de idioma instalado y `es-BO` no existe |
| `RISK-024` sin parciales en Candidato B | **Confirmado** en teléfono real |
| Nuevo: Whisper afirma texto sobre silencio | `[MÚSICA]` reproducido en hardware real |

## Decisión

`ADR-002` permanece **`Proposed`**.

Hay recomendación técnica con evidencia —Candidato A como primario, Whisper como
reserva— pero la decisión es del propietario y el gate del Pixel 8 sigue
abierto. No se ha descartado ningún candidato ni se ha introducido ningún
servicio remoto.
