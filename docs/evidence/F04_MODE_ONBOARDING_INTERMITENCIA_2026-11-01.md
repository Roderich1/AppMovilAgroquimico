# `operation_mode_onboarding_test`: causa de la intermitencia y corrección de la prueba

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01 (UTC), entre las 20:05Z y las 20:58Z |
| Base | Mobile `main` `c98edc0` |
| Rama | `test/f04-mode-onboarding-sincronizar` |
| Procedencia | **HOST**: Windows 11 Home 10.0.26200, Flutter 3.47.2 y SQLite por `sqflite_common_ffi` |
| Alcance | Solo infraestructura de prueba: `test/operation_mode_onboarding_test.dart` y `test/support/f04_mode_ui_harness.dart`. No se toca `lib/` |
| Relación | Desbloquea el cierre de MOB #170 y #171, detenido por la CI de `main` en `c98edc0` (run 41342822654) |

## 1. Fallos observados

| Fecha | Dónde | Línea | Mensaje |
|---|---|---|---|
| 2026-10-27 | Local, con otra suite en paralelo (tres veces) | 160 | 0 widgets con «Ahora usa inventario…»; después, `database_closed` |
| 2026-11-01 | CI, run 41333943248 intento 1 (PR #175, `37cc7c6`) | 164 | 0 widgets con «Modalidad actual: inventario compartido» |
| 2026-11-01 | CI de `main`, run 41342822654 intento 1 (`c98edc0`) | 160 | 0 widgets con «Ahora usa inventario compartido». Después: `Error mostrado al usuario \| error: Bad state: Tried to read a provider from a ProviderContainer that was already disposed` |

Ninguno de esos commits cambiaba la prueba ni `lib/`.

## 2. Causa demostrada

**El flujo de la app.** Al tocar «Confirmar», `_change` de `OperationModeScreen` (`lib/presentation/screens/operation_mode_screen.dart`) hace, en orden:
1. `setState(_saving = true)`, que solo desactiva «Cambiar…» y **no muestra indicador de carga**;
2. `_store.apply(...)`, una transacción sqflite con E/S real (línea 86);
3. `ref.read(operationModeProvider.notifier).reload()`, otra lectura real (línea 88);
4. el aviso «Ahora usa inventario compartido…»;
5. `setState(_current = _store.current())`, una relectura real. `FutureBuilder` conserva mientras tanto el dato anterior («propio»), también **sin indicador**.

Antes, tocar «Cambiar…» ejecuta `_store.evaluate(...)`, que también es E/S real sin indicador, y solo después abre el diálogo.

**La espera de la prueba.** Tras cada toque, la prueba usaba `settle` del arnés. Esa función sale en cuanto pasan 8 vueltas sin `CircularProgressIndicator`. Como este flujo no lo muestra nunca, `settle` daba siempre 9 vueltas de 20 ms reales, unos 180 ms, más un `pump` de 300 ms, y la prueba miraba:
- **línea 160:** falla si `apply` o `reload` no han terminado;
- **línea 164:** falla si falta la relectura;
- **línea 154:** si `evaluate` no ha terminado, el diálogo no existe todavía.

**Quién desecha el `ProviderContainer`.** Lo desecha el arnés: `pumpModeApp` registra `addTearDown(container.dispose)`. Cuando la prueba falla con `_change` a medias:
1. ese teardown desecha el contenedor **con la pantalla todavía montada**;
2. la operación pendiente continúa;
3. su `ref.read(operationModeProvider.notifier)` (línea 88) lanza `StateError`;
4. el `on Object catch` (línea 116) lo muestra con `showError`, que lo registra como «Error mostrado al usuario».

**Por qué no es un defecto de la app.** En la app, el contenedor es el del `ProviderScope` raíz (`lib/main.dart:37`) y solo se desecha al desmontar ese mismo árbol. Desecharlo con una pantalla montada es un orden que solo produce el teardown de esta prueba. No se ha demostrado ningún defecto del código funcional.

## 3. Reproducción controlada

Se usaron copias temporales del caso, sin versionar y borradas después. El generador está en el scratchpad de la sesión (`mk_onb_probes.py`).

**Cómo se retrasa la operación.** Antes del toque elegido, la prueba abre una transacción real sobre la misma base y la retiene (`db.transaction((txn) => release.future)`). Como sqflite serializa las operaciones, la de la pantalla espera detrás de ella el tiempo indicado. No se toca `lib/`.

Cada sonda se ejecutó con `timeout 300 flutter test <sonda>`.

| Sonda | Condición | Versión anterior (`c98edc0`) | Versión corregida |
|---|---|---|---|
| A | Transacción retenida 400 ms reales antes de «Confirmar» | **Falla** en la aserción de la línea 160: `Found 0 widgets with text containing Ahora usa inventario compartido`. Después se queda colgada en el teardown hasta el límite de 300 s (salida 124), porque el trabajo pendiente no se drena antes de cerrar la base | **Pasa** (2 s) |
| B | Transacción retenida 400 ms antes de «Cambiar a inventario compartido» | **Falla** en la línea 154: `Bad state: No element` al buscar el diálogo. Después se cuelga igual | **Pasa** (2 s) |
| C | Transacción **no liberada** durante la prueba; la sonda la libera en su teardown | — | **Falla explícitamente** en 6 s: «No terminó el cambio de modalidad (guardar, recargar y releer) en 150 vueltas: cambio en curso: true; modalidad mostrada: Modalidad actual: inventario propio.». **Ningún** `Bad state` del contenedor y sin colgarse |
| D | Como A, pero liberada en un teardown que corre **después** de `container.dispose`, y luego se avanza la prueba | **Falla** en la línea 160, y el registro muestra `Bad state: Tried to read a provider from a ProviderContainer that was already disposed`, como en la CI de `main`. La pantalla seguía montada (1) al desechar el contenedor | — |

Repeticiones, todas con el mismo resultado cada vez:
- A y B corregidas: 2 veces cada una;
- C: 3 veces;
- D: 2 veces;
- A y B anteriores: 1 vez cada una en esta forma, más una primera variante de A (sin teardown de liberación) que falló igual en la línea 160 y registró el mismo `Bad state`.

## 4. Corrección

**`waitUntil(tester, what, done, {state, rounds = 150})`**, nueva en el arnés:
- avanza como `waitFor` (20 ms reales y 20 ms simulados por vuelta) hasta que `done()` se cumpla;
- si no se cumple, `fail('No terminó <what> en <rounds> vueltas: <state>.')`.

Las demás pruebas del arnés no cambian.

**En el caso que fallaba:**
- **Tras «Cambiar a inventario compartido»:** espera a que exista el diálogo (`mode-consequence`), en lugar de `settle`.
- **Tras «Confirmar»:** espera a que el cambio termine, en lugar de `settle`. Termina cuando «Cambiar…» vuelve a estar activo (`_saving = false`, al final de `_change`, bien o mal) **y** la modalidad mostrada ya no es la anterior, es decir, la relectura está hecha.
- **Teardown de drenaje:** se registra después de `pumpModeApp`, así que corre **antes** de `container.dispose`. Si la prueba falla con el cambio a medias, lo deja terminar con el mismo límite para que no lea un contenedor ya desechado. Si no termina, también falla con diagnóstico.

**Se conservan todas las aserciones**, sin cambios. No hay esperas fijas nuevas, ni skips, ni capturas de excepciones, ni expectativas modificadas.

## 5. Comprobación local

```text
dart format --output=none --set-exit-if-changed (los dos archivos)    → 0 cambios
flutter analyze lib test                                              → No issues found!
flutter test test/operation_mode_onboarding_test.dart (5 veces)       → +3, 5 de 5
flutter test (los 15 archivos que usan f04_mode_ui_harness.dart)      → +89, todas superadas
```

La suite completa se decide en la CI del PR.

## 6. Revisión

Otro agente de esta misma sesión hizo una lectura de contraste del diff, sin recibir estas conclusiones; no es una revisión independiente. **No encontró bloqueantes.**

**Coincidencias con la causa de §2:**
- el `Bad state` sale de la línea 88;
- `reload()` atrapa sus propios errores;
- el teardown del arnés desecha el contenedor y la pantalla sigue montada.

**Comprobaciones:**
- Las 11 aserciones del caso se conservan sin cambios.
- La espera tras «Confirmar» no puede cumplirse antes de tiempo: cuando se cumple, el aviso ya está en el árbol.
- El drenaje corre antes de `container.dispose`, `database.close` y `postTest`.

**Hallazgos menores:**

| Hallazgo | Qué se hizo |
|---|---|
| El comentario del drenaje prometía más: no espera la relectura final | Corregido |
| El diagnóstico debía incluir el aviso o el bloqueo visibles | Añadido |
| `waitFor` sigue sin fallar al agotarse | Es anterior y no se toca |
| La condición presupone que se parte de «propio» | Es cierto en este caso y lo dice el código |

## 7. Hallazgo aparte: defecto del código funcional (reproducido, NO corregido)

Lo señaló la revisión y se reprodujo en HOST. Corregirlo queda fuera de la autorización de este cambio, que cubre solo la infraestructura de prueba.

**El defecto.** Si el usuario sale de «Modo de uso» mientras se guarda el cambio de modalidad:
- **Lo que muestra la sonda:** la base queda con la modalidad nueva, pero `operationModeProvider` y la presentación siguen con la anterior, sin ningún aviso ni registro. Así queda hasta otra recarga, por ejemplo al reiniciar la app.
- **Lo que se deduce del código, sin excepción registrada que lo confirme:** `_change` continúa tras `_store.apply` con la pantalla ya desmontada. El `ref.read(operationModeProvider.notifier)` de la línea 88 se rechaza: Riverpod 3.4.2 no admite usar `ref` de un widget desmontado. `on Object catch` sale por `if (!mounted) return;` sin mostrar ni registrar nada.

**Reproducción** (sonda temporal `zz_probe_salir_test.dart`, guardada en el scratchpad de la sesión):
1. Desde «propio», se retiene una transacción real.
2. Se toca «Confirmar» para pasar a compartido.
3. Se vuelve atrás con `router.pop()`.
4. Se libera la transacción y se avanza.

Salida:

```text
PROBE guardando: cambio en curso: true; modalidad mostrada: Modalidad actual: inventario propio; avisos: []
PROBE pantalla de modo montada: 0
PROBE base: OperationMode.shared; operationModeProvider: OperationMode.personal
PROBE Operaciones muestra Transferencias: 0
```

Con la base en compartido, «Operaciones» debería mostrar «Transferencias».

**Propuesta, a decidir por Roderich.** En `_change`, tomar `ref.read(operationModeProvider.notifier)` **antes** de `await _store.apply(...)` y llamar a su `reload()` aunque la pantalla se haya desmontado. Solo lo que toca la pantalla, el aviso y `setState`, debe seguir condicionado a `mounted`. El controlador vive en el contenedor raíz, así que la recarga es válida.

Acompañaría una prueba de regresión basada en esta sonda.

## 8. Límites

- **Otros puntos con el mismo patrón.** En el mismo archivo, el caso «consulta posterior…» también usa `settle` tras «Cambiar», con E/S sin indicador (`evaluate` y `describe`). No se ha observado fallando y no se cambia aquí.
- **Lo que no demuestra la reproducción.** Retener una transacción fija el *mecanismo* (operación pendiente más una espera fija), no la causa exacta de la lentitud en el runner de la CI.
