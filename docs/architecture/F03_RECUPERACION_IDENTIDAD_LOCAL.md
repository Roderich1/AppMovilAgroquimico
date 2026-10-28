# F03: recuperación de acceso y credencial local del titular — contrato

- **Fecha real:** 2026-10-23 (America/La_Paz). Sesión A, sobre Mobile `main` `b0d169b`, cuyo código funcional es `463d3ec`.
- **Fuente:** `_briefs/INICIO_F01_F08_2026-10-23/01_DECISIONES_APROBADAS.md` §2, §3 y §9 (SHA-256 `5a88f232…`). Es una decisión del autor para el entorno sintético, no una aprobación institucional.
- **Revisión:** B revisa F03; C revisa la credencial y su relación con la restauración.
- **Trazabilidad:** RF-01, RF-13, CU-01, CU-15 y RNF-04.

**Qué cambia en el contrato.** Hasta ahora, `AccessStatusScreen` sólo decía «requiere revisión» en `identityMismatch` y `sessionDamagedNotActivated`. Y una instalación activada con la sesión **ausente o ilegible** no tenía camino para recuperar las funciones remotas, porque `ReauthenticationScreen` exige una sesión legible. Este contrato añade una salida explícita, **«Recuperar acceso»**. No cambia las reglas de `classifyInstallation`.

## 1. Tres mecanismos separados

| Mecanismo | Qué recupera | Qué **no** concede |
|---|---|---|
| **Recuperar acceso** (este contrato) | La sesión segura (Auth V2) de **la misma cuenta del titular** | Ni el PIN ni la clave del respaldo |
| **Credencial local del titular (PIN)** (§4) | La autorización local de reversiones y revisiones tardías (RF-13 y RF-03), sin red | Ni la sesión ni la clave del respaldo |
| **Clave de recuperación del respaldo** (ADR de C, F08) | El descifrado de las copias remotas | Ni la sesión ni el PIN |

Recuperar uno no concede los otros. **El PIN nunca se usa como clave criptográfica del respaldo, ni la clave del respaldo como PIN.**

## 2. «Recuperar acceso» según el estado

| Estado (`InstallationAccessState`) | Qué se ofrece | Comprobación antes de guardar nada | Resultado |
|---|---|---|---|
| `activatedSessionUnavailable`, sesión **legible** (expirada o en cuarentena) | La reautenticación existente (`/reauth`), con el mismo registro de cliente | La de siempre | Funciones remotas recuperadas |
| `activatedSessionUnavailable`, sesión **ausente o ilegible** | «Recuperar acceso»: inicio de sesión del titular | El **Member y el tenant del login** son iguales al **vínculo activo**, antes de registrar el cliente | `activated`. Mientras tanto la operación local sigue permitida |
| `restoredRequiresActivation` | «Recuperar acceso» (activación del mismo titular) | Lo mismo | `activated`; la instalación nueva queda registrada. **Antes no se habilita ninguna operación** |
| `identityMismatch` | **«Salir de esta sesión»** y después «Recuperar acceso» con la cuenta del titular | La salida no lee ni cambia datos. La entrada exige el mismo Member y tenant | Ningún dato se adopta para la otra cuenta |
| `sessionDamagedNotActivated` (base nueva, sin vínculo, sesión ilegible) | «Recuperar acceso»: rehace **sólo** la sesión | Ninguna de titular, porque no hay vínculo | `activationPendingOwner`: falta elegir el titular. **No se habilitan operaciones antes** |
| `newRequiresActivation`, `legacyUnbound` y `activationPendingOwner` | Sin cambios (activación y elección del titular existentes) | — | — |

**Reglas comunes:**
1. **Nada se borra:** ni la base SQLite, ni los titulares, ni los vínculos, ni el historial, ni la outbox, ni los archivos del respaldo (llavero `agrocuentas_backup_keys_v1`, `<databases>/previo`, `remote_backups`; R5 de C). Ninguna operación se reasigna. La base histórica no se convierte en nueva. El propietario no cambia porque otra persona inicie sesión.
2. **Cuenta equivocada:** se aborta en cuanto el login devuelve otro Member o tenant, antes de `registerClient`. Se intenta cerrar ese login (`logout`) y no se guarda ninguna credencial. El estado anterior queda intacto.
3. **Cancelación** antes de guardar: se aceptan como en la primera activación (`requestCancel`). Desde que empieza la escritura atómica, no se cancela.
4. **Red caída o respuesta perdida:** no se guarda nada y el estado anterior se conserva. No hay reintento automático de login, bind ni `/me`.
5. **Fallo a mitad:** la escritura es la de `SecureSessionStore.commitAndVerify` (ranura inactiva, puntero atómico y relectura). Un fallo antes del puntero no cambia la sesión anterior. Uno después se informa como **resultado incierto**, sin fingir un rollback. Nunca queda una identidad a medio instalar.
6. **Sesión ilegible:** se reemplaza sólo en «Recuperar acceso», y sólo así:
   - con un **slot ilegible** (`corrupt` o `incompatible`) y un puntero legible, el candidato nuevo se escribe en la otra ranura y el puntero se mueve con `expected` = el puntero actual;
   - con un **puntero corrupto**, un método nativo nuevo, `resetCorruptPointer`, lo quita **sólo si** al releerlo sigue corrupto;
   - un almacenamiento **no disponible** (`unavailable`) **no** se reemplaza: se informa y se ofrece reintentar.
7. **La outbox no se toca:**
   - una cola en `RESTORE_PAUSED` sigue pausada hasta la acción expresa existente, que libera el titular verificado;
   - recuperar el acceso no dispara ninguna publicación;
   - las intenciones ya autorizadas siguen su ciclo normal cuando vuelve la capacidad remota, como antes.
8. **Sin red** se conservan los datos y sólo se permite la operación local que el estado ya autoriza.

**Identidades que se distinguen:**
- **credenciales:** la sesión Auth V2 en el almacén seguro;
- **identidad de instalación:** `installationClientId` y `installationReference`;
- **vínculo de negocio:** `owner_bindings`, con Member, tenant y persona titular.

«Recuperar acceso» sólo crea credenciales. No cambia la identidad de instalación ni el vínculo, salvo registrar la instalación activada (`recordActivatedInstallation`), como ya ocurría.

## 3. Implementación (Mobile, sesión A)

- **Activación:** `FirstActivationCoordinator.activate` acepta dos parámetros opcionales:
  - `requiredScope`: aborta con `ownerMismatch` antes de `registerClient`;
  - `replaceUnreadableSession`.
  - Sin ellos, el comportamiento es el de hoy.
- **Almacén seguro:** `SecureSessionStore.commitAndVerify(candidate, {replaceUnreadable})`. El puntero corrupto se resuelve con `resetCorruptPointer` (Kotlin), que es idempotente y se niega si el puntero es válido.
- **Salir de una sesión ajena:** `ForeignSessionSignOut.signOut()`.
  1. `logout` remoto con el refresh guardado, como intento.
  2. `SecureSessionStore.delete()`.
  3. Recálculo del acceso.
  - No toca SQLite.
- **Interfaz:** `AccessStatusScreen` muestra la acción según el §2 y `/recuperar` abre el formulario.
- **Espacios de nombres del almacén seguro (R3 de C).** Cada almacén borra sólo sus propias claves. `SecureSessionStore.delete()`, `ForeignSessionSignOut`, «Olvidé el PIN» y el bloqueo tras 10 fallos actúan sobre su espacio de nombres: la sesión (`agrocuentas_secure_session_v1`) o la credencial (`agrocuentas_owner_credential_v1`). **Nunca** llaman a `deleteAll()`. El llavero del respaldo de C (`agrocuentas_backup_keys_v1`) sobrevive a todos ellos por diseño (ADR F08-ADR-003 §3.6). Una prueba lo afirma.

## 4. Credencial local del titular (PIN)

