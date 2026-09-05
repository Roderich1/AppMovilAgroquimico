# 26 — Deuda técnica

Clasificación por **impacto** (qué se rompe si no se atiende), **riesgo** (probabilidad de
que cause un problema real) y **esfuerzo** (coste de corregirlo).

## Marcadores explícitos en el código

Búsqueda exhaustiva de `TODO`, `FIXME`, `HACK`, `XXX`, `WORKAROUND` en `lib/` y `test/`:

| Marcador | Ubicación | Contenido |
|---|---|---|
| `TODO` | `android/app/build.gradle.kts` | *"Specify your own unique Application ID"* — **ya resuelto**: el `applicationId` es `com.comunidad.agro.agroquimicos`, no el de la plantilla. El comentario quedó obsoleto |
| `TODO` | `android/app/build.gradle.kts` | *"Add your own signing config for the release build"* — **NO resuelto**. Ver [23_SECURITY_AUDIT](23_SECURITY_AUDIT.md) S-01 |
| `@Deprecated` | `agro_repository.dart` | `transferProductFifoV3Legacy` — *"Compatibilidad con transferencias V3."* |
| `@Deprecated` | `agro_repository.dart` | `transferStockLegacy` — *"Use transferProductFifo; kept for source compatibility."* |

**En `lib/` no hay ni un solo `TODO` o `FIXME`.** Es un dato positivo: la deuda de este
proyecto no está anotada, está **implícita en la estructura**, que es lo que documenta el
resto de esta página.

## Código comentado

**No se encontró ningún bloque de código comentado** en `lib/` ni en `test/`. Los únicos
comentarios son los de la plantilla de Flutter en `pubspec.yaml`, `analysis_options.yaml` y
los manifiestos. Otro dato positivo.

---

## Registro de deuda técnica

### DT-01 · Código muerto: ~400 líneas

| | |
|---|---|
| **Impacto** | Medio — infla archivos, engaña sobre la complejidad real, confunde a quien llega |
| **Riesgo** | Bajo — no se ejecuta |
| **Esfuerzo** | **Bajo** — es borrar |

| Elemento | Ubicación | Líneas |
|---|---|---:|
| `_PurchaseDialog` + `_PurchaseDialogState` + `_AllocationInput` + `_select` | `purchases_screen.dart` | ~350 |
| `transferProductFifoV3Legacy` | `agro_repository.dart` | ~110 |
| `transferStockLegacy` | `agro_repository.dart` | ~73 |
| `_farmOwner` | `application_form_screen.dart` | 4 |
| Parámetro `people` sin usar en `_confirm` | `purchase_form_screen.dart` | 1 |

`_PurchaseDialog` es un diálogo de compra **mono-producto** que quedó sustituido por
`PurchaseFormScreen` (multiproducto). Conserva incluso valores de prueba hardcodeados:
`TextEditingController(text: '420')`, `'16'`, `'7'` — que son exactamente los del caso de
test de `money_test.dart`. Es un residuo de una versión anterior.

**Advertencia antes de borrar los métodos `@Deprecated`**: aunque no tengan llamadas hoy,
puede haber intención de conservarlos. Ver la nota de comprobación en
[29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md).

---

### DT-02 · Divergencia entre `_createSchema` y `_upgradeSchema`

| | |
|---|---|
| **Impacto** | **Alto** — dos poblaciones de usuarios con esquemas distintos |
| **Riesgo** | **Medio-alto** — silencioso hasta que causa datos duplicados |
| **Esfuerzo** | Bajo (corregir) / Medio (reparar bases ya migradas) |

Tres divergencias confirmadas:

| Elemento | `_createSchema` | `_upgradeSchema` |
|---|---|---|
| `idx_application_item_unique` | `CREATE UNIQUE INDEX` | `CREATE INDEX` (v4) |
| `idx_plan_item_unique` | `CREATE UNIQUE INDEX` | `CREATE INDEX` (v4) |
| Tabla `app_settings` | Se crea | **No se crea en ninguna migración** |

