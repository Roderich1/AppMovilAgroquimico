# F03-MOB-AUTH-02 — base de primera activación (#19)

Estado: **FOUNDATION, no activación de producción**. Esta entrega no cierra #19 ni
modifica GATE-F03 (#23). La dependencia #20 (almacenamiento seguro) es material:
sin ella no hay recuperación duradera de la sesión y no se puede declarar una
activación definitiva. La próxima secuencia recomendada es revisar esta base,
implementar #20 con su contrato seguro y sólo entonces integrar y completar #19.

## Límites y decisión arquitectónica

`FirstActivationCoordinator` es una máquina de estados sin widgets, SQLite ni
almacenamiento de credenciales. Usa la identidad de instalación F02-B existente
(`InstallationClientIdStore`); exige el resultado `READY` del bootstrap y lee
de nuevo el UUID v4 canónico antes de construir el cliente HTTP. `CORRUPT`,
`UNAVAILABLE`, ausencia o corrupción del UUID impiden toda petición remota. No
crea otra identidad, no llama `getOrCreate()` ni `rotate()` para recuperarse.

La secuencia en memoria, sin reordenamiento ni reintentos automáticos, es:

1. `POST /api/v1/auth/v2/login` con email, contraseña y `refreshTransport=BODY`.
2. Validación inicial de Account, Member, Tenant y AuthSession activos, rol
   `AGRICULTOR`, transporte BODY y expiración futura.
3. `POST /api/v1/auth/clients` con el access JWT y el `clientId` existente.
4. Comprobación del ClientRegistration activo y no revocado.
5. `POST /api/v1/auth/v2/session/client` con su `registrationId`; comprobación
   de la respuesta vinculada al registro esperado.
6. `GET /api/v1/auth/v2/me` y comparación de Account, Member, Tenant, sesión,
   registro vinculado, estados, rol y expiración contra el login.
7. Entrega efímera de un `SessionCommitCandidate` al puerto seguro de #20. Sólo
   tras `commitAndVerify` se emite `completed`.

El candidato incluye refresh token y metadatos de sesión, nunca se serializa ni
se registra. Su `toString` está redactado. El estado observable y sus mensajes
no contienen secretos, UUID, payloads ni rutas internas. No se infiere un
`Member` central a partir del nombre de una persona contable local.

No existe implementación de producción de `SecureSessionCommitPort` ni ruta
de navegación para esta activación. El único puerto falso vive en tests. Por
ello, aunque el test del protocolo alcance `completed`, ningún usuario puede
activar su cuenta con esta base sola. La operación individual offline-first y
la base SQLite permanecen independientes.

## Máquina de estados y recuperación

`idle → checkingIdentity → preparingClient → loggingIn →
registeringClient → bindingSession → verifyingContext → committingSession →
completed`. En cualquier etapa previa a `committingSession` puede solicitarse
cancelación; no se aceptan activaciones paralelas ni cancelación durante el
commit atómico. Los errores concluyen en `failed` o `cancelled`, con resultado
de limpieza `notNeeded`, `confirmed` o `unconfirmed` y una marca separada de
resultado remoto desconocido.

Si ya se conoce la sesión del login, un fallo posterior provoca **un** intento
de logout idempotente con el refresh token en memoria. Un logout 204 confirma
la revocación de sesión; un fallo de logout queda `unconfirmed`. Si el login
falla por timeout, red o respuesta inválida, pudo haber creado una sesión pero
no se conoce su token: el resultado remoto queda desconocido y no se reintenta
a ciegas. Lo mismo aplica a resultados indeterminados de registro o binding;
un logout confirmado revoca la sesión conocida, pero no equivale a revocar un
ClientRegistration ya creado. El registro por `clientId` es idempotente sólo
según el contrato Backend vigente; ante conflicto o incertidumbre se requiere
reautenticación/reconciliación supervisada, no rotación del UUID.

Se clasifican configuración HTTPS ausente, 400, 401, 409, 429, timeout,
conexión, JSON/respuesta inválida, contexto incoherente, commit fallido y
cancelación. No se muestran respuestas HTTP ni excepciones crudas al usuario.
Los errores de identidad y red no bloquean, borran ni migran SQLite local.

## Contrato pendiente de #20

`SecureSessionCommitPort.commitAndVerify(candidate)` debe hacer un compromiso
duradero, cifrado y de todo-o-nada del refresh token y metadatos mínimos;
verificar lectura posterior; impedir persistencia en preferencias ordinarias,
SQLite, backups o archivos temporales sin protección; y dejar **ninguna**
credencial utilizable si lanza una excepción. Debe definir recuperación segura,
lectura y eliminación para #21/#22. Un éxito parcial o un simple write sin
readback no satisface el contrato. #19 no debe conectar UI/ruta de producción
ni declararse completado hasta integrar y probar una implementación real de
este puerto.

## Matriz de evidencia y pendientes

| Comportamiento | Evidencia de esta entrega | Límite |
|---|---|---|
| Identidad READY/CORRUPT/UNAVAILABLE y UUID canónico | Tests de coordinador con store simulado | DEVICE pendiente |
| Orden login/registro/binding/me y coherencia | `MockClient` y DTOs de #18 | E2E Mobile→Backend no ejecutado |
| 400/401/409/429, timeout, red, JSON inválido y limpieza | Tests unitarios | Reconciliación remota real pendiente |
| Concurrencia, cancelación y fallo de commit | Tests con puerto falso | Persistencia segura #20 pendiente |
| Datos individuales tras fallo remoto | Test SQLite local | DEVICE/offline-reopen #21 pendiente |
| Refresh, revocación, reautenticación | No implementados | #22 |

Riesgos residuales: sesión remota desconocida tras timeout de login, posible
registro remoto persistente tras fallo posterior, logout de compensación no
confirmado y ausencia de almacenamiento seguro/productive UI. Ninguno se
presenta como activación terminada. No se modifican Backend, F05, F06, backup,
esquema SQLite ni los criterios de GATE-F03.
