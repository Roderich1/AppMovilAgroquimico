# F04-MODE-03 (#26): flujos del modo propio sin duplicar dominio

Refs #26 y #27. Trazabilidad (Cap. III v1.5): RF-06, RF-11; CU-05, CU-08; RN-17.

El modo de uso y su persistencia (#24) y las transiciones seguras (#27) ya estaban integrados con #77, #78 y sus correcciones ([F04_ACTIVACION_TITULAR_MODO.md](F04_ACTIVACION_TITULAR_MODO.md), [F04_CORRECCIONES_REVISION.md](F04_CORRECCIONES_REVISION.md)). Esta entrega cubre lo que faltaba de #26: que la interfaz en inventario propio deje de ofrecer transferencias y la elección de responsables. La parte de #25 está en [F04_MOB_MODE_02_ONBOARDING_UX.md](F04_MOB_MODE_02_ONBOARDING_UX.md).

## Identidad de la ejecución

| Elemento | Valor |
|---|---|
| Fecha | 2026-10-17 |
| Rama | `feat/f04-modo-ui`, desde `main` `ce5678f89449453c60c3f1889cd6e973f09f6548` |
| Commits verificados | `db0b10a` (dominio y lecturas) y `7ac7153d5f7a37d143d3afa8ff693ea0d91afd79` (interfaz y pruebas) |
| Entorno | Windows 11 Home 10.0.26200, Flutter 3.47.2 (Dart 3.13.2) |
| Tipo de prueba | Pruebas de host y de widgets (`flutter test`, `sqflite_common_ffi`, app real con base en archivo). **Sin dispositivo** |
| Ejecución | Sesión A de Claude Code, por delegación técnica. Sin revisión de Roderich ni del tutor |

## Qué cambia

**Una modalidad reactiva para la presentación** (`lib/operation_mode_controller.dart`).
- La carga el router al crearse.
- Se recarga al cambiarla (Modo de uso, elección del titular) y al restaurar una copia (`GuardedRestore`), así que las pantallas abiertas cambian sin reiniciar.
- Sólo decide qué se muestra. El repositorio sigue leyendo modalidad y titular **dentro** de la transacción de cada escritura y rechaza lo que no corresponde, como desde #77.

**En inventario propio:**

| Lugar | Antes | Ahora |
|---|---|---|
| Operaciones | Tarjeta «Transferencias» | No aparece. «Modo de uso» dice «Ahora: inventario propio» y el subtítulo lo explica |
| Atajo «Nuevo» | Ofrecía «Transferencia» | No la ofrece |
| `/transferencias`, `/transferencias/nueva` abiertas directamente | Se abrían; el repositorio rechazaba al confirmar | Vuelven a `/operaciones` (`operationModeRedirect`) |
| Transferencias abierta al pasar a propio | Seguía abierta | Abierta con `go` (ruta base), el router reevalúa y vuelve a Operaciones, también si está debajo de Modo de uso. **Abierta con `push` desde la tarjeta de Operaciones** (el camino normal), go_router no cambia la ruta base y el redirect no la cierra: la propia pantalla deja de ofrecer acciones y ofrece «Volver a Operaciones» (corregido tras la revisión; ver abajo) |
| Nueva compra | Reparto por persona («Asignaciones») y pagador | Sin reparto ni pagador: la línea entera es del titular y paga el titular. Se muestra «Para el titular: …» y «Paga el titular: …» |
| Nueva aplicación | Selector «Persona» | Aplica el titular, que se muestra sin elegirlo; sólo sus chacos |
| Nueva planificación | Todos los chacos | Sólo los del titular |
| Pago al proveedor (Compras) | Selector «Pagador» | Paga el titular |
| Catálogos › Personas | «Agregar persona» | No se agregan responsables; un aviso explica cómo pasar a compartido. Las personas ya registradas siguen a la vista |
| Alta de chaco | Selector «Propietario» | Es del titular, sin elegirlo |
| Liquidación | «Registrar pago/adelanto» para cada persona | Sólo para el titular; para las demás, un aviso no seleccionable. El repositorio ya lo rechazaba sin escribir (corregido tras la revisión) |
| Formulario abierto cuando cambia la modalidad | Confirmaba con las opciones cargadas antes | Avisa y deshabilita «Confirmar» hasta volver a abrirlo; no guarda nada |

En compartido todo sigue igual. Un solo dominio y una sola base: no hay tablas, modelos ni rutas por modalidad.

**Lecturas sin consultas nuevas.** Los formularios necesitaban la modalidad y el titular. Una consulta extra antes de cargar dejaba 3 pruebas de formularios «cargando», porque su arnés concede poca E/S real. Igual que en `8e52fe1`, se corrigió el código y no las pruebas: `peopleAndContextFor` y `farmsAndContext` devuelven modalidad y titular en la misma consulta que ya leía personas o chacos.

## Defecto de dominio encontrado y corregido (`db0b10a`)

**Hallazgo:** en inventario propio, **revertir** una operación histórica de otra persona le devolvía actividad. Es justo lo que el paso a propio exige que no exista (CU-05, RN-17).

**Reproducción sobre `ce5678f`:** archivo temporal `test/zz_repro_reversal_test.dart`, `flutter test`, borrado después. Pasos: compra de 3000 para la hermana, consumo o transferencia de todo, pago de su cuenta y paso a propio. Luego:

| Operación en propio | Resultado observado |
|---|---|
| `reverseApplication` (aplicación de la hermana) | Sin error. Después, `stock3={2} balance3={2}`: la hermana con existencias y saldo |
| `reverseTransfer` (hermana → titular) | Sin error. `stock3={2}`: la hermana vuelve a tener existencias |
| `reversePurchase` (compra de la hermana, ya consumida) | Rechazada por la regla existente («La compra tiene lotes consumidos…») |

**Corrección:**
- `reverseApplication`: en propio sólo la del titular.
- `reverseTransfer`: en propio no hay transferencias, tampoco para deshacerlas.

Las guardas se leen dentro de la transacción, como las demás. En compartido no cambia nada. Con la corrección, las dos reversiones se rechazan sin cambios y la de compra sigue igual.

## Pruebas

| Archivo | Casos | Qué comprueba |
|---|---|---|
| `test/personal_mode_flows_test.dart` (nuevo) | 12 | **Navegación:** en propio, Operaciones y «Nuevo» sin transferencias; al pasar a compartido con la pantalla abierta, vuelven. Las dos rutas de transferencias abiertas directamente vuelven a Operaciones. Transferencias abierta, también debajo de Modo de uso, se cierra al pasar a propio. La pantalla, montada en propio, no ofrece acciones. **Formularios en propio:** la compra no muestra reparto ni pagador, tiene **menos campos que en compartido** y, confirmada por la interfaz, deja la asignación (4000) y el pago al titular. La aplicación no pide persona y sólo ofrece el chaco del titular; la planificación, también. Catálogos sin «Agregar persona» y alta de chaco sin propietario. Un formulario abierto al cambiar la modalidad avisa y deshabilita «Confirmar». **Compartido:** la transferencia ofrece origen y destino. **Dominio:** las dos reversiones de terceros se rechazan con volcado completo idéntico; la del titular se revierte; en compartido la transferencia se revierte |
| `test/f04_admin_owner_restore_ui_test.dart` | +1 | Restaurar desde Liquidación una copia del mismo Member que está en propio deja Operaciones en propio sin reiniciar |
| `test/f04_admin_owner_restore_ui_test.dart` | 1 cambiado | **Cambio de expectativa.** «propio con titular familiar: el titular paga al proveedor». Antes: el selector «Pagador» sólo ofrecía al titular. Ahora: no hay selector; se muestra «Paga el titular: Titular» y el pago registrado es del titular (`provider_payments.payer_person_id`). Se conserva que el otro administrador no paga |

Arnés común: `test/support/f04_mode_ui_harness.dart`. Monta la app real; sólo sustituye la sesión segura, la identidad, la sesión remota y el transporte HTTP. Ese transporte falla y cuenta las peticiones.

### Resultados (sobre `7ac7153`, 2026-10-17 13:38–13:40Z)

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 200 archivos, 0 cambiados |
| `flutter analyze` | `No issues found!` |
| `flutter test` | **1089 pasan, 2 omitidas, 0 fallos** |

**Fallos observados durante la construcción:**
- La primera suite completa dio 3 fallos: dos pruebas de `regression_widget_test` quedaron cargando por la consulta extra, y la del pagador en propio cambió de expectativa.
- Una sonda temporal con más E/S real (600 ms en lugar de 150 ms) pasó, lo que confirmó que era el tiempo del arnés.
- El controlador escribía su estado después de desmontarse (`UnmountedRefException`). Se corrigió con `ref.mounted`.
- La lectura inicial lanzada por el propio proveedor dejaba un temporizador pendiente en una prueba de formulario suelto. La lectura inicial pasó al router.

### Mutaciones (sobre `7ac7153`)

Procedimiento:
- cada mutación es un reemplazo exacto en `lib/` (debe aparecer una vez);
- después se ejecutaron `personal_mode_flows_test`, `operation_mode_onboarding_test` y `f04_admin_owner_restore_ui_test`;
- se restauró con `git checkout HEAD -- <archivo>`, con `git status --porcelain` vacío después de cada una.

| Id | Mutación | Resultado |
|---|---|---|
| N1 | El router no saca de las rutas de transferencias | detectada: 2 |
| N2 | «Nuevo» ofrece Transferencia en propio | detectada: 1 |
| N3 | Operaciones muestra Transferencias en propio | detectada: 4 |
| N4 | La compra en propio pide reparto y pagador | detectada: 2 |
| N5 | La aplicación en propio pide persona | detectada: 1 |
| N6 | Planificación ofrece chacos de terceros en propio | detectada: 1 |
| N7 | Catálogos permite agregar personas en propio | detectada: 1 |
| N8 | Un formulario abierto no detecta el cambio de modalidad | detectada: 1 |
| N9 | Modo de uso no recarga la modalidad | detectada: 1 |
| N10 | La elección del titular no recarga la modalidad | detectada: 1 |
| N11 | Restaurar no recarga la modalidad | detectada: 1 |
| N12 | En propio se revierte la aplicación de otra persona | detectada: 1 |
| N13 | En propio se revierte una transferencia | detectada: 1 |
| N14 | El bloqueo no nombra a quién tiene existencias | detectada: 3 |
| N15 | La pantalla de transferencias actúa en propio | detectada: 1 |

15 de 15 detectadas.

## Contraste con los criterios de #26

| Criterio | Evidencia | Estado |
|---|---|---|
| En propio, menú principal y formularios de compra o aplicación sin transferencia ni selección de responsables, y con menos pasos | `personal_mode_flows_test` (navegación; compra con menos campos; aplicación). Mutaciones N1–N5 | Cumplido en host |
| En compartido la transferencia sigue disponible con origen, destino, producto, cantidad, unidad y fecha efectiva | Navegación en compartido y formulario con «Persona origen». Las reglas de la transferencia no cambian (`f04_bug_01`, `f04_bug_02` y las pruebas de repositorio existentes siguen verdes) | Cumplido en host |
| Al cambiar de modo no se elimina ni se reasigna nada | `operation_mode_onboarding_test` (volcado de negocio idéntico); `f04_operation_mode_test` existente (ida y vuelta). Las reversiones en propio ya no devuelven actividad a terceros | Cumplido en host |
| Un único conjunto de tablas y modelos | Sin cambios de esquema; la modalidad sólo está en `app_settings` | Cumplido |

## Límites y decisiones declaradas

- **Sin dispositivo.** La comprobación en el POCO está pendiente: se hará en una sesión física dedicada, junto con la de #97.
- **Historial de transferencias en propio.** El listado de Transferencias no se muestra en propio. Los movimientos siguen en la base, el detalle de inventario muestra el origen «transferencia del lote #N» y el listado vuelve a verse al pasar a compartido. No se borra ni se reasigna nada.
- **Personas en propio.** La sección Personas y Catálogos › Personas siguen mostrando a todas las personas, con su historial, y permiten corregir nombres o archivar; sólo no se agregan responsables nuevos. En Liquidación se consultan y exportan los estados de cuenta de todos; registrar pagos o adelantos queda para el titular.
- **Al arrancar**, la modalidad se lee en paralelo con el acceso. Mientras no se conoce, la presentación es la de compartido, que es la modalidad por defecto; el repositorio aplica la real en cada escritura.
- **Cambiar de modalidad con Transferencias debajo de Modo de uso** lleva a Operaciones y cierra también Modo de uso. Por la interfaz no se llega a esa pila: es un caso de restauración o programático.

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-17.
- Revisión técnica del PR: la hace otra sesión antes de integrar.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.

## Correcciones tras la revisión de la sesión C (2026-10-17)

Revisión de `11c8c3e`: **LISTO**, con 4 hallazgos menores (`_briefs/ESTADO_C_BACKUP.md`). Corrección en `edab2d0`.

| Hallazgo | Tratamiento |
|---|---|
| En propio, Liquidación seguía ofreciendo «Registrar pago/adelanto» a otras personas. El repositorio lo rechazaba sin escribir, pero esta evidencia decía «Liquidación no cambia» | Corregido. El titular se lee en paralelo con el resto de la pantalla, sin otra espera en cadena; las pruebas de Liquidación con arnés estrecho siguen verdes. Prueba nueva «liquidación: pagos y adelantos sólo del titular» y **mutación N16** (se ofrecen a todos): detectada, 1 fallo |
| Con `push` desde Operaciones el redirect no cierra Transferencias: la pantalla se defiende sola y esta evidencia lo describía mal | Corregido el texto (tabla de arriba). Prueba nueva del camino `push` → aviso → «Volver a Operaciones». `currentPath()` del arnés documenta que es la ruta base |
| Al arrancar, mientras la modalidad aún vale `null`, el shell ofrece Transferencia | Ya declarado en los límites; sin cambio |
| La prueba del pagador en el formulario ya no lee `payer_person_id` | Lo comprueba en la base el caso de compra de `personal_mode_flows_test` |

**Resultados sobre `edab2d0` (2026-10-17):**
- `dart format`: 0 cambiados.
- `flutter analyze`: sin issues.
- `flutter test`, primera corrida (14:03–14:04Z): **1090 pasan, 1 falla, 2 omitidas.** Falló el primer caso de `operation_mode_onboarding_test` con el PC muy cargado; aislado pasó 3 de 3.
- `flutter test`, segunda corrida: **1091 pasan, 2 omitidas, 0 fallos.**

Se conserva la falla intermitente. La prueba se endureció con esperas explícitas a la pantalla del titular y al mensaje de transición, en lugar de pausas fijas.

`personal_mode_flows_test` pasa a tener **14 casos**.

