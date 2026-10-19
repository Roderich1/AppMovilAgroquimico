# REC-003 (#39): SQLite rechaza una escritura a mitad de `confirmPurchase` (RNF-02)

- **Fecha:** 2026-10-19 (America/La_Paz). Sesión C de Claude Code, por la opción (b) que eligió Roderich Rendón para #39, transmitida por la sesión A.
- **Base:** Mobile `main` `7c37ce8`. Prueba en el commit `dd34289`. Flutter 3.47.2 en Windows 11.
- **Tipo de prueba:** host (`flutter test`, `sqflite_common_ffi`), base en memoria propia de cada prueba. **Sin dispositivo.**
- **Alcance:** no toca `lib/`, el esquema de la app ni las migraciones. El estado del issue y del Project los fija Roderich; este archivo no los cambia.

## Qué faltaba

La conciliación (`REC_CONCILIACION_2026-10-19.md`, fila de #39 en §6) dejaba un único faltante: ninguna prueba hacía que **SQLite** rechazara una escritura a mitad de una transacción. `repository_test.dart:233` es un rollback por un `StateError` del repositorio, y `rec_046…:278` y `rec_047…:88`/`:119` lo son por `BusinessRuleException`. En los tres casos el motor nunca rechaza nada.

## La prueba: `test/rec_039_sqlite_abort_test.dart`

**Fixture (`setUp`):**
- Ana (familia, cobro por uso), Beto (tercero, cobro por asignación), Agro Sur, campaña Verano activa desde el 01/01, Glifosato (L) y Atrazina (KG).
- Compra sembrada del 05/01, de dos líneas:
  - Glifosato 10 L a Bs 100,00 para Ana;
  - Atrazina 2 kg a Bs 200,00 para Beto, con cargo de Bs 400,00.

**Compra intentada (10/02, factura F-200):**
- línea 1: Glifosato 6 L a Bs 120,00, repartido Ana 4 L y Beto 2 L;
- línea 2: Atrazina 3 kg a Bs 210,00 para Beto;
- total Bs 1.350,00.

**Disparador de prueba:**
- Se crea con `CREATE TEMP TRIGGER rec039_abort_second_line BEFORE INSERT ON purchase_items`. Al ser TEMP vive en `sqlite_temp_master` de esa conexión, no en el esquema principal.
- Su cuerpo es `SELECT RAISE(ABORT, 'ENSAYO_REC039_ABORT: segunda linea rechazada por SQLite')`. Se usó `RAISE(ABORT)`, no `RAISE(ROLLBACK)`, así que quien deshace la transacción es la aplicación y no el disparador.
- Su condición `WHEN` exige que, para la compra en curso (`NEW.purchase_id`), ya estén escritos dentro de la misma transacción:
  - 1 línea;
  - 2 asignaciones;
  - 2 lotes;
  - 2 movimientos `PURCHASE_IN`;
  - 1 cargo `PURCHASE_ALLOCATION_CHARGE`, el de Beto.
- Es decir: la cabecera, la primera línea y todos sus efectos ya existen cuando el motor rechaza la segunda línea. No falla antes de escribir.
- No se abrió una segunda conexión.

| Caso | Qué comprueba | Resultado |
|---|---|---|
| «si SQLite rechaza la segunda línea, confirmPurchase no deja nada y, sin el disparador, la misma compra se confirma» | ver el detalle de abajo | PASS |
| «el disparador no salta antes de la segunda línea: con él puesto, una compra de una sola línea se confirma» | control: con el disparador puesto, la línea 1 sola se confirma (total 72000) | PASS |

**Detalle del primer caso:**
1. Guarda el estado inicial:
   - el volcado completo de todas las tablas (`dumpTables`);
   - `sqlite_sequence`;
   - el esquema principal (`sqlite_master`);
   - los saldos derivados:
     - stock `{(Ana, Glifosato): 10000, (Beto, Atrazina): 2000}`;
     - cuentas `{Beto: 40000}`;
     - tablero: compras 140000, pagado 0, familia 0, terceros 40000, recibido 0, stock 12000.
2. Crea el disparador y comprueba que existe en `sqlite_temp_master`.
3. Llama a `repo.confirmPurchase` por el camino normal. Espera un `DatabaseException` con la marca y con `getResultCode()` = 1811 (`SQLITE_CONSTRAINT_TRIGGER`). Un `StateError` o una `BusinessRuleException` no satisfacen ese matcher.
4. Compara contra el estado inicial: todas las tablas, `sqlite_sequence`, `sqlite_master` y los saldos son **idénticos**. No se excluye ninguna tabla de negocio: el disparador TEMP no aparece en `sqlite_master`.
5. Quita el disparador y confirma la misma compra:
   - id 2: los contadores se deshicieron con el rechazo;
   - las filas previas de las seis tablas escritas no cambian, y las demás tablas son idénticas;
   - `sqlite_sequence` y las filas nuevas se comparan con literales (cabecera, 2 líneas, 3 asignaciones, 3 lotes, 3 `PURCHASE_IN` y 2 cargos de Beto, de 24000 y 63000);
   - saldos: stock `{(Ana, Glifosato): 14000, (Beto, Atrazina): 5000, (Beto, Glifosato): 2000}`, cuentas `{Beto: 127000}`, tablero compras 275000, terceros 127000, stock 21000.

**Error que devuelve el motor** (salida de una corrida con una aserción de código provisional; resumida):

```text
SqfliteFfiException(sqlite_error: 1811, , SqliteException(1811): while executing statement,
ENSAYO_REC039_ABORT: segunda linea rechazada por SQLite, constraint failed (code 1811)
Causing statement: INSERT INTO purchase_items (...) VALUES (...),
parameters: 2, 2, 3000, BOB, 21000, 21000, 63000, 63000
```

La sentencia rechazada es la segunda línea: `purchase_id` 2, Atrazina, 3000.

## Comandos y resultado

```text
dart format test/rec_039_sqlite_abort_test.dart        → 0 changed
flutter analyze test/rec_039_sqlite_abort_test.dart    → No issues found!
flutter test test/rec_039_sqlite_abort_test.dart       → +2: All tests passed!
```

La suite completa corre en el CI del PR.

## Mutaciones (locales, no commiteadas)

| Mutación | Resultado |
|---|---|
| El disparador exige 3 asignaciones en vez de 2 (estado que nunca existe) | **falla**: `confirmPurchase` devuelve 2 en vez de lanzar. La condición lee el estado real de la transacción en curso. |
| `_write` (`lib/data/agro_repository.dart`) atrapa el error dentro de la transacción, deja que se confirme y lo relanza después (rollback ausente) | **falla**: el volcado difiere en `account_transactions[1]`, el cargo de Beto de la línea 1, que quedó como residuo. |

Ambas se revirtieron. `git status` quedó limpio, salvo el archivo de prueba antes de su commit.

## Lo que esta prueba no cubre

- Equivalencia de esquema desde V1, V2, V4 y V5, y restricciones sobre una base migrada: siguen como límites históricos, sin cambios.
- Un rechazo del motor en otras escrituras (aplicación, transferencia, reversión). Todas pasan por el mismo `_write`, pero no se ensayaron aquí.
- Un fallo de E/S real (disco lleno, corte de energía). Está fuera del alcance de una prueba de host.
