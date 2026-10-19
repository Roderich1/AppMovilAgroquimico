# F10 — Preflight E2E acotado de preparación DS-UX (POCO, sin red → sincronización → Central → Web)

- **Fecha real:** 2026-10-19 de 03:05Z a 03:31Z (UTC) = 2026-10-18 de 23:05 a 23:31 (America/La_Paz).
- **Ejecutó:** la sesión A de Claude Code, por la aprobación técnica delegada de Roderich Rendón del 2026-10-18 («Autorización del Project y preparación final de la usabilidad», §5: «E2E sobre main integrado: sí, una comprobación acotada como preparación de DS-UX»). Operación por `adb` y por la API real con cuentas sintéticas. **No es una sesión de usabilidad ni la sustituye; no hay participantes. Sin inspección personal de Roderich ni revisión del tutor.**
- **Qué cubre:** compra y aplicación sin red, necesidad declarada con outbox, sincronización explícita con ACK, registro central de esa intención y resumen colectivo de la misma campaña en la API y en la Web, con cantidades privadas, ausencia de duplicados y dato autorizado publicado. **No cierra BE #43** por sí solo (ver §7).
- **Escenario separado del de la evaluación humana:** este preflight usa el seed demo del Backend con una campaña «Verano Demo» y tres aportantes (60 L esperados); **no** es el tenant Web DS-UX (seis miembros, 150 L, cobertura 4 de 6) ni su oráculo.
- **Issues:** Roderich1/Agro_Sindicato_Backend-Web#43 (F10-QA-01), Roderich1/Agro_Sindicato_Backend-Web#47, #37 (F10-UX-01). GATE-F10 (Roderich1/Agro_Sindicato_Backend-Web#49) sigue **Pending**.

## 1. Resultado

| Paso | Resultado | Comprobación |
|---|---|---|
| Siembra DS-UX Móvil (generador de C) | **PASS** | `DSUX_RESULT`: campaña local «Verano Demo» 04/10–17/11/2026 dentro de la central (desde 18/09/2026), **tres vínculos `VALID`** (campaña, Glifosato Demo, Bellator), saldos **5 000 / 1 000 mL**, 2 compras iniciales del 08/10, outbox 0 → 0, `integrity_check` ok; huella de la base **igual en el PC y en el teléfono** |
| Compra sin red (2 L de Glifosato Demo a 50 Bs/L + 0,5 L de Bellator a 180 Bs/L) | **PASS** | Total leído antes de confirmar: «TOTAL COMPRA 2 productos · sin foto 190,00 Bs»; compras 2 → 3, líneas 2 → 4, movimientos 2 → 4; **outbox 0** |
| Aplicación sin red (Norte; 1 L de Glifosato Demo + 0,2 L de Bellator) | **PASS** | «Titular · Norte · Verano Demo · 2 producto(s) Glifosato Demo 1 L · Bellator 0,2 L»; aplicaciones 0 → 1, líneas 0 → 2, movimientos 4 → 6; **outbox 0**; saldos nominales 6 L y 1,3 L |
| Necesidad declarada sin red (20 L de Glifosato Demo) | **PASS** | «Glifosato Demo · Verano Demo 20 L · Pendiente»; necesidades 0 → 1, **outbox 1** (PENDING) |
| Red sin peticiones mientras estuvo cortada | **PASS** | **0 peticiones** en el observador entre 03:19:38Z y 03:27:51Z (`Active default network: none`; `f10_pre/requests_observador.txt`) |
| Sincronización explícita («Sincronizar ahora») | **PASS** | 1 `POST /auth/v2/refresh 200` + 1 `POST /sync/v1/push 200`; «Sincronizado: 1 · Último ACK: 18/10/2026»; fila «Necesidad declarada · Publicar · 20 L Sincronizado … ACK»; outbox **1/1 ACKED** |
| Registro central de esa intención | **PASS** | Journal de la cuenta del teléfono: **una** entrada `a20188df` PUBLISH, `FINAL APPLIED OK RETIRE_FROM_OUTBOX`, secuencia 1; contribución `DECLARED_NEED` «Verano Demo / Glifosato Demo» ACTIVE, 20 000 mL |
| Dos aportantes sintéticos adicionales (20 L cada uno, Sync v1 real) | **PASS** | Cuentas AGRICULTOR S y R del mismo tenant, con el recorrido de la app (login → registro de cliente → sesión de cliente → push → revocación de su propio registro → logout): `5bc69435` y `5001238f`, ambos `APPLIED` y `FINAL APPLIED OK` |
| Ausencia de duplicados | **PASS** | Central: **3** entradas de journal con **3** `operationId` distintos; contribuciones `ACTIVE DECLARED_NEED` = 3, suma **60 000 mL** |
| Cantidades privadas fuera del Central | **PASS** | El teléfono sólo envió `refresh` y `push`; **0** peticiones a rutas de compras, aplicaciones o inventario en todo el preflight (`f10_pre/requests_observador.txt`); en el Central, **0** filas de `PurchaseItem`, `AgrochemicalApplication`, `InventoryLot` y `DemandForecast` con «Glifosato Demo» o «Bellator», y 0 proveedores «Proveedor Demo» |
| Resumen colectivo por la API (ADMINISTRADOR con funciones de Directiva) | **PASS** | `DECLARED_NEED` Glifosato Demo **DISCLOSED**, `total_presentation` **60 L**, **3** aportantes; cobertura `linked_members` 12, `members_with_contribution` 3, sin celdas suprimidas; divulgación `PROVISIONAL_SYNTHETIC`, política F07-POL-01 **no aprobada**, k = 3 (`f10_pre/summary_api.json`, sin identificadores) |
| Resumen colectivo en la Web (Chrome 155.0.8059.82, 1366×768) | **PASS** | Celda «Glifosato Demo (L) Publicado 60 L 3»; cobertura «3 de 12 agricultores vinculados con cifras publicadas. Ausencia de aporte = desconocido, no cero.»; aviso «Modo provisional con datos sintéticos. Política F07-POL-01 no aprobada (umbral provisional k = 3). No usar para decisiones reales.»; igual a la API |
| Oráculo DS-UX Móvil sobre la base final (sólo lectura) | **PASS** | `DSUX_ORACLE`: Glifosato Demo 5 000 + 2 000 − 1 000 = **6 000 mL** y Bellator 1 000 + 500 − 200 = **1 300 mL**, `consistent: true` en ambos; necesidad ACTIVE 20 000 mL versión 1; outbox `ACKED: 1`; la huella de la base no cambió al ejecutar el oráculo |

