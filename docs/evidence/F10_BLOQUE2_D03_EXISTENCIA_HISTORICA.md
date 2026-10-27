# Bloque 2 — D-03: existencia histórica en aplicaciones con fecha pasada

- **Fecha real:** 2026-10-27 (America/La_Paz). Rama `feat/d03-existencia-historica-aplicacion` sobre Mobile `main` `ed9c55c`.
- **Fuente:** decisión del autor, Roderich Rendón, del 2026-10-27 (bloque 2, D-03). Es una decisión del autor; no se atribuye al tutor ni a la Directiva. El análisis previo está en la revisión integral del 2026-10-26 (decisiones de negocio, §1).
- **Trazabilidad:** RN-25 (stock suficiente, precisada), RN-26 (FIFO), RF-03 (elegibilidad temporal de §2.3), CU-09 (aplicación).
- **Procedencia:** sólo pruebas de **host** (`flutter test`, Windows 11, Flutter 3.47.2, reloj real del 2026-10-27). Sin dispositivo, sin emulador y sin personas.
- **Esta mejora no forma parte de X01 ni de X02**, y sus evidencias no cambian.

## 1. Commits

| SHA | Qué |
|---|---|
| `d2f186a` | `confirmApplication`: con un día local efectivo anterior a hoy, la elegibilidad de RF-03 (`_lotsAvailableAt`); con el día de hoy, la ruta de siempre (`_lotsAvailableNow`). `HistoricalStockException` con producto, fecha y existencia elegible. Pruebas nuevas, dos pruebas existentes ajustadas (§4), contrato §2.6 y precisión de RN-25 |
| (este archivo) | Evidencia |

## 2. Diseño

