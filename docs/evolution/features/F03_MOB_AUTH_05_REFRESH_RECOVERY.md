# F03-MOB-AUTH-05 — refresh seguro y recuperación de sesión

Estado: implementación de Mobile #22 para revisión independiente. PR draft; GATE-F03 #23 sigue abierto. Baseline Mobile: `6c8ab946c1d87239e1831a02fd5f3cc07b8ba512` (627 pruebas). Contrato Backend: `a09876106dd696868217b301a9abf9125ac6d01d` y `docs/api/openapi-f02.json` de ese commit.

## Límite local/remoto

`ExistingSessionStartupState` de #21 sigue indicando **sólo** el vínculo cifrado local. `RemoteSessionState` representa la capacidad remota y no contiene JWT, refresh, IDs ni respuestas HTTP. `main.dart` no construye el cliente HTTP ni invoca refresh. Dashboard, SQLite, lectura y escritura de datos individuales siguen disponibles cuando el acceso remoto falla. La acción «Verificar acceso en línea» es explícita y on-demand; `/reauth` es distinta de `/activar`.

El access JWT sólo existe transitoriamente en el flujo de `AuthV2Api`; nunca se guarda en SQLite, preferences, backup, secure store o logs. El refresh permanece en `SecureSessionStore` cifrado de #20. El guard no guarda tokens ni identificadores.

## Amenaza: rotation y reuse

El Backend consume el refresh anterior al emitir uno nuevo. Si la respuesta se pierde y Mobile reenvía el anterior, el Backend puede declarar la sesión `COMPROMISED` y revocar sus credenciales. Por ello no hay retry automático del token anterior tras una request que pudo salir del dispositivo. Timeout, socket, respuesta malformada y muerte del proceso se tratan como resultado remoto incierto.

`AndroidRefreshGuard` usa el canal `agrocuentas/secure_session_pointer`. El Kotlin nativo serializa `readRefreshGuard`, `setRefreshGuard` y `clearRefreshGuard` bajo el mismo lock del pointer, y verifica `SharedPreferences.commit()` más relectura. La clave booleana `refreshQuarantined` reside en `AgrocuentasSessionPointer.xml`, ya excluido de backup anterior y posterior a Android 12, incluido device-transfer. No se añade una preferencia con secretos. Un valor corrupto o una operación no confirmada falla cerrado. `setRefreshGuard` exige `clear`, de modo que dos intentos concurrentes no pueden enviar el mismo refresh.

Orden de refresh: leer sesión cifrada `available` → validar configuración HTTPS → leer guard `clear` → persistir `quarantined` → una sola request `/refresh` BODY → validar contexto y rotación → `SecureSessionStore.commitAndVerify` → limpiar guard durable → `remoteAvailable`. Si el guard no se confirma **no sale HTTP**. Si el proceso muere en cualquier punto después de activarlo, el siguiente arranque conserva el bloqueo sin hacer red. La lectura local del guard sólo afecta los controles remotos del Dashboard, no SQLite. El coordinador rechaza una segunda operación remota simultánea en el mismo isolate, incluso desde otra instancia; el set nativo del guard tiene además compare-and-set bajo lock.

## Validación del refresh

La respuesta debe ser V2/BODY, agricultor activo, con cuenta/miembro/tenant activos y sesión `ACTIVE`. `account.id`, `member.id`, `tenant.id`, `session.id` y `session.clientRegistrationId` deben coincidir con `StoredSession`; este último debe ser el `registrationId` guardado. `sessionExpiresAt`, `context.session.expiresAt` y la expiración almacenada deben ser el mismo instante y continuar vigentes. El refresh nuevo debe diferir del anterior. Sólo entonces se crea `SessionCommitCandidate` que conserva installationClientId y todos los IDs existentes. Una sesión local expirada puede intentar refresh, pero una ausente, corrupta, incompatible o ilegible no.

| Resultado | Estado remoto y guard | SQLite |
|---|---|---|
| 200 válido + commit + clear confirmados | `remoteAvailable`, guard clear | Disponible |
| 401 o rechazo HTTP 400/403/404/409/429/5xx | `requiresReauthentication`, guard quarantined | Disponible |
| Network, timeout, JSON/contrato inválido | `outcomeUnknown`, guard quarantined, sin retry | Disponible |
| Contexto/registro/sesión discrepante con refresh rotado conocido | Un logout best-effort del refresh nuevo; `requiresReauthentication`, sin commit, guard quarantined | Disponible |
| Commit local definitivamente fallido | Un logout best-effort del refresh nuevo; `requiresReauthentication`, guard quarantined | Disponible |
| Commit local incierto | Sin logout ni relectura interpretada como confirmación; `requiresReauthentication`, guard quarantined | Disponible |
| Clear no confirmado tras commit | No se afirma acceso remoto; recuperación segura requerida | Disponible |
| HTTPS ausente antes de request | `configurationUnavailable`, guard sin cambio, cero HTTP | Disponible |

## Reautenticación de la misma cuenta

Sólo se ofrece cuando existe vínculo local disponible/expirado y el guard está quarantined. El flujo **no** llama `registerClient` ni rota el UUID: login BODY → validar AGRICULTOR activo y account/member/tenant exactamente iguales a `StoredSession` → bind de `stored.registrationId` → `/me` → comprobar mismos IDs, registro vinculado, sesión nueva coherente y expiración → commit cifrado del refresh nuevo → clear durable. Puede cambiar `sessionId`; no cambian installationClientId, registrationId, accountId, memberId o tenantId. Un bind 401/404/409 bloquea capacidad remota y no se interpreta como permiso para recrear el registro. La contraseña se limpia del formulario después del intento y no entra en el estado Riverpod.

