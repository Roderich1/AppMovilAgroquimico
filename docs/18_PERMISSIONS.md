# 18 — Permisos y capacidades del dispositivo

## Resumen

La aplicación usa **una sola capacidad del dispositivo**: la captura de imágenes (cámara y
galería) para las fotos de factura. No hay gestión explícita de permisos: se delega
íntegramente en el plugin `image_picker`.

**No existe `permission_handler`** ni ninguna dependencia equivalente. No hay ninguna
solicitud de permiso escrita en código Dart.

## Android

### Permisos declarados por la aplicación

`android/app/src/main/AndroidManifest.xml` — **ninguno**.

El manifiesto no contiene un solo elemento `<uses-permission>`. Es el manifiesto de la
plantilla de Flutter con el `activity`, el `meta-data` de `flutterEmbedding` y el bloque
`<queries>` de `PROCESS_TEXT`.

`android/app/src/debug/AndroidManifest.xml` y `.../profile/AndroidManifest.xml` declaran
`android.permission.INTERNET`, pero eso lo añade la propia herramienta Flutter para el
*hot reload* y **no llega a la build de release**.

### Qué permisos acaban realmente en el APK

El manifiesto final es el resultado de la **fusión de manifiestos de Gradle**: los plugins
aportan los suyos. `image_picker_android` y `flutter_plugin_android_lifecycle` inyectan lo
que necesitan (típicamente un `FileProvider` y, según versión y `targetSdk`, permisos de
lectura de medios).

> ⚠️ `NO CONFIRMADO EN EL REPOSITORIO`: el conjunto exacto de permisos del APK final **no
> puede determinarse leyendo el código fuente**, porque depende de la fusión de manifiestos.
> Para verificarlo hay que compilar y ejecutar:
>
> ```sh
> flutter build apk --debug
> # y después, con las build-tools de Android:
> aapt dump permissions build/app/outputs/flutter-apk/app-debug.apk
> ```
>
> Alternativamente, inspeccionar el manifiesto fusionado en
> `build/app/intermediates/merged_manifests/`.

### Nota técnica sobre `CAMERA` en Android

Hay una particularidad de la plataforma que conviene registrar, porque la ausencia del
permiso en el manifiesto **no es necesariamente un defecto**:

- `image_picker` con `ImageSource.camera` lanza un `Intent` a la aplicación de cámara del
  sistema. Ese flujo **no requiere** el permiso `CAMERA`.
- Sin embargo, si una aplicación **declara** `CAMERA` en su manifiesto, Android **exige**
  que se conceda en tiempo de ejecución antes de permitir ese mismo `Intent`.

Es decir: **no declarar `CAMERA` es el camino más simple y funcional** para este caso de
uso. Si alguna vez se añade ese permiso al manifiesto por otro motivo, habrá que añadir
también la solicitud en tiempo de ejecución, o la cámara dejará de funcionar.

### Almacenamiento

- Las fotos se copian al **directorio de documentos de la app**
  (`getApplicationDocumentsDirectory`), que está dentro del sandbox: **no requiere permiso**.
- El backup se escribe en `getDownloadsDirectory()`. En Android moderno,
  `path_provider` resuelve esto a un directorio accesible sin permiso de almacenamiento
  heredado. `NO CONFIRMADO EN EL REPOSITORIO` para versiones antiguas de Android: el
  comportamiento exacto depende de `targetSdk`, que este proyecto **no fija**
  (usa `flutter.targetSdkVersion`).

### `android:allowBackup`

El manifiesto **no declara** `android:allowBackup`, por lo que se aplica el valor por
defecto de la plataforma (históricamente `true`). Esto significa que la base de datos sin
cifrar podría incluirse en copias de seguridad automáticas de Android. Registrado en
[23_SECURITY_AUDIT](23_SECURITY_AUDIT.md).

## iOS

`ios/Runner/Info.plist` declara **dos** descripciones de uso, correctamente redactadas en
español y explicando el propósito real:

```xml
<key>NSCameraUsageDescription</key>
<string>Agrocuentas usa la cámara para guardar fotografías de facturas.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Agrocuentas permite seleccionar fotografías de facturas.</string>
```

Ambas son **obligatorias** para pasar la revisión de App Store cuando se usa
`image_picker`, y ambas están presentes y bien justificadas. 🟢

### Claves de permiso ausentes (correctamente)