## 2. Versiones y entorno

| Elemento | Valor |
|---|---|
| Mobile | `main` **`fd8dc7d94ceeae6f822b4a8baca1fe095e72d6b3`** (código `lib/` = `27c4654`) |
| APK | Copia aislada nueva **`com.comunidad.agro.agroquimicos.f10pre`** («Agrocuentas F10-PRE»), **profile**, compilada el 2026-10-19 03:12–03:14Z desde el worktree limpio de `fd8dc7d` con `tool/f10_eval/build_profile_apk.sh` y el origen del túnel; SHA-256 **`75d143443bb5c2aabca423f18c918fdd71efed551632a1b0d20609c49297f49e`**; `aapt2`: `minSdkVersion 24`, `targetSdkVersion 36`, depurable; firmada con la clave local (no distribuible). Instalada con `adb install -r` (Success); 17 paquetes `com.comunidad.agro.agroquimicos*` después: la app normal y las copias anteriores intactas |
| Generador DS-UX Móvil | PR MOB #133 (sesión C), **`f1fb755`** (el HEAD posterior `f6a7493` sólo cambia su README; mismo código) (`lib/`, `android/` y `pubspec.yaml` idénticos a `fd8dc7d`), ejecutado desde un worktree en ese SHA: `F10_UX_SESSION_DATE=2026-10-18`, `F10_UX_MODALIDAD=PROPIA`, `F10_UX_REFERENCES` = JSON literal de `GET /sync/v1/references` del tenant; semilla 20261018 |
| Backend | `main` **`df0df1d`** (código = `cab433d`); `dist` compilado sobre `6e4a0e2` (código idéntico); contenedor nuevo **`agro_a_f10pre_pg`** (postgres:16-alpine `sha256:4e6e670b…`), 11 migraciones, seed demo (12 agricultores, 14 productos), contraseñas rotadas; API 3136, observador 3137 |
| Configuración de la API | **`NODE_ENV=development` y `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic`** (la misma desviación declarada de §0.4 que R5/W1–W5: en producción el resumen colectivo no publica cifras), `SYNC_V1_PRODUCTION_ADMISSION=enabled` sólo en este entorno desechable; limitador sin cambios |
| Web | `Web/` de `df0df1d` (`Web/src` sin cambios desde `cab433d`), `vite build` + `vite preview` en el puerto 4180 con proxy a la API 3136; detenida al terminar |
| Red | Cloudflare quick tunnel (`cloudflared` 2026.10.0) hacia el observador (método, ruta enmascarada, estado y hora) |
| Auxiliares de este preflight (versionados aquí) | `tool/f10_pre/pre_sync_client.cjs` (cliente Sync v1 sintético por la API real; no inserta en la base ni firma tokens) y `tool/f10_pre/pre_web_summary.mjs` (lectura del resumen en la Web con `puppeteer-core` 25.12.0); Node v25.9.0 |
| Dispositivo | POCO X5 Pro 5G (`22101320G`), Android 12 / API 31, MIUI V14, 1080×2400, `font_scale` 1,0; cargando por AC, batería 100 %, 27,0–30,0 °C |

