# Textos de licencia de la voz local

Avisos de los componentes que la APK con voz local distribuye y que el aviso de Flutter (`assets/flutter_assets/NOTICES.Z`, paquetes Dart y motor) no cubre. La app los registra en `LicenseRegistry` (`lib/licenses/third_party_licenses.dart`) y los muestra en **Más › Licencias**.

- **Copias literales.** Cada archivo se descargó el 2026-11-08 de la fuente indicada y se copió byte a byte. `.gitattributes` impide que git cambie los fines de línea, para que el SHA-256 siga coincidiendo.
- **Comprobación.** `test/licenses/third_party_licenses_test.dart` compara el SHA-256 de cada archivo con esta tabla.
- **Este README no viaja en la APK.** `pubspec.yaml` declara sólo las subcarpetas.

## Archivos

| Archivo | Componente | Fuente oficial | Versión o commit | SHA-256 | Bytes |
|---|---|---|---|---|---|
| `assets/licenses/vosk/COPYING` | Vosk Android 0.3.75 (`libvosk.so`) | `https://raw.githubusercontent.com/alphacep/vosk-api/625e44c62607a3b48fec6d72a30118448909e83f/COPYING` | `alphacep/vosk-api` `625e44c62607a3b48fec6d72a30118448909e83f` (ver nota 1) | `bb618af833c817ab01c1564bd3ec75ba4b4f9cf30910a4a2168e30a674ee8cc6` | 10 173 |
| `assets/licenses/vosk/kaldi/COPYING` | Kaldi, dentro de `libvosk.so` | `https://raw.githubusercontent.com/alphacep/kaldi/8b7fecf92b329b7253d9d1cd97898c8b13f9aef3/COPYING` | rama `vosk-android`, cabeza `8b7fecf92b329b7253d9d1cd97898c8b13f9aef3` (ver nota 5) | `3fd3dd523b1717f1fb2ae40896df943d767fa5e664e46156c2dba7094f0d7172` | 17 264 |
| `assets/licenses/vosk/openfst/COPYING` | OpenFST 1.8.0, dentro de `libvosk.so` | `https://raw.githubusercontent.com/alphacep/openfst/18e94e63870ebcf79ebb42b7035cd3cb626ec090/COPYING` | rama `master`, cabeza `18e94e63870ebcf79ebb42b7035cd3cb626ec090` (ver nota 5) | `dd0c6c9378a98b6a0e96b559b285c8506434fe2691eeeef151e8a8c1c492778e` | 559 |
| `assets/licenses/vosk/openblas/LICENSE` | OpenBLAS 0.3.20, dentro de `libvosk.so` | `https://raw.githubusercontent.com/OpenMathLib/OpenBLAS/0b678b19dc03f2a999d6e038814c4c50b9640a4e/LICENSE` | etiqueta `v0.3.20` = `0b678b19dc03f2a999d6e038814c4c50b9640a4e` | `190b5a9c8d9723fe958ad33916bd7346d96fab3c5ea90832bb02d854f620fcff` | 1 548 |
| `assets/licenses/vosk/openblas/GotoBLAS_00License.txt` | OpenBLAS 0.3.20, aviso de GotoBLAS2 | `https://raw.githubusercontent.com/OpenMathLib/OpenBLAS/0b678b19dc03f2a999d6e038814c4c50b9640a4e/GotoBLAS_00License.txt` | ídem | `38d9eb2e3d49d73fa12b18729a112fa949f7887c3ff12be23a02c0c97d9fb5b8` | 1 608 |
| `assets/licenses/vosk/clapack/COPYING` | CLAPACK 3.2.1, dentro de `libvosk.so` | `https://raw.githubusercontent.com/alphacep/clapack/f4e1647de96343fb20eea08a9d4f0e0d04c31c51/COPYING` | rama `v3.2.1`, cabeza `f4e1647de96343fb20eea08a9d4f0e0d04c31c51` (ver nota 5) | `23014869214a231525b38c39fdb5f82364fa24154ac80fdcab2a79671460fd09` | 1 607 |
| `assets/licenses/vosk/clapack/libf2c/Notice` | libf2c (de CLAPACK), dentro de `libvosk.so` | `https://raw.githubusercontent.com/alphacep/clapack/f4e1647de96343fb20eea08a9d4f0e0d04c31c51/F2CLIBS/libf2c/Notice` | ídem | `44561c447e91203ddc747beeca5cc2794d95ee982c17c578670e4f0408bc3904` | 1 212 |
| `assets/licenses/jna/LICENSE` | JNA 5.18.1 (`libjnidispatch.so`) | `https://raw.githubusercontent.com/java-native-access/jna/3c493c1642b1555d541755e0984c968ba6c0f540/LICENSE` | etiqueta `5.18.1` = `3c493c1642b1555d541755e0984c968ba6c0f540` | `07c938b23950ab7d47a24ef35f9f5da3a05ae164278dc959ad6994135ed59ff1` | 797 |
| `assets/licenses/jna/AL2.0` | JNA 5.18.1, licencia Apache 2.0 | `https://raw.githubusercontent.com/java-native-access/jna/3c493c1642b1555d541755e0984c968ba6c0f540/AL2.0` | ídem | `0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594` | 10 174 |
| `assets/licenses/jna/libffi/LICENSE` | libffi, dentro de `libjnidispatch.so` | `https://raw.githubusercontent.com/java-native-access/jna/3c493c1642b1555d541755e0984c968ba6c0f540/native/libffi/LICENSE` | ídem | `2c9c2acb9743e6b007b91350475308aee44691d96aa20eacef8e199988c8c388` | 1 132 |
| `assets/licenses/whisper_cpp/LICENSE` | whisper.cpp (`libagro_whisper.so`) | `https://raw.githubusercontent.com/ggml-org/whisper.cpp/52a939a2a762224e255d366c1182b2af4dd1a032/LICENSE` | `52a939a2a762224e255d366c1182b2af4dd1a032`, el de `tool/voice_local/build_whisper_libs.sh` | `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d` | 1 078 |
| `assets/licenses/ggml/LICENSE` | ggml (`libggml.so`, `libggml-base.so`, `libggml-cpu.so`) | `https://raw.githubusercontent.com/ggml-org/ggml/e91ded11bdcd78c42f9c8d3978ff6686eb4c1226/LICENSE` | `ggml-org/ggml` `e91ded11bdcd78c42f9c8d3978ff6686eb4c1226` (ver nota 2) | `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d` | 1 078 |
| `assets/licenses/vosk_model_small_es_0_42/README` | Modelo `vosk-model-small-es-0.42` | `https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip`, archivo `README` del zip | zip `09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f` | `94132a6f5334701d8c0b4d25ef6890f74972909d8824c6c5974c41bca0542d88` | 483 |
| `assets/licenses/apache-2.0/LICENSE-2.0.txt` | Texto Apache 2.0 compartido: modelo `vosk-model-small-es-0.42` (nota 3) y, en la compilación *profile*, AndroidX Test, Espresso, Guava, failureaccess, J2ObjC Annotations, JavaWriter y javax.inject (nota 6) | `https://www.apache.org/licenses/LICENSE-2.0.txt` | sin versión en la URL; descargado el 2026-11-08. Es idéntico byte a byte al archivo de licencia de cada proyecto en su versión (nota 6) | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` | 11 358 |
| `assets/licenses/whisper_model/LICENSE` | Pesos del modelo Whisper de OpenAI (ver nota 4) | `https://raw.githubusercontent.com/openai/whisper/31243bad24cc746f07d4c8bfdd2d974872cb1803/LICENSE` | etiqueta `v20250625` = `31243bad24cc746f07d4c8bfdd2d974872cb1803` | `b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d` | 1 063 |
| `assets/licenses/integration_test/flutter/LICENSE` | Plugin `integration_test` (parte Android), del SDK de Flutter | `https://raw.githubusercontent.com/flutter/flutter/d3b14c876900e553bc736ca19295fc09e3853e8e/LICENSE` | etiqueta `3.47.2` = `d3b14c876900e553bc736ca19295fc09e3853e8e`, el SDK local | `a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20` | 1 519 |
| `assets/licenses/integration_test/junit/LICENSE-junit.txt` | JUnit 4.12 | `https://raw.githubusercontent.com/junit-team/junit4/64155f8a9babcfcf4263cf4d08253a1556e75481/LICENSE-junit.txt` | etiqueta `r4.12` = `64155f8a9babcfcf4263cf4d08253a1556e75481`. Idéntico al que trae `junit-4.12.jar` | `9648bb2891b9813970bddb68d4be8a5e6ec8280d0180a53dfb29236b579c55bb` | 11 376 |
| `assets/licenses/integration_test/junit/NOTICE.txt` | JUnit 4.12 | `https://raw.githubusercontent.com/junit-team/junit4/64155f8a9babcfcf4263cf4d08253a1556e75481/NOTICE.txt` | ídem | `cffc5b39811d6ef40395a858f209215fa87e8230f1641068200c167014638d32` | 335 |
| `assets/licenses/integration_test/hamcrest/LICENSE.txt` | Hamcrest 1.3 (core, library, integration) | `https://raw.githubusercontent.com/hamcrest/JavaHamcrest/36d525e1e425006939a77aec5183aecd7c775b05/LICENSE.txt` | etiqueta `hamcrest-java-1.3` = `36d525e1e425006939a77aec5183aecd7c775b05`. Idéntico al `LICENSE.txt` de `hamcrest-core-1.3.jar` | `1cde867cab5c8e842929da5391cef98b4017314822270e934e8e2eef3767c666` | 1 509 |
| `assets/licenses/integration_test/checker_framework/LICENSE.txt` | Checker Framework `checker-compat-qual` 2.5.5 | `https://raw.githubusercontent.com/typetools/checker-framework/62602db32dbc0dd64b5aecc8c84671252a50e08b/LICENSE.txt` | etiqueta `checker-framework-2.5.5` = `62602db32dbc0dd64b5aecc8c84671252a50e08b` | `b9e14418b2f652461fd3348031ec2b46d89369405108df9b03f3c8adb49322e1` | 22 369 |
| `assets/licenses/integration_test/javax_inject/Inject.java-cabecera.txt` | javax.inject 1 | líneas 1 a 15 de `https://raw.githubusercontent.com/javax-inject/javax-inject/1e4a33307a1a2c5f38dd87e9458591a02b6f2f41/src/javax/inject/Inject.java` (archivo completo `04cefc686b5ea6d0d40d569d2345a3a6f0a5f6baa5c39976f047fbbd7bc5cf9f`) | etiqueta `1` = `1e4a33307a1a2c5f38dd87e9458591a02b6f2f41` | `030729292c636a6afc1505f5404ba728bca73beed714a69cd85bbcd5c6126c90` | 613 |
| `assets/licenses/integration_test/animal_sniffer/IgnoreJRERequirement.java-cabecera.txt` | Animal Sniffer Annotations 1.18 | líneas 3 a 26 de `https://raw.githubusercontent.com/mojohaus/animal-sniffer/fde3a201bc9e18717cd73d0ee9c0d7e859b6aee6/animal-sniffer-annotations/src/main/java/org/codehaus/mojo/animal_sniffer/IgnoreJRERequirement.java` (archivo completo `184579efc042fcb11945640030e6b1efb8a57e3ba26ca6fda11ce2d2823d4e51`), la única clase del artefacto | etiqueta `animal-sniffer-parent-1.18` = `fde3a201bc9e18717cd73d0ee9c0d7e859b6aee6` | `406e252a6601b0a9d873d32d413b02fe2fa953d790e42a65dcde6ead022f82e5` | 1 165 |

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
   - La lista oficial `https://alphacephei.com/vosk/models`, descargada el 2026-11-08 (SHA-256 de la página `54ea4c1e367e18a67e8f4fce6232de62e5a467f8ec094266be7650efa1d7e77a`), le asigna «Apache 2.0» en la fila de `vosk-model-small-es-0.42`. Por eso se acompaña el texto de apache.org (`assets/licenses/apache-2.0/`).
