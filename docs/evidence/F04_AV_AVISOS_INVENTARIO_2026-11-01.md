# F04-AV — Avisos de existencias y vencimiento (MOB #168–#171)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01 (UTC; noche del 2026-10-31 en Bolivia) |
| Rama | `feat/f04-av-avisos-inventario`, local, **sin publicar** |
| Base | Mobile `main` `774ae88` |
| Código verificado | `4f5d321` (`375ac24` más las correcciones de la revisión). `lib/` y `test/` de este documento son los de ese commit |
| Issues | Refs #168, #169, #170, #171. Ninguno se cierra con este trabajo |
| Origen | Implementación nueva; datos sintéticos |

## 1. Fuente de cada numeración

| ID | Fuente | Qué dice, en corto |
|---|---|---|
| RU-22 | Tesis v1.22.1, Cap. III, Tabla 3.14 | Avisos comprensibles sin conexión: existencia baja, vencido, próximo según plazo, sin fecha. Sin nivel no hay aviso. Ningún aviso cambia cantidades, movimientos ni orden de consumo |
| RN-31 | Tesis v1.22.1, Cap. III | Fecha en el lote de compra, conservada en los lotes por transferencia. Vencido si la fecha es anterior a la del teléfono; próximo dentro del plazo del producto; sin fecha: «sin fecha de vencimiento» |
| RN-32 | Tesis v1.22.1, Cap. III | Existencia baja si la existencia neta ≤ nivel mínimo; sin nivel no se emite; por responsable y total en compartida; sin efectos ni publicación |
| RF-42, RF-43, RF-44 | Tesis v1.22.1, Cap. III | Registro y corrección trazable; cálculo y vista sin conexión; configuración por el titular |
| DAT-22 | Tesis v1.22.1, Cap. III | Datos opcionales; ausencia distinguible de cero; estados derivados, no almacenados |
| CU-22, SC-CU22-01 a 05 | Tesis v1.22.1, Apéndice A | Flujo, alternativos A1–A3, excepciones E1–E2 y criterios |
| 30 días | Tesis v1.22.1, 3.12.4.2 | Plazo inicial configurable, pendiente de validación con los agricultores |

**Advertencia de numeración.** `docs/15_BUSINESS_RULES.md` de este repositorio usa RN-31 y RN-32 para reglas de transferencias («Al menos un ítem con cantidad positiva» y «No se repiten productos en una transferencia»). En el código y en las pruebas de este bloque, RN-31 y RN-32 son siempre los de la tesis, y así se indica en cada comentario.

