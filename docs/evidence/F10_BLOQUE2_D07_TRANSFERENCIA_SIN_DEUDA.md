# Bloque 2 · D-07 — Transferencia sin deuda

- **Fecha real:** 2026-10-27 (America/La_Paz), hacia las 13:50. Rama `feat/d07-transferencia-sin-deuda` sobre Mobile `main` `ed9c55c`, worktree `_wt/A-D07`.
- **Decisión:** del autor (Roderich Rendón), del 2026-10-27 (`_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`, D-07). RN-35 **se mantiene**: transferir no genera ningún cargo. No hay `TRANSFER_CHARGE`. No se modifican transferencias, asientos ni saldos históricos. Vender, prestar o cobrar entregas queda fuera.
- **Trazabilidad:** RN-35, RN-10, RN-27, CU-08, RF-11.
- **Tipo de prueba:** pruebas de host (`flutter test`, sqflite FFI en memoria). No hay comprobación en dispositivo ni en emulador para este frente.

## 1. Commits

| SHA | Qué |
|---|---|
| `94b8ebe` | Aviso en la confirmación. Rótulos de historial y costo de referencia. Prueba `test/f10_d07_transferencia_sin_deuda_test.dart` |
| (este commit) | RN-35 en `docs/15_BUSINESS_RULES.md`, `docs/07_SCREENS.md` (P-12, P-16, P-17), `docs/06_USER_FLOWS.md` (UF-07) y esta evidencia |

Archivos de `lib/`: `domain/labels.dart` (`transferNoDebtNotice`, `transferNoDebtLabel`), `presentation/widgets/common.dart` (los exporta), `presentation/screens/transfer_form_screen.dart`, `transfers_screen.dart` e `inventory_detail_screen.dart`. **No se tocó `agro_repository.dart`.** En modo propio las transferencias siguen sin existir: no se cambiaron guardas ni rutas.

## 2. Textos antes y después

| Pantalla | Antes (`ed9c55c`) | Después |
|---|---|---|
| Confirmar transferencia | «De: Ana / A: Beto», líneas de producto y nada más | Lo mismo, y después, en negrita: «Esta transferencia entrega producto a Beto, pero no genera una deuda.». Debajo: «No se registra ningún cargo ni cobro a Beto. El costo del producto entregado sólo es de referencia, no un precio de venta.». Con uno o varios productos la frase es la misma. |
| Nueva transferencia, fila de producto | «X disponibles · N lote(s) · costo Y/L» | «X disponibles · N lote(s) · costo de referencia Y/L» |
| Transferencias, subtítulo | «Pases de productos de una persona a otra, con su costo.» | «Entregas de producto de una persona a otra. No generan deuda; el costo es sólo de referencia.» |
| Transferencias, fila | «10/01/2026 · Glifosato 3 L» | «10/01/2026 · Glifosato 3 L» y, en otra línea, «Entrega sin deuda» |
| Transferencias, detalle | «1 producto(s) · 1 lote(s) · costo 300,00 Bs» | «1 producto(s) · 1 lote(s) · costo de referencia 300,00 Bs» y «Es el costo de compra del producto entregado, no un precio de venta: Don Carlos no debe nada por esta entrega.» |
| Revertir transferencia | «Costo 300,00 Bs» / «El stock volverá a la persona de origen. Esta acción no se puede deshacer.» | «Costo 300,00 Bs, sólo de referencia: la transferencia no generó deuda.» / «El stock volverá a la persona de origen y ninguna cuenta cambia. Esta acción no se puede deshacer.» |
| Detalle de producto, ayuda de «Movimientos» | «Lo que explica el saldo: compras, aplicaciones, pases y reversiones, del más reciente al más antiguo.» | «Lo que explica el saldo: compras, aplicaciones, pases (entregas sin deuda) y reversiones, del más reciente al más antiguo.» |
| Detalle de producto, movimientos del bloque 1 | «Pase a Don Carlos» · «10/01/2026 · Ana» | El título no cambia. Subtítulo: «10/01/2026 · Ana · entrega sin deuda». Lo mismo en «Recibido de X». En «Pase revertido: …» se añade «· sin deuda». |

## 3. Pruebas

Archivo nuevo: `test/f10_d07_transferencia_sin_deuda_test.dart`, con 6 pruebas:

1. **A un familiar** (Ana → Beto, desde el formulario real): la confirmación muestra la frase con «Beto». Al confirmar, la transferencia existe y `account_transactions` es idéntica fila por fila a la de antes. No aparece ningún `TRANSFER_CHARGE`.
2. **A un tercero con cobro por compra y dos productos** (Ana → Don Carlos, `THIRD_PARTY` / `BY_PURCHASE_ALLOCATION`, comprobado en la base): Don Carlos ya tiene su `PURCHASE_ALLOCATION_CHARGE` de una compra propia. La confirmación muestra las dos líneas y la frase con «Don Carlos». Después de confirmar hay 1 transferencia con 2 ítems, `account_transactions` no cambia y su saldo sigue en 200,00 Bs.
3. «Revisar» cierra la confirmación sin guardar nada.
4. Lista y detalle de Transferencias: «Entrega sin deuda», «costo de referencia» y «no debe nada por esta entrega».
5. Aviso de reversión: «no generó deuda» y «ninguna cuenta cambia». Cancelar no cambia `account_transactions`.
6. Movimientos del detalle de producto: pases con «entrega sin deuda», sus reversiones con «sin deuda» y la compra sin cambios.

