# F08 — Respaldo cifrado en el teléfono, clave de recuperación y `.previo`: evidencia HOST

| Campo | Valor |
|---|---|
| Fecha real | 2026-10-23 (America/La_Paz) |
| Origen | Implementación nueva de este bloque (no reconstruida) |
| Diseño | `docs/adr/F08-ADR-003-respaldo-cifrado-y-previo.md` (revisión de B: LISTO sobre el texto en `dfbcc7b`; A: LISTO con alineaciones, aplicadas) |
| Rama | `feat/f08-respaldo-cifrado`, sobre `f90d330` (dependencia común `cryptography: 2.9.0`, de A) sobre `b0d169b` |
| Entorno | **HOST**: Windows 11, Flutter 3.47.2 stable, `sqflite_common_ffi`. **Nada de esto es DEVICE ni B2 real** |
| Datos | Sintéticos: bases y fotos generadas por las pruebas, claves efímeras generadas en cada prueba. Ninguna clave se imprime ni se guarda |

## 1. Qué se implementó

- **`lib/data/backup_encryption.dart`:**
  - formato 2: cabecera de 80 bytes como AAD y ChaCha20-Poly1305 en streaming, con clave por archivo derivada por HKDF-SHA256 de la clave de recuperación;
  - la clave de recuperación: 32 bytes, Base32 de Crockford en 14 grupos y suma de comprobación;
  - límites antes de descifrar y `.part` hasta verificar la etiqueta.
- **`lib/services/backup/backup_keyring.dart`:**
  - llavero en `flutter_secure_storage`, con un espacio de nombres propio, `agrocuentas_backup_keys_v1`;
  - la clave pasa de pendiente a confirmada y después a retirada, y no se borra automáticamente;
  - `id remoto → keyId`.
- **`lib/services/backup/remote_backup_service.dart`:**
  - la subida se cifra desde la carpeta privada y se vuelve a descifrar para comprobarla;
  - restauración: transporte, descifrado, validación interna, propiedad, confirmación y `GuardedRestore`;
  - `RecoveryKeyRequired` cuando falta la clave;
  - las copias del formato 1 se siguen pudiendo restaurar, con aviso.
- **`lib/data/restore_safety_copies.dart` y `BackupService.restore`:**
  - registro durable de las `.previo` en `<databases>/previo/`;
  - plazo de 7 días y cota de 2, por separado;
  - `interrupted` protegida y bloqueante;
  - las heredadas, sólo por acción expresa;
  - comprobación del estado restaurado antes de `finalized`.
- **Interfaz:**
  - pantalla de la clave: mostrar, marcar «la anoté», volver a escribirla completa y confirmar;
  - petición de la clave al restaurar;
  - etiquetas «cifrada / SIN CIFRAR»;
  - sección «Copias previas a restauraciones».
- **Android:** exclusiones de auto-backup y de transferencia del llavero, de `database/previo` y de `file/remote_backups` (turno de A, devuelto en `0af382c`).
- **Fotos de los borradores tardíos (RF-03 de A):** `late_operation_drafts.invoice_image_path`, si la columna existe, viaja y se reapunta.

## 2. Pruebas ejecutadas

### 2.1 Suite completa (turno pesado concedido por A)

| SHA | Comando | Resultado |
|---|---|---|
| `e4f16bf` | `flutter test --reporter expanded` | **+731 ~3 −1** |

El único fallo es `operation_mode_onboarding_test.dart` («propio → compartido con historial…», l. 157: no aparece el snackbar a tiempo). Al repetir el archivo solo: **3/3 PASS**. No toca respaldos. Queda **NO_CONCLUYENTE**, por tiempos bajo carga.

Después de `e4f16bf` hubo cambios (revisión de B y A, la comprobación del estado restaurado, fotos de los borradores y códigos 422). **La suite completa no se volvió a ejecutar sobre el HEAD final**: el turno pesado quedó bloqueado por memoria (CONTROL §7). Los archivos afectados se ejecutaron uno a uno (§2.2).

### 2.2 Archivos ejecutados tras los cambios

