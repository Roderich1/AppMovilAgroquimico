# 20 — Configuración y compilación

## Requisitos

| Herramienta | Versión requerida | Fuente |
|---|---|---|
| **Flutter SDK** | `>= 3.44.0` | `pubspec.lock` → `sdks:` |
| **Flutter verificado** | 3.47.2 (stable, rev. `d3b14c8769`) | `flutter --version` durante esta auditoría |
| **Dart SDK** | `>= 3.13.2 < 4.0.0` | `pubspec.yaml` → `environment.sdk: ^3.13.2` |
| **JDK** | **17** | `android/app/build.gradle.kts` → `JavaVersion.VERSION_17`, `JvmTarget.JVM_17` |
| **Android SDK** | `compileSdk`/`minSdk`/`targetSdk` delegados a `flutter.*` | `android/app/build.gradle.kts` |
| **Xcode** | Solo para iOS. `NO CONFIRMADO`: no hay `Podfile`, no se especifica versión | `ios/` |
| **Node.js** | ⬜ No se requiere | — |

No hay Docker, ni `Makefile`, ni scripts de arranque en el repositorio.

## Puesta en marcha (según el README, verificado)

```sh
flutter pub get
flutter run
```

Esto es literalmente todo. **No hay ningún paso de configuración previo**: no hay archivos
`.env` que crear, ni claves de API que obtener, ni servicios que aprovisionar, ni base de
datos que inicializar.

### Por qué no hay variables de entorno

Verificado por ausencia: no existen `.env`, `.env.example`, `config.json`,
`environment.dart`, `flutter_dotenv`, `--dart-define`, `String.fromEnvironment`, ni flavors.

Si se documentara una plantilla de configuración, hoy estaría vacía:

```
# No se requiere ninguna variable de entorno.
# API_KEY=<NO APLICA - la aplicacion no realiza llamadas de red>
```

Es una consecuencia directa de que la app sea offline-only.
Ver [11_API_INTEGRATION](11_API_INTEGRATION.md).

## Comandos de verificación

Los del README, **ejecutados durante esta auditoría** con su resultado real:

| Comando | Propósito | Resultado obtenido |
|---|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | El formato está aplicado | ✅ **39 archivos, 0 modificados** |
| `flutter analyze` | Sin errores ni avisos de lint | ✅ **No issues found!** (1,1 s) |
| `flutter test` | Suite completa | ✅ **44 tests, todos en verde** (13 s) |
| `flutter build apk --debug` | La app compila para Android | No ejecutado en esta auditoría |

El proyecto llega a la auditoría en un estado **limpio**: sin avisos del analizador, con el
formato canónico aplicado y con la suite verde. Es un punto de partida sólido y poco común.

## Compilación

### Android

```sh
flutter build apk --debug      # → build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release
flutter build appbundle        # → build/app/outputs/bundle/release/app-release.aab
```

Configuración en `android/app/build.gradle.kts`:

```kotlin
android {
    namespace = "com.comunidad.agro.agroquimicos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17
                     targetCompatibility = JavaVersion.VERSION_17 }
    defaultConfig {
        applicationId = "com.comunidad.agro.agroquimicos"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release { signingConfig = signingConfigs.getByName("debug") }   // ⚠️
    }
}
```

> ### 🔴 La build de release usa la clave de depuración
>
> ```kotlin
> // TODO: Add your own signing config for the release build.
> // Signing with the debug keys for now, so `flutter run --release` works.
> signingConfig = signingConfigs.getByName("debug")
> ```
>
> Este `TODO` es de la plantilla de Flutter y **sigue sin resolverse**. Consecuencias:
>
> - El APK/AAB de release **no se puede publicar en Google Play**: la consola rechaza
>   binarios firmados con la clave de depuración.
> - Cualquiera puede firmar una actualización que el sistema aceptará como legítima, porque
>   la clave de depuración es pública y común a todos los SDK de Android.
> - No hay rotación ni custodia de una clave real.
>
> Clasificado **HIGH** en [23_SECURITY_AUDIT](23_SECURITY_AUDIT.md) y **P0** en
> [29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md) **si el producto va a distribuirse**.
> Si el uso es exclusivamente interno mediante instalación directa del APK, el riesgo real
> es menor, pero el bloqueo para publicar sigue existiendo.

**Cómo se corregiría** (no aplicado — esta auditoría no modifica código):

1. Generar un keystore y **guardarlo fuera del repositorio**.
2. Crear `android/key.properties` (añadido a `.gitignore`) con `storeFile`, `storePassword`,
   `keyAlias`, `keyPassword`.
3. Leerlo desde `build.gradle.kts` y declarar un `signingConfigs.create("release")`.
4. Usar valores tipo `<REQUIRED>` en la documentación; **nunca** commitear el keystore ni las
   contraseñas.

### iOS

```sh
flutter build ios
flutter build ipa
```

**No hay `Podfile` en el repositorio.** Se generará automáticamente en la primera ejecución
de `flutter run` o `flutter build ios` sobre macOS. Requisitos adicionales no confirmables
desde aquí:

- `NO CONFIRMADO EN EL REPOSITORIO`: equipo de firma, perfiles de aprovisionamiento y
  `PRODUCT_BUNDLE_IDENTIFIER` de release. El `Info.plist` usa `$(PRODUCT_BUNDLE_IDENTIFIER)`,
  cuyo valor está en `Runner.xcodeproj/project.pbxproj`, no auditado en detalle.
