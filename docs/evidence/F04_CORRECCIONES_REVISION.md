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

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-15 (resultados arriba) y en el CI de GitHub del PR.
- Revisión de Roderich Rendón: hallazgos de la revisión del 2026-10-15 corregidos aquí; la revisión del diff final queda registrada en el PR.
- Revisión del tutor: se registra aparte, por entregable o gate, en GOV-01.
