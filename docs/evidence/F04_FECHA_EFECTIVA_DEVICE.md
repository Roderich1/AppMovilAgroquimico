# F04 — Campaña por fecha efectiva en el teléfono (casos E1–E4 del ensayo F09-ENS-01)

- **Origen:** Live. **Fecha real:** 2026-10-17 (noche, America/La_Paz; en UTC, 2026-10-18 entre las 00:40 y las 02:05). Sesión A de Claude Code, por la delegación técnica de Roderich Rendón (instrucción del 2026-10-17, «Continúa la preparación y ejecución del ensayo F04-C2/F09», puntos 5–7).
- **Dispositivo:** HONOR JDY-LX3P, Android 16 / API 36, compilación `user` (código de ensayo **F09-ENS-01**; nota de cambio de dispositivo: [F09_NOTA_CAMBIO_DISPOSITIVO_2026-10-17.md](F09_NOTA_CAMBIO_DISPOSITIVO_2026-10-17.md)). No es el POCO.
- **Base:** Mobile `main` `65f7cfc70d2dafc1c32da9a803fc55111c7a4c6e` (merge de MOB #116; CI 39081132396 SUCCESS, 1498 pasan, 4 omitidas, 44 de fechas en America/La_Paz, build de release). Copia aislada `com.comunidad.agro.agroquimicos.f09voz` («Agrocuentas F09 voz»), **debug**, SHA-256 `fe6878741e5321855c0a8eb397918bac408ce3e0165733d023309eef2db7ffb0`, instalada nueva (no había copias aisladas en este teléfono). Backend `6e4a0e2ce8fb33ac3d6bf70e88cb6e60641456f0` en el entorno aislado del ensayo. La app normal (`com.comunidad.agro.agroquimicos`) no se tocó: `firstInstallTime` y `lastUpdateTime` iguales antes y después (2026-09-06).
- **Trazabilidad:** RF-03, RF-07, RF-12, RN-15, RN-16; SRS §10.4. Refs #28 (GATE-F04 sigue **Pending**) y MOB #110 (criterio 5).
- **Método:** datos sintéticos creados desde la interfaz; huella SHA-256 de **todas** las tablas antes y después de cada caso con `tool/f04_device/devdb.py <paquete> dump` (copia temporal por `run-as`, sólo lectura; el teléfono se selecciona por `ANDROID_SERIAL`, nunca por el primer dispositivo); conteos con `tool/f10_eval/eval_counts.sh`.

## 1. Hallazgo de preparación: los formularios no admiten elegir la fecha

La preparación ([F09_VOZ_ENSAYO_PREPARACION.md](../evolution/features/F09_VOZ_ENSAYO_PREPARACION.md) §3) pedía compras «fechadas» en T−5, T−6 y T−31. **No es posible desde la aplicación:** el formulario de compra y el de aplicación fijan la fecha efectiva con la hora actual del teléfono (`purchaseDate: DateTime.now()`, `appliedAt: DateTime.now()`) y no tienen selector de fecha. No se falseó el reloj del teléfono ni se inyectó nada.

Los casos se reformulan con **la misma regla** (RN-15: la operación pertenece a la campaña cuyo período contiene su fecha efectiva) y la fecha de hoy, moviendo el **calendario** en vez de la fecha de la operación:

| Caso de la preparación | Cómo se ejecutó aquí |
|---|---|
| E1 (fecha dentro del período) | Igual: compra de hoy con la campaña 2 activa, que contiene hoy |
| E2 (frontera: primer día de la campaña 2) | **Coincide con E1**: la campaña 2 empieza hoy (17/10/2026), así que la compra de E1 cae en su primer día |
| E3 (último día de la campaña 1, cerrada) | **Variante:** una campaña **cerrada** cuyo período contiene hoy, con otra campaña activa que no lo contiene |
| E4 (fecha anterior a toda campaña) | **Variante:** hoy fuera de todo período, con la campaña activa terminada ayer por «Fijar fin previsto…» |

Lo que **no** se ejercitó en el teléfono: los **registros tardíos** de un período cerrado con una fecha pasada (RF-03). Es coherente con el acta de GATE-F04 (criterio 5: «registros tardíos de un período cerrado: no cumplido»). En HOST sí están probados (`test/f04_campaign_effective_date_test.dart`).

## 2. Datos sintéticos (orden real de creación)

1. Productos «Bellator», «Belator», «Glifosato» (L) y «Expansive» (KG); proveedor «Agro Norte»; chacos «Sur» (2 ha) y «Norte» (3 ha), del titular «Titular F09» en inventario propio. *(El nombre de las campañas se tecleó como «Campana»; el teclado del teléfono lo corrigió a «Campaña».)*
2. «Campaña ensayo 1», desde el 17/09/2026, activa; un plan pendiente en «Sur» (Glifosato, 1 ha × 2 L/ha).
3. **E4** (abajo), con la campaña 1 terminada el 16/10/2026.
4. «Campaña ensayo 2», desde el **17/10/2026 (hoy)**; «Cerrar y activar» cierra la 1 y activa la 2.
5. **E1**: compra de Glifosato (10 L × 50 Bs) en la campaña 2.
6. Planes de la campaña 2: dos en «Sur» (Glifosato 2 L; Bellator 1 L) y dos en «Norte» (Glifosato 1 L; Expansive 3 KG). El de Norte/Glifosato se aplicó desde Planificación («Aplicar este plan»): aplicación n.º 1, plan APPLIED, stock 10 → 9 L. Después, otras compras y aplicaciones del ensayo de F09 (ver `F09_VOZ_DEVICE.md`).
7. **E3** al final del turno, porque cierra la campaña 2.

## 3. Resultados

| ID | Preparación | Qué se hizo | Qué se observó | Huellas | Resultado |
|---|---|---|---|---|---|
| **E4** | Campaña 1 activa, del 17/09/2026 al 16/10/2026 («Fijar fin previsto…» en «Vincular con el sindicato», con el aviso del diálogo). Ninguna campaña contiene hoy | Compra manual de Glifosato (10 L × 50 Bs) y «Confirmar compra» | Rechazo bajo el total: «La fecha 17/10/2026 no está dentro de ninguna campaña («Campaña ensayo 1» va del 17/09/2026 al 16/10/2026). Re…» (el final quedó fuera de la captura). La compra no se registró | `dump_01_pre_E4` = `dump_02_post_E4`: **todas las tablas idénticas** (TOTAL `b075cad74c6e…`) | **PASS** |
| **E1 (= E2)** | Campaña 2 activa desde hoy; campaña 1 cerrada | Compra manual de Glifosato (10 L × 50 Bs) | «Agro Norte · Campaña ensayo 2 · 1 producto · Total 500,00 Bs · Confirmada». En la base: `purchases.campaign_id = 2`, `purchase_date = 2026-10-18T00:57:10Z` (17/10/2026 20:57 en La Paz, **primer día** de la campaña 2) | Cambian sólo `purchases`, `purchase_items`, `purchase_allocations`, `inventory_lots` e `inventory_movements` (+1 fila cada una) | **PASS** (E2 cubierto por coincidir con el día de frontera) |
| **E3** | Campaña 2 **cerrada** (del 17/10/2026 al 30/11/2026, contiene hoy); «Campaña ensayo 3» creada desde el 01/12/2026 y activa | Compra manual de Glifosato (1 L × 50 Bs) con la campaña 3 propuesta por el formulario; «Confirmar compra» dos veces | Mensaje transitorio (≈ 2–3 s): «La fecha 17/10/2026 corresponde a la campaña cerrada «Campaña ensayo 2» (del 17/10/2026 al 30/11/2026). Una operación de un período cerrado requiere revisión y no se registra en otra campaña. No se registró nada.» | `dump_12_pre_E3` = `dump_13_post_E3` (dos intentos): **idénticas** (TOTAL `67936ac60f26…`) | **PASS** |
| E2 (frontera) | — | Cubierto por E1 (la campaña 2 empieza hoy) | — | — | **PASS por E1**; no hay un caso independiente |

Conteos finales de la copia aislada (incluye lo registrado por el ensayo de F09): compras 4, líneas 4, aplicaciones 3, líneas 3, movimientos 7, outbox 2 (2 ACK), necesidades 1, `integrity_check = ok`.

## 4. Observaciones (no cambian el resultado; para revisión)

- **Cierre con fin ya fijado.** El diálogo «¿Cerrar…?» no muestra el selector de fin si la campaña ya tiene fin previsto, y `closeCampaign` no revalida ese fin: la campaña 2 quedó **cerrada con fin 30/11/2026, futuro**. La regla «el cierre no admite un fin futuro» (revisión de B sobre #110) sólo cubre el fin elegido en el diálogo. Para RN-16 la pertenencia sigue siendo correcta (E3 lo demuestra), pero conviene decidir si una campaña cerrada puede terminar en el futuro.
- El mensaje de E3 es un aviso transitorio; el de E4 queda fijo bajo el total. Son dos presentaciones distintas del mismo tipo de rechazo.
- El selector de fecha del alta de campaña y de «Fijar fin previsto…» aparece en inglés (localización por defecto de Material), aunque la app está en español.

## 5. Límites

- Un solo teléfono (HONOR JDY-LX3P) y una sola copia aislada; datos sintéticos.
- Sin registros fechados en el pasado desde la interfaz (§1); E2 no tiene caso propio.
- La ejecución fue por `adb` (toques e `input text`), con una persona junto al equipo sólo para la autorización USB; no hubo dictado.
- GATE-F04 (#28) sigue **Pending**: lo decide Roderich.
