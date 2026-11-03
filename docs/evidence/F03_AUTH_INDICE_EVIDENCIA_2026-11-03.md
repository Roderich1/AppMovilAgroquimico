# F03: índice de evidencia de MOB #18–#22 (autenticación)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-03 (UTC) |
| Qué es | Un **índice**: lleva a la evidencia que ya existe y añade las pruebas HOST del 2026-11-03 para #18. No vuelve a medir nada de lo citado ni cambia su procedencia, fecha o SHA |
| Por qué | Las evidencias de #18–#22 viven en `docs/evolution/features/F03_MOB_AUTH_0x_*`, no en `docs/evidence/`. Así lo señalan `GATE_F03_DECISION.md` y el inventario de OE3 del 2026-11-03 (Backend PR #200) |
| Base | Mobile `main` `5b5b318` |
| Lo que no es | No es una aceptación ni cambia `Evidence` o `Gate`. #23 (GATE-F03) conserva su decisión; los cambios de campo los decide Roderich Rendón |

Procedencias: **HOST** (pruebas en el PC), **CI** (GitHub Actions), **DEVICE** (teléfono físico). Los criterios de aceptación de #18–#22 son los genéricos de la plantilla: entregable integrado; casos nominales, límites y fallos cubiertos; documentación actualizada; y la «Verificación requerida» de cada issue. Por eso las filas de abajo siguen los casos que cada entrega definió.

## #18 AUTH-01: cliente HTTP y contrato de autenticación

| Criterio o caso | Evidencia | SHA | Procedencia | Estado |
|---|---|---|---|---|
| Entregable integrado | PR #62. HEAD `5716613`, merge `b472647`. Comentario de cierre del 2026-09-29 en #18 | `b472647` | CI: run 36516624600 sobre el HEAD | Hecho |
| Origen HTTPS, allowlist de rutas, sin redirecciones, serialización, 400/401/409/429/500 (sólo en login), red, timeout, JSON inválido, redacción, SQLite intacto | `test/auth_v2_api_test.dart`, 20 casos. Doc: `docs/evolution/features/F03_MOB_AUTH_01_HTTP_FOUNDATION.md` | 20/20 en la CI del merge; repetido el 2026-10-15 sobre `278cbd3` (`REC_MOBILE_BASELINE.md` §F03) | HOST + CI | Hecho |
| **403 → `forbidden` y 404 → `notFound`**, en las seis operaciones, sin cuerpo, URL ni credenciales | **Nuevo:** `test/oe3_auth_01_403_404_entorno_test.dart`, grupo «#18: 403 y 404» (12 casos) | Ejecutado sobre la rama `test/oe3-host-cierre` el 2026-11-03; el SHA exacto está en [OE3_HOST_CIERRE_2026-11-03.md](OE3_HOST_CIERRE_2026-11-03.md) | HOST | Hecho, con mutaciones |
| **`ApiEndpointConfig.fromEnvironment` (`AGRO_API_BASE_URL`)**: ausente, válida, inválida e imposible de analizar | **Nuevo:** el mismo archivo, grupo «#18: AGRO_API_BASE_URL». Sin `--dart-define` prueba la ausencia; las otras tres variantes se ejecutan con `--dart-define` | Ídem | HOST | Hecho, con mutaciones |
| Mapeo de 400/401/409/429/500 en las otras cinco operaciones | — | — | — | **Pendiente**: sólo login (hueco (c) de `REC_MOBILE_BASELINE.md`). 403 y 404 sí cubren las seis |
| Permiso `INTERNET` y build release | `aapt dump permissions` y `flutter build apk --release`, citados en la doc de AUTH-01 | — | Manual y CI | No hay prueba automatizada de la suite |
| E2E Mobile→Backend y DEVICE | Los cubren #19 (DEVICE-D) y #71, no #18 | — | — | `NOT_MEASURED` en #18 por diseño |
| Valor de `AGRO_API_BASE_URL` compilado en una APK concreta | — | — | — | **No se puede probar en HOST**: es una constante de compilación. La ausencia en DEVICE está en #19 DEVICE-B |

## #19 AUTH-02: primera activación en línea

