# 42 — Plan de corrección de los UIBUG

Plan de implementación por **lotes agrupados por causa raíz**, no por síntoma.
Fuente de verdad de los hallazgos: [41_UIBUG_MASTER_BACKLOG.md](41_UIBUG_MASTER_BACKLOG.md).

Fecha: **2026-09-05** · Rama base: `hardening/stabilization` (`81c919f`)

> **Este plan no se ha ejecutado.** Ningún archivo de `lib/` fue modificado al redactarlo.
> Los 66 hallazgos están en `OPEN`.

---

## 1. Principio de agrupación

**No hay 66 cambios independientes.** 16 grupos de causa raíz (§6 de `41`) cubren los 66
hallazgos, y varios grupos comparten archivo. Los lotes de abajo se diseñaron para que:

- cada lote tenga **una causa raíz dominante** y un diff acotado;
- cada lote sea **verificable por separado** (tests que fallan antes y pasan después);
- el orden respete las **dependencias reales**, no la numeración;
- ningún lote mezcle un cambio de riesgo alto con uno cosmético.

**Regla transversal de la fase**: cada lote empieza escribiendo el test que **falla**
reproduciendo el defecto, y solo entonces se toca `lib/`. Es el mismo método que la fase de
estabilización aplicó a STAB-001 y STAB-002.

### Antes de empezar cualquier lote

Tres decisiones de producto bloquean los lotes A, C, D y H. **Deben tomarse primero**
(§10 de `41`):

| Decisión | Bloquea |
|---|---|
| Formato de entrada numérica aceptado | **BATCH A** |
| Dónde entra `/compras`; qué hacen las tarjetas de Operaciones | **BATCH C**, BATCH J |
| Política de Atrás desde destino raíz (004B) | **BATCH D** |
| Vocabulario de saldos | **BATCH H** |
| ¿Un plan se puede aplicar dos veces? | BATCH I (parte 045) |

## 2. Resumen de lotes

| Lote | Tema | UIBUG | Nº | Prio | Riesgo de regresión |
|---|---|---|---:|---|---|
| **A** | Parseo y formato numérico | 003, 034, 065 | 3 | **P0-A** | **ALTO** |
| **B** | Backup en Android | 001, 049 | 2 | **P0-A** | BAJO |
| **C** | Acceso a compras | 002, 011 | 2 | **P0-B** | MEDIO |
| **D** | Pila de navegación y retorno | 004A, 004B, 062 | 3 | **P0-B** | **ALTO** |
| **E** | Diálogo de pago | 005, 012, 014 | 3 | **P0-B** | MEDIO |
| **F** | Formato y localización de salida | 016, 024, 025, 026, 027, 056 | 6 | P1-A | MEDIO |
| **G** | Consistencia de reversiones | 010, 045 | 2 | P1-A | MEDIO |
| **H** | Semántica de saldos | 013, 028, 058 | 3 | P1-A | MEDIO |
| **I** | Búsqueda | 007, 019, 052, 053 | 4 | P1-A/P2 | BAJO |
| **J** | Mensajes de error y navegación menor | 015, 050, 051 | 3 | P1-B | BAJO |
| **K** | Selector de entidad | 006, 035, 036, 054, 061 | 5 | P2 | BAJO |
| **L** | FAB, insets y alturas fijas | 008, 009, 018, 030, 055, 064 | 6 | P2 | MEDIO |
| **M** | Ajuste de texto y accesibilidad | 017, 020, 021, 063 | 4 | P2 | BAJO |
| **N** | UX de formularios | 031, 032, 033, 037, 038, 039, 040, 041, 042, 043, 044, 046, 060 | 13 | P2/P3 | BAJO |
| **O** | Afordancias de listas y pulido | 022, 023, 029, 047, 048, 057, 059 | 7 | P3 | BAJO |
| | | **Total** | **66** | | |

Orden de ejecución: **A → B → C → D → E → F → G → H → I → J → K → L → M → N → O**.

Los lotes **K–O** son independientes entre sí y pueden paralelizarse una vez cerrados A–J.

---

## 3. Lotes

### BATCH A · Parseo y formato numérico

