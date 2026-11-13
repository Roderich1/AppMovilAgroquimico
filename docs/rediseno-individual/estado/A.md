# Sesión A — Operaciones y voz (modo individual)

Rama `feat/modo-individual-a` (`_wt/IND-A`), base `3d6eef4`. Trabajo del 2026-11-13. Sin push.

## Commits

| Commit | Contenido |
|---|---|
| `54802a9` | Compra, aplicación, plan y voz en modo individual; pruebas existentes ajustadas a los textos nuevos |
| `5f1b9a5` | `test/ind_a_modo_individual_test.dart`; dos pruebas existentes ajustadas; voz con letra grande |
| `8eea40c` | Capturas del arnés: `docs/evidence/rediseno-individual/2026-11-13/a/` (80 PNG) |
| (este) | Estado |

## Archivos

- **`lib/` (todos de A):** `purchase_form_screen.dart`, `purchase_form_voice.dart`, `application_form_screen.dart`, `plan_form_screen.dart`, `voice/voice_form_dictation.dart`.
- **Nuevos:**
  - `test/support/ind_a_household.dart`: hogar individual real, sin terceros.
  - `test/ind_a_modo_individual_test.dart`.
  - `tool/rediseno/capturas_ind_a_test.dart`.
- **Pruebas existentes ajustadas por cambios intencionales de texto o fila:**
  - `test/personal_mode_flows_test.dart`;
  - `test/f10_compra_destinatario_explicito_test.dart`;
  - `test/f10_x01_aplicacion_productos_test.dart`;
  - `test/voice_draft/formulario_unico_accesos_test.dart`;
  - `test/fix_aplicacion_costo_cargo_test.dart`;
  - `test/f04_admin_owner_restore_ui_test.dart` (sólo el caso del formulario de aplicación).
- **No toqué** `agro_repository.dart` ni ningún archivo de otro propietario. Todo el cambio se condiciona al modo vigente (`personalOwnerId`, `personalMode`, `loadedMode`). No se añadió otra bandera.

## Láminas cubiertas

| Lámina | Qué cambia en modo individual | Prueba | Captura |
|---|---|---|---|
| I-10 | Rótulo «Paso 1 de 2 · campaña». La tarjeta ya no dice «Para el titular» y sólo avisa «Pendiente de cantidad». | `ind_a…` compra a crédito | `I-10_paso1*` |
| I-11 | Hoja sin «¿Para quién es?», selector ni aviso «Para el titular». Mismo borrador; la página queda atenuada detrás. | `ind_a…`, `f10_compra_destinatario…` (e) | `I-11*`, `I-11k_hoja_teclado*` |
| I-12 | «Hoy · entra a su almacén», sin «Para:» por línea. Con «Todavía no»: «Esta compra quedará por pagar: X con proveedor…». El doble toque registra una sola compra. Al contado, el pago es del titular por el total. | `ind_a…` (dos casos) | `I-12*`, `I-12b*`, `I-12c*` |
| I-13 | «Escuchando» en hoja oscura, con la guía «Diga producto, cantidad y precio» y «Cancelar» y «Terminar». A letra grande, uno sobre otro. | `ind_a…` voz | `I-13_escuchando*` |
| I-14 | «Procesando tu voz · Los datos aparecerán en el formulario para que los revise» y «Cancelar». Un resultado tardío tras cancelar no se aplica. | `ind_a…` cancelar | `I-14_procesando*`, `I-14b_cancelado*` |
| I-15 | «Dictar más» en lima y «Deshacer último dictado» contorneado. El aviso va aparte: «Parte del dictado no corresponde a este formulario…». Un nombre dictado no crea ni asigna persona: la tabla `persons` no cambia y la línea queda para el titular. | `ind_a…`, `formulario_unico_accesos` | `I-15*` |
| I-20 | Sin fila «Aplica el titular» ni «Quién aplicó». El campo se llama «Superficie tratada»; la ayuda indica la superficie del chaco. | `ind_a…`, `personal_mode_flows`, `f10_x01…` | `I-20*` |
| I-21 | Teclado abierto en la hoja de producto (336 dp simulados). | captura | `I-21_teclado*` |
| I-22 | Revisión con «superficie tratada: 1 ha de 3 ha», «SALE DE SU ALMACÉN», «Tiene 26 L · le quedarán 24 L» y «Se suma a los costos de <chaco> en esta campaña. No es una deuda.». Se verificó que las existencias del titular bajan de 26 000 a 24 000. | `ind_a…` aplicación, `fix_aplicacion_costo_cargo` | `I-22*` |
| I-23 | «Fecha prevista (opcional)», que ya existía en el modelo como `planned_date`. Además: «Superficie prevista», «Cantidad prevista», «Tiene 14 L · alcanza / faltan» y el botón «Continuar». | `ind_a…` plan | `I-23*` |
| I-24 | Paso «Revise el plan» con «PREVISTO EN PLANES» y «Un plan no descuenta existencias ni registra una deuda…». Atrás vuelve al formulario sin perder nada. Al guardar se crea un plan `PLANNED` sin movimientos de inventario ni pagos. | `ind_a…` plan | `I-24_revision*` |