**Sobre la base** (`git checkout ed9c55c --` sobre los cinco archivos de `lib/`; con `git diff --stat ed9c55c -- lib/` vacío durante la corrida; después, `git checkout HEAD --`):

```
flutter test test/f10_d07_transferencia_sin_deuda_test.dart
Found 0 widgets with text "Esta transferencia entrega producto a …   (pruebas 1 y 2)
Found 0 widgets with key [<'transfer-no-debt-notice'>]               (prueba 3)
Found 0 widgets with text "Entregas de producto de una persona a otra. …  (prueba 4)
does not contain 'sólo de referencia: la transferencia no generó deuda.'  (prueba 5)
has no match for 'Pase a Don Carlos | 10/01/2026 · Ana · entrega sin deuda'  (prueba 6)
00:12 +0 -6: Some tests failed.
```

**Con el cambio** (`94b8ebe`):

```
flutter test test/f10_d07_transferencia_sin_deuda_test.dart
00:13 +6: All tests passed!
```

**Sobre `account_transactions`:** RN-35 ya se cumplía en la base. Las pruebas 1 y 2 fallan allí por el aviso, antes de llegar a la comparación de asientos. Para comprobar que esa comparación no pasa sola, se añadió **temporalmente** a `transferProductsFifo` un `txn.insert('account_transactions', …)` por el costo transferido. No se guardó en ningún commit y se revirtió con `git checkout HEAD -- lib/data/agro_repository.dart`. Resultado de `flutter test … --plain-name "confirmación de la transferencia"`: `00:08 +1 -2: Some tests failed.` Fallaron las pruebas 1 y 2 en la comparación de `account_transactions` (líneas 211 y 258). La 3 pasa porque no confirma.

**Pruebas existentes relacionadas** (no se corrió la suite completa por la carga del host). Se corrieron 20 archivos con `flutter test -j 2`: el nuevo, `e2e_v5`, `f04_admin_owner_restore_ui`, `f04_bug_01_reverse_transfer`, `f04_bug_02_reverse_purchase_after_transfer`, `f04_repository_guards`, `fix_inventario_movimientos`, `formatting_and_labels`, `hierarchical_navigation`, `numeric_input`, `personal_mode_flows`, `rec_046_051_net_figures`, `rec_046_inventory_detail`, `rec_048_transfer_guards`, `rec_050_reversal_rules`, `responsive_v5`, `ui_polish`, `v5_domain`, `f04_activation_app_policy` y `set_state_contract`. Resultado: `01:25 +203 -1: Some tests failed.`

El único fallo fue «restaurar desde Liquidación una copia del mismo Member en inventario propio deja la navegación en propio sin reiniciar (#26)», que esperaba `OperationMode.personal` y obtuvo `shared`. Esa prueba no toca transferencias ni los textos cambiados. Corrida sola en la rama: `00:28 +7: All tests passed!`. Se trata como inestable bajo carga paralela, no como regresión.

- `dart format lib test`: «Formatted 324 files (1 changed)». El cambio fue en la prueba nueva, antes del commit. Sin cambios después.
- `flutter analyze`: «No issues found!».

## 4. Pruebas existentes ajustadas

Ninguna. `rec_050_reversal_rules_test` busca `Costo 300,00` dentro del diálogo de reversión. El texto nuevo conserva ese prefijo («Costo 300,00 Bs, sólo de referencia: …»). `fix_inventario_movimientos_test` compara los títulos de los movimientos, que no cambian, y los subtítulos de una compra y una aplicación, que tampoco.

## 5. Límites

- Hueco conocido y aceptado por la decisión: un tercero con `BY_PURCHASE_ALLOCATION` que recibe producto por transferencia no queda debiendo nada. RN-10 sólo carga al comprar y RN-27 sólo carga por consumo con `BY_ACTUAL_USAGE`. El aviso lo hace explícito, pero no lo cobra. Vender, prestar o cobrar entregas queda para otro bloque.
- El aviso no anticipa cargos futuros por aplicar lo recibido, por ejemplo el de un familiar que paga por consumo (efecto secundario de RN-35). Se omitió a propósito para no adelantar reglas de Cuentas que cambian en otros frentes (D-04, E-15).
- Los textos de otras pantallas no cambian: Inicio, Cuentas, reportes y la bitácora no muestran transferencias.
- Pruebas de host solamente. No hubo comprobación en emulador ni en teléfono.
