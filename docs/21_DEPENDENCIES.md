# 21 — Dependencias

Datos tomados de `pubspec.yaml` (restricciones) y `pubspec.lock` (versiones resueltas), y
contrastados con el uso real (`import` + invocación) en el código.

## Dependencias directas de producción

| Paquete | Restricción | Resuelta | ¿Se usa? | Criticidad |
|---|---|---|:--:|---|
| `flutter` | sdk | — | ✅ | Esencial |
| `flutter_riverpod` | `^3.0.3` | 3.4.2 | ✅ | **Esencial** |
| `go_router` | `^17.0.1` | 17.5.0 | ✅ | **Esencial** |
| `sqflite` | `^2.4.2` | 2.4.3 | ✅ | **Esencial** |
| `sqflite_common_ffi` | `^2.4.0+2` | 2.4.2+1 | ✅ | **Esencial** (tests y escritorio) |
| `path` | `^1.9.1` | 1.9.1 | ✅ | Esencial |
| `path_provider` | `^2.1.5` | 2.1.6 | ✅ | **Esencial** |
| `intl` | `^0.20.2` | 0.20.3 | ✅ | Esencial |
| `image_picker` | `^1.2.3` | 1.2.3 | ✅ | Opcional a nivel funcional |
| `cupertino_icons` | `^1.0.8` | 1.0.9 | ❌ | **Prescindible** |

## Dependencias de desarrollo

| Paquete | Restricción | Resuelta | ¿Se usa? | Criticidad |
|---|---|---|:--:|---|
| `flutter_test` | sdk | — | ✅ | Esencial |
| `flutter_lints` | `^6.0.0` | 6.0.0 | ✅ | Recomendable |
| `fake_async` | `^1.3.3` | 1.3.3 | ❌ | **Prescindible** |

## Ficha por dependencia

### `flutter_riverpod` 3.4.2 — Esencial
- **Responsabilidad**: inyección de dependencias y acceso al repositorio desde los widgets.
- **Dónde**: `lib/app.dart` define los tres `Provider`; 14 pantallas son `ConsumerWidget` o
  `ConsumerStatefulWidget`.
- **Alcance real de uso**: **muy limitado**. Solo se usa `Provider` (el tipo más simple) y
  `ref.read`/`ref.watch`. No se usan `StateNotifier`, `AsyncNotifier`, `FutureProvider`,
  `family` ni `autoDispose`. Ver [09_STATE_MANAGEMENT](09_STATE_MANAGEMENT.md).
- **¿Sustituible?** Sí, técnicamente: un `InheritedWidget` bastaría para lo que se usa hoy.
  Pero **no conviene sustituirlo**: es el punto de inyección de los tests
  (`overrideWithValue`) y la base natural si algún día se adopta estado reactivo.
- **Riesgo**: la versión 3.x es reciente y su API cambió respecto a 2.x. Está en la mayor
  versión actual, lo cual es bueno.

### `go_router` 17.5.0 — Esencial
- **Responsabilidad**: enrutado declarativo con `ShellRoute` y parámetros de ruta.
- **Dónde**: `lib/app.dart` (17 rutas); `context.go`/`context.push` en 8 pantallas.
- **Alcance real**: se usan `ShellRoute`, `pathParameters`, `queryParameters` y el retorno
  tipado de `push<bool>`. **No** se usan `redirect`, `errorBuilder`, `refreshListenable`,
  rutas con nombre ni `StatefulShellRoute`.
- **Riesgo detectado**: la mezcla de `go` y `push` hacia rutas de nivel superior provoca un
  fallo confirmado. Ver [08_NAVIGATION](08_NAVIGATION.md) y [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md).
- **Nota de mantenimiento**: `go_router` es de los paquetes que más rompen entre versiones
  mayores. Ir por la 17 implica revisar el changelog en cada actualización.

