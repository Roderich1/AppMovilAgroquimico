# F03 «Recuperar acceso», credencial del titular, RF-13 y RF-03: evidencia en host

- **Fecha real:** 2026-10-23 (America/La_Paz). Redactada por la sesión A de Claude Code.
- **Rama:** `feat/f03-recuperar-acceso`. **Verificado sobre `04162ff`.** Base: Mobile `b0d169b`.
- **Procedencia:** HOST (Windows 11, Flutter 3.47.2 stable, `d3b14c8769`). **DEVICE: pendiente.** No se ha ejecutado nada de esta rama en un teléfono.
- **Contratos:**
  - [F03_RECUPERACION_IDENTIDAD_LOCAL.md](../architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md): RF-01, RF-13, CU-01, CU-15, RNF-04;
  - [F04_RF13_RF03_ACTOR_Y_TARDIAS.md](../architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md): RF-03, RF-13, RN-15, RN-16, CU-06, CU-09, DAT.
- **Gates:** este documento no decide ninguno. Lo que se presente a gate queda `Pending` hasta que Roderich lo decida.

## Commits

| SHA | Contenido |
|---|---|
| `f90d330` | Dependencia `cryptography` 2.9.0 (común con F08) |
| `c2456de`, `1c05683` | Contrato F03 y revisión de C (R1–R5) |
| `cc88fdd`, `9672ac2` | «Recuperar acceso» por estado; comprobación del ámbito antes de guardar la sesión (revisión de B) |
| `7713f9c` | Credencial local del titular (PIN) y autorización de un solo uso |
| `bdfeb66`, `fce6c5b` | Contrato RF-13/RF-03 y revisiones de C (R1–R4) y B (I1–I4, m1–m5) |
| `6e5db96`, `48dd1b7` | RF-13: reversiones autorizadas con motivo y auditoría privada (esquema v11) |
| `b97a95f` | RF-03: compra y aplicación tardías con revisión del titular |
| `caca66c` | `CAMPAIGN_SEALED` terminal en Mobile (contrato F07 de B) |
| `6a40dce` | RF-03: pantalla «Operaciones tardías» y oferta de registro para revisión |
| `04162ff` | Sólo formato (`dart format lib test`) |

## Comandos y resultados (2026-10-23, sobre `04162ff`)

- `dart format --output=none --set-exit-if-changed lib test`: código de salida 0, 288 archivos, ninguno cambiado.
- `flutter analyze`: «No issues found!».
- `flutter test --concurrency=1 test/<archivo>.dart`, **un archivo por invocación** (ver «Límites»):

