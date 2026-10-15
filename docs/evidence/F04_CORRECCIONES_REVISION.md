# F04 — Correcciones de la revisión de PR #77 y PR #78

Refs #76, #24, #27 y #28. Registro de las correcciones pedidas por Roderich Rendón el 2026-10-15 al revisar #77 y #78. Las evidencias anteriores se conservan sin cambios de resultados: [F04_ACTIVACION_TITULAR_MODO.md](F04_ACTIVACION_TITULAR_MODO.md) (partes 1 y 2). Donde una afirmación anterior resultó incorrecta, se marca allí con una nota que remite aquí.

Ejecución con Claude Code en el entorno de desarrollo (Windows 11 Home 10.0.26200, Flutter 3.47.2, Dart 3.13.2). Pruebas de host y de widgets, sin dispositivo.

## Parte A — #77 (dominio y datos)

### A.1 Hallazgos y reproducción

| Id | Hallazgo | Reproducción sobre `b90c6289ec29608b45acaef9663aadbb66f0f07d` |
|---|---|---|
| R1 | Las guardas de modo propio leían modalidad y titular **fuera** de la transacción que escribe | Compra asignada a un tercero, concurrente con `OperationModeStore.apply(PERSONAL)`: `mode=OperationMode.personal purchaseError=null modeError=null stock={(3, 1): 1000}`. Las dos se confirmaron: modo propio con existencias del tercero |
| R2 | El titular se restringía a `FAMILY`: el agricultor histórico registrado como `ADMIN` local no podía ser titular | `bindExistingPerson` con la persona ADMIN: `OwnerBindingException: El titular debe ser una persona de la familia, no un administrador de pagos ni un tercero…` |

La parte 1 decía que la lectura fuera de la transacción «no tiene carrera práctica». **Era incorrecto**: R1 la reproduce con el planificador normal de sqflite, sin ganchos.

Comando de las dos reproducciones: `flutter test test/zz_repro_test.dart`, con un archivo temporal que se borró después de ejecutar. Las regresiones versionadas de A.3 cubren los mismos casos.

### A.2 Corrección

- **Tres nociones separadas** (`lib/domain/person_roles.dart`):
  - titular: el vínculo con el Member;
  - rol privado de negocio: `persons.role`, que decide cargos, pagos y liquidación;
  - rol central de seguridad: el de la cuenta en el servicio, que no vive en `persons` ni concede acceso a operaciones privadas.
- **Titular `ADMIN` con tratamiento explícito.**
  - `ownerEligibility`: `FAMILY` es elegible; `ADMIN` exige confirmación (`OwnerAdministratorConfirmationRequired`); `THIRD_PARTY` no es elegible.
  - `bindExistingPerson` y `changeOwner` aceptan `confirmAdministrator`.
  - `owner_bindings.owner_role` (`FAMILY`/`ADMIN`) registra con qué rol se aceptó al titular. El disparador lo hace inmutable.
  - No cambia `persons.role` ni `settlement_policy`, no crea otra persona y no reasigna movimientos.
  - Las reglas de costos (`MANUAL`: sin cargos), pagos y liquidación se conservan.
- **Formularios.** `canActAs`/`eligiblePeople` y `AgroRepository.peopleFor(purpose)` deciden quién se ofrece en cada formulario:
  - En compartido se conservan las reglas por rol, y el titular `ADMIN` puede además aplicar y transferir.
  - En propio sólo actúa el titular, también como pagador.
  - `peopleFor` lee personas, modalidad y titular en una sola consulta.
- **Carrera.** Toda escritura de `AgroRepository` pasa por `_write`: compuerta y luego lectura de modalidad y titular **dentro** de la transacción que escribe. `OperationModeStore.apply` ya evaluaba y escribía en la suya; SQLite serializa las dos.
- **Modo propio.** El pago al proveedor lo registra el titular (guarda nueva en `addProviderPayment`).

Commits:

- `731750e6ebce305f4c7406ad236328f84afa605b` (corrección);
- `8e52fe1e87e2eb21317d4ac877424fa41474a8f0` (`peopleFor` y `operatingContext` en una sola consulta).

### A.3 Pruebas nuevas o cambiadas