| Aspecto | Decisión |
|---|---|
| Mecanismo existente | No hay un PIN en el código (`463d3ec`). Se crea **uno solo**, `LocalOwnerCredential`, y no se duplica en otros módulos |
| Dónde vive | En el almacén seguro de Android (`flutter_secure_storage` 11.2.0, cifrado con claves de Android Keystore), en un espacio de nombres propio, `agrocuentas_owner_credential_v1`. **Nunca** en SQLite, en un respaldo, en un log ni en texto legible |
| Qué se guarda | Un verificador `{versión, sal aleatoria de 16 bytes, PBKDF2-HMAC-SHA256 con ≥ 210 000 iteraciones, Member, tenant, enrolmentId aleatorio, fecha}`. Las iteraciones se miden en el dispositivo y se registran en la evidencia, no se suponen. La primitiva sale de una biblioteca mantenida: si C adopta `cryptography` (dint.dev) en su ADR, se usa su `Pbkdf2`; si no, se pide el turno de pubspec para ella. No se escribe un KDF propio |
| Límite declarado | Un PIN de 6 dígitos tiene 10⁶ valores. Si alguien extrajera el verificador del almacén seguro, lo probaría por fuerza bruta fuera del teléfono aunque use PBKDF2. Su protección real es que el almacén está cifrado con claves de Android Keystore no exportables, junto con el límite de intentos de la app. Por eso el PIN **no** protege los respaldos (§1), que usan una clave aleatoria de C |
| Forma del PIN | 6 dígitos. Se rechazan las secuencias triviales: todos iguales, ascendente o descendente |
| Enrolamiento | Sólo en el estado `activated`: vínculo activo y sesión legible del mismo Member y tenant. Hay **dos vías y ninguna otra**. **(a)** En `/titular/pin` (Más › PIN del titular, o «Configurar PIN» desde una acción): la contraseña de la cuenta con `confirmAccount` y la relectura del ámbito (§9). Sirve para enrolar y para restablecer. **(b)** Sólo el **primer** PIN del titular, justo después de confirmarlo en la primera activación, con la acreditación de activación (§4 bis). Nunca restablece. En las dos se pide dos veces el PIN y se guarda el verificador con el ámbito del vínculo. *Redacción anterior, sustituida el 2026-10-27:* «Sólo en el estado `activated`: vínculo activo y sesión legible del mismo Member y tenant. Requiere **acreditar en línea al mismo titular**: contraseña de la cuenta y la reautenticación existente (`reauthenticate`), que verifica el mismo registro de cliente y el ámbito. Después se piden dos veces el PIN y se guarda el verificador con el ámbito del vínculo» |
| Ejecución | El PBKDF2 se calcula **fuera del hilo de la interfaz** (`Isolate.run`), en el enrolamiento y en cada verificación. El tiempo en el teléfono se mide y se registra (R4 de C) |
| Comprobación | Funciona **sin red**: verificador local, comparación en tiempo constante y ámbito igual al vínculo activo. Si el vínculo cambió (otra base restaurada), el verificador **no vale** y hay que enrolar de nuevo |
| Intentos | El contador vive en el mismo almacén seguro y no se reinicia al cerrar la app. Tras 5 fallos seguidos hay una espera creciente: 30 s, 2 min y 10 min. Tras 10 fallos se bloquea y sólo se restablece acreditando al titular en línea. Un acierto pone el contador a cero |
| Recuperación del PIN | «Olvidé el PIN»: acreditar en línea al mismo titular, como en el enrolamiento, y enrolar de nuevo. **Sin red no se puede restablecer.** Restablecer el PIN **no** descifra copias ni recupera la clave del respaldo |
| Tras una restauración | El verificador **no viaja** en el respaldo. En otra instalación no existe: tras «Recuperar acceso», el titular enrola un PIN nuevo. En la misma instalación vale sólo si el vínculo de la base restaurada tiene el mismo Member y tenant; si no, se pide enrolar. **C lo invoca, no lo duplica** |
| Qué identifica | Una **autorización** del titular en esta instalación. No prueba quién sostenía físicamente el teléfono. |

### Interfaz para RF-13, RF-03 y C

Alineada con el código el 2026-10-27. La versión anterior describía `enroll({pin, pinConfirmation})` y un `resetAfterOnlineVerification` que nunca existieron: enrolar y restablecer son un solo camino.

```dart
class LocalOwnerCredential {
  Future<CredentialStatus> status(OwnerBindingContext? binding); // notEnrolled | enrolled | locked (lockedUntil) | requiresOnlineReset | scopeMismatch
  Future<void> enroll({required String pin, required String pinConfirmation,
      required OnlineOwnerProof? proof, required OwnerBindingContext binding}); // enrolar o restablecer
  Future<OwnerAuthorization> verify({required String pin, required AuthorizationPurpose purpose,
      required String subjectRef, required OwnerBindingContext binding});
  Future<String?> currentEnrolmentId();
  bool accepts(OwnerAuthorization authorization); // lo usa consumeOwnerAuthorization (§8)
}

class OwnerOnlineVerification {
  Future<OnlineOwnerProof?> verify({required String email, required String password,
      required OwnerBindingContext binding});                           // origen: contraseña (§9)
  Future<OnlineOwnerProof?> fromActivation({required OwnerBindingContext binding}); // origen: activación (§4 bis)
}
```

**Origen del comprobante.** `OnlineOwnerProof` lleva un origen privado: **contraseña** (`verify`) o **activación** (`fromActivation`). `enroll` acepta los dos sólo si los emitió la `OwnerOnlineVerification` configurada (§8). El de activación, además, sólo enrola cuando el titular no tiene un PIN propio en el almacén (§4 bis.4, comprobación 7).

**Propósitos** (`AuthorizationPurpose`):
- de A: `REVERSE_PURCHASE`, `REVERSE_APPLICATION`, `REVERSE_TRANSFER`, `CONFIRM_LATE_OPERATION` y `REJECT_LATE_OPERATION`;
- de C (R1): `SHOW_BACKUP_RECOVERY_KEY` y `ROTATE_BACKUP_RECOVERY_KEY`, con `subjectRef` = keyId en hex. Sólo **autorizan** mostrar o rotar la clave. El PIN no entra en ninguna derivación.
- Sin un PIN enrolado, C muestra la clave sin PIN **sólo** en su primer enrolamiento; para volver a mostrarla exige el PIN o la acreditación en línea. Aceptado.

**Consumo (R2 de C).** Al **consumirla**, en la misma transacción que la acción, el repositorio compara su `bindingId`, Member y tenant con el **vínculo activo en ese momento**, no sólo en `verify`. Así, una autorización emitida antes de una restauración (que `GuardedRestore` puede completar dentro de los 120 s) no vale después.

`OwnerAuthorization` es un objeto de **un solo uso**, de vida corta (120 s) y ligado a un propósito y a un objeto (por ejemplo `REVERSE_PURCHASE:<id>`). Se crea sólo en `verify`, con un constructor privado. El repositorio lo consume en la misma transacción que la acción. **Llamar al repositorio sin una autorización válida falla**: no basta con saltarse la pantalla.

Lleva `{enrolmentId, personId del titular, bindingId, Member, tenant, método LOCAL_PIN, verificadoEn}`. No lleva el PIN.

## 4 bis. Enrolamiento del PIN dentro de la activación (decisión del autor, Roderich Rendón, 2026-10-27)

- **Fecha real:** 2026-10-27 (America/La_Paz). Base: Mobile `main` `ed9c55c`, rama `feat/e12-pin-en-activacion`.
- **Fuente de la regla:** `_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`, sección E-12, y el análisis previo `_briefs/REVISION_INTEGRAL_MOB_2026-10-26/01_DECISIONES_DE_NEGOCIO.md` §4 (con el hallazgo A-15).
  - Sólo la **regla** es decisión del autor: el paso opcional y recomendado; una acreditación vinculada, con vigencia y consumo; sin guardar la contraseña; configurar más tarde y restablecer como hoy; el retorno a la revisión sin ejecución automática; la separación de secretos y la invalidación al restablecer.
  - No se atribuye aprobación del tutor ni de la Directiva.
  - Los criterios técnicos de esta sección son **diseño del frente**: las vigencias, las comprobaciones y los ajustes H1–H10 y las resoluciones del §4 bis.10, que salen de la revisión cruzada del 2026-10-27, «LISTO CON AJUSTES», sin bloqueantes.
- **Estado:** implementado en `e3af008` (HOST). Evidencia: `docs/evidence/F10_BLOQUE2_E12_PIN_EN_ACTIVACION.md`. EMULADOR el 2026-10-28 (`docs/evidence/F10_BLOQUE2_EMULADOR_2026-10-28.md`): E1 y E2, y E3 desde una reversión, ejecutados. Pendientes: E3 desde una tardía (no hay campaña cerrada en la siembra) y E4 (no se mide sin personas).
- **Trazabilidad:** RF-01, RF-13, RF-03, CU-01 y RNF-04.

**La regla.** Después de confirmar al titular se ofrece crear el PIN, aprovechando la acreditación en línea que el mismo titular acaba de hacer al activar. Es un paso opcional y recomendado. No basta con que exista una sesión. Fuera de ese momento, todo sigue como en el §4.

### 4 bis.1 Punto de partida (leído en `ed9c55c`)

