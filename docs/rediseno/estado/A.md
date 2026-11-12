# Estado de la sesión A

- Dueño del worktree: sesión proyectoagro-4d desde 2026-11-12 (hora local en el commit)
- Base incorporada: B0 (33e581f)

## Entregas listas

| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
|---|---|---|---|---|---|
| 1 | ver «Entrega 1» (último commit de la serie `be78956`, `76b7afd` y este estado) | `/aplicaciones/nueva`: paso 1 «¿Dónde aplicó?», paso 2 «¿Qué aplicó?» con hoja de producto y «Dosis y costo», paso 3 «Revise y confirme»; panel de voz anclado, aviso tras dictar, revisión de chaco de otra persona; aplicación desde un plan | ver «Entrega 1 · pruebas» | `flutter test tool/rediseno/capturas_a_test.dart` (100 %, `RDM_TEXT_SCALE=1.3`/`2.0`, `RDM_WIDTH=360`) → `build/rediseno_capturas_a/` (no versionado) | ver «Entrega 1 · diferencias» |

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

## En curso

- Planificación: «Nuevo plan» + voz (láminas Plan y VozPlan).

## Solicitudes al orquestador

- No bloqueante: `ValueRow` no tiene línea secundaria; la de «Persona» va como texto propio dentro del grupo (`application-person-hint`). Si sirve a otras sesiones, un `hint:` en `ValueRow`/`AdaptiveEntityPicker(rowStyle:)`.
- No bloqueante: `side_by_side.py` falla con `python -I` (no encuentra PIL); comparé lámina y captura por separado.

## Bloqueos y decisiones del autor

- **«Persona» en la aplicación (pendiente de confirmación del autor, no aceptada por él).** Comprobado el 2026-11-12 sobre B0 (`33e581f`):
  - `applications.person_id` es el dueño del chaco. Elegir un chaco fija la persona a su dueño, y cambiar de persona limpia el chaco y la mezcla (`application_form_screen.dart` `selectFarm`/`selectPerson`; voz: `_selectFarmForVoice`). Con un plan, la persona sale de `farms.owner_person_id` (`agro_repository.dart` `planForApplication`).
  - Se consumen sus existencias por FIFO (`availableProductsForOwner`; `inventory_movements.owner_person_id = person_id` en `_insertApplication`), y el cargo sigue su `settlement_policy` (`_chargeText`; `docs/architecture/D04_E15_*`). Al revertir, existencias y cargos vuelven a ella.
  - No se guarda quién ejecutó físicamente la aplicación. El contrato F04 la llama «el responsable» de la operación (`docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md`, `original_person_id`), y RN-35 la llama «quien aplica» (`docs/15_BUSINESS_RULES.md`).
  - Decisión del orquestador: se conserva el rótulo «Persona», con la línea secundaria neutra «Responsable del chaco · se usan sus productos». El modo propio («Aplica el titular») no cambia. No hay campo nuevo ni efecto distinto. Por eso no se usa «Quién aplicó» (lámina 3.1).

## Hallazgos fuera de alcance
