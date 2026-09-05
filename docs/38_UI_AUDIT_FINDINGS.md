# 38 — Hallazgos de la auditoría de interfaz


> **Estado del backlog (2026-09-05).** Los defectos de este documento se han corregido en su mayor parte: **38 `VERIFIED`** en Pixel 8, **16** corregidos y cubiertos por tests, **9** MEDIUM/LOW abiertos con justificación, **2** pendientes de decisión de producto y **1** `WONT_FIX`. Este documento conserva la **observación original**; el estado vigente está en [`43_UIBUG_FIX_TRACEABILITY.md`](43_UIBUG_FIX_TRACEABILITY.md) y el cierre en [`45_UI_AUDIT_FINAL_VERIFICATION.md`](45_UI_AUDIT_FINAL_VERIFICATION.md).

Todos los defectos observados **ejecutando la aplicación** sobre el emulador Pixel 8.

## Entorno común a todos los hallazgos

Salvo que un hallazgo diga lo contrario:

| | |
|---|---|
| **Dispositivo** | Pixel 8 (AVD `Pixel_8`), Android 16 (API 36) |
| **Resolución** | 1080 × 2400 · 420 dpi · vertical |
| **Escala de fuente** | 1.0 |
| **Binario** | `app-debug.apk` |
| **Estado de datos** | Dataset de `36_UI_AUDIT_DATASET.md`, recién recargado |
| **Frecuencia** | ALWAYS |
| **Estado** | OPEN — **no se corrigió ningún hallazgo en esta fase** |

Evidencia: rutas relativas a `artifacts/ui-audit/`.

> **Backlog vigente**: para planificar y ejecutar, usa
> [41_UIBUG_MASTER_BACKLOG.md](41_UIBUG_MASTER_BACKLOG.md). Este documento conserva los pasos de
> reproducción y la evidencia de cada hallazgo tal como se observaron.

## Resumen

| Severidad | IDs | Nº |
|---|---|---:|
| CRITICAL | 001–004 | 4 |
| HIGH | 005–021 | 17 |
| MEDIUM | 022–056 | **35** |
| LOW | 057–065 | 9 |
| **Total** | **001–065** | **65** |

> **Corrección de conteo (2026-09-05).** Este resumen declaraba antes *26 MEDIUM* y un total de
> *56*. Era un recuento arrastrado sin actualizar tras ampliar la sección MEDIUM: el documento
> siempre definió, con contenido propio, los **65** IDs `UIBUG-001`…`UIBUG-065`, de los cuales
> **35** son MEDIUM. Verificado mecánicamente (65 IDs únicos, 65 bloques de definición).
> Ningún hallazgo se añadió, eliminó ni cambió de severidad al corregir la cifra.
> Detalle en [`41` §2](41_UIBUG_MASTER_BACKLOG.md).

> **Subdivisión de UIBUG-004 (2026-09-05).** Se dividió en **004A** (navegación jerárquica sin
> retorno — CRITICAL) y **004B** (política de Atrás desde un destino raíz — MEDIUM, decisión de
> diseño). El texto original de más abajo se conserva **sin modificar**; la separación y su
> justificación están en [`41` §3](41_UIBUG_MASTER_BACKLOG.md). Con la subdivisión el backlog
> tiene **66 entradas** sobre **65 IDs históricos**.

---

# CRITICAL

## UIBUG-001 · Exportar backup falla siempre en Android

| | |
|---|---|
| **Severidad** | CRITICAL · **Categoría** FUNCTIONAL / ERROR_HANDLING |
| **Pantalla / Ruta** | Liquidación y cuentas · `/liquidacion` |

**Precondiciones**: ninguna.

**Pasos**
1. Abrir la pestaña **Cuentas**.
2. Pulsar el icono de nube de la cabecera.
3. Elegir **Exportar backup**.

**Resultado actual** — snackbar rojo con el error técnico en inglés:

```
DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be performed using
SQLiteDatabase query or rawQuery methods only.) sql 'PRAGMA wal_checkpoint(FULL)' args []
```

No se genera ningún archivo. En consecuencia **Restaurar backup** responde siempre
*"No se encontró ningún backup"*.

**Resultado esperado**: se escribe el archivo de respaldo y se informa de su ruta.

**Impacto**: la **única** protección de datos de la aplicación no funciona en la plataforma
real. Un usuario que confíe en el backup perdería toda su contabilidad ante una pérdida del
dispositivo. Afecta también a la restauración, que nunca encuentra nada que restaurar.

**Posible causa técnica** (con evidencia): `lib/data/backup_service.dart:63` ejecuta
`database.execute('PRAGMA wal_checkpoint(FULL)')`. En Android `sqflite` mapea `execute()` a
`SQLiteDatabase.execSQL`, que rechaza sentencias que devuelvan filas, y `wal_checkpoint`
devuelve una fila. La suite no lo detecta porque `backup_service_test.dart` corre sobre
`sqflite_common_ffi` (escritorio), donde `execute()` sí lo admite.

**Archivos probablemente relacionados**: `lib/data/backup_service.dart`,
`test/backup_service_test.dart`.

**Relación**: STAB-007 · `13_LOCAL_STORAGE.md` · `14_OFFLINE_AND_SYNC.md`

**Evidencia**: `UI-10-liquidacion/UI-10-exportar-backup.png`,
`UI-10-liquidacion/UI-10-restaurar-backup.png`

---

## UIBUG-002 · La pantalla de historial de compras es inalcanzable

| | |
|---|---|
| **Severidad** | CRITICAL · **Categoría** NAVIGATION / FUNCTIONAL |
| **Pantalla / Ruta** | Compras · `/compras` |

**Pasos**: recorrer toda la aplicación buscando un acceso al historial de compras.

**Resultado actual**: no existe. La ruta `/compras` está declarada en `lib/app.dart:63` pero
**ninguna parte de `lib/` navega hacia ella**. Verificado enumerando todas las llamadas a
`context.go` y `context.push` del proyecto:

| Origen | Destinos |
|---|---|
| Barra/rail del shell | `/`, `/operaciones`, `/inventario`, `/personas`, `/liquidacion` |
| Tarjetas de Operaciones | `/planificacion`, `/compras/nueva`, `/aplicaciones`, `/transferencias`, `/catalogos` |
| FAB "Nuevo" | `/planificacion`, `/compras/nueva`, `/aplicaciones`, `/liquidacion`, `/transferencias` |
| Dashboard | `/inventario`, `/inventario/:id`, `/aplicaciones`, `/liquidacion` |

**Resultado esperado**: poder consultar las compras registradas.

