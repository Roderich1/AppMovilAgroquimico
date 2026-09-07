# Banco de pruebas de motores de voz — EVOLUTION-3, Fases 0 y 0-bis

> **Esto no es Agrocuentas.** Es un spike descartable cuyo único objetivo es
> medir motores de transcripción sobre teléfonos reales para resolver `ADR-002`.
> Se borra eliminando `benchmark/` y las cuatro líneas que lo mencionan en
> `analysis_options.yaml` y `.gitignore` de la raíz.

## Qué garantiza el aislamiento

| Frontera | Cómo se garantiza |
|---|---|
| No toca el negocio | No importa `package:agroquimicos`; hay un test que falla si alguien lo hace |
| No abre SQLite | No declara `sqflite` ni ninguna dependencia de base; test de `pubspec` |
| No sale de la app | El manifiesto **no** declara `INTERNET`; verificable en el APK instalado |
| No se mezcla con el producto | `applicationId` propio por sabor; se instala al lado de Agrocuentas |
| No entra en CI | El workflow de la raíz sólo construye la aplicación |
| No infla el APK | El APK de producción sigue pesando lo mismo, byte por byte |

El único permiso que pide es `RECORD_AUDIO`.

## Arquitectura

```text
BenchScreen                       (interfaz de medición)
    ↓
BenchController                   (corpus, tiempos, exportación)
    ↓
SpeechTranscriptionPort           ← el contrato que heredará EVO-009
    ↓
PlatformSpeechTranscriptionPort   (MethodChannel + EventChannel)
    ↓
TranscriptionEngine               (Kotlin; una implementación por sabor)
    ├── AndroidSpeechEngine       → android.speech.SpeechRecognizer
    └── WhisperEngine             → AudioRecord + whisper.cpp por JNI
```

`BaseSpeechTranscriptionPort` concentra el ciclo de vida (doble inicio, timeout,
cancelación, `dispose`, liberación del micrófono) para que **se pruebe una sola
vez** y valga igual para los dos motores y para el fake.

El puerto transporta texto y estados. El audio nunca cruza el canal, no se
escribe a disco y no aparece en el log.

## Los sabores

| Sabor | `applicationId` | Motor | Modelo |
|---|---|---|---|
| `androidSpeech` | `…voicebench.android` | `SpeechRecognizer` del sistema | — |
| `whisperTiny` | `…voicebench.whispertiny` | whisper.cpp | `ggml-tiny-q5_1.bin` |
| `whisperBase` | `…voicebench.whisperbase` | whisper.cpp | `ggml-base-q5_1.bin` |
| `whisperSmall` | `…voicebench.whispersmall` | whisper.cpp | `ggml-small-q5_1.bin` |
| `vosk` | `…voicebench.vosk` | Vosk Android | `vosk-model-small-es-0.42` |
| `hybrid` | `…voicebench.hybrid` | Vosk + whisper.cpp | los dos anteriores |

Se eligieron **sabores** y no proyectos separados porque la interfaz, el
corpus y el puerto son idénticos: con proyectos distintos nada impediría que las
mediciones se hicieran contra código que fue divergiendo. Cada sabor compila sólo
su motor, así que el APK de Android no contiene una línea de Whisper y viceversa.
Los `applicationId` distintos permiten tenerlos todos instalados a la vez.

## Preparar y compilar

```bash
# 1. Librerías nativas de whisper.cpp (commit fijo, ver el script)
bash tool/build_whisper_libs.sh arm64-v8a

# 2. Modelos, con verificación de SHA-256
bash tool/fetch_whisper_models.sh

# 2b. Modelo español de Vosk, con verificación de SHA-256 y de tamaño extraído
bash tool/fetch_vosk_model.sh

# 3. Los APK. `BENCH_COMMIT` queda registrado en cada resultado exportado:
#    sin él la casilla sale vacía, que es mejor que un commit inventado.
flutter build apk --release --flavor vosk --target-platform android-arm64 \
  --dart-define=BENCH_COMMIT=$(git rev-parse --short HEAD)
```

Librerías y modelos **no se versionan**: son binarios regenerables de decenas de
MB. Los scripts fijan el commit de whisper.cpp y el hash de cada modelo, de modo
que dos personas obtienen exactamente lo mismo.

### Por qué `--release` y no `--debug`

Un APK de depuración pesa 184–253 MB y, sobre todo, corre Dart sin compilar: las
latencias medidas serían las del intérprete, no las del motor. Para un banco de
pruebas eso invalidaría el resultado. Los APK van firmados con la clave de
depuración —son instalables, no publicables— y ese es el único sentido en que
son "de prueba".

### Por qué `--target-platform` importa