4. **Modelo Whisper.**
   - La APK lleva `ggml-base-q5_1.bin` (o `ggml-small-q5_1.bin` con `fetch_voice_models.sh small`), descargado de `https://huggingface.co/ggerganov/whisper.cpp`. Es la conversión a ggml de los pesos de Whisper de OpenAI, hecha por el proyecto whisper.cpp.
   - El `README.md` de ese repositorio, revisión `5359861c739e955e79d9a303bcbc70fb988958b1` (SHA-256 `21fd967098804f33fc84e803fb0e5ab7666d71801f4027cf28a65e7af09c1758`), declara `license: mit` y no trae archivo de licencia. No se copia en la APK.
   - Los pesos originales son de OpenAI, con el `LICENSE` MIT de `openai/whisper` («Copyright (c) 2022 OpenAI»), que es el que se muestra.

5. **Lo que `libvosk.so` lleva dentro.**
   - **Cómo se compiló.** `android/lib/build-vosk.sh` de `vosk-api` en `625e44c`, el commit que fija la versión 0.3.75. Clona:
     - OpenBLAS con `-b v0.3.20` (etiqueta) y `ONLY_CBLAS=1`, que implica `NO_LAPACK=1`: no entra el `lapack-netlib` de OpenBLAS;
     - `alphacep/clapack` con `-b v3.2.1` (es una rama, no una etiqueta), de la que compila `libf2c`, `BLAS` y `SRC`;
     - `alphacep/openfst` sin rama (la de por defecto, `master`), con `OPENFST_VERSION=1.8.0`;
     - `alphacep/kaldi` con `-b vosk-android`.

     `src/Makefile` del mismo commit enlaza `libopenblas.a`, `liblapack.a`, `libblas.a`, `libf2c.a`, `libfst.a`, `libfstngram.a` y las bibliotecas de Kaldi.
   - **Qué se fija con certeza.** Sólo OpenBLAS tiene etiqueta. Para Kaldi, OpenFST y CLAPACK el script usa ramas, y no se sabe en qué commit estaban el día en que se compiló el AAR. Lo verificable es esto:
     - el último cambio de cada archivo de licencia es anterior a `625e44c` (2025-12-08): Kaldi `COPYING` 2018-05-07, OpenFST `COPYING` 2020-12-21 («Upgrade to Openfst 1.8.0»), CLAPACK `COPYING` y `F2CLIBS/libf2c/Notice` 2021-01-05, GotoBLAS 2011-01-24;
     - las cabezas actuales de esas ramas también son anteriores: Kaldi y OpenFST 2024-08-23, CLAPACK 2025-05-01.

     Por eso el texto es el mismo en cualquier commit de esas ramas posterior a esas fechas. Se copia el de la cabeza actual.
   - **Qué no se puede verificar.** Que el AAR publicado en Maven Central se compilara con ese script, porque lo compila Alpha Cephei. En el `.so` sí aparecen las piezas:
     - `kaldi::`, `OpenBLAS` y `cblas_sgemm`;
     - de CLAPACK, `sgesvd_` y `slamch_`;
     - de libf2c, `s_cat`, `pow_ri` y su mensaje «apparent state».

     Cadenas contadas en `lib/x86_64/libvosk.so` de la APK `b19adf3`.
   - **C++.** El script enlaza con `-static-libstdc++` (libc++ del NDK, Apache-2.0 con excepción LLVM). No se añade aviso: la excepción LLVM no exige atribución en forma binaria. Decide el autor si quiere mostrarlo.