Una instalación nueva tiene la garantía de unicidad a nivel de motor; una **migrada**
depende únicamente de la validación en Dart (RN-18, RN-23). Si alguna vez se abre una vía
que salte esa validación, las instalaciones migradas aceptarán duplicados.

La corrección no es solo cambiar el `CREATE INDEX`: hay que añadir un paso de migración a
v5 que elimine y recree los índices, tras verificar que no existan ya filas duplicadas.

---

### DT-03 · Ausencia de tipos en la capa de lectura

| | |
|---|---|
| **Impacto** | **Alto** — es el techo de mantenibilidad del proyecto |
| **Riesgo** | Medio — cada refactorización de SQL puede romper una pantalla sin aviso |
| **Esfuerzo** | **Alto** — ~20 clases de lectura |

Detalle completo en [24_CODE_QUALITY_AUDIT](24_CODE_QUALITY_AUDIT.md) Q-01.

Es deuda **acumulativa**: cuanto más código se escriba sobre `Map<String, Object?>`, más
caro será salir. Pero también es **divisible**: puede abordarse consulta a consulta.

---

### DT-04 · Repositorio monolítico

| | |
|---|---|
| **Impacto** | **Alto** — cuello de botella para cualquier trabajo en paralelo |
| **Riesgo** | Medio |
| **Esfuerzo** | **Alto** |

1 862 líneas, seis responsabilidades. Ver [24](24_CODE_QUALITY_AUDIT.md) Q-02.

**Atenuante**: las responsabilidades ya están **agrupadas físicamente** en el archivo, lo
que hace la división mecánicamente sencilla. Y los 44 tests cubren bien los tres motores
críticos.

---

### DT-05 · Lógica FIFO duplicada en cuatro lugares

| | |
|---|---|
| **Impacto** | **Alto** — un cambio de política de costeo exige cuatro ediciones coherentes |
| **Riesgo** | **Medio-alto** — es exactamente el tipo de duplicación que produce divergencias |
| **Esfuerzo** | Medio |

`confirmApplication`, `transferProductsFifo`, `transferProductFifoV3Legacy` (muerto) y
`estimateFifoCost` implementan el mismo algoritmo, y los tres primeros repiten además la
misma consulta SQL con variaciones cosméticas (`JOIN` vs `LEFT JOIN`).

**Ya hay evidencia de divergencia**: `confirmApplication` usa `JOIN inventory_movements`
mientras `transferProductsFifo` usa `LEFT JOIN`. Con el `HAVING available > 0` el resultado
coincide, pero es señal de que las copias ya empezaron a separarse.

---

### DT-06 · Herencia de la versión mono-producto en `transfers`

| | |
|---|---|
| **Impacto** | Medio — dato incorrecto disponible para quien no conozca la historia |
| **Riesgo** | Medio — una consulta nueva que use `transfers.product_id` dará un resultado erróneo |
| **Esfuerzo** | Medio — requiere migración de datos |

`transfers.product_id` y `transfers.quantity_base` se rellenan con `validItems.first`, por
lo que en una transferencia multiproducto describen solo el primero. `transfer_items` (v4)
tiene el dato correcto, y `transfers()` lo prefiere con un `COALESCE`, pero la columna
engañosa sigue ahí y **es `NOT NULL`**, así que no se puede simplemente dejar de rellenar.

---

### DT-07 · Estados y columnas fantasma

| | |
|---|---|
| **Impacto** | Bajo — confunde el modelo mental |
| **Riesgo** | Bajo |
| **Esfuerzo** | **Bajo** |

