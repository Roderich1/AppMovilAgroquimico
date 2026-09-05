# ESPECIFICACIÓN DE IMPLEMENTACIÓN V2
## App móvil para planificación, compras, almacén compartido, aplicaciones, multi-moneda y cuentas familiares de agroquímicos

**Tecnologías objetivo:** Flutter + SQLite  
**Arquitectura operativa:** Offline-first  
**Usuario inicial:** un único administrador  
**Moneda base/reporting:** Bolivianos (BOB)  
**Monedas de compra V1:** BOB y USD  
**Versión:** 2.0

---

# 1. Cambio fundamental incorporado en V2

Además del control físico del agroquímico, la aplicación debe controlar correctamente el dinero.

El proceso real incluye:

- productos comprados directamente en bolivianos;
- productos cotizados en dólares;
- tipo de cambio acordado con el proveedor para cada compra;
- un mismo proveedor puede acordar 7, 9, 10, 12.10 Bs/USD u otro valor;
- el administrador normalmente paga al proveedor por toda la compra;
- cada familiar maneja su propio dinero;
- los familiares deben devolver al administrador el costo de lo que realmente utilizan;
- normalmente la liquidación se realiza al final de campaña;
- excepcionalmente pueden pagar durante la campaña;
- un tercero/conocido puede pagar antes o después de la compra.

Por tanto, deben separarse cuatro conceptos:

1. **precio de compra del proveedor**;
2. **conversión de USD a BOB**;
3. **quién pagó al proveedor**;
4. **quién debe reembolsar y por cuánto**.

---

# 2. Ejemplo real obligatorio

Producto:

- cantidad: 420 L
- precio: 16 USD/L
- tipo de cambio acordado: 7 Bs/USD

Cálculo:

`420 × 16 × 7 = 47.040 Bs`

La aplicación debe conservar por separado:

- cantidad: 420 L;
- moneda original: USD;
- precio unitario original: 16 USD/L;
- tipo de cambio utilizado: 7 Bs/USD;
- costo unitario convertido: 112 Bs/L;
- subtotal convertido: 47.040 Bs.

Nunca debe perderse el precio original en USD aunque todos los reportes financieros se consoliden en BOB.

---

# 3. Objetivo general

Desarrollar una app móvil que permita controlar de punta a punta:

**planificación → necesidad → compra → conversión de moneda → pago al proveedor → distribución del stock → aplicación real → costo consumido → cuentas por cobrar → pagos familiares → sobrantes.**

---

# 4. Actores financieros

## 4.1 Administrador

Es quien normalmente:

- realiza la compra;
- paga al proveedor;
- administra el almacén;
- registra aplicaciones;
- adelanta dinero por los familiares;
- cobra posteriormente a cada familiar o tercero.

## 4.2 Familiar

Tiene sus propios chacos y su propio dinero.

Puede:

- tener producto reservado/asignado;
- consumir producto durante la campaña;
- generar deuda según consumo real;
- hacer pagos parciales;
- liquidar al final de campaña.

## 4.3 Tercero / conocido

Puede participar en una compra conjunta.

Puede:

- pagar antes;
- pagar al momento;
- pagar después;
- generar una deuda asociada directamente a la cantidad comprada para él.

## 4.4 Proveedor

Puede vender productos:

- en BOB;
- en USD;
- usando un tipo de cambio consensuado.

---

# 5. Moneda base del sistema

La moneda base contable será:

**BOB**

Todos los:

- saldos;
- cuentas por cobrar;
- costos consumidos;
- reportes consolidados;
- pagos familiares;

se expresarán principalmente en BOB.

La compra debe conservar además su moneda original.

---

# 6. Política de tipo de cambio

Nunca hardcodear un tipo de cambio.

El tipo debe registrarse como **snapshot histórico de la compra**.

Ejemplos válidos:

- 7.00 Bs/USD
- 9.00 Bs/USD
- 10.00 Bs/USD
- 12.10 Bs/USD
- cualquier otro valor acordado

