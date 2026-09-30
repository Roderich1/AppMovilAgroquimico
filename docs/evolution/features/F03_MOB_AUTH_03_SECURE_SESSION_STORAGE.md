# F03-MOB-AUTH-03 — almacenamiento seguro de sesión (#20)

Estado: **DRAFT, DEVICE NOT_MEASURED, #20 abierto**. Esta PR apilada sobre #63 no
activa una pantalla de producción ni cierra #19. No implementa refresh, Sync,
reapertura offline ni revocación remota.

## Decisión tecnológica

Se fija `flutter_secure_storage` **11.2.0** para cifrar **un único registro por
slot** con Android Keystore (RSA-OAEP para envolver la clave y AES-GCM para el
valor). `storageNamespace=agrocuentas_secure_session_v1` aísla datos, clave y
configuración. `resetOnError=false` evita que una lectura corrupta borre la
evidencia/sesión silenciosamente; `migrateOnAlgorithmChange=false` obliga a
planificar una migración futura. No se implementa criptografía propia.

Alternativas: `SharedPreferences` ordinarias y SQLite se descartaron por texto
plano; un `flutter_secure_storage.write` seguido de `read` se descartó como
prueba de durabilidad porque la biblioteca usa `SharedPreferences.apply()` en
Android; `EncryptedSharedPreferences` no se seleccionó porque Jetpack Security
está deprecado. Se eligió un puente Android pequeño que sólo confirma escritura
en disco y conmuta un puntero; no recibe ni cifra tokens. El SDK del proyecto
es Flutter 3.47.2 / Dart 3.13.2 y la dependencia resuelve con ese toolchain.