| Elemento | Situación |
|---|---|
| `campaigns.status = 'ARCHIVED'` | Se **comprueba** en `activateCampaign` (RN-12) pero **ninguna ruta lo escribe** |
| `application_plans.status = 'DRAFT'` | Es el `DEFAULT` de la columna y se consulta en `WHERE status IN ('DRAFT','PLANNED')`, pero `addPlanMulti` siempre inserta `'PLANNED'` |
| `purchase_items.price_major_unit` | `NOT NULL DEFAULT 1000`; nunca escrita ni leída |
| `application_items.notes` | Añadida en v4; nunca usada |
| `application_items.fifo_estimated_cost_bob_minor` | Siempre igual a `cost_bob_minor`: se escriben con el mismo valor en el mismo `UPDATE` |
| Tabla `app_settings` | Nunca usada; ni siquiera se crea al migrar |
| `persons.phone` | Existe en el esquema y en `addPerson`; la UI nunca la rellena |
| `farms.location` | Idem |
| `purchases.notes`, `purchases.exchange_rate_note` | Existen en `PurchaseDraft`; la UI nunca las rellena |
| `application_plans.planned_date` | Existe; la UI nunca la rellena |
| `purchase_allocations.notes` | Nunca usada |

Ninguno hace daño. En conjunto, dan una impresión de esquema más rico de lo que realmente se
usa, lo que puede llevar a un desarrollador nuevo a suposiciones erróneas.

---

### DT-08 · Funcionalidades parcialmente implementadas

| Funcionalidad | Estado real |
|---|---|
| **Filtros de la bitácora de chaco** | `farmLogbook` acepta `campaignId` y `productId`; `FarmLogbookScreen` **nunca los pasa**. La capacidad existe en datos, no en UI |
| **Fecha de operación** | `confirmPurchase`, `confirmApplication` y `transferProductsFifo` aceptan fecha; las tres pantallas envían siempre `DateTime.now()`. **No se puede registrar una operación con fecha pasada** |
| **`ExchangeRateSource`** | El enum tiene 4 valores; la UI **siempre** envía `agreedWithSupplier` |
| **`method` de pago a proveedor** | Columna `NOT NULL`; la UI **siempre** envía `'TRANSFER'` |
| **`SettlementPolicy` personalizada** | `addPerson` acepta `policy`; la UI nunca la pasa |
| **Plataforma web** | Carpeta presente; la app **no funciona** en navegador |
| **`archiveCatalog` para campañas** | Implementado, pero **inalcanzable**: la pestaña de campañas dirige al menú de `_campaignAction`, que nunca llama a `_archive` |
| **Restauración de backup** | Solo existe exportación |

El caso de la **fecha** es el de mayor impacto funcional: registrar una compra de la semana
pasada exige hacerlo el mismo día, o aceptar una fecha incorrecta que afectará al orden FIFO.

---

### DT-09 · Documentación desactualizada

| | |
|---|---|
| **Impacto** | Medio — induce a error a quien llega |
| **Riesgo** | Bajo |
| **Esfuerzo** | **Trivial** |

| Afirmación | Realidad |
|---|---|
| `README.md`: *"La versión de esquema SQLite es 2"* | Es **4** (`app_database.dart`) |
| `README.md`: *"La migración desde V1 agrega área tratada, dosis y necesidad teórica"* | Describe solo v1→v2; hay dos tramos más |
| `README.md`: *"offline-first"* | Es **offline-only**: no hay servidor con el que sincronizar |
| `pubspec.yaml`: `description: "A new Flutter project."` | Texto de plantilla sin personalizar |
| `build.gradle.kts`: TODO del `applicationId` | Ya resuelto |
| `AndroidManifest.xml`: `android:label="agroquimicos"` | La app se llama "Agrocuentas" en su título |

---

### DT-10 · Naming inconsistente entre plataformas

| | |
|---|---|
| **Impacto** | Bajo (pero visible para el usuario final) |
| **Riesgo** | Bajo |
| **Esfuerzo** | **Trivial** |

| Ubicación | Nombre |
|---|---|
| `MaterialApp.title` | `Agrocuentas` |
| `README.md` | `Agrocuentas V2` |
| Android `android:label` | `agroquimicos` (minúscula) |
| iOS `CFBundleDisplayName` | `Agroquimicos` |
| iOS `CFBundleName` | `agroquimicos` |
| Paquete Dart | `agroquimicos` |

El usuario ve **"agroquimicos"** bajo el icono en Android y **"Agroquimicos"** en iOS, pero
**"Agrocuentas"** dentro de la app.

---

### DT-11 · Sin infraestructura de observabilidad

