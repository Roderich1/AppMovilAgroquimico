# F10 · Bloque 2 · D-04: imputación de pagos entre campañas (evidencia HOST)

- **Fecha real:** 2026-10-27, hacia las 18:40Z.
- **Decisión:** D-04 es una decisión del autor del proyecto, Roderich Rendón, del 2026-10-27 (`_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`). Los criterios de aplicación los fijó el coordinador y el autor puede revisarlos (`docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md` §7). No se atribuye aprobación al tutor ni a la Directiva.
- **Rama:** `feat/d04-imputacion-pagos-campanas`, desde Mobile `main` `ed9c55c`.
- **Commits:** `09963b4` (diseño, revisión 1), `2b3a73d` (diseño, revisión 2, tras la revisión cruzada) y `973dc1e` (implementación). Esta evidencia va en el commit siguiente.
- **Entorno:** HOST Windows 11, Flutter 3.47.2, `sqflite_common_ffi`. No hay dispositivo; la comprobación en el emulador la coordina el coordinador.
- **Trazabilidad (Cap. III):** RF-03, RF-12/CU-09, RF-13/CU-17, DAT. Las cuentas no tienen RF propio (C-01 del documento).

## Qué cambia

- **Imputación de pagos nuevos.** `registerAccountPayment` imputa sólo a **cargos** con deuda pendiente (importe − revertido − imputado), en orden de día local y luego id. `addAccountPayment` la llama. Las imputaciones guardadas no se tocan.
- **Libro de cuentas.** `domain/account_ledger.dart` lo calcula en Dart puro a partir de **una** consulta (`accountLedger`): deuda pendiente por cargo, pagos aplicados (de `payment_allocations`), a favor no aplicado a deuda (pagos sin imputar + liberado por reversión − otros ajustes) y saldo neto.
- **Cuentas.** Con «Todas», el saldo neto; con una campaña, la «Deuda pendiente por origen · K», el saldo neto y lo que queda a favor sin campaña. El diálogo de pago muestra la campaña de registro, el saldo neto y la imputación escrita.
- **Detalle y exportación.** Desglose por origen (a hoy) y estado cronológico por período de fechas, con apertura y cierre.
- **Inicio.** «Familias/Terceros por cobrar» = Σ max(0, saldo neto), con «A favor de …» aparte.
- **Resumen de campaña.** Deuda pendiente por origen, sin ADMIN.
- **Sin cambios.** El esquema y los datos históricos no cambian. Las lecturas heredadas `settlements`, `detailedStatement`, `personCampaignBalance` y `statement` se conservan para su caracterización. El número de consultas de la carga de Cuentas no cambia (5) y el de `dashboard()` baja de 6 a 4.

## Comandos y salidas

```text
$ flutter test test/d04_imputacion_ledger_test.dart test/d04_imputacion_base_test.dart   # sobre 973dc1e
00:08 +43: All tests passed!
```

**Discriminación sobre la base.** Se restauró `lib/` de `ed9c55c` dentro del mismo worktree (`git checkout ed9c55c -- lib/` y se retiraron los tres archivos nuevos de `lib/`). Se ejecutaron las mismas pruebas y después se restauró `git checkout HEAD -- lib/`, quedando el árbol limpio.

