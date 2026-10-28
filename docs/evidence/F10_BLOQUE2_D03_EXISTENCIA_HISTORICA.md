# Bloque 2 — D-03: existencia histórica en aplicaciones con fecha pasada

- **Fecha real:** 2026-10-27 y 2026-10-28 (America/La_Paz).
  - 2026-10-27: primera versión hacia las 13:50 y ajustes de la revisión cruzada hacia las 14:10.
  - 2026-10-28: anulaciones demostradas, hacia las 11:55 (§8), y ajustes de su revisión cruzada, hacia las 12:10 (§8.5).
- **Rama:** `feat/d03-existencia-historica-aplicacion` sobre Mobile `main` `ed9c55c`. Estado verificado: `39e7229`.
- **Fuente:** decisiones del autor, Roderich Rendón, del 2026-10-27 (bloque 2, D-03) y del 2026-10-28 (anulaciones demostradas, §8). Son decisiones del autor; no se atribuyen al tutor ni a la Directiva. El análisis previo está en la revisión integral del 2026-10-26 (decisiones de negocio, §1).
- **Trazabilidad:** RN-25 (stock suficiente, precisada), RN-26 (FIFO), RF-03 (elegibilidad temporal de §2.3), RF-13 (reversiones), CU-09 (aplicación).
- **Procedencia:** sólo pruebas de **host** (`flutter test`, Windows 11, Flutter 3.47.2, reloj real del 2026-10-27 y del 2026-10-28). Sin dispositivo, sin emulador y sin personas.
- **Esta mejora no forma parte de X01 ni de X02**, y sus evidencias no cambian.

## 1. Commits

| SHA | Qué |
|---|---|
| `d2f186a` | `confirmApplication`: con un día local efectivo anterior a hoy, la elegibilidad de RF-03 (`_lotsAvailableAt`); con el día de hoy, la ruta de siempre (`_lotsAvailableNow`). `HistoricalStockException`. Pruebas nuevas; `e2e_v5_test` y `fix_inventario_movimientos_test` ajustadas (§4); contrato §2.6; precisión de RN-25 |
| `faa628a` | Primera versión de esta evidencia |
| `4ccaca1` | Ajustes de la revisión cruzada: el rechazo histórico se aplica siempre, también cuando tampoco alcanza el saldo de hoy; mensaje en dos casos; `heldBase` y `_lotHistoryAt`; pruebas 1b, 3b, 3c y 3d; `rec_046` y `rec_047` cambian el texto esperado (§4); contrato §2.6 ampliado |
| `a7fac66` | Evidencia actualizada a `4ccaca1` |
| `d3894db` | Decisión del 2026-10-28: la proyección histórica (`_lotHistoryAt`) neutraliza los pares operación + reversión con vínculo de anulación demostrado; cupo limitado al saldo de hoy; prueba nueva `f10_d03_anulaciones_demostradas_test`; 3c cambia y se añade 3c-bis; `fix_inventario_movimientos_test` vuelve a su versión de `ed9c55c`; contrato §2.3 y §2.6; RN-25 (§8) |
| `506ff8c` | Evidencia actualizada a `d3894db` |
| `39e7229` | Ajustes de la revisión cruzada de `d3894db`: el comentario describe el tope como defensivo; pruebas nuevas (pase de dos lotes, tres casos negativos de pase, consumo q/r, otro lote elegible) y bitácora sin corregir en 3c; F04 §2.3 y §2.6 (§8.5) |
| (este commit) | Evidencia actualizada a `39e7229` |

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
| 3c. (versión del 2026-10-27, sustituida el 2026-10-28, §8) Límite de las reversiones: 8 L el 21/01 → `HistoricalStockException` con 7000 elegibles | falla: `emitted <3>` (se aceptó) | pasaba en `4ccaca1` |
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
- **`fix_inventario_movimientos_test` (en `d2f186a`):** la aplicación del 21/01 de 8 L contaba 3 L devueltos por reversiones fechadas hoy. El 21/01 Ana tenía 4 L + 3 L. Ahora aplica 7 L, también de dos lotes (`-7000`), y las doce aplicaciones extra de «Ver más» van con la fecha de hoy. El caso original de 8 L queda fijado como límite en la prueba 3c. **El 2026-10-28** esta prueba volvió a su versión de `ed9c55c` (§8.3).
- **`rec_046_inventory_detail_test` y `rec_047_application_rules_test` (en `4ccaca1`):** sólo cambia el texto esperado. Sus aplicaciones tienen fecha pasada (28/03 y 01/03 en UTC, que en La Paz son el 27/03 y el 28/02), y la decisión D-03 («el mensaje debe indicar producto, fecha y existencia elegible») sustituye «Stock insuficiente para confirmar la aplicación.» por «Glifosato: el 27/03/2026 esa persona tenía 5 L; pidió 5,001 L. …» y por «Glifosato: el 28/02/2026 esa persona tenía 20 L; pidió 20,001 L. …». El rechazo y la ausencia de efectos no cambian.
- `f10_x01_aplicacion_productos_test` también espera «Stock insuficiente…», pero con fecha de hoy, así que no cambia.

