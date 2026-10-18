# F04 — No activar una sucesora cuyo inicio no llegó mientras otra campaña esté activa (#125)

- **Origen:** Live. **Fecha real:** 2026-10-18 (America/La_Paz). Sesión C de Claude Code, por la decisión técnica delegada de Roderich Rendón del 2026-10-18 (MOB #125).
- **Base:** Mobile `main` `b1aa42d0cb7246949170b91f1bac3109065d2dfe` (integra #123 y #124).
- **Rama:** `fix/f04-activacion-anticipada`. **Commit verificado:** `53ddaea1a884d64026872cde140c44247b82528d`.
- **Entorno:** pruebas de **HOST** (Windows 11, zona del sistema −04:00; Flutter 3.47.2). **No es una prueba DEVICE.** El retest físico acotado (caso R-10 del protocolo de A) lo hace A sobre la base que integre #124 y #125.
- **Trazabilidad:** RF-03, RF-17; RN-15, RN-16; CU-19; DAT-02. Refs #28 (GATE-F04 sigue **Pending**) y #124.
- **Antecedente:** límite declarado en `F04_FECHA_EFECTIVA_Y_CIERRE.md` §5 (#124, `968a1d8`): «Cerrar y activar» una sucesora futura dejaba la anterior cerrada con un fin futuro. Esa evidencia conserva su texto, con una nota fechada.

## 1. Qué fallaba (sobre `b1aa42d`)

`activateCampaign(id, closeCurrent: true)` sólo cambiaba estados: la anterior pasaba a CLOSED con el fin que ya había fijado el alta de la sucesora (el día previo al inicio de ésta) y la sucesora pasaba a ACTIVE aunque su inicio fuera futuro. Si la sucesora empezaba dentro de 10 días, el día de hoy quedaba dentro de una campaña **cerrada**: ninguna campaña operable para compras ni aplicaciones de hoy, y la pantalla ofrecía «Cerrar y activar» como salida válida. #124 corrigió `closeCampaign`, no este camino.

## 2. Qué cambia

**Repositorio** (`agro_repository.dart`, `activateCampaign`, en la misma transacción):

- Con **otra campaña ACTIVE**, si el día local de inicio de la campaña a activar es **posterior a hoy**, se lanza `CampaignActivationNotYetException` con la fecha desde la que se podrá activar: «“X” empieza el dd/mm/aaaa, después de hoy. Mientras “Y” esté activa no se puede activar cerrándola: el día de hoy quedaría dentro de una campaña cerrada. Se podrá activar desde el dd/mm/aaaa; hasta entonces queda planificada.» Vale **con y sin** `closeCurrent`, y se decide **antes** del conflicto genérico (`CampaignConflictException`), de modo que la pantalla no llega a ofrecer «Cerrar y activar». No cambia ninguna tabla, estado, fecha, vínculo ni cola.
- El **día de inicio cuenta como llegado** (inclusivo): una sucesora que empieza hoy se activa; la anterior termina ayer (fin que fijó el alta) y hoy queda dentro de la nueva activa.
- **Sin otra campaña activa no aplica:** una planificada con inicio futuro se puede activar (la excepción ya documentada: campaña ACTIVE cuyo inicio no llegó) y sigue cerrándose sólo en su propio día de inicio. La excepción no se amplía ni se quita, y ninguna base existente se altera automáticamente.
- **Llegar la fecha no salta las guardas existentes:** `_endOpenCampaignBefore`, los solapes y la revalidación del vínculo central siguen igual.

**Pantalla** (`catalogs_screen.dart`, pestaña «Campañas»): la fila de una planificada cuyo inicio no llegó, mientras otra esté activa, añade «Se podrá activar desde el dd/mm/aaaa». «Activar» sigue en el menú: al tocarlo se muestra el mensaje del repositorio con esa fecha y **no** aparece «Cerrar y activar». Una pantalla desactualizada o una llamada directa quedan protegidas por el repositorio.

**Sin cambios:** reloj, períodos, fechas de operaciones, historia, outbox, `closeCampaign` (#124), precisión de área y confirmación única (#115), contención/retención/conciliación (#116). Sin migración. Nada de voz.

## 3. Pruebas

| Archivo | Casos |
|---|---|
| `test/f04_activation_not_yet_test.dart` (nuevo; fechas relativas a hoy) | **Antes del inicio** (hoy + 10): rechazo con y sin `closeCurrent`, con la fecha en el mensaje; no es `CampaignConflictException`; **volcado completo igual**; la actual sigue ACTIVE y hoy opera en ella (compra de hoy aceptada). **Mañana a medianoche local**: rechazo. **Día de inicio, inclusive**: se activa; la anterior CLOSED con fin ayer; hoy pertenece a la nueva y opera. **Inicio pasado**: se admite como siempre. **Sin otra activa**: cerrar la actual con su fin efectivo y activar la futura; su cierre sólo en su inicio. **Guardas existentes**: con la actual abierta y una compra de hoy, una heredada que empieza hoy no se activa («tiene operaciones del…»), volcado igual |
| `test/f04_campaign_dialogs_ui_test.dart` (dos pruebas nuevas) | Sucesora a 30 días: la fila dice «Se podrá activar desde el dd/mm/aaaa»; «Activar» muestra ese mensaje, **no** aparece «Cerrar y activar», las campañas no cambian (ACTIVE / PLANNED). Sucesora que empieza hoy: «Activar» → «Cerrar y activar» → la anterior CLOSED con fin ayer y la nueva ACTIVE con inicio hoy |

**Fixtures ajustados**, con su propósito conservado:
- `f04_campaign_effective_date_test.dart`, «el alta en orden fija el fin de la anterior…»: activaba «Primavera» (01/12, futuro) cerrando la actual; ahora «Primavera» empieza el 01/10 y «Otoño» el 10/10, ya pasados. Sigue probando que activar no borra el fin fijado por el alta de la siguiente.
- `f04_campaign_effective_date_test.dart`, «la excepción de la campaña activa que no empezó…» (de #124): activaba «Futura» cerrando «Invierno» y anotaba el límite; ahora espera el rechazo de #125, cierra «Invierno» con su fin efectivo y activa «Futura» sin otra activa, y sigue comprobando que esa campaña cierra sólo en su inicio.
- `v5_domain_test.dart`, «catálogo, stock y deuda permanecen al cambiar campaña»: activaba «Invierno» (mañana) cerrando «Primavera»; ahora cierra «Primavera» con `closeCampaign` (hoy) y activa «Invierno» sin otra activa. Sigue probando que catálogo, stock y deuda sobreviven al cambio.

**El código anterior falla.** Con `agro_repository.dart` y `catalogs_screen.dart` repuestos desde `b1aa42d` sobre el árbol de trabajo (y, para que compile, `CampaignActivationNotYetException` sustituida por `BusinessRuleException` en una copia temporal del archivo nuevo): en el archivo nuevo **fallan los dos casos de rechazo** («antes del inicio: se rechaza con y sin closeCurrent…» y «mañana a medianoche local también es futuro…»: la activación se aceptaba) y pasan los tres que no dependen de la regla nueva (inicio pasado, sin otra activa, guardas existentes); en `f04_campaign_dialogs_ui_test.dart` falla «una sucesora futura no se activa desde Catálogos…» (aparecía «Cerrar y activar») y pasa «una sucesora que empieza hoy…».

## 4. Resultados sobre `53ddaea1a884d64026872cde140c44247b82528d`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test --concurrency=3` de los 12 archivos afectados (`f04_activation_not_yet_test`, `f04_campaign_dialogs_ui_test`, `f04_campaign_effective_date_test`, `v5_domain_test`, `campaign_lifecycle_test`, `campaign_lifecycle_ui_test`, `e2e_v5_test`, `v4_repository_test`, `f04_effective_date_form_test`, `f04_c2_campaign_period_test`, `f04_repository_guards_test`, `regression_widget_test`) | **115 pasan, 1 omitida, 0 fallos** |
| `flutter test` (suite completa) | **1522 pasan, 3 omitidas, 0 fallos** (`--concurrency=4`) |

CI del HEAD del PR: en el PR. La CI repite `f04_activation_not_yet_test.dart` en `America/La_Paz`.

## 5. Límites declarados

- **HOST, no DEVICE.** El caso R-10 (R2 activa, intentar activar R3 con inicio T+5 desde Catálogos: rechazo con la fecha, tablas idénticas, R2 ACTIVE y R3 PLANNED) lo repite A.
- **La comparación de días usa el reloj del teléfono** (`DateTime.now()`), como el resto del calendario: un reloj mal puesto no se detecta.
- **«Activar» sigue visible** para la planificada futura: la explicación llega al tocarlo (y en la fila). Se eligió no esconderlo para que la persona vea por qué no puede, y porque el repositorio protege igual una pantalla desactualizada.
- **Un hueco sin campaña** sigue siendo posible por otros caminos ya existentes (por ejemplo, cerrar la actual con fin hoy sin activar la siguiente hasta su inicio); esta tarea sólo impide crearlo cerrando la actual anticipadamente.
- GATE-F04 (#28) sigue **Pending**: lo decide Roderich. D-F04-C1 sigue como límite de RF-03.