- **UIBUG** 003 (CRITICAL), 034, 065
- **Causa raíz** `NUMERIC_INPUT`. `tryParseDecimal` (`common.dart:131`) normaliza `,` → `.` y
  trata el punto como decimal, mientras `formatBob`/`formatQuantity` (`money.dart:35,41`)
  imprimen con convenio es-BO, donde el punto es separador de miles. **Entrada y salida usan
  convenciones opuestas.**
- **Bloqueado por** decisión de formato de entrada (§1).
- **Archivos esperados**
  `lib/presentation/widgets/common.dart` · `lib/domain/money.dart` ·
  `lib/presentation/screens/transfer_form_screen.dart` ·
  `lib/presentation/screens/settlements_screen.dart` · los otros 3 formularios (formatters)
- **Tests ANTES del fix** (deben **fallar**)
  - `tryParseDecimal('1.500')` → se espera `1500`, hoy da `1.5`
  - `tryParseDecimal('15.000')` → `15000`, hoy `15.0`
  - ida y vuelta: `tryParseDecimal(formatQuantity(15000000,'KG').split(' ').first) == 15000`
  - widget: teclear `1.500` en el diálogo de pago registra `150000` minor, no `150`
  - widget: en `/transferencias/nueva` escribir `5` en un campo recién enfocado da `5`, no `05`
  - widget: teclear `abc` en el pago produce "no se pudo interpretar", no "mayor a cero"
- **Tests DESPUÉS** los anteriores en verde + tabla de casos límite del dataset
  (`0,125`, `99999,750`, `9999999,99`, vacío, `-1`, `1.500.000`) + **la suite completa (91)
  sigue verde**.
- **Riesgo de regresión ALTO** — `tryParseDecimal` lo usan **los 4 formularios y el diálogo de
  pago**. Un cambio mal calibrado convierte un error de ÷1000 en uno de ×1000. Mitigación:
  tests de tabla antes de tocar nada, y no fusionar sin verificación en Pixel 8.
- **Dependencias** ninguna previa. **Bloquea** la parte numérica de E.
- **Prueba manual Pixel 8**
  1. Transferencia: origen con "15.000 KG disponibles", teclear `15.000` → el resumen debe
     decir 15.000 KG.
  2. Pago: teclear `1.500` → registrar → **leer `account_transactions` en el dispositivo** y
     comprobar `-150000`.
  3. Teclear `abc` → mensaje correcto.
- **Criterio de terminado** los 3 UIBUG verificados en dispositivo; ningún campo numérico de la
  app acepta una cadena cuya interpretación difiera de lo que la app imprimiría.

### BATCH B · Backup en Android

- **UIBUG** 001 (CRITICAL), 049
- **Causa raíz** `BACKUP_ANDROID`. `backup_service.dart:63` usa `execute()` para
  `PRAGMA wal_checkpoint(FULL)`; en Android `execute` → `SQLiteDatabase.execSQL`, que rechaza
  sentencias que devuelven filas. **La suite no lo detecta porque corre sobre `sqflite_common_ffi`.**
- **Archivos esperados** `lib/data/backup_service.dart` · `test/backup_service_test.dart` ·
  `lib/presentation/screens/settlements_screen.dart` (iconos, 049)
- **Tests ANTES** test que ejercite `export()` contra un doble que **imite la semántica de
  Android** (lanzar en `execute` de una sentencia que devuelve filas) — debe fallar hoy.
- **Tests DESPUÉS** el anterior en verde + ida y vuelta exportar → restaurar → los datos
  coinciden + test de que el checkpoint no rompe si el modo WAL no está activo.
- **Riesgo de regresión BAJO** — un archivo, una línea de comportamiento. Cuidado con no
  degradar la garantía de consistencia del checkpoint.
- **Dependencias** ninguna. **Relacionado** el mensaje crudo que hoy se ve es 015 (BATCH J):
  conviene verificar B **después** de J, o comprobar ambos en la misma sesión de dispositivo.
- **Prueba manual Pixel 8** exportar → **comprobar el archivo en Descargas con `adb`** →
  restaurar → verificar que la contabilidad vuelve. Repetir tras reinstalar la app.
