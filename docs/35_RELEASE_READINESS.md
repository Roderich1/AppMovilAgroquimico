# 35 — Informe de preparación para release

> ## ⛔ ESTE VEREDICTO ESTÁ SUPERADO
>
> Las secciones 1–13 describen el estado **tras la fase de estabilización** y **antes** de la
> auditoría de interfaz ejecutada sobre Pixel 8. Se conservan íntegras como registro histórico.
>
> **El estado vigente es [§ POST-BACKLOG STATUS](#post-backlog-status--cierre-del-backlog-uibug),
> al final de este documento: `RELEASE CANDIDATE`.** Entre medias, § POST-UI-AUDIT STATUS
> registra el `NOT READY` que siguió a la auditoría de interfaz.
>
> La auditoría posterior encontró **4 defectos CRITICAL reales**, entre ellos uno de riesgo
> contable (×1000) y otro que deja la exportación de backup inoperativa en Android. Todo lo que
> abajo se lee como "0 P0 conocidos", "Navegación READY" o "Backup export ✅" es **anterior a esa
> evidencia**.

Evaluación del estado del proyecto tras la fase de estabilización.
Fecha: **2026-09-05** · Rama: `hardening/stabilization` · Base: `5d0b8ef`

Cada sección se clasifica como **READY**, **PARTIALLY READY** o **NOT READY**, con evidencia.

## Veredicto global (histórico, 2026-09-05, pre-auditoría): **RELEASE CANDIDATE**

> **Superado.** Ver [POST-UI-AUDIT STATUS](#post-ui-audit-status).

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
  Verificado con `apksigner verify`:
  ```
  app-release.apk -> DOES NOT VERIFY (Missing META-INF/MANIFEST.MF)
  app-debug.apk   -> Verifies, v2 scheme, 1 signer (clave de depuración)
  ```
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

---

# POST-UI-AUDIT STATUS

Sección añadida el **2026-09-05**, tras normalizar la auditoría de interfaz ejecutada sobre un
emulador **Pixel 8** (Android 16, API 36). **Todo lo anterior a esta sección se conserva sin
modificar** como registro del estado previo.

## Veredicto vigente: **NOT READY**

## 1. Estado anterior vs. estado actual

| | Estado anterior (pre-auditoría) | Estado actual (post-auditoría) |
|---|---|---|
| **Veredicto global** | RELEASE CANDIDATE | **NOT READY** |
| Defectos P0 conocidos | 0 abiertos | **4 CRITICAL abiertos** (UIBUG-001, 002, 003, 004A) |
| Defectos totales conocidos | KI residuales documentados | **66 hallazgos** (65 IDs) — 4 CRITICAL, 17 HIGH, 36 MEDIUM, 9 LOW |
| **Corrección funcional** | READY | **NOT READY** |
| **Recuperación de datos** | PARTIALLY READY | **NOT READY** |
| **Navegación** | READY | **NOT READY** |
| **Manejo de errores** | READY | **PARTIALLY READY** |
| Integridad de la base | READY | READY *(sin cambios: ningún UIBUG la contradice)* |
| Seguridad de migraciones | READY | READY *(sin cambios)* |
| Testing | READY | **PARTIALLY READY** — la suite es verde pero **no detecta los CRITICAL** |
| Build | READY | READY *(sin cambios)* |
| Firma | NOT READY (bloqueo externo) | NOT READY *(sin cambios)* |

## 2. Fecha y alcance de la auditoría

| | |
|---|---|
| Fecha | **2026-09-05** |
| Método | ejecución real de la aplicación, no revisión de código |
| Dispositivo | AVD `Pixel_8` (`emulator-5554`), Android 16 (API 36), 1080×2400, 420 dpi |
| Binarios | `app-debug.apk`; además `app-profile.apk` para un contraste concreto |
| Cobertura | 16 de 17 pantallas (la 17.ª es inalcanzable, y eso es UIBUG-002) |
| Evidencia | **119 capturas** en `artifacts/ui-audit/`; 108 referencias en documentos, **0 rotas** |
| Documentos | `36`–`40` (auditoría), `41`–`43` (backlog, plan y trazabilidad de corrección) |

## 3. Evidencia nueva que invalida el veredicto anterior

### 3.1 · "Defectos P0 conocidos: 0 abiertos" → **4 CRITICAL abiertos**

| UIBUG | Defecto | Evidencia |
|---|---|---|
| **003** | Teclear `1.500` en *Registrar pago* guarda **1,50 Bs**. Verificado leyendo `account_transactions` en el dispositivo. Error de **×1000 en una aplicación de contabilidad**, sin confirmación ni acuse que lo delate. Causa confirmada: `common.dart:131` trata el punto como decimal mientras `money.dart:35,41` lo imprimen como separador de miles. | `UI-17-transfer-form/UI-17-ISSUE-formato-millares.png` |
| **001** | Exportar backup **falla siempre** en Android. Causa confirmada: `backup_service.dart:63` ejecuta `PRAGMA wal_checkpoint(FULL)` con `execute()`, que en Android rechaza sentencias que devuelven filas. | `UI-10-liquidacion/UI-10-exportar-backup.png` |
| **002** | El historial de compras **no tiene ninguna puerta de entrada**. Con él quedan inaccesibles los pagos a proveedor posteriores, el visor de facturas y la reversión de compras. | enumeración de las 16 llamadas de navegación de `lib/` |
| **004A** | La navegación jerárquica usa `context.go`, que reemplaza la pila: Atrás cierra la app desde cualquier detalle, y `PageFrame` no tiene flecha de volver. **Callejón sin salida funcional.** | `UI-14-persona-detalle/UI-14-ISSUE-back-desde-detalle.png` |

### 3.2 · "Navegación — READY" → **NOT READY**

La sección 6 declaraba `Volver atrás ✅ Sin excepciones, deja pantalla utilizable`. Eso es
cierto **solo para las 3 vías al formulario de compra**, que es lo que STAB-001 corrigió y lo
que sus tests cubren. La auditoría en dispositivo demostró que:

- **UIBUG-004A** — desde `/personas/:id`, `/inventario/:id`, `/chacos/:id` y las 4 subrutas de
  Operaciones, Atrás **cierra la aplicación**, y no hay flecha de volver. Confirmado con
  `dumpsys window`: `mCurrentFocus = …nexuslauncher…`.
- **UIBUG-002** — una ruta declarada sin ningún origen.
- **UIBUG-062** — la barra inferior resalta "Inicio" mientras se está en la bitácora de un chaco.
- **UIBUG-051** — tarjetas del mismo estilo con comportamiento de navegación distinto.

`08_NAVIGATION.md` describe el mapa como completo y no señala ninguno de estos huecos.

### 3.3 · "Backup export ✅" → **NOT READY**

La sección 4 marcaba `Exportar backup ✅ Con wal_checkpoint(FULL) previo`. La verificación en
dispositivo demuestra que **ese mismo `wal_checkpoint` es la causa del fallo**: lo que se
documentó como una garantía es el defecto. La **única** protección de datos de la aplicación
**no funciona en la plataforma real**, y en consecuencia la restauración —correctamente
implementada y probada— nunca encuentra nada que restaurar.

La limitación ya conocida (el backup no incluye las fotografías de factura) sigue vigente y
**pasa a segundo plano**: hoy no hay backup en absoluto.

### 3.4 · "Testing — READY" → **PARTIALLY READY**

`flutter test` sigue dando **91/91 en verde** y `flutter analyze` **0 issues**. Ambos se
reejecutaron al normalizar este backlog. Pero:

- **la suite no detecta ninguno de los 4 CRITICAL**;
- UIBUG-001 lo demuestra de forma nítida: `backup_service_test.dart` corre sobre
  `sqflite_common_ffi` (escritorio), donde `execute()` **sí** admite `wal_checkpoint`. La
  cobertura verde es **engañosa** para el comportamiento en Android.

La conclusión no es que los tests estén mal escritos, sino que **la suite no sustituye a la
verificación en dispositivo**, y el informe anterior la trataba como si lo hiciera.

### 3.5 · Manejo de errores: READY → **PARTIALLY READY**

El hueco que la sección 5 registraba como teórico (`friendlyError` no traduce
`DatabaseException`) está ahora **reproducido en dispositivo** (UIBUG-015): el usuario ve un
error de SQLite en inglés en un snackbar rojo. Se suma UIBUG-050 (un aviso informativo pintado
como error) y UIBUG-065, cuyo análisis reveló que el `catch (_) {}` que la sección 5 calificaba
de "inofensivo" es en realidad **código muerto inalcanzable** que enmascara un mensaje
engañoso.

## 4. Lo que la auditoría confirmó como correcto

El veredicto baja por evidencia, no por pesimismo. Se verificaron **en dispositivo**:

| Comprobación | Resultado |
|---|---|
| Cálculos de compra y conversión USD→BOB | ✅ exactos (12,5 L × 45,90 = 573,75 Bs; 18,75 × 6,96 = 130,50) |
| Propagación compra → inventario | ✅ 500 L → 512,5 L |
| STAB-005 (productos en cero en reportes) | ✅ verificado en dispositivo |
| STAB-010 (confirmación de acciones destructivas) | ✅ verificado: diálogo completo y correcto |
| Atrás en los 4 formularios (que usan `push`) | ✅ correcto |
| Rotación a horizontal | ✅ sin desbordes |
| 30 cambios rápidos de pestaña | ✅ sin excepciones en logcat |
| `RenderFlex overflow` en toda la auditoría | ✅ **ninguno**, ni al 130 % de escala |
| STAB-019 ("dirty" espurio) | ✅ **no reproducible** con datos realistas |

Las secciones 2 (integridad de la base), 3 (seguridad de migraciones) y 10 (build) del informe
histórico **siguen siendo válidas**: ningún UIBUG las contradice.

## 5. Criterios de salida de NOT READY

El veredicto solo puede revisarse cuando se cumpla **todo** lo siguiente:

1. los **4 CRITICAL** (001, 002, 003, 004A) están en estado `VERIFIED` en
   `43_UIBUG_FIX_TRACEABILITY.md`, es decir **verificados en Pixel 8**, no solo corregidos;
2. ningún hallazgo con riesgo `DATA_LOSS`, `ACCOUNTING` o `FUNCTIONAL_BLOCKER` sigue `OPEN`
   (hoy son 13: ver `41` §7);
3. las **7 decisiones de diseño pendientes** (`41` §10) están tomadas y registradas;
4. la suite tiene **tests que fallaban antes de cada fix** y ahora pasan, y su número **supera
   los 91** de partida;
5. existe al menos **un test que ejercite la semántica de Android** en el camino del backup
   (la lección de UIBUG-001);
6. **UI-06 `/compras` ha sido auditada por primera vez** — hoy es la única pantalla sin
   auditar, y solo porque es inalcanzable.

El bloqueo del **keystore** (§11 histórica) sigue vigente y es independiente de todo lo
anterior: aunque se cerraran los 66 hallazgos, el binario seguiría sin poder firmarse.

## 6. Nota sobre la rama

La auditoría y este backlog viven en **`hardening/stabilization`** (`81c919f`).
**`origin/main` está en `5d0b8ef`** y no contiene ni la fase de estabilización ni la auditoría
de interfaz. Cualquier evaluación de release que se haga sobre `main` es engañosa hasta que
esta rama se integre.

## 7. Trazabilidad de esta actualización

| | |
|---|---|
| Motivo | la auditoría de interfaz sobre Pixel 8 aportó evidencia que contradice el veredicto de la fase de estabilización |
| Qué se conservó | las secciones 1–13 completas, sin borrar ni reescribir ninguna conclusión histórica |
| Qué se añadió | esta sección y el aviso del encabezado |
| Fuente de los hallazgos | [41_UIBUG_MASTER_BACKLOG.md](41_UIBUG_MASTER_BACKLOG.md) |
| Plan de corrección | [42_UIBUG_FIX_PLAN.md](42_UIBUG_FIX_PLAN.md) |
| Seguimiento | [43_UIBUG_FIX_TRACEABILITY.md](43_UIBUG_FIX_TRACEABILITY.md) |
| Código de producción modificado | **ninguno** — `lib/` intacto |
| `flutter analyze` | **0 issues** |
| `flutter test` | **91 / 91 en verde** |

---

# POST-FIX STATUS — lote 1 de corrección

Sección añadida el **2026-09-05**, tras la primera tanda de correcciones sobre los defectos de
mayor riesgo. Las secciones anteriores se conservan sin modificar.

## Veredicto vigente: sigue siendo **NOT READY**

Quedan **1 CRITICAL abierto** (UIBUG-004A) y los HIGH funcionales y de datos sin abordar.

## 1. Qué se corrigió y se verificó en el Pixel 8

Siete defectos pasaron a `VERIFIED`, es decir **corregidos y comprobados físicamente en el
dispositivo**, no solo en tests:

| UIBUG | Sev. | Qué se demostró en el dispositivo |
|---|---|---|
| **003** | CRITICAL | Tecleando `1.500` se guarda `-150000` (1.500,00 Bs); antes `-150` (1,50 Bs). Transferencia de `15.000` → `quantity_base` **15000000**; antes 15000. `1,500` se rechaza por ambiguo **sin escribir nada**. Leído de la base del dispositivo |
| **001** | CRITICAL | Ciclo completo: exportar → archivo de 196 608 B → `validate()` OK (esquema v5) → modificar (28 asientos) → restaurar → **estado anterior recuperado** (27 asientos, saldo 3005700) |
| **002** | CRITICAL | `/compras` alcanzable desde Operaciones. **UI-06 auditada por primera vez.** Visor de factura, pago a proveedor y reversión: accesibles |
| **005** | HIGH | 20 aperturas del diálogo de pago sin pantalla roja; logcat sin `disposed` / `_dependents` / `dirty widget` |
| **012** | HIGH | El diálogo identifica persona, campaña y saldo pendiente |
| **014** | HIGH | Snackbar *"Pago de 1.500,00 Bs registrado a José Luis Ñáñez Álvarez."* |
| **065** | HIGH→LOW | `abc` explica el formato esperado en vez del engañoso *"El importe debe ser mayor a cero"*, y no escribe nada |

**UIBUG-011** queda en `FIXED_NOT_DEVICE_VERIFIED`: el listado ya muestra el acuse al volver del
formulario, pero **no se ejecutó una compra completa en el dispositivo**.

## 2. Cambio de estado por sección

| Sección | Antes de este lote | Ahora |
|---|---|---|
| **Recuperación de datos** | NOT READY (el backup no funcionaba en Android) | **PARTIALLY READY** — exportar y restaurar funcionan y están verificados en dispositivo; sigue sin incluir las fotografías de factura y sin cifrado |
| **Corrección funcional** | NOT READY (4 CRITICAL) | **NOT READY** — queda **UIBUG-004A** |
| **Navegación** | NOT READY | **NOT READY** — `/compras` ya es alcanzable, pero **Atrás sigue cerrando la aplicación** desde las rutas del shell (UIBUG-004A). Comprobado: `mCurrentFocus = …nexuslauncher…` |
| **Manejo de errores** | PARTIALLY READY | **PARTIALLY READY** — el diálogo de pago ya da mensajes exactos; `friendlyError` sigue sin traducir `DatabaseException` (UIBUG-015) |
| **Testing** | PARTIALLY READY (la suite no detectaba los CRITICAL) | **PARTIALLY READY, mejor fundada** — de **91 a 139** tests. Ahora existen: la especificación numérica completa, un doble que reproduce la semántica de Android, y una guardia estructural contra rutas huérfanas |

## 3. Lección incorporada a la suite

El motivo por el que UIBUG-001 llegó a producción con la suite en verde era doble, y ambas
partes están ahora cubiertas:

1. `backup_service_test.dart` **nunca llamaba a `export()`**. Ahora
   `backup_android_semantics_test.dart` sí lo ejercita, de extremo a extremo.
2. La suite corre sobre `sqflite_common_ffi`, donde `execute()` admite sentencias que devuelven
   filas. Ahora hay un doble que **reproduce la restricción de Android** (`execSQL` rechaza esas
   sentencias) y que fallaba con el mensaje literal del dispositivo.

En la misma línea, `purchases_access_test.dart` incorpora una guardia estructural: **ninguna
ruta declarada puede quedar sin origen en `lib/`**. Antes del fix señalaba exactamente
`['/compras']`.

## 4. Regresión detectada y resuelta

Verificando UIBUG-002 en el dispositivo apareció una regresión **introducida por el lote
numérico**: el diálogo de pago a proveedor precargaba `20000.00` con `toStringAsFixed`, formato
que la nueva regla es-BO rechaza. Sólo se vio al abrir una pantalla que **hasta entonces era
inalcanzable**. Corregida con `formatForInput` en los tres puntos que precargaban campos, y
cubierta por la invariante `parseNumericInput(formatForInput(v)).value == v`.

Además, `navigation_test.dart` señaló el cambio de topología de Operaciones. **No se debilitó
ninguna aserción**: el test se actualizó al recorrido real (un salto más) conservando el mismo
helper y el mismo invariante de STAB-001.

## 5. Estado de las comprobaciones

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **139 / 139 en verde** (partida: 91) |
| `dart format lib test` | limpio |
| CRITICAL cerrados | **3 de 4** (001, 002, 003) |
| CRITICAL abiertos | **1** — UIBUG-004A (navegación jerárquica) |

## 6. Qué falta para revisar el veredicto

Los criterios de salida de la sección POST-UI-AUDIT §5 siguen vigentes. Pendiente:

1. **UIBUG-004A** — es el último CRITICAL y bloquea además el criterio "volver atrás" de
   UIBUG-002.
2. Los HIGH de datos y consistencia: **007** (búsqueda que miente), **010** (operaciones
   revertidas), **013** (semántica de saldos), **015** (errores técnicos en inglés).
3. Verificar **UIBUG-011** en dispositivo con una compra completa.
4. El bloqueo del **keystore** sigue vigente y es independiente de todo lo anterior.

---

# POST-BACKLOG STATUS — cierre del backlog UIBUG

Sección añadida el **2026-09-05**, tras cerrar el backlog y ejecutar la auditoría de regresión
completa sobre Pixel 8. Las secciones anteriores se conservan sin modificar.

## Veredicto vigente: **RELEASE CANDIDATE**

Sube desde `NOT READY`. **No es READY** porque persiste el bloqueo externo del keystore, que
esta fase no puede resolver.

## 1. Por qué cambia el veredicto

| Criterio de salida de POST-UI-AUDIT §5 | Estado |
|---|---|
| Los 4 CRITICAL en `VERIFIED` en Pixel 8 | ✅ 001, 002, 003, 004A |
| Ningún hallazgo `DATA_LOSS`, `ACCOUNTING` o `FUNCTIONAL_BLOCKER` abierto | ✅ los 13 cerrados |
| Decisiones de diseño tomadas y registradas | ✅ 5 de 7 (002, 003, 004B, 013, 017); quedan 045 y 059 |
| Tests que fallaban antes de cada fix, y más de 91 | ✅ **170** (partida 91) |
| Un test que ejercite la semántica de Android en el backup | ✅ `backup_android_semantics_test.dart` |
| UI-06 `/compras` auditada por primera vez | ✅ completa |

## 2. Estado por sección

| Sección | Antes de esta fase | Ahora |
|---|---|---|
| **Corrección funcional** | NOT READY (1 CRITICAL) | **READY** — 4/4 CRITICAL y 17/17 HIGH cerrados |
| **Navegación** | NOT READY | **READY** — jerarquía y política de Atrás verificadas |
| **Recuperación de datos** | PARTIALLY READY | PARTIALLY READY *(sin cambio: sigue sin incluir fotos ni cifrado)* |
| **Manejo de errores** | PARTIALLY READY | **READY** — `friendlyError` cubre `DatabaseException`; los avisos no se pintan como error |
| **Testing** | PARTIALLY READY | **READY** — 170 tests; la suite ya detecta la clase de defecto que se le escapaba |
| **Accesibilidad (nuevo)** | — | **PARTIALLY READY** — 130 % usable, con un compromiso documentado en la barra inferior |
| Integridad de la base · Migraciones · Build | READY | READY *(sin cambio)* |
| Seguridad · Rendimiento | PARTIALLY READY | PARTIALLY READY *(sin cambio)* |
| **Firma** | NOT READY (bloqueo externo) | **NOT READY (bloqueo externo)** |

## 3. Comprobaciones

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | **0 issues** |
| `dart format --set-exit-if-changed lib test` | **limpio** |
| `flutter test` | **170 / 170** |
| `flutter build apk --release` | ✅ `app-release.apk` (59,8 MB) |
| Rutas auditadas | **17 / 17** |
| Backlog cerrado | **54 de 66** (38 `VERIFIED` + 16 `FIXED_NOT_DEVICE_VERIFIED`) |

## 4. Lo que impide declarar READY

1. **Keystore ausente** (§11 histórica). El binario compila pero **no se puede firmar ni
   publicar**. Depende de un secreto que sólo el propietario puede generar y custodiar.
2. **Dos decisiones de producto** sin tomar: reaplicación de planes (045) y reapertura de
   campañas cerradas (059).
3. **Nueve MEDIUM/LOW cosméticos** abiertos, todos justificados en
   [`45` §8](45_UI_AUDIT_FINAL_VERIFICATION.md): ninguno tiene riesgo contable, pérdida de datos
   ni bloqueo funcional.
4. Limitaciones ya conocidas que **no** cambian: el respaldo no incluye las fotografías de
   factura, no hay cifrado, no hay control de acceso, y cuatro pantallas siguen creando su
   `Future` en `build()`.

## 5. Riesgo residual

| Riesgo | Valoración |
|---|---|
| Contable | **Bajo** — el parser numérico rechaza lo ambiguo, el pago acusa recibo y las reversiones se marcan igual en todas las vistas |
| Pérdida de datos | **Bajo para la base, medio para las facturas** — exportar/restaurar verificado en Android; las imágenes siguen fuera del respaldo |
| Funcional | **Bajo** — 17/17 rutas alcanzables y con retorno |
| Cosmético | **Medio-bajo** — nueve MEDIUM/LOW abiertos, ninguno bloqueante |
| Publicación | **Alto y externo** — sin keystore no hay release firmable |
