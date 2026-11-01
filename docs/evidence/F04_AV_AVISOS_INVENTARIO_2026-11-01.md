# F04-AV — Avisos de existencias y vencimiento (MOB #168–#171)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01 (UTC; noche del 2026-10-31 y madrugada del 2026-11-01 en Bolivia) |
| Rama | `feat/f04-av-avisos-inventario` |
| Base | Mobile `main` `774ae88` |
| Código verificado | `f99fc56` y, para el «Nuevo» flotante, `ce3b788` (§4 y §6). Fuera de esa corrección, `lib/` y `test/` de este documento son los de `f99fc56` |
| Issues | Refs #168, #169, #170, #171. Ninguno se cierra con este trabajo |
| Origen | Implementación nueva; datos sintéticos |
| EMULADOR | `docs/evidence/F04_AV_AVISOS_INVENTARIO_EMULADOR_2026-11-01.md` |
| DEVICE | `docs/evidence/F04_AV_AVISOS_INVENTARIO_DEVICE_2026-11-01.md` y su complemento `docs/evidence/F04_AV_AVISOS_INVENTARIO_DEVICE_COMPLEMENTO_2026-11-01.md` |

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

**El esquema 12 cambió antes de publicarse.** El CHECK del número de lote pasó de 40 a 100 caracteres. Ninguna instalación de esta rama existía antes: el paquete del EMULADOR se instaló nuevo. Una instalación de desarrollo hecha con un commit anterior de la rama conserva el CHECK de 40 y hay que reinstalarla.

## 2. Decisiones del autor, implementadas

### Primera tanda (2026-11-01)

1. **Mínimo por producto, total y responsable por separado.** El mismo nivel se compara con la existencia de toda la instalación y con la de cada responsable. La vista tiene dos secciones: «Existencia baja en toda la instalación» y «Existencia baja por responsable». El resumen del inventario las cuenta por separado («bajo en el total», «bajo por responsable»).
2. **Aviso de cero para quien tuvo movimientos, sin confundirlo con falta en la instalación.** Ejemplo en pantalla: «Hermana no tiene existencias propias; nivel mínimo 2 KG. En toda la instalación: 3 KG». Quien nunca tuvo el producto no recibe aviso.
3. **Corregir vencimiento o lote después del registro exige motivo y PIN del titular.** Propósito `CORRECT_LOT_DATA`. Queda auditado el actor, el vínculo, el método y el enrolamiento, más una fila por lote cambiado. Sólo cambian los lotes de **procedencia demostrada**:
   - los lotes de compra de la línea, sin padre y con su entrada `PURCHASE_IN` por una asignación de esa línea;
   - recursivamente, los lotes de destino enlazados por `parent_lot_id` y una fila de `transfer_lot_items`.
   Un lote de la línea al que no se llega así no se toca y se cuenta (`unproven_lot_count`). Si ninguno se demuestra, no se corrige nada.
4. **Sin correcciones nuevas sobre compras revertidas.** El repositorio las rechaza y el detalle oculta «Corregir»; la consulta y «Ver correcciones» se conservan.
5. **30 días como valor inicial configurable,** sin cambios.

### Segunda tanda (2026-11-01, después de la primera evidencia)

1. **Plazo de anticipación: entero de 0 a 365 días.**
   - Es el **rango funcional elegido** para la configuración, no una regla agronómica, y así se documenta en el código (`AgroRepository.maxAlertLeadDays`, comentario del esquema).
   - El campo sólo admite dígitos: «0x10» y «+5» se rechazan.
2. **Número de lote opcional, hasta 100 caracteres.**
   - Se cuentan caracteres Unicode, como `length()` de SQLite.
   - Se conserva el contenido tal cual: sólo se quitan los espacios de los lados.
   - El exceso se rechaza con «El número de lote admite hasta 100 caracteres; tiene N. Revise lo escrito: no se recorta.». Los campos ya no usan `maxLength`, que recortaba lo pegado, y muestran un contador «N/100».
   - En la compra, el exceso impide pasar a la revisión; en la corrección, deja «Continuar» inactivo.
   - No hay backfill: los lotes anteriores quedan sin número.
3. **Productos archivados: sin aviso de existencia baja.** Sus lotes con cantidad conservan el aviso de vencimiento. Ya era así; ahora lo fija una regresión.
4. **«Vence hoy».**
   - Tiene estado (`ExpiryStatus.today`) y sección propios.
   - Va en una tarjeta ámbar con icono de advertencia, entre «Vencidos» (rojo) y «Próximos».
   - Se muestra aunque el plazo sea 0.
   - Pasa a vencido al día siguiente, según la fecha local del teléfono. Con el reloj inyectado se prueba el último instante del día y el primero del siguiente, en dos zonas de desfase.