| Tema | Dónde | Qué hace hoy |
|---|---|---|
| Activación | `first_activation_screen.dart:35-55`, `first_activation_providers.dart:90-126`, `first_activation_coordinator.dart:211-390` | La pantalla envía el correo y la contraseña. El controlador pasa `requiredScope` = el ámbito del vínculo activo, si lo hay (`first_activation_providers.dart:105-115`). El coordinador hace estos pasos: `login` (264); valida un agricultor activo con la sesión sin cliente registrado (398-406); si hay `requiredScope`, compara el Member y el tenant (267-271); llama a `registerClient` (283), `bindSessionClient` (295) y `/me` (310). `_validateCurrent` (408-425) exige la misma cuenta, el mismo correo, Member, tenant, sesión y registro. Después escribe con `commitAndVerify` (324-338). Sólo entonces emite `completed` (339). El estado de la interfaz no lleva identificadores (80-81) y la contraseña se borra del campo (`first_activation_screen.dart:48`) |
| Confirmación del titular | `app.dart:107-110`, `owner_setup_screen.dart:59-129`, `owner_binding_store.dart:201-261` | El router lleva `activationPendingOwner` a `/titular`. `_confirm` exige `allowsOwnerBinding`, el ámbito de la sesión legible (62) y `installationRef` (63). Crea el vínculo con `bindExistingPerson` o `bindNewPerson`, que también escriben `activated_installation`. Recalcula el acceso (110) y va a `/` (122). El almacén devuelve el vínculo **releído después** de la transacción (226, 260) y la pantalla lo descarta |
| Enrolamiento del PIN | `more_screen.dart:66-71`, `app.dart:283-286`, `owner_credential_screen.dart:41-105, 139-192` | Exige `activated` (109-111, 139-144). Pide el correo y la contraseña (147-175) y obtiene un comprobante con `OwnerOnlineVerification.verify` (`local_owner_credential.dart:106-115`). Después pide dos veces el PIN y llama a `enroll` (452-492) |
| Qué prueba la acreditación en línea | `remote_session_coordinator.dart:269-295, 466-490, 511-518`; `local_owner_credential.dart:112-113` | `confirmAccount` hace un **login nuevo con la contraseña contra Central**. Exige que `account.id`, `member.id` y `tenant.id` sean iguales a los de la sesión guardada, un agricultor activo y la sesión sin registro de cliente. Después cierra ese login con `logout` (289-291) sin tocar la sesión guardada ni el guard. Luego se relee el Member y el tenant de la sesión guardada y se comparan con el vínculo. **No comprueba la instalación** (`installationClientId` ni `registrationId`: el login nuevo no se vincula al cliente) **ni el `bindingId`**. La reautenticación (`reauthenticate`, 297-432) sólo recupera una sesión en cuarentena (313-318) y no se usa para el PIN (§9) |
| Artefacto que produce | `local_owner_credential.dart:74-84, 434-447`; `owner_credential_screen.dart:27` | Un `OnlineOwnerProof` `{scope, issuedAt, emisor privado, _used}`, sólo en memoria, en el estado de la pantalla. `_requireProof` lo acepta sólo si lo emitió **la misma instancia** configurada (`identical`), si no se usó, si tiene el mismo ámbito, si tiene 5 minutos o menos y si no está fechado en el futuro. Se marca usado antes del KDF. La forma y la igualdad del PIN se validan antes (472-477), así que un error de tecleo no gasta el comprobante |
| ¿Hay ya una «acreditación reciente» reutilizable? | `remote_session_coordinator.dart:57-58, 128-260`; `existing_session_providers.dart:12-23`; `remote_session_providers.dart:48` | **No.** `remoteAvailable` puede venir de `refreshOnDemand`, que no usa contraseña. `runtimeSecureCommitCompletedProvider` es un booleano sin identidad ni vigencia. El access token en memoria sirve a Sync y no prueba que se conozca la contraseña. Lo único acotado es el `OnlineOwnerProof` de 5 minutos, que sólo existe dentro de `OwnerCredentialScreen` |
| Invalidación al restablecer | `local_owner_credential.dart:347-362, 406-413, 488-490, 186-228`; `agro_repository.dart:1673-1682, 2644-2653` | Enrolar y restablecer son el mismo camino, `enroll`, en la cola del almacén. `enroll` borra el enrolamiento conocido antes de escribir el verificador y lo fija después. `accepts` exige el mismo almacén y el enrolamiento vigente. El repositorio consume la autorización dentro de la transacción de la acción. No hay una generación numérica: la «época» del PIN es el `enrolmentId` aleatorio |
| Operación pendiente (A-15) | `owner_reversal_flow.dart:16-44`; `owner_credential_screen.dart:213-257, 198-201` | `requestOwnerApproval` pide el motivo y después llama a `requestOwnerAuthorization`. Sin PIN aparece «Esta acción la autoriza sólo el titular con su PIN. Configure el PIN del titular primero.» (231-233). «Configurar PIN» hace `context.push('/titular/pin')` **sin esperar** y devuelve null (255-256). El llamador abandona la acción: `purchases_screen.dart:130-160`, `applications_screen.dart:72`, `transfers_screen.dart:40`, `late_operations_screen.dart:137-180` y, en F08, `remote_backup_providers.dart:105-125`. «Volver» cierra sin resultado. No se ejecuta nada: es un problema de uso, no de seguridad |

**Identidad (C-6).** En Mobile la identidad es `account.id`, `member.id` y `tenant.id` del contexto Auth V2. No se lee ningún JWT ni su `sub`.

### 4 bis.2 Flujo propuesto

**Única secuencia válida (H2):**
1. Instalación nueva (origen `newUnderPolicy`), sin sesión guardada y sin vínculo de titular.
2. «Activar cuenta» termina en `completed`. El acceso pasa a `activationPendingOwner`.
3. «Confirmar titular» en `/titular`. El acceso pasa a `activated`.
4. Oferta del PIN.

Cualquier otra secuencia anula la acreditación o no la crea:
- una base histórica (`legacyUnbound`), donde el titular se elige después, desde el Inicio, y no dentro de este flujo;
- llegar a `activated` sin haber confirmado al titular en este flujo, es decir, entrar al shell antes;
- cualquier otro estado de acceso.

1. **«Activar cuenta»: sin cambios visibles.** Al terminar con `completed`, el controlador emite la *acreditación de activación* (§4 bis.3) sólo si se cumplen todas estas condiciones; si no, no emite nada:
   - al empezar no había sesión (`effectiveLocalSessionProvider` = `noLocalSession`);
   - `requiredScope == null`;
   - sin `replaceUnreadableSession`;
   - al recibir `completed`, SQLite no tiene un vínculo activo y su origen es `newUnderPolicy`, por lectura directa (H7).
2. **«Titular de los datos»: sin cambios visibles hasta «Confirmar titular».** Si el vínculo se crea con el acceso en `activationPendingOwner`, se ata a la acreditación (§4 bis.3, H5). La oferta del paso 3 se abre sólo si se cumplen **todas** estas condiciones; si falta alguna, la acreditación se borra y se sigue a `/` como hoy:
   - la acreditación se ató a este vínculo;
   - el acceso recalculado es `activated`;
   - el estado de la credencial para este vínculo se pudo leer y es `notEnrolled` o `scopeMismatch`. Si `status()` lanza, no hay oferta (H8). Con `enrolled`, `locked` o `requiresOnlineReset` tampoco hay oferta, de modo que **un restablecimiento nunca usa esta acreditación**. Además, la credencial lo vuelve a comprobar dentro de su cola (§4 bis.4, comprobación 7).
