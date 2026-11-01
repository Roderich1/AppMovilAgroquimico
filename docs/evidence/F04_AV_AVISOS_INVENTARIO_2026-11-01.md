# F04-AV — Avisos de existencias y vencimiento (MOB #168–#171)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01 (UTC; noche del 2026-10-31 en Bolivia) |
| Rama | `feat/f04-av-avisos-inventario`, local, **sin publicar** |
| Base | Mobile `main` `774ae88` |
| Código verificado | `335e3ff`. `lib/` y `test/` de este documento son los de ese commit |
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

## 2. Decisiones del autor del 2026-11-01, implementadas

Roderich decidió el 2026-11-01:

1. **Mínimo por producto, total y responsable por separado.** El mismo nivel se compara con la existencia de toda la instalación y con la de cada responsable. La vista tiene dos secciones: «Existencia baja en toda la instalación» y «Existencia baja por responsable». El resumen del inventario las cuenta por separado («bajo en el total», «bajo por responsable»).
2. **Aviso de cero para quien tuvo movimientos, sin confundirlo con falta en la instalación.** Ejemplo en pantalla: «Hermana no tiene existencias propias; nivel mínimo 2 KG. En toda la instalación: 3 KG». Quien nunca tuvo el producto no recibe aviso.
3. **Corregir vencimiento o lote después del registro exige motivo y PIN del titular.** Propósito `CORRECT_LOT_DATA`. Queda auditado el actor, el vínculo, el método y el enrolamiento, más una fila por lote cambiado. Sólo cambian los lotes de **procedencia demostrada**:
   - los lotes de compra de la línea, sin padre y con su entrada `PURCHASE_IN` por una asignación de esa línea;
   - recursivamente, los lotes de destino enlazados por `parent_lot_id` y una fila de `transfer_lot_items`.
   Un lote de la línea al que no se llega así no se toca y se cuenta (`unproven_lot_count`). Si ninguno se demuestra, no se corrige nada. Todo rechazo ocurre antes de gastar la autorización.
4. **Sin correcciones nuevas sobre compras revertidas.** El repositorio las rechaza y el detalle oculta «Corregir»; la consulta y «Ver correcciones» se conservan.
5. **30 días como valor inicial configurable,** sin cambios.

## 3. Qué se implementó

- **Esquema 12, aditivo.** `inventory_lots.expiry_date` y `inventory_lots.lot_number`, `products.min_stock_base` y `products.alert_lead_days`, todos opcionales. Tablas `lot_data_corrections` y `lot_data_correction_lots`, inmutables por disparadores. Las mismas sentencias crean una base nueva y migran una existente, con `IF NOT EXISTS`. No hay backfill: un lote anterior queda «sin fecha registrada».
- **Compra.** Vencimiento y número de lote opcionales por línea, plegados en el formulario; pasan a cada lote de la línea. También viajan en el borrador de una compra tardía.
- **Transferencia.** El lote de destino hereda vencimiento y número de lote del de origen. El orden de consumo sigue siendo por fecha de adquisición.
- **Corrección.** Detalle de compra → datos nuevos → motivo y PIN. «Continuar» queda desactivado si nada cambió. «Ver correcciones» muestra anterior, nuevo, motivo, quién autorizó y cuántos lotes cambiaron.
- **Configuración.** En el detalle del producto: nivel mínimo y plazo. Vacío significa «sin nivel» o «valor inicial de 30 días».
- **Cálculo.** Sin red, con reloj inyectable. Lote con cantidad remanente: vencido, próximo (incluye «vence hoy») o sin fecha. Existencia neta como el «Físico» del inventario. Aviso si la fecha del teléfono es anterior al último movimiento.
- **Vista.** Entrada «Avisos de inventario» en Inventario y vista propia. Tocar un aviso abre el producto sin iniciar ninguna operación; al volver, la vista recalcula.
- **Sin efectos.** No cambia existencias, movimientos ni FIFO, no bloquea operaciones, no envía notificaciones del sistema y no se publica al Sindicato.

## 4. HOST

**Entorno:** Windows 11 Home 10.0.26200, Flutter 3.47.2 (stable), SQLite por `sqflite_common_ffi`.

