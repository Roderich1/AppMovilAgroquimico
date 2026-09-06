# Documentación técnica — Agrocuentas V2 (`agroquimicos`)

Línea base generada por auditoría de código sobre el repositorio **tal como existe hoy**.
Ninguna afirmación de estos documentos proviene de suposiciones: cada regla, endpoint,
pantalla o flujo está referenciado a un archivo y, cuando aplica, a una línea concreta.

Cuando algo no pudo determinarse desde el código, aparece marcado explícitamente como
`NO CONFIRMADO EN EL REPOSITORIO` o `REQUIERE INFORMACIÓN DEL DESARROLLADOR`.

## Estado vigente del proyecto

> # BASELINE CONGELADA — `v1.0.0-base-stable`
>
> **Baseline de desarrollo: `READY FOR EVOLUTION`.**
> **Distribución en tienda: `NOT READY — KEYSTORE REQUIRED`.**
>
> Son dos gates distintos y se evalúan por separado: lo único que falta para publicar es una
> clave privada, no código ni pruebas. Ver
> [35_RELEASE_READINESS § BASELINE FREEZE STATUS](35_RELEASE_READINESS.md#baseline-freeze-status--dos-gates-separados).
>
> **0 CRITICAL · 0 HIGH · 0 MEDIUM · 0 LOW abiertos** · 0 decisiones de producto pendientes ·
> 0 defectos conocidos fuera del backlog · 253 tests en verde · CI en GitHub Actions verde ·
> 17/17 rutas verificadas en Pixel 8.
>
> **Empieza por [46_BASELINE_FINAL_FREEZE](46_BASELINE_FINAL_FREEZE.md)**: es el cierre
> definitivo y el resumen más corto del estado real.

La documentación de este repositorio está en **seis capas**, y confundirlas lleva a
conclusiones equivocadas:

| Capa | Documentos | Qué es | ¿Vigente? |
|---|---|---|---|
| **1 · Línea base y auditoría de código** | `01`–`31` | Descripción del sistema tal como está escrito. Se generó por lectura de código, **sin ejecutar la app**. | Vigente como descripción; sus veredictos de calidad son **anteriores** a las capas 2 y 3. |
| **2 · Estabilización (histórica)** | `32`–`35` | Fase que **sí modificó código** (STAB-001…019). Su informe de release concluía *RELEASE CANDIDATE*. | **Histórica.** El veredicto está **superado** por la capa 3; el análisis se conserva íntegro. |
| **3 · Auditoría de interfaz (posterior)** | `36`–`40` | Auditoría **ejecutando la aplicación** en Pixel 8. Encontró 65 defectos, 4 de ellos CRITICAL. | **Histórica como observación**; 54 de 66 ya corregidos. Para el estado vigente, `43` y `45`. |
| **4 · Backlog y corrección** | `41`–`45` | Backlog normalizado, plan de corrección por lotes y trazabilidad de cada arreglo. | **Vigente**: `41` es el catálogo de hallazgos y `43` la trazabilidad. `45` es el cierre de su fase. |
| **5 · Congelación de la baseline** | **`46`** | **Cierre definitivo del proyecto base**: estado, decisiones de producto, evidencia y veredicto. | **Vigente. Empieza aquí.** |
| **6 · Evolución posterior** | **`evolution/`** | Gobierno, roadmap, specs, planes, riesgos y verificaciones posteriores a `v1.0.0-base-stable`. | **Vigente para toda funcionalidad nueva.** |

**Documento de estado actual: [46_BASELINE_FINAL_FREEZE](46_BASELINE_FINAL_FREEZE.md).**
**Catálogo de hallazgos: [41_UIBUG_MASTER_BACKLOG](41_UIBUG_MASTER_BACKLOG.md).**
**Trazabilidad de las correcciones: [43_UIBUG_FIX_TRACEABILITY](43_UIBUG_FIX_TRACEABILITY.md).**

> **Baseline funcional congelada**: `v1.0.0-base-stable` →
> `f4c6510438991f4948fda921eec7c67fe2a2acc2`. El HEAD documental posterior es
> `bdd7b82f3e06d9943749a571284db8f94194c3b3`; entre ambos no existen cambios en código de
> producción, tests, dependencias ni esquema.

## Punto de entrada recomendado

| Si vienes a… | Empieza por |
|---|---|
| saber en qué estado está el proyecto | **[46 congelación de la baseline](46_BASELINE_FINAL_FREEZE.md)** |
| entender el sistema | **[28_SYSTEM_MAP.md](28_SYSTEM_MAP.md)** (15–30 min) |
| saber si se puede publicar | **[35 § BASELINE FREEZE STATUS](35_RELEASE_READINESS.md#baseline-freeze-status--dos-gates-separados)** — dos gates |
| empezar una funcionalidad nueva | **[Índice de evolución](evolution/00_EVOLUTION_INDEX.md)** y **[46 §18](46_BASELINE_FINAL_FREEZE.md)** |
| ver el estado de un defecto | **[41 catálogo](41_UIBUG_MASTER_BACKLOG.md)** → **[43 trazabilidad](43_UIBUG_FIX_TRACEABILITY.md)** |
| ver la evidencia de un defecto | **[38 hallazgos](38_UI_AUDIT_FINDINGS.md)** y `artifacts/ui-audit/` |

## Índice

### Capa 1 — Línea base y auditoría de código

| # | Documento | Contenido |
|---|-----------|-----------|
| 01 | [PROJECT_OVERVIEW](01_PROJECT_OVERVIEW.md) | Qué es el producto, alcance, actores |
| 02 | [ARCHITECTURE](02_ARCHITECTURE.md) | Arquitectura real en 3 capas |
| 03 | [PROJECT_STRUCTURE](03_PROJECT_STRUCTURE.md) | Árbol de archivos comentado |
| 04 | [TECH_STACK](04_TECH_STACK.md) | Lenguaje, SDK, librerías y su uso real |
| 05 | [FEATURES](05_FEATURES.md) | Inventario de funcionalidades |
| 06 | [USER_FLOWS](06_USER_FLOWS.md) | Recorridos de usuario reconstruidos |
| 07 | [SCREENS](07_SCREENS.md) | Ficha de cada pantalla |
| 08 | [NAVIGATION](08_NAVIGATION.md) | Rutas, shell y mapa de navegación |
| 09 | [STATE_MANAGEMENT](09_STATE_MANAGEMENT.md) | Riverpod + FutureBuilder + setState |
| 10 | [DATA_MODEL](10_DATA_MODEL.md) | Esquema SQLite, ER, drafts de dominio |
| 11 | [API_INTEGRATION](11_API_INTEGRATION.md) | Comunicación externa (no existe) |
| 12 | [AUTHENTICATION](12_AUTHENTICATION.md) | Autenticación/autorización (no existe) |
| 13 | [LOCAL_STORAGE](13_LOCAL_STORAGE.md) | SQLite, archivos de factura, backup |
| 14 | [OFFLINE_AND_SYNC](14_OFFLINE_AND_SYNC.md) | Modelo offline-only, sin sincronización |
| 15 | [BUSINESS_RULES](15_BUSINESS_RULES.md) | Reglas de negocio confirmadas |
| 16 | [VALIDATIONS](16_VALIDATIONS.md) | Validación de UI vs. regla de negocio |
| 17 | [ERROR_HANDLING](17_ERROR_HANDLING.md) | Estrategia de errores y estados |
| 18 | [PERMISSIONS](18_PERMISSIONS.md) | Permisos de dispositivo |
| 19 | [NOTIFICATIONS](19_NOTIFICATIONS.md) | Notificaciones (no existen) |
| 20 | [BUILD_AND_CONFIGURATION](20_BUILD_AND_CONFIGURATION.md) | Cómo levantar y compilar |
| 21 | [DEPENDENCIES](21_DEPENDENCIES.md) | Dependencias y criticidad |
| 22 | [TESTING](22_TESTING.md) | Cobertura real y huecos |
| 23 | [SECURITY_AUDIT](23_SECURITY_AUDIT.md) | Hallazgos de seguridad clasificados |
| 24 | [CODE_QUALITY_AUDIT](24_CODE_QUALITY_AUDIT.md) | Calidad objetiva vs. estilo |
| 25 | [PERFORMANCE_AUDIT](25_PERFORMANCE_AUDIT.md) | Riesgos de rendimiento |
| 26 | [TECHNICAL_DEBT](26_TECHNICAL_DEBT.md) | Deuda técnica clasificada |
| 27 | [KNOWN_ISSUES](27_KNOWN_ISSUES.md) | Defectos observables |
| 28 | [SYSTEM_MAP](28_SYSTEM_MAP.md) | **Mapa maestro del sistema** |
| 29 | [IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md) | Oportunidades P0–P3 |
| 30 | [IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md) | Plan por fases |
| — | [31_TRACEABILITY_MATRIX](31_TRACEABILITY_MATRIX.md) | Matriz funcionalidad → test |

### Capa 2 — Estabilización (histórica)

| # | Documento | Contenido |
|---|-----------|-----------|
| 32 | [STABILIZATION_BASELINE](32_STABILIZATION_BASELINE.md) | Estado medido **antes** de estabilizar |
| 33 | [STABILIZATION_FINDINGS](33_STABILIZATION_FINDINGS.md) | Hallazgos verificados (STAB-001…019) |
| 34 | [CHANGE_TRACEABILITY](34_CHANGE_TRACEABILITY.md) | Hallazgo → código → test → documento |
| 35 | [RELEASE_READINESS](35_RELEASE_READINESS.md) | Informe de release. §1–13 y § POST-UI-AUDIT **históricas**; **§ POST-BACKLOG STATUS es el estado vigente: `RELEASE CANDIDATE`** |

### Capa 3 — Auditoría de interfaz sobre Pixel 8 (evidencia)

| # | Documento | Contenido |
|---|-----------|-----------|
| 36 | [UI_AUDIT_DATASET](36_UI_AUDIT_DATASET.md) | Dataset determinista de la auditoría de interfaz y procedimiento RESET/SEED |
| 37 | [UI_SCREEN_INVENTORY](37_UI_SCREEN_INVENTORY.md) | Inventario de pantallas, matriz de cobertura y matriz de flujos |
| 38 | [UI_AUDIT_FINDINGS](38_UI_AUDIT_FINDINGS.md) | **Los 65 UIBUG observados en el Pixel 8**, con pasos y evidencia |
| 39 | [UI_AUDIT_TRACEABILITY](39_UI_AUDIT_TRACEABILITY.md) | UIBUG → pantalla → feature → regla → evidencia → archivo |
| 40 | [UI_AUDIT_SUMMARY](40_UI_AUDIT_SUMMARY.md) | Resumen ejecutivo de la auditoría de interfaz |

### Capa 4 — Backlog y corrección

| # | Documento | Contenido |
|---|-----------|-----------|
| **41** | [**UIBUG_MASTER_BACKLOG**](41_UIBUG_MASTER_BACKLOG.md) | **Backlog maestro — fuente de verdad operativa.** 66 entradas sobre 65 IDs, con causa raíz, riesgo, dependencias y prioridad |
| **42** | [**UIBUG_FIX_PLAN**](42_UIBUG_FIX_PLAN.md) | **Plan de corrección en 15 lotes** por causa raíz, con tests antes/después y criterios de terminado |
| **43** | [**UIBUG_FIX_TRACEABILITY**](43_UIBUG_FIX_TRACEABILITY.md) | Seguimiento de la corrección: UIBUG → grupo → test → código → verificación en dispositivo → estado |
| 44 | [NUMERIC_INPUT_SPEC](44_NUMERIC_INPUT_SPEC.md) | Especificación de la entrada numérica es-BO (regla única de UIBUG-003) |
| 45 | [UI_AUDIT_FINAL_VERIFICATION](45_UI_AUDIT_FINAL_VERIFICATION.md) | Cierre de la fase de corrección del backlog: 17/17 rutas, flujos y veredicto de entonces (histórico, íntegro) |

### Capa 5 — Congelación de la baseline

| # | Documento | Contenido |
|---|-----------|-----------|
| **46** | [**BASELINE_FINAL_FREEZE**](46_BASELINE_FINAL_FREEZE.md) | **Cierre definitivo del proyecto base**: baseline, estado de los 69 UIBUG, plan de un solo uso, campaña terminal, respaldo con fotografías, CI, 17/17 en Pixel 8, builds, limitaciones aceptadas y veredicto `READY FOR EVOLUTION` |

### Capa 6 — Evolución posterior a la baseline

| Documento | Contenido |
|---|---|
| [**EVOLUTION_INDEX**](evolution/00_EVOLUTION_INDEX.md) | Entrada normativa para toda capacidad posterior a `v1.0.0-base-stable` |
| [EVOLUTION_ROADMAP](evolution/06_EVOLUTION_ROADMAP.md) | Orden aprobado: `EVOLUTION-2` y después `EVOLUTION-3` |
| [EVOLUTION_BACKLOG](evolution/16_EVOLUTION_BACKLOG.md) | Registro único de IDs, estados, dependencias y prioridad |
| [`features/`](evolution/features/) | Especificaciones, planes y verificaciones de cada evolución |

## Estado verificado del repositorio

Comandos ejecutados y su resultado real, por fase:

> **Nota**: la primera columna corresponde a la auditoría inicial de solo lectura. Después se
> ejecutó una **fase de estabilización** que sí modificó código, y después una **auditoría de
> interfaz** que **no** modificó código.

| Comando | Auditoría inicial | Tras la estabilización | Tras la auditoría de interfaz | **Al congelar la baseline (vigente)** |
|---|---|---|---|---|
| `flutter analyze` | 0 issues | 0 issues | 0 issues | **0 issues** |
| `dart format --set-exit-if-changed lib test` | 0 cambios | 0 cambios | 0 cambios | **0 cambios** |
| `flutter test` | 44 en verde | 91 en verde | 170 en verde | **253 en verde** |
| `flutter build apk --release` | no medido | ✅ compila | ✅ compila | ✅ **60,6 MB** (sin firmar) |
| `flutter build appbundle --release` | no medido | ✅ compila | ✅ compila | ✅ **58,6 MB** (sin firmar) |
| Verificación automática (CI) | no existía | no existía | no existía | ✅ **GitHub Actions verde** |
| Versión de esquema SQLite | 4 | 5 | 5 | **6** |
| Defectos CRITICAL abiertos | — | 0 conocidos | 0 | **0** |
| Defectos HIGH abiertos | — | — | 0 | **0** |
| Defectos MEDIUM / LOW abiertos | — | — | 9 | **0** |
| Decisiones de producto pendientes | — | — | 2 | **0** |
| Rutas verificadas en Pixel 8 | — | — | 17/17 | **17/17** |
| Respaldo incluye fotografías | no | no | no | **sí** |
| Veredicto de release | — | RELEASE CANDIDATE | RELEASE CANDIDATE | **READY FOR EVOLUTION** (distribución: keystore) |

> La suite pasó de 91 a 170 y de 170 a **253**. El hueco que dejó escapar UIBUG-001
> —`export()` sin cobertura y una suite que sólo corre sobre escritorio— está cerrado con
> `backup_android_semantics_test.dart`, que reproduce la restricción de Android. El que dejó
> escapar UIBUG-066 —una guarda que sólo miraba dos formas de escribir el defecto— está
> cerrado con `set_state_contract_test.dart`, que reconoce cualquier campo declarado `Future`.

Para saber **qué cambió en la estabilización y por qué**, lee
[34_CHANGE_TRACEABILITY](34_CHANGE_TRACEABILITY.md) y las secciones históricas de
[35_RELEASE_READINESS](35_RELEASE_READINESS.md).

Para saber **qué se encontró y por qué ocurría**, lee
[41_UIBUG_MASTER_BACKLOG](41_UIBUG_MASTER_BACKLOG.md); para **cómo se corrigió cada cosa y
cómo se comprobó**, [43_UIBUG_FIX_TRACEABILITY](43_UIBUG_FIX_TRACEABILITY.md).
[42_UIBUG_FIX_PLAN](42_UIBUG_FIX_PLAN.md) conserva el plan por lotes con el que se ejecutó.

Para saber **cómo quedó todo al congelar la baseline**, lee
[46_BASELINE_FINAL_FREEZE](46_BASELINE_FINAL_FREEZE.md). El cierre de la fase anterior sigue
en [45_UI_AUDIT_FINAL_VERIFICATION](45_UI_AUDIT_FINAL_VERIFICATION.md), sin modificar.

> **Nada conocido queda fuera del backlog.** Los tres defectos que aparecieron durante la fase
> de cierre (`066` el aviso de `setState`, `067` la cinta de campaña, `068` el rail en
> horizontal al 130 %) tienen ficha, causa, corrección y test, igual que los 66 originales.