Capturas: sufijo vacío = 390 dp al 100 %; `_x13` = 130 %; `_x20` = 200 %; `_w900` = 900 dp. Todas salen del arnés de pruebas con fuentes reales y datos sintéticos, no de un teléfono. Los dictados son texto inyectado por el puerto falso.

## Pruebas (todas con `ftest.sh`, focalizadas)

- `test/ind_a_modo_individual_test.dart`: **9/9**. Verifica filas en la base: asignaciones, pagos, existencias, planes y movimientos.
- Conjunto de 38 archivos que usan los formularios de compra, aplicación o plan, o la voz (lista en `build/ind_a_tests.txt`): **306 pasan, 1 falla**.
  - El fallo es `personal_mode_flows_test.dart` › «catálogos: no se agregan responsables…».
  - **Es anterior a la sesión A:** también falla en la base `3d6eef4`, comprobado en un worktree temporal ya retirado.
  - Causa: la barra individual de la base común añade la pestaña «Chacos», y `find.text('Chacos')` encuentra dos widgets. Afecta a la base común (ORQ), no a mis archivos.
- **Intermitentes:** en la primera pasada del conjunto fallaron dos casos de restauración de `f04_admin_owner_restore_ui_test.dart`. Pasaron solos en IND-A, en la base y en la segunda pasada completa. Son de carga, no de este cambio.
- `flutter analyze` de `lib/presentation`, del arnés y de las pruebas nuevas: sin avisos.

## Diferencias intencionales respecto a las láminas

- **Compra en dos pasos con el proveedor en la página**, como la lámina. La hoja conserva «Listo» y «Añadir otro», no «Guardar» ni «Guardar y añadir otro», por la decisión anterior de que la hoja no guarda.
- **El número del envase sigue plegado en «Más datos del envase»:** es un dato secundario y opcional.
- **«Factura, notas y campaña (opcional)»** en lugar de «Comprobante y notas»: la campaña se conserva.
- **El aviso «Todavía no»** habla del saldo de **esta** compra, no del total adeudado al proveedor. Remite a «Registrar › Pago a un proveedor», que depende del rótulo del ORQ en la hoja (I-03).
- **Aplicación en tres pasos** (dónde, qué, revisión), no en una sola página. El campo de cantidad está en la hoja «Agregar producto». En el modo individual sólo cambian los textos y las filas.
- **«Costo estimado»** en lugar de «Costo de lo aplicado»: el costo final se fija al confirmar, por FIFO.
- **Con cobro por consumo**, el aviso de costo añade «Queda anotado como consumo propio»: el repositorio lo anota, según E-15.
- **Voz:**
  - Sin forma de onda: no hay nivel de audio y sería simulado.
  - El resumen sigue siendo «N campos completados, M líneas añadidas», no «La voz completó 2 productos».
  - Un precio que falta se marca «Falta: precio» en la tarjeta, y «Continuar» lo explica al pulsarlo. No hay botón «Escribir precio».
- **Los estados de voz nuevos sólo se aplican en modo individual** (`individualHint`, `individual`). El modo con varias personas mantiene su panel. Decisión abierta para el autor: ¿llevar el mismo panel a ese modo?

## Peticiones a otros propietarios

- **ORQ (base común):** `personal_mode_flows_test.dart` › catálogos falla por la pestaña «Chacos». La prueba debe tocar el texto dentro de Catálogos con un buscador acotado, no `find.text('Chacos')`.
- **ORQ (`register_sheet.dart`):** el aviso de la compra a crédito dice «Registrar › Pago a un proveedor». Ese rótulo debe existir en la hoja (lámina I-03).
- **ORQ (`agro_repository.dart`):** los mensajes de excepción visibles dicen «En inventario propio…». Si se adopta «modo individual» en toda la interfaz, falta cambiar esos textos. No los toqué.

## Pendientes y limitaciones

- No probé en emulador ni en teléfono, sólo en el arnés. La voz real (Vosk y Whisper) no se ejecutó; sólo el puerto falso.
- A 200 %, en la hoja de producto el subtotal queda bajo los botones fijos hasta desplazar. Es el comportamiento de la ronda 2 y no cambié la hoja en ningún modo.
- Al cambiar de modalidad durante un dictado, éste se cancela y el formulario queda bloqueado por `ModeChangedNotice`, como antes.