**Impacto**: toda la funcionalidad de `PurchasesScreen` queda fuera del alcance del usuario:
consultar el historial, **registrar pagos a proveedor posteriores a la compra**, **ver la
fotografía de la factura** y **revertir una compra**. Es funcionalidad implementada y probada
que nadie puede usar. Deja además sin salida la foto de factura: se puede adjuntar, pero nunca
consultar.

**Discrepancia con la documentación**: `07_SCREENS.md` P-06 describe la pantalla como accesible
y `08_NAVIGATION.md` la lista entre las rutas del shell sin señalar que carece de entrada.

**Archivos probablemente relacionados**: `lib/app.dart`, `lib/presentation/app_shell.dart`,
`lib/presentation/screens/operations_screen.dart`.

**Relación**: F-04 (compras) · `07_SCREENS.md` P-06 · `08_NAVIGATION.md`

---

## UIBUG-003 · El formato que la app muestra, tecleado tal cual, divide el valor por mil

| | |
|---|---|
| **Severidad** | CRITICAL · **Categoría** DATA / VALIDATION |
| **Pantalla / Ruta** | Todos los campos numéricos. Verificado en `/transferencias/nueva` y en el diálogo de pago de `/liquidacion` |

**Precondiciones**: Juan Pérez tiene 15 000 KG de Cloruro de Potasio.

**Pasos (transferencia)**
1. Operaciones → Transferir inventario → **Nueva**.
2. Origen: Juan Pérez. Junto al campo se lee **"15.000 KG disponibles"**.
3. Teclear en el campo exactamente **`15.000`**.
4. Destino: Ana Áñez → **Revisar y confirmar**.

**Resultado actual**: el diálogo resume **"Cloruro de Potasio: 15 KG"**.

**Pasos (pago — sin red de seguridad)**
1. Cuentas → ⋮ de José Luis → **Registrar pago**.
2. Teclear **`1.500`** → **Registrar**.

**Resultado actual**: se guarda `account_transactions.amount_bob_minor_signed = -150`, es decir
**1,50 Bs en lugar de 1.500,00 Bs**. Verificado leyendo la base del dispositivo.

**Resultado esperado**: o bien se interpreta el separador de miles que la propia aplicación
imprime, o bien se rechaza la entrada con un mensaje.

**Impacto**: **error de ×1000 en una aplicación de contabilidad**. En la transferencia el
diálogo de confirmación muestra la cantidad ya interpretada y un usuario atento puede
detectarlo; en el diálogo de pago **no hay confirmación, ni mensaje de éxito, ni resumen**, de
modo que el error se registra en silencio.

**Posible causa técnica** (con evidencia): `lib/presentation/widgets/common.dart:132`

```dart
final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
return num.tryParse(normalized);
```

El punto es siempre separador decimal. `formatQuantity` y `formatBob` usan
`NumberFormat(..., 'es_BO')`, donde el punto es separador de **miles**. Entrada y salida usan
convenciones opuestas.

**Archivos probablemente relacionados**: `lib/presentation/widgets/common.dart`,
`lib/domain/money.dart`.

**Relación**: RN-50 (redondeo/importes) · `16_VALIDATIONS.md` · `10_DATA_MODEL.md`

**Evidencia**: `UI-17-transfer-form/UI-17-ISSUE-formato-millares.png`,
`UI-17-transfer-form/_c-conf.png`

---

## UIBUG-004 · El botón Atrás sale de la aplicación desde cualquier pantalla, y los detalles no tienen botón de volver

> **⚠️ Este hallazgo se subdividió el 2026-09-05.** Mezclaba dos comportamientos con distinto
> veredicto. El texto de abajo se conserva íntegro como observación original.
>
> - **UIBUG-004A — CRITICAL** · la navegación **jerárquica** (`/personas/:id`, `/inventario/:id`,
>   `/chacos/:id` y las 4 subrutas de Operaciones) usa `context.go`, que reemplaza la pila, y
>   `PageFrame` no dibuja flecha de volver: **callejón sin salida funcional**.
> - **UIBUG-004B — MEDIUM · `DESIGN_DECISION_REQUIRED`** · que Atrás salga desde un **destino
>   raíz** (`/`, `/operaciones`, `/inventario`, `/personas`, `/liquidacion`) **no es
>   automáticamente un defecto**: es una política de navegación. Material 3 recomienda volver
>   antes al destino inicial; muchas apps de producción salen directamente. No hay pérdida de
>   datos ni contenido inalcanzable.
>
> Justificación completa y enumeración de la navegación en
> [`41` §3](41_UIBUG_MASTER_BACKLOG.md). En contextos de bloqueo de release, "UIBUG-004"
> significa **UIBUG-004A**.

| | |
|---|---|
| **Severidad** | CRITICAL · **Categoría** NAVIGATION |
| **Pantalla / Ruta** | Todas las del `ShellRoute`, en especial `/personas/:id`, `/inventario/:id`, `/chacos/:id` |

**Pasos**
1. Pestaña **Personas**.
2. Tocar una persona → se abre `/personas/:id`.
3. Pulsar el botón **Atrás** de Android.

**Resultado actual**: la aplicación **se cierra** y aparece el lanzador. Confirmado con
`dumpsys window`: `mCurrentFocus = …nexuslauncher…`. La pantalla de detalle **tampoco tiene
flecha de volver** en su cabecera, por lo que no existe ninguna forma de regresar a la lista:
hay que volver a entrar por la barra inferior.

Reproducido igualmente en Operaciones → *Registrar aplicación* → Atrás.

**Resultado esperado**: Atrás devuelve a la pantalla anterior; las pantallas de detalle
ofrecen una flecha de volver.

**Impacto**: se pierde el contexto de trabajo constantemente, y en un formulario a medio llenar
el gesto más natural del sistema cierra la aplicación. Es el defecto que más fricción genera en
el uso diario.

**Posible causa técnica** (con evidencia): toda la navegación del shell usa `context.go`, que
**reemplaza** la pila en lugar de apilar; nunca hay nada que desapilar. Las cuatro pantallas de
formulario (que sí usan `push`) no están afectadas: en ellas Atrás funciona bien.

**Archivos probablemente relacionados**: `lib/presentation/app_shell.dart`,
`lib/presentation/screens/persons_screen.dart`,
`lib/presentation/screens/person_detail_screen.dart`,
`lib/presentation/screens/inventory_screen.dart`,
`lib/presentation/screens/dashboard_screen.dart`.

**Relación**: STAB-001 (corrigió solo el caso del formulario de compra) · `08_NAVIGATION.md`

**Evidencia**: `UI-14-persona-detalle/UI-14-ISSUE-back-desde-detalle.png`,
`UI-02-operaciones/UI-02-ISSUE-back-sale-de-la-app.png`

---

# HIGH

