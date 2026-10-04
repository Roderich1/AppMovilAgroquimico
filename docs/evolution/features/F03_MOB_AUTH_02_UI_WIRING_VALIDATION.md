# F03-MOB-AUTH-02 — presentación y wiring de primera activación

Estado: **implementado en PR #63, pendiente de auditoría y merge**. Código de
UI/wiring: `2b571a6dd9d277884cd636c4ccf4958c5d80f903`. Este informe
complementa la foundation histórica de #19; no modifica sus resultados previos
ni la evidencia física de #20. Fecha de validación local: 2026-09-30.

## Alcance y secuencia

`main.dart` inicializa la identidad F02-B y entrega su resultado a Riverpod.
Un fallo `CORRUPT` o `UNAVAILABLE` no bloquea el dominio SQLite, pero deshabilita
la activación remota. La pantalla `/activar` es una ruta real de GoRouter,
accesible desde el botón **Activar cuenta en línea** de Inicio. Es una entrada
explícita, no una política de reapertura ni una ruta oculta de test.

La composición productiva inyecta el `InstallationClientIdStore` existente,
`ApiEndpointConfig.fromEnvironment()`, un `http.Client` administrado por
Riverpod, `AuthHttpClient`, `AuthV2Api` y
`SecureSessionStore.android(identityStore: ...)`. El cliente HTTP se cierra al
liberar su provider. La URL se lee sólo al iniciar un intento real; no se
introduce un origin alternativo si falta `AGRO_API_BASE_URL`. Se preservan HTTPS,
validación origin-only, seis rutas permitidas y la prohibición de redirects.
Los dobles de HTTP y secure commit están limitados a tests.

El controlador conecta los cambios de estado de `FirstActivationCoordinator`
con la UI. El recorrido es login V2/BODY → registrar UUID lógico F02-B →
vincular ClientRegistration → `/me` y verificación de contexto →
`commitAndVerify` del refresh en el almacén seguro → `completed`. Sólo entonces
se borra la contraseña del controlador y se navega una vez al dominio local.
No se almacena el access JWT. La contraseña también se limpia al terminar un
intento fallido o cancelado. Los formularios se deshabilitan durante la
operación y no aceptan doble submit.

`localCommitUnknown` y `remoteOutcomeUnknown` muestran una instrucción de
reconciliación y deshabilitan nuevos intentos en esta ejecución. No se borra
el almacén ni SQLite, no se rota el clientId y no se reintentan operaciones
remotas de resultado incierto. Los mensajes visibles provienen de
`FirstActivationProblem.safeMessage`, nunca de una excepción o payload.
La cancelación se solicita al coordinador; no se fuerza durante el secure
commit. Un resultado cancelado o fallido no navega como éxito.

## Fronteras

- **#21, ExistingSessionStartup:** leer y reconciliar la sesión al abrir la app,
  y definir la política posterior offline/online. El marcador de incertidumbre
  de la UI es de esta ejecución, no una solución persistente de reapertura.
- **#22:** refresh silencioso, rotación, revocación, reautenticación y política
  de resolución remota. No se invoca refresh en startup ni en esta pantalla.
- La operación individual SQLite continúa independiente. No se modificaron
  esquema, backups, F05/F06 ni Backend.

## Validación automática

Baseline 581 tests. Se añadieron 26 tests de UI/DI; **607/607** pasaron en
`flutter test --reporter expanded` el 2026-09-30. Cubren entrada real desde
Inicio, validación vacía, contraseña oculta, submit único, progreso, 400/401/
403/409/429, timeout, fallo de red, configuración HTTPS ausente, JSON inválido,
contexto no autorizado o incoherente, identidad corrupta/no disponible, navegación
única tras commit, fallos de commit, incertidumbre local/remota, cancelación,
ausencia de secretos en textos de error y SQLite disponible tras 401. Los tests
usan `MockClient` y un commit port falso: **no son E2E Mobile→Backend**.
El test de composición comprueba el binding de producción a la factoría
Android-only; las pruebas físicas de Keystore siguen en la evidencia #20.
El caso de configuración descubrió que una excepción emitida dentro de un
provider quedaba envuelta por Riverpod y aparecía como error inesperado. El
wiring ahora representa explícitamente configuración ausente y entrega al
coordinador su error tipado antes de construir HTTP.