## 3. Preparación del Central (acciones de Directiva por la API, no SQL)

Con la cuenta sintética ADMINISTRADOR (funciones de Directiva), el 2026-10-19 a las 03:12Z: `POST /campaigns/{Campana Verano 2026}/close` 200 (la única ABIERTA del seed); `POST /campaigns` 201 «Verano Demo» con inicio 18/09/2026 y sin fin; `POST /campaigns/{Verano Demo}/open` 200; `POST /inventory/products` 201 «Glifosato Demo» (L) y 201 «Bellator» (L). Las referencias del tenant se leyeron con otra cuenta AGRICULTOR sintética (E2) por el recorrido completo de cliente, revocando su registro al terminar: «Verano Demo» ABIERTA con `accepts_contributions: true`; ambos productos activos, `base_unit` ML, `linkable`.

## 4. Pasos en el teléfono (UTC del 2026-10-19)

1. 03:14:49Z instalación; 03:15:51Z activación con la cuenta sintética D (`login 200`, `clients 201`, `session/client 201`, `me 200`), titular «Titular», **modalidad propia**.
2. 03:18:27–03:19:12Z siembra DS-UX sobre la base extraída (app detenida); devolución con `adb push` + `run-as cp`; huella `98200080…` igual en el PC y en el teléfono. Inicio con «Campaña activa: Verano Demo» y la fila de Bellator (1 L).
3. 03:19:38Z modo avión (`Active default network: none`).
4. 03:23:25Z compra confirmada tras leer el total (captura `pre_compra_total`); 03:25:51Z aplicación confirmada (`pre_aplicacion_lista`); 03:27:31Z necesidad declarada (`pre_necesidad_confirmar`).
5. 03:27:51Z red restaurada; 03:27:58Z «Sincronizar ahora» → ACK (`pre_sync_ack`).
6. 03:28:39–03:28:43Z aportantes sintéticos S y R; 03:29:01Z resumen por la API; 03:30:31Z resumen en la Web (`pre_web_resumen`).
7. 03:31:32Z ajustes restaurados; 03:31:48Z API, observador, túnel y contenedor detenidos (volumen conservado).

Capturas (no se publican: pantallas con datos sintéticos, como en las series anteriores), SHA-256: `pre_compra_total.png` `20fbe7893a226e41…f595`; `pre_aplicacion_lista.png` `9adfd5fd6ea3dddf…50fd`; `pre_necesidad_confirmar.png` `0dac21a5ee96a0ba…2f1f`; `pre_sync_ack.png` `16356fc519ca28a0…66a1`; `pre_web_resumen.png` `c99806618aafa777…5c63`; `pre_aplicacion_form.png` `ecd35b5f…0939`; `pre_compra_estado.png` `e6379543…0c29`.

## 5. Incidentes del arnés (declarados)

- **I-1. Arranque del entorno:** `up.sh` terminó en silencio después de crear el contenedor (sin migraciones ni seed; el filtro de salida ocultó el motivo) y la API quedó levantada contra una base vacía. Se detuvieron API, observador y túnel sin usarlos; como los secretos efímeros se pierden con la shell, se **reasignó la contraseña efímera** del contenedor recién creado y vacío (por `stdin`, sin borrar nada) y se repitieron a mano migraciones (11), seed y rotación. Ninguna operación del preflight usó el primer arranque.
- **I-2. Lectura de referencias:** el primer intento con la cuenta D por la API dio 403 `AUTH_CONTEXT_FORBIDDEN` porque Sync v1 exige una sesión ligada a un registro de cliente; el segundo, con otra variable de contraseña equivocada, dio `login 400`. Se resolvió con la cuenta E2 y el recorrido completo de cliente. Nada se escribió.
- **I-3. Formulario de compra:** un BACK enviado con el teclado ya cerrado abrió «¿Descartar cambios?»; se eligió «Seguir editando» (nada se descartó ni se escribió) y la compra se confirmó sólo tras leer el total.