## UIBUG-005 · Registrar un pago rompe la interfaz en compilación de depuración

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** FUNCTIONAL / ERROR_HANDLING |
| **Pantalla / Ruta** | `/liquidacion` |

**Pasos**: Cuentas → ⋮ de una persona → *Registrar pago* → escribir `150` → **Registrar**.

**Resultado actual**: la pantalla entera se sustituye por la pantalla roja de error de Flutter
(`'_dependents.isEmpty': is not true`) y la app queda **inusable hasta reiniciarla**. Ocurre
igual con importe válido y con el campo vacío. Cadena registrada en logcat:

1. `A TextEditingController was used after being disposed`
2. `framework.dart: Failed assertion line 6281: '_dependents.isEmpty': is not true`
3. `Tried to build dirty widget in the wrong build scope (InputDecorator)`

**El pago sí se guarda** (verificado: `account_transactions` id 28), pero el usuario no recibe
confirmación y, ante la pantalla roja, es probable que reinicie y **vuelva a registrarlo**.

**Alcance verificado**: se compiló e instaló `app-profile.apk` (assertions desactivadas, igual
que release) y el mismo paso **funciona correctamente**, sin pantalla roja: el saldo pasó de
800,50 a 950,50 Bs de pagos. **El fallo es exclusivo de las compilaciones de depuración.**
Se documentan ambos resultados.

**Impacto**: el APK de depuración es hoy el único instalable (el de release está sin firmar),
así que quien pruebe la aplicación se encontrará con esto. El uso indebido de un controlador
liberado es real aunque en release no lance.

**Posible causa técnica** (con evidencia): `settlements_screen.dart:71` crea
`final amount = TextEditingController();` dentro del método y lo libera en la línea 98
(`amount.dispose();`) justo al retornar `showDialog`, **mientras el diálogo aún se anima al
cerrarse**; el `TextField` sigue vivo y vuelve a suscribirse al controlador ya liberado.
Contraste: los diálogos de `catalogs_screen.dart` y `_PaymentDialog` de `purchases_screen.dart`
son `StatefulWidget` y liberan en `State.dispose()` — correctos.

**Archivos probablemente relacionados**: `lib/presentation/screens/settlements_screen.dart`.

**Evidencia**: `UI-10-liquidacion/UI-10-ISSUE-pago-vacio.png`,
`UI-10-liquidacion/UI-10-pago-valido.png`,
`UI-10-liquidacion/UI-10-pago-en-PROFILE-sin-asserts.png`

---

## UIBUG-006 · La etiqueta del campo y el texto "Seleccionar" se dibujan superpuestos en todos los selectores

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** LAYOUT |
| **Pantalla / Ruta** | `/planificacion/nueva`, `/compras/nueva`, `/aplicaciones/nueva`, `/transferencias/nueva` |

**Pasos**: abrir cualquiera de los cuatro formularios y mirar un selector sin valor.

**Resultado actual**: la etiqueta y el valor se pintan **uno encima del otro** y quedan
ilegibles: "Chaco" + "Seleccionar" se ve como `SelacctoOnar`; "Agregar producto" + "Seleccionar"
como `Seleccionarroducto`. En el formulario de compra ocurre a la vez en Proveedor, Producto y
Persona. Al elegir un valor la etiqueta sube y el campo se ve bien.

**Resultado esperado**: la etiqueta flota arriba y el texto de ayuda se lee limpio.

**Impacto**: es lo primero que ve el usuario al abrir cualquier formulario; da sensación de
producto roto y no se entiende qué pide el campo.

**Posible causa técnica** (con evidencia):
`lib/presentation/widgets/adaptive_entity_picker.dart:76` pasa `isEmpty: selected == null` al
`InputDecorator`, con lo que la etiqueta **no flota** y se queda en el centro del campo, justo
donde la línea 100 (`child: Text('Seleccionar')`) siempre pinta.

**Archivos probablemente relacionados**:
`lib/presentation/widgets/adaptive_entity_picker.dart`.

**Evidencia**: `UI-05-plan-form/UI-05-ISSUE-etiqueta-superpuesta.png`,
`UI-07-purchase-form/UI-07-formulario-inicial.png`, `UI-17-transfer-form/UI-17-inicial.png`

---

## UIBUG-007 · El buscador del inicio solo filtra las 5 filas precargadas y afirma que no hay inventario

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** FUNCTIONAL / DATA |
| **Pantalla / Ruta** | Inicio · `/` |

**Pasos**: Inicio → *Buscar producto* → escribir `glifo`.

**Resultado actual**: **"Aún no hay inventario."**, pese a existir `Glifosato 48 SL` y
`Glifosato 68 SG` con stock.

**Resultado esperado**: mostrar los dos productos; si no hubiera coincidencias, decir que la
búsqueda no encontró resultados, no que no hay inventario.

**Impacto**: el usuario concluye que su almacén está vacío. Son dos defectos que se refuerzan:
el filtro actúa sobre `inventorySummary(limit: 5)` (solo las 5 primeras filas alfabéticas) y el
estado vacío reutiliza el mensaje de "sin datos" para un caso de "sin coincidencias".

**Posible causa técnica**: filtrado en cliente sobre una consulta limitada a 5 filas.

**Archivos probablemente relacionados**: `lib/presentation/screens/dashboard_screen.dart`.

**Evidencia**: `UI-01-dashboard/UI-01-busqueda-resultado.png`

---

## UIBUG-008 · El FAB "Nuevo" tapa de forma permanente el último elemento de las listas

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** LAYOUT |
| **Pantalla / Ruta** | `/`, `/inventario`, `/liquidacion`, `/catalogos`, `/aplicaciones`, `/transferencias` |

**Pasos**: abrir Inicio y desplazarse hasta el final.

**Resultado actual**: el FAB queda encima del contenido y, **una vez agotado el scroll**, sigue
tapándolo. Casos observados:

| Pantalla | Qué queda oculto |
|---|---|
| Inicio | El importe del último saldo ("Juan Pérez · Familiar") |
| Liquidación | El importe **y el menú ⋮** de la tercera tarjeta |
| Catálogos → Productos | La última fila (`Zinc Quelatado`), cortada, con su ⋮ inaccesible |
| Aplicaciones | El botón ↩ de la última fila |
| Inventario | El valor de la última fila |

**Resultado esperado**: el desplazamiento reserva espacio suficiente bajo el FAB.

**Impacto**: información y **controles** permanentemente inaccesibles. En Liquidación impide
operar sobre una persona; en Catálogos impide editar o archivar el último registro.

**Posible causa técnica**: falta de relleno inferior en las listas para compensar el
`FloatingActionButton.extended`.

**Archivos probablemente relacionados**: `lib/presentation/app_shell.dart`,
`lib/presentation/widgets/common.dart` (`PageFrame`).