Campos conceptuales:

- currencyCode
- exchangeRateBobPerUsd
- exchangeRateSource
- exchangeRateNote

`exchangeRateSource`:

- AGREED_WITH_SUPPLIER
- OFFICIAL_REFERENCE
- MANUAL
- OTHER

Cambiar posteriormente una tasa de referencia global NO debe modificar compras históricas.

---

# 7. Compra con productos en BOB y USD

Cada `PurchaseItem` debe poder indicar su moneda.

Esto hace al modelo robusto incluso si en el futuro una factura contiene líneas con monedas diferentes.

Campos nuevos principales de PurchaseItem:

- currencyCode: BOB / USD
- originalUnitPriceMinor
- exchangeRateScaled nullable
- convertedUnitPriceBobMinor
- originalSubtotalMinor
- subtotalBobMinor

Para BOB:

- exchangeRate = null;
- subtotalBob = subtotal original.

Para USD:

- exchangeRate obligatorio;
- subtotalBob = cantidad × precio USD × tipo de cambio.

---

# 8. Precisión monetaria

No usar `double` para dinero.

## Dinero

Guardar en centavos.

Ejemplos:

- Bs 53.47 -> 5347
- USD 16.00 -> 1600

## Tipo de cambio

Guardar como entero escalado.

Recomendación:

`exchangeRateScaled = tasa × 1_000_000`

Ejemplos:

- 7.00 -> 7_000_000
- 12.10 -> 12_100_000

Esto permite cálculos determinísticos.

---

# 9. Cantidades

Recomendación:

## Volumen

mililitros.

420 L -> 420000 mL.

## Peso

gramos.

56 kg -> 56000 g.

No convertir litros a kilos.

---

# 10. Fórmula de conversión

Si el precio está expresado por litro y la cantidad se almacena en mililitros:

```text
subtotalBobMinor =
  quantityMl
  × unitPriceUsdMinor
  × exchangeRateScaled
  / 1000
  / 1_000_000
```

Aplicar una política explícita de redondeo monetario.

La UI mostrará el resultado en BOB con dos decimales.

---

# 11. Separar pago a proveedor de cobro familiar

Este es un requisito crítico.

## 11.1 ProviderPayment

Representa dinero que alguien paga al proveedor.

Campos:

- id
- purchaseId
- payerPersonId
- paymentDate
- amountBobMinor
- paymentMethod
- notes

Normalmente:

`payerPersonId = administrador`

Una compra puede quedar:

- no pagada;
- parcialmente pagada;
- totalmente pagada.

---

# 12. Cuenta corriente interna de cada persona

No reutilizar `ProviderPayment` para pagos familiares.

Crear un ledger financiero interno.

## AccountTransaction

Campos:

- id
- personId
- campaignId nullable
- transactionDate
- type
- amountBobMinorSigned
- referenceType
- referenceId
- notes

Tipos:

- USAGE_CHARGE
- PURCHASE_ALLOCATION_CHARGE
- PAYMENT
- ADVANCE
- REFUND
- CREDIT
- DEBIT_ADJUSTMENT
- CREDIT_ADJUSTMENT

Convención recomendada:

- cargos/deudas: positivos;
- pagos/créditos: negativos.

Saldo:

`SUM(amountBobMinorSigned)`

Resultado:

- > 0: la persona debe dinero;
- = 0: cuenta saldada;
- < 0: tiene saldo a favor.

---

# 13. Dos políticas de cobro

## 13.1 Familia: cobrar por uso real

Política predeterminada:

`BY_ACTUAL_USAGE`

Cuando un familiar aplica agroquímico:

1. se registra la aplicación;
2. se determina cuánto producto consumió;
3. se calcula el costo BOB de ese consumo;
4. se genera un `USAGE_CHARGE`;
5. el familiar puede pagar inmediatamente o posteriormente.

La deuda puede acumularse durante toda la campaña.

Al final se genera el estado de cuenta.

---

## 13.2 Tercero: cobrar por cantidad comprada para él