| Criterio o caso | Evidencia | SHA | Procedencia | Estado |
|---|---|---|---|---|
| Implementación en `main` | PR #63/#64. Comentario del 2026-10-01 en #19 | `564e174`; CI 608/608 | CI | Hecho |
| Flujo y estados, con dobles | `first_activation_coordinator_test`, `first_activation_screen_test`. Doc: `F03_MOB_AUTH_02_FIRST_ACTIVATION_FOUNDATION.md` | `564e174` | HOST + CI. Son `MockClient`, no E2E | Hecho |
| DEVICE-A, pantalla; DEVICE-B, configuración ausente | `F03_MOB_AUTH_02_UI_WIRING_VALIDATION.md` (tablas de resultados) | `d824ee8`, POCO, 2026-09-30 | DEVICE | PASS |
| DEVICE-D, activación nominal real; DEVICE-E, force-stop posterior | Ídem, §«DEVICE-D» y §«DEVICE-E» | `18b9de3` con Backend `a098761`, POCO, 2026-10-04. Doc integrada en `278cbd3` (PR #68) | DEVICE | PASS |
| DEVICE-C, corte de red durante la activación | Ídem | — | — | **NOT_MEASURED** |
| DEVICE-F, reactivación en el mismo proceso | Ídem; hay una regresión de widget | — | HOST | **NOT_MEASURED** en DEVICE |

## #20 AUTH-03: almacenamiento seguro de la sesión

| Criterio o caso | Evidencia | SHA | Procedencia | Estado |
|---|---|---|---|---|
| Implementación en `main` | PR #64 (vía #63). Comentario del 2026-10-01 en #20 | `564e174` | CI | Hecho |
| Commit atómico A/B, puntero, corrupción, incompatibilidad, borrado, sin secretos en SQLite ni en el respaldo | `secure_session_store_test`. Doc: `F03_MOB_AUTH_03_SECURE_SESSION_STORAGE.md` | `564e174` | HOST + CI | Hecho |
| DEVICE-01 a 12 y 14 a 18 | `F03_MOB_AUTH_03_DEVICE_VALIDATION.md` | `d34a5e2`, POCO, 2026-09-30 | DEVICE. 06 y 07 se simularon con pausa más `force-stop` | PASS |
| Slot dañado en la app real | P13 de `F03_F04_DEVICE_2026-10-17.md` | `1902e6e`, POCO | DEVICE | PASS |
| DEVICE-13: Auto Backup y D2D reales | Sólo inspección estática de las reglas | — | — | **NOT_MEASURED** |
| Corte de energía físico | — | — | — | **NOT_MEASURED** |
| Concurrencia entre isolates | — | — | — | `NOT_CLAIMED` |

## #21 AUTH-04: apertura posterior sin Internet

| Criterio o caso | Evidencia | SHA | Procedencia | Estado |
|---|---|---|---|---|
| Implementación en `main` | PR #65. Comentario del 2026-10-01 en #21 | `6c8ab94`; CI 627/627 | CI | Hecho |
| Arranque sin red y operación SQLite independiente; cero HTTP | `existing_session_startup_test`, `existing_session_screen_test`. Doc: `F03_MOB_AUTH_04_OFFLINE_STARTUP.md` | `6c8ab94` | HOST + CI | Hecho |
| DEVICE-21-A a D: disponible, reinicio, expirada y ausente, sin red | Ídem, §DEVICE | HEAD inicial `8ca7ec5`, POCO, 2026-10-01. No se repitió sobre la corrección `def2d01` | DEVICE | PASS |
| 21-E: almacén corrupto o incompatible real | P13 de `F03_F04_DEVICE_2026-10-17.md` cubre un tipo de daño (slot cifrado sustituido) | `1902e6e` | DEVICE en parte | **Parcial**: no se probaron el almacén incompatible ni el keystore |

## #22 AUTH-05: refresh, revocación y reautenticación

| Criterio o caso | Evidencia | SHA | Procedencia | Estado |
|---|---|---|---|---|
| Implementación en `main` | PR #66. Comentario del 2026-10-01 en #22 | `8404b22`; CI 690/690 | CI | Hecho |
| Rotación, guard en cuarentena, reautenticación, sin reintentos ciegos | `remote_session_coordinator_test`, `refresh_guard_test`, `remote_session_screen_test`. Doc: `F03_MOB_AUTH_05_REFRESH_RECOVERY.md` | `8404b22` | HOST + CI | Hecho |
| DEVICE-22-A, B y C | Ídem, §DEVICE. Doc integrada por PR #67 | `8404b22`, POCO, 2026-10-02 | DEVICE | PASS |
| 22-D, refresh real; 22-E, 401 real | `docs/evidence/F03_RES_01_DEVICE.md` (#71): D, E-1 y E-2 | `94e7d24`, POCO, 2026-10-15 | DEVICE | PASS |
| E-2 con escaneo de logcat ampliado | Ídem, §«Repetición de E-2» | `5527784`, POCO, 2026-10-16 | DEVICE | PASS |
| E-1 con escaneo ampliado de valores opacos | Ídem, «Lo que esta repetición no cubre» | — | — | **NOT_MEASURED**: residual del logcat de E-1 |

## Pendiente común (no lo resuelve este índice)

- Revisión personal de Roderich Rendón y del tutor (GOV-01).
- Un solo modelo de teléfono (POCO X5 Pro 5G) en todo F03.
- Las decisiones del inventario de OE3, §7: aceptar o medir.
  - #19: C y F.
  - #20: Auto Backup, D2D y corte de energía.
  - #21: 21-E.
  - #71: E-1.