| Archivo | Resultado | Cubre |
|---|---|---|
| `f08_backup_encryption_test.dart` | 32 PASS | Vectores RFC 8439 §2.8.2 y RFC 5869 A.1 contra la biblioteca fijada. AAD autenticado en streaming. Ida y vuelta 0 / 1 / 65535 / 65536 / 300001 bytes. Clave incorrecta (por identificador). Sin clave, no escribe. Bit alterado en el ciphertext, en el último bloque y en la etiqueta. Sal y nonce alterados. Versión, algoritmo y flags. Magic. Truncado de cuatro formas, también con la longitud ajustada. Bytes añadidos. Límite antes de descifrar. Longitud enorme. El destino previo no se pierde |
| `f08_backup_keyring_test.dart` | 9 PASS | Pendiente → confirmada. Confirmación errónea. Descarte. Rotación (la anterior sigue descifrando). Clave recuperada activa o retirada. Llavero ilegible no sobrescrito. Escrituras simultáneas. El llavero no está en SQLite. Exclusiones en los XML |
| `f08_restore_safety_copies_test.dart` | 15 PASS | Reloj de prueba. Cota con 3 finalizadas el mismo día. Plazo con 1 sola (7 días exactos no; 7 días + 1 s sí). Plazo desde la resolución también en un rollback. Sin mantenimiento no se borra nada. `interrupted` protegida para siempre y bloqueante hasta «Mantener los actuales». Restauración en curso no interrumpida. Heredadas y ajenas intactas. Registro ilegible. Registro atómico. Con `BackupService`: 3 restauraciones dejan 2; un rollback terminado queda `rolledBack`; un rollback que no termina queda `interrupted` y bloquea la siguiente sin tocar la base; un esquema distinto tras restaurar provoca rollback; un rechazo antes de preparar no deja copia |
| `f08_recovery_key_screen_test.dart` | 1 PASS | No se continúa sin «la anoté». Campo sin sugerencias, sin autocorrección y sin aprendizaje del teclado. Clave con un carácter cambiado rechazada. Clave correcta activada |
| `f08_late_draft_photos_test.dart` | 2 PASS | La foto de un borrador tardío viaja y se reapunta. Sin la tabla no cambia nada |
| `remote_backup_client_test.dart` | 41 PASS | Las 29 anteriores, adaptadas al formato cifrado, más las del grupo F08-ADR-003 (§3) |
| Restauración existente: `backup_service`, `f10_restore_wal_rollback`, `f04_restore_authorization`, `rec_019_restore_legacy_schema`, `backup_restore_sha256`, `f10_backup_extract_limits`, `backup_container`, `backup_export_atomic`, `f04_restore_ownership_rules`, `f04_admin_owner_restore_ui` | todas PASS | WAL/rollback, exclusión de escrituras, propiedad, límites del contenedor y formato histórico, sin regresión. Las búsquedas de restos `.previo-` pasan a ser recursivas, porque las copias viven ahora en `previo/` |
| `secure_session_store_test`, `refresh_guard_test` | 23 PASS | Las exclusiones de la sesión siguen en los XML |

`flutter analyze`: sin incidencias.

### 2.3 Restauración remota (`remote_backup_client_test.dart`, contra un doble HTTP del servidor; **no es el Backend real ni B2**)

| Caso | Resultado |
|---|---|
| El servidor sólo recibe el formato 2 | Magic `AGROENC`; ni `SQLite format 3`, ni `manifest.json`, ni `agrocuentas` en los bytes; ningún `.agrobackup` en la carpeta de respaldos locales |
| Teléfono nuevo sin la clave | `RecoveryKeyRequired`. Una clave equivocada da `wrongKey` y una mal escrita, error de comprobación, las dos sin cambios en la base. Con la clave correcta (en minúsculas) restaura datos, fotos y la cola `RESTORE_PAUSED` como antes, y la clave queda activa |
| Clave distinta de la activa | Queda retirada. La subida siguiente usa la activa y la copia antigua se descifra sin volver a escribirla |
| Copia de otro Member, con la clave correcta | Se rechaza por propiedad y la base no cambia |
| Contenedor alterado por dentro y vuelto a cifrar con la misma clave | Lo detecta la validación interna, no el cifrado |
| Cifrado alterado o truncado, o sin la etiqueta, con un SHA-256 de transporte coherente | Falla el cifrado. Base, fotos y carpeta privada intactas |
| Metadatos falsos: formato 2 con contenido legible, formato 1 con contenido cifrado, formato 3 | Rechazo sin tocar nada |
| Formato 1 heredado | Se restaura con `unencrypted` y queda intacto en el servidor |
| Sin clave confirmada | No sale ninguna petición |
| Rotación | La copia anterior sigue descifrándose |
| Cambio de sesión | No toca el llavero |
| Cola restaurada | Pausada antes de que nadie vea la base; liberada sin duplicar (pruebas existentes, ahora con copia cifrada) |