3. **«PIN del titular», modo de activación** (`/titular/pin/activacion`; no pide el correo ni la contraseña). Textos de pantalla:
   - Encabezado: «Titular vinculado.», seguido del aviso de modalidad que antes salía en el mensaje emergente («Usa inventario compartido; puede cambiarlo en Operaciones › Más › Modo de uso.» o su variante para el inventario propio, o el aviso de que no se pudo cambiar la modalidad).
   - Utilidad: «Le recomendamos crear ahora el PIN del titular. Con él, el titular autoriza en este teléfono, incluso sin conexión, las acciones que sólo él puede aprobar: revertir una operación o revisar una operación tardía.»
   - Por qué ahora: «Acaba de confirmar su cuenta en línea, así que ahora no hace falta volver a escribir la contraseña. Si lo deja para después, tendrá que confirmar la cuenta en línea con su correo y su contraseña.»
   - Separación: «El PIN no se guarda en el respaldo y no sirve para descifrar copias: la clave de recuperación del respaldo es otra. Tampoco reemplaza la contraseña de su cuenta.»
   - Formulario: «Elija un PIN de 6 dígitos que no sea una secuencia.», con los campos «PIN» y «Repita el PIN».
   - Botones: «Crear PIN» (principal) y «Ahora no». Atrás equivale a «Ahora no».
   - Éxito: «PIN del titular creado. Funciona sin conexión.», con el botón «Continuar», que lleva a `/`.
   - «Ahora no» lleva a `/` con este mensaje: «Puede crear el PIN más tarde en Operaciones › Más › PIN del titular. Entonces se le pedirá confirmar su cuenta en línea.»
   - Acreditación vencida o anulada: «Ya no se puede crear el PIN con la confirmación de la activación: pasó el tiempo, salió de la aplicación o cambió la cuenta, la instalación o el titular. Puede crearlo más tarde en Operaciones › Más › PIN del titular, confirmando su cuenta en línea.», con «Continuar».
   - Ya había un PIN propio (comprobación 7): «Ya hay un PIN del titular en este teléfono. Para cambiarlo, confirme su cuenta en línea en Operaciones › Más › PIN del titular.», con «Continuar».
   - Errores de forma del PIN: los mensajes de hoy (`pinProblem` y «Los dos PIN no coinciden.»). Se comprueban **antes** de tocar la acreditación, así que no la gastan.
   - Fallo al guardar: «No se pudo guardar el PIN. Puede crearlo más tarde en Operaciones › Más › PIN del titular, confirmando su cuenta en línea.» En este punto la acreditación ya se consumió.
4. **El paso 3 no hace ninguna petición de red.**

### 4 bis.3 La acreditación de activación

| Aspecto | Decisión de diseño |
|---|---|
| Qué la origina | **Sólo** `FirstActivationController.activate`, con las condiciones del paso 1 (H7). Se crea después de la propia llamada a `recovered()` del controlador. **No** la originan: el arranque con una sesión guardada, `refreshOnDemand`, `reauthenticate`, `confirmAccount`, «Recuperar acceso» (`access_recovery.dart:139-199`, que usa otro coordinador e incluye la reconstrucción sólo de la sesión, `rebuildSessionOnly`), una activación con el titular ya vinculado ni un resultado `localCommitUnknown`, que no es `completed` |
| Qué contiene | `accountId`, `memberId`, `tenantId`, `sessionId`, `registrationId` e `installationClientId` de la sesión confirmada (los del `/me` validado y del candidato escrito); el instante de emisión en el reloj de pared; y un cronómetro monotónico. Al vincular se añaden **una sola vez** `bindingId`, `personId` y `boundAt` del vínculo creado. **No** contiene la contraseña, el refresh ni el access token. `toString` va redactado y nunca se registra |
| A qué queda atada | **Identidad:** cuenta, Member y tenant. **Sesión:** `sessionId` y `registrationId`. Un refresh conserva los dos. Una reautenticación conserva `registrationId`, porque vuelve a vincular el mismo registro, pero cambia `sessionId`. Una sesión nueva cambia los dos. **Instalación:** `installationReference(installationClientId)` frente a la identidad actual (`installationRefProvider`) y a `activated_installation` de la base. **Vínculo:** nace sin vínculo (C-4) y se ata una sola vez al que crea el paso 2. Ese vínculo tiene que estar activo, con el mismo Member y tenant y un `boundAt` posterior o igual a la emisión. El almacén lo devuelve desde **dentro** de su transacción (H5) |
| Dónde vive | **Sólo en memoria**, en un campo privado del `FirstActivationController` (Notifier de Riverpod). Nunca en SQLite, en el almacén seguro, en un respaldo ni en un log. **Por qué:** (a) tiene que morir con el proceso; si sobreviviera a un reinicio, días después cualquiera con el teléfono desbloqueado podría crear el PIN sin la contraseña; (b) el almacén seguro protege un secreto contra la lectura, pero aquí el riesgo es la capacidad que concede, no su lectura, y persistirla exigiría además otro mecanismo de borrado y de vigencia; (c) el flujo es continuo y no la necesita tras reiniciar. **Si el Notifier se recrea**, por ejemplo al invalidarse una dependencia, la acreditación se pierde y la oferta no aparece: falla cerrado (H6). Tampoco se escribe si `ref.mounted` es falso después de una espera |
| Vigencia | **10 minutos** desde `completed`, medidos con el reloj de pared y con un cronómetro monotónico. Vence en cuanto **cualquiera** de los dos los supera, y también si el reloj de pared marca una hora anterior a la emisión. **Además se anula al pasar la app a `hidden` o `paused`** (pantalla apagada o cambio de app; H3). `inactive`, por ejemplo con la cortina de notificaciones, no la anula. El comprobante que se emite desde ella conserva la regla existente de 5 minutos y suma un tope `notAfter` = el vencimiento de la acreditación: entre la contraseña y el PIN guardado pasan como mucho 10 minutos. **Justificación:** el paso 2 incluye elegir o crear al titular y la modalidad, con sus explicaciones; con un facilitador puede superar los 5 minutos. Se mantienen 10 (D-1), pero **se bajará a 5 si la medición E4 en el emulador da una mediana por debajo de unos 3 minutos** entre `completed` y «Crear PIN» |
| Consumo | Se **retira de forma síncrona**: entre leer el campo y ponerlo a null no hay ningún `await`. Ocurre en cuanto se pulsa «Crear PIN» con un PIN de forma válida y repetido igual. `OwnerOnlineVerification.fromActivation` la retira primero y la comprueba después (§4 bis.4). Si vale, emite un `OnlineOwnerProof` del **mismo emisor configurado**, de origen *activación*. `_requireProof` marca usado ese comprobante. Hay un solo uso: la segunda llamada encuentra el campo vacío |
| Anulación | Se borra en todos estos casos: «Ahora no» o Atrás en el paso 3; salir de esa pantalla por cualquier vía (`dispose`, con el controlador guardado al entrar, sin usar `ref` en `dispose`; H9); salir de «Titular de los datos» sin vincular; el vencimiento; `hidden` o `paused`; cualquier error al emitir o al enrolar, porque ya se retiró; un cambio de sesión en ejecución (`runtimeSessionTransitionProvider`); un estado de acceso fuera de la secuencia válida; llegar a `activated` sin vínculo atado; una llamada nueva a `activate`; el fin del proceso. **GuardedRestore la borra explícitamente antes de sustituir la base** (H4). Estos borrados son una **ayuda**: la **garantía** son las comprobaciones 1–7 al consumir (§4 bis.4), que la rechazan si algo cambió aunque un borrado no hubiera llegado a ejecutarse |

### 4 bis.4 Por qué no basta una sesión cualquiera

Una sesión guardada dura días y se renueva con un refresh, sin contraseña. La tiene quien sostenga el teléfono desbloqueado. Si bastara para enrolar, esa persona podría crear el PIN o, peor, restablecerlo, con lo que invalidaría las autorizaciones del titular (§8). Después podría autorizar reversiones, que es justo lo que el PIN protege. El PIN tiene que nacer de una **prueba reciente de conocer la contraseña, dentro del mismo flujo**.

**Comprobaciones al consumir** (`fromActivation` y `enroll`). Todas fallan cerradas: devuelven null o lanzan `CredentialException`, y no escriben nada. Si falta cualquier dependencia de `fromActivation`, devuelve null (H8).
1. **Existe:** sólo `activate` escribe el campo y no hay un método público para fijarlo. Sin acreditación no hay oferta, y `/titular/pin` sigue pidiendo la contraseña.
2. **Vigente** según los dos relojes, y el reloj de pared no es anterior a la emisión. Se comprueba al retirarla y otra vez justo antes de emitir el comprobante.
3. **La misma sesión:** se relee la sesión guardada. Tiene que estar disponible, y `accountId`, `memberId`, `tenantId`, `sessionId`, `registrationId` e `installationClientId` tienen que ser iguales a los de la acreditación.
4. **La misma instalación:** `installationReference(installationClientId)` de la acreditación, `installationRefProvider` y `activated_installation` de la base coinciden.
5. **El mismo vínculo:** el vínculo activo tiene el `id`, el `personId`, el `boundAt` y el ámbito que se ataron, y es el `OwnerBindingContext` con el que se enrola. El comprobante de activación guarda además `bindingId` y `personId`, y la credencial los vuelve a comparar en `_requireProof` (ajuste 6 de la revisión de la implementación). Así la comprobación no depende sólo de la pantalla.
6. El acceso es `activated`.
7. **Primer PIN del titular (H1, D-3).** Dentro de la cola de la credencial, la misma que serializa `enroll` y `verify`, un comprobante de origen *activación* se rechaza con `CredentialException`, y sin escribir nada, si el verificador leído existe, se puede decodificar y tiene el mismo ámbito del vínculo, esté `enrolled`, `locked` o `requiresOnlineReset`.
   - Con un verificador de **otro** Member (`scopeMismatch`) se permite. Ese verificador desaparece al sobrescribirse, y con él valen ya nada las autorizaciones emitidas con él: el enrolamiento conocido cambia (§8).
   - **Un verificador ilegible cuenta como `notEnrolled` y se sobrescribe**, igual que hoy (`_verifier` devuelve null).

