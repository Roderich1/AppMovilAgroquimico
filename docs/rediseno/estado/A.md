# Estado de la sesión A

- Dueño del worktree: sesión proyectoagro-4d desde 2026-11-12 (hora local en el commit)
- Base incorporada: B2 (`794a44b`) + coordinación `b70d37e` (grupo Personas cedido por B)

## Entregas listas

| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
|---|---|---|---|---|---|
| 1 | `65e48f8` (serie `be78956`, `76b7afd`, `65e48f8`) | `/aplicaciones/nueva`: paso 1 «¿Dónde aplicó?», paso 2 «¿Qué aplicó?» con hoja de producto y «Dosis y costo», paso 3 «Revise y confirme»; panel de voz anclado, aviso tras dictar, revisión de chaco de otra persona; aplicación desde un plan | ver «Entrega 1 · pruebas» | `flutter test tool/rediseno/capturas_a_test.dart` (100 %, `RDM_TEXT_SCALE=1.3`/`2.0`, `RDM_WIDTH=360`) → `build/rediseno_capturas_a/` (no versionado) | ver «Entrega 1 · diferencias» |
| 2 | `1c7ff89` (serie `ede5ffc`, `b7298a6`, `1c7ff89`) | `/planificacion/nueva`: «¿Qué piensa aplicar?», chaco y área, tarjetas de producto con dosis, «Necesita» y cobertura; panel de voz anclado, aviso tras dictar, conflicto de chaco y área | ver «Entrega 2 · pruebas» | mismo arnés (`3.5*`, `3.6*`) | ver «Entrega 2 · diferencias» |
| 3 | `55bbbf0` (serie `0f082b6`, `26ed816`, `97aa823`, `55bbbf0`) | Revisión A-1 (puntos 1 y 2) en `/aplicaciones/nueva` y `/planificacion/nueva`; listas `/aplicaciones` y `/planificacion` (punto 3) | ver «Entrega 3 · pruebas» | arnés con la vista entera; `3.7*`, `3.8*`; lado a lado en `build/rediseno_lado_a_lado/` | ver «Entrega 3 · diferencias» |
| 4–5 | ver «Entregas 4 y 5» (serie `1001218`, `ec5f7e8`, `0ef45e7`, `a6de432`, `cd2fb23` y este estado) | Pruebas del arreglo de «Deshacer» de B2; `/chacos/:id` (Bitácora); `/personas/:id` (Persona) | ver «Entregas 4 y 5 · pruebas» | `5.7*`, `5.2*` | ver «Entregas 4 y 5 · diferencias» |

## Entrega 1 · aplicación (2026-11-12)

Archivos: `lib/presentation/screens/application_form_screen.dart` (sólo presentación y textos; estado, validaciones, guardado y voz sin cambios de comportamiento), `tool/rediseno/capturas_a_test.dart` (nuevo) y pruebas adaptadas.

### Pruebas

- `flutter analyze` de la pantalla, la parte de voz y el arnés: sin avisos.
- Verdes, por pares con `--concurrency=2`: `f10_x01_aplicacion_productos`, `fix_aplicacion_hoja_existencias`, `fix_aplicacion_costo_cargo`, `fix_aplicacion_dosis_area`, `f04_effective_date_form`, `f10_d03_existencia_historica_form`, `plan_application_area_precision`, `uxj_b_altas_vencimiento`, `voice_draft/aplicacion_formulario_unico`, `voice_draft/formulario_unico_accesos`, `f10_x01_inicio_mas`, `ux_altas_en_contexto`, `personal_mode_flows`, `e12_pending_operation_return`, `f10_x01_regresiones`, `regression_widget`, `destructive_actions`, `responsive_v5`, `f04_admin_owner_restore_ui`, `plan_lifecycle_ui`.
- Adaptadas, sin cambiar lo que comprueban: encabezados de paso («Paso 1 de 3 · Persona y chaco» → «¿Dónde aplicó?», etc.); la fecha dice «Hoy, …» como la compra (antes «… (hoy)»); el costo total se lee por la clave `application-review-cost`; la fila de selección vacía dice «Elegir»; «Quitar» es el icono con nombre «Quitar <producto>»; «Añadir producto» es `DashedAddButton`; «Área tratada» con sufijo «ha»; «Pidió … Baje … registre» y «Escriba el área…» (usted); la vuelta desde «Registrar compra» se espera por la clave `application-step` (ya no hay título «Nueva aplicación»).

