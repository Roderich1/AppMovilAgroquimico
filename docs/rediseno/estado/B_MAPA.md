# Sesión B — mapa de pantallas, rutas y accesos

Lo mantiene la sesión B en su rama. Rutas tal como están en `lib/app.dart` (base B1); B no añade ni cambia rutas. «Entra desde» lista los puntos de entrada que la pantalla necesita; si uno depende de un archivo del orquestador, va en «Solicitudes» de `B.md`.

## Estado por lámina

| Lámina | Ruta | Archivo | Tipo | Entra desde | Estado |
|---|---|---|---|---|---|
| 1.2 Inicio | `/` | `dashboard_screen.dart` | P | pestaña Inicio | **implementado + probado (entrega 1)** |
| 1.4 Almacén | `/inventario` | `inventory_screen.dart` | P | pestaña Almacén; Inicio › «Ver cuánto queda» | **implementado + probado (entrega 1)** |
| 4.2 Avisos | `/inventario/avisos` | `inventory_alerts_screen.dart` | P | Almacén (fichas y «Todos los avisos»); Inicio › «Para atender» | resumen con unidades (entrega 1); pantalla pendiente |
| 4.1 Producto | `/inventario/:id` | `inventory_detail_screen.dart` | P | Almacén (fila); Avisos (fila) | pendiente |
| 4.3 Estimación | `/inventario/estimacion` | `estimation_screen.dart` | P | Almacén › «Estimación del consumo» | pendiente |
| 1.3 Actividad | `/operaciones` | `operations_screen.dart` | P | pestaña Actividad | pendiente |
| — Compras (lista) | `/compras` | `purchases_screen.dart` | P | Actividad (filtro «Compras»); Inicio › «compras con saldo por pagar» | pendiente |
| 2.8 Compra · detalle | `/compras/detalle/:id` | `purchase_detail_screen.dart` | P | Compras (fila); Actividad (fila) | pendiente |
| — Aplicaciones / Planificación (listas) | `/aplicaciones`, `/planificacion` | (de A) | P | Actividad enlaza; **no** se duplican sus funciones | sólo enlace |
| — Transferencias (lista) | `/transferencias` | `transfers_screen.dart` | P | Actividad (filtro); sólo en compartido | pendiente |
| 5.4 Nueva transferencia | `/transferencias/nueva` | `transfer_form_screen.dart` | P | hoja «Registrar» (B1); Transferencias | pendiente |
| 1.5 Personas | `/personas` | `persons_screen.dart` | P | pestaña Personas | pendiente |
| 5.1 Persona | `/personas/:id` | `person_detail_screen.dart` | P | Personas; Inicio › «Principales saldos» | pendiente |
| 5.2 Cuenta | `/liquidacion` | `settlements_screen.dart` + `account_statement_view.dart` | P | **Personas** (acceso «Cuentas», B1 la quitó de la barra) | pendiente |
| 5.3 Registrar pago | (hoja) | `settlements_screen.dart` | H | Personas, Persona, Cuenta, hoja «Registrar» | pendiente |
| 5.5 Consumo y costos propios | (en Cuentas/Persona) | `settlements_screen.dart` | P/E | Personas › titular «Ver movimientos propios» | pendiente |
| 5.6 Costos por chaco | `/chacos/:id` y reporte | `farm_logbook_screen.dart` / Cuentas | P | Personas › «Costos por chaco» | pendiente (sin exportación propia) |
| 5.7 Bitácora del chaco | `/chacos/:id` | `farm_logbook_screen.dart` | P | Persona › chaco | pendiente |

Tipos: P = pantalla (ruta), H = hoja, E = estado de otra lámina.

## Accesos que B1 trasladó y dónde quedan

| Acceso | Antes | Ahora |
|---|---|---|
| Ajustes y datos (`/mas`) | Actividad › Más | Inicio › engranaje de la cabecera (`home-settings`) |
| Campañas (`/campanas`) | Actividad › Campañas | Inicio › campaña activa de la cabecera (`home-active-campaign`) |
| Cuentas (`/liquidacion`) | pestaña Cuentas | Personas (pendiente, siguiente entrega de Personas) |
| Inventario en Inicio, aplicaciones recientes | Inicio | Almacén y Actividad |

## Lo que la lámina no muestra y se conserva

- Inicio: avisos de sesión y acceso (activar, recuperar, volver a autenticar arriba; estado de rutina y «Verificar acceso en línea» al final, «Cuenta en línea»), elección de titular, aviso de convocatoria nueva, «Ver cuánto queda», «Enviar al sindicato», «Principales saldos» (compartido), «A favor de familias/terceros», guarda «Activa una campaña…» al registrar aplicación.
- Almacén: actualizar, búsqueda (lupa), estimación del consumo, resumen de avisos restantes (por vencer, por responsable, sin fecha), valor por producto, lo vencido incluido en la existencia.

## Exportación

La sesión B no implementa exportaciones. Los botones de exportar de las láminas Actividad y Costos por chaco quedan fuera hasta la integración de la sesión F (Excel) por el orquestador.
