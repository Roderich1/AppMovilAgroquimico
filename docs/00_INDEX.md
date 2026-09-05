# Documentación técnica — Agrocuentas V2 (`agroquimicos`)

Línea base generada por auditoría de código sobre el repositorio **tal como existe hoy**.
Ninguna afirmación de estos documentos proviene de suposiciones: cada regla, endpoint,
pantalla o flujo está referenciado a un archivo y, cuando aplica, a una línea concreta.

Cuando algo no pudo determinarse desde el código, aparece marcado explícitamente como
`NO CONFIRMADO EN EL REPOSITORIO` o `REQUIERE INFORMACIÓN DEL DESARROLLADOR`.

## Punto de entrada recomendado

Si es la primera vez que tocas este proyecto, lee **[28_SYSTEM_MAP.md](28_SYSTEM_MAP.md)** primero
(15–30 min) y vuelve al resto según necesites.

## Índice

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
| 32 | [STABILIZATION_BASELINE](32_STABILIZATION_BASELINE.md) | Estado medido **antes** de estabilizar |
| 33 | [STABILIZATION_FINDINGS](33_STABILIZATION_FINDINGS.md) | Hallazgos verificados (STAB-001…019) |
| 34 | [CHANGE_TRACEABILITY](34_CHANGE_TRACEABILITY.md) | Hallazgo → código → test → documento |
| 35 | [RELEASE_READINESS](35_RELEASE_READINESS.md) | **Informe de preparación para release** |
| 36 | [UI_AUDIT_DATASET](36_UI_AUDIT_DATASET.md) | Dataset determinista de la auditoría de interfaz y procedimiento RESET/SEED |
| 37 | [UI_SCREEN_INVENTORY](37_UI_SCREEN_INVENTORY.md) | Inventario de pantallas, matriz de cobertura y matriz de flujos |
| 38 | [UI_AUDIT_FINDINGS](38_UI_AUDIT_FINDINGS.md) | **Los 56 UIBUG observados en el Pixel 8** |
| 39 | [UI_AUDIT_TRACEABILITY](39_UI_AUDIT_TRACEABILITY.md) | UIBUG → pantalla → feature → regla → evidencia → archivo |
| 40 | [UI_AUDIT_SUMMARY](40_UI_AUDIT_SUMMARY.md) | **Resumen ejecutivo de la auditoría de interfaz** |

## Estado verificado del repositorio al momento de la auditoría

Comandos ejecutados y su resultado real:

> **Nota**: esta sección describía la auditoría inicial de solo lectura. Después se ejecutó
> una **fase de estabilización** que sí modificó código. El estado vigente es el de abajo.

| Comando | Auditoría inicial | Tras la estabilización |
|---|---|---|
| `flutter analyze` | 0 issues | **0 issues** |
| `dart format --set-exit-if-changed lib test` | 0 cambios | **0 cambios** |
| `flutter test` | 44 en verde | **91 en verde** |
| `flutter build apk --release` | no medido | ✅ compila |
| `flutter build appbundle --release` | no medido | ✅ compila |
| Versión de esquema SQLite | 4 | **5** |

Para saber qué cambió y por qué, empieza por
[35_RELEASE_READINESS](35_RELEASE_READINESS.md) y
[34_CHANGE_TRACEABILITY](34_CHANGE_TRACEABILITY.md).
