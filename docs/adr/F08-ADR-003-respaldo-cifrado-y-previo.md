# F08-ADR-003 — Respaldo cifrado en el teléfono, clave de recuperación y limpieza de `.previo`

| Campo | Valor |
|---|---|
| Fecha real | 2026-10-23 (America/La_Paz), redacción |
| Estado | **Aceptado para el alcance académico con datos sintéticos** (decisión de Roderich del 2026-10-24). No aprueba GATE-F08 ni habilita datos reales. Historial y alcance en el §0 |
| Autor | Sesión C del bloque INICIO_F01_F08_2026-10-23 |
| Decisión de origen | Decisión de Roderich del 2026-10-23 (F08: cifrado en el teléfono, cinco copias y limpieza de `.previo`), ratificada para el bloque sintético |
| Trazabilidad | RF-26, RF-27, RNF-04, RNF-10, DAT-14, CU-14, CU-15 |
| Relacionados | BE `docs/architecture/F08_BACKUP_THREAT_MODEL.md` (condición 2 del §5), BE `F08_BKP_06_RETENCION.md`, Mobile `F03_RECUPERACION_IDENTIDAD_LOCAL.md` (A) |

La numeración 003 evita chocar con `BE-ADR-002` (renumeración de fases), que ya está en esta carpeta.

## 0. Estado y aceptación

### 0.1 Historial de estado

| Fecha real | Estado | Fuente |
|---|---|---|
| 2026-10-23 | **Propuesto, para revisión** (B y A). No aprueba GATE-F08 ni habilita datos reales | Cabecera original de este ADR. Revisado sobre el texto por B y por A |
| 2026-10-24 | **Aceptado para el alcance académico con datos sintéticos** | Decisión de Roderich del 2026-10-24 por la noche (hora local −04:00), transmitida por la sesión A. La registra la sesión C |

Las secciones 1 a 10 conservan el texto con el que se propuso. Donde describían como «actual» o «previsto» un estado anterior, llevan una **aclaración del 2026-10-24** que no reescribe lo anterior.

### 0.2 Qué acepta y qué no

**Acepta**, para la entrega académica con datos sintéticos, el diseño de este ADR:
- la biblioteca (§2);
- las claves y su custodia (§3);
- el formato 2 (§4);
- el reparto de responsabilidades (§5);
- la compatibilidad con el formato 1 (§6);
- la limpieza de `.previo` (§7).

