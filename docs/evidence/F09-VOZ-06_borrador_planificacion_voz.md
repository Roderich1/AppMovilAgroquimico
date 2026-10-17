# F09-VOZ-06 — Borrador seguro de planificación por voz (#14)

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz).
- **Rama:** `feat/f09-borrador-plan`, apilada sobre `feat/f09-borrador-compra` (PR #100) y `feat/f09-captura-voz` (PR #99). **Commit verificado:** `fd9ee7d1542b0e5650da0975c57926371aa1702f`.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #14 y #16. GATE-F09 (#17) sigue Pending.

## 1. Qué se construyó

Usa el mismo patrón de #16 que la compra (`VoiceDraftController`, las piezas comunes de `voice_draft_widgets.dart` y el lector de segmentos cerrados).

| Pieza | Qué hace |
|---|---|
| `lib/voice_draft/plan/voice_plan_draft.dart` | Chaco, campaña activa (propuesta), área (propuesta desde el chaco) y productos con dosis por hectárea. Bloqueos visibles. `toDomain()` da los argumentos de `addPlanMulti` |
| `lib/voice_draft/plan/plan_interpreter.dart` | «planificar el chaco Sur», «en dos hectáreas», «dos litros por hectárea de Bellator» o «Bellator a dos litros por hectárea». Nombrar otra vez un producto corrige su dosis |
| `VoiceDraftGateway.planCatalog / confirmPlan` | Chacos, productos y campaña activa; en PERSONAL **sólo los chacos del titular**. Crea con `addPlanMulti`, el caso de uso del formulario, que vuelve a comprobar PERSONAL y campaña |
| `lib/presentation/voice/voice_plan_draft_screen.dart` | Revisión, corrección, «Necesita …» calculado y «Crear plan» con un toque |

## 2. Criterios de #14 y pruebas

| Criterio | Prueba (`test/voice_planning_draft_test.dart` y `test/voice_draft/voice_plan_draft_screen_test.dart`) |
|---|---|
| Dictado válido → borrador editable; no se crea plan ni cambia inventario o necesidades | «el borrador queda listo…»; «crear el plan no cambia inventario ni necesidades» (volcado de todas las tablas salvo las del plan) |
| Chaco, campaña, producto o cantidad ausente o con varios candidatos → marcado y bloqueado | «un chaco con varias coincidencias queda ambiguo y bloquea», «un producto que no está en el catálogo…», «sin dosis no hay línea…», «sin campaña activa…», «litros por hectárea de un producto en kilos bloquea» |
| Confirmar una vez → exactamente un plan por el flujo existente; un segundo toque no crea otro | «confirmar dos veces crea un solo plan»; pantalla «dos toques crean un solo plan»; «mismo plan que el formulario manual» (filas de `application_plans` y `application_plan_items` iguales a `addPlanMulti` manual) |
| La edición manual no la sobrescribe un resultado tardío | «la dosis corregida a mano…», «el área corregida a mano…»; pantalla «la dosis corregida a mano no la cambia la voz» |
| Cancelar → ningún plan ni efecto | «cancelar o liberar no crea plan ni toca inventario»; pantalla «cancelar no crea plan y suelta el micrófono» |
| PERSONAL / titular | «PERSONAL: sólo se ofrecen los chacos del titular» |

## 3. Resultados sobre `fd9ee7d1542b0e5650da0975c57926371aa1702f`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/voice_planning_draft_test.dart test/voice_draft/voice_plan_draft_screen_test.dart` | 20 pasan (17 + 3) |
| `flutter test` (suite completa) | **1327 pasan, 2 omitidas, 0 fallos** |

## 4. Alcance y límites declarados

- **Área y dosis por hectárea, no «cantidades y unidades» sueltas.** El plan del dominio es área + dosis por hectárea, y la cantidad necesaria se calcula. El texto de #14 dice «cantidades y unidades»; alinearlo es la decisión pendiente **D-F09-3**.
- **Sin dictar:** la fecha planificada y las notas (el formulario tampoco las pide).
- **Sin «Crear nuevo»:** un chaco o un producto que no está en el catálogo bloquea (D-F09-2).
- **«el chaco X»** se compara con y sin la palabra «chaco»; sólo vale una coincidencia exacta única.
- **Sin conectar:** la pantalla no está en ninguna ruta; la conecta A después de F04.
- **Motor:** el fake prueba la lógica; el reconocimiento real exige dictado real en el teléfono.

## 5. Revisiones posteriores (2026-10-17)

Lo de §1 a §4 describe `fd9ee7d`, con la suite completa de 1327 pruebas. Después llegaron estos cambios:

| Commit | Qué |
|---|---|
| `a55d240` | Piezas comunes de pantalla (#16), sin cambio de comportamiento. Las frases comunes de los intérpretes (`002c5d8`) llegaron después, en #104 |
| `84f0480` | Merge de las correcciones de la revisión de #99 y #100 |
| `ab7e6ec` | Mismo patrón que la compra: `PopScope` y bloqueo si el área o una dosis visibles difieren del borrador. CI del PR: pass (run 39040063127), **1332 pasan, 3 omitidas** |
| `eba7342` | **M-1** (revisión de A): el área propuesta se muestra con 4 decimales de hectárea. Con 2, un chaco de 12 345 m² se veía «1,23», no coincidía y bloqueaba «Crear plan». Prueba «un área que no es múltiplo de 100 m² se ve exacta y no bloquea»: con 2 decimales falla (`'1,23'` en vez de `'1,2345'`) |

**Resultado sobre `eba7342ddb84e53e7c58f7d97a50712dba6b4f38`:** `flutter test test/voice_draft/voice_plan_draft_screen_test.dart`, **5 pasan**. La suite completa la ejecuta la CI de esta cabeza.
