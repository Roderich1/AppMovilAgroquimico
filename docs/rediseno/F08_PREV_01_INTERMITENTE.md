# f08_prev_01_previo_ui_test — fallo intermitente (investigación del 2026-11-12)

**Estado: ABIERTO.** Mecanismo reproducido de forma controlada; la causa del retraso dentro de la suite completa no está observada.

## Síntoma

En 2 de 5 suites completas de `feat/rediseno-movil` (concurrencia 4) falló la prueba «Mis datos están bien» pide la misma confirmación y sólo entonces la pasa a las reglas normales:

> El registro no terminó [confirmar] en 100 vueltas: pedidas [confirmar], terminadas [].

Las dos suites completas siguientes (`e6d72b3`, `6b397c9`) pasaron. Que pasen no lo resuelve.

## Qué cambió respecto de la base `01b2576`

- La prueba, `lib/data/restore_safety_copies.dart` y `lib/data/backup_service.dart`: **sin cambios**.
- `remote_backup_screen.dart`: cambio de presentación (rediseño de Respaldos) y la sección «En este teléfono». No añade llamadas al registro en el camino de la prueba (la única nueva, `onRestored` tras una restauración local, no se ejecuta aquí).
- Esquema v18 (rama F): la prueba abre la base, pero `confirmRecovery` no la usa.

## Mediciones (`tool/rediseno/diag_f08_rondas_test.dart`, copia de la prueba con medición; mismas aserciones)

Cada «vuelta» del auxiliar = `runAsync` 5 ms + `pump` 50 ms. Las acciones del registro avanzan un paso de E/S por vuelta.

| Condición | `seguir` | `confirmar` |
|---|---|---|
| Aislada, `HEAD` (3 veces) | 10 vueltas, 230–280 ms | 15 vueltas, 310–400 ms |
| Con carga (concurrencia 4 y 9 archivos pesados, como `f08_load.sh`), `HEAD` (3 veces) | 10 vueltas, 209–226 ms | 15 vueltas, 291–364 ms |
| La misma carga sobre la base `01b2576` (3 veces) | 10 vueltas, 138–241 ms | 15 vueltas, 153–318 ms |

- El número de vueltas no cambia con la carga ni entre la rama y la base: la carga de esta medición no explica el fallo.
- El tope del auxiliar es de vueltas, pero en la práctica es un **tope de tiempo real**: 30 vueltas de `settle` + 100 de `settleRegistry` ≈ 1,5–2 s desde el toque.

## Reproducción controlada

`DIAG_STALL_MS` retiene `confirmRecovery` ese tiempo **real** (temporizador de la zona raíz, como la E/S real) antes de que el registro escriba:

| Retención | Resultado |
|---|---|
| 0 ms | pasa (15 vueltas) |
| 1000 ms | pasa (118 vueltas) |
| 2000, 3000, 5000 ms | **falla con el mismo mensaje** («pedidas [confirmar], terminadas []») |

Comando: `DIAG_STALL_MS=2000 flutter test --plain-name "pide la misma confirmación" tool/rediseno/diag_f08_rondas_test.dart`.

## Conclusión provisional

El fallo es compatible con **una sola operación de archivo** del registro (`registro.json.tmp` escrito con `flush` y renombrado, en `%TEMP%`) que tarda más de ≈1,5 s durante la suite completa. Con un bloqueo real (que nunca termina) el mensaje sería el mismo, pero en 9 ejecuciones medidas nunca hizo falta más de 15 vueltas.

**No demostrado:** qué retiene esa operación dentro de la suite completa (contención de disco o análisis del antivirus son hipótesis sin medir). No se cambiaron tiempos, esperas ni aserciones.

## Siguiente paso (cuando haya motivo para otra suite completa)

Incluir el diagnóstico en una suite completa con `DIAG_CAP=3000` para medir cuánto tarda de verdad la acción cuando ocurre. Si se confirma una retención de E/S, el autor decide entre un tope expresado en tiempo real (documentado) o dejarlo como limitación del entorno de pruebas en Windows.