## 5. Ejecuciones sobre `4ccaca1` (2026-10-27; las del 2026-10-28, en §8.2)

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

## 8. Reversiones: anulaciones demostradas (decisión del autor del 2026-10-28)

- **Fecha real:** 2026-10-28 (America/La_Paz), hacia las 11:55. Base de comparación: `a7fac66`. Cambio: `d3894db`. Todo es host.
- **Decisión** (Roderich Rendón, 2026-10-28), literal: «Conservar operación, reversión y fechas reales en la bitácora; neutralizar sus efectos en la proyección histórica únicamente cuando el vínculo de anulación esté demostrado. La corrección debe: conservar la fecha original de adquisición; impedir disponibilidad duplicada; respetar los movimientos posteriores y el saldo actual; no reescribir costos ni registros históricos; no utilizar el PIN para permitir existencias insuficientes. El caso de Ana sólo se acepta si el historial corregido acredita existencia suficiente y los demás controles se cumplen. Conserva RN-39 y la guarda vigente de paso a modo propio. Las dos modificaciones opcionales no entran en este bloque.»
- **Dónde:** `_lotHistoryAt`, que filtra `_lotsAvailableAt`. Es la proyección histórica única, compartida por la aplicación con fecha pasada (D-03) y la operación tardía (RF-03 §2.3). La ruta de hoy (`_lotsAvailableNow`) no cambia.

### 8.1 Vínculo de anulación demostrado

Se neutraliza un par de movimientos (`_demonstratedAnnulments` y `_annulmentRecorded`) sólo si se cumplen todas estas condiciones:

1. **Mismo lote.**
2. **Misma operación,** con el mismo `reference_id`:
   - aplicación: `APPLICATION_OUT`/`APPLICATION` con `APPLICATION_REVERSAL`/`APPLICATION_REVERSAL`;
   - pase, en el lote de origen: `TRANSFER_OUT`/`TRANSFER` con `TRANSFER_REVERSAL_IN`/`TRANSFER_REVERSAL`.
3. **Exactamente una salida y una reversión** de esa operación en el lote.
4. **Cantidades opuestas e iguales**, con la salida negativa.
5. **La operación consta como revertida:**
   - aplicación: `applications.reversed_at` no nulo y `status = 'REVERSED'`, con un único consumo en ese lote, revertido y por la misma cantidad;
   - transferencia: `transfers.reversed_at` no nulo y `status = 'REVERSED'`, con una única fila de `transfer_lot_items` para ese lote de origen, por la misma cantidad y con el lote de destino anulado.
6. **Auditoría:** si existe `reversal_audit` de la operación, sus efectos nombran el movimiento de reversión.

Si falta algo o hay ambigüedad, no se neutraliza nada de esa operación. Las reversiones de compra no se neutralizan, porque el lote queda anulado.

- **Efecto:** el par se excluye del cálculo; nada se escribe.
- **Sin duplicación:** las operaciones posteriores siguen descontando. El mínimo de los saldos corregidos posteriores limita el cupo a lo que queda hoy, porque un par neutralizado suma cero. El tope explícito del saldo de hoy en el código es defensivo e inalcanzable con datos válidos.
- **PIN:** no interviene.
- **Mensaje:** se calcula sobre la historia corregida.