5. **Mínimo y plazo corresponden al titular.**
   - Al guardar se pide **una vez** su PIN vigente para los dos datos (propósito `CONFIGURE_PRODUCT_ALERTS`, objeto `product_alerts:<id>`), con lo que cambia a la vista.
   - Cancelar en cualquier paso no modifica nada.
   - Sin cambios, «Guardar» queda inactivo. Si se escribe el mismo valor de otra forma («2,50»), se avisa «No hay cambios que guardar» sin pedir el PIN.

### Consumo de la autorización (revisión pedida)

`_writeAuthorized` en `agro_repository.dart`, usado por la corrección y por la configuración:

- **Rechazo de validación previo.** Formato, motivo, compra revertida, sin procedencia, sin cambios, producto inexistente y los rechazos de `consumeOwnerAuthorization`. Ocurre antes de consumir: la autorización queda sin gastar y puede usarse en el reintento.
- **Fallo después de iniciar la mutación.** Una vez consumida, si la escritura falla dentro de la transacción:
  - la transacción se deshace y no queda nada escrito;
  - la autorización sigue gastada y su reutilización se rechaza con «La autorización ya se usó.»;
  - sale `AuthorizedChangeNotSaved`: «No se guardó el cambio. La confirmación con el PIN ya se usó: vuelva a intentarlo y confirme otra vez con el PIN.»;
  - el registro local guarda el tipo y el código del error, no su texto.
- **Contrato existente sin cambios.** `consumeOwnerAuthorization` y las reversiones y tardías siguen igual: consumen al inicio de su transacción.
- **`friendlyError` muestra el motivo de un rechazo de autorización** sin el nombre de la clase.

## 3. Qué se implementó

- **Esquema 12, aditivo.**
  - Columnas opcionales: `inventory_lots.expiry_date` y `inventory_lots.lot_number` (1 a 100 caracteres), `products.min_stock_base` y `products.alert_lead_days` (0 a 365).
  - Tablas `lot_data_corrections` y `lot_data_correction_lots`, inmutables por disparadores.
  - Las mismas sentencias crean una base nueva y migran una existente, con `IF NOT EXISTS`. No hay backfill.
- **Compra.** Vencimiento y número de lote opcionales por línea, plegados en el formulario; pasan a cada lote de la línea. También viajan en el borrador de una compra tardía.
- **Transferencia.** El lote de destino hereda vencimiento y número de lote del de origen. El orden de consumo sigue siendo por fecha de adquisición.
- **Corrección.** Detalle de compra → datos nuevos → motivo y PIN. «Ver correcciones» muestra anterior, nuevo, motivo, quién autorizó y cuántos lotes cambiaron.
- **Configuración.** En el detalle del producto, con el PIN del titular al guardar.
- **Cálculo.** Sin red, con reloj inyectable. Lote con cantidad remanente: vencido, vence hoy, próximo o sin fecha. Existencia neta como el «Físico» del inventario. Aviso si la fecha del teléfono es anterior al último movimiento.
- **Vista.** Entrada «Avisos de inventario» en Inventario y vista propia. Tocar un aviso abre el producto sin iniciar ninguna operación; al volver, la vista recalcula.
- **Sin efectos.** No cambia existencias, movimientos ni FIFO, no bloquea operaciones, no envía notificaciones del sistema y no se publica al Sindicato.

## 4. HOST

**Entorno:** Windows 11 Home 10.0.26200, Flutter 3.47.2 (stable), SQLite por `sqflite_common_ffi`.

```text
dart format --set-exit-if-changed lib test                  → sin cambios
flutter analyze lib test                                    → No issues found!
flutter test test/f04_av_inventory_alerts_test.dart \
             test/f04_av_inventory_alerts_ui_test.dart      → 39 correctas (34 + 5)
```

`flutter analyze` sin rutas también informa 4 avisos `invalid_use_of_visible_for_testing_member`. Están en `tool/av/seed_av_mobile.dart`, la siembra sintética local que no se commitea; el código versionado no tiene ninguno.

**Suites completas.** El equipo tenía poca memoria libre: el servidor de análisis de Dart del editor ocupaba 6,7–7,4 GB, y durante la sesión Android también corrían Docker y el emulador.

