# F09 — Ensayo físico de voz (F09-ENS-01): preparación completa, casos sin habla ejecutados, reconocimiento `NOT_MEASURED`

- **Origen:** Live. **Fecha real:** 2026-10-17 (noche, America/La_Paz; en UTC, 2026-10-18 entre las 00:20 y las 02:10). Sesión A de Claude Code, por la delegación técnica de Roderich Rendón (instrucción del 2026-10-17, «Continúa la preparación y ejecución del ensayo F04-C2/F09», puntos 1–12).
- **Protocolo:** [F09_VOZ_ENSAYO_FISICO_PLAN.md](../evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md) (SHA-256 `bfbc8ee0db05989aa42ee4d77b972372181bab0ef26b0a8cfae51cad29257f75` en el `main` del ensayo), sin cambios. Preparación: [F09_VOZ_ENSAYO_PREPARACION.md](../evolution/features/F09_VOZ_ENSAYO_PREPARACION.md) (MOB #114; actualización en MOB #117). Cambio de dispositivo: [F09_NOTA_CAMBIO_DISPOSITIVO_2026-10-17.md](F09_NOTA_CAMBIO_DISPOSITIVO_2026-10-17.md).
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07, DAT-17; MOB #12 y #17. Refs #17 (GATE-F09 sigue **Pending**).
- **Resultado en una línea:** la base, la APK, el entorno y los datos sintéticos quedaron fijados y se ejecutaron **todos los controles que no necesitan habla** (E1–E4, G1–G3 y las partes manuales de V1, V8, V9, V12–V19). **No hubo persona que dictara ni conjunto nuevo**: el reconocimiento real, V2–V7, V10, V11 y el conjunto C1–C7 / P1–P6 / A1–A7 / S1–S2 quedan **`NOT_MEASURED`**. No se usó TTS, texto inyectado ni el fake como reconocimiento. No se grabó audio ni se copió ninguna frase.

## 1. Lo fijado antes de medir (`fijado_parcial.json`, fuera del repositorio)

| Huella | Valor |
|---|---|
| Dispositivo | **HONOR JDY-LX3P**, Android 16 / API 36, `user`, arm64-v8a, zona America/La_Paz, idioma del sistema `es-BO`, reconocedor por defecto Speech Services by Google (`com.google.android.tts`). Código **F09-ENS-01**. El POCO no se usó; por D-F09-6 este ensayo acredita sólo este modelo |
| `mobile_sha` | `65f7cfc70d2dafc1c32da9a803fc55111c7a4c6e` (= `main`, merge de MOB #116; CI 39081132396 SUCCESS: 1498 pasan, 4 omitidas, 44 de fechas, build de release) |
| `interpreter_tree` (`lib/voice_draft`, 14 archivos) | `21c6704c4fd60bd3d07a7688a2fcc86f16bd25ca` |
| `protocol_sha256` | `bfbc8ee0db05989aa42ee4d77b972372181bab0ef26b0a8cfae51cad29257f75` |
| Nota de dispositivo | commit `ae0148871d2ff80c2bb38dd49d72a8716429009b`, SHA-256 `fe4d7265e81751a3f43ef7cf462d72ed7f1f7a9c437a4ea3dff65a2762cf5ed3` |
| APK | `com.comunidad.agro.agroquimicos.f09voz` («Agrocuentas F09 voz»), **debug**, `versionCode 1`, SHA-256 `fe6878741e5321855c0a8eb397918bac408ce3e0165733d023309eef2db7ffb0`; compilada con `tool/f03_res_01/build_isolated_apk.sh` desde un worktree limpio en `65f7cfc`; `applicationId` comprobado con `aapt dump badging` **antes** de instalar; instalada con `adb -s <serial> install` como copia nueva (en este teléfono sólo existían la app normal y dos paquetes del banco de voz, que no se tocaron) |
| Backend | `6e4a0e2ce8fb33ac3d6bf70e88cb6e60641456f0` (= `main` BE), 11 migraciones, seed sintético con contraseñas rotadas; contenedor `agro_a_f09dev_pg` y volumen propios; API, observador y túnel HTTPS temporal (origen no publicado) |
| `set_sha256` | **no fijado**: no hubo conjunto nuevo (ver §4) |

Opciones del teléfono registradas al inicio y comprobadas al final: `stay_on_while_plugged_in = 0`, `screen_off_timeout = 2147483647`, `font_scale = 1.45`, `airplane_mode_on = 0`, `wifi_on = 1`. Durante G3 se usaron modo avión y Wi‑Fi apagada; ambos volvieron a su valor inicial. La copia aislada queda instalada con sus datos y con el permiso de micrófono concedido (§3, V1).

## 2. Datos sintéticos

Como en la preparación §3, adaptados a que los formularios no admiten fecha (ver [F04_FECHA_EFECTIVA_DEVICE.md](F04_FECHA_EFECTIVA_DEVICE.md) §1): catálogo del protocolo («Bellator», «Belator», «Glifosato» L, «Expansive» KG; «Agro Norte»; chacos «Sur» y «Norte»); «Campaña ensayo 1» (17/09/2026–16/10/2026, cerrada) con un plan pendiente en «Sur»; «Campaña ensayo 2» (desde el 17/10/2026, activa durante los casos V) con compras de Glifosato (10 L y 2 L) y de Bellator (5 L), dos planes pendientes en «Sur», dos en «Norte» y uno de ellos aplicado a mano. Conteos al empezar los casos V: compras 1, aplicaciones 1, movimientos 2, outbox 2 (2 ACK), necesidades 1.

## 3. Escenarios de la app (V1–V19)

«Parte manual» = lo que el escenario tiene de permisos, navegación, selección, confirmación o salida, ejecutado sin dictado. **Ningún PASS de esta tabla es un PASS de reconocimiento.** Lo que requería habla queda `NOT_MEASURED`.

| ID | Parte ejecutada | Qué se observó | Conteos | Resultado |
|---|---|---|---|---|
| V1 | Primer toque del micrófono en «Compra por voz»; «No permitir» en el diálogo del sistema | El sistema pidió el permiso **en contexto** («¿Permitir que Agrocuentas F09 voz grabe audio?»). Tras denegar, la pantalla explica la salida: «Sin permiso de micrófono no se puede dictar. Puedes concederlo y volver a intentarlo, o escribir el texto a mano…», y el borrador se puede completar a mano («Elegir» proveedor, «Añadir producto a mano»). Bloque de estado: «Reconocedor: todavía no se sabe · Idioma solicitado: **es-US** · Idioma utilizado: todavía no se sabe» | sin cambios | **PASS** (denegación explicada; se puede escribir). Hallazgo **F09-D1** aparte (abajo) |
| V2 | — | Requiere dictado. Sólo se vio la etiqueta «Idioma solicitado: es-US» (no se promete `es-BO`) | — | **NOT_MEASURED** |
| V3 | — | Requiere dictado. Con modo avión la pantalla mostró «Modo avión: activado.» y «Todavía no se ha comprobado que funcione sin conexión en este teléfono.»; en otro momento «Modo avión: no se pudo comprobar.» | — | **NOT_MEASURED** |
| V4 | — | Requiere reconocimiento | — | **NOT_MEASURED** |
| V5–V7 | — | Requieren dictado | — | **NOT_MEASURED** |
| V8 | Micrófono abierto (con permiso, en silencio) → «Cancelar» del borrador | La pantalla se cierra y vuelve a «Registrar por voz»; el indicador desaparece | iguales antes y después (compras 2, aplicaciones 1) | **PASS** (parte manual) |
| V9 | Borrador de compra **construido a mano** (proveedor «Agro Norte», «Añadir producto a mano»: Glifosato, 1 L, 50 Bs, moneda BOB; «Total calculado: 50,00 Bs») y **dos toques seguidos** en «Registrar compra» (`input tap` ×2 consecutivos) | Una sola compra | compras 2 → **3** (+1), movimientos +1 | **PASS** (parte manual; el texto no vino del reconocimiento). Observación **F09-D2** |
| V10, V11 | — | Requieren dictado | — | **NOT_MEASURED** |
| V12 | Micrófono abierto → Inicio del sistema (`KEYCODE_HOME`; foco en el launcher) → volver a la app | El botón vuelve a «Hablar. Abre el micrófono.»; nada escrito | sin cambios | **PASS** (parte manual) |
| V13 | Micrófono abierto → Atrás | La pantalla se cierra y el borrador se descarta | sin cambios | **PASS** (parte manual) |
| V14 | Con el permiso denegado (tras V1): «Usar el formulario manual» → compra de Glifosato 2 L × 50 Bs | El formulario manual completa la misma operación («Compra registrada») | compras 1 → **2** | **PASS** |
| V15 | «Aplicación por voz» → chaco «Sur» (dos planes pendientes) | «Sur tiene 2 planes pendientes. Puede aplicar uno en vez de una aplicación libre:» con el selector «Elegir»; la lista muestra **los dos** («Plan n.º 2 · sin fecha · Glifosato», «Plan n.º 3 · sin fecha · Bellator»); **no se elige solo**; sin plan ni productos, «Registrar aplicación» está deshabilitado («Para registrar falta: • Añada al menos un producto aplicado») | sin cambios | **PASS** (parte manual) |
| V16 | Elegir «Plan n.º 2» y «Registrar aplicación» | La línea se propone desde el plan: «Glifosato · Propuesto · Stock actual 12 L · quedaría 10 L · Planeado 2 L»; «Quitar el plan (aplicación libre)» disponible. Tras registrar: aplicación n.º 2 con `plan_id = 2`, plan **APPLIED** | aplicaciones 1 → **2**, movimientos +1 | **PASS** (parte manual) |
| V17 | Planes ofrecidos por chaco | Para «Sur» **no** se ofrecen el plan de la campaña 1 (cerrada) ni los ya aplicados; tras V16 y V19, «Sur» no muestra el aviso de planes. Para «Norte» se ofrece **1** (el pendiente de Expansive), no el ya aplicado | sin cambios | **PASS** (parte manual: no se ofrece lo que no corresponde) |
| V18 | Elegir «Plan n.º 2» y «Cancelar» → «Descartar» | El plan sigue `PLANNED` | sin cambios | **PASS** |
| V19 | Elegir «Plan n.º 3» (Bellator, stock 5 L) y **dos toques seguidos** en «Registrar aplicación» | Una sola aplicación; el plan pasa a `APPLIED` una vez | aplicaciones 2 → **3**, movimientos +1 | **PASS** (parte manual) |

Conteos finales: compras 4, líneas 4, aplicaciones 3, líneas 3, movimientos 7, outbox 2 (2 ACK), necesidades 1, `integrity_check = ok`. Huella final de todas las tablas: TOTAL `67936ac60f26912f…`.

**Hallazgos (para triaje; no son resultados de reconocimiento):**
- **F09-D1 — estado atascado tras denegar el permiso.** Después de «No permitir», un **segundo toque** en el micrófono no volvió a mostrar el diálogo del sistema; el botón pasó a «Detener. El micrófono está escuchando.» y el bloque de estado quedó en «**Estado: Abriendo el micrófono**» durante más de 60 s, sin error visible. Mientras tanto `appops RECORD_AUDIO = ignore` y `granted=false`, y el sistema no registró ninguna grabación para la app. La pantalla se recuperó al cancelar. Para seguir con V8, V12 y V13 el permiso se concedió **explícitamente** por `adb shell pm grant` (equivalente a Ajustes › Permisos; queda concedido en la copia aislada y se declara aquí).
- **F09-D2 — diálogo de descarte después de registrar.** En V9, V16 y V19, inmediatamente después de registrarse la operación, apareció «¿Descartar el borrador? No se registró ninguna aplicación…» (o «…nada…»). La operación **sí** se registró (los conteos lo muestran); el texto induce a error. «Descartar» no escribió nada más.
- **Observación.** La actividad de micrófono se atribuye al servicio de reconocimiento del sistema, no a la app: `appops get <paquete>` no muestra accesos de la app al micrófono con el botón en «escuchando». No se verificó por otro medio que el reconocedor estuviera grabando.

## 4. Conjunto nuevo (D-F09-5) y banco de voz

- **Conjunto nuevo (C1–C7, P1–P6, A1–A7, S1–S2): `NOT_MEASURED`.** No hubo persona que lo escribiera fuera del repositorio ni que dictara; `set_sha256` no se fijó. La sesión A no escribió frases ni expectativas.
- **Holdout expuesto** (`benchmark/voice_benchmark`, partición `aceptacion`): no se ejecutó.
- **Registro por ID** (preparación §4): no hay entradas; no se calculó WER ni ninguna tasa.

## 5. Privacidad y registro

- `tool/f03_res_01/logcat_scan.sh` sobre el uid de la copia aislada al terminar: 73 líneas revisadas; JWT 0; UUID completos 0; contraseñas del ensayo 0; nombres de campos sensibles 0; FATAL/Unhandled 0; «valores opacos de 43+ caracteres» 1 — es la cabecera del búfer de logcat del fabricante («beginning of (HKS)…»), no un dato de la app. Registro propio de la app (`agrocuentas.log`): 68 líneas, 0 JWT, 0 UUID, 0 campos sensibles.
- No se grabó audio; no hay transcripciones en logs ni en Central; las capturas no se guardaron (los registros son volcados de `uiautomator` sin valores sensibles, en la carpeta local del ensayo).
- El observador vio 14 peticiones en todo el turno: referencias ×2, consulta de operación ×1 (404), push ×2 (una por intención), autenticación y health.

## 6. Qué falta para medir el reconocimiento

1. Una persona real junto al teléfono que escriba el conjunto nuevo fuera del repositorio (plantilla `tool/f09_device/conjunto_plantilla.csv`) y lo dicte. Puede ser la misma persona si no ajustó las reglas del intérprete y se declara.
2. Fijar `set_sha256` con `tool/f09_device/fingerprints.py` **antes** de la primera toma, con las demás huellas de §1 (que no cambian mientras la base siga en `65f7cfc`).
3. Ejecutar V2–V7, V10, V11, las partes dictadas de V15–V19 y el conjunto, registrando por ID: presencia de texto, campos automáticos frente a expectativas antes de corregir, correcciones y efecto de negocio.
4. Triaje de F09-D1 y F09-D2 (B o C), con regresión en HOST si procede.

GATE-F09 (#17), GATE-F04 (#28) y GATE-F06 (BE #22) siguen **Pending**; los decide Roderich. Esta evidencia no atribuye revisión a ninguna persona ni institución.