6. **Lo que trae `integration_test` a la compilación *profile*.**
   - **Por qué está.** `integration_test` está en `dev_dependencies`. El plugin de Gradle de Flutter 3.47.2 (`PluginHandler.kt`) añade los plugins de desarrollo a todos los tipos de compilación menos `release`. «AC F09» se distribuye como *profile*, así que estos artefactos viajan con código.
   - **Cómo se obtuvo la lista.** `./gradlew :app:dependencies --configuration profileRuntimeClasspath`, menos `releaseRuntimeClasspath`, sin las variantes del motor de Flutter (`io.flutter:*_profile`). Para cada artefacto se cuentan en los `classes*.dex` de la APK `b096487` los descriptores de sus clases:

     | Artefacto | Clases en el dex | Licencia (POM) |
     |---|---|---|
     | `androidx.test.espresso:espresso-core:3.3.0` | 610 de 610 | Apache 2.0 |
     | `androidx.test.espresso:espresso-idling-resource:3.3.0` | 4 de 4 | Apache 2.0 |
     | `androidx.test:monitor:1.3.0` | 68 de 68 | Apache 2.0 |
     | `androidx.test:rules:1.2.0` | 29 de 29 | Apache 2.0 |
     | `androidx.test:runner:1.3.0` | 138 de 138 | Apache 2.0 |
     | `com.google.guava:guava:28.1-android` | 1 863 de 1 863 | Apache 2.0 (`guava-parent`) |
     | `com.google.guava:failureaccess:1.0.1` | 2 de 2 | Apache 2.0 (`guava-parent`) |
     | `com.google.j2objc:j2objc-annotations:1.3` | 12 de 12 | Apache 2.0 |
     | `com.squareup:javawriter:2.1.1` | 2 de 2 | Apache 2.0 |
     | `javax.inject:javax.inject:1` | 6 de 6 | Apache 2.0 |
     | `junit:junit:4.12` | 286 de 286 | EPL 1.0 |
     | `org.hamcrest:hamcrest-core:1.3` | 45 de 45 | BSD (`hamcrest-parent`) |
     | `org.hamcrest:hamcrest-library:1.3` | 35 de 35 | ídem |
     | `org.hamcrest:hamcrest-integration:1.3` | 5 de 5 | ídem |
     | `org.checkerframework:checker-compat-qual:2.5.5` | 10 de 10 | GPL-2.0 con excepción de classpath, o MIT |
     | `org.codehaus.mojo:animal-sniffer-annotations:1.18` | 1 de 1 | MIT (`animal-sniffer-parent`) |

     Además, el propio plugin (`dev.flutter.plugins.integration_test`), con 21 referencias. Su licencia es la del SDK de Flutter, y `NOTICES.Z` no lo menciona.
   - **Lo que no se registra.** `com.google.guava:listenablefuture:9999.0-empty-to-avoid-conflict-with-guava` no tiene clases. `jsr305:3.0.2` y `error_prone_annotations` también están en release (los trae `flutter_secure_storage` → Tink): no son de `integration_test`.
   - **Fuentes por versión.**
     - Apache 2.0: el archivo de licencia de cada proyecto, en su versión, es idéntico byte a byte al de apache.org (`cfc7749b…d30`). Por eso se muestra una sola copia. Archivos comparados:
       - `android/android-test` `LICENSE` en `androidx-test-1.3.0` (`336e98882e2c552ce8c22c38e92ca096440c9f1b`; runner y monitor 1.3.0, Espresso 3.3.0) y en `androidx-test-1.2.0` (`3a938108ae453e289995dad0b045bde0425a8887`; rules 1.2.0);
       - `google/guava` `COPYING` en `v28.1` (`e30495f4e09e2511b4f2bb95d2b9e1b262c4215d`) y en `failureaccess-v1.0.1` (`b8d5ecd40b9cfbd9cafc08bf50bd2382369812e9`);
       - `google/j2objc` `LICENSE` en `1.3` (`1c1a8b7f1f816e0714c9fff9369e10adecb3b3b6`);
       - `square/javapoet` (antes `javawriter`) `LICENSE.txt` en `javawriter-2.1.1` (`84fd31ce9b407dbd1aaea1137dbffbb3065e9b87`).

       Ninguno de esos proyectos tiene `NOTICE` en esa versión.
     - **javax.inject 1:** el repositorio no trae archivo de licencia en la etiqueta `1`. Se muestran la cabecera Apache de `Inject.java` («Copyright (C) 2009 The JSR-330 Expert Group») y el texto de apache.org.
     - **Animal Sniffer 1.18:** no hay archivo de licencia en la etiqueta. Se muestra la cabecera MIT de su única clase, que contiene el texto completo y el aviso de copyright.
     - **Checker Framework:** su `LICENSE.txt` explica que las anotaciones (`checker-qual`/`compat-qual`) están bajo MIT. Se copia entero, con el texto GPL incluido.
     - **JUnit:** su `NOTICE.txt` remite a Hamcrest, que también se muestra.
   - **En release** la app no registra este grupo (`kReleaseMode`), porque no viaja.
