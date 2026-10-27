# F10 · Bloque 2 · E-15: consumo y costos propios del titular (evidencia HOST)

- **Fecha real:** 2026-10-27, hacia las 19:00Z.
- **Decisión:** E-15 es una decisión del autor del proyecto, Roderich Rendón, del 2026-10-27 (`_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`). Los criterios Q-2 y Q-3 son criterios de aplicación del coordinador que el autor puede revisar (`docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md` §7). No se atribuye aprobación al tutor ni a la Directiva.
- **Rama:** `feat/e15-consumo-propio-titular`, apilada sobre D-04 `4970124` (`feat/d04-imputacion-pagos-campanas`).
- **Commit de implementación:** `fd39326`. Esta evidencia va en el commit siguiente.
- **Entorno:** HOST Windows 11, Flutter 3.47.2, `sqflite_common_ffi`. La comprobación en el emulador la coordina el coordinador.
- **Trazabilidad (Cap. III):** RF-06/CU-05, RF-12/CU-09, RF-13/CU-17, DAT.

## Qué cambia

- **Propiedad de los asientos.** El libro de cuentas de D-04 lee, en la **misma** consulta, `owner_bindings` y las aplicaciones de las personas que han sido titulares. Un asiento o una aplicación es propio si su persona era titular en su día local (criterio Q-3). Lo anterior al primer vínculo se atribuye al primer titular, y la reversión de un cargo sigue la propiedad de su cargo. Es un supuesto de presentación: no escribe ni cambia datos.
- **Fuera de las cuentas por cobrar.** Los asientos propios no entran en la lista de Cuentas, en «Familias/Terceros por cobrar», en «Pagos recibidos», en «Principales saldos» (ahora sale del libro, en `dashboard()`) ni en el resumen de campaña.
- **Tarjeta «Consumo y costos propios».** Muestra el consumo aplicado a costo FIFO, calculado desde las aplicaciones no revertidas y no desde `USAGE_CHARGE`, así que también vale con `MANUAL` o `BY_PURCHASE_ALLOCATION`. Las aplicaciones revertidas van aparte. Los asientos se muestran como registro: «cargos anotados», «créditos por reversión» y «pagos y ajustes registrados». El menú tiene «Ver movimientos propios», «Exportar movimientos propios» y conserva pago y adelanto (criterio Q-2, #26).
- **«Movimientos propios».** Sin acumulado, sin «Pendiente a hoy» y sin «Pagado»; sólo «Revertido el …». Su exportación es «Movimientos propios del titular».
- **Personas.** El titular aparece con «Consumo propio X». El detalle de un titular anterior muestra «Consumo propio mientras fue titular».
- **Formulario de aplicación.** Para el titular dice «Costo propio» en las dos modalidades. Con `BY_PURCHASE_ALLOCATION` dice «Esta aplicación no genera cargo: a X se le cargó al comprarlo.».
- **Sin cambios.** No cambian las escrituras, el esquema ni los datos. Las consultas de la carga de Cuentas siguen siendo 5. Las de Inicio bajan de 8 (D-04) a 7, porque `topSettlements` ya no se lee aparte; en `ed9c55c` eran 10.

## Comandos y salidas

```text
$ flutter test test/e15_consumo_propio_ledger_test.dart test/e15_consumo_propio_base_test.dart   # sobre fd39326
00:06 +19: All tests passed!
```

**Discriminación sobre D-04.** Se puso `lib/` de `4970124` en el mismo worktree (`git checkout 4970124 -- lib/`), se ejecutaron las pruebas y se restauró con `git checkout HEAD -- lib/`, quedando el árbol limpio.

```text
$ flutter test test/e15_consumo_propio_base_test.dart       # con lib/ de 4970124
00:05 +0 -9: Some tests failed.
  Expected: not contains <4>   Actual: [4, 1, 2]                    (E15-01: el titular, id 4, en la lista)
  Expected: <0>     Actual: <4500>                                  (E15-04: Pagos recibidos)
  Expected: <4500>  Actual: <9000>                                  (M-10: Familias por cobrar)
  Expected: <2000>  Actual: <10100>                                 (E15-06: Familias por cobrar)
  Expected: 'Movimientos propios del titular'  Actual: 'Estado de cuenta'   (exportación)
  Found 0 widgets with key 'own-consumption-card'                   (Cuentas, E15-01 y E15-05)
  Found 0 widgets with text containing 20,00 Bs … Familias por cobrar  (Inicio)
  Found 0 widgets with text "Consumo propio 81,00 Bs"               (Personas)

$ flutter test test/e15_consumo_propio_ledger_test.dart     # con lib/ de 4970124
test/e15_consumo_propio_ledger_test.dart:58:7: Error: Method not found: 'ownConsumptionLine'.
(no compila: usa las lecturas de E-15; la discriminación por aserción la da el archivo anterior)

$ flutter test test/fix_aplicacion_costo_cargo_test.dart    # prueba existente cambiada, con lib/ de 4970124
00:11 +2 -1: Some tests failed.
  Found 0 widgets with text "Esta aplicación no genera cargo: a Vecino se …"
```

**Pruebas afectadas**, en tandas de tres como mucho, sobre `fd39326`:

```text
d04_imputacion_ledger_test, d04_imputacion_base_test, e15_consumo_propio_ledger_test -> +53: All tests passed!
fix_aplicacion_costo_cargo_test, e15_consumo_propio_base_test                       -> +12: All tests passed!
fix_aplicacion_hoja_existencias_test, personal_mode_flows_test (con la anterior)   -> ver nota
f04_historical_admin_owner_test, f04_admin_owner_restore_ui_test, f04_activation_app_policy_test -> +29: All tests passed!
report_reads_characterization_test, typed_reads_parity_test, reports_test          -> +49: All tests passed!
repository_test, e2e_scenario_test, e2e_v5_test                                    -> +13: All tests passed!
v5_domain_test, v4_repository_test, regression_widget_test                         -> +14: All tests passed!
rec_039_sqlite_abort_test, f04_mode_race_test, f04_operation_mode_test             -> +21: All tests passed!
f04_repository_guards_test, reports_screen_test, report_composer_test              -> +77: All tests passed!
report_export_service_test, report_pdf_test, payment_dialog_test                   -> +59: All tests passed!
error_states_test, ui_polish_test, f10_compat_129_presentacion_test                -> +33: All tests passed!
rec_015_logbook_profile_test, rec_046_051_net_figures_test, set_state_contract_test -> +25: All tests passed!
hierarchical_navigation_test, formatting_and_labels_test, voice_architecture_guard_test -> +51: All tests passed!
voice_draft_architecture_guard_test                                                -> +7: All tests passed!
existing_session_screen_test, first_activation_screen_test, remote_session_screen_test -> +46: All tests passed!
$ dart format lib test  -> Formatted 332 files (0 changed)
$ flutter analyze       -> No issues found!
```

Nota: en la tanda `fix_aplicacion_costo_cargo_test` + `fix_aplicacion_hoja_existencias_test` + `personal_mode_flows_test`, la única falla fue la prueba de `fix_aplicacion_costo_cargo_test` que cambia por la decisión (tabla de abajo). Las otras dos pasaron. Tras el cambio, `fix_aplicacion_costo_cargo_test` pasa entera (tanda siguiente). `personal_mode_flows_test`, incluida «liquidación: pagos y adelantos sólo del titular», pasa **sin cambios**: el titular conserva pago y adelanto en su tarjeta.

No se ejecutó la suite completa.

## Prueba existente cambiada

| Prueba | Cambio | Decisión y ejemplo |
|---|---|---|
| `fix_aplicacion_costo_cargo_test` («cobro por compra: el mismo costo y "No genera cargo"») | Espera «Esta aplicación no genera cargo: a Vecino se le cargó al comprarlo.» en lugar de «No genera cargo: Vecino ya pagó estos productos al comprarlos». El texto anterior es falso si el tercero todavía debe la compra | E-15 §B.2; M-7 |

## Cuentas antes (D-04) y después (E-15), por ejemplo

| Ej. | D-04 (`4970124`) | E-15 (`fd39326`) |
|---|---|---|
| E15-01 | Lista: «Titular» con neto 81,00 (primero), Familiar 20,00. Inicio: Familias **101,00** y Titular en «Principales saldos». Resumen I 101,00 | Tarjeta: «Consumo aplicado (costo FIFO) · Invierno 2026 81,00 Bs» · «1 aplicación vigente» · «Asientos en su cuenta (no son deuda): cargos anotados 81,00 Bs · créditos por reversión 0,00 Bs · pagos y ajustes registrados 0,00 Bs». Lista: sólo Familiar 20,00. Inicio: Familias **20,00**, sin Titular. Resumen I 20,00. Personas: «Consumo propio 81,00 Bs». Exportación «Movimientos propios del titular» |
| E15-02a | Titular ADMIN fuera de Cuentas; su consumo no se ve | Tarjeta «Consumo aplicado … 81,00 Bs» · «Sin asientos en su cuenta.» |
| E15-02b | «Titular» con neto 90,00 | Tarjeta consumo **45,00 Bs** · cargos anotados 90,00 Bs; Inicio no lo suma |
| E15-03 | «Titular» con neto 45,00 | Consumo 45,00 · «1 aplicación vigente · 1 revertida (81,00 Bs, no cuenta)» · cargos anotados 126,00 · créditos por reversión 81,00 |
| E15-04 | «Titular» con neto 0,00. Inicio: Pagos recibidos 81,00 (45,00 en la prueba base) | Consumo 81,00 · pagos y ajustes registrados 81,00. Inicio: Pagos recibidos **0,00** |
| E15-05 | Modo propio: «Titular» con neto 81,00. Inicio: Familias 81,00 | Tarjeta con 81,00 y pago y adelanto. Inicio: Familias **0,00**. Con sólo el titular: «En inventario propio no hay cuentas por cobrar.» |
| E15-06 | Inicio: Familias 101,00 | P1 (titular anterior) con neto 0,00 y «Consumo propio mientras fue titular 81,00 Bs». P2 (titular actual) con neto 20,00 en la lista y «Sin aplicaciones vigentes» en su tarjeta. Inicio: Familias **20,00** |
| M-9 | «Titular» con neto 83,00; tras revertir, 0,00 | Consumo **83,00** · «1 aplicación vigente». Tras revertir: 0,00 · «Sin aplicaciones vigentes · 1 revertida (83,00 Bs, no cuenta)» |
| M-10 | Inicio: Familias **90,00** | Consumo del titular 45,00 (lo transferido no cuenta). Familiar 45,00. Inicio: Familias **45,00** |

## Límites declarados

- **Q-3 es un supuesto de presentación por día local.** Un asiento del mismo día de un cambio de titular se atribuye al titular nuevo. Las bases con varios vínculos se clasifican por intervalos sin escribir nada.
- **Pagos cruzados.** Una imputación de un pago propio a un cargo que no es propio (o al revés) sólo puede darse con un cambio de titular por medio. Esa imputación se respeta tal como está guardada. En ese caso, el saldo neto por cobrar de esa persona puede no coincidir con la suma de sus asientos no propios. No se encontró en los ejemplos.
- **Selector de Reportes.** Conserva a la persona tal cual. La exportación del titular vigente se compone como «Movimientos propios del titular», y la de un titular anterior sigue siendo su estado de cuenta.
- **Pendiente:** la comprobación en el emulador y la confirmación de C-09 en dispositivo quedan para la verificación integrada.