### Recorrido para revisarlo

1. Registrar › Aplicación (o `/aplicaciones/nueva`). Paso 1: «Completar por voz» abre el panel abajo (no enciende el micrófono); ✕ lo cierra. Persona → Chaco (sólo los suyos; sin persona dice «Elija primero la persona») → Fecha → Área (precargada del chaco).
2. Continuar. Paso 2: «Añadir producto» abre la hoja; más de lo disponible deja el botón deshabilitado con «Pidió … y hay …». En la tarjeta: «Editar», «Dosis y costo» (dosis, teórico y costo) y la papelera. Si falta algún producto, el aviso con «Registrar compra» (vuelve con el borrador entero).
3. Continuar. Paso 3: aviso de lotes vencidos si los hay, resumen con costo por producto y total, «?» con la explicación del costo, cargo según la forma de cobro, notas plegadas. «Confirmar aplicación» guarda una sola vez.
4. Voz: dictar en el paso 1 cierra el panel y deja el aviso «Dictar más / Deshacer último dictado»; con otra persona elegida, un chaco ajeno queda en «Revisar» y bloquea Continuar.
5. Desde un plan (Planificación › Aplicar): persona y chaco fijos, sin micrófono.

### Diferencias con la lámina (Aplicacion1–3, VozAplicacion)

| Lámina | App | Motivo |
|---|---|---|
| «Quién aplicó» | «Persona» + «Responsable del chaco · se usan sus productos» | No se registra a quien hizo el trabajo (ver «Bloqueos y decisiones del autor»). |
| Chaco antes que la persona | Persona, Chaco, Fecha | Los chacos se filtran por su responsable y cambiar de persona vacía chaco y mezcla: el orden vigente lo hace visible. |
| Sin micrófono arriba | Micrófono en la cabecera en los pasos 1 y 2 (no en el 3 ni con plan) | Conserva `form-dictar` (mostrar/ocultar el panel), como la compra. |
| Área en tarjeta con el número a la derecha | Campo con borde del tema, cifra grande, sufijo «ha» y la ayuda debajo | Mismo campo grande que la compra; la ayuda y el error del campo no caben al lado a 200 %. |
| Paso 2 sin título de lista | «Productos (n)» | Cuenta visible de la mezcla. |
| «Cambiar cantidad» | «Editar» | La hoja cambia producto y cantidad. |
| «Rosa Vargas no tiene Insecticida… para ella» | «Sin existencias de <persona>: … hasta que se registre una compra para <persona>.» | Texto vigente, sin género. |
| Hoja de producto como lámina de compra | Hoja modal vigente con el estilo nuevo, «Agregar a la mezcla» / «Guardar cambios» y «Cancelar» | Recorrido explícito del piloto X01: sólo confirmar agrega. |
| «Es costo propio: … no como deuda» | Texto del cargo vigente (E-15) según la forma de cobro | No se cambia qué se dice del cargo. |
| Sin ayuda del costo | «?» con «¿Cómo se calcula el costo?» | Función vigente (2026-11-05). |
| Título «Nueva aplicación» (barra antigua) | Sin título; «Paso n de 3» | Igual que la compra del bloque 1. |
| — | Textos en «usted» («Elija», «Escriba», «Pidió … Baje …») | Coherencia con la compra. |

## Entrega 2 · plan (2026-11-12)

Archivos: `lib/presentation/screens/plan_form_screen.dart` (sólo presentación; validación, guardado con `addPlanMulti` y voz sin cambios: guardar un plan no descuenta inventario ni genera cargos) y `tool/rediseno/capturas_a_test.dart`.

### Pruebas