Fuentes primarias: [biblioteca y opciones Android](https://pub.dev/packages/flutter_secure_storage),
[cambios 11.2.0](https://pub.dev/packages/flutter_secure_storage/changelog),
[semántica `apply`/`commit`](https://developer.android.com/reference/android/content/SharedPreferences.Editor),
[reglas de Auto Backup](https://developer.android.com/identity/data/autobackup).

## Registro, acceso y estados

`SecureSessionStore` implementa `SecureSessionCommitPort` de #19. El JSON
cifrado versionado contiene sólo refresh token, installationClientId,
registrationId, accountId, memberId, tenantId, sessionId y expiresAt. No guarda
access JWT, contraseña, identificador físico ni persona contable SQLite. Un
único valor cifrado impide combinar token y metadatos de sesiones distintas;
AES-GCM detecta alteración del ciphertext. `StoredSession.toString`, errores y
estados observables no contienen secretos. Los consumidores no deben registrar
el objeto ni su contenido.

`read()` distingue `absent`, `available`, `corrupt`, `unavailable` e
`incompatible`. En `available` compara el UUID seudónimo existente de F02-B con
el almacenado, e informa `expiredLocally` sin asumir autorización/revocación
remota. Si falta o cambia la identidad de instalación, nunca devuelve el token.
Las futuras #21/#22 deben realizar su propia política offline/remota.

Hay dos slots cifrados `a` y `b` y un puntero Android
`AgrocuentasSessionPointer.xml`, que contiene únicamente `a` o `b`. Todas las
operaciones Dart se serializan por proceso; Android verifica `expected` bajo un
bloqueo antes de cambiar el puntero. La API permite leer y eliminar. No hay
implementación provisional en preferencias sin cifrar.

## Compromiso, interrupciones y sesión anterior

| Momento | Estado observable y recuperación |
|---|---|
| Antes de escribir | El puntero anterior sigue activo o no existe. Una sesión anterior válida se conserva. |
| Escritura del slot inactivo | La biblioteca usa `apply()`: el slot nuevo **no** es todavía una confirmación durable ni visible por `read()`. Una interrupción conserva el puntero anterior; un huérfano cifrado se puede sobrescribir después. |
| Verificación previa | Se relee y valida el JSON descifrado exacto. Fallo: no se activa el slot nuevo. |
| Barrera Android | `commit()` vacío en los tres archivos de preferencias de la biblioteca espera sus `apply()` pendientes y reporta fallo de disco. No se confunde una relectura en memoria con durabilidad. |
| Activación | `commit()` síncrono reemplaza el puntero y se verifica en la misma llamada nativa. Sólo entonces el nuevo registro queda seleccionado. |
| Verificación posterior | `read()` comprueba puntero, descifrado, esquema, identidad y candidato. Sólo un resultado coherente permite éxito. |

La sustitución de una sesión anterior **no** promete rollback atómico entre
Android Keystore, tres archivos de preferencias, MethodChannel y el puntero.
Si falla la llamada de activación o se pierde su respuesta, puede haberse
confirmado el puntero: se lanza `SecureSessionCommitOutcomeUnknown`, nunca se
declara éxito ni se afirma que la credencial nueva no existe. Ésta es la
incompatibilidad real que exige el ajuste mínimo del contrato de #19:
`localCommitUnknown=true` en el estado fallido. Un fallo antes de activar el
puntero sí deja seleccionada la sesión anterior. Tras incertidumbre se debe
releer/reconciliar y reautenticar; no reintentar a ciegas ni utilizar un token
que pueda haber sido revocado por la limpieza remota del coordinador.

`delete()` confirma primero la ausencia durable del puntero y después elimina
ambos ciphertexts y fuerza su escritura. Si falla la limpieza final, no queda
sesión utilizable por la API, pero puede quedar ciphertext huérfano y `delete()`
reporta error; una llamada posterior puede reintentar. Si falla la eliminación
del puntero, se conserva el estado anterior o se reporta incertidumbre. Las
pruebas con fakes demuestran la política del coordinador, **no** un corte de
energía ni la durabilidad física del dispositivo.

## Backup y aislamiento

`backup_rules.xml` (Android 11 o anterior) y `data_extraction_rules.xml`
(Android 12+, cloud y device-transfer) excluyen exactamente los cuatro archivos
de preferencias: datos cifrados, clave envuelta, configuración y puntero. No se
deshabilita el resto del backup Android. El UUID de instalación sigue en
`noBackupFilesDir`. El `.agrobackup` de Agrocuentas empaqueta SQLite individual
y fotos, no preferencias ni esta sesión. Tras reinstalación, la ausencia del
puntero da `absent`; si una restauración indebida conserva ciphertext pero la
identidad cambió, la lectura falla cerrada como `corrupt`.

La configuración Android se probó estáticamente; **cloud/D2D/reinstalación
físicos no están medidos**. Actualizar la biblioteca o cambiar su namespace
requiere volver a auditar rutas y reglas antes de publicar.

## Amenazas y límites

| Amenaza | Mitigación / límite |
|---|---|
| Texto plano, logs, SQLite, `.agrobackup` | Valor único cifrado; no se usan esas rutas; errores y `toString` redactados. |
| Auto Backup o transferencia cruzada | Exclusiones por archivo para las dos generaciones de reglas; verificar en DEVICE. |
| Corrupción, clave inaccesible o versión futura | Lectura `corrupt`/`unavailable`/`incompatible`; sin `resetOnError`; no se devuelve un token. |
| Interrupción o escrituras concurrentes | Slot inactivo, barrera `commit`, puntero esperado y serialización; respuesta perdida sigue siendo `unknown`. |
| Token antiguo o rotación futura | Sólo el puntero activo es accesible; #22 debe revocar/rotar y limpiar huérfanos. |
| Root, malware privilegiado, memoria del proceso | No hay resistencia absoluta; Keystore no garantiza respaldo hardware en todo dispositivo. |

## Matriz de verificación

| Nivel | Evidencia | Pendiente |
|---|---|---|
| UNIT con fakes | Commit/lectura, ausencia, corrupción, versión, errores, sesión anterior, concurrencia, expiración, identidad cruzada y cancelación incierta en #19. | No demuestra disco/Keystore. |
| Integración local | Adaptador Flutter con canal simulado; reglas XML verificadas; suite completa y build release. | No simula corte de energía. |
| DEVICE | `NOT_MEASURED`. | Procedimiento siguiente. |

### Procedimiento DEVICE pendiente (POCO X5 Pro, cuenta y token de prueba)

1. Usar instalación de pruebas aislada, nunca datos reales. Registrar modelo,
   API, build SHA, fecha y hash del APK de prueba.
2. Confirmar instalación limpia: `read=absent`; comprometer un token ficticio y
   verificar metadatos/identidad y ausencia de secretos en logcat, SQLite y
   `.agrobackup` exportado.
3. Force-stop y reapertura; luego reiniciar el teléfono y repetir la lectura.
4. Con herramientas de prueba controladas, simular fallo de escritura,
   verificación, eliminación y corrupción de ciphertext; registrar estado
   anterior/nuevo sin imprimir el token. No manipular la sesión de un usuario.
5. Probar dos commits sucesivos y comprobar que el puntero selecciona el último
   sólo tras confirmación; medir interrupción durante staging y activación.
6. Comprobar Auto Backup cloud y D2D donde estén disponibles y restaurar en
   otra instalación: no debe recuperarse una sesión ni el UUID anterior.
7. Desinstalar/reinstalar, verificar `absent` e identidad nueva; conservar
   capturas/logs sanitizados, checksums y resultados negativos.

No se declara #20 completado ni GATE-F03 aprobado con esta matriz pendiente.
