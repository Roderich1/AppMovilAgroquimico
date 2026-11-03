# OE3: sesión física agrupada en el POCO (2026-11-03)

**Qué es.** La ejecución del plan del POCO de `OE3_PLAN_DEVICE_B2_2026-11-03.md` §2 y §4 (Backend PR #200). Se hizo en una sola sesión, contra un Central propio y desechable, con datos sintéticos.

**Qué no es.**
- No es una revisión del autor ni del tutor.
- No cambia ningún gate.
- No es una restauración desde B2.
- No mide nada en el HONOR, porque no estaba conectado.

Las filas sin medir quedan NOT_MEASURED, con el motivo de cada una.

## 1. Entorno

| Elemento | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G (`cc14247a`), Android 12. Es el único modelo usado |
| Código Mobile | `b7a981356e6eae368598971ac79e9fd068151996`: `main` `5b5b318` más `tool/oe3/` sin cambios en `lib/` |
| APK | `com.comunidad.agro.agroquimicos.oe3` («AC OE3»), profile arm64. SHA-256 `a1e4ff4f8e44a8826805e8f9cc056bcfe5c7f27e534600db1a0dbf3cbf9a5225`. Compilada con el origen del túnel del día; instalada a las 16:21:32Z, confirmando el diálogo de MIUI |
| Backend | Worktree `_wt/F12-EST-08` en `6a5cab4`. `Back/src` y `Back/prisma` son idénticos a `origin/main` `5973b49` (`git diff` vacío) |
| Central | PostgreSQL desechable `agro_oe3_pg` (127.0.0.1:55495, `--rm`, sin volumen), API en 3320 y observador en 3321, con la siembra `docs/evidence/f12_est_07/control-sintetico.cjs` |
| Túnel | Quick tunnel HTTPS de `cloudflared` 2026.10.0, temporal. Cerrado al terminar |
| Observador | `tool/f03_res_01/observer.cjs`: registra sólo hora, método, ruta y estado. Esta sesión le añade el modo `hold-path <ruta>` (§5) |

**Credenciales.**
- **Contraseñas:** son de un solo uso. Se generan, se guarda su hash en la base desechable y se teclean sólo en un campo `password="true"` (`oe3.sh credential`). Nunca se imprimieron ni se escribieron.
- **Administrador sintético:** usa el mismo patrón (`tool/oe3/admin.sh`). La petición la hace `node`, con el token sólo en el entorno.
- **PIN del titular:** sólo en la memoria de `tool/oe3/pin_holder.sh`, tecleado por `pin_safe.sh` únicamente en campos de contraseña. Se descartó al terminar.

## 2. Resultados

Horas en UTC. «Volcado» es el SHA-256 de todas las filas de la base de la app (`tool/oe3/appdb.sh --dump`), tomado de una copia temporal con `run-as`.

| Caso | Pendiente | Resultado | Evidencia |
|---|---|---|---|
| P-01 | #19 DEVICE-C: corte de red durante la activación | **PASS** | Ver P-01 |
| P-02 | #19 DEVICE-F: reactivación en el mismo proceso | **PASS**, por la entrada que ofrece el producto («Volver a autenticar») | Ver P-02 |
| P-03 | #21 21-E: almacén dañado | **PASS** para el almacén entero dañado. **NOT_MEASURED**: versión incompatible real y Keystore | Ver P-03 |
| P-04 | #71 E-1 con el escaneo ampliado | **PASS** | Ver P-04 |
| P-05 | #76 criterio 4: otro Member | **PASS** para la sesión de otro Member. «Sin sesión» no se alcanza desde la interfaz | Ver P-05 |
| P-06 | #121 R-03: cancelar el selector de fecha | **PASS** | Ver P-06 |
| P-07 | #125: sucesora con inicio hoy | **PASS**. El vínculo con el sindicato no se ejerció | Ver P-07 |
| P-08 | #28 criterio 4: transferencia en modo compartido | **PASS** | Ver P-08 |
| P-09 | #49: pago a la deuda previa en modo compartido | **PASS** | Ver P-09 |
| P-10 | #97: nombre largo con `font_scale` 1,3 | **PASS** | Ver P-10 |
| P-11 | #151 punto 10: cota | **PASS**. **NOT_MEASURED**: el plazo de 7 días | Ver P-11 |
| C10 | BE #18: otra instalación del mismo Member | **PASS**, contra el servidor real | Ver «Sincronización» |
| C16 | BE #18: valor nuevo en una campaña cerrada | **PASS**, contra el servidor real | Ídem |
| C18 | BE #18: CANCEL en una campaña cerrada | **PASS**, contra el servidor real | Ídem |
| C19 | BE #18: producto inactivo | **PASS** sólo para la variante «inactivo». Las variantes «inexistente» y «de otro sindicato» quedan NOT_MEASURED en DEVICE | Ídem |
| C33 | BE #18: sucesor tardío de una rama cercada | **NOT_MEASURED** | §4 |

### P-01: corte durante el vínculo (#19 DEVICE-C)

**Estado inicial.** Instalación nueva. En Central, el Agricultor A tenía 0 registros de cliente y 0 sesiones.

**Cómo se cortó.**
1. Se preparó `hold-path /api/v1/auth/v2/session/client`: el observador retiene sin reenviar la llamada de vínculo.
2. 16:24:56.781: `login` 200.
3. 16:24:57.026: `auth/clients` 201.
4. 16:24:57.215: `session/client` RETENIDA_SIN_REENVIAR. Central nunca la recibió.
5. 16:24:58: **modo avión del teléfono**, con la llamada en curso.
6. 16:25:27: el observador cerró la conexión retenida.

**Resultado del intento cortado.**
- **App:**
  - muestra «No se pudo confirmar la operación remota. Sus datos locales siguen disponibles.» y «El resultado necesita revisión. No vuelva a activar esta instalación hasta verificar el estado de la sesión.»;
  - deja «Activar» deshabilitado;
  - al volver a entrar en el mismo proceso sigue bloqueado. Es el marcador de esta ejecución que documenta `F03_MOB_AUTH_02_UI_WIRING_VALIDATION.md`.
- **Teléfono:** puntero ausente y sesión cifrada ausente. No quedó un vínculo parcial. Identidad `3d2a44ef5edf`.
- **Central:** 1 registro ACTIVE y 1 sesión ACTIVE **sin vincular**. No hubo `logout`, porque la limpieza no pudo confirmarse sin red.

**Reintento.**
1. 16:25:49: red restablecida.
2. `force-stop` y apertura.
3. 16:27:20: `login` 200, `auth/clients` 201, `session/client` 201, `me` 200. La app pasó a la pantalla del titular.

**Resultado del reintento.**
- **Central:** sigue con **1** registro de cliente (el mismo), más una sesión vinculada.
- **Teléfono:** slot `a` y la **misma** identidad.

**Residuo.** La sesión sin vincular del intento cortado sigue ACTIVE en Central hasta que venza. No sirve para sincronizar, porque no tiene registro.

**Capturas:** `P01_corte_vinculo.png`, `P01_reintento_titular.png`.

### P-04: desactivación con escaneo ampliado (#71 E-1)

**Acción.**
1. 16:30:42: el Administrador sintético desactiva al Agricultor (`PATCH users/{id}/deactivate` 200; `logout` 204). User y Member quedan inactivos.
2. Una sola pulsación de «Verificar acceso en línea».

**Resultado en la app.**
- **Peticiones:** exactamente **1** `refresh` 401 (16:30:47.784) y **0** peticiones en los 60 s siguientes.
- **Pantalla:** muestra «Se requiere volver a autenticar…».
- **Guard:** `quarantined`.
- **Central:** la sesión no quedó COMPROMISED.

**Escaneo de logcat** (uid de `.oe3`, 210 líneas, en memoria):

| Patrón | Coincidencias |
|---|---|
| JWT | 0 |
| UUID completos | 0 |
| Valores opacos de 43 o más caracteres | 0 |
| Campos sensibles, sin distinguir mayúsculas | 0 |
| FATAL | 0 |
| Correo del Agricultor | 0 |
| Id de la sesión y su prefijo de 8 | 0 |
| Id del registro | 0 |

El registro propio de la app (`app_flutter/agrocuentas.log`, 6 líneas) también dio 0 en todo. Al final de la sesión se repitió sobre 319 líneas, con 0 JWT, 0 opacos, 0 campos y 0 correos.

**Captura:** `P04_reautenticar.png`.

### P-02: reactivación en el mismo proceso (#19 DEVICE-F)

**Por qué esta entrada.** Con un titular vinculado, el producto no ofrece una «activación libre» ni un cierre de sesión. La entrada es «Volver a autenticar» o «Recuperar acceso», con el mismo Member (diseño de F03). Se midió esa entrada.

**Pasos.**
1. Estado previo: volcado `ecddecb6…` (5 filas), 1 persona, 1 titular, PID 29130.
2. 16:33:30: reactivación de la cuenta (`PATCH users/{id}` `isActive=true`, 200).
3. 16:34:32: «Volver a autenticar»: `login` 200, `session/client` 201, `me` 200. Sin `auth/clients`.

**Resultado.**
- **Pantalla:** «Acceso en línea verificado».
- **Proceso:** el **mismo PID**.
- **Sesión:** slot `b` nuevo, guard libre y la misma identidad.
- **Datos:** el volcado es **idéntico**, con 1 persona y 1 titular.

**Observación.** La sesión anterior, la que tuvo el 401, sigue ACTIVE en Central después de reactivar la cuenta.

**Captura:** `P02_recuperado_mismo_proceso.png`.

### P-03: almacén seguro entero dañado (#21 21-E)

**Pasos.**
1. `force-stop` y, a las 17:05:25, modo avión.
2. Con `run-as`, `shared_prefs/agrocuentas_secure_session_v1.xml` se sustituyó por XML inválido de 62 bytes: los dos slots y la estructura, no un solo slot como en P13.

**Al abrir sin red.**
- **Pantalla:** «La vinculación local no puede leerse. Los datos locales siguen disponibles.», más «Recuperar acceso» y «puede seguir registrando».
- **Datos:** **0** peticiones, el volcado **idéntico** (`c00ca168…`, 39 filas) y el archivo dañado intacto, sin borrado. «Nueva compra» se abre. No se trató como una instalación nueva.

**Recuperación.**
1. 17:06:03: red restablecida.
2. «Recuperar acceso» con la misma cuenta: `login`, `auth/clients`, `session/client` y `me`.

**Resultado de la recuperación.**
- **Sesión:** slot `a` nuevo y la misma identidad.
- **Datos:** el volcado es idéntico.
- **Central:** sigue con **1** registro de cliente.

**NOT_MEASURED:**
- **Versión de registro incompatible:** el número de versión va dentro del texto cifrado, y sin la clave del Keystore no se puede fabricar un registro válido con otra versión.
- **Daño del Keystore:** requiere root.

**Captura:** `P03_almacen_danado_sin_red.png`.

### P-07: sucesora con inicio hoy (#125)

**Pasos.**
1. «Invierno Sintetica», desde el 01/10, pasa a ACTIVE.
2. Se crea «Verano Sintetica» con inicio **hoy**, 03/11, sin tocar el reloj. Queda PLANNED, y la anterior pasa a terminar el 02/11, como avisa la app.
3. «Activar» abre «Cerrar y activar».

**Resultado.**
- **Campañas:** Verano ACTIVE desde el 03/11; Invierno CLOSED del 01/10 al 02/11. No hay solape y el intervalo anterior se conserva.
- **Operaciones:** la compra y la aplicación de hoy quedaron en Verano.
- **Límite:** `campaign_bindings` = 0, así que el vínculo con el sindicato no se ejerció en este caso. Se ejerció después, en «Sincronización».

**Capturas:** `P07_antes.png`, `P07_despues.png`.

### P-10: nombre largo con `font_scale` 1,3 (#97)

**Preparación.**
- `font_scale` pasó de 1,0 a 1,3 a las 16:41:29 y se restauró a 1,0 a las 17:01:47.
- Persona «Maximiliano Bartolome Fernandez de la Cruz Villarroel», de 53 caracteres.
- Compra de 10 L repartida entre Ana (5 L) y Maximiliano (5 L).

**Resultado.** El nombre se ve completo, sin cortes ni palabras partidas:
- en el selector de persona, en 2 líneas;
- en el campo del reparto, en 3 líneas cortadas en espacios;
- en la revisión, también completo.

**Capturas:** `P10_selector_persona_fs13.png`, `P10_reparto_fs13.png`, `P10_revision_fs13.png`, `P10_resumen_aplicacion_fs13.png`.

### P-06: cancelar el selector de fecha (#121 R-03)

En el formulario de aplicación, con la persona ya elegida, se abrió el selector, se eligió el lunes 2 de noviembre y se pulsó «Cancelar». El formulario quedó idéntico: 03/11 «hoy» y la misma persona, con el `diff` del volcado de la interfaz vacío.

**Capturas:** `P06_selector_cambiado.png`, `P06_tras_cancelar.png`.

### P-09: pago a la deuda previa en modo compartido (#49)

**Asientos.**
- La aplicación de Maximiliano (2 L) genera `USAGE_CHARGE` 60000.
- Su pago de 250 Bs genera `PAYMENT` −25000.

**Imputación.** `payment_allocations` tiene una sola fila: el pago 2 se imputa al cargo 1 por **25000**, y el cargo no cambia.

**Pantalla:** «pagos aplicados 250,00 Bs», con saldo y deuda pendiente de 350,00 Bs.

**Captura:** `P09_pago_form.png`.

### P-08: transferencia y reversión en modo compartido (#28 criterio 4)

**Antes.** Saldos por persona: Ana 5000 y Maximiliano 3000.

**Transferencia.**
- Ana → Maximiliano, 2 L. El diálogo avisa de que no genera cargo ni cobro.
- Movimientos: `TRANSFER_OUT` −2000 para Ana y `TRANSFER_IN` +2000 para Maximiliano.
- `account_transactions` no cambia.

**Reversión.**
- Exige el PIN del titular. Se configuró con una confirmación en línea (`login` 200 y `logout` 204), mediante el guardián.
- Se revirtió con el motivo «Ensayo OE3 reversion» y el PIN.
- Movimientos compensatorios: `TRANSFER_REVERSAL_IN` +2000 para Ana y `TRANSFER_REVERSAL_OUT` −2000 para Maximiliano.

**Resultado.**
- **Saldos:** vuelven a los de antes (5000 / 3000).
- **Lo que no cambia:** `account_transactions` sigue en 2 filas, con suma 35000.
- **Estado:** la transferencia queda REVERSED, con una fila en `reversal_audit`.
- **Lo que no aparece:** saldos negativos y consumos.

**Capturas:** `P08_transferencia_form.png`, `P08_confirmar.png`, `P08_revertida.png`.

### P-11: cota de copias previas (#151 punto 10)

**Pasos.**
1. Respaldo local exportado a las 17:02:27 (10 798 bytes, esquema 13, sin fotos).
2. Tres restauraciones: 17:03:31, 17:04:10 y 17:04:32.

**Resultado.**
- `databases/previo/registro.json` pasa de 1 a 2 entradas `finalized`.
- Tras la tercera quedan exactamente **2**: las de 17:04:10 y 17:04:32. La de 17:03:31 se retiró, con su entrada y su archivo.
- El volcado es idéntico.
- No se pidió el PIN para restaurar el respaldo propio.

**NOT_MEASURED:**
- **Plazo de 7 días:** exige mover el reloj, que no está autorizado.
- **Copias `interrupted` y `retained`:** no se ejercieron. No hace falta una cota para `retained`: la protege la excepción vigente (F08-ADR-003 §7.2).

**Captura:** `P11_tras_tercera.png`.

### P-05: respaldo de otro Member (#76 criterio 4)

**Cómo se conservó el contenedor de la app.** Android 12 impide leer la exportación de `files/Download` con `adb pull` y con `run-as` (*Permission denied*), igual que en `F10_RESTORE_DEVICE.md`. Para no tener que fabricar un contenedor:
1. A las 17:09:33, `force-stop`.
2. Con `run-as` se borraron sólo los datos **internos** de `.oe3`: `app_flutter`, `databases`, `files`, `no_backup`, `shared_prefs`, `cache` y `code_cache`.
3. Quedó la exportación de Ana (Member A), la de 17:02:27, en la carpeta externa.

**No es una desinstalación:** las claves del Keystore del paquete pueden seguir.

**Pasos.**
1. El Administrador sintético creó el Agricultor B (`POST users` 201).
2. 17:10:13: activación de B, con identidad nueva `fbfd5f1db214` y titular «Beatriz Sintetica».
3. Volcado previo: `58d2720b…` (5 filas).
4. 17:11:36: «Restaurar» el respaldo de A.

**Resultado.**
- **Rechazo:** la app rechaza al instante, antes de sustituir nada: «Esta copia pertenece a otro titular (otra cuenta o sindicato). No se restauró; sus datos actuales se conservan.»
- **Datos:** el volcado es **idéntico**, no hay carpeta `previo` y el titular sigue siendo Beatriz.
- **Red y sesión:** 0 peticiones y la sesión de B intacta.

**«Sin sesión».** No se alcanza desde la interfaz: antes de activar, la app sólo ofrece «Activar en línea». Sigue cubierto en HOST por `f04_restore_authorization_test`.

### Sincronización contra el Central real

Todo ocurrió en la instalación de B.

**Vínculos.**
- «Campana B» (03/11/2026–01/02/2027; la app exigió fijar un fin) ↔ «Campaña abierta A» (ABIERTA, 01/09/2026–01/03/2027).
- «Herbicida B» ↔ «Herbicida de ensayo».
- `refresh` 200 y `references` 200.

**Operación base.** `f42331f1` PUBLISH 20 L, `push` 200 a las 17:20:16, APPLIED.

**Medición complementaria (no es una de las filas pendientes): respuesta perdida en la misma instalación.**
- `drop-push-response` sobre `c7dac644` (25 L): Central la aplicó (17:21:25.076) y el teléfono no recibió la respuesta.
- La app reintentó sola a las 17:21:36 (200) y la operación quedó ACKED, con `server_accepted_at` = 17:21:25.076, la hora del primer envío.
- El journal tiene 1 fila para ese id.

**C10: otra instalación del mismo Member (PASS).**
1. `a01883f5` (30 L) con la respuesta retenida: Central la aplicó a las 17:28:53.931.
2. Modo avión a las 17:28:54: el teléfono queda con OUTCOME_UNKNOWN / NETWORK.
3. Exportación del respaldo sin red (17:30:48).
4. Borrado interno y nueva activación de B (17:31:37): Central tiene **2** registros de cliente ACTIVE de B, con la identidad `b51ee391b19d`.
5. Restauración: `a01883f5` RESTORE_PAUSED, 0 peticiones.
6. «Liberar» (17:33:39): `push` 200 y ACKED.

**Resultado:**
- `server_accepted_at` es la original, 17:28:53.931.
- La fila del journal no cambia (APPLIED, `updatedAt` 17:28:53.936).
- La segunda instalación no creó otra aplicación: el registro no forma parte de la clave.
- El observador no guarda cuerpos, así que el `resultCode` literal de la respuesta no queda registrado.

**Captura:** `P12_pausado_restauracion.png`.

**C16: valor nuevo en una campaña cerrada (PASS).**
- El Administrador cerró «Campaña abierta A» por la API (`POST campaigns/{id}/close` 200, CERRADA a las 17:34:46).
- El teléfono, sin saberlo, sustituyó por 35 L: `22654d23` **REJECTED / CAMPAIGN_NOT_OPEN**.
- La contribución en Central siguió ACTIVE, con 30000 y cabeza en `a01883f5`.
- La pantalla dice: «Rechazada por el sindicato: La campaña ya no admite publicaciones…».

**Captura:** `C16_rechazada.png`.

**C18: CANCEL en una campaña cerrada (PASS).**
- «Anular» generó `e13c55ec` CANCEL, apoyado en `a01883f5`, la última aceptada, no la rechazada.
- Quedó **APPLIED**, y la contribución pasó a **CANCELLED, sin cantidad**.

**Captura:** `C18_anulada.png`.

**Reapertura.** Reabrir la campaña (`POST …/open`) da 400. Es correcto.

**C19: producto inactivo (PASS en esta variante).**
- El Administrador desactivó «Herbicida de ensayo» (`POST inventory/products/{id}/deactivate` 200).
- «Declarar de nuevo» 12 L generó `4566b06d` PUBLISH **REJECTED / REFERENCE_UNAVAILABLE**, sin contribución.
- La pantalla muestra un mensaje genérico: «El sindicato no reconoce el producto o la campaña…».
- Central comprueba el producto antes que el estado de la campaña (`push-operation.use-case.ts`), por eso el código es ese y no CAMPAIGN_NOT_OPEN.

**Captura:** `C19_producto_inactivo.png`.

## 3. Observaciones nuevas (no investigadas)

1. **Cantidad con punto decimal en la transferencia.** Con «1.5» en la cantidad, «Revisar y confirmar» no avanzó y la pantalla no mostró ningún mensaje. Con «2», sí avanzó. No se probó «1,5» ni se miró el código. Hay que reproducirlo antes de clasificarlo como defecto.
2. **Sesiones remanentes en Central.** Quedan ACTIVE en Central:
   - la sesión sin vincular del corte de P-01;
   - la sesión del 401 de P-04, después de reactivar la cuenta.

   Ninguna tiene uso desde el teléfono. Conviene que el autor decida si la desactivación debería revocarlas.

## 4. No ejecutado y por qué

- **Filas de transporte controlado** de BE #18 (C07, C08, C09, C12, C13, C17, C21, C25–C29, C32, C37, C39):
  - necesitan modos nuevos del observador que alteren el cuerpo del envío;
  - esta sesión sólo añadió `hold-path`;
  - siguen NOT_MEASURED en DEVICE, con su PASS de HOST.
- **C33:** necesita dos instalaciones simultáneas con un conflicto resuelto y un sucesor tardío. No se montó.
- **C19, variantes «inexistente» y «de otro sindicato».**
- **#20 Auto Backup, D2D y corte de energía:** necesitan ajustes globales, un reset o cortar la energía, y ninguno está autorizado.
- **HONOR** (H-01 #129 y H-02 #151 punto 7): el teléfono no estaba conectado. No se sustituyó por el POCO.
- **B2:** no hay credenciales autorizadas. Ninguna restauración de esta sesión es desde B2: todas son desde un archivo local.

## 5. Herramientas añadidas (`tool/oe3/`)

| Herramienta | Qué hace |
|---|---|
| `install_miui.sh` | Instala la APK y pulsa «Instalar» sólo en el diálogo de MIUI |
| `central.sh` | Conteos y estados del Agricultor en el Central desechable, en sólo lectura |
| `admin.sh` | Acciones del Administrador sintético por la API real: desactivar, activar, crear el Agricultor B y `post` genérico |
| `appdb.sh` | Consulta o volcado de una copia temporal de la base de la app |
| `pin_holder.sh` y `pin_safe.sh` | Adaptados de `_wt/tools/av` para el POCO |
| `oe3.sh` | `OE3_FARMER=B` para el segundo Agricultor |
| `tool/f03_res_01/observer.cjs` y `fault.sh` | Modo `hold-path <ruta>`: retiene sin reenviar el próximo POST a esa ruta |

## 6. Cierre e incidente

**Cierre.**
- PIN descartado.
- `.oe3` desinstalado. Era el único paquete tocado: los otros 20 siguen intactos.
- Modo avión apagado y `font_scale` en 1,0.
- `stay_on` en 3: es el valor que tenía al empezar esta sesión, y no se cambió.
- Túnel y observador cerrados, supervisor detenido y contenedor `--rm` eliminado.
- La API, detenida por PID. Puertos 3320, 3321 y 55495 libres.

**Incidente.** Al identificar el proceso de la API para detenerlo, se consultó la línea de comandos de su proceso padre (`env.exe`). La salida de la sesión mostró los **secretos efímeros del Central desechable**: `JWT_SECRET`, `JWT_REFRESH_SECRET` y la clave de huella de sync-v1.
- **Dónde no están:** en ningún archivo, log del repositorio ni commit.
- **Qué se hizo:** el proceso se detuvo al instante, y el contenedor, que se crea con `--rm`, ya no existe.
- **Riesgo:** esos valores no sirven fuera de ese entorno.
- **Prevención:** en adelante, la API se detiene por puerto y PID, sin leer su línea de comandos.