| Archivo | Casos | Qué comprueba |
|---|---|---|
| `f04_mode_race_test.dart` (nuevo) | 9 | Cuatro escrituras que crean actividad de terceros (compra, transferencia, plan y pago de cuenta), concurrentes con el paso a propio y en los dos órdenes de inicio: nunca se confirman las dos; en modo propio no queda actividad de terceros. También una compra iniciada en propio con el paso a compartido a la vez |
| `f04_historical_admin_owner_test.dart` (nuevo) | 7 | Base **v7 real** migrada, con el agricultor ADMIN. Sin confirmación, rechazo y volcado idéntico. Con confirmación, vínculo `owner_role=ADMIN`, persona con `role=ADMIN` y `MANUAL`, todas las demás tablas idénticas fila por fila y sin duplicar personas. En compartido el titular compra, aplica en su chaco, transfiere y paga: existencias 8000/12000/5000; su cuenta sigue vacía; las cuentas de los demás no cambian; asignación `MANUAL`; fuera de la liquidación. En propio, un agricultor solo registrado como ADMIN compra, paga y aplica (4000) y no transfiere. Cambio de titular a ADMIN con confirmación. Matriz de `canActAs` |
| `f04_owner_binding_test.dart` | 3 cambiados | Columna `owner_role` en el vínculo. ADMIN exige confirmación y un tercero se rechaza aun con ella. La inmutabilidad se prueba por columna y también **junto a un cierre válido**. El segundo vínculo activo se inserta como fila completa y debe fallar por `UNIQUE` |
| `f04_repository_guards_test.dart` | +1 | Pago al proveedor por otra persona en propio: rechazado sin cambios; el titular familiar sí paga |

### A.4 Resultados

| Sobre | Comando | Resultado |
|---|---|---|
| `731750e` | `dart format --output=none --set-exit-if-changed lib test` | 129 archivos, 0 cambiados |
| `731750e` | `flutter analyze` | `No issues found!` |
| `731750e` | `flutter test` | PASS 779/779 (762 previas + 17 nuevas) |
| `8e52fe1` | las mismas tres | 129 archivos, 0 cambiados · `No issues found!` · PASS 779/779 |

### A.5 Mutaciones

Cada mutación se aplicó con un reemplazo exacto en `lib/`. Después se ejecutaron las pruebas indicadas y se restauró el archivo con una copia byte a byte, comprobando su SHA-256. La primera tanda corrió sobre el árbol que se confirmó como `731750e`; la tanda final, sobre `8e52fe1`.

| Mutación | Pruebas | Resultado |
|---|---|---|
| A1 contexto leído fuera de la transacción (el defecto R1) | `f04_mode_race_test` | detectada: 4 fallos |
| A2 el titular ADMIN deja de aplicar en compartido | `f04_historical_admin_owner_test` | detectada: 2 |
| A3 modo propio admite transferencias del titular | `f04_historical_admin_owner_test` | detectada: 2 |
| A4 ADMIN aceptado sin confirmación explícita | `f04_owner_binding_test`, `f04_historical_admin_owner_test` | detectada: 3 |
| A5 un tercero aceptado como titular | `f04_owner_binding_test` | detectada: 1 |
| A6 el vínculo guarda siempre `FAMILY` | `f04_historical_admin_owner_test` | detectada: 2 |
| A7 pago al proveedor de otra persona en propio | `f04_repository_guards_test` | detectada: 1 |
| A8 `owner_role` mutable en el disparador | `f04_owner_binding_test` | detectada: 1 (en la primera tanda sobrevivió; ver abajo) |
| A9 `member_id` mutable en el disparador | `f04_owner_binding_test` | detectada: 1 |

**Observado en la primera tanda:** A8 (`owner_role` deja de ser inmutable) **sobrevivió**. Las pruebas de inmutabilidad modificaban un vínculo activo sin cerrarlo, de modo que siempre lo rechazaba la condición «vínculo activo» y nunca la comprobación de cada columna. La misma debilidad afectaba a las columnas de la parte 1. Se reforzó la prueba (cada cambio también junto a un cierre válido) y se añadió A9 (`member_id` mutable). Después las dos quedaron detectadas.

### A.6 Limitaciones de la parte A

- `THIRD_PARTY` sigue sin poder ser titular: un tercero no es el agricultor dueño de los datos.
- En propio, un titular `FAMILY` acumula cargos por uso (`BY_ACTUAL_USAGE`) frente a sí mismo. Es la regla de costos existente y no se cambió.
- En compartido el pagador sigue siendo sólo `ADMIN` (regla existente). Una instalación nueva cuyo titular es familiar necesita una persona administradora para pagar en compartido.
- Sin pruebas en dispositivo.

## Parte B — #78 (arranque, interfaz y restauración)

### B.1 Hallazgo y reproducción

