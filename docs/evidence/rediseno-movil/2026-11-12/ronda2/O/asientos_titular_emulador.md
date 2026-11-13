# Asientos de pago al titular en los datos del emulador (sólo lectura)

- **Fecha real:** 2026-11-12.
- **Dispositivo:** `emulator-5556` (AVD `RDM_Pixel8`), paquete `.rdm`, código instalado `fc12123`.
- **Datos:** sintéticos, cuenta de revisión del autor.

## Cómo se obtuvo

1. Copia de la base, sin tocar la que usa la app: `adb exec-out run-as <paquete .rdm> cat databases/agroquimicos_v2.db > copia.db`. La copia quedó en el scratchpad de la sesión, fuera del repositorio.
2. `sqlite3 -readonly copia.db < tool/rediseno/asientos_pago_titular.sql`. La consulta es de la sesión C (`3fdd345`) y es de sólo lectura.

## Resultado

| Asiento | Persona | Tipo | Fecha (UTC) | Día local | Campaña de registro | Importe | Imputado | Imputación (cargo:centavos) | Motivo |
|---|---|---|---|---|---|---|---|---|---|
| 5 | Rosa Vargas | PAYMENT | 2026-11-12T23:50:38Z | 2026-11-12 | Invierno 2026 | 22,00 Bs | 22,00 Bs | 3:2200 | titular vigente |

Es el único asiento de este tipo.

## Origen

La app no guarda desde qué pantalla se registró un pago. En el código instalado (`fc12123`), la única entrada que permitía registrar un pago a la persona titular era «Registrar pago» en el menú ⋮ de la tarjeta «Consumo y costos propios» de Cuentas (criterio Q-2). El asiento tiene la hora de la revisión del autor del 2026-11-12 y no aparecía en su captura anterior de «Movimientos propios». Por eso se atribuye a esa entrada, que es el defecto que el autor informó.

## Tratamiento

No se borró ni se reclasificó. Con la corrección (`3fdd345`), el repositorio rechaza registrar un pago así. El asiento existente se sigue mostrando como registro («pagos y ajustes registrados»), nunca como cobro. Cualquier corrección de datos (por ejemplo, revertirlo con su motivo) queda pendiente de la decisión del autor.

Captura del estado anterior: `antes/04_movimientos_propios_titular.png` y `antes/00_cuentas_titular_pagos_registrados.png`.