- `flutter analyze` de la pantalla, la parte de voz y el arnés: sin avisos.
- Verdes (`--concurrency=2`): `voice_draft/plan_formulario_unico` (incluye «guardar no toca inventario ni cuentas»), `voice_draft/formulario_unico_accesos`, `uxj_b_altas_vencimiento`, `ux_altas_en_contexto`, `regression_widget`, `responsive_v5`, `personal_mode_flows`, `plan_lifecycle_ui`.
- Adaptadas: «Área planificada (ha)» → «Área planificada» con sufijo «ha»; la espera tras guardar usa la clave `plan-header`.
- Capturas: 100 %, 130 %, 200 % y 360 dp sin desbordes.

### Recorrido para revisarlo

1. Registrar › Planificar (o Planificación › Nuevo plan). «Completar por voz» abre el panel abajo; ✕ lo cierra.
2. Chaco: debajo dice su responsable («… · se compara con sus existencias»). El área se precarga del chaco.
3. «Agregar producto» → elegir → «+» (Agregar al plan). En cada tarjeta: dosis, «Necesita» (área × dosis) y «Cubierto · hay …» o «Falta comprar … · hay …»; sin dosis, «Escriba la dosis». La papelera quita la línea.
4. «Guardar plan» crea el plan una sola vez; no cambia existencias ni cuentas.
5. Voz: el dictado cierra el panel y deja el aviso «Dictar más / Deshacer último dictado»; con otro chaco ya elegido, chaco y área quedan en «Elegir» y bloquean «Guardar plan».

### Diferencias con la lámina (Plan, VozPlan)

| Lámina | App | Motivo |
|---|---|---|
| «Chaco Norte · Rosa Vargas» en la fila | Nombre del chaco en la fila y debajo «<responsable> · se compara con sus existencias» | El valor de la fila es el nombre (el selector lo usa); la segunda línea dice de quién son las existencias que cubren el plan. |
| Área en la misma tarjeta, a la derecha | Campo grande aparte, como en la aplicación | Mismo campo en los dos formularios; cabe a 200 %. |
| «Añadir otro producto» punteado | Selector «Agregar producto» + botón «+» (Agregar al plan) | Recorrido vigente de dos actos explícitos (sin autoselección, 2026-11-05); «Crear producto» sigue en el selector. |
| Dosis «2 L/ha» en un recuadro pequeño | Campo «Dosis (L/ha)» ancho con cifra grande | Rótulo vigente y espacio para decimales a 200 %. |
| «Productos» | «Productos (n)» | Cuenta visible. |
| Etiqueta «Cubierto · hay 8 L» | Igual; además «Falta comprar … · hay …» (ámbar) y «Escriba la dosis» (gris) | Estados que la lámina no dibuja; el texto, no sólo el color, dice el estado. |
| Sin título de barra | «Nuevo plan · <campaña>» y el micrófono | Conserva `form-dictar`. |

## Entrega 3 · revisión A-1 y listas (2026-11-12)

Archivos: `application_form_screen.dart` y `plan_form_screen.dart` (sólo `hint:` y `BadgeTone.ok`), `applications_screen.dart`, `planning_screen.dart`, `widgets/rdm_a_list.dart` (nuevo: cabecera de lista, botón de registro, vacío), `tool/rediseno/capturas_a_test.dart`; pruebas `f04_effective_date_form` y `uxj_a_navegacion`.

### Correcciones de A-1

1. Capturas de hojas: `shot()` copiado del arnés de B1 (vista entera); recapturadas todas (100 %, 130 %, 200 %, 360 dp). `3.2h_hoja_producto` ya muestra la hoja.
2. «Persona» usa `AdaptiveEntityPicker(rowStyle:, hint:)` (clave `application-person-hint`); el chaco del plan, `hint:` (clave `plan-farm-owner`); «Cubierto», `BadgeTone.ok`.
3. Listas rediseñadas (abajo).

### Pruebas

