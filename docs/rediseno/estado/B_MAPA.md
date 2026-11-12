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
| 1.3 Actividad | `/operaciones` | `operations_screen.dart` | P | pestaña Actividad | **implementado + probado (entrega 2)** |
| — Compras (lista) | `/compras` | `purchases_screen.dart` | P | Actividad › Compras › «Lista de compras»; Inicio › «compras con saldo por pagar» | pendiente |
| 2.8 Compra · detalle | `/compras/detalle/:id` | `purchase_detail_screen.dart` | P | Compras (fila); Actividad (fila) | pendiente |
| — Aplicaciones / Planificación (listas) | `/aplicaciones`, `/planificacion` | (de A) | P | Actividad › filtro › «Lista de …»; «Aplicar» de un plan abre `/aplicaciones/nueva?planId=` | sólo enlace |
| — Transferencias (lista) | `/transferencias` | `transfers_screen.dart` | P | Actividad › Transferencias › «Lista de transferencias»; fila de transferencia; sólo en compartido | pendiente |
| 5.4 Nueva transferencia | `/transferencias/nueva` | `transfer_form_screen.dart` | P | hoja «Registrar» (B1); Transferencias | pendiente |
| 1.5–5.7 Personas, Persona, Cuenta, Pago, Propios, Costos, Bitácora | `/personas`, `/personas/:id`, `/liquidacion`, `/chacos/:id` | — | — | — | **cedidas a la sesión A** (2026-11-12); Inicio enlaza `/personas/:id` |

Tipos: P = pantalla (ruta), H = hoja, E = estado de otra lámina.

## Accesos que B1 trasladó y dónde quedan

| Acceso | Antes | Ahora |
|---|---|---|
| Ajustes y datos (`/mas`) | Actividad › Más | Inicio › engranaje de la cabecera (`home-settings`) |
| Campañas (`/campanas`) | Actividad › Campañas | Inicio › campaña activa de la cabecera (`home-active-campaign`) |
| Cuentas (`/liquidacion`) | pestaña Cuentas | Personas (pendiente, siguiente entrega de Personas) |
| Inventario en Inicio, aplicaciones recientes | Inicio | Almacén y Actividad |
| Reportes (`/reportes`) | Actividad › tarjeta | Actividad › botón de la cabecera (`activity-reports`) |
| Compras, Aplicaciones, Planificación, Transferencias (listas) | Actividad › tarjetas | Actividad › filtro › «Lista de …» (`activity-open-*`) |

## Lo que la lámina no muestra y se conserva

- Inicio: avisos de sesión y acceso (activar, recuperar, volver a autenticar arriba; estado de rutina y «Verificar acceso en línea» al final, «Cuenta en línea»), elección de titular, aviso de convocatoria nueva, «Ver cuánto queda», «Enviar al sindicato», «Principales saldos» (compartido), «A favor de familias/terceros», guarda «Activa una campaña…» al registrar aplicación.
- Almacén: actualizar, búsqueda (lupa), estimación del consumo, resumen de avisos restantes (por vencer, por responsable, sin fecha), valor por producto, lo vencido incluido en la existencia.

## Exportación

La sesión B no implementa exportaciones. Los botones de exportar de las láminas Actividad y Costos por chaco quedan fuera hasta la integración de la sesión F (Excel) por el orquestador.