**Evidencia**: `UI-01-dashboard/UI-01-ISSUE-fab-tapa-ultima-fila.png`,
`UI-03-catalogos/UI-03-ISSUE-ultimo-item-inalcanzable.png`

---

## UIBUG-009 · Con el teclado abierto el FAB tapa el campo de búsqueda activo

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** LAYOUT / FORM |
| **Pantalla / Ruta** | Inicio · `/` |

**Pasos**: Inicio → tocar *Buscar producto* → escribir.

**Resultado actual**: el FAB queda **encima de la mitad derecha del campo**; no se ve lo
escrito en esa zona y un toque ahí activa el FAB en lugar del campo. Además los resultados
quedan por debajo del teclado y la pantalla no se desplaza hasta ellos, así que al teclear no
hay ninguna respuesta visible.

**Resultado esperado**: el FAB se oculta o se aparta con el teclado abierto y los resultados
quedan visibles.

**Evidencia**: `UI-01-dashboard/UI-01-busqueda-teclado.png`

---

## UIBUG-010 · Las aplicaciones revertidas no se marcan y el inicio las sigue contando

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** DATA / CONSISTENCY |
| **Pantalla / Ruta** | `/aplicaciones` y `/` |

**Precondiciones**: el dataset contiene una aplicación revertida (Juan Pérez · Lote 2 ·
178,75 Bs, `status = REVERSED`).

**Pasos**
1. Abrir **Aplicaciones**: la fila revertida aparece igual que las demás.
2. Abrir **Inicio** → *Aplicaciones recientes*: aparece con su costo de 178,75 Bs.
3. Abrir **Cuentas** → *Costo por chaco y hectárea*: "Lote 2 · Juan Pérez · **Total 0,00 Bs**".

**Resultado actual**: en Aplicaciones la única diferencia es la **ausencia** del botón ↩ — que
se confunde con "no se puede revertir". En Inicio no hay ninguna marca y se muestra el importe.
El reporte, en cambio, **sí la excluye**.

**Resultado esperado**: marca explícita "Revertida" y tratamiento coherente entre vistas, como
ya hace `TransfersScreen`, que sí escribe "Revertida".

**Impacto**: el usuario cree que una operación anulada sigue vigente, y ve dos cifras distintas
para el mismo hecho según la pantalla.

**Archivos probablemente relacionados**:
`lib/presentation/screens/applications_screen.dart`,
`lib/presentation/screens/dashboard_screen.dart`, `lib/data/agro_repository.dart`
(`applications()` no filtra por estado).

**Evidencia**: `UI-02-operaciones/UI-02-registrar-aplicacion-destino.png`,
`UI-01-dashboard/UI-01-scroll1.png`, `UI-10-liquidacion/UI-10-reportes.png`

---

## UIBUG-011 · Confirmar una compra no da ninguna confirmación

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** UX / FUNCTIONAL |
| **Pantalla / Ruta** | `/compras/nueva` |

**Pasos**: Operaciones → *Registrar compra* → completar la compra → **Confirmar**.

**Resultado actual**: el formulario se cierra y se vuelve a **Operaciones** sin ningún mensaje.
Nada indica que se hayan registrado 573,75 Bs. Y como `/compras` es inalcanzable (UIBUG-002),
no hay forma de comprobarlo.

**Resultado esperado**: mensaje de éxito, o volver a un listado donde la compra aparezca.

**Impacto**: el usuario no sabe si la operación se guardó; riesgo de registrarla dos veces.

**Posible causa técnica**: `pop(true)` devuelve el resultado a quien abrió el formulario;
`OperationsScreen` es `StatelessWidget` y no hace nada con él. El único llamador que sí muestra
mensaje y refresca es `PurchasesScreen`, que no es alcanzable.

**Archivos probablemente relacionados**:
`lib/presentation/screens/operations_screen.dart`, `lib/presentation/app_shell.dart`,
`lib/presentation/screens/purchase_form_screen.dart`.

**Evidencia**: `UI-07-purchase-form/UI-07-confirmada.png`

---

## UIBUG-012 · El diálogo "Registrar pago" no dice a quién se le está pagando

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** UX / DATA |
| **Pantalla / Ruta** | `/liquidacion` |

**Pasos**: Cuentas → ⋮ de una persona → *Registrar pago*.

**Resultado actual**: el diálogo se titula solo **"Registrar pago"** y contiene un único campo
"Importe BOB". No muestra la persona, ni su saldo pendiente, ni la campaña a la que se imputará,
ni pide confirmación.

**Resultado esperado**: identificar a la persona y la campaña, y mostrar el saldo.

**Impacto**: en una lista de seis personas con tarjetas altas es fácil abrir el menú equivocado
y **registrar un cobro a quien no era**, sin ningún punto de control. Se agrava con UIBUG-003
(el importe puede quedar dividido por mil) y con UIBUG-014 (no hay mensaje de éxito).

**Archivos probablemente relacionados**: `lib/presentation/screens/settlements_screen.dart`.

**Evidencia**: `UI-10-liquidacion/UI-10-dialogo-registrar-pago.png`

---

## UIBUG-013 · La misma persona muestra tres saldos distintos en tres pantallas

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** CONSISTENCY / DATA |
| **Pantalla / Ruta** | `/liquidacion`, `/personas`, diálogo de estado de cuenta |

**Precondiciones**: José Luis Ñáñez Álvarez, campaña Verano 2026.

**Pasos**
1. Cuentas (filtro Verano 2026) → tarjeta de José Luis → **"Saldo pendiente 19.359,50 Bs"**.
2. ⋮ → *Ver detalle cronológico* → la última fila acumulada dice **"Saldo 30.057,00 Bs"**.
3. Personas → José Luis → **"30.057,00 Bs"**.

**Resultado actual**: dos cifras distintas bajo la misma palabra "saldo", sin ninguna etiqueta
que explique que una es del periodo y la otra acumulada (el diálogo parte de un "saldo inicial
de campaña" de 10.697,50 Bs).

**Resultado esperado**: nombres distintos para conceptos distintos, o una nota que aclare el
alcance de cada cifra.

**Impacto**: en una liquidación entre familiares, ver dos importes distintos para lo mismo
destruye la confianza en la aplicación.

**Evidencia**: `UI-10-liquidacion/UI-10-lista.png`,
`UI-10-liquidacion/UI-10-estado-de-cuenta.png`, `UI-13-personas/UI-13-lista.png`

---

## UIBUG-014 · Registrar un pago no muestra ningún mensaje de éxito

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** UX |
| **Pantalla / Ruta** | `/liquidacion` |

**Pasos**: registrar un pago válido (comprobado en compilación *profile*, donde no interviene
UIBUG-005).

**Resultado actual**: la lista se refresca y nada más. Otras operaciones sí muestran mensaje
(*"Aplicación multiproducto confirmada."*).

**Impacto**: junto con UIBUG-003 y UIBUG-012, deja la escritura contable más delicada de la
aplicación sin ningún punto de verificación.

**Evidencia**: `UI-10-liquidacion/UI-10-pago-en-PROFILE-sin-asserts.png`

---

## UIBUG-015 · Errores técnicos de SQLite en inglés llegan al usuario

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** ERROR_HANDLING / TEXT |
| **Pantalla / Ruta** | `/liquidacion` (reproducido); potencialmente cualquiera |

**Pasos**: los de UIBUG-001.

**Resultado actual**: *"DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be
performed using SQLiteDatabase query or rawQuery methods only.) sql 'PRAGMA
wal_checkpoint(FULL)' args []"* en un snackbar rojo.