| Id | Hallazgo | Reproducción sobre `abfcd26` (#78 con las correcciones de #77) |
|---|---|---|
| R3 | Restaurar desde Liquidación refrescaba los datos, pero no recalculaba `installationAccessProvider`; además no comprobaba de quién era la copia ni excluía escrituras durante la sustitución | Base vinculada a A, sesión legible de A, restauración de una copia vinculada a B por el mismo camino que la pantalla. Resultado: `vínculo=B estado=InstallationAccessState.activated reclasificado=InstallationAccessState.identityMismatch errorEscritura=null`. A escribió sobre los datos de B con la autorización anterior |

Comando: `flutter test test/zz_repro_test.dart`, con un archivo temporal que se borró después de ejecutar. Las regresiones de B.3 recorren el camino real.

### B.2 Corrección

- **Exclusión** (`lib/data/database_replacement.dart`, en `AppDatabase.replacement`):
  - Las escrituras en curso terminan antes de sustituir la base.
  - Durante la sustitución ninguna escritura nueva entra (`DatabaseReplacementInProgressException`): repositorio, modalidad, vínculo de titular y copia de fotografías.
  - Las lecturas esperan a que termine.
  - La compuerta del repositorio se consulta ya dentro de la exclusión.
- **Propiedad antes de reemplazar** (`BackupService.readOwnership`/`inspectOwnership` y `lib/domain/restore_ownership.dart`):
  - Se lee el titular que declara la base del respaldo, la misma que se va a copiar.
  - Se rechaza una copia de otro Member o tenant (frente al vínculo actual o a la sesión legible).
  - Se rechaza una de una activación sin terminar.
  - Se rechaza una cuya propiedad no se puede leer.
  - La base y las fotografías actuales quedan intactas y no se crea copia previa.
  - Una copia anterior a v8 se restaura como histórica, sin titular.
  - Sin sesión legible, una copia del mismo Member activada en otra instalación queda en `restoredRequiresActivation`: restaurar no demuestra identidad.
- **Recálculo** (`GuardedRestore`, `InstallationAccessController.recomputeAfterReplacement`):
  - La autorización se recalcula con la base resultante dentro de la exclusión, antes de volver a admitir escrituras.
  - Si falla, el estado queda `null` y la compuerta falla cerrada. Nunca se conserva la autorización de la base anterior.
  - También se recalcula tras un rechazo o un rollback.
- **Restaurar no publica ni reasigna intenciones.** No crea ni modifica vínculos. Sólo registra la instalación actual cuando la sesión legible es del mismo Member que el vínculo restaurado (reactivación). Aún no hay cola F05; su tratamiento al restaurar queda para v9.
- **Interfaz.**
  - Liquidación muestra de quién es la copia antes de pedir confirmación y no ofrece restaurar una ajena.
  - El titular ofrece al agricultor histórico ADMIN con su rol privado visible y una casilla de confirmación explícita.
  - Aplicación, transferencia, compra, pago al proveedor y alta de chacos usan `peopleFor`.

Commit: `812fe4995621c2ae0ed3a5f49101fe65ec71d62d`.

**Corrección de una afirmación mía durante el trabajo.** Dije que el formulario de aplicación lanzaba `StateError` al elegir un chaco cuyo dueño es ADMIN. Por el flujo normal no ocurre: el selector de chaco se habilita al elegir persona y filtra por ella. El defecto real era que el titular ADMIN no aparecía como persona que aplica. El `firstWhere` se volvió defensivo igualmente.

### B.3 Pruebas nuevas

| Archivo | Casos | Qué comprueba |
|---|---|---|
| `f04_restore_authorization_test.dart` | 13 | Recorrido real con base en archivo, `BackupService`, controlador de acceso real y `GuardedRestore`. Misma cuenta: contenido del respaldo fila por fila, vínculo intacto, instalación registrada, copia previa idéntica a la base anterior y escritura posterior en la base restaurada. Otro Member y otro tenant: rechazo, volcado idéntico, sin copia previa, autorización y escrituras conservadas. Base histórica sin vínculo con sesión de B: la copia de A se rechaza. Propiedad ilegible: rechazo. Copia v7: histórica, sin titular. Sin sesión: `restoredRequiresActivation` y escrituras bloqueadas. Contenedor `.agrobackup`. Recálculo fallido: estado `null`, escritura bloqueada como pendiente y recuperación al reintentar. Rollback: base anterior idéntica y autorización recalculada. Durante la sustitución se rechazan escritura, modalidad, titular y fotografía, y la lectura espera y ve la base restaurada. `BackupService.restore` es exclusivo por sí solo. Una escritura en curso queda en la copia previa |
| `f04_restore_ownership_rules_test.dart` | 11 | Regla pura de propiedad (misma cuenta, otro Member o tenant con cualquier sesión, sin vínculo actual, sin sesión, histórica, activación incompleta, ámbito de una sesión ilegible) y `DatabaseReplacementGuard` (rechazo y admisión interna, espera de escrituras, lecturas que esperan, sin sustitución desde una escritura ni doble, liberación tras fallo) |
| `f04_admin_owner_restore_ui_test.dart` | 6 | App real: el agricultor histórico ADMIN se ofrece con su rol, un tercero no; sin la casilla no se vincula; con ella, vínculo ADMIN y personas idénticas. En propio con titular ADMIN, la aplicación ofrece sólo al titular y su chaco. En compartido, la transferencia lo ofrece y otro ADMIN sigue fuera. En propio con titular familiar, el titular paga en el formulario de compra y en Compras, y otro ADMIN no. Restaurar desde Liquidación: la copia de otro Member se rechaza sin pedir confirmación ni tocar nada; la del mismo Member avisa, restaura y queda `activated` |

**Fallos observados durante el trabajo:**

- Seis pruebas existentes de formularios (`regression_widget_test`, `responsive_v5_test`) quedaron cargando. Su arnés sólo concede un intervalo de E/S real y `peopleFor` hacía tres consultas encadenadas. Se corrigió el código (`8e52fe1`, una sola consulta), no las pruebas.
- Dos pruebas nuevas de la exclusión «no terminaban». Esperar desde la zona de la prueba un futuro fallido creado en `Zone.root` lo provoca incluso con una función trivial, así que era el arnés. Las pruebas usan ahora la zona de la prueba capturada antes de sustituir.
- En la prueba del titular, el botón quedaba fuera de la superficie de 800×600. Se usa una superficie más alta.

### B.4 Resultados

| Sobre | Comando | Resultado |
|---|---|---|
| `812fe49` | `dart format --output=none --set-exit-if-changed lib test` | 141 archivos, 0 cambiados |
| `812fe49` | `flutter analyze` | `No issues found!` |
| `812fe49` | `flutter test` | PASS 832/832 (785 de la parte 2 + 17 de la parte A + 30 de la parte B) |

### B.5 Mutaciones

Mismo procedimiento que en A.5. Se ejecutaron las cuatro pruebas F04 de interfaz y restauración (`f04_restore_ownership_rules_test`, `f04_restore_authorization_test`, `f04_admin_owner_restore_ui_test` y `f04_activation_app_policy_test`). La primera tanda corrió sobre el árbol de trabajo antes de añadir la prueba de B7; la final, sobre `812fe49`.

| Mutación | Resultado |
|---|---|
| B1 la restauración no comprueba la propiedad | detectada: 3 fallos |
| B2 tras restaurar se conserva el estado anterior (el defecto R3) | detectada: 4 |
| B3 si el recálculo falla se conserva la autorización anterior | detectada: 1 |
| B4 las escrituras entran durante la sustitución | detectada: 3 |
| B5 la sustitución no espera a las escrituras en curso | detectada: 1 |
| B6 las lecturas no esperan a la sustitución | detectada: 1 |
| B7 `BackupService.restore` sin exclusión propia | detectada: 1 (en la primera tanda sobrevivió; ver abajo) |
| B8 toda copia se lee como histórica (vínculo ignorado) | detectada: 6 |
| B9 se acepta una copia de una activación sin terminar | detectada: 1 |
| B10 Liquidación no rechaza en la vista previa | detectada: 1 |
| B11 la pantalla del titular sólo ofrece familiares | detectada: 1 |
| B12 se vincula al ADMIN sin la casilla (las dos capas) | detectada: 1 |
| B13 aplicación con el filtro anterior | detectada: 1 |
| B14 transferencia con el filtro anterior | detectada: 1 |
| B15 pagador del formulario de compra sólo ADMIN | detectada: 1 |
| B16 pagador de Compras sólo ADMIN | detectada: 1 |

**Observado en la primera tanda:** B7 (`BackupService.restore` sin exclusión propia) **sobrevivió**. Ninguna prueba llamaba al servicio sin `GuardedRestore`, que ya envuelve la sustitución. Se añadió esa prueba y quedó detectada.

### B.6 Limitaciones de la parte B

- La compuerta se consulta dentro de la exclusión sin esperas intermedias. No hay mutación que lo pruebe aislado, porque entre la comprobación y la transacción no queda ninguna espera que se pueda intercalar.
- La exportación de respaldos no usa la exclusión (sin cambios): copia tras un checkpoint.
- Sin pruebas en dispositivo de la restauración ni de las pantallas nuevas.

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-15 (resultados arriba) y en el CI de GitHub del PR.
- Revisión de Roderich Rendón: hallazgos de la revisión del 2026-10-15 corregidos aquí; la revisión del diff final queda registrada en el PR.
- Revisión del tutor: se registra aparte, por entregable o gate, en GOV-01.