```text
$ flutter test test/d04_imputacion_base_test.dart        # con lib/ de ed9c55c
00:05 +0 -18: Some tests failed.
  Expected: <3100>   Actual: <8100>          (D04-01 1b, resumen de Verano)
  Expected: <0>      Actual: <8100>          (D04-02)
  Expected: <0>      Actual: <8100>          (D04-03)
  Expected: <0>      Actual: <-1900>         (D04-04, Familias por cobrar)
  Expected: <37000>  Actual: <7000>          (D04-05, resumen de Invierno)
  Expected: <0>      Actual: <-1000>         (D04-06)
  Expected: {2: 4000} Actual: {1: 5000}      (D04-07, imputación al cargo revertido)
  Expected: <0>      Actual: <-10000>        (D04-08, Terceros por cobrar)
  Expected: <8100>   Actual: <3100>          (D04-09b)
  Expected: empty    Actual: {1: 2100}       (M-2r)
  Expected: {1: 2500} Actual: {2: 2000, 1: 500}  (M-3)
  Expected: <2100>   Actual: <11100>         (M-4)
  Expected: <0>      Actual: <-10000>        (M-5)
  Expected: <0>      Actual: <1000>          (D-R6, ADMIN en el resumen)
  Expected: contains 'Saldo al inicio del período (Bs);81,00'   (M-8, exportación)
  Found 0 widgets with text "Cargos de Invierno 2026 40,00 Bs · …"  (Cuentas, D04-01 1b)
  Found 0 widgets with text "Se registra en: Invierno 2026"        (diálogo de pago)
  Found 0 widgets with text "0,00 Bs " … Familias por cobrar        (Inicio, D04-04)

$ flutter test test/d04_imputacion_ledger_test.dart      # con lib/ de ed9c55c
test/d04_imputacion_ledger_test.dart:14:8: Error: Error when reading 'lib/domain/account_ledger.dart' …
test/d04_imputacion_ledger_test.dart:32:3: Error: 'AccountSummary' isn't a type.
(no compila: usa las lecturas nuevas; la discriminación por aserción la da el archivo anterior)
```

**Pruebas existentes afectadas**, en tandas de tres archivos como mucho, sobre el árbol de `973dc1e`:

```text
report_reads_characterization_test, typed_reads_parity_test, reports_test        -> +49: All tests passed!
repository_test, e2e_scenario_test, e2e_v5_test                                  -> +13: All tests passed!
v5_domain_test, v4_repository_test, rec_039_sqlite_abort_test                    -> +12: All tests passed!
regression_widget_test                                                           -> +4: All tests passed!
f04_historical_admin_owner_test, f04_mode_race_test, f04_operation_mode_test     -> +26: All tests passed!
f04_repository_guards_test, personal_mode_flows_test, reports_screen_test        -> +60: All tests passed!
report_composer_test, report_export_service_test, report_pdf_test                -> +88: All tests passed!
payment_dialog_test, error_states_test, ui_polish_test                           -> +29: All tests passed!
f10_compat_129_presentacion_test, rec_015_logbook_profile_test, rec_046_051_net_figures_test -> +34: All tests passed!
set_state_contract_test, hierarchical_navigation_test, formatting_and_labels_test -> +35: All tests passed!
f04_admin_owner_restore_ui_test, f04_activation_app_policy_test                  -> +22: All tests passed!
voice/voice_architecture_guard_test, voice_draft/voice_draft_architecture_guard_test -> +26: All tests passed!
$ dart format lib test  -> Formatted 329 files (0 changed)
$ flutter analyze       -> No issues found!
```

No se ejecutó la suite completa.

## Pruebas existentes cambiadas y por qué

| Prueba | Cambio | Decisión y ejemplo |
|---|---|---|
| `regression_widget_test` («estado de cuenta abre y cierra 20 veces») | El repositorio falso devuelve el libro (`accountLedger`) con la misma persona y el mismo adelanto, en lugar de `settlements`/`detailedStatement`. La comprobación del título pasa a `textContaining('Estado de cuenta · ')`, porque el diálogo trae además la cabecera «Estado de cuenta cronológico · …» | D-04 §2.5, D04-01 |
| `report_export_service_test` («el estado de cuenta cuadra con el saldo») | Espera «Saldo a hoy (Bs);500,00» en lugar de «Saldo final (Bs);500,00». La cifra es la misma | D-04 §2.6, M-8 |
| `rec_016_export_coherence_test` (resumen de las campañas 1 y 2) | Espera «Deuda pendiente por origen;;530,00» y «Deuda pendiente por origen (Bs);530,00» en lugar de «Saldo por cobrar…», y lo mismo con 297,50 en la campaña 2. Las cifras no cambian | D-04: el resumen de campaña muestra la deuda pendiente por campaña de origen, no un saldo por `campaign_id`, y los dos cálculos no comparten rótulo (§2.3 y §2.7, I-6) |

