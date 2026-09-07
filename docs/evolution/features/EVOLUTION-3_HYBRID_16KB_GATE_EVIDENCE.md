# EVOLUTION-3 — Gate de páginas de 16 KB, ejecutado

Estado: **ejecutado para C1 y C3**. C4 queda pendiente y se probará en el mismo
entorno.

La validación estática no sustituye a la ejecución real, y por eso este
documento existe: un ELF puede estar alineado a 16 KB y aun así el proceso puede
no arrancar, no encontrar la librería o caerse al primer uso.

## Entorno

| Campo | Valor |
|---|---|
| AVD | `Pixel_8` |
| Imagen | `system-images;android-36.1;google_apis_playstore_ps16k;x86_64` |
| Huella | `google/sdk_gphone16k_x86_64/emu64xa16k:16/BE4B.251210.005/14574095:user/dev-keys` |
| API / Android | 36 / 16 |
| ABI | `x86_64` |
| `adb shell getconf PAGE_SIZE` | **`16384`** |
| Fecha | 2026-09-07 |

El emulador es `x86_64`, así que se construyeron APK de esa ABI **sólo para este
gate**. Los APK que se instalan en los teléfonos son `arm64-v8a` y llevan una
sola ABI cada uno; ambos juegos salen del mismo commit.

## Qué se comprobó

| Comprobación | C1 (Vosk) | C3 (Whisper small) |
|---|---|---|
| Instalación | OK | OK |
| Proceso vivo tras arrancar | OK | OK |
| `dlopen` de las librerías propias | `libjnidispatch.so`, `libvosk.so` | `libggml.so`, `libggml-base.so`, `libggml-cpu.so`, `libwhisper_bench.so` |
| `UnsatisfiedLinkError` | ninguno | ninguno |
| ELF incompatible | ninguno | ninguno |
| Crash nativo (`SIGSEGV`, tombstone) | ninguno | ninguno |
| ANR | ninguno | ninguno |
| Modo de compatibilidad de páginas no declarado | no aparece | no aparece |
| Carga del modelo | 60.286.598 B en **905 ms** | 190.085.487 B en **808 ms** |
| Transcripción ejecutada | sí | sí |

Los `dlopen failed` que aparecen en el log del emulador son de
`DevicePersonalizationPrebuiltPixel2021` buscando `libtextclassifier3_jni_agsa.so`,
un componente del sistema. No pertenecen a estos procesos y están antes de
instalar nada.

## Lo que la ejecución encontró, y la estática no podía

### C1 sobre silencio: `noMatch`

El emulador no tiene micrófono con señal: la captura son 4692 ms de silencio.
Vosk procesó ese audio y devolvió **`noMatch`**, sin texto. Es el
comportamiento que el guardrail exige: ausencia de habla no produce una
afirmación.

### C3 sobre silencio: `[MÚSICA]`

Con 5177 ms del mismo silencio, `ggml-small-q5_1` devolvió **`[MÚSICA]`**.

Es `RISK-026` otra vez —el motivo por el que `ADR-002` eligió Android sobre
Whisper— y **el modelo `small` no lo arregla**. Es el hallazgo más importante de
esta construcción y hay que tenerlo delante al leer cualquier comparación
posterior de exactitud: un motor que afirma texto que nadie dijo puede afirmar
un producto o un monto sobre ruido de campo.

En la primera ejecución el banco lo mostró como resultado final **sin ninguna
advertencia**. El motor sí lo había detectado y lo marcaba como
`possibleHallucination`, pero el aviso se perdía entre Kotlin y Dart. Corregido:
ahora la pantalla lo señala y la marca viaja en el resultado exportado, que es
donde se cuenta el guardrail. Ver `16k-04` (sin aviso) y `16k-05` (con aviso).

### C3 en carga fría: se agota el plazo de sesión

La primera ejecución tras instalar copia el modelo de 190 MB desde los assets,
lo carga y después infiere. En este emulador eso superó el tope de 60 segundos
de la sesión y el puerto respondió `timeout · max-duration`, soltando el
micrófono.

Es el comportamiento correcto —el plazo existe para que un motor colgado no se
quede con el micrófono— y **no es una medición del teléfono**: el emulador es
`x86_64` por software. Queda anotado como algo a vigilar en el aparato real,
donde la carga fría de C3 puede acercarse al tope si el teléfono es lento.

## Lo que este gate NO dice

- **No mide rendimiento.** En el emulador, C3 tardó 45.689 ms en resolver 3176 ms
  de audio. Ese número describe una máquina virtual, no un teléfono, y **no debe
  copiarse a ninguna tabla de resultados**. El factor de tiempo real de `ADR-004`
  se mide en el POCO y en el HONOR, y sigue `NOT_MEASURED`.
- **No mide exactitud.** No se dictó ninguna frase: no hay micrófono con voz.
- **No cubre C4.** El híbrido se probará en este mismo entorno cuando exista.
- **No sustituye la prueba física.** Los dos teléfonos obligatorios tienen
  páginas de 4 KB; este gate cubre lo que ellos no pueden cubrir, y al revés.

## Cómo repetirlo

```bash
emulator -avd Pixel_8 -no-snapshot-load -no-boot-anim -gpu swiftshader_indirect &
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell getconf PAGE_SIZE          # debe decir 16384

cd benchmark/voice_benchmark
flutter build apk --release --flavor vosk         --target-platform android-x64 \
  --dart-define=BENCH_COMMIT=$(git rev-parse --short HEAD)
flutter build apk --release --flavor whisperSmall --target-platform android-x64 \
  --dart-define=BENCH_COMMIT=$(git rev-parse --short HEAD)

adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-vosk-release.apk
adb -s emulator-5554 shell pm grant com.comunidad.agro.voicebench.vosk \
  android.permission.RECORD_AUDIO
```

Después: elegir el corpus híbrido, grabar, detener, y comprobar en
`adb logcat` que no aparecen `UnsatisfiedLinkError`, `FATAL EXCEPTION`,
`SIGSEGV` ni `ANR in com.comunidad`.