Política predeterminada:

`BY_PURCHASE_ALLOCATION`

Si se compraron 30 L específicamente para un conocido, se puede generar el cargo al confirmar la compra/asignación.

Si pagó antes:

1. se registra ADVANCE;
2. posteriormente se genera el cargo;
3. el crédito compensa la deuda.

---

# 14. Política configurable por persona

Agregar en `Person`:

- settlementPolicy

Valores:

- BY_ACTUAL_USAGE
- BY_PURCHASE_ALLOCATION
- MANUAL

Valores sugeridos:

- ADMIN -> MANUAL / NOT_APPLICABLE
- FAMILY -> BY_ACTUAL_USAGE
- THIRD_PARTY -> BY_PURCHASE_ALLOCATION

El administrador puede cambiarlo.

---

# 15. Problema del costo real del producto

Para cobrar por consumo no basta saber cuántos litros se utilizaron.

También es necesario saber:

**de qué compra provino ese producto y cuánto costó en BOB.**

Ejemplo:

Compra A:
- Glifosato
- 100 L
- 100 Bs/L

Compra B:
- Glifosato
- 100 L
- 115 Bs/L

Si posteriormente alguien consume 120 L, el sistema necesita una política de valoración.

---

# 16. Solución: lotes de inventario

Agregar:

## InventoryLot

Campos:

- id
- purchaseItemId
- productId
- ownerPersonId
- acquiredDate
- initialQuantityBase
- unitCostBobMinorPerMajorUnit
- currencyCode
- originalUnitPriceMinor
- exchangeRateScaled nullable
- notes

Cada asignación confirmada de compra genera uno o varios lotes.

Ejemplo:

Compra:
420 L

Asignación:
- Familia: 390 L
- Tercero: 30 L

Genera:

Lot A:
- producto X
- familia
- 390 L
- costo 112 Bs/L

Lot B:
- producto X
- tercero
- 30 L
- costo 112 Bs/L

---

# 17. Inventario sigue siendo ledger

`InventoryLot` NO reemplaza `InventoryMovement`.

El saldo físico continúa derivándose de movimientos.

Cada movimiento debe poder tener:

- lotId nullable;
- productId;
- ownerPersonId;
- quantitySigned.

Esto mantiene:

- trazabilidad;
- costo histórico;
- propiedad;
- historial.

---

# 18. Consumo de lotes

Agregar:

## ApplicationConsumption

Relaciona:

- ApplicationItem
- InventoryLot
- quantityConsumedBase
- costBobMinor

Una aplicación puede consumir varios lotes.

Ejemplo:

Se aplican 50 L.

Lote antiguo:
20 L a 100 Bs/L

Lote nuevo:
30 L a 115 Bs/L

Costo:

- 20 × 100 = 2.000 Bs
- 30 × 115 = 3.450 Bs

Total cargo:

**5.450 Bs**

---

# 19. Política FIFO

Para V1/V2 utilizar:

**FIFO por defecto**

Consumir primero los lotes más antiguos disponibles de:

- mismo producto;
- mismo propietario.

Esto es:

- simple;
- auditable;
- fácil de explicar;
- conserva costos reales históricos.

Permitir selección manual de lote posteriormente si el cliente lo necesita.

---

# 20. Cobro familiar al confirmar aplicación

Para una persona `BY_ACTUAL_USAGE`:

```text
Application
   ↓
ApplicationItem
   ↓
ApplicationConsumption
   ↓
Costo consumido en BOB
   ↓
AccountTransaction: USAGE_CHARGE
```

Ejemplo:

Carlos consume 42 L.

Costo FIFO resultante:

112 Bs/L.

Cargo:

42 × 112 = 4.704 Bs.

La cuenta de Carlos aumenta en:

**Bs 4.704**

---

# 21. Pago durante la campaña

Carlos debe:

Bs 4.704.

Paga:

Bs 2.000.

AccountTransaction:

- USAGE_CHARGE +470400 centavos
- PAYMENT -200000 centavos

