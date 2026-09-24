# F02 — Evidencia física de identidad de instalación

## Identidad de la ejecución

| Elemento | Resultado |
|---|---|
| Fecha | 2026-09-24 |
| Mobile HEAD probado | `32096fa69530b45150c94669787d213e428aef00` |
| Build | APK debug de la PR #61 |
| Dispositivo | Xiaomi POCO X5 Pro 5G |
| Android / API | Android 12 / API 31 |
| Arquitectura | ARM64 (`arm64-v8a`) |
| ADB serial | No registrado |

No se registró UUID raw, IMEI, Android ID, MAC ni ningún identificador único del teléfono.

## Gates previos

- `flutter pub get`: PASS.
- `flutter analyze`: PASS, sin issues.
- `flutter test`: PASS, 519/519.
- `flutter build apk --debug`: PASS.
- `git diff --check`: PASS.
- CI de la PR #61: PASS.

## Resultados A–F

| Caso | Resultado | Evidencia |
|---|---|---|
| A — instalación limpia | PASS | La app inició y creó un UUID v4 canónico lowercase con versión y variante válidas. |
| B — force-stop | PASS | Después de force-stop y reapertura, `hash(A2) == hash(A)`. |
| C — reinicio | PASS | Se esperó `sys.boot_completed=1`; después del reinicio, `hash(A3) == hash(A)`. |
| D — backup Agrocuentas | PASS | Export y restore reales desde la UI; se creó copia `.previo-*` y `hash(after_restore) == hash(A)`. |
| E — reinstalación | PASS | El package fue eliminado, reinstalado desde la misma APK y produjo UUID v4 B con `hash(B) != hash(A)`. |
| F — privacidad | PASS | Sin APIs de hardware, networking F02-B ni exposición del UUID en logcat/AppLog. |

## Comparaciones seudónimas

- `SHA-256(A)`: `d39c2b94acbeeb9b90e8b7423f64e884bcfb4ef71964207b5baccddd64f201a7`.
- `SHA-256(A2)`: `d39c2b94acbeeb9b90e8b7423f64e884bcfb4ef71964207b5baccddd64f201a7`.
- `SHA-256(A3)`: `d39c2b94acbeeb9b90e8b7423f64e884bcfb4ef71964207b5baccddd64f201a7`.
- `SHA-256(after_restore)`: `d39c2b94acbeeb9b90e8b7423f64e884bcfb4ef71964207b5baccddd64f201a7`.
- `SHA-256(B)`: `b62075b6ee833a36cc8827f293a6702c17fed7d0eddba8a57a7f7d7512516b5a`.

Los hashes se usan únicamente para igualdad/desigualdad; no permiten que la aplicación trate el clientId
como secreto, autenticador ni autoridad.

## Backup y ubicación

- Ruta verificada mediante `run-as`: `no_backup/installation_identity/client_id`.
- No existe `client_id` bajo `files/`, `databases/` ni `shared_prefs/`.
- `ANDROID_SYSTEM_BACKUP_EXCLUDED = VERIFIED_ON_DEVICE` por ubicación física bajo `no_backup`.
- El restore produjo `databases/agroquimicos_v2.db.previo-*`, confirmando la ejecución real del flujo.
- El `.agrobackup` quedó en el directorio externo privado de la aplicación. Android/FUSE permitió
  enumerarlo, pero bloqueó su lectura directa por `adb pull`/`run-as unzip`; por ello la inspección física
  de entradas se registra como `NOT_READABLE_VIA_ADB`, no como PASS inventado.
- La suite focal 11/11 inspecciona el contenedor real y confirma ausencia de `client_id`, temporales,
  `installation_identity` y UUID raw; el restore automatizado conserva la identidad actual.

## Privacidad y permisos

- No hay uso de IMEI, `ANDROID_ID`, serial, MAC, advertising ID, `TelephonyManager` ni `WifiInfo`.
- La única coincidencia textual de esos nombres es el comentario que prohíbe su uso.
- El diff F02-B no añade Dio, Retrofit, `package:http`, `HttpClient` ni permiso `INTERNET`.
- APK release: sin permiso `INTERNET`.
- APK debug: `INTERNET` proviene del tooling Flutter; F02-B no implementa transporte.
- UUID raw ausente de logcat y del log local de la aplicación.
- `CORRUPTION_DEVICE = NOT_MEASURED`; la cobertura automatizada preserva el archivo corrupto, evita
  regeneración silenciosa y permite la operación local.

## Comandos relevantes

```text
adb uninstall com.comunidad.agro.agroquimicos
adb install build/app/outputs/flutter-apk/app-debug.apk
adb shell run-as com.comunidad.agro.agroquimicos cat no_backup/installation_identity/client_id
adb shell am force-stop com.comunidad.agro.agroquimicos
adb reboot
adb wait-for-device
adb shell getprop sys.boot_completed
```

La salida raw de `cat` sólo se procesó en memoria para validación UUID/SHA-256 y nunca se incluyó en esta
evidencia.

## Desviaciones y riesgos residuales

1. MIUI rechazó inyección de eventos ADB (`INJECT_EVENTS`); el propietario operó manualmente export y
   restore desde la UI. ADB verificó antes y después los hashes y la copia de seguridad previa.
2. La inspección física interna del ZIP quedó limitada por FUSE; se conserva la prueba automatizada del
   contenedor como evidencia complementaria, sin afirmar una lectura ADB inexistente.
3. El registro remoto Mobile→Central permanece `NOT_IMPLEMENTED_BY_DESIGN`; corresponde a la futura capa
   de autenticación/transporte, no a esta validación DEVICE.
4. La PR #8 de voz modifica también `MainActivity.kt`; el conflicto Git futuro es conocido y resoluble.

DEVICE =
PASS
