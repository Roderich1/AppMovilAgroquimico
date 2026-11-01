# F04-MODE-05 (MOB #178): salir de «Modo de uso» durante el guardado

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01 (UTC), entre las 21:40Z y las 22:07Z |
| Base | Mobile `main` `b35de08` |
| Rama | `fix/f04-mode-recarga-al-salir` |
| Código verificado | `b1b586b` (corrección y regresión). Es el mismo árbol que `6412f76`, que no llegó a publicarse; solo se corrigió el mensaje del commit |
| Procedencia | **HOST**: Windows 11 Home 10.0.26200, Flutter 3.47.2 y SQLite por `sqflite_common_ffi`. **Sin DEVICE** (§6) |
| Issue | Refs #178. No se cierra con este trabajo |
| Trazabilidad | RF-06, RF-11, CU-05, CU-08 |

## 1. Defecto

En `OperationModeScreen._change` (`lib/presentation/screens/operation_mode_screen.dart`), la modalidad global se recargaba **después** de guardar y con el `ref` de la pantalla:

```dart
await _store.apply(target, confirmed: true);
await ref.read(operationModeProvider.notifier).reload();
if (!mounted) return;
```

Si el usuario salía de la pantalla mientras se guardaba:
- la base quedaba con la modalidad nueva;
- `operationModeProvider` seguía con la anterior, de modo que la navegación, los atajos y los formularios no cambiaban hasta otra recarga, por ejemplo al reiniciar la app;
- no aparecía ningún aviso.

Con la pantalla desmontada, ese `ref.read` lanza un `StateError` («Using "ref" when a widget is about to or has been unmounted», según el código de `flutter_riverpod` 3.4.2, `consumer.dart`, también en release; no aparece en ningún registro porque se capturaba). `on Object catch` lo capturaba y salía por `if (!mounted) return;` sin mostrar ni registrar nada.

## 2. Corrección

```dart
if (!confirmed || !mounted) return;
final modes = ref.read(operationModeProvider.notifier);
setState(() => _saving = true);
try {
  await _store.apply(target, confirmed: true);
  await modes.reload();
  if (!mounted) return;
  showSuccess(...);   // sólo con la pantalla montada
  setState(...);      // sólo con la pantalla montada
```

**Alcance:** 5 líneas de código y un comentario en un solo método. Sin cambios en `OperationModeStore` (reglas y guardas de la transición), en el controlador, en el router ni en otras pantallas. Sin retrasos ni ganchos de prueba.

**Por qué el controlador capturado sigue siendo válido:**
- **Es un objeto del contenedor raíz.** `operationModeProvider` es un `NotifierProvider` sin `autoDispose`, y su `build()` no observa nada. En `lib/` nadie lo invalida ni lo recrea; solo se llama a `reload()`, desde la app, la elección de titular, la restauración y esta pantalla. Su instancia dura lo que el contenedor raíz (`ProviderScope` de `main.dart`), es decir, toda la vida de la app, y no depende de la pantalla.
- **Se toma con la pantalla montada.** Se lee justo después de `if (!confirmed || !mounted) return;`.
- **Ya hay un precedente.** `GuardedRestore` (`lib/guarded_restore.dart:85`) toma el mismo controlador antes de una espera larga y lo recarga después.
- **`reload()` tolera un contenedor desechado.** Atrapa sus errores y solo escribe `state` si `ref.mounted`. Un contenedor desechado solo ocurre al cerrar la app o en el teardown de una prueba; incluso entonces no lanza.
- **No hay más accesos tras las esperas.** El resto de `_change`, y `_blockedText` con su getter `_store`, que hace `ref.read`, solo se usan después de comprobar `mounted`.

## 3. Regresión determinista

`test/operation_mode_leave_during_save_test.dart` usa la app real con el arnés de modalidad, sin red. El contenedor raíz sigue vivo durante toda la reproducción: la app no se reinicia.