- **Criterio de terminado** un backup exportado en Pixel 8 se restaura con éxito en el mismo
  dispositivo y los saldos coinciden con los previos.

### BATCH C · Acceso a compras

- **UIBUG** 002 (CRITICAL), 011
- **Causa raíz** `NAVIGATION_STACK`. `/compras` está declarada (`app.dart:62`) y ninguna de las
  16 llamadas de navegación de `lib/` apunta a ella. 011 depende de esto: la solución natural a
  "confirmar una compra no da acuse" es volver al listado, que hoy no existe.
- **Bloqueado por** decisión de ubicación de la entrada.
- **Archivos esperados** `lib/presentation/screens/operations_screen.dart` ·
  `lib/presentation/app_shell.dart` · `lib/app.dart` (si se añade destino raíz) ·
  `lib/presentation/screens/purchase_form_screen.dart`
- **Tests ANTES**
  - test que **enumere las rutas declaradas** y falle si alguna no tiene origen en `lib/`
    (guardia permanente contra este defecto)
  - test de navegación: llegar a `/compras` desde la interfaz — falla hoy
  - test: confirmar una compra muestra acuse — falla hoy
- **Tests DESPUÉS** los anteriores en verde + **auditar UI-06 por primera vez** (pendiente
  desde `37`).
- **Riesgo de regresión MEDIO** — si se añade un destino raíz cambia `selectedIndex`
  (`app_shell.dart:25-41`) y con él el resaltado de toda la barra. Cubrir con el test unitario
  de `selectedIndex` para las 17 rutas (que también cierra 062, BATCH D).
- **Dependencias** conviene hacerlo **antes** de D, para que D rediseñe la pila con el mapa de
  navegación ya completo.
- **Prueba manual Pixel 8** llegar a `/compras`; registrar un pago a proveedor; **ver la foto
  de factura** (nunca se ha probado); revertir una compra. Auditar la pantalla entera.
- **Criterio de terminado** `/compras` alcanzable, sus 3 diálogos auditados, y el test de
  "ninguna ruta huérfana" en la suite.

### BATCH D · Pila de navegación y retorno

- **UIBUG** 004A (CRITICAL), 004B, 062
- **Causa raíz** `NAVIGATION_STACK`. Dos causas que se suman: (a) `context.go` en toda la
  navegación jerárquica (5 sitios) reemplaza la pila; (b) `PageFrame` (`common.dart:5`) no
  tiene `AppBar` ni flecha de volver.
- **Bloqueado por** decisión 004B (§1): la política de raíz determina cómo se estructura el shell.
- **Archivos esperados** `lib/presentation/app_shell.dart` · `lib/app.dart` ·
  `lib/presentation/widgets/common.dart` (`PageFrame`) · `persons_screen.dart` ·
  `inventory_screen.dart` · `person_detail_screen.dart` · `dashboard_screen.dart` ·
  `operations_screen.dart`
- **Tests ANTES**
  - por cada ruta jerárquica (`/personas/:id`, `/inventario/:id`, `/chacos/:id` y las 4
    subrutas de Operaciones): entrar → `pop` → se vuelve al origen y la pantalla es utilizable
  - `PageFrame` muestra flecha de volver cuando `Navigator.canPop()` — falla hoy
  - `selectedIndex` para las 17 rutas, incluida `/chacos/:id` (062) — falla hoy
- **Tests DESPUÉS** los anteriores en verde + **el test de STAB-001 sigue verde** (la
  navegación al formulario de compra no debe romperse).
- **Riesgo de regresión ALTO** — es el cambio más transversal del plan. Toca el shell, el
  router y 5 pantallas. Un `push` mal puesto apila pestañas indefinidamente; un `go` mal puesto
  reintroduce 004A. Mitigación: hacerlo **solo** en este lote, con los tests de navegación
  escritos primero, y sin mezclar cambios visuales.
- **Dependencias** después de C. **Cierra parcialmente** 011, 051 y 047 (el mapa queda definido).
- **Prueba manual Pixel 8** Atrás **físico y por gesto** en: los 3 detalles, las 4 subrutas de
  Operaciones, los 5 destinos raíz y los 4 formularios. Comprobar además que la barra inferior
  resalta el destino correcto en `/chacos/:id`.
