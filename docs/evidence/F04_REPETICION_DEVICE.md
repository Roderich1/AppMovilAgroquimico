# F04 — Repetición física acotada F04-REP-01 (HONOR JDY-LX3P, base `ad5b43d`)

- **Origen:** Live. **Fecha real:** 2026-10-18, 08:05–09:04 America/La_Paz (12:05–13:04Z). Sesión A de Claude Code, único operador del teléfono, por la delegación técnica de Roderich Rendón (`_briefs/PROMPT_A_REPETICION_F04_2026-10-18.md`). **Una sola ejecución** del protocolo R-01…R-12 preparado antes de medir (SHA-256 del protocolo local `7873519bfba73db125157c895209d182a737f76f4070aadeb1ae0674b4834430`).
- **Dispositivo:** HONOR JDY-LX3P, Android 16 / API 36, compilación `user`, zona America/La_Paz, idioma es-BO; batería 100 %, Wi‑Fi y datos móviles. El serial se conserva fuera del repositorio. El POCO y la app normal no se usaron.
- **Base Mobile:** `main` **`ad5b43d97b15e55c2b8a86bd7e0fcfa5602b68dd`** (merge de MOB #126; incluye #123, #124 y #125), árbol `82d7b88a5be0d815203ff000a67c2429c2a085de`, `lib` `b07ebbb05fe76efe2a4963bbd2f2dc68b100d7f8`. **CI integrada 39124111274 SUCCESS** (push a `main`: 1521 pasan, 4 omitidas, 78 en America/La_Paz, build de release).
- **APK aislada:** `com.comunidad.agro.agroquimicos.f04date` («Agrocuentas F04 fecha»), **debug**, `versionCode 1`, SHA-256 **`219d81801e9448d696c8efa857926b03bc57a7d5eff09e68095438be62625d0f`**, compilada con `tool/f03_res_01/build_isolated_apk.sh` desde un worktree limpio en `ad5b43d` (limpio también tras compilar). `applicationId` comprobado con `aapt dump badging` **antes** de instalar. Copia nueva: no existía `.f04date`. Se conservan `.f09voz` (con sus datos y su entorno detenido), la app normal (`lastUpdateTime` 2026-09-06 antes y después) y los volúmenes anteriores.
- **Backend:** `main` `6c54c00` sólo añade `docs/` sobre `f77c030`/`6e4a0e2`. **Backend ejecutado: `6e4a0e2ce8fb33ac3d6bf70e88cb6e60641456f0`** (dist compilado el 2026-10-17). Entorno nuevo `agro_a_f04date_pg` (55454; API 3128; observador 3127→3129; túnel HTTPS temporal no publicado), 11 migraciones, seed sintético, contraseñas rotadas. **Incidente conservado:** en el primer `up.sh` la API no arrancó («Invalid Sync v1 fingerprint keyring: key is not base64»); se reinició con un script local que genera la clave con Python y renueva la contraseña de PostgreSQL por socket, sin reseed. El ensayo sólo usó la API para la activación (observador: 6 peticiones, `auth` y `health`; ninguna de sync).
- **Trazabilidad:** RF-03, RF-07, RF-12, RF-17, RF-31; RN-15, RN-16; CU-06, CU-09, CU-19; DAT-02. Refs #28 (GATE-F04 **Pending**), #121, #122, #125 (cerradas por #124/#126).
- **Método:** acciones desde la interfaz por `adb` (`ANDROID_SERIAL` fijo; toques, `input text`, selector de fecha de Material tocando el día real); datos sintéticos; huella SHA-256 de **todas** las tablas antes y después de cada caso (`tool/f04_device/devdb.py <paquete> dump`, copia temporal por `run-as`, sólo lectura); conteos con `tool/f10_eval/eval_counts.sh`; mensajes leídos con `uiautomator dump` (sin capturas). **No se movió el reloj ni el calendario** para sustituir el selector; ninguna intervención SQL del arnés se cuenta como acción de pantalla (no hubo ninguna sobre la base del teléfono).

## 1. Datos sintéticos (todo desde la interfaz, inventario propio)

| Paso | Qué | Resultado |
|---|---|---|
| 1 | Activación con la cuenta sintética S, titular «Titular F04», modalidad propia | `install_origin = NEW_UNDER_POLICY`, `operation_mode = PERSONAL` |
| 2 | Catálogo: «Glifosato» (L), «Expansive» (KG), «Bellator» (L); «Agro Norte»; chaco «Sur» 2 ha | 3 productos, 1 proveedor, 1 chaco (20 000 m²) |
| 3 | «Campaña R1» desde el **08/09/2026** (selector: «Previous month» → 8) | ACTIVE |
| 4 | Compra de stock en R1 **fechada el 28/09/2026 con el selector**: Glifosato 10 L × 50 Bs y Expansive 4 KG × 30 Bs | `purchases` 1: `campaign_id = 1`, `purchase_date = 2026-09-28T04:00:00Z` (medianoche local), 620,00 Bs, 2 lotes |
| 5 | «Campaña R2» desde el **08/10/2026**; «Activar» → «Cerrar y activar» (inicio ya pasado: permitido) | R1 CLOSED con fin 07/10/2026 (fijado por el alta); R2 ACTIVE |
| 6 | «Campaña R3» planificada desde el **23/10/2026** | R3 PLANNED; el alta fija el fin previsto de R2 en 22/10/2026 |

Las campañas se teclearon como «Campana»; el teclado del teléfono corrigió a «Campaña».

## 2. Resultados

| ID | Qué se hizo | Qué se observó | Base del teléfono | Procedencia | Resultado |
|---|---|---|---|---|---|
| **R-01** | Compra en R2 con fecha **15/10/2026** elegida en el selector; dos productos (Glifosato 2 L × 50, Expansive 1 KG × 30) | «Agro Norte · Campaña R2 · 2 productos · Total 130,00 Bs · Confirmada» | `purchases` 2: `campaign_id = 2`, `purchase_date = 2026-10-15T04:00:00Z`; cambian sólo `purchases`, `purchase_items`, `purchase_allocations`, `inventory_lots`, `inventory_movements` (+1/+2/+2/+2/+2) | DEVICE | **PASS** |
| **R-02** | Aplicación en R2 con fecha **16/10/2026**, chaco «Sur», área **1 ha**, Glifosato 1 L y Expansive 1 KG | La pantalla mostró «Disponible 12 L · stock después 11 L» y «Disponible 5 KG · stock después 4 KG»; registrada | `applications` 1: `campaign_id = 2`, `applied_at = 2026-10-16T04:00:00Z`, `treated_area_m2 = 10000`; `application_items`: 1000 mL (FIFO 50,00 Bs) y 1000 g (30,00 Bs); cambian `applications`, `application_items`, `application_consumptions`, `inventory_movements` (+2), `account_transactions` | DEVICE | **PASS** (área exacta, multiproducto, FIFO) |
| **R-03** | Compra: con una línea en el borrador, abrir el selector de fecha y **cancelar**. Aplicación: abrir el selector y cancelar | Compra: la fila sigue «Fecha de la compra 18/10/2026 (hoy)» y la línea «Glifosato 1 L · 50,00 Bs» intacta; tablas idénticas. **Aplicación: el paso no llegó a ejecutarse** (el toque no abrió el selector; nada cambió) | Idénticas (`dump_R03_pre` = `dump_R03_post`) | DEVICE (compra) | **PASS (compra)**; aplicación **NOT_MEASURED** |
| **R-04** | Compra con fecha **03/10/2026** (dentro de R1, cerrada) | Aviso ≈ 2 s: «La fecha 03/10/2026 corresponde a la campaña cerrada «Campaña R1» (del 08/09/2026 al 07/10/2026). Una operación de un período cerrado requiere revisión y no se registra en otra campaña. No se registró nada.» | Idénticas | DEVICE | **PASS** (D-F04-C1: rechazo explícito, sin reapertura) |
| **R-05** | Compra con fecha **03/09/2026** (antes de toda campaña) | «La fecha 03/09/2026 no está dentro de ninguna campaña («Campaña R2» va del 08/10/2026 al 22/10/2026). Revise la fecha. No se registró nada.» | Idénticas | DEVICE | **PASS** |
| **R-06** | Fecha futura en el selector de compra | Con hoy 18/10: el 18 habilitado; **19/10 y 31/10 deshabilitados**; «Next month» deshabilitado | — | DEVICE (selector). El rechazo del repositorio ante una fecha futura (`CampaignDateProblem.future`) sigue siendo **HOST** (#124) | **PASS (interfaz)** |
| **R-07** | **Sin red** (modo avión + Wi‑Fi apagada; `Active default network: none`): compra fechada **17/10/2026**, dos productos (Glifosato 1 L × 50, Expansive 1 KG × 30); `force-stop` de la app y reapertura | Registrada sin red: `purchases` 3, `campaign_id = 2`, `purchase_date = 2026-10-17T04:00:00Z`, 80,00 Bs. Tras el cierre forzado: mismos conteos (compras 3, líneas 6, movimientos 8) y misma fila | Cambian sólo las tablas de compra/lotes/movimientos | DEVICE | **PASS** (multiproducto sin red; persistencia) |
| **R-08** | Compra de hoy confirmada con **dos toques seguidos** | Una sola compra | compras 4 → **5**; `purchases` 5 con la hora real (`2026-10-18T12:58:47Z`) | DEVICE | **PASS** |
| **R-09** | Compra fechada **08/10/2026** (primer día de R2, frontera inclusiva) | Registrada en R2 | `purchases` 4: `campaign_id = 2`, `purchase_date = 2026-10-08T04:00:00Z` | DEVICE | **PASS** |
| **R-10** | Con R2 activa, «Activar» la planificada R3 (inicio 23/10) desde Catálogos | Fila: «Campaña R3 Planificada · 23/10/2026 · Se podrá activar desde el 23/10/2026». Al tocar «Activar»: «“Campaña R3” empieza el 23/10/2026, después de hoy. Mientras “Campaña R2” esté activa no se puede activar cerrándola: el día de hoy quedaría dentro de una campaña cerrada. Se podrá activar desde el 23/10/2026; hasta entonces queda planificada.» **No aparece «Cerrar y activar»** | Idénticas (`dump_R10_pre` = `dump_R10_post`); R2 ACTIVE, R3 PLANNED | DEVICE | **PASS** (#125) |
| **R-11** | «Cerrar» R2, que tenía **fin previsto 22/10/2026** (fijado por el alta de R3) | Diálogo: «Fin previsto 22/10/2026. El fin efectivo que confirme abajo lo sustituye.» y «Termina el 18/10/2026 Cambiar»; en el selector del fin, 19/10 y 22/10 **deshabilitados**; «Cerrar definitivamente» | `campaigns` 2: CLOSED, `end_date = 2026-10-18T04:00:00Z` (hoy, no el 22/10). Cambia **sólo** `campaigns` | DEVICE (diálogo y cierre). El rechazo del repositorio a un fin futuro por llamada directa sigue siendo **HOST** (#124) | **PASS** (#122) |
| **R-12** | Activar R3 **sin otra activa** (excepción documentada: inicio futuro) y compra fechada **hoy** | R3 ACTIVE desde 23/10/2026; el formulario propone «Campaña R3»; al confirmar: «La fecha 18/10/2026 corresponde a la campaña cerrada «Campaña R2» (del 08/10/2026 al 18/10/2026). Una operación de un período cerrado requiere revisión y no se registra en otra campaña. No se registró nada.» | Idénticas (`dump_R12_pre` = `dump_R12_post`) | DEVICE | **PASS** (D-F04-C1) |

**Conteos finales:** compras 5, líneas 8, aplicaciones 1, líneas 2, movimientos 10, outbox 0, necesidades 0, `integrity_check = ok`; `campaigns` 3 (R1 y R2 CLOSED, R3 ACTIVE). Huella final de todas las tablas: TOTAL `9ac5ec005f81e06d…`. Volcados `dump_*.txt` en la carpeta local del ensayo (`agro_a_f04date`, fuera del repositorio).

## 3. Incidentes del arnés (no son defectos del producto)

- El botón «Confirmar compra» queda a veces en y≈1548, dentro de la franja del gesto de navegación del HONOR: un toque ahí mandó la app al fondo y los deslizamientos y dígitos siguientes fueron a la búsqueda del sistema (no a la app). Se corrigió desplazando el formulario para que el botón quede por encima de y=1480. Ningún dígito extraviado llegó a la base: los borradores contaminados se descartaron y los conteos se comprobaron antes de cada caso.
- Dos intentos de R-04/R-05 no mostraron mensaje porque el campo de precio del borrador había recibido dígitos extraviados (validación del formulario antes del repositorio); se corrigió el precio y se repitieron con el mensaje capturado. En todos los intentos las tablas quedaron idénticas.
- `logcat_scan.sh` sobre el uid de la copia (155 líneas): JWT 0, UUID 0, contraseñas 0, FATAL 0; las 2 coincidencias de «valores opacos» y 2 de «campos sensibles» son líneas del sistema (cabecera del búfer HKS; `InputMethodManager … showSoftInput … Password`, el tipo del campo de contraseña del teclado; `ImeTracker`), no datos de la app. Registro propio de la app: 53 líneas sin JWT, UUID ni campos sensibles.

## 4. Lo que se demuestra sólo en HOST (procedencia conservada)

- Rechazo del repositorio ante una fecha futura por llamada directa (`CampaignDateProblem.future`); en el teléfono el selector no ofrece el futuro (R-06).
- Rechazo de `closeCampaign` ante un fin efectivo futuro por llamada directa; en el teléfono el selector del fin se detiene en hoy (R-11).
- Representación de la hora en UTC y America/La_Paz y conservación del día al guardar y leer **en la misma zona** (#124); no se afirma nada sobre un cambio de zona del teléfono.
- Guardas de `activateCampaign` ante una pantalla desactualizada o llamada directa (#125); en el teléfono se midió el camino de la pantalla (R-10).
- Una necesidad declarada con una versión fechada después de hoy bloquea el cierre hasta ese día (`_lastOperationDay` lee también `declared_need_versions`); no se ejercitó en el teléfono (no hubo vínculo central ni necesidades).

## 5. Límites

- Un solo teléfono (HONOR JDY-LX3P), una copia aislada nueva, datos sintéticos, operación por `adb`. Sin voz (F09 en pausa).
- R-03 en el formulario de aplicación quedó **NOT_MEASURED**; en el de compra, medido.
- **D-F04-C1 sigue como límite de RF-03:** un período cerrado no se reabre ni recibe registros tardíos (R-04 y R-12 lo muestran como rechazo explícito).
- GATE-F04 (#28) sigue **Pending**; la propuesta de cierre académico está en [F04_GATE_DECISION_PROPUESTA.md](F04_GATE_DECISION_PROPUESTA.md). No se atribuye inspección personal a Roderich ni revisión al tutor.
- F09-ENS-01 y las mediciones anteriores conservan su dispositivo, fecha y SHA; esta repetición no las reatribuye.