**Resultado esperado**: un mensaje en español que explique qué pasó y qué hacer.

**Posible causa técnica**: `friendlyError` (`common.dart:150`) solo traduce `FormatException` y
`StateError`; `DatabaseException` pasa tal cual.

**Relación**: E-01 de `17_ERROR_HANDLING.md` — registrado como hueco conocido y ahora
**reproducido en dispositivo**.

**Evidencia**: `UI-10-liquidacion/UI-10-exportar-backup.png`

---

## UIBUG-016 · Literales de base de datos en inglés mostrados al usuario

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** TEXT |
| **Pantalla / Ruta** | varias |

**Casos observados**

| Dónde | Qué se ve | Qué debería verse |
|---|---|---|
| Catálogos → Campañas | `PLANNED`, `CLOSED` (la activa sí dice "Activa") | Planificada, Cerrada |
| `/compras/nueva`, selector de asignación | `ADMIN`, `FAMILY`, `THIRD_PARTY` | Administrador, Familiar, Tercero |
| Persona → pestaña Cuenta | `PAYMENT` como título del movimiento | Pago |
| Diálogo de estado de cuenta | `PAYMENT` como título | Pago |

**Agravante de coherencia**: los mismos roles **sí** se traducen en Catálogos → Personas
("Familiar · Cobro por consumo") y en el selector de **origen** del formulario de transferencia
("Familiar", "Tercero"). Es decir, el mismo dato se muestra traducido en unas pantallas y en
crudo en otras.

**Impacto**: el usuario objetivo es un agricultor hispanohablante; estos literales no
significan nada para él.

**Evidencia**: `UI-03-catalogos/UI-03-menu-campana.png`,
`UI-07-purchase-form/UI-07-picker-persona2.png`,
`UI-17-transfer-form/UI-17-picker-origen.png`,
`UI-14-persona-detalle/UI-14-ISSUE-pestana-cuenta-inalcanzable.png`

---

## UIBUG-017 · Con escala de fuente al 130 % el texto se parte a mitad de palabra y las columnas se solapan

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** ACCESSIBILITY / LAYOUT |
| **Pantalla / Ruta** | `/liquidacion` (peor caso); afecta a toda la app |

**Pasos**: Ajustes de Android → tamaño de fuente ≈130 % (`settings put system font_scale 1.3`)
→ abrir **Cuentas**.

**Resultado actual**
- "Rodríguez" se parte como **"Rodrígue / z"** y "Salvatierra" como **"Salvatierr / a"**.
- El subtítulo "Cargos … pagos/créditos …" **choca con la columna del importe**
  ("Cargos" queda pegado a "14.530,00 Bs").
- La etiqueta **"Operaciones" de la barra inferior se parte en dos líneas** y desborda.

No se registró ningún `RenderFlex overflow` en logcat: el texto se ajusta por carácter en vez
de desbordar, por lo que el defecto es de legibilidad, no una excepción.

**Resultado esperado**: el texto se parte por palabras y las columnas mantienen su separación.

**Impacto**: la escala de fuente grande es habitual entre usuarios mayores, público probable de
esta aplicación.

**Evidencia**: `UI-23-fontscale/UI-23-liquidacion-130.png`

---

## UIBUG-018 · La última fila de los catálogos queda permanentemente cortada e inoperable

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** SCROLL / LAYOUT |
| **Pantalla / Ruta** | `/catalogos` |

**Pasos**: Operaciones → Administrar datos → pestaña **Productos** (22 productos) → desplazar
hasta el final.

**Resultado actual**: la última fila (`Zinc Quelatado`) queda **cortada por la mitad** entre la
barra inferior y el FAB, con su subtítulo ilegible y su menú ⋮ inalcanzable. El primer elemento
visible también aparece seccionado por arriba. Se comprobó que es el final real del
desplazamiento repitiendo el gesto.

**Resultado esperado**: poder ver y operar sobre todos los registros.

**Impacto**: el último elemento de cualquier catálogo no se puede editar ni archivar.

**Posible causa técnica**: la lista vive en un contenedor de altura fija (≈520 px según
`07_SCREENS.md` P-03) dentro de la página, de modo que su final coincide con la barra de
navegación.

**Evidencia**: `UI-03-catalogos/UI-03-ISSUE-ultimo-item-inalcanzable.png`

---

## UIBUG-019 · La búsqueda distingue tildes

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** FUNCTIONAL / UX |
| **Pantalla / Ruta** | selectores de los 4 formularios; también los buscadores de lista |

**Pasos**: `/planificacion/nueva` → selector **Chaco** → escribir `maria`.

**Resultado actual**: **0/8 resultados**, aunque existe *"Hacienda Santa María de los Ángeles
del Norte Grande"*.

**Resultado esperado**: encontrarlo; en un teclado móvil español lo normal es escribir sin
tildes.

**Impacto**: el usuario concluye que el registro no existe y lo crea duplicado.

**Posible causa técnica**: comparación con `toLowerCase().contains(query)` sin normalizar
diacríticos.

**Evidencia**: `UI-05-plan-form/UI-05-ISSUE-busqueda-sin-tildes.png`

---

## UIBUG-020 · Los nombres largos rompen la maqueta de las tarjetas de liquidación

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** LAYOUT |
| **Pantalla / Ruta** | `/liquidacion` |

**Resultado actual**: "María Fernanda Rodríguez Salvatierra" se reparte en **cuatro líneas, una
palabra por línea**, y el subtítulo fluye alrededor del importe. La tarjeta triplica su altura y
la lista se vuelve difícil de recorrer.

**Resultado esperado**: reparto de ancho razonable entre nombre e importe, o truncamiento con
elipsis.

**Evidencia**: `UI-10-liquidacion/UI-10-lista.png`

---

## UIBUG-021 · El texto se parte a mitad de palabra en el estado de cuenta