- `flutter analyze` de los seis archivos: sin avisos.
- Verdes (`--concurrency=2`): `plan_lifecycle_ui`, `uxj_a_navegacion`, `f04_effective_date_form`, `e12_pending_operation_return`, `destructive_actions`, `f10_x01_aplicacion_productos`, `voice_draft/aplicacion_formulario_unico`, `voice_draft/plan_formulario_unico`, `uxj_b_altas_vencimiento`, `fix_aplicacion_hoja_existencias`, `plan_application_area_precision`, `ux_altas_en_contexto`, `personal_mode_flows`, `regression_widget`, `responsive_v5`, `f10_x01_inicio_mas`, `f10_x01_regresiones`, `fix_aplicacion_costo_cargo`, `fix_aplicacion_dosis_area`, `f10_d03_existencia_historica_form`, `voice_draft/formulario_unico_accesos`.
- `f04_admin_owner_restore_ui`: una vez falló «restaurar desde Liquidación … deja la navegación en propio» corriendo en par con otro archivo; sola pasó dos veces seguidas. No usa estas pantallas: intermitencia de concurrencia (ver «Hallazgos fuera de alcance»).
- Adaptadas: el botón de la lista se busca por «Registrar aplicación»; el aviso tras registrar se comprueba con «Aplicación registrada» (antes «Aplicación multiproducto confirmada»).

### Recorrido para revisarlo

1. Actividad › Aplicaciones: «Registrar aplicación» (sin campaña activa: «Falta una campaña activa» › «Ir a campañas»). Filtro de campaña y búsqueda. Cada fila: persona · chaco, campaña · n productos, productos, costo y «Revertir» (motivo y PIN del titular). Una revertida: etiqueta «Revertida», quién la autorizó y costo tachado.
2. Actividad › Planificación: «Nuevo plan». «Para el sindicato · Necesidad declarada» abre la necesidad declarada. Filtro de campaña, «Mostrar planes aplicados». Cada plan: chaco · responsable, campaña · n productos, «Pendiente» o «Aplicado»; al desplegar, cada producto (área, dosis, cantidad) y «Aplicar este plan» (sólo pendientes; al volver la lista se recarga).

### Diferencias (no hay lámina de estas listas)

| Antes | Ahora | Motivo |
|---|---|---|
| «Registrar» | «Registrar aplicación» / «Nuevo plan» | Revisión A-1: sin botón flotante desde B1, el botón dice qué registra. |
| Título de `PageFrame` | Cabecera del rediseño (`RdmAListPage`, igual que la de C) | Lenguaje del bloque 1. |
| «n producto(s)» | «1 producto» / «n productos» | Plural correcto. |
| Chip «Aplicado» en lugar del indicador | Etiqueta «Pendiente»/«Aplicado» bajo la fila; el indicador de despliegue queda libre | El estado siempre en palabras (UIBUG-046). |
| Icono ↩ «Revertir» | Botón con texto «Revertir» (mismo nombre accesible) | Acción explícita. |
| «Aplicación multiproducto confirmada.» | «Aplicación registrada.» | Mismo texto que la hoja «Registrar»; sin jerga. |

## Entregas 4 y 5 · B2, Bitácora y Persona (2026-11-12)

### Arreglo de «Deshacer» de B2

- Dos pruebas nuevas (`voice_draft/aplicacion_formulario_unico`, `voice_draft/plan_formulario_unico`): deshacer el dictado retira la revisión del chaco ajeno (aplicación) y la elección de chaco y área (plan) que planteó; vuelven «Continuar» / «Guardar plan»; lo elegido a mano sigue. **Fallan con la versión anterior de `voice_form_dictation.dart` (`acce0ad`) y pasan con B2**: comprobado restaurando el archivo sólo en local y devolviéndolo después (sin cambios en el árbol).

### Bitácora (`/chacos/:id`, `farm_logbook_screen.dart`)

- Cabecera oscura con el chaco, «Bitácora · responsable · ha» y dos cifras: «Aplicado» y «Por hectárea», **todas las campañas**, del mismo informe que «Costo por chaco» (`farmCostReportTyped`, sin cálculo nuevo; una lectura más).
- Aplicaciones agrupadas por mes («Noviembre 2026»), en tarjetas; cada línea se despliega con área, dosis, teórico, real, costo y lotes (texto sin cambios). Revertida: tachada y «Revertida».

### Persona (`/personas/:id`, `person_detail_screen.dart`)

- Cabecera oscura: nombre, rol y saldo (texto sin cambios) y la cifra: «Debe / A favor / Sin saldo · todas las campañas» (`account.netMinor`) o, para el titular, «Consumo propio · no es deuda».
- Pestañas en pastilla (la elegida en verde oscuro con marca) y filas en grupos blancos. Mismos datos y textos.

### Pruebas

