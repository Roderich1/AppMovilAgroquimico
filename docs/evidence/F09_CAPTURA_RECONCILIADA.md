# F09 — Captura por voz reconciliada con main (EVO-009, PR #8)

- **Origen:** Live. Se reconcilia una rama anterior: los 9 commits del PR #8 (HEAD `534d6b06553ca4eac8d11c07672b9c357371e66e`, de 2026-09-06), aplicados por cherry-pick con `-x`.
- **Fecha real:** 2026-10-17 (America/La_Paz).
- **Base:** Mobile `main` `ce5678f89449453c60c3f1889cd6e973f09f6548`.
- **Rama:** `feat/f09-captura-voz`. **Commit verificado:** `c45f71f3a908c16d6557f6f57b2b2d492dcb983f`.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #8 y #13. GATE-F09 (#17) sigue Pending.

## 1. Qué se reconcilió

| Commit del PR #8 | En esta rama | Cambio en la reconciliación |
|---|---|---|
| `c1d8fbf` puerto y sesión | `87e46dd` | Ninguno |
| `37e3622` adaptador Android | `8f8fe4a` | Conflictos en el manifiesto y en `MainActivity.kt`, resueltos: se conserva `INTERNET` (F03) y los canales de sesión segura e identidad de la instalación, y se añaden el puente de voz y `RECORD_AUDIO`. El mensaje del commit dice que el original afirmaba lo contrario |
| `e47ff27` pantalla | `c12c1f4` | **Sin** la ruta `/voz`, la tarjeta de Operaciones ni el FAB oculto (`app.dart`, `app_shell.dart` y `operations_screen.dart`), que A tiene reservados para F04. La prueba «entrada desde Operaciones» va con esa conexión, en un commit aparte |
| `4198608`, `4181bb4`, `7b7f5af`, `d262010`, `ce4d1bc` y `534d6b0` | `2464e36`, `0d07e51`, `fe0d25f`, `bd4777c`, `6d7abf3` y `3888a28` | Ninguno; se aplicaron sin conflicto |
| — | `c45f71f` | Reconciliación de la afirmación sobre `INTERNET` (§2) |

**No se tocó:** activación, sesión, compuertas de operación, sincronización, respaldos, esquema, migraciones, FIFO, `confirmPurchase()`, `confirmApplication()` ni `pubspec.yaml`.

## 2. La afirmación sobre INTERNET

**Lo que afirmaba el PR #8:**
- Guarda: «NO se declara INTERNET en la build que se distribuye»; los permisos del manifiesto `main` debían ser exactamente `[RECORD_AUDIO]`.
- Documentación: «La build de release no declara `INTERNET`», con la salida de `aapt2` del APK de entonces.

**Por qué ya no es cierto:**
- `INTERNET` entró en el manifiesto `main` con `b3efd0d` (2026-09-28, «feat(f03): add typed Flutter auth HTTP foundation»), después de la base del PR #8 (`ff38c48`).
- La app lo necesita para la activación, la sesión, la sincronización y los respaldos remotos. La voz no puede retirarlo.

**Qué fija ahora la guarda** (`test/voice/voice_architecture_guard_test.dart`):
- release declara exactamente `INTERNET` y `RECORD_AUDIO`, sin `ACCESS_NETWORK_STATE`;
- `lib/voice/` no contiene código de red (guarda del PR #8, se mantiene);
- `VoiceSpeechBridge.kt` y `VoiceSpeechEngine.kt` no usan la red (guarda nueva);
- `debug` y `profile` sólo añaden `INTERNET` (guarda del PR #8, se mantiene).

**Reconocedor del sistema** (decisión pendiente D-F09-7): puede usar la red por su cuenta. La pantalla lo avisa («El sistema podría usar Internet para transcribir») y pregunta antes de cambiar a él. Lo cubre la prueba de pantalla «agotado el español local, se pregunta antes de cambiar», que comprueba ese texto.

**Prueba en rojo:** antes de la reconciliación, sobre `3888a28`, `flutter test test/voice/voice_architecture_guard_test.dart` fallaba en 2 pruebas:
- «se declara RECORD_AUDIO y ningún otro permiso nuevo»: `Expected: ['android.permission.RECORD_AUDIO']`, `Actual: ['android.permission.INTERNET', 'android.permission.RECORD_AUDIO']`;
- «NO se declara INTERNET en la build que se distribuye».

## 3. Resultados sobre `c45f71f`

| Comando | Resultado |
|---|---|
| `flutter pub get` | OK, sin dependencias nuevas |
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (210 archivos) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/voice/` | 176 pasan, 0 fallos |
| `flutter test` (suite completa) | **1249 pasan, 2 omitidas, 0 fallos** (main `ce5678f`: 1073; +176 de voz) |

## 4. Límites

- **Sólo host.** El reconocimiento real exige dictado real en un teléfono; esa prueba la ejecuta la sesión A, con turno, cuando la conexión del shell esté integrada.
- **Antecedente del HONOR:** los defectos 001–005 del PR #8 se midieron en el HONOR JDY-LX3P (Android 16 / API 36) el 2026-09-06. Lo describen los mensajes de `ce4d1bc` y `534d6b0`, pero en `docs/evidence/` no hay archivo de aquella prueba. **No es evidencia de #12.**
- **Sin acceso desde la app:** sin la conexión del shell, la pantalla no se puede abrir todavía.
- **Productos:** se reconocen mal (ADR-002: 5/17). Se tratan en la interpretación contra el catálogo, no en el motor.
- **Pixel 8 / API 36:** `WAIVED_BY_OWNER` (ADR-002), sin cambios.
- **Audio y texto:** no se guardan ni se registran. Los diagnósticos llevan códigos y longitudes, nunca frases.