7. **libc++ (Apache-2.0 WITH LLVM-exception).**
   - Va enlazada estática en `libvosk.so` (`-static-libstdc++`) y en las bibliotecas de whisper.cpp/ggml (NDK r28c, `28.2.13676358`, LLVM 19.0.1 `r530567e`, base `llvm/llvm-project` `3b5e7c83a6e226d5bd7ed2e9b67449b64812074c`). La APK no lleva `libc++_shared.so`.
   - `libcxx/LICENSE.TXT` en ese commit (SHA-256 `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b`) dice en «LLVM Exceptions to the Apache 2.0 License»: «if, as a result of your compiling your source code, portions of this Software are embedded into an Object form of such source code, you may redistribute such embedded portions in such Object form without complying with the conditions of Sections 4(a), 4(b) and 4(d) of the License».
   - Esos apartados son los que exigen entregar la licencia y los avisos. **No se añade aviso.**
   - No se sabe con qué NDK compiló Alpha Cephei `libvosk.so`. La excepción está en `LICENSE.TXT` de llvm-project desde que el proyecto cambió de licencia.

## Fuera de esta carpeta

- **Paquetes Dart y motor de Flutter.** `flutter build` los añade solo, en `NOTICES.Z`, y la página de licencias los muestra junto a éstos.
- **Textos que ya trae la APK.** JNA deja `META-INF/AL2.0` y `META-INF/LGPL2.1` en la raíz de la APK. Sus avisos para la persona usuaria se muestran desde aquí.
- **`LICENSE-junit.txt` en la raíz de la APK *profile*.** Lo deja `junit-4.12.jar` (nota 6). Su texto se muestra desde aquí.
- **Sin cubrir: las dependencias Android de la app en todas las compilaciones.** Siguen sin registrarse androidx, Kotlin, kotlinx-coroutines, Tink, Gson, jsr305, error_prone_annotations, jspecify, relinker, etc. (`releaseRuntimeClasspath`). Algunas dejan su `LICENSE.txt` en `META-INF/` y `NOTICES.Z` no las cubre. Quedan fuera del alcance de esta ronda.
