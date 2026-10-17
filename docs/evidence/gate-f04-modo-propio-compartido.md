# GATE-F04 (#28): modo propio/compartido pasa la regresión móvil — acta propuesta

- **Fecha:** 2026-10-17. Redactada por la sesión A de Claude Code, por la delegación técnica de Roderich.
- **Estado del gate: Pending.** Este documento **no** decide: la decisión es de Roderich, con confirmación explícita. La revisión del tutor se registra en GOV-01 (BE #105). **No se propone Passed por el número de pruebas.**
- **Base:** Mobile `main` `cf3d510`, que integra MOB #102 (F04 #25/#26). Después entraron #103 (#97, `8103766`) y #107 (menores de Liquidación); ninguno cambia lo que evalúa esta acta. #97 es de F10-COMPAT y no condiciona este gate. **Añadido del 2026-10-17 (tarde):** el criterio 5 se evalúa además sobre la rama `feat/f04-campana-fecha-efectiva` (base `main` `8a2c558`); el PR y su CI constan en [F04_CAMPANA_FECHA_EFECTIVA.md](F04_CAMPANA_FECHA_EFECTIVA.md).
- Trazabilidad (Cap. III v1.5): RF-03 a RF-13, RF-17, RF-31; RNF-01, RNF-02; CU-04 a CU-10, CU-17, CU-19.

## Tareas del gate (#24–#27)

| Issue | Entrega | Evidencia | Estado |
|---|---|---|---|
| #24 MODE-01: persistir la modalidad | #77 (migración v8, `OperationModeStore`) | `F04_ACTIVACION_TITULAR_MODO.md` (`fccd74c`), `F04_CORRECCIONES_REVISION.md` (`731750e`, `8e52fe1`, `812fe49`); `f04_operation_mode_test` (valor por defecto, persistencia tras reabrir, base migrada); DEVICE P3/P8 (`operation_mode` en la base del teléfono) | Cumplida |
| #25 MODE-02: elección, consulta y cambio comprensibles | #78 + **#102** | `F04_MOB_MODE_02_ONBOARDING_UX.md` (`7ac7153`; la espera explícita de `0615966` consta en `F04-MODE-03_flujos_modo_personal.md`); DEVICE P3, P8 y P9 | Cumplida |
| #26 MODE-03: propio sin transferencias ni elección de responsables | **#102** | `F04-MODE-03_flujos_modo_personal.md` (14 casos, 16 mutaciones detectadas); DEVICE P4–P7 | Cumplida |
| #27 MODE-04: transiciones seguras | #77 (atomicidad, bloqueo, carrera corregida) + **#102** (en propio no se revierte actividad de terceros) | `f04_operation_mode_test`, `f04_mode_race_test`; reversiones en `personal_mode_flows_test`; DEVICE P8 (negocio idéntico) y P9 (bloqueo con nombre, base idéntica) | Cumplida |

**Discrepancia conservada.** #24 y #27 dicen «movimientos de terceros». Se aplica la v1.5 (CU-05 A2/E1, RN-17) y el criterio D de la política de activación del 2026-10-15 (`F04_ACTIVACION_TITULAR_MODO.md`, tabla «Contraste con las fuentes»): bloquean los **datos activos** (existencias, planes abiertos y saldos), no el historial. Allí consta como discrepancia declarada. `_briefs/PLAN_TERMINAR_F01_F09_ANTES_F10_2026-10-17.md` §4 la llama «criterio aprobado de datos activos frente a texto antiguo de movimientos históricos».

## Criterios de #28

| # | Criterio | Evidencia | Procedencia | Estado |
|---|---|---|---|---|
| 1 | Propio → compartido: compras, aplicaciones, movimientos, necesidades y campañas siguen con el titular y consultables | `f04_operation_mode_test` (ida y vuelta con tablas idénticas); `operation_mode_onboarding_test` (volcado de negocio y existencias idénticos); **DEVICE P8** (tablas de negocio idénticas antes y después, sin red) | HOST + DEVICE | Cumplido |
| 2 | Compartido con existencias o movimientos de otros → propio: se bloquea o exige resolver, sin borrar ni reasignar | `f04_operation_mode_test` (existencias, planes y saldos de terceros); **DEVICE P9** («Existencias de Hermana DEV…», base idéntica, sigue `SHARED`) | HOST + DEVICE | Cumplido |
| 3 | Propio: sin responsables ni transferencias en compra, inventario, aplicación y necesidad; mismos resultados del dominio único | `personal_mode_flows_test` (navegación, compra, aplicación, planificación, catálogos y liquidación; las filas son las del dominio); 16 mutaciones; **DEVICE P4–P7** | HOST + DEVICE | Cumplido |
| 4 | Compartido: una transferencia compensa salida y entrada sin crear consumo ni saldo negativo | Pruebas de repositorio y `f04_bug_01`/`f04_bug_02` (transferencias multiproducto y reversiones), verdes en la suite; en `personal_mode_flows_test` la transferencia se revierte en compartido | HOST | Cumplido en host. **No se hizo una transferencia en el teléfono en esta sesión** |
| 5 | En cualquier modo y sin conexión: una compra o aplicación multiproducto confirmada persiste tras cerrar y reabrir, con la campaña de la fecha efectiva | **Campaña por fecha efectiva** (2026-10-17, [F04_CAMPANA_FECHA_EFECTIVA.md](F04_CAMPANA_FECHA_EFECTIVA.md)). Una compra o aplicación se registra sólo si la única campaña que contiene el día local de su fecha es la activa. Ninguna, varias, cerrada o planificada se rechazan sin escrituras parciales. El calendario no se solapa. `f04_campaign_effective_date_test`: 13 casos, compra y aplicación **multiproducto** en **los dos modos**, cierre y reapertura, límites de día local y FIFO con la hora completa; 15 mutaciones detectadas. **DEVICE P6/P7** (antes de esta regla): compra y aplicación de un producto, sin red, persisten tras forzar el cierre | HOST (campaña y multiproducto) + DEVICE (persistencia, un producto) | **Cumplido para lo que se registra**, en host. **RF-03, registros tardíos de un período cerrado: no cumplido**: se rechazan como salvaguarda, a decidir en D-F04-C1. Residual D-F04-C2: el período local no se compara con el central. Ver «Para decidir» |
| 6 | `flutter test` sigue en verde sin pruebas debilitadas | CI 39039421077 sobre `0615966` (integrado como `cf3d510`): SUCCESS, **1090 pasan y 3 omitidas**. En local (Windows), 1091 pasan y 2 se omiten; una prueba depende de la plataforma. **Cambiaron de expectativa:** la prueba del pagador en propio (el selector desapareció; ahora se comprueba en la base) y la espera explícita de `operation_mode_onboarding_test`, sin debilitarla | CI + HOST | Cumplido |

## Límites

- **Dispositivo:** un solo teléfono y un solo modelo. Transferencia y multiproducto sólo en host. La regla de campaña por fecha efectiva sólo se probó en host; la sesión física del 2026-10-17 fue anterior a ella.
- **REC (#38–#57).** Son capacidades reconstruidas anteriores al seguimiento: no condicionan este gate ni se presentan como trabajo nuevo. Su estado está en la matriz F01–F09 (BE `docs/evaluation/F01_F09_MATRIZ_OPERATIVA.md`, integrada con BE #130 en `e4b9c29`).
- **Usabilidad.** Que las explicaciones de #25 se entiendan sólo se evaluará con personas, en F10 (SUS y tareas); aquí no se afirma.

## Para decidir (Roderich)

1. **GATE-F04:** Passed para el alcance académico, con los límites de arriba y con D-F04-C1 y D-F04-C2 resueltas o aceptadas como límite; o Pending hasta resolverlos. *(Antecedente: hasta el 2026-10-17 este punto decía «incluida la campaña por fecha efectiva, no implementada». Desde MOB PR del criterio 5 está implementada para lo que se registra.)*
   - **D-F04-C1, registros tardíos de un período cerrado** (RF-03: «registros tardíos quedan asociadas al período correcto»; Cap. III §3.11.13: «requerirán revisión, conservando su historia»):
     - (A) construir un estado «requiere revisión»: la operación se guarda en la campaña cerrada de su fecha, visible, sin reabrir, sin reasignar y sin publicarse a Central. Antes hay que definir quién revisa, qué resultados tiene y qué efecto tiene en el inventario;
     - (B) aceptar el rechazo actual como límite del alcance académico.
     - Las fuentes no definen la revisión, así que no se construyó por intuición.
   - **D-F04-C2, período local frente al central.** El vínculo con Central lee las fechas centrales de la campaña, pero no comprueba que el período local quepa en ellas. Afecta a los vínculos futuros y al consumo **ya publicado** con fechas locales fuera del período central. Opciones:
     - comprobarlo al vincular y señalar lo ya publicado (trabajo de F05);
     - o aceptarlo como límite.
2. **#24, #25, #26 y #27 ya están cerradas** desde el 2026-10-17 a las 14:54Z. Las cerró la sesión A, con la cuenta Roderich1, con un comentario de mapeo de criterios en cada una y Done/Verified en el Project. Para **#24 y #27** se apoyó en `_briefs/PLAN_TERMINAR_F01_F09_ANTES_F10_2026-10-17.md` (§2, fila F04: «verificar y cerrar #24/#27»). **#25 y #26 los cerró por criterio propio**: el mismo plan (§4, punto 2) pide completarlas («completa la elección comprensible…», «en PERSONAL oculta…») y sus criterios quedaron cumplidos en host y en el teléfono. El plan no pide expresamente cerrarlas. Si Roderich no está de acuerdo, se reabren; no condicionan el gate.

## Revisiones

- Redacción: sesión A de Claude Code, el 2026-10-17.
- Revisión técnica del PR #102: sesión C (LISTO).
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
