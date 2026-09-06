# EVO-019 — Pago de cuenta mediante borrador de voz

## Estado

`APPROVED`. Este alcance registra pagos de personas/cuentas; no pagos a proveedores.

## Objetivo

Preparar un pago con persona, importe, fecha y campaña visibles, explicar su efecto en el
saldo y registrar sólo después de confirmación táctil.

## Ejemplo

> “Registra un pago para José Luis de dos mil bolivianos.”

| Campo | Valor propuesto |
|---|---|
| Persona | José Luis; selección obligatoria si hay homónimos |
| Importe | Bs 2.000 |
| Fecha | Hoy, visible y editable |
| Campaña | Activa o todas según contrato actual, siempre visible |
| Tipo | Pago normal |
| Saldo antes/después | Ambos calculados y mostrados |

## Reglas

- Resolver persona por catálogo; teléfono/rol u otro descriptor ayuda a desambiguar, pero no
  se inventa una identidad.
- El importe usa enteros BOB y el parser monetario central.
- Recalcular saldo inmediatamente antes de confirmar.
- Si no existe deuda o el importe supera el saldo, no convertir silenciosamente en adelanto.
- Mostrar una elección explícita: reducir el importe, cancelar o registrar como adelanto si el
  dominio actual lo permite y el usuario lo confirma táctilmente.
- No cambiar reglas de `ADMIN`, `FAMILY` o `THIRD_PARTY` desde voz.

## Confirmación

El botón específico `Registrar pago` sólo se habilita cuando persona, importe, fecha, campaña
y tratamiento de excedente son válidos. Al pulsarlo, convertir el draft al contrato de
`addAccountPayment()` y conservar sus reglas y transacción.

## Requisitos

- `EVO-019-REQ-001`: extraer persona e importe y mostrar los defaults de fecha/campaña.
- `EVO-019-REQ-002`: bloquear homónimos hasta selección manual o aclaración inequívoca.
- `EVO-019-REQ-003`: mostrar saldo antes y saldo previsto después.
- `EVO-019-REQ-004`: permitir editar todos los campos por voz o manualmente.
- `EVO-019-REQ-005`: requerir decisión explícita ante pago sin deuda o excedente.
- `EVO-019-REQ-006`: registrar una sola vez mediante `addAccountPayment()`.
- `EVO-019-REQ-007`: cancelar, fallar o volver atrás no crea asiento ni cambia saldo.

## Pruebas obligatorias

- Persona única, homónimos, inexistente y corrección por voz.
- Importes en palabras y cifras; cero, negativo, límite y formato ambiguo.
- Pago menor, igual y mayor al saldo; persona sin deuda.
- Elección explícita de adelanto y cancelación.
- Cambio de saldo entre preview y confirmación.
- Paridad con el flujo manual, doble toque y fallo transaccional.