Sólo entonces se emite el `OnlineOwnerProof`, con el emisor configurado (por eso `enroll` lo acepta, como en el §8), de origen *activación* y con `notAfter`.

**Frontera.** Es la misma del §8: el código dentro del proceso puede hacer cualquier cosa. Lo que queda cerrado, por las API públicas: no se obtiene un comprobante de activación sin una activación completada en este proceso, ni desde una sesión anterior, ni con otra cuenta, ni en otra instalación, ni para cambiar un PIN existente del titular.

### 4 bis.5 Qué no cambia

- **Configurar más tarde:** `/titular/pin`, desde «Más» o desde el diálogo, sigue pidiendo el correo y la contraseña (`confirmAccount` y la relectura del ámbito), con el comprobante de 5 minutos y de un solo uso. Sin red no se puede.
- **Restablecer un PIN olvidado o bloqueado:** igual que hoy. La acreditación de activación nunca reemplaza un verificador del titular (comprobación 7).
- **Invalidación al restablecer:** el modo de activación usa el mismo `enroll`, con la cola por almacén y el borrado y la fijación de `knownEnrolmentId`. `accepts` y `consumeOwnerAuthorization` no cambian.
- **Separación de secretos:**
  - la contraseña sólo viaja a Central al activar y no se retiene; no está en la acreditación;
  - el PIN sólo produce el verificador PBKDF2 en `agrocuentas_owner_credential_v1`;
  - la clave del respaldo sigue en `agrocuentas_backup_keys_v1`, intacta, y el PIN no deriva nada.
  - La acreditación de activación no es ninguno de los tres: es una capacidad que vive en memoria.
- **El PIN que se teclea al enrolar nunca produce una `OwnerAuthorization`.** Enrolar y autorizar siguen separados.
- Sin cambios: los 6 dígitos, las secuencias triviales, los intentos, las esperas, el KDF fuera del hilo de la interfaz y las restauraciones (el verificador no viaja).
- **Restauración y «Recuperar acceso» (D-2):** no se amplía. Tras restaurar en otro teléfono, «Recuperar acceso» (incluida la reconstrucción sólo de la sesión, `rebuildSessionOnly`) o la reactivación con el titular ya vinculado, el PIN se enrola por la vía (a), con contraseña.

### 4 bis.6 Retorno a una operación pendiente (A-15)

Máquina de estados de `requestOwnerAuthorization` (y, a través de ella, de `requestOwnerApproval`):

```
REVISIÓN       --Continuar-------------------------> COMPROBAR_PIN
COMPROBAR_PIN  --sin vínculo de titular------------> CANCELADA (texto del §5, sin «Configurar PIN»)
COMPROBAR_PIN  --PIN válido para el vínculo--------> PEDIR_PIN
COMPROBAR_PIN  --bloqueado con espera--------------> CANCELADA (como hoy, sin «Configurar PIN»)
COMPROBAR_PIN  --sin PIN, ámbito distinto o
                 restablecimiento en línea---------> SIN_PIN
SIN_PIN        --Cerrar----------------------------> CANCELADA
SIN_PIN        --Configurar PIN--------------------> CONFIGURANDO (push esperado de /titular/pin)
CONFIGURANDO   --vuelve sin PIN creado-------------> CANCELADA
CONFIGURANDO   --vuelve con PIN creado-------------> REVALIDAR
REVALIDAR      --ya no aplica o cambió el titular--> CANCELADA (con aviso)
REVALIDAR      --sigue aplicando-------------------> REVISIÓN (una sola vuelta)
PEDIR_PIN      --Cancelar--------------------------> CANCELADA
PEDIR_PIN      --PIN correcto y «Autorizar»--------> AUTORIZADA
AUTORIZADA     --el llamador llama al repositorio, que revalida y consume en la transacción
```

**Reglas:**
1. Se espera `context.push<bool>('/titular/pin')`. La pantalla devuelve `true` sólo si `enroll` terminó en esa visita. «Volver» y Atrás del sistema devuelven ese mismo resultado: la pantalla tiene `PopScope` (H9). Un fallo devuelve `false`.
2. **REVALIDAR:**
   - se relee el vínculo (`ownerBindingContextReaderProvider`), que tiene que tener el mismo `bindingId` que al empezar;
   - el `status` de la credencial tiene que ser `enrolled`;
   - una función opcional `revalidate`, que da cada llamador, relee el objeto. Devuelve null si sigue aplicando, o el motivo si ya no aplica. Los efectos que se muestran son los de la revisión original, porque el objeto se comprobó sin cambios; el repositorio calcula los efectos reales.
   - Por llamador: compra, aplicación o transferencia sin revertir; borrador tardío todavía `PENDING`; en F08, el mismo `activeKey().keyId`. Todo es local, y las lecturas se hacen **sólo** en este camino.
3. **Vuelta a la revisión:**
   - en las reversiones reaparece el diálogo del motivo con los mismos efectos y **el motivo ya escrito y editable** (D-5), encabezado por «PIN del titular configurado. Revise la operación y autorícela con su PIN.»; después, el diálogo del PIN. El texto sirve también para restablecer, rechazar y F08;
   - en las operaciones tardías y en F08, el diálogo del PIN con sus efectos y el mismo encabezado.
4. **Nunca se ejecuta sola:**
   - el enrolamiento no devuelve ninguna autorización;
   - el PIN recién tecleado no se reutiliza;
   - no hay temporizadores ni acciones automáticas.
   - Hay que teclear el PIN en el diálogo y pulsar «Autorizar». Después, el repositorio revalida y consume dentro de la transacción (`agro_repository.dart:1673-1682, 2644-2653`), con comprobaciones de existencia como la de `agro_repository.dart:2159`.
5. **Una sola vuelta.** Si al volver sigue sin haber un PIN válido, termina en CANCELADA con «No se configuró el PIN. La operación no cambió.».
6. Si la pantalla de la operación se cerró entretanto (`context.mounted` falso), termina en CANCELADA sin ejecutar nada.
7. **App matada en CONFIGURANDO:** la operación pendiente sólo vivía en memoria. Tras reiniciar no se ejecuta nada y se empieza de nuevo desde la lista.
8. **F08 incluido (C-5, D-4).** Comparte la función, y el retorno nunca ejecuta nada. Para evitar dos mensajes, F08 la llama sin los avisos propios del retorno y conserva el suyo («Hace falta la autorización del titular en este teléfono. No se mostró ni se cambió la clave.»). Las pruebas F08 no cambian sus aserciones.
9. **Textos del retorno:**
   - «No se configuró el PIN. La operación no cambió.»
   - «Esta operación ya no está pendiente: <motivo>. No se hizo ningún cambio.»
   - «El titular de estos datos cambió. No se hizo ningún cambio.»
   - Si `revalidate` lanza: «No se pudo comprobar la operación. No se hizo ningún cambio.»
   - Sin vínculo: «Esta acción la autoriza sólo el titular con su PIN. Para habilitarla, active la aplicación, elija el titular y configure el PIN.»
10. El retorno usa siempre la vía (a), con contraseña. En ese momento no hay una acreditación de activación, porque se borra al salir del paso 3 o al no ofrecerse.

### 4 bis.7 Matriz de amenazas

