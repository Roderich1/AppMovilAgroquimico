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

## Estado verificado del repositorio al momento de la auditoría

Comandos ejecutados y su resultado real:

| Comando | Resultado |
|---|---|
| `flutter --version` | Flutter 3.47.2 · canal stable · Dart en `sdk: ^3.13.2` |
| `flutter analyze` | **No issues found!** |
| `dart format --set-exit-if-changed lib test` | **0 archivos cambiados** (39 formateados) |
| `flutter test` | **44 tests, todos en verde** |

El código fuente **no fue modificado** por esta auditoría. Los únicos archivos añadidos
son los de esta carpeta `docs/`.