```text
dart format --output=none --set-exit-if-changed lib test   → código 0
flutter analyze lib test                                    → No issues found!
flutter test test/f04_av_inventory_alerts_test.dart         → 27 correctas
flutter test test/f04_av_inventory_alerts_ui_test.dart      → 5 correctas
```

**Suite completa sobre `335e3ff`**, `flutter test --reporter json`:

2026-11-01 05:28:04Z–05:30:29Z.

| Correctas | Omitidas | Fallidas | Archivos |
|---|---|---|---|
| 2172 | 3 | 0 | 187 |

**Inestabilidad por carga, ya presente en `main`.** En este equipo, con poca memoria libre, las corridas completas fallan cada vez en pruebas de pantalla distintas, que pasan solas:
- Sobre el código previo a `335e3ff` (2026-11-01 05:09:20Z–05:24:21Z, 15 min, 1,7 GB de memoria libre al terminar): 2167 correctas, 3 omitidas y 5 fallidas, en `test/f04_effective_date_form_test.dart` y `test/f10_x01_pago_datos_test.dart`. Esos dos archivos, solos, pasaron 16 de 16 dos veces seguidas. Ninguno de los dos cambió en este bloque.
- Sobre `065e391`, sin fallos: 2169 correctas, 3 omitidas.
- Sobre `main` `774ae88`, en el mismo equipo la noche anterior: 2137 correctas, 3 omitidas y 3 fallidas del mismo tipo (`test/f08_prev_01_previo_ui_test.dart` y `test/operation_mode_onboarding_test.dart`).

**Qué cubren las pruebas nuevas:**

| Criterio | Prueba |
|---|---|
| #168 migración desde 11 sin cambiar filas; lotes «sin fecha registrada» | `una base v11 con lotes migra sin cambiar filas` |
| #168 idempotencia | `la migración es idempotente si las columnas ya existen` |
| #168 compra por línea, a cada lote | `la compra guarda vencimiento y número de lote en cada lote de la línea` |
| #168 formato | `una fecha o un número de lote mal formados no se guardan` |
| #168 transferencia; FIFO intacto | `la transferencia conserva vencimiento y número de lote y no altera el FIFO` |
| Decisión 3: PIN, auditoría, procedencia en dos niveles | `corregir con PIN cambia sólo esos datos en los lotes de procedencia demostrada…` |
| Decisión 3: rechazos sin escribir; PIN incorrecto | `sin PIN válido, sin motivo o con otra autorización no se corrige nada` |
| Decisión 3: un rechazo previo no gasta el PIN | `un rechazo previo (sin cambios, sin procedencia, revertida) no gasta la autorización` |
| Decisión 3: lote sin procedencia | `un lote de la línea sin procedencia demostrada no se cambia y se cuenta`; `un lote de compra sin su entrada de compra…` |
| Decisión 4 | `una compra revertida no admite correcciones; su historial se consulta` y la prueba de pantalla del detalle |
| #168 respaldo idéntico | `un respaldo .agrobackup devuelve fechas, lotes, niveles y correcciones idénticos`, con avisos no vacíos |
| #168 respaldo de una versión anterior | `restaurar un respaldo v11 lo migra con lotes «sin fecha registrada»` |
| #168 compra tardía | `el borrador de una compra tardía conserva vencimiento y número de lote` |
| SC-CU22-01 | vencido con cantidad, próximo con días, fuera de plazo sin aviso; plazo definido frente al inicial |
| SC-CU22-02 | sin fecha registrada no es vigente ni vencido |
| SC-CU22-03 | ≤ nivel avisa, > nivel no, sin nivel no; se indica que puede definirse |
| SC-CU22-04 y decisiones 1–2 | compartido por responsable con el total al lado; propio sólo total; cero para quien tuvo movimientos; en pantalla, sección del total y texto del cero |
| SC-CU22-05 | consultar no cambia ninguna tabla; aplicar consume el lote más antiguo aunque esté vencido; transferir y comprar no se bloquean |
| #171 lote agotado | un lote agotado, transferido entero o revertido no avisa; el de destino sí, con la fecha heredada |
| CU-22 E2 | movimiento posterior a la fecha del teléfono |
| #170 vista | inventario → avisos, textos, plazo inicial explicado, tocar abre el producto, nada escrito |

