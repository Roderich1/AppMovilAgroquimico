# 33 — Matriz de hallazgos de estabilización

Inventario estructurado de hallazgos. Cada uno se **verificó contra el código real** antes de
clasificarlo; ninguno se dio por bueno porque apareciera en la auditoría anterior.

**Estados**: `CONFIRMADO` · `FALSO POSITIVO` · `YA CORREGIDO` · `PARCIALMENTE CORRECTO` ·
`NO REPRODUCIBLE` · `PENDIENTE DE VERIFICAR`
**Severidades**: `P0` crítico · `P1` alto · `P2` medio · `P3` bajo

## Resumen

| ID | Título | Sev. | Estado | Resultado |
|---|---|:--:|---|---|
| STAB-001 | Navegación rota al volver del formulario de compra | P0 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-002 | Esquema migrado ≠ esquema nuevo (índices UNIQUE) | P0 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-003 | `app_settings` nunca se creaba al migrar | P1 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-004 | `FutureBuilder` evalúa `hasData` antes que `hasError` | P1 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-005 | `productCostReport` oculta productos al filtrar por campaña | P1 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-006 | Cobertura nula en lecturas, reportes, dashboard y perfiles | P1 | **CONFIRMADO** | ✅ CUBIERTO (17 tests) |
| STAB-007 | Sin backup/restauración ante pérdida del dispositivo | P1 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-008 | Firma de release usa la clave de depuración | P1 | **CONFIRMADO** | ✅ CORREGIDO (falta keystore del propietario) |
| STAB-009 | Sin logging ni diagnóstico | P1 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-010 | Reversiones sin confirmación | P1 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-011 | `inventorySummary`: `CASE` muerto y división truncada | P2 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-012 | ~400 líneas de código muerto | P2 | **CONFIRMADO** (499 líneas) | ✅ CORREGIDO |
| STAB-013 | Lecturas sin tipar (`Map<String, Object?>`) | P2 | **CONFIRMADO** | NO ABORDADO (justificado) |
| STAB-014 | Repositorio monolítico | P2 | **PARCIALMENTE CORRECTO** | PARCIAL: extraído `BackupService` |
| STAB-015 | Métodos `@Deprecated` sin uso | P2 | **CONFIRMADO** | ✅ CORREGIDO |
| STAB-016 | Naming inconsistente del producto | P3 | **CONFIRMADO** | NO ABORDADO (decisión del propietario) |
| STAB-017 | KI-20: "no es repositorio Git" | — | **YA CORREGIDO** | ✅ documentación actualizada |
| STAB-018 | `dart format .` falla al recorrer `build/` | P3 | **CONFIRMADO** | Documentado |
| STAB-019 | El formulario de compra nace "sucio" sin intervención del usuario | P3 | **CONFIRMADO** | PENDIENTE |

---

## STAB-001 · Navegación rota al volver del formulario de compra

| Campo | Contenido |
|---|---|
| **Categoría** | Navegación / usabilidad crítica |
| **Severidad** | **P0** — deja la aplicación en pantalla en blanco |
| **Estado** | **CONFIRMADO** → ✅ **CORREGIDO** |
| **Archivos** | `lib/presentation/app_shell.dart`, `lib/presentation/screens/operations_screen.dart` |
| **Funcionalidad** | F-04 Registro de compras |
| **Regla de negocio** | Ninguna (defecto de interfaz) |

### Reproducción

1. Abrir la app → FAB **"Nuevo"** → **"Compra"**.
2. Pulsar el botón atrás del formulario.
3. El formulario está *sucio* (ver STAB-019) → aparece "¿Descartar cambios?" → **Descartar**.

### Evidencia

Reproducido en un arnés de test sobre `AgroApp` completo:

```
E5 Descartar=1
You have popped the last page off of the stack, there are no pages left to show
F1 NuevaCompra=0
F2 Inicio=0          ← ni formulario ni inicio: PANTALLA EN BLANCO
F3 exc=Multiple exceptions (2) were detected...
```

Traza: `GoRouterDelegate._debugAssertMatchListNotEmpty (delegate.dart:178)` ←
`NavigatorState.pop` ← `_PurchaseFormScreenState._close`.

### Riesgo

Alto. Dos de las tres vías de acceso al formulario de compra —la operación más frecuente del
producto— dejaban la app inutilizable hasta reiniciarla.

### Causa raíz

`/compras/nueva` está declarada **fuera** del `ShellRoute`. `context.go()` **reemplaza toda
la pila** por esa única ruta, de modo que el `Navigator.pop()` del formulario no tiene
ninguna página debajo. `PurchasesScreen` usaba `context.push` y por eso no fallaba.