| | |
|---|---|
| **Severidad** | HIGH · **Categoría** LAYOUT / TEXT |
| **Pantalla / Ruta** | diálogo *Ver detalle cronológico* de `/liquidacion` |

**Resultado actual**: *"Herbicida Selectivo **Po / stemergente** para Cultivos…"*. La columna de
descripción es tan estrecha que "Glifosato 68 SG, Mancozeb 80" ocupa cuatro líneas.

**Resultado esperado**: partir por palabras y dar más ancho a la descripción.

**Evidencia**: `UI-10-liquidacion/UI-10-estado-de-cuenta.png`,
`UI-10-liquidacion/UI-10-dialogo-pago.png`

---

# MEDIUM

## UIBUG-022 · La tabla del inicio muestra una columna de casillas sin función
`/` · LAYOUT. El `DataTable` presenta una casilla de selección en la cabecera y en cada fila,
pero no existe ninguna acción masiva: tocar la fila navega al detalle. Roba ancho en una tabla
que ya no cabe. Causa probable: `onSelectChanged` en las filas activa `showCheckboxColumn`.
Evidencia `UI-01-dashboard/UI-01-inicio.png`.

## UIBUG-023 · Al desplazar la tabla del inicio en horizontal desaparece el nombre del producto
`/` · SCROLL. La primera columna no queda fijada; al llegar a "Valor" las filas son
`0 L / 500 L / 16.700,00 Bs` sin saber a qué producto pertenecen.
Evidencia `UI-01-dashboard/UI-01-tabla-scroll-horizontal.png`.

## UIBUG-024 · Punto y coma decimal mezclados en la misma línea
`/liquidacion`, `/personas`, `/chacos/:id`, `/planificacion` · TEXT / CONSISTENCY.
En *Costo por chaco y hectárea* se lee **"80.0 ha"** (punto decimal) junto a **"20.160,00 Bs"**
(punto de millares y coma decimal) en la **misma línea**. En un plan expandido conviven
"Área 120.0 ha" y "1.800 KG". Causa probable: las superficies se imprimen con una división
cruda (`area_m2 / 10000`) en lugar de `NumberFormat`.
Evidencia `UI-10-liquidacion/UI-10-ISSUE-mezcla-separadores.png`,
`UI-04-planificacion/UI-04-plan-expandido.png`.

## UIBUG-025 · Las cantidades de los resúmenes generados en SQL no usan el formato de la app
`/aplicaciones`, `/transferencias` · TEXT / CONSISTENCY. Se ve `Urea 25.0 KG`,
`Semilla Soya INTA-90 300.0 KG`, `Fosfato Diamónico 5000.0 KG`: punto decimal, decimal
superfluo y **sin separador de miles**, mientras el resto de la app usa `1.750,25 KG`. Causa
evidenciada: `items_summary` y `products_summary` se arman con `GROUP_CONCAT` y
`(quantity_base / 1000.0) || ' ' || unit` en SQL, sin pasar por `formatQuantity`.
Evidencia `UI-08-aplicaciones/_zoom-cantidad.png`, `UI-16-transferencias/UI-16-lista.png`.

## UIBUG-026 · La bitácora muestra el detalle FIFO en unidades internas
`/chacos/:id` · DATA / TEXT. En la entrada expandida se lee **"FIFO: #1: 600000"**: identificador
de lote y cantidad en **gramos**, sin unidad ni formato, justo debajo de un correcto
"real 600 KG". Causa: `farm_logbook_screen.dart:70` interpola `row['fifo_lots']` en crudo.
Evidencia `UI-15-bitacora/UI-15-ISSUE-fifo-crudo.png`.

## UIBUG-027 · Fechas en formato ISO
Varias pantallas · TEXT. `2026-01-25`, `2025-07-01`. No se localiza a `dd/mm/aaaa`. Observado en
la bitácora del chaco, la pestaña Cuenta de la persona y el estado de cuenta.

## UIBUG-028 · La pestaña "Cuenta" de la persona no muestra saldo acumulado
`/personas/:id` · DATA / CONSISTENCY. Lista los movimientos sin saldo corrido ni total, mientras
el diálogo de estado de cuenta de Liquidación sí lo calcula. Dos vistas del mismo dato con
distinto nivel de información.

## UIBUG-029 · El TabBar de la persona no se desplaza al tocarlo y trunca las etiquetas
`/personas/:id` · NAVIGATION / LAYOUT. De cinco pestañas se ven cuatro, la cuarta recortada como
**"Inve"** y "Cuenta" fuera de pantalla. Deslizar la barra no hace nada; solo se alcanzan
deslizando el **contenido**, sin ninguna pista de que se pueda.
Evidencia `UI-14-persona-detalle/UI-14-ISSUE-tabbar-recortado.png`.

## UIBUG-030 · Enorme espacio vacío bajo el contenido del detalle de persona
`/personas/:id` · LAYOUT. El área de pestañas tiene altura fija (480 px según `07_SCREENS.md`
P-14): con dos filas de contenido queda más de media pantalla en blanco.
Evidencia `UI-15-bitacora/UI-15-pestana-chacos.png`.

## UIBUG-031 · Guardar con el nombre vacío no hace nada y no explica por qué
`/catalogos` · VALIDATION / UX. En *Nuevo producto*, pulsar **Guardar** con los campos vacíos
deja el diálogo abierto sin error en línea, sin snackbar y sin deshabilitar el botón: parece que
la aplicación no responde.
Evidencia `UI-03-catalogos/_crop-guardar-vacio.png`.

## UIBUG-032 · El mensaje de validación del plan no refleja qué falta
`/planificacion/nueva` · TEXT / VALIDATION. Con el chaco ya elegido y sin productos, el error
dice *"Seleccione chaco y al menos un producto."*, mencionando algo que ya está resuelto.
Evidencia `UI-05-plan-form/_c-UI-05-guardar-sin-productos.png`.

## UIBUG-033 · En "¿Descartar cambios?" el botón destructivo es el primario
`/planificacion/nueva`, `/compras/nueva`, `/aplicaciones/nueva`, `/transferencias/nueva` · UX.
**Descartar** es el botón relleno y **Seguir editando** un texto plano; además no usa el color
de error que sí usa `confirmDestructiveAction` en las reversiones. Un toque por inercia pierde
el trabajo.
Evidencia `UI-05-plan-form/_c-UI-05-descartar-cambios.png`.

## UIBUG-034 · Los campos de cantidad vienen con "0" y el 0 no se limpia al enfocar
`/transferencias/nueva` · FORM. Escribir `5` deja **`05`**. Con ocho productos en pantalla, todos
a cero, además cuesta ver dónde se ha escrito.
Evidencia `UI-17-transfer-form/_zoom-cero.png`.