## 6. Limitaciones

- **Una sola corrida, sólo modalidad propia**, en el POCO; la variante compartida del generador no se ejercitó en el teléfono (C la sembró en una base de prueba en el PC con el JSON de referencias del destino «movil» del generador de B, no en un teléfono).
- **El escenario de 60 L** usa el seed demo con 12 agricultores (cobertura 3 de 12); no reproduce el tenant Web DS-UX ni su oráculo de 150 L, que verificó la sesión B por separado.
- **Modo de divulgación provisional y sintético** con `NODE_ENV=development`; no habilita cifras reales (#107 y GATE-F07 pendientes).
- **Los aportantes adicionales** se crearon por la API real con cuentas sintéticas, no desde otros teléfonos.
- Datos sintéticos; APK profile; túnel público. Sin inspección personal de Roderich ni revisión del tutor.

## 7. Aporte a la matriz de BE #43 (F10-QA-01)

| Criterio de la cadena móvil → backend → web | Lo que aporta este preflight sobre `main` integrado (`fd8dc7d` / `df0df1d`) | Lo que no cubre |
|---|---|---|
| Operación privada sin red y persistencia local | Compra y aplicación sin red, con conteos y 0 peticiones | Otros tipos de operación (transferencias, pagos) |
| Intención publicable con outbox y sincronización explícita | Necesidad PENDING → ACK, journal único, sin duplicados | Reintentos, OUTCOME_UNKNOWN y conflictos (cubiertos por #18/#42 en sus SHA) |
| Privacidad en el Central | Ninguna cantidad privada en el Central | Auditoría completa de campos (BE #45) |
| Publicación agregada en API y Web | 60 L con 3 aportantes, cobertura y aviso de modo, iguales en API y Web | Reconciliación (W3) y propuesta (W4) en este escenario; respaldos (F08) |

La matriz de B (`_briefs/MATRIZ_F10_CONCILIACION_2026-10-18.md`) proponía para #43 Validation · Partial por composición de evidencias en SHA anteriores; este preflight añade una comprobación única sobre `main` integrado. El estado del issue lo decide Roderich.

## 8. Archivos

- `f10_pre/condiciones.txt`, `f10_pre/requests_observador.txt` (registro del observador; el nombre `requests.log` lo excluye el `.gitignore` del repositorio, por eso se publica con extensión `.txt` y el mismo contenido: método, ruta enmascarada, estado y hora; sin cuerpos ni cabeceras), `f10_pre/dsux_result.txt`, `f10_pre/dsux_oracle.txt`, `f10_pre/summary_api.json` (sin identificadores).
- Huellas SHA-256 (archivos con LF): `condiciones.txt` `6eaf03212627c36d01043f0ec2a6e1c4d4be18586c30b4445ca118fcc875b771`; `requests_observador.txt` `866d067f70f3687ea0cedfc3e6e9ee623234c3dd699a30851c8d14ab01c75245`; `dsux_result.txt` `dc8f65f4c21bcde2c6d6b936db1588aeb3146dfc836e8968b087811f19e3951a`; `dsux_oracle.txt` `ed04e6ac6cfaa77eb942c8c0f39034e6998b8f868160b85c7a5d6c65226d05a5`; `summary_api.json` `8b6cf9ee9931ddb54027486dffb810c2d1c5d6ffc78c02c2cf0a893af9514f33`; `tool/f10_pre/pre_sync_client.cjs` `f293ef51476909fdeae08c09eb3235a4d72d14e378468c87333c8036076a3dfd`; `tool/f10_pre/pre_web_summary.mjs` `0cc093c325ce7bab6b9716a7142593da9c3defe6e65cc3e63656bf2a76ad5e0a`.
- Conservado en local (no publicado): bases antes y después de la siembra y la base final, capturas, `references_pre.json` y logs de la API. En este preflight no se grabaron vídeos.
