# F10: preflight DS-UX Mobile sobre la base nueva del piloto (`1d77c14`, esquema 11)

- **Fecha real:** 2026-10-25 de 01:50Z a 01:58Z (UTC), que en America/La_Paz es el 2026-10-24 de 21:50 a 21:58.
- **Por qué:** el 2026-10-24 Roderich aprobó cambiar la base prevista del piloto a Mobile `1d77c14` / Backend `4bcb1ea`. Antes de ejecutarlo pidió comprobar DS-UX en el esquema v11 y su oráculo.
- **Ejecutó:** la sesión A, por `adb`, con cuentas sintéticas.
- **No es** una sesión de usabilidad: no hay participantes ni datos reales.
- **No se cambian** tarjetas, tareas, umbrales, cuestionarios, dataset ni oráculo.
- **Se conservan** el preflight anterior (`F10_PREFLIGHT_DSUX.md`, sobre `fd8dc7d`) y sus mediciones.
- **Issues:** MOB #37 (F10-UX-01) y Roderich1/Agro_Sindicato_Backend-Web#47. GATE-F10 (Roderich1/Agro_Sindicato_Backend-Web#49) sigue Pending.

## 1. Resultado

| Paso | PROPIA | COMPARTIDA |
|---|---|---|
| Activación de una copia limpia con una cuenta sintética del tenant MOVPIL | **PASS**. `x01-movpil`: `login` 200, `clients` 201, `session/client` 201 y `me` 200. Titular «Titular», «Propio» | **PASS**. `pm clear` sólo del paquete de preflight, y `p01-movpil` con el mismo recorrido. Titular «Titular», «Compartido» |
| Base recién activada | Esquema **11**, `integrity_check` ok; sólo el titular; ninguna campaña, producto, compra ni outbox | Igual |
| Siembra DS-UX-1 (`seed_dsux_mobile.dart`) sobre la base v11 | **PASS**. `DSUX_RESULT`: «Verano Demo» activa del 11/10/2026 al 24/11/2026, dentro de la central (desde el 25/09/2026); 3 vínculos `VALID`; Glifosato Demo 5 000 mL y Bellator 1 000 mL; 2 compras iniciales el 15/10; outbox 0 → 0; `integrity_check` ok; `wal_left` false | **PASS**. Lo mismo, con 2 personas y «Familiar Demo» |
| Huella de la base devuelta, en el PC y en el teléfono | **Igual**: `9d16e1352ad1f07d4d39939f5663c393ed0f8bda78d5a4ad2965bfddc4a8dde4` | **Igual**: `1b9d631d4d6e0a9a883735111e1a1b210223dc2ffe272de862ffe791f64af482` |
| Oráculo inicial (`oracle_dsux_mobile.dart`, sólo lectura) | **PASS**. Glifosato Demo 5 000 = 5 000 y Bellator 1 000 = 1 000, `consistent: true`; sin compras ni aplicaciones posteriores; sin necesidades; outbox vacío. La huella no cambia | **PASS**. Lo mismo, con `by_person_base` en «Titular» |
| Interfaz, sólo lectura | «Campaña activa: Verano Demo», «Compras 405,00 Bs» (5 × 45 + 180); Inventario «Bellator Físico 1 L» y «Glifosato Demo Físico 5 L» | Lo mismo, y en Personas «Familiar Demo» y «Titular» |
| Peticiones | Sólo las de las dos activaciones (observador). Ningún `push` | — |

**Valores esperados de T3, sin cambios:** Glifosato Demo 6 L y Bellator 1,3 L tras T1 y T2 (`nominal_after_t2_base`: 6 000 y 1 300 mL). El oráculo condicionado a lo guardado no cambia.

**Elementos nuevos que ve el participante sin intervenir en ninguna tarea** (base `1d77c14`; anotarlos para el facilitador):
- en Inicio, «PIN del titular»;
- en Operaciones, al final, «Registrar por voz» y «Operaciones tardías».

«Registrar por voz» es F09 (en pausa): ninguna tarea lo usa y el manual no lo describe. Ningún enunciado de T1–T6 cambia.

**Incompatibilidades: ninguna.** El generador y el oráculo, sin modificar, funcionan sobre el esquema 11.

## 2. Versiones y entorno

