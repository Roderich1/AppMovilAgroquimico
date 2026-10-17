# F09-VOZ-08 — Patrón común de vista previa, edición, confirmación y callbacks tardíos (#16)

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz).
- **Commit verificado:** `04d6b361881914a06ff34f8baf8cc70a4b59d566`, rama `feat/f09-borrador-aplicacion` (la última de la pila #99 → #100 → #101 → este PR).
- **Entorno:** pruebas de **host**. **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #16, con #11, #14 y #15. GATE-F09 (#17) sigue Pending.

## 1. Un solo patrón para las tres operaciones

| Pieza común | Archivo | Compra | Planificación | Aplicación |
|---|---|---|---|---|
| Estados por campo (resuelto, ambiguo, faltante, inválido) y origen (voz, manual, propuesto) | `lib/voice_draft/core/draft_field.dart` | ✓ | ✓ | ✓ |
| La edición manual gana a la voz tardía | `DraftField.mergeVoice` y `mergeField` | ✓ | ✓ | ✓ |
| Una sola confirmación, sin escritura durante ni después | `lib/voice_draft/core/voice_draft_controller.dart` | `confirmPurchase` | `addPlanMulti` | `confirmApplication` |
| Fallo sin efectos; el borrador queda editable | ídem | ✓ | ✓ | ✓ (stock cambiado) |
| Cancelar o liberar descarta y suelta el micrófono | controlador + pantalla | ✓ | ✓ | ✓ |
| Provisional (panel de escucha) frente a aplicado («Ya aplicado al borrador») | `VoiceListeningPanel`, `VoiceSegmentFeed` y `VoiceAppliedPanel` | ✓ | ✓ | ✓ |
| Mismo aviso, estado de campo, selector de catálogo y bloqueos | `lib/presentation/voice/voice_draft_widgets.dart` | ✓ | ✓ | ✓ |
| Mismas frases: chaco, área y resolución | `lib/voice_draft/interpretation/phrases.dart` | — | ✓ | ✓ |
| Alternativa manual equivalente | `onOpenManualForm` en cada pantalla (la conecta A) y el mismo caso de uso del formulario | ✓ | ✓ | ✓ |
| Guardas: el borrador no ve la base ni llama a casos de uso que escriben | `test/voice_draft/voice_draft_architecture_guard_test.dart` | ✓ | ✓ | ✓ |

## 2. Criterios de #16 y pruebas

| Criterio | Prueba |
|---|---|
| Edición manual + callback tardío → se conserva | `test/voice_draft_flow_test.dart` «la edición manual gana…»; las tres pantallas, «… corregida a mano no la cambia …» |
| Provisional y refinado distinguibles | Pantalla de compra «lo provisional se ve aparte y no cambia el borrador» |
| Cancelar antes o después de resultados → nada persiste | `test/voice/voice_draft_no_side_effects_test.dart` (tres operaciones × cancelar, liberar y resultado tras cancelar, con volcado de todas las tablas); pantallas «cancelar…» |
| Una sola escritura tras una única confirmación | `voice_draft_flow_test.dart` «doble toque…» y «un callback de voz durante la escritura no entra»; base real en las tres; pantallas «dos toques…» |
| Compra, planificación y aplicación con el mismo patrón y entrada manual equivalente | Tabla de §1; equivalencia de filas con el flujo manual en las tres |

## 3. Resultados sobre `04d6b361881914a06ff34f8baf8cc70a4b59d566`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (239 archivos) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/voice_draft_flow_test.dart` | 10 pasan (patrón común) |
| Borradores: `test/voice_draft/`, `test/voice_purchase_draft_test.dart`, `test/voice_planning_draft_test.dart` y `test/voice_application_draft_test.dart` | 88 pasan (texto 17, guardas 7, compra 18 + 6, planificación 17 + 3, aplicación 17 + 3) |
| `flutter test test/voice/voice_draft_no_side_effects_test.dart` | 9 pasan (3 operaciones × 3 formas de terminar sin confirmar) |
| `flutter test` (suite completa) | **1356 pasan, 2 omitidas, 0 fallos** |

## 4. Límites

- El patrón está construido y probado en host. **Las pantallas no están conectadas** a rutas ni formularios: esa conexión la integra A en serie, después de F04. Hasta entonces, la «entrada manual equivalente» existe —los formularios no cambian—, pero el enlace entre ambas pantallas no.
- **Reconocimiento real:** exige dictado real en un teléfono (ensayo físico con turno de A).
- **Decisiones pendientes que acotan el alcance:** D-F09-2 (sin «Crear nuevo»), D-F09-3 (plan = área + dosis) y D-F09-4 (sin aplicar un plan por voz).

- **Límite de M-2 (declarado, sin cambio de código):** si el nombre de un producto termina en número y la cantidad se dice justo después («urea cuarenta y seis dos kilos»), los dos números quedan seguidos y la cantidad se marca inválida: hay que escribirla o dictarla de otra forma («dos kilos de urea cuarenta y seis»). Falla del lado seguro: no se interpreta una cantidad equivocada.
