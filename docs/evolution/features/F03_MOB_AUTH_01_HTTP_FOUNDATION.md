# F03-MOB-AUTH-01 — cliente HTTP y contrato de autenticación

**Estado:** implementación en PR para revisión independiente; [Mobile #18](https://github.com/Roderich1/AppMovilAgroquimico/issues/18). [GATE-F03 #23](https://github.com/Roderich1/AppMovilAgroquimico/issues/23) permanece pendiente.

## Autoridad y límites

- Mobile base: `main@9e9cb2334eeaa4c710dc87feb7cfa847ea339724`.
- Backend contractual: `main@a09876106dd696868217b301a9abf9125ac6d01d`, [`docs/api/openapi-f02.json`](https://github.com/Roderich1/Agro_Sindicato_Backend-Web/blob/a09876106dd696868217b301a9abf9125ac6d01d/docs/api/openapi-f02.json), controladores V2 y ClientRegistration de esa misma baseline.
- Mobile sigue siendo la autoridad del registro individual offline-first. La nueva capa no toca `AppDatabase`, `AgroRepository`, backup, navegación ni pantallas. Los roles de `persons` son contables, no identidad de Backend.

## Recorrido contractual previsto

| Orden | Operación Backend | Contrato | Estado de esta entrega |
|---|---|---|---|
| 1 | `POST /api/v1/auth/v2/login` | `{email,password,refreshTransport:"BODY"}` → 200, `contractVersion:2`, access JWT, refresh opaco y contexto | **IMPLEMENTED** método tipado, sin UI ni persistencia |
| 2 | `POST /api/v1/auth/clients` | Bearer access; `{clientId}` usa UUID v4 canónico de `InstallationClientIdStore` F02-B → 201 `registrationId` | **IMPLEMENTED** método; leer/validar identidad READY y orquestar activación queda en #19 |
| 3 | `POST /api/v1/auth/v2/session/client` | Bearer access; `{registrationId}` → 201 binding de Session | **IMPLEMENTED** método, no flujo de activación |
| 4 | `GET /api/v1/auth/v2/me` | Bearer access → 200 contexto Account/Member/Tenant/Session vigente | **IMPLEMENTED** método tipado |
| 5 | `POST /api/v1/auth/v2/refresh` | BODY `{refreshToken}` → 200, access y refresh rotado | **IMPLEMENTED** contrato stateless; refresh silencioso/rotación almacenada **DELEGATED #20/#22** |
| 6 | `POST /api/v1/auth/v2/logout` | BODY `{refreshToken}` → 204; sin credencial también 204 | **IMPLEMENTED** contrato stateless; revocación/reautenticación coordinada **DELEGATED #22** |

Ninguna operación conserva el access, refresh o password fuera de la memoria del caller; **no existe sesión duradera ni activación funcional en la app**. El transporte no tiene cookie jar y nunca envía COOKIE. Las rutas, métodos, estados y claves anteriores proceden del OpenAPI/controladores versionados; `409` en binding/registro, `400`, `401` y `429` se clasifican sin incluir cuerpo remoto en errores. No se implementa Sync F05.

## Arquitectura implementada

```text
future UI / activation (#19, #20–#22)
    → AuthV2Api (métodos tipados, sin estado)
    → AuthHttpClient (cliente inyectado, timeout, errores seguros)
    → package:http Client (real o MockClient)
```

`ApiEndpointConfig` recibe un origen HTTPS externo mediante `--dart-define=AGRO_API_BASE_URL=https://...` o inyección explícita en pruebas. No hay URL, credenciales ni certificados de entorno embebidos. Si falta o es inválida, la configuración falla al **construir el cliente remoto**, no durante el arranque local. No se permite HTTP en claro ni se añadió una excepción de seguridad de red. El manifiesto Android principal añade sólo `INTERNET`, necesario para release; debug/profile ya lo declaraban para Flutter. No se cambió otro componente nativo.

`AuthApiException` expone únicamente categoría y estado HTTP; descarta body, URL y excepción subyacente. Las clases con password/tokens tienen `toString` redactado. No hay logging de peticiones, respuestas, JWT, refresh ni UUID; no se añade almacenamiento de credenciales en SQLite, backup o archivos. `http: ^1.6.0` es la única dependencia directa nueva: cliente multiplataforma con inyección de `Client` y `MockClient`, sin generador de DTOs ni interceptor global.

## Delegación y verificaciones pendientes

- [#19](https://github.com/Roderich1/AppMovilAgroquimico/issues/19): pantalla/flujo de primera activación, vínculo de cuenta, verificación de UUID READY **antes de intentar red** y secuencia login → registro → binding → contexto; rechazo remoto no debe borrar datos locales. Una identidad CORRUPT/UNAVAILABLE no debe regenerarse silenciosamente ni bloquear la operación local.
- [#20](https://github.com/Roderich1/AppMovilAgroquimico/issues/20): almacenamiento seguro de refresh/session metadata y recuperación segura ante fallos. Esta entrega **no persiste tokens**.
- [#21](https://github.com/Roderich1/AppMovilAgroquimico/issues/21): apertura posterior y operación individual offline tras activación.
- [#22](https://github.com/Roderich1/AppMovilAgroquimico/issues/22): refresh silencioso, revocación y reautenticación; coordinar rotación atómica del token con #20.
- GATE-F03: DEVICE de activación y sesión offline, red intermitente, 401/429 reales, release con permiso INTERNET y TLS en teléfono físico **NOT_MEASURED**. No se presenta `MockClient` como E2E Mobile→Backend.
- La evidencia DEVICE F02-B se **reutiliza**: archivo en `noBackupFilesDir`, estabilidad/reinstalación verificadas en POCO API 31. ZIP interno `NOT_READABLE_VIA_ADB` y corrupción en dispositivo `NOT_MEASURED` siguen vigentes; no se repitió la prueba física.
- El timeout limita la espera del caller, pero no demuestra cancelación remota del login/refresh; #19/#22 deberán resolver la recuperación/reconsulta sin reintentos ciegos ni pérdida de datos locales.

## Evidencia de esta entrega

`test/auth_v2_api_test.dart` usa `MockClient` para serialización exacta, respuestas válidas, 400/401/409/429/500, fallo de conexión, timeout, JSON inválido o incompleto, redacción de secretos y persistencia de un dato SQLite local tras un error remoto. Son pruebas UNIT/contractuales con fixture, **no E2E**. La suite F02-B y backup se vuelven a ejecutar como regresión automatizada; no sustituye DEVICE.

Validación local de esta rama: `flutter pub get` PASS; `dart format --output=none --set-exit-if-changed lib test` PASS; `flutter analyze` PASS sin issues; suite focal auth **13/13**; `flutter test` completo **532/532**; regresión focal F02-B/backup **51/51**; `flutter build apk --release` PASS. `aapt dump permissions` sobre la APK release confirma `android.permission.INTERNET`. `git diff --check` debe permanecer limpio antes de publicar. La CI de la PR se registrará por separado: estos resultados locales no se presentan como CI ni como DEVICE.

No se afirma porcentaje de cobertura ni funcionamiento contra un Backend real en esta entrega.
