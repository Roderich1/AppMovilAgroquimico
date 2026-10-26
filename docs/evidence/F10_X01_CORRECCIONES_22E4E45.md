# F10 usabilidad — correcciones tras el piloto X01 (regla del pagador, productos de la aplicación, Inicio) y comprobación en el teléfono

- **Fecha real:** 2026-10-26, de 03:52Z a 05:45Z (UTC), que en America/La_Paz es la noche del 2026-10-25 al 2026-10-26.
- **Ejecutó:** la sesión A de Claude Code, por la delegación de Roderich Rendón del 2026-10-26 («Autorizo implementar las correcciones y simplificaciones…»).
- **Qué es:** la evidencia técnica de las correcciones que produjo el piloto X01 (`docs/evidence/F10_PILOTO_X01_2026-10-25.md`, repositorio Backend) y de su comprobación con datos sintéticos en un paquete aislado del POCO. **No es una sesión de usabilidad:** no hay participantes, tiempos, SEQ ni SUS, y estos recorridos técnicos no sustituyen al piloto siguiente (X02).
- **Rama:** `fix/x01-pagador-productos-inicio`, sobre `main` `f9a4b76` (`lib/` = `1d77c14`, la base del piloto). Commits: `22e4e45` (correcciones y pruebas) y el siguiente (textos de la pantalla del titular, visto en el teléfono). La APK de comprobación se compiló desde `22e4e45`; el segundo commit sólo cambia tres textos de `owner_setup_screen.dart`.
- **Issues:** MOB #37 (UX-01), Roderich1/Agro_Sindicato_Backend-Web#47 (UX-02). GATE-F10 (Roderich1/Agro_Sindicato_Backend-Web#49) sigue **Pending**. Sin cambios en el Project.
- **Backend y esquema:** sin cambios. No hace falta ninguna migración: la regla del pagador se aplica con las tablas existentes (`owner_bindings`, `provider_payments`).

## 1. Lo que se corrige y por qué

| Id (registro X01) | Qué pasaba en `1d77c14` | Qué hace la rama |
|---|---|---|
| **X01-D1** | En Nueva aplicación, elegir un producto lo agregaba al instante y, con una sola opción restante, `AdaptiveEntityPicker` la autoseleccionaba: entraban dos productos al elegir uno | Recorrido explícito «Agregar producto → elegir → cantidad → Agregar a la mezcla» en una hoja; sólo esa confirmación agrega **una** tarjeta; abrir, cancelar o reconstruir no agrega nada; el selector de la hoja abre con `autoSelectSingle: false`; sin duplicados (el selector sólo ofrece lo que falta); tarjetas con producto, cantidad y unidad, **Editar** y **Quitar**; dosis, teórico y costo en el «Detalle» |
| **X01-D2 / X01-R1** | El pagador se filtraba por rol ADMIN; en un hogar sin ADMIN el selector no tenía opciones y la compra no podía quedar pagada | Regla aprobada: paga el **titular vigente** (`owner_bindings`, `ended_at IS NULL`), en las dos modalidades. `canActAs(providerPayer) = isOwner`; `addProviderPayment` lo exige; `confirmPurchase(paidInFullByOwner:)` escribe compra y pago juntos. Nueva compra pregunta «¿Pagaste toda esta compra?» sin respuesta por defecto y muestra «Pago registrado por: [titular]» sin editar. Nadie cambia de rol; los pagos históricos no se reasignan; los pagos de cuenta y adelantos no cambian |
| **X01-D3** | Compra y pago en dos transacciones: un fallo del pago dejaba la compra guardada y reintentar la duplicaba | Una sola transacción; el pagador se comprueba antes de escribir |
| **X01-U1** | Acciones principales detrás de Operaciones → lista → «Nueva …»; Operaciones con 9 tarjetas | Inicio con cuatro accesos (Registrar compra, Registrar aplicación, Ver cuánto queda, Enviar al sindicato) sin «Nuevo» flotante; Operaciones con Compras, Aplicaciones, Planificación, Transferencias (compartida) y **Más**; `/mas` con Reportes, Administrar datos, Modo de uso, Vínculos con el sindicato, Respaldo en la nube, Copias de seguridad, PIN del titular, Operaciones tardías y Registrar por voz (F09 en pausa, al final). Los avisos de sesión y acceso siguen en Inicio |
| **X01-U2** | Compra en una pantalla larga | Dos pasos: proveedor y productos (fecha de hoy, cambiable); revisión y pago (factura, notas y campaña plegadas). En compartida el reparto sigue siendo explícito, por línea |
| **X01-U3** | Aplicación con todo a la vez | Tres pasos: persona y chaco (en propia, «Aplica el titular» sin elegirlo); productos y cantidades; resumen y confirmación |
| **X01-U4** | FIFO en subtítulos y en el selector; mensajes genéricos | Sin FIFO en las instrucciones; «Compra guardada.», «Aplicación guardada.»; rechazo de existencias: «No alcanza el Bellator: hay 1,5 L y escribiste 5 L. Baja la cantidad o registra primero la compra.» |

