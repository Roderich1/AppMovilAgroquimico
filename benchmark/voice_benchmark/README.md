# Banco de pruebas de motores de voz — EVOLUTION-3, Fase 0

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

## Los tres sabores

| Sabor | `applicationId` | Motor | Modelo |
|---|---|---|---|
| `androidSpeech` | `…voicebench.android` | `SpeechRecognizer` del sistema | — |
| `whisperTiny` | `…voicebench.whispertiny` | whisper.cpp | `ggml-tiny-q5_1.bin` |
| `whisperBase` | `…voicebench.whisperbase` | whisper.cpp | `ggml-base-q5_1.bin` |

Se eligieron **sabores** y no tres proyectos separados porque la interfaz, el
corpus y el puerto son idénticos: con proyectos distintos nada impediría que las
mediciones se hicieran contra código que fue divergiendo. Cada sabor compila sólo
su motor, así que el APK de Android no contiene una línea de Whisper y viceversa.
Los `applicationId` distintos permiten tener los tres instalados a la vez.

## Preparar y compilar

```bash
# 1. Librerías nativas de whisper.cpp (commit fijo, ver el script)
bash tool/build_whisper_libs.sh arm64-v8a

# 2. Modelos, con verificación de SHA-256
bash tool/fetch_whisper_models.sh

# 3. Los tres APK
flutter build apk --release --flavor androidSpeech --target-platform android-arm64
flutter build apk --release --flavor whisperTiny  --target-platform android-arm64
flutter build apk --release --flavor whisperBase  --target-platform android-arm64
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

`assets/corpus.json`: 100 frases, 40 de ajuste y 60 de aceptación, sin ninguna
frase compartida entre ambos. Es **texto**; no contiene ni referencia grabaciones
de personas reales, y personas, proveedores y chacos son ficticios. Las frases
llevan ortografía española real porque se leen en voz alta.

`test/corpus_and_isolation_test.dart` falla si alguien recorta el corpus, mezcla
los dos conjuntos o quita una categoría obligatoria.

## Qué se hace con los resultados

El teléfono exporta JSON o CSV a su carpeta de archivos. Desde la raíz del
repositorio:

```bash
dart run tool/voice_benchmark/main.dart <carpeta con los exportados> -o informe.md
```

El agregador nunca rellena un hueco: lo que nadie midió sale como
`NOT_MEASURED`.
