# «AC F09»: configuración de compilación

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08 (Bolivia, UTC−4) |
| Rama | `feat/f09-licencias`, en `_wt/F09-LIC`. Sin push, sin PR |
| Base | `27e9a4e` (HEAD de `feat/f09-integracion`) |
| Procedencia | **HOST**. Cada valor se comprobó en el código o en el binario indicado. Nada se instaló: ni emulador ni teléfono |

## 1. Identidad de la APK

| Parámetro | Valor | Comprobado en |
|---|---|---|
| Paquete | `com.comunidad.agro.agroquimicos.f09` (`applicationId` del repositorio + sufijo `.f09`) | `aapt2 dump badging` de `agrocuentas-f09-fc6478d-x86_64-profile.apk` |
| Etiqueta | «AC F09» | ídem (`application-label:'AC F09'`) |
| Perfil | `profile`, firmado con la clave de depuración: para probar, no para distribuir | `tool/voice_local/build_voice_apk.sh` |
| ABI | `x86_64` para el emulador (`--target-platform android-x64`); `arm64-v8a` para un teléfono (`android-arm64`). Una ABI por APK (`--split-per-abi`) | ídem; `native-code: 'x86_64'` en la APK `fc6478d` |
| SDK | `minSdkVersion` 24, `targetSdkVersion` 36 | badging de la APK `fc6478d` |

**El sufijo y la etiqueta no están en ningún script versionado.**
- `build_voice_apk.sh` aplica `.voz` y «AC VOZ», y los restaura al terminar.
- La APK `.f09` de `fc6478d` se compiló a mano con el mismo procedimiento, cambiando el sufijo, la etiqueta y los `--dart-define`.
- Para repetirla hay que hacer lo mismo, o añadir parámetros al script. Ese archivo no es de esta sesión: lo decide la coordinadora.

## 2. `--dart-define`

| Variable | Valor para «AC F09» | Por defecto si no se pasa | Dónde se lee |
|---|---|---|---|
| `AGRO_VOICE_ENGINE` | `local` (no hace falta pasarla) | `local`. Con `android`, el reconocedor del sistema (ADR-002) | `lib/voice/voice_providers.dart` |
| `AGRO_VOICE_EVIDENCE` | `true` | `false`: sin evidencia ni pantalla de consentimiento | `lib/presentation/voice/voice_evidence_hook.dart` |
| `AGRO_APP_COMMIT` | SHA corto del commit compilado | vacío = «desconocido» | ídem |
| `AGRO_VOICE_REVIEW_TIMEOUT_MS` | `5000` (no hace falta pasarla) | `5000` ms | `lib/voice/voice_providers.dart` |
| `AGRO_API_BASE_URL` | Origen HTTPS del Central, sólo para activar la instalación | vacío: la app arranca, pero no se puede activar | `lib/services/auth/api_endpoint_config.dart` |

- **`AGRO_API_BASE_URL`.** La app exige `https`, sin usuario, ruta, consulta ni fragmento (`_validate`). El valor queda compilado dentro de la APK: no se escribe en documentos, evidencias ni commits, y una APK compilada con él no se publica. `build_voice_apk.sh` lo toma de la variable de entorno del mismo nombre.
- **En la APK `fc6478d`** aparece la cadena `fc6478d` en `libapp.so` (`AGRO_APP_COMMIT`). No se compiló con origen del Central.

## 3. Motor y modelos