| # | Amenaza | Resultado esperado | Prueba |
|---|---|---|---|
| T1 | **Identidad diferente:** otra cuenta, Member o tenant entre la activación y el PIN (salir de la sesión y activar otra; vínculo con otro ámbito) | No se ofrece, o `fromActivation` devuelve null. El almacén no se escribe. Más tarde el PIN pide la contraseña | U2 |
| T2 | **Instalación diferente:** `installationRef` actual, `activated_installation` o `installationClientId` de la sesión distintos | null, sin escribir | U3 |
| T3 | **Acreditación vencida:** más de 10 minutos en cualquiera de los dos relojes, o reloj atrasado | null, sin escribir | U4 |
| T4 | **Reuso:** doble toque, segundo intento tras un error o re-enrolar con la misma acreditación para cambiar el PIN | Vale el primer uso; los siguientes dan null o `CredentialException`; se escribe un solo verificador | U5 |
| T5 | **Cancelación:** «Ahora no», Atrás o salir de «Titular de los datos» sin vincular | Acreditación borrada y ningún PIN. `/titular/pin` pide el correo y la contraseña | U6, W8 |
| T6 | **Fallo de red** | Durante la activación: no hay acreditación ni oferta, porque la activación falla como hoy. Después de activar: el paso 3 no usa la red y el PIN se crea dentro de la vigencia. Configurar más tarde sin red sigue siendo imposible | U9 |
| T7 | **Restauración de un respaldo** dentro de la ventana, del mismo titular o de otro, venga o no de otro teléfono | GuardedRestore la borra antes de sustituir la base. Además, el vínculo restaurado no coincide en `id`, `personId` y `boundAt`. El verificador no viaja. En la base restaurada en otro teléfono no hay acreditación, porque nunca se guarda | U10 |
| T8 | **App matada a mitad:** (a) tras activar, antes de elegir el titular; (b) en la oferta; (c) durante el KDF de `enroll`; (d) en CONFIGURANDO desde una operación | (a) y (b): la acreditación se pierde; tras reiniciar no hay oferta y el PIN pide la contraseña. (c): el comprobante ya está usado; si el verificador no llegó a escribirse queda `notEnrolled`, y si se escribió el PIN vale, como hoy. (d): no se ejecuta nada | U8, W6 |
| T9 | **Una sesión cualquiera:** arranque con sesión guardada, refresh, reautenticación, «Recuperar acceso» o activación con el titular ya vinculado | No hay acreditación y no hay oferta | U11 |
| T10 | **Usarla para restablecer** un PIN existente, olvidado o bloqueado | No se ofrece, y la credencial la rechaza en su cola aunque se llegue por otro camino | U12 |
| T11 | **Fabricarla** o fabricar el comprobante desde otra instancia | `enroll` rechaza un comprobante de otro emisor (§8) y el campo no tiene un escritor público | U15 y las pruebas existentes del §8 |
| T12 | **Cambio de titular** dentro del mismo Member (`changeOwner`) en la ventana | El vínculo es distinto: null | U2 |
| T13 | **Otra persona con el teléfono** durante los 10 minutos | **Límite declarado**, igual que hoy con el comprobante de 5 minutos tras la contraseña. Lo mitiga que la oferta sea inmediata y se anule al salir, al apagar la pantalla o al cambiar de app | — |
| T14 | **Sesión revocada en el servidor** dentro de la ventana | **Límite declarado:** el paso 3 no consulta la red. La próxima operación remota detecta la revocación | — |
| T15 | **Retorno a la operación** que se ejecuta solo o con datos viejos | Nunca: exige el PIN y «Autorizar», y se revalida en la interfaz y en la transacción | W1-W5 |
| T16 | **La app pasa a segundo plano** (pantalla apagada, cambio de app) durante la ventana | Al pasar a `hidden` o `paused` la acreditación se borra y la oferta muestra el texto de anulada | U13 |
| T17 | **Otro camino enrola** entre la comprobación de la oferta y la escritura (por ejemplo, `/titular/pin` con contraseña) | La comprobación 7, dentro de la cola, ve el verificador del titular y rechaza sin escribir | U12 |
| T18 | **Escritura de la sesión con resultado incierto** (`localCommitUnknown`) | No es `completed`: no hay acreditación | U11 |
| T19 | **El Notifier se recrea** | La acreditación se pierde: no hay oferta (falla cerrado) | U8 |
| T20 | **Base histórica** (`legacyUnbound`) en la que se activa y se sale al shell para elegir el titular más tarde | No se emite acreditación (origen histórico) y no hay oferta | U14 |
| T21 | **Cambio de cuenta o de rol en el servidor** dentro de la ventana (cuenta desactivada, rol distinto del de agricultor) | **Límite declarado:** el paso 3 no consulta la red, así que no lo detecta. Lo hará la próxima operación remota | — |

### 4 bis.8 Cambios por archivo

| Archivo | Cambio |
|---|---|
| `lib/services/auth/first_activation_coordinator.dart` | Un getter `committedIdentity`, sin token: cuenta, Member, tenant, sesión, registro e `installationClientId`. Se fija sólo al emitir `completed` y se limpia al empezar cada `activate`. `FirstActivationState` no cambia y sigue sin identificadores |
| `lib/services/auth/activation_owner_evidence.dart` (nuevo) | `SessionIdentity`, `ActivationBindingRef` y la acreditación: redactada, con la vigencia de los dos relojes y `attachBinding`, que se ata una sola vez |
| `lib/services/auth/first_activation_providers.dart` | El campo privado y su emisión con las condiciones H7. Expone `takeActivationEvidence()` (síncrona), `attachOwnerBinding(...)`, `discardActivationEvidence()` y `hasActivationEvidence`. Oyentes de sesión, de acceso y del ciclo de vida (H3) |
| `lib/services/auth/local_owner_credential.dart` | El origen privado del comprobante y `notAfter`, que comprueba `_requireProof`. La comprobación 7 dentro de `_enroll`. `OwnerOnlineVerification.fromActivation` con sus dependencias opcionales (H8). `verify` no cambia |
| `lib/services/auth/local_owner_credential_providers.dart` | Conecta esas dependencias: la sesión guardada, `installationRef`, `activated_installation`, el vínculo activo y el acceso |
| `lib/data/owner_binding_store.dart` | `bindExistingPerson` y `bindNewPerson` devuelven la fila insertada leída **dentro** de la transacción (H5) |
| `lib/guarded_restore.dart` | `discardActivationEvidence()` antes de sustituir la base (H4) |
| `lib/presentation/screens/owner_setup_screen.dart` | Conserva el vínculo, lo ata, decide la oferta y borra la acreditación al salir sin vincular. No usa `ref` en `dispose` (H9) |
| `lib/presentation/screens/owner_credential_screen.dart` | El modo de activación y sus textos, y `PopScope` con el resultado. `requestOwnerAuthorization` espera el `push`, revalida y vuelve a la revisión (parámetros `revalidate` y `announceReturn`) |
| `lib/presentation/widgets/owner_reversal_flow.dart` | La vuelta a la revisión con el motivo ya escrito |
| `purchases_screen.dart`, `applications_screen.dart`, `transfers_screen.dart`, `late_operations_screen.dart`, `services/backup/remote_backup_providers.dart` | Pasan `revalidate` |
| `lib/app.dart` | La ruta `/titular/pin/activacion`, fuera del shell |
| Sin cambios | `secure_session_store.dart`, `remote_session_coordinator.dart`, la lógica de consumo de `agro_repository.dart` y el llavero del respaldo |

### 4 bis.9 Pruebas, por caso

**Unidad y servicio** (`test/e12_activation_evidence_test.dart`):
- **U1. Camino feliz.** Emitir, atar, `fromActivation` y `enroll`: el estado pasa a `enrolled`, sin ninguna petición HTTP.
- **U2. Identidad diferente.** Ámbito del vínculo distinto, sesión de otra cuenta o con otra sesión, y vínculo distinto del atado. En todos: null y el almacén sin escribir.
- **U3. Instalación diferente.** `installationRef`, `activated_installation` o `installationClientId` distintos: null.
- **U4. Vencida.** En todos los casos, null:
  - 10 min + 1 s en los dos relojes;
  - 10 min + 1 s **sólo en el reloj de pared**, con el cronómetro en cero;
  - el cronómetro por encima, con el reloj de pared quieto;
  - el reloj atrasado;
  - un comprobante usado después de `notAfter`.
- **U5. Reuso.** Segundo `fromActivation`: null. Segundo `enroll` con el mismo comprobante: `CredentialException`.
- **U6. Cancelación.** Tras `discardActivationEvidence()`, el campo queda vacío.
- **U8. Recreación del Notifier.** Un contenedor o Notifier nuevo no tiene acreditación.
- **U9. Red.** Si la activación falla por conexión, no hay acreditación. Después de activar, `fromActivation` no hace peticiones.
- **Comprobación 5 en la credencial.** Un comprobante de activación no enrola otro `bindingId` ni otro `personId`, sin escribir nada. Con su vínculo, el mismo comprobante, que no se gastó, sí enrola.
- **U10. Restauración.** Un vínculo con el mismo `id` y el mismo ámbito pero otro `boundAt` da null.
- **U11. Otros orígenes.** Una activación con `requiredScope`, con sesión al empezar, con un vínculo en SQLite o con `localCommitUnknown` no emite.
- **U12. Comprobación 7.** Con un verificador del titular en `enrolled`, `locked` o `requiresOnlineReset`: `CredentialException` sin escribir. Con `scopeMismatch` o con un verificador ilegible: se enrola.
- **U13. Ciclo de vida.** `hidden` o `paused` la borran; `inactive` no.
- **U14. Base histórica.** No se emite.
- **U15. Mutaciones.** Cada una tiene que hacer fallar su prueba:
  - quitar la comparación de `sessionId` (U2);
  - quitar el vencimiento por los dos relojes (U4);
  - quitar sólo el vencimiento por reloj de pared (U4, caso «sólo reloj de pared»);
  - no retirar la acreditación en `takeActivationEvidence` del controlador. La detecta la U1 de la emisión real («segunda retirada vacía»), no la U5: la U5 usa un doble de la retirada;
  - quitar la comprobación del vínculo vigente en `fromActivation` (U10);
  - quitar la comparación de `bindingId` y `personId` en `_requireProof` (comprobación 5 en la credencial);
  - quitar la comprobación 7 (U12).