| Código | Hora (UTC) | Correctas | Omitidas | Fallidas | Fallos |
|---|---|---|---|---|---|
| `e6cc25e` | 08:57:49–09:00:10 | 2179 | 3 | 0 | — |
| `f99fc56` | 09:11:07–09:15:30 | 2176 | 3 | 3 | `f03_access_recovery_app_test` (1), `f08_prev_01_previo_ui_test` (2) |
| `f99fc56` | 09:49:08–09:55:08 | 2177 | 3 | 2 | `f08_prev_01_previo_ui_test` (2) |
| `e6cc25e`, comparación en las mismas condiciones | 09:55:38–09:58:59 | 2174 | 3 | 5 | `f08_prev_01_previo_ui_test` (4), `remote_backup_client_test` (1) |

**Lectura.**
- **Los fallos son de carga.** Las pruebas que fallan esperan estados de la copia previa con tiempos reales (`runAsync`).
- **No dependen de `f99fc56`.**
  - `e6cc25e` falla igual en las mismas condiciones.
  - `f99fc56` no toca el respaldo ni la copia previa.
  - `f03_access_recovery_app_test` y `f08_prev_01_previo_ui_test`, solos sobre `f99fc56`, pasaron 3 de 3 seguidas. Una corrida anterior de los dos juntos, inmediatamente después de la suite, falló.
- **Ya estaba en `main`.** El 2026-10-31, sobre `main` `774ae88`, también fallaban `f08_prev_01_previo_ui_test` y `operation_mode_onboarding_test`.
- **La CI de GitHub decide.**

**Qué cubren las pruebas nuevas:**

| Criterio | Prueba |
|---|---|
| #168 migración desde 11 sin cambiar filas; lotes «sin fecha registrada» | `una base v11 con lotes migra sin cambiar filas` |
| #168 idempotencia | `la migración es idempotente si las columnas ya existen` |
| #168 compra por línea, a cada lote | `la compra guarda vencimiento y número de lote en cada lote de la línea` |
| #168 formato; exceso con mensaje | `una fecha o un número de lote mal formados no se guardan` |
| Decisión 2.2 (100 caracteres) | `el número de lote admite hasta 100 caracteres, se guarda tal cual y no se recorta…` (Unicode, CHECK de la base, corrección sin gastar el PIN); en pantalla, compra y corrección con 101 |
| #168 transferencia; FIFO intacto | `la transferencia conserva vencimiento y número de lote y no altera el FIFO` |
| Decisión 1.3: PIN, auditoría, procedencia en dos niveles | `corregir con PIN cambia sólo esos datos en los lotes de procedencia demostrada…` |
| Decisión 1.3: rechazos sin escribir; PIN incorrecto | `sin PIN válido, sin motivo o con otra autorización no se corrige nada` |
| Consumo: rechazo previo | `un rechazo previo (sin cambios) no gasta la autorización`; `un lote de compra sin su entrada de compra no tiene procedencia: … el PIN no se gasta` |
| Consumo: fallo posterior | `un fallo después de consumir la autorización no deja nada escrito y la autorización no se reutiliza` (disparador que aborta tras consumir) |
| Decisión 1.3: lote sin procedencia | `un lote de la línea sin procedencia demostrada no se cambia y se cuenta` |
| Decisión 1.4 | `una compra revertida no admite correcciones; su historial se consulta` y la prueba de pantalla del detalle |
| Decisión 2.5 y consumo | `configurar exige el PIN del titular una vez para los dos datos…`; `sin titular vinculado no vale la autorización de otra credencial`; `configuración: un fallo después de consumir no guarda nada…`; en pantalla: inactivo sin cambios, cancelar en el PIN y en los valores, «2,50», «0x10», 400 días |
| Decisión 2.3 | `un producto archivado no avisa de existencia baja; sus lotes con cantidad siguen avisando del vencimiento` |
| Decisión 2.4 | `vence hoy hasta el último instante del día local; al siguiente, vencido`; `el día es el local del teléfono, no el UTC`; clasificación pura; en pantalla, sección propia y orden |
| #168 respaldo idéntico | `un respaldo .agrobackup devuelve fechas, lotes, niveles y correcciones idénticos`, con avisos no vacíos |
| #168 respaldo de una versión anterior | `restaurar un respaldo v11 lo migra con lotes «sin fecha registrada»` |
| #168 compra tardía | `el borrador de una compra tardía conserva vencimiento y número de lote` |
| SC-CU22-01 | vencido con cantidad, vence hoy aparte, próximo con días, fuera de plazo sin aviso; plazo definido frente al inicial |
| SC-CU22-02 | sin fecha registrada no es vigente ni vencido |
| SC-CU22-03 | ≤ nivel avisa, > nivel no, sin nivel no; se indica que puede definirse |
| SC-CU22-04 y decisiones 1.1–1.2 | compartido por responsable con el total al lado; propio sólo total; cero para quien tuvo movimientos; en pantalla, sección del total y texto del cero |
| SC-CU22-05 | consultar no cambia ninguna tabla; aplicar consume el lote más antiguo aunque esté vencido; transferir y comprar no se bloquean |
| #171 lote agotado | un lote agotado, transferido entero o revertido no avisa; el de destino sí, con la fecha heredada |
| CU-22 E2 | movimiento posterior a la fecha del teléfono |
| #170 vista | inventario → avisos, textos, plazo inicial explicado, tocar abre el producto, nada escrito |

