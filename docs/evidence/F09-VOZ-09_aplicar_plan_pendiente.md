# F09-VOZ-09 — Aplicar un plan pendiente por voz (D-F09-4, EVO-018)

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz).
- **Base:** Mobile `main` `8a2c5589b8ca4942d7c4800a8c54a669ecc0af8e` (#109 integrado).
- **Rama:** `feat/f09-plan-pendiente-voz`. **Commit verificado:** `8d94e68da4c0db14a7aa80e429c75f52e4d922c1`.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #15 y #16, con EVO-018. GATE-F09 (#17) sigue Pending.
- **Decisión:** D-F09-4 (Roderich, 2026-10-17): **sí se aplica un plan pendiente por voz**, con las condiciones de la matriz BE `docs/evaluation/F01_F09_MATRIZ_OPERATIVA.md` (`main` `e4b9c29`).

## 1. Qué se construyó

| Pieza | Qué hace |
|---|---|
| `lib/voice_draft/catalog/voice_catalog.dart` | `PendingPlan` y `PendingPlanItem`, con producto, dosis y cantidad requerida por línea. `plansFor(chaco, campaña)` devuelve sólo los planes de ese chaco **y** esa campaña |
| `lib/voice_draft/application/voice_application_draft.dart` | Campo `plan` (null = aplicación libre). Cada línea tiene **planeado** (inmutable), **real** y **diferencia**. Bloquean: un plan ambiguo o faltante, un plan de otro chaco o de otra campaña y un producto que no está en el plan. `toDomain()` lleva `planId`, la dosis del plan y la teórica (área × dosis), como el formulario |
| `lib/voice_draft/application/application_interpreter.dart` | «Aplicar la planificación del chaco Sur» resuelve el chaco y **ofrece** sus planes pendientes, **sin elegir ninguno, aunque haya uno solo**. Sin chaco, o sin planes, lo dice y bloquea; la frase no se vuelve sola una aplicación libre. `selectPlan` sólo acepta un plan de `plansFor`; las líneas son las del plan, con la real igual a la requerida. Cambiar de chaco quita el plan y ofrece los del nuevo; `clearPlan` vuelve a la aplicación libre. «De Bellator en realidad usamos diez litros» corrige sólo la real de esa línea |
| `lib/presentation/voice/voice_draft_gateway.dart` | Lee los planes con `plans()` y `planForApplication()`, las mismas lecturas que Planificación y «Aplicar este plan», y sólo para los chacos que se ofrecen en la modalidad. **No escribe**; la confirmación es `confirmApplication()`, una vez |
| `lib/presentation/voice/voice_application_draft_screen.dart` | Sección «Plan pendiente» (`voz-plan`): selector explícito (`voz-plan-elegir`) y «Quitar el plan (aplicación libre)» (`voz-plan-quitar`). En cada línea, «Planeado X · diferencia ±Y» (`voz-planeado-<n>`). Sin plan pedido, si el chaco tiene planes se ofrecen como opción y no bloquean |

**Sin cambios** en `agro_repository.dart`, `application_form_screen.dart`, `app.dart` ni `app_shell.dart`.

## 2. Condiciones de D-F09-4 y requisitos de EVO-018

| Condición | Cómo se cumple | Prueba |
|---|---|---|
| Selección explícita, por el flujo existente | El plan se elige tocando una opción; la voz sólo lo pide | «con varios planes…», «con un solo plan tampoco se elige solo», pantalla «pedir el plan no elige ninguno…» |
| Sólo planes pendientes de la campaña y el chaco elegidos (EVO-018-REQ-001) | `plans()` sólo devuelve pendientes; el gateway y `plansFor` filtran por campaña activa y chaco; `selectPlan` rechaza uno de fuera | «un plan de otro chaco…», «un plan de otra campaña…», «el catálogo ofrece sólo planes pendientes de la campaña activa» |
| Nunca elegir solo entre varios (REQ-002) | El campo queda ambiguo con todas las opciones | «con varios planes del chaco se ofrecen todos y no se elige ninguno» |
| Nada cambia en el plan, el stock ni FIFO antes de confirmar (REQ-007) | El borrador no escribe; las tablas se comparan enteras antes y después | «dictar, elegir el plan y cancelar o liberar no cambia nada», pantalla «…elegirlo y confirmar…» (antes de confirmar) |
| Planeado, real, diferencia y stock posterior (REQ-003) | Por línea; el stock posterior es el del borrador de aplicación | «al seleccionar…», «corregir por voz…», «una real menor…» |
| Correcciones por voz y a mano (REQ-004) | `mergeField`: lo manual no lo cambia un dictado tardío | «lo corregido a mano no lo cambia un dictado tardío», ««De Bellator en realidad usamos diez litros»…» |
| Una sola confirmación con `confirmApplication()` (REQ-006) | Controlador con confirmación única; el repositorio rechaza un plan ya aplicado dentro de la transacción | «doble confirmación…» |
| Plan usado por otra acción: conflicto y sin aplicación libre automática | `confirmApplication()` falla, no se escribe nada y el borrador sigue abierto con el error | «plan ya aplicado antes de confirmar…» |
| Stock cambiado entre la vista y la confirmación | `confirmApplication()` lo rechaza dentro de la transacción | «stock consumido entre la vista y la confirmación…» |
| La aplicación libre se conserva | Sin elegir plan, la aplicación no lleva `planId` y el plan sigue pendiente | pantalla «una aplicación libre en un chaco con plan no lo usa si no se elige», «quitar el plan vuelve a una aplicación libre» |
| Equivalencia con el flujo manual (REQ «atomicidad/FIFO/costo») | Misma escritura que el formulario abierto desde «Aplicar este plan» | «mismo resultado que el formulario abierto desde «Aplicar este plan»», que compara `applications`, `application_items`, `application_consumptions`, `application_plans`, `application_plan_items`, `inventory_movements` y `account_transactions` sin marcas de tiempo ni UUID |
| Modalidad (F04) | SHARED ofrece los planes de cada chaco. F04 no deja pasar a PERSONAL con planes ajenos pendientes, y en PERSONAL sólo se ofrece el chaco del titular | «SHARED ofrece…», «PERSONAL ofrece sólo el chaco y los planes del titular» |

Pruebas: `test/voice_plan_application_draft_test.dart` (nuevo) y `test/voice_draft/voice_application_draft_screen_test.dart` (grupo «plan pendiente (D-F09-4)»). En `test/voice_application_draft_test.dart`, la prueba que esperaba «no cambia nada» ahora espera que se pida elegir el plan.

## 3. Resultados sobre `8d94e68da4c0db14a7aa80e429c75f52e4d922c1`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (249 archivos, 0 cambiados) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/voice_plan_application_draft_test.dart` | 23 pasan |
| `flutter test` (suite completa) | **1428 pasan, 2 omitidas, 0 fallos** |

**Convivencia con MOB #110** (campaña por fecha efectiva, sin integrar). Es una comprobación local, no una verificación de #110. Sobre una rama temporal sin push, se fusionó `8d94e68` con el HEAD de #110, `0bc68483ca3366a1a853c582fa75e1f4df7adbf7`, sin conflictos. Allí, `flutter test test/voice_plan_application_draft_test.dart test/voice_application_draft_test.dart test/voice_draft test/voice test/voice_draft_flow_test.dart` dio **288 pasan**. La rama temporal se borró. No se ejecutó la suite completa sobre esa fusión.

## 4. Límites declarados

- **Sin prueba en el teléfono.** Todo se probó con el puerto de voz fake. El ensayo físico (V15–V19 de `docs/evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md`) lo hace A, con turno, y hasta entonces el reconocimiento queda `NOT_MEASURED`.
- **Un plan, aunque sea uno, no se preselecciona.** EVO-018 dice «si hay uno, se propone». Aquí se muestra como única opción y hay que tocarla, que es lo que pide D-F09-4.
- **Si el plan lo aplicó otra acción**, el borrador queda abierto con el error, no sólo para revisión. La persona puede quitar el plan y registrar una aplicación libre, pero eso nunca ocurre solo.
- **Área del plan:** la voz usa el área exacta del plan en m². El formulario la muestra en hectáreas con 3 decimales, de modo que, en un plan con un área que no es múltiplo de 10 m², los dos caminos podrían no coincidir. La equivalencia se probó con 10 000 m².
  - *Corrección del 2026-10-17 (C), posterior a este registro:* el formulario conserva ahora el área exacta del plan y la del chaco (4 decimales de hectárea) y calcula la teórica en enteros, como la voz. La comparación de los dos recorridos con un plan de 10001 m² está en `docs/evidence/F09-VOZ-10_area_exacta_plan_formulario.md`. El texto de arriba se conserva tal como se verificó sobre `8d94e68`.
- **Lectura de planes:** `plans()` con su límite por defecto (400 líneas), igual que la pantalla de Planificación.
- **«Dictar con voz» no se ofrece en el formulario abierto desde «Aplicar este plan»** (`application_form_screen.dart` no se tocó). Se entra por `/aplicaciones/voz`.
- **Fechas:** la aplicación usa «ahora», como el formulario. Con MOB #110 (campaña por fecha efectiva), las pruebas usan fechas dentro de la campaña activa.