**Pantalla** (`test/e12_pin_offer_screen_test.dart`, `test/e12_pending_operation_return_test.dart`):
- La oferta muestra los textos del §4 bis.2 sin `pin-email` ni `pin-password`. La pantalla de anulada. «Ahora no» y su mensaje.
- **W1.** Reversión sin PIN → «Configurar PIN» → enrolar → volver: reaparece la revisión con el motivo. El repositorio **no** se llama hasta teclear el PIN y pulsar «Autorizar», y la compra sigue sin revertir antes de autorizar.
- **W2.** Volver sin enrolar: CANCELADA, la base intacta y el texto del §4 bis.6.
- **W3.** La operación se revirtió durante la configuración: aviso, sin diálogo y sin llamar al repositorio.
- **W4.** Operación tardía: no se confirma ni se rechaza sola.
- **W5.** Sin vínculo: CANCELADA con el texto del §5, sin «Configurar PIN».
- **W6.** Reinicio en CONFIGURANDO: no se ejecuta nada.
- **W7.** Restablecer el PIN invalida una autorización anterior: se rechaza.
- **W8.** Salir de «Titular de los datos» sin vincular, o de la oferta, la borra.
- **W8b.** Si «Titular de los datos» se desmonta **después** de vincular y antes de la oferta, la borra (ajuste 3).
- **Más casos de retorno** (ajuste 2):
  - reversión de una aplicación (W1b) y de una transferencia (W1c);
  - tardía resuelta mientras se configuraba el PIN (W3b);
  - titular cambiado (W5b);
  - `revalidate` que lanza (W3c);
  - `requiresOnlineReset` → «Configurar PIN» → restablecer con contraseña → vuelve a la revisión sin ejecutar (W2c);
  - en F08, la misma `keyId` vuelve al diálogo del PIN, una clave cambiada no lo pide, y en los dos casos queda un solo aviso, el de F08.

Se mantienen en verde, sin cambiar sus aserciones: `f03_local_owner_credential_test`, `f03_owner_online_confirmation_test`, `first_activation_coordinator_test`, `first_activation_screen_test`, `f03_access_recovery_test`, `f03_access_recovery_app_test`, `f04_owner_binding_test`, `f04_rf03_late_screen_test`, `f04_rf13_reversal_audit_test`, `f08_recovery_key_owner_pin_test` y las demás pruebas F08 que tocan el PIN.

**Emulador** (2026-10-28, `docs/evidence/F10_BLOQUE2_EMULADOR_2026-10-28.md`: E1, E2 y E3 desde una reversión ejecutados; E3 desde una tardía y E4 no ejecutados):
- **E1.** Activación, titular, PIN sin contraseña y reversión autorizada sin red.
- **E2.** «Ahora no» y, después, el PIN con contraseña.
- **E3.** Retorno desde una reversión y desde una operación tardía.
- **E4.** Medición del tiempo entre `completed` y «Crear PIN» (D-1).

### 4 bis.10 Contradicciones y dudas: resoluciones

Resoluciones de la revisión cruzada del 2026-10-27, dentro de lo aprobado. Son diseño del frente, no decisiones nuevas del autor.

| # | Qué era | Resolución |
|---|---|---|
| C-1 | La fila «Enrolamiento» del §4 exigía la contraseña y `reauthenticate` (ya desfasada por el §9) | Reescrita con las dos vías (a) y (b). Se conserva la redacción anterior, marcada «sustituida el 2026-10-27» |
| C-2 | La interfaz del §4 no coincidía con el código | Alineada. Se retira `resetAfterOnlineVerification` y se documenta el origen del comprobante |
| C-3 | `docs/12_AUTHENTICATION.md` afirmaba que no hay autenticación ni PIN | Lleva un aviso breve de documento obsoleto que apunta a este contrato. No se reescribe |
| C-4 | El vínculo no existe cuando se emite la acreditación | Nace sin vínculo y se ata una sola vez al vínculo creado en el paso 2 |
| C-5 / D-4 | `requestOwnerAuthorization` es compartida con F08 | F08 queda incluido, porque el retorno nunca ejecuta nada. Su `revalidate` compara el mismo `activeKey().keyId`. Sus pruebas siguen en verde sin cambiar las aserciones |
| C-6 | `sub` en el encargo | La identidad es `account.id`, `member.id` y `tenant.id`. No se leen JWT |
| D-1 | Vigencia | 10 minutos, más la anulación en `hidden` o `paused`. Se baja a 5 si E4 da una mediana por debajo de unos 3 minutos |
| D-2 | Restauración en otro teléfono | No se amplía, ni a «Recuperar acceso» ni a `rebuildSessionOnly` |
| D-3 | `scopeMismatch` | Sí. Lo aplica la credencial (comprobación 7). El verificador del otro Member desaparece y eso invalida sus autorizaciones |
| D-5 | El motivo al volver a la revisión | Se conserva escrito y editable |

## 5. Bases históricas sin operador

En `legacyUnbound` no hay titular vinculado:
- **las acciones nuevas** que exigen `OwnerAuthorization` (reversión y revisión tardía) **no se habilitan** hasta activar, elegir el titular y enrolar el PIN, que es el procedimiento explícito;
- el resto de la gestión privada sigue como antes;
- no se atribuye nada a ninguna cuenta.

## 6. Pruebas mínimas (HOST; DEVICE con el paquete aislado)

- Cada estado del §2, con:
  - la misma cuenta: datos, vínculos y outbox intactos;
  - la cuenta equivocada: abortada antes de `registerClient`, sin guardar nada;
  - cancelación;
  - red caída;
  - fallo de escritura antes y después del puntero;
  - sesión con el slot ilegible o el puntero corrupto;
  - `RESTORE_PAUSED` conservado;
  - sin peticiones adicionales.
- PIN:
  - enrolamiento sólo en `activated` con acreditación;
  - verificación sin red;
  - límites de intentos tras reiniciar el almacén;
  - restablecimiento sólo con acreditación;
  - ámbito distinto tras restaurar;
  - autorización de un solo uso y caducada;
  - llamada directa al repositorio sin autorización.

## 7. Revisión del código del PIN (2026-10-23)

**B, sobre `7713f9c`**, por lectura: LISTO con condiciones.
- **P1, aplicado: intentos contados sin carreras.**
  - `enroll` y `verify` van serializados **por almacén**: la cola va con el objeto almacén, de modo que dos instancias sobre el mismo almacén también se esperan. `AndroidCredentialStorage` es único en el proceso (nota de B sobre `cf4ae8a`), así que dos objetos no pueden quedar sobre el mismo espacio de nombres sin esperarse.
  - Una primera versión con un candado estático en todo el proceso encadenaba esperas entre pruebas de widget y colgaba `rec_050`; se descartó.
  - El fallo se cuenta **antes** del KDF y se pone a cero sólo si el PIN es correcto, así que cerrar la app durante el KDF no deja un intento sin contar.
  - Coste: si la app se cierra durante una verificación correcta, ese intento cuenta como fallo.
  - Pruebas: 4 verify() simultáneos con PIN erróneo sobre 2 instancias cuentan 4, y el 5.º bloquea (sin el candado, la prueba falla); un KDF interrumpido 5 veces bloquea.
- **Límites declarados:**
  - **P2, reloj:** las esperas usan el reloj del teléfono. Adelantarlo las acorta, pero no salta el tope de 10 fallos, que exige restablecer en línea.
  - ~~**P3, constructor público:** `OwnerOnlineVerification` es público y acepta funciones. El modelo de amenaza es saltarse la pantalla, no código malicioso dentro de la app. El proveedor de la app lo conecta con la reautenticación real.~~ **Sustituido el 2026-10-24 (§8):** no era un límite aceptable, porque permitía fabricar una autorización utilizable.
  - ~~**P4, PIN restablecido:** `consumeOwnerAuthorization` no compara el enrolamiento con el PIN vigente. Una autorización emitida justo antes de restablecer el PIN vale como mucho sus 120 s.~~ **Sustituido el 2026-10-24 (§8):** restablecer el PIN invalida al instante las autorizaciones anteriores.
