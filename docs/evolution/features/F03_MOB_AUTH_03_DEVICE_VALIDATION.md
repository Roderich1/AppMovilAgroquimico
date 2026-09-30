# F03-MOB-AUTH-03 — Validación DEVICE parcial de PR #64

Estado: `DEVICE_PARTIAL_NOT_MEASURED` — criterios físicos principales observados;
Android Auto Backup/restore permanece `NOT_MEASURED`. **No autoriza por sí solo
merge ni cierre del issue/gate**; requiere auditoría independiente.

Fecha: 2026-09-30 (America/La_Paz). Repositorio: `Roderich1/AppMovilAgroquimico`.
Código bajo prueba: `d34a5e266b1a1885041dc804c05a1f2e4b975894` (PR #64, draft,
apilada sobre #63 `ce9c310149cebc15aa0dc95f44c463626bf1adf7`; `main`
`b472647d457c4092399b226e6b9d4df0de8df664`). Durante la medición se usó un
harness temporal no versionado; no se alteró `SecureSessionStore`.

Dispositivo: Xiaomi POCO X5 Pro 5G (`22101320G`), Android 12/API 31,
`arm64-v8a`, ADB `cc14…47a` (identificador abreviado; sin IMEI/Android ID).
Se usó exclusivamente el paquete aislado
`com.comunidad.agro.agroquimicos.devicevalidation`, sin sobrescribir la instalación
normal. Todos los IDs y tokens fueron sintéticos. No se registraron valores completos.

APK debug inicial (DEVICE-01): 166211644 bytes,
SHA-256 `FF0F09E6964FCA484FD235545649E7DFF8E308B48B6B2D222F02699BB5F82B2B`.
APK debug con canal temporal para comandos ADB (DEVICE-02 a 18):
189630336 bytes,
SHA-256 `6D9C191E3A98DF7CAB3782F64E570CA2F53C7F499BCB282031896222CF7861A7`.
MIUI denegó la inyección táctil (`INJECT_EVENTS`); el canal temporal sólo existe en
la copia de validación y recibe intents explícitos en el paquete aislado. No forma
parte de la PR ni de la navegación productiva.

## Matriz

| Caso | Resultado | Evidencia observada y límite |
|---|---|---|
| DEVICE-01 | PASS | Paquete de prueba ausente antes de instalar; primer arranque: identidad creada, `read=absent`. |
| DEVICE-02 | PASS | `commitAndVerify` con candidato sintético; `read=available`, coincidencia de campos, puntero `a`; el token sólo se correlacionó por hash. No se inspeccionó aún SQLite ni logcat exhaustivamente en este punto. |
| DEVICE-03 | PASS | Tras `am force-stop` y nuevo proceso, `read=available`, perfil y hash del token idénticos. |
| DEVICE-04 | PASS | Tras reinicio real y `sys.boot_completed=1`, `read=available`; mismo hash de token y metadatos. |
| DEVICE-05 | PASS | Segundo commit: nuevo perfil activo y puntero `b`; hash distinto, sin mezcla de campos. |
| DEVICE-06 | PASS (simulado) | Pausa instrumentada después de escribir el slot inactivo; `force-stop`; al reabrir permaneció activa la sesión anterior con el mismo hash. **No** se simuló corte de energía. |
| DEVICE-07 | PASS (simulado) | Pausa después del commit nativo del puntero y antes del acuse; tras `force-stop`, la nueva sesión fue activa. Pérdida de acuse simulada devolvió `commitUncertain`, nunca éxito; lectura posterior mostró una sesión disponible. No se midió pérdida de energía. |
| DEVICE-08 | PASS (puntero) | En el paquete de prueba, el puntero persistido `b` se alteró a `x`: lectura `corrupt`, sin `StoredSession`. Se restauró `b` y volvió a leerse la sesión anterior. No se probaron otros tipos de corrupción. |
| DEVICE-09 | PASS | `delete` produjo `absent`; persistió tras `force-stop` y reinicio real. |
| DEVICE-10 | PASS | Marcador SQLite sintético permaneció tras commit, delete, `force-stop` y reinicio; búsqueda binaria del prefijo ficticio en `agroquimicos_v2.db` fue negativa. No se inspeccionaron todas las tablas mediante SQL. |
| DEVICE-11 | PASS | `.agrobackup` contenía sólo `manifest.json` y `database.db`; inspección de entradas descomprimidas: token ausente; sin artefactos de sesión/`client_id`. Restore mantuvo sesión, identidad y marcador SQLite. El archivo exportado se eliminó después del ensayo. |
| DEVICE-12 | PASS | Desinstalación del paquete aislado: éxito. Primer intento de reinstalación bloqueado por MIUI (`INSTALL_FAILED_USER_RESTRICTED`); tras nueva autorización USB, reinstalación exitosa. Nuevo arranque: identidad creada con hash distinto y `read=absent`. |
| DEVICE-13 | NOT_MEASURED | XML de exclusión de cloud/D2D revisado estáticamente; `bmgr` indica servicio habilitado, pero no se ejecutó backup/restore controlado. `AUTO_BACKUP_STATIC_CONFIGURATION = PASS`; restores Android y D2D no medidos. |
| DEVICE-14 | PASS | `LOGCAT_SECRET_SCAN = PASS`. Tras `logcat -c`, commit/read, error controlado `commitUncertain` y delete: barrido del PID de prueba sin prefijo del token, contraseña, Authorization, JWT, UUID, ruta privada ni valor de slot. Barrido global posterior sin prefijo de token/metadatos sintéticos. No se adjuntó log crudo ni se probaron credenciales reales. |
| DEVICE-15 | PASS — DEBUG-ACCESSIBLE SCOPE | `run-as` mostró cuatro XML de preferencias esperados y `client_id` bajo `no_backup`; búsqueda de prefijo de token/metadatos en `shared_prefs` y `no_backup` negativa. Slot cifrado presente; no se intentó extraer Keystore ni leer otros paquetes. |
| DEVICE-16 | PASS | Se alteró sólo el `version` del registro cifrado activo a `2`; lectura `incompatible`, también tras `force-stop`; puntero y slot permanecieron, sin borrado silencioso. |
| DEVICE-17 | PASS | Tras un commit válido, rotación controlada de identidad lógica: `read=corrupt`, confirmado en segunda lectura, sin credencial utilizable. No hubo rotación automática para forzar éxito. |
| DEVICE-18 | PASS (mismo isolate) | Dos commits próximos finalizaron serializados con el segundo candidato activo, campos coherentes y mismo hash tras `force-stop`. `MULTI_ISOLATE_CONCURRENCY=NOT_CLAIMED`. |

