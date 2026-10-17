# GATE-F03 (#23): activación online y sesión offline verificadas en dispositivo — acta propuesta

- **Fecha:** 2026-10-17. Redactada por la sesión A de Claude Code, por la delegación técnica de Roderich.
- **Estado del gate: Pending.** Este documento **no** decide. La decisión (Passed, Failed o Waived, con su alcance) es de Roderich, con confirmación explícita. La revisión del tutor se registra aparte en GOV-01 (BE #105).
- **Base:** Mobile `main` `cf3d510` (incluye F04 #102). La sesión física de hoy se hizo con la versión `1902e6e`, que tiene el mismo código de la app que el PR de #97. Backend `e2263b0`.
- Trazabilidad (Cap. III v1.5): RF-01, RF-17, RNF-02; CU-01; RN-12.

## Antecedentes

Se conservan; no se reescriben.

| Fecha | Hecho | Dónde |
|---|---|---|
| 2026-10-04 | Decisión de cierre del gate como PASS con residuales NOT_MEASURED, sobre Mobile `278cbd3` y Backend `a098761` (CI 37231657078, 690 pruebas) | Comentario en #23. **No existía acta en `docs/evidence/`** |
| 2026-10-15 | El gate vuelve a Validation / **Pending** hasta medir en dispositivo el refresh real y la revocación (#71) | Comentario en #23 |
| 2026-10-15/16 | #71: D (refresh real), E-1 (desactivación), E-2 (revocación del registro) y reaperturas sin red, PASS en el POCO. E-2 se repitió con el escaneo de logcat ampliado | `F03_RES_01_DEVICE.md` (MOB `94e7d24`/`5527784`, BE `c2acbd4`/`063437d`) |
| 2026-10-15/16 | #83 (doble mensaje de estado), corregido en #84; #87 (correo), corregido en #88 | `F03_BUG_01.md`, `F03_BUG_02.md` |
| 2026-10-15 | **#76** (compuerta de primera activación): integrada con #77/#78 y sus correcciones; sólo pruebas de host | `F04_ACTIVACION_TITULAR_MODO.md`, `F04_CORRECCIONES_REVISION.md` |
| 2026-10-17 | **#76 en el POCO:** los cinco criterios, incluidos los casos negativos | [F03_F04_DEVICE_2026-10-17.md](F03_F04_DEVICE_2026-10-17.md) |

## Criterios de #23

| # | Criterio | Evidencia | Procedencia | Estado |
|---|---|---|---|---|
| 1 | #18 AUTH-01 con evidencia suficiente | Cliente HTTP y autenticación. `test/auth_v2_api_test.dart` (20), en CI hasta hoy (main 1072 → 1091). El extremo a extremo y el DEVICE vienen de #19 y #71 | CI + DEVICE indirecto | Cumplido para el gate. Hueco declarado: 403/404 y `ApiEndpointConfig.fromEnvironment` sin prueba |
| 2 | #19 AUTH-02 | Primera activación y vínculo: `docs/evolution/features/F03_MOB_AUTH_02_UI_WIRING_VALIDATION.md` (POCO, `18b9de3`, D y E PASS). Activaciones reales posteriores: #71 y P3 de la sesión de hoy (login 200, registro 201, sesión 201, me 200) | DEVICE | Cumplido. Residuales: 19-C (corte de red durante la activación) y 19-F |
| 3 | #20 AUTH-03 | Almacén seguro: `F03_MOB_AUTH_03_DEVICE_VALIDATION.md` (POCO, `d34a5e2`). Hoy (P13) una sesión cifrada ilegible no borra nada ni se trata como instalación nueva | DEVICE | Cumplido. Residuales: Auto Backup, D2D y corte de energía |
| 4 | #21 AUTH-04 | Apertura posterior sin red: `F03_MOB_AUTH_04_OFFLINE_STARTUP.md` (21-A…D en `8ca7ec5`). Reaperturas sin red en #71 y hoy (P6, P7, P11 tras vencer el token de acceso) | DEVICE | Cumplido. Residual: 21-E (almacén corrupto del sistema) |
| 5 | #22 AUTH-05 | Refresh y revocación: `F03_MOB_AUTH_05_REFRESH_RECOVERY.md` (22-A/B/C) y **#71 con 401 real** (E-1, E-2) | DEVICE | Cumplido. 22-D/E, que eran NOT_MEASURED, se midieron en #71 |
| 6 | Primera instalación con Internet; después, operación local sin red; un refresh inválido bloquea sólo lo remoto y no destruye SQLite | **a)** Activación real (#19, #71, P3 de hoy). Una base nueva sin activar no deja operar en el teléfono (**P1 de hoy**: 0 filas de negocio). **b)** Operación sin red (#21, #71, P6/P7/P11 de hoy). **c)** 401 real con el guard en cuarentena y SQLite intacto (#71 E-1/E-2) | DEVICE + CI | Cumplido |

**DoD de #23** («Revisión, trazabilidad, documentación y evidencia completas»): no había acta. Esta es la propuesta.

## #76 (F03-RES-02): los cinco criterios, en host y en el teléfono

| Criterio | Host / CI (con mutaciones) | Dispositivo (2026-10-17) |
|---|---|---|
| 1. Base nueva sin sesión: no escribe | `f04_repository_guards_test`, `f04_installation_access_test`, `first_activation_screen_test` | **P1 PASS**: sólo pantalla de acceso; 0 filas de negocio; 0 vínculos |
| 2. Activada y reabierta sin red, con sesión vencida o ilegible: opera y SQLite no cambia | `f04_installation_access_test`, `f04_activation_app_policy_test`, `existing_session_screen_test` | **P11 PASS** (sin red, token de acceso vencido; abrir no cambia la base; escribe) y **P13 PASS** (sesión ilegible; aviso; abrir no cambia la base; escribe) |
| 3. Base v7 o anterior: histórica, sin tocar filas ni atribuir datos | `f04_install_policy_migration_test`, `f04_historical_admin_owner_test` | **P2 PASS**: v7 → V con `LEGACY_PRE_POLICY`; todas las tablas previas idénticas; 0 vínculos; aviso de datos sin vincular |
| 4. Base vinculada en otra instalación, sin sesión u otro Member: no opera ni adopta | `f04_installation_access_test`, `f04_restore_authorization_test`, `f04_restore_ownership_rules_test` | **P12 PASS**: «Estos datos se activaron en otra instalación…»; abrir no cambia la base; ningún vínculo nuevo. Antes, por restauración: `F10_RESTORE_DEVICE.md` caso C |
| 5. Sesión ilegible: no se trata como nueva ni se borra | `f04_installation_access_test`, `f04_activation_app_policy_test` | **P13 PASS** |

**Propuesta para #76:** cerrarla con esta evidencia; los criterios están cumplidos en host y en el teléfono. Quedan como límites declarados, sin cambio de regla:
- con «sesión dañada sin activar» y con «sesión de otro Member», la pantalla muestra la condición sin una salida automática (criterio B de #78);
- un solo modelo de teléfono.

## Residuales NOT_MEASURED

No se convierten en PASS:
- DEVICE-19-C (corte de red durante la activación) y DEVICE-19-F;
- DEVICE-21-E (almacén cifrado del sistema dañado; hoy sólo se dañó el texto cifrado de un slot);
- Auto Backup restore, D2D y corte de energía (#20); multi-isolate (no reclamado);
- logcat de valores opacos de la sesión del 2026-10-15 (#71), y E-1 sin el escaneo ampliado;
- un solo modelo de teléfono (POCO X5 Pro 5G, Android 12).

**Regresión posterior a las sesiones físicas:**
- MOB #96 (mensajes de cuenta y autorización) se probó en host.
- F04 (#102) se probó hoy en el teléfono en lo que toca al arranque y la activación (P1–P3, P11–P13).

## Para decidir (Roderich)

1. **GATE-F03:**
   - **Passed para el alcance académico**, con los residuales de arriba como límite declarado;
   - o mantenerlo **Pending** hasta medir alguno (por ejemplo, 19-C);
   - o **Waived** parcial.
2. **#76:** cerrarla con [F03_F04_DEVICE_2026-10-17.md](F03_F04_DEVICE_2026-10-17.md).
3. **`Evidence = Verified`** (sólo con archivo verificable):
   - #71 (`F03_RES_01_DEVICE.md`), si se acepta el residual de E-1;
   - #18–#22 siguen Partial: sus evidencias están en `docs/evolution/features/` y #18 tiene huecos de prueba;
   - #83: el añadido con la versión medida y la observación en el teléfono va en este mismo PR (`F03_BUG_01.md`); queda para Roderich si pasa a Verified.

## Revisiones

- Redacción y sesión física: sesión A de Claude Code, el 2026-10-17.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