**Pruebas existentes ajustadas al esquema 12.** Cinco pruebas comparaban filas o columnas exactas o fijaban la versión 11. Ahora comparan sin las columnas nuevas, que nacen NULL, y comprueban que la versión es la vigente. La comparación de columnas de `migration_test.dart` admite sólo las columnas de v12 al final de su tabla.

## 5. EMULADOR

**NOT_RUN.** El 2026-11-01 `adb devices` no listó ningún emulador en ejecución, y no se arrancó.

**Preparado, sin ejecutar:** comprobación sin red en un entorno aislado.
- Central propio (`agro_a_av_pg`, puertos 55497/3200/3201) y paquete `.av1` «AC AVISOS».
- Siembra sintética relativa al día.
- Trece comprobaciones (AV-A1 a AV-A13), con el resultado esperado calculado en HOST con la misma siembra.
- Herramientas locales sin commitear en `_wt/tools/av/` y `tool/av/`; protocolo en los briefs del proyecto.

**Precondiciones observadas:** Docker Desktop detenido; 3,9 GB de memoria libre con el servidor de análisis de Dart del editor en 4,1 GB.

## 6. DEVICE

**NOT_RUN.** El 2026-11-01 `adb devices` no listó ningún teléfono conectado.

## 7. Revisión del código

Dos revisiones de lectura por otros agentes de esta misma sesión; no son independientes.

- **Sobre `774ae88..375ac24`:** sin bloqueantes. Sus observaciones se aplicaron en `4f5d321`.
- **Sobre `774ae88..065e391`:** sin bloqueantes de código.
  - Comprobó que la consulta recursiva con `?1` es válida en sqflite de Android y en FFI.
  - Comprobó que las reversiones de transferencia no crean lotes.
  - Comprobó que ningún `switch` sobre `AuthorizationPurpose` quedaba incompleto.
  - Señaló la evidencia desactualizada, que este documento corrige.
  - Aplicado en `335e3ff`:
    - procedencia calculada antes de gastar el PIN;
    - valores anteriores tomados de un lote demostrado;
    - «Continuar» desactivado sin cambios;
    - resumen separado por total y por responsable;
    - migración con `IF NOT EXISTS`;
    - pruebas más estrictas.
- **Declarado, sin cambio:**
  - el mensaje «N lotes» cuenta también los lotes de destino de transferencias revertidas, que siguen en el árbol de procedencia;
  - una autorización gastada no se devuelve si la transacción falla después (mismo patrón que las reversiones; después del consumo no queda ninguna comprobación que pueda fallar);
  - la prueba de pantalla de la vista usa el reloj real;
  - la «v11» de las pruebas se obtiene quitando las columnas de una v12.

## 8. Decisiones todavía no aprobadas

Implementadas así, sin bloquear nada. Las decide Roderich.

1. **Rangos de validación.** Plazo de 0 a 365 días; número de lote de 1 a 40 caracteres. No están en la tesis. Ejemplo: un plazo de 400 días se rechaza con «Escriba un número entero de días, de 0 a 365».
2. **Productos archivados.** No dan aviso de existencia baja, pero sus lotes con existencias sí dan avisos de vencimiento. Ejemplo: Atrazina archivada con 1 L vencido y nivel mínimo 2 L aparece en «Vencidos», pero no en «Existencia baja».
3. **Vence hoy.** Un lote cuya fecha es hoy es «próximo» con «Vence hoy», no vencido, porque RN-31 dice «anterior a la fecha actual». Ejemplo: un lote que vence el 10/11 aparece como vencido recién el 11/11.

Fuera de este bloque y sin decisión: configurar el nivel mínimo y el plazo no pide PIN.

## 9. Límites declarados

- Sólo HOST. EMULADOR y DEVICE sin ejecutar.
- No hay evaluación con agricultores. El plazo de 30 días sigue pendiente de validación.
- Una versión anterior de la app rechaza un respaldo con esquema 12 («más reciente… Actualice la aplicación»). Es el comportamiento existente para respaldos más nuevos.
- El aviso del reloj compara con el último movimiento; no detecta una fecha del teléfono adelantada.
- Los avisos se recalculan al abrir Inventario o la vista, o al refrescar; no hay cálculo en segundo plano.
