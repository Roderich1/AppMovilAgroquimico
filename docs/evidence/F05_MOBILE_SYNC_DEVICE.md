# Evidencia F05 Mobile en dispositivo — E2E de D3 contra Central real

Issues: [#29](https://github.com/Roderich1/AppMovilAgroquimico/issues/29), [#30](https://github.com/Roderich1/AppMovilAgroquimico/issues/30), [#31](https://github.com/Roderich1/AppMovilAgroquimico/issues/31), [#72](https://github.com/Roderich1/AppMovilAgroquimico/issues/72) y [#34](https://github.com/Roderich1/AppMovilAgroquimico/issues/34) (parte local). Complementa [F05_MOBILE_SYNC](F05_MOBILE_SYNC.md), que reúne las pruebas de host y el recorrido simulado.

Sesión física ejecutada con Claude Code el **2026-10-15 entre las 21:07 y las 22:25 (America/La_Paz, UTC−4)**, autorizada por Roderich con una app aislada y datos sintéticos. En la misma sesión se ejecutó #71 (`docs/evidence/F03_RES_01_DEVICE.md`, rama `test/f03-res-01-env`). **No es un PASS de GATE-F05 (BE #19)**, que sigue Pending hasta la revisión de Roderich.

## 1. Identidad

| Elemento | Valor |
| --- | --- |
| Dispositivo | POCO X5 Pro 5G, modelo `22101320G` (redwood), Android 12, API 31, MIUI `V14.0.7.0.SMSMIXM`, zona horaria America/La_Paz. No se publica el serial ADB |
| App | Copia aislada `com.comunidad.agro.agroquimicos.f03res01`, etiqueta «Agrocuentas F03-RES-01», build debug. La app normal `com.comunidad.agro.agroquimicos` (instalada el 2026-09-24) no se abrió, actualizó ni desinstaló; sus fechas siguen iguales |
| Mobile | Worktree desacoplado y limpio en cada build: `94e7d240c61684dd1535de2f36b79ea0296d3cfc` (HEAD de PR #80 al empezar), `023a47b3edb11a7f3e7e1e110c13eeef6f00ad6b` y `5027a354fe0133bc49df398a58aaf4cb46a91a3b`. Las dos últimas corrigen los defectos de §4. Cada resultado indica su versión |
| APK (SHA-256) | `94e7d24`: `8fcff313934a1eb6eaad55883ee93e2a9a35254a0c60def7f81518c81c9e090e`; `023a47b`: `ebb970cdb043bdf21700300cf7f400743910af3a7dc559f672e8a1d25716aeb8`; `5027a35`: `873d960dab01781e0da026f25412bbc7515f9c554f77ea7baec697395ca92d4e`. Antes de instalar se comprobó con `aapt dump badging` el paquete, la etiqueta y `debuggable`, y que llevaba el origen del día |
| Cambios temporales de empaquetado | `applicationIdSuffix ".f03res01"` en el build debug, `android:label` y `--dart-define=AGRO_API_BASE_URL=<origen>`. Los aplica y revierte `build_isolated_apk.sh`; no se commitean. Sin instrumentación de código |
| Backend | PR BE #109 sin fusionar, `c2acbd4cc6b51befec92dc6f5f9ad9ed059d8357` (worktree desacoplado), `NODE_ENV=production`, TTL por defecto |
| Configuración temporal del Backend | Clave de huella aleatoria (sólo en el proceso de la API) y `SYNC_V1_PRODUCTION_ADMISSION=enabled`, **sólo** en este entorno desechable. En producción la admisión sigue cerrada hasta F10 (#45) |
| Base | Contenedor efímero `agro_f03res01_pg` (`postgres:16-alpine`, `127.0.0.1:55432`). Las 6 migraciones se aplicaron con `prisma migrate deploy`, entre ellas `20261007202233_f05_sync_v1_journal_expand` y `20261015220130_f05_sync_v1_contribution`. Seed sintético, con las contraseñas de los 15 usuarios rotadas |
| HTTPS | Cloudflare quick tunnel (`cloudflared` 2026.10.0, SHA-256 `86aee401…b23c`, igual al release). Origen `HTTPS_EPHEMERAL_ORIGIN_REDACTED`. Se cerró a las 22:24:45 |
| Cuenta | `pedro.mamani@agro.local` (AGRICULTOR del seed). Contraseña de un solo uso por activación (`credential.sh`): nunca se imprimió ni se escribió |
| Central | «Campana Verano 2026» (ABIERTA) y «Glifosato 48 SL» (L) |
| Locales | Campaña «Campania E2E D3» (sin «ñ»: `adb input text` no la teclea), creada en la app con inicio hoy y sin fin. Producto «Glifosato E2E» (L) |
| Arnés | `tool/f03_res_01/` de la rama `test/f03-res-01-env` (observador, fallos controlados, `device.sh`, `check.sh sync`) |

## 2. Método

- **Peticiones.** Un observador local entre el túnel y la API registra sólo hora, método, ruta (UUID enmascarados) y estado. Fallos controlados, de un solo uso, para la siguiente petición de push:
  - `drop-push-response`: se reenvía a Central y se lee su respuesta completa (commit confirmado), pero no se entrega; el teléfono agota su timeout de 10 s.
  - `hold-push-request`: no se reenvía; Central nunca la recibe.
- **Central.** Consultas de sólo lectura a `SyncV1OperationJournal` y `SyncV1Contribution`. Las operaciones se identifican por sus 8 primeros hex.
- **Teléfono.** Copia temporal de SQLite con `run-as` (build debug) y consultas de sólo lectura sobre `sync_outbox`, `declared_needs`, `declared_need_versions` y los vínculos; la copia se borra después. La UI se lee con `uiautomator`.
- **Radios.** Modo avión por `cmd connectivity airplane-mode`.
- **Contenido, no sólo filas.** En cada paso se comparan operación, acción, antecesor, cantidad, head, estado y efecto entre el teléfono y Central.

## 3. Resultados

### 3.1 Primer intento sobre `94e7d24` (21:36–21:41)

| Paso | Observado | Resultado |
| --- | --- | --- |
| Vincular campaña y producto | `GET /sync/v1/references` 200. Leer no vincula nada: no hay filas. La campaña planificada y la cerrada aparecen como «No admite nuevos aportes»; los productos en kg, como «Unidad distinta: no se convierte». Hay confirmación explícita y los vínculos quedan VALID con refs `f969cefd` y `556aa10f` (L→ML), iguales a los IDs centrales | PASS |
| Declarar sin red | «Ninguna campaña cubre esa fecha» para el 15/10/2026 | **FAIL → defecto D3-DATE (§4)**. Se canceló sin escribir: 0 necesidades, 0 intenciones, 0 peticiones |

### 3.2 D3 completo sobre `023a47b` (21:50–22:06)

Instalación nueva, activación de la cuenta, titular «Titular S D3» (huella de Member igual a la de Central), campaña y producto locales. Después, verificación de acceso: un refresh 200.

| Paso de D3 | Esperado | Observado | Resultado |
| --- | --- | --- | --- |
| 1. Vincular explícitamente | Elección y confirmación; nunca por nombre | Igual que en 3.1, con capturas D3b-01 a D3b-05 | PASS |
| 2. Sin red, declarar | Necesidad con historial e intención pendiente | La campaña se resuelve («Campaña: Campania E2E D3»). Hay confirmación «Declarar al sindicato: 12,5 L de Glifosato E2E para Campania E2E D3.» y no se escribe nada antes de confirmar. Queda la necesidad 1 ACTIVE con 12500 en la versión 1, la versión 1.1 con `op 4f3ad1e2` y la intención PUBLISH sin antecesor por 12500 ML. Pantalla: «Pendiente (sin confirmar)». 0 peticiones; Central sin datos | PASS. La intención quedó en `OUTCOME_UNKNOWN` con 2 intentos `NETWORK`, no en PENDING con 0: el acceso verificado seguía en memoria y el worker intentó sin red (contrato C03) |
| 3. Recuperar red: ACK y Central | ACK válido y contribución | La red volvió a las 21:57:29 y el ciclo automático envió a las 21:57:59. Intención ACKED con `serverAcceptedAt` 01:57:59.187Z. Central: journal `4f3ad1e2` PUBLISH FINAL APPLIED/OK, secuencia 1; contribución DECLARED_NEED «Campana Verano 2026 / Glifosato 48 SL» ACTIVE, head `4f3ad1e2`, 12500 ML | PASS. La lista siguió «Pendiente» hasta volver a entrar: **defecto D3-LIST (§4)** |
| 4. Respuesta perdida tras un commit confirmado | Central confirma; el teléfono no recibe el ACK | Cambio a 20 L («Sustituye el total anterior; no se suma») con `drop-push-response`. A las 22:01:14 la petición llegó y Central respondió 200, pero la respuesta se retuvo. Central: `75f4cb2b` SUPERSEDE, antecesor `4f3ad1e2`, APPLIED, secuencia 2; head con 20000. Teléfono: `75f4cb2b` en OUTCOME_UNKNOWN, 1 intento, `TIMEOUT` | PASS |
| 5. Reenviar la misma intención | Mismo ID, un solo efecto | A las 22:01:58 el ciclo automático reenvió. La API registró `outcome=ALREADY_APPLIED code=OK` (SUPERSEDE). Teléfono: ACKED, 2 intentos, `serverAcceptedAt` 02:01:14.271Z (la del commit original). Central: **1** fila de journal para el ID, 2 en total, una contribución, secuencia 2 y 20000 ML, sin sumar | PASS |
| 6. Cierre forzado durante un envío | La cola persiste; se verifica el acceso de nuevo | Cambio a 25 L con `hold-push-request`. La petición quedó retenida a las 22:03:27.263 y el force-stop fue a las 22:03:27.911 (0 procesos). Con la app muerta, SQLite tenía `868593c0` SUPERSEDE (antecesor `75f4cb2b`, 25000) en SENDING con 1 intento. Central no la tenía. Al reabrir: OUTCOME_UNKNOWN y 0 peticiones, porque no había acceso en memoria. La verificación explícita hizo un refresh 200, sin `COMPROMISED`: el refresh rotado a las 22:00:05 sobrevivió al force-stop. Con «Sincronizar ahora» llegó a Central por primera vez: APPLIED, secuencia 3, head 25000; teléfono ACKED con 2 intentos | PASS |
| 7. Modificar y retirar | SUPERSEDE y CANCEL con antecesores, historial, cantidades y estado central | 30 L: `f60cdc0b` SUPERSEDE (antecesor `868593c0`), ACKED al primer intento, secuencia 4. Anular: `be54b90d` CANCEL (antecesor `f60cdc0b`/VALUE, sin cantidad), ACKED, secuencia 5. Central: contribución CANCELLED, head `be54b90d`, sin cantidad. Teléfono: necesidad CANCELLED en la versión 5; historial 12,5 / 20 / 25 / 30 L / Anulada, con la operación de cada versión | PASS |

### 3.3 Repetición de los casos afectados sobre `5027a35` (22:16–22:22)

Se actualizó la copia aislada con `adb install -r`, conservando sus datos (1 necesidad, 5 versiones, 5 intenciones y la misma identidad de instalación).

| Caso | Observado | Resultado |
| --- | --- | --- |
| R1. Sin red, declarar tras un CANCEL | 10 L: versión 1.6 con `op 964419b0`. PUBLISH con antecesor `be54b90d`/CANCEL, en PENDING con **0 intentos**: tras reiniciar el proceso no había acceso en memoria. Pantalla «10 L · Pendiente»; 0 peticiones. Luego Central: APPLIED, secuencia 6 | PASS |
| R2. ACK de un ciclo de fondo, sin salir de la lista | Sin red, cambio a 12 L: `714ed3fa` en OUTCOME_UNKNOWN/NETWORK, pantalla «Pendiente (sin confirmar)». La red volvió a las 22:20:50 y, sin tocar la pantalla, el ciclo de fondo envió a las 22:21:26. La lista pasó sola a «12 L · Sincronizado». Central: SUPERSEDE con antecesor `964419b0`, secuencia 7 | PASS (corrige D3-LIST) |
| R3. Anular | `92a962a6` CANCEL (antecesor `714ed3fa`), ACKED; «Anulada · Sincronizado». Central CANCELLED, secuencia 8 | PASS |

**Conciliación final.** El teléfono tiene 8 intenciones ACKED y Central las mismas 8 operaciones, con los mismos antecesores, en 8 filas de journal (8 IDs distintos) y una sola contribución, CANCELLED. Hubo 9 pushes procesados por Central: los 8 primeros envíos más el reenvío de `75f4cb2b`. La necesidad está CANCELLED en la versión 8, con 8 versiones inmutables.

**Registros.** Logcat del UID de la copia (1064 líneas): JWT 0, UUID completos 0, nombres de campos sensibles 0, FATAL 0. El registro propio de la app (`app_flutter/agrocuentas.log`) tampoco tiene ninguno.

## 4. Defectos y hallazgos

| ID | Dónde | Reproducción | Estado |
| --- | --- | --- | --- |
| D3-DATE | `DeclaredNeedStore.campaignForDate` (#80) | Una campaña creada a las 21:38 en La Paz se guardó como `2026-10-16T01:38:55Z`, y la consulta comparaba el día UTC con el día local. Entre las 20:00 y las 24:00 una campaña nueva no cubría su propio día. La limitación anterior, «es correcto en Bolivia», era falsa | Corregido en `023a47b`: la comparación usa el día local. Test de regresión; con la consulta anterior falla en America/La_Paz («día 15»). En UTC no puede discriminar. Repetido en el dispositivo (3.2) |
| D3-LIST | `DeclaredNeedsScreen` (#80) | Un ACK por el temporizador o al reconectar no refrescaba la lista hasta volver a entrar | Corregido en `5027a35`: la lista se relee cuando el controlador publica el resumen de cada ciclo. Test que falla con la pantalla anterior. Repetido en el dispositivo (R2) |
| UTC-DISPLAY | `formatDate` (`lib/domain/money.dart`), **anterior a #80** | «Último ACK: 16/10/2026» y «Versión N · 16/10/2026» para acciones del 15/10 por la noche. `formatDate` formatea sin pasar a hora local. También afecta a Reportes (CSV/PDF), la bitácora, las liquidaciones y las transferencias | **Sin corregir aquí**: es un ayudante compartido fuera del alcance de F05. Issue [#82](https://github.com/Roderich1/AppMovilAgroquimico/issues/82) |

## 5. Matriz C01–C40 (columna Mobile)

Sólo se marcan las filas medidas en este dispositivo contra el Backend real (BE `docs/evidence/F05_SYNC_06.md` §4):
- **C01** (PUBLISH nominal): PASS.
- **C02 y C04** (ACK perdido o conexión caída tras un commit durable; reenvío ALREADY_APPLIED): PASS.
- **C03** (petición que no llegó a Central; reenvío idéntico): PASS.

Las otras 36 filas siguen **NOT_MEASURED** en dispositivo, entre ellas 401/403 en push (C22–C24), forks y resolución del propietario (C11, C13–C15), ACK inválido (C30), restore (C35) y relogin (C38). Las pruebas de host y el recorrido simulado no cuentan como dispositivo.

## 6. Fuera de esta sesión

- **`CONSUMPTION_TOTAL`.** No se produce (D4, MOB #32/#33); nada de esta sesión se atribuye a consumo total.
- **Forks entre teléfonos** y la decisión del propietario: sólo simulados en host.
- **Backoff medido:** los reintentos se observaron, pero no se midió la distribución del jitter.

## 7. Capturas y registros

Capturas sanitizadas (sin barra de estado, sólo contenido sintético) y registros sin valores sensibles, conservados localmente fuera de los worktrees en `ProyectoAgro/_evidencias_locales/2026-10-15_E2E_F03RES01_D3/` (`SHA256SUMS.txt`). No forman parte de este PR. SHA-256:

| Archivo | SHA-256 |
| --- | --- |
| D3-01-vinculos-sin-vincular.png | `cb6cc06c3c928f0a0e6c68caed2718721b225bff2f3fd1b9a605f2969e6183ad` |
| D3-02-opciones-campania.png | `14bfb21b0e93b78af3071aa7b13f174082b334e1d98ac34aa40c9359542650c8` |
| D3-03-confirmar-vinculo-campania.png | `00eb106350592b29e67f2c59bd510f85ede321885d9559772bf751624b93f0bc` |
| D3-04-opciones-producto.png | `226076ac0414be12dc7288ad4b42dc1c86926693dc00fb8c89b2303c7bfe98ac` |
| D3-05-vinculos-vigentes.png | `7556d82ad87e4153990d786ae6e3849f40ef9886c8671fba5a4921051023f319` |
| D3-06-defecto-fecha-campania-utc.png | `4475f1b2db303ae3125036ff49ef02c004c2c07615dbd7b89e181de8da2a8bc0` |
| D3b-01-vinculos-sin-vincular.png | `f22823e398ae4f686664d56c8625481b3c5d184e885a2235e1e269fde1957ef4` |
| D3b-02-opciones-campania.png | `c476c88df98c6a9d2ec4d1417a441deb074070425a49f9de76afd267bb305833` |
| D3b-03-confirmar-campania.png | `5313cd148d601f925166ac134c57ef582b7d34a0a8a392457b0f8257fca17cec` |
| D3b-04-opciones-producto.png | `41ba43ee381dc3f95daf8b20a222a3a243539264af05fe2cbc49dc7a8e17de6a` |
| D3b-05-vinculos-vigentes.png | `53dc08dcd4b2ac23ce6f89e0f8189e18c9d2fc45a6d5e0dd11988b6d397a6719` |
| D3b-06-formulario-campania-resuelta.png | `21de815986d2dd9e397e78eb07a8517bc9cdca1cbd6ea1f3a9e10ace98a7c477` |
| D3b-07-confirmar-declaracion.png | `172da115677ba71e70b94fbe15db932d7c138ecae7e9074a674b0c427d53c84e` |
| D3b-08-declarada-sin-red.png | `b16e4c99cbb7f9dad34034f5c2febec5cff3ddf504139100e56f6dc4e0b2c49b` |
| D3b-09-ack-tras-reconectar.png | `657802fed9a86f20751b50c3cc03d55982ba878ce7d24ef16a7a4130abc6e576` |
| D3b-10-sincronizacion-tras-ack.png | `302b7ef120a610945fa62b599695bf25ab13579b1ca815d16d0db93475b74ecb` |
| D3b-11-necesidad-tras-reentrar.png | `0287b75f1c073c7eeb614b16bd71264243d0d0997a4306e433761608e8b22be4` |
| D3b-12-confirmar-cambio-20.png | `e034d914832fd0a927bba010d4de2329544fb9daa3b88cc2313d1c0390e275fc` |
| D3b-13-ack-perdido.png | `43d6d8cfd6155125c9ef6d0c5a9edf5c57b5f4f7c4eb1791ac853d705546b43d` |
| D3b-14-reenvio-ack.png | `76c87c1cc2b27c123e4b1750fdb92300c8edd603dc543d76a002385654200357` |
| D3b-15-reapertura-tras-cierre.png | `13697c67205054434943a2f0a83461593f5271e83156b4213b42a18e7b909c90` |
| D3b-16-reenvio-tras-reapertura.png | `abced6407d97307595aa79b09cb97872f474a819c4f1160de2fc2b7f16046bcb` |
| D3b-17-confirmar-anular.png | `fd294f4da45a7c52ab19d5c071f814c754b192aad784346f0bfbc02399912b1f` |
| D3b-18-historial.png | `3847d904812daf3a6de5b42823e3091e48bcd1276e496e0d30aea0e5f07ff545` |
| D3b-19-anulada.png | `ed8a8a1884d8d9378588d9bacff66f4198750aecda2e70cdd6476c7c304bae7b` |
| R-01-declarada-sin-red.png | `534e29970c44f89a0f1779e9ac7ec45df271ce2694aac3479dcc967f04207cba` |
| R-02-ack-de-fondo-en-la-lista.png | `bcc8fe54e59a9c81dbded96b84d2c41eb75a204d4bf49c02ee2f03d49235d398` |
| R-03-cambio-sin-red.png | `28498ba044fe181994ce3d8a445bba9c7afd6e08afc71cc758ee9700b8808000` |
| R-04-ack-de-fondo-sin-salir.png | `d2080ba68f2f9c24fdd4bde3060876ca31f65775104c8049a35ec29ddba399ca` |
| R-05-anulada.png | `6ae48485d5b101bf65754ce705f1293dc6e8a79eb953eae5464d7c08b1a697fc` |
| observador-peticiones.log (hora, método, ruta enmascarada, estado) | `10067db607ebde12062ee82a4e30515c1a3a6cc03113d59782b28d5654137e5a` |
| api-resumen-sanitizado.log (líneas `SyncV1Push`, UUID enmascarados) | `793d6a9cd27e5190a5d964fad7c17b36d0269d51cea72f26ad663a012bd3dd86` |

## 8. Revisiones

- Ejecución: Claude Code, 2026-10-15 (arriba). Sin revisión humana todavía.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte, por entregable o gate, en GOV-01.
- GATE-F05 (BE #19): **Pending**. Esta evidencia no lo cierra.
