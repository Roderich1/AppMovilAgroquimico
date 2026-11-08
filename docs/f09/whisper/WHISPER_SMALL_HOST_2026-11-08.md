# Whisper base frente a small en HOST (#166), 2026-11-08

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08 (Bolivia, UTC−4). Ejecuciones: r1 11:26–11:30, r2 11:31–11:35 |
| Procedencia | **HOST** (PC de desarrollo). **No es un teléfono ni el emulador** |
| Rama / commit del script | `feat/f09-a2-whisper-small`; `tool/voice_local/host_compare.py` idéntico (comprobado con `diff`) al de `b24dca0`. Base de la rama: `fc6478d` |
| PC | Intel Core i7-13700HX, 24 hilos lógicos, Windows 11. Otras sesiones (emulador, compilaciones) podían estar usando el PC: los tiempos llevan ese ruido |
| Motores | Vosk 0.3.45 (Python) con `vosk-model-small-es-0.42`; `whisper-cli` de whisper.cpp `52a939a2` (el mismo commit que la app), compilado para el PC |
| Modelos (SHA-256 verificado hoy) | `ggml-base-q5_1.bin` `422f1ae4…a8898` (59 707 625 B); `ggml-small-q5_1.bin` `ae85e4a9…411bb` (190 085 487 B) |
| Audio | 53 WAV **sintéticos** de `synth_reference_audio.ps1` (voces Helena, Laura y Pablo de Windows) a partir de `tool/voice_local/reference_phrases.tsv`: 16 frases + 1 compuesta (`p01`) × 3 voces = 51 con referencia, más 2 de rechazo (silencio y ruido). Huella del conjunto (`sha256sum *.wav \| sha256sum`): `b7a26dc2…9696d2` |
| Frases | Sólo las de ajuste de `reference_phrases.tsv`, escritas para esta comprobación. **Ninguna frase de aceptación ni del holdout de #12** |
| Configuración | `HOST_COMPARE_THREADS=4` (la app usa `min(4, núcleos)`), `HOST_COMPARE_DECODING=app` (voraz, sin reintentos de temperatura, como `whisper_jni.c`), pista de vocabulario en `base_hint` y `small_hint` |
| Datos | `host_2026-11-08/host_compare_r1.json` (`4d309a63…`), `host_compare_r2.json` (`ad761856…`), `seleccion_app.json` (`8d3f1239…`; r1 y r2 dan exactamente el mismo archivo) |

> **Advertencia.** Todo lo de este documento describe **este PC**. No dice cuánto tarda, cuánta memoria usa ni cuánto acierta la segunda pasada en el POCO, en el HONOR ni en ningún teléfono, ni con voz humana: eso es **NOT_MEASURED**. Los umbrales de #12 se aplican **por teléfono**; aquí sólo se informan como referencia, sin veredicto.

## 1. Comandos

```bash
# Modelos verificados por SHA-256 (caché %LOCALAPPDATA%/AgroVoiceModels/dl)
sha256sum ggml-base-q5_1.bin ggml-small-q5_1.bin

# Comparación (r1 y r2, mismos argumentos)
HOST_COMPARE_THREADS=4 HOST_COMPARE_DECODING=app \
  "$LOCALAPPDATA/AgroVoiceModels/venv/Scripts/python.exe" -I tool/voice_local/host_compare.py \
  "$LOCALAPPDATA/AgroVoiceModels/ref_audio" tool/voice_local/reference_phrases.tsv \
  "$LOCALAPPDATA/AgroVoiceModels/models/vosk-model-small-es-0.42" \
  "$LOCALAPPDATA/AgroVoiceModels/whispercpp/build-host/bin/Release/whisper-cli.exe" \
  "$LOCALAPPDATA/AgroVoiceModels/dl/ggml-base-q5_1.bin" \
  "$LOCALAPPDATA/AgroVoiceModels/dl/ggml-small-q5_1.bin" host_compare_r1.json

# La regla de la app (chooseReviewedText con voiceQuantityFacts) sobre cada frase
AGRO_HOST_COMPARE=host_compare_r1.json AGRO_REF_OUT=seleccion_app.json \
  flutter test tool/voice_local/selection_on_results_test.dart     # +2: All tests passed!
python -I tool/voice_local/host_compare.py --score-selection host_compare_r1.json seleccion_app.json
```

## 2. Coste por frase (54 segmentos de Vosk; el más largo, 4,38 s)

`inferencia` = `total − load` de `whisper_print_timings` (el modelo ya cargado, como en la app). `RTF` = inferencia / duración del segmento. Memoria = pico del proceso `whisper-cli` sólo (sin Vosk ni la app). Percentiles de rango más cercano, sin interpolar.

| Configuración | Ejecución | Inferencia p50 / p95 / máx (ms) | RTF p50 / p95 | Carga p50 (ms) | Pico residente / privado (MB) |
|---|---|--:|--:|--:|--:|
| base + pista | r1 | 729 / 801 / 926 | 0,226 / 0,313 | 63 | 195 / 657 |
| base + pista | r2 | 739 / 784 / 795 | 0,223 / 0,306 | 62 | 195 / 657 |
| small + pista | r1 | 2 672 / 2 998 / 6 891 | 0,849 / 1,129 | 150 | 389 / 851 |
| small + pista | r2 | 2 697 / 2 898 / 2 972 | 0,833 / 1,164 | 144 | 389 / 851 |

