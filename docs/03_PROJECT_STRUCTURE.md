# 03 — Estructura del proyecto

## Raíz del repositorio

```
AppFamiliaAgricultor/
├── .dart_tool/                              generado (ignorado)
├── .flutter-plugins-dependencies            generado; lista plugins nativos resueltos
├── .gitignore
├── .idea/                                   config de IntelliJ/Android Studio
├── .metadata                                revisión de Flutter y plataformas migradas
├── AGROQUIMICOS_IMPLEMENTATION_SPEC_V2.md   spec de diseño previo (INTENCIÓN, no estado)
├── CODEX_MASTER_PROMPT_AGROQUIMICOS_V2.md   prompt de generación previo
├── README.md                                instrucciones de ejecución y verificación
├── agroquimicos.iml
├── analysis_options.yaml                    flutter_lints + 4 reglas desactivadas
├── android/                                 proyecto Gradle (Kotlin DSL)
├── build/                                   artefactos (ignorado)
├── ios/                                     proyecto Xcode (SIN Podfile)
├── lib/                                     ← todo el código Dart de producción
├── pubspec.yaml / pubspec.lock              dependencias
├── test/                                    13 archivos, 44 tests
└── web/                                     index.html, manifest, iconos
```

> **Este repositorio no es un repositorio Git** en su estado actual (`git rev-parse` falla).
> Por tanto no fue posible ejecutar `git diff` como pedía la fase de validación, ni existe
> historial de commits que consultar. Ver [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md).
> `REQUIERE INFORMACIÓN DEL DESARROLLADOR`: si existe un repositorio remoto, no está
> vinculado a esta copia de trabajo.

## `lib/` comentado (8 250 líneas)

| Archivo | Líneas | Responsabilidad |
|---|---:|---|
| `main.dart` | 9 | Bootstrap: `ProviderScope` + `AgroApp` |
| `app.dart` | 151 | `databaseProvider`, `repositoryProvider`, `routerProvider`, `ThemeData` |
| **`domain/`** | **173** | |
| `domain/models.dart` | 129 | 4 enums, `EnumCode`, 7 clases `*Draft`, `DashboardSummary` |
| `domain/money.dart` | 44 | `divideRoundedHalfUp`, `convertedUnitPriceBobMinor`, `subtotalMinor`, `costForBaseQuantity`, `formatBob`, `formatQuantity` |
| **`data/`** | **2 176** | |
| `data/app_database.dart` | 314 | Esquema v4 (22 tablas, 15 índices) y migraciones v1→v4 |
| `data/agro_repository.dart` | **1 862** | Todas las reglas de negocio, costeo FIFO, contabilidad y reportes |
| **`presentation/`** | **5 741** | |
| `presentation/app_shell.dart` | 129 | Navegación adaptativa + FAB "Nuevo" |
| `presentation/widgets/common.dart` | 118 | `PageFrame`, `EmptyState`, snackbars, parsers, `friendlyError` |
| `presentation/widgets/adaptive_entity_picker.dart` | 231 | Selector genérico con búsqueda y autoselección |
| `presentation/screens/` (17 archivos) | 5 263 | Ver tabla siguiente |

### Pantallas ordenadas por tamaño

| Archivo | Líneas | Tipo | Ruta que la monta |
|---|---:|---|---|
| `purchase_form_screen.dart` | 772 | Formulario | `/compras/nueva` |
| `purchases_screen.dart` | 658 | Lista | `/compras` |
| `catalogs_screen.dart` | 620 | Gestión (5 pestañas) | `/catalogos` |
| `application_form_screen.dart` | 584 | Formulario | `/aplicaciones/nueva` |
| `settlements_screen.dart` | 432 | Lista + reportes | `/liquidacion` |
| `transfer_form_screen.dart` | 361 | Formulario | `/transferencias/nueva` |
| `dashboard_screen.dart` | 354 | Dashboard | `/` |
| `plan_form_screen.dart` | 343 | Formulario | `/planificacion/nueva` |
| `inventory_detail_screen.dart` | 198 | Detalle | `/inventario/:id` |
| `applications_screen.dart` | 193 | Lista | `/aplicaciones` |
| `person_detail_screen.dart` | 182 | Detalle (5 pestañas) | `/personas/:id` |
| `planning_screen.dart` | 141 | Lista | `/planificacion` |
| `inventory_screen.dart` | 106 | Lista | `/inventario` |
| `transfers_screen.dart` | 103 | Lista | `/transferencias` |
| `farm_logbook_screen.dart` | 82 | Detalle | `/chacos/:id` |
| `operations_screen.dart` | 79 | Menú estático | `/operaciones` |
| `persons_screen.dart` | 55 | Lista | `/personas` |