Saldo:

Bs 2.704.

Puede continuar utilizando productos y acumulando nuevos cargos.

---

# 22. Liquidación al final de campaña

Crear pantalla:

**Liquidación de campaña**

Por cada persona mostrar:

- saldo inicial;
- consumo total;
- cargos por agroquímicos;
- otros ajustes;
- pagos realizados;
- saldo pendiente;
- saldo a favor.

Ejemplo:

Carlos:

- consumo cargado: Bs 18.530
- pagó durante campaña: Bs 5.000
- saldo final: Bs 13.530

Botón:

**Registrar pago de liquidación**

---

# 23. Estado de cuenta individual

Pantalla de persona:

```text
Fecha       Concepto                 Cargo     Pago      Saldo
01/06       Aplicación Glifosato     4.704               4.704
15/06       Pago                               2.000      2.704
22/06       Aplicación Paraquat      1.800               4.504
...
```

Debe poder filtrarse por:

- campaña;
- fecha;
- producto;
- tipo de movimiento.

---

# 24. Diferencia entre asignación y deuda

**Asignar stock a una persona NO significa automáticamente que esa persona deba dinero.**

Depende de `settlementPolicy`.

### Familiar BY_ACTUAL_USAGE

Asignación:
50 L

Todavía no debe por los 50 L.

Consume:
28 L

Se le cargan únicamente los 28 L valorizados.

### Tercero BY_PURCHASE_ALLOCATION

Asignación:
30 L

Se le carga el costo de los 30 L al confirmar la compra.

---

# 25. Sobrante familiar

Ejemplo:

Se reservaron para Carlos:
50 L

Consumió:
46 L

Quedan:
4 L

Si Carlos usa política BY_ACTUAL_USAGE:

- se cobra 46 L;
- los 4 L todavía permanecen como inventario;
- pueden usarse en otra aplicación;
- transferirse;
- devolverse;
- permanecer para otra campaña.

Esto refleja la operación explicada por el cliente.

---

# 26. Compra conjunta con tercero y familia

Ejemplo completo:

Compra total:
420 L.

Precio:
16 USD/L.

Tipo de cambio:
7 Bs/USD.

Costo total:
47.040 Bs.

Asignación:

- Familia: 390 L
- Tercero: 30 L

Costo convertido unitario:
112 Bs/L.

Tercero:
30 × 112 = 3.360 Bs.

Familia:
390 × 112 = 43.680 Bs.

Si el tercero paga antes:

- ADVANCE = -3.360
- PURCHASE_ALLOCATION_CHARGE = +3.360
- saldo = 0.

Para los familiares BY_ACTUAL_USAGE no se genera deuda por los 390 L completos. La deuda aparece conforme consuman su parte.

---

# 27. Entidades actualizadas

Tablas principales:

- persons
- farms
- campaigns
- products
- suppliers
- application_plans
- application_plan_items
- purchases
- purchase_items
- purchase_allocations
- provider_payments
- inventory_lots
- inventory_movements
- applications
- application_items
- application_consumptions
- account_transactions
- app_settings

---

# 28. Purchase

Campos principales:

- id
- supplierId
- campaignId
- purchaseDate
- invoiceNumber
- defaultCurrencyCode
- defaultExchangeRateScaled nullable
- exchangeRateSource nullable
- exchangeRateNote nullable
- totalBobMinor
- status
- notes
- invoiceImagePath nullable

---

# 29. PurchaseItem

Campos principales:

- id
- purchaseId
- productId
- quantityBase
- priceMajorUnit
- currencyCode
- originalUnitPriceMinor
- exchangeRateScaled nullable
- convertedUnitPriceBobMinor
- originalSubtotalMinor
- subtotalBobMinor

---

# 30. PurchaseAllocation

Campos principales:

- id
- purchaseItemId
- personId
- quantityBase
- chargePolicySnapshot
- amountBobMinorIfAllocationCharge
- notes

`chargePolicySnapshot` es importante para conservar la regla histórica aunque luego se cambie la política de la persona.

