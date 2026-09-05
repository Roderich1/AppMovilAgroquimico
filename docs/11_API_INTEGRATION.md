# 11 — API e integración de red

## Conclusión

**Esta capacidad no fue encontrada en la implementación actual.**

La aplicación **no realiza ninguna comunicación de red**. No hay base URLs, ni clientes
HTTP, ni interceptores, ni endpoints, ni serialización JSON, ni manejo de tokens.

## Evidencia de la ausencia

Verificaciones realizadas sobre el repositorio completo:

| Verificación | Resultado |
|---|---|
| Dependencias HTTP en `pubspec.yaml` (`http`, `dio`, `chopper`, `retrofit`, `graphql`) | **Ninguna** |
| Dependencias de backend (`firebase_*`, `supabase`, `appwrite`, `amplify`) | **Ninguna** |
| `import 'dart:io'` usado para `HttpClient` | No: solo para `File`, `Directory`, `Platform` |
| `Uri.parse` / `Uri.https` en `lib/` | Ninguna ocurrencia |
| `WebSocket` / `EventSource` | Ninguna ocurrencia |
| WebView (`webview_flutter`) | Sin dependencia ni uso |
| `<uses-permission android:name="android.permission.INTERNET"/>` en `main/AndroidManifest.xml` | **Ausente** |
| Permiso INTERNET en `debug/` y `profile/AndroidManifest.xml` | Presente, pero es el que añade la propia herramienta Flutter para *hot reload*; **no llega a la build de release** |
| `NSAppTransportSecurity` en `Info.plist` | Ausente (no se necesita) |
| Archivos `.env`, `config.json`, `environment.dart` | **No existen** |
| Flavors / build variants con URLs distintas | **No existen** |
| Serialización (`json_serializable`, `freezed`, `dart:convert` para API) | **Ninguna** |

La ausencia del permiso `INTERNET` en el manifiesto de `main` es la prueba más concluyente:
**una build de release de esta app no puede abrir un socket de red aunque quisiera.**

## Qué sustituye a la capa de red

El equivalente funcional de una API en este proyecto es `AgroRepository`
(`lib/data/agro_repository.dart`), que expone ~60 métodos públicos contra SQLite local.
Su catálogo completo está en [28_SYSTEM_MAP](28_SYSTEM_MAP.md).

Si en el futuro se añade un backend, ese repositorio es el punto de inserción natural: hoy
no tiene interfaz abstracta, por lo que habría que extraer una primero. Registrado en
[29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md).

## Integraciones externas que sí existen (no de red)

| Integración | Mecanismo | Archivo |
|---|---|---|
| Cámara del dispositivo | `image_picker` → intent / `UIImagePickerController` nativos | `purchase_form_screen.dart` |
| Galería de fotos | `image_picker` | `purchase_form_screen.dart` |
| Sistema de archivos | `dart:io` + `path_provider` | `agro_repository.dart` (`storeInvoiceImage`, `exportBackup`) |
| SQLite | `sqflite` / `sqflite_common_ffi` | `app_database.dart` |

Detalle en [13_LOCAL_STORAGE](13_LOCAL_STORAGE.md) y [18_PERMISSIONS](18_PERMISSIONS.md).

## Implicaciones

1. **No hay secretos de API que proteger** — no hay claves, tokens ni credenciales de
   servicio en el repositorio. Confirmado en [23_SECURITY_AUDIT](23_SECURITY_AUDIT.md).
2. **No hay superficie de ataque de red**: ni TLS mal configurado, ni *pinning* de
   certificados, ni inyección por respuesta del servidor.
3. **No hay multi-dispositivo**: cada instalación es una isla de datos. Ver
   [14_OFFLINE_AND_SYNC](14_OFFLINE_AND_SYNC.md).
4. **No hay respaldo remoto**: la única copia de seguridad es manual y local
   (`exportBackup`). Este es el mayor riesgo operativo del producto.
