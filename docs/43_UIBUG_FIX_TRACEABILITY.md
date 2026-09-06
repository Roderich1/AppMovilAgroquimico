# 43 — Trazabilidad de la corrección de los UIBUG

Matriz de seguimiento de la fase de corrección.

Fecha de apertura: **2026-09-05** · Última actualización: **2026-09-06** ·
Rama base: `hardening/stabilization` (`81c919f`) → cierre en `hardening/final-polish`

> # FASE CERRADA — 2026-09-06
>
> **68 de 69 filas están `VERIFIED` en el Pixel 8.** Las dos excepciones están justificadas
> por escrito: `015` no es reproducible en dispositivo y `058` es `WONT_FIX`.
>
> | Estado | Nº |
> |---|---:|
> | `VERIFIED` (corregido y comprobado en Pixel 8) | **67** |
> | `FIXED_NOT_DEVICE_VERIFIED` | **1** (`015`) |
> | `WONT_FIX` justificado | **1** (`058`) |
> | `OPEN` · `IN_PROGRESS` · `DESIGN_DECISION_REQUIRED` | **0** |
>
> Las filas `VERIFIED` han sido corregidas **y comprobadas físicamente en el Pixel 8**, con
> evidencia en `artifacts/ui-audit/fixed/<UIBUG>/` (fases anteriores) y en
> `artifacts/ui-audit/fixed/final-freeze/` (esta fase, 60 PNG). Las columnas *Code*,
> *Device Verification* y *After Evidence* sólo están rellenas cuando el cambio existe y se ha
> verificado.
>
> Ninguna fila se marca `VERIFIED` por inspección de código ni por tests: la regla es que el
> defecto se ha reproducido y comprobado en el dispositivo. La única fila que no la cumple lo
> dice en su propia celda de estado, con el motivo.
>
> **Cierre definitivo de la baseline:** [`46_BASELINE_FINAL_FREEZE`](46_BASELINE_FINAL_FREEZE.md).
> **Catálogo de hallazgos:** [`41_UIBUG_MASTER_BACKLOG`](41_UIBUG_MASTER_BACKLOG.md).

Documentos relacionados:
[41 backlog maestro](41_UIBUG_MASTER_BACKLOG.md) ·
[42 plan de corrección](42_UIBUG_FIX_PLAN.md) ·
[38 hallazgos](38_UI_AUDIT_FINDINGS.md) ·
[39 trazabilidad de auditoría](39_UI_AUDIT_TRACEABILITY.md)

## Leyenda de columnas

| Columna | Qué contiene |
|---|---|
| **UIBUG** | identificador estable (`004` se subdividió en `004A`/`004B`, ver `41` §3) |
| **Root Cause Group** | grupo de causa raíz de `41` §6 |
| **Batch** | lote de `42` §3 |
| **Test Planned** | prueba que debe **fallar antes** del fix y pasar después |
| **Code** | archivos realmente modificados — *vacío hasta que exista el cambio* |
| **Device Verification** | resultado en Pixel 8 — *vacío hasta verificarlo* |
| **Before Evidence** | captura de la auditoría, en `artifacts/ui-audit/` |
| **After Evidence** | captura posterior al fix — *vacío hasta que exista* |
| **Status** | `OPEN` · `IN_PROGRESS` · `FIXED_NOT_DEVICE_VERIFIED` · `VERIFIED` · `WONT_FIX` · `DUPLICATE` · `DESIGN_DECISION_REQUIRED` |

## Reglas de actualización

1. Una fila pasa a `FIXED_NOT_DEVICE_VERIFIED` **solo** cuando *Code* y *Test Planned* están
   rellenos y la suite está verde.
2. Una fila pasa a `VERIFIED` **solo** con *After Evidence* real capturada en Pixel 8.
3. Ninguna fila se marca `VERIFIED` por inspección de código.
4. Si un lote cierra varios UIBUG con un solo cambio, **cada fila se verifica por separado**.
5. Una fila `DESIGN_DECISION_REQUIRED` no puede pasar a `IN_PROGRESS` hasta que la decisión
   esté registrada en `41` §10.

---

## Tabla de trazabilidad

