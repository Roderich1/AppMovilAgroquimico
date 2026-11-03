# GATE-F04 (#28) — Acta y propuesta de cierre académico (Evidence Partial, RF-03 parcial)

## Identificación y autoridad

- **Proyecto:** Agrocuentas, Proyecto de Grado 2026. **Fase:** F04, dominio y modalidades (propio/compartido). **Gate:** MOB [#28](https://github.com/Roderich1/AppMovilAgroquimico/issues/28).
- **Fecha de preparación:** 2026-10-18 (America/La_Paz). La prepara la sesión A de Claude Code, por la delegación técnica de Roderich Rendón del 2026-10-18 («Si los casos físicos previstos pasan, prepara el acta y la propuesta de cierre académico de GATE-F04 con Evidence Partial y el límite RF-03 explícito. Entrega PR documental, HEAD, revisión y CI aplicable para su integración y decisión»), **después** de la repetición física F04-REP-01.
- **Lo que este documento es:** una **propuesta** de decisión técnica, pendiente de revisión (sesiones B y C) y de la decisión de Roderich. **Lo que no es:** una inspección personal de Roderich, una revisión del tutor (GOV-01, BE #105) ni una validación institucional. Hasta la decisión, `Gate = Pending` en GitHub y en el Project. No se propone Passed por el número de pruebas.
- **Antecedentes que se conservan tal cual:** [gate-f04-modo-propio-compartido.md](gate-f04-modo-propio-compartido.md) (acta del 2026-10-17 sobre `cf3d510`), `F04_CAMPANA_FECHA_EFECTIVA.md` (#110), `F04_C2_PERIODO_LOCAL_CENTRAL.md` (#116), `F04_FECHA_EFECTIVA_DEVICE.md` y `F04_C2_DEVICE.md` (F09-ENS-01, HONOR, `65f7cfc`), `F04_FECHA_EFECTIVA_Y_CIERRE.md` (#124), `F04_ACTIVACION_ANTICIPADA.md` (#125) y [F04_REPETICION_DEVICE.md](F04_REPETICION_DEVICE.md) (F04-REP-01, HONOR, `ad5b43d`). Cada una conserva su SHA, fecha y dispositivo; nada se reatribuye.

## Decisión propuesta

- `GATE_F04 = PASSED`, `SCOPE = ACADEMIC`, `EVIDENCE = PARTIAL`.
- **Límite explícito de RF-03 (D-F04-C1):** una operación cuya fecha efectiva cae en un período **cerrado** se **rechaza** de forma explícita y no se registra en otra campaña; no existe circuito de revisión, reapertura ni reasignación de períodos cerrados, y los registros tardíos de un período cerrado no se admiten. RF-03 queda **parcial** en ese punto. Esta propuesta no lo resuelve ni lo oculta.
- **Base de referencia:** Mobile `main` `ad5b43d97b15e55c2b8a86bd7e0fcfa5602b68dd` (CI integrada 39124111274 SUCCESS); dispositivo HONOR JDY-LX3P (Android 16 / API 36). Las mediciones de `65f7cfc` (F09-ENS-01) y de `cf3d510` (acta del 17) conservan sus bases.

## Criterios de #28 y evidencia

| # | Criterio | Evidencia | Procedencia |
|---|---|---|---|
| 1 | Propio → compartido conserva compras, aplicaciones, movimientos, necesidades y campañas con el titular | `f04_operation_mode_test` (ida y vuelta con tablas idénticas); DEVICE P8 de `F03_F04_DEVICE_2026-10-17.md` (POCO, `1902e6e`) | HOST + DEVICE (2026-10-17) |
| 2 | Compartido → propio con existencias o movimientos de otros: bloqueo o resolución, sin borrar ni reasignar | `f04_operation_mode_test`; DEVICE P9 (POCO) | HOST + DEVICE (2026-10-17) |
| 3 | Propio: sin responsables ni transferencias; mismos resultados del dominio único | `personal_mode_flows_test`; DEVICE P3–P7 (POCO) y toda la repetición F04-REP-01 en modalidad propia | HOST + DEVICE |
| 4 | Compartido: transferencia compensa salida y entrada sin consumo ni saldo negativo | Repositorio y `f04_bug_01`/`f04_bug_02`; DEVICE P9 | HOST + DEVICE (2026-10-17) |
| 5 | En cualquier modo y sin conexión: compra o aplicación multiproducto confirmada persiste tras cerrar y reabrir, **con la campaña de la fecha efectiva** | **Campaña por fecha efectiva** (#110, HOST). DEVICE F09-ENS-01 (`65f7cfc`): E1/E2, E3 y E4 como variantes con la fecha de hoy. **DEVICE F04-REP-01 (`ad5b43d`): R-01 (compra multiproducto fechada el 15/10 en la activa), R-02 (aplicación fechada el 16/10, área exacta 10 000 m², FIFO), R-07 (compra multiproducto **sin red**, persiste tras `force-stop`), R-09 (frontera inclusiva 08/10), R-04 y R-12 (período cerrado: rechazo explícito, tablas idénticas), R-05 (ninguna campaña), R-08 (doble toque: una sola compra), R-11 (cierre con fin efectivo confirmado aunque exista fin previsto), R-10 (no se cierra la actual al activar una sucesora futura, #125)** | HOST + DEVICE (2026-10-17 y 2026-10-18) |
| 6 | `flutter test` en verde sin pruebas debilitadas | CI integrada 39124111274 sobre `ad5b43d`: SUCCESS, 1521 pasan, 4 omitidas, 78 regionales en America/La_Paz, build de release. Las regresiones nuevas de #124 y #125 fallan sobre el código anterior (registrado en `F04_FECHA_EFECTIVA_Y_CIERRE.md` §3 y `F04_ACTIVACION_ANTICIPADA.md` §3) y las mutaciones de la revisión de A (abajo) las matan | CI + HOST |

> **Corrección del 2026-11-03:** la cita «DEVICE P9» del criterio 4 no corresponde a una
> transferencia, y el límite D-F04-C1 de RF-03 está superado. La tabla se conserva tal cual; la
> corrección está en el [Anexo del 2026-11-03](#anexo-del-2026-11-03-cita-de-p9-transferencia-y-d-f04-c1).

**Mutaciones de la revisión de A (HOST, worktrees propios; no versionadas en los PR, se registran aquí):**
- Sobre `9f3e3af` (código de MOB #124): sin el rechazo de fecha futura en `_ensureEffectiveDateInCampaign` falla «una fecha futura se rechaza en compra y aplicación sin escribir»; sin el tope «fin ≤ hoy» en `closeCampaign` fallan «el cierre no admite un fin futuro», «un fin previsto futuro no cierra la campaña en el futuro…» y «la excepción de la campaña activa que no empezó se conserva…». Base intacta: analyze limpio, format 0, 61 pasan / 1 omitida en los cuatro archivos.
- Sobre `53ddaea` (código de MOB #126): con la guarda de #125 desactivada (`if (false && active.isNotEmpty)`) fallan «antes del inicio: se rechaza con y sin closeCurrent…», «mañana a medianoche local también es futuro…» y la de pantalla «una sucesora futura no se activa desde Catálogos». Base intacta: 52 pasan en cinco archivos.

**Decisiones delegadas que se ratifican:** D-F04-C1 (período cerrado se rechaza; opción B) y D-F04-C2 (período local contenido en el central; retención y conciliación, #116, comprobado en el teléfono con G1–G3 el 2026-10-17). La política de fechas y cierre del `CONTINUACION_F09_ENS_01_TRIAGE_2026-10-17.md` §3 está construida (#124) y la activación anticipada bloqueada (#125), ambas verificadas en el HONOR.

## Límites que se conservan (por eso `Evidence = Partial`)

- **RF-03 parcial** por D-F04-C1 (arriba).
- **Sólo en HOST (#124/#125):** rechazo del repositorio ante fecha futura y ante fin efectivo futuro por llamada directa (en el teléfono el selector no los ofrece); representación de la hora en UTC y La Paz probada guardando y leyendo en la **misma** zona (no se afirma nada sobre un cambio de zona del teléfono); guardas de `activateCampaign` por llamada directa, con y sin `closeCurrent` (el camino que seguiría una pantalla desactualizada; **la pantalla desactualizada no se simuló**); el cierre rechaza un fin anterior al día de la última versión de una necesidad declarada (probado con fechas pasadas y tablas iguales). Que una versión fechada **después de hoy** impida cerrar «hasta ese día» se **deduce** de esa guarda más el tope «fin ≤ hoy», probados por separado: no hay prueba que lo ejecute ni que pruebe la retirada de la necesidad (`_lastOperationDay` no filtra por estado); `declared_need_versions` es historial inmutable por los disparadores `trg_declared_need_versions_no_delete` y `trg_declared_need_versions_no_update` (`app_database.dart`), además de que el código sólo lo inserta (`declared_need_store.dart`) y lo lee en el historial.
- **Sólo en HOST (#116, D-F04-C2), límites declarados por C y conservados:** la carrera entre la selección y el marcado del envío se cierra en la transacción de marcado (un cambio de período entre el marcado y el POST no se ve); el ACK perdido y las respuestas inválidas o de otra operación se prueban con el Central falso; una intención con consulta 404 queda retenida sin plazo; un CANCEL detrás de una sustitución nunca recibida espera; si el período vuelve a caber dentro de `heldQueryInterval`, el envío espera a `next_attempt_at`. En el teléfono (G1–G3, `F04_C2_DEVICE.md`, `65f7cfc`) la incompatibilidad se provocó por el fin **local** sin red; la variante «fin central anterior + Actualizar» **no se ejecutó** en el teléfono.
- **DEVICE acotado:** dos teléfonos en total (POCO X5 Pro 5G el 2026-10-17 para P1–P13 sobre `1902e6e`; HONOR JDY-LX3P el 17 sobre `65f7cfc` y el 18 sobre `ad5b43d`), una copia aislada por ensayo, datos sintéticos, operación por `adb`. **La modalidad compartida (criterios 1, 2 y 4) no se repitió en DEVICE sobre `ad5b43d`:** su DEVICE sigue siendo el POCO del 17 sobre `1902e6e`; sobre `ad5b43d` es sólo CI/HOST. R-03 en el formulario de aplicación quedó `NOT_MEASURED`.
- **Observaciones de presentación:** selectores de fecha en inglés; «Cerrar y activar» sigue existiendo para sucesoras ya iniciadas (correcto); el mensaje de rechazo por fecha es un aviso transitorio en algunos formularios.
- **F09 en pausa** (#119/#120): nada de voz se evalúa aquí.
- Las issues REC reconstruidas de F04 (MOB #39, #43, #46–#48, #50–#52, #57) siguen abiertas con `Evidence = Partial`: no representan funcionalidades ausentes; su cierre por alcance es una decisión administrativa aparte.

## Revisiones

- **Preparación:** sesión A, 2026-10-18, a partir de `F04_REPETICION_DEVICE.md` y de las evidencias enlazadas.
- **Revisión técnica de B y C:** pendiente sobre este PR.
- **Decisión de Roderich Rendón:** pendiente. Sólo él cambia `Gate` en #28 y en el Project.
- **Revisión del tutor:** se registra aparte en GOV-01.

## Anexo del 2026-11-03: cita de P9, transferencia y D-F04-C1

Redactado el 2026-11-03 (UTC) en el cierre de OE3, sobre Mobile `main` `5b5b318`. **No cambia el texto de arriba**, que se conserva como se escribió el 2026-10-18, ni decide nada: `Gate` lo decide sólo Roderich Rendón.

**1. Criterio 4 (transferencia): la cita «DEVICE P9» es incorrecta.**
- P9 de `F03_F04_DEVICE_2026-10-17.md` (línea 44; POCO, `1902e6e`) es, en compartido, una **compra asignada** a «Hermana DEV» y el **bloqueo del cambio a inventario propio**. No ejecuta ninguna transferencia. En esa sesión no hay ningún paso con una transferencia.
- Lo que sí acredita la transferencia:
  - **HOST:** `f04_bug_01_reverse_transfer_test`, `f04_bug_02_reverse_purchase_after_transfer_test`, `v5_domain_test` («transferencia multiproducto…», conserva el total) y `f10_d07_transferencia_sin_deuda_test` (RN-35, sin cargo).
  - **EMULADOR, en otros SHA:**
    - `F10_BLOQUE2_EMULADOR_2026-10-28.md`, fila D-07: APK-1 de Mobile `e5ba07c`, Pixel_8, API 36. Transferencia de 1 L, Titular → Familiar Demo, por la interfaz: «Entrega sin deuda» y `account_transactions` 0 → 0;
    - `F10_UX_C1_EMULADOR_2026-10-30.md`: Mobile `1027cd4`. Las transferencias se **sembraron** con `AgroRepository`; por la interfaz se ejercitó su **reversión** con PIN (`transfers.status REVERSED` y el stock vuelve).
  - **DEVICE: ninguno.** En `F04_AV_AVISOS_INVENTARIO_DEVICE_2026-11-01.md` (POCO, `ce3b788`) la base tenía un lote derivado de una transferencia, pero esa transferencia la creó la siembra sintética en el PC: no se ejecutó en el teléfono.
- En consecuencia, la procedencia del criterio 4 es **HOST + EMULADOR**, no «HOST + DEVICE (2026-10-17)». Lo mismo vale para la frase de «Límites», «su DEVICE sigue siendo el POCO del 17», en lo que toca al criterio 4. Los criterios 1 y 2 sí tienen DEVICE (P8 y P9).
- La transferencia en DEVICE sigue pendiente, salvo que el autor la exceptúe.

**2. D-F04-C1 está superado (el límite de RF-03 del §«Decisión propuesta» ya no describe el código).**
- **Construido:** las operaciones tardías RF-03. Una compra o aplicación con fecha de una campaña cerrada se guarda como borrador para revisión y el titular la confirma con su PIN en esa campaña cerrada, sin reabrirla y sin publicar al sindicato.
  - Contrato: `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md`.
  - **HOST:** `F03_F04_RECUPERAR_ACCESO_RF13_RF03_HOST.md`, 2026-10-23, sobre `04162ff`: `f04_rf03_late_operations_test` (11) y `f04_rf03_late_screen_test` (2).
- **DEVICE:** `F01_F08_DEVICE_FINAL_2026-10-24.md`, casos B1–B3, más B4 y B5. POCO X5 Pro 5G, Mobile `1d77c14`, 2026-10-24 local (2026-10-25 UTC), sin red:
  - compra `FIN-003` del 15/09/2026 en la campaña cerrada «Pasada ensayo», guardada para revisión;
  - aviso corregido;
  - confirmada con PIN;
  - exactamente +1 compra y ninguna publicación.
- **Lo que no cambia:** no se reabren campañas ni se reasignan operaciones a otra campaña. Las fechas de un período cerrado se siguen rechazando en la ruta normal; lo nuevo es la oferta de registrarlas para revisión.
- Los rechazos R-04 y R-12 de `F04_REPETICION_DEVICE.md` (`ad5b43d`) se midieron **antes** de las operaciones tardías y conservan su fecha y su SHA.

**3. «Versión de necesidad posterior a hoy» (§«Límites», punto de #124/#125).**
- Dejó de ser una deducción. Desde el 2026-11-03 la ejecuta una prueba HOST: `test/oe3_f04_close_01_necesidad_futura_test.dart`. Cubre una necesidad declarada para un día futuro, la retirada y una versión `CANCELLED` sola.
- Detalle en `docs/evidence/OE3_HOST_CIERRE_2026-11-03.md`. Sigue siendo sólo HOST.