Una respuesta de login de otra cuenta se rechaza y se intenta **una sola** limpieza por logout del login nuevo. También se intenta limpiar una sesión nueva conocida antes del commit cuando bind o `/me` fallan. Si esa limpieza falla, se informa `cleanupUnconfirmed`. No se realiza cleanup automático del refresh antiguo tras un commit nuevo: mantenerlo en memoria para ese fin aumenta superficie de exposición y el guard ya prohíbe reutilizarlo. Si login/bind tienen resultado remoto incierto, no hay blind retry; se conserva quarantine y se requiere reconciliación. Una pérdida de acuse del commit cifrado no se relee como éxito.

## Corrective audit — definite local commit cleanup

La revisión previa al merge identificó `ORPHAN_REMOTE_SESSION_AFTER_DEFINITE_LOCAL_COMMIT_FAILURE`: después de recibir un refresh nuevo o completar login/bind/`/me`, un fallo local definitivo podía dejar activa en Backend una sesión cuya credencial nueva no quedó activa en el almacenamiento cifrado del teléfono. Ahora `invalidCandidate`, `existingSessionUnreadable` y `writeFailed` de `SecureSessionStore` permiten exactamente un `logout` best-effort con **el refresh nuevo conocido**, tanto en refresh como en reauth. El resultado sigue siendo `requiresReauthentication / localCommitFailed`, el guard sigue `quarantined`, no se repiten login, refresh ni commit y el fallo de logout se refleja únicamente en `cleanupUnconfirmed`.

`SecureSessionCommitUncertainException` se captura antes de `SecureSessionStorageException`: si la activación durable pudo ocurrir, el resultado es `localCommitUnknown` y **se prohíbe el logout automático** del nuevo refresh. También se trata conservadoramente como incierto un error no clasificado durante commit. No se relee el almacenamiento como confirmación ni se reutiliza el refresh antiguo. Ante un 200 parseable con refresh efectivamente rotado pero contexto inválido, se intenta un solo logout del refresh nuevo antes de descartarlo; si el valor recibido coincide con el token antiguo, no se lo revoca mediante este cleanup. Network, timeout, JSON inválido y respuestas HTTP sin nuevo refresh conocido no generan logout inventado. Ninguna credencial se añade al estado, logs, SQLite, preferencias o documentación.

## Pruebas y limitaciones

Baseline previa a la corrección: 681 pruebas. La suite local correctiva contiene **690/690** (+9): 52 pruebas del coordinador, 4 del canal y 7 de UI/SQLite añadidas desde la baseline Mobile de 627. `flutter pub get`, formato, `flutter analyze` y `flutter build apk --release` aprobaron; esta build release no está firmada ni distribuida. Las pruebas de coordinador usan `MockClient` y respuestas contractuales sintéticas; son `CONTRACT_SIMULATED`, no E2E Mobile→Backend. Verifican orden guard→HTTP→commit→clear, un único refresh, concurrencia en el isolate, 401 y otros HTTP, network, timeout, JSON inválido, mismatches de identidad/registro/sesión/rol/expiración, cleanup único del nuevo refresh en fallo definitivo y contexto inválido, ausencia de logout en commit incierto, ausencia de segundo refresh, reauth de la misma cuenta, rechazo de otra cuenta, bind 401/404/409, `/me`, no `registerClient`, limpieza de contraseña en UI, ausencia de secretos en estado y continuidad SQLite/UI sin HTTP de arranque. Las pruebas del canal simulan recreación del wrapper, fallos de set/clear y exclusiones de backup. El `commit()` Android real requiere DEVICE; un mock no lo demuestra.

En POCO X5 Pro 5G / API 31 se compiló un APK debug temporal con package aislado `com.comunidad.agro.agroquimicos.f03auth05test` y datos de sesión sintéticos. Se verificó el package antes de instalar. Dos intentos previos de `adb install -r` devolvieron `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. Tras el commit correctivo y CI verde se compiló otra vez el package aislado y un tercer intento el 2026-10-01 devolvió el mismo error Android, `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. `pm list packages` confirmó antes del intento que sólo estaba la app normal; la instalación fallida no sembró ni modificó ninguna sesión del teléfono. El entrypoint/harness y `applicationIdSuffix` temporales se retiraron del árbol de la PR. `DEVICE_INSTALLATION_BLOCKED`: DEVICE-22-A (force-stop con guard), B (reboot con guard) y C (configuración HTTPS ausente) son **`NOT_MEASURED`**, no FAIL funcional ni PASS. DEVICE-22-D (refresh real) y E (401/revocación real) también son `NOT_MEASURED` sin Backend HTTPS y cuenta AGRICULTOR controlados. `E2E_MOBILE_BACKEND = BLOCKED_ENVIRONMENT`. #19 sigue abierto: esta implementación no acredita primera activación nominal real.

Riesgo residual: una pérdida del acuse de `clearRefreshGuard` puede dejar la UI bloqueada aunque el refresh nuevo ya esté cifrado; se prefiere recuperación conservadora a reuso del token viejo. Un resultado remoto incierto durante reauth puede dejar un login nuevo en Backend con cleanup no confirmado. Ninguno habilita borrar SQLite, crear otro ClientRegistration o cambiar de usuario silenciosamente.
