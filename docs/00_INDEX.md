# Documentación técnica — Agrocuentas V2 (`agroquimicos`)

Línea base generada por auditoría de código sobre el repositorio **tal como existe hoy**.
Ninguna afirmación de estos documentos proviene de suposiciones: cada regla, endpoint,
pantalla o flujo está referenciado a un archivo y, cuando aplica, a una línea concreta.

Cuando algo no pudo determinarse desde el código, aparece marcado explícitamente como
`NO CONFIRMADO EN EL REPOSITORIO` o `REQUIERE INFORMACIÓN DEL DESARROLLADOR`.

## Estado vigente del proyecto

> **Veredicto de release: `RELEASE CANDIDATE`** — ver
> [35_RELEASE_READINESS § POST-BACKLOG STATUS](35_RELEASE_READINESS.md#post-backlog-status--cierre-del-backlog-uibug).
> **0 CRITICAL y 0 HIGH abiertos**; quedan 9 MEDIUM/LOW cosméticos justificados y el bloqueo
> externo del **keystore**.

La documentación de este repositorio está en **cuatro capas**, y confundirlas lleva a
conclusiones equivocadas:

| Capa | Documentos | Qué es | ¿Vigente? |
|---|---|---|---|
| **1 · Línea base y auditoría de código** | `01`–`31` | Descripción del sistema tal como está escrito. Se generó por lectura de código, **sin ejecutar la app**. | Vigente como descripción; sus veredictos de calidad son **anteriores** a las capas 2 y 3. |
| **2 · Estabilización (histórica)** | `32`–`35` | Fase que **sí modificó código** (STAB-001…019). Su informe de release concluía *RELEASE CANDIDATE*. | **Histórica.** El veredicto está **superado** por la capa 3; el análisis se conserva íntegro. |
| **3 · Auditoría de interfaz (posterior)** | `36`–`40` | Auditoría **ejecutando la aplicación** en Pixel 8. Encontró 65 defectos, 4 de ellos CRITICAL. | **Histórica como observación**; 54 de 66 ya corregidos. Para el estado vigente, `43` y `45`. |
| **4 · Backlog y cierre** | **`41`–`45`** | **Fuente de verdad operativa**: backlog normalizado, plan de corrección por lotes y trazabilidad. | **Vigente. Empieza aquí para trabajar.** |

**Documento de estado actual: [45_UI_AUDIT_FINAL_VERIFICATION](45_UI_AUDIT_FINAL_VERIFICATION.md).**
**Backlog vigente: [41_UIBUG_MASTER_BACKLOG](41_UIBUG_MASTER_BACKLOG.md).**

> **Rama**: la estabilización y la auditoría viven en `hardening/stabilization` (`81c919f`).
> **`origin/main` (`5d0b8ef`) no contiene ninguna de las dos.**

## Punto de entrada recomendado

| Si vienes a… | Empieza por |
|---|---|
| entender el sistema | **[28_SYSTEM_MAP.md](28_SYSTEM_MAP.md)** (15–30 min) |
| saber si se puede publicar | **[45 verificación final](45_UI_AUDIT_FINAL_VERIFICATION.md)** |
| corregir defectos | **[41 backlog](41_UIBUG_MASTER_BACKLOG.md)** → **[42 plan](42_UIBUG_FIX_PLAN.md)** |
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

### Capa 4 — Backlog vigente

| # | Documento | Contenido |
|---|-----------|-----------|
| **41** | [**UIBUG_MASTER_BACKLOG**](41_UIBUG_MASTER_BACKLOG.md) | **Backlog maestro — fuente de verdad operativa.** 66 entradas sobre 65 IDs, con causa raíz, riesgo, dependencias y prioridad |
| **42** | [**UIBUG_FIX_PLAN**](42_UIBUG_FIX_PLAN.md) | **Plan de corrección en 15 lotes** por causa raíz, con tests antes/después y criterios de terminado |
| **43** | [**UIBUG_FIX_TRACEABILITY**](43_UIBUG_FIX_TRACEABILITY.md) | Seguimiento de la corrección: UIBUG → grupo → test → código → verificación en dispositivo → estado |
| 44 | [NUMERIC_INPUT_SPEC](44_NUMERIC_INPUT_SPEC.md) | Especificación de la entrada numérica es-BO (regla única de UIBUG-003) |
| **45** | [**UI_AUDIT_FINAL_VERIFICATION**](45_UI_AUDIT_FINAL_VERIFICATION.md) | **Cierre**: 17/17 rutas auditadas, flujos, estado del backlog y veredicto de release |

## Estado verificado del repositorio

Comandos ejecutados y su resultado real, por fase:

> **Nota**: la primera columna corresponde a la auditoría inicial de solo lectura. Después se
> ejecutó una **fase de estabilización** que sí modificó código, y después una **auditoría de
> interfaz** que **no** modificó código.

| Comando | Auditoría inicial | Tras la estabilización | Tras la auditoría de interfaz (vigente) |
|---|---|---|---|
| `flutter analyze` | 0 issues | 0 issues | **0 issues** |
| `dart format --set-exit-if-changed lib test` | 0 cambios | 0 cambios | **0 cambios** |
| `flutter test` | 44 en verde | 91 en verde | **170 en verde** |
| `flutter build apk --release` | no medido | ✅ compila | ✅ compila (sin firmar) |
| `flutter build appbundle --release` | no medido | ✅ compila | ✅ compila (sin firmar) |
| Versión de esquema SQLite | 4 | 5 | **5** |
| Defectos CRITICAL abiertos | — | 0 conocidos | **0** (los 4 corregidos y verificados) |
| Defectos HIGH abiertos | — | — | **0** (los 17 corregidos) |
| Veredicto de release | — | RELEASE CANDIDATE | **RELEASE CANDIDATE** |

> La suite pasó de 91 a **170** tests. El hueco que dejó escapar UIBUG-001 —`export()` sin
> cobertura y una suite que sólo corre sobre escritorio— está cerrado con
> `backup_android_semantics_test.dart`, que reproduce la restricción de Android.

Para saber **qué cambió en la estabilización y por qué**, lee
[34_CHANGE_TRACEABILITY](34_CHANGE_TRACEABILITY.md) y las secciones históricas de
[35_RELEASE_READINESS](35_RELEASE_READINESS.md).

Para saber **qué está roto hoy y en qué orden se corrige**, lee
[41_UIBUG_MASTER_BACKLOG](41_UIBUG_MASTER_BACKLOG.md) y
[42_UIBUG_FIX_PLAN](42_UIBUG_FIX_PLAN.md).

Para saber **cómo quedó todo tras corregir el backlog**, lee
[45_UI_AUDIT_FINAL_VERIFICATION](45_UI_AUDIT_FINAL_VERIFICATION.md).
