# Bloque de experiencia C1: comprobación en el emulador (A1–A4)

- **Fecha real:** 2026-10-30, 11:25–12:20 (America/La_Paz).
- **Código comprobado:** Mobile `1027cd4b43162c214f9cff38eb9d59ca174f48b5` (rama `fix/ux-cuentas-compras-transferencias`, PR #162). APK profile x86_64 compilada desde ese commit con el origen HTTPS del túnel, SHA-256 `2f754cdf2ba570bb8190ef04f6732640f49e372ed8f4eb9b65b04ec982489cb9`.
- **Procedencia:** **[EMU]**, emulador Pixel_8 (Android 16 / API 36, 1080×2400, 420 dpi, 411 dp de ancho), un solo operador, datos sintéticos. **Sin teléfono físico y sin personas.** Lo que esta página afirma sobre lo guardado sale de copias de la base de la instalación leídas en el PC (oráculo de sólo lectura).
- **Autorización:** Roderich autorizó el 2026-10-30 un entorno sintético propio y un túnel con el procedimiento existente (`tool/f03_res_01/tunnel.sh`).
- **Capturas:** originales en `%TEMP%\agro_a_ux_env\capturas\` (fuera del repositorio); copias al 50 % en `docs/evidence/img/ux_c1/`. El SHA-256 de cada original está en §7.

## 1. Entorno propio, aislado de EXP y de los pilotos

| Pieza | Valor |
|---|---|
| Central | contenedor `agro_a_ux_pg` (`postgres:16-alpine`, volumen `agro_a_ux_pgdata`, `127.0.0.1:55490`, base `agro_ux`), 13 migraciones |
| API | `dist` de Backend `main` `9233acc` compilado en `_wt/A-EXP-BE/Back`, ejecutado como proceso propio en `127.0.0.1:3190` con esta base; secretos generados en memoria |
| Túnel | quick tunnel de cloudflared → observador `3191` → API `3190`; origen en `%TEMP%\agro_a_ux_env\origin`, no publicado |
| Tenant | `ux-sindicato` («Sindicato Demo UX-C1»): una Directiva y un agricultor `u1-ux@agrocuentas.example.test`, contraseñas inutilizables; campaña «Verano 2026» abierta; tres productos. Sin aportaciones ni sellado |
| Paquete | `com.comunidad.agro.agroquimicos.uxc1` («AC UX-C1»), instalado nuevo; **no** se tocó la app normal, la demo, `.f10eval` ni `.expa`–`.expe` |
| Activación | por la interfaz, con una contraseña de un solo uso tecleada y no mostrada; titular «Rosa Mamani Quispe de Condori», COMPARTIDA; PIN creado en la oferta de la activación (E-12) con un valor que vivió sólo en la memoria de `pin_holder.sh` y se descartó al terminar |
| Siembra local | `tool/ux/seed_ux_mobile.dart` (sin commitear) sobre la copia de la base recién activada, por `AgroRepository`: María Fernanda Quispe Mamani (familiar), Don Carlos Gutiérrez Villarroel (tercero, cobro por compra), proveedor «Comercializadora Agroquímica del Valle Alto S.R.L.», 3 compras (F-1001, F-1029 con una línea en dólares y pago parcial de 100 Bs, F-1040), un **adelanto histórico** de 20 Bs a María, 2 aplicaciones y 2 transferencias. Base sembrada: SHA-256 `29a35610…77cb` igual en el PC y en el emulador |
| Herramientas | `_wt/tools/ux/ux.sh`, `ux_device.sh`, `ux_activate.sh`, `ux_central_seed.cjs` (fuera de los repositorios) |

## 2. Incidente registrado

Al abrir la instalación, en el emulador estaba en primer plano el paquete `.expd` (entorno EXP de Roderich) con el diálogo del sistema «AC EXP-D isn't responding». Mi primer paso (abrir la app y tocar la pestaña Cuentas) cayó sobre **esa** app: sólo navegación, sin escribir datos. Lo hecho después:
- no se tocó «Close app» ni «Wait»; se pulsó Atrás del sistema y la app EXP-D siguió viva (`pidof` 3177);
- las dos capturas tomadas de EXP-D se borraron;
- `ux_device.sh` aborta cualquier acción de pantalla si `topResumedActivity` no es el paquete `.uxc1` (guarda añadida ese momento), y todas las comprobaciones de abajo se hicieron con esa guarda.

## 3. Resultados por comprobación

Cada fila contrasta lo mostrado con lo guardado (copias `t0` sembrada, `t1`/`t2` antes y después de consultar detalles, `t4`/`t5` finales).

| Comprobación pedida | Qué se hizo | Mostrado | Guardado | Resultado |
|---|---|---|---|---|
| **Pago único** | Menú ⋮ de Don Carlos y menú ⋮ del titular | «Ver detalle cronológico», «Exportar estado de cuenta», **«Registrar pago»**; en el titular «Ver movimientos propios», «Exportar movimientos propios», **«Registrar pago»**. Sin «Registrar adelanto» | — | OK (A1) — capturas 12 y 18 |
| **Importe inicialmente vacío** | Abrir «Registrar pago» de Don Carlos | Campo vacío, etiqueta «Importe del pago», sufijo «Bs», sin ejemplo; «Si no hay deuda, el pago queda a favor (como un adelanto).» | — | OK (A4) — captura 13 |
| **Validación numérica** | Teclear «1,500» y Registrar | «"1,500" es ambiguo: escriba 1.500 si son miles, o 1,5 si es decimal.», el diálogo sigue abierto | ninguna fila nueva | OK — captura 14 |
| **Pago parcial** | 30 Bs a Don Carlos (deuda 45) | «Pago de 30,00 Bs registrado a Don Carlos Gutiérrez Villarroel. Imputado: Verano 2026 30,00 Bs.»; la tarjeta pasa a «pagos aplicados 30,00 Bs» | `PAYMENT −3000`, `payment_allocations` 3000 al cargo 1 | OK — captura 15 |
| **Sobrante a favor** | 50 Bs a Don Carlos (quedaban 15) | «… Imputado: Verano 2026 15,00 Bs. Sin imputar: 35,00 Bs (queda a favor).»; tarjeta «0,00 Bs» pendiente, «A favor (no aplicado a deuda) 35,00 Bs (sin campaña)» | `PAYMENT −5000`, imputación 1500; el resto sin imputar (RN-39/RN-40) | OK — capturas 16 y 16b |
| **Lectura de adelantos históricos** | «Ver detalle cronológico» de María | Fila «Adelanto · 08/10/2026 · registrado en Verano 2026 · Sin imputación registrada: 20,00 Bs (queda a favor…)», −20,00 Bs; «A favor (no aplicado a deuda) 20,00 Bs» | `ADVANCE −2000` del 08/10 intacto | OK (A1) — captura 17. **Hallazgo F-1 (§5)** |
| **Detalle de compra confirmada** | Tocar la tarjeta F-1029 | Proveedor, «Confirmada», factura, fecha 12/10/2026, Verano 2026, Total 270,48 Bs, Pagado 100,00 Bs, origen del tipo de cambio, notas; Glifosato 4 L a 45,00 Bs por L, subtotal 180,00, «Para Rosa…: 3 L · se cobra al aplicar», «Para Don Carlos…: 1 L · cargo por compra 45,00 Bs»; Mancozeb 2 KG «6,50 US$ por KG · tipo de cambio 6,96 = 45,24 Bs por KG», subtotal 90,48; pago 13/10/2026 · Efectivo · pagó Rosa… · 100,00 Bs | `total_bob_minor 27048`, `provider_payments 10000 CASH`, asignaciones 3000/1000/2000, cargo 4500 | OK (A2) — capturas 21 y 22 |
| **Detalle sin pagos** | Tocar F-1001 | «Pagos al proveedor: No hay pagos registrados.» | sin filas | OK — captura 23 |
| **Sin escrituras al consultar** | Copia de la base antes y después de abrir el listado y dos detalles | — | SHA-256 de la base idéntico (`a79aa413…74da6`) y oráculo idéntico | OK (A2) |
| **Reversión de compra con motivo largo** | ⋮ de F-1040 → «Revertir compra» → motivo de 94 caracteres → PIN → «Autorizar» | Lista: F-1040 «Revertida». Detalle: «Revertida», «Pagado y no revertido: 0,00 Bs», «Revertida el: 30/10/2026», «Autorizada por el titular con el PIN de este teléfono · Factura emitida dos veces por el proveedor: la segunda entrega nunca lleg%C3%B3 a la comunidad» | `purchases.status REVERSED`, `reversal_audit` PURCHASE/3 con ese motivo y `LOCAL_PIN` | OK (A2) — capturas 24, 26 y 27. El «%C3%B3» es del arnés (§6) |
| **Transferencia antes y después de revertir** | Lista a 411 dp; ↩ de Rosa → Don Carlos (0,5 L), motivo largo, PIN, «Autorizar»; fila desplegada | Antes: dos filas «Entrega sin deuda» con ↩. Después: «Rosa Mamani Quispe de Condori → Don Carlos Gutiérrez Villarroel», **«Revertida»**, fecha y producto, «Entrega sin deuda», «Autorizada por el titular con el PIN de este teléfono · Se eligi%C3%B3 a la persona equivocada en la lista al registrar la entrega», todo en el cuerpo de la fila; a la derecha sólo la flecha de desplegar | `transfers.status REVERSED` (id 2), `reversal_audit` TRANSFER/2, el stock vuelve a Rosa | OK (A3) — capturas 30, 32 y 33 |
| **Ancho estrecho y fuente ampliada** | `wm size 945x2400` (360 dp) y `font_scale` 1,3 y 2,0 | Transferencias: la fila revertida se lee entera, sin recorte ni desborde, a ×1,3 y ×2,0. Cuentas: «Filtrar por campaña» ocupa el ancho sin desbordar (E-1); el diálogo de pago a ×1,3 y ×2,0 muestra el error completo y los botones, desplazándose (E-2) | — | OK — capturas 34–41 |
| **Teclado abierto** | `dumpsys input_method` → `mInputShown=true` al abrir el diálogo | El emulador tiene `hw.keyboard=yes`: Gboard muestra sólo su barra flotante, no las teclas. El desplazamiento con 300 dp de teclado lo cubre la prueba de widget | — | Parcial (§6) |
| **Modalidad propia y compartida** | Más › Modo de uso › «Cambiar a inventario propio», después de devolver al titular las existencias de María y de Don Carlos por `transferProductsFifo` (siembra `seed_ux_back.dart`) | «Todavía no se puede pasar a inventario propio. Resuélvalo en modo compartido: • Saldo de cuenta de Don Carlos Gutiérrez Villarroel, María Fernanda Quispe Mamani: registre el pago en Cuentas. No se borra ni se reasigna nada.» | saldos: Don Carlos 35 Bs a favor, María 2,50 Bs | **No ejercida en el emulador** (§6): la app bloquea el cambio mientras haya saldos. Es la regla vigente (#26), no un defecto. Lo propio de C1 en PROPIA queda en `personal_mode_flows_test.dart` y `e15_*` |
| **Nombres largos** | En todas las pantallas | Proveedor de 51 caracteres y personas de 29–31 caracteres: se parten en líneas en Transferencias, en el detalle y en los diálogos | — | OK. **Hallazgo F-2 (§5)** en la tarjeta de Cuentas |

## 4. Estado final guardado (copia `t5`, SHA-256 `ebd8eb22…2be17e`, igual a `t4`)

- `account_transactions`: 4 asientos sembrados + `PAYMENT −3000` y `PAYMENT −5000` a Don Carlos. Ningún `ADVANCE` nuevo. El `ADVANCE −2000` histórico intacto.
- `payment_allocations`: (pago 5 → cargo 1: 3000), (pago 6 → cargo 1: 1500).
- `purchases`: F-1001 y F-1029 `CONFIRMED`; F-1040 `REVERSED` (`reversed_at` 2026-10-30T15:56:59Z).
- `transfers`: 1 `CONFIRMED`; 2 `REVERSED`; 3 y 4 `CONFIRMED` (devoluciones de la preparación de modalidad, sin asientos: RN-35).
- `reversal_audit`: 2 filas, `LOCAL_PIN`, con los motivos tecleados.
- `sync_outbox`: 0 (nada pasó por el sindicato; por el túnel sólo fueron la activación y el health).
- `PRAGMA integrity_check`: ok.

## 5. Hallazgos conservados (no son de C1; no se corrigen aquí)

| Id | Dónde | Qué se vio | Captura |
|---|---|---|---|
| **F-1** | `account_statement_view.dart`, diálogo «Estado de cuenta» a 411 dp | Las filas de movimientos se parten **por carácter**: «Adelant / o», «08/10/20 / 26 ·». El `trailing` de 140 px deja al título ~100 px dentro del diálogo de 620 px de ancho máximo en un teléfono de 411 dp. Es la lectura del adelanto histórico, así que afecta a lo que A1 muestra | 17 |
| **F-2** | `settlements_screen.dart`, tarjeta de persona a 411 dp | «Don Carlos Gutiérrez Villarr…»: el nombre se recorta con puntos suspensivos (`maxLines: 2`) mientras el importe conserva su columna | 11, 16b |
| **F-3** | FAB «Nuevo» | A 360 dp tapa el ⋮ de la tarjeta que queda abajo y, a ×2,0, el texto de la fila revertida. Roderich ya decidió retirarlo en el rediseño | 35, 36 |
| **F-4** | Barra de pestañas a 360 dp y ×2,0 | Las etiquetas se reducen de tamaño para caber (`_fittedLabelStyle`), en contra de la regla «el texto no se encoge»; en el rediseño sólo la pestaña activa mostrará su etiqueta | 35 |

## 6. Limitaciones declaradas

- **Modalidad propia:** no se pudo entrar con este conjunto de datos; ver §3. No se forzó el cambio por la base.
- **Teclado:** con `hw.keyboard=yes` no aparecen las teclas en pantalla. Cambiarlo exige reiniciar el emulador, que comparte con los paquetes EXP de Roderich; no se hizo.
- **Tildes en los motivos:** `adb shell input text` no acepta caracteres no ASCII, así que los dos motivos quedaron con «%C3%B3» en lugar de «ó». Es un artefacto del arnés, no de la app; la pantalla muestra exactamente lo guardado.
- **Un solo operador y datos sintéticos;** ninguna persona participó. Nada de esto es evaluación humana.
- **Volcados de pantalla:** uiautomator tarda entre 10 y 60 s y a veces devuelve vacío tras una transición; los scripts reintentan. Por eso algunos pasos se repitieron (fases 2b, 3b, 4b, 4c y 7 en `%TEMP%\agro_a_ux_env\phase*.log`).
- **Procedimiento de cierre:** `ux.sh down` detuvo sólo la API, el observador, el túnel y el contenedor propios (datos conservados en `agro_a_ux_pgdata`); se detuvieron el `vite preview` propio y el `pin_holder`; `font_scale` volvió a 1,0 y `wm size` a su valor; el paquete `.uxc1` queda instalado con sus datos. No se cerró ningún proceso ajeno.

## 7. Capturas (SHA-256 de los originales, 1080×2290 u 945×2290 sin barra de estado)

| Archivo | SHA-256 (16) |
|---|---|
| 11_cuentas_411 | fb1e5d6eb899fb2c |
| 12_menu_carlos | 7e738886b703580c |
| 13_dialogo_vacio | 179f8e9460ce7e4e |
| 14_dialogo_ambiguo | ff246d792ecff843 |
| 15_pago_parcial_snackbar | 5ecaf11dc9a05c76 |
| 16_sobrante_a_favor_snackbar | ebebdcaf1229b1ca |
| 16b_cuentas_tras_pagos | cc0ad62514b818c3 |
| 17_detalle_maria_adelanto | 0c32ca17144e2704 |
| 18_menu_titular | 439e84456fd51f7d |
| 20_compras_lista | d2bf31bf39349c62 |
| 21_detalle_f1029_arriba | 2e06160ec631d490 |
| 22_detalle_f1029_abajo | 5c6d05d9598d31d9 |
| 23_detalle_f1001 | c918ab92064c5d4e |
| 24_motivo_reversion | 2b76e3c4b0c27866 |
| 26_compras_tras_reversion | 41b2ce01b5596026 |
| 27_detalle_f1040_revertida | 6cbef1c5d2206c11 |
| 30_transferencias_antes | 511fe2ad26d177a5 |
| 32_transferencias_411_despues | cdf8610e588201c9 |
| 33_transferencia_desplegada | 70207806b25650af |
| 34_transferencias_360_x13 | f39b00e6b6e7f0ac |
| 35_transferencias_360_x20 | 32d20ad71db2889d |
| 36_transferencias_360_x20_abajo | 1cfa296dd37dd8a9 |
| 37_cuentas_360_x13 | 005132af2e98da0a |
| 38_dialogo_pago_360_x13 | 9b7ee23af14b463f |
| 39_dialogo_pago_360_x13_error | 3431bd8884b4e5de |
| 40_cuentas_360_x20 | d6f1c5c752aa81e1 |
| 41_dialogo_pago_360_x20_error | 0cc925d719bd9c62 |
| 51_confirmar_propio | 92b6c22231a320cb |
