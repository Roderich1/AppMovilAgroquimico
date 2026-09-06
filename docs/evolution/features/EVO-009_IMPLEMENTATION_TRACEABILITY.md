# EVO-009 — Trazabilidad de implementación

## Identidad

| Campo | Valor |
|---|---|
| Feature | `EVO-009` — captura, transcripción continua y vista previa editable |
| Etapa | `EVOLUTION-3`, fase 1 |
| Estado | `IN_PROGRESS` |
| Rama | `evolution/evo-009-safe-transcription` |
| SHA base (`origin/main`) | `ff38c48a2b26b2c9a147b689fc4eeca1a9ec76e0` |
| Motor | Android `SpeechRecognizer` (`ADR-002` `Accepted`) |
| Whisper | **No distribuido.** Sigue siendo reserva medida en `benchmark/` |

`EVO-003` es diagnóstico local exportable y **no** tiene relación con esto.

## Qué se construyó

```text
VoiceCaptureScreen                 lib/voice/ui/
    ↓
VoiceSessionController             lib/voice/session/
    ↓
SpeechTranscriptionPort            lib/voice/port/
    ↓
AndroidSpeechTranscriptionAdapter  lib/voice/port/
    ↓
MethodChannel / EventChannel       agro.voice/speech · agro.voice/speech_events
    ↓
VoiceSpeechBridge + VoiceSpeechEngine   android/.../agroquimicos/
    ↓
android.speech.SpeechRecognizer
```

### Una decisión de diseño que conviene entender

El puerto modela **un turno de escucha**, no la sesión del usuario.
`SpeechRecognizer` cierra la escucha por su cuenta al detectar silencio; si el
puerto fingiera una sesión continua, cada adaptador futuro tendría que
reimplementar la continuidad y volverían a divergir el fake y el dispositivo
(`RISK-007`). Así, el puerto emite `TranscriptionTurnEnded` y **la sesión decide**
si reabre. La continuidad está en un solo sitio y se prueba sin teléfono.

## Archivos

### Nuevos — aplicación

| Archivo | Qué es |
|---|---|
| `lib/voice/port/speech_transcription_port.dart` | Contrato: estados, eventos tipados, disponibilidad y petición. Sin Flutter, sin SQLite |
| `lib/voice/port/android_speech_transcription_adapter.dart` | Adaptador sobre los canales. Garantiza un único cierre por turno, incluso si el sistema enmudece |
| `lib/voice/session/voice_session_state.dart` | Los catorce estados, la evidencia de modo sin conexión y la fotografía inmutable de la sesión |
| `lib/voice/session/voice_session_controller.dart` | Continuidad, acumulación de segmentos, edición manual, ciclo de vida y entrega |
| `lib/voice/session/voice_locale_policy.dart` | Lista de fallback de español y cuándo se avanza |
| `lib/voice/session/voice_continuity_policy.dart` | Máximos, backoff acotado y topes de sesión |
| `lib/voice/ui/voice_capture_screen.dart` | La pantalla |
| `lib/voice/voice_providers.dart` | Fábrica del puerto, sustituible en pruebas |

### Nuevos — Android

| Archivo | Qué es |
|---|---|
| `android/app/src/main/kotlin/.../VoiceSpeechEngine.kt` | `SpeechRecognizer`, disponibilidad, modo avión del sistema y mapeo de errores |
| `android/app/src/main/kotlin/.../VoiceSpeechBridge.kt` | Canales, permiso contextual, ajustes del sistema y liberación en `onPause` |

### Nuevos — pruebas y documentación

| Archivo | Qué es |
|---|---|
| `test/voice/support/fake_speech_transcription_port.dart` | Fake determinista guionizable |
| `test/voice/speech_transcription_port_contract_test.dart` | Contrato del puerto |
| `test/voice/voice_session_controller_test.dart` | Máquina de estados y continuidad |
| `test/voice/voice_locale_policy_test.dart` | La lista de idiomas exacta |
| `test/voice/voice_capture_screen_test.dart` | Pantalla, entrada desde Operaciones y accesibilidad |
| `test/voice/voice_architecture_guard_test.dart` | Guardas estructurales |
| `EVOLUTION-3_OWNER_DEVICE_TEST_PLAN_EVO-009.md` | Prueba en teléfono para el propietario |