| | |
|---|---|
| **Impacto** | **Alto** para el mantenimiento a largo plazo |
| **Riesgo** | Medio |
| **Esfuerzo** | Bajo (logging) / Medio (crash reporting) |

Cero sentencias de logging en 8 250 líneas. Sin `FlutterError.onError`, sin
`runZonedGuarded`, sin crash reporting.

**Consecuencia práctica**: si un usuario reporta *"me dio error al guardar una compra"*, no
hay **absolutamente ninguna** información que consultar. El diagnóstico depende por completo
de reproducir el problema.

**Tensión a resolver**: el crash reporting requiere el permiso `INTERNET`, lo que
contradice la postura offline actual (que es una fortaleza de seguridad). Un **log local
rotativo** dentro del directorio de la app, exportable junto con el backup, evita esa
contradicción y resuelve el 80 % del problema.

---

### DT-12 · Duplicación de formateo y etiquetas

| | |
|---|---|
| **Impacto** | Bajo |
| **Riesgo** | Bajo |
| **Esfuerzo** | **Trivial** |

- Traducción de rol (`'FAMILY' → 'Familiar'`): **4 implementaciones** en pantallas distintas.
- `(x as int) / 10000` para hectáreas: **8 ocurrencias** sin helper, con salida inconsistente
  (`28.0 ha`, `2.8000000000000003 ha`).
- Diálogo "¿Descartar cambios?": 4 copias casi idénticas.
- Bloque `PopScope` + `dirty`/`saving` + `addPostFrameCallback`: 4 copias.

Llamativo porque `money.dart` **ya es** la capa de formateo centralizada, y simplemente no
se le añadieron `formatHectares` ni `roleLabel`.

---

## Deuda arquitectónica con fecha de caducidad

### DT-13 · Identificadores locales autoincrementales

| | |
|---|---|
| **Impacto** | **Muy alto** *si* alguna vez se quiere multi-dispositivo |
| **Riesgo** | Nulo hoy; total en ese escenario |
| **Esfuerzo** | **Muy alto** si se pospone |

Todas las PK son `INTEGER AUTOINCREMENT`. Dos instalaciones generan el id `1` para entidades
distintas, lo que hace **imposible fusionar bases** sin rediseño.

Es la deuda más importante de este documento en términos estratégicos: su coste **crece con
cada dato que se acumula**. Si multi-dispositivo está en el horizonte, la migración a UUID
debe planificarse pronto. Si no lo está, esta deuda **no existe** y no hay que actuar.

`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ¿es multi-dispositivo un objetivo del producto?

---

## Resumen priorizado

| ID | Deuda | Impacto | Riesgo | Esfuerzo | Actuar |
|---|---|:--:|:--:|:--:|:--:|
| DT-02 | Divergencia de esquema entre creación y migración | Alto | Alto | Bajo | **Ya** |
| DT-11 | Sin observabilidad | Alto | Medio | Bajo | **Ya** |
| DT-09 | Documentación desactualizada | Medio | Bajo | Trivial | **Ya** |
| DT-05 | FIFO duplicado ×4 | Alto | Medio-alto | Medio | Pronto |
| DT-01 | ~400 líneas de código muerto | Medio | Bajo | Bajo | Pronto |
| DT-08 | Fecha de operación no editable | Medio | Bajo | Bajo | Pronto |
| DT-12 | Duplicación de formateo | Bajo | Bajo | Trivial | Pronto |
| DT-10 | Naming inconsistente | Bajo | Bajo | Trivial | Pronto |
| DT-07 | Estados y columnas fantasma | Bajo | Bajo | Bajo | Cuando toque |
| DT-03 | Sin tipos en lectura | Alto | Medio | Alto | Planificar |
| DT-04 | Repositorio monolítico | Alto | Medio | Alto | Planificar |
| DT-06 | Desnormalización en `transfers` | Medio | Medio | Medio | Planificar |
| DT-13 | Ids locales | Muy alto* | Nulo hoy | Muy alto | **Decidir** |

\* Solo si multi-dispositivo entra en el alcance del producto.
