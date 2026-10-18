# F04 — Fecha efectiva editable (#121) y cierre con fin efectivo confirmado (#122)

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz). Sesión C de Claude Code, por la delegación técnica de Roderich Rendón (`CONTINUACION_F09_ENS_01_TRIAGE_2026-10-17.md`, §3 «Política de fechas y cierre» y §6).
- **Base:** Mobile `main` `0cc2ee3f518f715bb008fc6cf50a891068b0d649` (merge documental de #118; `lib`, `test`, `android` y `pubspec` idénticos a `65f7cfc`, la base del ensayo F09-ENS-01).
- **Rama:** `fix/f04-fecha-efectiva-y-cierre`. **Commit verificado:** `9f3e3afee5b9072f853d1cdbb7b02ec1ac186732`.
- **Entorno:** pruebas de **HOST** (Windows 11, zona del sistema −04:00; Flutter 3.47.2). **No es una prueba DEVICE.** La repetición en el teléfono de los casos afectados la hace A después de integrar.
- **Trazabilidad:** RF-03, RF-07, RF-12, RF-17, RF-31; RN-15, RN-16; CU-06, CU-09, CU-19; DAT-02. Refs #28 (GATE-F04 sigue **Pending**) y #41.
- **Antecedente:** `F04_FECHA_EFECTIVA_DEVICE.md` (#118) §1 («los formularios no admiten elegir la fecha») y §4 («cierre con fin ya fijado»). Esa evidencia no se modifica: conserva su dispositivo, su fecha y su SHA.

## 1. Qué fallaba (sobre `0cc2ee3` = `65f7cfc`)

| Issue | Dónde | Qué pasaba |
|---|---|---|
| #121 | `purchase_form_screen.dart`, `application_form_screen.dart` | `purchaseDate` y `appliedAt` eran `DateTime.now()`; no había selector. En el teléfono, E2–E4 hubo que sustituirlos moviendo el calendario, no registrando una fecha pasada |
| #121 | `agro_repository.dart` | Ninguna regla rechazaba una fecha futura: la clasificación por campaña aceptaba cualquier día contenido en la activa |
| #122 | `agro_repository.dart`, `closeCampaign` | Si `end_date` ya existía (alta de la siguiente o «Fijar fin previsto…»), el cierre **no validaba nada** y conservaba ese fin. En el HONOR, una campaña iniciada el 17/10 quedó CLOSED con fin 30/11, futuro |
| #122 | `catalogs_screen.dart` | El diálogo «¿Cerrar…?» omitía el selector de fin cuando ya había fin previsto |

## 2. Qué cambia

### 2.1 Fecha efectiva (#121)

- **Los dos formularios** muestran «Fecha de la compra» / «Fecha de la aplicación» (`purchase-date`, `application-date`): hoy por defecto, con «(hoy)»; «Cambiar» abre el selector de Material con `lastDate: hoy`. Cancelar el selector no toca nada del borrador. Elegir marca el borrador como editado.
- **Representación de la hora cuando sólo se eligió un día** (`campaign_calendar.dart`, `effectiveInstantForDay(day, now)`):
  - si el día es **hoy**, el instante es `now`: la hora real se conoce, como antes;
  - si es **otro día**, la **medianoche local** de ese día. No se inventa una hora que nadie registró.
  - Se guarda en UTC (`toUtc().toIso8601String()`), como todas las fechas. El día civil que se lee de vuelta (`storedLocalDay`) es el elegido, en cualquier zona. En UTC, un 15/08 elegido se guarda como `2026-08-15T00:00:00.000Z`; en La Paz (−04:00), como `2026-08-15T04:00:00.000Z`. La prueba lo comprueba en las dos zonas (la CI repite el archivo en `America/La_Paz`).
    - *Precisión (2026-10-18, revisión de Roderich):* «en cualquier zona» está probado guardando y leyendo en la **misma** zona (UTC o La Paz). Si el teléfono cambia de zona después de guardar, un instante UTC puede leerse como otro día civil; no se afirma lo contrario. No se rediseña el almacenamiento de fechas.
  - Consecuencia declarada: en FIFO, una compra fechada en un día pasado queda **antes** de cualquier compra de ese mismo día con hora real. No se recalcula ningún histórico.
- **Repositorio** (`_ensureEffectiveDateInCampaign`, dentro de la transacción, antes de escribir): una fecha **posterior a hoy** se rechaza con `CampaignDateProblem.future` («es posterior a hoy… No se registró nada»), también en llamadas directas. Después, la clasificación de #110 sin cambios: ninguna / ambigua / planificada / cerrada se rechazan sin escribir; nunca se elige otra campaña en silencio.
- **D-F04-C1 no cambia:** una fecha de un período cerrado se rechaza. No hay circuito de revisión, reapertura ni reasignación; RF-03 sigue parcial en ese punto.

### 2.2 Cierre con fin efectivo (#122)

`closeCampaign(id, {end})` valida **igual haya o no fin previsto**:

| Regla | Mensaje |
|---|---|
| Fin ≥ inicio | «no puede ser anterior al inicio» |
| Fin ≤ hoy; si la campaña todavía no empezó, fin = su día de inicio (excepción ya documentada, **no se amplía**) | «no puede ser posterior al …: los días siguientes quedarían en una campaña cerrada» |
| Ningún registro fechado después del fin: compras, aplicaciones (revertidas incluidas), necesidades declaradas y **sus versiones** (`_lastOperationDay`) | «tiene operaciones del …, posteriores al fin elegido» |
| Sin solapes con otra campaña | «se solapa con …» |

Si pasa, `status = CLOSED` y `end_date = fin efectivo` en la **misma transacción**, y `CentralBindingStore.revalidateCampaignPeriod` se ejecuta ahí mismo (D-F04-C2). Un rechazo no escribe nada. Sin `end`, el fin efectivo es hoy, como antes.

**Diálogo** («Campañas» › «Cerrar»): si existe un fin previsto, lo muestra aparte («Fin previsto: dd/mm/aaaa. El fin efectivo que confirme abajo lo sustituye.», `campaign-close-planned-end`) y pide **siempre** «Termina el» (`campaign-close-end`), hoy por defecto, con el selector limitado a hoy. Nada se acorta en silencio: la persona ve los dos y confirma.

## 3. Pruebas

| Archivo | Casos |
|---|---|
| `test/f04_effective_date_form_test.dart` (nuevo; app real, modalidad propia) | **Compra:** hoy por defecto; elegir el día 1 del mes (o del anterior si hoy es 1) con el selector real → se guarda ese día, a medianoche local, en la campaña activa, con el resto del borrador intacto. Cancelar el selector conserva borrador y fecha, sin escribir. Un día de la campaña cerrada → mensaje «campaña cerrada», el borrador sigue en pantalla y **todas las tablas iguales**. **Aplicación:** día pasado a medianoche local, área exacta 10 000 m² (#115) y **una sola aplicación con dos toques**; cancelar conserva el borrador; hoy fuera de toda campaña → «ninguna campaña», tablas iguales |
| `test/f04_campaign_effective_date_test.dart` (ampliado) | `effectiveInstantForDay`: hoy es `now`; otro día, 00:00 local; cadena UTC declarada en UTC y en La Paz; centinela del paso regional. Fecha futura (mañana, y la medianoche local de mañana) rechazada en compra y aplicación sin escribir. Día pasado multiproducto: compra y aplicación en su campaña, instante exacto, conservado tras reabrir. Fronteras a medianoche local: 01/07 entra en «Invierno»; 30/06 se rechaza como «Verano» cerrada. **#122:** fin previsto futuro → cerrar con ese fin se rechaza y cerrar sin fin toma hoy; con fin previsto, antes del inicio y registros fuera se rechazan, igual al previsto ya pasado se acepta; el fin efectivo no solapa la siguiente; la campaña que no empezó cierra sólo en su día de inicio, también con fin previsto |
| `test/f04_campaign_dialogs_ui_test.dart` (actualizado) | Con fin fijado por el alta de la siguiente: el diálogo muestra «Fin previsto» y «Termina el» (hoy), y cierra con hoy; la siguiente no cambia. El caso del teléfono: campaña iniciada con fin previsto futuro → cierra con hoy. Cancelar no cambia ninguna campaña. Las tres pruebas anteriores se conservan (campaña abierta; campaña que no empezó) |

**Fixtures ajustados**, con su propósito conservado:
- `f04_campaign_effective_date_test.dart`, «límites inclusivos en día local»: la campaña siguiente empezaba el 01/12 y la compra del último minuto era del **30/11, futura**; ahora empieza el 01/10 y la compra es del 30/09 23:59. Sigue probando que los dos extremos del día local son inclusivos.
- `f04_c2_campaign_period_test.dart`, «rechazos: … cerrada»: la necesidad declarada era del **20/11, futura**, y el cierre con fin previsto no validaba; ahora es del 20/09 y la prueba comprueba además que el cierre fija hoy como fin efectivo, no el 15/12 previsto. Sigue probando que una campaña cerrada no cambia su período.

**El código anterior falla.** Con los cinco archivos de `lib` repuestos desde `0cc2ee3` sobre el árbol de trabajo:
- `f04_effective_date_form_test.dart`: **6 de 6 fallan** (no existe el campo de fecha).
- `f04_campaign_dialogs_ui_test.dart`: fallan las dos pruebas de #122 (no hay «Fin previsto» ni «Termina el» con fin fijado).
- `f04_campaign_effective_date_test.dart`: no compila (`effectiveInstantForDay` y `CampaignDateProblem.future` no existían). Para #122 se ejecutó una copia temporal sólo con ese grupo, que usa la API preexistente: **4 de 4 fallan**: `closeCampaign` con fin previsto no lanzaba «no puede ser posterior», «10/08/2026» ni «se solapa», y conservaba el fin previsto.

## 4. Resultados sobre `9f3e3afee5b9072f853d1cdbb7b02ec1ac186732`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (259 archivos, 0 cambiados) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test --concurrency=2` de los 11 archivos afectados (`f04_effective_date_form_test`, `f04_campaign_dialogs_ui_test`, `f04_campaign_effective_date_test`, `campaign_lifecycle_test`, `campaign_lifecycle_ui_test`, `f04_c2_campaign_period_test`, `regression_widget_test`, `plan_application_area_precision_test`, `f04_repository_guards_test`, `personal_mode_flows_test`, `date_display_test`) | **121 pasan, 2 omitidas, 0 fallos** |
| `flutter test` (suite completa) | **1515 pasan, 3 omitidas, 0 fallos** (`--concurrency=4`; en `main` `0cc2ee3` la CI daba 1498 pasan y 4 omitidas) |

CI del HEAD del PR: en el PR. La CI repite `f04_campaign_effective_date_test.dart` y `f04_effective_date_form_test.dart` en `America/La_Paz` (`.github/workflows/flutter-ci.yml`).

## 5. Límites declarados

- **HOST, no DEVICE.** La repetición física (fecha elegida, fronteras, rechazo de cerrada/ninguna, multiproducto, reapertura y cierre con fin previsto) la hace A en una copia aislada propia.
- **«Cerrar y activar» una sucesora futura** (`activateCampaign(closeCurrent: true)`) deja la anterior cerrada con el fin que fijó el alta de la sucesora, que puede ser futuro. No es el camino de `closeCampaign` y no se cambia aquí; la prueba «la excepción de la campaña activa que no empezó…» lo deja anotado.
  - *Actualización (2026-10-18):* corregido en MOB #125 (`F04_ACTIVACION_ANTICIPADA.md`): con otra campaña activa, una sucesora cuyo inicio no llegó no se activa, con ni sin `closeCurrent`. La prueba citada ahora espera ese rechazo.
- **Necesidad declarada con fecha futura:** como el fin efectivo no puede pasar de hoy y no puede dejar fuera necesidades ni versiones, una campaña con una necesidad fechada después de hoy no se puede cerrar hasta retirarla. Es la consecuencia de las dos reglas pedidas; se declara.
  - *Precisión (2026-10-18, revisión de Roderich):* «hasta retirarla» no basta. `_lastOperationDay` consulta también `declared_need_versions`, un historial inmutable: mientras exista una versión fechada después de hoy, el cierre con fin ≤ hoy se rechaza aunque la necesidad se haya retirado. Lo que el código permite es cerrar cuando ese día haya llegado. No se borra historial para lograr el cierre.
- **FIFO** con una compra fechada en un día pasado: su lote entra a la medianoche local de ese día (`acquired_date`) y, por eso, ordena **antes** que los lotes de ese día con hora real para los **consumos posteriores**. Los consumos y costos ya registrados no se recalculan: una compra fechada hacia atrás no cambia ninguna aplicación anterior (revisión de B).
- **«Hoy» se fija al abrir el formulario:** `effectiveDay` se calcula al crear el estado. Un formulario que se deja abierto a través de la medianoche sigue mostrando «(hoy)» con el día anterior y, si no se cambia, guarda ese día a su medianoche local. Menor (revisiones de A y B); no se toca ahora.
- **El rechazo de fecha futura usa el reloj del teléfono** (`DateTime.now()` en el repositorio, el mismo reloj de siempre). Un reloj mal puesto no se detecta: con el reloj atrasado, una fecha real de hoy se rechazaría como futura; con el reloj adelantado, se admitiría un día que aún no llegó (revisión de B).
- **Selector de Material en inglés:** la app no configura localizaciones; es la observación de #118 y no se abre otro frente.
- **No cambian** el reloj, el contrato de proyección, los CSV de mediciones ni ningún registro confirmado. No hay migración.
- GATE-F04 (#28) sigue **Pending**: lo decide Roderich. D-F04-C1 sigue como límite de RF-03.