### 2.4 Rendimiento en el host (orientativo, JIT; **NOT_MEASURED en el dispositivo**)

Un archivo temporal, no commiteado, con 50 MiB aleatorios:
- cifrado en 1419 ms y descifrado con verificación en 2011 ms;
- RSS máximo del proceso de prueba, 148 MiB. No está aislado: incluye el arnés.

No se fija ningún tiempo ni consumo para Android: se mide en el ensayo del teléfono (turno de A).

## 3. Lo que esta evidencia **no** acredita

- **DEVICE:** pendiente del turno de A con un paquete aislado.
- **B2 real (#151):** BLOQUEADO. No existen los perfiles `b151-*`; sólo la clave amplia, que no se usa.
- **Usabilidad:** pendiente. Que la persona anote y vuelva a escribir la clave se prueba con un widget, no con personas.
- **Mostrar o cambiar la clave de nuevo:** en esta rama **falla cerrado** a propósito (`backupKeyAuthorizerProvider`). Se conecta con la credencial local de A en la composición (`comp/f01-f08-mob`). No es un defecto del ensayo.
- **La base activa en el auto-backup de Google:** sigue incluida. Es una decisión pendiente de Roderich (CONTROL §8b).
- **Exportación local manual:** sigue sin cifrar (EVO-001).
- **La pantalla que muestra la clave no usa `FLAG_SECURE`:** la miniatura de «recientes» y las capturas de pantalla pueden conservarla. Hace falta un canal en `MainActivity` (archivo general de A): queda como limitación declarada y propuesta.

## 4. Revisión de defectos de la implementación (agente de revisión de C, sólo lectura; no es una revisión de B ni independiente)

Corregidos en el commit siguiente a `6190a05`, con su prueba de regresión:

1. **Importante.** Un llavero ilegible (JSON dañado o Keystore invalidado) bloqueaba restaurar y listar, y no había salida. Ahora el llavero ilegible se trata como «no tengo la clave»: se pide la clave escrita; las copias se listan como «pedirá la clave»; la lectura que falla cuenta como ilegible, no como vacía; y hay una acción expresa, «Empezar un llavero nuevo», con aviso.
2. **Menor.** Una copia en preparación cuyo paso a interrumpida no se pudo guardar ya no deja restaurar otra: bloquea cualquier `preparing` ajena al proceso en curso.
3. **Menor.** El registro, su `.tmp`, los registros apartados y los `.part` propios ya no se ofrecen como «copias sin registro». El texto del diálogo se ajustó.
4. **Menor.** Las operaciones del registro `.previo` se serializan.
5. **Menor.** Si no se puede anotar la clave de una subida que ya llegó al servidor, la subida no se da por fallida: se avisa.
6. **Menor.** Los restos de la carpeta de trabajo remota se limpian al abrir la pantalla. `FLAG_SECURE` queda como limitación (§3).

Además, una observación de diseño: la cota de 2 cuenta juntas las `finalized` y las `rolledBack`. Dos restauraciones fallidas seguidas retiran la copia previa de la última que terminó, aunque las `rolledBack` dupliquen los datos actuales. Es lo ratificado; se informa a Roderich.

Archivos ejecutados tras las correcciones: keyring 10, previo 17 y remoto 43 (70 en total, PASS), más 130 de restauración, cifrado, pantalla y borradores (PASS). `flutter analyze`: limpio.