- **Criterio de terminado** ninguna pantalla es un callejón sin salida; la política de Atrás en
  raíz es la decidida y está documentada en `08_NAVIGATION.md`.

### BATCH E · Diálogo de pago

- **UIBUG** 005 (HIGH), 012, 014
- **Causa raíz** `PAYMENT_FLOW`. `settlements_screen.dart:67-98`: `_record` crea un
  `TextEditingController` local y lo libera (línea 98) mientras el diálogo aún se anima al
  cerrarse. El mismo diálogo carece de contexto (012) y de acuse (014).
- **Archivos esperados** `lib/presentation/screens/settlements_screen.dart` (un solo archivo)
- **Tests ANTES**
  - abrir y cerrar el diálogo de pago **20 veces** sin excepción — falla hoy en debug
    (patrón ya existente en `regression_widget_test.dart` para el estado de cuenta)
  - el diálogo muestra nombre, campaña y saldo de la persona correcta — falla hoy
  - tras registrar aparece un snackbar con el importe — falla hoy
- **Tests DESPUÉS** los anteriores en verde + test de que el pago se registra **una sola vez**.
- **Riesgo de regresión MEDIO** — reescribir el diálogo como `StatefulWidget` es acotado, pero
  toca la escritura contable. El patrón correcto ya existe en el repositorio
  (`_PaymentDialog` de `purchases_screen.dart`, diálogos de `catalogs_screen.dart`): **copiarlo,
  no inventar**.
- **Dependencias** **después de A** — el diálogo es donde 003 hace más daño (sin confirmación
  ni acuse), y 065 se cierra aquí junto con A.
- **Prueba manual Pixel 8** en **debug** (donde se manifiesta 005) y en **profile**: registrar
  un pago válido, uno vacío y uno con texto. Verificar la fila en la base del dispositivo.
- **Criterio de terminado** ninguna pantalla roja; el diálogo identifica a la persona; hay
  acuse; el importe guardado coincide con el tecleado.

### BATCH F · Formato y localización de salida

- **UIBUG** 016, 024, 025, 026, 027, 056
- **Causa raíz** `FORMAT_LOCALIZATION`. Cuatro focos verificados: `/10000` crudo en 8 sitios;
  `GROUP_CONCAT` con `quantity_base/1000.0` en `agro_repository.dart:1070,1072,1191`;
  `COALESCE(..., t.type) concept` en `:1559`; fechas ISO por `substring(0,10)` en 3 sitios;
  patrón `#,##0.###` en `money.dart:43`.
- **Archivos esperados** `lib/domain/money.dart` (helpers nuevos) ·
  `lib/data/agro_repository.dart` · `farm_logbook_screen.dart` · `persons_screen.dart` ·
  `catalogs_screen.dart` · `application_form_screen.dart` · `settlements_screen.dart` ·
  `person_detail_screen.dart` · `applications_screen.dart` · `transfers_screen.dart` ·
  `purchase_form_screen.dart`
- **Tests ANTES** unitarios de `formatHectares`, `formatDate` y del helper de etiquetas de
  dominio (no existen); widget tests que comprueben que ninguna pantalla pinta `80.0 ha`,
  `25.0 KG`, `2026-01-25`, `PAYMENT`, `PLANNED` ni `600000`.
- **Tests DESPUÉS** los anteriores en verde + **revisar los tests existentes que dependan del
  patrón `#,##0.###`** antes de cambiarlo (056).
- **Riesgo de regresión MEDIO** — 056 toca `formatQuantity`, usado en toda la app y en varios
  tests. Hacer 056 **al final del lote**, en un commit propio.
- **Dependencias** después de A (mismo dominio conceptual: no cambiar formato de salida antes
  de haber fijado el de entrada, o se persigue un blanco móvil). **Provee helpers** a I, N y O.
- **Prueba manual Pixel 8** recorrer las 8 pantallas afectadas y comprobar que **ningún número
  ni fecha ni literal de esquema** aparece en formato crudo.
- **Criterio de terminado** un único convenio es-BO en toda la interfaz; ningún literal del
  esquema visible.

### BATCH G · Consistencia de reversiones

