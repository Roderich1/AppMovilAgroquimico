# Datos del pago al proveedor y comprobación en EMULADOR de las correcciones X01

- **Fecha real:** 2026-10-26 (America/La_Paz). Sesión A.
- **Rama / PR:** `fix/x01-pagador-productos-inicio`, PR Mobile #149. Commits de este bloque: `fce91df` (ajuste del pago) y `0f1e15f` (hallazgos de la revisión cruzada). Base previa: `09ad5f9`.
- **Qué es:** (1) el ajuste previo al merge que pidió Roderich sobre `confirmPurchase(paidInFullByOwner:)` y (2) la comprobación técnica y visual de #149 en el **emulador Android** del equipo, porque no hay teléfono físico disponible. **No es una sesión de usabilidad** ni sustituye a X02; nada de lo observado se atribuye a un participante. Los tiempos del emulador no se comparan con los del POCO.
- **Lo anterior se conserva:** el registro de X01 (Backend, PR #169) y la comprobación en el POCO de `22e4e45` (`F10_X01_CORRECCIONES_22E4E45.md`) no cambian.

## 1. El problema y la solución mínima

`confirmPurchase(paidInFullByOwner: true)` escribía el pago con `method = 'TRANSFER'` y `payment_date = fecha de la compra` aunque «¿Pagaste toda esta compra?» sólo dice que se pagó el total. El pago posterior desde Compras también mandaba `'TRANSFER'` fijo (lo hacía desde antes de X01: `docs/10_DATA_MODEL.md` lo documentaba como «la UI siempre manda 'TRANSFER'»).

**Contrato** (`app_database.dart`, tabla `provider_payments`): `payment_date TEXT NOT NULL`, `method TEXT NOT NULL`, sin enumeración ni `CHECK` de valores. Ninguna lectura de `lib/` consume `method` ni `payment_date` (sólo sumas de importes); `provider_payments` no se sincroniza con Central; el respaldo copia el archivo. No hay cambio de esquema ni de Backend.

**Solución aplicada** (`fce91df`, `0f1e15f`):

| Pieza | Antes | Ahora |
|---|---|---|
| Pagador | Titular vigente (`owner_bindings`), automático | **Igual** |
| Pregunta | «¿Pagaste toda esta compra?» sin respuesta por defecto | **Igual** |
| Importe | Total de la compra | **Igual**, mostrado («Importe: …») |
| Medio | `'TRANSFER'` fijo, invisible | `PaymentMethod` (`lib/domain/models.dart`): **Efectivo / Transferencia / Sin indicar**, chips visibles bajo «Sí, pagué todo»; por defecto **«Sin indicar»**, que se guarda como `UNSPECIFIED` (el valor explícito de «no lo indicó»; la columna exige un valor y no se supone ninguno) |
| Fecha | Fecha de la compra, invisible | Fila **«Fecha del pago»** visible y corregible: empieza en el día de la compra («(el día de la compra)», o «(hoy)» si la compra es de hoy); el selector no ofrece el futuro |
| Pago posterior (Compras › Registrar pago) | `'TRANSFER'` fijo, fecha = ahora, invisibles | Mismos campos (`ProviderPaymentFields`): medio por defecto «Sin indicar», día por defecto hoy, los dos corregibles |
| Repositorio | `confirmPurchase(draft, paidInFullByOwner: bool)`; `addProviderPayment(method: String)` | `confirmPurchase(draft, {ProviderPaymentDetails? paidInFull})`; `addProviderPayment(method: PaymentMethod, date?)`. **Una sola transacción** compra + pago, como antes. Regla nueva sólo para pagos nuevos: la fecha del pago **no puede ser posterior a hoy** (RN-16, `docs/15_BUSINESS_RULES.md`); un anticipo anterior a la compra se admite (el contrato no lo prohíbe). Los pagos guardados no se reescriben |
| Captura tardía (RF-03) | El pago no se guarda con la revisión y se avisa | **Igual** |

Documentación: `docs/05_FEATURES.md` (F-06), `docs/10_DATA_MODEL.md`, `docs/15_BUSINESS_RULES.md` (RN-16), `docs/26_TECHNICAL_DEBT.md` (deuda resuelta).

## 2. Revisión cruzada (antes de integrar)

Revisión independiente del diff `09ad5f9..fce91df` por otra sesión, sin editar código. Cuatro hallazgos; todos atendidos en `0f1e15f`:

| # | Gravedad | Hallazgo | Respuesta |
|---|---|---|---|
| 1 | Media | La cota «fecha del pago no anterior a la compra» era una regla nueva, fuera del contrato y de RN-16; impediría registrar un anticipo real | **Quitada.** Queda sólo «no posterior a hoy». El selector abre desde 2000. Prueba cambiada: el anticipo se guarda tal cual |
| 2 | Baja | Si el día mostrado quedara después del reloj (reloj atrasado, base restaurada), `showDatePicker` recibiría `firstDate > lastDate` | `lastDate = max(hoy, día mostrado)` |
| 3 | Baja | `docs/26_TECHNICAL_DEBT.md` seguía diciendo «la UI siempre envía 'TRANSFER'» | Marcado como resuelto el 2026-10-26 |
| 4 | Baja | La prueba «compra de un día anterior» no ejercita el cambio de día de pago cuando el día del mes es 1, y depende de la localización inglesa del selector («OK», «Previous month»), como `f10_x01_pago_revision_test` | Anotado aquí como límite; la rama se ejercita los otros 30 días |

Comprobado sin hallazgo por la revisión: ningún otro productor de `provider_payments` (voz confirma la compra sin pago; captura tardía nunca crea pago; restauración copia el archivo); atomicidad (el rechazo por fecha deshace también la compra; `saving` evita el doble envío); históricos intactos (el único `UPDATE` es `reversed_at` en la reversión, preexistente); etiquetas «(hoy)» / «(el día de la compra)» y zona horaria (UTC−4, guardado en UTC, mismo día local a la vuelta); chips en `Wrap` y formulario desplazable con fuente ampliada y teclado.

## 3. Pruebas automatizadas

Nueva: `test/f10_x01_pago_datos_test.dart` (8 pruebas): códigos de `PaymentMethod`; el medio indicado se guarda tal cual (los tres valores); fecha futura rechazada sin escribir compra ni pago (`dumpTables` igual antes y después); anticipo admitido; pago posterior no futuro con medio guardado; **pantallas**: compra de hoy con «Sí» sin tocar nada más (medio «Sin indicar» y «(hoy)» visibles; guardado `UNSPECIFIED` y día de hoy), compra de un día anterior (empieza en «(el día de la compra)»; se corrige a Efectivo y a hoy; guardado `CASH`), pago posterior desde Compras (medio y fecha visibles; «Transferencia» guardada). Adaptadas: `f10_x01_pagador_titular_test` (medio y fecha explícitos), fixtures con el enum (`ui_audit_seed`: «EFECTIVO» → `cash`, «CHEQUE» → `unspecified`; textos libres que la app nunca ofreció).

Resultados: §6.

## 4. Comprobación en el EMULADOR (no es un dispositivo físico ni una sesión con participante)

| Elemento | Valor |
|---|---|
| Emulador | AVD `Pixel_8` del equipo: Android **16** (API 36, `google_apis_playstore`, x86_64, página de 16 KB), 1080 × 2400 px, 420 dpi, `font_scale` 1,0; `hw.keyboard` puesto en `no` durante la comprobación para que aparezca el teclado en pantalla (Gboard) y restaurado a `yes` al terminar; zona horaria puesta en America/La_Paz (arranca en GMT). No es el POCO X5 Pro: **sus tiempos no se comparan** con los de las sesiones físicas |
| Paquete | `com.comunidad.agro.agroquimicos.x01emu` («Agrocuentas X01 emu»), **profile**, ABI x86_64, aislado: la app normal y la `.f10eval` que ya estaban en el emulador no se tocaron. **Desinstalado al terminar**; la APK se conserva en `%TEMP%\agro_a_x01emu\` |
| APK | `build_profile_apk_x64.sh` (copia de `tool/f10_eval/build_profile_apk.sh` con `--target-platform android-x64`) sobre el worktree limpio en **`0f1e15f`**, con el túnel del día. SHA-256 **`875505c37645b5b7495cf04a99601c3b483e1b533b7bfd8b897b2bc65d852ebe`**, igual al `base.apk` instalado. targetSdk 36. (Una APK previa de `fce91df`, `9e4378f2…`, sólo sirvió para activar y sembrar; se reinstaló con `-r` conservando los datos antes de cualquier recorrido) |
| Central | Contenedor nuevo `agro_a_x01emu_pg` (postgres:16-alpine, 127.0.0.1:55480), sólo las 13 migraciones; API del `dist` de Backend `4bcb1ea` en el 3164 con `NODE_ENV=development`, `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic`, `COLLECTIVE_SEALING=disabled`, `SYNC_V1_PRODUCTION_ADMISSION=enabled`; observador en el 3165 y quick tunnel de `cloudflared` 2026.10.0. Al terminar se pararon API, túnel y observador; el contenedor se conserva, como los anteriores (`agro_a_x01_pg`, `agro_a_x01fix_pg` intactos) |
| Siembra Central | `Back/scripts/f10-dsux-central-seed.cjs` de BE `main` `1cc439b`, destino `movil`, etiqueta `X01EMU`, S = 2026-10-26, cuentas sintéticas `T01` y `T02` (tenant `f10ux-movil-x01emu`); referencias SHA-256 `22445f58…`, `same_tenant_as_accounts: true` |
| Siembra Mobile | `tool/f10_ux/seed_dsux_mobile.dart` de `0f1e15f` (sin cambios desde `1d77c14`), `F10_UX_SESSION_DATE=2026-10-26`. T02 en **COMPARTIDA** (base `84c14fe9…`, igual en PC y emulador) y T01 en **PROPIA** (base `f301b97d…`, igual). Oráculo inicial en las dos: 5 000 = 5 000 y 1 000 = 1 000, `consistent: true` |
| Contraseñas | De un solo uso, asignadas por `stdin` (bcrypt) y tecleadas por el arnés; no se mostraron ni escribieron |
| Red | Encendida. El observador registró **sólo las dos activaciones** (login, clients, session/client, me) y ningún `push` |

### 4.1 Recorridos

Capturas en `%TEMP%\agro_a_x01emu\capturas\` (SHA-256, 16 hex). «UI» = textos leídos con `uiautomator`; «base» = consulta de sólo lectura sobre una copia de la base del emulador.

| # | Modalidad · fuente | Recorrido | Resultado | Captura |
|---|---|---|---|---|
| E1 | Compartida · 100 % | Inicio tras la siembra | **PASS.** Cuatro accesos, sin «Nuevo» flotante; «Campaña activa: Verano Demo», «Compras 405,00 Bs» | `9f74dee2b621a842` |
| E2 | Compartida | Registrar compra → paso 1 con el **teclado abierto** en «Cantidad comprada» | **PASS.** El campo queda visible sobre el teclado (`adjustResize`); nada se solapa | `217592915620fb6c` |
| E3 | Compartida | Paso 1: Proveedor Demo, Glifosato Demo 2 L a 45 Bs/L, «¿Para quién es?» Titular 2 L | **PASS.** Tarjeta «Glifosato Demo 2 L · 90,00 Bs · Asignado» | `9dc61630b2b205f1` |
| E4 | Compartida | Continuar → paso 2 → **Atrás** → paso 1 conserva producto, cantidad, precio y reparto → Continuar | **PASS** | — |
| E5 | Compartida | Paso 2: Confirmar sin responder → «Indica si pagaste toda esta compra.»; «Sí, pagué todo» | **PASS.** Aparecen «Pago registrado por: Titular», «¿Cómo pagaste?» con **«Sin indicar» marcada** y «Fecha del pago 26/10/2026 (hoy) · Cambiar»; antes de responder no hay campos del pago | `db26a236bc66557c` |
| E6 | Compartida | Confirmar compra **sin tocar medio ni fecha** | **PASS.** Inicio: «Compras 495,00 Bs», «Pagado proveedores 90,00 Bs». Base: compra 3 (9 000) y pago 1: pagador **1 = Titular = `owner_bindings`**, 9 000, `method = UNSPECIFIED`, `payment_date` = el instante de la compra (hoy) | `d84d2b172c0918b3` |
| E7 | Compartida | Registrar compra con **fecha 20/10/2026** (selector), Bellator 0,5 L a 180 para Familiar Demo → Continuar → «No, todavía no» → Confirmar | **PASS.** «La compra queda sin pago…»; base: compra 4 (`2026-10-20T04:00Z` = medianoche local), asignación a la persona 2 (500 mL), **ningún pago nuevo** | `14c123d4ef9e8bb7` |
| E8 | Compartida | Operaciones › Compras › menú de la compra 4 › «Registrar pago» | **PASS.** Diálogo: «Paga el titular: Titular», importe 90 (máximo 90,00), «¿Cómo pagaste?» con «Sin indicar» marcada, «Fecha del pago 26/10/2026 (hoy) · Cambiar» | `214a9170da05bd47`, `1faa6859cb92bf6b` |
| E9 | Compartida | «Transferencia» → Cambiar → **23/10/2026** → Registrar | **PASS.** Lista: «pagado 90,00 Bs». Base: pago 2 (compra 4, pagador 1, `2026-10-23T04:00Z`, 9 000, `TRANSFER`) | `393d56f222edd9e1` |
| E10 | Compartida | Registrar aplicación → paso 1: Titular, Norte (1 ha precargada) → Continuar → «Productos (0)» → «Agregar producto» → **Cancelar** → otra vez → cantidad 1 sin producto → «Elige el producto.» | **PASS** | — |
| E11 | Compartida | Elegir Glifosato Demo («Disponible 7 L», «Hay 7 L.») con el **teclado abierto** → «Agregar a la mezcla» | **PASS.** Hoja entera sobre el teclado; «Productos (1)», tarjeta «Glifosato Demo · 1 L · Hay 7 L · quedarán 6 L», Editar y Quitar. **Bellator no entró** | `50848e521780fb11`, `2c7249e0e3a56461` |
| E12 | Compartida | «Agregar producto» → el selector ofrece **sólo Bellator (1/1)** → agregar 0,2 L → **Editar** 0,3 L → «Guardar cambios» → **Quitar** → volver a agregar 0,2 L | **PASS.** «Productos (2)»; tras editar «0,3 L · quedarán 0,7 L»; tras quitar «Productos (1)» sin Bellator; tras volver a agregar «Productos (2)» con 1 L y 0,2 L; «Todos los productos en existencia ya están en la mezcla.» | `7464c645023bea1c` |
| E13 | Compartida | **Atrás** (Titular y Norte conservados) → Continuar («Productos (2)» conservados) → Continuar → resumen → Confirmar aplicación | **PASS.** Base: 1 aplicación (Titular, Norte, 10 000 m²) con **exactamente** dos líneas (1 000 y 200 mL); existencias Titular 6 000 / 800 mL, Familiar Demo 500 mL de Bellator | `514daa93f8048f77` |
| E14 | Compartida | Registrar aplicación → Bellator **5 L** en la hoja | **PASS.** «Hay 0,8 L.» y «Con esa cantidad la aplicación no se podrá guardar: hay 0,8 L.»; tarjeta «5 L · Hay 0,8 L: faltan 4,2 L»; al confirmar: «No alcanza el Bellator: hay 0,8 L y escribiste 5 L. Baja la cantidad o registra primero la compra.»; base sin cambios (1 aplicación, 2 líneas) | `82f11fa7ee1ad3aa`, `0c8d3c05ae754d78` |
| E15 | Compartida | Botón **Atrás del sistema** en el paso 3 y en el 2 | **PASS** (observación): vuelve un paso conservando el borrador; sólo en el paso 1 ofrece «¿Descartar cambios?» | — |
| E16 | Compartida | «Ver cuánto queda» | **PASS.** «Bellator Físico 1,3 L», «Glifosato Demo Físico 6 L» | `11071395732d64fd` |
| E17 | Compartida | «Enviar al sindicato» | **PASS.** Abre «Sincronización» con «Sincronizar ahora» y «Lo que se envía al sindicato: sólo totales propios.»; **ninguna petición** en el observador | `83448c3c1225c2a2` |
| E18 | Compartida | Operaciones y Más | **PASS.** Compras, Aplicaciones, Planificación, Transferencias y Más; Más con Reportes, Administrar datos, Modo de uso («Ahora: inventario compartido»), Vínculos, Respaldo en la nube, Copias de seguridad, PIN del titular (y, al desplazar, Operaciones tardías y Registrar por voz); «Volver» | `f9364ff59ee4d705` |
| E19 | Compartida · **130 %** | Paso 2 con «Sí, pagué todo» (borrador hecho al 100 %, `font_scale` 1,3 aplicado sin perderlo) | **PASS.** Los chips pasan a **dos líneas** (`Wrap`); «Fecha del pago» y «Cambiar» enteros; nada recortado. Borrador descartado después | `e5aa80cdeac30f48`, `20552998e89fe35c`, `91fdf263d87f504e` |
| E20 | Compartida · 130 % | Inicio | **PASS.** Los cuatro accesos siguen en dos columnas (411 dp de ancho) con **las palabras enteras** | `c31f9b1a924ecc50` |
| E21 | Compartida · 130 % | Diálogo «Registrar pago» (compra DSUX-INI-1, sin pagar) → Cancelar | **PASS.** Chips en dos líneas, fecha y botones enteros; nada se guardó (siguen 2 pagos) | `e292fe1c8cf78627` |
| E22 | Compartida · 130 % | Hoja «Agregar producto» con el teclado abierto; tarjeta; Más | **PASS.** Hoja entera sobre el teclado; tarjeta «1 L · Hay 6 L · quedarán 5 L» con Editar y Quitar; Más legible. Borrador descartado | `9cfa29c52cf5e535`, `17d5c77e12522684`, `d6676bb97d8ac8e6` |
| E23 | **Propia** · 100 % | `pm clear`, activación con T01, titular «Titular», **Propio**; siembra PROPIA. Registrar compra con **fecha 20/10/2026**: Glifosato Demo 1 L a 45 | **PASS.** «Para el titular: Titular», sin reparto que elegir | `262da9d2a9d4f804` |
| E24 | Propia | Paso 2 → «Sí, pagué todo» | **PASS.** «Fecha del pago **20/10/2026 (el día de la compra)**», «Sin indicar» marcada | `9cef21f5c0c47225` |
| E25 | Propia | Confirmar (el arnés dejó marcada «Transferencia» por un toque desviado; la pantalla lo mostraba así antes de confirmar) | **PASS.** «Compra guardada.». Base: compra 3 (`2026-10-20T04:00Z`, 4 500); pago 1 (pagador 1 = Titular = `owner_bindings`, **`payment_date` = 2026-10-20**, `TRANSFER`): **lo guardado es exactamente lo que la pantalla mostraba**. El titular es FAMILY, no ADMIN | — |
| E26 | Propia | Segundo borrador con fecha 20/10: «Sí» → **Efectivo** → Cambiar → el selector abre en el 20/10 (ayuda «Fecha del pago») → **23/10/2026** → OK | **PASS.** «Efectivo» marcada y «Fecha del pago 23/10/2026» (sin «(el día de la compra)»). Borrador descartado sin guardar (siguen 3 compras y 1 pago) | `455f97700d398dba`, `dc99332737c865d1` |
| E27 | Propia | Registrar aplicación → «Aplica el titular: Titular» (sin selector) → Norte → Glifosato Demo 1 L → resumen → Confirmar | **PASS.** «Aplicación guardada.». Base: 1 aplicación del Titular en Norte con 1 línea de 1 000 mL | `c0ec2a22c54feb9c`, `5ec874aabbdaf3d3` |
| E28 | Ambas | `adb logcat` desde el arranque de cada instalación, al 100 % y al 130 % | **0** mensajes `overflowed by` / `RenderFlex`. Las únicas líneas `[ERROR]` de la app son los mensajes mostrados a propósito («Indica si pagaste toda esta compra.», «No alcanza el Bellator…») | — |

**Oráculo final de cada instalación** (`oracle_dsux_mobile.dart`, sólo lectura):
- **T02 (compartida)**, base `5db42f9c…`: Glifosato Demo 5 000 + 2 000 − 1 000 = 6 000 = 6 000; Bellator 1 000 + 500 − 200 = 1 300 = 1 300 (Titular 800, Familiar Demo 500); `consistent: true`; sin necesidades; cola vacía. **Los mismos valores que en el POCO** (`F10_X01_CORRECCIONES_22E4E45.md` §4) y que la hoja de valores esperados de T3.
- **T01 (propia)**, base `db68cb6b…`: Glifosato Demo 5 000 + 1 000 − 1 000 = 5 000 = 5 000; Bellator 1 000; `consistent: true`.

**Incidencias del operador** (no del producto): tres veces el arnés tecleó en el campo de precio o marcó otro chip porque el campo o el chip de destino quedaba bajo el teclado o desplazado (igual que en el POCO); se corrigió a mano y, en E25, se registró lo que la pantalla mostraba. El botón Atrás del sistema con el teclado cerrado retrocede un paso del formulario (E15); el arnés ahora comprueba `mInputShown` antes de pulsarlo.

## 5. Observaciones fuera de este bloque (no corregidas aquí)

- La pantalla «Sincronización» (acceso «Enviar al sindicato») muestra la etiqueta **«Sin ACK todavía»**: lenguaje técnico que el bloque X01 pedía evitar (sin FIFO/outbox/ACK). No se cambió en este PR para no ampliar el alcance del ajuste; queda para decisión de Roderich.
- Al 130 % en el emulador (411 dp) los accesos de Inicio quedan en dos columnas; en el POCO (393 dp) pasaron a una. En los dos casos las palabras quedan enteras: es el comportamiento previsto por `_PrimaryActions` (medida del texto), no una diferencia de código.

## 6. Resultados de la suite y límites

- **Suite completa sobre `0f1e15f`** (`flutter test`, terminada el 2026-10-26 18:40:33Z, con el emulador apagado y sin otra carga): **1 843 pasan, 3 omitidas, 0 fallan** («All tests passed!», 01:41). `dart format --set-exit-if-changed`: 0 cambios. `flutter analyze`: No issues found.
- Una ejecución anterior de la suite, lanzada sobre `fce91df` **mientras** se compilaba la APK, corría Gradle y se editaban archivos del mismo worktree para los hallazgos de la revisión, dio 6 fallos en pruebas de pantalla con tiempos fijos (`f10_x01_aplicacion_productos`, `f10_x01_inicio_mas`, `f10_x01_pago_datos`, `f10_x01_regresiones`); las mismas pruebas pasan solas y en la suite limpia. Se anota como la sensibilidad a la carga ya conocida de esas suites, no como un defecto del producto.
- Comprobación técnica por un solo operador, en un emulador, con datos sintéticos. **No mide usabilidad**, no sustituye a X02 y sus tiempos no se comparan con los del POCO. Lo que sólo un teléfono puede mostrar (teclado del fabricante, cámara de la factura, red móvil, MIUI) queda sin comprobar en esta versión y se hará el día de X02 con la `.f10ux` del SHA integrado.
- La prueba «compra de un día anterior» no ejercita el cambio del día de pago cuando el día del mes es 1 (revisión, hallazgo 4).