- **R4 de C y punto 1 de B, se consume antes de aplicar:** la autorización se marca usada antes de aplicar los efectos. Si la transacción se deshace, hay que volver a poner el PIN.

## 8. Autoridad de la autorización y restablecimiento del PIN (2026-10-24)

**Decisión de Roderich (delegación, 2026-10-23).** Restablecer o reconfigurar el PIN invalida de inmediato las autorizaciones emitidas con el enrolamiento anterior. Un constructor público no es aceptable si permite fabricar una autorización utilizable. Las auditorías ya escritas conservan su enrolamiento.

**Qué se podía fabricar (comprobado leyendo el código de `f706e11`):**
1. **Sobre la credencial de la app.** Cualquier código podía construir `OwnerOnlineVerification` con funciones que siempre aciertan, obtener un `OnlineOwnerProof`, enrolar un PIN nuevo y verificarlo. Así obtenía una `OwnerAuthorization` real, sin acreditación en línea.
2. **Con una credencial sobre otro almacén** (por ejemplo, en memoria). Enrolar y verificar ahí daba una autorización que el repositorio aceptaba, porque el consumo sólo comparaba el vínculo.

Que `OwnerAuthorization._` sea privado no impedía ninguno de los dos.

**Control aplicado:**
- **Credencial de la instalación.** `consumeOwnerAuthorization` exige `installation`, la credencial del titular de la instalación, y rechaza la autorización salvo que `installation.accepts(auth)`: la emitió **ese mismo almacén** (`identical`, guardado en privado en la autorización) con el enrolamiento vigente. El repositorio recibe la credencial de la raíz de composición (`repositoryProvider` → `localOwnerCredentialProvider`) y la comprueba dentro de la transacción de la acción, sin esperar a nada. Sin ella, ninguna autorización vale. *(Primera versión del 2026-10-24: comparaba sólo el `enrolmentId`; sustituida por R3 de B, más abajo.)*
- **El enrolamiento que conoce el proceso** (`knownEnrolmentId`):
  - sólo lo publican los caminos de la cola: `verify`, al leer el verificador antes de emitir, y `enroll`. Una lectura fuera de la cola (`status`, `currentEnrolmentId`) no lo toca (R1 de B);
  - `enroll` lo borra justo antes de escribir el verificador nuevo y lo fija justo después. Mientras se restablece, o si la escritura informa de un fallo, no vale nada hasta la siguiente verificación (R2 de B). Fijarlo es el instante en que el restablecimiento surte efecto.
  - Va con el objeto almacén (`Expando`), igual que la cola, y el almacén Android es único en el proceso.
  - Una primera versión leía el almacén con una espera dentro de la transacción. Bloqueaba las pruebas de pantalla (`rec_050`), se detectó al ejecutarlas y se sustituyó por esta comparación síncrona.
- **Comprobante de la acreditación propia.** `enroll` sólo acepta un `OnlineOwnerProof` emitido por la `OwnerOnlineVerification` con la que se configuró la credencial, que en la app es la reautenticación real (`ownerOnlineVerificationProvider`). Un comprobante de otra instancia, armada con funciones cualesquiera, se rechaza sin escribir nada.

**Exclusión real frente a un restablecimiento concurrente:**
- `enroll` y `verify` van en la misma cola por almacén: una verificación encolada antes del restablecimiento emite con el PIN anterior, y esa autorización deja de valer cuando el restablecimiento termina. Una verificación encolada después ya no acepta el PIN anterior.
- El consumo no entra en esa cola. Compara el enrolamiento conocido en el momento de consumir: antes del restablecimiento la reversión se aplica, con el enrolamiento anterior en su auditoría; después se rechaza sin escribir.

**Pruebas:**
- **`f03_local_owner_credential_test`:**
  - restablecer invalida al instante;
  - restablecimiento concurrente con una verificación, en los dos órdenes;
  - comprobante de otra acreditación rechazado, sin escribir el almacén;
  - credencial con otro enrolamiento rechazada, y también la que **copia** el enrolamiento de la instalación en otro almacén (R3 de B);
  - una lectura lenta que empezó antes del restablecimiento no devuelve el PIN anterior (R1 de B);
  - escritura del verificador informada como fallida: nada vale hasta la siguiente verificación (R2 de B);
  - enrolamiento conocido: desconocido hasta leerlo, cambiado al restablecer y por almacén.
- **`f04_rf13_reversal_audit_test`**, cada rechazo con la base y la auditoría intactas (volcado completo):
  - verificar, restablecer y usar la autorización anterior: se rechaza;
  - credencial de otro almacén, aunque copie el enrolamiento: se rechaza (m2 de B);
  - repositorio sin lector: se rechaza;
  - restablecimiento concurrente con la reversión: o se aplica con el enrolamiento anterior o se rechaza.
- **Mutaciones detectadas:**
  - sin la cola, falla la prueba de los 4 PIN simultáneos;
  - sin actualizar el enrolamiento al restablecer, falla la de verificar, restablecer y usar;
  - si las lecturas fuera de la cola publican, falla la de R1;
  - sin la comprobación del almacén emisor, falla la de la copia (R3);
  - sin borrar antes de escribir, falla la de R2.

**Límites declarados:**
- **Sin protección entre isolates ni entre procesos.** El enrolamiento conocido y la cola viven en el isolate principal; un segundo proceso o isolate con su propio almacén no se coordina con ellos. La app no tiene ninguno de los dos.
- **La frontera es el código del proceso** (redacción pedida por B, R3):
  - los constructores de `LocalOwnerCredential`, `OwnerOnlineVerification` y `AndroidCredentialStorage` (singleton) son públicos;
  - `enrolmentId` es un identificador y no un secreto: está en la auditoría y en los respaldos;
  - el código dentro del proceso puede construir una `LocalOwnerCredential` sobre el almacén Android real con una acreditación propia, y re-enrolar el PIN, o escribir `FlutterSecureStorage` directamente. Así funciona `TestOwnerPin` en las pruebas, sobre memoria.
  - Nada en Dart impide eso y no se afirma lo contrario. Lo que queda cerrado:
    - la vía de las API públicas sin re-enrolar: pantalla, repositorio y credencial de la app;
    - la autorización emitida con otro enrolamiento, o desde otro almacén aunque copie el enrolamiento;
    - la emitida antes de restablecer el PIN.
- **Reloj y consumo antes del commit:** siguen como en §7, aceptados para el entorno sintético.
- La autorización de la clave de recuperación del respaldo (F08, sesión C) usa el mismo `consumeOwnerAuthorization`. En la composición pasa `installation: ref.read(localOwnerCredentialProvider)`, con los propósitos de mostrar y rotar la clave, `subjectRef` = identificador de la clave y el vínculo vigente (m1 de B).

## 9. Acreditación del titular con la sesión sana (DEVICE, 2026-10-24)

- **FAIL en DEVICE** (POCO X5 Pro, composición `bfee4dc`): la acreditación en línea para enrolar o restablecer el PIN usaba `reauthenticate`, que sólo recupera una sesión en cuarentena. Con la sesión sana abortaba sin salir a la red y dejaba la app en «volver a autenticar» hasta reabrirla. Las pruebas de host simulaban `reauthenticate` y no lo detectaban. Evidencia: `docs/evidence/F01_F08_DEVICE_COMPOSICION_2026-10-24.md`.
- **Corrección:** `RemoteSessionCoordinator.confirmAccount` hace un login nuevo y lo valida igual que la reautenticación: misma cuenta, Member y tenant, agricultor activo y sin registro de cliente. Después lo cierra siempre con `logout`. No toca la sesión guardada, el guard ni el estado publicado. B la revisó (LISTO).
- **Resultado único (n1 de B):** «otra operación remota en curso», «sin red», 401/429 y «otra cuenta» dan el mismo `false` (fail-closed). El mensaje de la pantalla lo dice: revisar la cuenta, la contraseña y la conexión, o esperar si el teléfono se está sincronizando. Un resultado tipado queda como mejora posible.
- **Límite declarado (n2 de B):** si falla el `logout` del login nuevo, o si el servidor crea la sesión y la respuesta del login se pierde, queda en el servidor una sesión **sin registro de cliente** hasta su TTL. Su refresh token sólo estuvo en memoria y se descarta, así que nadie la usa. No se registra.
- **Pendiente:** repetir en DEVICE el enrolamiento, la verificación, el restablecimiento y la invalidación (§8) con un APK que incluya la corrección.