| Elemento | Valor |
|---|---|
| Mobile | `main` `1d77c140d347210bf4f924b05f5f59f31e284738`, en un worktree desacoplado y limpio, también después de compilar |
| APK de preflight | `com.comunidad.agro.agroquimicos.f10prefin` («Agrocuentas F10-PREFIN»), **profile**, con `tool/f10_eval/build_profile_apk.sh` y el origen del túnel del día. SHA-256 `a82f50a6bce6ff86ad45221d10d46fdb4312a1daeefba38a7e0c346c8a8969bd`, igual al instalado; targetSdk 36; depurable |
| | Es un paquete distinto de `.f10ux`, que **no se tocó**: el `.f10ux` instalado y la APK `2c39b344…` del 2026-10-19 se conservan |
| | Al terminar se desinstaló `.f10prefin` y quedaron 26 paquetes `com.comunidad.agro*`, como antes |
| Generador y oráculo DS-UX Mobile | `tool/f10_ux/` de `1d77c14`, sin cambios de código desde `f1fb755` (sólo cambia el README; comprobado por C). Blobs: `seed_dsux_mobile.dart` `9d03a2c5…`, `dsux_fixture.dart` `fe45d650…` y `oracle_dsux_mobile.dart` `3eb5616d…`. Flutter 3.47.2 |
| Entrada | `F10_UX_SESSION_DATE=2026-10-25` **explícita**: la misma S que en Central. `F10_UX_MODALIDAD=PROPIA` y `COMPARTIDA`. `F10_UX_REFERENCES` = el cuerpo literal de `GET /sync/v1/references` del tenant MOVPIL (`references-MOVPIL.json`, SHA-256 `e4ca3567…`), con `same_tenant_as_accounts: true` |
| Central | Lo preparó la sesión B: Backend `4bcb1ea` (`dist` de ese SHA), contenedor `agro_b_dsux4bcb_pg` y base `movpil_20261025_014659`, con el generador `Back/scripts/f10-dsux-central-seed.cjs` (blob `bb01c6c1…`), destino `movil`, etiqueta `MOVPIL` y la misma S. API 3156, con `NODE_ENV=development`, `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic` y el sellado sin activar |
| | Su verificación Central/Web y su suplemento de base están en el Backend: `docs/evidence/F10_DSUX_CENTRAL_VERIFICACION_4BCB1EA.md` |
| Credenciales | Contraseñas de un solo uso asignadas por `stdin` (hash bcrypt) a `x01-movpil` y `p01-movpil`, y tecleadas en el teléfono sin mostrarse ni escribirse |
| Red | Observador `tool/f03_res_01/observer.cjs` (puerto 3157) y quick tunnel de `cloudflared` 2026.10.0. Parados al terminar |
| Dispositivo | POCO X5 Pro 5G (`22101320G`, serial `cc14247a`), Android 12. `stay_on` 3 durante el preflight y 0 al terminar |

## 3. Procedimiento

Es el mismo de `tool/f10_ux/README.md` y del preflight del 2026-10-19:
1. app detenida (`am force-stop`);
2. la base se extrae con `run-as … cat`;
3. la base se siembra en el PC;
4. vuelve al teléfono con `adb push` a `/data/local/tmp`, `run-as cp` y el borrado del temporal;
5. se compara su SHA-256 en el PC y en el teléfono antes de abrir la app.

El journal residual de 512 bytes que dejó la activación se descartó antes de sembrar. La base estaba en modo `delete` e íntegra.

## 4. Límites

- Una sola corrida por modalidad, en un solo teléfono y con un solo operador.
- No se ejecutaron las tareas T1–T6. Para el piloto, `.f10ux` se compila desde `1d77c14` el día de cada sesión, con el túnel del día, y se activa por participante según el protocolo.
- `.f10prefin` es profile, igual que `.f10ux`, pero con otro sufijo. La APK de `.f10ux` sobre `1d77c14` todavía no existe.
- No se repiten las series de rendimiento ni la compatibilidad (R1–R6). Diferencia de base que hay que declarar: R6 midió respaldos del formato 1 sin cifrar, y la base nueva cifra en el teléfono.
- **Fecha DS-UX:** el preflight del 2026-10-19 usó `F10_UX_SESSION_DATE=2026-10-18` explícita en Mobile. El generador de Mobile no tiene valor por defecto. El valor por defecto dependiente de la zona horaria estaba sólo en `run-dsux.sh`, del Backend, y se corrige allí aparte.
