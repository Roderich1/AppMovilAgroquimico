# Bloque B: altas en el formulario, revisiones y aviso de lote vencido (2026-11-05)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-05. Pruebas nuevas a las ~13:42, commits a las 13:44–13:45 y suite completa después, hora de Bolivia (UTC−4) |
| Procedencia | **HOST** (Windows 11, Flutter 3.47.2 stable, `sqflite_common_ffi`). Nada de esta página es EMULADOR ni DEVICE |
| Rama | `feat/uxj-b-altas-vencimiento`, creada desde `f534015` (#191, `feat/ux-presentacion-altas`) |
| Commits verificados | `b4dba09` (primera suite completa) y `a116747` (código final; esta página va en el commit siguiente) |
| Fuera de alcance | Rutas, menús y listados (otros bloques), sincronización, voz |

## 1. Qué cambia

| Área | Cambio |
|---|---|
| Diálogos (`catalog_dialogs.dart`) | `createPersonFromDialog(purpose:)`: la regla de Catálogos —sólo en inventario compartido; en propio registra sólo el titular (#26)—, comprobada de nuevo con la modalidad leída en ese momento. `PersonDialog(roles:)` ofrece sólo los tipos que pueden cumplir el papel del formulario (`canActAs`, con `isOwner: false`: una persona nueva nunca es el titular) |
| Compra | «Agregar persona» en los selectores de persona de «¿Para quién es?» (toda para una persona y cada fila del reparto), sólo en compartido; queda elegida en el selector desde el que se pidió. El botón que añade una línea pasa de «Agregar producto» a **«Añadir otro producto»** (`purchase-add-line`). Revisión: el total aparece **una vez** («TOTAL COMPRA»; se quita «Importe: …») y la pregunta es **«¿Ya pagaste al proveedor?»**; el reparto por línea se conserva |
| Aplicación | «Agregar persona» en el selector de persona (compartido, sin plan): sólo Familiar o Tercero, porque un Administrador que no es titular no puede aplicar. Paso 2: dice qué productos del catálogo no tienen existencias de la persona y por qué no aparecen; botón **«Registrar compra»** que abre `/compras/nueva` con `push` y, al volver, conserva el borrador y relee existencias y costos. Resumen: costo estimado con una ayuda breve desplegable (`application-cost-help`); el cargo se conserva |
| Aviso de lote vencido | `previewApplicationLots` (repositorio, sólo lectura) devuelve los lotes que consumiría la aplicación con **la misma regla** que la escritura: el reparto FIFO se extrajo a `fifoTakes` y lo usan `confirmApplication` y la previsión. El resumen muestra «Se usará producto vencido» si algún lote previsto vence **antes de la fecha efectiva** de la aplicación |
| Planificación | Ya se podía planificar un producto sin existencias (§3): sin cambio de regla. Único cambio: el selector «Agregar producto» ya no autoelige el único producto (ver §3.1) |

## 2. Decisiones

- **«Vence hoy» no es vencido.** Un lote que vence el mismo día de la aplicación se indica aparte («Vence hoy», o «Vence el día de la aplicación» si la fecha es pasada) y no como vencido. Es la misma regla de `classifyExpiry` (F04-AV, decisión del autor del 2026-11-01), tomando como «hoy» el día de la aplicación con plazo 0.
- **Aplicación histórica.** Se compara con la fecha efectiva de la aplicación, no con hoy. Los lotes previstos son los del cupo histórico de D-03 (`_lotsAvailableAt`), los mismos que usará `confirmApplication`.
- **Sólo informa.** El aviso no bloquea ni cambia el orden de consumo. Si la previsión no se puede leer (por ejemplo, el cupo de una fecha pasada no alcanza), no se avisa y la confirmación valida como siempre.
- **Quién puede crear personas.** La app sólo lo decide por la modalidad (Catálogos oculta «Agregar persona» en propio). El repositorio (`addPerson`) no tiene guarda propia; no se añadió para no cambiar reglas fuera del encargo.
- **Planificación sin existencias.** `addPlanMulti` no exige existencias y el formulario ya ofrece todos los productos del catálogo y muestra «comprar …». No había nada que corregir.

## 3. Pruebas HOST

Archivo nuevo `test/uxj_b_altas_vencimiento_test.dart` (app completa sobre base en archivo, repositorio real, modalidad compartida; las dos últimas, sobre el repositorio):

| Caso | Qué comprueba |
|---|---|
| (c1) | Catálogo vacío (proveedor y producto archivados): se crean desde el selector vacío y quedan elegidos; la cantidad escrita se conserva |
| (c2) | Con «Proveedor» elegido, crear «Agro Sur» lo deja elegido (también tras más fotogramas: la autoselección no lo pisa) |
| (c3) | Cancelar «Crear producto»: la línea y el proveedor siguen igual y no se escribe ningún producto |
| (c4) | «Agregar persona» en «Toda para una persona» queda elegida (rol Familiar); en «Repartir entre varias», queda en la fila 2 y la fila 1 sigue vacía |
| (c5) | «Añadir otro producto» agrega una línea; «Agregar producto» ya no está; cada línea mantiene «Crear producto» |
| (c6) | Revisión: el total una sola vez, sin «Importe», «¿Ya pagaste al proveedor?», «Para: Hermana» visible; sin respuesta no se guarda |
| (a1) | «Agregar persona» en Aplicación no ofrece «Administrador»; Tercero «Peón» queda elegido; «Crear chaco» con dueño Peón; paso 2 dice «Sin existencias de Peón: Glifosato» y ofrece «Registrar compra» |
| (a2) | «Registrar compra» → compra de Mancozeb para Hermana → vuelta: paso 2, línea de Glifosato 1 L, Mancozeb ya agregable; en el paso 1 siguen persona, chaco, área 0,4 y fecha de hoy |
| (a3) | Resumen: costo, ayuda desplegable y cargo; lote L-77 vencido ayer → «Se usará producto vencido»; se confirma igual |
| (a4) | Lote que vence hoy → «Vence hoy», sin aviso de vencido |
| (p1) | Planificar Glifosato para la hermana sin existencias: «comprar 1 L» y el plan se guarda |
| (r1) | Dos lotes (el más antiguo sin vencimiento): 0,5 L sólo usa el antiguo y no avisa; 2 L usa 1 L de cada uno y avisa del lote B. Los consumos escritos por `confirmApplication` son exactamente los previstos |
| (r2) | Lote que vence el 10/03/2026 (vencido hoy): aplicación del 05/03 no avisa; del 10/03, «vence ese día»; del 15/03, vencido |
| unidad | `expiryAtApplication`: el mismo día → `sameDay`; el día anterior → `expired`; posterior o sin fecha → nada |

Pruebas existentes ajustadas al texto nuevo (sin cambiar lo que comprueban): `f04_admin_owner_restore_ui_test`, `f10_compat_129_presentacion_test`, `f10_compra_destinatario_explicito_test`, `ux_altas_en_contexto_test` («Añadir otro producto») y `f10_x01_pago_revision_test` («Indica si ya pagaste al proveedor.»). También `tool/f10_eval/ui.py` (arnés del emulador).

| Comando (sobre `b4dba09`) | Resultado |
|---|---|
| `dart format --set-exit-if-changed lib test` | 381 archivos, 0 cambiados |
| `flutter analyze` | `No issues found!` |
| `flutter test test/uxj_b_altas_vencimiento_test.dart` | **14 pasan** (`00:35 +14: All tests passed!`) |
| `flutter test` sobre los 34 archivos de `test/` que montan las pantallas o diálogos tocados | **268 pasan, 0 fallan** (`01:12 +268: All tests passed!`) |
| `flutter test` (suite completa) sobre `b4dba09` | `05:40 +2295 ~3 -9: Some tests failed.` Ver §3.1 |
| Los 7 archivos con fallos, aislados, sobre `b4dba09` | todos pasan (`f08_prev_01_previo_ui` 8, `f12_est_07_estimation_ui` 4, `fix_aplicacion_costo_cargo` 4, `f10_backup_extract_limits` 28, `remote_backup_client` 43, `rec_016_export_coherence` 9, `ux_altas_en_contexto` 8) |
| `flutter test` sobre los archivos de Planificación y Aplicación tras las correcciones de §3.1 | 51 pasan; luego 70 pasan (10 archivos de Aplicación/Planificación + el nuevo) |
| `dart format --set-exit-if-changed lib test` y `flutter analyze` sobre `a116747` | 0 cambiados; `No issues found!` |
| `flutter test` (suite completa) sobre `a116747` | `03:16 +2303 ~3 -1: Some tests failed.` El único fallo es `regression_widget_test.dart` «estado de cuenta abre y cierra 20 veces sin perder la pantalla» (no encontró el `PopupMenuButton` de Cuentas, pantalla que este bloque no toca); aislado, `regression_widget_test.dart` pasa (**4 pasan**) |

### 3.1 Fallos de la primera suite completa

En la primera suite completa (sobre `b4dba09`) fallaron 9 pruebas de 7 archivos; aisladas pasan todas. Dos son de pantallas de este bloque:

- `ux_altas_en_contexto_test` (e): esperaba «Cipermetrina UX» en «Agregar producto» de Planificación y vio «Glifosato». Causa: con un solo producto, el selector lo **autoelegía** al elegir el chaco, y la espera de la prueba (`value != null`) se cumplía antes del alta. Corrección en `3efb743`: el producto a agregar ya no se autoelige (como en Compra, B-08) y la prueba espera el nombre creado.
- `fix_aplicacion_costo_cargo_test` «cobro por compra»: tiempo agotado (30 s) bajo carga. Para aliviar el formulario, `a116747` lee chacos y productos a la vez y las previsiones de lotes en paralelo.

Los otros (copias de respaldo, estimación, exportación) son de pantallas que este bloque no toca; fallaron por tiempo o por la base cerrada bajo carga y pasan aislados. En la segunda suite completa no volvieron a fallar.

Comprobación de que las aserciones dentro de `tester.runAsync` fallan cuando deben: con (r2) alterado para esperar «vencido» el 05/03, la prueba falló (`Expected: …expired / Actual: <null>`); se restauró.

## 4. Limitaciones

- Sólo HOST. No se verificó en emulador ni en teléfono.
- La fecha de una aplicación histórica no se recorre en la interfaz (el selector de fecha es incómodo de manejar en pruebas): el caso histórico se prueba en el repositorio y en la función pura, y la pantalla pasa su fecha efectiva a ambos.
- «Registrar compra» se probó con la compra confirmada. Si se cancela la compra, la aplicación también relee existencias, sin cambios visibles.