`flutter pub get`, `flutter analyze`, `dart format --output=none
--set-exit-if-changed lib test`, `git diff --check` y
`flutter build apk --release` pasaron. El APK release local sin
`AGRO_API_BASE_URL` fue generado sin modificar las restricciones de red:
SHA-256 `8387CA8A1E7AC82A3E893B1B7DC8FE1324FDE2F2D4D00F06206712839EAEAA3F`
(66 637 491 bytes). El build no equivale a instalación física ni E2E.

## Backend, E2E y DEVICE

El OpenAPI de Backend `a09876106dd696868217b301a9abf9125ac6d01d`
contiene las seis rutas utilizadas. No hay `AGRO_API_BASE_URL` ni credenciales
de cuenta AGRICULTOR de prueba configuradas en este entorno; no se ejecutó un
login contra un Backend HTTPS real. `E2E_MOBILE_BACKEND = BLOCKED_ENVIRONMENT`.
Ni los tests widget ni el build reemplazan ese resultado.

El POCO X5 Pro 5G (`22101320G`), Android 12/API 31, `arm64-v8a`, está
conectado por ADB. Para no sobrescribir la app normal se compiló una copia
debug temporal con suffix `.auth02validation`, no versionada, SHA-256
`86FB3E5D2CA0AED4A78ACE48898A137E6E0A848B136E0C09D02FDF9E7C5DB9A9`.
Dos intentos de instalación fueron rechazados por MIUI con
`INSTALL_FAILED_USER_RESTRICTED`; el suffix se retiró del árbol de trabajo.
Por tanto DEVICE-A/B/C/D/E quedan **NOT_MEASURED** hasta autorizar la
instalación USB; no se afirma interacción visual ni E2E. La validación #20
existente no se repitió y no equivale a DEVICE-E de esta UI.
Este párrafo registra aquel intento histórico; el reintento autorizado y sus
resultados se documentan al final de este informe.

## Seguridad y riesgos residuales

La UI no escribe password ni access JWT en SQLite, preferencias, backups,
archivos o logs. El refresh se entrega sólo a `SecureSessionStore.android`;
su aislamiento cifrado y exclusiones de `.agrobackup` están documentados en
la evidencia propia de #20. La activación no debilita TLS ni usa HTTP.