Las ABIs que empaqueta Gradle se derivan de ese argumento. Si el APK llevara las
librerías de Whisper para x86_64 mientras el motor de Flutter se compiló sólo
para arm64, Android elegiría x86_64 por las librerías nativas y después no
encontraría `libflutter.so`. Ese defecto apareció de verdad durante la
construcción y por eso el filtro se deriva automáticamente en
`android/app/build.gradle.kts`.

## Gates propios

```bash
flutter analyze
flutter test
```

No los cubre la CI de la raíz: este paquete está excluido a propósito del
análisis del proyecto porque tiene su propio `pubspec.yaml`.

## Corpus

Hay dos corpus versionados y **separados**. El banco arranca sin ninguno: quien
opera elige uno en la pantalla, se verifica su SHA-256 y sólo entonces se puede
grabar.

| Corpus | Archivo | Versión | SHA-256 | Frases |
|---|---|---|---|--:|
| Fase 0 histórica | `assets/corpus.json` | `1.0.0` | `7a891fd1…83f6b6b` | 100 |
| Híbrido A–G | `assets/corpus_hybrid.json` | `hybrid-1.0.0` | `52822895…efb00bd0` | 54 |

Los dos son **texto**; no contienen ni referencian grabaciones de personas
reales, y personas, proveedores y chacos son ficticios. Las frases llevan
ortografía española real porque se leen en voz alta.

El de la Fase 0 se conserva intacto para poder repetir lo medido en el POCO. No
sirve para el benchmark híbrido: se escribió antes de que existieran las
categorías A–G y no tiene muestras sin habla. **C1, C3 y C4 sólo son
comparables entre sí sobre el corpus A–G.**

### Particiones

Tres, y son disjuntas: `ajuste`, `aceptación` y `técnicas / sin habla`. La
tercera reúne las muestras sin habla de los dos conjuntos y se dicta como tanda
aparte; sus resultados no entran en la misma tabla que las frases habladas. La
Fase 0 no tiene esa partición y la pantalla lo dice en vez de ofrecer una tanda
vacía.

### Por qué el digest importa

El SHA-256 se calcula sobre los bytes que la aplicación acaba de leer, se
muestra antes de grabar y viaja en cada resultado exportado. Es el mismo que
devuelve `sha256sum` sobre el archivo del repositorio, así que se puede
comprobar desde fuera sin creerle nada al teléfono.

El `.gitattributes` de la raíz marca estos assets `-text` para que Git no
convierta los fines de línea al obtenerlos: sin eso, el mismo commit daría bytes
distintos en Windows y en Linux y el digest identificaría la máquina en vez del
contenido.

Si el archivo falta, está vacío, no se puede leer o su digest no coincide, **se
bloquea la ejecución** con un diagnóstico. No se sustituye por otro corpus ni se
conserva el anterior: quedarse con el previo es exactamente cómo se mediría la
Fase 0 con el rótulo de A–G puesto.

### Guardas

`test/corpus_selector_test.dart` y `test/hybrid_corpus_test.dart` fallan si
alguien recorta un corpus, mezcla ajuste con aceptación, repite un
identificador, repite una frase en las mismas condiciones o cambia los bytes de
un corpus ya medido. Una frase puede repetirse dentro de un conjunto **si se
dicta bajo condiciones distintas**: `AC-046` en silencio y `AC-055` con ruido
son la misma frase medida en dos entornos, y compararlas es el objetivo.

## Candidatos

`lib/bench/candidates.dart` asocia cada sabor con su candidato del plan. El
candidato se resuelve desde `BuildConfig.ENGINE_ID`, que es **observado**: si se
instala el APK equivocado, el banco lo ve. Un motor que no esté en la tabla no
se aproxima al más parecido: bloquea la grabación, porque una medición que no se
puede nombrar no se puede colocar en ninguna columna.

| Candidato | Sabor | Parciales | Final |
|---|---|---|---|
| C0 | `androidSpeech` | Android | Android |
| C1 | `vosk` | Vosk small es 0.42 | Vosk small es 0.42 |
| C2 | `whisperBase` | ninguno | Whisper base q5_1 |
| C3 | `whisperSmall` | ninguno | Whisper small q5_1 |
| C4 | `hybrid` | Vosk small es 0.42 | Whisper small q5_1 |

## Qué se hace con los resultados

El teléfono exporta JSON o CSV a su carpeta de archivos. Desde la raíz del
repositorio:

```bash
dart run tool/voice_benchmark/main.dart <carpeta con los exportados> -o informe.md
```

El agregador nunca rellena un hueco: lo que nadie midió sale como
`NOT_MEASURED`.

Y **se niega a generar el informe** si lo que se le pasa no es comparable entre
sí: dos corpus, dos versiones, dos digests, dos particiones, dos locales
solicitados, dos modelos bajo el mismo candidato o un candidato mal etiquetado.
Sale con código 65 y enumera los conflictos. Poner dos corpus en la misma tabla
presentaría como diferencia entre motores lo que es diferencia entre exámenes.