- Verdes: `rec_015_logbook_profile`, `rec_046_051_net_figures`, `hierarchical_navigation`, `error_states`, `voice_draft/aplicacion_formulario_unico`, `voice_draft/plan_formulario_unico`, `voice_draft/formulario_unico_accesos`, `plan_lifecycle_ui`. Analyze limpio. Ninguna prueba adaptada en estas entregas.
- Capturas 100 % y 200 %: `5.7_bitacora`, `5.7b_bitacora_detalle`, `5.2_persona`, `5.2b_persona_cuenta`, `5.2c_persona_titular`.

### Diferencias con las láminas (Bitacora, Persona)

| Lámina | App | Motivo |
|---|---|---|
| «Por hacer» con el plan del chaco y «Aplicar» | No | `plans()` no devuelve el chaco por id y el repositorio está fuera de alcance; «Aplicar este plan» sigue en Planificación. |
| «aplicó Rosa Vargas» | «… · <persona>» (texto vigente) | La persona es la responsable, no quien aplicó (ver «Persona»). |
| Cifras de la campaña | «todas las campañas» | La bitácora no se filtra por campaña; se dice el alcance. |
| Día grande a la izquierda | Fecha en la línea | El hueco del desplegable no admite el bloque (desbordaba). |
| Persona: «Registrar pago» en la cabecera | No (todavía) | El pago vive en Cuentas; se añadirá cuando el pago sea compartido (entrega de Cuentas). |
| Pestañas «Resumen · Cuenta · Chacos · Aplicado · Tiene» | «Resumen · Chacos · Aplicaciones · Inventario · Cuenta» | Rótulos vigentes y más claros; mismo contenido. |
| «Tiene en su poder» y «Ver la cuenta completa» en el resumen | En sus pestañas (Inventario, Cuenta) | Contenido vigente sin duplicar. |

## En curso

- Personas (`/personas`), Cuentas (`/liquidacion`) con Pago, Propios y Costos por chaco.

## Solicitudes al orquestador

- ~~`BadgeTone.ok`~~: hecho en B1 y usado.

- ~~`hint:` en `ValueRow`~~: hecho en B1 y usado.
- ~~PIL~~: resuelto con el venv de `_artefactos/rediseno/herramientas`.
- No bloqueante: `RdmAListPage` (A) y `RdmCPage` (C) son la misma cabecera; si se promueve una a `agro_ui.dart`, la uso.

## Bloqueos y decisiones del autor

- **«Persona» en la aplicación (pendiente de confirmación del autor, no aceptada por él).** Comprobado el 2026-11-12 sobre B0 (`33e581f`):
  - `applications.person_id` es el dueño del chaco. Elegir un chaco fija la persona a su dueño, y cambiar de persona limpia el chaco y la mezcla (`application_form_screen.dart` `selectFarm`/`selectPerson`; voz: `_selectFarmForVoice`). Con un plan, la persona sale de `farms.owner_person_id` (`agro_repository.dart` `planForApplication`).
  - Se consumen sus existencias por FIFO (`availableProductsForOwner`; `inventory_movements.owner_person_id = person_id` en `_insertApplication`), y el cargo sigue su `settlement_policy` (`_chargeText`; `docs/architecture/D04_E15_*`). Al revertir, existencias y cargos vuelven a ella.
  - No se guarda quién ejecutó físicamente la aplicación. El contrato F04 la llama «el responsable» de la operación (`docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md`, `original_person_id`), y RN-35 la llama «quien aplica» (`docs/15_BUSINESS_RULES.md`).
  - Decisión del orquestador: se conserva el rótulo «Persona», con la línea secundaria neutra «Responsable del chaco · se usan sus productos». El modo propio («Aplica el titular») no cambia. No hay campo nuevo ni efecto distinto. Por eso no se usa «Quién aplicó» (lámina 3.1).

## Hallazgos fuera de alcance

- `test/f04_admin_owner_restore_ui_test.dart` («restaurar desde Liquidación una copia del mismo Member en inventario propio…»): falló una vez en par con `formulario_unico_accesos` (`--concurrency=2`, esperaba modo propio y leyó compartido); sola pasa. Posible intermitencia por tiempo; no se tocó.