---

# 31. ProviderPayment

Campos:

- id
- purchaseId
- payerPersonId
- paymentDate
- amountBobMinor
- method
- notes

---

# 32. AccountTransaction

Campos:

- id
- personId
- campaignId
- transactionDate
- type
- amountBobMinorSigned
- referenceType
- referenceId
- notes

---

# 33. Flujo financiero completo

```text
PLANIFICAR
    ↓
COMPRAR
    ↓
PRECIO BOB o USD
    ↓
SI USD → REGISTRAR TIPO DE CAMBIO
    ↓
CALCULAR COSTO EN BOB
    ↓
ADMINISTRADOR PAGA AL PROVEEDOR
    ↓
ASIGNAR STOCK
    ↓
FAMILIA UTILIZA PRODUCTO
    ↓
FIFO DETERMINA COSTO REAL
    ↓
GENERAR CARGO POR USO
    ↓
PAGOS DURANTE CAMPAÑA (opcionales)
    ↓
LIQUIDACIÓN FINAL
```

---

# 34. Dashboard financiero

Agregar:

- total pagado a proveedores en campaña;
- total por cobrar a familiares;
- total por cobrar a terceros;
- pagos recibidos;
- saldo pendiente;
- compras BOB;
- compras USD convertidas;
- costo consumido por persona.

---

# 35. Pantalla de registro de compra

Cada línea debe mostrar:

- producto;
- cantidad;
- unidad;
- moneda;
- precio unitario;
- tipo de cambio si USD;
- precio convertido BOB;
- subtotal BOB.

Ejemplo UI:

```text
Producto: Glifosato
Cantidad: 420 L
Moneda: USD
Precio: $16.00 / L
Tipo de cambio: 7.00 Bs/USD
Costo unitario: Bs 112.00 / L
Subtotal: Bs 47.040,00
```

---

# 36. UX del tipo de cambio

Al seleccionar USD:

Mostrar campo obligatorio:

**Tipo de cambio aplicado**

Selector opcional:

- Acordado con proveedor
- Referencia oficial
- Manual
- Otro

Mostrar inmediatamente:

```text
$16.00 × 7.00 = Bs 112.00/L
```

El usuario debe poder verificar visualmente el cálculo antes de confirmar.

---

# 37. No asumir una tasa global

Puede existir en Settings:

- tipo de cambio sugerido actual;

pero debe funcionar únicamente como valor inicial.

Al confirmar la compra:

- copiar la tasa dentro de la compra/item;
- no enlazar dinámicamente al valor de Settings.

---

# 38. Reportes nuevos

Agregar:

1. compras originales en USD;
2. compras originales en BOB;
3. compras convertidas a BOB;
4. tipos de cambio utilizados;
5. pagos a proveedores;
6. dinero adelantado por administrador;
7. consumo valorizado por familiar;
8. cuentas por cobrar;
9. pagos recibidos;
10. liquidación por campaña;
11. estado de cuenta por persona;
12. costo por chaco;
13. costo por hectárea;
14. costo por producto.

---

# 39. Costo por chaco

Como mejora muy útil:

```text
Costo total de aplicaciones del chaco
÷
hectáreas
=
Costo de agroquímicos por hectárea
```

Esto permitirá comparar terrenos y campañas.

---

# 40. Reglas de negocio nuevas

