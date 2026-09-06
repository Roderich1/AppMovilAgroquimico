# EVO-017 — Compra mediante borrador de voz

## Estado

`APPROVED`. Implementar después de `EVO-009` y `EVO-010`, en una PR independiente.

## Objetivo

Preparar una compra multiproducto mediante voz continua, permitir completar o corregir todo el
borrador por voz o manualmente y registrar la compra sólo tras validación y confirmación
táctil.

## Datos del borrador

| Campo | Regla |
|---|---|
| Campaña | Proponer la única activa y mostrarla; no ocultar el default |
| Fecha | Proponer hoy y mostrarla |
| Proveedor | Puede decirse, seleccionarse o proponerse como nuevo |
| Producto | Resolver existente o marcar `nuevo propuesto` |
| Cantidad/unidad | Obligatoria por línea y convertida a unidad base |
| Moneda | Obligatoria; puede heredarse sólo si el usuario lo ve y acepta |
| Precio unitario | Obligatorio; entero exacto en moneda original |
| Tipo de cambio | Obligatorio para USD según reglas actuales |
| Propietario/asignación | Por línea o regla visible `todo para ...` |
| Total | Calculado, nunca dictado como fuente autoritativa |
| Factura/notas | Opcionales; no inventar datos ausentes |

Proveedor y asignación pueden ingresarse por voz o desde los controles manuales. Todos los
campos y líneas son editables sin abandonar la sesión.

## Ejemplo esperado

> “Quiero registrar compra: cincuenta litros de Bellator a ciento ochenta y seis bolivianos el
> litro, cincuenta litros de Germispa a ciento ochenta y uno, cincuenta litros de Germi cien a
> setenta y cinco y doce kilos de Expansive a ciento ochenta. El proveedor es Agro Norte y todo
> queda asignado al administrador.”

La UI muestra productos, cantidades, unidades, precio unitario, subtotal, proveedor, campaña,
fecha, moneda, asignación y total calculado. Cualquier faltante permanece destacado.

## Producto o proveedor inexistente

- Mostrar texto oído y propuesta normalizada.
- Buscar coincidencias y alias antes de proponer crear.
- El usuario elige un existente, edita o confirma `Crear nuevo`.
- Mostrar unidad base y nombre finales antes de confirmar.
- No crear silenciosamente por una coincidencia débil.

## Atomicidad

La creación aprobada de catálogos y `confirmPurchase()` forman una sola unidad atómica de
negocio. Si falla cualquier validación, inserción o asignación, no queda producto, proveedor,
compra, lote ni movimiento parcial. La implementación puede añadir un caso de uso
transaccional acotado que reutilice las validaciones actuales; no puede duplicar SQL o FIFO en
el subsistema de voz.

## Bloqueos de confirmación

- Sin campaña activa válida.
- Proveedor faltante/ambiguo/no confirmado como nuevo.
- Línea sin producto resuelto o creación confirmada.
- Cantidad, unidad, precio, moneda o tipo de cambio inválidos.
- Asignaciones faltantes o cuyo total no coincide con la cantidad.
- Nombre nuevo duplicado por normalización/alias.

## Requisitos

- `EVO-017-REQ-001`: permitir dictado continuo y adición de varias líneas.
- `EVO-017-REQ-002`: permitir proveedor y asignación por voz o manual.
- `EVO-017-REQ-003`: permitir editar cualquier campo o eliminar una línea antes de confirmar.
- `EVO-017-REQ-004`: calcular subtotales y total con políticas monetarias actuales.
- `EVO-017-REQ-005`: mostrar creación de catálogo como parte de la confirmación.
- `EVO-017-REQ-006`: registrar mediante una transacción atómica y sin efectos duplicados por
  doble toque/reintento.
- `EVO-017-REQ-007`: después de éxito, mostrar resumen e identificador; después de fallo,
  conservar el borrador editable sin escrituras parciales.

## Pruebas obligatorias

- Cuatro productos, unidades L/kg, alias y una asignación común.
- BOB y USD con tipo de cambio válido/inválido.
- Producto existente, ambiguo, nuevo, duplicado normalizado y corrección por voz.
- Proveedor hablado, seleccionado, nuevo y ambiguo.
- Asignación única, por línea, incompleta y suma incorrecta.
- Fallo inducido en cada paso transaccional: base sin cambios.
- Doble toque y reintento: una sola compra.
- Paridad con el formulario manual y con inventario/costos posteriores.

