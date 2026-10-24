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
| Enrolamiento | Sólo en el estado `activated`: vínculo activo y sesión legible del mismo Member y tenant. Requiere **acreditar en línea al mismo titular**: contraseña de la cuenta y la reautenticación existente (`reauthenticate`), que verifica el mismo registro de cliente y el ámbito. Después se piden dos veces el PIN y se guarda el verificador con el ámbito del vínculo |
| Ejecución | El PBKDF2 se calcula **fuera del hilo de la interfaz** (`Isolate.run`), en el enrolamiento y en cada verificación. El tiempo en el teléfono se mide y se registra (R4 de C) |
| Comprobación | Funciona **sin red**: verificador local, comparación en tiempo constante y ámbito igual al vínculo activo. Si el vínculo cambió (otra base restaurada), el verificador **no vale** y hay que enrolar de nuevo |
| Intentos | El contador vive en el mismo almacén seguro y no se reinicia al cerrar la app. Tras 5 fallos seguidos hay una espera creciente: 30 s, 2 min y 10 min. Tras 10 fallos se bloquea y sólo se restablece acreditando al titular en línea. Un acierto pone el contador a cero |
| Recuperación del PIN | «Olvidé el PIN»: acreditar en línea al mismo titular, como en el enrolamiento, y enrolar de nuevo. **Sin red no se puede restablecer.** Restablecer el PIN **no** descifra copias ni recupera la clave del respaldo |
| Tras una restauración | El verificador **no viaja** en el respaldo. En otra instalación no existe: tras «Recuperar acceso», el titular enrola un PIN nuevo. En la misma instalación vale sólo si el vínculo de la base restaurada tiene el mismo Member y tenant; si no, se pide enrolar. **C lo invoca, no lo duplica** |
| Qué identifica | Una **autorización** del titular en esta instalación. No prueba quién sostenía físicamente el teléfono. |

### Interfaz para RF-13, RF-03 y C

```dart
abstract interface class LocalOwnerCredential {
  Future<CredentialStatus> status();          // notEnrolled | enrolled | lockedUntil(t) | requiresOnlineReset | scopeMismatch
  Future<void> enroll({required String pin, required String pinConfirmation}); // exige la acreditación en línea previa (token de un solo uso)
  Future<OwnerAuthorization> verify({required String pin, required AuthorizationPurpose purpose, required String subjectRef});
  Future<void> resetAfterOnlineVerification({required String pin, required String pinConfirmation});
}
```

**Propósitos** (`AuthorizationPurpose`):
- de A: `REVERSE_PURCHASE`, `REVERSE_APPLICATION`, `REVERSE_TRANSFER`, `CONFIRM_LATE_OPERATION` y `REJECT_LATE_OPERATION`;
- de C (R1): `SHOW_BACKUP_RECOVERY_KEY` y `ROTATE_BACKUP_RECOVERY_KEY`, con `subjectRef` = keyId en hex. Sólo **autorizan** mostrar o rotar la clave. El PIN no entra en ninguna derivación.
- Sin un PIN enrolado, C muestra la clave sin PIN **sólo** en su primer enrolamiento; para volver a mostrarla exige el PIN o la acreditación en línea. Aceptado.

**Consumo (R2 de C).** Al **consumirla**, en la misma transacción que la acción, el repositorio compara su `bindingId`, Member y tenant con el **vínculo activo en ese momento**, no sólo en `verify`. Así, una autorización emitida antes de una restauración (que `GuardedRestore` puede completar dentro de los 120 s) no vale después.

`OwnerAuthorization` es un objeto de **un solo uso**, de vida corta (120 s) y ligado a un propósito y a un objeto (por ejemplo `REVERSE_PURCHASE:<id>`). Se crea sólo en `verify`, con un constructor privado. El repositorio lo consume en la misma transacción que la acción. **Llamar al repositorio sin una autorización válida falla**: no basta con saltarse la pantalla.

Lleva `{enrolmentId, personId del titular, bindingId, Member, tenant, método LOCAL_PIN, verificadoEn}`. No lleva el PIN.

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