### `sqflite` 2.4.3 — Esencial
- **Responsabilidad**: motor SQLite en Android e iOS.
- **Dónde**: `app_database.dart` (`mobile.databaseFactory`, `getDatabasesPath`);
  `agro_repository.dart` importa solo los tipos que necesita:
  `show Database, DatabaseExecutor, Sqflite` — **buena higiene de importación**.
- **Uso destacado**: `Sqflite.firstIntValue()` para consultas escalares;
  `db.transaction((txn) async {...})` en todas las operaciones de escritura.
- **¿Sustituible?** Sí (Drift, sqlite3), pero implicaría reescribir las ~35 consultas
  `rawQuery`. Ver [30_IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md).

### `sqflite_common_ffi` 2.4.2+1 — Esencial
- **Responsabilidad**: SQLite vía FFI en Windows, Linux y macOS, y **en el entorno de test**.
- **Dónde**: `app_database.dart` (`sqfliteFfiInit`, `databaseFactoryFfi`) y **los 13 archivos
  de test**.
- **Por qué es esencial**: sin él, **ninguno de los 44 tests podría ejecutarse** sin un
  emulador. Es lo que hace que la suite corra en 13 segundos en un portátil.
- **Nota**: aparece como dependencia de producción, no de desarrollo. Es lo correcto, porque
  `app_database.dart` (código de producción) la importa para la rama de escritorio.

### `path_provider` 2.1.6 — Esencial
- **Responsabilidad**: resolver directorios del sistema por plataforma.
- **Funciones usadas**: `getApplicationSupportDirectory` (BD en escritorio),
  `getApplicationDocumentsDirectory` (carpeta `invoices/` y respaldo del backup),
  `getDownloadsDirectory` (destino preferido del backup).
- **Sin alternativa razonable**: es el paquete canónico del equipo de Flutter.

### `path` 1.9.1 — Esencial
- **Responsabilidad**: composición y análisis de rutas independiente de plataforma.
- **Funciones usadas**: `p.join`, `p.extension`.
- **Nota**: correctamente importado con alias (`as p`) en ambos archivos, evitando colisiones.

### `intl` 0.20.3 — Esencial
- **Responsabilidad**: formateo de moneda y cantidades.
- **Dónde**: **exclusivamente** `lib/domain/money.dart`. Ninguna pantalla lo importa
  directamente — buena centralización.
- **Uso**:
  - `NumberFormat.currency(locale: 'es_BO', symbol: 'Bs ', decimalDigits: 2)`
  - `NumberFormat('#,##0.###', 'es_BO')`
- **No se usa para i18n**: no hay `intl_translation`, `.arb`, ni `AppLocalizations`. El
  locale está **fijado a `es_BO`** en el código, no tomado del dispositivo.
- **Efecto secundario**: los importes se formatean siempre a la boliviana, aunque el
  dispositivo esté en otro idioma. Para este producto es lo deseable.

### `image_picker` 1.2.3 — Opcional a nivel funcional
- **Responsabilidad**: capturar o seleccionar la foto de la factura.
- **Dónde**: **exclusivamente** `purchase_form_screen.dart` (`_pickImage`).
- **Configuración**: `imageQuality: 82`, `maxWidth: 1800` — compresión sensata.
- **Peso**: arrastra 7 paquetes federados más `flutter_plugin_android_lifecycle`, `jni`,
  `jni_flutter` y los tres `file_selector_*` de escritorio.
- **Criticidad**: la compra funciona perfectamente sin foto, y el error se maneja con
  elegancia. Es la única dependencia que **podría** eliminarse sin romper el núcleo del
  producto, aunque perdiendo una funcionalidad valorada.

### `cupertino_icons` 1.0.9 — ❌ Prescindible
- **Verificado**: no hay ningún `import 'package:cupertino_icons/...'` ni ningún uso de
  `CupertinoIcons` en `lib/`. Toda la iconografía es `Icons.*` de Material.
- **Origen**: dependencia de la plantilla `flutter create`.
- **Recomendación**: eliminar. Impacto nulo, limpieza real. Prioridad P3.