### 8.2 Pruebas

Archivos:
- nuevo: `test/f10_d03_anulaciones_demostradas_test.dart`, 10 pruebas;
- ayudante nuevo: `test/support/d03_dump.dart`, que comprueba que sólo aparecen las filas de la aplicación aceptada y que ninguna fila previa cambia;
- cambiadas: 3c y 3c-bis en `f10_d03_existencia_historica_test.dart`.

| Prueba | Base `a7fac66` | `d3894db` |
|---|---|---|
| 3c. Ana: historia corregida 10 L el 21/01 → 8 L aceptados (7 L del 05/01, 1 L del 06/01); sólo filas nuevas | falla: rechazo «Glifosato: el 21/01/2026 esa persona tenía 7 L; pidió 8 L. …» | pasa |
| 3c-bis. Ana, con 4 L de lo devuelto usados hoy → rechazo «tenía 10 L; de eso quedan 6 L…; pidió 8 L» | falla: el mensaje dice «tenía 7 L; de eso quedan 6 L» | pasa |
| Vínculo demostrado (aplicación revertida): 0,5 L el 12/10 aceptados; sólo filas nuevas | falla: rechazo «tenía 1 L; de eso quedan 0 L…» | pasa |
| Ruta de hoy con un par revertido: usa el saldo actual (control) | pasa | pasa |
| Sin duplicación (el límite lo pone el mínimo de los saldos posteriores): con 0,6 L de lo devuelto usados hoy, 0,5 L el 12/10 rechazado con «quedan 0,4 L»; 0,4 L aceptado | falla: dice «quedan 0 L» | pasa |
| Sin vínculo: falta `reversed_at` / la referencia no coincide / la cantidad no coincide / otro lote → rechazo «quedan 0 L», sin efectos (4 pruebas, guardas) | pasan | pasan |
| Transferencia revertida: el origen recupera 1 L el 18/10 y se acepta; el destino anulado no aporta («no tenía este producto») | falla: «Bellator: el 18/10/2026 esa persona tenía 0,4 L; pidió 1 L. …» | pasa |
| Tardía con una reversión auditada con PIN: se confirma; sólo filas nuevas | falla: `Expected: …confirmed Actual: …conflict` | pasa |
| Tardía con una auditoría que no nombra el movimiento: conflicto `LATE_STOCK_UNAVAILABLE`, sin efectos (guarda) | pasa | pasa |
| `fix_inventario_movimientos_test`, restaurada a `ed9c55c` (8 L de dos lotes) | falla (3 pruebas): rechazo «tenía 7 L; pidió 8 L» | pasa |

**Comandos y salidas literales:**
```
git checkout a7fac66 -- lib/data/agro_repository.dart
flutter test --timeout 120s -r expanded test/f10_d03_anulaciones_demostradas_test.dart test/f10_d03_existencia_historica_test.dart test/fix_inventario_movimientos_test.dart
00:04 +20 -9: Some tests failed.
git checkout HEAD -- lib/data/agro_repository.dart
flutter test --timeout 120s -r expanded (los mismos tres archivos)      → 00:07 +29: All tests passed!
```

Tandas sobre el árbol de `d3894db`, de tres archivos como mucho:
```
f10_d03_anulaciones_demostradas_test + f10_d03_existencia_historica_test        → 00:02 +25: All tests passed!
fix_inventario_movimientos_test + rec_046_inventory_detail_test + rec_047_application_rules_test → 00:02 +11: All tests passed!
e2e_v5_test + f10_d03_existencia_historica_form_test + f04_rf03_late_operations_test → 00:05 +15: All tests passed!
f04_rf03_late_screen_test + f04_rf13_reversal_audit_test + rec_050_reversal_rules_test → 00:07 +25: All tests passed!
f04_bug_01_reverse_transfer_test + f04_bug_02_reverse_purchase_after_transfer_test + f04_rf13_reversal_backup_test → 00:01 +17: All tests passed!
```

