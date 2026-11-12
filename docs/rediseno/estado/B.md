# Estado de la sesión B

- Dueño del worktree: proyectoagro-a8 desde 2026-11-12 07:09
- Base incorporada: B1 (`0a2e321`, fusión `20ed54a`)
- Mapa de pantallas, rutas y accesos: `docs/rediseno/estado/B_MAPA.md`

## Entregas listas

| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
|---|---|---|---|---|---|
| 1 | el commit que añade esta fila (código: `950ce19`, `e79d422`, `032a100`) | Inicio `/` (1.2), Almacén `/inventario` (1.4), resumen de avisos del Almacén | ver «Entrega 1» | `docs/evidence/rediseno-movil/2026-11-12/sesion-b/entrega-1/` | ver «Entrega 1» |

### Entrega 1 — Inicio y Almacén

**Qué hace Inicio ahora**
- Cabecera oscura: «Agrocuentas», campaña activa (abre `/campanas`), engranaje (abre `/mas`). Cifra principal según el modo de uso: compartido → «Por cobrar» (familias + terceros, D-04) con cada grupo sólo si tiene importe, «A favor de …» aparte; propio → «Compras» (E-15: no hay cuentas por cobrar; «Por cobrar» y «Pagos recibidos» sólo si quedara importe). Cifras de compras, pagado a proveedores y pagos recibidos, rotuladas «Cifras de todas las campañas» (`dashboard()` no filtra por campaña).
- Accesos grandes (`ActionTile`): «Registrar compra», «Registrar aplicación» (con la guarda de campaña activa). Filas «Ver cuánto queda» y «Enviar al sindicato».
- «Para atender», sólo con lo que el teléfono calcula: lotes vencidos / que vencen hoy, lotes por vencer, productos bajos en el total y existencias bajas por responsable, compras confirmadas con saldo por pagar al proveedor (total > pagado, el mismo saldo que propone Compras), fecha del teléfono atrasada (CU-22 E2), errores de cálculo. Vacío: «Nada pendiente por ahora».
- «Principales saldos» (E-15, sin titular ni ADMIN) en compartido.
- Sesión: lo urgente (activar, recuperar, volver a autenticar, estado ilegible) arriba con borde de atención; lo de rutina («aún no fue verificado», «Verificar acceso en línea», «Comprobando…») al final en «Cuenta en línea». Mismas claves, textos y acciones.
- Actualizar: tirando hacia abajo y al volver de cualquier pantalla abierta desde Inicio.

**Qué hace Almacén ahora**
- Fichas: lotes vencidos, lotes que vencen hoy, productos bajos en el total (abren Avisos). «Todos los avisos» con el resto (por vencer, existencias bajas por responsable, lotes sin fecha). «Estimación del consumo».
- Cada producto: nombre, **Existencia** grande con su unidad (físico, `availableBase`), «Previsto en planes X · quedarán/faltarán Y» sólo si hay planes (`committedBase` / `projectedBase`, no es reserva), «Incluye X vencidos» si hay lotes vencidos, valor, etiquetas de avisos (lote vencido, vence hoy, vence en N días, queda poco / poco por responsable). Si la cifra no cabe al lado del nombre, baja debajo.
- Búsqueda con la lupa; «Ningún producto coincide con …» distinto de «No hay productos para mostrar.»; actualizar.