1. Una compra USD requiere tipo de cambio.
2. Una compra BOB no requiere tipo de cambio.
3. El tipo histórico nunca cambia automáticamente.
4. Todos los reportes consolidados usan BOB.
5. El precio original debe conservarse.
6. Pago a proveedor y pago de familiar son entidades diferentes.
7. El administrador puede pagar una compra aunque los beneficiarios no hayan pagado.
8. Un familiar BY_ACTUAL_USAGE genera deuda solo al consumir.
9. Un tercero BY_PURCHASE_ALLOCATION puede generar deuda al comprar.
10. Un adelanto puede crear saldo a favor.
11. Aplicar producto debe generar consumo de lotes.
12. El costo de uso debe provenir de los lotes consumidos.
13. FIFO es política predeterminada.
14. Cancelar una aplicación debe revertir inventario y cargo financiero.
15. Cancelar una compra debe revertir lotes, inventario, cargos y pagos relacionados según reglas seguras.
16. No permitir cancelar una compra cuyo lote ya fue consumido sin un flujo explícito de reversión.
17. Transferir stock debe conservar costo del lote.
18. Dividir un lote al transferir no debe cambiar su costo unitario.
19. Los pagos parciales deben conservar historial.
20. La liquidación final no debe borrar movimientos previos.

---

# 41. Transacciones SQLite críticas

## Confirmar compra

Atómicamente:

- purchase;
- items;
- conversión;
- allocations;
- lots;
- PURCHASE_IN;
- cargos por allocation si aplica.

## Confirmar aplicación

Atómicamente:

- application;
- items;
- selección FIFO;
- application_consumptions;
- APPLICATION_OUT;
- USAGE_CHARGE si corresponde.

## Pago familiar

Atómicamente:

- account transaction PAYMENT;
- actualización derivada de saldo.

## Reversión de aplicación

Atómicamente:

- reverse inventory;
- reverse consumptions;
- reverse account charge.

---

# 42. Casos de prueba adicionales

## FX01

420 L × 16 USD/L × 7 = 47.040 Bs.

## FX02

420 L × 16 USD/L × 12.10 = 81.312 Bs.

## FX03

Producto BOB:
100 L × Bs 50 = Bs 5.000.
No solicita FX.

## FIN01

Administrador paga proveedor Bs 47.040.
No significa que todos los familiares hayan pagado al administrador.

## FIN02

Familiar recibe asignación 50 L BY_ACTUAL_USAGE.
Sin consumo:
deuda = 0.

## FIN03

Consume 28 L a Bs 112/L.
Cargo = Bs 3.136.

## FIN04

Debe Bs 3.136.
Paga Bs 1.000.
Saldo = Bs 2.136.

## FIN05

Tercero obtiene 30 L BY_PURCHASE_ALLOCATION a Bs 112/L.
Cargo = Bs 3.360.

## FIN06

Tercero había adelantado Bs 3.360.
Después del cargo:
saldo = 0.

## LOT01

20 L a Bs 100 + 30 L a Bs 115 consumidos FIFO.
Costo = Bs 5.450.

---

# 43. Escenario de aceptación actualizado

La aplicación debe poder demostrar:

1. Crear administrador.
2. Crear familiares.
3. Crear tercero.
4. Crear chacos.
5. Crear Glifosato.
6. Planificar 28 ha × 1.5 L = 42 L.
7. Registrar compra de 420 L.
8. Moneda USD.
9. Precio $16/L.
10. Tipo de cambio 7.
11. Obtener Bs 47.040.
12. Registrar que administrador paga al proveedor.
13. Asignar 390 L familia y 30 L tercero.
14. Crear lotes conservando costo Bs 112/L.
15. Registrar que tercero pagó antes o queda debiendo.
16. Registrar una aplicación familiar.
17. Consumir lote FIFO.
18. Descontar inventario.
19. Crear cargo por uso real.
20. Registrar pago parcial familiar.
21. Mostrar saldo.
22. Liquidar campaña.
23. Mostrar sobrantes.
24. Exportar backup.

---

# 44. Decisiones técnicas obligatorias

- Flutter.
- SQLite.
- Offline-first.
- BOB como moneda base de reporting.
- BOB y USD soportados desde V1.
- Tipo de cambio histórico por compra/item.
- Nunca usar tasa dinámica para recalcular historia.
- Pago proveedor separado de cuenta familiar.
- Familia cobrable por uso real.
- Terceros configurables por compra/asignación.
- Inventario basado en movimientos.
- Costos basados en lotes.
- FIFO por defecto.
- Operaciones financieras e inventario con transacciones SQLite.
