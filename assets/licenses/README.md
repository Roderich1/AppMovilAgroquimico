# Textos de licencia de la voz local

Avisos de los componentes que la APK con voz local distribuye y que el aviso de Flutter (`assets/flutter_assets/NOTICES.Z`, paquetes Dart y motor) no cubre. La app los registra en `LicenseRegistry` (`lib/licenses/third_party_licenses.dart`) y los muestra en **Más › Licencias**.

- **Copias literales.** Cada archivo se descargó el 2026-11-08 de la fuente indicada y se copió byte a byte. `.gitattributes` impide que git cambie los fines de línea, para que el SHA-256 siga coincidiendo.
- **Comprobación.** `test/licenses/third_party_licenses_test.dart` compara el SHA-256 de cada archivo con esta tabla.
- **Este README no viaja en la APK.** `pubspec.yaml` declara sólo las subcarpetas.

## Archivos

| Archivo | Componente | Fuente oficial | Versión o commit | SHA-256 | Bytes |
|---|---|---|---|---|---|
| `assets/licenses/vosk/COPYING` | Vosk Android 0.3.75 (`libvosk.so`) | `https://raw.githubusercontent.com/alphacep/vosk-api/625e44c62607a3b48fec6d72a30118448909e83f/COPYING` | `alphacep/vosk-api` `625e44c62607a3b48fec6d72a30118448909e83f` (ver nota 1) | `bb618af833c817ab01c1564bd3ec75ba4b4f9cf30910a4a2168e30a674ee8cc6` | 10 173 |
| `assets/licenses/jna/LICENSE` | JNA 5.18.1 (`libjnidispatch.so`) | `https://raw.githubusercontent.com/java-native-access/jna/3c493c1642b1555d541755e0984c968ba6c0f540/LICENSE` | etiqueta `5.18.1` = `3c493c1642b1555d541755e0984c968ba6c0f540` | `07c938b23950ab7d47a24ef35f9f5da3a05ae164278dc959ad6994135ed59ff1` | 797 |
| `assets/licenses/jna/AL2.0` | JNA 5.18.1, licencia Apache 2.0 | `https://raw.githubusercontent.com/java-native-access/jna/3c493c1642b1555d541755e0984c968ba6c0f540/AL2.0` | ídem | `0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594` | 10 174 |
| `assets/licenses/jna/libffi/LICENSE` | libffi, dentro de `libjnidispatch.so` | `https://raw.githubusercontent.com/java-native-access/jna/3c493c1642b1555d541755e0984c968ba6c0f540/native/libffi/LICENSE` | ídem | `2c9c2acb9743e6b007b91350475308aee44691d96aa20eacef8e199988c8c388` | 1 132 |
| `assets/licenses/whisper_cpp/LICENSE` | whisper.cpp (`libagro_whisper.so`) | `https://raw.githubusercontent.com/ggml-org/whisper.cpp/52a939a2a762224e255d366c1182b2af4dd1a032/LICENSE` | `52a939a2a762224e255d366c1182b2af4dd1a032`, el de `tool/voice_local/build_whisper_libs.sh` | `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d` | 1 078 |
| `assets/licenses/ggml/LICENSE` | ggml (`libggml.so`, `libggml-base.so`, `libggml-cpu.so`) | `https://raw.githubusercontent.com/ggml-org/ggml/e91ded11bdcd78c42f9c8d3978ff6686eb4c1226/LICENSE` | `ggml-org/ggml` `e91ded11bdcd78c42f9c8d3978ff6686eb4c1226` (ver nota 2) | `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d` | 1 078 |
| `assets/licenses/vosk_model_small_es_0_42/README` | Modelo `vosk-model-small-es-0.42` | `https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip`, archivo `README` del zip | zip `09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f` | `94132a6f5334701d8c0b4d25ef6890f74972909d8824c6c5974c41bca0542d88` | 483 |
| `assets/licenses/vosk_model_small_es_0_42/LICENSE-2.0.txt` | Modelo `vosk-model-small-es-0.42`, licencia Apache 2.0 (ver nota 3) | `https://www.apache.org/licenses/LICENSE-2.0.txt` | sin versión en la URL; descargado el 2026-11-08 | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` | 11 358 |
| `assets/licenses/whisper_model/LICENSE` | Pesos del modelo Whisper de OpenAI (ver nota 4) | `https://raw.githubusercontent.com/openai/whisper/31243bad24cc746f07d4c8bfdd2d974872cb1803/LICENSE` | etiqueta `v20250625` = `31243bad24cc746f07d4c8bfdd2d974872cb1803` | `b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d` | 1 063 |