- **Small cuesta unas 3,6 veces lo que base** por frase en este PC (p50 2 672–2 697 ms frente a 729–739 ms), y el doble de memoria residente del proceso (389 frente a 195 MB).
- **El codificador domina y no depende de la longitud.** Codificar cuesta lo mismo para una frase de 2 s que de 4 s (p50 de `encode`: small ≈ 2 350 ms, base ≈ 605 ms), porque whisper.cpp procesa siempre una ventana de 30 s. Por eso el RTF de frases cortas es alto aunque la frase sea breve.
- **Variación entre ejecuciones.** La mediana se repite (diferencia ≤ 1,5 %); el máximo no: en r1 dos frases de small tardaron 4 345 y 6 891 ms (`f13_laura`, `p01_laura`), y en r2 ninguna pasó de 2 972 ms. Se atribuye a carga del PC, sin poder comprobarlo.
- **Frente a los umbrales de #12 (sólo como referencia, sin veredicto):** en este PC, small ya supera el p50 ≤ 2 500 ms (53 y 54 de 54 frases por encima) y el RTF p95 ≤ 0,50 (54 de 54 por encima); el p95 ≤ 5 000 ms se cumple (1 y 0 de 54 por encima). Base queda dentro de los tres. Un teléfono suele ser más lento que este PC, pero **eso no se midió**: el rendimiento en el POCO y el HONOR es NOT_MEASURED.
- **Tope por frase de la app (5 000 ms).** En r1, 1 de 54 frases de small lo habría superado y habría quedado con el texto de Vosk; en r2, ninguna.

## 3. Exactitud sobre las 51 frases con referencia

Igual en r1 y r2 (decodificación determinista). Productos: los 45 nombres de producto de las referencias; cantidades: la secuencia de números normalizada de cada frase.

| Configuración | WER medio | Exactas (normalizadas) | Productos | Productos no dichos | Cantidades |
|---|--:|--:|--:|--:|--:|
| Vosk solo | 0,154 | 23 | 21/45 | 0 | 51/51 |
| Whisper base, sin pista | 0,193 | 14 | 15/45 | 0 | 48/51 |
| Whisper base + pista | 0,060 | 32 | 39/45 | 0 | 49/51 |
| Whisper small + pista | 0,029 | 43 | 42/45 | 0 | 51/51 |
| **App con base** (regla de selección) | 0,064 | 32 | 38/45 | 0 | **51/51** |
| **App con small** (regla de selección) | 0,029 | 43 | 42/45 | 0 | **51/51** |

- **La regla de la app** acepta la revisión en 48 de 54 frases con base (6 descartadas por cantidades) y en 50 de 54 con small (4 descartadas por cantidades). Con las dos, las cantidades que llegan al borrador coinciden con la referencia en 51/51.
- **WER sólo como dato** (protocolo, A3): no hay umbral de WER.
- **Rechazo.** En el silencio y el ruido Vosk no cerró ninguna frase, así que la app no llamaría a Whisper. Pasado el archivo entero, small «oyó» texto en los dos («La Cámara de la Sombra de la Sombra…» sobre silencio) y base, «y»: es la razón por la que la segunda pasada sólo corre sobre frases en las que Vosk oyó palabras.

## 4. Lo que esto no dice

- Nada sobre el POCO, el HONOR ni el emulador: tiempos, RTF, memoria total (con Vosk y la app), batería, temperatura y estabilidad en 30 sesiones son **NOT_MEASURED**.
- Nada sobre voz humana, acentos ni ruido real: el audio es sintético de tres voces de Windows.
- No es la evaluación de #12: no usa el holdout ni las fichas, y sus resultados no cuentan como medición de esa evaluación.
- No decide entre base y small: la elección es del autor (ADR-005 sigue con base, provisional).

## 5. APK x86_64 con small (sólo compilación)

Sólo para comprobar que compila y cuánto pesa. **No se instaló** ni se ejecutó en el emulador ni en ningún teléfono.

```bash
bash tool/voice_local/fetch_voice_models.sh small        # verificado ggml-small-q5_1.bin ae85e4a9…411bb
bash tool/voice_local/build_voice_apk.sh x64 <carpeta fuera del repositorio>
bash tool/voice_local/fetch_voice_models.sh              # vuelve a base
```

| Campo | Valor |
|---|---|
| Hora | 11:38:39–11:39:45 (Gradle `assembleProfile` 60,6 s) |
| Código | `b24dca0`. El script avisó «+ cambios sin commit»: el único archivo versionado modificado era `tool/voice_local/README.md` (documentación), que no entra en la APK |
| APK | `agrocuentas-voz-b24dca0-x86_64-review-small-profile.apk`, **277 655 352 B**, SHA-256 `5cfcd25b609644b484302d285b6e631c2e39c47b0f787a3b5841865f8b385a5d`. Queda fuera del repositorio, en la carpeta temporal de la sesión |
| Contenido comprobado | `assets/voice/whisper-small-q5_1/` 190 085 487 B; manifiesto con `variant: small` y el SHA-256 de small; `lib/x86_64/libagro_whisper.so` y las `libggml*` presentes. El Kotlin de esta rama compiló |
| Referencia | La APK x86_64 de base `03124a0` pesa 149 696 990 B (otro código). La diferencia de modelos es 130 377 862 B |
| ARM64 | No compilada hoy. Por la misma diferencia de modelo, la de `03124a0` (147 553 315 B) pasaría a unos 278 MB: **estimación, no medida** |

**Estado del worktree al terminar:** `android/app/voice-models/voice/` vuelve a tener **base** (`fetch_voice_models.sh` sin argumento, SHA-256 verificado). Su `manifest.json` incluye ahora `"variant": "base"`, que antes no estaba; los modelos son los mismos bytes. La APK con small quedó también en `build/app/outputs/flutter-apk/` (ignorado por git): la siguiente compilación la sobrescribe.