**Cómo se alarga el guardado:** se retiene una transacción real de la misma base. sqflite atiende las transacciones en orden, así que la del cambio espera detrás. Las esperas de la prueba son condiciones con límite que fallan con diagnóstico: una transacción de control avisa cuando le toca, sin retrasos fijos. Un teardown suelta lo retenido y deja terminar lo pendiente antes de desechar el contenedor.

| Caso | Pasos | Se comprueba |
|---|---|---|
| Salir, propio → compartido | Confirmar → escritura retenida → volver atrás → soltar | La base queda en compartido. `operationModeProvider` = compartido. «Operaciones» ofrece «Transferencias» y `/transferencias` se abre |
| Salir, compartido → propio | Igual | La base queda en propio. `operationModeProvider` = propio. Sin «Transferencias», y `/transferencias` vuelve a `/operaciones` |
| Salir y guardado rechazado | Tras el diálogo aparecen existencias de un tercero → confirmar → retenida → volver → soltar | La base y la modalidad global siguen en compartido. Ningún «Ahora usa…». La navegación sigue en compartido |
| Quedarse, compartido → propio | Confirmar | Aviso «Ahora usa inventario propio», modalidad mostrada propio, base y modalidad global en propio, navegación de propio |
| Quedarse y guardado rechazado | Existencias de un tercero antes de confirmar | Se muestra el bloqueo «Existencias de Hermana…». Ningún «Ahora usa…». Mostrada, guardada y global siguen en compartido |
| Quedarse y guardado fallido | Restauración en curso (`replacement.replace`) | Error «Se está restaurando un respaldo…». Ningún «Ahora usa…». Mostrada y global en compartido, guardada en compartido |

Propio → compartido quedándose ya lo cubre `operation_mode_onboarding_test` («propio → compartido con historial…»). Las guardas sobre datos de terceros las cubren el caso de bloqueo de ese archivo y las pruebas de `personal_mode_flows_test`.

## 4. Resultado antes y después

```text
flutter test test/operation_mode_leave_during_save_test.dart
```

| Código | Resultado |
|---|---|
| `b35de08` + prueba nueva (sin corrección) | **2 fallidas de 6**. Fallan los dos casos de salir: «No terminó la recarga de la modalidad global tras salir en 150 vueltas: operationModeProvider: OperationMode.personal; guardada: OperationMode.shared.», y su inverso. Los otros 4 pasan |
| `6412f76`/`b1b586b` (con corrección) | **6 de 6**, en 3 ejecuciones seguidas. En el registro solo aparece el error esperado del caso de restauración en curso; ningún acceso a un contenedor o widget desechado |

## 5. Otras comprobaciones (HOST)

```text
dart format --output=none --set-exit-if-changed lib test        → 0 cambios
flutter analyze lib test                                        → No issues found!
flutter test operation_mode_leave_during_save_test.dart
             operation_mode_onboarding_test.dart                → +9
flutter test (25 archivos: arnés de modalidad, operationModeProvider,
             OperationModeScreen, restauración guardada)        → ver abajo
```

**La tanda de 25 archivos** dio 1 fallo en cada ejecución con la corrección, y siempre en archivos que no usan la pantalla de modo de uso:
- `f04_admin_owner_restore_ui_test`, que sola pasó 7 de 7;
- `f08_prev_01_previo_ui_test`, línea 390.

**La misma tanda sobre `main` sin la corrección** (24 archivos, sin la prueba nueva, en el mismo equipo) falló 1 de 2 veces en `f08_prev_01_previo_ui_test`, línea 435: «Decidir» todavía no estaba en la pantalla cuando se tocó. Son intermitencias previas bajo carga, ajenas a este cambio. La de `f08_prev_01_previo_ui_test` es una espera fija tras montar la pantalla, distinta de la corregida en #175, y queda pendiente aparte. La suite completa la decide la CI.