**Pruebas existentes ajustadas al esquema 12.** Cinco pruebas comparaban filas o columnas exactas o fijaban la versión 11. Ahora comparan sin las columnas nuevas, que nacen NULL, y comprueban que la versión es la vigente.

**`ce3b788`: el «Nuevo» flotante en «Avisos de inventario».** En el emulador el FAB global tapaba el aviso que pasaba por debajo al desplazarse; al final de la lista no lo tapaba, porque la página ya reservaba su alto. La vista es una consulta que no inicia operaciones (#170), así que se retira el FAB en esa ruta, como ya se hacía en el detalle de compra. Inventario conserva su «Nuevo».

Regresión nueva en `test/f04_av_inventory_alerts_ui_test.dart`:
- Usa el tamaño lógico del POCO (1080×2400 a 440 dpi) con la letra al 100, 130 y 200 %.
- Entra desde Inventario y comprueba que allí hay «Nuevo» y en la vista no.
- Lleva cada aviso al borde inferior y comprueba que recibe el toque en el centro y en la flecha.
- Con la lista agotada, el último aviso queda sobre la barra y abre su producto.
- Sin el arreglo, falla al 100 %: el «Nuevo» se queda el toque de la flecha de un aviso.

```text
dart format --output=none --set-exit-if-changed lib test     → 0 cambios
flutter analyze lib test                                      → No issues found!
flutter test f04_av_inventory_alerts_ui_test, f04_av_inventory_alerts_test,
             ui_polish_test, hierarchical_navigation_test,
             f10_x01_inicio_mas_test                          → 75 correctas
```

La suite completa de `ce3b788` corre en la CI del PR (no se repitió en este equipo).

## 5. EMULADOR

**Ejecutado el 2026-11-01** sobre `f99fc56`, con la APK `.av1` aislada en el emulador `Pixel_8` (Android 16 / API 36), sin red y con datos sintéticos.

- **AV-A1 a AV-A18: PASS**, con lo guardado comprobado en la base.
- **Detalle:** en `F04_AV_AVISOS_INVENTARIO_EMULADOR_2026-11-01.md`.
- **Incidente:** un PIN sintético quedó expuesto en la salida de la sesión. Se restableció y se añadió una guarda.
- **Observación:** el «Nuevo» flotante tapaba parte del último aviso visible. Se corrigió después, en `ce3b788` (§4); el EMULADOR no se repitió con ese commit.

## 6. DEVICE

**Ejecutado el 2026-11-01 (12:36Z–13:08Z)** sobre `ce3b788`. Se usó la APK `.av1` aislada arm64 (SHA-256 `09eebbfb…`) en el POCO X5 Pro 5G `22101320G`, con Android 12 / API 31, sin red, con datos sintéticos y una cuenta sintética propia (`u2-av`).

- **AV-A1 a AV-A14 y AV-A16 a AV-A18: PASS**, con lo guardado comprobado en la base.
- **AV-A15 (cambio de día): NOT_RUN** en el teléfono, porque no se cambia el reloj global. Se vio el límite con fechas relativas al día; el paso de un día al siguiente está cubierto en HOST y en el EMULADOR.
- **Derivadas:**
  - **AV-A19: PASS.** Sin «Nuevo» en la vista; el último aviso se ve y se toca al final de la lista, con la letra al 100, 130 y 200 %.
  - **AV-A20: PASS.** Persistencia al cerrar y reabrir sin red.
- **Observador:** 0 peticiones en el tramo sin red. Los ajustes del teléfono quedaron como al empezar y las 26 instalaciones previas no se tocaron.
- **Detalle:** en `F04_AV_AVISOS_INVENTARIO_DEVICE_2026-11-01.md`.
- **Complemento, 2026-11-01 de 17:57Z a 18:14Z.** Se hizo en el mismo POCO, con la misma APK, sin reinstalar ni usar el PIN. AV-A15 sigue NOT_RUN. AV-A21 a AV-A24 son criterios nuevos de esa sesión.
  - **AV-A21: PASS.** La vista muestra los mismos avisos con y sin conexión, sin cambios en la base entre las dos consultas. «Con conexión» significa la red del teléfono activa con el Central del ensayo detenido; no hubo sincronización real.
  - **AV-A22: PASS.** Aparece la existencia baja en toda la instalación y por responsable.
  - **AV-A23: PASS.** Un lote agotado por consumo deja de avisar de su vencimiento.
  - **AV-A24: PASS.** Consultar o tocar los avisos no cambia la base local.
  - **Detalle:** en `F04_AV_AVISOS_INVENTARIO_DEVICE_COMPLEMENTO_2026-11-01.md`.

## 7. Revisión del código

Las revisiones son de lectura y las hicieron otros agentes de esta misma sesión; no son independientes.

- **Sobre `774ae88..375ac24`:** sin bloqueantes. Sus observaciones se aplicaron en `4f5d321`.
- **Sobre `774ae88..065e391`:** sin bloqueantes de código. Lo aplicado en `335e3ff`:
  - procedencia antes de gastar el PIN;
  - valores anteriores tomados de un lote demostrado;
  - «Continuar» inactivo sin cambios;
  - resumen separado;
  - `IF NOT EXISTS`.
- **Sobre `e6cc25e` (segunda tanda), sin bloqueantes:**
  - Comprobó que `consumed` es local a cada llamada y que `_write` no reintenta.
  - Comprobó que la variante de configuración sin PIN sólo se usa en pruebas y que `runes` y `length()` cuentan igual.
  - Lo aplicado en `f99fc56`:
    - registro de la causa;
    - el comentario ya no promete el caso de un COMMIT fallido;
    - plazo sólo con dígitos;
    - aviso de «sin cambios»;
    - ámbar para «Vence hoy»;
    - `friendlyError` limpio;
    - la prueba del día local deja de ser tautológica;
    - títulos de prueba ajustados.
  - Declarado, sin cambio:
    - el CHECK de 40 en instalaciones de desarrollo previas (§1);
    - la prueba de pantalla de la vista usa el reloj real;
    - con la vista abierta al pasar la medianoche, «Vence hoy» se actualiza al pulsar «Volver a calcular» o al volver a abrirla.
- **Declarado de antes, sin cambio:**
  - el mensaje «N lotes» cuenta también los lotes de destino de transferencias revertidas, que siguen en el árbol de procedencia;
  - la «v11» de las pruebas se obtiene quitando las columnas de una v12.

- **Sobre `ce3b788` (el «Nuevo» flotante):**
  - Es una entrada en `_routesWithoutGlobalFab` y su comentario; no cambia otras rutas.
  - Se comprobó que la ruta llega al shell también cuando la vista se abre con `push` desde Inventario: la prueba entra así.
  - La regresión falla sin el arreglo.
  - No hay rediseño general ni cambios en el selector de productos archivados.

## 8. Decisiones pendientes

Todas las del bloque están decididas. No hay decisiones abiertas de este bloque.

## 9. Límites declarados

- **DEVICE en un solo teléfono** (POCO, Android 12). AV-A15, el cambio de día, no se ejecutó en él porque no se cambia el reloj global.
- **Sin evaluación con agricultores.** El plazo de 30 días sigue pendiente de validación.
- **El nivel mínimo y el plazo no guardan historial de cambios.** Se exige el PIN al cambiarlos, pero no hay tabla de auditoría como la de las correcciones; la decisión no lo pedía.
- **Respaldos con esquema 12 en una versión anterior de la app.** Se rechazan con «más reciente… Actualice la aplicación»; es el comportamiento existente para respaldos más nuevos.
- **El aviso del reloj compara con el último movimiento.** No detecta una fecha del teléfono adelantada.
- **No hay cálculo en segundo plano.** Los avisos se recalculan al abrir Inventario o la vista, o al pulsar «Volver a calcular».
