# Conciliación de las REC de Mobile fuera de voz — 2026-10-19

- **Fecha real:** 2026-10-19 (America/La_Paz; UTC del mismo día).
- **Encargo:** decisión de Roderich Rendón del 2026-10-19 («Agrocuentas: integraciones, T3 y conciliación de tarjetas EI/REC», §4–§5): una única conciliación de 14 REC antes de planificar más desarrollo sobre ellas.
- **Preparación:** sesiones de Claude Code. B concilió #39, #40, #43, #46, #47, #48 y #50 (datos y reglas de negocio); C concilió #44, #51, #52, #53, #55, #56 y #57 (interfaz, reportes y recuperación); A consolidó este documento, comprobó por lectura una muestra de los hallazgos y redactó el dry-run de seguimiento.
  - **No es una revisión personal de Roderich ni del tutor.**
  - Las propuestas de estado **no están aplicadas**: las decide Roderich sobre el dry-run.
- **Base:** Mobile `main` **`f4dbb18d6fbec9bb2aa9dcc64bf2a7c400ca4b05`** (merge de MOB #134). `lib/` es idéntico a `fd8dc7d` y a `27c4654` (`git diff` vacío en `lib/`, `android/` y `pubspec.yaml`). Los `archivo:línea` citados son de `f4dbb18`.
- **Comando y resultado:** ninguna de las tres sesiones ejecutó pruebas para esta conciliación. Las pruebas de host citadas pasan en **Flutter CI run 39198106138** sobre `f4dbb18` (push a `main`, 2026-10-19 04:10–04:22Z): pub get, formato, análisis estático, tests, tests de fechas en America/La_Paz y build de release, todos en *success*. La evidencia de dispositivo citada es la de sus propios archivos (`docs/evidence/F08_*`, `F10_*`), con su modelo, SHA y fecha.
- **Línea base:** `docs/evidence/REC_MOBILE_BASELINE.md` (2026-10-15 sobre `278cbd3`, 690 pruebas de host OK, con su nota del 2026-10-17). Las frases de ausencia de aquella fecha —por ejemplo «docs/evidence no existe»— se comprobaron contra `f4dbb18` antes de citarlas: son **contexto histórico** y no se borran ni se reescriben. Lo resuelto después se cita con su PR y su SHA. El defecto de `reverseTransfer` multiproducto lo resolvió #73 (PR #75, `905e67c`). El respaldo sin identidad lo resolvió `812fe49` (#78), y el SHA-256 de la base y la atomicidad, F08/F10 (`6c6a1a2`, `1663e92`, `e5a1364`).
- **Trazabilidad y campos:** se conservan Origin = Reconstructed, la Engineering Iteration (EI) y los `Requirement refs`. El trabajo nuevo que corrija un defecto se registrará con su fecha real; no se convierte en trabajo reconstruido. No cambia ningún gate.
- **Fuera de este documento:** las REC de voz (#58, #59) y los demás elementos de F09, que siguen al final.

## 0. Regla aplicada (de Roderich)

| Situación | Propuesta |
|---|---|
| Criterios cubiertos, implementación integrada y evidencia suficiente | Cierre *completed*, Status **Done**, Evidence **Verified** |
| Cierre con un límite académico aceptado de forma explícita | Alcance documentado y **Partial**; no se llama cobertura completa |
| Implementación existente con la revisión real incompleta | **Validation** (o In Review) + **Partial**, con el hueco concreto |
| Función o comportamiento realmente ausente | **Pendiente**, describiendo lo que falta |

No se exige el 100 % de líneas. Sólo se propone una comprobación nueva cuando falta cubrir un criterio material: propiedad, atomicidad, conservación de cantidades o costos, reversión o recuperación.

**Unificación de A:** C propuso *In Review* para #44, #51 y #52, y B *Validation* para sus siete. Para que todas las tarjetas que quedan con huecos de prueba estén en una sola columna, A propone **Validation** para todas, como en las F10 de la misma situación (#42–#46 de Backend). Así #52 pasaría de In Review a Validation. Si Roderich prefiere *In Review*, la diferencia es sólo de columna.

**Muestra comprobada por A (lectura, 2026-10-19):**
- `reversed_by` no existe en `lib/`;
- el rechazo de origen = destino (`agro_repository.dart:1522-1526`) no tiene prueba;
- los textos de rechazo de `confirmPurchase` no aparecen en `test/`;
- ninguna prueba afirma `variance_quantity_base`;
- no hay aserción de «CHECK constraint» en `test/`;
- el tag `v1.0.0-base-stable` resuelve a `bd3289f`, ancestro de `main`, con el mismo árbol `6c005a96…` que `f4c6510` (el merge de #4 que registra GitHub);
- `_neutralize` aplica `trimLeft()` antes de mirar el primer carácter (`csv_report_generator.dart:100-104`), y la prueba `report_csv_test.dart:205` usa `'\t=1+1'`;
- `flutter-ci.yml:15-16` declara `permissions: contents: read`.

## 1. Resumen de las 14 tarjetas

| Tarjeta | EI · REC | Hoy (Status · Evidence) | Propuesta | Motivo |
|---|---|---|---|---|
| #39 | EI-02 · REC-003 | Backlog · Partial | **Validation · Partial** (alternativa Done · Partial si Roderich acepta el límite) | Los 6 criterios literales están cubiertos; las restricciones de motor (FK, CHECK, campaña activa única por inserción directa) que el autor pasó a F10 siguen sin prueba |
| #40 | EI-02 · REC-004 | Backlog · Partial | **Validation · Partial** | 5 de 7; siguen sin prueba el archivado que conserva la historia y el rechazo del nombre vacío |
| #43 | EI-03 · REC-007 | Backlog · Partial | **Validation · Partial** | Factura BOB/USD y atomicidad cubiertas; ningún rechazo de `confirmPurchase` tiene prueba; RF-08 sólo para el tipo de cambio del ítem |
| #44 | EI-03 · REC-008 | Backlog · Partial | **Validation · Partial** | El visor de factura no tiene evidencia; `storeInvoiceImage` no tiene prueba directa; la cámara no se ejercitó |
| #46 | EI-03 · REC-010 | Backlog · Partial | **Validation · Partial** | 6 de 7 (el rechazo de una aplicación no afirma el saldo intacto); el detalle de producto no tiene prueba de host |
| #47 | EI-03 · REC-011 | Backlog · Partial | **Validation · Partial** | FIFO, repetidos y plan único cubiertos; siguen sin prueba la atomicidad multiproducto, la cantidad ≤ 0 y la variación real − teórica |
| #48 | EI-03 · REC-012 | Backlog · Partial | **Validation · Partial** | #73 resuelto; siguen sin prueba origen = destino y la reversión con el destino ya movido |
| #50 | EI-03 · REC-014 | Backlog · Partial | **Validation · Partial** + **decisión de Roderich** (RF-13, responsable) | #73 y #74 resueltos; sigue sin prueba la doble reversión de una aplicación; la app no registra el actor |
| #51 | EI-03 · REC-015 | Backlog · Partial | **Validation · Partial** | La bitácora de chaco y el contenido del perfil no tienen prueba |
| #52 | EI-04 · REC-016 | In Review · Partial | **Validation · Partial** (alternativa Done · Partial si Roderich acepta el límite) | Sólo 2 de los 5 reportes comparan contenido en la exportación; el «Verified» de la línea base lo corrigió su nota del 2026-10-17 |
| #53 | EI-04 · REC-017 | Backlog · Partial | **Pendiente: Backlog · Partial** | Defecto probable, comprobado por lectura, en la neutralización de una tabulación inicial sin «=»; falta la prueba de interfaz de la cancelación |
| #55 | EI-04 · REC-019 | Backlog · Partial | **Done · Verified · cierre completed** | 6 criterios con prueba de host material; 5 también en dispositivo; propiedad, SHA-256, atomicidad y esquema antiguo resueltos después del 15/10 |
| #56 | EI-04 · REC-020 | Backlog · Partial | **Done · Verified · cierre completed** (alternativa Done · Partial) | 7 criterios con prueba de host material; la usabilidad y la accesibilidad semántica quedan fuera del alcance declarado |
| #57 | EI-04 · REC-021 | In Review · Partial | **Done · Verified · cierre completed** | Los 5 criterios están cubiertos por la configuración y por la CI real; el tag y el merge de #4 tienen el mismo árbol |

**Recuento:** 3 cierres propuestos (#55, #56 y #57), 10 a Validation · Partial y 1 pendiente (#53). Ninguna tarjeta se archiva, se borra ni se oculta.

## 2. Decisiones que corresponden a Roderich

1. **#50, RF-13:** RF-13 pide registrar al responsable de la reversión y la app local no guarda actor. Se acepta como límite académico (la opera el titular del dispositivo y quedan la fecha y el motivo) o se abre trabajo nuevo.
2. **#39:** aceptar o no como límite las restricciones de motor sin prueba (alternativa Done · Partial).
3. **#52:** aceptar o no como suficiente la cadena paridad + compositor + cableado visible para los 3 reportes sin comparación de contenido (alternativa Done · Partial).
4. **#56:** si el diálogo «Descartar cambios», que aparece en «Incluye», debe contar como criterio (alternativa Done · Partial).
5. **#53:** autorizar la corrección de una línea en `_neutralize` (cambio de producción, en su propio PR). Decidir también el `Requirement refs` RF-31, que el 2026-10-15 se señaló como no correspondiente a la exportación CSV.
6. **Comprobaciones nuevas (§4):** autorizar o no cada una antes de construirla.

## 3. Matriz por criterio

Cada tabla da, por criterio: el texto literal, el código en `f4dbb18`, la prueba o evidencia con su SHA y fecha, la cobertura (material o parcial; HOST o DEVICE), el hallazgo histórico y qué lo resolvió, y el faltante real. Las tablas son las de B y C, con las dos precisiones de A ya indicadas: la unificación del estado propuesto a Validation y la frase sobre `f4c6510`.

### 3.1 Datos y reglas de negocio (preparado por B)

### #39 — [EI-02][REC-003][DATA] Persistencia SQLite y migraciones v1–v6 (RF-17, RNF-02)

| # | Criterio literal | Código en `f4dbb18` | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «Dada una base en versión 3, cuando se abre con `AppDatabase` y migra a v6, entonces su firma de esquema (tablas, columnas e índices con unicidad y parcialidad) es igual a la de una base creada desde cero.» | `app_database.dart:265-268` (`version`, `onConfigure`, `onUpgrade`), `:436-575` (pasos `oldVersion < 2…10`) | `test/schema_equivalence_test.dart:228` «una base migrada desde V3 queda con el mismo esquema que una nueva» (en `278cbd3`; hoy migra V3 → **v10**) | material, HOST | 15/10: «la equivalencia sólo se prueba desde V3; faltan V1, V2, V4 y V5» → **sigue** (fuera del literal, que pide V3) | ninguno para el literal |
| 2 | «Dada una base V1 o V3 con datos, cuando migra, entonces las filas existentes se conservan y se agregan las columnas y tablas nuevas.» | `:436-560` | `test/migration_test.dart:31` «migración V1 a V2 conserva filas…», `:81` «migración V3 a V4 agrega items de transferencia sin perder historial»; además `:168` «v$version → versión actual conserva todas las filas…» para v6, v7 y v8 (`d63bfce`, 2026-10-17) | material, HOST | — | ninguno |
| 3 | «Dada una base V3 con filas duplicadas en `application_items`, cuando migra a v5 o a una versión posterior, entonces no se elimina ninguna fila, el índice se conserva como no único y la anomalía queda registrada en `app_settings`.» | `:560-562` (v5) | `schema_equivalence_test.dart:282` «una base V3 con duplicados preexistentes migra sin perder filas ni fallar» (anomalía `application_items:1`, `idx_application_item_unique|unique=0`) | material, HOST | 15/10: «no hay prueba de duplicados en `application_plan_items`» → **sigue** (fuera del literal) | ninguno para el literal |
| 4 | «Dada una base V5 con planes `COMPLETED` o reutilizados, cuando migra a v6, entonces los planes pasan a `APPLIED`, los pendientes reales siguen en `PLANNED` y se impone el índice único parcial, o se registra la anomalía si los datos no lo permiten.» | `:563-565` (v6) | `test/plan_lifecycle_test.dart:377` «COMPLETED pasa a APPLIED y el pendiente real se conserva»; `:394` «la migración impone la unicidad cuando los datos lo permiten» (`unique=1`, `partial=1`, sin anomalía); `:419` «con un plan aplicado dos veces conserva las filas y deja constancia» (`unique=0`, anomalía `'1'`) | material, HOST | — | ninguno |
| 5 | «Dado un plan ya aplicado, cuando se inserta directamente en `applications` una segunda aplicación con el mismo `plan_id`, entonces SQLite la rechaza.» | índice `idx_application_plan_single_use` | `plan_lifecycle_test.dart:165` «la base rechaza por su cuenta una segunda aplicación del plan» (inserción directa → `DatabaseException`) | material, HOST (motor) | — | ninguno |
| 6 | «Dados datos confirmados, cuando se cierra y reabre la base, entonces el estado persiste.» | archivo SQLite; `_open` | `plan_lifecycle_test.dart:227` «el estado sobrevive a cerrar y reabrir la base»; también `campaign_lifecycle_test.dart:193` y `central_reference_binding_test.dart:17` | material para el estado probado, HOST | 15/10 (#40 d): la reapertura sólo afirma `plans()` | ninguno para el literal |

**Hallazgos del 15/10 que el autor pasó a F10 (comentario del 2026-10-15) — estado hoy:**

| Hallazgo | Estado en `f4dbb18` |
|---|---|
| `PRAGMA foreign_keys = ON` no se comprueba (activo y que una FK inválida falle en el motor) | **Sigue.** El código lo activa (`app_database.dart:266`); ninguna prueba lo afirma. `f10_restore_wal_rollback_test.dart:398` lo apaga a propósito para otro fin |
| CHECK del esquema sin prueba de motor (`persons.role`, `products.unit/base_unit`, `farms.area_m2`, importes > 0, transferencia con origen ≠ destino, `quantity_base > 0`) | **Sigue.** No hay ninguna aserción de «CHECK constraint failed» en `test/` |
| `idx_campaign_single_active` sólo probado por el repositorio | **Sigue en el motor.** `schema_equivalence_test.dart:206` lo declara y `:267` comprueba los UNIQUE de base nueva; ninguna inserción directa de dos `ACTIVE` |
| Escritura SQLite fallida a mitad (RNF-02) | **Sigue** como prueba de motor; a nivel de repositorio sí hay rollback (#43 c5, #48 c4) |
| Otras barreras de motor añadidas después | **Nuevas, con prueba:** inmutabilidad del vínculo de titular (`f04_owner_binding_test.dart:190`, `:224`, `:242`; `fccd74c`, PR #77, 2026-10-15) y `owner_binding_id NOT NULL` en `sync_outbox` (`migration_test.dart:225`) |

**Propuesta:** **Validation · Partial.** Los seis criterios literales están cubiertos e integrados con pruebas de host. Lo que el propio autor dejó para F10 —las restricciones del motor (FK, CHECK, campaña activa única por inserción directa)— protege la integridad y sigue sin prueba. Comprobación nueva propuesta, **no ejecutada**: `test/rec_039_schema_constraints_test.dart` con tres casos (FK activa e inválida rechazada; un CHECK por tabla; segunda campaña `ACTIVE` por inserción directa). Si Roderich acepta esas restricciones como límite académico, la alternativa es **Done · Partial**.

**Texto de resolución (para el comentario):**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18` (`lib/` = `fd8dc7d`, CI 39176151765 SUCCESS). Los seis criterios literales están cubiertos por pruebas de host integradas: equivalencia V3 → versión actual (`schema_equivalence_test.dart:228`), conservación de filas V1/V3 y v6–v8 (`migration_test.dart:31`, `:81`, `:168`), duplicados de `application_items` con anomalía (`schema_equivalence_test.dart:282`), migración v6 de planes con índice único parcial o anomalía (`plan_lifecycle_test.dart:377`, `:394`, `:419`), rechazo en el motor de una segunda aplicación del plan (`:165`) y persistencia tras reabrir (`:227`). El esquema actual es v10; v1–v6 se conservan como alcance histórico. La evidencia `docs/evidence/REC_MOBILE_BASELINE.md` existe en `main` desde el 2026-10-15. **Queda pendiente** lo que el autor pasó a F10 el 2026-10-15: pruebas de motor de `PRAGMA foreign_keys`, de los CHECK del esquema y de `idx_campaign_single_active` por inserción directa; y, fuera del literal, la equivalencia desde V1, V2, V4 y V5. Evidence se mantiene **Partial**.

---

### #40 — [EI-02][REC-004][MOB] Catálogos de personas, chacos, productos y proveedores (RF-04, RF-05, CU-04)

| # | Criterio literal | Código | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «…proveedores, cuando se guarda el diálogo sin nombre, entonces el diálogo sigue abierto, muestra «Escriba nombre del proveedor.» y no se escribe ningún registro.» | `lib/presentation/screens/catalogs_screen.dart` (diálogos de alta) | `test/ui_polish_test.dart:164` «guardar sin nombre muestra el error y no cierra el diálogo» (`:184` el texto exacto) | material, HOST (widget) | — | ninguno |
| 2 | «Dado el diálogo de chaco, cuando se guarda sin propietario, nombre ni superficie, entonces se muestran los tres errores y no se crea ningún chaco.» | ídem | `ui_polish_test.dart:191` «el chaco exige propietario, nombre y superficie válida» | material, HOST | — | ninguno |
| 3 | «…cada sección del catálogo… el botón primario indica qué crea» | ídem | `ui_polish_test.dart:384` «el botón primario dice qué crea en cada sección» | material, HOST | — | ninguno |
| 4 | «Dadas varias personas activas, cuando se consulta `people()`, entonces se devuelven ordenadas por nombre y el teléfono puede ser nulo.» | `agro_repository.dart:1809-1810` (`active=1`, `orderBy: 'name'`) | `test/report_reads_characterization_test.dart:307` «sólo personas activas, ordenadas por nombre»; `:316` «el teléfono puede ser nulo» | material, HOST | — | ninguno |
| 5 | «Dados 20 productos dados de alta, cuando se consulta `products()`, entonces se devuelven los 20.» | `:1866-1867` | `test/e2e_v5_test.dart:32-40` (20 altas L/KG, `hasLength(20)`; también `:163`) | material, HOST | — | ninguno |
| 6 | «Dado un registro de catálogo con operaciones asociadas, cuando se archiva, entonces deja de aparecer en las consultas activas y sus operaciones históricas se conservan (pendiente de test).» | `archiveCatalog` `:1789-1807` (`active=0` lógico; desde F04 rechaza archivar al titular vinculado, `:1795-1799`); lecturas activas `:1809-1810`, `:1866-1876` | **Sin prueba del criterio.** Sólo llaman a `archiveCatalog`: `campaign_lifecycle_test.dart:224` (campañas), `f04_owner_binding_test.dart:121` (persona archivada no se vincula), `f04_repository_guards_test.dart:114`, `:288`, `:294` (compuerta y titular) | sin prueba | 15/10 (a) → **sigue** | prueba que archive persona, chaco, producto y proveedor con operaciones y afirme: fuera de `people/farms/products/suppliers`, fila con `active=0`, operaciones intactas |
| 7 | «…renombrar con un nombre vacío, entonces se rechaza con un error de regla de negocio (pendiente de test).» | `renameCatalog` `:1774-1787` (`'El nombre no puede estar vacío.'` en `:1777-1778`) | **Sin prueba del criterio.** La única llamada es `f04_repository_guards_test.dart:112` (compuerta cerrada, nombre «Y») | sin prueba | 15/10 (b) → **sigue** | prueba de nombre en blanco → `BusinessRuleException` y fila sin cambio |

**Otros hallazgos del 15/10:** (c) validación de los diálogos de persona y producto → **sigue** (sólo proveedor y chaco). (d) persistencia con aserciones sobre catálogos → **sigue** (la reapertura de `plan_lifecycle_test.dart:227` afirma planes). (e) «docs/evidence no existe» → **resuelto** (`0ab6043`, 2026-10-15). (f) trazabilidad de personas y proveedores → **sigue** como nota de revisión, sin cambiar refs.

**Propuesta:** **Validation · Partial.** Cinco de siete criterios con prueba; los dos que la tarjeta ya marcaba «pendiente de test» siguen sin ella y uno es material (el archivado conserva la historia). Comprobación nueva propuesta, **no ejecutada**: `test/rec_040_catalog_archive_rename_test.dart` (archivar los cuatro catálogos con operaciones asociadas; renombrar en blanco).

**Texto de resolución:**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18`. Cubiertos por pruebas de host integradas: validaciones del diálogo de proveedor y de chaco (`ui_polish_test.dart:164`, `:191`), botón primario por sección (`:384`), `people()` activas por nombre con teléfono nulo (`report_reads_characterization_test.dart:307`, `:316`) y 20 productos (`e2e_v5_test.dart:32-40`). El archivado es lógico en el código (`agro_repository.dart:1789-1807`, `active=0`, y desde F04 no permite archivar al titular vinculado) y `renameCatalog` rechaza el nombre vacío (`:1777-1778`), pero **ninguna prueba** afirma que un registro archivado desaparezca de las lecturas activas conservando sus operaciones, ni el rechazo del nombre vacío. Siguen también las validaciones de los diálogos de persona y producto. La evidencia de línea base existe en `main` desde el 2026-10-15. Evidence se mantiene **Partial**.

---

### #43 — [EI-03][REC-007][MOB] Compras multiproducto, multi-moneda y asignaciones (RF-07, RF-08, CU-06)

| # | Criterio literal | Código | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «Dada una compra con varias líneas en BOB y USD… se crea una línea por producto, y una asignación y un lote por cada reparto; el total en BOB es exacto (p. ej., Bs 57.600,00…).» | `confirmPurchase` `:875-1023` dentro de `_write` (`:917`, transacción `:120`); `purchase_items` `:960-962`, lotes `:994-996` | `test/repository_test.dart:262` «una factura admite tres productos, BOB/USD, asignaciones y foto» (`total_bob_minor` 5760000; 3 ítems, 3 asignaciones, 3 lotes). DEVICE: M3 / R2-b en el POCO y el HONOR (`F10_COMPATIBILIDAD_MOBILE.md`, `F10_RENDIMIENTO_MOBILE*.md`), compras BOB | material, HOST (+ DEVICE en BOB) | — | ninguno |
| 2 | «Dada una línea cuyas asignaciones no suman la cantidad comprada… se rechaza con un error de regla de negocio.» | `:904-909` (`'La cantidad asignada debe coincidir con la cantidad comprada.'`) | **Ninguna.** Ningún texto de rechazo de `confirmPurchase` aparece en `test/` | sin prueba | 15/10 (1) → **sigue** | prueba del rechazo y de que no se escribe nada |
| 3 | «Dada una línea en USD sin tipo de cambio, o una línea en BOB con tipo de cambio… se rechaza.» | `:889-894` (USD sin tipo de cambio o ≤ 0), `:895-900` (BOB con tipo de cambio) | **Ninguna** | sin prueba | 15/10 (2), (3) → **sigue** | dos casos de rechazo |
| 4 | «Dada una compra confirmada en USD… cada línea y cada lote conservan la moneda, el precio original y el tipo de cambio utilizados.» | ítems `:960-962`, lotes `:994-996` (`currency_code`, `original_unit_price_minor`, `exchange_rate_scaled`) | **Parcial:** `test/voice_draft/voice_purchase_draft_screen_test.dart:281` afirma `purchase_items.exchange_rate_scaled = 6960000` tras confirmar por voz (`939552f`, PR #100, 2026-10-17). Ninguna prueba afirma moneda ni precio original, ni nada del lote | parcial, HOST | 15/10 (RF-08) → **sigue en parte** | aserción de los tres campos en ítem y lote de una compra USD |
| 5 | «Dado un fallo interno durante la confirmación (p. ej., una persona inexistente en una asignación)… no queda persistida ninguna compra, línea ni lote.» | `_write` transaccional | `repository_test.dart:233` «fallo interno revierte toda la transacción de compra» (asignación a la persona 999999: 0 compras, 0 ítems, 0 lotes) | material, HOST | — | ninguno |

**Otros hallazgos del 15/10:** productos repetidos (`:879-880`), compra sin líneas (`:876-877`) y cantidad o precio ≤ 0 (`:884-888`) siguen **sin prueba**. Formulario: `ui_polish_test.dart:270`/`:280` ya validaban líneas vacías y persona faltante en la línea base; el formulario en modalidad propia se prueba en `personal_mode_flows_test.dart:199` (`7ac7153`, PR #102, 2026-10-17); los mensajes de tipo de cambio sin elegir y suma distinta **siguen** sin prueba de widget. «docs/evidence no existe» → **resuelto**.

**Propuesta:** **Validation · Partial.** Faltan las pruebas de dos criterios literales materiales (conservación de cantidades por la suma de asignaciones y regla de tipo de cambio, que conserva el costo) y la mitad de RF-08. Comprobación nueva propuesta, **no ejecutada**: `test/rec_043_purchase_rules_test.dart` (suma distinta; USD sin o con tipo de cambio ≤ 0; BOB con tipo de cambio; producto repetido; sin líneas; cantidad o precio ≤ 0; y una compra USD con aserción de `currency_code`, `original_unit_price_minor` y `exchange_rate_scaled` en ítem y lote). Cada rechazo debe comprobar que no queda ninguna fila.

**Texto de resolución:**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18`. Cubiertos: la factura de tres productos BOB/USD con 3 ítems, 3 asignaciones, 3 lotes y total exacto de Bs 57.600,00 (`repository_test.dart:262`) y la atomicidad ante un fallo interno (`:233`), ambas con pruebas de host integradas; las compras BOB se ejercitaron además en el teléfono en las series F10. Las reglas de rechazo están implementadas en `confirmPurchase` (`agro_repository.dart:876-909`: al menos un producto, sin repetidos, cantidad y precio > 0, USD con tipo de cambio > 0, BOB sin tipo de cambio, asignaciones que suman lo comprado), pero **ninguna prueba** las ejercita. La conservación de moneda, precio original y tipo de cambio sólo está afirmada para el tipo de cambio del ítem (`voice_purchase_draft_screen_test.dart:281`, 2026-10-17), no para el lote. Evidence se mantiene **Partial**.

---

### #46 — [EI-03][REC-010][MOB] Inventario por lotes, movimientos y proyecciones (RF-09, RF-10, CU-07)

| # | Criterio literal | Código | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «…el saldo físico es igual a la suma de sus movimientos.» | `stock` `:1994-1999`, `inventorySummary` `:2001-2020` (`SUM(m.quantity_signed)`) | `test/reports_test.dart:208` «resume compras, stock y saldos con los valores esperados»; `repository_test.dart:147` (FIFO deja stock vacío) | material, HOST | — | ninguno |
| 2 | «Dados productos en L y en KG… cada producto conserva su unidad y no se suman cantidades de unidades distintas.» | `inventorySummary` y `personStockSummary` `:2022-2031` agrupan por producto con `p.unit` | `repository_test.dart:317` «inventario separa litros y kilos y calcula stock por persona» | material, HOST | — | ninguno |
| 3 | «Dado un plan pendiente… se muestran por separado el físico, el comprometido y el proyectado.» | `:2008-2014` (`committed_base`, `projected_base`) | `reports_test.dart:296` «un plan pendiente compromete stock y reduce la proyección» | material, HOST (lectura) | 15/10 (2): sin prueba de widget de `InventoryScreen` → **sigue** en host; DEVICE: la pestaña Inventario se leyó en las series F10 (§6) | ninguno para el literal |
| 4 | «Dado un saldo disponible menor que la cantidad solicitada, cuando se confirma una aplicación o una transferencia, entonces la operación se rechaza y el saldo no cambia.» | aplicación `:1133-1137`; transferencia `:1564-1568` | Transferencia: `v4_repository_test.dart:111` «transferencia insuficiente hace rollback completo» (sin transferencias ni cambio de saldo). Aplicación: `repository_test.dart:367` sólo afirma la excepción (21000 > 20000) | material (transferencia) / parcial (aplicación) | — | aserción de saldo intacto tras el rechazo de una aplicación |
| 5 | «Dada una transferencia… el físico total del producto no cambia y la suma por responsables coincide con él.» | `transferProductsFifo` `:1515-1650` | `test/v5_domain_test.dart:53` «transferencia multiproducto conserva físico y suma owners» | material, HOST | — | ninguno |
| 6 | «Dada una aplicación revertida… el saldo vuelve al valor previo a la aplicación.» | `reverseApplication` `:1277-1352` | `repository_test.dart:188` «reversión de aplicación restaura inventario y revierte el cargo» (50000); `destructive_actions_test.dart:144` | material, HOST | — | ninguno |
| 7 | «Dado un producto con lotes vigentes, cuando se abre su detalle, entonces se muestran la cabecera de stock, el reparto por persona y los lotes con su procedencia (compra, proveedor, campaña). Este criterio aún no tiene test automatizado.» | `inventoryProductHeader` `:2033-2049`, `inventoryProductDistribution` `:2051-2062`, `inventoryProductLots` `:2064-2093` (excluye revertidos y filtra por persona, proveedor y campaña) | **Sin prueba de host** de las tres lecturas (grep vacío). **DEVICE parcial:** en R3 de la serie 2 (HONOR, `ad5b43d`, 2026-10-18) el detalle de `DSV-001` mostró comprado, consumido, físico, comprometido, libre proyectado, valor físico y «Distribución por persona» en las 10 repeticiones (`docs/evidence/F10_RENDIMIENTO_MOBILE_S2.md` §5); no se afirmaron los lotes con su procedencia | parcial (DEVICE de cabecera y reparto) | 15/10 (1) → **sigue** en host | prueba de las tres lecturas, incluidos los filtros y la exclusión de lotes revertidos |

**Otros hallazgos del 15/10:** (3) consulta de historial de movimientos por saldo → **sigue sin implementar**, y el alcance de la tarjeta lo excluye expresamente («No incluye: una consulta dedicada al historial»). (4) visibilidad autorizada en las consultas de inventario → **sigue** para las lecturas; las escrituras sobre otra persona en modalidad propia sí tienen prueba (`f04_repository_guards_test.dart:159`, `fccd74c`, PR #77, 2026-10-15). (5) «docs/evidence no existe» → **resuelto**.

**Propuesta:** **Validation · Partial.** Seis de siete criterios con prueba material (el 4.º, sólo para transferencias). El 7.º, que la tarjeta ya declaraba sin prueba, tiene observación física parcial y ninguna prueba de host. Comprobación nueva propuesta, **no ejecutada**: `test/rec_046_inventory_detail_test.dart` (cabecera, reparto, lotes con procedencia y filtros, exclusión de revertidos; saldo intacto tras rechazar una aplicación por stock).

**Texto de resolución:**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18`. Cubiertos por pruebas de host integradas: saldo como suma de movimientos (`reports_test.dart:208`), L y KG separados (`repository_test.dart:317`), físico, comprometido y proyectado (`reports_test.dart:296`), transferencia que conserva el total y la suma por responsables (`v5_domain_test.dart:53`), saldo restituido al revertir una aplicación (`repository_test.dart:188`) y rechazo de una transferencia sin stock sin efectos (`v4_repository_test.dart:111`). El rechazo de una aplicación sin stock sólo afirma la excepción (`repository_test.dart:367`). El detalle de producto se observó en el teléfono en las series F10 (cabecera y distribución por persona, `F10_RENDIMIENTO_MOBILE_S2.md` §5), pero `inventoryProductHeader`, `inventoryProductDistribution` e `inventoryProductLots` no tienen prueba de host y no se afirmaron los lotes con su procedencia. La consulta de historial por saldo sigue fuera del alcance. Evidence se mantiene **Partial**.

---

### #47 — [EI-03][REC-011][MOB] Aplicaciones multiproducto con costeo FIFO (RF-12, CU-09)

| # | Criterio literal | Código | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «…20000 unidades base disponibles… aplicación de 21000… se rechaza con BusinessRuleException (la comprobación de que el stock queda intacto está pendiente de test).» | `:1133-1137` | `repository_test.dart:367` «detalle de producto expone stock, lotes y bloquea exceso» (sólo la excepción) | parcial | 15/10 (4) → **sigue** | aserción de stock intacto |
| 2 | «Dados dos lotes… con costos distintos, cuando se aplica una cantidad que agota ambos, entonces se consume primero el lote más antiguo, cada consumo registra su costo exacto y el total de la aplicación es la suma de esos costos.» | FIFO `:1121-1126` (`ORDER BY l.acquired_date, l.id`) | `repository_test.dart:147` «FIFO consume lotes de costos diferentes y valoriza Bs 5.450» (`total_cost_bob_minor` 545000; stock vacío) | material, HOST | — | ninguno |
| 3 | «Dada una aplicación con varios productos de unidades distintas… se persiste un ítem y al menos un consumo por producto, y el total coincide con la suma de los ítems sin mezclar unidades.» | `confirmApplication` `:1067-1236` | `e2e_v5_test.dart:106-136`: 3 líneas de productos L/KG, `application_items` = 3 y plan `APPLIED`; **no afirma** consumos por producto ni el total frente a la suma de ítems | parcial, HOST | — | aserción de consumos por ítem y del total |
| 4 | «Dada una aplicación con un producto repetido… se rechaza.» | `:1072-1077` | `v5_domain_test.dart:168` «duplicados se bloquean en aplicación, plan y transferencia» | material, HOST | — | ninguno |
| 5 | «Dada una aplicación vinculada a un plan… el plan pasa a APPLIED, un segundo intento se rechaza sin crear aplicación ni gastar stock y revertir la aplicación no reabre el plan.» | plan único (índice) | `plan_lifecycle_test.dart:109`, `:116`, `:150` «dos envíos simultáneos sólo producen una aplicación», `:189`, `:196` | material, HOST | — | ninguno |
| 6 | «…multiproducto en la que una línea no tiene stock suficiente… no persiste ningún efecto de las demás líneas (pendiente de test).» | `_write` transaccional; rechazo dentro del bucle `:1116-1137` | **Ninguna** | sin prueba | 15/10 (3) → **sigue** | prueba de atomicidad multiproducto (aplicación, ítems, consumos y movimientos de la primera línea: 0) |
| 7 | «Dada una línea con cantidad igual o menor que cero… se rechaza (pendiente de test).» | `:1117-1120` | **Ninguna** | sin prueba | 15/10 (5) → **sigue** | prueba del rechazo |
| 8 | «…`variance_quantity_base` registra la cantidad real menos la teórica (pendiente de test).» | `:1154-1156` | **Ninguna** (grep vacío; `e2e_v5_test.dart` pasa teórica = real y no la afirma) | sin prueba | 15/10 (1) → **sigue** | aserción de la variación con teórica ≠ real |

**Otros hallazgos del 15/10:** (2) `estimateFifoCost` (`:2270`) sin prueba directa → **sigue**. (6) pruebas de widget de `ApplicationFormScreen` → **resuelto en parte**: `personal_mode_flows_test.dart:263` (PR #102, 2026-10-17) y `f04_effective_date_form_test.dart:290-320` (`9f3e3af`, PR #124, 2026-10-18) montan el formulario y comprueban lo escrito. (7) lectura directa de `APPLICATION_OUT` y `USAGE_CHARGE` → **sigue**. (8) «docs/evidence no existe» → **resuelto**. DEVICE: la aplicación multiproducto y el rechazo por saldo se ejercitaron en el teléfono (M4 de `F10_COMPATIBILIDAD_MOBILE.md` y de la serie 3, `F10_COMPATIBILIDAD_MOBILE_S3.md`, con conteos sin cambio tras el rechazo de 999 L), lo que cubre físicamente el rechazo con saldo intacto en un caso de una línea.

**Propuesta:** **Validation · Partial.** Cuatro criterios materiales cubiertos; tres de los «pendiente de test» siguen sin prueba y uno es de atomicidad (RN-04). Comprobación nueva propuesta, **no ejecutada**: `test/rec_047_application_rules_test.dart` (atomicidad multiproducto; cantidad ≤ 0; variación real − teórica; stock intacto tras el rechazo; `estimateFifoCost` contra el costo real; consumos por ítem).

**Texto de resolución:**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18`. Cubiertos por pruebas de host integradas: FIFO con dos lotes y costo exacto Bs 5.450 (`repository_test.dart:147`), rechazo de productos repetidos (`v5_domain_test.dart:168`) y el ciclo del plan único, incluido el envío simultáneo y la reversión que no lo reabre (`plan_lifecycle_test.dart:109-196`). El rechazo por stock insuficiente sólo afirma la excepción (`repository_test.dart:367`); en el teléfono, el rechazo de 999 L se comprobó con conteos sin cambio (M4 de las series F10). La aplicación multiproducto afirma los ítems, no los consumos ni el total (`e2e_v5_test.dart:106-136`). **Siguen sin prueba** la atomicidad multiproducto cuando una línea no tiene stock, el rechazo de cantidades ≤ 0, `variance_quantity_base` y `estimateFifoCost`, aunque el código los implementa (`agro_repository.dart:1116-1137`, `:1154-1156`, `:2270`). Evidence se mantiene **Partial**.

---

### #48 — [EI-03][REC-012][MOB] Transferencias FIFO conservando costo histórico (RF-11, CU-08)

| # | Criterio literal | Código | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «Dado un origen con dos lotes… cantidad mayor que el primer lote… se consumen los lotes por orden FIFO, se crea un lote destino por cada tramo y el costo total… es la suma del costo histórico de cada tramo.» | FIFO `:1553-1557`; lote derivado `:1585-1600` | `v4_repository_test.dart:51-110` (transferencia FIFO de varios lotes y su reversión, `:99`); `f04_bug_01_reverse_transfer_test.dart:195` (filas por lote) | material, HOST | — | ninguno |
| 2 | «Dado un lote origen con costo unitario y precio original, cuando se transfiere parte… el lote destino conserva el costo unitario y el precio original y el stock total no cambia.» | `:1593-1596` | `repository_test.dart:245` «transferencia divide lote sin modificar costo histórico» | material, HOST | 15/10 (4): moneda, tipo de cambio, `acquired_date` y `parent_lot_id` del derivado sin aserción → **sigue** (fuera del literal) | — |
| 3 | «Dada una transferencia multiproducto… el inventario total de cada producto no cambia y la suma de origen y destino es igual al total.» | `transferProductsFifo` `:1515-1650` | `v5_domain_test.dart:53` | material, HOST | — | ninguno |
| 4 | «…un ítem no tiene stock suficiente… no se registra ninguna transferencia ni movimiento y el stock del origen no cambia.» | `:1564-1568` dentro de `_write` | `v4_repository_test.dart:111` «transferencia insuficiente hace rollback completo» | material, HOST | — | ninguno |
| 5 | «Dada una transferencia con productos repetidos, o con el mismo origen y destino… se rechaza con `BusinessRuleException`.» | repetidos `:1533-1538`; mismo origen y destino `:1522-1526` | Repetidos: `v5_domain_test.dart:168`. **Mismo origen y destino: ninguna** | parcial | 15/10 (1) → **sigue** | prueba de origen = destino |
| 6 | «Dada una transferencia confirmada cuyo stock destino no se ha movido, cuando se revierte, entonces el origen recupera su saldo y el destino queda en cero, con cada movimiento de reversión asociado a su propio producto. Si el stock destino ya se movió, la reversión se rechaza.» | `reverseTransfer` `:1651-1735`: producto de cada lote `:1668-1708`; guarda de destino movido `:1687-1692`; doble reversión `:1658-1664` | **#73 resuelto:** `f04_bug_01_reverse_transfer_test.dart:152` «revertir una transferencia de 3 productos deja cada saldo igual al previo», `:195` (cada fila con su lote, responsable, cantidad y producto; cabecera `REVERSED`), `:316-323` (una segunda reversión se rechaza sin escribir movimientos), `:325` (un solo producto, regresión) y la reparación de datos en la migración v7 (`:414-658`). **Destino ya movido: ninguna prueba** | material (reversión por producto, doble reversión) / sin prueba (destino movido) | 15/10 (2) defecto de `product_id` de cabecera → **resuelto** por PR #75 (`905e67c`, fix `69ec88c`, 2026-10-15; `docs/evidence/F04_BUG_01.md`, con prueba de mutación). 15/10 (3) doble reversión → **resuelto**; guarda de destino movido → **sigue** | prueba de la guarda «El stock transferido ya tuvo movimientos» |

**Otros hallazgos del 15/10:** (5) fecha efectiva de `TRANSFER_OUT`/`TRANSFER_IN`: el código usa el parámetro `date` (`:1519`, `movement_date` en `:1616`), **sin prueba** → **sigue**. (6) pruebas de widget del formulario y de la reversión desde `TransfersScreen` → **sigue en parte**: `personal_mode_flows_test.dart:461` monta la transferencia en modalidad compartida (origen y destino), pero no la confirma ni la revierte desde la pantalla. (7) transferencias sólo en modalidad compartida → **resuelto** por F04: en propio no se ofrecen ni se abren por ruta y `reverseTransfer` se rechaza (`personal_mode_flows_test.dart:63`, `:94`, `:111`, `:541`; PR #102, `cf3d510`, 2026-10-17). (8) «docs/evidence no existe» → **resuelto**.

**Propuesta:** **Validation · Partial.** El defecto material de #73 está corregido, integrado y con evidencia; cinco de seis criterios cubiertos. Faltan dos casos de rechazo de criterios literales (origen = destino; reversión con destino ya movido), éste último de reversión. Comprobación nueva propuesta, **no ejecutada**: `test/rec_048_transfer_guards_test.dart` (ambos rechazos sin efectos; y, fuera del literal, fecha efectiva de los movimientos y campos del lote derivado).

**Texto de resolución:**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18`. El defecto de la reversión multiproducto (#73: los movimientos de reversión usaban el producto de la cabecera) está corregido por PR #75 (`905e67c`, 2026-10-15): `reverseTransfer` usa el producto de cada lote (`agro_repository.dart:1668-1708`) y la migración v7 repara los datos; lo prueban `f04_bug_01_reverse_transfer_test.dart:152`, `:195`, `:325` y `:414-658`, con evidencia `docs/evidence/F04_BUG_01.md`. Cubiertos además: FIFO por tramos, conservación del costo y del precio original, totales multiproducto, rollback por stock insuficiente, rechazo de repetidos y de una segunda reversión, y la restricción a la modalidad compartida (F04, PR #102). **Siguen sin prueba** el rechazo de origen = destino (`:1522-1526`) y el de una reversión cuyo stock destino ya se movió (`:1687-1692`); y, fuera del literal, la fecha efectiva de los movimientos y la moneda, el tipo de cambio, la fecha y `parent_lot_id` del lote derivado. Evidence se mantiene **Partial**.

---

### #50 — [EI-03][REC-014][MOB] Reversiones auditables y movimientos compensatorios (RF-13, CU-17)

| # | Criterio literal | Código | Prueba / evidencia | Cobertura | Hallazgo histórico y resolución | Faltante real |
|---|---|---|---|---|---|---|
| 1 | «Dado una aplicación confirmada, cuando se revierte… el stock consumido vuelve al inventario, el saldo de la persona se compensa y la aplicación queda en `REVERSED`. El cargo original se conserva y se agrega un `CREDIT_ADJUSTMENT`.» | `reverseApplication` `:1277-1352` (`APPLICATION_REVERSAL` `:1308`, crédito `:1331-1337` con `reversal_of_id`, `REVERSED` `:1342`) | `repository_test.dart:188` (stock 50000, saldo 0, `REVERSED`) y `typed_reads_parity_test.dart:279` (`a6da1be`, 2026-09-06: tras revertir una aplicación real, el estado de cuenta contiene un `CREDIT_ADJUSTMENT`, `:290`); **ninguna afirma** que el cargo original siga ni el `reversal_of_id` del crédito | parcial, HOST | 15/10 (5) `reversal_of_id` → **resuelto para compras** (abajo), **sigue para aplicaciones** | aserción del cargo conservado y del `reversal_of_id` *(corregido el 2026-10-19 en la revisión de MOB #135: la versión anterior decía que ninguna prueba afirmaba el crédito)* |
| 2 | «Dado una aplicación revertida, cuando se consultan los reportes de costo, entonces ya no suma.» | reportes | `reports_test.dart:169` «una aplicación revertida deja de contar», `:199` «una aplicación revertida no suma» | material, HOST | — | ninguno |
| 3 | «Dado una aplicación generada desde un plan, cuando se revierte, entonces el plan sigue en `APPLIED` y no se puede volver a aplicar.» | plan único | `plan_lifecycle_test.dart:189`, `:196` | material, HOST | — | ninguno |
| 4 | «Dado una compra con lotes consumidos por aplicaciones vigentes, cuando se intenta revertir… se rechaza con `BusinessRuleException` sin cambiar nada.» | `reversePurchase` `:1365-1369` | `repository_test.dart:214` «compra consumida bloquea cancelación directa» (sólo la excepción). Para la guarda vecina de lote transferido: `f04_bug_02_reverse_purchase_after_transfer_test.dart:220`, `:263`, `:300` | parcial («sin cambiar nada» no se afirma en este caso) | 15/10 (3) guarda de lote transferido o ajustado → **resuelto** (#74) | aserción de «sin cambiar nada» con lotes consumidos |
| 5 | «Dado una transferencia FIFO que tomó varios lotes, cuando se revierte… el stock vuelve al origen y el destino queda en cero.» | `reverseTransfer` | `v4_repository_test.dart:99`; `f04_bug_01_reverse_transfer_test.dart:152`, `:195` | material, HOST | — | ninguno |
| 6 | «Dado la pantalla de aplicaciones, cuando el usuario toca revertir, entonces se pide confirmación… Si cancela, no se revierte nada; si confirma… el stock se restituye.» | `applications_screen.dart:66-68` | `destructive_actions_test.dart:98`, `:120`, `:144` | material, HOST (widget) | — | ninguno |
| 7 | «Dado una operación ya revertida, cuando se intenta revertir otra vez… se rechaza y no se produce una segunda restitución. (Ningún test cubre todavía este criterio.)» | aplicación `:1281-1287`; compra `:1372-1376`; transferencia `:1658-1664` | **Compra:** `f04_bug_02…test.dart:140` (el segundo intento se rechaza y el volcado completo de tablas queda idéntico, líneas ~218-223). **Transferencia:** `f04_bug_01…test.dart:316-323` (rechazo sin movimientos nuevos). **Aplicación: ninguna** | material (compra y transferencia) / sin prueba (aplicación) | 15/10 (4) → **resuelto para compra y transferencia** por PR #79 y PR #75; **sigue para aplicación** | doble reversión de una aplicación con volcado idéntico |

**Otros hallazgos del 15/10:** (1) reversión exitosa de compra → **resuelto** por #74: `f04_bug_02…test.dart:140` afirma tres `PURCHASE_REVERSAL`, un único `CREDIT_ADJUSTMENT` con `reversal_of_id` del cargo original, pago al proveedor revertido y compra `REVERSED` (PR #79, `505c230`, fix `1c03d05`, 2026-10-15/16; `docs/evidence/F04_BUG_02.md`). (2) guarda de transferencia con destino movido y `REVERSED` → `REVERSED` y movimientos `TRANSFER_REVERSAL_*` **resueltos** (#73); la guarda de destino movido **sigue** sin prueba. (5) motivo (`notes`) persistido → **sigue** (las pruebas pasan `reason` y no lo leen). (6) **responsable de la reversión:** el esquema y el repositorio **no registran actor** (`reversed_by` no existe en `lib/`) → **sigue**; es una decisión, no un defecto de prueba. (7) confirmación al revertir compras y transferencias: el código la pide (`purchases_screen.dart:122-132` «¿Revertir esta compra?», `transfers_screen.dart:34-36` «¿Revertir esta transferencia?»), **sin prueba de widget** → **sigue**. (8) «docs/evidence no existe» → **resuelto**.

**Propuesta:** **Validation · Partial.** Los defectos materiales de #74 (y de #73 en transferencias) están corregidos con evidencia, y la doble reversión de compras y transferencias está probada. Faltan la doble reversión de una aplicación (reversión, material), las aserciones de «sin cambiar nada» y del crédito en la aplicación, y una **decisión de Roderich** sobre el responsable de la reversión que pide RF-13: aceptarlo como límite académico (Mobile local-first sin identificación de operador por acción: la operación la hace el titular del dispositivo; queda fecha y motivo) o abrir trabajo. Comprobación nueva propuesta, **no ejecutada**: `test/rec_050_reversal_rules_test.dart` (doble reversión de aplicación; cargo conservado y `CREDIT_ADJUSTMENT` con `reversal_of_id`; compra consumida sin cambios; motivo persistido; confirmación en compras y transferencias).

**Texto de resolución:**
> Conciliación del 2026-10-19 sobre `main` `f4dbb18`. Los defectos de reversión hallados el 2026-10-15 están corregidos e integrados: revertir una compra tras revertir su transferencia (#74, PR #79, `505c230`; `docs/evidence/F04_BUG_02.md`) y la reversión multiproducto de transferencias (#73, PR #75, `905e67c`; `docs/evidence/F04_BUG_01.md`). Cubiertos por pruebas de host: reversión de compra con tres `PURCHASE_REVERSAL`, crédito único vinculado al cargo, pago revertido y segundo intento rechazado sin cambios (`f04_bug_02_reverse_purchase_after_transfer_test.dart:140`); reversión de transferencia por producto y segundo intento rechazado (`f04_bug_01_reverse_transfer_test.dart:152-323`); reportes sin la aplicación revertida (`reports_test.dart:169`, `:199`); plan que sigue `APPLIED` (`plan_lifecycle_test.dart:189`, `:196`); confirmación al revertir una aplicación (`destructive_actions_test.dart:98-144`). **Siguen** sin prueba la doble reversión de una aplicación, el cargo conservado y el `reversal_of_id` del crédito al revertir una aplicación, «sin cambiar nada» ante una compra consumida, el motivo persistido y la confirmación en compras y transferencias (implementada en `purchases_screen.dart:122-132` y `transfers_screen.dart:34-36`). **RF-13 pide registrar el responsable** y la aplicación no lo guarda: queda para decisión de Roderich (límite académico o trabajo). Evidence se mantiene **Partial**.

### 3.2 Interfaz, reportes y recuperación (preparado por C)

### #44 REC-008 — Fotografías de factura

**Campos actuales:** Status **Backlog** · Evidence **Partial** · Phase F10 · Origin Reconstructed · EI-03.

| # | Criterio (literal) | Código (`f4dbb18`) | Prueba / evidencia (SHA, fecha) | Cobertura | Hallazgo histórico → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dado un formulario de compra, cuando el usuario adjunta una foto desde la cámara o la galería y confirma, entonces la imagen se copia a la carpeta privada `invoices` y la compra conserva su ruta en `invoice_image_path`.» | `purchase_form_screen.dart:196` (`_pickImage`), `:519` cámara, `:526` galería, `:273-283` (`storeInvoiceImage` y `invoiceImagePath`); `agro_repository.dart:2418-2430` (copia a `invoices/` con nombre `invoice_<µs><ext>`, `.jpg` por defecto); `:940` (`invoice_image_path`); `invoice_storage.dart:15` | **DEVICE, sólo galería:** M5 de la serie 1 (POCO, `dff6802`, 2026-10-17, A1 04:21Z: `invoice_…jpg` en `app_flutter/invoices`), serie 2 (HONOR, `ad5b43d`, 2026-10-18, A4 y A4-F: fotos 0 → 1 → 2, `invoice_…jpg` de 720 747 B). HOST: `repository_test.dart` y `e2e_scenario_test.dart` sólo pasan una ruta literal a `PurchaseDraft` | DEVICE material para la galería; **la cámara no se ejercitó**. HOST repite (no llama a `storeInvoiceImage`) | 10-15 punto 1 (sin prueba de `storeInvoiceImage`) y punto 2 (sin prueba de widget de cámara/galería) → **siguen**: `rg storeInvoiceImage test/` no da nada | Prueba de `storeInvoiceImage` (bytes íntegros, `.jpg` por defecto, ruta guardada). Cámara: no ejercitada en ningún soporte |
| 2 | «Dada una compra con fotografía, cuando se consulta el historial de compras, entonces aparece la opción de ver la factura y la imagen se abre.» | `purchases_screen.dart:264-269` (opción «Ver factura» sólo si hay `invoice_image_path`), `:255-257`, `:48-70` (`_viewInvoice`: diálogo con `Image.file`; si falta el archivo, «La imagen de factura ya no está disponible…») | **Ninguna.** Ninguna prueba abre el visor; las series F10 no registran «Ver factura» | — | 10-15 punto 3 → **sigue** | **Criterio material sin evidencia:** prueba de widget de la opción, del diálogo y del aviso de archivo ausente |
| 3 | «Dadas compras con fotografías, cuando se exporta el respaldo, entonces el contenedor incluye cada fotografía con sus bytes originales. Si falta alguna, se avisa sin ocultar la pérdida.» | `backup_service.dart:261` (`export`), `:291-343` (adjuntos con SHA-256, `missingAttachments` y aviso) | HOST: `backup_container_test.dart:162`, `:185` y `:198` («una fotografía que ya no existe se avisa, no se oculta»), `6c6a1a2`, 2026-10-16. DEVICE: `F08_MOBILE_RESTORE.md` §5 (POCO, 2026-10-16, 3 compras con foto) y `F10_RESTORE_DEVICE.md` caso A («Contiene la base de datos y 3 fotografía(s)», POCO, `2f4b634`, 2026-10-16) | material, HOST + DEVICE | — | — |
| 4 | «Dado un respaldo con una fotografía ausente o alterada, cuando se valida, entonces se rechaza sin tocar la base ni las fotografías existentes.» | `backup_service.dart:483` (`validate`); exige el SHA-256 de cada adjunto | HOST: `backup_container_test.dart:326` y `:334`; `backup_restore_sha256_test.dart` (8 casos, `1663e92`, 2026-10-16), incluido «un nombre de fotografía con ruta se rechaza» y, en F08, «una fotografía no descrita en el manifiesto no se restaura» (fallaba antes de `6c6a1a2`). DEVICE: `F10_RESTORE_DEVICE.md` caso C (alterada: rechazo y todo igual) | material, HOST + DEVICE | Hueco señalado en el comentario de #55 (un adjunto sin `sha256` pasaba) → **resuelto** en `6c6a1a2` (#90) | — |
| 5 | «Dado un respaldo válido, cuando se restaura en otro dispositivo o carpeta, entonces se recuperan las fotografías y las rutas de las compras apuntan a archivos existentes en la carpeta local.» | `backup_service.dart:817` (`restore`) | HOST: `backup_container_test.dart:503` («las rutas se reconstruyen para este dispositivo»). DEVICE: `F10_RESTORE_DEVICE.md` caso A (ruta modificada) y `F08_MOBILE_RESTORE.md` §5 (`invoice_image_path` reconstruida y fotos iguales en nombre y SHA-256) | material, HOST + DEVICE | — | — |
| 6 | «Dada una compra con fotografía, cuando se prepara la información colectiva, entonces la fotografía no forma parte de ella.» | `sync_wire.dart:6` (`envelopeOf`) y `sync_outbox_store.dart:189-204`: el payload sólo lleva `campaign_ref`, `product_ref`, `base_unit` y `quantity_base` | HOST: `need_sync_payload_test.dart:36` («payload con exactamente la whitelist de cada acción»; afirma el conjunto exacto de claves) y `sync_wire_test.dart:177` («whitelist cerrada»), `30c04b6`, 2026-10-15. DEVICE: `F10_PREFLIGHT_DSUX.md` (POCO, `fd8dc7d`, 2026-10-19): tras activar, el teléfono sólo envió `refresh` y `push`, y no hizo ninguna petición a rutas privadas (`requests_observador.txt`) | material: un conjunto exacto de claves excluye cualquier campo de foto; HOST + DEVICE | 10-15 punto 4 → **resuelto** por las pruebas de whitelist (F05/F06) | — |

**Documentación:**
- **El punto 5 del 15/10 era sólo en parte cierto.** `docs/13_LOCAL_STORAGE.md:181-185` conserva el apartado «Limitacion conocida (sin resolver)», que dice que el respaldo contiene sólo la base. Pero el mismo archivo, en `:246-250`, añade «Actualización 2026-09-06 — Respaldo 2.0 … Esa limitación queda cerrada». Esa actualización ya existía en `bc08477`, antes del 15/10.
- **Sigue la contradicción interna** del documento: el encabezado viejo no se retiró.

**Propuesta:** **Validation + Partial**, con el hueco concreto:
- el visor (criterio 2) no tiene ninguna evidencia;
- `storeInvoiceImage` no tiene prueba directa, y la cámara no se ejercitó.

**Comprobación nueva propuesta (no ejecutada):** un archivo aparte, `test/rec_008_invoice_viewer_test.dart`, de unos 45 min:
- (a) `storeInvoiceImage` con `_WorkspacePathProvider`: bytes íntegros, `.jpg` por defecto y la ruta guardada;
- (b) `PurchasesScreen`: la opción «Ver factura» sólo con ruta, el diálogo con la imagen y el aviso si falta el archivo.

No cambia el código de producción. La cámara queda como límite: necesita un dispositivo o simular `ImagePicker`.

**Texto de resolución (para el comentario de #44):**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura; las pruebas citadas pasan en Flutter CI 39198106138 sobre ese commit).

Cubierto:
- Copia a invoices/ y ruta en la compra: en dispositivo por galería (M5 de las series F10 1 y 2: POCO dff6802, 2026-10-17; HONOR ad5b43d, 2026-10-18).
- Respaldo con fotos y aviso de las que faltan: backup_container_test (6c6a1a2). En dispositivo: F08_MOBILE_RESTORE §5 y F10_RESTORE_DEVICE A (POCO, 2026-10-16).
- Rechazo de una foto ausente o alterada: backup_container_test, backup_restore_sha256_test (1663e92), F10_RESTORE_DEVICE C.
- Rutas reconstruidas en otra carpeta: backup_container_test:503 y F10_RESTORE_DEVICE A.
- Exclusión de la foto de la información colectiva: el payload tiene exactamente la whitelist de 4 campos (need_sync_payload_test, sync_wire_test). En el preflight del POCO (fd8dc7d, 2026-10-19), tras activar, el teléfono sólo envió refresh y push.

Falta:
- El visor de factura en el historial de compras (criterio 2): ninguna prueba ni evidencia de dispositivo.
- Una prueba directa de AgroRepository.storeInvoiceImage.
- La cámara no se ejercitó, ni en dispositivo ni con un selector simulado.
- docs/13_LOCAL_STORAGE.md conserva el apartado «Limitacion conocida (sin resolver)», contradicho por su propia actualización del 2026-09-06.

Estado propuesto: Validation · Evidence Partial. No se cierra.
```

---

### #51 REC-015 — Dashboard, perfiles y bitácora de chaco

**Campos actuales:** Status **Backlog** · Evidence **Partial** · Phase F04 · Origin Reconstructed · EI-03.

| # | Criterio (literal) | Código (`f4dbb18`) | Prueba / evidencia | Cobertura | Hallazgo histórico → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dado un escenario con compras, una aplicación y pagos, cuando se consulta el dashboard, entonces los totales de compras, pagos, saldos por cobrar y stock coinciden con los calculados a mano. Con la base vacía, todos los totales valen cero y no se produce ningún error.» | `agro_repository.dart:2361` (`dashboard()`); `dashboard_screen.dart:105-131` (tarjetas) | HOST: `reports_test.dart`, grupo `dashboard`: «resume compras, stock y saldos con los valores esperados», «refleja pagos de proveedor y de cuenta», «base vacía devuelve todo en cero sin lanzar» (valores fijos, p. ej. `purchasesBobMinor` 250000 y `stockBase` 25000; `de5d0d4`, 2026-09-05). DEVICE: R1 de la serie 3 (POCO, 2026-10-18): tarjetas con importes en las 11 repeticiones; no se contrastaron a mano | material en la consulta (valores calculados a mano en la prueba); la pantalla sólo da formato | 10-15 punto 4 (la pantalla no cubre las tarjetas de resumen) → la pantalla sigue sin prueba de valores; el criterio se cumple en la consulta | — (la prueba de pantalla es deseable, no material) |
| 2 | «Dado un familiar con un chaco y consumos, cuando se abre su perfil, entonces aparecen su superficie, su saldo, su stock por producto y unidad y su estado de cuenta. Si una aplicación se revirtió, el estado de cuenta conserva el cargo original y muestra además el crédito compensatorio.» | `person_detail_screen.dart:28-29` (`farmsForPerson` y `applications(personId:)`), `:58`, `:82` (saldo total); `agro_repository.dart:2312` (`statement`) | HOST, sólo la regla del estado de cuenta: `report_composer_test.dart:462` («una reversión aparece como crédito, no borra el cargo»; `ac52e4e`, 2026-10-15) y `typed_reads_parity_test.dart:278` (reversión igual en los caminos legacy y tipado; `a6da1be`). **Ninguna prueba monta `PersonDetailScreen` ni comprueba lo que muestra** | la regla del cargo y del crédito es material en composición y lectura; **la pantalla del perfil no está cubierta** | 10-15 punto 3 → **sigue** | Prueba de widget del perfil: superficie, saldo, stock por producto y unidad, y estado de cuenta con una reversión |
| 3 | «Dado un chaco con aplicaciones, cuando se abre su bitácora, entonces cada aplicación aparece con fecha, campaña, persona, producto, área, dosis, cantidad teórica y real, costo y lotes FIFO consumidos. La consulta `farmLogbook` del repositorio permite además filtrar por campaña y por producto.» | `agro_repository.dart:2129` (`farmProfile`), `:2139-2161` (`farmLogbook`: filtros `campaignId` y `productId`, columna `fifo_lots`, consumos no revertidos); `farm_logbook_screen.dart:19-20` y `:70` | **Ninguna.** `rg farmLogbook\|farmProfile\|FarmLogbookScreen test/` no da nada | — | 10-15 punto 1 → **sigue** | **Criterio material sin prueba:** `farmLogbook` con los dos filtros, `fifo_lots` y una aplicación revertida; montaje de `FarmLogbookScreen` |
| 4 | «Dado un móvil del ancho de un Pixel 8, cuando el dashboard muestra stock, entonces cada fila de inventario presenta el nombre del producto junto a sus cifras rotuladas y no hay desplazamiento horizontal.» | `dashboard_screen.dart:400` (`_tableMinWidth` = 560) y `_InventoryCards` | HOST: `ui_polish_test.dart:118-156` (UIBUG-023: «en ancho de móvil no hay tabla desplazable en horizontal», «cada fila muestra el nombre junto a sus cifras etiquetadas»; `18889b6`, 2026-09-05). DEVICE: R1 de la serie 3 (POCO, 392,7 dp, 2026-10-18): la primera fila de `_InventoryCards` con nombre y etiquetas Físico · Comprometido · Proyección (`F10_RENDIMIENTO_MOBILE_S3.md` §4) | material, HOST + DEVICE | — | — |

**Otros hallazgos del 15/10:**
- **Punto 5 resuelto:** el archivo de evidencia existe desde la integración de la baseline.
- **El recorrido de rutas en el Pixel 8** que cita el issue sigue sin archivo propio. Lo sustituyen como evidencia de dispositivo las series F10 en el POCO y en el HONOR.

**Propuesta:** **Validation + Partial**, con dos huecos materiales:
- la bitácora (criterio 3) no tiene ninguna prueba;
- el contenido del perfil (criterio 2) no se comprueba en pantalla.

**Comprobación nueva propuesta (no ejecutada):** `test/rec_015_logbook_profile_test.dart`, de 60 a 75 min:
- `farmLogbook` con un filtro de campaña, uno de producto, `fifo_lots` y una reversión;
- `FarmLogbookScreen` con los campos del criterio;
- `PersonDetailScreen` con superficie, saldo, stock y estado de cuenta con una reversión.

No cambia el código de producción.

**Texto de resolución:**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura; las pruebas pasan en Flutter CI 39198106138).

Cubierto:
- Totales del dashboard y base vacía: reports_test, grupo dashboard, con valores calculados a mano (de5d0d4).
- Fila de inventario con nombre y cifras rotuladas, sin desplazamiento horizontal en ancho de móvil: ui_polish_test, UIBUG-023. En dispositivo: R1 de la serie F10 3 en el POCO (2026-10-18).
- Regla del estado de cuenta con una reversión (se conserva el cargo y se añade el crédito): report_composer_test:462 y typed_reads_parity_test:278.

Falta:
- Bitácora de chaco: ninguna prueba de farmLogbook (filtros por campaña y producto, fifo_lots, reversiones) ni de FarmLogbookScreen.
- Perfil de persona: ninguna prueba comprueba lo que muestra PersonDetailScreen.

Estado propuesto: Validation · Evidence Partial. No se cierra.
```

---

### #52 REC-016 — Lecturas tipadas y composición neutral de reportes (prioridad documental)

**Campos actuales:** Status **In Review** · Evidence **Partial** · Phase F04 · Origin Reconstructed · EI-04.

**Discrepancia documental:**
- `REC_MOBILE_BASELINE.md:27` marcó #52 como «full · Verified» el 2026-10-15.
- La nota del mismo archivo del 2026-10-17 («Revisión de la sesión C… #52 no se cierra. Sólo 2 de los 5 reportes comparan contenido, así que “full” no se sostiene») la corrige sin reescribir la tabla.
- **El tablero (Partial) es coherente con esa nota.** No hay error de campo: la fila del 15/10 es registro histórico y la nota del 17/10 es el estado vigente.

| # | Criterio (literal) | Código (`f4dbb18`) | Prueba / evidencia | Cobertura | Hallazgo → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dado un conjunto de datos de campañas, compras, aplicaciones y cuentas, cuando se ejecuta cada lectura tipada y su equivalente legacy sobre la misma base, entonces ambos caminos devuelven el mismo número de filas, en el mismo orden y con los mismos valores enteros, incluidas las reversiones y la base vacía.» | `lib/data/typed_reads.dart` | `typed_reads_parity_test.dart`: 13 casos, uno por lectura (`:111-249`), la reversión (`:278`) y la base vacía (`:300`); `a6da1be`, 2026-09-06 | material, HOST | — | — |
| 2 | «Dada una fila con una columna ausente, nula donde no se permite o de tipo inválido, cuando se mapea al modelo tipado, entonces falla con `RowMappingException`, que nombra la consulta y la columna sin exponer el valor.» | `read_models.dart:27-39` | `read_models_test.dart:31`, `:60`, `:77` y `:90` («el mensaje no incluye el valor de la celda»); 23 casos, `a6da1be` | material, HOST | — | — |
| 3 | «Dados modelos tipados de entrada, cuando `ReportComposer` compone cualquiera de los cinco reportes, entonces produce un `ReportTable` con columnas, filtros y totales enteros sin depender de SQLite ni de los formatos CSV o PDF.» | `report_composer.dart:92`, `:128`, `:161`, `:203` y `:255` (los cinco) | `report_composer_test.dart`: 37 casos, `ac52e4e`, 2026-10-15 | material, HOST | — | — |
| 4 | «Dado el servicio de exportación migrado a lecturas tipadas, cuando se exportan los cinco reportes, entonces el contenido coincide con las consultas de la aplicación y la base de datos no se modifica.» | `report_export_service.dart:131-192`: cada tipo con su lectura tipada | `report_export_service_test.dart` (`fccd74c`, 2026-10-15): `:290` «los diez reportes dejan la base byte a byte igual» y `:308`; `:118` «… produce un archivo», sólo existencia. **Coherencia de contenido sólo en 2 de 5:** `:328` (inventario) y `:341` (estado de cuenta) | la parte de la base no modificada es material para los 5; **el contenido no se compara para costo por producto, costo por chaco ni resumen de campaña** | Nota del 17/10 (2 de 5) → **sigue** | **Faltan 3 comparaciones de contenido**: un error de cableado entre el tipo y su lectura o filtro (`:137-165`) no se detectaría |

**Propuesta:** **Validation + Partial**, con el hueco concreto: la coherencia de contenido de 3 de los 5 reportes en la exportación.

Si Roderich acepta como suficiente la cadena paridad de lecturas + compositor + cableado visible en `report_export_service.dart:137-165`, puede declararlo como límite académico y pasar a **Done + Partial**. **No propongo Verified** mientras falten esas 3 comparaciones.

**Comprobación nueva propuesta (no ejecutada):** `test/rec_016_export_coherence_test.dart`, de unos 30 min. Exporta el costo por producto, el costo por chaco y el resumen de campaña, y compara sus filas y totales con `productCostReportTyped`, `farmCostReportTyped` y `campaignCloseSummaryTyped` sobre la misma base. No cambia el código de producción.

**Texto de resolución:**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura; las pruebas pasan en Flutter CI 39198106138).

Estado documental: REC_MOBILE_BASELINE.md marcó #52 «full · Verified» el 2026-10-15. Su nota del 2026-10-17 lo corrigió («sólo 2 de los 5 reportes comparan contenido»). El Partial del tablero es el estado vigente.

Cubierto:
- Paridad tipado/legacy en todas las lecturas, con reversión y base vacía: typed_reads_parity_test, 13 casos.
- RowMappingException con consulta y columna, sin el valor: read_models_test.
- Composición de los cinco reportes sin SQLite, CSV ni PDF: report_composer_test, 37 casos.
- Ninguno de los diez reportes (5 × 2 formatos) modifica la base: report_export_service_test:290.

Falta:
- La comparación de contenido en la exportación de costo por producto, costo por chaco y resumen de campaña. Hoy sólo se comparan el inventario (:328) y el estado de cuenta (:341).

Estado propuesto: Validation · Evidence Partial (o Done · Partial si Roderich acepta ese límite). No se cierra como Verified.
```

---

### #53 REC-017 — Exportación CSV

**Campos actuales:** Status **Backlog** · Evidence **Partial** · Phase F10 · Origin Reconstructed · EI-04.

| # | Criterio (literal) | Código (`f4dbb18`) | Prueba / evidencia | Cobertura | Hallazgo → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dado un reporte con filas, cuando se genera el CSV, entonces empieza por el BOM UTF-8, separa los campos con `;`, termina cada registro con CRLF y conserva el título, la fecha, los filtros, las cabeceras, las filas y los totales.» | `csv_report_generator.dart:52-71` | `report_csv_test.dart:41`, `:52`, `:63`, `:81` y `:236` (`67081a3`, 2026-09-06) | material, HOST | — | — |
| 2 | «Dado un texto con comillas, `;`, saltos de línea o espacios en los extremos, cuando se genera el CSV, entonces la celda se entrecomilla y se doblan las comillas.» | `csv_report_generator.dart:107-112` (`_escape`) | `report_csv_test.dart:96`, `:107`, `:118` y `:134` | material, HOST (por subcadenas; sin un parser externo, que era opcional el 15/10) | — | — |
| 3 | «Dado un texto que empieza por `=`, `+`, `-`, `@` o una tabulación, cuando se genera el CSV, entonces se neutraliza con un apóstrofo, mientras que un importe negativo se mantiene numérico.» | `csv_report_generator.dart:36` (disparadores, `\t` y `\r` incluidos), `:100-104` (`_neutralize` aplica `trimLeft()` antes de mirar el primer carácter) | `report_csv_test.dart:190`, `:196`, `:200`, `:205` («una tabulación inicial también se neutraliza», con `'\t=1+1'`) y `:213` (importe negativo) | material para `=`, `+`, `-`, `@` y el importe; **no para la tabulación sola** | El comentario del 15/10 lo anticipaba: `trimLeft()` elimina `\t` y `\r`, así que `'\tABC'` no se neutraliza; la prueba sólo pasa gracias al `=` → **sigue**. Código sin cambios desde `67081a3`. **Defecto probable, comprobado por lectura, no por ejecución** | Prueba con `'\tABC'` y `'\rABC'` y corrección de una línea en `_neutralize` (cambio de producción: lo decide Roderich) |
| 4 | «Dado un reporte sin filas, cuando se exporta, entonces el CSV conserva las cabeceras, los filtros y el mensaje de estado vacío.» | `csv_report_generator.dart:63-64` | `report_csv_test.dart:250`; `reports_screen_test.dart:241` | material, HOST | — | — |
| 5 | «Dado un filtro inexistente o un fallo de almacenamiento, cuando se exporta, entonces se informa un error tipado, no queda archivo final ni temporal y la base no cambia.» | `report_export_service.dart` (errores tipados); `report_storage.dart:92-123` (temporal y renombrado) | `report_export_service_test.dart:155`, `:170`, `:183`, `:190` y `:308`; `report_storage_test.dart` (18 casos, `90aa23c`); `reports_screen_test.dart:282` y `:295` | material, HOST | — | — |
| 6 | «Dada una exportación en curso, cuando el usuario cancela, entonces no queda ningún archivo y la pantalla muestra “Exportación cancelada. No se guardó ningún archivo.” (pendiente de test de interfaz).» | `reports_screen.dart:137` (mensaje) y `:419` (`_running?.cancel()`) | En el servicio: `report_export_service_test.dart:226` y `:239` (no queda archivo). En la pantalla: `reports_screen_test.dart:256` sólo muestra progreso y no pulsa Cancelar | lo de no dejar archivo es material en el servicio; **el mensaje de la pantalla no se prueba** | 10-15 punto 1 → **sigue** (`rg "Exportación cancelada" test/` no da nada) | Prueba de interfaz con un servicio cuyo `compose` espere (sobrescribiendo `reportExportServiceProvider`), como describía el comentario del 15/10 |
| 7 | «Dada una exportación correcta en CSV, cuando termina, entonces la pantalla muestra “Reporte guardado” con el nombre y la carpeta, y el archivo guardado tiene extensión `.csv`.» | `reports_screen.dart:198` | `reports_screen_test.dart:209` (nombre y carpeta, en PDF) y `:229` (CSV: botón y extensión) | en parte: con CSV sólo se comprueba la extensión | 10-15 punto 5 → **sigue** | Comprobar nombre y carpeta también con CSV (dos líneas en `:229`) |

**Trazabilidad:** el 15/10 se señaló que `RF-31` («conservar la consulta histórica…») no corresponde a la exportación CSV. **Sigue** en el campo `Requirement refs`. Lo decide Roderich, con un ID del Cap. III; no se propone ninguno aquí.

**Propuesta:** **pendiente**. Falta algo de verdad:
- **un defecto probable** del criterio 3 (la tabulación sola);
- **la prueba de interfaz** que el propio criterio 6 declara pendiente.

Mantener **Backlog** (o In Progress si se trabaja) con **Evidence Partial**.

**Comprobación nueva:** las dos pruebas descritas en el comentario del 15/10 (unos 55 min) y la corrección de una línea en `_neutralize`. **No se ejecutó nada.** La corrección es un cambio de producción: antes, un PR propio con el visto bueno de Roderich.

**Texto de resolución:**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura; las pruebas citadas pasan en Flutter CI 39198106138).

Cubierto:
- BOM, «;», CRLF, cabecera, filas y totales: report_csv_test.
- Entrecomillado y comillas dobladas: report_csv_test.
- Neutralización de =, +, -, @ e importe negativo numérico: report_csv_test.
- Reporte vacío: report_csv_test:250 y reports_screen_test:241.
- Errores tipados sin archivo y sin cambios en la base: report_export_service_test, report_storage_test y reports_screen_test.
- Cancelación sin archivo, a nivel de servicio: report_export_service_test:226 y :239.

Falta:
- Una celda que empieza por tabulación o retorno de carro y no sigue con «=» no se neutraliza: _neutralize aplica trimLeft() antes de mirar el primer carácter (csv_report_generator.dart:100-104). La prueba :205 pasa sólo por el «=». Comprobado por lectura; requiere una prueba y una corrección de una línea.
- Ninguna prueba de interfaz pulsa «Cancelar» ni comprueba «Exportación cancelada. No se guardó ningún archivo.».
- Con CSV, el diálogo de éxito sólo se comprueba por la extensión, no por el nombre y la carpeta.
- Requirement refs RF-31 no corresponde a la exportación CSV (señalado el 2026-10-15); lo decide Roderich.

Estado propuesto: pendiente · Evidence Partial. No se cierra.
```

---

### #55 REC-019 — Respaldo local con fotos, integridad, legacy y rollback

**Campos actuales:** Status **Backlog** · Evidence **Partial** · Phase F08 · Origin Reconstructed · EI-04.

| # | Criterio (literal) | Código (`f4dbb18`) | Prueba / evidencia | Cobertura | Hallazgo → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dada una base con compras con fotografía, cuando se exporta el respaldo, entonces se genera un .agrobackup con manifiesto, base y fotografías, y el archivo pasa la validación de la propia aplicación.» | `backup_service.dart:261-343` | HOST: `backup_container_test.dart:131-219` (grupo «exportación»); `backup_export_atomic_test.dart`: 3 casos, entre ellos «un fallo con el parcial ya escrito no deja ningún archivo» y «una copia truncada sin excepción no se publica» (`e5a1364`, 2026-10-16). DEVICE: `F08_MOBILE_RESTORE.md` §5 y `F10_RESTORE_DEVICE.md` (POCO, 2026-10-16): exportación con 3 fotos, verificada por SHA-256 | material, HOST + DEVICE | 10-15 (2): un fallo de exportación podía dejar un artefacto → **resuelto** en `6c6a1a2` (#90) y `e5a1364` | — |
| 2 | «Dado un contenedor con una fotografía alterada, ausente, sin manifiesto, de otra aplicación o con un esquema futuro, cuando se valida o se restaura, entonces se rechaza sin modificar la base ni las fotografías actuales.» | `backup_service.dart:483` (`validate`), `:653-671` | HOST: `backup_container_test.dart:258-363` (13 casos de daño); `backup_restore_sha256_test.dart` (8 casos: base alterada con SQL válido, manifiesto sin SHA-256 o sin descripción, tamaño distinto, nombre con ruta; `1663e92`); `f10_backup_extract_limits_test.dart` (17 casos, `f211ea0`, 2026-10-16). DEVICE: `F10_RESTORE_DEVICE.md` caso C (alterada, ajena y bomba: todo IGUAL) | material, HOST + DEVICE | «Hueco omitido» del 15/10 (el SHA-256 de la base no se comparaba; un adjunto sin `sha256` pasaba) → **resuelto** en `6c6a1a2` (#90); en F08 esas pruebas fallaban antes de la corrección | — |
| 3 | «Dado un respaldo .db histórico, cuando se restaura, entonces la base se recupera y se avisa de que no contiene fotografías.» | `backup_service.dart:30`, `:48`, `:69` y `:689` (formato `legacyDatabase`) | HOST: `backup_container_test.dart:392` y `:412` («restaurarlo funciona y avisa de que no trae fotografías»); con esquema antiguo, `rec_019_restore_legacy_schema_test.dart` (`60f169e`, 2026-10-17; `REC_019_RESTORE_LEGACY.md`: base v7 sintetizada, `user_version` 9, `integrity_check` ok, filas idénticas; la mutación se detecta) | material, **sólo HOST** (base v7 sintetizada, no generada por una app v7) | 10-15 (3): la prueba de esquema antiguo sólo validaba → **resuelto** por MOB #106 (`60f169e`); la prueba antigua se conserva con su nombre | — (límite declarado: base sintetizada) |
| 4 | «Dado un respaldo válido restaurado en otra carpeta de facturas, cuando termina la restauración, entonces cada compra apunta a una fotografía existente en este dispositivo y la base pasa integrity_check.» | `backup_service.dart:817` (`restore`), `:905` (copia previa) | HOST: `backup_container_test.dart:503`, `:534` y `:631`. DEVICE: `F10_RESTORE_DEVICE.md` caso A (ruta modificada, 3 fotos, `.previo` creada y consultada, `integrity_check` ok) | material, HOST + DEVICE | — | — |
| 5 | «Dado un fallo a mitad de la restauración, cuando se interrumpe la copia de fotografías, entonces la base y las fotografías vuelven al estado previo.» | `backup_service.dart:817-905`; `guarded_restore.dart:66-83` | HOST: `backup_container_test.dart:590` («un fallo a mitad de la restauración lo deshace todo»); `f10_restore_wal_rollback_test.dart` (7 casos, `3552397`, 2026-10-16); `f04_restore_authorization_test.dart:410`. DEVICE: `F10_RESTORE_DEVICE.md` caso B (fallo después de sustituir: 29 tablas y 3 fotos IGUAL) | material, HOST + DEVICE | — | — |
| 6 | «Dado un respaldo de otro agricultor, cuando se intenta restaurar, entonces se rechaza (pendiente: no implementado).» | `domain/restore_ownership.dart:56-72` («Esta copia pertenece a otro titular…»); `guarded_restore.dart:60-83` | HOST: `f04_restore_ownership_rules_test.dart` (11 casos, `812fe49`, 2026-10-15), `f04_restore_authorization_test.dart` (13 casos, `d63bfce`, 2026-10-17) y `f04_admin_owner_restore_ui_test.dart` (7). DEVICE: `F10_RESTORE_DEVICE.md` caso C («ajena» → rechazo antes de sustituir, 0 push) y C34 | material, HOST + DEVICE | 10-15 (1): sin identidad ni propiedad → **resuelto** en `812fe49` (#78), `F04_CORRECCIONES_REVISION.md` parte B. **La nota «(pendiente: no implementado)» del criterio ya no describe el código** | — |

**Otros hallazgos del 15/10, sin efecto sobre los criterios:**
- **(4) Faltan pruebas de interfaz** de los flujos de exportar y restaurar en local. **Sigue** en HOST. En DEVICE, la restauración desde la nube (A) y la validación desde la lista local (C) usan la misma interfaz y el mismo código.
- **`InvoiceStorage`** sigue sin prueba propia; es el hueco de #44.
- **(5) El ciclo físico de `docs/46`** es documental. Lo sustituyen como evidencia de dispositivo `F08_MOBILE_RESTORE` §5 y `F10_RESTORE_DEVICE` (POCO, 2026-10-16).
- **HOST frente a DEVICE:** los seis criterios tienen HOST material. Tienen además DEVICE el 1, el 2, el 4, el 5 y el 6; el 3 es sólo HOST.
- **Las 22 filas DEVICE diferidas de Roderich1/Agro_Sindicato_Backend-Web#18** (`docs/evidence/F05_SYNC_06.md` del Backend, §3, columna Mobile NOT_MEASURED de la suite adversarial de Sync) no intervienen en #55 y no se usan aquí.

**Propuesta:** **Done + Verified + cierre completed.** Los seis criterios están cubiertos, integrados en `main` y con evidencia; cinco de ellos, también en el teléfono. Límites que se declaran sin bloquear el cierre:
- el esquema antiguo se probó con una base v7 sintetizada, sólo en HOST;
- no hay pruebas de widget de los flujos de exportar y restaurar en local;
- la restauración en un **teléfono nuevo** es el límite con el que se cerró MOB #36 (F08, Done · Partial), fuera de esta REC.

**Texto de resolución:**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura; las pruebas pasan en Flutter CI 39198106138). Criterio por criterio:

1. Exportación .agrobackup con manifiesto, base y fotos, revalidada; sin artefacto ante un fallo. backup_container_test y backup_export_atomic_test (6c6a1a2 #90, e5a1364). En dispositivo: F08_MOBILE_RESTORE §5 y F10_RESTORE_DEVICE (POCO, 2026-10-16).
2. Rechazo de foto alterada o ausente, sin manifiesto, de otra aplicación o de esquema futuro, sin cambios. backup_container_test, backup_restore_sha256_test (1663e92: el SHA-256 de la base ahora se compara) y f10_backup_extract_limits_test. En dispositivo: F10_RESTORE_DEVICE C (alterada, ajena y bomba; todo igual).
3. Respaldo .db histórico restaurado con aviso de que no trae fotos. backup_container_test:412. Con esquema antiguo y migración: rec_019_restore_legacy_schema_test (60f169e, base v7 sintetizada; REC_019_RESTORE_LEGACY.md).
4. Restauración en otra carpeta, con rutas reconstruidas e integrity_check. backup_container_test:503 y :631. En dispositivo: F10_RESTORE_DEVICE A.
5. Fallo a mitad con vuelta al estado previo de base y fotos. backup_container_test:590 y f10_restore_wal_rollback_test (3552397). En dispositivo: F10_RESTORE_DEVICE B.
6. Rechazo de la copia de otro titular, antes de sustituir. Implementado en 812fe49 (#78): f04_restore_ownership_rules_test y f04_restore_authorization_test. En dispositivo: F10_RESTORE_DEVICE C («ajena»). La nota «pendiente: no implementado» del criterio ya no describe el código.

Límites declarados:
- El esquema antiguo se probó con una base v7 sintetizada, sólo en host.
- No hay pruebas de widget de exportar y restaurar en local; el dispositivo cubre la interfaz de restauración.
- InvoiceStorage sin prueba propia (ver #44).
- La restauración en un teléfono nuevo es el límite con el que se cerró MOB #36 (F08, Done · Partial), fuera de esta REC.

Estado propuesto: Done · Evidence Verified · cierre completed.
```

---

### #56 REC-020 — Hardening de interfaz, errores, navegación y accesibilidad

**Campos actuales:** Status **Backlog** · Evidence **Partial** · Phase F10 · Origin Reconstructed · EI-04.

**Alcance:** el issue excluye expresamente:
- el estudio de usabilidad (RNF-07: éxito de tareas, SUS);
- las pruebas automatizadas de accesibilidad semántica;
- la compatibilidad con navegadores.

Por eso los puntos 1 y 2 del 15/10 no bloquean sus criterios.

| # | Criterio (literal) | Código (`f4dbb18`) | Prueba / evidencia | Cobertura | Hallazgo → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dado un fallo del repositorio en Compras o Liquidaciones, cuando se abre la pantalla, entonces no queda un indicador de carga y se muestra el mensaje de negocio sin prefijo técnico.» | `purchases_screen.dart:162-165`, `settlements_screen.dart:483-486`, `common.dart:300` (`friendlyError`) | `error_states_test.dart:76`, `:99` y `:122` (STAB-004 en liquidación y compras; «pasa por friendlyError (sin prefijo técnico)»; `de5d0d4`) | material, HOST | — | — |
| 2 | «Dada una subruta (detalle de persona, de inventario o de operación), cuando el usuario pulsa Atrás, entonces vuelve a la pantalla padre. Desde un destino raíz vuelve a Inicio, y desde Inicio no redirige.» | `app_shell.dart:107` (`backFallback`), `:288` (`PopScope`), `:79` (`selectedIndex`) | `hierarchical_navigation_test.dart`: 11 casos (`5f112a1`, 2026-10-15) | material, HOST | — | — |
| 3 | «Dada una ruta declarada en `lib/app.dart`, cuando se analiza `lib/`, entonces existe un punto de navegación hacia ella; el historial de compras se alcanza desde Operaciones.» | `lib/app.dart` (rutas) | `purchases_access_test.dart:134` («ninguna ruta declarada queda sin origen en lib/») y sus 3 casos (`5f112a1`) | material, HOST (análisis estático) | — | — |
| 4 | «Dado un Pixel 8 en horizontal con la fuente al 130 %, cuando se muestra el shell, entonces usa NavigationRail dentro de un scroll, sin desbordamiento y con los 5 destinos visibles.» | `app_shell.dart:167-173` (`SingleChildScrollView` + `NavigationRail`) | `ui_polish_test.dart:440` y `:462` (Pixel 8 apaisado, 2400×1080 a DPR 2,625, fuente 1,3) | material, HOST | — | — |
| 5 | «Dados los anchos 360, 393, 600 y 800 dp y texto al 140 %, cuando se abren los formularios de plan y de transferencia, entonces no se produce ninguna excepción de layout.» | `plan_form_screen.dart`, `transfer_form_screen.dart` | `responsive_v5_test.dart:15-26` (cinco tamaños, `textScaleFactorTestValue = 1.4`, `takeException()` nulo; `5d0b8ef`) | material, HOST | — | — |
| 6 | «Dada una aplicación confirmada, cuando el usuario pulsa Revertir, entonces se muestra una confirmación con el chaco y el importe. Cancelar deja la aplicación y el stock intactos; confirmar la revierte y devuelve el stock.» | `applications_screen.dart:66`; `common.dart:248` (`confirmDestructiveAction`) | `destructive_actions_test.dart:98`, `:120` y `:144` (`de5d0d4`) | material, HOST | — | — |
| 7 | «Dado el código de `lib/`, cuando se analiza estáticamente, entonces ningún `setState` de flecha devuelve un Future.» | `lib/` | `set_state_contract_test.dart:78` (`2dd47f9`) | material, HOST | — | — |

**Evidencia posterior que refuerza el alcance (no está en los criterios):**
- **Texto escalado en dispositivo:** M8 CUMPLE en el POCO en A1 y A1-F (serie 3, lib `27c4654`, 2026-10-18), con las pruebas de widget de #97 y #129 (`f10_legibility_97_test.dart`, `f10_compat_129_presentacion_test.dart`). **A4-F del HONOR sigue NO CUMPLE en la serie 2 y pendiente de repetición** (#129, cierre técnico con alcance reducido).
- **Diálogo de descartar cambios en formularios reales**, que el 15/10 sólo estaba en una réplica, en dispositivo:
  - «¿Descartar cambios?» → «Descartar cambios» en Nueva compra y Nueva aplicación (serie 3, H-2; serie 2, M4);
  - «Seguir editando» conservó lo escrito en Nueva compra (preflight `F10_PREFLIGHT_DSUX.md`, I-3).
- **Sigue sin prueba automatizada sobre los formularios reales.** `back_navigation_test.dart` usa una réplica que aún dice «Descartar», y `navigation_test.dart:99` sólo actúa si el diálogo aparece. **Plan y transferencia no tienen evidencia de este diálogo.**

**Otros hallazgos del 15/10:**
- **(1) Accesibilidad semántica:** sigue, pero **fuera del alcance declarado**. `rg meetsGuideline test/` no da nada.
- **(2) Estudio de usabilidad:** fuera del alcance. Preparado en el paquete Backend; RNF-07 no ejecutado.
- **(3) Los 67 UIBUG y el recorrido del Pixel 8:** documentales. Los sustituyen como dispositivo las series F10.
- **(4) Descartar cambios:** en parte, como se describe arriba.
- **(6) La «limitación residual»:** el issue sigue sin nombrarla.

**Propuesta:** **Done + Verified + cierre completed.** Los siete criterios tienen pruebas HOST materiales, integradas y en verde sobre `f4dbb18`. Límites que se declaran en el cierre sin bloquearlo:
- la usabilidad y la accesibilidad semántica, fuera del alcance;
- el diálogo de descartar cambios, sin prueba sobre los formularios reales (sólo dispositivo en compra y aplicación);
- A4-F del HONOR, pendiente.

Si Roderich prefiere que el diálogo cuente como criterio, porque está en «Incluye», la alternativa es **Done + Partial** con ese límite.

**Texto de resolución:**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura; las pruebas pasan en Flutter CI 39198106138). Los siete criterios:
1. Errores en Compras y Liquidaciones sin carga infinita y sin prefijo técnico: error_states_test.
2. Atrás jerárquico y desde destinos raíz: hierarchical_navigation_test.
3. Toda ruta declarada tiene un origen en lib/: purchases_access_test:134.
4. Rail en scroll, Pixel 8 apaisado al 130 %, sin desbordar: ui_polish_test:440 y :462.
5. Formularios de plan y transferencia en 360, 393, 600 y 800 dp al 140 %, sin excepción: responsive_v5_test.
6. Confirmación informada al revertir una aplicación: destructive_actions_test.
7. Ningún setState de lib/ devuelve un Future: set_state_contract_test:78.

Evidencia posterior:
- Texto escalado en dispositivo: M8 CUMPLE en el POCO en A1 y A1-F (serie F10 3, lib 27c4654, 2026-10-18), con las pruebas de #97 y #129.
- Diálogo de descartar cambios observado en Nueva compra y Nueva aplicación en el POCO (serie 3 y preflight del 2026-10-19).

Límites declarados (no son criterios de esta REC):
- El estudio de usabilidad (RNF-07) y la accesibilidad semántica automatizada están fuera del alcance.
- El diálogo de descartar cambios no tiene prueba automatizada sobre los formularios reales; plan y transferencia no tienen evidencia.
- A4-F del HONOR pendiente de repetición (#129).

Estado propuesto: Done · Evidence Verified · cierre completed.
```

---

### #57 REC-021 — CI, regresión y congelación de baseline (prioridad documental)

**Campos actuales:** Status **In Review** · Evidence **Partial** · Phase F04 · Origin Reconstructed · EI-04. Se reabrió el 2026-10-17 tras un cierre por error (PR #70).

**Discrepancia documental:**
- `REC_MOBILE_BASELINE.md:32` dice «partial (tests); CI verificado · Verified — ver REC_021_CI.md».
- `REC_021_CI.md` concluye Verified para el CI.
- Las notas del 2026-10-17 en ambos archivos dejan #57 en Partial por tres puntos:
  - ninguna automatización comprueba el workflow;
  - `docs/46` no registra el SHA del tag;
  - el tag no coincide con el merge de #4.

Lo contrasto abajo: **los tres puntos o están fuera del alcance del issue o ya se pueden resolver con un hecho.**

| # | Criterio (literal) | Código / configuración (`f4dbb18`) | Prueba / evidencia | Cobertura | Hallazgo → resolución | Faltante |
|---|---|---|---|---|---|---|
| 1 | «Dado un PR o un push a `main`, cuando se ejecuta Flutter CI, entonces corren en orden formato, análisis, tests y build de APK release, y el job falla si cualquiera de ellos falla.» | `.github/workflows/flutter-ci.yml:7-11` (disparadores), `:56` pub get, `:59` formato, `:62` análisis, `:65` tests, `:75` repetición de las pruebas de fechas en America/La_Paz (añadida en `ac52e4e`, 2026-10-15), `:82` build | CI **39198106138** sobre `f4dbb18` (2026-10-19): todos los pasos en success y en ese orden. Antes, 37231657078 sobre `278cbd3` (2026-10-04). Un paso que falla corta el job: es el comportamiento por defecto de GitHub Actions, sin `continue-on-error` en el archivo | material (configuración y ejecuciones reales) | — | — |
| 2 | «Dado el workflow, cuando se revisa su configuración, entonces declara solo `contents: read` y no usa keystore ni secretos.» | `flutter-ci.yml:15-16` (`permissions: contents: read`), `:80` («No se sube ningún secreto»); ninguna referencia a `secrets.` | lectura del archivo, 2026-10-19 | material | — | — |
| 3 | «Dado el tag `v1.0.0-base-stable`, cuando se consulta en git, entonces resuelve al commit de `main` que integra el PR #4, y `docs/46_BASELINE_FINAL_FREEZE.md` conserva el commit de partida, las versiones de herramientas y las limitaciones aceptadas.» | tag → **`bd3289f`** «Merge pull request #4 from Roderich1/hardening/final-polish» (2026-09-05T21:16:10-04:00), **ancestro de `main`**; `docs/46_BASELINE_FINAL_FREEZE.md:18` (commit de partida `c36e5b7`), versiones y limitaciones (`bc08477`) | `git rev-parse`, `git merge-base --is-ancestor` y `gh api …/commits/f4c6510` (2026-10-19): el merge que GitHub registra para #4, **`f4c6510`** (01:16:10Z), **tiene el mismo árbol** que `bd3289f` (**`6c005a96…`**) y no está en la historia de `main` (GitHub lo conserva como commit suelto). Es la versión anterior a la reescritura del historial que retiró las líneas de atribución, el mismo caso que `5d57fcc`/`0ab6043` de `REC_021_CI.md` | material: el tag resuelve al merge de #4 que está en `main` | «Discrepancia entre el SHA del tag y la metadata del merge» (riesgo histórico) → **explicada**: mismo árbol y commit reescrito; no hay dos contenidos distintos. `docs/46` sigue sin el SHA del tag, pero el criterio no lo pide | Opcional: anotar `bd3289f` en el comentario de cierre (no hace falta editar `docs/46`) |
| 4 | «Dada la suite de regresión, cuando se ejecuta `flutter test`, entonces pasan los casos de plan de un solo uso, campaña cerrada terminal, respaldo con rollback, equivalencia de esquema migrado y escenario completo de campaña.» | `test/plan_lifecycle_test.dart` (14), `campaign_lifecycle_test.dart` (10), `backup_container_test.dart` (27), `schema_equivalence_test.dart` (4), `e2e_scenario_test.dart` (1), `regression_widget_test.dart` (4) | CI 39198106138, paso *Tests* en success sobre `f4dbb18` | material, HOST | — | — |
| 5 | «Dado `lib/`, cuando corre la guarda estática de `set_state_contract_test.dart`, entonces ningún `setState` devuelve un `Future`.» | — | `set_state_contract_test.dart:78`, en verde en la misma CI | material, HOST | — | — |

**Otros pendientes del 15/10 y del 17/10:**
- **«Ninguna automatización comprueba el workflow»:** el propio issue lo excluye («No incluye: pruebas automatizadas del propio workflow o del tag»). No bloquea. `REC_021_CI.md` lo registró como mejora no bloqueante.
- **«`docs/46` no registra el SHA del tag»:** cierto. El criterio 3 no lo pide; se anota en el cierre.
- **«Falta una ejecución local sobre `278cbd3`»:** histórico. Existe la CI 37231657078 sobre `278cbd3` y la actual 39198106138 sobre `f4dbb18`.

**Propuesta:** **Done + Verified + cierre completed.** Los cinco criterios están cubiertos con configuración y ejecuciones reales. El riesgo histórico del tag queda explicado con un hecho comprobable: el mismo árbol.

**Texto de resolución:**

```text
Conciliación del 2026-10-19 sobre Mobile main f4dbb18 (sesión C, sólo lectura).

1. Flutter CI corre en orden pub get, formato, análisis, tests, tests de fechas en America/La_Paz y build release, en PR, en push a main y a mano (flutter-ci.yml:7-82). Un paso fallido corta el job. Ejecución 39198106138 sobre f4dbb18 (2026-10-19): todos los pasos en success.
2. permissions: contents: read (flutter-ci.yml:15-16); sin keystore ni secretos.
3. El tag v1.0.0-base-stable resuelve a bd3289f, «Merge pull request #4 from Roderich1/hardening/final-polish», ancestro de main. docs/46 conserva el commit de partida c36e5b7, las versiones y las limitaciones. Sobre la discrepancia histórica: el merge que GitHub registra para #4 (f4c6510) tiene el mismo árbol que bd3289f (6c005a96…) y no está en la historia de main (GitHub lo conserva como commit suelto), porque es la versión anterior a la reescritura del historial que retiró las líneas de atribución. No hay dos contenidos distintos.
4 y 5. La suite de regresión (plan de un uso, campaña cerrada terminal, respaldo con rollback, equivalencia de esquema, escenario E2E) y la guarda de setState pasan en esa misma CI.

Límites declarados:
- No hay una comprobación automatizada del propio workflow ni del tag; el issue la excluye.
- docs/46 no anota el SHA del tag (bd3289f, registrado aquí).

Estado propuesto: Done · Evidence Verified · cierre completed.
```

## 4. Comprobaciones nuevas propuestas (ninguna ejecutada)

Son pruebas de host pequeñas, cada una en su archivo nuevo. Sólo cambia el código de producción la corrección de #53. **No se construyen sin la autorización de Roderich**, y no se ejecutan en paralelo varias suites pesadas.

| Tarjeta | Archivo propuesto | Criterio material que cubriría |
|---|---|---|
| #39 | `test/rec_039_schema_constraints_test.dart` | FK activa y una FK inválida rechazada; un CHECK por tabla; segunda campaña `ACTIVE` por inserción directa |
| #40 | `test/rec_040_catalog_archive_rename_test.dart` | Archivar los cuatro catálogos conservando sus operaciones; renombrar en blanco |
| #43 | `test/rec_043_purchase_rules_test.dart` | Rechazos de `confirmPurchase` sin dejar filas; moneda, precio original y tipo de cambio en el ítem y en el lote |
| #44 | `test/rec_008_invoice_viewer_test.dart` | `storeInvoiceImage`; «Ver factura», el diálogo y el aviso de archivo ausente |
| #46 | `test/rec_046_inventory_detail_test.dart` | Cabecera, reparto y lotes con su procedencia y filtros; saldo intacto tras rechazar una aplicación |
| #47 | `test/rec_047_application_rules_test.dart` | Atomicidad multiproducto; cantidad ≤ 0; variación; `estimateFifoCost` |
| #48 | `test/rec_048_transfer_guards_test.dart` | Origen = destino; reversión con el destino ya movido |
| #50 | `test/rec_050_reversal_rules_test.dart` | Doble reversión de una aplicación; cargo y `CREDIT_ADJUSTMENT`; compra consumida sin cambios; motivo; confirmaciones |
| #51 | `test/rec_015_logbook_profile_test.dart` | `farmLogbook` con filtros, `fifo_lots` y reversión; `FarmLogbookScreen`; `PersonDetailScreen` |
| #52 | `test/rec_016_export_coherence_test.dart` | Contenido exportado de costo por producto, costo por chaco y resumen de campaña frente a sus lecturas |
| #53 | dos pruebas descritas el 2026-10-15 y la corrección de una línea en `_neutralize` | `'\tABC'` y `'\rABC'` neutralizados; cancelación en la interfaz; éxito CSV con nombre y carpeta |

## 5. Límites de esta conciliación

- Es una lectura del código y de la evidencia existente. No es una prueba nueva ni una revisión humana.
- La cobertura «material» la juzgan las sesiones por lectura de cada prueba. No se midió cobertura de líneas.
- La evidencia de dispositivo se limita a la de los archivos citados (POCO X5 Pro 5G y HONOR JDY-LX3P). Las 22 filas DEVICE de Roderich1/Agro_Sindicato_Backend-Web#18 (`docs/evidence/F05_SYNC_06.md` del Backend, §3) siguen diferidas y no intervienen.
- La restauración en un teléfono nuevo es el límite con el que se cerró MOB #36 (F08, Done · Partial).

## 6. Decisiones de Roderich y resultados de las comprobaciones (actualización del 2026-10-19)

Esta sección actualiza la matriz única; no hay otro catálogo de REC. Las secciones 0 a 5 se conservan tal como se integraron en `324df1a`, como registro de la conciliación por lectura.

### 6.1 Decisiones del 2026-10-19

Fuente: «Agrocuentas: resolución de REC y autorización del bloque de comprobaciones», bajo la delegación técnica de Roderich. No es una revisión del tutor ni una validación institucional.

- **Lote aplicado:** 10:25:08–10:25:55Z, 34 operaciones, relectura 168/168.
  - #55 y #57: Done · Verified, cerradas.
  - #56: Done · Partial, cerrada.
  - 10 tarjetas: Validation · Partial.
  - #53: Backlog · Partial, con RF-31 retirado.
- **#50, límite académico aceptado (RF-13):** no hay un registro separado del operador que ejecuta cada reversión. No se autoriza una migración ni un sistema de auditoría para resolverlo.
  - El límite no permite afirmar que el titular hizo la reversión por estar el dispositivo vinculado a él, ni completar actores desconocidos.
  - Se conservan el responsable de la operación original, las referencias, la fecha, el motivo y los efectos correctivos.
  - **Interpretación:** RF-13 pide el actor y el ámbito autorizados y la preservación del responsable. Queda **cubierto en parte**: se preserva el responsable de la operación original, pero no se identifica individualmente al ejecutor de la reversión. No se inventa un campo ni una atribución humana.
  - Cubiertos los demás criterios, #50 admite un cierre académico **Done · Partial**, nunca Verified, sin cambiar GATE-F04.
- **#56, límite académico aceptado:**
  - el diálogo «Descartar cambios» no tiene prueba automatizada sobre todos los formularios reales;
  - plan y transferencia no tienen evidencia de ese diálogo;
  - el estudio de usabilidad y la accesibilidad semántica quedan fuera del alcance de la REC y no se presentan como cumplidos.
- **#39 y #52:** límites no aceptados; se autorizaron sus comprobaciones.
- **#53:** RF-31 se retira como atribución directa de los criterios CSV y la brecha se declara en el cuerpo del issue. La exportación es una capacidad derivada de `docs/evolution/features/EVOLUTION-2_TYPED_READS_AND_REPORT_EXPORT_SPEC.md`.
- **Comprobaciones:** las once, autorizadas como pruebas de comportamiento y agrupadas en tres PR.

### 6.2 Entregas

| PR | Rama | HEAD revisado | CI del HEAD | Revisión cruzada | Cambios de `lib/` |
|---|---|---|---|---|---|
| MOB #137 (B) | `test/rec-datos-reglas` | `e3a7ff7` | Flutter CI 39239990432 SUCCESS (antes, 39238552838 sobre `3fa736b`: 1567 passed, 4 skipped; La Paz 78 passed) | LISTO de C sobre `e3a7ff7` | ninguno |
| MOB #138 (C) | `test/rec-interfaz-reportes` | `9c779c4` | Flutter CI 39239353186 SUCCESS | LISTO de B | `farm_logbook_screen.dart` (texto «· Revertida»; defecto 1) |
| MOB #136 (C) | `fix/rec-017-csv-neutralizacion` | `927488e` | Flutter CI 39238051217 SUCCESS | LISTO de B | `csv_report_generator.dart` (`_neutralize`) |

- **Base y autoría:** todos parten de `main` `324df1a`, con autor Roderich1 y sin trailers.
- **Ejecución:** en local sólo los archivos afectados, `dart format` y `flutter analyze`; la suite completa, en el CI de cada PR.
- **Valores esperados:** son literales fijados por la fixture de cada archivo. «Sin cambios» se comprueba con el volcado completo de las tablas (`dumpTables`) y con los saldos.
- **Detalle por caso:** en la descripción de #137, y en `docs/evidence/REC_008_015_016_COMPROBACIONES.md` (#138) y `docs/evidence/REC_017_CSV_NEUTRALIZACION.md` (#136).

### 6.3 Resultado por tarjeta

| Tarjeta | Comprobación nueva (archivo y casos) | Resultado | Defecto | Queda (fuera del literal o límite) | Propuesta |
|---|---|---|---|---|---|
| #39 | `rec_039_schema_constraints_test.dart` sobre el esquema vigente v10 creado desde cero (no la línea base v6): FK activa e inválida rechazada (`:44`); CHECK representativos de las tablas de REC-003 (`:77`); segunda campaña `ACTIVE` por inserción directa (`:216`) | 3/3 PASS | — | Equivalencia desde V1, V2, V4 y V5; restricciones sobre una base migrada; CHECK de seis tablas F04–F06, fuera de REC-003. La escritura fallida a mitad tiene prueba de repositorio con rollback (`repository_test.dart:233`, con una FK inválida dentro de la transacción) | **Done · Verified · cerrar** |
| #40 | `rec_040_catalog_archive_rename_test.dart`: archivado lógico de los cuatro catálogos conservando sus operaciones (`:81`); renombrado en blanco (`:131`) | 2/2 PASS | — | Validación de los diálogos de persona y producto, y persistencia de los catálogos al reabrir la base (hallazgos c y d del 15/10, fuera de los 7 criterios) | **Done · Verified · cerrar** |
| #43 | `rec_043_purchase_rules_test.dart`: rechazos de `confirmPurchase` sin residuos (`:59`); moneda, precio original y tipo de cambio en la línea y en el lote (`:184`). Reutiliza `repository_test.dart:233` para c5 | 2/2 PASS | — | Pruebas de widget de los mensajes del formulario | **Done · Verified · cerrar** |
| #44 | `rec_008_invoice_viewer_test.dart`: `storeInvoiceImage` (bytes, `.jpg` por defecto, original intacto, ruta guardada); «Ver factura», diálogo con `FileImage` y aviso de archivo ausente | 6/6 PASS | — | **La cámara no se ejercita**, ni en el teléfono ni simulando `ImagePicker`; la galería sí, en las series F10 1 y 2. `docs/13_LOCAL_STORAGE.md:181-185` conserva el apartado «sin resolver», que contradice su actualización de `:246-250` | **Done · Partial · cerrar**, con el límite de la cámara (lo acepta Roderich al aprobar) |
| #46 | `rec_046_inventory_detail_test.dart`: cabecera y reparto (`:168`); lotes con su procedencia y filtros (`:182`); saldo intacto tras rechazar una aplicación (`:278`) | 3/3 PASS | — | Pruebas de widget del detalle; visibilidad autorizada en las lecturas. **Observación de §6.4** | **Decisión de Roderich (§6.4)**; mientras tanto, Validation · Partial |
| #47 | `rec_047_application_rules_test.dart`: atomicidad multiproducto (`:88`); cantidad ≤ 0 (`:119`); `variance_quantity_base` (`:139`); `estimateFifoCost` frente al costo real, con los consumos por ítem y el total (`:207`). c1 está en `rec_046…:278` | 4/4 PASS | — | Lectura directa de `APPLICATION_OUT` (hallazgo 7 del 15/10) | **Done · Verified · cerrar** |
| #48 | `rec_048_transfer_guards_test.dart`: origen = destino, multiproducto y por lote (`:84`); reversión con el destino ya movido (`:117`, `:158`) | 3/3 PASS | — | Fecha efectiva de `TRANSFER_OUT/IN`; tipo de cambio de un lote derivado de una compra en USD | **Done · Verified · cerrar** |
| #50 | `rec_050_reversal_rules_test.dart`: cargo conservado, `CREDIT_ADJUSTMENT` con `reversal_of_id` y motivo (`:111`); doble reversión de una aplicación (`:209`); compra consumida sin cambios (`:228`); motivo en compras y transferencias (`:270`); confirmación en `PurchasesScreen` (`:366`) y `TransfersScreen` (`:420`) | 6/6 PASS | — | **Responsable de la reversión: límite aceptado (§6.1)** | **Done · Partial · cerrar** |
| #51 | `rec_015_logbook_profile_test.dart`: `farmLogbook` con sus campos, `fifo_lots`, los filtros, su combinación y la reversión; `FarmLogbookScreen`; `PersonDetailScreen` (superficie, saldo, stock, y cuenta con el cargo conservado y el crédito) | 12/12 PASS con `82d02fc` | **Defecto 1:** la bitácora pintaba una aplicación revertida como hecha. Reproducido sobre `f1519d2` (+11 −1) y corregido sólo en el texto («· Revertida») | El texto «Consumido» del perfil no se afirma. **Observación de §6.4** | **Decisión de Roderich (§6.4)**; mientras tanto, Validation · Partial |
| #52 | `rec_016_export_coherence_test.dart`: CSV completo del costo por producto y por chaco (todas las campañas, C1 y C2) y de los resúmenes de C1 y C2, contra literales de la fixture. Si se quita el filtro de campaña del cableado, fallan los casos filtrados | 8/8 PASS | — | No se extrae el texto del PDF, que sale del mismo `ReportTable` cubierto por `report_composer_test`. Se conserva la corrección del 2026-10-17: el «Verified» de la tabla del 2026-10-15 no respaldaba estos tres casos | **Done · Verified · cerrar** |
| #53 | `report_csv_test.dart`: tres casos nuevos que **fallan sobre `324df1a`** (`'\tABC'`, `'\rABC'`, `' \tABC'`) y una salvaguarda; corrección de `_neutralize` (`c2b9906`). `reports_screen_test.dart`: cancelación sin archivos finales, temporales ni `.parcial`, con la base y los saldos sin cambios; éxito CSV con nombre y carpeta | 27/27 en `report_csv_test`; pantalla en verde en el CI | **Incumplimiento del contrato de neutralización**, corregido. No se demostró la ejecución de ninguna fórmula | `'\nABC'` sale entrecomillada y sin guarda, porque el salto de línea no está en el contrato y ampliarlo sería un cambio de contrato. Requirement refs sin asignar (brecha declarada) | **Done · Verified · cerrar** |

**Recuento de propuestas:**
- **9 cierres:** 7 en Done · Verified (#39, #40, #43, #47, #48, #52, #53) y 2 en Done · Partial (#44, #50);
- **2 tarjetas** siguen en Validation · Partial hasta la decisión de §6.4 (#46, #51).

Ningún cierre se propone por el número de pruebas: cada uno corresponde a criterios literales cubiertos. Todos dependen de que Roderich integre #136, #137 y #138, y de que el CI del `main` resultante pase.

### 6.4 Observación de diseño que decide Roderich: «comprado» y «consumido» brutos

B (#46) y C (#51) la encontraron por separado y tiene una sola raíz: una reversión no borra el movimiento original, sino que añade su compensación (`APPLICATION_REVERSAL`, `PURCHASE_REVERSAL`), y estas lecturas suman los movimientos originales.
- **«Comprado»** (`inventorySummary`, `inventoryProductHeader`) incluye los `PURCHASE_IN` de las compras revertidas.
- **«Consumido»** (esas dos lecturas, `inventoryProductDistribution` y `personStockSummary`) incluye los `APPLICATION_OUT` de las aplicaciones revertidas.
- **«Asignado»** (`inventoryProductDistribution` y `personStockSummary`) cuenta todo movimiento positivo, también `APPLICATION_REVERSAL`.

**Lo que sí es correcto:** el físico, el valor y el costo.

Con la fixture de #51, la cabecera muestra «comprado 8 L − consumido 6 L» junto a «físico 2,5 L», cuando el consumo neto es de 5,5 L: las cifras no cuadran a la vista. Ninguna prueba fija esa semántica con reversiones.

**Opciones:**
- **(a)** aceptar las cifras brutas como semántica documentada: #46 y #51 pasan a Done · Verified;
- **(b)** pedir cifras netas: cambia lecturas que comparten el perfil y el detalle de inventario, así que requiere un diseño concreto antes de implementarlo. Mientras tanto, #46 y #51 siguen en Validation.

No afecta a T1–T6 ni a W1–W5: ninguna tarea del piloto revierte una operación, y T3 pregunta el saldo, no lo consumido.