## Distinción de evidencia y durabilidad

- **DEMONSTRATED_ON_DEVICE:** instalación limpia, commit/read, persistencia
  normal tras `force-stop` y reboot, rotación de slot, corrupción controlada
  fail-closed, delete persistente, aislamiento de SQLite y `.agrobackup`,
  reinstalación sin sesión/identidad anteriores, barrido logcat, versión
  incompatible, identidad cruzada y serialización en un isolate.
- **SIMULATED_ON_DEVICE:** interrupción tras staging y pérdida de acuse
  alrededor del commit del puntero. Se ejecutaron en el hardware mediante
  pausas/control del harness, pero **no** equivalen a pérdida de energía.
- **NOT_MEASURED:** restore real de Android Auto Backup o D2D, pérdida de
  energía física, todas las variantes de corrupción y concurrencia
  multi-isolate/multi-engine. `MULTI_ISOLATE_CONCURRENCY = NOT_CLAIMED`.

`AUTO_BACKUP_STATIC_CONFIGURATION = PASS` por inspección de las reglas XML.
`AUTO_BACKUP_DEVICE_RESTORE = NOT_MEASURED`.
`D2D_DEVICE_RESTORE = NOT_MEASURED`.
Este riesgo residual no invalida por sí solo los resultados demostrados de
almacenamiento seguro, pero debe conservarse como `NOT_MEASURED` para futuras
revisiones y GATE-F03. Android Backup **no** está certificado físicamente.

La exclusión observada en `.agrobackup` (DEVICE-11) y la ausencia tras
reinstalación normal (DEVICE-12) no prueban un restore de cloud/D2D: son
mecanismos diferentes.

No se ha demostrado defecto funcional de PR #64. La restricción USB de MIUI
fue temporal y se resolvió. La clasificación sigue siendo parcial porque los
restores de Android Backup/D2D no se midieron, no porque se haya observado fallo.
El harness borró la sesión y luego se desinstaló el paquete de prueba; la
instalación normal de Agrocuentas permaneció intacta.

## Verificación automática post-DEVICE y gobierno

- `flutter pub get`: PASS.
- `dart format --output=none --set-exit-if-changed lib test`: 101 archivos,
  0 cambios, PASS.
- `flutter analyze`: PASS, sin hallazgos.
- `flutter test --reporter compact`: **581/581**, PASS.
- `flutter build apk --release`: PASS, APK sin firma, no instalado.
- `git diff --check`: PASS.
- En el momento de la medición, PR #63 y #64: OPEN/DRAFT, sin merge. CI remoto
  SUCCESS sobre el HEAD de código `d34a5e2`, previo a publicar esta evidencia.
  #19, #20 y #23: OPEN; gate sin modificar.
- Instrumentación temporal **no versionada**: sufijo de paquete debug, canal de
  intents en `MainActivity` y entrypoint del harness. Este documento es la
  única pieza destinada a publicación en PR #64.

## Reproducción y continuación segura

1. Confirmar de nuevo HEAD/estado de PR #64/#63 y `main`, además de ADB/ABI/API.
2. Para elevar DEVICE-13 a `PASS`, diseñar y ejecutar un backup/restore o D2D
   controlado del **paquete de prueba**, sin cambiar de forma persistente la
   configuración global de backup ni afectar otros paquetes. No equiparar XML
   con un restore medido.
3. La auditoría independiente debe revisar esta evidencia y decidir si la
   limitación de DEVICE-13 es aceptable para PR #64. No inferir autorización
   productiva de una decisión académica.

No se fusionaron PRs, no se cerraron issues ni se cambió GATE-F03.