Nota (2026-10-27, coordinación A): las tandas de la rama no incluían `rec_016_export_coherence_test`. Esa prueba falló en la suite completa de la composición local `ae5d1a3` (`01:58 +2058 ~3 -2`): sólo por el rótulo, con las mismas cifras. Fallaba igual en `b7661ca` y en E-15 `d58ec42`. Se corrigió en esta rama con la justificación de arriba; el archivo sólo, tras el cambio: `00:01 +9: All tests passed!`.

Las demás pruebas existentes pasan sin cambios. Las caracterizaciones de las lecturas heredadas siguen valiendo porque esas lecturas no se tocaron.

## Cuentas antes y después, por ejemplo

En «hoy», la columna «I» es Cuentas filtrada por Invierno 2026 (filtro por defecto: campaña activa). En «D-04», la cifra grande de cada tarjeta es: con «Todas», el saldo neto; con una campaña, la «Deuda pendiente por origen · K». Importes en Bs.

| Ej. | Hoy: Todas / V / I | D-04: Todas (neto) / V / I | Otros cambios comprobados |
|---|---|---|---|
| D04-01 (1b) | 71 / 81 / **−10** | 71 / **31** / **40** | Resumen V 31, I 40; cronológico I: inicio 81, a hoy 71 |
| D04-02 | 0 / 81 / **−81** | 0 / **0** / 0 | Resumen V 0, I 0 |
| D04-03 | 21 / 81 / **−60** | 21 / **0** / **21** | «Imputado: Verano 2026 81,00 · Invierno 2026 19,00» |
| D04-04 | −19 / 81 / 0 | −19 / **0** / 0, «A favor … 19,00 (sin campaña)» | Inicio Familias **0** (antes −19) y «A favor de familias: 19,00» |
| D04-05 | 70 / 0 / 70 | 70 / 0 / **370**, con a favor 300 | Resumen I 370; el anticipo queda «Sin imputación registrada» |
| D04-06 | −10 / 0 / 40 | −10 / 0 / 40, con a favor 50 | Cronológico I: inicio **81** (antes 0), a hoy −10; Inicio Familias 0 |
| D04-07 | −10 / 0 / **−10** | −10 / 0 / **0** | Imputación nueva q1 → c2 40 (antes q1 → c1 50) |
| D04-07h | −10 / 0 / −10 | −10 / 0 / **40** | Imputación guardada q1 → c1 50 conservada y mostrada |
| D04-08 | −100 / **−100** / 0 | −100 / **0** / 0, con a favor 100 | Inicio Terceros 0 (antes −100) |
| D04-09b | 31 / 31 / 0 | 31 / **81** / 0, con a favor 50 | Sin imputación fabricada; Resumen V 81 |
| M-1 | 0 / 0 / 0 | 0 / 0 / 0 | «Pagado» e «Imputado: Invierno 2026 40,00» |
| M-2 | −9 / 81 / −60 | −9 / **0** / **0** | q3 «… sin imputar 9,00» |
| M-2r | −90 | −90; q3 sin imputar 30 | Imputación de q3: ninguna (antes c1 21) |
| M-3 | I 25 | I 25 | Imputación c1 25 (antes c2 20 y c1 5) |
| M-4 | 61 / **111** / **−50** | 61 / **21** / **40** | Cronológico V cierra 81 → 111 tras la tardía |
| M-4b | 71 / 31 / 40 | 71 / 31 / 40 | Diálogo «Se registra en: Verano 2026 (cerrada)…»; cronológico V cierra en 81 |
| M-5 | −100 / 0 / **−100** | −100 / 0 / **0** | Inicio Familias 0 (antes −100); resumen I 0 |
| M-6 | 0,01 | 0,01 | Cargo 5,06 por redondeo por lote |
| M-7 | 30 / 0 / **90** | 30 / 0 / **30** | Costo por chaco 45 sin cambio |
| M-8 | — | — | Exportación: columnas y totales de §2.6; CSV sin «Saldo final» |

## Límites declarados

