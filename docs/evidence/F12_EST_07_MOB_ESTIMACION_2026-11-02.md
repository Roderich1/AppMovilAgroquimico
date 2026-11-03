# F12-EST-07-MOB — Consulta y copia descargada de la estimación (MOB #164)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-02 y 2026-11-03 (UTC) |
| Rama | `feat/f12-est-07-mob-copia` |
| Base | Mobile `main` `4ca2088`. Servicio: Backend-Web `main` `635cc8f` (#195, con `GET /estimation/download`) |
| Código verificado | Primera entrega: `398db76` y `1c97b40` (§5–§8). **Retirada persistente y ensayo contra el Backend real: §10–§12**, código final `5594599` (sin cambios en `lib/` después) |
| Issue | Refs #164. **No se cierra** |
| Origen | Implementación nueva. Solo datos sintéticos |
| Contrato | Backend-Web `docs/architecture/F12_EST_07_COPIA_MOBILE.md` y `F12_EST_01_ESTIMATION_CONTRACT.md` §9 (INT-09 v1). Si discrepan con el prototipo, **gana el contrato** |
| Procedencia | **HOST** (§5, §10). **DEVICE con servidor REAL** (§11) y **DEVICE con servidor simulado** (§6). **EMULADOR: no ejecutado** |

## 1. Trazabilidad

| ID | Qué cubre aquí |
|---|---|
| CU-21 | Consultar la estimación del consumo (perfil del Agricultor) |
| RF-39 | Consulta con conexión de los resultados permitidos |
| RF-40 | Copia descargada legible sin conexión, con sus fechas y el aviso |
| RN-30 | La estimación es una referencia: no se suma a la necesidad declarada, no cambia el inventario ni crea compras |
| DAT-20 | Copia local vinculada a identidad, sindicato y campaña; fuera del respaldo privado |
| INT-09 | `GET /api/v1/estimation/results` y `/download`, perfil `FARMER` |

## 2. Qué se construye

| Pieza | Estado |
|---|---|
| Entrada en Inventario | Tarjeta «Estimación del consumo» → `/inventario/estimacion`, sin el «Nuevo» flotante |
| Al abrir | Lee **solo** la copia de este teléfono para el titular vigente. **No consulta al servidor por su cuenta** |
| «Consultar con conexión» | Verifica el acceso (token V2 en memoria, o `verifyOnline`). Lista las campañas del sindicato (`GET /sync/v1/references`) y muestra `GET /estimation/results` con el perfil FARMER y la vigencia al consultar |
| «Descargar copia para consultar sin conexión» | Solo con conexión y a petición. Guarda la respuesta de `GET /estimation/download` **tal como llegó** |
| Lectura sin conexión | Muestra el aviso de posible desactualización, y además:<br>• la fecha de descarga y la de generación de cada resultado;<br>• el período objetivo y la temporada;<br>• por resultado, la vigencia **al descargar** y la vigencia **actual**, «desconocida sin conexión» |
| Ausencias | «Datos insuficientes» con su motivo y «Sin cifra». Con `SOURCES_WITHDRAWN`, «Cifra retirada». **Nunca un cero** |
| Sin copia | «Sin copia descargada. No hay una estimación descargada en este teléfono: sin conexión no se muestra ninguna cifra…» |
| Cálculo | **Ninguno en el teléfono:** no hay SES ni otra regla. Las cantidades se formatean con texto y enteros, sin coma flotante |
| Pie | «Es una referencia: no se suma a su necesidad declarada, no cambia su inventario y no crea compras.» Ningún código suma la estimación a necesidades ni inventarios |

### 2.1 Contraste con el prototipo M6 (figura 3.25)

La fuente es una copia de trabajo del documento de tesis v1.22.1 (sha256 `964286d1…`), que **no se modifica**.

| Elemento de M6 | En la app | Resultado |
|---|---|---|
| Dentro de Inventario | Tarjeta en Inventario y ruta `/inventario/estimacion` | **Coincide** |
| «Sin conexión: copia descargada. Generada el … y descargada el …; vigente al descargar, puede haber cambiado» | Aviso con la fecha de descarga y la advertencia; la fecha de generación va en cada resultado | **Coincide** |
| Campaña objetivo | Período objetivo y temporada | **Coincide** |
| Producto «Calculada» con la cifra | Estado «Estimado» y la cifra exacta: «111 L (111.000 mL)» | **Coincide** |
| Producto con «Datos insuficientes» y su motivo, sin cifra | «Datos insuficientes» con el motivo del servidor y «Sin cifra» | **Coincide** |
| «Es una referencia: no se suma a su necesidad declarada…» | El mismo texto en el pie | **Coincide** |
| Línea base naive | **No se muestra** | **Diferencia:** el contrato excluye el naive del perfil FARMER |
| «Cobertura Invierno 2026: 9 de 12» | **No se muestra** | **Diferencia:** el contrato excluye la cobertura del perfil FARMER |
| «Observado (cifras publicadas)», serie 96·120·104·116 | **No se muestra** | **Diferencia:** la descarga FARMER no trae la serie |
| α = 0,50 | No se muestra | No viene en el perfil FARMER |

**Por qué prevalece el contrato.** El documento presenta M6 como prototipo conceptual con cifras ilustrativas. INT-09 v1 (contrato §9 y `F12_EST_07_COPIA_MOBILE.md` §2) no entrega al Agricultor ni el naive, ni la cobertura, ni la serie. Si se quisieran mostrar, habría que decidirlo en el contrato y en la política, no en la app.

## 3. Migración (esquema 13)

**Número.** Se tomó el 13 tras comprobar el esquema actual: Mobile `main` `4ca2088` está en el 12 (F04-AV, #168) y ninguna otra rama abierta reclama un número. F04-AV ya lo había anotado: «#164 … si integra después, debe tomar el 13».

**Aditiva e idempotente:** dos tablas nuevas, vacías, con `IF NOT EXISTS`. No toca ninguna otra tabla ni fila.
- `estimation_copies`:
  - una fila por `(member_ref, tenant_ref, target_campaign_ref)`;
  - con `owner_binding_id` (el titular que la descargó), `format_version` 1, `downloaded_at` (hora del servidor), `saved_at` y `payload` (la respuesta tal como llegó);
  - sin credenciales.
- `estimation_copy_access`: una sola fila con un identificador aleatorio de acceso. Cada invalidación la borra y la siguiente descarga crea una nueva.

**Pruebas:**
- una base v12 con operaciones migra a la 13 y conserva **todas** las filas de las demás tablas (`dumpTables` idéntico);
- `schema_equivalence_test` sigue verde: una base nueva y una migrada terminan iguales;
- `rec_039` fija la versión 13.

## 4. Reglas de la copia

1. **Lectura.** Solo con identidad, es decir:
   - instalación `activated`;
   - sesión segura legible, del mismo Member y sindicato que el **titular vigente**;
   - la fila coincide en Member, sindicato y vínculo de titular;
   - el JSON guardado es de esa identidad y de esa campaña.

   Sin identidad no se lee nada, y que exista una fila no autoriza a leerla.
2. **Guardado.** En **una transacción**, solo si:
   - el identificador de acceso es el que había al pedir la descarga;
   - el titular vigente sigue siendo el de la identidad;
   - `subject.member_ref` y `scope.tenant_ref` son los suyos.

   Solo se reemplaza por una descarga con `downloaded_at` posterior.
3. **Descarte:**

   | Cuándo | Qué se borra |
   |---|---|
   | Cierre de sesión (`signedOut`) | Todo |
   | Cambio de titular | Todo, **dentro de la transacción de `changeOwner`** |
   | Otra identidad (cambio del estado de acceso) | Las filas que no son suyas |
   | 401 o 403 | Todo, y se vacía el token en memoria |
   | 409 `POLICY_PENDING` | Todo |
   | Perfil que no es FARMER | Todo, como permiso perdido |
   | 404 | La copia de esa campaña |

   En todos los casos se borra también el acceso, así que una respuesta que llegue después no se guarda. **La copia nunca se ofrece como alternativa a un rechazo.**
4. **Si el borrado falla.** SQLite no cambia nada, porque la transacción se deshace. La copia **deja de leerse durante esa ejecución de la app** y el aviso dice que «su borrado no se completó»: **no se afirma borrada**.
5. **Sin escrituras superfluas.** Sin copias ni acceso que borrar, ni el cierre de sesión ni el cambio de identidad abren una transacción.
6. **Fuera de Sync v1.** La outbox solo admite `CONSUMPTION_TOTAL` y `DECLARED_NEED`, por un CHECK del esquema. Guardar la copia no encola nada, y una prueba lo comprueba.
7. **Endpoint.** `ApiEndpointConfig` admite consulta (query) solo en `/api/v1/estimation/results` y `/download`, y allí exige exactamente `target_campaign_ref` con un UUID v4 en minúsculas. Toda otra ruta sigue sin consulta.

## 5. HOST

**Procedencia:** Windows 11 Home 10.0.26200, Flutter 3.47.2 y `sqflite_common_ffi`.

```text
flutter analyze                    → No issues found!
flutter test (toda la suite)       → 2228 pruebas, 2228 success (00:31:26Z–00:33:39Z del 2026-11-03)
  nuevas: f12_est_07_estimation_copy_test.dart (16), _service_test.dart (16), _ui_test.dart (4)
  (después, una prueba más en _copy_test: 17; ver §8 y la suite final de §5)
```

**Respaldo y restauración (HOST):**
- **El respaldo no contiene la copia.**
  - El teléfono de origen tiene 2 copias y operaciones confirmadas: 2 compras y 1 aplicación.
  - En el `.agrobackup` exportado, `database.db` tiene `estimation_copies` y `estimation_copy_access` **vacías**.
  - Sus bytes no contienen el nombre del producto ni la referencia de la campaña de la copia: se borran de la base empaquetada y se compacta con `VACUUM`.
  - El resto de las tablas es **idéntico** al origen.
  - La base del teléfono de origen **conserva** su copia: solo se excluye del respaldo.
- **Restaurar no trae copia:**
  - en otro teléfono que tenía su propia copia, quedan 0 copias y **todas** las demás tablas idénticas al origen; la pantalla muestra «sin copia descargada»;
  - un archivo de base que sí contiene una copia (formato histórico) también se restaura sin ella;
  - una descarga pedida antes de restaurar no se guarda en la base restaurada.

**Fallos conservados de esta sesión (HOST):**
- **Primera suite: 6 de 2192 no pasaron.**
  - La aserción fija del esquema 12 (`rec_039`): se actualizó a 13.
  - Un `setState` de flecha que devolvía un `Future` (`set_state_contract_test`): se corrigió.
  - La salida de una sesión ajena escribía una fila de acceso en una base sin copias (`f03_access_recovery_app_test`): ahora no se escribe nada si no hay nada que borrar.
  - `f04_admin_owner_restore_ui_test` falló en esa ejecución: pasó solo y en la suite siguiente.
  - Dos pruebas de `f10_x01_aplicacion_productos_test`: un tiempo agotado y un error del arnés en la prueba siguiente.
- **Segunda suite, detenida:** se agotó el tiempo en `f04_effective_date_form_test`, con el aviso «database has been locked».
  - **Causa:** el guardián de la copia abría una transacción en cada cambio del estado de acceso, también en pruebas de pantalla con tiempo simulado.
  - **Corrección:** el guardián y el descarte primero leen si hay algo que borrar; sin nada, no abren ninguna transacción.
- **Tercera suite:** 2228/2228.
- **Suite final sobre `1c97b40`**, con la prueba añadida en §8: **2229/2229**, de 00:48:59Z a 00:51:39Z del 2026-11-03. `flutter analyze`: «No issues found!».

## 6. DEVICE

| Campo | Valor |
|---|---|
| Teléfono | Xiaomi 22101320G (POCO X5 Pro 5G), Android 12, arm64-v8a, 1080×2400 |
| App | **Aislada:** paquete `com.comunidad.agro.agroquimicos.est164`, compilación debug con un sufijo temporal en `build.gradle.kts` que se revierte al terminar. Se **desinstaló** al terminar (0 paquetes `.est164` después) |
| Otras instalaciones del teléfono | **No se tocaron:** la app normal y las de otros ensayos siguen igual |
| Ajuste del teléfono | `stay_on_while_plugged_in` se fijó en 3 durante el ensayo y se restauró a su valor previo |
| Servidor | **SIMULADO** en este ensayo: un transporte HTTP de prueba con respuestas de la forma INT-09 v1. El ensayo contra el Backend **real** está en §11 |
| Ejecución | `flutter test integration_test/f12_est_07_estimation_device_test.dart -d cc14247a`. Primera vez sobre `398db76` (00:34:02Z–00:39:13Z, 5/5). **Repetida sobre `3c2446e`** (`lib/` = `5594599`, con la retirada persistente) de 01:58:27Z a 02:01:38Z: **5/5**. Las capturas y `version.txt` de `f12_est_07_mob/` son las de esta repetición |
| Resultado | **5/5** («All tests passed!») en las dos |

**Qué se ejercitó en el teléfono real:** el SQLite de Android, los archivos de la app, el respaldo `.agrobackup` y la restauración, y la pantalla.

| Prueba | Comprobado | Captura |
|---|---|---|
| Sin conexión, con copia | «111 L (111.000 mL)», «Sin cifra» con el motivo, las fechas, la vigencia al descargar y la actual desconocida, y el aviso | `f12_est_07_mob/01`, `02` |
| Sin copia | «Sin copia descargada» y ninguna cifra | `03` |
| Con conexión (simulada) | Consulta FARMER sin naive. Descarga explícita: «Copia guardada en este teléfono.», con 1 fila en SQLite | `04`, `05` |
| 409 de política | Aviso; sin cifras ni copia; 0 filas | `06` |
| Respaldo y restauración en el teléfono | El `.agrobackup` (9154 bytes) no tiene filas ni bytes de la copia. Tras restaurar no hay copia y las 6 tablas de operaciones (personas, compras, líneas, lotes, movimientos y vínculos) son **idénticas** al origen. La pantalla muestra «sin copia descargada» | `07` |

Las capturas se recortaron para quitar la barra de estado del teléfono, que mostraba notificaciones personales.

**Lo que no se ejercitó en DEVICE:**
- el recorrido con backend real;
- la activación;
- la sesión V2 real;
- el cierre de sesión desde la pantalla de acceso.

## 7. EMULADOR

**No ejecutado.** Existe el AVD `Pixel_8`, pero no se arrancó: el teléfono físico estaba disponible y cubre Android real. Nada de este documento se declara ejecutado en un emulador.

## 8. Alteraciones de las reglas

Las alteraciones se hicieron una por caso sobre `398db76` y se restauraron después. Cada una ejecutó las tres pruebas nuevas, de 00:39:40Z a 00:46:17Z del 2026-11-03.

**Fallan 22 de las 22 alteraciones válidas:**
- **Lectura:**
  - sin identidad se leen todas las copias;
  - la lectura no exige el titular;
  - la lectura no comprueba el JSON de la fila.
- **Guardado:**
  - no comprueba el acceso;
  - no comprueba el titular vigente;
  - acepta otro Member;
  - reemplaza por una más antigua.
- **Invalidación:**
  - un 404 no invalida el acceso;
  - descartar no borra el acceso;
  - cambiar de titular no descarta;
  - un rechazo no borra;
  - un rechazo deja el token en memoria;
  - cerrar la sesión no descarta;
  - una reautenticación se trata como falta de conexión;
  - un fallo al borrar no bloquea la lectura.
- **Respaldo:**
  - incluye la copia;
  - no compacta con `VACUUM`, y quedan los bytes de la copia;
  - la restauración trae la copia.
- **Endpoint:** cualquier consulta se admite en las rutas de la estimación.
- **Formato:**
  - se admite el perfil institucional;
  - se admiten claves de más (naive, cobertura);
  - una ausencia se muestra como cero.

**Dos resultados conservados:**
- **«Guardar no comprueba el titular vigente» sobrevivía en la primera pasada.** El cambio de titular de las pruebas pasaba por `changeOwner`, que ya borra el acceso, y además la primera alteración estaba mal construida (`false && a || b…` seguía comprobando). Se añadió la prueba «si el titular vigente ya no es el de la descarga, no se guarda aunque el acceso siga», con el vínculo cambiado por otra vía, y se rehízo la alteración: ahora falla.
- **«Sin identidad se consulta igual» no compila:** la identidad pasaría a ser anulable. No es una alteración válida y no se cuenta.

**Segunda tanda, sobre la retirada persistente** (`3c2446e`, de 02:04:09Z a 02:09:30Z del 2026-11-03, con las cuatro suites de #164): **fallan 14 de 16**.
- **Las que fallan:**
  - lectura sin el contexto vigente, sin comprobar la retirada, y sin renovar el contexto al retirar todo;
  - una campaña retirada sin subir la generación;
  - guardar ignorando la retirada o el contexto de la petición;
  - la marca pendiente sin consultar, o una marca ilegible tratada como admisible;
  - no dejar la marca si SQLite no retira;
  - un rechazo o un 404 que solo borran, sin registrar la retirada;
  - cerrar la sesión sin retirar;
  - el respaldo con la copia y la restauración que la trae.
- **Las dos que sobrevivían:**
  - una generación posterior a la del contexto, en un registro manipulado;
  - las retiradas, que no se borraban del respaldo.

  Se añadieron sus pruebas (`095684e`) y ahora **fallan las dos**.

## 9. Límites que permanecen

- **El titular, no la persona.** La copia se lee con la sesión del titular vigente en la instalación. Quien use el teléfono con esa sesión puede leerla; no se añadieron PIN ni contraseñas.
- **Revocaciones sin conexión.** Sin conexión no se conocen revocaciones ni cambios de política o de fuentes. La invalidación llega con la siguiente consulta con conexión, o con el cierre de sesión o el cambio de titular en el teléfono.
- **Un borrado fallido** ya no reactiva la copia: la retirada persiste aparte (§10). Solo si fallan a la vez SQLite y el almacenamiento seguro, la lectura queda bloqueada únicamente durante esa ejecución.
- **Fallos de almacenamiento** solo se inyectaron en HOST. En el teléfono, los borrados se completaron.
- **El Central del ensayo real** era propio, desechable y sintético. No se probó contra un Central de pilotos ni con datos reales.
- **Cierre de sesión.** Hoy, la única salida de sesión de la app es la de una sesión ajena (F03). La regla `discard_on: SIGN_OUT` se aplica allí y al perder la identidad.
- **Documentación del servicio.** `F12_EST_07_COPIA_MOBILE.md` del servicio se actualiza tras integrar, en un PR documental aparte.

## 10. Retirada persistente (2026-11-03)

**Qué estaba mal en `267592a`.** `discardAll` y `discardCampaign` borraban la copia y el acceso en la misma transacción. Si el borrado fallaba, los dos quedaban, y tras cerrar y volver a abrir la app la copia se leía otra vez, porque la identidad coincidía. Era el límite declarado en §9.

### 10.1 Reproducción antes de corregir (HOST, fallos inyectados)

`test/f12_est_07_estimation_restart_test.dart` se escribió antes de tocar el código y se ejecutó sobre `267592a` (2026-11-03 01:26:55Z): **fallan 5 de 5**. Están en `f12_est_07_mob/reproduccion-reinicio-267592a.txt`, con la prueba y la salida.

**Cómo se simula el arranque nuevo:** otro `ProviderContainer` y otra instancia de `AppDatabase` sobre el mismo archivo, sin proveedores ni variables en memoria.

**Fallos inyectados:** disparadores de SQLite que abortan la escritura. Ninguno se ejercitó en el teléfono.

En los cinco casos, la copia se lee tras reiniciar sin conexión:
- **Rechazo 409** con el borrado fallido: las dos copias.
- **404 de verano** con el borrado fallido: también verano.
- **Respuesta pedida antes del rechazo** y respondida después.
- **Reintento de limpieza:** la copia no se borra, porque ya no se sabe que estaba retirada.
- **SQLite tampoco admite registrar la retirada.**

### 10.2 Corrección (`c127c45`)

| Pieza | Qué hace |
|---|---|
| Contexto local persistente | `estimation_copy_access`, con `context_id` aleatorio y generación. Sin él no se lee ninguna copia |
| Retiradas por campaña | `estimation_copy_retirements`, por contexto y campaña, con la generación |
| Copia | Guarda el contexto y la generación **de cuando se pidió** |
| Lectura | Exige el contexto vigente y que la campaña no se retirara después de pedirla (generación de la copia mayor que la de la retirada), además de la identidad y el titular |
| Retirada (`retireAll`, `retireCampaign`) | Escritura pequeña, **primero y aparte**. Cerrar la sesión, un 401, 403 o 409, o un perfil que no es FARMER renuevan el contexto; un 404 registra la retirada de la campaña y sube la generación |
| Borrado físico (`purge`) | **Después**. Si falla, queda pendiente: la copia no se lee, tampoco tras reiniciar, y el siguiente intento la borra |
| Marca persistente | Si SQLite no admite ni la retirada, se deja `retirement_pending` en el almacenamiento seguro del teléfono (el mismo mecanismo que la sesión y el llavero del respaldo; sin identificadores ni credenciales). Mientras exista, no hay contexto admisible: no se muestran cifras ni se guarda nada. El siguiente arranque completa la retirada y la quita |
| Sin contexto admisible | Si la marca no se puede leer, no se muestra ninguna cifra |
| Doble fallo | Si no se pueden registrar ni la retirada ni la marca, la lectura queda bloqueada en esa ejecución. Es el único caso sin persistencia, porque fallan los dos almacenes |
| Respuestas | Una respuesta o escritura anterior a la retirada se rechaza (`accessChanged` o `targetRetired`) o no se lee. Solo una descarga **posterior** autorizada vuelve a valer |

**Lo que no cambia:**
- no se añaden PIN ni contraseñas;
- la recuperación de acceso de F03 (`access_recovery.dart`) no se toca;
- la retirada por cambio de titular sigue dentro de la transacción de `changeOwner`.

**Esquema.** Sigue siendo el 13, aditivo e idempotente, ahora con tres tablas. Se ajustó antes de integrarse: ninguna instalación tenía el 13 anterior, porque las apps de ensayo se desinstalaron.

### 10.3 Pruebas de la corrección (HOST)

- **`f12_est_07_estimation_restart_test.dart`** (7): los 5 casos de §10.1, ahora en verde, más estos dos:
  - con el almacén seguro ilegible no hay contexto admisible: ni cifras ni descarga;
  - si no se pueden registrar la retirada ni la marca, la lectura queda bloqueada en esa ejecución.

  En cada caso se comprueba que **la fila sigue** (solo se impidió el acceso) y, cuando el almacenamiento vuelve, que el siguiente arranque la borra y una descarga autorizada se lee.
- **Pruebas anteriores adaptadas a `retire*` y `purge`:** retirar no borra y la fila sigue hasta purgar. Se conservan las de exclusión del respaldo, restauración sin copia y conservación de las operaciones agrícolas.
- **Suites:** sobre `c127c45`, 2236/2236. La suite final está en §12.

## 11. Android contra el Backend REAL (DEVICE, 2026-11-03)

| Campo | Valor |
|---|---|
| Teléfono | Xiaomi 22101320G (POCO X5 Pro 5G), Android 12 |
| App | Aislada `com.comunidad.agro.agroquimicos.est164` («AC EST164»), profile arm64. Se **desinstaló** al terminar; los demás paquetes no se tocaron (20 antes y 20 después) |
| Servidor | **Real:** Backend-Web `main` `635cc8f` (`dist` compilado del worktree `F12-EST-07`, árbol idéntico). Central **propio y desechable** (`tool/f12_est_07/est164_supervisor.sh`): PostgreSQL 16.13 `--rm` sin volumen, base sintética del control de F12-EST-07 y trabajador real. Sin pilotos ni datos reales |
| HTTPS | Túnel temporal de Cloudflare (`cloudflared` 2026.10.0) hacia el observador → API. Autorizado por Roderich para este ensayo. Se cerró al terminar y el contenedor se eliminó |
| Secretos | JWT, huella y contraseñas solo en la memoria del supervisor. La contraseña del Agricultor sintético es de un solo uso y solo se teclea si el campo enfocado es de contraseña; no se muestra ni se guarda. **No se creó PIN**: se eligió «Ahora no» |
| Observador | `f12_est_07_mob/real/requests.log`: hora, método, ruta y estado, sin cuerpos ni cabeceras |

**Recorrido** (capturas `f12_est_07_mob/real/r01`–`r10`):

| Paso | Resultado | APK |
|---|---|---|
| Activación con la identidad sintética | `POST /auth/v2/login` 200, `/auth/clients` 201, `/auth/v2/session/client` 201, `/auth/v2/me` 200; titular «Titular sintetico EST164», compartida | `c127c45` |
| Consulta real de `/results` | **200**, perfil FARMER: «Herbicida de ensayo», «Estimado», «111 L (111.000 mL)», «Vigencia: Vigente» (`r02`) | `c127c45` |
| Descarga real de `/download` | **200** para invierno y verano | `c127c45` |
| Lo que llegó al teléfono | El JSON guardado en SQLite (copiado con `run-as`): perfil `FARMER`, `subject.role` `AGRICULTOR`; **sin** `naive_base`, `coverage`, `points`, `series` ni `alpha`; outbox de Sync v1 con 0 filas | `c127c45` |
| Producto sin datos suficientes | Verano: «Datos insuficientes» con su motivo y «Sin cifra» (`r03`) | `c127c45` |
| Defecto visual visto aquí | El título «Copia descargada en este teléfono» se solapaba con el selector. Se corrigió en `5594599`, se recompiló con el mismo origen y se reinstaló con `-r` (conserva sesión y datos). Lo siguiente es todo con la APK final | — |
| Modo avión, cierre y reapertura | Sin red real (`ping`: «Network is unreachable», «Wi-Fi is disabled»). Tras `force-stop` y abrir: verano con «Sin cifra» e invierno con «111 L (111.000 mL)», cada uno con su fecha de descarga, la vigencia al descargar y la actual desconocida (`r04`–`r06`) | `5594599` |
| **404 real** | La campaña de invierno pasa al sindicato B en el Central. La app la tenía en la lista y al elegirla, `/results` **404**: «Esa campaña no existe o no es de su sindicato. Su copia descargada se borró.» Queda solo verano (`r07`) | `5594599` |
| **409 real** | El supervisor reinicia la API sin modo provisional y `/results` da **409** `POLICY_PENDING`. Sin cifras: «La copia descargada se borró.» (`r08`) | `5594599` |
| Persistencia tras reiniciar | `force-stop`, modo avión y reapertura: **«Sin copia descargada»**. En la base: 0 copias, contexto renovado y 0 retiradas pendientes (`r09`) | `5594599` |
| Nueva descarga autorizada | Con la API de nuevo en modo provisional: `/results` 200 y `/download` 200. Tras `force-stop`, modo avión y reapertura, la copia se lee (`r10`); en la base, 1 copia FARMER sin naive, cobertura ni serie | `5594599` |

**Peticiones vistas por el observador** (01:39Z–01:55Z):

| Petición | Respuestas |
|---|---|
| `/auth/v2/login` | 1 × 200 |
| `/auth/clients` | 1 × 201 |
| `/auth/v2/session/client` | 1 × 201 |
| `/auth/v2/me` | 1 × 200 |
| `/auth/v2/refresh` | 3 × 200 |
| `/sync/v1/references` | 4 × 200 |
| `/estimation/results` | 3 × 200, 1 × 404, 1 × 409 |
| `/estimation/download` | 3 × 200 |

**Real o inyectado:** en este recorrido todo es del servidor real, también los rechazos. **No** se inyectó ningún fallo de SQLite en el teléfono: el borrado tras el 404 y el 409 se completó, y la persistencia ante un borrado fallido se prueba en HOST (§10).

**Además, en el teléfono, con servidor SIMULADO** (`integration_test`, §6), sobre `3c2446e`, cuyo `lib/` es idéntico a `5594599`: **5/5**, de 01:58:27Z a 02:01:38Z.
- Pasa el respaldo `.agrobackup` en Android, sin filas ni bytes de la copia; tras restaurar no queda copia y las operaciones son idénticas.
- En el primer intento, MIUI negó la instalación (`INSTALL_FAILED_USER_RESTRICTED`, «Instalar vía USB» sin confirmar). El guion ahora pulsa «Instalar» solo en ese diálogo del sistema.

## 12. Versiones probadas

| Prueba | Commit de código (`lib/`) | Artefacto |
|---|---|---|
| Reproducción del defecto (HOST) | `267592a` | — |
| Corrección y suites (HOST) | `c127c45` | — |
| Activación, primera consulta y primeras descargas (DEVICE, servidor real) | `c127c45` | APK profile arm64 SHA-256 `281117cb2ffaa6db043e5e10d147ff12ef68a5e38d28c8411c25d49c062928cd` |
| Lectura en avión, 404, 409, persistencia y nueva descarga (DEVICE, servidor real) | `5594599` | APK profile arm64 SHA-256 `9fab4a7ac81047885bed4814c70e8e40db09f8fc794d221ffde9b46e43a67e5d` |
| `integration_test` en el teléfono (servidor simulado) | `3c2446e` (`lib/` = `5594599`) | APK debug que compila `flutter test` |
| Suite HOST final y alteraciones | `095684e`: **2237/2237** (02:11:31Z–02:13:41Z), `analyze` sin incidencias | — |
| HEAD del PR | El commit de evidencia publicado sobre `095684e` | Solo añade documentación y herramientas sobre `3c2446e`; ningún cambio en `lib/` después de `5594599` |

**Diferencias entre commits:**
- **De `c127c45` a `5594599`:** solo el espacio entre el título y el selector de la copia, que es un cambio visual. Aun así, todo lo que dependía de la pantalla se **repitió** con la APK de `5594599`: lectura en avión, 404, 409, persistencia y nueva descarga.
- **Lo hecho con la APK de `c127c45`:** la activación, la consulta y las descargas; no dependen de ese espacio.
- **`3c2446e`:** solo cambia el guion del teléfono.
- **La suite HOST final** se ejecutó sobre el código final.
