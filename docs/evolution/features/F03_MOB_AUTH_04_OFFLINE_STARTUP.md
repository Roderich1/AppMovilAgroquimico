# F03-MOB-AUTH-04 — reapertura local de sesión y operación offline

Estado: implementación de #21, pendiente de auditoría independiente. Este documento no cierra GATE-F03.

## Problema y alcance

La primera activación (#19) puede comprometer una sesión cifrada mediante la implementación de #20, pero el arranque anterior no leía esa sesión. Una nueva ejecución perdía la clasificación local de vinculación. Este cambio la recupera sin consultar al Backend y sin cambiar SQLite. La existencia de una sesión cifrada **no demuestra** vigencia, autorización ni ausencia de revocación remota.

## Arquitectura

`main.dart` inicializa `AppLog`, crea **un único** `InstallationClientIdStore`, inicializa la identidad y pasa ese mismo objeto a `SecureSessionStore.android(...).read()`. La lectura se limita a tres segundos; un error o timeout se clasifica como `unavailable`. El resultado publicado en `existingSessionStartupProvider` es únicamente un enum, nunca un `StoredSession` ni identificadores. Después se inicia `AgroApp` sin bloquear el dominio SQLite.

`ExistingSessionStartup` es local y está separado de `FirstActivationController`. Si la identidad es corrupta o no está disponible, no intenta leer ni reinterpretar la sesión cifrada. Nunca borra la sesión, rota la identidad o lanza una operación HTTP. La UI muestra un mensaje seguro y sólo ofrece `/activar` cuando el resultado es `noLocalSession`; la ruta misma repite la restricción para impedir una activación accidental por navegación directa. El provider predeterminado es `unavailable` para fallar cerrado si faltara el wiring de producción.

| Lectura local | Estado observable | Primera activación | SQLite |
|---|---|---|---|
| `absent` | `noLocalSession` | Disponible, sin iniciarse automáticamente | Disponible |
| `available`, no expirada | `localSessionAvailable` | Bloqueada | Disponible |
| `available`, expirada | `localSessionExpired` | Bloqueada; sin refresh ni borrado | Disponible |
| `corrupt` | `corrupt` | Bloqueada; sin reparación automática | Disponible |
| `unavailable` o error/timeout | `unavailable` | Bloqueada; no se trata como ausencia | Disponible |
| `incompatible` | `incompatible` | Bloqueada; sin migración | Disponible |

El estado `checking` no es visible porque la lectura se resuelve antes de `runApp`. El timeout limita la espera del secure store, no depende de Internet. La identidad conserva el bootstrap existente de F02-B. El indicador de Dashboard representa sólo estado **local**, no acceso remoto.

## Frontera con #22

Este cambio no invoca `login`, `refresh`, `/me`, `registerClient`, `bindSessionClient` ni `logout` durante el arranque; tampoco valida revocación, solicita contraseña, elimina una sesión expirada o recupera una sesión corrupta. La verificación remota y la política de recuperación corresponden a #22. La primera activación nominal Mobile→Backend sigue siendo asunto abierto de #19. No se marca el criterio compuesto final de GATE-F03.

## Pruebas automatizadas

`existing_session_startup_test.dart` verifica todos los estados, fail-closed, timeout, ausencia de identificadores en el estado y uso del mismo store para identidad y lectura cifrada. `existing_session_screen_test.dart` comprueba Dashboard, escritura/lectura SQLite, ausencia de llamadas HTTP y protección de `/activar` para cada estado. Las pruebas existentes de primera activación se ajustan sólo para inyectar `noLocalSession`, conservando su contrato. Una prueba con cliente simulado demuestra que el flujo probado no pide HTTP; no reemplaza la observación DEVICE ni implica validación de Backend.

El 2026-10-01, `flutter test` terminó 626/626 (baseline 608), `flutter analyze` sin issues, formato sin cambios y `flutter build apk --release` compiló. Esta build de release no se presenta como binario firmado o distribuible. La CI del HEAD de la PR se informa por separado cuando exista.

## DEVICE — POCO X5 Pro 5G, Android 12 / API 31

Se instaló exclusivamente `com.comunidad.agro.agroquimicos.f03auth04test`, sin reemplazar `com.comunidad.agro.agroquimicos`. Un harness temporal no versionado usó `SecureSessionStore` real y valores sintéticos para preparar `available` y `expired`; luego se reinstaló el build normal de la copia aislada antes de cada reapertura. No se modificó SQLite al sembrar la sesión. Wi-Fi y datos móviles permanecieron deshabilitados durante A–D, y se restauraron después. El paquete aislado, incluida su persona local sintética, se desinstaló al finalizar; la app normal siguió instalada. El harness y el `applicationIdSuffix` se retiraron antes del commit.

| Caso | Resultado | Observación |
|---|---|---|
| DEVICE-21-A, sesión disponible offline | PASS | Tras force-stop y reapertura: `localSessionAvailable`, Dashboard y mensaje local visibles, sin botón de primera activación. Se creó y leyó una persona sintética mediante la UI/SQLite. |
| DEVICE-21-B, reboot offline | PASS | Wi-Fi y datos seguían desactivados tras reiniciar; `localSessionAvailable`, Dashboard y persona local persistieron. |
| DEVICE-21-C, expiración local | PASS | Tras sembrado sintético con vencimiento pasado y reapertura normal: `localSessionExpired`, Dashboard disponible, persona local legible y sin primera activación. Otra reapertura mantuvo `localSessionExpired`, sin borrado automático. |
| DEVICE-21-D, ausencia | PASS | En instalación aislada limpia: `noLocalSession`, Dashboard disponible y acción de primera activación visible; no se afirmó activación exitosa. |
| DEVICE-21-E, corrupto/incompatible real | NOT_MEASURED | No se manipuló ciphertext ni versión del almacenamiento físico; la política fail-closed tiene cobertura automatizada. |

`DEVICE_LOCAL_SESSION_SEEDED` demuestra únicamente el camino **local**. No es una activación E2E Mobile→Backend, ni prueba refresh/revocación. El comando de lanzamiento informó red no conectada; la ausencia de llamadas HTTP se sustenta también en la composición local y en los tests con transporte simulado. No se registraron tokens ni identificadores completos en los mensajes de arranque inspeccionados. El criterio final compuesto de GATE-F03 sigue pendiente de #19 y #22.
