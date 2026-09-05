# PROMPT MAESTRO PARA CODEX — AGROQUÍMICOS V2

Implementa la aplicación Flutter descrita en `AGROQUIMICOS_IMPLEMENTATION_SPEC_V2.md`.

La especificación V2 reemplaza a cualquier versión anterior cuando exista contradicción.

# Stack obligatorio

- Flutter
- Dart
- SQLite
- offline-first
- sin backend en V1
- Drift recomendado
- Riverpod recomendado
- go_router recomendado

# Contexto de negocio crítico

Un administrador compra y paga agroquímicos para varios familiares y ocasionalmente conocidos.

Los familiares tienen chacos propios y manejan su propio dinero.

El administrador suele pagar todo al proveedor y después recuperar el dinero según el uso real de agroquímicos de cada familiar, normalmente al final de campaña, aunque pueden existir pagos parciales durante la campaña.

Los conocidos pueden participar en compras conjuntas y pagar antes o después.

# Multi-moneda obligatorio

Algunos productos se compran en BOB y otros se cotizan en USD.

Si un producto está en USD, el proveedor acuerda un tipo de cambio concreto para esa compra.

Ejemplo obligatorio:

- 420 L
- $16/L
- FX 7 Bs/USD
- total = Bs 47.040

Nunca hardcodees el FX.

Conserva:

- moneda original;
- precio original;
- tasa histórica;
- precio convertido;
- subtotal BOB.

Todos los reportes consolidados usan BOB.

# Dinero

No usar double.

- dinero en centavos;
- FX como integer escalado a 1e6;
- cantidades en unidades base enteras cuando sea viable.

# Finanzas: separar dos mundos

NO mezclar:

1. pagos al proveedor;
2. pagos/reembolsos de familiares y terceros.

Crear `provider_payments`.

Crear ledger interno `account_transactions`.

# Política de cobro

Agregar `settlementPolicy` en persona:

- BY_ACTUAL_USAGE
- BY_PURCHASE_ALLOCATION
- MANUAL

Defaults:

- FAMILY -> BY_ACTUAL_USAGE
- THIRD_PARTY -> BY_PURCHASE_ALLOCATION

Para familia:

asignar stock NO crea deuda.

Confirmar consumo/aplicación SÍ genera deuda por el costo real consumido.

Para tercero:

la asignación puede generar el cargo directamente.

# Costeo obligatorio

Implementar lotes (`inventory_lots`) asociados a `purchase_items`.

Cada lote conserva:

- producto;
- propietario;
- cantidad;
- costo unitario BOB;
- precio original;
- moneda;
- FX histórico.

El inventario continúa basado en `inventory_movements`.

Para aplicaciones usar FIFO.

Crear `application_consumptions` para registrar qué lotes se consumieron y qué costo BOB produjeron.

# Ejemplo financiero familiar

Un lote cuesta Bs 112/L.

Carlos aplica 28 L.

Cargo:

28 × 112 = Bs 3.136.

Crear:

`USAGE_CHARGE +313600`

Si Carlos paga Bs 1.000:

`PAYMENT -100000`

Saldo:

Bs 2.136.

# Adelanto de tercero

Si un tercero pagó antes:

crear `ADVANCE` negativo.

Cuando se confirme su allocation:

crear `PURCHASE_ALLOCATION_CHARGE`.

El saldo resultante puede quedar en 0.

# Operaciones atómicas

Usar transacciones SQLite para:

- confirmar compra;
- generar allocations;
- crear lots;
- registrar PURCHASE_IN;
- generar cargos;
- confirmar aplicación;
- seleccionar FIFO;
- crear application_consumptions;
- registrar APPLICATION_OUT;
- generar USAGE_CHARGE;
- registrar transferencias;
- revertir operaciones.

# Fases de implementación

## Fase 0
Proyecto, dependencias, router, theme, database, migrations.

## Fase 1
Personas, settlementPolicy, chacos, campañas, productos, proveedores.

## Fase 2
Planificación de aplicaciones y cálculo de necesidades.

## Fase 3
Compras multi-moneda.

Implementar primero y probar exhaustivamente:

- BOB;
- USD;
- FX histórico;
- totales BOB.

## Fase 4
Purchase allocations + inventory lots + inventory movements.

## Fase 5
Aplicaciones + FIFO + application_consumptions.

## Fase 6
Account ledger + pagos + adelantos + cuentas familiares.

## Fase 7
Liquidación por campaña, reportes, costos por chaco/hectárea.

## Fase 8
Backup y exportación.

# Pantalla de compra USD

Mostrar claramente:

Producto
Cantidad
Moneda
Precio unitario
Tipo de cambio
Precio convertido BOB
Subtotal BOB

Ejemplo visual:

420 L
$16.00/L
FX 7.00
Bs 112.00/L
Bs 47.040,00

# Liquidación de campaña

Crear vista por persona con:

- consumo total;
- cargos;
- pagos;
- saldo;
- saldo a favor;
- detalle cronológico.

# Reglas de cancelación

No borres operaciones financieras o de inventario confirmadas silenciosamente.

Usa reversión.

Si una compra tiene lotes ya consumidos, bloquear cancelación directa y exigir reversión consistente.

# Pruebas obligatorias

Debe existir cobertura para:

- FX 7;
- FX 12.10;
- BOB sin FX;
- asignación que no crea deuda familiar;
- aplicación que sí crea deuda familiar;
- tercero con cargo por allocation;
- tercero con adelanto;
- FIFO con lotes de costos diferentes;
- pagos parciales;
- reversión;
- rollback transaccional.

# Escenario E2E obligatorio

1. crear administrador;
2. crear familiar y tercero;
3. crear chacos;
4. crear glifosato;
5. planificar 28 ha × 1.5 L = 42 L;
6. comprar 420 L a $16 con FX 7;
7. obtener Bs 47.040;
8. registrar pago total del administrador al proveedor;
9. asignar 390 L a familia y 30 L a tercero;
10. verificar stock físico 420 L;
11. verificar lotes;
12. tercero: adelanto o deuda;
13. familiar aplica producto;
14. FIFO calcula costo;
15. se genera deuda por uso;
16. registrar pago parcial;
17. verificar saldo;
18. generar liquidación de campaña;
19. mostrar sobrantes;
20. backup.

# Forma de trabajo

Trabaja fase por fase.

Después de cada fase:

- formatter;
- analyzer;
- tests;
- corregir errores;
- resumen;
- archivos modificados;
- decisiones tomadas.

No continúes si la fase actual no compila.

No simplifiques silenciosamente las reglas financieras.