- **UIBUG** 010, 045
- **Causa raíz** `REVERSAL_CONSISTENCY`. El estado `REVERSED` solo se usa en
  `applications_screen.dart:190` para **ocultar** el botón ↩; no se etiqueta en ninguna vista, y
  el dashboard pinta el importe de una operación anulada que el reporte sí excluye
  (`agro_repository.dart:1567`, `a.reversed_at IS NULL`). Para 045 **no existe estado de plan**.
- **Bloqueado por** decisión sobre reaplicación de planes (045).
- **Archivos esperados** `applications_screen.dart` · `dashboard_screen.dart` ·
  `planning_screen.dart` · `lib/data/agro_repository.dart` · posiblemente
  `lib/data/app_database.dart` (**migración v6**, solo si 045 exige estado persistido)
- **Tests ANTES** la fila revertida muestra "Revertida" en Aplicaciones y en Inicio — falla hoy;
  el total del inicio y el del reporte **no se contradicen** — falla hoy; un plan ya aplicado
  no ofrece Aplicar sin advertencia — falla hoy.
- **Tests DESPUÉS** los anteriores + si hay migración: **equivalencia de esquema v5→v6**
  (reutilizar `schema_equivalence_test.dart`, que ya cubre este patrón) y migración no
  destructiva.
- **Riesgo de regresión MEDIO**, **ALTO si se añade migración**. Si 045 exige esquema, hacerlo
  en un lote propio (**G2**) separado de 010, con el mismo rigor que STAB-002.
- **Dependencias** después de F (usa el helper de etiquetas para "Revertida").
- **Prueba manual Pixel 8** con el dataset, comprobar la aplicación revertida en las tres
  vistas; intentar reaplicar un plan.
- **Criterio de terminado** una operación revertida se ve igual en todas las vistas y ninguna
  cifra se contradice entre pantalla y reporte.

### BATCH H · Semántica de saldos

- **UIBUG** 013, 028, 058
- **Causa raíz** `BALANCE_SEMANTICS`. Tres consultas con alcances distintos —
  `settlements(campaignId:)` (campaña), `profile['balance']` (histórico),
  `detailedStatement` + acumulado (campaña con arrastre) — y ninguna declara su alcance.
- **Bloqueado por** decisión de vocabulario (§1). **Sin glosario, cualquier renombrado es una
  opinión.**
- **Archivos esperados** `lib/data/agro_repository.dart` (`settlements`, `topSettlements`,
  `statement`, `detailedStatement`) · `settlements_screen.dart` · `person_detail_screen.dart` ·
  `docs/15_BUSINESS_RULES.md` (glosario)
- **Tests ANTES** test de repositorio que **fije el valor esperado de cada consulta** para el
  dataset de `36` y documente por qué difieren (hoy no existe); test de que ambas vistas del
  estado de cuenta dan el mismo acumulado (028) — falla hoy.
- **Tests DESPUÉS** los anteriores + widget tests de las etiquetas nuevas.
- **Riesgo de regresión MEDIO** — no se cambian los cálculos, solo su presentación y
  posiblemente su unificación. **No alterar ninguna fórmula en este lote.**
- **Dependencias** después de F (usa `formatDate` y el helper de etiquetas).
- **Prueba manual Pixel 8** el recorrido exacto de UIBUG-013 con José Luis Ñáñez Álvarez:
  las tres cifras deben ser explicables leyendo solo la pantalla.
- **Criterio de terminado** un usuario puede explicar, sin ayuda, por qué dos pantallas
  muestran cifras distintas para la misma persona.

### BATCH I · Búsqueda

- **UIBUG** 007 (HIGH), 019 (HIGH), 052, 053
- **Causa raíz** `SEARCH`. `toLowerCase().contains` sin normalizar diacríticos en 6 sitios +
  el selector; y `dashboard_screen.dart:38,73` filtra en cliente sobre `inventorySummary(limit: 5)`.
- **Archivos esperados** `lib/presentation/widgets/common.dart` (helper `normalizeForSearch`) ·
  `dashboard_screen.dart` · `applications_screen.dart` · `catalogs_screen.dart` ·
  `inventory_screen.dart` · `settlements_screen.dart` · `transfer_form_screen.dart` ·
  `adaptive_entity_picker.dart` · `persons_screen.dart` · `transfers_screen.dart` ·
  `lib/data/agro_repository.dart` (búsqueda en servidor para 007)