**Lo que no cambia:** reglas de stock, FIFO, costos, campañas, operaciones tardías (RF-03: la captura tardía sigue sin crear pagos), actor de reversión (RF-13), PIN, aislamiento del titular, sincronización, respaldos, voz (F09: sin cambios en reconocimiento ni intérprete; su acceso queda en Más) y la precisión de área y confirmación única de las aplicaciones vinculadas a un plan (`plan_application_area_precision_test` adaptado al recorrido nuevo y en verde).

## 2. Regresión demostrada sobre la base del piloto

`test/f10_x01_regresiones_test.dart` (dos pruebas de interfaz con el formulario y el selector reales, app completa, base en archivo, hogar compartido con titular y familiar sin ADMIN) ejecutado sobre `f9a4b76` el 2026-10-26 04:07Z, **antes** de cambiar `lib/`:

```
X01-A · aplicación: elegir un producto agrega exactamente ese producto, no el que queda
  Expected: exactly one matching candidate   Actual: Found 0 widgets with text "Productos (1)"
X01-B · compra en compartida sin ADMIN: se puede registrar el pago, y lo paga el titular vigente
  Expected: no matching candidates           Actual: Found 1 widget with text "Pagador"
00:06 +0 -2: Some tests failed.
```

Con la corrección las dos pasan (misma intención; el recorrido de la interfaz se adaptó al nuevo).

## 3. Pruebas automatizadas

| Qué | Resultado |
|---|---|
| `dart format --set-exit-if-changed lib test` y `flutter analyze` | Sin cambios pendientes; **No issues found** |
| Nuevas: `f10_x01_regresiones_test` (2), `f10_x01_pagador_titular_test` (regla pura, repositorio, atomicidad, pagos históricos: 9), `f10_x01_aplicacion_productos_test` (uno, dos y varios productos; cancelar, quitar, volver a agregar, reconstruir; editar; atrás conserva; guardar; existencia insuficiente; propia: 6), `f10_x01_inicio_mas_test` (shell, cuatro accesos sin FAB, «Compra guardada.», Operaciones y Más: 4) | Todas en verde |
| Suites existentes adaptadas al recorrido nuevo y a la regla del pagador | `personal_mode_flows`, `f04_admin_owner_restore_ui`, `f04_effective_date_form`, `plan_application_area_precision`, `f10_legibility_97`, `f10_compat_129_presentacion`, `ui_polish`, `navigation`, `hierarchical_navigation`, `reports_screen`, `operation_mode_onboarding`, `voice_wiring`, `purchases_access`, `existing_session_screen` (guardián determinista), `f04_historical_admin_owner` (los pagos históricos de las fixtures se insertan tal cual, sin la validación nueva), `repository`, `e2e_scenario`, `reports`, `f04_bug_02`, `support/ui_audit_seed` (el ADMIN de la fixture pasa a ser el titular) |
| Suite completa (`flutter test`) sobre `22e4e45` | **1 831 pasan, 3 omitidas, 0 fallan** en la segunda corrida completa (01:33). En la primera corrida completa falló una vez `f04_effective_date_form_test` («registrarla para revisión desde la lista», aplicación) y en una corrida parcial la variante de compra, siempre por el tiempo del aviso bajo carga; aisladas pasaron 2/2 cada vez. Se sustituyó el `settle` fijo por una espera del aviso. La corrida completa sobre el HEAD final se registra en §7 |

## 4. Comprobación en el teléfono

