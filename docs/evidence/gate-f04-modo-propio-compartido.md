# GATE-F04 (#28): modo propio/compartido pasa la regresión móvil — acta propuesta

- **Fecha:** 2026-10-17. Redactada por la sesión A de Claude Code, por la delegación técnica de Roderich.
- **Estado del gate: Pending.** Este documento **no** decide: la decisión es de Roderich, con confirmación explícita. La revisión del tutor se registra en GOV-01 (BE #105). **No se propone Passed por el número de pruebas.**
- **Base:** Mobile `main` `cf3d510`, que integra MOB #102 (F04 #25/#26). #97 (MOB #103) es de F10-COMPAT y no condiciona este gate.
- Trazabilidad (Cap. III v1.5): RF-03 a RF-13, RF-17, RF-31; RNF-01, RNF-02; CU-04 a CU-10, CU-17, CU-19.

## Tareas del gate (#24–#27)

| Issue | Entrega | Evidencia | Estado |
|---|---|---|---|
| #24 MODE-01: persistir la modalidad | #77 (migración v8, `OperationModeStore`) | `F04_ACTIVACION_TITULAR_MODO.md` (`fccd74c`), `F04_CORRECCIONES_REVISION.md` (`731750e`, `8e52fe1`, `812fe49`); `f04_operation_mode_test` (valor por defecto, persistencia tras reabrir, base migrada); DEVICE P3/P8 (`operation_mode` en la base del teléfono) | Cumplida |
| #25 MODE-02: elección, consulta y cambio comprensibles | #78 + **#102** | `F04_MOB_MODE_02_ONBOARDING_UX.md` (`7ac7153`/`0615966`); DEVICE P3, P8 y P9 | Cumplida |
| #26 MODE-03: propio sin transferencias ni elección de responsables | **#102** | `F04-MODE-03_flujos_modo_personal.md` (14 casos, 16 mutaciones detectadas); DEVICE P4–P7 | Cumplida |
| #27 MODE-04: transiciones seguras | #77 (atomicidad, bloqueo, carrera corregida) + **#102** (en propio no se revierte actividad de terceros) | `f04_operation_mode_test`, `f04_mode_race_test`; reversiones en `personal_mode_flows_test`; DEVICE P8 (negocio idéntico) y P9 (bloqueo con nombre, base idéntica) | Cumplida |

**Discrepancia aprobada y conservada.** #24 y #27 dicen «movimientos de terceros». Se aplica el criterio de la v1.5 y el D del 2026-10-15: bloquean los **datos activos** (existencias, planes abiertos y saldos), no el historial (`F04_ACTIVACION_TITULAR_MODO.md`).

## Criterios de #28

| # | Criterio | Evidencia | Procedencia | Estado |
|---|---|---|---|---|
| 1 | Propio → compartido: compras, aplicaciones, movimientos, necesidades y campañas siguen con el titular y consultables | `f04_operation_mode_test` (ida y vuelta con tablas idénticas); `operation_mode_onboarding_test` (volcado de negocio y existencias idénticos); **DEVICE P8** (tablas de negocio idénticas antes y después, sin red) | HOST + DEVICE | Cumplido |
| 2 | Compartido con existencias o movimientos de otros → propio: se bloquea o exige resolver, sin borrar ni reasignar | `f04_operation_mode_test` (existencias, planes y saldos de terceros); **DEVICE P9** («Existencias de Hermana DEV…», base idéntica, sigue `SHARED`) | HOST + DEVICE | Cumplido |
| 3 | Propio: sin responsables ni transferencias en compra, inventario, aplicación y necesidad; mismos resultados del dominio único | `personal_mode_flows_test` (navegación, compra, aplicación, planificación, catálogos y liquidación; las filas son las del dominio); 16 mutaciones; **DEVICE P4–P7** | HOST + DEVICE | Cumplido |
| 4 | Compartido: una transferencia compensa salida y entrada sin crear consumo ni saldo negativo | Pruebas de repositorio y `f04_bug_01`/`f04_bug_02` (transferencias multiproducto y reversiones), verdes en la suite; en `personal_mode_flows_test` la transferencia se revierte en compartido | HOST | Cumplido en host. **No se hizo una transferencia en el teléfono en esta sesión** |
| 5 | En cualquier modo y sin conexión: una compra o aplicación multiproducto confirmada persiste tras cerrar y reabrir, con la campaña de la fecha efectiva | Host: suites de compra y aplicación multiproducto y de campañas. **DEVICE P6/P7**: compra y aplicación **de un producto**, sin red, persisten tras forzar el cierre, en la campaña activa | HOST + DEVICE | Cumplido. En el teléfono sólo con un producto y en propio |
| 6 | `flutter test` sigue en verde sin pruebas debilitadas | `cf3d510`: CI 39039421077 de `0615966` SUCCESS. En local, 1091 pasan y 2 se omiten. **Cambiaron de expectativa:** la prueba del pagador en propio (el selector desapareció; ahora se comprueba en la base) y la espera explícita de `operation_mode_onboarding_test`, sin debilitarla | CI + HOST | Cumplido |

## Límites

- **Dispositivo:** un solo teléfono y un solo modelo. Transferencia y multiproducto sólo en host.
- **REC (#38–#57).** Son capacidades reconstruidas anteriores al seguimiento: no condicionan este gate ni se presentan como trabajo nuevo. Su estado está en la matriz F01–F09 (BE `docs/evaluation/F01_F09_MATRIZ_OPERATIVA.md`).
- **Usabilidad.** Que las explicaciones de #25 se entiendan sólo se evaluará con personas, en F10 (SUS y tareas); aquí no se afirma.

## Para decidir (Roderich)

1. **GATE-F04:** Passed para el alcance académico, con los límites de arriba, o Pending hasta probar en el teléfono una transferencia y una compra multiproducto.
2. **Cierres de #24, #25, #26 y #27** con este mapeo de evidencia.

## Revisiones

- Redacción: sesión A de Claude Code, el 2026-10-17.
- Revisión técnica del PR #102: sesión C (LISTO).
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
