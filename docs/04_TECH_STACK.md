# 04 — Stack tecnológico

Todo lo de esta página está confirmado contra `pubspec.yaml`, `pubspec.lock`,
`.flutter-plugins-dependencies` y el uso real en el código (`import` + llamada).

## Núcleo

| Elemento | Valor confirmado | Fuente |
|---|---|---|
| Lenguaje | Dart | — |
| Restricción de SDK Dart | `^3.13.2` (es decir `>=3.13.2 <4.0.0`) | `pubspec.yaml`, `pubspec.lock` |
| Framework | Flutter | — |
| Flutter mínimo resuelto | `>=3.44.0` | `pubspec.lock` (`sdks:`) |
| Flutter usado en esta auditoría | **3.47.2**, canal `stable`, revisión `d3b14c8769` | `flutter --version` |
| Revisión declarada en `.metadata` | `d3b14c876900e553bc736ca19295fc09e3853e8e` | `.metadata` |
| Diseño | Material 3 (`useMaterial3: true`) | `lib/app.dart` |
| Arquitectura | 3 capas propias (ver [02](02_ARCHITECTURE.md)) — **no** Clean/MVVM/BLoC | Análisis de código |
| Base de datos | SQLite, esquema versión **4** | `lib/data/app_database.dart` |
| Gestión de estado | Riverpod para DI + `FutureBuilder`/`setState` para datos | Ver [09](09_STATE_MANAGEMENT.md) |
| Navegación | `go_router` declarativo | `lib/app.dart` |
| Networking | **Ninguno** | Ver [11](11_API_INTEGRATION.md) |
| Serialización | **Ninguna**; se usa `Map<String,Object?>` de sqflite | Ver [02](02_ARCHITECTURE.md) |
| Autenticación | **Ninguna** | Ver [12](12_AUTHENTICATION.md) |
| Mapas / geolocalización | **Ninguno** | Sin dependencias ni permisos |
| Cámara | `image_picker` (foto de factura) | `purchase_form_screen.dart` |
| Notificaciones | **Ninguna** | Ver [19](19_NOTIFICATIONS.md) |
| Analytics / crash reporting | **Ninguno** | Sin dependencias |
| Logging | **Ninguno** (ni `print`, ni `logger`, ni `dart:developer`) | Búsqueda en `lib/` |
| Build system | Gradle Kotlin DSL (Android), Xcode (iOS) | `android/`, `ios/` |
| CI/CD | **No existe** (`.github/` ausente, sin `.gitlab-ci.yml`, sin `Jenkinsfile`) | Raíz del repo |
| Servicios cloud | **Ninguno** | — |
| APIs de terceros | **Ninguna** | — |

## Dependencias de producción

| Paquete | Restricción | Versión resuelta | Responsabilidad | Dónde se usa | ¿Esencial? |
|---|---|---|---|---|---|
| `flutter` | sdk | — | Framework | Todo | Esencial |
| `flutter_riverpod` | `^3.0.3` | **3.4.2** | Inyección de dependencias y acceso al repositorio desde widgets | `app.dart` (3 providers); `ConsumerWidget`/`ConsumerStatefulWidget` en 14 pantallas | **Esencial** |
| `go_router` | `^17.0.1` | **17.5.0** | Router declarativo con `ShellRoute` y parámetros de ruta | `app.dart` (`routerProvider`); `context.go`/`context.push` en 8 pantallas | **Esencial** |
| `sqflite` | `^2.4.2` | **2.4.3** | Motor SQLite en Android/iOS | `app_database.dart` (`mobile.databaseFactory`, `getDatabasesPath`); `agro_repository.dart` (tipos `Database`, `DatabaseExecutor`, `Sqflite.firstIntValue`) | **Esencial** |
| `sqflite_common_ffi` | `^2.4.0+2` | **2.4.2+1** | SQLite vía FFI en Windows/Linux/macOS y en tests | `app_database.dart` (`sqfliteFfiInit`, `databaseFactoryFfi`); **los 13 archivos de test** | **Esencial** (sin él no hay suite de tests) |
| `path` | `^1.9.1` | **1.9.1** | Composición de rutas de archivo | `app_database.dart` (`p.join`); `agro_repository.dart` (`p.join`, `p.extension`) | Esencial |
| `path_provider` | `^2.1.5` | **2.1.6** | Directorios del sistema | `app_database.dart` (`getApplicationSupportDirectory`); `agro_repository.dart` (`getDownloadsDirectory`, `getApplicationDocumentsDirectory`) | **Esencial** (backup y fotos) |
| `intl` | `^0.20.2` | **0.20.3** | Formato de moneda y cantidades en `es_BO` | **Solo** `domain/money.dart` (`NumberFormat`) | Esencial |
| `image_picker` | `^1.2.3` | **1.2.3** | Captura de foto de factura desde cámara o galería | **Solo** `purchase_form_screen.dart` (`ImagePicker().pickImage`) | Opcional a nivel de producto (la compra funciona sin foto), pero está integrada |
| `cupertino_icons` | `^1.0.8` | **1.0.9** | Set de iconos iOS | **Ningún `import` en `lib/`** | **Prescindible** — dependencia de plantilla no utilizada |