| UIBUG | Sev. | Root Cause Group | Batch | Test Planned | Code | Device Verification | Before Evidence | After Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| **UIBUG-003** | CRITICAL | `NUMERIC_INPUT` | A | tryParseDecimal tabla es-BO + ida y vuelta format/parse + widget pago | `domain/numeric_input.dart` (nuevo), `widgets/common.dart`, `settlements_screen.dart` | **Pixel 8 OK** - pago `1.500`->-150000, `1.500,25`->-150025, `0,125`->-13, `1,500` rechazado; transferencia `15.000`-> `quantity_base` 15000000. Leido de la base del dispositivo. | `UI-17-transfer-form/UI-17-ISSUE-formato-millares.png, _c-conf.png` | `fixed/UIBUG-003/` (3 PNG + verification.md) | `VERIFIED` |
| **UIBUG-001** | CRITICAL | `BACKUP_ANDROID` | B | export() contra doble con semantica Android + ida y vuelta exportar/restaurar | `data/backup_service.dart` (`_consolidateForCopy` + validacion del archivo escrito) | **Pixel 8 OK** - exportar -> archivo 196608 B -> validate() OK (esquema v5) -> modificar (28 tx) -> restaurar -> estado anterior recuperado (27 tx, saldo 3005700) | `UI-10-liquidacion/UI-10-exportar-backup.png, UI-10-restaurar-backup.png` | `fixed/UIBUG-001/` (4 PNG + verification.md) | `VERIFIED` |
| **UIBUG-002** | CRITICAL | `NAVIGATION_STACK` | C | ruta sin origen falla la suite + navegacion hasta /compras | `operations_screen.dart` (la tarjeta abre `/compras`) | **Pixel 8 OK** - historial alcanzable (UI-06 auditada por primera vez), visor de factura, pago a proveedor y reversion accesibles. Atras desde `/compras` sigue saliendo: es UIBUG-004A, lote D | `enumeracion de rutas (38, 41 §3)` | `fixed/UIBUG-002/` (4 PNG + verification.md) | `VERIFIED` |
| **UIBUG-004A** | CRITICAL | `NAVIGATION_STACK` | D | entrar/pop por cada ruta jerarquica + PageFrame muestra flecha si canPop | `app_shell.dart`, `app.dart`, `widgets/common.dart` (PageFrame), 5 pantallas: `go`->`push` en toda navegación jerárquica + flecha de volver | **Pixel 8 OK** — Atrás desde detalle vuelve a la lista y `mCurrentFocus` sigue en la app (antes `nexuslauncher`); flecha visible en cabecera | `UI-14-persona-detalle/UI-14-ISSUE-back-desde-detalle.png, UI-02-ISSUE-back-sale-de-la-app.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-005** | HIGH | `PAYMENT_FLOW` | E | abrir/cerrar dialogo de pago 20 veces sin excepcion | `settlements_screen.dart` (`_RecordPaymentDialog` StatefulWidget) | **Pixel 8 OK** - sin pantalla roja en debug; logcat sin `disposed` / `_dependents` / `dirty widget`. | `UI-10-ISSUE-pago-vacio.png, UI-10-pago-valido.png, UI-10-pago-en-PROFILE-sin-asserts.png` | `fixed/UIBUG-005/` (2 PNG + verification.md) | `VERIFIED` |
| **UIBUG-006** | HIGH | `ENTITY_PICKER` | K | selector sin valor: etiqueta y hint no se solapan | `adaptive_entity_picker.dart` (`isEmpty:false` + `floatingLabelBehavior`) | **Pixel 8 OK** — etiqueta flotante y "Seleccionar" legibles en los 4 formularios | `UI-05-ISSUE-etiqueta-superpuesta.png, UI-07-formulario-inicial.png, UI-17-inicial.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-007** | HIGH | `SEARCH` | I | buscar 'glifo' devuelve 2 filas; 'zzz' dice sin coincidencias | `dashboard_screen.dart` + `agro_repository.dart` (sin `limit` al buscar) | **Pixel 8 OK** — "glifo" encuentra los 2 productos; el vacío distingue "sin coincidencias" | `UI-01-dashboard/UI-01-busqueda-resultado.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-008** | HIGH | `FAB_SAFE_AREA` | L | scroll al final: ultimo item no queda bajo el FAB (6 pantallas) | `widgets/common.dart` (`ContentInsets` + `PageFrame`), `app_shell.dart` | **Pixel 8 OK** — en Inicio y Catálogos la última fila queda por encima del FAB | `UI-01-ISSUE-fab-tapa-ultima-fila.png, UI-03-ISSUE-ultimo-item-inalcanzable.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-009** | HIGH | `FAB_SAFE_AREA` | L | con viewInsets simulado el campo de busqueda no queda bajo el FAB | `app_shell.dart` (FAB oculto con teclado) + `PageFrame` (`viewInsets`) | **Pixel 8 OK** — con el teclado abierto el FAB desaparece y el campo queda visible | `UI-01-dashboard/UI-01-busqueda-teclado.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-010** | HIGH | `REVERSAL_CONSISTENCY` | G | fila revertida muestra 'Revertida' en Aplicaciones e Inicio; inicio y reporte no se contradicen | `applications_screen.dart`, `dashboard_screen.dart` | **Pixel 8 OK** — chip "Revertida" e importe tachado en Aplicaciones y en Inicio | `UI-02-registrar-aplicacion-destino.png, UI-01-scroll1.png, UI-10-reportes.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-011** | HIGH | `NAVIGATION_STACK` | C | confirmar compra muestra acuse y la compra figura en /compras | `operations_screen.dart` + `purchases_screen.dart` | **Pixel 8 OK** — la tarjeta abre el listado; el acuse se muestra al volver del formulario | — | `fixed/regression/` | `VERIFIED` |
| **UIBUG-012** | HIGH | `PAYMENT_FLOW` | E | el dialogo muestra nombre, campana y saldo de la persona correcta | `settlements_screen.dart` (`_RecordPaymentDialog`) | **Pixel 8 OK** - el dialogo muestra persona, `Campaña Verano 2026` y `Saldo pendiente 19.359,50 Bs`. | `UI-10-liquidacion/UI-10-dialogo-registrar-pago.png` | `fixed/UIBUG-012/` (1 PNG + verification.md) | `VERIFIED` |
| **UIBUG-013** | HIGH | `BALANCE_SEMANTICS` | H | valor esperado de cada consulta de saldo fijado y documentado | `settlements_screen.dart`, `person_detail_screen.dart` (cada cifra declara su alcance) | **Pixel 8 OK** — "Pendiente · Verano 2026" y "Saldo total · todas las campañas" | `UI-10-lista.png, UI-10-estado-de-cuenta.png, UI-13-lista.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-014** | HIGH | `PAYMENT_FLOW` | E | tras registrar aparece snackbar con el importe | `settlements_screen.dart` (`showSuccess` en `_record`) | **Pixel 8 OK** - snackbar *"Pago de 1.500,00 Bs registrado a Jose Luis Ñañez Alvarez."* | `UI-10-liquidacion/UI-10-pago-en-PROFILE-sin-asserts.png` | `fixed/UIBUG-014/` (2 PNG + verification.md) | `VERIFIED` |
| **UIBUG-015** | HIGH | `ERROR_MESSAGING` | J | friendlyError(DatabaseException) devuelve espanol; caso por defecto sin toString crudo | `widgets/common.dart` (`friendlyError` cubre `DatabaseException`) | Cubierto por la suite; no reproducible en dispositivo tras corregir UIBUG-001 | `UI-10-liquidacion/UI-10-exportar-backup.png` | — | `FIXED_NOT_DEVICE_VERIFIED` — **no verificable en dispositivo**: exigiría corromper la base mientras la app la tiene abierta, o sea fabricar una avería en vez de ejercitar el producto. Cubierto por `error_states_test.dart` |
| **UIBUG-016** | HIGH | `FORMAT_LOCALIZATION` | F | ninguna pantalla pinta PAYMENT/PLANNED/THIRD_PARTY; helper de etiquetas cubre el enum | `domain/labels.dart` (nuevo) + 5 pantallas | **Pixel 8 OK** — "Pago" en vez de `PAYMENT`; roles y estados en español | `UI-03-menu-campana.png, UI-07-picker-persona2.png, UI-17-picker-origen.png, UI-14-ISSUE-pestana-cuenta-inalcanzable.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-017** | HIGH | `TEXT_WRAPPING` | M | textScaler 1.3: sin solapes ni particion por caracter en liquidacion | `settlements_screen.dart` (reparto de ancho) + `app_shell.dart` (escala acotada en la barra) | **Pixel 8 OK a 130 %** — sin cortes a mitad de palabra, cifras completas, barra en una línea | `UI-23-fontscale/UI-23-liquidacion-130.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-018** | HIGH | `FIXED_HEIGHT` | L | la ultima fila del catalogo es alcanzable y su menu se puede pulsar | `catalogs_screen.dart` (sin `height: 520`, `shrinkWrap`) | **Pixel 8 OK** — `Zinc Quelatado` completo y con su ⋮ alcanzable | `UI-03-catalogos/UI-03-ISSUE-ultimo-item-inalcanzable.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-019** | HIGH | `SEARCH` | I | buscar 'maria' encuentra 'Maria'; unitarios de normalizeForSearch | `domain/text_search.dart` (nuevo) + 7 sitios | **Pixel 8 OK** — búsqueda sin tildes en listas y selectores | `UI-05-plan-form/UI-05-ISSUE-busqueda-sin-tildes.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-020** | HIGH | `TEXT_WRAPPING` | M | con el nombre largo del dataset la tarjeta no supera N lineas | `settlements_screen.dart` (flex 5/4 + elipsis en el nombre, `FittedBox` en el importe) | **Pixel 8 OK** — nombre en 2 líneas y el importe NUNCA se recorta | `UI-10-liquidacion/UI-10-lista.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-021** | HIGH | `TEXT_WRAPPING` | M | concepto largo en el estado de cuenta se parte por palabras | `settlements_screen.dart` (ancho acotado del importe) | **Pixel 8 OK** — la descripción se parte por palabras | `UI-10-estado-de-cuenta.png, UI-10-dialogo-pago.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-004B** | MEDIUM | `NAVIGATION_STACK` | D | test que fije la politica de Atras elegida en destino raiz | `app_shell.dart` (`backFallback` + `PopScope`) | **Pixel 8 OK** — Atrás desde `/personas` vuelve a Inicio; desde Inicio cede al sistema | `UI-02-operaciones/UI-02-ISSUE-back-sale-de-la-app.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-022** | MEDIUM | `LIST_AFFORDANCES` | O | la tabla del inicio no tiene Checkbox | `dashboard_screen.dart` (`showCheckboxColumn: false`) | **Pixel 8 OK** — la tabla del inicio ya no tiene columna de casillas | `UI-01-dashboard/UI-01-inicio.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-023** | MEDIUM | `LIST_AFFORDANCES` | O | widget test de la presentacion elegida (columna fija o tarjetas) | `dashboard_screen.dart` (`_InventoryCards` por debajo de 560 px; la tabla se conserva en pantalla ancha) | **Pixel 8 OK** — sin scroll horizontal; cada fila lleva el nombre por encabezado y las cifras rotuladas. A 130 % el `Wrap` reflota y nada se recorta | `UI-01-dashboard/UI-01-tabla-scroll-horizontal.png` | `artifacts/ui-audit/fixed/final-freeze/UI-01-inicio.png`, `A11Y-130-inicio-inventario.png` | `VERIFIED` |
| **UIBUG-024** | MEDIUM | `FORMAT_LOCALIZATION` | F | unitario formatHectares; ninguna pantalla pinta '80.0 ha' | `domain/money.dart` (`formatHectares`) + 8 sitios | **Pixel 8 OK** — "80,3 ha", "0,3 ha", "80 ha": coma decimal en toda la app | `UI-10-ISSUE-mezcla-separadores.png, UI-04-plan-expandido.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-025** | MEDIUM | `FORMAT_LOCALIZATION` | F | el resumen se compone en Dart con formatQuantity, no en SQL | `agro_repository.dart` (SQL devuelve datos) + `domain/money.dart` (`formatItemsSummary`) | **Pixel 8 OK** — "Urea 25 KG", "Semilla Soya INTA-90 500 KG" (antes `25.0 KG`) | `UI-08-aplicaciones/_zoom-cantidad.png, UI-16-lista.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-026** | MEDIUM | `FORMAT_LOCALIZATION` | F | la entrada expandida muestra '600 KG', no '600000' | `domain/money.dart` (`formatFifoLots`) + `farm_logbook_screen.dart` | **Pixel 8 OK** — "Lotes #27 96 L" (antes `FIFO: #1: 600000`) | `UI-15-bitacora/UI-15-ISSUE-fifo-crudo.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-027** | MEDIUM | `FORMAT_LOCALIZATION` | F | unitario formatDate; ninguna vista muestra fechas ISO | `domain/money.dart` (`formatDate`) + 4 sitios | **Pixel 8 OK** — "10/02/2026", "08/07/2025" (antes ISO) | `UI-15-bitacora/UI-15-entrada-expandida.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-028** | MEDIUM | `BALANCE_SEMANTICS` | H | ambas vistas del estado de cuenta dan el mismo acumulado | `person_detail_screen.dart` (`_withRunningBalance`) | **Pixel 8 OK** — la pestaña Cuenta muestra "Acumulado" en cada movimiento | `UI-14-ISSUE-pestana-cuenta-inalcanzable.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-029** | MEDIUM | `LIST_AFFORDANCES` | O | las 5 pestanas son alcanzables desde la barra | `person_detail_screen.dart` (pestañas como chips desplazables) | **Pixel 8 OK** — las 5 pestañas se alcanzan tocándolas | `UI-14-persona-detalle/UI-14-ISSUE-tabbar-recortado.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-030** | MEDIUM | `FIXED_HEIGHT` | L | con pocas filas no queda hueco desproporcionado | `person_detail_screen.dart` (`_PersonTabs` a medida del contenido) | **Pixel 8 OK** — sin el bloque de 480 px en blanco | `UI-15-bitacora/UI-15-pestana-chacos.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-031** | MEDIUM | `FORM_UX` | N1 | guardar vacio muestra error visible | `catalogs_screen.dart` (los 4 diálogos pasan a `Form` + `validator`) | **Pixel 8 OK** — "Guardar" con el nombre vacío marca el campo en rojo y escribe *"Escriba el nombre."* bajo él; el diálogo sigue abierto y no se escribe nada | `UI-03-catalogos/_crop-guardar-vacio.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-031-validacion-visible.png` | `VERIFIED` |
| **UIBUG-032** | MEDIUM | `FORM_UX` | N1 | los 3 casos de validacion del plan producen mensajes distintos | `plan_form_screen.dart` (un mensaje por condición) | **Pixel 8 OK** — sin chaco ni productos: *"Seleccione el chaco y agregue al menos un producto."*; con chaco y sin productos: *"Agregue al menos un producto al plan."* | `UI-05-plan-form/_c-UI-05-guardar-sin-productos.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-032-plan-validacion-1.png`, `-2.png` | `VERIFIED` |
| **UIBUG-033** | MEDIUM | `FORM_UX` | N4 | el boton destructivo usa color de error y no es el primario | los 4 formularios (criterio de acción destructiva) | **Pixel 8 OK** — el botón destructivo va en color de error y no es el primario, en "¿Descartar cambios?" y en el cierre de campaña | `UI-05-plan-form/_c-UI-05-descartar-cambios.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-059-confirmacion-cierre.png` | `VERIFIED` |
| **UIBUG-034** | MEDIUM | `NUMERIC_INPUT` | A | escribir '5' en un campo recien enfocado produce '5', no '05' | `transfer_form_screen.dart` (campo vacío con `hintText`) | **Pixel 8 OK** — los campos de cantidad de la transferencia abren vacíos, con la unidad por etiqueta y el `0` como pista | `UI-17-transfer-form/_zoom-cero.png` | `artifacts/ui-audit/fixed/final-freeze/UI-17-transferencia-con-origen.png` | `VERIFIED` |
| **UIBUG-035** | MEDIUM | `ENTITY_PICKER` | K | al abrir el selector no hay foco en el buscador | `adaptive_entity_picker.dart` (sin `autofocus`) | **Pixel 8 OK** — la hoja abre sin teclado; se ven las 6 opciones | `UI-05-plan-form/UI-05-picker-chaco.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-036** | MEDIUM | `ENTITY_PICKER` | K | con viewInsets simulado 'Sin resultados' es visible | `adaptive_entity_picker.dart` (alineación superior + `viewInsets`) | **Pixel 8 OK** — con el teclado abierto, el selector de 22 productos muestra `0/22` y *"Sin resultados."* completamente visible | `UI-05-plan-form/_crop-sinres.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-036-sin-resultados-con-teclado.png` | `VERIFIED` |
| **UIBUG-037** | MEDIUM | `FORM_UX` | N3 | sin producto elegido no se pinta la barra sin unidad | `purchase_form_screen.dart` (texto genérico sin unidad; forma corta al elegir producto) | **Pixel 8 OK** — sin producto: *"Precio por unidad"* y sólo *"Subtotal"*. Con producto: *"Precio BOB/L"* y *"Costo 0,00 Bs /L"* | `UI-07-ISSUE-precio-sin-unidad.png` | `artifacts/ui-audit/fixed/final-freeze/UI-07-compra-form-inicial.png`, `UIBUG-036-sin-resultados-con-teclado.png` | `VERIFIED` |
| **UIBUG-038** | MEDIUM | `FORM_UX` | N3 | el campo de cantidad de asignacion tiene etiqueta accesible | `purchase_form_screen.dart` (`labelText: Cantidad` + `suffixText` con la unidad; la de la línea pasa a "Cantidad comprada") | **Pixel 8 OK** — ningún campo del formulario queda sin etiqueta, y las dos cantidades se distinguen | `UI-07-ISSUE-asignacion-sin-etiqueta.png` | `artifacts/ui-audit/fixed/final-freeze/UI-07-compra-form-inicial.png` | `VERIFIED` |
| **UIBUG-039** | MEDIUM | `FORM_UX` | N1 | unitario del computo asignado/pendiente con persona nula | `purchase_form_screen.dart` (`_allocationStatus`: pendiente de cantidad / de persona / excede / asignado) | **Pixel 8 OK** — una línea recién abierta dice *"Pendiente de cantidad"*, no *"asignado"* | `UI-07-teclado-campo-inferior.png` | `artifacts/ui-audit/fixed/final-freeze/UI-07-compra-form-inicial.png` | `VERIFIED` |
| **UIBUG-040** | MEDIUM | `FORM_UX` | N3 | con los valores largos del dataset los campos no truncan | `purchase_form_screen.dart` (`_ResponsivePair`: proveedor/campaña y cantidad/moneda se apilan por debajo de 420 px) | **Pixel 8 OK** — "Verano 2026" y el proveedor se leen completos; "Cantidad comprada" ya no se recorta a "Cantidad compr…" | `UI-07-factura-con-teclado.png` | `artifacts/ui-audit/fixed/final-freeze/UI-07-compra-form-inicial.png` | `VERIFIED` |
| **UIBUG-041** | MEDIUM | `FORM_UX` | N3 | la etiqueta flotante no se solapa con la cabecera de la tarjeta | `purchase_form_screen.dart` (`childrenPadding` con relleno superior: se corrige el contenedor, no un texto concreto) | **Pixel 8 OK** — la etiqueta flotante "Producto" se ve entera, separada de la cabecera de la tarjeta | `UI-07-ISSUE-etiqueta-producto-recortada.png` | `artifacts/ui-audit/fixed/final-freeze/UI-07-compra-form-inicial.png` | `VERIFIED` |
| **UIBUG-042** | MEDIUM | `FORM_UX` | N2 | elegir un producto lo anade a la lista | `application_form_screen.dart` (elegir agrega) | **Pixel 8 OK** — elegir "Atrazina 50" lo agrega en el acto: "Productos (1)" | `UI-09-linea-producto.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-042-043-aplicacion-fila-agregada.png` | `VERIFIED` |
| **UIBUG-043** | MEDIUM | `FORM_UX` | N2 | la fila anadida muestra sus campos o su indicador de expansion | `application_form_screen.dart` (`initiallyExpanded`) | **Pixel 8 OK** — la fila nace desplegada, con Dosis, Cantidad real y el resumen de stock a la vista | `UI-09-application-form/_c-fila.png, _c-fila1.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-042-043-aplicacion-fila-agregada.png` | `VERIFIED` |
| **UIBUG-044** | MEDIUM | `FORM_UX` | N1 | stock despues negativo se pinta con el color de error | `application_form_screen.dart` (proyección negativa en rojo) | **Pixel 8 OK** — 50 L sobre 30 L disponibles pinta *"Disponible 30 L · stock después -20 L"* en rojo | `UI-09-application-form/_c-val.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-044-stock-negativo.png` | `VERIFIED` |
| **UIBUG-045** | MEDIUM | `REVERSAL_CONSISTENCY` | G | un plan aplicado no ofrece Aplicar sin advertencia; si hay migracion, equivalencia v5->v6 | `app_database.dart` (esquema **v6**: índice único parcial `applications(plan_id)` + normalización de estados), `agro_repository.dart` (`_ensurePlanNotApplied`, `PLANNED→APPLIED`, la reversión ya no reabre, `plans(includeApplied:)`), `planning_screen.dart` (lista de pendientes, histórico, sin acción si está aplicado, recarga al volver) | **Pixel 8 OK** — plan pendiente → Aplicar → aplicación creada → sale de la lista operativa → el histórico lo marca "Aplicado" → segundo intento rechazado con mensaje propio y **sin duplicar** → persiste tras reiniciar → revertir la aplicación **no** lo reabre | `UI-04-planificacion/UI-04-lista.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-045-*.png` (7 PNG) | `VERIFIED` |
| **UIBUG-046** | MEDIUM | `FORM_UX` | N2 | la fila de plan muestra indicador de expansion | `planning_screen.dart` (el botón deja libre el chevron) | **Pixel 8 OK** — las filas de planificación muestran su indicador de despliegue | `UI-04-planificacion/UI-04-plan-expandido.png` | `artifacts/ui-audit/fixed/final-freeze/UI-04-planificacion.png` | `VERIFIED` |
| **UIBUG-047** | MEDIUM | `LIST_AFFORDANCES` | O | widget test de la jerarquia entre Agregar y el FAB en Catalogos | `app_shell.dart` (`hidesGlobalFab` retira el FAB en `/catalogos`), `catalogs_screen.dart` (`_addLabel` dice qué crea) | **Pixel 8 OK** — en Catálogos no hay FAB y la única acción primaria dice "Agregar persona" / "chaco" / "producto" / "proveedor" / "campaña". El FAB no ofrecía ninguna creación de catálogo, así que no se pierde nada | `UI-03-catalogos/UI-03-personas.png` | `artifacts/ui-audit/fixed/final-freeze/UI-03-catalogos-personas.png`, `UI-03-catalogos-campanas.png` | `VERIFIED` |
| **UIBUG-048** | MEDIUM | `LIST_AFFORDANCES` | O | la fila de campana muestra el rango de fechas | `catalogs_screen.dart` (rango de fechas) | **Pixel 8 OK** — "Cerrada · 01/05/2025 – 05/09/2026" en la fila de campaña | `UI-03-catalogos/UI-03-menu-campana.png` | `artifacts/ui-audit/fixed/final-freeze/UI-03-catalogos-campanas.png` | `VERIFIED` |
| **UIBUG-049** | MEDIUM | `BACKUP_ANDROID` | B | - (cambio puramente visual de iconografia) | `settlements_screen.dart` (iconografía local, "respaldo") | **Pixel 8 OK** — icono de carpeta y textos sin "backup" | `UI-10-liquidacion/UI-10-menu-backup.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-050** | MEDIUM | `ERROR_MESSAGING` | J | sin backups se muestra aviso informativo, no error | `settlements_screen.dart` (aviso informativo, no error) | **Pixel 8 OK** — sin ningún respaldo se muestra un aviso informativo, no un error: *"Todavía no hay ningún respaldo. Use "Exportar respaldo" para crear el primero."* | `UI-10-liquidacion/UI-10-restaurar-backup.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-050-sin-respaldos.png` | `VERIFIED` |
| **UIBUG-051** | MEDIUM | `NAVIGATION_STACK` | J | test de navegacion por cada tarjeta de Operaciones | `operations_screen.dart` (títulos y destinos) | **Pixel 8 OK** — las cinco tarjetas nombran su destino y todas abren su listado | `UI-02-registrar-aplicacion-destino.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-052** | MEDIUM | `SEARCH` | I | widget test del buscador de Personas | `persons_screen.dart` (buscador + recarga) | **Pixel 8 OK** — Personas ya tiene buscador y botón de recarga | `UI-13-personas/UI-13-lista.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-053** | MEDIUM | `SEARCH` | I | widget test de fecha y filtro en Transferencias | `transfers_screen.dart` (fecha con `formatDate`) | **Pixel 8 OK** — la lista de transferencias muestra la fecha de cada movimiento | `UI-16-transferencias/UI-16-lista.png` | `artifacts/ui-audit/fixed/final-freeze/UI-16-transferencias.png` | `VERIFIED` |
| **UIBUG-054** | MEDIUM | `ENTITY_PICKER` | K | los 3 selectores de persona coinciden en criterio de subtitulo e inclusion | `transfer_form_screen.dart`, `purchase_form_screen.dart`, `domain/labels.dart` | **Pixel 8 OK** — los tres selectores de persona muestran el rol con el mismo criterio | `UI-17-picker-origen.png, UI-17-picker-destino.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-055** | MEDIUM | `FIXED_HEIGHT` | L | con 8 productos la lista no corta a mitad de fila sin senal | `transfer_form_screen.dart` (sin cota de 48 %) | **Pixel 8 OK** — con 8 productos la lista crece con su contenido y ninguna fila queda seccionada | `UI-17-productos-disponibles.png` | `artifacts/ui-audit/fixed/final-freeze/UI-17-transferencia-con-origen.png` | `VERIFIED` |
| **UIBUG-056** | MEDIUM | `FORMAT_LOCALIZATION` | F | formatQuantity con 174250 y 174100; revisar tests existentes del patron | `domain/money.dart` — patrón conservado; se documenta el criterio | **Pixel 8 OK** — patrón de cantidad uniforme en inventario, bitácora y selectores | `UI-11-inventario/UI-11-lista.png` | `artifacts/ui-audit/fixed/final-freeze/UI-11-inventario.png`, `UI-12-inventario-detalle.png` | `VERIFIED` |
| **UIBUG-057** | LOW | `LIST_AFFORDANCES` | O | widget test de la lista de Personas con ADMIN | `persons_screen.dart` (ADMIN marcado como no participante) | **Pixel 8 OK** — "Administrador · no participa en la liquidación" | `UI-13-personas/UI-13-lista.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-058** | LOW | `BALANCE_SEMANTICS` | H | - (convencion visual; se decide con 013) | `settlements_screen.dart` — convención conservada; se decide con 013 | Sin cambio: el signo es contablemente correcto | `UI-10-liquidacion/UI-10-estado-de-cuenta.png` | — | `WONT_FIX` |
| **UIBUG-059** | LOW | `LIST_AFFORDANCES` | O | widget test del menu sobre una campana cerrada | `agro_repository.dart` (`activateCampaign` rechaza `CLOSED`), `catalogs_screen.dart` (sólo `PLANNED` ofrece "Activar"; confirmación de cierre irreversible) | **Pixel 8 OK** — la campaña cerrada sólo ofrece "Editar"; la planificada sí "Activar"; la activa sólo "Cerrar". La confirmación declara periodo, qué deja de admitir y que no podrá reactivarse. Cerrada sigue cerrada tras reiniciar | `UI-03-catalogos/UI-03-menu-campana.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-059-*.png` (6 PNG) | `VERIFIED` |
| **UIBUG-060** | LOW | `FORM_UX` | N3 | widget test del formulario de transferencia recien abierto | `transfer_form_screen.dart` (estado vacío explícito; el recuento sólo aparece con origen) | **Pixel 8 OK** — sin origen no hay ningún `0`: *"Seleccione un origen para ver su inventario."* y ningún control de cantidad | `UI-17-transfer-form/UI-17-inicial.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-060-transferencia-sin-origen.png` | `VERIFIED` |
| **UIBUG-061** | LOW | `ENTITY_PICKER` | K | widget test del selector con 4 y con 22 elementos | `adaptive_entity_picker.dart` (alto por contenido acotado) | **Pixel 8 OK** — la hoja se ajusta al número de elementos | `UI-07-purchase-form/UI-07-picker-proveedor.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-062** | LOW | `NAVIGATION_STACK` | D | unitario de selectedIndex para las 17 rutas | `app_shell.dart` (`_detailOwners`) | **Pixel 8 OK** — la bitácora de chaco resalta **Personas** (antes Inicio) | `UI-15-bitacora/UI-15-entrada-expandida.png` | `fixed/regression/` | `VERIFIED` |
| **UIBUG-063** | LOW | `TEXT_WRAPPING` | M | a 914 px de ancho el rail muestra etiquetas | `app_shell.dart` (`labelType: all` por debajo de 1150 px) | **Pixel 8 OK** — en horizontal el rail muestra las etiquetas de los cinco destinos | `UI-22-orientacion/UI-22-horizontal-bitacora.png` | `artifacts/ui-audit/fixed/final-freeze/UIBUG-068-rail-130-horizontal.png` | `VERIFIED` |
| **UIBUG-064** | LOW | `SYSTEM_INSETS` | L | con viewPadding inferior simulado el total no queda bajo la barra de gestos | `purchase_form_screen.dart` (`viewPadding` en el relleno inferior) | **Pixel 8 OK** — la tarjeta TOTAL COMPRA queda holgadamente por encima de la barra de gestos | `UI-07-purchase-form/_c-confirmar.png` | `artifacts/ui-audit/fixed/final-freeze/UI-07-compra-form-inicial.png` | `VERIFIED` |
| **UIBUG-065** | LOW | `NUMERIC_INPUT` | A | escribir 'abc' produce 'no interpretable', no 'mayor a cero' | `settlements_screen.dart`, `domain/numeric_input.dart` | **Pixel 8 OK** - `abc` muestra el formato esperado y `1,500` el aviso de ambiguedad; ya no dice "mayor a cero" ni escribe nada. | `- (revision de codigo, sin captura)` | `fixed/UIBUG-065/` (2 PNG + verification.md) | `VERIFIED` |
| **UIBUG-066** | LOW | `CODE_CORRECTNESS` | — | setState no devuelve Future: 2 tests de widget + guarda estática sobre todo `lib/` | `applications_screen.dart`, `inventory_screen.dart`, `planning_screen.dart`, `transfers_screen.dart`, `persons_screen.dart` (cuerpo de bloque en `refresh()`) | **Pixel 8 OK** — **0 ocurrencias** de `setState() callback` en `logcat` tras recorrer las cinco listas | `45` §12 (anotado sin identificador) | `artifacts/ui-audit/fixed/final-freeze/` (logcat limpio) | `VERIFIED` |
| **UIBUG-067** | LOW | `TEXT_WRAPPING` | — | cubierto por `ui_polish_test.dart`: un desbordamiento de layout hace fallar el test | `dashboard_screen.dart` (`Expanded` en la cinta de campaña activa) | **Pixel 8 OK** — la cinta se lee entera; `logcat` sin `RenderFlex` | destapado por el test de 023 (`overflowed by 84 pixels`) | `artifacts/ui-audit/fixed/final-freeze/UI-01-inicio.png` | `VERIFIED` |
| **UIBUG-068** | MEDIUM | `TEXT_WRAPPING` | — | 3 tests: el shell usa rail en horizontal, no desborda al 130 %, y el rail tiene scroll propio | `app_shell.dart` (el rail dentro de `SingleChildScrollView` + `ConstrainedBox` + `IntrinsicHeight`) | **Pixel 8 OK** — sin `BOTTOM OVERFLOWED`; los cinco destinos alcanzables y "Cuentas" al desplazar | no existía: latente desde el arreglo de 063 | `artifacts/ui-audit/fixed/final-freeze/UIBUG-068-rail-130-horizontal.png`, `UIBUG-068-rail-desplazado.png` | `VERIFIED` |
---

## Recuento de control

| Métrica | Valor |
|---|---:|
| Filas | **69** |
| IDs cubiertos | **68** (001–068; `004` subdividido en A/B) |
| **`VERIFIED`** (corregido y comprobado en Pixel 8) | **67** |
| `FIXED_NOT_DEVICE_VERIFIED` (corregido, cubierto por tests) | **1** |
| `OPEN` | **0** |
| `DESIGN_DECISION_REQUIRED` | **0** |
| `WONT_FIX` (con justificación) | **1** |
| `IN_PROGRESS` / `DUPLICATE` | **0** |
| Filas con *Code* rellenado | **69** |
| Filas con *After Evidence* | **67** |

### Las dos filas que no son `VERIFIED`, y por qué

| UIBUG | Estado | Motivo |
|---|---|---|
| **015** | `FIXED_NOT_DEVICE_VERIFIED` | El defecto era que un `DatabaseException` de SQLite llegaba al usuario en inglés. Reproducirlo en el dispositivo exigiría **corromper la base mientras la aplicación la tiene abierta**: eso es fabricar una avería, no ejercitar el producto. El arreglo (`friendlyError` cubre `DatabaseException`) está cubierto por `error_states_test.dart`, y la causa original que lo hacía visible —`export()` fallando siempre en Android— es UIBUG-001, que **sí** está verificado en dispositivo. |
| **058** | `WONT_FIX` | El signo del asiento es **contablemente correcto**. Invertirlo para que "se lea mejor" contradiría el modelo de cuentas. Es una decisión registrada, no un defecto pendiente. |

### Evidencia de esta fase

60 capturas en `artifacts/ui-audit/fixed/final-freeze/`, tomadas en el mismo entorno conocido
(Pixel 8 · Android 16 / API 36 · 1080×2400 · 420 dpi), además de las 119 originales de la
auditoría y las de las fases anteriores, **ninguna sustituida**.

Una sola captura acredita varios UIBUG cuando la pantalla los reúne: por ejemplo
`UI-07-compra-form-inicial.png` prueba a la vez 037, 038, 039, 040, 041 y 064, porque los seis
se ven en el estado inicial del formulario de compra. No se han duplicado capturas para inflar
el recuento.

Las **5** filas que en su momento fueron `DESIGN_DECISION_REQUIRED` eran: **004B** (política de Atrás en
destino raíz), **013** (vocabulario de saldos), **045** (reaplicación de planes), **057**
(ADMIN en la lista de personas) y **059** (reapertura de campaña cerrada). Ver `41` §10.

Dos de las siete decisiones iniciales **ya se tomaron y están documentadas**:

| UIBUG | Decisión tomada | Dónde se justifica |
|---|---|---|
| **003** | Convenio **es-BO estricto**: la coma decide decimales, el punto miles; `1,500` se **rechaza por ambiguo** en vez de adivinar | [`44_NUMERIC_INPUT_SPEC.md`](44_NUMERIC_INPUT_SPEC.md) |
| **002** | La tarjeta de Operaciones abre el **listado** `/compras`, como aplicaciones y transferencias; el FAB sigue abriendo el formulario | `artifacts/ui-audit/fixed/UIBUG-002/verification.md` |

## Cobertura por lote

| Batch | UIBUG | Nº |
|---|---|---:|
| A | 003, 034, 065 | 3 |
| B | 001, 049 | 2 |
| C | 002, 011 | 2 |
| D | 004A, 004B, 062 | 3 |
| E | 005, 012, 014 | 3 |
| F | 016, 024, 025, 026, 027, 056 | 6 |
| G | 010, 045 | 2 |
| H | 013, 028, 058 | 3 |
| I | 007, 019, 052, 053 | 4 |
| J | 015, 050, 051 | 3 |
| K | 006, 035, 036, 054, 061 | 5 |
| L | 008, 009, 018, 030, 055, 064 | 6 |
| M | 017, 020, 021, 063 | 4 |
| N1–N4 | 031, 032, 033, 037, 038, 039, 040, 041, 042, 043, 044, 046, 060 | 13 |
| O | 022, 023, 029, 047, 048, 057, 059 | 7 |
| | **Total** | **66** |