| Elemento | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G `22101320G`, serial `cc14247a`, Android 12, MIUI V14.0.7.0 |
| Paquete | `com.comunidad.agro.agroquimicos.x01fix` («Agrocuentas X01 fix»), **profile**, aislado: ni la app normal ni la `.f10ux` del piloto se tocaron. **Desinstalado al terminar**; la APK se conserva en `%TEMP%\agro_a_x01fix\`. Quedaron 26 paquetes `com.comunidad.agro*`, como antes |
| APK | `tool/f10_eval/build_profile_apk.sh` sobre el worktree limpio en `22e4e45`, con el túnel del día. SHA-256 **`34e06302e9c2a3521c71043831f365f7ec6d71d4c24ac7bcf86bce9cc32eee5b`**, igual al `base.apk` instalado. targetSdk 36 |
| Central | Contenedor nuevo `agro_a_x01fix_pg` (postgres:16-alpine, 127.0.0.1:55479), sólo las 13 migraciones, API del `dist` de Backend `4bcb1ea` en el 3162 con `NODE_ENV=development`, `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic`, `COLLECTIVE_SEALING=disabled`, `SYNC_V1_PRODUCTION_ADMISSION=enabled`; observador `tool/f03_res_01/observer.cjs` en el 3163 y quick tunnel de `cloudflared` 2026.10.0. Al terminar se pararon API, túnel y observador; el contenedor se conserva, como los anteriores |
| Siembra Central | `Back/scripts/f10-dsux-central-seed.cjs` de BE `main` `1cc439b`, destino `movil`, etiqueta `X01FIX`, **S = 2026-10-26**, cuentas sintéticas `T01` y `T02` del tenant `f10ux-movil-x01fix`; referencias SHA-256 `be018d79…`, `same_tenant_as_accounts: true` |
| Siembra Mobile | `tool/f10_ux/seed_dsux_mobile.dart` de la rama (sin cambios desde `1d77c14`), `F10_UX_SESSION_DATE=2026-10-26`. T02 en **COMPARTIDA** (base `0c4555fe…`, igual en PC y teléfono) y T01 en **PROPIA** (base `e46adcc9…`, igual). Journal residual de 512 B borrado antes de devolver la base, como en el preflight |
| Contraseñas | De un solo uso, asignadas por `stdin` (bcrypt) y tecleadas por el arnés; no se mostraron ni escribieron |
| Red | Encendida. El observador registró **sólo las dos activaciones** (login, clients, session/client, me) y ningún `push` |

### 4.1 Recorridos

Capturas en `%TEMP%\agro_a_x01fix\capturas\` (SHA-256, 16 hex). «UI» = textos leídos con `uiautomator`; «base» = consulta de sólo lectura sobre una copia de la base del teléfono.

| # | Modalidad · fuente | Recorrido | Resultado | Captura |
|---|---|---|---|---|
| 1 | Compartida · 100 % | Inicio tras la siembra | **PASS.** Cuatro accesos (Registrar compra, Registrar aplicación, Ver cuánto queda, Enviar al sindicato), sin «Nuevo» flotante; «Campaña activa: Verano Demo», «Compras 405,00 Bs» | `8ac7948158fac056` |
| 2 | Compartida | Registrar compra → paso 1: Proveedor Demo, Glifosato Demo 2 L a 45 Bs/L, reparto «¿Para quién es?» Titular 2 L | **PASS.** Tarjeta «Glifosato Demo 2 L · 90,00 Bs · Asignado» | `4e1c2b344f5b02d6` |
| 3 | Compartida | Continuar → paso 2 → **Atrás** → paso 1 conserva producto, cantidad, precio y reparto → Continuar | **PASS** (regreso sin perder el borrador) | — |
| 4 | Compartida | Paso 2: «¿Pagaste toda esta compra?» sin respuesta («Elige una opción para poder confirmar.») → «Sí, pagué todo» → «Pago registrado por: Titular» → Confirmar compra | **PASS.** Vuelve a Inicio («Compras 495,00 Bs»). Base: compra 3 de 9 000 (90,00 Bs); `provider_payments` (3, pagador **1 = Titular = `owner_bindings`**, 9 000, misma fecha que la compra); asignación al Titular | `9023918a15ac964f` |
| 5 | Compartida | Registrar compra: Bellator 0,5 L a 180 Bs/L, reparto «Familiar Demo» 0,5 L → Continuar → «No, todavía no» («La compra queda sin pago. Puedes anotarlo después en Operaciones, Compras.») → Confirmar | **PASS.** Aviso «Compra guardada.» en Inicio. Base: compra 4 de 9 000, asignación a la persona 2 (Familiar Demo, 500 mL), **ningún pago nuevo** (sigue 1) | `6c60d9cafec1c3e6` |
| 6 | Compartida | Registrar aplicación → paso 1: Persona Titular, Chaco Norte (área 1 ha precargada) → Continuar → «Productos (0)» | **PASS** | — |
| 7 | Compartida | «Agregar producto» → hoja → **Cancelar** sin elegir; otra vez → cantidad 1 sin producto → «Elige el producto.»; elegir Glifosato Demo («Hay 7 L.») → «Agregar a la mezcla» | **PASS.** «Productos (1)», tarjeta «Glifosato Demo · 1 L · Hay 7 L · quedarán 6 L», Editar y Quitar. **Bellator no entró** | `fb6cf0d9a36ab390` |
| 8 | Compartida | «Agregar producto» → el selector ofrece **sólo Bellator (1/1)** → Cancelar | **PASS.** Sigue «Productos (1)» | — |
| 9 | Compartida | Agregar Bellator 0,2 L → **Editar** → 0,3 L → «Guardar cambios» → **Quitar** Bellator → volver a agregar 0,2 L | **PASS.** «Productos (2)» con 1 L y 0,2 L; tras editar 0,3 L; tras quitar «Productos (1)» sin Bellator; tras volver a agregar «Productos (2)» | `01a7d7f3ab5aa9de` |
| 10 | Compartida | **Atrás** al paso 1 (Titular y Norte conservados) → Continuar → «Productos (2)» conservados → Continuar → resumen («Persona: Titular · Chaco: Norte · 1 ha tratadas · Glifosato Demo · 1 L · Bellator · 0,2 L») → Confirmar aplicación | **PASS.** Aviso «Aplicación guardada.» en Inicio. Base: 1 aplicación (Titular, Norte, 10 000 m²) con **exactamente** las dos líneas (1 000 y 200 mL); existencias del Titular 6 000 / 800 mL, de Familiar Demo 500 mL de Bellator | `5f40a34b201de653` |
| 11 | Compartida | Registrar aplicación → Titular, Norte → Agregar producto → Bellator → **5** | **PASS.** La hoja avisa: «Hay 0,8 L.» y «Con esa cantidad la aplicación no se podrá guardar: hay 0,8 L.»; se puede agregar | `5252a0bf10d632c8` |
| 12 | Compartida | Tarjeta «5 L · Hay 0,8 L: faltan 4,2 L» (en rojo) → Continuar → Confirmar aplicación | **PASS.** Rechazo: «No alcanza el Bellator: hay 0,8 L y escribiste 5 L. Baja la cantidad o registra primero la compra.»; el borrador sigue en pantalla; base: sigue 1 aplicación y 2 líneas. Se descartó el borrador con «¿Descartar cambios?» | `cad0f5f5b1bafbc3` |
| 13 | Compartida | «Ver cuánto queda» | **PASS.** Inventario: «Bellator Físico 1,3 L», «Glifosato Demo Físico 6 L» | `99cff30a97fffe65` |
| 14 | Compartida | «Enviar al sindicato» | **PASS.** Abre «Sincronización» con «Sincronizar ahora» y «Lo que se envía al sindicato: sólo totales propios.»; **ninguna petición** en el observador: tocar el acceso no publica nada | `fbefd695d1bd1cbf` |
| 15 | Compartida | Operaciones | **PASS.** Compras, Aplicaciones, Planificación, Transferencias y Más, sin FIFO en los subtítulos | `72acd6459b0afb11` |
| 16 | Compartida | Más | **PASS.** «Lo que se usa de vez en cuando.»: Reportes, Administrar datos, Modo de uso («Ahora: inventario compartido»), Vínculos con el sindicato, Respaldo en la nube, Copias de seguridad en este teléfono (y, por debajo, PIN del titular, Operaciones tardías y Registrar por voz, visibles al desplazar); «Volver» a Operaciones | `939f0947c4e48af2` |
| 17 | Compartida · **130 %** | Inicio con `font_scale` 1,3 | **PASS.** Los cuatro accesos pasan a **una columna**; ninguna palabra partida | `463b91d16c26cd8b` |
| 18 | Compartida · 130 % | Nueva compra, paso 1 | **PASS.** Cabecera, proveedor, «Productos (1)» y «Agregar producto» enteros | `cfafafdf18d88085` |
| 19 | Compartida · 130 % | Nueva aplicación: hoja «Agregar producto» y paso 2 con una tarjeta | **PASS.** Hoja con producto, «Hay 7 L.», cantidad y los dos botones; tarjeta «1 L · Hay 6 L · quedarán 5 L» con Editar y Quitar | `9efd0b5b55da9063`, `6e87eaed1076d8f8` |
| 20 | Compartida · 130 % | Más | **PASS** | `c43a30791e6830a2` |
| 21 | **Propia** · 130 % | `pm clear`, activación con T01, titular «Titular», **Propio**; siembra PROPIA. Registrar compra → paso 1: Glifosato Demo 1 L a 45 | **PASS.** «Para el titular: Titular», sin reparto que elegir | `a97ec055c3c64235` |
| 22 | Propia · 130 % | Paso 2 → «Sí, pagué todo» → «Pago registrado por: Titular» → Confirmar | **PASS.** «Compra guardada.». Base: compra 3 de 4 500; pago (3, pagador 1 = Titular = `owner_bindings`, 4 500); asignación al Titular. **El titular es FAMILY, no ADMIN:** la regla antigua no habría dejado pagar | `4d6f79a5f28abe2b` |
| 23 | Propia · 130 % | Registrar aplicación → «Aplica el titular: Titular» (sin selector de persona) → Chaco Norte → Continuar → Agregar Glifosato Demo 1 L → Continuar → resumen → Confirmar | **PASS.** «Aplicación guardada.». Base: 1 aplicación del Titular en Norte con 1 línea de 1 000 mL | `4aa519e0593a1f22`, `f488ac7cc01dadcb` |
| 24 | Ambas | `adb logcat` desde el arranque, al 100 % y al 130 % | **0** mensajes `overflowed by` / `RenderFlex` | — |

**Oráculo final de cada instalación** (`tool/f10_ux/oracle_dsux_mobile.dart`, sólo lectura):
- **T02 (compartida)**, base `98e25081…`: Glifosato Demo 5 000 + 2 000 − 1 000 = 6 000 = 6 000; Bellator 1 000 + 500 − 200 = 1 300 = 1 300 (Titular 800, Familiar Demo 500); `consistent: true`; sin necesidades; cola vacía.
- **T01 (propia)**, base `c28238af…`: Glifosato Demo 5 000 + 1 000 − 1 000 = 5 000 = 5 000; Bellator 1 000; `consistent: true`.

**Incidencias del operador** (no del producto): la `.x01fix` se instaló al tercer intento de `adb install`, porque el diálogo «Instalar vía USB» de MIUI exige tocar «Instalar» en menos de 10 s (igual que en sesiones anteriores). Dos veces el arnés tecleó un dígito en el campo de precio en vez de en el de reparto (el campo quedaba bajo el teclado): se corrigió a mano antes de continuar y la validación del paso 1 **rechazó** continuar mientras el reparto estaba pendiente («Pendiente 0,5 L»), como debe. Una vez la app se cerró al pulsar Atrás estando en Inicio (comportamiento previsto desde UIBUG-004B) y se reabrió.

## 5. Revisión cruzada

Una sesión independiente de Claude Code (sin acceso a este texto) leyó el diff completo `git diff f9a4b76..HEAD` con las reglas aprobadas como pauta, ejecutó `flutter analyze` y 49 pruebas (las nuevas más `plan_application_area_precision`, `f04_effective_date_form` y `personal_mode_flows`), y no modificó nada. **Comprobó como correctas** las tres reglas (pagador = titular vigente leído en la misma transacción; única entrada de productos por la hoja, sin autoselección ni duplicados; Inicio/Operaciones/Más con todos los accesos) y las guardas (campaña y fecha efectiva, RF-03 sin pagos en la captura ni en la confirmación tardía, RF-13, PIN, modo propio, `modeChangedSince`, voz sin pagos). Sin hallazgos de nulos, `setState` tras `dispose` ni `PopScope`.

**Hallazgos y qué se hizo (commit siguiente a `b6f5974`):**

| # | Gravedad | Hallazgo | Corrección |
|---|---|---|---|
| 1 | media | `purchases_screen.dart` (pago posterior): comentario y mensaje decían que pagan los ADMIN («Registra una persona administradora…»); con la regla nueva la lista vacía sólo significa que no hay titular vinculado | Mensaje: «No hay un titular vinculado: el pago al proveedor lo registra el titular.» |
| 2 | baja | El diálogo de pago posterior pedía elegir «Pagador» en compartida, con una sola opción | `fixedPayer` en las dos modalidades: «Paga el titular: …», sin selector. Prueba (c) en `f10_x01_pago_revision_test` |
| 3 | media | Con «Sí, pagué todo» y fecha de campaña cerrada, la nota de la captura tardía («El pago al proveedor se registra después de confirmarla») podía leerse como automática; ni la captura ni la confirmación tardía crean pagos | Nota en activa: «El pago al proveedor no se guarda con la revisión. Si el titular la confirma, anótalo después en Operaciones, Compras, «Registrar pago».» Prueba (b): borrador tardío guardado y `provider_payments` vacío |
| 4 | baja (preexistente) | Tras guardar, `saving` bajaba a `false` un fotograma antes del `pop`: un segundo toque en ese fotograma podía escribir otra compra o aplicación | `saving` se queda en `true` hasta cerrar, en los dos formularios |
| 5 | baja (preexistente) | Aplicación vinculada a un plan: en compartida se podía cambiar la persona (vaciaba las cantidades previstas) o el chaco (sobrescribía el área exacta) y la aplicación seguía con `planId` | Con plan, persona y chaco se muestran fijos («Persona del plan», «Chaco del plan»); `plan_application_area_precision_test` adaptado |
| 6 | baja | Pruebas: faltaban (a) confirmar sin responder el pago, (b) el caso 3 y (c) el pago posterior; el comentario de `f10_x01_regresiones_test` afirmaba un fallo no reproducible desde el commit | `f10_x01_pago_revision_test` (a, b, c); comentario reescrito: la versión que falló sobre `f9a4b76` recorría la interfaz anterior y su salida está en §2 |
| 7 | baja | Esta evidencia estaba sin commitear al revisar | Se confirma junto con las correcciones |

Las categorías «reconstruir la pantalla» del punto 6 se dejan como están: la protección real es `autoSelectSingle: false`, comprobada por el texto «Seleccionar» en la hoja.

## 6. Límites

- Comprobación técnica por un solo operador, en un solo teléfono, con datos sintéticos. **No mide usabilidad** ni sustituye al piloto X02.
- La APK de comprobación es de `22e4e45`; el HEAD de la rama añade un commit que sólo cambia tres textos de la pantalla del titular (`git diff --stat 22e4e45 HEAD -- lib`: un archivo). La `.f10ux` de X02 se compila desde la versión integrada, el día de la sesión, con el túnel del día.
- No se repitieron las series de rendimiento (R1–R6) ni la compatibilidad; los cambios son de presentación y de regla, sin cambios de esquema.
- La hoja «Agregar producto» admite una cantidad mayor que la existencia (con aviso) para que el rechazo ocurra **al guardar**, como prevé la pista de T6; es una decisión, no un descuido.
- La prueba `f04_effective_date_form_test` depende de tiempos reales de E/S y falló una vez bajo la carga de la suite completa antes de endurecerse; se deja anotado.

## 7. Cierre

- **Suite completa sobre `b6f5974`** (`flutter test`): **1 832 pasan, 3 omitidas, 0 fallan** («All other tests passed!», 01:24). `flutter analyze`: No issues found.
- **Suite completa sobre `34afe20`** (las correcciones de la revisión, §5; `flutter test` terminado el 2026-10-26 05:52Z): **1 835 pasan, 3 omitidas, 0 fallan** («All other tests passed!», 01:22). `flutter analyze`: No issues found.
- **Revisión cruzada:** §5.
- **CI del PR:** se registra literalmente en el PR, con el nombre y la conclusión de cada check.