- **Tests ANTES** buscar `glifo` en Inicio devuelve 2 filas — falla hoy; buscar `zzz` dice "sin
  coincidencias" y no "sin inventario" — falla hoy; buscar `maria` encuentra `María` — falla hoy.
- **Tests DESPUÉS** los anteriores + unitarios del helper (`áéíóúñ`, mayúsculas, cadena vacía).
- **Riesgo de regresión BAJO** — helper puro y aditivo; el cambio de 007 a búsqueda en servidor
  es el único con efecto en consultas.
- **Dependencias** después de F. 052 y 053 son aditivos y pueden ir al final.
- **Prueba manual Pixel 8** buscar `glifo`, `maria`, `anez` en todos los buscadores y selectores.
- **Criterio de terminado** ninguna búsqueda de la app distingue tildes ni miente sobre la
  existencia de datos.

### BATCH J · Mensajes de error y navegación menor

- **UIBUG** 015 (HIGH), 050, 051
- **Causa raíz** `ERROR_MESSAGING` + resto de `NAVIGATION_STACK`. `friendlyError`
  (`common.dart:150`) solo cubre `FormatException` y `StateError`; el aviso "sin backups" se
  pinta con `showError`; las tarjetas de Operaciones mezclan `push` y `go` bajo etiquetas del
  mismo estilo.
- **Archivos esperados** `lib/presentation/widgets/common.dart` ·
  `settlements_screen.dart` · `operations_screen.dart` · `app_shell.dart`
- **Tests ANTES** `friendlyError(DatabaseException)` devuelve español — falla hoy; sin backups
  se muestra aviso informativo, no error — falla hoy; test de navegación por cada tarjeta de
  Operaciones.
- **Tests DESPUÉS** los anteriores + un caso por defecto que nunca devuelva `error.toString()` crudo.
- **Riesgo de regresión BAJO**. Cuidado: `friendlyError` se usa en todas las pantallas; no
  ocultar información útil de diagnóstico (el log local de STAB-009 debe seguir registrando el
  error técnico completo).
- **Dependencias** después de D (051 necesita el mapa de navegación decidido). Verificar
  **junto con B**: 015 es lo que hace visible el fallo de 001.
- **Prueba manual Pixel 8** provocar un error real de base; restaurar sin backups; pulsar las
  cinco tarjetas de Operaciones.
- **Criterio de terminado** ningún texto en inglés técnico llega al usuario; los avisos no se
  pintan como errores.

### BATCH K · Selector de entidad

- **UIBUG** 006 (HIGH), 035, 036, 054, 061
- **Causa raíz** `ENTITY_PICKER`. Un solo archivo, `adaptive_entity_picker.dart`:
  `isEmpty: selected == null` (línea 78) impide que la etiqueta flote y la deja donde la
  línea 100 pinta "Seleccionar"; `height * 0.65` fijo (línea 166); autofoco del buscador;
  "Sin resultados" centrado sobre el área que tapa el teclado.
- **Archivos esperados** `lib/presentation/widgets/adaptive_entity_picker.dart` ·
  `transfer_form_screen.dart` y `purchase_form_screen.dart` (054, criterio común de selector
  de persona)
- **Tests ANTES** el selector sin valor no solapa etiqueta y hint — falla hoy; al abrir no hay
  foco en el buscador; con `viewInsets` simulado "Sin resultados" es visible; con 4 elementos la
  hoja no ocupa el 65 %.
- **Tests DESPUÉS** los anteriores + los 3 selectores de persona coinciden en criterio.
- **Riesgo de regresión BAJO** — un archivo, pero usado por **los 4 formularios**: cualquier
  fallo se ve en todas partes. Verificar los 4 en dispositivo.
- **Dependencias** después de F (054 depende del helper de etiquetas de 016) e I (normalización
  de búsqueda del selector, 019).
- **Prueba manual Pixel 8** abrir los ~10 selectores de la app, con y sin valor, con teclado
  abierto y cerrado.