`NSPhotoLibraryAddUsageDescription`, `NSLocationWhenInUseUsageDescription`,
`NSMicrophoneUsageDescription`, `NSContactsUsageDescription`,
`NSBluetoothAlwaysUsageDescription`, `NSFaceIDUsageDescription`: **ninguna está declarada,
y ninguna hace falta**. La app no usa esas capacidades.

### Otras claves relevantes de `Info.plist`

| Clave | Valor | Comentario |
|---|---|---|
| `UISupportedInterfaceOrientations` | Portrait + Landscape L/R | Permite rotación en iPhone |
| `UISupportedInterfaceOrientations~ipad` | Las cuatro | Rotación completa en iPad |
| `CADisableMinimumFrameDurationOnPhone` | `true` | Habilita ProMotion (120 Hz) |
| `UIApplicationSupportsIndirectInputEvents` | `true` | Soporte de puntero/trackpad |
| `CFBundleDisplayName` | `Agroquimicos` | Ver inconsistencia de naming en [01](01_PROJECT_OVERVIEW.md) |

## Matriz permiso ↔ funcionalidad

| Capacidad | ¿Se usa? | Funcionalidad que la requiere | Declaración | Punto en el código |
|---|:--:|---|---|---|
| **Cámara** | ✅ | F-05: foto de factura | iOS: `NSCameraUsageDescription`. Android: ninguna (correcto, ver arriba) | `purchase_form_screen.dart` → `_pickImage(ImageSource.camera)` |
| **Galería / fotos** | ✅ | F-05: foto de factura | iOS: `NSPhotoLibraryUsageDescription`. Android: por fusión del plugin | `purchase_form_screen.dart` → `_pickImage(ImageSource.gallery)` |
| **Almacenamiento (escritura)** | ✅ | F-05 (copia interna) y F-16 (backup) | Ninguna necesaria: sandbox + `path_provider` | `storeInvoiceImage`, `exportBackup` |
| **Internet** | ❌ | — | No declarado en release | — |
| **Ubicación / GPS** | ❌ | — | — | `farms.location` es un `TEXT` que **nunca se escribe** |
| **Micrófono** | ❌ | — | — | — |
| **Bluetooth** | ❌ | — | — | — |
| **Notificaciones** | ❌ | — | — | Ver [19](19_NOTIFICATIONS.md) |
| **Biometría** | ❌ | — | — | Ver [12](12_AUTHENTICATION.md) |
| **Contactos** | ❌ | — | — | `persons.phone` **nunca se escribe** desde la UI |
| **Calendario** | ❌ | — | — | — |
| **Sensores** | ❌ | — | — | — |

## Manejo de la denegación de permisos

**No hay manejo explícito.** El único tratamiento es un `try/catch` genérico:

```dart
Future<void> _pickImage(ImageSource source) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: source, imageQuality: 82, maxWidth: 1800);
    if (!mounted || picked == null) return;
    setState(() { invoiceImage = picked; dirty = true; });
  } catch (error) {
    if (mounted)
      showError(context, 'No se pudo adjuntar la factura. Revise los permisos.');
  }
}
```

**Fortalezas:**
- No revienta si el usuario deniega.
- El mensaje **menciona los permisos**, orientando al usuario.
- Distingue correctamente `picked == null` (el usuario canceló → silencio) de una excepción
  (→ mensaje).
- La compra puede completarse **sin foto**: la funcionalidad es opcional y no bloquea.

**Debilidades:**
- No distingue "permiso denegado" de "denegado permanentemente" ni de otros fallos.
- No ofrece un acceso directo a los ajustes del sistema (requeriría `permission_handler` o
  `app_settings`).
- No comprueba el estado del permiso **antes** de intentar; solo reacciona al fallo.

Para el alcance de este producto — una función auxiliar y opcional — el tratamiento es
**proporcionado y suficiente**. No se recomienda añadir `permission_handler` salvo que
aparezcan más capacidades del dispositivo.

## Riesgo de privacidad

Las fotos de factura pueden contener datos comerciales (proveedor, importes, identificación
fiscal). Se almacenan **sin cifrar** en el directorio de documentos de la app. En un
dispositivo sin root/jailbreak están aisladas del resto de aplicaciones; en uno comprometido,
o mediante una copia de seguridad de Android, serían accesibles.

Valorado en [23_SECURITY_AUDIT](23_SECURITY_AUDIT.md).
