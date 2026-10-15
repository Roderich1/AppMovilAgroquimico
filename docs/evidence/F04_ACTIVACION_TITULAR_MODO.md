# F04 — Política de activación, titular y modalidad (parte 1: dominio y datos)

Issues:
- #76 F03-RES-02 (compuerta de primera activación);
- #24 F04-MODE-01 (persistir la modalidad);
- #27 F04-MODE-04 (transiciones seguras).

Trazabilidad (Cap. III v1.5): RF-01, RF-06; CU-01, CU-05; RN-12, RN-17; §3.11.5–§3.11.6.

Esta parte deja la política en el dominio, los datos y el repositorio. Conectarla al arranque y a la interfaz (router, elección del titular, pantalla de modalidad) es la parte 2.

## Identidad de la ejecución

| Elemento | Valor |
|---|---|
| Fecha | 2026-10-15 |
| Rama | `feat/f04-activacion-titular-modo` |
| Base | `a1ab210f61fee2794a3b543251f050849a76125b` (HEAD de la rama de #73, PR #75 abierto) |
| Commit verificado | `fccd74c859a6042f1fc9a57e45ffcbee8069c9b5` |
| Sistema operativo / Flutter | Windows 11 Home 10.0.26200 / Flutter 3.47.2 |
| Tipo de prueba | Pruebas de host (`flutter test`, `sqflite_common_ffi`), sin dispositivo |
| Ejecución | Pruebas automatizadas ejecutadas con Claude Code en el entorno de desarrollo |

## Contraste con las fuentes y los criterios aprobados

| Fuente o criterio | Cómo se aplica |
|---|---|
| RF-01: validar identidad y vinculación «antes de habilitar por primera vez el contexto local»; no eliminar datos si falta autorización remota | Estado A (base nueva sin sesión) y estados sin vínculo verificado bloquean escrituras; ningún estado borra |
| v1.5 §3.11.6: activación incompleta se muestra y se repite; una sesión dañada se recupera conservando datos | `activationPendingOwner` (activada sin titular) bloquea hasta elegir titular; sesión ilegible con vínculo en la misma instalación sigue operando |
| CU-01: «No se habilita acceso a datos o funciones de otro miembro» | Sesión de otro Member o tenant → `identityMismatch`, escrituras bloqueadas, sin adopción de datos |
| Criterio A (referencias mínimas) | Se guardan `member_id` y `tenant_id` (ámbito de la clave F05 §5 y de C34/C38) y un SHA-256 de la instalación. **No** se guarda `account_id`, tokens ni contraseñas. Restaurar no habilita: hay que reactivar con el mismo Member |
| Criterio B (sin restablecimiento genérico) | No se añade ninguna acción que borre sesión, guardas, installationClientId, titular, SQLite o cola |
| Criterio C (titular) | Sólo una persona `FAMILY` activa, elegida explícitamente. No es el Administrador del sistema ni el rol local «Administrador». Sin coincidencia por nombre o teléfono. Los roles no cambian |
| Criterio D y CU-05 A2/E1, RN-17 | SHARED → PERSONAL se bloquea con existencias, planes DRAFT/PLANNED o saldos de cuenta de terceros. Exige confirmación y es atómico. El historial, los propietarios y las cantidades no cambian |
| #24/#27 dicen «movimientos de terceros» | Se sigue la v1.5 y el criterio D: bloquean los **datos activos**, no el historial. Discrepancia declarada |

## Pruebas nuevas (63 casos)

| Archivo | Cubre |
|---|---|
| `f04_install_policy_migration_test.dart` (6) | Base nueva v8 con la marca NEW. v7 con datos → LEGACY, con todas las tablas previas idénticas fila por fila y `app_settings` sólo con la marca nueva. v7 vacía → LEGACY: no se decide por filas. Nueva con datos → sigue NEW. La reapertura no cambia nada. Mismos disparadores en base nueva y migrada |
| `f04_installation_access_test.dart` (17) | A, activación sin titular y F, incluido que la sesión ilegible no se trata como nueva. Instalación activada: sesión legible, expirada, ilegible, ausente e identidad de instalación dañada. Datos restaurados en otra instalación. Otro Member y otro tenant. Base histórica con cada estado de sesión. La referencia de instalación no contiene el identificador |
| `f04_owner_binding_test.dart` (14) | Columnas guardadas (sin secretos). ADMIN y tercero rechazados sin cambiar ningún dato. Sin vínculo por homónimo. Persona archivada o inexistente, ámbito inválido y segundo vínculo rechazados. Alta del titular atómica. El motor impide reasignar, borrar, reabrir y tener dos vínculos activos. Cambio de titular: rechazado con cola pendiente, en modo propio o desde otra identidad; aceptado sin cola, con historial y sin cambios en los datos de negocio. Restauración: otra cuenta no adopta los datos; el mismo Member sólo registra la instalación. El archivo SQLite no contiene el installationClientId, «refresh» ni JWT |
| `f04_operation_mode_test.dart` (10) | SHARED por defecto en base nueva y migrada. Persiste tras cerrar y reabrir. Sin confirmación no cambia nada. Sin titular se bloquea. Existencias de un tercero bloquean, se informan y no se toca nada. Un plan abierto en el chaco de otra persona bloquea. Tras resolver explícitamente (consumo y pago) se admite con volcado de negocio idéntico. PERSONAL → SHARED conserva todo. Ida y vuelta con tablas idénticas. Un fallo a mitad de la escritura no deja efectos |
| `f04_repository_guards_test.dart` (16) | Cada estado bloqueado rechaza las 22 escrituras públicas sin cambiar la base. Los estados permitidos dejan pasar. La lectura sigue con la compuerta cerrada. En modo propio se rechazan compra, aplicación, chaco, plan y pago de otra persona y las tres rutas de transferencia; el titular opera normalmente y no se puede archivar. Modo propio sin titular falla cerrado |

Pruebas existentes ajustadas, sin cambiar lo que comprueban: en `f04_bug_01_reverse_transfer_test.dart` y `report_export_service_test.dart`, el literal `7` de versión pasa a `AppDatabase.schemaVersion` (≥ 7 donde la prueba es de la reparación de v7).

## Resultados (sobre `fccd74c`)

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | PASS, 126 archivos, 0 cambiados |
| `flutter analyze` | PASS, `No issues found!` |
| `flutter test` | PASS 762/762 (67 s de reloj) |

Antes de ajustar los literales de versión, la suite falló en 4 pruebas: las 3 de la reparación v7 que comparaban `user_version` con 7 y la de `report_export_service_test`. Se conservan como fallos observados de la ejecución intermedia.

### Mutaciones (sobre `fccd74c`)

Cada mutación se aplicó en `lib/`. Después se ejecutaron los cinco archivos `test/f04_*` nuevos (63 casos) y se restauró con `git checkout HEAD -- lib`; `git status` quedó vacío después de cada una.

| Mutación | Resultado |
|---|---|
| G1 sin `ensureAllowed()` en el repositorio | detectada: 5 fallos |
| C1 sesión dañada sin activar tratada como instalación nueva | detectada: 1 |
| C2 se ignora la instalación activada (restaurada = misma) | detectada: 3 |
| C3 sólo se compara el Member, no el tenant | detectada: 1 |
| M1 la migración marca la base como NEW | detectada: 2 |
| T1 sin el disparador «sólo cerrar» | detectada: 4 |
| O1 se ignoran las existencias de terceros | detectada: 1 |
| O2 se aplica la transición sin re-evaluar el bloqueo | detectada: 1 |
| P1 transferencias admitidas en modo propio | detectada: 1 |
| P2 compras o aplicaciones de otra persona en modo propio | detectada: 3 |
| B1 un administrador de pagos puede ser titular | detectada: 1 (regla cambiada el 2026-10-15: un ADMIN puede serlo con confirmación explícita; ver [F04_CORRECCIONES_REVISION.md](F04_CORRECCIONES_REVISION.md)) |
| B2 cambio de titular con cola pendiente | detectada: 1 |

## Limitaciones de esta parte

- El arranque, el router y la interfaz todavía no usan la compuerta: `repositoryProvider` construye el repositorio sin restricción hasta la parte 2.
- Las guardas de modo leen la modalidad al inicio de cada escritura, fuera de su transacción. En este dispositivo, con un solo usuario y transacciones serializadas por sqflite, no hay carrera práctica; queda declarado.
  - **Nota del 2026-10-15:** esta afirmación era incorrecta. La carrera se reprodujo (R1) y se corrigió en `731750e`; ver [F04_CORRECCIONES_REVISION.md](F04_CORRECCIONES_REVISION.md).
- `SyncQueueInspector` devuelve 0 hasta que exista la outbox de F05 (v9). Las pruebas del bloqueo por cola usan un doble.
- La restauración de respaldos (`BackupService`) no pasa por la compuerta: reemplaza la base completa y la clasificación posterior decide (F08).
  - **Nota del 2026-10-15:** la clasificación posterior no se recalculaba y una copia de otro Member quedaba autorizada (R3). Corregido en `812fe49` (exclusión, propiedad previa y recálculo); ver [F04_CORRECCIONES_REVISION.md](F04_CORRECCIONES_REVISION.md), parte B.
- Sin pruebas en dispositivo.

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-15.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.

---

# Parte 2: arranque, router e interfaz

| Elemento | Valor |
|---|---|
| Fecha | 2026-10-15 |
| Rama | `feat/f04-activacion-arranque-ui` (sobre `b90c6289ec29608b45acaef9663aadbb66f0f07d`, parte 1) |
| Commits verificados | `5f112a1920516e48df8550ddf5e76b2ce3ef3ee7` (implementación) y `c89057c91fe8d5e2520f832c79d7d10f62a452d8` (prueba añadida tras la mutación R7) |
| Tipo de prueba | Pruebas de host y de widgets (`flutter test`), con base sqflite real y sesión segura sustituida; sin dispositivo |
| Ejecución | Pruebas automatizadas ejecutadas con Claude Code en el entorno de desarrollo |

## Qué se conecta

- **Arranque.** `bootstrapExistingSession` devuelve el ámbito de la sesión sólo si es `available`, y sólo en memoria. `main.dart` calcula `installationReference` si la identidad está lista.
- **`InstallationAccessController`.**
  - Calcula el estado A–F.
  - Tras una activación en esta ejecución relee la sesión segura.
  - Si el mismo Member reactiva en otra instalación, registra la instalación.
  - Ante cualquier error falla cerrado (estado `null`) y ofrece reintentar. Nunca escribe datos de negocio.
- **`repositoryProvider`.** Instala `FarmerOperationGate`: con el estado `null` o bloqueado, toda escritura se rechaza.
- **Router.**
  - Sin estado o bloqueado: `/acceso`.
  - Activación sin titular: sólo `/titular`.
  - Estados que operan: libre.
- **Pantallas.**
  - Acceso: mensaje y acción permitida; nunca restablece nada.
  - Titular: elección explícita de un familiar o alta, y modalidad inicial.
  - Modo de uso: bloqueos, consecuencias y confirmación.
- **Activación.** «Continuar con datos locales» sólo aparece si ya se puede operar; si no, «Continuar» lleva a `/acceso`.

## Pruebas que cambian de expectativa (requisito anterior → política)

| Prueba | Antes | Ahora |
|---|---|---|
| `first_activation_screen_test`: `real app dashboard exposes activation route` | Base nueva sin sesión → Dashboard | **Reemplazada** por «nueva instalación (#76)»: no abre el Dashboard; la escritura directa al repositorio se rechaza sin cambios; una ruta de formulario vuelve a `/acceso`; desde ahí se abre la activación |
| `first_activation_screen_test`: `successful activation updates local binding state in the same runtime` | Activar → Dashboard y escritura | **Reemplazada** por «activación correcta (#76)»: tras activar, el estado es «activada sin titular» con escrituras bloqueadas; se crea el titular; luego Dashboard, vínculo con Member/tenant y escritura habilitada; la activación no se repite |
| `first_activation_screen_test`: `local SQLite remains writable after authentication failure` | Escribía en otra base sin relación | **Reemplazada** por «authentication failure does not touch the SQLite domain»: volcado idéntico antes y después del fallo |
| `existing_session_screen_test` (6 estados de sesión) | Base nueva | Base de una instalación **ya activada** (titular y misma instalación); las aserciones se mantienen. Es el caso de reapertura sin red que protege |
| `remote_session_screen_test` (7) | Base nueva | Instalación ya activada del Member A; aserciones sin cambios |
| `navigation_test`, `hierarchical_navigation_test`, `purchases_access_test`, `reports_screen_test`, `widget_test` | Sin compuerta | Override explícito `activatedInstallationForTests()`; no tratan la activación |

## Pruebas nuevas de la parte 2 (22 casos)

| Archivo | Cubre |
|---|---|
| `f04_activation_app_policy_test.dart` (15) | Base histórica: abre el Dashboard, opera y no se vincula sola. Base histórica con sesión legible: titular elegido explícitamente, roles intactos. Activada con sesión ilegible: opera, con aviso. Reapertura sin red con sesión expirada: no escribe nada al abrir. Base restaurada de otra instalación: `/acceso`, escritura rechazada, volcado idéntico. Sesión de otro Member: `/acceso`, sin «Elegir titular», volcado idéntico. Base nueva con sesión dañada: no se ofrece activar ni se borra nada. Repositorio de la app falla cerrado mientras se evalúa. Modo de uso: bloqueo con existencias de terceros sin cambios; sin terceros pide confirmación y pasa a propio con datos de negocio idénticos. `accessRedirect` (4). La app instala la compuerta real |
| `existing_session_startup_test.dart` (+7) | Sólo una sesión `available` expone Member y tenant, sin credenciales; los estados ilegibles, una lectura fallida y una lectura no `available` con datos de sesión no exponen ámbito |

## Resultados (sobre `c89057c`)

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | PASS, 132 archivos, 0 cambiados |
| `flutter analyze` | PASS, `No issues found!` |
| `flutter test` | PASS 785/785 (63 s de reloj) |

### Fallos observados durante la construcción

| Paso | Observación | Resolución |
|---|---|---|
| Primera suite con la compuerta | 35 fallos en 8 archivos que montan la app: el `redirect` y la compuerta aplicaban la política real | Overrides explícitos y pruebas reescritas (tabla anterior) |
| `purchases_access_test`: «ninguna ruta declarada queda sin origen» | `/acceso` sólo se alcanzaba por `redirect`; luego, con un ternario, la guarda no lo veía | Navegación literal `context.go('/acceso')`. La guarda no se modificó |
| Pruebas de app nuevas | `pumpAndSettle` no termina con sqflite real; el toque fallaba fuera de la pantalla de prueba; la espera salía antes de construir la ruta nueva | Espera con `runAsync`, `ensureVisible` y un mínimo de vueltas |
| `redirect` | Desde `/acceso` no se pasaba a `/titular` al quedar la activación sin titular | Regla explícita: activación sin titular → sólo `/titular` |

### Mutaciones (sobre `5f112a1`)

Archivos ejecutados: `f04_activation_app_policy_test`, `first_activation_screen_test`, `existing_session_screen_test`, `remote_session_screen_test`, `existing_session_startup_test`. La restauración se hizo con `git checkout HEAD -- lib`, con `git status` vacío después de cada mutación.

| Mutación | Resultado |
|---|---|
| R1 sin `redirect` | detectada: 5 fallos |
| R2 `repositoryProvider` sin compuerta | detectada: 7 |
| R3 se ignora el ámbito de la sesión del arranque | detectada: 3 |
| R4 no se relee la sesión tras activar | detectada: 1 |
| R5 la compuerta deja pasar mientras el estado es `null` | detectada: 2 |
| R6 «Elegir titular» sin sesión legible | detectada: 1 |
| R7 el arranque expone el ámbito de una lectura no `available` | **sobrevivió** en `5f112a1` (las pruebas sólo usaban lecturas sin sesión). Se añadió la prueba de `c89057c` y quedó detectada: 1 |

## Limitaciones de la parte 2

- Sin ejecución en dispositivo: el flujo real de activación en el POCO se verifica con #71 o en una ejecución coordinada.
- Sesión dañada sin activar (F) y sesión de otro Member: la pantalla muestra la condición sin una salida automática. No se añadió un restablecimiento (criterio B); el tratamiento explícito queda como decisión.
- MODE-03 (#26) no está incluido: la interfaz en modo propio todavía muestra los selectores y el menú de transferencias. El repositorio rechaza esas operaciones.
- La restauración de respaldos no recalcula el estado hasta reabrir la app (F08).
  - **Nota del 2026-10-15:** esta limitación era un defecto (R3). Corregido en `812fe49`; ver [F04_CORRECCIONES_REVISION.md](F04_CORRECCIONES_REVISION.md), parte B.

## Revisiones (parte 2)

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-15.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