### Nota sobre `cupertino_icons`

Búsqueda en `lib/`: no hay ningún `import 'package:cupertino_icons/...'` ni uso de
`CupertinoIcons`. Toda la iconografía usa `Icons.*` de Material. Es una dependencia
heredada de la plantilla `flutter create`.

## Dependencias de desarrollo

| Paquete | Restricción | Resuelta | Responsabilidad | Uso real |
|---|---|---|---|---|
| `flutter_test` | sdk | — | Framework de test y widget testing | Los 13 archivos de `test/` |
| `flutter_lints` | `^6.0.0` | **6.0.0** | Set de lints recomendado | Incluido en `analysis_options.yaml` |
| `fake_async` | `^1.3.3` | **1.3.3** | Control de tiempo virtual en tests | **Ningún `import` en `test/`** — declarada pero no usada |

## Plugins nativos resueltos

De `.flutter-plugins-dependencies` (federados; se resuelven aunque la plataforma no se use):

- `image_picker` + `image_picker_android`, `image_picker_ios`, `image_picker_linux`,
  `image_picker_macos`, `image_picker_windows`, `image_picker_for_web`
- `path_provider` + `path_provider_android`, `path_provider_foundation`,
  `path_provider_linux`, `path_provider_windows`
- `sqflite` + `sqflite_android`, `sqflite_darwin`
- `file_selector_linux`, `file_selector_macos`, `file_selector_windows`
  (dependencias transitivas de `image_picker` en escritorio)
- `flutter_plugin_android_lifecycle` (transitiva de `image_picker_android`)
- `jni`, `jni_flutter` (transitivas)

## Configuración de análisis estático

`analysis_options.yaml` incluye `package:flutter_lints/flutter.yaml` y **desactiva** cuatro
reglas:

```yaml
rules:
  curly_braces_in_flow_control_structures: false
  unnecessary_underscores: false
  use_null_aware_elements: false
  prefer_initializing_formals: false
```

La primera es la más significativa: permite `if (x) return;` sin llaves, patrón que aparece
decenas de veces en el repositorio (`if (snapshot.hasError) return EmptyState(...)`). Es una
elección de estilo consciente, **no un defecto**, pero aumenta el riesgo del clásico bug de
*dangling else* si alguien añade una segunda sentencia. Ver [24](24_CODE_QUALITY_AUDIT.md).

`exclude` cubre `build/`, `android/`, `ios/`, `web/`.

## Toolchain Android

| Elemento | Valor | Fuente |
|---|---|---|
| Plugin | `com.android.application` + `dev.flutter.flutter-gradle-plugin` | `android/app/build.gradle.kts` |
| `namespace` / `applicationId` | `com.comunidad.agro.agroquimicos` | idem |
| `compileSdk` / `minSdk` / `targetSdk` | Delegados a `flutter.*` (no fijados en el proyecto) | idem |
| Java / Kotlin JVM target | **17** | idem |
| Firma de release | `signingConfig = signingConfigs.getByName("debug")` | idem — **hallazgo de seguridad HIGH**, ver [23](23_SECURITY_AUDIT.md) |

## Lo que se buscó y NO se encontró

Verificado por ausencia en `pubspec.yaml`/`pubspec.lock` y por ausencia de `import`:

`dio`, `http`, `retrofit`, `chopper`, `graphql` · `firebase_*`, `supabase`, `appwrite` ·
`shared_preferences`, `flutter_secure_storage`, `hive`, `isar`, `drift`, `objectbox`,
`realm` · `json_serializable`, `freezed`, `built_value` · `get_it`, `injectable`,
`provider`, `bloc`, `flutter_bloc`, `mobx`, `redux` · `permission_handler` ·
`geolocator`, `google_maps_flutter` · `firebase_messaging`, `flutter_local_notifications` ·
`connectivity_plus` · `workmanager` · `mockito`, `mocktail`, `integration_test`,
`golden_toolkit`, `patrol`.

La ausencia de `connectivity_plus` y de cualquier cliente HTTP es la confirmación más
directa de que **el modelo offline no es una estrategia de resiliencia sino la única
modalidad de operación** — ver [14_OFFLINE_AND_SYNC](14_OFFLINE_AND_SYNC.md).
