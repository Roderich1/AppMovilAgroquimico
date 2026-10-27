# Bloque 2 — D-03: existencia histórica en aplicaciones con fecha pasada

- **Fecha real:** 2026-10-27 (America/La_Paz). Primera versión hacia las 13:50; ajustes de la revisión cruzada hacia las 14:10. Rama `feat/d03-existencia-historica-aplicacion` sobre Mobile `main` `ed9c55c`. Estado verificado: `4ccaca1`.
- **Fuente:** decisión del autor, Roderich Rendón, del 2026-10-27 (bloque 2, D-03). Es una decisión del autor; no se atribuye al tutor ni a la Directiva. El análisis previo está en la revisión integral del 2026-10-26 (decisiones de negocio, §1).
- **Trazabilidad:** RN-25 (stock suficiente, precisada), RN-26 (FIFO), RF-03 (elegibilidad temporal de §2.3), CU-09 (aplicación).
- **Procedencia:** sólo pruebas de **host** (`flutter test`, Windows 11, Flutter 3.47.2, reloj real del 2026-10-27). Sin dispositivo, sin emulador y sin personas.
- **Esta mejora no forma parte de X01 ni de X02**, y sus evidencias no cambian.

## 1. Commits

| SHA | Qué |
|---|---|
| `d2f186a` | `confirmApplication`: con un día local efectivo anterior a hoy, la elegibilidad de RF-03 (`_lotsAvailableAt`); con el día de hoy, la ruta de siempre (`_lotsAvailableNow`). `HistoricalStockException`. Pruebas nuevas; `e2e_v5_test` y `fix_inventario_movimientos_test` ajustadas (§4); contrato §2.6; precisión de RN-25 |
| `faa628a` | Primera versión de esta evidencia |
| `4ccaca1` | Ajustes de la revisión cruzada: el rechazo histórico se aplica siempre, también cuando tampoco alcanza el saldo de hoy; mensaje en dos casos; `heldBase` y `_lotHistoryAt`; pruebas 1b, 3b, 3c y 3d; `rec_046` y `rec_047` cambian el texto esperado (§4); contrato §2.6 ampliado |
| (este commit) | Evidencia actualizada a `4ccaca1` |

## 2. Diseño