| Pieza | Valor | Fijado en |
|---|---|---|
| Motor principal | Vosk Android **0.3.75** (`com.alphacephei:vosk-android:0.3.75`, AAR SHA-256 `ab2f8b91ac8051561aa325546b35fed9a68b36b8121bac5c6fb927525c4adfad`), con JNA **5.18.1** (AAR `7f053e3ec99e14dd71259c82c1c8a02738d64a13c31226b2acc170f3060951e0`) | `android/app/build.gradle.kts`: versión exacta y `verifyPinnedVoiceArtifacts` antes de cada build |
| Modelo principal | `vosk-model-small-es-0.42` (zip `09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f`), dentro de la APK en `assets/voice/` | `tool/voice_local/fetch_voice_models.sh`; cada archivo en `manifest.json` |
| Segunda pasada | whisper.cpp commit `52a939a2a762224e255d366c1182b2af4dd1a032` (tar `6212572f00e887698440dbbf87aef27de6e56dbe73907f6148686ec55d584a19`), en `libagro_whisper.so` + `libggml*.so`. Idioma `es`, sin traducir, hasta 4 hilos | `build_whisper_libs.sh`; `whisper_jni.c`; `LocalVoiceEngine.kt` |
| Modelo de la segunda pasada | **`ggml-base-q5_1.bin`** (SHA-256 `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`), el valor por defecto de `fetch_voice_models.sh` | `fetch_voice_models.sh` (`REVIEW=${1:-base}`) |

- **Whisper small, NO en esta etapa.** Sólo entra si se prepara con `fetch_voice_models.sh small` (`ggml-small-q5_1.bin`, `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb`), y entonces el nombre de la APK lleva `-review-small`.
- **x86_64.** Las `.so` de whisper.cpp se compilan con AVX2, FMA y F16C: sólo para el emulador.
- **La segunda pasada es condicional.** La app la usa sólo si el aparato la admite (`lib/voice/port/review_capability.dart`):
  - base exige 1 700 MiB de memoria total, small 3 400 MiB;
  - un aparato `isLowRamDevice` o con fallo de carga queda sólo con Vosk.
  Son mínimos de prudencia, no una medición.

## 4. Alcance de #166

- **Implementado:** el modelo de revisión es seleccionable al compilar (`base`, `small` o `none`). Por defecto, **base**.
- **Medido:** sólo en HOST con audio sintético (`docs/f09/whisper/WHISPER_SMALL_HOST_2026-11-08.md`).
- **Sin medir:** el tiempo, la memoria y la exactitud en un teléfono, con base o con small. La elección base o small es del autor.

## 5. Avisos de licencia

La APK lleva los textos de `assets/licenses/` en `assets/flutter_assets/assets/licenses/`. Se ven en **Más › Licencias**, junto a los paquetes Dart y el motor de Flutter (`NOTICES.Z`). Procedencia en `assets/licenses/README.md`; inventario en `tool/voice_local/THIRD_PARTY.md`.

### 5.1 Verificación en una APK compilada

- **Comando:** `bash tool/voice_local/build_voice_apk.sh x64 %TEMP%/agro_f09_lic/apk`, sin `AGRO_API_BASE_URL`, sobre `b19adf3`. El script deja `.voz` y «AC VOZ»: para comprobar el contenido da igual. Sólo compilada, no instalada.
- **APK:** `agrocuentas-voz-b19adf3-x86_64-profile.apk`, SHA-256 `d7612475eef833eff3894195803db3b25665993819b759d16b78306b3e143e5c`, 150 107 887 B. El script la marca «+ cambios sin commit» por `tool/voice_local/THIRD_PARTY.md`, que no entra en la APK. `build.gradle.kts` y `AndroidManifest.xml` quedaron restaurados.
- **Resultado:** los nueve textos están en `assets/flutter_assets/assets/licenses/` y son idénticos byte a byte (`cmp`) a los de `assets/licenses/`. `README.md` y `.gitattributes` no entran.
- **Contenido nativo y modelos:** `lib/x86_64/` lleva `libvosk.so`, `libjnidispatch.so`, `libagro_whisper.so`, `libggml.so`, `libggml-base.so` y `libggml-cpu.so`. `assets/voice/` lleva el modelo Vosk y `ggml-base-q5_1.bin`, como la APK `fc6478d`.
- **`NOTICES.Z`:** sigue sin mencionar Vosk, JNA, whisper ni ggml (0 apariciones). Por eso hacen falta los textos de `assets/licenses/`.
- **Raíz de la APK (no es de esta sesión):** además, `META-INF/AL2.0` y `META-INF/LGPL2.1` (de JNA) y `LICENSE-junit.txt` (EPL-1.0). No se investigó qué dependencia aporta este último.