Permanecen **NOT_MEASURED** el restore de Android Auto Backup, el restore D2D
y la pérdida física de energía; la concurrencia multi-isolate queda
**NOT_CLAIMED**. También quedan pendientes E2E nominal/fallido sobre HTTPS,
reconciliación al reabrir (#21) y políticas de refresh/revocación (#22).
PR #63 debe seguir draft; #19 y #20 abiertos; GATE-F03 #23 pendiente.

## Corrective audit — reactivación durante el mismo runtime

La auditoría pre-integración detectó que, tras `completed → /`, abrir de nuevo
`/activar` creaba una nueva instancia de pantalla con `_navigated = false`,
mientras el `firstActivationProvider` conservaba `completed`. El formulario no
consultaba ese estado para impedir otro intento. La regresión
`completed activation cannot be repeated in the same runtime` se ejecutó
primero contra el código anterior: esperaba un login y observó **dos**.

La pantalla ahora comprueba `state.isCompleted` antes de construir el
formulario y muestra solamente una explicación de alcance local y la acción
**Continuar con datos locales**. `_submit()` también se niega a iniciar una
activación si el provider ya está en `completed`, aunque se intentara llamar
por otra ruta de UI. No se modificaron `FirstActivationCoordinator`, Dashboard,
almacenamiento #20 ni contratos HTTP.

La misma prueba pasa después del cambio: al volver a `/activar` bajo el mismo
`ProviderScope` no hay formulario ni password reutilizable; el estado sigue
`completed`, `loginCalls = 1`, `commit.calls = 1` y la secuencia remota completa
no se repite. Se verificó la navegación de regreso al dominio local. La suite
anterior de 607 pruebas sigue intacta: **608/608 PASS**; `flutter pub get`,
formato, `flutter analyze`, `git diff --check` y build release local PASS.

`SAME_RUNTIME_REACTIVATION = BLOCKED` por la guarda de UI y la regresión.
`EXISTING_SESSION_AFTER_RESTART = #21 / NOT_IMPLEMENTED`: un nuevo proceso aún
no reconstruye `completed` desde el almacén seguro, ni se afirma vigencia
remota o funcionamiento offline posterior. Refresh/revocación siguen en #22.
El Backend HTTPS de pruebas y una cuenta AGRICULTOR de desarrollo aún faltan:
`E2E_MOBILE_BACKEND = BLOCKED_ENVIRONMENT`.

En el primer preflight DEVICE de esta corrección, `adb devices -l` no mostró
ningún dispositivo; un segundo sondeo tampoco. No se instaló APK ni se tocó la
aplicación normal. DEVICE-A/B están bloqueados por desconexión/autorización
USB; DEVICE-C/D/E/F permanecen `NOT_MEASURED` por ausencia de entorno HTTPS,
activación real y/o dispositivo. Los rechazos MIUI de la medición anterior
siguen siendo evidencia histórica, no un PASS. La prueba widget de mismo
runtime no se presenta como validación física DEVICE-F.
Ese preflight sin dispositivo también es histórico; no sustituye el resultado
del reintento posterior.

## Reintento DEVICE autorizado — 2026-09-30

Después de que el propietario conectó y autorizó el teléfono por USB,
`adb devices -l` mostró `cc14… device`, modelo `22101320G` (POCO X5 Pro 5G),
Android 12/API 31, `arm64-v8a`. Se construyó desde el HEAD corregido
`d824ee89e1c38f720041cfdb5015323717eb8d3f` una copia **debug aislada**:
`com.comunidad.agro.agroquimicos.auth02validation`, etiqueta
`Agrocuentas F03 test`. El APK tenía 169 788 998 bytes y SHA-256
`15BAAC7A239A70C9CDA70FF5E6B4D623B0A0BB63F690D2D98D3D725964AA3971`.
El suffix y la etiqueta fueron cambios locales temporales, retirados antes de
publicar. `adb install` respondió `Success`; el paquete normal
`com.comunidad.agro.agroquimicos` permaneció instalado por separado.

| Caso | Resultado físico | Evidencia y límite |
|---|---|---|
| DEVICE-A — pantalla | **PASS** | Desde Inicio se abrió `Activar cuenta en línea`; se vio la pantalla correcta, correo editable, contraseña enmascarada, teclado y acciones utilizables sin overflow visible, y `Continuar con datos locales` disponible. |
| DEVICE-B — configuración ausente | **PASS** | Con correo y contraseña exclusivamente sintéticos se pulsó `Activar` sin `AGRO_API_BASE_URL`. Apareció `La conexión segura todavía no está configurada.`, la contraseña quedó vacía, la app siguió abierta y `Continuar con datos locales` devolvió a Inicio. Es fallo seguro de configuración, no validación de credenciales ni E2E. |
| DEVICE-C — pérdida de red real | **NOT_MEASURED** | Sin origin HTTPS de prueba no se inició request de red que pudiera interrumpirse. |
| DEVICE-D — completed real | **NOT_MEASURED** | Faltan origin HTTPS alcanzable y cuenta AGRICULTOR de desarrollo. |
| DEVICE-E — force-stop posterior | **NOT_MEASURED** | Depende de DEVICE-D; la evidencia previa de #20 no sustituye esta prueba. |
| DEVICE-F — reactivación en el mismo runtime | **NOT_MEASURED** | Depende de DEVICE-D. La regresión widget de 608/608 sigue siendo evidencia contractual, no física. |

La inspección se hizo con capturas de la copia aislada y entradas ADB de prueba;
no se capturaron ni emplearon credenciales reales. La ausencia de crash se
observó en pantalla durante DEVICE-B, sin afirmar una auditoría completa de
logs. `E2E_MOBILE_BACKEND = BLOCKED_ENVIRONMENT` y
`EXISTING_SESSION_AFTER_RESTART = #21 / NOT_IMPLEMENTED` permanecen sin cambios.

## E2E Mobile→Backend after integration

Medición física del **2026-10-04** (America/La_Paz), posterior a la integración.
Esta sección reemplaza el bloqueo ambiental para el recorrido nominal medido;
los resultados anteriores conservan su fecha y alcance histórico. No cierra
#19 ni GATE-F03 #23 y queda pendiente de auditoría independiente.

### Entorno y reproducción

- Mobile exacto: `18b9de3bc0f9702ed22863f933cf93cd691ee491`; baseline de
  **690 tests**, sin cambios funcionales durante esta medición.
- Backend exacto: `a09876106dd696868217b301a9abf9125ac6d01d`.
- Dispositivo: POCO X5 Pro 5G (`22101320G`), Android 12 / API 31,
  `arm64-v8a`; ADB autorizado, identificado únicamente como `cc14…`.
- PostgreSQL 16 en container y volumen exclusivos, DB `agro_f03_e2e`, puerto
  local alternativo 55432. No se utilizaron bases ni datos reales del sindicato.
  Se ejecutaron `npm ci`, Prisma generate, las cuatro migraciones mediante
  `prisma migrate deploy`, build, build de seed y seed sobre esta DB efímera.
  Se conservaron schema, migraciones y dependencias del SHA contractual.
- Se eligió el primer agricultor de `farmersSeed`. Antes del login, SQL confirmó
  User activo/AGRICULTOR, Member activo/AGRICULTOR y Tenant activo. La contraseña
  demo se obtuvo del seed y se introdujo en un campo enmascarado; no se incluye
  en este documento ni en GitHub. No hubo login adicional de preflight.
- Backend local, secretos JWT y contraseña PostgreSQL temporales en memoria.
  Health local y health HTTPS devolvieron **200** antes de instalar la copia.
  Un túnel temporal cloudflared entregó un origin HTTPS público confiable:
  `HTTPS_EPHEMERAL_ORIGIN_REDACTED`. Android lo aceptó durante las cuatro
  operaciones reales, con la validación TLS y origin-only productivas intactas.
  No se introdujeron certificados alternativos ni bypass TLS.
- Worktrees aislados desde ambos SHAs. Sólo para la build se añadieron suffix
  `.f03auth02e2e` y etiqueta `Agrocuentas F03 E2E`. El origin se pasó mediante
  `--dart-define=AGRO_API_BASE_URL`, nunca como modificación de source.
  APK debug SHA-256:
  `3BDCDC6746EC72FC9BFCD8A14053CC884D9027A992771E4F0660548E8254B208`.
- Package de prueba: `com.comunidad.agro.agroquimicos.f03auth02e2e`.
  Instalación **Success**, inicialmente sin sesión precargada, con identidad
  de instalación F02-B y SQLite propios. Coexistió con el package normal
  `com.comunidad.agro.agroquimicos`, al que no se instaló ni limpió nada.

Se utilizó la composición productiva Flutter, `InstallationClientIdStore` y
`SecureSessionStore.android`, transporte HTTPS, AuthV2Controller/Nest y
PostgreSQL reales. Un proxy local temporal transparente reenvió las peticiones
al Backend exacto y conservó únicamente método, ruta y status para observar la
secuencia; no simuló respuestas, no inspeccionó payloads y no registró headers.
No hubo harness de sesión ni mocks en este recorrido.

### DEVICE-D — activación nominal real

Desde Inicio se observó **Activar cuenta en línea**, se abrió la pantalla
productiva `/activar`, se introdujeron las credenciales seed y se pulsó una vez
**Activar**. La secuencia HTTP observada fue:

| Operación | Ruta real | Status | Clasificación |
|---|---|---|---|
| Login BODY | `POST /api/v1/auth/v2/login` | 200 | `LOGIN_200 = PASS` |
| Registrar instalación | `POST /api/v1/auth/clients` | 201 | `CLIENT_REGISTER_201 = PASS` |
| Vincular sesión | `POST /api/v1/auth/v2/session/client` | 201 | `SESSION_BIND_201 = PASS` |
| Contexto autenticado | `GET /api/v1/auth/v2/me` | 200 | `ME_200 = PASS` |

No hubo 429 ni repetición del login. Las fases fueron demasiado rápidas para
documentar cada label como observado. Al terminar, la UI navegó a Inicio y
mostró **Cuenta vinculada en este dispositivo. El estado en línea aún no fue
verificado.**; ya no ofreció primera activación. Las consultas del Dashboard y
la pantalla Personas abrieron SQLite; se comprobó la existencia de
`agroquimicos_v2.db` dentro del package aislado.

La composición real sólo emite `completed` después de `commitAndVerify` y
reconcilia su resultado local. Se confirmó el commit Android mediante el
resultado de UI, la presencia de los archivos del namespace cifrado y del
puntero durable (sin leer credenciales), y la recuperación física posterior de
DEVICE-E. La navegación productiva limpia `_password` antes de `context.go('/')`,
como se comprobó en el source exacto. Tras navegar ya no había campo de password;
su valor vacío no se inspeccionó directamente después de abandonar la pantalla.
No se publica una captura del formulario con las credenciales.

La consulta SQL posterior, sin devolver IDs ni hashes, confirmó:

| Comprobación | Resultado |
|---|---|
| User AGRICULTOR, Member y Tenant activos | PASS |
| ClientRegistration para el Member de prueba | **1** |
| `CLIENT_REGISTRATION_ACTIVE` | PASS |
| AuthSession activa | PASS |
| `clientRegistrationId` no nulo y asociado a esa instalación/Member | PASS |
| `SESSION_BOUND_TO_REGISTRATION` | PASS |
| `REFRESH_TRANSPORT_BODY` | PASS |

`DEVICE-D_COMPLETED_REAL = PASS`.
`E2E_MOBILE_BACKEND_NOMINAL = PASS`.

### DEVICE-E — force-stop después de la activación real

Sin reinstalar ni precargar una sesión, se desactivaron datos móviles y Wi-Fi.
Se verificó su estado **0/0** y se ejecutó force-stop únicamente del package
E2E; se confirmó que el proceso había terminado. Después se abrió la copia
mediante su launcher normal, todavía offline.

Tras completar startup, Inicio mostró nuevamente la cuenta vinculada local,
la acción **Verificar acceso en línea** y el mensaje de estado remoto todavía
no verificado. Primera activación siguió ausente. Dashboard/SQLite estuvieron
disponibles y no hubo crash. El observador HTTP no recibió nuevas peticiones
durante esta reapertura. Los archivos del almacén cifrado, del puntero y de
identidad no-backup permanecieron presentes; no se imprimió su contenido.
No se creó un marcador SQLite adicional: la comprobación cubre reapertura de
la base y sus consultas, no persistencia de una nueva transacción de negocio.

`DEVICE-E_FORCE_STOP_AFTER_REAL_ACTIVATION = PASS`.
Esto acredita recuperación de la sesión local realmente creada en D; no
demuestra refresh remoto ni autorización Backend vigente al reabrir offline.

### Matriz vigente y límites

| Caso | Resultado | Alcance |
|---|---|---|
| DEVICE-A | PASS histórico | Pantalla y entrada, medición del 2026-09-30 conservada. |
| DEVICE-B | PASS histórico | Configuración ausente y password vacío, medición del 2026-09-30 conservada. |
| DEVICE-C | NOT_MEASURED | No se interrumpió una activación en curso; la ventana nominal fue breve y no se alteró el producto para provocarla. |
| DEVICE-D | PASS | Primera activación física, HTTPS/Nest/PostgreSQL y commit Android reales. |
| DEVICE-E | PASS | Recuperación local offline después de force-stop de la sesión creada en D. |
| DEVICE-F | NOT_MEASURED | Dashboard no ofrece activar tras D; no se identificó una entrada productiva disponible para repetir `/activar` en ese runtime. |
| `SAME_RUNTIME_REACTIVATION` | BLOCKED_AUTOMATED | La regresión automatizada previa sigue siendo evidencia propia; no se fabricó un PASS físico. |
| `E2E_MOBILE_BACKEND_NOMINAL` | PASS | Sólo la secuencia nominal de primera activación descrita arriba. |

No se midieron en esta ejecución pérdida de red transaccional, reactivación
física en el mismo runtime, refresh real ni revocación real. Tampoco Auto
Backup, D2D, pérdida física de energía o concurrencia multi-isolate. D/E no
cambian las clasificaciones DEVICE de #22 ni autorizan producción.

### Privacidad, limpieza y gobierno

El análisis en memoria de logcat del UID exclusivo de la copia abarcó
activación y reapertura (**238 líneas**) y encontró **0** coincidencias de la
contraseña seed, patrones JWT, UUID completos, asignaciones de nombres
sensibles y señales `FATAL EXCEPTION`/`Unhandled Exception`. Se publican
únicamente estos resultados sanitizados. Este scan acotado no es una prueba
general de ausencia de filtración. La evidencia versionada y los textos de
GitHub no contienen password, JWT, refresh, hostname del túnel, serial completo
ni IDs internos. Los outputs locales de herramientas de preparación no se
publican como artefactos ni logs de evidencia.

Al terminar se detuvieron túnel, proxy y Backend; se verificaron **0** procesos
cloudflared y **0** listeners de los dos puertos Backend/proxy temporales. Se
eliminaron exclusivamente el container y volumen PostgreSQL E2E, destruyendo
los datos demo, y la copia Android E2E. Los contenedores ajenos siguieron
activos y el package normal permaneció instalado. Se restauraron datos móviles
**1**, Wi-Fi **0** y modo avión **0**, conforme al estado inicial.

Se retiraron suffix, etiqueta, APK, proxy, capturas y binario temporal del
túnel. Se restauró el artefacto incremental generado por el build Backend.
Ambos worktrees mostraron `git status --short`, `git diff` y `git diff --cached`
vacíos antes de crear la rama documental. No se publicó ningún cambio
funcional, de dependencias, schema, migraciones o workflow.

Entrega: rama `evidence/f03-mob-auth-02-e2e-activation`, PR documental **DRAFT**
con únicamente este informe. La CI normal de esa PR debe verificarse y
registrarse en su descripción antes del comentario de trazabilidad en #19.
#19 permanece **OPEN**, sin normalizar sus checkboxes, Project
**In Review / Partial / N/A**. #23 permanece **OPEN**, sin modificación:
#18 ✓, #19 ☐, #20 ✓, #21 ✓, #22 ✓, criterio final ☐.

`F03_MOB_AUTH_02_E2E_NOMINAL_PASS_READY_FOR_AUDIT`.
Próxima acción: `INDEPENDENT_AUDIT_F03_MOB_AUTH_02_E2E`.