- **«Hoy» frente a día pasado:** se compara `localDay(appliedAt)` con `localDay(DateTime.now())`, la misma convención de `_ensureEffectiveDateInCampaign` (#121) y de RF-03. Las fechas futuras ya se rechazan antes.
  - **Hoy:** la ruta de siempre, con la misma consulta, el mismo FIFO, el mismo costo y el mismo mensaje. No puede haber lotes ni movimientos posteriores a hoy, así que el saldo de hoy ya es el cupo histórico. Mantener la consulta evita cualquier diferencia en el caso de uso más frecuente.
  - **Día pasado:** `_lotsAvailableAt(day)`, la misma función de `confirmLateOperation`: lotes no anulados con `acquired_date` ≤ día (el mismo día cuenta), y un cupo por lote que es el mínimo del saldo al final del día y al final de cada día posterior con movimientos. Así ningún saldo posterior queda negativo.
- **Rechazo:** dentro de la transacción de `_write`; la excepción la deshace entera.
- **Mensaje:** si tampoco alcanza el saldo de hoy, el rechazo sigue siendo el de RN-25 («Stock insuficiente para confirmar la aplicación.»). Así D-03 sólo cambia el resultado de lo que antes se aceptaba, y `rec_046` y `rec_047` siguen sin cambios.
- **Productores cubiertos:** el formulario (también «Aplicar este plan», con `planId`), la voz (`VoiceDraftGateway.confirmApplication`, aplicación libre y de plan) y cualquier llamada directa a `confirmApplication`. La sincronización no crea aplicaciones. `confirmLateOperation` no cambia.

### Texto de rechazo

`<producto>: el <dd/mm/aaaa> había <existencia elegible> disponibles para esa persona; pidió <cantidad>. Una aplicación con fecha pasada sólo puede usar lo que esa persona ya tenía ese día y no se usó después: no cuenta el producto comprado o recibido más tarde. Revise la fecha o la cantidad. No se registró nada.`

Ejemplos que comprueban las pruebas:
- «Bellator: el 15/10/2026 había 0 L disponibles para esa persona; pidió 0,8 L. …»
- «Bellator: el 15/10/2026 había 0,3 L disponibles para esa persona; pidió 0,5 L. …»
- «Expansive: el 15/10/2026 había 0 KG disponibles para esa persona; pidió 1 KG. …»

## 3. Pruebas nuevas y su carácter discriminante

Archivos: `test/f10_d03_existencia_historica_test.dart` (repositorio y voz) y `test/f10_d03_existencia_historica_form_test.dart` (formulario, app real en modalidad propia).

| Prueba | Base `ed9c55c` (`lib/` restaurado) | Con `d2f186a` |
|---|---|---|
| 1. Compra 20/10, aplicación 15/10 → rechazo con producto, fecha y 0 L; volcado intacto | falla: `Actual: <Instance of 'Future<int>'> Which: emitted <1>` (se aceptó) | pasa |
| 2. Existencia anterior suficiente; el lote recibido el 20/10 por un pase (adquirido el 05/10) no se usa | falla: `Expected: {2: (600, 12000)} Actual: {3: (500, 5000), 2: (100, 2000)}` | pasa |
| 2b. Lote adquirido el mismo día: elegible (control) | pasa | pasa |
| 3. Cupo comprometido por una aplicación del 18/10: 0,5 L rechazado («había 0,3 L»); 0,3 L aceptado, sin saldos negativos (oráculo por día) | falla: `emitted <2>` (se aceptó) | pasa |
| 4. Multiproducto: la 2.ª línea no existía → nada en `applications`, `inventory_movements`, `account_transactions`, `sync_outbox` ni en el resto del volcado | falla: `emitted <1>` | pasa |
| 4b. Plan con fecha pasada: misma regla, plan sin cambios | falla: `emitted <1>` | pasa |
| 6. Hoy: mismo FIFO, mismo costo (Bs 100 + Bs 100), fechas y cargo (control) | pasa | pasa |
| 6b. Registro anterior inconsistente (aplicación del 15/10 sobre un lote del 20/10): no se corrige y no impide la aplicación de hoy (control) | pasa | pasa |
| 7a. Voz con reloj 15/10 y compra 20/10 → `confirm()` nulo, mismo mensaje y volcado intacto | falla: `Expected: null Actual: <1>` | pasa |
| 7b. Voz con existencia de esa fecha → confirma (control) | pasa | pasa |
| Formulario: día pasado (01/10/2026) con la compra de hoy → se ve «Glifosato: el 01/10/2026 había 0 L disponibles para esa persona; pidió 2 L.» y el volcado no cambia | falla: `Found 0 widgets with text containing Glifosato: el 01/10/2026` | pasa |

Las pruebas de control (2b, 6, 6b y 7b) comprueban que no cambia lo que debe seguir igual. Por eso pasan en las dos versiones.

**Comandos:**
```
git checkout ed9c55c -- lib/data/agro_repository.dart
flutter test -j 2 -r expanded test/f10_d03_existencia_historica_test.dart test/f10_d03_existencia_historica_form_test.dart test/e2e_v5_test.dart test/fix_inventario_movimientos_test.dart
git checkout HEAD -- lib/data/agro_repository.dart
```
Salida en la base: `00:11 +8 -8: Some tests failed.` (los ocho fallos de la tabla, más `fix_inventario_movimientos_test`, §4). Con `d2f186a`, los mismos cuatro archivos dan `00:02 +15: All tests passed!` y el formulario `00:04 +1: All tests passed!`.

## 4. Pruebas existentes cuyo resultado esperado cambia por D-03

- **`e2e_v5_test`:** la aplicación del 10/01 consumía producto recibido en un pase sin fecha, es decir, de hoy. Con D-03 se rechaza: «Producto 1: el 09/01/2026 había 0 L disponibles…». El día es el 09/01 porque `DateTime.utc(2026, 1, 10)` cae ese día en La Paz. El pase se fecha ahora el 06/01, antes de la aplicación. El resto del escenario y sus cifras no cambian, y la prueba pasa en las dos versiones.
- **`fix_inventario_movimientos_test`:** la aplicación del 21/01 de 8 L contaba 3 L devueltos por reversiones (del pase del 15/01 y de la aplicación del 17/01) que quedan fechadas hoy. El 21/01 Ana tenía 4 L + 3 L. Ahora aplica 7 L, también de dos lotes, así que la vista sigue mostrando una sola fila para dos movimientos (`-7000` en vez de `-8000`). Las doce aplicaciones extra de «Ver más» van con la fecha de hoy, el único día con saldo. En la base esta prueba falla (`Expected: <13> Actual: <12>`), porque allí los 7 L salen de un solo lote.
- **Sin cambios:** `rec_046_inventory_detail_test` y `rec_047_application_rules_test`. Esperan «Stock insuficiente para confirmar la aplicación.» con fecha pasada, y siguen pasando porque en esos casos tampoco alcanza el saldo de hoy (§2).

## 5. Regresión (archivos relevantes, sin la suite completa)

La máquina compartía la carga con otros tres agentes, así que la suite completa la corre el coordinador. Sobre `d2f186a` se corrieron los 48 archivos de prueba que mencionan `confirmApplication`, `LateOperation`, FIFO o `VoiceDraftGateway`, junto con los dos archivos nuevos:

```
flutter test -j 2 -r expanded <48 archivos>
02:05 +473: All tests passed!
```

Entre ellos están `e2e_scenario_test`, `e2e_v5_test`, `repository_test`, `v4_repository_test`, `v5_domain_test`, `f04_campaign_effective_date_test`, `f04_effective_date_form_test`, `f04_repository_guards_test`, `plan_lifecycle_test`, `plan_lifecycle_ui_test`, `rec_046`–`rec_050`, `reports_test`, `voice_*` y `f10_x01_aplicacion_productos_test`.

Operaciones tardías (comprobación 5), por separado:

```
flutter test test/f04_rf03_late_operations_test.dart   → 00:00 +13: All tests passed!
flutter test test/f04_rf03_late_screen_test.dart       → 00:03 +2: All tests passed!
```

Voz y tardías juntas (`f04_rf03_late_operations_test`, `f04_rf03_late_screen_test`, `voice_application_draft_test`, `voice_plan_application_draft_test`): `00:03 +56: All tests passed!`.

Primera corrida, antes de ajustar §4 y de conservar el mensaje de RN-25: 6 fallos (`e2e_v5_test`, tres de `fix_inventario_movimientos_test`, `rec_046_inventory_detail_test` y `rec_047_application_rules_test`). Así se detectaron los casos de §4 y el criterio del mensaje de §2.

## 6. Calidad

- `dart format lib test`: «Formatted 325 files (0 changed)».
- `flutter analyze`: «No issues found!».
- Commits con la identidad de Roderich1, sin trailers. Sin push ni operaciones de GitHub.

## 7. Límites y observaciones para el autor

- **Las reversiones devuelven con su propia fecha.** Una reversión de una aplicación o de un pase devuelve el producto en la fecha en que se revierte. Para una aplicación anterior a esa fecha, ese producto no cuenta, aunque la operación revertida haya sido un error que en la realidad nunca ocurrió. RF-03 §2.3 ya funcionaba así. Nunca deja saldos negativos, pero puede rechazar una aplicación que sí tenía producto. Se ve en `fix_inventario_movimientos_test` (§4). **Contradicción material para decidir:** si una reversión «por error» debe devolver la existencia con la fecha de la operación anulada. No se resolvió aquí.
- **Registros anteriores inconsistentes:** no se recalculan ni se corrigen. Un lote con un saldo histórico negativo por esos registros no aporta cupo a una aplicación con fecha pasada. La ruta de hoy usa el saldo actual (prueba 6b).
- **Transferencias con fecha pasada:** siguen consumiendo con el saldo de hoy (`transferProductsFifo`). Quedan fuera de D-03.
- **Formulario:** la vista previa sigue mostrando la existencia de hoy y no añade consultas (lección de las pruebas con *settle* fijo). Para un día pasado, la existencia de esa fecha llega con el rechazo del repositorio al confirmar. Los textos del formulario siguen en tú («escribiste»); los del repositorio, en usted, como los demás.
- **Mensaje con saldo de hoy insuficiente:** se mantiene el mensaje de RN-25, sin la existencia de esa fecha. El formulario y la voz ya lo detienen antes con su vista previa.
- **Medianoche:** si el día cambia entre la apertura del formulario y la confirmación, la fecha elegida pasa a ser un día pasado y se aplica la regla histórica. Es el comportamiento correcto.
- Todo es host. No hay comprobación en dispositivo ni en emulador.