| Archivo | Resultado | Qué comprueba |
|---|---|---|
| `f03_access_recovery_test` | 13 pasan | Comportamiento por estado de acceso. Recuperar exige la cuenta del titular vinculado: el ámbito se comprueba antes del registro de cliente y otra vez antes de guardar. Una sesión ajena se cierra sin tocar SQLite. Volcado completo de la base sin cambios, `RESTORE_PAUSED` incluido; en una instalación restaurada sólo cambia `activated_installation_ref` |
| `f03_access_recovery_app_test` | 3 pasan | Recorrido de pantallas `/recuperar` desde estado de acceso y panel |
| `f03_local_owner_credential_test` | 14 pasan | PIN con PBKDF2 en isolate; bloqueos de 30 s, 2 min y 10 min; restablecimiento en línea a los 10 fallos; autorización de un solo uso, 120 s, por propósito y sujeto, contra el vínculo vigente; nunca `deleteAll` |
| `secure_session_store_test` | 25 pasan | Incluye los 6 casos de sustitución de una sesión ilegible o de un puntero corrupto, y el rechazo con una sesión legible, ausente o no disponible |
| `existing_session_screen_test` | 6 pasan | Sesión efectiva tras recuperar o cerrar sesión |
| `f04_activation_app_policy_test` | 15 pasan | Primera activación con el ámbito del controlador |
| `f04_rf13_reversal_audit_test` | 13 pasan (12 sobre `04162ff`; la 13.ª se añadió en el commit de esta evidencia) | Reversión con motivo y PIN; auditoría con sus efectos en la misma transacción; tablas inmutables por trigger; reversión completa ante un fallo inyectado; doble pulsación; las tablas `sync_*` no cambian con una reversión auditada; sin titular vinculado no se autorizan nuevas reversiones; migración v10→v11; una reversión anterior a v11 queda sin actor y no se infiere ninguno (en pantalla, «Actor no registrado») |
| `rec_050_reversal_rules_test` | 6 pasan | Reglas de reversión existentes con el nuevo flujo de aprobación |
| `f04_rf03_late_operations_test` | 11 pasan | Borrador sin efectos (volcado idéntico salvo `late_operation_drafts`). Al confirmar se revalidan la campaña, los lotes de esa fecha, el FIFO y el tope temporal, con un oráculo calculado a mano por día y por lote; confirmaciones fuera de orden; lote adquirido después de la fecha; campaña cambiada (`LATE_CAMPAIGN_CHANGED`) y existencias (`LATE_STOCK_UNAVAILABLE`). Rechazo sin efectos; persistencia al reabrir; período histórico cerrado y sin solapes |
| `f04_rf03_late_screen_test` | 2 pasan | Confirmación con PIN desde la pantalla, aplicada en la campaña cerrada con aviso de corrección privada; la oferta sólo aparece con fecha de campaña cerrada y exige motivo |
| `sync_retry_worker_test` | 36 pasan | `CAMPAIGN_SEALED` es terminal, no se reenvía tras reiniciar, y tiene su explicación |
| `f04_install_policy_migration_test` | 6 pasan | Triggers v11 y exclusión de las tablas v11 en los volcados antiguos |
| `migration_test` | 7 pasan | Migraciones hasta v11 |

La prueba de pantalla de RF-03 encontró un defecto: `setState` recibía un cierre que devolvía un `Future`. Se corrigió en `6a40dce` antes de dar la prueba por buena.

## Composición con F08 (sesión C)

La rama `comp/f01-f08-mob` integra `e5bf32b` (`feat/f08-respaldo-cifrado`) con `--no-ff` (`d263407`), sin conflictos. Encima van, por fast-forward, `d13ef03` y `6c77c83` de C, que conectan la clave de recuperación con la credencial del titular. Sobre `6c77c83`:

- el formato no cambia nada y `flutter analyze` no da avisos;
- 29 archivos de respaldo, restauración, F03, RF-13/RF-03, esquema y sincronización, uno por uno, sobre `d263407`: **28 pasan y 1 falla**;
- después se repitieron cuatro sobre `6c77c83` y pasan: keyring 13, pantalla de clave 1, cliente remoto 43, credencial 14.

**Fallo pendiente:** `f08_late_draft_photos_test` (archivo de C). Crea una tabla `late_operation_drafts` sustituta, que en la composición ya existe con el esquema v11 real. No es un defecto de producto: el trigger `trg_late_drafts_resolved_immutable` no incluye `invoice_image_path`, así que el reapuntado de la restauración está permitido. C ajusta la prueba. **La composición no está verde hasta ese commit.**

## Límites

- **Sin suite completa.** El turno pesado está bloqueado por memoria (1,2 GB libres de 23,7 al ejecutar). La suite completa de Mobile y el CI quedan pendientes de autorización de Roderich.
- **Sin dispositivo:** recuperación de acceso, PIN y Keystore (`AndroidCredentialStorage`, canal `agrocuentas/secure_session_pointer`) sólo se han probado en host, con dobles.
- **Saldos acumulados:** no hay ninguna vista de saldos acumulados por fecha. El orden de vistas pedido en la revisión I1 de B sólo se aplicará a vistas futuras.
- **Una aplicación tardía no se vincula a un plan:** si viene de un plan, no se ofrece el registro para revisión.
- **Pago al proveedor:** en una compra tardía se registra después de confirmarla, no al capturarla.
- **Revisiones:** las de B y C fueron por lectura de contratos y código; no ejecutaron estas pruebas.
