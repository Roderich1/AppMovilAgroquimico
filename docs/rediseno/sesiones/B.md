# Sesión B — Inicio, Actividad, Almacén, Personas

Leer antes `sesiones/COMUN.md` y `COORDINACION.md`.

- Láminas: Main (Inicio), Actividad, CompraDetalle, Almacen, Producto, Avisos, Estimacion, Personas, Persona, Cuenta, Pago, Transferencia, Propios, CostosChaco, Bitacora.
- Rutas: `/`, `/operaciones` (Actividad), `/compras`, `/compras/detalle/:id`, `/aplicaciones`/`/planificacion` sólo como entradas desde Actividad (sus listas son de A), `/inventario`, `/inventario/:id`, `/inventario/avisos`, `/inventario/estimacion`, `/personas`, `/personas/:id`, `/chacos/:id`, `/liquidacion`, `/transferencias`, `/transferencias/nueva`.
- La barra nueva y la hoja «Registrar» son del orquestador (base B1). Cuentas (`/liquidacion`) deja de ser pestaña: decide su acceso dentro de Personas (lámina Cuenta) sin quitar la ruta.
- «Reservado» → «Previsto en planes» (`committedBase`, `domain/read_models.dart`); «quedarán» es `projectedBase` y puede ser negativo. La estimación conserva el alcance de cada cifra (F12).
- Pago recibido usa `widgets/provider_payment_fields.dart` (del orquestador, ya rediseñado).
- Saldos, pagos, costos, inventario: sin cambiar cálculos. Inicio conserva las alertas de sesión, sincronización y recuperación.
