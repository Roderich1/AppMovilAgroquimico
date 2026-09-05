# 35 — Informe de preparación para release

Evaluación del estado del proyecto tras la fase de estabilización.
Fecha: **2026-09-05** · Rama: `hardening/stabilization` · Base: `5d0b8ef`

Cada sección se clasifica como **READY**, **PARTIALLY READY** o **NOT READY**, con evidencia.

## Veredicto global: **RELEASE CANDIDATE**

El proyecto está funcionalmente correcto, probado y compilable, con un único bloqueo externo
—el keystore de firma— que **no puede resolverse técnicamente** porque depende de un secreto
que solo el propietario puede proporcionar.

---

## 1. Corrección funcional — **READY**

| Evidencia | Resultado |
|---|---|
| `flutter analyze` | 0 issues |
| `flutter test` | **91 / 91** en verde |
| Defectos P0 conocidos | **0 abiertos** (2 corregidos: STAB-001, STAB-002) |
| Defectos P1 conocidos | 0 abiertos sin justificación documentada |

Los dos defectos que rompían la aplicación —navegación en blanco al volver del formulario de
compra, y esquema divergente entre instalaciones nuevas y migradas— están corregidos con
tests de regresión que fallaban antes del cambio.

## 2. Integridad de la base de datos — **READY**

| Evidencia | Resultado |
|---|---|
| Versión de esquema | 5 |
| Equivalencia base nueva ↔ migrada | ✅ verificada automáticamente |
| `PRAGMA foreign_keys` | Activado en `onConfigure` |
| Invariante de campaña única activa | Índice único parcial + lógica transaccional |
| Atomicidad de compras, aplicaciones y transferencias | Cubierta por 3 tests de rollback |

`test/schema_equivalence_test.dart` compara tablas, columnas (tipo, nullability, default, PK)
e índices (**incluida la unicidad**) entre una base creada desde cero y una migrada desde v3.
Cualquier divergencia futura hará fallar la suite.

## 3. Seguridad de las migraciones — **READY**

| Criterio | Estado |
|---|---|
| Migraciones históricas sin modificar | ✅ Se añadió v5; no se tocó v1–v4 |
| Migración no destructiva | ✅ v5 no borra ni modifica filas de usuario |
| Comportamiento ante datos anómalos | ✅ Con duplicados preexistentes conserva el índice no único y registra la anomalía en `app_settings`, en vez de fallar o borrar |
| Cobertura de test | v1→v2, v3→v4, v3→v5 (equivalencia completa), y el caso con duplicados |

**Hueco restante**: la migración **v2→v3** no tiene test propio. Su riesgo es bajo porque el
test de equivalencia desde v3 valida el estado final, pero queda registrado.

## 4. Recuperación de datos — **PARTIALLY READY**

| Capacidad | Estado |
|---|---|
| Exportar backup | ✅ Con `wal_checkpoint(FULL)` previo |
| **Restaurar backup** | ✅ **Nuevo** — con validación y copia de seguridad previa |
| Validar el archivo | ✅ Integridad, tablas requeridas y versión de esquema |
| Protección ante sobrescritura accidental | ✅ Confirmación explícita + copia previa recuperable |
| Restauración transaccional | ✅ Si la copia falla, restituye el estado anterior |
| Migración de un backup antiguo | ✅ Se migra al reabrir |
| **Fotografías de factura** | ❌ **No se incluyen en el backup** |
| Backup automático o programado | ❌ Sigue siendo manual |
| Cifrado del backup | ❌ El archivo queda en claro |

Es **PARTIALLY READY** y no READY porque una restauración en otro dispositivo recupera toda
la contabilidad pero **no las imágenes de factura**. La aplicación lo detecta y lo comunica,
sin romperse.

## 5. Manejo de errores — **READY**

| Criterio | Estado |
|---|---|
| Un error nunca se muestra como "cargando" | ✅ Corregido en 4 pantallas |
| Un error nunca se muestra como "sin datos" | ✅ `EmptyState` de error distinto del de vacío |
| Mensajes en lenguaje de usuario | ✅ `friendlyError` aplicado de forma uniforme |
| Manejadores globales | ✅ `FlutterError.onError` y `PlatformDispatcher.onError` |
| Diagnóstico persistente | ✅ Log local con niveles y rotación |
| `catch` que silencian errores | Quedan 1 (`settlements_screen`, inofensivo: `parseMinor` no lanza) |

**Hueco restante**: `friendlyError` sigue sin traducir `DatabaseException`, por lo que una
violación de restricción de SQLite llega al usuario en texto técnico. Registrado.

## 6. Navegación — **READY**

| Criterio | Estado |
|---|---|
| Rutas del shell | ✅ 5 destinos probados |
| Rutas fuera del shell | ✅ `push` en las 3 vías al formulario de compra |
| Volver atrás | ✅ Sin excepciones, deja pantalla utilizable |
| Semántica `go` vs `push` | ✅ Explícita mediante `isForm` |
| Protección de formularios sucios | ✅ `PopScope` ya existente, ahora ejercitado de extremo a extremo |

## 7. Testing — **READY**

| Métrica | Antes | Después |
|---|---:|---:|
| Tests | 44 | **91** |
| Archivos de test | 13 | **20** |

Áreas nuevas cubiertas: equivalencia de esquema, navegación real, reportes y dashboard,
backup y restauración, logging, estados de error, acciones destructivas.

Los valores esperados de los reportes se derivan a mano en los comentarios del test, no
reproduciendo la fórmula de producción.

**Huecos restantes**: bitácora de chaco, detalle de inventario y `detailedStatement` siguen
sin tests propios.

## 8. Seguridad — **PARTIALLY READY**