**No** aprueba ni cambia:
- GATE-F08 (Roderich1/Agro_Sindicato_Backend-Web#41), que conserva su decisión del 2026-10-16;
- la admisión de datos reales: `BACKUP_PRODUCTION_ADMISSION` sigue cerrada y `BACKUP_REQUIRE_CLIENT_ENCRYPTION` sigue desactivada por defecto;
- Roderich1/Agro_Sindicato_Backend-Web#151, que sigue abierta.

**La aceptación conserva los riesgos declarados:**
- **Exportación local sin cifrar:** la exportación manual a `Descargas` sigue siendo el contenedor legible de EVO-001 (§6 y §8).
- **Límites de accesibilidad:** `FLAG_SECURE` actúa sólo sobre la composición de la ventana (capturas, grabación y miniatura de recientes). **No es una protección frente a los servicios de accesibilidad autorizados**: un servicio que la persona activó en Ajustes puede leer la clave mientras se muestra o se escribe (§3.4 y §8).
- **Pérdida de la clave de recuperación:** perder a la vez el teléfono y la clave anotada hace irrecuperables las copias cifradas, porque no hay escrow (§3.3 y §3.6).
- **Condiciones pendientes para producción** (§0.4).

### 0.3 Accesibilidad de la clave (decisión del 2026-10-24)

**Se mantiene la accesibilidad de la clave para TalkBack.** La clave conserva su semántica mientras se muestra y mientras se escribe, para que quien usa un lector de pantalla pueda anotarla y confirmarla.

El riesgo del §8 se acepta tal como está declarado y el código no cambia. Lo que lo reduce sigue siendo lo mismo:
- un servicio de accesibilidad sólo actúa si la persona lo activó;
- la clave sólo se muestra al crearla, al volver a verla con el PIN y al escribirla para recuperar.

### 0.4 Pruebas que siguen pendientes y condiciones para producción

**Pruebas que siguen pendientes.** Se conservan como tales; la aceptación no las da por ejecutadas:
- **Rendimiento** del cifrado en Dart puro en el dispositivo: **NOT_MEASURED** (§2.3).
- **Rotación completada en DEVICE**, con descifrado posterior de la copia antigua. En el teléfono sólo se probó cambiar y cancelar (D6e, segunda ronda).
- **Archivo alterado o truncado en DEVICE.** Está cubierto en el host; en el teléfono sólo se probó una clave incorrecta (D7c).
- **Auto Backup y transferencia D2D reales.** En el teléfono sólo se inspeccionó el paquete con `aapt2` (D9).
- **Comprobación con personas** de cómo se guarda la clave fuera del teléfono. Hoy sólo la cubre una prueba de widget.

También siguen pendientes, según la conciliación del 2026-10-24:
- restaurar con la clave correcta escrita en una instalación nueva;
- restaurar en un teléfono de otro modelo (#151, ítem 7);
- el cambio de contraseña de la cuenta en DEVICE;
- el plazo, la cota y una `interrupted` de `.previo` en DEVICE;
- una copia cifrada **por el teléfono** que pase por B2 real y se restaure en el teléfono. Las comprobaciones en B2 del 2026-10-24 usaron sobres sintéticos del formato 2.

Lo que se ejecute después se anotará con su propia evidencia y su fecha real, no en este ADR.

**Condiciones para producción**, separadas de la entrega académica:
- las condiciones del §5 del modelo de amenazas del BE (`F08_BACKUP_THREAT_MODEL.md`) que siguen abiertas, con su enmienda: `BACKUP_REQUIRE_CLIENT_ENCRYPTION=true`;
- revisar el paquete `cryptography` antes de cualquier admisión real (§2.3);
- claves del proveedor por entorno y de mínimo privilegio, con su rotación y su revocación (#151);
- retención institucional y ciclo de cierre de cuenta o servicio para datos reales (el plazo de 30 días no está aprobado);
- la admisión productiva, que decide Roderich.

## 1. Contexto

Hoy el teléfono sube al servidor el contenedor `.agrobackup` (un ZIP con `manifest.json`, `database.db` e `invoices/…`) **en texto legible**. SSE-B2 cifra en reposo, pero el proveedor descifra para quien tenga la clave de la cuenta B2. Por eso el modelo de amenazas deja abierta **T3**: el operador del servidor o del bucket puede leer los respaldos.

> **Aclaración del 2026-10-24.** «Hoy» es el 2026-10-23, antes de este ADR. Desde Mobile #144 (`main` `1d77c14`) el teléfono sólo sube el formato 2: lo prueba el host (`F08_RESPALDO_CIFRADO_HOST.md` §2.3). En el teléfono lo vio el caso D7a de la primera ronda DEVICE, sobre el árbol `84f9d82`: el objeto empezaba por `AGROENC\0` y no contenía «SQLite format». Ese objeto quedó en el disco del Backend desechable, no en B2.

Roderich decidió cifrar en el teléfono antes de subir. Este ADR fija:

- la biblioteca;
- el formato exterior;
- la custodia y la recuperación de la clave;
- las responsabilidades de cada lado;
- la compatibilidad con lo anterior;
- la limpieza de las copias locales `.previo`.

## 2. Biblioteca

### 2.1 Elección: `cryptography` 2.9.0 (pub.dev, editor verificado dint.dev), fijada exacta

**Algoritmos que se usan, todos de la propia biblioteca:**
- `Chacha20.poly1305Aead()`: AEAD de RFC 8439, con clave de 256 bits, nonce de 96 bits y etiqueta de 128 bits.
- `Hkdf(hmac: Hmac.sha256(), outputLength: n)`: RFC 5869.

**Primitivas que no se usan:** ni `cryptography_flutter` ni las implementaciones de plataforma. Las mismas clases Dart se ejecutan en el host, en la CI (ubuntu) y en Android. Así, lo que prueba la suite es exactamente lo que corre en el teléfono.

**Comprobado en las fuentes primarias el 2026-10-23:**
- Página de pub.dev: 2.9.0, plataformas Android, iOS, Linux, macOS, Windows y web.
- Paquete 2.9.0 descargado de `pub.dev/api/archives`.
- Repositorio `dint-dev/cryptography`: último commit 2025-11-21 (la publicación 2.9.0), 37 issues abiertos, no archivado.
- En el código:
  - `Cipher.encryptStream` y `decryptStream` procesan por bloques. `decryptStream` lanza `SecretBoxAuthenticationError` al cerrar el flujo si la etiqueta no coincide.
  - `Mac.==` usa `constantTimeBytesEquality`.
  - Poly1305 usa limbs de 16 bits, no `BigInt`.
  - Depende sólo de paquetes de Google (`crypto`, `ffi`, `collection`, `meta`, `typed_data`).

### 2.2 Alternativas descartadas

| Opción | Por qué no |
|---|---|
| `sodium` 4.1.2 (libsodium 1.0.22, `crypto_secretstream`) | Es la mejor construcción para archivos, con autenticación por bloque y `TAG_FINAL`. Pero la 4.x compila libsodium desde el código fuente con *build hooks*. En Windows, el build de Android exige bash y `make` (autotools), y el propio autor dice que no garantiza que funcione en todas las máquinas. En esta máquina no hay `make`. `sodium_libs` está *discontinued*. El riesgo de no poder compilar el APK del ensayo es real |
| Tink `StreamingAead` por canal de plataforma | Mantenida por Google, pero sólo Android. En el host habría que probar con un doble, y la criptografía real sólo se ejercitaría en el dispositivo |
| `pointycastle` o `webcrypto` | No ofrecen AEAD en streaming. Habría que construir el troceado por cuenta propia, y eso es criptografía propia |

### 2.3 Límites que se aceptan y se declaran

- **Mantenedor único y 11 meses sin publicación.** Se fija la versión exacta, se ejecutan vectores RFC 8439 propios en la suite (§9) y se revisa el paquete antes de cualquier admisión real.
- **Rendimiento en Dart puro: NOT_MEASURED en el dispositivo.** No se fija un tiempo ni un consumo de memoria. Se mide en el ensayo del teléfono (turno de A) y se registra lo observado.
  - *Aclaración del 2026-10-24:* las tres rondas DEVICE del 2026-10-24 no lo midieron, así que sigue en **NOT_MEASURED** (§0.4). Lo único medido es orientativo y en el host (`F08_RESPALDO_CIFRADO_HOST.md` §2.4).
- **`decryptStream` entrega texto descifrado antes de verificar la etiqueta**, como cualquier AEAD de un solo mensaje. Mitigación obligatoria (§5.3): se escribe sólo a un `.part` en la carpeta privada, y se descarta si la etiqueta falla. Nada lo lee antes de la verificación.

## 3. Claves

### 3.1 Clave de recuperación (K_r)

- **32 bytes de `Random.secure()`**, el generador criptográfico del sistema.
- **No se deriva del PIN ni de la contraseña de la cuenta, ni se relaciona con ellos.** Por eso no hay KDF de contraseña: no hay tiempos ni memoria de Argon2/PBKDF2 que fijar.
- **Presentación para anotarla en papel:** 35 bytes = versión `0x01` ‖ K_r ‖ 2 bytes de comprobación (`SHA-256("agrocuentas/recovery-key/v1" ‖ K_r)[0..2]`).
  - Se codifican en **Base32 de Crockford**: 56 caracteres, en 14 grupos de 4 (`XXXX-XXXX-…`).
  - Al leerla se aceptan minúsculas, espacios y guiones, y `O→0`, `I/L→1`.
  - La comprobación detecta errores de escritura **antes** de intentar descifrar, y el mensaje es distinto («la clave tiene un error de escritura» frente a «la clave no corresponde a esta copia»).
- **Identificador de clave (no secreto):** `key_id = HKDF-SHA256(ikm=K_r, salt=∅, info="agrocuentas/backup/key-id/v1", L=16)`.
  - Va en la cabecera de cada copia.
  - Permite elegir la clave del llavero y detectar una clave equivocada sin descifrar.
  - No revela K_r (HKDF es una PRF). Sólo permite saber que dos copias del mismo titular usan la misma clave, algo que el servidor ya sabe por el propietario.

### 3.2 Clave de cada archivo

`K_f = HKDF-SHA256(ikm=K_r, salt=file_salt[32 aleatorios], info="agrocuentas/backup/file-key/v1", L=32)` y `nonce` de 12 bytes aleatorios.

Cada copia tiene su propia clave, de modo que el nonce nunca se reutiliza con la misma clave.

### 3.3 Custodia local

- **El llavero vive en `flutter_secure_storage`**, que ya es dependencia y está fijado en 11.2.0, con un almacén propio `agrocuentas_backup_keys_v1` en Android, cifrado con Android Keystore.
- **Contenido:** una lista de `{keyId, key, createdAt, confirmedAt?, retiredAt?}`.
- **Fuera del respaldo:** no está en SQLite, así que no viaja en el respaldo.
- **Fuera del auto-backup de Android:** ningún dominio de la app entra en el respaldo automático ni en la transferencia entre dispositivos (§3.8).
- **Sin escrow ni recuperación centralizada:** no hay escrow administrativo, ni clave maestra, ni copia en el servidor, ni recuperación por parte de la Directiva.
- **Nada se registra en logs:** ni la clave ni el `toString()` de sus objetos.
- **Mostrarla de nuevo o cambiarla es una acción deliberada.** Exige una `OwnerAuthorization` de un solo uso (`LocalOwnerCredential.verify(pin:, purpose:, subjectRef:)` de A, propósitos `SHOW_BACKUP_RECOVERY_KEY` y `ROTATE_BACKUP_RECOVERY_KEY`, `subjectRef` = `keyId` en hex), consumida contra el vínculo vigente. La credencial autoriza, pero nunca se usa para derivar la clave. **El llavero exige y consume la autorización**, no la pantalla: `revealActive(authorization:)` y `startRotation(authorization:)` llaman al consumidor inyectado (`consumeOwnerAuthorization` de A en la composición) contra el `keyId`, y con una clave activa no nace otra pendiente sin `startRotation`. Revisión de B, C2. Una clave **pendiente** (la primera o la de una rotación ya autorizada) se puede volver a mostrar sin otra autorización hasta que se confirme o se descarte: es deliberado, porque nada se ha cifrado con ella ni se cifrará antes de confirmarla. En esta rama el consumidor y el punto de enganche de la interfaz (`backupKeyAuthorizationConsumerProvider` y `backupKeyAuthorizerProvider`) **fallan cerrados** y se conectan en la composición. El primer enrolamiento de la clave no pide PIN: nada depende todavía de ella.
  - *Aclaración del 2026-10-24:* «en esta rama» describe la rama antes del puente con F03. En `main` `1d77c14` los dos puntos están conectados: `backupKeyAuthorizationConsumerProvider` llama a `consumeOwnerAuthorization` y `backupKeyAuthorizerProvider` pide el PIN con `requestOwnerAuthorization` (`lib/services/backup/remote_backup_providers.dart`; HOST §7). En el teléfono, en la segunda ronda DEVICE (árbol `d6d9c8c`), la clave se negó sin PIN (D6a), se mostró con el PIN correcto (D6d), el PIN anterior se rechazó (D3c) y se probó cambiar y cancelar (D6e).

### 3.4 Confirmación antes de depender de la copia cifrada

1. La app genera K_r y la muestra una sola vez en una pantalla dedicada, con instrucciones: anotarla en papel y guardarla fuera del teléfono. No se copia al portapapeles ni se comparte: los teclados con historial y las nubes quedan fuera. El campo donde se escribe no tiene menú de copiar y pegar.
2. La persona **vuelve a escribirla completa**. La app comprueba la suma de verificación y la igualdad con K_r, y sólo entonces marca `confirmedAt`.
3. **Mientras no haya una clave confirmada, «Subir respaldo» no sube nada** y lleva a este procedimiento.
4. **Pantalla protegida (FLAG_SECURE).** Mientras se muestra, se confirma o se escribe la clave (la pantalla de la clave, el diálogo que la vuelve a mostrar y el que la pide para recuperar) la ventana lleva `FLAG_SECURE`: sin capturas ni grabación, y la miniatura de recientes en blanco, también en segundo plano.
   - **Sin un primer fotograma desprotegido:** lo sensible se pinta sólo cuando Android ya confirmó la marca (`ScreenSecureChannel`, canal `agrocuentas/screen_secure`, que responde desde el hilo de la interfaz con el estado que quedó). Hasta entonces se ve un indicador.
   - **Cuenta anidada:** cada pantalla o diálogo toma su permiso (`ScreenSecure.acquire`) y la marca se quita al devolver el último. Cerrar un diálogo no desprotege la pantalla que sigue abierta debajo. El permiso se devuelve cuando la pantalla terminó de cerrarse.
   - **Falla cerrado:** si Android no confirma la marca, la clave no se muestra y se ofrece reintentar. Si lo que falla es quitarla, la pantalla sigue protegida.
   - **Límite declarado:** protege contra capturas y grabación del sistema, no contra una cámara apuntando a la pantalla. **Tampoco oculta la clave al árbol de accesibilidad** (§8). La marca real en la ventana se comprueba en el dispositivo (DEVICE, lo opera A). En el host se prueba la cuenta y el orden con el canal simulado.
   - *Aclaración del 2026-10-24:* «protegida» se refiere sólo a la composición de la ventana; **no es una protección frente a los servicios de accesibilidad autorizados** (§0.2 y §0.3). La marca en la ventana se comprobó en el teléfono: `fl=SECURE` y `screencap` de 0 bytes con la clave pendiente (D6b, primera ronda, árbol `84f9d82`) y al volver a mostrarla con el PIN (D6d, segunda ronda, árbol `d6d9c8c`).

### 3.5 Teléfono nuevo, reinstalación o llavero ilegible

1. **Autenticación del titular** (Auth V2 y el flujo de activación de A) para listar y descargar. El servidor sólo sirve copias del mismo Member y tenant.
2. Si el `key_id` de la cabecera no está en el llavero, se pide la **clave de recuperación**: se comprueba la suma, se deriva su `key_id` y se compara con el de la cabecera, y sólo entonces se descifra.
3. **Tras una restauración correcta**, la clave introducida se guarda en el llavero como confirmada, porque la persona demostró tenerla fuera del teléfono. «Correcta» es que `GuardedRestore.restore` devolvió su resultado (si falla, lanza y no se llega a guardarla), aunque después el recálculo del acceso quede en null (revisión de B, m2).
4. **Regla de la clave activa** (revisión de B, I1): la activa es la última confirmada en este teléfono y no retirada; una clave pendiente nunca cifra. La clave escrita al restaurar:
   - pasa a activa sólo si el llavero no tenía ninguna activa (teléfono nuevo o reinstalado);
   - si ya había una activa (el teléfono creó y confirmó la suya antes de restaurar una copia antigua), se guarda como **retirada**, sólo para descifrar, y las subidas siguientes usan la activa.
   - Prueba: `remote_backup_client_test.dart`, «restaurar con una clave distinta de la activa…».

### 3.6 Separación de los tres mecanismos

| Se recupera | No concede |
|---|---|
| Sesión o cuenta (contraseña, Auth V2) | Descifrar copias: hace falta K_r |
| PIN local (A, §4 de su contrato) | Ni K_r ni la sesión |
| Clave de recuperación | Descargar: hace falta la sesión del titular |

**Cambiar o recuperar la contraseña o el PIN no toca el llavero ni las copias.** Las copias anteriores siguen descifrándose con la misma K_r.

**Perder a la vez el teléfono y la clave anotada hace irrecuperables las copias cifradas.** Es la consecuencia aceptada de que el operador no tenga la clave.

### 3.7 Rotación

- **«Cambiar la clave de recuperación»** genera una K_r nueva, exige confirmarla (§3.4) y deja la anterior en el llavero como `retired`. Las copias nuevas usan la nueva.
- **En este bloque una clave retirada nunca se borra automáticamente** (revisión de B, m2). No hay borrado manual en la interfaz; si se añadiera, sólo con cero copias dependientes conocidas y confirmación, y una copia del servidor con `key_id` desconocido la mantendría indefinidamente.
  - El teléfono anota localmente `id remoto → key_id` de lo que sube. Es un dato no secreto, en un archivo de la carpeta privada.
  - Una copia del servidor cuyo `key_id` no se conoce cuenta como dependiente.
  - La app avisa de que la clave anotada anterior sigue siendo necesaria para N copias.
- **No se re-cifran ni se sobrescriben copias remotas.** La rotación del servidor, que conserva las 5 últimas verificadas, las retira por el orden normal.

### 3.8 Respaldo automático de Android y transferencia entre dispositivos

Decidido el 2026-10-23 (continuación de Roderich, transmitida por A): **nada de Agrocuentas sale del teléfono por el respaldo de Google ni por la transferencia entre dispositivos.** El único respaldo es el propio de la app, local o cifrado en la nube.

Inventario de dónde guarda cada cosa, verificado sobre las versiones fijadas de los plugins (`path_provider_android` 2.3.1, `sqflite_android` 2.4.3, `flutter_secure_storage` 11.2.0) y sobre la composición:

| Dominio de Android | Qué guarda la app ahí |
|---|---|
| `database` (`getDatabasesPath`) | La base activa `agroquimicos_v2.db` con su `-journal`/`-wal`/`-shm`, las copias `previo/` con su registro, y los `.descifrado` de una restauración. |
| `root` → `app_flutter/` | `getApplicationDocumentsDirectory` es `getDir("flutter")`, **no** `files/`. Contiene las fotos de factura (`invoices/`), el log y, si no hay carpeta de descargas, las exportaciones `.agrobackup` sin cifrar y los informes. |
| `file` (`getApplicationSupportDirectory`) | `remote_backups/`: descargas, subidas y descifrados del respaldo en la nube. |
| `sharedpref` | Los almacenes seguros `agrocuentas_secure_session_v1` (sesión y refresh), `agrocuentas_owner_credential_v1` (PIN del titular, de A) y `agrocuentas_backup_keys_v1` (claves de recuperación). Cada uno ocupa tres archivos: `<ns>.xml`, `FlutterSecureKeyStorage:<ns>.xml` y `FlutterSecureStorageConfiguration:<ns>.xml`. Además, `AgrocuentasSessionPointer.xml`. |
| `external` → `Download/` (`getDownloadsDirectory`) | Exportaciones `.agrobackup` sin cifrar e informes. Android las respalda por defecto. |
| `no_backup/` | La identidad de la instalación. Android nunca la respalda. |
| caché | Los temporales de Dart (`Directory.systemTemp`) y los de `path_provider`. Android no la respalda. |

Reglas:

- `backup_rules.xml` (Android 11 y anteriores) y las dos secciones `cloud-backup` y `device-transfer` de `data_extraction_rules.xml` (Android 12 y posteriores) **excluyen los cinco dominios enteros** (`path="."`).
- **Se excluye el dominio entero, no archivo por archivo,** porque cada dominio mezcla secretos y datos privados y no hay nada inocuo que incluir. Así, un archivo nuevo queda fuera sin tocar las reglas.
- **Segunda barrera:** se mantienen además, por su nombre, las exclusiones de los tres almacenes seguros, del puntero de sesión, de `previo/` y de `remote_backups/`. Si alguien quitara una exclusión de dominio, los secretos seguirían fuera, y las pruebas de F03 que las buscan por su nombre no cambian.
- No hay inclusiones: una inclusión limitaría el respaldo a lo incluido, y no hay nada que se quiera respaldar.
- **No se confía en `allowBackup="false"`:** en Android 12 y posteriores no detiene la transferencia entre dispositivos. El manifiesto no cambia, y tampoco `minSdk`.
- Prueba en el host: `f08_android_backup_rules_test.dart`. La regla empaquetada y el manifiesto fusionado se comprueban sobre el APK con `aapt2` (evidencia).
- **No cubierto:** el almacenamiento protegido del dispositivo (`device_*`), que la app no usa, y la sección `cross-platform-transfer` de Android 16, que no se añade para no depender de cómo la lean versiones anteriores.

**Consecuencia que se declara: desinstalar la app, borrar sus datos o cambiar de teléfono sin un respaldo propio válido pierde los datos.** Ni Google ni la transferencia entre teléfonos los traen. Hace falta una exportación local guardada fuera del teléfono, o una copia cifrada en la nube junto con su clave de recuperación.

## 4. Formato exterior versionado (formato 2)

Bytes, enteros en big-endian:

| Desplazamiento | Tamaño | Campo | Valor |
|---|---|---|---|
| 0 | 8 | magic | ASCII `AGROENC` + `0x00` |
| 8 | 2 | formatVersion | `2` (es el mismo número que `X-Backup-Format-Version`) |
| 10 | 1 | algorithm | `1` = ChaCha20-Poly1305 RFC 8439 + HKDF-SHA256 |
| 11 | 1 | flags | `0` (cualquier otro valor se rechaza) |
| 12 | 16 | keyId | §3.1 |
| 28 | 32 | fileSalt | §3.2 |
| 60 | 12 | nonce | §3.2 |
| 72 | 8 | plaintextLength | bytes del contenedor interior |
| 80 | n | ciphertext | `ChaCha20(K_f, nonce)` del contenedor interior |
| 80+n | 16 | tag | Poly1305 sobre AAD y ciphertext |

- **La cabecera de 80 bytes es el AAD.** Por eso cambiar versión, algoritmo, `keyId`, sal, nonce o longitud invalida la etiqueta.
- **Tamaño exacto:** `fileLength == 80 + plaintextLength + 16`. Cualquier otro tamaño se rechaza antes de descifrar.
- **Truncamiento y basura final:** la etiqueta se calcula sobre la longitud total (RFC 8439 §2.8). Truncar, añadir bytes o reordenarlos hace fallar la etiqueta o el control de tamaño.
- **Interior sin cambios:** es el contenedor `.agrobackup` actual, con `backupFormatVersion: 1` en el manifiesto. Se vuelve a validar entero tras descifrar.
- **Límites:**
  - `plaintextLength ≤ BackupExtractionLimits.maxContainerBytes` (257 MiB); se comprueba **antes** de descifrar.
  - En el servidor el límite de `BACKUP_MAX_BYTES` (100 MiB por defecto) se aplica a los bytes cifrados.
  - El cifrado no comprime: no hay expansión del formato exterior. El lector ZIP acotado conserva sus límites contra expansión.
- **Sin metadatos legibles del contenido:** no hay nombres, fechas, esquema ni titular dentro de la cabecera.
  - `X-Backup-Schema-Version` sigue viajando como hasta ahora, porque el servidor ya lo guarda y el teléfono lo usa para avisar de incompatibilidad. Es un entero del esquema de la app, no de los datos.

## 5. Responsabilidades

### 5.1 Backend (BE `modules/backups`)

**El Backend sólo guarda ciphertext.** Comprueba:
- propietario (Auth V2), permisos y cupos;
- `formatVersion ∈ {1, 2}` (§6);
- tamaño;
- SHA-256 de transporte de los bytes cifrados;
- para el formato 2, la **forma exterior** de la cabecera en streaming: magic, versión igual a la cabecera, algoritmo 1, flags 0 y `fileLength == 80 + plaintextLength + 16`. Si no cumple, responde 422 `BACKUP_FORMAT_INVALID` y no deja bytes;
- para el formato 1, sólo que no lleve el magic del formato 2 (un cuerpo cifrado etiquetado como legible se rechaza); su contenido no se inspecciona, como antes. Ninguna de las dos comprobaciones relaja la otra (revisión de B, m4).

**No afirma** haber comprobado el contenido descifrado: no puede, no tiene la clave.

Se conservan sin cambios: el owner-scoping, el staging, la validación antes de AVAILABLE, una subida en curso por Member, las 5 copias verificadas (la antigua se retira en la misma transacción que deja AVAILABLE a la nueva) y la reconciliación de versiones físicas.

**No necesita migración:** `formatVersion INTEGER` ya existe. Se libera la reserva `20261023110000`.

### 5.2 Teléfono

1. **Cifra antes de enviar.**
   - El contenedor interior se genera en la carpeta privada, no en `Descargas`.
   - Se cifra en streaming a un `.part` privado y se vuelve a descifrar y validar antes de subir: un respaldo que no se sabe releer no protege.
   - Se sube sólo el formato 2.
   - El contenedor en texto legible se borra al terminar, también si algo falla.
2. **Restaura** en el orden del encargo:
   1. la sesión del mismo titular;
   2. el tamaño y el SHA-256 de transporte del ciphertext, que ya se comprueban;
   3. el descifrado con la etiqueta verificada, a un `.part` privado que se renombra sólo tras verificar;
   4. la validación interna del manifiesto, la base, el esquema y las fotos (`BackupService.validate`), y la propiedad (`GuardedRestore.preview`);
   5. la confirmación de la persona;
   6. `GuardedRestore.restore`, con exclusión, copia previa, WAL/rollback, pausa de la outbox (`RESTORE_PAUSED`) y recálculo de la autorización.
   - El SHA-256 del contenedor descifrado se anota al prepararlo y se vuelve a cotejar justo antes del paso 6.

### 5.3 Errores, temporales y último respaldo válido

- **No tocan la base activa:** una clave incorrecta (`keyId` distinto), una etiqueta que no coincide, un tamaño inconsistente, una cabecera desconocida, la falta de espacio (`FileSystemException`) o un fallo en la preparación. En todos los casos se borra el `.part`.
- **Todos los temporales van en carpetas privadas de la app:** `getApplicationSupportDirectory()/remote_backups` y `Directory.systemTemp`, que en Android es la caché privada. Se limpian en `finally` y, al iniciar la siguiente preparación, se retiran los restos.
- **El último respaldo válido del servidor no se toca** cuando falla una subida, porque el servidor no retira ninguna copia hasta que la nueva es AVAILABLE.
- **Una clave equivocada no borra nada.**

## 6. Compatibilidad con lo anterior

- **Copias remotas del formato 1, sin cifrar:** se reconocen por `formatVersion` y por su magic ZIP.
  - Se listan marcadas «sin cifrar (formato anterior)» y se pueden restaurar como hasta ahora, con un aviso.
  - No se convierten ni se borran en silencio. Salen sólo por borrado explícito o por la rotación documentada de 5 copias, cuando haya 5 cifradas más recientes.
  - **Migración:** subir una copia nueva, que ya va cifrada. Es la única «migración»: el contenido antiguo sigue en texto legible hasta que se retira.
  - **Límite:** en este bloque sólo existen copias sintéticas del formato 1.
- **Subidas nuevas del formato 1:** el Backend las sigue admitiendo para no romper la herramienta B2 de #160 (`tool/f08_b2`), que sube contenedores sintéticos del formato 1. `BACKUP_REQUIRE_CLIENT_ENCRYPTION=true` rechaza el formato 1 con 422 `BACKUP_ENCRYPTION_REQUIRED`.
  - Es una condición para admitir datos reales (enmienda del §5 del modelo de amenazas) y no altera la admisión, que sigue cerrada.
  - *Aclaración del 2026-10-24:* la herramienta de #160 integrada en BE `main` `4bcb1ea` también sube sobres sintéticos del formato 2, y exige elegir el formato con `F08_B151_FORMATO` para el ítem 6. El formato 1 sigue admitido por defecto.
- **Exportación local manual (`Descargas`):** sigue siendo el contenedor sin cifrar, que es la función de compartir de EVO-001. Fuera del alcance de este ADR; se declara como riesgo residual (§8).
- **Herramienta #160:** se conserva la versión del ensayo original. Un ensayo nuevo del formato 2 usa otra subcarpeta y una versión etiquetada de la herramienta, para no mezclar resultados.
  - *Aclaración del 2026-10-24:* los ensayos del formato 2 en B2 real se hicieron ese día bajo la raíz `ensayo-f08/b151-20261024/`, con una subcarpeta por ejecución. No se creó una etiqueta git: cada ejecución queda atada al SHA de la herramienta y del código que usó (BE `docs/evidence/F08_BKP_08_HERRAMIENTA_B151.md`, nota del 2026-10-24). La versión integrada (`8ce0263`) no se usó en ninguna de ellas y exige una raíz explícita (`F08_B151_RAIZ`), sin valor por defecto.

## 7. Limpieza local de `.previo`

**Qué es una `.previo`:** la copia de la base activa que `BackupService.restore` guarda antes de sustituirla. Hoy se escribe junto a la base como `<db>.previo-<stamp>.db` y **nunca se limpia**. La carpeta de fotografías previa ya se borra al terminar.

> **Aclaración del 2026-10-24.** «Hoy» es el estado anterior a #144. En `main` `1d77c14` las copias nuevas van a `previo/`, con su registro, y se limpian con las reglas del §7.2 (`maxResolved = 2` y `maxAge = 7 días`, en `restore_safety_copies.dart`). En el teléfono sólo se vio una entrada `finalized`, con `rw-------` y el estado anterior conservado (D8, primera ronda, árbol `84f9d82`). El plazo, la cota y una `interrupted` siguen sin ensayarse en DEVICE (§0.4).

### 7.1 Registro durable

- **Nueva carpeta:** `<databases>/previo/`, dentro de la carpeta privada.
- **Registro:** `previo/registro.json`, escrito de forma atómica (`.tmp` + flush + rename).
- **Cada entrada:** `{id, dbFile, invoicesDir?, createdAt, state, resolvedAt?}`.

| Estado | Se pone cuando | ¿Protegida? |
|---|---|---|
| `preparing` | Antes de escribir la copia | Sí |
| `finalized` | La restauración terminó, la outbox quedó pausada y **se comprobó el estado restaurado**: la base abre, `integrity_check` es `ok`, `user_version` es el de esta versión (ya migrada) y están las tablas de la aplicación. Si la comprobación falla, se deshace todo y la entrada queda `rolledBack` | No |
| `rolledBack` | La restauración falló y el rollback terminó sin error: la base activa vuelve a ser la anterior | No |
| `interrupted` | En el mantenimiento, una entrada `preparing` sin restauración en curso en este proceso, es decir, el proceso murió a medias | **Sí** |

- **Si el rollback falla**, la entrada queda en `preparing` y pasa a `interrupted`, protegida.
- **La propiedad no forma parte de la comprobación:** la reclasifica `GuardedRestore` y, si no puede, deja el acceso en null (falla cerrado) sobre una base íntegra. Revisión de B, I2, y de A, A3.
- **Proceso muerto antes de sustituir:** también deja una `interrupted` (conservador; revisión de B, m3). El mensaje del bloqueo dice que lo más probable es que los datos actuales estén bien y que «Mantener los actuales» lo resuelve.
- **Si la preparación falla antes de sustituir nada**, se borran la copia y su entrada, como hoy.
- **La protección no se deduce del nombre ni de suponer que el proceso terminó:** sólo de estados escritos en disco antes y después de cada paso.

### 7.2 Reglas (ratificadas el 2026-10-23)

En cada oportunidad de mantenimiento (al abrir la sección de respaldos, antes de cada restauración, después de terminarla y en la limpieza explícita), con un reloj inyectable:

1. **Plazo:** se retira toda entrada `finalized` o `rolledBack` con `resolvedAt` de más de **7 días**.
2. **Cota:** si quedan más de **2** `finalized`/`rolledBack`, se retiran las más antiguas hasta dejar 2.
- **Reloj:** el plazo usa el reloj del teléfono. Si se adelanta, las copias se retiran antes; si se atrasa, después. Es un límite declarado, igual que no prometer el séptimo día exacto (revisión de B, m3).
- **Un solo estado por proceso:** la cola de operaciones del registro y el conjunto de restauraciones en curso son únicos por carpeta `previo/` en todo el proceso, aunque haya varias instancias del servicio (revisión de B, C1).
3. **Protegidas:** nunca se retiran una `preparing` ni una `interrupted`, ni la base activa.
4. **Retirar** borra exactamente los archivos que nombra la entrada, dentro de `previo/`, y después la entrada. Nada de patrones.

**La cota y el plazo actúan por separado:**
- La cota de 2 no garantiza 7 días de conservación: una tercera restauración el mismo día retira la más antigua.
- El plazo retira las antiguas aunque haya menos de 2.
- No se promete la limpieza exacta al séptimo día con la app apagada: se hace en la siguiente oportunidad.

**Bloqueo:**
- Si existe una `interrupted`, **se bloquea otra restauración antes de tocar nada**, con este mensaje: «Hay una restauración anterior que no terminó; se conserva la copia de sus datos de entonces. Resuélvala antes de restaurar otra».
- Resolver es una acción explícita: «Mantener los datos actuales» la marca `rolledBack` (con fecha) y entra en las reglas normales.
- Recuperar el contenido de una copia `interrupted` desde la interfaz **queda fuera de este bloque**: es un procedimiento técnico, declarado como limitación.

**Copias heredadas:**
- Los `<db>.previo-*.db` que ya existen junto a la base, sin entrada, **no se borran automáticamente**: no se sabe si alguna fue indispensable.
- Se muestran en la limpieza explícita y se borran sólo una a una, con confirmación.

### 7.3 Protección (modelo de amenazas)

- Las `.previo` contienen la base en texto legible, igual que la base activa, y viven en su misma carpeta privada.
- Ni las `.previo` ni la base activa salen del teléfono por el respaldo de Google o la transferencia entre dispositivos (§3.8). El hallazgo de la primera versión de este ADR, que la base activa sí entraba, queda resuelto así.

## 8. Riesgo residual

- **Teléfono desbloqueado o comprometido:** en él, la clave está en el llavero. El cifrado protege el servidor y el bucket, no el dispositivo.
- **Sesión robada:** el atacante puede descargar ciphertext, pero no descifrarlo sin K_r.
- **La exportación local manual** sigue sin cifrar.
- **Sin un respaldo propio válido, desinstalar o cambiar de teléfono pierde los datos** (§3.8).
- **No hay firma:** un servidor comprometido puede borrar o retener copias (disponibilidad), pero no fabricar una que pase la etiqueta sin K_r.
- **Paquete de un solo mantenedor (§2.3).**
- **Rendimiento en el dispositivo: NOT_MEASURED** hasta el ensayo. *Aclaración del 2026-10-24:* sigue sin medirse (§0.4).
- **Accesibilidad (añadido el 2026-10-24):** `FLAG_SECURE` no oculta la clave al árbol de accesibilidad.
  - **Qué se vio:** en el ensayo DEVICE de A sobre la composición `bfee4dc`, `uiautomator` leyó el texto de dos claves pendientes, en `content-desc` y en el campo de confirmación. Cualquier servicio de accesibilidad con permiso puede leer lo mismo. A las descartó antes de activarlas, así que nunca protegieron ninguna copia.
  - **No es una regresión:** es el límite de la marca, que sólo actúa sobre la composición de la ventana (capturas, grabación y recientes).
  - **Por qué no se oculta:** quitar la semántica a la clave dejaría sin poder anotarla ni confirmarla a quien usa TalkBack. **Ocultarla o no es decisión de Roderich.** Hasta que decida, el código no cambia y el riesgo se declara.
  - **Lo que reduce el riesgo:** el servicio de accesibilidad debe estar activado por la persona en Ajustes. La clave sólo se muestra al crearla, al volver a verla con el PIN y al escribirla para recuperar.
  - *Aclaración del 2026-10-24:* **Roderich decidió mantener la accesibilidad de la clave para TalkBack** (§0.3). La semántica no se oculta y el riesgo se acepta tal como está declarado. `FLAG_SECURE` no protege frente a los servicios de accesibilidad autorizados.

## 9. Pruebas previstas

> **Aclaración del 2026-10-24.** Esta lista es la que se planificó el 2026-10-23. Lo ejecutado está en sus evidencias, cada una con su SHA y su entorno; este ADR no lo resume como cumplido:
> - **HOST** (dobles): Mobile `docs/evidence/F08_RESPALDO_CIFRADO_HOST.md`.
> - **PostgreSQL desechable** (CI): BE `backups.postgres.spec.ts`, en la CI de `main` `4bcb1ea`.
> - **B2 real**, con sobres sintéticos: BE `docs/evidence/F08_BKP_08_B2_REAL_FORMATO2.md`, `…_REPETICION.md` y `…_ACOTADA.md`. Conservan sus FAIL y NO_CONCLUYENTE.
> - **DEVICE**: Mobile `docs/evidence/F01_F08_DEVICE_COMPOSICION_2026-10-24.md`, de A, en tres rondas sobre árboles distintos.
>
> Lo que sigue pendiente está en el §0.4.

- **Vectores** RFC 8439 §2.8.2 y RFC 5869 A.1, contra la biblioteca fijada.
- **Ida y vuelta** en streaming, con clave correcta e incorrecta. Cabecera manipulada: versión, algoritmo, flags, `keyId`, sal, nonce y longitud. Ciphertext truncado, ampliado y con un bit alterado. Etiqueta alterada. Tamaño inconsistente. Límite de longitud.
- **Restauración remota:** formato 2 limpio. Clave equivocada y archivo alterado sin tocar la base. Formato 1 sin cifrar todavía restaurable y avisado. Espacio insuficiente simulado. Owner mismatch. Outbox pausada y liberada sin duplicar.
- **Llavero:** generar, confirmar, rechazar una confirmación errónea, rotar sin perder la clave necesaria, sobrevivir al cambio de PIN o sesión, y nunca aparecer en el SQLite exportado.
- **`.previo`:** reloj de prueba (plazo y cota por separado), `interrupted` protegida y bloqueante, heredadas intactas y rollback fallido protegido.
- **Backend:** forma exterior 422, formato 3 rechazado, `BACKUP_REQUIRE_CLIENT_ENCRYPTION` y la conservación de la rotación de 5 con el formato 2. Con dobles y PostgreSQL desechable. **El doble no acredita B2.**

## 10. Cambios compartidos que se piden a A

> **Aclaración del 2026-10-24.** Estado en los `main` integrados, comprobado con `git grep`:
> - Mobile `1d77c14`: `cryptography: 2.9.0` (`pubspec.yaml:46`); `MainActivity.kt` registra `ScreenSecureChannel`; las reglas de Android excluyen los cinco dominios (D9, inspección del paquete).
> - BE `4bcb1ea`: `BACKUP_REQUIRE_CLIENT_ENCRYPTION` está en `env.schema.ts`, y `docs/api/openapi-f08-backups.json` documenta `BACKUP_FORMAT_INVALID`.

- **Mobile `pubspec.yaml`/lock:** `cryptography: 2.9.0`, en el mismo turno que A (que también lo usará).
- **Mobile `android/app/src/main/res/xml/backup_rules.xml` y `data_extraction_rules.xml`:** exclusión de los cinco dominios (§3.8). Asignado por A a este frente el 2026-10-23.
- **Mobile `MainActivity.kt`:** sólo la línea que registra `ScreenSecureChannel` (archivo nuevo). Turno concedido por A el 2026-10-23. `SecureSessionPointerChannel` no cambia.
- **BE `env.schema.ts`:** `BACKUP_REQUIRE_CLIENT_ENCRYPTION` (booleano, por defecto `false`), si la configuración de backups no puede leerlo de su propio módulo.
- **BE `openapi-f08-backups.json`:** regenerarlo al final, por las descripciones de la cabecera de formato y los códigos 422 nuevos.
- **Liberadas:** BE `20261023110000` y Mobile v12.