- No existe la reversión de pagos de cuenta (H-10). D-04 no la añade. La clase «compensación de un crédito» la deja prevista sin tratarla como deuda (prueba §2.1).
- Un anticipo previo a los cargos y el crédito liberado por una reversión **no se imputan** a cargos posteriores (criterio Q-1, I-8). Por eso una persona puede ver «Deuda pendiente por origen · Invierno 2026: 300,00» con saldo neto 0,00 (D04-05).
- No está implementada la leyenda «Incluye operaciones tardías confirmadas» (carencia previa, C-13).
- La comprobación en el emulador y la confirmación de C-09 en dispositivo quedan para la verificación integrada.
- Lo propio del titular es E-15, en la rama apilada `feat/e15-consumo-propio-titular`. En D-04 el titular sigue siendo una persona más de la lista.

## Revisión cruzada 2 (2026-10-27, ajustes en `500f5ad`)

La revisión cruzada de `4970124` dio «listo con ajustes», sin errores contables, y recalculó los diez ejemplos. Ajustes aplicados:

- **Fin del período (media).** El período terminó si `endDay` es anterior a hoy, sea cual sea el estado; es el mismo criterio en `periodClosed` y en el diálogo de pago. Antes una campaña ACTIVA con fin pasado (#125) cortaba las filas y aun así rotulaba «Saldo a hoy», lo que rompía I-4.
- **Documentos.** F-11 y D-R7: Personas sigue con `detailedStatementTyped` hasta E-15. D-R8 (`withDetails: false`), §2.2/§2.4/RN-42 (fin por fecha) y la nota de §4 sobre las imputaciones guardadas por instante.
- **Lecturas heredadas** (`settlements*`, `personCampaignBalance*`, `statement`, `detailedStatement`, `ReportComposer.accountStatement`) marcadas «sólo caracterización». No se usó `@Deprecated`, porque las pruebas de caracterización lo convertirían en avisos del análisis.
- **Pruebas nuevas:**
  - campaña ACTIVA con fin pasado y pago posterior;
  - asiento en un hueco entre campañas;
  - 07h seguido de un pago nuevo (la imputación histórica intacta y el pago nuevo a c2);
  - PDF de `ledgerStatement` filtrado por Invierno con sus cifras;
  - I-4 con fin e I-5 de terceros dentro de las invariantes;
  - M-4/D04-06 con la confirmación tardía RF-03 y la reversión RF-13 reales, con PIN de prueba (`d04_imputacion_real_ops_test.dart`). Allí la tardía, con id mayor, recibe primero la imputación por su día (2025) y el cierre de «Campaña 2025» pasa de 0,00 a 50,00. La reversión libera 50,00 y un pago posterior no se imputa.

```text
$ flutter test --timeout 120s <tanda>                                   # sobre 500f5ad
d04_imputacion_ledger_test, d04_imputacion_base_test, d04_imputacion_real_ops_test -> +48: All tests passed!
regression_widget_test, report_export_service_test, report_composer_test           -> +68: All tests passed!
report_pdf_test, navigation_test, sync_screens_test                                -> +35: All tests passed!
f10_mensajes_autorizacion_test, reports_test, report_reads_characterization_test   -> +42: All tests passed!
typed_reads_parity_test, payment_dialog_test, reports_screen_test                  -> +44: All tests passed!
$ dart format lib test -> Formatted 330 files (0 changed)
$ flutter analyze      -> No issues found!

# Discriminación de las pruebas nuevas
$ flutter test test/d04_imputacion_ledger_test.dart --plain-name "revisión cruzada 2"   # lib/ de 4970124
test/d04_imputacion_ledger_test.dart:1104:9: Error: No named parameter with the name 'now'.
00:00 +0 -1: Some tests failed.
$ flutter test test/d04_imputacion_real_ops_test.dart test/d04_imputacion_ledger_test.dart   # lib/ de ed9c55c
test/d04_imputacion_real_ops_test.dart:95:32: Error: The method 'accountLedger' isn't defined for the type 'AgroRepository'.
(las dos no compilan sobre las bases; el árbol se restauró con git checkout HEAD -- lib/ y quedó limpio)
```
