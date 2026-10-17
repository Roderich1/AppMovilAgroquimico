# F09-VOZ-07 — Borrador de aplicación multiproducto por voz (#15)

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz).
- **Rama:** `feat/f09-borrador-aplicacion`, apilada sobre `feat/f09-borrador-plan` (PR #101), `feat/f09-borrador-compra` (PR #100) y `feat/f09-captura-voz` (PR #99). **Commit verificado:** `04d6b361881914a06ff34f8baf8cc70a4b59d566`.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #15, #16 y #17. GATE-F09 (#17) sigue Pending.

## 1. Qué se construyó

| Pieza | Qué hace |
|---|---|
| `lib/voice_draft/application/voice_application_draft.dart` | Chaco, persona que aplica (el dueño del chaco, como en el formulario), área tratada propuesta desde el chaco, una línea por producto con su cantidad real, y el **stock proyectado** del dueño: leído, nunca descontado. `toDomain()` da el mismo `ApplicationDraft` que el formulario sin plan |
| `lib/voice_draft/application/application_interpreter.dart` | «apliqué dos litros de Bellator y tres kilos de Expansive en el chaco Sur», «en media hectárea». Nombrar otra vez un producto corrige su cantidad. «… por hectárea» es una dosis, no una cantidad. «aplicar la planificación…» no se atiende (D-F09-4) |
| `VoiceDraftGateway.applicationCatalog / availableStock / confirmApplication` | Mismo filtro que el formulario: personas de `peopleFor(applicator)` y sólo chacos cuyo dueño puede aplicar. Stock por `availableProductsForOwner`. Registro con `confirmApplication()` |
| `lib/presentation/voice/voice_application_draft_screen.dart` | Revisión y corrección, con «Stock actual … · quedaría …» por línea y «Registrar aplicación» con un toque. Una lectura de stock que llega tarde para otro chaco se descarta |

## 2. Criterios de #15 y pruebas

| Criterio | Prueba (`test/voice_application_draft_test.dart`, `test/voice_draft/voice_application_draft_screen_test.dart` y `test/voice/voice_draft_no_side_effects_test.dart`) |
|---|---|
| Varios productos → una línea editable por producto; no cambia stock, FIFO ni plan | «varias líneas; el chaco fija quién aplica…»; «cancelar o liberar no crea aplicación ni toca stock ni plan» (volcado de todas las tablas) |
| Producto, cantidad o unidad ambigua → visible y bloquea | «un producto ambiguo queda visible y bloquea», «kilos de un producto en litros bloquea», «un chaco cuyo dueño no puede aplicar bloquea» |
| Edición manual no sobrescrita por voz tardía | «la cantidad corregida a mano…» (dominio y pantalla) |
| Confirmación explícita → `confirmApplication()` una sola vez, resultado idéntico al manual | «dos confirmaciones: una sola aplicación y un solo descuento»; «mismo resultado que el formulario manual» (filas de `applications`, `application_items`, `application_consumptions`, `inventory_movements` y `account_transactions` iguales) |
| Cancelar → sin aplicación ni cambios en plan o inventario | «cancelar o liberar…»; GATE «cancelar / liberar / resultado tras cancelar» en las tres operaciones |
| Proyección de stock sin escritura previa | «con el stock leído: proyección sin escribir y bloqueo si falta»; pantalla «quedaría 3 L» |
| Stock cambiado entre la vista previa y la confirmación | «stock cambiado entre la vista previa y la confirmación»: la escritura falla sin efectos y el borrador queda editable |
| PERSONAL / titular | «PERSONAL: sólo los chacos del titular y nadie más aplica» |
| Regresión del flujo manual | `test/repository_test.dart` y `test/plan_lifecycle_test.dart` dentro de la suite completa, sin cambios |

## 3. Resultados sobre `04d6b361881914a06ff34f8baf8cc70a4b59d566`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (239 archivos) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/voice_application_draft_test.dart test/voice_draft/voice_application_draft_screen_test.dart test/voice/voice_draft_no_side_effects_test.dart` | 29 pasan (17 + 3 + 9) |
| `flutter test` (suite completa) | **1356 pasan, 2 omitidas, 0 fallos** |

## 4. Alcance reducido y límites declarados

- **Aplicar un plan pendiente por voz (EVO-018): no se entrega.** La voz registra una aplicación libre. «aplicar la planificación…» avisa y no cambia nada. Es la decisión pendiente **D-F09-4**; si se exige, es una brecha de #15.
- **Dosis y cantidad teórica:** no se dictan. Como en el formulario con la dosis vacía, la teórica es 0.
- **Persona:** no se dicta; la fija el chaco, como en el formulario.
- **Notas y fecha:** no se dictan; la fecha es «ahora», como en el formulario.
- **Sin «Crear nuevo»** (D-F09-2).
- **Sin conectar:** la conecta A después de F04.
- **Motor:** el fake prueba la lógica; el reconocimiento real exige dictado real.

## 5. Correcciones tras la revisión de #100 (sobre `2233e77a959cc1eb7c15fca863323788e0437960`)

- **Fecha de la aplicación.** Mismo defecto que B-100-1: el borrador fijaba `appliedAt` al abrirse. Ahora es el instante de la confirmación, con el reloj del gateway (`DateTime.now`, como el formulario al enviar). La prueba de equivalencia usa ese instante.
- **Patrón común:**
  - `PopScope`: durante la escritura no se puede salir; con un borrador empezado, Atrás pregunta antes de descartar. Prueba: «Atrás con una aplicación empezada pregunta y no registra».
  - Bloqueo si el área o una cantidad visibles difieren del borrador.
- **Resultados** (sin suite completa durante la ventana física de A):
  - `flutter analyze`: sin avisos.
  - Pruebas focalizadas de borradores, gate y guardas: **133 pasan**.
