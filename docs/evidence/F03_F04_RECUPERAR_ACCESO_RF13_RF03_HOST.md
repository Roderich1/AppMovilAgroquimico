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

## Actualización del 2026-10-23 (noche): revisiones de código de B y C

**Commits:**
- **`f7f6a73`**, revisiones de C (RF-13) y de B (PIN):
  - **R1 y R2:** texto del actor; un fallo de lectura no se muestra como «Actor no registrado», y se distingue el PIN de este teléfono de uno que ya no está configurado;
  - **R3:** prueba del respaldo;
  - **P1:** cola y conteo del intento antes del KDF.
- **`cf4ae8a`:** la cola del PIN es por almacén y no estática. La versión estática encadenaba esperas entre pruebas de widget y colgó `rec_050`: se detectó al ejecutarlo y se descartó.
- **`f706e11`:** `AndroidCredentialStorage` único por proceso (nota de B).

**Resultados sobre `cf4ae8a`** (formato sin cambios, `flutter analyze` sin avisos, un archivo por invocación):
- recuperación 13, app 3, credencial 16;
- RF-13 13, **RF-13 respaldo 3** (nuevo), RF-03 11 + 2;
- sesión 25, retry 36, rec_050 6, migraciones 6 + 7, sesión existente 6, activación 15.

**Sobre `f706e11`:** credencial 17, con la prueba del almacén único.

**Mutación:** sin la cola, la prueba de 4 verificaciones simultáneas falla. Comprobado sobre las dos versiones de la cola; el código se restauró después de cada comprobación.

**Revisiones, por lectura:**
- **B:** PIN LISTO sobre `cf4ae8a`.
- **C:** RF-13 LISTO sobre `f7f6a73`.

**`f04_rf13_reversal_backup_test`** usa la exportación y la restauración locales (el contenedor). El formato 2 de C sólo envuelve la subida remota, así que esta prueba no lo cubre.

## Actualización del 2026-10-24: autoridad de la autorización, publicación y CI

**Decisión de Roderich** (delegación, 2026-10-23), aplicada:
- restablecer el PIN invalida al instante las autorizaciones anteriores;
- se cierra la fabricación de autorizaciones por llamada directa.

El diseño, los límites y las pruebas están en el contrato F03 §8.

**Commits:**
- `f4c85c5`: enrolamiento vigente de la instalación y comprobante de la acreditación propia;
- `664e85e`: RF-03, fallo transaccional al confirmar y ninguna publicación;
- `94ef034`: revisión de B, R1–R3 (sólo la cola publica, borrado antes de escribir, almacén emisor);
- `b8cccfb`: redacción, m1–m2;
- `fc20110`: tres pruebas que fallaban en la suite completa de CI. Ninguna se debilitó:
  - «Operaciones tardías» pasa al final del menú;
  - la fecha de campaña cerrada abre la oferta RF-03;
  - revertir exige motivo y PIN.

**Revisiones, por lectura:** B, LISTO sobre `94ef034` (R1–R3 resueltas, m1–m2 aplicadas). C reescribió el consumidor F08 de la composición con la API nueva.

**Mutaciones dirigidas, todas detectadas** (2026-10-24; código restaurado después de cada una):
- cola desactivada;
- sin actualizar el enrolamiento al restablecer;
- lecturas fuera de la cola que publican;
- sin comprobar el almacén emisor;
- sin borrar antes de escribir.

**Publicación (Lote 1 autorizado):** MOB **#143** (esta rama), #144 (F08) y #145 (composición «NO FUSIONAR»).

**CI de GitHub, `flutter-ci.yml`** (format, analyze, suite completa, suite de fechas en America/La_Paz y `flutter build apk --release`):

| PR | HEAD | Run | Resultado |
|---|---|---|---|
| #143 | `fc20110` | 40062639297 | **success**: 1695 pasan y 4 se omiten; fechas, 78; APK release compilada |
| #145 | composición `8364528` | 40062678967 | **success**: 1795 pasan y 4 se omiten; fechas, 78; APK release compilada |
| #145 | composición `490deb5` (anterior) | 40061867736 | **failure**: 3 pruebas, corregidas en `fc20110` |

**Las 4 omitidas son por diseño:**
- 3 centinelas de zona horaria que corren en el paso regional (`date_display_test` ×2 y `f04_c2_campaign_period_test`);
- `f06_reconciliation_integration_test`, que necesita un Central real.

**Lo que esta CI no ejecuta:**
- DEVICE;
- las mutaciones, que se hicieron sólo en local;
- aapt2 del manifiesto fusionado y de las reglas empaquetadas: la CI no publica el APK;
- el ensayo con un Backend real: la suite usa dobles.

**DEVICE, intentado el 2026-10-24 y NO ejecutado:**
- se preparó el entorno: PostgreSQL desechable `agro_a_f01f08_pg`, Backend de la composición `453acce` compilado en local y túnel HTTPS con el health en 200;
- no se pudo compilar la APK aislada `.f01f08`: quedaban 0,5 GB libres, y el servidor de lenguaje Dart del editor ocupaba unos 7 GB, que no es un proceso de esta sesión;
- el entorno se desmontó sin datos medidos;
- no se instaló nada en el teléfono.
