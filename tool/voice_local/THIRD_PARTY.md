# Voz local: componentes de terceros

Nada de esta lista se versiona en el repositorio. Lo obtienen los scripts de esta carpeta desde la fuente indicada y lo verifican por SHA-256 antes de usarlo. Los valores coinciden byte a byte con los que registró el banco híbrido el 2026-09-07 (`benchmark/voice_benchmark/THIRD_PARTY.md`, rama `evolution/evolution-3-hybrid-voice-benchmark`); se volvieron a descargar y comprobar el 2026-11-05.

| Componente | Versión | Fuente | Licencia | SHA-256 | Dónde se fija |
|---|---|---|---|---|---|
| Vosk Android (AAR) | 0.3.75 | Maven Central `com.alphacephei:vosk-android` | Apache-2.0 | `ab2f8b91ac8051561aa325546b35fed9a68b36b8121bac5c6fb927525c4adfad` | `android/app/build.gradle.kts` (`verifyPinnedVoiceArtifacts`, antes de cada build) |
| JNA (AAR, transitiva de Vosk) | 5.18.1 | Maven Central `net.java.dev.jna:jna` | Apache-2.0 (elegida frente a LGPL-2.1) | `7f053e3ec99e14dd71259c82c1c8a02738d64a13c31226b2acc170f3060951e0` | ídem |
| Modelo Vosk español | `vosk-model-small-es-0.42` | `https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip` | Apache-2.0 | zip `09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f` | `fetch_voice_models.sh`; cada archivo, en `manifest.json` |
| Modelo Whisper (por defecto) | `ggml-base-q5_1.bin`, multilingüe | `https://huggingface.co/ggerganov/whisper.cpp` | MIT | `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898` | ídem |
| Modelo Whisper (opción `small`) | `ggml-small-q5_1.bin`, multilingüe | ídem | MIT | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` | ídem |
| whisper.cpp (código) | commit `52a939a2a762224e255d366c1182b2af4dd1a032` | `codeload.github.com/ggml-org/whisper.cpp` | MIT | tar `6212572f00e887698440dbbf87aef27de6e56dbe73907f6148686ec55d584a19` | `build_whisper_libs.sh` |

## Notas

- **La app comprueba cada archivo.** Al copiar los modelos del APK a su carpeta privada (`noBackupFilesDir/voice/`), compara el tamaño y el SHA-256 de cada archivo con `manifest.json`. Si alguno no coincide, no lo usa.
- **Firma de Vosk.** La firma PGP del AAR de Vosk no se pudo verificar (`RISK-033`, banco híbrido). El hash fija los bytes aceptados, no su autoría.
- **Modelos sólo en español o multilingües.** No se usa ningún modelo exclusivo de inglés. Whisper se llama con `language = "es"` y `translate = false`.
- **Código derivado.** `android/app/src/main/cpp/whisper_jni.c` y `CMakeLists.txt` derivan del ejemplo Android de whisper.cpp (MIT, © The ggml authors), a través del puente del banco híbrido.
- **Variante x86_64.** Sólo para el emulador, se compila con AVX2, FMA y F16C. arm64-v8a usa armv8-a sin extensiones.