### Solución aplicada

Se marcan explícitamente las rutas de formulario con un campo `isForm` y se navega con
`push` en lugar de `go`. Cambio mínimo, sin tocar el router ni los formularios.

Se descartó una alternativa más amplia (un *fallback* `canPop()` en los cuatro formularios)
por exceder el principio de cambio mínimo: la causa raíz es el uso incorrecto de `go`.

### Tests

`test/navigation_test.dart` — 4 tests:
- `STAB-001: FAB Nuevo -> Compra -> atrás vuelve al inicio`
- `STAB-001: Operaciones -> Registrar compra -> atrás vuelve`
- `Compras -> Nueva compra -> atrás vuelve a la lista` (vía `push`, no debía romperse)
- `las 5 pestañas del shell navegan sin excepciones`

Los dos primeros **fallaban antes** del cambio y pasan después.

### Documentos afectados

`08_NAVIGATION.md`, `27_KNOWN_ISSUES.md` (KI-01), `22_TESTING.md`, `28_SYSTEM_MAP.md`

---

## STAB-002 · Esquema migrado ≠ esquema creado desde cero

| Campo | Contenido |
|---|---|
| **Categoría** | Integridad de datos / esquema |
| **Severidad** | **P0** — dos poblaciones de usuarios con esquemas distintos |
| **Estado** | **CONFIRMADO** → ✅ **CORREGIDO** |
| **Archivos** | `lib/data/app_database.dart` |
| **Regla de negocio** | RN-18, RN-23 (unicidad de producto en plan y aplicación) |

### Evidencia

Test de equivalencia de esquema, **fallando antes del cambio**:

```
application_items:      índice solo en el esquema NUEVO   -> idx_application_item_unique|unique=1
application_items:      índice solo en el esquema MIGRADO -> idx_application_item_unique|unique=0
application_plan_items: índice solo en el esquema NUEVO   -> idx_plan_item_unique|unique=1
application_plan_items: índice solo en el esquema MIGRADO -> idx_plan_item_unique|unique=0
```

Causa estática confirmada: `_createSchema` usa `CREATE UNIQUE INDEX`; la migración a v4 usa
`CREATE INDEX` para los mismos dos índices.

### Riesgo

Las instalaciones **migradas** carecían de la garantía de unicidad a nivel de motor y
dependían solo de la validación en Dart. Cualquier razonamiento sobre garantías del esquema
era falso para esos usuarios.

### Solución aplicada

**Nueva migración a la versión 5** (`_upgradeToV5`). No se modificó ninguna migración
histórica, conforme a la regla de no alterar migraciones ya ejecutadas en dispositivos
reales.

La migración:
1. Crea `app_settings` si falta (resuelve STAB-003).
2. Para cada índice: cuenta duplicados; si no hay, `DROP` + `CREATE UNIQUE INDEX`.
3. Si **hay duplicados preexistentes**, conserva el índice no único y registra la anomalía en
   `app_settings` (`schema_v5_duplicate_anomaly`).

**Decisión deliberada**: no se eliminan filas del usuario para poder imponer la unicidad.
Perder datos silenciosamente sería peor que mantener la divergencia. La anomalía queda
registrada para que el propietario la revise.

### Tests

`test/schema_equivalence_test.dart` — 4 tests:
- `una base migrada desde V3 queda con el mismo esquema que una nueva` (**fallaba antes**)
- `los índices de unicidad existen realmente como UNIQUE en base nueva`
- `una base V3 con duplicados preexistentes migra sin perder filas ni fallar`
- `app_settings se crea al migrar, no solo en instalaciones nuevas`

La comparación no es solo de nombres: cubre columnas (tipo, nullability, default, PK) e
índices (**unicidad**, parcialidad, origen, columnas).

### Documentos afectados

`10_DATA_MODEL.md`, `27_KNOWN_ISSUES.md` (KI-02), `22_TESTING.md`, `20_BUILD_AND_CONFIGURATION.md`

---

## STAB-003 · `app_settings` nunca se creaba al migrar

| Campo | Contenido |
|---|---|
| **Severidad** | P1 |
| **Estado** | **CONFIRMADO** → ✅ **CORREGIDO** (junto con STAB-002) |

`app_settings` solo existía en `_createSchema`. Una base migrada desde v1/v2/v3 nunca la
tenía. Era inocuo mientras la tabla no se usara, pero se convirtió en bloqueante al necesitar
registrar la anomalía de STAB-002.

Cubierto por el test `app_settings se crea al migrar, no solo en instalaciones nuevas`.