## Notas

1. **Vosk.**
   - `vosk-api` no tiene etiqueta `0.3.75`. El commit `625e44c` (2025-12-08, «Bump JNA requirements to 5.18.1 and update version») es el que pone `version = '0.3.75'` en `android/build.gradle` y JNA 5.18.1.
   - El POM de Maven Central (`com.alphacephei:vosk-android:0.3.75`) declara «The Apache License, Version 2.0».
   - El `COPYING` del repositorio no es idéntico al texto de apache.org: dice «this License» en vez de «This License» en el §6 y no trae el apéndice. Se copia tal cual.
2. **ggml.**
   - La APK no lleva ggml desde su repositorio: lo compila `build_whisper_libs.sh` desde la copia incluida en whisper.cpp `52a939a`. El `LICENSE` raíz de whisper.cpp («Copyright (c) 2023-2026 The ggml authors») la cubre.
   - `scripts/sync-ggml.last` de ese commit apunta a ggml `e91ded11bdcd78c42f9c8d3978ff6686eb4c1226`. Su `LICENSE` es idéntico byte a byte al de whisper.cpp.
   - Compilación sin `GGML_LLAMAFILE`, sin `GGML_CPU_KLEIDIAI` y sin OpenMP: no entra código de terceros con licencia propia (`CMakeCache.txt` y `.ninja_log` de la compilación local, 2026-11-08).
3. **Modelo Vosk.**
   - El zip no trae texto de licencia. Su `README` sólo dice «Copyright 2022-2050 AC Technologies LLC».
   - La lista oficial `https://alphacephei.com/vosk/models`, descargada el 2026-11-08 (SHA-256 de la página `54ea4c1e367e18a67e8f4fce6232de62e5a467f8ec094266be7650efa1d7e77a`), le asigna «Apache 2.0» en la fila de `vosk-model-small-es-0.42`. Por eso se acompaña el texto de apache.org.
4. **Modelo Whisper.**
   - La APK lleva `ggml-base-q5_1.bin` (o `ggml-small-q5_1.bin` con `fetch_voice_models.sh small`), descargado de `https://huggingface.co/ggerganov/whisper.cpp`. Es la conversión a ggml de los pesos de Whisper de OpenAI, hecha por el proyecto whisper.cpp.
   - El `README.md` de ese repositorio, revisión `5359861c739e955e79d9a303bcbc70fb988958b1` (SHA-256 `21fd967098804f33fc84e803fb0e5ab7666d71801f4027cf28a65e7af09c1758`), declara `license: mit` y no trae archivo de licencia. No se copia en la APK.
   - Los pesos originales son de OpenAI, con el `LICENSE` MIT de `openai/whisper` («Copyright (c) 2022 OpenAI»), que es el que se muestra.

## Fuera de esta carpeta

- **Paquetes Dart y motor de Flutter.** `flutter build` los añade solo, en `NOTICES.Z`, y la página de licencias los muestra junto a éstos.
- **Textos que ya trae la APK.** JNA deja `META-INF/AL2.0` y `META-INF/LGPL2.1` en la raíz de la APK. Sus avisos para la persona usuaria se muestran desde aquí.
- **Sin cubrir: lo que `libvosk.so` enlaza dentro.** El binario contiene Kaldi, OpenFST y OpenBLAS (cadenas `kaldi::`, `fst::` y `OpenBLAS` en el `.so`) y, según `android/lib/build-vosk.sh` de `vosk-api`, CLAPACK. El AAR no trae sus avisos y no se puede saber desde el binario de qué commit sale cada uno. Queda para que decida el autor.