- **«Hoy» frente a día pasado:** se compara `localDay(appliedAt)` con `localDay(DateTime.now())`, la misma convención de `_ensureEffectiveDateInCampaign` (#121) y de RF-03. Las fechas futuras ya se rechazan antes.
  - **Hoy:** la ruta de siempre, con la misma consulta, el mismo FIFO, el mismo costo y el mismo mensaje de RN-25. No puede haber lotes ni movimientos posteriores a hoy, así que el saldo de hoy ya es el cupo histórico.
  - **Día pasado:** `_lotsAvailableAt(day)`, la misma función de `confirmLateOperation`:
    - lotes no anulados con `acquired_date` ≤ día (el mismo día cuenta);
    - un cupo por lote que es el mínimo del saldo al final del día y al final de cada día posterior con movimientos.
  - Ahora `_lotsAvailableAt` filtra `_lotHistoryAt`, que además devuelve el saldo del lote al final del día (`held`). Para la operación tardía el resultado es el mismo (§5).
- **Rechazo:** dentro de la transacción de `_write`, sin efectos parciales. Con fecha pasada es siempre `HistoricalStockException`, también si tampoco alcanza el saldo de hoy.
- **Productores cubiertos (los actuales):**
  - el formulario, también «Aplicar este plan» con `planId`;
  - la voz (`VoiceDraftGateway.confirmApplication`), que en producción confirma siempre con la fecha de hoy;
  - cualquier llamada directa a `confirmApplication`.

  La sincronización no crea aplicaciones y `confirmLateOperation` no cambia. `transferProductsFifo` acepta fechas libres por API y queda fuera de D-03 (§7).

### Textos de rechazo (exactos)

Cola común, `<cola>`: «Una aplicación con fecha pasada sólo puede usar lo que esa persona ya tenía ese día y no se usó después: no cuenta el producto comprado o recibido más tarde. Revise la fecha o la cantidad. No se registró nada.»

- **Ese día no tenía el producto** (`heldBase` = 0): `<producto>: el <dd/mm/aaaa> esa persona no tenía este producto; pidió <cantidad>. <cola>`
  - «Bellator: el 15/10/2026 esa persona no tenía este producto; pidió 0,8 L. …»
- **Lo tenía y queda menos sin usar después** (0 < cupo < `heldBase`, o cupo 0 con `heldBase` > 0): `<producto>: el <dd/mm/aaaa> esa persona tenía <held>; de eso quedan <cupo> sin usar en operaciones posteriores; pidió <cantidad>. <cola>`
  - «Bellator: el 15/10/2026 esa persona tenía 1 L; de eso quedan 0,3 L sin usar en operaciones posteriores; pidió 0,5 L. …»
- **Lo tenía, nada posterior lo usó, pero no alcanza** (cupo = `heldBase`): la misma frase sin la cláusula intermedia: `<producto>: el <dd/mm/aaaa> esa persona tenía <held>; pidió <cantidad>. <cola>`
  - «Bellator: el 15/10/2026 esa persona tenía 1 L; pidió 2 L. …»
  - «Glifosato: el 21/01/2026 esa persona tenía 7 L; pidió 8 L. …»
- **Con fecha de hoy:** «Stock insuficiente para confirmar la aplicación.», sin cambios.

«Tenía» es la suma, por lote elegible, del saldo al final de ese día; un saldo histórico negativo cuenta como cero. «Quedan» es el cupo. Las aserciones comprueban que el mensaje nunca contiene «no había existencias» ni «había 0 ».

## 3. Pruebas nuevas o cambiadas, y su carácter discriminante

Archivos nuevos:
- `test/f10_d03_existencia_historica_test.dart`: repositorio y voz, 14 pruebas;
- `test/f10_d03_existencia_historica_form_test.dart`: formulario con la app real en modalidad propia, 1 prueba.

Base = `ed9c55c`, con sólo `lib/` restaurado:
```
git checkout ed9c55c -- lib/data/agro_repository.dart
flutter test -r expanded test/f10_d03_existencia_historica_test.dart test/f10_d03_existencia_historica_form_test.dart test/e2e_v5_test.dart
flutter test -r expanded test/rec_046_inventory_detail_test.dart test/rec_047_application_rules_test.dart test/fix_inventario_movimientos_test.dart
git checkout HEAD -- lib/data/agro_repository.dart
```

| Prueba | Base `ed9c55c` | `4ccaca1` |
|---|---|---|
| 1. Compra 20/10, aplicación 15/10 → «no tenía este producto»; volcado intacto | falla: `Actual: <Instance of 'Future<int>'> Which: emitted <1>` (se aceptó) | pasa |
| 1b. Fecha pasada y tampoco alcanza hoy (1 L, pide 2 L) → «tenía 1 L; pidió 2 L»; hoy conserva RN-25 | falla: `threw BusinessRuleException:<Stock insuficiente para confirmar la aplicación.>` | pasa |
| 2. Existencia anterior suficiente; el lote recibido el 20/10 (adquirido el 05/10) no se usa | falla: `Actual: {3: (500, 5000), 2: (100, 2000)}` | pasa |
| 2b. Lote adquirido el mismo día: elegible (control) | pasa | pasa |
| 3. Cupo comprometido por una aplicación del 18/10 → «tenía 1 L; de eso quedan 0,3 L…; pidió 0,5 L»; 0,3 L aceptado sin saldos negativos | falla: `emitted <2>` | pasa |
| 3b. Pase posterior del mismo lote, del lado de quien da → mismo mensaje; 0,3 L aceptado | falla: `emitted <1>` | pasa |
| 3c. Límite de las reversiones: 8 L el 21/01 → `HistoricalStockException` con 7000 elegibles, volcado intacto | falla: `emitted <3>` (se aceptó) | pasa |
| 3d. Lote con historial negativo previo (−0,5 L el 15/10, hoy 0,5 L) no aporta cupo: 0,6 L rechazado («tenía 0,4 L»), 0,4 L sólo del lote propio | falla: `emitted <2>` | pasa |
| 4. Multiproducto: la 2.ª línea no existía → «Expansive: … no tenía este producto; pidió 1 KG»; nada nuevo en `applications`, `inventory_movements`, `account_transactions`, `sync_outbox` ni en el resto del volcado | falla: `emitted <1>` | pasa |
| 4b. Plan con fecha pasada: misma regla, plan sin cambios | falla: `emitted <1>` | pasa |
| 6. Hoy: mismo FIFO, mismo costo, fechas y cargo (control) | pasa | pasa |
| 6b. Registro anterior inconsistente: no se corrige y no impide la aplicación de hoy (control) | pasa | pasa |
| 7a. Voz con reloj fijo el 15/10 y compra del 20/10 → `confirm()` nulo, mismo mensaje | falla: `Expected: null Actual: <1>` | pasa |
| 7b. Voz con existencia de esa fecha → confirma (control) | pasa | pasa |
| Formulario, día 01/10/2026 con la compra de hoy → «Glifosato: el 01/10/2026 esa persona no tenía este producto; pidió 2 L.» | falla: `Found 0 widgets with text containing Glifosato: el 01/10/2026` | pasa |
| `rec_046`: con fecha pasada, «tenía 5 L; pidió 5,001 L» | falla: `threw BusinessRuleException:<Stock insuficiente para confirmar la aplicación.>` | pasa |
| `rec_047`: con fecha pasada, «tenía 20 L; pidió 20,001 L» | falla: `threw BusinessRuleException:<Stock insuficiente para confirmar la aplicación.>` | pasa |
| `fix_inventario_movimientos_test` (repositorio, §4) | falla: `Expected: <13> Actual: <12>` | pasa |
| `e2e_v5_test` (§4) | pasa | pasa |

Salidas en la base:
- `00:09 +5 -11: Some tests failed.` Pasan los cuatro controles y `e2e_v5_test`.
- `00:02 +8 -3: Some tests failed.`

Las pruebas de control (2b, 6, 6b y 7b) comprueban que no cambia lo que debe seguir igual. Por eso pasan en las dos versiones.

**Prueba 7a:** en producción la voz siempre usa la fecha de hoy. La prueba fija el reloj del gateway en un día pasado sólo para demostrar que el rechazo y su mensaje llegan igual al borrador de voz.

## 4. Pruebas existentes cuyo resultado esperado cambia por D-03

- **`e2e_v5_test` (en `d2f186a`):** la aplicación del 10/01 consumía producto recibido en un pase sin fecha, es decir, de hoy. Con D-03 se rechaza. El pase se fecha ahora el 06/01, antes de la aplicación; el resto del escenario y sus cifras no cambian.
- **`fix_inventario_movimientos_test` (en `d2f186a`):** la aplicación del 21/01 de 8 L contaba 3 L devueltos por reversiones fechadas hoy. El 21/01 Ana tenía 4 L + 3 L. Ahora aplica 7 L, también de dos lotes (`-7000`), y las doce aplicaciones extra de «Ver más» van con la fecha de hoy. El caso original de 8 L queda fijado como límite en la prueba 3c.
- **`rec_046_inventory_detail_test` y `rec_047_application_rules_test` (en `4ccaca1`):** sólo cambia el texto esperado. Sus aplicaciones tienen fecha pasada (28/03 y 01/03 en UTC, que en La Paz son el 27/03 y el 28/02), y la decisión D-03 («el mensaje debe indicar producto, fecha y existencia elegible») sustituye «Stock insuficiente para confirmar la aplicación.» por «Glifosato: el 27/03/2026 esa persona tenía 5 L; pidió 5,001 L. …» y por «Glifosato: el 28/02/2026 esa persona tenía 20 L; pidió 20,001 L. …». El rechazo y la ausencia de efectos no cambian.
- `f10_x01_aplicacion_productos_test` también espera «Stock insuficiente…», pero con fecha de hoy, así que no cambia.

## 5. Ejecuciones sobre `4ccaca1`

En tandas de hasta tres archivos, sin la suite completa (la corre el coordinador):

```
flutter test -r expanded test/f10_d03_existencia_historica_test.dart test/f10_d03_existencia_historica_form_test.dart test/e2e_v5_test.dart
00:05 +16: All tests passed!

flutter test -r expanded test/rec_046_inventory_detail_test.dart test/rec_047_application_rules_test.dart test/fix_inventario_movimientos_test.dart
00:02 +11: All tests passed!

flutter test test/f04_rf03_late_operations_test.dart test/f04_rf03_late_screen_test.dart
00:03 +15: All tests passed!
```

Las 16 de la primera tanda son las 14 del repositorio y la voz, la del formulario y `e2e_v5`. La tercera tanda cubre las operaciones tardías (comprobación 5), que siguen igual.

**Antecedente en `d2f186a`, sin repetir sobre `4ccaca1`:** los 48 archivos que mencionan `confirmApplication`, `LateOperation`, FIFO o `VoiceDraftGateway`, más los nuevos, dieron `02:05 +473: All tests passed!`.

## 6. Calidad

- `dart format lib test`: «Formatted 325 files (0 changed)».
- `flutter analyze`: «No issues found!».
- Commits con la identidad de Roderich1, sin trailers. Sin push ni operaciones de GitHub.

## 7. Límites

- **Registros anteriores inconsistentes:** no se recalculan ni se corrigen. Un lote con saldo histórico negativo por esos registros no aporta cupo con fecha pasada (prueba 3d). La ruta de hoy usa el saldo actual (prueba 6b).
- **Negativos transitorios dentro de un día posterior:** el cupo se comprueba al final de cada día, como en RF-03 §2.3. Si un día posterior tiene una salida y después una entrada, el saldo intermedio de ese día puede quedar negativo aunque el del final del día no lo sea.
- **Transferencias:** `transferProductsFifo` acepta por API cualquier fecha pasada y consume con el saldo de hoy. Queda fuera de D-03; la regla vale con los productores actuales de aplicaciones.
- **Formulario:** la vista previa sigue mostrando la existencia de hoy y no añade consultas (lección de las pruebas con *settle* fijo). Para un día pasado, la existencia de esa fecha llega con el rechazo del repositorio al confirmar. Los textos del formulario siguen en tú; los del repositorio, en usted.
- **Voz:** en producción confirma siempre con la fecha de hoy, así que la regla histórica sólo se activa si el reloj del gateway marca un día pasado. Eso sólo ocurre en las pruebas, o si la medianoche pasa entre la apertura y la confirmación.
- **Medianoche:** si el día cambia entre la apertura del formulario y la confirmación, la fecha elegida pasa a ser un día pasado y se aplica la regla histórica.
- Todo es host. No hay comprobación en dispositivo ni en emulador.

## 8. Reversiones: decisión pendiente del autor

Una reversión, de una aplicación o de un pase, devuelve el producto con la fecha en que se revierte, no con la de la operación anulada. Para una aplicación con fecha anterior a la reversión, ese producto no cuenta, aunque la operación revertida haya sido un error que en la realidad no ocurrió. Ejemplo de la prueba 3c: Ana tiene 10 L hoy, y el 21/01 se rechazan 8 L con 7 L elegibles.

Se mantiene tal como está en el código, porque es la convención de RF-03 §2.3 y nunca deja saldos negativos. Alternativas registradas, sin aplicar:
- (a) mantener la convención actual (vigente);
- (b) neutralizar en el cálculo los pares operación + reversión, como si la operación anulada no hubiera existido;
- (c) guardar una columna de fecha efectiva propia de la reversión;
- (d) mostrar un mensaje específico, o pedir un permiso expreso, cuando el rechazo se debe a una reversión posterior.
