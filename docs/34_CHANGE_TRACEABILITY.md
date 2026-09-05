# 34 — Trazabilidad de cambios

Cada cambio importante de la fase de estabilización, enlazado desde el hallazgo hasta su
evidencia, su código, su test y su documentación.

**Ningún P0 ni P1 corregido queda sin trazabilidad.**

## Tabla maestra

| Finding | Regla / requisito | Evidencia | Cambio en código | Test | Documentación | Estado |
|---|---|---|---|---|---|---|
| **STAB-001** | Navegación: volver atrás debe dejar una pantalla utilizable | Aserción de go_router *"You have popped the last page off of the stack"* reproducida sobre `AgroApp` | `app_shell.dart`, `operations_screen.dart` → `push` para rutas fuera del `ShellRoute` | `navigation_test.dart` (4) | `08_NAVIGATION.md`, `27_KNOWN_ISSUES.md` KI-01 | ✅ FIXED |
| **STAB-002** | RN-18, RN-23: unicidad de producto en plan y aplicación | Test de equivalencia: `unique=1` en base nueva vs `unique=0` en migrada | `app_database.dart` → migración v5 `_upgradeToV5` | `schema_equivalence_test.dart` (4) | `10_DATA_MODEL.md`, `27_KNOWN_ISSUES.md` KI-02 | ✅ FIXED |
| **STAB-003** | `app_settings` debe existir en toda instalación | Tabla ausente en bases migradas | `app_database.dart` → creación en v5 | `schema_equivalence_test.dart` | `10_DATA_MODEL.md` | ✅ FIXED |
| **STAB-004** | Un error nunca debe presentarse como "cargando" | Test: `CircularProgressIndicator` presente tras fallo de consulta | `settlements_screen.dart`, `purchases_screen.dart`, `purchase_form_screen.dart`, `catalogs_screen.dart` | `error_states_test.dart` (3) | `17_ERROR_HANDLING.md`, `27_KNOWN_ISSUES.md` KI-03, KI-15 | ✅ FIXED |
| **STAB-005** | Un reporte filtrado no debe ocultar filas en cero | Test: filtrado por campaña devolvía 1 de 3 productos | `agro_repository.dart` → condición al `ON` del `LEFT JOIN` | `reports_test.dart` (4) | `27_KNOWN_ISSUES.md` KI-04 | ✅ FIXED |
| **STAB-006** | Las lecturas críticas deben tener cobertura | Cero tests de reportes, dashboard y perfiles | — (solo tests) | `reports_test.dart` (17) | `22_TESTING.md`, `31_TRACEABILITY_MATRIX.md` | ✅ CUBIERTO |
| **STAB-007** | Debe existir recuperación ante pérdida de datos | No existía restauración ni validación | **nuevo** `backup_service.dart`; `settlements_screen.dart`; `app.dart` | `backup_service_test.dart` (10) | `13_LOCAL_STORAGE.md`, `14_OFFLINE_AND_SYNC.md` | ✅ FIXED |
| **STAB-008** | Debe poder producirse una release publicable | Release firmada con la clave de depuración | `android/app/build.gradle.kts`, `key.properties.example`, `.gitignore` | `apksigner verify` sobre ambos APK | `20_BUILD_AND_CONFIGURATION.md`, `23_SECURITY_AUDIT.md` S-01 | ✅ FIXED (bloqueo externo: keystore) |
| **STAB-009** | Los errores importantes deben poder diagnosticarse | Cero sentencias de logging en `lib/` | **nuevo** `app_log.dart`; `main.dart`; `common.dart` | `app_log_test.dart` (6) | `17_ERROR_HANDLING.md`, `23_SECURITY_AUDIT.md` | ✅ FIXED |
| **STAB-010** | Una acción irreversible no debe ejecutarse de un toque | Reversión inmediata sin confirmación en 3 pantallas | `common.dart` (`confirmDestructiveAction`), `applications_screen.dart`, `transfers_screen.dart`, `purchases_screen.dart` | `destructive_actions_test.dart` (3) | `27_KNOWN_ISSUES.md` KI-12 | ✅ FIXED |
| **STAB-011** | RN-50: redondeo mitad arriba en todo cálculo monetario | Test: valor de inventario 0 donde correspondía 1 (truncamiento) | `agro_repository.dart` → `inventorySummary`, `inventoryProductHeader` | `reports_test.dart` | `27_KNOWN_ISSUES.md` KI-09 | ✅ FIXED |
| **STAB-012** | El código muerto confunde y engaña sobre la complejidad | 0 referencias verificadas en `lib/` y `test/` | `purchases_screen.dart` (−294), `agro_repository.dart` (−205), `application_form_screen.dart` (`_farmOwner`) | Suite completa en verde | `24_CODE_QUALITY_AUDIT.md`, `26_TECHNICAL_DEBT.md` | ✅ FIXED |
| **STAB-015** | Métodos `@Deprecated` sin uso | 0 llamadas verificadas | `agro_repository.dart` → eliminados `transferProductFifoV3Legacy`, `transferStockLegacy` | Suite completa en verde | `26_TECHNICAL_DEBT.md` | ✅ FIXED |
| **STAB-017** | KI-20 "no es repositorio Git" | `git rev-parse` responde; rama `hardening/stabilization` | — | — | `20_BUILD_AND_CONFIGURATION.md`, `27_KNOWN_ISSUES.md` KI-20 | ✅ YA CORREGIDO |
| **STAB-018** | `dart format .` falla al recorrer `build/` | `PathNotFoundException` en rutas de Gradle | — (documentación) | — | `32_STABILIZATION_BASELINE.md`, `20_BUILD_AND_CONFIGURATION.md` | ✅ DOCUMENTADO |