> `purchases_screen.dart` contiene **~350 líneas de código muerto** (`_PurchaseDialog`,
> `_PurchaseDialogState`, `_AllocationInput`, `_select`): ninguna referencia en `lib/` ni
> en `test/`. Su tamaño real efectivo es ~300 líneas. Ver [26_TECHNICAL_DEBT](26_TECHNICAL_DEBT.md).

## `test/` (1 972 líneas, 44 tests)

| Archivo | Tests | Tipo | Qué cubre |
|---|---:|---|---|
| `repository_test.dart` | 11 | Unit/integración con SQLite en memoria | Cargos, FIFO, reversiones, multiproducto, multi-moneda |
| `v5_domain_test.dart` | 6 | Integración | Transferencias multiproducto, duplicados, continuidad entre campañas, plan→aplicación |
| `v4_repository_test.dart` | 4 | Integración | Campaña única activa, FIFO en transferencias, rollback, saldo inicial cruzando campañas |
| `regression_widget_test.dart` | 4 | Widget con repo real | Precarga de área, `FormatException`, estado de cuenta 20 aperturas, `setState` |
| `money_test.dart` | 3 | Unit puro | Conversión FX exacta |
| `adaptive_picker_test.dart` | 2 | Widget | Búsqueda con 50 ítems, autoselección |
| `back_navigation_test.dart` | 2 | Widget (arnés aislado) | Contrato `PopScope` de formularios sucios |
| `migration_test.dart` | 2 | Integración con archivo | Migraciones v1→v2 y v3→v4 conservan filas |
| `widget_test.dart` | 2 | Widget | Navegación principal, sin overflow a 360px/1.6× |
| `e2e_scenario_test.dart` | 1 | E2E | Escenario completo de campaña |
| `e2e_v5_test.dart` | 1 | E2E | Catálogo 20 productos, compra 12 líneas, transferencia, plan, aplicación |
| `responsive_v5_test.dart` | 1 (×5 tamaños) | Widget | Formularios en 5 resoluciones con `textScaleFactor` 1.4 |
| `volume_test.dart` | 1 | Rendimiento | Fixture 100 productos / 1000 aplicaciones / 300 compras |

No existen `mocks/` ni `fixtures/` como carpetas: los datos de prueba se construyen
programáticamente en cada `setUp`. Ver [22_TESTING](22_TESTING.md).

## `android/`

```
android/
├── app/
│   ├── build.gradle.kts        namespace com.comunidad.agro.agroquimicos, Java 17
│   └── src/
│       ├── debug/AndroidManifest.xml     solo INTERNET (herramienta Flutter)
│       ├── main/AndroidManifest.xml      sin permisos declarados
│       └── profile/AndroidManifest.xml   solo INTERNET
├── build.gradle.kts
├── gradle/ · gradlew · gradlew.bat
└── settings.gradle.kts
```

El `AndroidManifest.xml` de `main` **no declara ningún `uses-permission`**, lo que confirma
que la app no accede a Internet en release. Ver [18_PERMISSIONS](18_PERMISSIONS.md).

## `ios/`

```
ios/
├── Flutter/
├── Runner/
│   ├── AppDelegate.swift · SceneDelegate.swift
│   ├── Info.plist          NSCameraUsageDescription + NSPhotoLibraryUsageDescription
│   ├── GeneratedPluginRegistrant.{h,m}
│   └── Assets.xcassets · Base.lproj
├── Runner.xcodeproj · Runner.xcworkspace
└── RunnerTests/
```

**No hay `Podfile`.** Se generará en la primera ejecución de `flutter build ios` /
`flutter run` en macOS. La build de iOS no fue verificada en esta auditoría.

## `web/`

`favicon.png`, `icons/`, `index.html`, `manifest.json` — plantilla estándar de Flutter, sin
personalizar. Como se explica en [01_PROJECT_OVERVIEW](01_PROJECT_OVERVIEW.md), la app **no
funciona en web** por el uso de `dart:io` y de un `DatabaseFactory` no compatible.

## Convenciones de nombres observadas

- Archivos y carpetas: `snake_case.dart`.
- Clases: `PascalCase`; privadas de archivo con guion bajo (`_LineCard`, `_Section`).
- Columnas SQL: `snake_case`, con sufijos semánticos muy consistentes y útiles:
  - `_base` → cantidad en unidad base (ml o g), factor 1000 respecto a L/kg;
  - `_minor` → dinero en centavos;
  - `_scaled` → tipo de cambio multiplicado por 1 000 000;
  - `_m2` → superficie en metros cuadrados;
  - `_signed` → valor con signo (movimientos de inventario y asientos contables).
- Textos de UI: **español**, hardcodeados en los widgets.
- Códigos persistidos de enums: `SCREAMING_SNAKE_CASE` vía `EnumCode` (`models.dart`).