`dart format lib test`: «Formatted 327 files (0 changed)». `flutter analyze`: «No issues found!».

### 8.3 Pruebas existentes cuyo resultado esperado cambia por esta decisión

- **3c** (`f10_d03_existencia_historica_test`): el caso de Ana pasa de rechazado con 7 L elegibles a aceptado con la historia corregida (10 L).
- **`fix_inventario_movimientos_test`** vuelve exactamente a su versión de `ed9c55c`: 8 L de dos lotes y las doce aplicaciones extra en enero. El ajuste de `d2f186a` (§4) se debía sólo a la convención que esta decisión corrige.
- **Sin cambios:** las tardías (`f04_rf03_late_operations_test` y `f04_rf03_late_screen_test`) y las de reversión (`f04_rf13_reversal_audit_test`, `rec_050`, `f04_bug_01`, `f04_bug_02` y `f04_rf13_reversal_backup_test`), que no tenían pares neutralizables con aplicaciones posteriores con fecha pasada.

### 8.4 Observaciones

- **Saldo cronológico de la bitácora:** sin corregir, puede verse negativo entre la fecha de la operación anulada y la de su reversión. Por ejemplo, después de aceptar los 8 L, el lote del 05/01 de Ana queda en −3 L el 21/01 en la bitácora sin corregir (Ana en total, −1 L), hasta las reversiones de hoy. Recalculado: lote del 05/01, +10 −3 −2 −1 −7 = −3 L; lote del 06/01, +3 −1 = +2 L. Lo comprueba 3c (§8.5). Ninguna vista de la app muestra un saldo acumulado de existencias, y la decisión pide conservar las fechas reales en la bitácora.
- **RF-03 §2.3** decía que el cupo «no deja negativo ningún saldo histórico». Ahora se lee sobre la proyección corregida; se añadió esa precisión en §2.3. No contradice el objetivo de §2.3, que es no consumir material que otra operación usó después: lo anulado por un vínculo demostrado no se usó.
- **Sin cambios:** RN-39 y la guarda de paso a modo propio. Las dos modificaciones opcionales no entran en este bloque.

### 8.5 Ajustes de la revisión cruzada (2026-10-28, hacia las 12:10, `39e7229`)

- **Contrato F04:**
  - §2.3: «no deja negativo ningún saldo de la proyección corregida ni el actual».
  - §2.6: desde el 2026-10-28 la tardía usa la misma proyección corregida. Extenderla a RF-03 es un criterio de aplicación del coordinador («la proyección histórica es una sola»), pendiente de que el autor lo confirme de forma expresa.
  - §2.6: cifra de Ana precisada y tope descrito como defensivo.
- **Código:** sólo cambia el comentario del tope del saldo de hoy (defensivo e inalcanzable con datos válidos). La lógica es la de `d3894db`.

**Pruebas nuevas.** «Base» es el `lib/` de `a7fac66`; «mutación» es una mutación temporal, revertida sin commit.

| Prueba | Base `a7fac66` | Mutación | `39e7229` |
|---|---|---|---|
| (a) L1 de 0,4 L el 10/10 y L2 de 0,6 L el 11/10; pase de 1 L el 15/10 revertido hoy; hoy se aplican 0,5 L (L1 0,4 + L2 0,1). El 16/10, 1 L se rechaza con cupo 0 + 0,5 L («tenía 1 L; de eso quedan 0,5 L»), sin duplicar; 0,5 L se aceptan, sólo de L2 | falla: «… esa persona no tenía este producto; pidió 1 L» | — | pasa |
| (b) Pase revertido sin vínculo: destino sin anular / `status` distinto de `REVERSED` / otra cantidad en `transfer_lot_items` (3 pruebas). Rechazo «tenía 0,4 L; pidió 1 L» sin efectos | pasan (guardas) | **fallan las 3**: `emitted <1>` (se aceptan) | pasan |
| (c) Consumo de la aplicación con otra cantidad (q) / sin `reversed_at` (r); movimientos opuestos e iguales (2 pruebas) | pasan (guardas) | **fallan las 2** | pasan |
| (d) Reversión movida a otro lote **elegible** el 12/10: 1,5 L rechazado con «tenía 2 L; de eso quedan 1 L»; 1 L aceptado sólo del otro lote | pasa (guarda) | pasa | pasa |
| (e) 3c: el lote del 05/01 queda en −3000 el 21/01 en la bitácora sin corregir; el del 06/01, en +2000; la historia corregida da 0 el 21/01 y nunca es negativa | falla (3c, rechazo) | — | pasa |