## UIBUG-035 · El selector abre el teclado automáticamente y deja ver solo tres opciones
Los cuatro formularios · FORM / SCROLL. Con ≥8 elementos el buscador toma el foco al abrir la
hoja; el teclado ocupa más de la mitad y de 8 chacos se ven 3. Hay que cerrar el teclado para
poder elegir.
Evidencia `UI-05-plan-form/UI-05-picker-chaco.png`.

## UIBUG-036 · "Sin resultados." queda oculto tras el teclado
Selectores de los formularios · LAYOUT. El mensaje se centra verticalmente en un área que el
teclado tapa: mientras se escribe el usuario ve un hueco en blanco. Solo aparece al cerrar el
teclado.
Evidencia `UI-05-plan-form/_crop-sinres.png`.

## UIBUG-037 · Etiquetas colgando cuando aún no hay producto elegido
`/compras/nueva` · TEXT. Se lee **"Precio BOB/"** y **"Costo 0,00 Bs /"**, con la barra sin
unidad detrás, hasta que se elige el producto.
Evidencia `UI-07-purchase-form/UI-07-ISSUE-precio-sin-unidad.png`.

## UIBUG-038 · El campo de cantidad de la asignación no tiene etiqueta
`/compras/nueva` · FORM. Aparece como un recuadro vacío; tras elegir producto su única pista es
la unidad (`L`). Nada dice que ahí va la cantidad asignada a esa persona.
Evidencia `UI-07-purchase-form/UI-07-ISSUE-asignacion-sin-etiqueta.png`.

## UIBUG-039 · La línea de compra dice "asignado" sin haber elegido persona
`/compras/nueva` · TEXT / DATA. Basta escribir la cantidad para que el resumen pase de
"pendiente 12,5 L" a "asignado", aunque la asignación no tenga persona. La validación al
confirmar sí lo detecta.

## UIBUG-040 · Campos de media anchura que truncan su contenido
`/compras/nueva` · LAYOUT. "Agropecuaria del Este S.R.L." se muestra como **"Agropecu…"** y
"Verano 2026" como **"Verano 20…"**, pese a haber espacio libre a la derecha.
Evidencia `UI-07-purchase-form/UI-07-factura-con-teclado.png`.

## UIBUG-041 · La etiqueta "Producto" queda recortada por la cabecera de la línea
`/compras/nueva` · LAYOUT. La etiqueta flotante del selector se solapa con la fila de resumen de
la tarjeta.
Evidencia `UI-07-purchase-form/UI-07-ISSUE-etiqueta-producto-recortada.png`.

## UIBUG-042 · Elegir en "Agregar producto" no agrega el producto
`/aplicaciones/nueva` · UX. Tras elegir en el selector, el contador sigue en **Productos (0)** y
el estado vacío sigue diciendo *"Agregue los productos de la mezcla."*. Hay que pulsar además un
botón **+** contiguo, que solo entonces se habilita. La acción no coincide con su etiqueta.
Evidencia `UI-09-application-form/UI-09-linea-producto.png`.

## UIBUG-043 · La línea de producto nace plegada y sin indicador de que se despliega
`/aplicaciones/nueva` · UX / FORM. Añadido el producto se ve solo *"Urea · 0 KG real / 0 KG
teórico · 0,00 Bs"*. Los campos **Dosis** y **Cantidad real** están dentro de un desplegable
cuyo chevron fue sustituido por el botón "Quitar", así que **no hay ninguna señal** de que la
fila se abra. Se comprobó que sí se despliega al tocarla.
Evidencia `UI-09-application-form/_c-fila.png` (plegada) y `_c-fila1.png` (desplegada).

## UIBUG-044 · "stock después" negativo no se resalta
`/aplicaciones/nueva` · UX. Al pedir más de lo disponible se muestra *"stock después
-249,75 KG"* en color normal, mientras `/inventario` sí pinta en rojo las proyecciones
negativas. La validación al confirmar es correcta.
Evidencia `UI-09-application-form/_c-val.png`.

## UIBUG-045 · Los planes ya aplicados siguen ofreciendo "Aplicar" sin ningún estado
`/planificacion` · DATA / UX. Los cinco planes del dataset ya se aplicaron y todos muestran el
botón **Aplicar** sin distintivo. Nada advierte de que volver a aplicarlos duplicaría el consumo.
Evidencia `UI-04-planificacion/UI-04-lista.png`.

## UIBUG-046 · Las filas de planificación son desplegables sin indicarlo
`/planificacion` · UX. El chevron fue sustituido por el botón "Aplicar"; el detalle por producto
solo aparece si se acierta a tocar el cuerpo de la fila.

## UIBUG-047 · Dos puntos de creación distintos en la misma pantalla
`/catalogos` · UX. Conviven el botón **Agregar** (crea en la pestaña activa) y el FAB **Nuevo**
(abre la hoja global de operaciones). Mismo aspecto de acción primaria, significados distintos.

## UIBUG-048 · La lista de campañas no muestra fechas
`/catalogos` · DATA. Solo nombre y estado, aunque `campaigns` guarda inicio y fin, y las fechas
son el criterio natural para distinguir campañas.

## UIBUG-049 · Iconografía de nube para un backup puramente local
`/liquidacion` · UX / TEXT. La acción se representa con una **nube con flecha**, que sugiere
sincronización remota; la aplicación no tiene ninguna función de red y el respaldo es un archivo
local. Dentro del menú, además, **"Exportar backup"** usa un icono de **descarga**.
Evidencia `UI-10-liquidacion/UI-10-menu-backup.png`.

## UIBUG-050 · Un aviso informativo se muestra como error
`/liquidacion` · UX. *"No se encontró ningún backup. Exporte uno primero…"* aparece en el
snackbar **rojo** de error, cuando es una indicación normal.
Evidencia `UI-10-liquidacion/UI-10-restaurar-backup.png`.

## UIBUG-051 · Las tarjetas de Operaciones prometen una acción y llevan a una lista
`/operaciones` · UX / NAVIGATION. *"Registrar aplicación"* lleva a `/aplicaciones` (el listado) y
*"Transferir inventario"* a `/transferencias`, mientras *"Registrar compra"* sí abre el
formulario. Comportamiento distinto bajo etiquetas del mismo estilo.
Evidencia `UI-02-operaciones/UI-02-registrar-aplicacion-destino.png`.

## UIBUG-052 · Personas es la única lista sin buscador ni recarga
`/personas` · UX / CONSISTENCY. Inicio, Inventario, Aplicaciones, Compras y Liquidación tienen
buscador; Inventario e Inicio tienen botón de recarga. Personas no tiene ninguno.