## 6. Revisión

Otro agente de esta misma sesión hizo una lectura de contraste del commit, sin recibir estas conclusiones; no es una revisión independiente. **No encontró bloqueantes.**

**Validez del controlador capturado.** No hay `ProviderScope` anidados, ni `invalidate` o `refresh` sobre `operationModeProvider`. `reload()` no lanza aunque el contenedor esté desechado: captura `UnmountedRefException` y escribe `state` solo con `ref.mounted`.

**Restauración durante el guardado.** `replace()` espera a que terminen las escrituras activas. El `reload()` de la pantalla espera con `whenReadable()` y lee la base restaurada. No hay estado obsoleto.

**Accesos tras las esperas.** No quedan accesos a `ref` ni a `context` sin comprobar `mounted` en `_change` y `_blockedText`.

**La prueba.**
- Es determinista: el `Lock` de sqflite_common es FIFO.
- El orden de los teardowns es correcto y no hay cuelgues posibles.
- Ninguna espera puede cumplirse antes de tiempo.
- El revisor la repitió por su cuenta: 6 de 6 tres veces con la corrección, y con la pantalla de `b35de08` fallan exactamente los dos casos de salir.

**Hallazgos menores y tratamiento:**

| Hallazgo | Tratamiento |
|---|---|
| El mensaje del commit no decía que el `ref.read` lanzaba un `StateError` antes de `if (!mounted) return;` | Corregido en el mensaje (`b1b586b`) y en el §1 |
| «Rechazo tras salir» pasa también sin la corrección y no comprueba que se tomara el camino de `ModeTransitionException` | Declarado: es una guarda de «no anunciar ni cambiar», no detecta el defecto |
| Cobertura en pantalla: falta propio → compartido quedándose en este archivo; falta un error genérico después de salir y una restauración encolada durante el guardado; las guardas de planes, saldos y titular solo se prueban en el almacén | Declarado. Propio → compartido quedándose lo cubre `operation_mode_onboarding_test`. Las guardas no cambian y siguen cubiertas en `test/f04_operation_mode_test.dart` |
| Defecto previo, fuera de alcance: si una restauración se cuela entre guardar y recargar con la pantalla montada, se anuncia «Ahora usa…» aunque la base restaurada traiga otra modalidad (la modalidad global sí queda bien) | Pendiente aparte |
| Mismo patrón en `owner_setup_screen.dart:187` (recarga de la modalidad tras la elección del titular) y en `remote_backup_screen.dart:265` (`refreshSummary` fuera del `try` tras restaurar) | Pendiente aparte; no se reproducen ni se cambian aquí |

## 7. DEVICE: no realizado

Se intentó preparar un recorrido normal en el POCO (`22101320G`) con un paquete aislado nuevo (`.mod1`) y una cuenta sintética nueva (`u3-mod`) en el Central propio.
- **Rechazo:** el **clasificador de permisos rechazó abrir el túnel temporal** (`av.sh tunnel`) sin dar motivo. Sin túnel no se puede activar el paquete. Como dispone la regla del proyecto, se registra y **no se buscó otra vía**.
- **Lo que llegó a hacerse:** se arrancó el Central (13 migraciones, API con health 200) y se añadió `u3-mod`, que queda en el volumen `agro_a_av_pgdata`. No se compiló ni se instaló ninguna APK, y el teléfono no se tocó.
- **Cierre:** el Central y Docker Desktop se detuvieron.

No hay, por tanto, recorrido en teléfono ni reproducción física de la carrera.

## 8. Límites

- Solo HOST.
- La reproducción retiene una transacción para abrir la ventana de la carrera. En un teléfono, el guardado suele durar milisegundos.
- **Mismo patrón, fuera del alcance de #178:** `owner_setup_screen.dart:187` y `remote_backup_screen.dart:265` (§6). No se han reproducido; quedan señalados para revisión aparte.
