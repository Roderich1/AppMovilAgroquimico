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