**Número de esquema.** Este bloque usa el esquema 12. El 2026-11-01 no había ninguna rama ni worktree de F12-EST-07-MOB (#164) que reclamara ese número. #164 pide una migración aditiva coordinada con F04-AV-01: si integra después, debe tomar el 13. Si integra antes, este bloque se renumera, y también la versión fijada a mano en `test/rec_039_schema_constraints_test.dart`.

## 2. Qué se implementó

- **Esquema 12, aditivo.** `inventory_lots.expiry_date` y `inventory_lots.lot_number`, `products.min_stock_base` y `products.alert_lead_days`, todos opcionales. Tabla `lot_data_corrections`, inmutable por disparadores. Las mismas sentencias crean una base nueva y migran una existente. No hay backfill: un lote anterior queda «sin fecha registrada».
- **Compra.** Vencimiento y número de lote opcionales por línea, plegados en el formulario; pasan a cada lote de la línea. También viajan en el borrador de una compra tardía.
- **Transferencia.** El lote de destino hereda vencimiento y número de lote del de origen. El orden de consumo sigue siendo por fecha de adquisición.
- **Corrección.** Desde el detalle de compra. Cambia sólo esos dos datos en todos los lotes de la línea, incluidos los transferidos, y deja una fila con los valores anteriores y los nuevos. «Ver correcciones» muestra ese historial.
- **Configuración.** En el detalle del producto: nivel mínimo y plazo. Vacío significa «sin nivel» o «valor inicial de 30 días».
- **Cálculo.** Sin red, con reloj inyectable. Lote con cantidad remanente: vencido, próximo (incluye «vence hoy») o sin fecha. Existencia baja con la suma de movimientos, como el «Físico» del inventario. Aviso si la fecha del teléfono es anterior al último movimiento.
- **Vista.** Entrada «Avisos de inventario» en Inventario y vista propia. Tocar un aviso abre el producto sin iniciar ninguna operación; al volver, la vista recalcula.
- **Sin efectos.** No cambia existencias, movimientos ni FIFO, no bloquea operaciones, no envía notificaciones del sistema y no se publica al Sindicato.

## 3. HOST

**Entorno:** Windows 11 Home 10.0.26200, Flutter 3.47.2 (stable), SQLite por `sqflite_common_ffi`.

```text
dart format --output=none --set-exit-if-changed lib test   → código 0
flutter analyze                                             → No issues found!
flutter test test/f04_av_inventory_alerts_test.dart         → 21 correctas
flutter test test/f04_av_inventory_alerts_ui_test.dart      → 4 correctas
```

**Suite completa sobre `4f5d321`**, 2026-11-01 04:22:05Z–04:24:18Z, `flutter test --reporter json`:

| Correctas | Omitidas | Fallidas | Archivos |
|---|---|---|---|
| 2165 | 3 | 0 | 187 |

**Inestabilidad por carga, ya presente en `main`.** Corridas completas anteriores de la rama fallaron cada vez en una prueba de pantalla distinta, y cada una pasa sola. La última, sobre `375ac24`, falló en «restaurar desde Liquidación una copia del mismo Member…» (`test/f04_admin_owner_restore_ui_test.dart`), que después pasó tres veces seguidas sola. La suite sobre `main` `774ae88`, en el mismo equipo y la misma noche, dio 2137 correctas, 3 omitidas y 3 fallidas del mismo tipo: dos de «Decidir» (`test/f08_prev_01_previo_ui_test.dart`) y «propio → compartido con historial» (`test/operation_mode_onboarding_test.dart`). No se atribuye a este bloque.

**Qué cubren las pruebas nuevas:**

| Criterio | Prueba |
|---|---|
| #168 migración desde 11 sin cambiar filas; lotes «sin fecha registrada» | `una base v11 con lotes migra sin cambiar filas` |
| #168 idempotencia | `la migración es idempotente si las columnas ya existen` |
| #168 compra por línea, a cada lote | `la compra guarda vencimiento y número de lote en cada lote de la línea` |
| #168 formato | `una fecha o un número de lote mal formados no se guardan` |
| #168 transferencia; FIFO intacto | `la transferencia conserva vencimiento y número de lote y no altera el FIFO` |
| #168 corrección trazable sin tocar cantidades | `corregir cambia sólo esos datos…` y la prueba de pantalla del detalle de compra |
| #168 respaldo idéntico | `un respaldo .agrobackup devuelve fechas, lotes, niveles y correcciones idénticos`, con avisos no vacíos |
| #168 respaldo de una versión anterior | `restaurar un respaldo v11 lo migra con lotes «sin fecha registrada»` |
| #168 compra tardía | `el borrador de una compra tardía conserva vencimiento y número de lote` |
| SC-CU22-01 | vencido con cantidad, próximo con días, fuera de plazo sin aviso; plazo definido frente al inicial |
| SC-CU22-02 | sin fecha registrada no es vigente ni vencido |
| SC-CU22-03 | ≤ nivel avisa, > nivel no, sin nivel no; se indica que puede definirse |
| SC-CU22-04 | compartido por responsable y total; propio sólo total |
| SC-CU22-05 | consultar no cambia ninguna tabla; aplicar consume el lote más antiguo aunque esté vencido; transferir y comprar no se bloquean |
| #171 lote agotado | un lote agotado, transferido entero o revertido no avisa; el de destino sí, con la fecha heredada |
| CU-22 E2 | movimiento posterior a la fecha del teléfono |
| #170 vista | inventario → avisos, textos, plazo inicial explicado, tocar abre el producto, nada escrito |
| Corrección visible | detalle de compra → «Ver correcciones» con valor anterior, nuevo y motivo |

**Pruebas existentes ajustadas al esquema 12.** Cinco pruebas comparaban filas o columnas exactas o fijaban la versión 11. Ahora comparan sin las columnas nuevas, que nacen NULL, y comprueban que la versión es la vigente. La comparación de columnas de `migration_test.dart` admite sólo las columnas de v12 al final de su tabla.

## 4. EMULADOR

**NOT_RUN.** El 2026-11-01 `adb devices` no listó ningún emulador en ejecución, y este bloque no lo arrancó. La sesión anterior en el emulador quedó detenida por el diálogo «System UI isn't responding»; descartarlo fue rechazado por el control de permisos y no se intentó otra vía.

## 5. DEVICE

**NOT_RUN.** El 2026-11-01 `adb devices` no listó ningún teléfono conectado.

## 6. Revisión del código

Revisión de lectura del diff `774ae88..375ac24` por otro agente de esta misma sesión; no es independiente.

- **Veredicto:** sin bloqueantes. Comprobó que nada llega a la sincronización, que el FIFO y las cantidades no cambian, la compatibilidad de `ADD COLUMN` con `CHECK` desde Android 7 (minSdk 24) y el cálculo por días civiles.
- **Aplicado en `4f5d321`:** rango del selector de fecha; recalcular al volver del producto; historial de correcciones visible; textos del mensaje de éxito, del plazo 0 y de dónde registrar la fecha; constante de unidades; tres aserciones de prueba que eran flojas.
- **No aplicado, pasa a decisiones (§7):** a quién se evalúa por responsable; corregir una compra revertida o de una campaña cerrada.
- **Pendiente menor:** la prueba de pantalla de la vista usa el reloj real, y podría fallar justo a medianoche. La «v11» de las pruebas se obtiene quitando las columnas de una v12, no con una base v11 real; las v7 y v8 reales sí se migran en otras pruebas.

## 7. Decisiones de negocio no cubiertas

Se implementó una opción en cada caso, sin bloquear nada. Cada una es reversible y la decide Roderich.

1. **Responsables que entran en «existencia baja».** Se evalúan las personas activas con algún movimiento del producto, aunque hoy tengan 0. Ejemplo: Hermana recibió 1 L de Glifosato y lo aplicó; con nivel mínimo 2 L aparece «Glifosato · Hermana: Quedan 0 L» hasta que reciba producto o se quite el nivel. Quien nunca tuvo el producto no recibe aviso, y una persona archivada tampoco, aunque sus lotes sí avisan de vencimiento. Las alternativas son avisar sólo a quien tiene existencias, o a todos los responsables.
2. **Un mismo nivel para cada responsable y para el total.** RF-44 habla de un nivel por producto. Ejemplo: nivel 10 L y tres responsables con 5 L cada uno dan tres avisos por responsable, y ninguno para el total de 15 L.
3. **Corrección sin PIN, con motivo opcional, para toda la línea.** Corregir no cambia cantidades, así que no se pidió el PIN del titular. Ejemplo: si el titular entregó 2 L a Hermana, corregir la fecha de la compra cambia también la del lote de Hermana. Configurar el nivel y el plazo tampoco pide PIN.
4. **Rangos de validación.** Plazo de 0 a 365 días; número de lote de 1 a 40 caracteres. No están en la tesis.
5. **Productos archivados.** No dan aviso de existencia baja, pero sus lotes con existencias sí dan avisos de vencimiento.
6. **Vence hoy.** Un lote cuya fecha es hoy es «próximo» con «Vence hoy», no vencido, porque RN-31 dice «anterior a la fecha actual».
7. **Corregir una compra revertida o de una campaña cerrada.** Hoy se permite, porque no toca cantidades, y queda registrado. Ejemplo: una compra revertida por error de proveedor sigue mostrando «Corregir vencimiento o lote». La alternativa es ocultarlo y rechazarlo en compras revertidas.

## 8. Límites declarados

- Sólo HOST. EMULADOR y DEVICE sin ejecutar.
- No hay evaluación con agricultores. El plazo de 30 días sigue pendiente de validación.
- Una versión anterior de la app rechaza un respaldo con esquema 12 («más reciente… Actualice la aplicación»). Es el comportamiento existente para respaldos más nuevos.
- El aviso del reloj compara con el último movimiento; no detecta una fecha del teléfono adelantada.
- Los avisos se recalculan al abrir Inventario o la vista, o al refrescar; no hay cálculo en segundo plano.