## UIBUG-053 · Transferencias no muestra fechas ni ofrece filtros
`/transferencias` · DATA / UX. El historial no indica **cuándo** ocurrió cada movimiento y
carece de buscador y de filtro por campaña, a diferencia de Aplicaciones.
Evidencia `UI-16-transferencias/UI-16-lista.png`.

## UIBUG-054 · Dos selectores contiguos de la misma pantalla muestran datos distintos
`/transferencias/nueva` · CONSISTENCY. El selector de **origen** muestra el rol de cada persona
("Familiar", "Tercero"); el de **destino**, no. Además el de origen excluye al ADMIN (6/6)
mientras el de asignación del formulario de compra lo incluye (7/7) y muestra el rol en inglés.
Evidencia `UI-17-transfer-form/UI-17-picker-origen.png`,
`UI-17-transfer-form/UI-17-picker-destino.png`.

## UIBUG-055 · La lista de productos disponibles se corta a mitad de fila
`/transferencias/nueva` · SCROLL / LAYOUT. La lista está acotada a ≈48 % de la altura de la
pantalla y su último elemento visible (`Semilla Soya INTA-90`) aparece seccionado, sin ninguna
señal de continuidad.
Evidencia `UI-17-transfer-form/UI-17-productos-disponibles.png`.

## UIBUG-056 · Decimales variables en la misma fila
`/inventario` · TEXT. Una fila muestra *"Físico 174,25 L"* y, como proyección, *"174,1 L"*: el
patrón `#,##0.###` suprime el cero final. Dificulta comparar cifras alineadas.

---

# LOW

- **UIBUG-057** · `/personas` — El administrador aparece con *"0.0 ha"* y saldo 0,00 Bs pese a no
  participar en la liquidación. Ruido en la lista.
- **UIBUG-058** · `/liquidacion` — En el estado de cuenta el cargo lleva un icono **+** naranja y
  el pago un **−** verde; la combinación signo/color se lee al revés de lo esperado.
- **UIBUG-059** · `/catalogos` — Se ofrece **Activar** sobre una campaña `CLOSED` sin advertir de
  que se reabre un periodo cerrado. (El cambio de campaña activa **sí** pide una confirmación
  clara y correcta.)
- **UIBUG-060** · `/transferencias/nueva` — La sección *"2. Productos disponibles"* muestra un
  escueto **0** antes de elegir origen, sin texto que lo explique.
- **UIBUG-061** · Selectores — La hoja ocupa el 65 % de la pantalla aunque solo haya 4 elementos
  (altura fija).
- **UIBUG-062** · `/chacos/:id` — La barra inferior resalta **Inicio** mientras se está en la
  bitácora de un chaco, porque la ruta no coincide con ningún destino.
- **UIBUG-063** · Horizontal — En el `NavigationRail` los destinos se muestran **solo con
  iconos**, sin etiqueta (el modo extendido exige ≥1150 px y el Pixel 8 apaisado da ≈914).
  Evidencia `UI-22-orientacion/UI-22-horizontal-bitacora.png`.
- **UIBUG-064** · `/compras/nueva` — La tarjeta *TOTAL COMPRA* queda parcialmente solapada por la
  barra de gestos del sistema.
- **UIBUG-065** · `/liquidacion` — El único `catch (_) {}` que queda (`parseMinor` en el botón
  Registrar) se traga en silencio un importe no parseable, sin ningún aviso.

  > **⚠️ Corrección de esta descripción (2026-09-05).** La afirmación de arriba es **incorrecta**
  > y se conserva solo como registro. Verificado en código: `parseMinor` es
  > `int parseMinor(String v) => tryParseMinor(v) ?? 0;` (`common.dart:147`) y **no lanza nunca**,
  > luego el `catch (_) {}` de `settlements_screen.dart:89` es **código muerto inalcanzable**.
  > Lo que ocurre en realidad: el texto no parseable se convierte en `0` y `addAccountPayment`
  > (`agro_repository.dart:598`) lo rechaza con *"El importe debe ser mayor a cero."*
  > **No es un error silencioso, es un mensaje engañoso.** La severidad **se mantiene en LOW**
  > (el error se detecta y no se escribe nada), pero el hallazgo cambia de naturaleza.
  > Ver [`41` §5 y ficha UIBUG-065](41_UIBUG_MASTER_BACKLOG.md).

---

# Comprobaciones que resultaron correctas

Se registran para que la auditoría no se lea como una lista sesgada:

| Comprobación | Resultado |
|---|---|
| Confirmación de reversión (transferencia, aplicación) | ✅ Icono de aviso, contexto completo, consecuencia explicada, botón rojo |
| Confirmación de cambio de campaña activa | ✅ Explica qué se cierra y qué se activa |
| Validación de stock insuficiente al aplicar | ✅ Mensaje claro y previsualización de "stock después" |
| Validación de asignación sin persona en la compra | ✅ *"Seleccione la persona de cada asignación."* |
| Cálculo en vivo de la compra | ✅ 12,5 L × 45,90 = 573,75 Bs exacto |
| Conversión USD→BOB | ✅ 18,75 USD × 6,96 = 130,50 Bs/L |
| Propagación compra → inventario | ✅ 2,4-D Amina 500 L → 512,5 L |
| Productos con stock cero en los reportes | ✅ Aparecen en cero, no desaparecen (STAB-005) |
| Reporte excluye la aplicación revertida | ✅ Correcto (el problema es que el inicio no) |
| Teclado en el formulario de compra | ✅ El campo activo permanece visible; la pantalla se desplaza |
| Cambio rápido de pestañas (30 veces seguidas) | ✅ Sin excepciones en logcat |
| Rotación a horizontal | ✅ Cambia a `NavigationRail` sin desbordes |
| Formato de cantidades en `formatQuantity` | ✅ Coma decimal y punto de millares correctos en es-BO |
| Selector de destino excluye al origen | ✅ 5/5 |
| "Descartar cambios" al salir de un formulario sucio | ✅ Aparece y funciona |
| Formulario recién abierto **no** se marca como sucio | ✅ **STAB-019 no reproducible** (ver abajo) |

## Hallazgo previo NO reproducido

**STAB-019 — "dirty" espurio del formulario de compra.** Se abrió el formulario de compra y el
de aplicación y se pulsó Atrás **sin tocar nada**: en ambos casos la pantalla se cerró
directamente, **sin** el diálogo "¿Descartar cambios?". Con este dataset no se reproduce, muy
probablemente porque la autoselección solo se dispara cuando existe una única opción y aquí hay
4 proveedores, 22 productos y varias personas. Queda como **NO REPRODUCIBLE con datos
realistas**.

Evidencia: `UI-07-purchase-form/_c-dirty.png`, `UI-09-application-form/_c-dirty.png`.