- **Criterio de terminado** ningún selector muestra texto superpuesto ni obliga a cerrar el
  teclado para elegir.

### BATCH L · FAB, insets del sistema y alturas fijas

- **UIBUG** 008 (HIGH), 018 (HIGH), 009, 030, 055, 064
- **Causa raíz** tres grupos vecinos que conviene tocar juntos porque comparten síntoma:
  `FAB_SAFE_AREA` (`PageFrame` cierra con 24 px bajo un FAB extendido; el FAB no se aparta con
  el teclado), `FIXED_HEIGHT` (`catalogs_screen.dart:264` `height: 520`;
  `person_detail_screen.dart:72` `height: 480`; `transfer_form_screen.dart:296` `0.48`) y
  `SYSTEM_INSETS` (`purchase_form_screen.dart` es el único formulario **sin `SafeArea`**).
  > **Corrección respecto a `39`**: 064 **no** pertenece al grupo del FAB — `/compras/nueva`
  > está fuera del `ShellRoute` y no tiene FAB.
- **Archivos esperados** `lib/presentation/widgets/common.dart` (`PageFrame`) ·
  `lib/presentation/app_shell.dart` · `catalogs_screen.dart` · `person_detail_screen.dart` ·
  `transfer_form_screen.dart` · `purchase_form_screen.dart`
- **Tests ANTES** con el scroll al final, el último ítem no queda bajo el FAB (comprobando
  rectángulos) — falla hoy en 6 pantallas; la última fila del catálogo es pulsable — falla hoy;
  con `viewInsets` simulado el campo de búsqueda del Inicio no queda bajo el FAB.
- **Tests DESPUÉS** los anteriores + comprobación en las 6 pantallas de la tabla de 008.
- **Riesgo de regresión MEDIO** — `PageFrame` lo usan **todas** las pantallas. Un relleno mal
  calculado añade hueco visible en todas. Cambiar `PageFrame` en un commit propio y revisar las
  16 pantallas.
- **Dependencias** ninguna estricta; hacerlo después de D evita rehacer trabajo si el shell cambia.
- **Prueba manual Pixel 8** recorrer las 6 pantallas de la tabla de 008 hasta el final del
  scroll; abrir el teclado en Inicio; llegar al final de `/compras/nueva`; abrir Catálogos con
  22 productos.
- **Criterio de terminado** ningún control queda permanentemente inalcanzable en ninguna
  pantalla.

### BATCH M · Ajuste de texto y accesibilidad

- **UIBUG** 017 (HIGH), 020 (HIGH), 021 (HIGH), 063
- **Causa raíz** `TEXT_WRAPPING`. Filas sin reparto de ancho acordado: el `Text` recibe una
  restricción tan estrecha que Flutter parte por carácter. 063: `app_shell.dart:53` exige
  ≥1150 px para el rail extendido y el Pixel 8 apaisado da ≈914.
- **Archivos esperados** `lib/presentation/screens/settlements_screen.dart` ·
  `lib/presentation/app_shell.dart`
- **Tests ANTES** con `textScaler` 1.3 la lista de liquidación no solapa columnas ni parte por
  carácter — falla hoy; con el nombre largo del dataset la tarjeta no supera N líneas — falla
  hoy; a 914 px de ancho el rail muestra etiquetas — falla hoy.
- **Tests DESPUÉS** los anteriores + comprobación a 1.0 y 1.3 de escala.
- **Riesgo de regresión BAJO** — cambios de layout acotados a una pantalla y al shell.
- **Dependencias** después de L (el reparto de ancho de las tarjetas se ve mejor con el scroll
  ya arreglado).
- **Prueba manual Pixel 8** al **130 %** de escala (`settings put system font_scale 1.3`) y en
  **horizontal**. **Restaurar `font_scale 1.0`, `user_rotation 0` y `accelerometer_rotation 1`
  al terminar**, como hizo la auditoría.
- **Criterio de terminado** al 130 % ninguna palabra se parte por la mitad y ninguna columna
  se solapa.

### BATCH N · UX de formularios