- `REQUIERE INFORMACIÓN DEL DESARROLLADOR`: si existe cuenta de Apple Developer y si la
  build de iOS se ha probado alguna vez.

### Web

```sh
flutter build web    # compilará, pero la app NO funcionará
```

La carpeta `web/` existe con la plantilla estándar, pero como se explica en
[01_PROJECT_OVERVIEW](01_PROJECT_OVERVIEW.md) y [13_LOCAL_STORAGE](13_LOCAL_STORAGE.md), la
app **no es funcional en navegador**: `dart:io` y el `DatabaseFactory` elegido no son
compatibles. Se recomienda o bien retirar la plataforma web, o bien tratarla como trabajo
futuro explícito.

### Escritorio

No hay carpetas `windows/`, `linux/` ni `macos/`, por lo que `flutter build windows` fallaría
sin ejecutar antes `flutter create --platforms=windows .`.

Sin embargo, el **código está preparado**: `AppDatabase` selecciona `databaseFactoryFfi` en
esas plataformas y usa `getApplicationSupportDirectory`. Añadir escritorio sería
relativamente barato. Hoy esa rama se usa sobre todo para que corran los tests.

## Flavors y entornos

**No existen.** Un solo `applicationId`, un solo `buildType` configurado explícitamente
(`release`), sin `productFlavors`, sin esquemas de Xcode adicionales.

Como no hay backend ni claves, la ausencia de entornos (dev/staging/prod) **es coherente**:
no habría nada que diferenciar entre ellos.

## Ejecución de tests

```sh
flutter test                                    # los 44
flutter test test/repository_test.dart          # un archivo
flutter test --coverage                         # genera coverage/lcov.info
```

Los tests usan `sqflite_common_ffi` con `sqfliteFfiInit()` y una base **en memoria**
(`inMemoryDatabasePath`), por lo que **corren en cualquier escritorio sin emulador ni
dispositivo**. Es una decisión de diseño muy acertada.

`migration_test.dart` es la excepción: crea un archivo real en
`Directory.systemTemp.createTemp('agro_migration_')` y lo borra en `addTearDown`.

## Depuración

- Sin configuración de logging: no hay `print`, `debugPrint` ni `dart:developer` en `lib/`.
- Sin `flutter_launcher_icons` ni `flutter_native_splash`: iconos y splash son los de la
  plantilla.
- `debugShowCheckedModeBanner: false` en `lib/app.dart` oculta el banner de debug.
- Para inspeccionar la base de datos en un dispositivo:
  `adb shell run-as com.comunidad.agro.agroquimicos ls databases/` (solo en builds
  depurables).
- La función **"Exportar backup"** de la propia app es la vía más práctica para obtener el
  `.db` de un dispositivo real y abrirlo con cualquier cliente SQLite.

## Integración continua

**No existe.** No hay `.github/workflows/`, `.gitlab-ci.yml`, `bitrise.yml`, `codemagic.yaml`
ni `Jenkinsfile`.

Como el README ya define los cuatro comandos de verificación y los cuatro pasan, montar CI
sería un trabajo de bajo coste y alto valor. Propuesta concreta en
[30_IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md).

## Control de versiones

> ⚠️ **El directorio de trabajo auditado no es un repositorio Git.** `git rev-parse` falla.
>
> Esto impidió cumplir el paso de validación "revisa `git diff`": no hay diff que revisar.
> La verificación de que solo se añadió documentación se hizo comparando el inventario de
> archivos antes y después (ver [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md)).
>
> Existe un `.gitignore` correcto y completo (ignora `build/`, `.dart_tool/`,
> `.flutter-plugins-dependencies`, `*.iml`, `.idea/`), lo que sugiere que **el proyecto sí
> estuvo o está bajo Git en otra copia**.
>
> `REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ubicación del repositorio real, rama de trabajo
> y si esta copia está sincronizada con él.

## Versionado de la aplicación

`pubspec.yaml`: `version: 1.0.0+1` → `versionName = "1.0.0"`, `versionCode = 1`.

No hay automatización de incremento ni changelog. Para publicar habrá que subir el
`versionCode` manualmente en cada entrega.

## Checklist para un desarrollador nuevo

```sh
# 1. Verificar el toolchain
flutter --version            # >= 3.44.0
java -version                # JDK 17
flutter doctor               # resolver lo que marque

# 2. Dependencias
cd AppFamiliaAgricultor
flutter pub get

# 3. Verificar que todo esta sano ANTES de tocar nada
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

# 4. Ejecutar
flutter run                              # dispositivo o emulador conectado
flutter build apk --debug                # APK instalable

# 5. Primer uso de la app (la base arranca VACIA)
#    Operaciones -> Administrar datos -> crear en este orden:
#    a) al menos una persona ADMIN y una FAMILY o THIRD_PARTY
#    b) una campana (la primera queda ACTIVE automaticamente)
#    c) uno o mas chacos (requieren propietario)
#    d) productos y proveedores
#    Sin esos datos, comprar, planificar y aplicar estan bloqueados.
```

El paso 5 es esencial y **no está documentado en el README**: sin él, la app parece rota
para quien la abre por primera vez. Ver [29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md).