### Modificados

| Archivo | Cambio |
|---|---|
| `lib/app.dart` | Ruta `/voz` dentro del `ShellRoute` |
| `lib/presentation/app_shell.dart` | `/voz` como subdestino de Operaciones y sin FAB global |
| `lib/presentation/screens/operations_screen.dart` | Tarjeta `Ingresar datos por voz` |
| `android/app/src/main/AndroidManifest.xml` | `RECORD_AUDIO` y `queries` de `RecognitionService` |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Enchufa el puente y reenvía el permiso |

**No se tocó**: schema, migraciones, FIFO, dinero, cuentas, `confirmPurchase()`,
`confirmApplication()`, `addAccountPayment()`, backup, `.agrobackup`, el tag
estable ni `pubspec.yaml`. **Ninguna dependencia nueva.**

## Requisitos → código → prueba

| Requisito | Dónde se cumple | Prueba |
|---|---|---|
| `REQ-001` toda transcripción pasa por vista previa editable | El texto de sesión es un `TextField` sin modo de sólo lectura | «el texto dictado se puede corregir a mano» |
| `REQ-002` entregar no llama repositorios ni SQLite | `deliver()` devuelve un `VoiceSessionText` | Guardas + «entrega el texto de sesión y no ejecuta ninguna operación» |
| `REQ-003` descartar borra y libera | `discard()` reinicia la fotografía y cancela el turno | «descartar borra el texto, libera el micrófono y deja cancelled» |
| `REQ-004` permiso contextual y denegación temporal/permanente | El puente pide al tocar; dos estados distintos | «denegación temporal…», «denegación permanente ofrece los ajustes» |
| `REQ-005` salir/background/interrupción liberan | `handleAppPaused`, `dispose` y `MainActivity.onPause` | «pasar a segundo plano…», «navegar atrás libera el micrófono» |
| `REQ-006` audio no persistido | El audio no cruza a Dart | Guarda: el subsistema no puede escribir en disco |
| `REQ-007` transcripción en memoria | Vive en la fotografía y muere con la pantalla | Guardas + prueba de pantalla |
| `REQ-008` locale visible y sin prometer offline | `_LocalePanel` y `_OfflinePanel` | «muestra siempre el idioma pedido y el utilizado», «no promete funcionar sin conexión sin haberlo comprobado» |
| `REQ-009` plugin aislado tras un puerto testeable | Puerto + fake + adaptador | Contrato del puerto (fake y adaptador comparten contrato) |
| `REQ-010` un error no deja sesión falsamente aceptada | El error fija estado y conserva el texto; nunca `delivered` | «el texto ya acumulado sobrevive a un fallo fatal» |
| `REQ-011` distinguir transcripción de operación | Aviso previo y recuadro de entrega | «usar este texto entrega y avisa que no registró nada» |
| `REQ-012` acumulación y continuar sin reiniciar | Segmentos acumulados + reapertura de turno | «tras un segmento la sesión vuelve a escuchar sin perder texto» |
| `REQ-013` se pide reconocimiento sin conexión | `preferOffline: true` en cada turno | «pedir offline no se muestra como offline comprobado» |
| `REQ-014` no confiar en las APIs: intentar y observar | Recorrido de idiomas intentando; `localeSupportKnown` separado | «recorre la lista de fallback y publica el que funciona» |
| `REQ-015` mostrar solicitado, utilizado, offline, modelo y si es recuperable | `_LocalePanel`, `_OfflinePanel`, `_ErrorPanel` | Pruebas de idioma y de errores accionables |
| `REQ-016` no prometer `es-BO`; mejor español con fallback visible | `VoiceLocalePolicy` | `voice_locale_policy_test.dart` completo |
| `REQ-017` sin reconocimiento: no bloquea, no reintenta sin fin, no descarga | `VoiceContinuityPolicy` + textos accionables | «sin reconocedor no bloquea la pantalla», «ERROR_CLIENT repetido no reintenta indefinidamente» |
| `REQ-018` la voz nunca confirma operaciones | No hay ninguna operación que confirmar | Guardas arquitectónicas |
| `REQ-019` los parciales son sólo texto provisional | `partialText` separado, nunca se acumula solo | «el parcial se muestra aparte y no entra en el texto de sesión» |
| `REQ-020` el texto pasará después por `EVO-010` | `deliver()` produce sólo texto | — (`EVO-010` no iniciada) |

