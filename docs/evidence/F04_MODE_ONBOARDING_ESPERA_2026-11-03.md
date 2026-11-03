# CI de `main` en `c2ac44a`: `operation_mode_onboarding_test` — diagnóstico y espera explícita

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-03 (UTC) |
| Fallo | Run 41566802912 («Flutter CI», push a `main`, `c2ac44a`, la integración de #180 / Refs #164). Se conserva visible y no se relanzó |
| Rama | `fix/f04-mode-onboarding-espera-explicita`, desde `main` `c2ac44a` |
| Procedencia | **HOST**: Windows 11, Flutter 3.47.2 y `sqflite_common_ffi`. Ninguna suite ni emulador en paralelo |
| Issue | Refs #164 |

## 1. Lo que falló, según la traza completa

**«recién activado sin titular: elige la modalidad…, sin red»**, en la línea 61:
- **La aserción:** `Expected: OperationMode.personal`, `Actual: OperationMode.shared`. Es `expect(await tester.runAsync(() => OperationModeStore(database).current()), OperationMode.personal)`, justo después de `waitFor(tester, find.textContaining('Usa inventario propio'))`.
- **Lo que siguió:** `Warning database has been locked for 0:00:10.000000` y `TimeoutException after 0:10:00`.

**«consulta posterior: muestra la vigente…»:** `'package:flutter_test/src/binding.dart': Failed assertion: line 2479 pos 12: '!inTest'`. No es una aserción de la prueba: el binding sigue ocupado por la prueba anterior, que agotó el tiempo.

Resumen del run: `2231 tests passed, 2 failed, 4 skipped`.

## 2. Comparación con la base

`c2ac44a` frente a su base `4ca2088`. Cada worktree se ejecutó por separado, en serie y sin otra suite. La instrumentación fue **temporal** (`print` con hora en el alta del titular, el guardado de la modalidad, el refresh del acceso, el reload del controlador, el guardián de estimación y `waitFor`) y se revirtió después.

| Comprobación | `4ca2088` | `c2ac44a` |
|---|---|---|
| La prueba, 5 ejecuciones | 5/5 | 5/5 |
| Vuelta de `waitFor` en que aparece «Usa inventario propio» | 5 en las 5 | 5 en las 5 |
| Orden en `c2ac44a` | — | vínculo guardado → modalidad aplicada → refresh → reload. El guardián actúa **después** de aplicar la modalidad (al cambiar el acceso) y no escribe |
| Archivo completo, 3 ejecuciones: `dispose` del contenedor con operaciones del guardián pendientes | — | 0 de 9 |

**Las cuatro preguntas:**
- **¿La base guarda una modalidad incorrecta?** No. Cuando el alta termina, guarda `personal` en las dos versiones.
- **¿La modalidad global queda desactualizada?** No. Tras el reload, el controlador tiene `personal`.
- **¿La interfaz se consulta antes de terminar?** **Sí, y está reproducido** (§3). `waitFor` no falla al agotar sus 150 vueltas: si el alta no terminó, la prueba sigue y lee la base antes de que se guarde la modalidad.
- **¿Hay tareas pendientes que interfieren entre pruebas?** **Sí, tras ese fallo prematuro.** Las operaciones pendientes del alta retienen la base en el cierre («database has been locked»), la prueba agota los 10 minutos y la siguiente falla por `'!inTest'`.

## 3. Reproducción controlada

**Coordinación de operaciones reales de SQLite.** Antes de confirmar el titular, la prueba abre una transacción en la base de la app y la retiene hasta después de la espera. El alta (`bindNewPerson`) queda esperando el cerrojo real. Prueba temporal: `f04_mode_onboarding/reproduccion.dart.txt`.

| Versión | Resultado |
|---|---|
| `c2ac44a`, con la espera original | «waitFor: NO encontrado tras 150 vueltas» → se libera el cerrojo → modalidad leída `shared` → **`Expected: personal, Actual: shared`** → «database has been locked for 0:00:10» → prueba colgada (6:36 hasta el límite) |
| `4ca2088`, base sin el guardián | **El mismo resultado:** `Expected: personal, Actual: shared`, «database has been locked», colgada (8:03) |
| Corrección, espera explícita | Falla a los 5 s con diagnóstico: «No terminó el alta del titular con inventario propio en 150 vueltas: acceso=activationPendingOwner, modalidad=shared, ruta=/titular.» No lee la base antes de tiempo |

**Conclusión:**
- **Lo que está demostrado:** la forma del fallo de la CI (aserción engañosa en la línea 61, base bloqueada y 10 minutos) es la de una prueba que sigue tras una espera agotada sin fallar. Ocurre igual con y sin el guardián de #164.
- **Lo que no se pudo confirmar:** **por qué** el alta tardó más de 150 vueltas en la CI de `main`. En local termina en 5 vueltas en las dos versiones. **No se atribuye al guardián:** no hay prueba de ello, porque añade las mismas vueltas que la base, es decir, ninguna. Tampoco se clasifica como preexistente: el fallo del 2026-11-01 en este archivo (`c98edc0`) fue en otro caso.

## 4. Corrección (solo en la prueba)

`test/operation_mode_onboarding_test.dart`: las dos esperas de la primera prueba pasan de `waitFor` a `waitUntil`, que falla con diagnóstico al agotarse.
- **Antes de elegir el titular:** que aparezca su pantalla.
- **Tras confirmar:** el **estado final** del alta, que es el acceso `activated`, la modalidad `personal` en el controlador y «Usa inventario propio» en pantalla.

El diagnóstico da el acceso, la modalidad y la ruta.

**Lo que no cambia:**
- el número de vueltas (150, el mismo de antes); no se añaden esperas fijas ni `skip`;
- las aserciones de la base (línea 61), del controlador y de la navegación;
- `lib/` y el guardián de las copias.

## 5. Resultados

**Prueba:** el archivo, 5 de 5 en local.

**Suite completa sobre la rama** (04:01:07Z–04:03:15Z): `flutter analyze` sin incidencias.

| Resultado | Pruebas |
|---|---|
| Correctas | 2233 |
| Omitidas | 3. Las mismas en todas las suites locales: dos centinelas del paso regional America/La_Paz y una de F06 con Central |
| Fallida | **1**, `f10_x01_pago_datos_test.dart`: «compra de hoy, "Sí, pagué todo"…» |

**Sobre la fallida:**
- **Lo que pasó:** tras confirmar la compra, el botón seguía (deshabilitado, guardando) cuando la prueba esperaba que se cerrara el formulario.
- **Sin relación con el cambio:** este cambio no toca ese archivo ni `lib/`.
- **Repeticiones:** la prueba sola pasó 3 de 3, y en la suite anterior sobre el mismo `lib/` (`095684e`) pasó.
- **Sin reproducir ni clasificar.** Su espera es `settle`, que termina cuando no ve indicadores de carga.
- **No se corrige aquí:** no es el fallo de la CI y no hay reproducción.

## 6. Límite

Si el alta sigue sin terminar en 150 vueltas, la prueba falla con el estado que tenía, y las operaciones pendientes de la app pueden retener la base en el cierre. Eso no se oculta: es la señal para diagnosticar.