- **UIBUG** 031, 032, 033, 037, 038, 039, 040, 041, 042, 043, 044, 046, 060
- **Causa raíz** `FORM_UX`. No es una sola causa técnica sino un conjunto de afordancias y
  validaciones de los 4 formularios y de Catálogos. Se agrupan porque comparten archivos,
  método de prueba y sesión de verificación en dispositivo.
- **Sub-agrupación sugerida** (commits separados dentro del lote):
  - **N1 validación y mensajes**: 031, 032, 039, 044
  - **N2 afordancias de expansión**: 042, 043, 046 (mismo patrón: `trailing` del `ExpansionTile`
    ocupado por un botón, que elimina el chevron)
  - **N3 etiquetas y anchos**: 037, 038, 040, 041, 060
  - **N4 acción destructiva**: 033 (reutilizar `confirmDestructiveAction`, que ya existe)
- **Archivos esperados** los 4 formularios + `catalogs_screen.dart` +
  `lib/presentation/widgets/common.dart` (033)
- **Tests ANTES** uno por UIBUG, todos de widget; todos deben fallar hoy.
- **Tests DESPUÉS** los anteriores en verde.
- **Riesgo de regresión BAJO** — cambios locales. **041 debe verificarse después de 006**
  (BATCH K): al hacer flotar la etiqueta, el solape con la cabecera de la tarjeta puede
  aparecer en más sitios.
- **Dependencias** después de K (006 cambia el aspecto de todos los selectores de los
  formularios) y F (037 y 044 usan formateadores).
- **Prueba manual Pixel 8** recorrer los 4 formularios de principio a fin, incluyendo
  validaciones fallidas y descarte de cambios.
- **Criterio de terminado** ningún control de formulario miente sobre lo que hace, y toda
  validación fallida produce un mensaje visible y exacto.

### BATCH O · Afordancias de listas y pulido

- **UIBUG** 022, 023, 029, 047, 048, 057, 059
- **Causa raíz** `LIST_AFFORDANCES`. Controles sin función (`onSelectChanged` activa
  `showCheckboxColumn` en `dashboard_screen.dart:235`), `TabBar` no desplazable, doble punto de
  creación en Catálogos, datos existentes no mostrados, ADMIN sin filtrar, acción sin advertencia.
- **Archivos esperados** `dashboard_screen.dart` · `person_detail_screen.dart` ·
  `catalogs_screen.dart` · `persons_screen.dart` · `app_shell.dart`
- **Tests ANTES** uno por UIBUG; todos de widget.
- **Tests DESPUÉS** los anteriores en verde.
- **Riesgo de regresión BAJO**.
- **Dependencias** después de C y D (047 depende de qué hace el FAB en cada ruta) y de F
  (048 usa `formatDate`). 057 y 059 requieren decisiones menores de producto.
- **Prueba manual Pixel 8** recorrido general de las 5 pantallas.
- **Criterio de terminado** ningún control visible carece de función.

---

## 4. Qué NO está en este plan

| Fuera de alcance | Por qué |
|---|---|
| Refactor de arquitectura | La regla de la fase lo prohíbe y ningún UIBUG lo exige. |
| `25_PERFORMANCE_AUDIT` P-01 (`Future` en `build()`) | No produjo ningún UIBUG observable en dispositivo (`39` lo registra como no convertido). |
| Cifrado de base o de backup (S-02, S-03) | Riesgos de seguridad conocidos, no defectos de interfaz. |
| Keystore de firma | Bloqueo externo; ver `35` §11. |
| STAB-019 | **No reproducible** con datos realistas; no se planifica corrección. |

## 5. Criterio de cierre de la fase de corrección

La fase termina cuando:

1. los **4 CRITICAL** están `VERIFIED` en Pixel 8;
2. ningún hallazgo con riesgo `DATA_LOSS`, `ACCOUNTING` o `FUNCTIONAL_BLOCKER` sigue `OPEN`;
3. `flutter analyze` sigue en **0 issues** y la suite sigue verde, con **más tests que los 91**
   de partida;
4. `43_UIBUG_FIX_TRACEABILITY.md` no tiene ninguna fila sin evidencia posterior;
5. `35_RELEASE_READINESS.md` se reevalúa con la evidencia nueva.

Hasta entonces el veredicto de release sigue siendo el de `35` §POST-UI-AUDIT STATUS.