## Detalle por cambio de código

### `lib/data/app_database.dart`
- `schemaVersion` pasa de 4 a **5** y se expone como constante.
- Nueva `_upgradeToV5`: promueve los dos índices a `UNIQUE` y crea `app_settings`.
- Nuevos `resolvedFactory` y `resolvePath()` para que `BackupService` valide un archivo
  candidato sin tocar la base en uso.
- **No se modificó ninguna migración histórica.**

### `lib/data/agro_repository.dart` (1 862 → 1 657 líneas)
- `productCostReport`: condición de campaña movida del `WHERE` al `ON` (STAB-005).
- `inventorySummary` e `inventoryProductHeader`: eliminado el `CASE` con ramas idénticas y
  aplicado redondeo mitad arriba (STAB-011).
- Eliminados `transferProductFifoV3Legacy`, `transferStockLegacy` y `exportBackup`
  (este último sustituido por `BackupService`).

### `lib/data/backup_service.dart` (nuevo)
`export`, `listAvailableBackups`, `validate`, `restore` y `BackupException`. Extraído del
repositorio porque es una responsabilidad distinta y la restauración es la operación más
destructiva de la aplicación.

### `lib/data/app_log.dart` (nuevo)
Registro local con niveles, rotación a 512 KB y manejadores globales
(`FlutterError.onError`, `PlatformDispatcher.onError`). No envía nada a ningún servidor.

### `lib/presentation/widgets/common.dart`
- Nuevo `confirmDestructiveAction`.
- `showError` registra en el log: punto único por el que pasan todos los errores visibles.

### Pantallas
| Archivo | Cambio |
|---|---|
| `app_shell.dart` | `isForm` + `push` para rutas fuera del shell |
| `operations_screen.dart` | idem |
| `settlements_screen.dart` | `hasError` antes de `hasData`; menú Exportar/Restaurar |
| `purchases_screen.dart` | `hasError` primero + `friendlyError`; confirmación de reversión; −294 líneas muertas |
| `purchase_form_screen.dart` | rama de error añadida |
| `catalogs_screen.dart` | `friendlyError` en lugar de `toString()` |
| `applications_screen.dart` | confirmación de reversión informada |
| `transfers_screen.dart` | confirmación de reversión informada |
| `application_form_screen.dart` | eliminado `_farmOwner` preservando el comportamiento |

### Configuración
| Archivo | Cambio |
|---|---|
| `android/app/build.gradle.kts` | Firma real desde `key.properties`; sin él, release sin firmar |
| `android/key.properties.example` | **nuevo** — plantilla sin secretos |
| `.gitignore` | `android/key.properties`, `*.jks`, `*.keystore` |
| `lib/main.dart` | Inicializa el log antes de arrancar |

## Tests: de 44 a 91

| Archivo | Tests | Cubre |
|---|---:|---|
| `schema_equivalence_test.dart` | 4 | STAB-002, STAB-003 |
| `navigation_test.dart` | 4 | STAB-001 |
| `reports_test.dart` | 17 | STAB-005, STAB-006, STAB-011 |
| `backup_service_test.dart` | 10 | STAB-007 |
| `app_log_test.dart` | 6 | STAB-009 |
| `error_states_test.dart` | 3 | STAB-004 |
| `destructive_actions_test.dart` | 3 | STAB-010 |
| **Nuevos** | **47** | |
| Existentes | 44 | Sin cambios de aserción salvo el ajuste documentado abajo |

### Único test existente modificado

`regression_widget_test.dart` → *"estado de cuenta abre y cierra 20 veces"*.

Afirmaba `find.byType(PopupMenuButton<String>)` **findsOneWidget**. Al añadir el menú de
copias de seguridad en la cabecera pasaron a existir dos. **No se debilitó la aserción**: se
hizo el localizador preciso (`find.descendant(of: Card, ...)`) para apuntar al menú de
persona, que es lo que el test pretende ejercitar. La aserción sigue siendo `findsOneWidget`.

## Cambios de comportamiento observable

Registrados explícitamente porque afectan a lo que ve el usuario:

| Cambio | Justificación |
|---|---|
| Revertir compra, aplicación o transferencia pide confirmación | STAB-010: acción irreversible |
| "Costo consumido por producto" filtrado por campaña muestra ahora todos los productos, los no consumidos en cero | STAB-005: antes desaparecían |
| El valor de inventario puede diferir en 1 céntimo respecto a antes | STAB-011: se redondea mitad arriba como el resto del sistema |
| El botón "Exportar backup" es ahora un menú con Exportar y Restaurar | STAB-007 |
| La build de release sin `key.properties` queda sin firmar en lugar de firmada en depuración | STAB-008 |

## Cambios NO realizados, y por qué

| Propuesta | Decisión |
|---|---|
| Modelos de lectura tipados (STAB-013) | **No abordado**: refactorización amplia (~20 clases) sin defecto asociado. Sigue en `29_IMPROVEMENT_AUDIT.md` |
| Dividir `AgroRepository` (STAB-014) | **Parcial**: se extrajo `BackupService` porque tenía una justificación concreta. No se dividió el resto: sería refactorización por estética |
| Incluir fotografías en el backup | **No abordado**: exigiría una dependencia de empaquetado. Documentado como limitación conocida |
| Corregir el "dirty" espurio del formulario de compra (STAB-019) | **No abordado**: P3, y cambiar la autoselección afectaría a todos los formularios |
| Unificar el naming del producto (STAB-016) | **No abordado**: P3 y requiere decisión del propietario sobre el nombre definitivo |
| Actualizar dependencias | **No abordado**: ninguna con vulnerabilidad, bug o incompatibilidad conocida |