---

## STAB-017 · KI-20 "el proyecto no está bajo control de versiones"

| Campo | Contenido |
|---|---|
| **Estado** | **YA CORREGIDO** — el hallazgo anterior ya no aplica |

La auditoría previa registró que `git rev-parse` fallaba. En el momento de esta
estabilización el repositorio **sí** existe:

- rama `hardening/stabilization`, HEAD `5d0b8ef`
- remoto `origin/main` configurado
- árbol de trabajo limpio, `docs/` versionado (32 archivos)

Se actualiza `27_KNOWN_ISSUES.md`. Ver [32_STABILIZATION_BASELINE](32_STABILIZATION_BASELINE.md).

---

## STAB-018 · `dart format .` falla al recorrer `build/`

| Campo | Contenido |
|---|---|
| **Severidad** | P3 |
| **Estado** | **CONFIRMADO** — no es un defecto del código |

```
PathNotFoundException: Directory listing failed, path =
'.\build\flutter_plugin_android_lifecycle\.transforms\...\bundleLibRuntimeToDirDebug_dex\...'
```

`dart format .` recorre `build/`, cuyas rutas de transformación de Gradle superan el límite
de ruta de Windows. **Ningún archivo Dart está mal formateado**: `dart format lib test`
reporta 0 cambios.

**Acción**: ninguna sobre el código. Se documenta que el comando correcto —y el que ya
figura en el `README.md`— es `dart format --output=none --set-exit-if-changed lib test`.
Relevante para una futura configuración de CI.

---

## STAB-019 · El formulario de compra nace "sucio"

| Campo | Contenido |
|---|---|
| **Severidad** | P3 |
| **Estado** | **CONFIRMADO** — descubierto durante esta estabilización |

`AdaptiveEntityPicker` autoselecciona cuando hay **exactamente una** opción, y esa
autoselección invoca `onChanged`, que marca `dirty = true`. Con un solo proveedor o una sola
campaña en la base, abrir el formulario de compra y pulsar atrás inmediatamente pregunta
"¿Descartar cambios?" **sin que el usuario haya tocado nada**.

Evidencia: `E5 Descartar=1` en el arnés de reproducción de STAB-001, sin ninguna interacción
previa con los campos.

No es un defecto de corrección de datos, sino de fricción de interfaz. Pendiente de decidir
si la autoselección debe considerarse "cambio del usuario".

---

## Hallazgos verificados y no abordados

Tres hallazgos se **confirmaron** pero se decidió no abordarlos en esta fase. La
justificación es parte del resultado, no una omisión:

### STAB-013 · Lecturas sin tipar — NO ABORDADO

**Confirmado**: toda la capa de lectura devuelve `Map<String, Object?>` y la interfaz hace
casts por cadena literal.

**Por qué no se abordó**: convertir ~20 consultas a modelos tipados es una refactorización
amplia **sin ningún defecto asociado**. Contradice la regla de cambio mínimo de esta fase,
cuya prioridad era corrección e integridad de datos. Sigue registrado como mejora P2 en
`29_IMPROVEMENT_AUDIT.md` (M-16), abordable de forma incremental.

### STAB-014 · Repositorio monolítico — PARCIAL

**Confirmado**: `AgroRepository` concentraba seis responsabilidades.

**Qué se hizo**: se extrajo `BackupService` porque tenía una justificación concreta —la
restauración es la operación más destructiva y debía poder probarse aislada— y porque hacía
falta código nuevo de todos modos. El repositorio bajó de **1 862 a 1 657 líneas** (−11 %),
sumando la extracción y la eliminación de código muerto.

**Qué no se hizo**: dividir el resto en seis servicios. Sin un defecto que lo motive sería
refactorización por estética, con riesgo de regresión sobre el motor de costeo.

### STAB-016 · Naming inconsistente — NO ABORDADO

**Confirmado**: el usuario ve "agroquimicos" en Android, "Agroquimicos" en iOS y
"Agrocuentas" dentro de la app.

**Por qué no se abordó**: `REQUIERE INFORMACIÓN DEL DESARROLLADOR`. Elegir el nombre
comercial definitivo es una decisión de producto. Cambiar `applicationId` además rompería la
continuidad de instalación, así que no debe tocarse.

## Estado de la suite

| Momento | analyze | format (`lib test`) | tests |
|---|---|---|---|
| Línea base | 0 issues | 0 cambios | **44 / 44** |
| Cierre de la estabilización | 0 issues | 0 cambios | **91 / 91** |

Build de release verificada: `flutter build apk --release` y
`flutter build appbundle --release` compilan correctamente.