| Hallazgo | Estado |
|---|---|
| S-01 Firma de release con clave de depuración | ✅ **Corregido** |
| Secretos en el repositorio | ✅ Ninguno; `key.properties` y `*.jks` ignorados |
| Inyección SQL | ✅ 100 % parametrizado |
| Logs con datos sensibles | ✅ El log documenta y aplica no registrar datos de negocio |
| S-02 Base de datos sin cifrar | ❌ Sin cambios |
| S-03 Backup sin cifrar en Descargas | ❌ Sin cambios |
| S-04 `android:allowBackup` sin desactivar | ❌ Sin cambios |
| S-05 Sin control de acceso | ❌ Sin cambios (decisión de producto pendiente) |
| S-06 Sin trazabilidad de autoría | ❌ Sin cambios |

Los pendientes son riesgos **conocidos y documentados**, cuya resolución depende de una
decisión de producto (¿uno o varios operadores?) que el código no puede tomar.

## 9. Rendimiento — **PARTIALLY READY**

Sin regresiones: la suite completa sigue ejecutándose en ~15 s.

**No abordado en esta fase** (P-01 de `25_PERFORMANCE_AUDIT.md`): cuatro pantallas siguen
creando su `Future` dentro de `build()`, lo que relanza consultas y provoca parpadeo. Es el
único hallazgo de rendimiento con efecto visible; se dejó fuera por priorizar corrección e
integridad de datos.

## 10. Build — **READY**

| Artefacto | Resultado |
|---|---|
| `flutter build apk --release` | ✅ `app-release.apk` (~60 MB) |
| `flutter build appbundle --release` | ✅ `app-release.aab` (~58 MB) |
| `flutter analyze` | ✅ 0 issues |
| `dart format lib test` | ✅ 0 cambios |

> `dart format .` sobre el repositorio completo falla en Windows al recorrer `build/`. No es
> un defecto del código: use `dart format ... lib test`.

## 11. Firma — **NOT READY (bloqueo externo)**

El mecanismo está completo y verificado, pero **falta el secreto**:

- ✅ `build.gradle.kts` lee `android/key.properties` y crea un `signingConfig` real.
- ✅ Sin ese archivo, la release queda **sin firmar** en lugar de firmarse en depuración.
  Verificado: el APK generado no contiene entradas de firma en `META-INF`.
- ✅ `key.properties.example` documenta exactamente qué hace falta.
- ❌ **No existe keystore.** No se generó ninguno: inventar uno sería peor que no tenerlo,
  porque quedaría sin custodia y sin copia de seguridad.

**Acción requerida del propietario**: generar y custodiar el keystore y crear
`android/key.properties`. Instrucciones en
[20_BUILD_AND_CONFIGURATION](20_BUILD_AND_CONFIGURATION.md).

Hasta entonces el binario **no es instalable ni publicable**. Es el único bloqueo real.

## 12. Documentación — **READY**

| Documento | Estado |
|---|---|
| `32_STABILIZATION_BASELINE.md` | Nuevo — estado previo medido |
| `33_STABILIZATION_FINDINGS.md` | Nuevo — matriz de hallazgos verificados |
| `34_CHANGE_TRACEABILITY.md` | Nuevo — hallazgo → código → test → doc |
| `35_RELEASE_READINESS.md` | Este documento |
| `08`, `10`, `13`, `17`, `20`, `22`, `27` | Actualizados con el estado real |

## 13. Limitaciones conocidas

Ninguna oculta. Todas registradas:

| Limitación | Documento |
|---|---|
| El backup no incluye las fotografías de factura | `13_LOCAL_STORAGE.md` |
| Sin backup automático ni cifrado | `14_OFFLINE_AND_SYNC.md` |
| Sin control de acceso a la aplicación | `12_AUTHENTICATION.md` |
| Sin trazabilidad de autoría de operaciones | `23_SECURITY_AUDIT.md` S-06 |
| `DatabaseException` sin traducir al usuario | `17_ERROR_HANDLING.md` E-01 |
| 4 pantallas crean el `Future` en `build()` | `25_PERFORMANCE_AUDIT.md` P-01 |
| Lecturas sin tipar (`Map<String, Object?>`) | `24_CODE_QUALITY_AUDIT.md` Q-01 |
| La app no funciona en web | `27_KNOWN_ISSUES.md` KI-19 |
| Sin fecha editable en operaciones | `27_KNOWN_ISSUES.md` KI-14 |
| Migración v2→v3 sin test propio | Este documento, sección 3 |
| Sin CI | `29_IMPROVEMENT_AUDIT.md` M-20 |
| Naming del producto inconsistente | `26_TECHNICAL_DEBT.md` DT-10 |

## Checklist de cierre

| Criterio de terminación | Estado |
|---|---|
| No quedan P0 conocidos | ✅ |
| P1 corregidos o justificados | ✅ |
| Esquema limpio ≡ migrado | ✅ verificado automáticamente |
| Tests sobre reglas y cálculos críticos | ✅ |
| Navegación crítica con tests | ✅ |
| Reportes críticos con tests | ✅ |
| Operaciones destructivas protegidas | ✅ |
| Estrategia de backup y restauración | ✅ (sin fotografías) |
| `flutter analyze` limpio | ✅ |
| Formatter limpio | ✅ |
| Todos los tests pasan | ✅ 91/91 |
| Build de release producible | ✅ compila; ⚠️ sin firmar por falta de keystore |
| Documentación refleja el código | ✅ |
| Trazabilidad de cambios importantes | ✅ |
| `KNOWN_ISSUES` no oculta defectos | ✅ |
| Diff final revisado | ✅ |