**Mutaciones**, en `_annulmentRecorded`, con `flutter test --timeout 120s -r expanded test/f10_d03_anulaciones_demostradas_test.dart`:
- **Rama de transferencias** (`if (operationType == 'TRANSFER') return true;`): `00:02 +14 -3: Some tests failed.` Fallan exactamente las tres de (b), con `Actual: <Instance of 'Future<int>'> Which: emitted <1>`.
- **Rama de aplicaciones** (`return true;` al entrar): `00:03 +13 -4: Some tests failed.` Fallan las dos de (c), la de «falta la marca reversed_at» y la de la auditoría que no nombra el movimiento.
- Las dos se revirtieron con `git checkout HEAD -- lib/data/agro_repository.dart`, sin commit.
- (d) no depende de `_annulmentRecorded`, porque en ningún lote hay salida y reversión de la misma operación. Ejercita el emparejamiento por lote (condiciones 1 a 3) en un lote elegible: si la reversión movida se emparejara con la salida del primer lote, el cupo sería 2 L y 1,5 L se aceptaría.

**Salidas literales sobre `39e7229`** (`--timeout 120s`, tandas de tres como mucho):
```
f10_d03_anulaciones_demostradas_test + f10_d03_existencia_historica_test + f10_d03_existencia_historica_form_test → 00:05 +33: All tests passed!
fix_inventario_movimientos_test + rec_046_inventory_detail_test + rec_047_application_rules_test            → 00:02 +11: All tests passed!
f04_rf03_late_operations_test + f04_rf03_late_screen_test + f04_rf13_reversal_audit_test                      → 00:03 +32: All tests passed!
f04_bug_01_reverse_transfer_test + rec_050_reversal_rules_test                                                → 00:06 +15: All tests passed!
```

Base `a7fac66` (sólo `lib/`), archivos D-03 de repositorio: `00:04 +25 -7: Some tests failed.` Fallan:
- vínculo demostrado;
- sin duplicación;
- 3c y 3c-bis;
- transferencia revertida;
- pase de dos lotes;
- tardía con reversión auditada.

Pasan las guardas y los controles.

`dart format lib test`: «Formatted 327 files (0 changed)». `flutter analyze`: «No issues found!».

## 9. Fallo de la CI en UTC y corrección (`cc74661`, 2026-10-28)

**Fallo:** en los dos PR fallaron las mismas dos pruebas.

| PR | HEAD | Run | Resultado |
|---|---|---|---|
| #161 (composición) | `e5ba07c` | 40718635052 | «2057 tests passed, 2 failed, 4 skipped.» |
| #156 | `a7fac66` | 40718556821 | «1919 tests passed, 2 failed, 4 skipped.» |

| Prueba | Esperado | Recibido |
|---|---|---|
| `rec_046_inventory_detail_test` | `… el 27/03/2026 …` | `… el 28/03/2026 …` |
| `rec_047_application_rules_test` | `… el 28/02/2026 …` | `… el 01/03/2026 …` |

**Causa:** el texto esperado fijaba la fecha en hora de La Paz para un instante UTC de medianoche. La suite principal de la CI corre en UTC, y en UTC el mensaje dice el día UTC. El código es correcto en las dos zonas: el mensaje usa el día local del teléfono.

**Corrección:** sólo en las pruebas. La fecha esperada ahora se calcula con `formatDate(localDay(instante))`, la misma conversión que usa el mensaje. `lib/` no cambia.

**Verificación en el host** (La Paz): `flutter test --timeout 120s test/rec_046_inventory_detail_test.dart test/rec_047_application_rules_test.dart` da `00:01 +7: All tests passed!`.

La comprobación en UTC queda a cargo de la CI: en Windows, Dart no respeta la variable `TZ`.
