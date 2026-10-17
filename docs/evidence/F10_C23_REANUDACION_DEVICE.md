# #18 C23: reanudación con un registro nuevo del mismo titular, en el POCO

- **Fecha real:** 2026-10-17, de 04:38Z a 04:48Z.
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica. Sin inspección personal de Roderich ni revisión del tutor.
- **Antecedente:** en la tanda 1 de #18 (Mobile `docs/evidence/F05_SYNC_06_DEVICE_F10.md`), C23 dio la **pausa** PASS y la **reanudación con un registro nuevo** NOT_MEASURED, porque requería otra instalación.
- **Este ensayo completa la reanudación** con el arnés existente (copias aisladas, respaldo F08 y acción real de revocación). Decisión del 2026-10-16: «Revisa C23 para completar la reanudación con el registro nuevo del mismo propietario si el arnés existente lo permite».
- **#18 sigue abierto.** No es un PASS de GATE-F05.

## Entorno

| Elemento | Valor |
|---|---|
| Backend | `ed069a6` compilado, `NODE_ENV=production`, entorno `agro_a_f10eval_pg` (el de la evaluación F10) y túnel HTTPS con observador |
| Copia X (la instalación que se revoca) | `com.comunidad.agro.agroquimicos.f10c23x`, APK profile de Mobile `dff6802`, SHA-256 `878916a5e4e44c861184664977d565d462578b2468a5a45a2e4967c58a4f9d52` |
| Copia Y (la instalación nueva) | `com.comunidad.agro.agroquimicos.f10c23y`, mismo código, SHA-256 `2be2dabb5d116e735fd62ae038cba9591f2027a407ee0498dca4f07220a0cd07` |
| Cuenta | Sintética E2, con contraseñas de un solo uso (`credential.sh`) que no se imprimieron |
| Dispositivo | POCO X5 Pro 5G, Android 12. `font_scale` 1,3 durante el ensayo: la activación de X sirvió también como M1 de A1-F |
| Datos | DS-V en X, sembrado en el host con `seed_dsv_mobile.dart`. Vínculos con «Campana Verano 2026» y «Glifosato 48 SL» hechos por la interfaz |

## Secuencia (horas UTC; peticiones según el observador: método, ruta y estado)

| Hora | Paso | Resultado |
|---|---|---|
| 04:39:14 | X: activación con E2 | `login` 200, `auth/clients` **201** (registro de X), `session/client` 201, `me` 200 |
| 04:41:06–24 | X: verificar acceso y referencias; vínculos | `refresh` 200, `references` 200 |
| 04:43 | **Protección:** se prepara `hold-push-request` en el observador. X se detiene, pasa a modo avión, se reabre sin acceso verificado y declara 40 L | Intención **`d05e9468`** PUBLISH: **PENDING**, 0 intentos |
| 04:43:49–52 | X, con red: «Subir respaldo» (copia en la nube **antes** de revocar). X se detiene al confirmarse | `refresh` 200, `POST /me/backups` 201 (231 916 B) y `GET` 200. **Ningún push:** el fallo de protección no se consumió y E2 no tenía journal |
| 04:44:20 | **Revocación real por la API**, hecha por la propia cuenta: `POST auth/clients/{id}/revoke` | HTTP 201. Registro de X **REVOKED**; sus sesiones, REVOKED |
| 04:44:47 | X: «Sincronizar ahora» | `refresh` **401**. Mensaje «Se requiere volver a autenticar para las funciones en línea. Sus datos locales siguen disponibles.» La intención sigue PENDING, **0 push** |
| 04:45:57 | Y: activación con la misma cuenta E2 | `login` 200, `auth/clients` **201** (registro **nuevo**), `session/client` 201, `me` 200. Titular «Titular C23 Y» |
| 04:46:53–04:47:08 | Y: «Respaldo en la nube» → copia de X → «Restaurar» | `refresh` 200, `GET /me/backups` 200 y `GET /me/backups/{id}/content` 200. «Verificada con SHA-256». Tras confirmar: **`d05e9468` RESTORE_PAUSED** y titular «Titular C23», del mismo Member. **Ningún push** al restaurar |
| 04:48:11 | Y: Sincronización → «Envíos pausados por una restauración… Liberar» → confirmar (acción explícita). Antes se retiró el fallo de protección | Un **único** `POST /sync/v1/push` 200 del mismo `operationId` → **ACKED** |

**Estado de Central al terminar:**
- journal `d05e9468`: PUBLISH, **FINAL APPLIED OK**, secuencia 1, aceptada a las 04:48:11;
- contribución DECLARED_NEED «Campana Verano 2026 / Glifosato 48 SL», **ACTIVE**, 40 000 ML;
- registros de E2: **ACTIVE 1 (Y)** y **REVOKED 1 (X)**. **El registro revocado no se reactivó.**

## Resultado

**C23 (columna Mobile): PASS, pausa y reanudación.**
- Tras la revocación del registro, la instalación revocada no publica.
- El mismo titular reanuda desde una instalación con un registro nuevo, restaurando su copia y liberando la intención con una acción explícita. El efecto queda **APPLIED una vez**, con el mismo `operationId`.
- No hubo refresh ni reanudación automáticos.

**Lo que no se midió en el dispositivo:** el reenvío posterior que devolvería ALREADY_APPLIED. La app no reenvía una intención ya ACKED. Ese reenvío lo acredita la columna Central (`sync-v1-adversarial` C23).

## Límites

- **Un solo teléfono, con dos copias aisladas.** No son dos teléfonos físicos.
- **Única ruta, y por diseño (#71):** una copia en la nube hecha **antes** de revocar. La instalación revocada no puede subir ni exportar después, y la exportación local no es legible desde fuera de su paquete en Android 12.
- **Fallo de protección:** `hold-push-request` estuvo preparado mientras X tenía acceso, por si salía un push. No se consumió y se retiró antes de liberar.
- **Titular de Y:** se creó al activar y la restauración lo sustituyó por el de la copia (mismo Member y tenant).
- **Logcat:** el escaneo de la sesión se hizo sobre `.f10eval`. Sobre `.f10c23x` y `.f10c23y` no se hizo escaneo propio.