**Diferencias con la lámina (decisiones visuales, declaradas)**
| Lámina | App | Motivo |
|---|---|---|
| Inicio: botón «Registrar aplicación» blanco | `ActionTile` verde oscuro | `ActionTile` (B1) sólo tiene lima y verde oscuro. Ver solicitud 1. |
| Inicio: sin «Ver cuánto queda» / «Enviar al sindicato» | dos filas bajo los accesos grandes | Accesos del piloto X01 que se conservan. |
| Inicio: «Para atender» con «1 consumo por publicar al sindicato» | no se muestra | Inicio no tiene hoy ese dato sin otra consulta de sincronización (C/orquestador); sigue «Enviar al sindicato». |
| Inicio: «1 producto vencido y 2 vencen hoy» | «1 lote vencido · 2 lotes vencen hoy» | Los vencimientos cuentan lotes, no productos. |
| Inicio: sin estado de sesión | «Cuenta en línea» al final; urgentes arriba | Se conservan los avisos de sesión (F03, #83). |
| Inicio: sin «Principales saldos» | se conservan en compartido | E-15; la comprobación de E15-01 sigue en Inicio. |
| Inicio: cifras sin unidad | con «Bs» y «Cifras de todas las campañas» | La campaña de la cabecera podría hacer creer que filtra. |
| Almacén: «Vencido 1 / Vencen hoy 2 / Con poco 4» | «Lote vencido / Lotes vencen hoy / Productos bajos» | Aclara qué se cuenta; «bajos» = en el total. |
| Almacén: «Reservado 6 L · quedarán 4 L» | «Previsto en planes 6 L · quedarán 4 L» (o «faltarán») | No es una reserva real (COORDINACION). |
| Almacén: «Valor 3.565,00 Bs» total | valor por producto | No se suma un total nuevo. |
| Almacén: sólo lupa | lupa + actualizar | Se conserva actualizar. |

**Pruebas corridas** (una a la vez, `--concurrency=2`, todas en verde sobre `032a100`): `d04_imputacion_base`, `e15_consumo_propio_base`, `existing_session_screen`, `remote_session_screen`, `first_activation_screen`, `f04_activation_app_policy`, `f04_admin_owner_restore_ui`, `f10_compat_129_presentacion`, `ui_polish`, `f04_av_inventory_alerts_ui`, `set_state_contract`, `f12_est_07_estimation_ui`, `f10_x01_inicio_mas`, `hierarchical_navigation`, `oe3_fab_sincronizacion`, `navigation`, `uxj_a_navegacion`, `e2_joint_purchase_screens`, `e15_consumo_propio_ledger`. `flutter analyze` sin avisos en lo tocado. Lista completa repetida sobre `032a100` el 2026-11-12.

**Pruebas adaptadas** (cambia cómo se llega o un texto renombrado; no lo que se comprueba)
- `d04_imputacion_base` D04-04 y `e15_consumo_propio_base` E15-01: el importe de las familias y «A favor de familias» se leen por clave (`home-receivable-family`, `home-credit-family`) en vez de dentro de la tarjeta antigua.
- `remote_session_screen`: `ensureVisible` antes de tocar «Verificar acceso en línea» (ahora al final de Inicio).
- `f10_compat_129_presentacion` (Inicio): rótulos nuevos (Por cobrar, Compras, Pagado a proveedores, Pagos recibidos, familias/terceros, «Para atender», «Principales saldos»); el último bloque es un `AgroGroup` o el de la sesión; ya no hay «Ver todos». Además carga DM Sans y Bricolage (como ya cargaba Roboto): sin ellas mide con la fuente de cuadrados. **Afecta también a los casos de compra del mismo archivo** (miden con las fuentes reales); pasan.
- `f04_av_inventory_alerts_ui`: las cifras del resumen se comprueban en las fichas y el resumen restante; espera por la ficha (antes esperaba un texto que ahora también aparece en Inicio).
- `ui_polish` UIBUG-023: se comprueba en Almacén (Inicio ya no lista inventario). **«En pantalla ancha se conserva la tabla» pasa a «en pantalla ancha tampoco hay desplazamiento horizontal»**: Almacén usa filas en todos los anchos. Es un cambio de comportamiento en tableta: lo marco para el autor.
- `f10_x01_inicio_mas`: el título del Almacén es «Almacén».

**Componentes propios** (`widgets/rdm_b_ui.dart`, candidatos a `agro_ui.dart`): `BigFigure`, `splitBob`, `splitQuantity`, `ScreenTitleBar`, `LinkRow`, `IconCircle`, `DotTone`, `FilterPill`/`FilterPillBar`, `GroupLabel`, `RdmScrollPage` (construye todo el contenido y reserva el espacio del flotante, como `PageFrame`; siempre desplazable para «tirar para actualizar»).

**Datos y arnés:** `test/support_rdm/b_seed.dart` (nombres largos, decimales, L y KG, lotes vencidos/hoy/por vencer, pago parcial, deudas, plan, transferencia); `tool/rediseno/capturas_b_test.dart`.

## En curso

- Siguiente: Actividad (`/operaciones`), Compras y detalle de compra (2.8), Transferencias.

## Solicitudes al orquestador

1. `ActionTile`: ¿un tono `surface` (blanco, texto verde oscuro) para el segundo acceso de Inicio, como la lámina? Hoy uso `ActionTileTone.ink`. No bloquea.
2. Botón flotante del shell en Almacén: tapa la cifra de la tarjeta que pasa por detrás mientras se desplaza (al final no tapa nada: `ContentInsets` funciona). Si se quiere evitar, sería en `app_shell.dart` (p. ej. el «Registrar» extendido de la lámina, más bajo). No bloquea.

## Bloqueos y decisiones del autor

- UIBUG-023 en tableta: Almacén sin tabla ancha (antes Inicio la mostraba ≥ 560 dp). ¿Se acepta?
- «1 consumo por publicar al sindicato» en «Para atender»: no se muestra hasta que haya un dato barato y acordado con C/orquestador.

## Hallazgos fuera de alcance

- Ninguno nuevo.