## Instrucciones del encargo → dónde están

| Pedido | Cumplido en |
|---|---|
| Catorce estados tipados, sin booleanos contradictorios | `VoiceSessionStatus`; `microphoneMayBeOpen` e `isTransition` derivan del estado |
| Eventos tipados: parcial, segmento, sesión final, `noMatch`, timeout, cancelación, error, locale, disponibilidad | Jerarquía sellada `TranscriptionEvent` |
| Backoff acotado y máximo de reintentos | `VoiceContinuityPolicy`, probado con `fake_async` |
| No duplicar el último segmento | Un solo segmento por turno (`_turnSegmentConsumed`) |
| No perder correcciones manuales | Regla de añadir al final; deshacer se desactiva al editar |
| Lista de fallback documentada y probada | Spec + `voice_locale_policy_test.dart` |
| Diferenciar los cinco estados del modo sin conexión | `VoiceOfflineEvidence` y `_OfflinePanel` |
| Sólo `RECORD_AUDIO`; sin `INTERNET` | Manifiesto + guarda que enumera los permisos |
| Guardas que fallen si Voice toca SQLite, compras, pagos, FIFO o backup | `voice_architecture_guard_test.dart` |

## Una precisión sobre el permiso de Internet

La build **de release** no declara `INTERNET`. Verificado sobre el binario, no
sobre el código:

```bash
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
# package: com.comunidad.agro.agroquimicos
# uses-permission: name='android.permission.RECORD_AUDIO'
```

El APK **debug** sí lo declara, porque `android/app/src/debug/AndroidManifest.xml`
—de la plantilla de Flutter, anterior a `EVO-009` y no modificado aquí— lo añade
para hot reload. Como la prueba en teléfono se hace con el APK debug, quien la
ejecute verá ese permiso; el plan de prueba lo advierte para que no se lea como
que la aplicación usa la red.

## Estado de verificación

| Gate | Estado |
|---|---|
| `dart format` | Verde |
| `flutter analyze` | Verde, sin avisos |
| `flutter test` | Verde |
| `flutter build apk --release` | Verde |
| CI sobre el SHA final | Ver informe de la rama |
| **Dispositivo físico** | **Pendiente**: `EVOLUTION-3_OWNER_DEVICE_TEST_PLAN_EVO-009.md` |
| **Revisión del propietario** | **Pendiente** |
| Pixel 8 / API 36 | `WAIVED_BY_OWNER — residual compatibility risk accepted` |

`EVO-009` **no puede** declararse `VERIFIED` hasta que las dos filas pendientes
tengan evidencia real.

## Lo que esta implementación no resuelve

- **Los nombres de producto siguen sin reconocerse.** `ADR-002` midió 5/17 y esta
  feature no cambia el motor. Se resuelve en `EVO-010` contra el catálogo local.
- **Las cantidades pueden variar entre tomas** (`RISK-027`): la misma frase dio
  `12` y `dos`. Por eso el texto es editable y no precarga nada.
- **El comportamiento sin conexión no es universal.** Depende del dispositivo,
  del fabricante y de los modelos instalados. La pantalla informa lo que observa
  en cada aparato en vez de generalizar.
- **API 36 sigue sin evidencia.**

## Riesgos abiertos

| Riesgo | Estado |
|---|---|
| `RISK-023` idioma y offline | Mitigado con recorrido y fallback visible; residual: la lista puede no cubrir un OEM concreto |
| `RISK-025` productos no reconocidos | **Abierto por diseño**: es alcance de `EVO-010` |
| `RISK-028` API 36 sin probar | Abierto, aceptado por el propietario |
| `RISK-029` bucle de reapertura del micrófono | Mitigado y probado; falta confirmarlo en teléfono |
| `RISK-030` una corrección manual se sobrescribe | Mitigado por la regla de añadir al final |