### `flutter_lints` 6.0.0 — Recomendable
- Incluido vía `include: package:flutter_lints/flutter.yaml`.
- El proyecto **desactiva cuatro reglas**: `curly_braces_in_flow_control_structures`,
  `unnecessary_underscores`, `use_null_aware_elements`, `prefer_initializing_formals`.
- Con esa configuración, `flutter analyze` da **cero avisos**.

### `fake_async` 1.3.3 — ❌ Prescindible
- **Verificado**: ningún `import 'package:fake_async/fake_async.dart'` en `test/` ni en `lib/`.
- Los tests que necesitan controlar el tiempo usan `tester.runAsync` + `tester.pump` con
  duraciones explícitas (ver el helper `settle` de `regression_widget_test.dart`), no
  `FakeAsync`.
- **Recomendación**: eliminar o empezar a usarla. Prioridad P3.

## Plugins nativos resueltos

De `.flutter-plugins-dependencies`. Se resuelven todos los paquetes federados aunque la
plataforma no se compile:

**Cadena de `image_picker`** (10 paquetes): `image_picker`, `image_picker_android`,
`image_picker_ios`, `image_picker_linux`, `image_picker_macos`, `image_picker_windows`,
`image_picker_for_web`, `file_selector_linux`, `file_selector_macos`,
`file_selector_windows`, más `flutter_plugin_android_lifecycle`, `jni`, `jni_flutter`.

**Cadena de `path_provider`** (5): `path_provider`, `path_provider_android`,
`path_provider_foundation`, `path_provider_linux`, `path_provider_windows`.

**Cadena de `sqflite`** (3): `sqflite`, `sqflite_android`, `sqflite_darwin`.

## Valoración global

### Lo que está bien

**Este es un conjunto de dependencias ejemplarmente austero.** Nueve paquetes directos de
producción para una aplicación con contabilidad, inventario FIFO, multi-moneda y 17
pantallas es una cifra muy baja, y tiene consecuencias positivas concretas:

- **Superficie de ataque mínima**: sin red, sin SDK de terceros, sin analítica.
- **Actualizaciones simples**: pocos paquetes que romper.
- **Compilación rápida** y binario pequeño.
- **Sin dependencias abandonadas**: todas son mantenidas activamente y están en versiones
  recientes.
- **Sin generación de código**: no hay `build_runner`, `freezed`, `json_serializable`. Eso
  significa que no hay archivos `.g.dart` que regenerar ni desincronizaciones posibles.
  (El coste es la ausencia de modelos tipados — ver [24](24_CODE_QUALITY_AUDIT.md)).

### Lo que falta y se nota

| Ausencia | Consecuencia | Prioridad |
|---|---|---|
| **Sin `mockito` / `mocktail`** | Los widget tests usan el repositorio real con SQLite en memoria. Es una decisión defendible (prueban de verdad), pero impide aislar fallos y simular errores | P2 |
| **Sin `integration_test`** | No hay pruebas en dispositivo real | P2 |
| **Sin `golden_toolkit`** | Ninguna prueba de regresión visual, pese a haber tests de responsive | P3 |
| **Sin librería de logging** | Cero observabilidad. Un fallo reportado por el usuario no deja rastro | **P1** |
| **Sin crash reporting** | Los fallos en producción son invisibles. Requeriría añadir el permiso `INTERNET`, lo que hay que sopesar contra la postura offline actual | P2 |
| **Sin `flutter_launcher_icons` / `flutter_native_splash`** | Iconos y pantalla de arranque son los de la plantilla | P3 |

### Salud de versiones

Todas las dependencias directas están en versiones actuales o muy cercanas. No se detectó
ninguna dependencia obsoleta, sin mantenimiento o con vulnerabilidades conocidas.

Para comprobar actualizaciones disponibles:

```sh
flutter pub outdated
```

No se ejecutó en esta auditoría porque requiere acceso a la red, que estaba fuera del
alcance definido.
