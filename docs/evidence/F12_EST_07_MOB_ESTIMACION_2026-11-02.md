# F12-EST-07-MOB — Consulta y copia descargada de la estimación (MOB #164)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-02 y 2026-11-03 (UTC) |
| Rama | `feat/f12-est-07-mob-copia` |
| Base | Mobile `main` `4ca2088`. Servicio: Backend-Web `main` `635cc8f` (#195, con `GET /estimation/download`) |
| Código verificado | `398db76` (implementación; DEVICE y alteraciones) y `1c97b40` (una prueba más; suite HOST final) |
| Issue | Refs #164. **No se cierra** |
| Origen | Implementación nueva. Solo datos sintéticos |
| Contrato | Backend-Web `docs/architecture/F12_EST_07_COPIA_MOBILE.md` y `F12_EST_01_ESTIMATION_CONTRACT.md` §9 (INT-09 v1). Si discrepan con el prototipo, **gana el contrato** |
| Procedencia | **HOST** (§5) y **DEVICE** (§6). **EMULADOR: no ejecutado** |

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
| App | **Aislada:** paquete `com.comunidad.agro.agroquimicos.est164`, compilación debug de `398db76` con un sufijo temporal en `build.gradle.kts` que se revierte al terminar. Se **desinstaló** al terminar (0 paquetes `.est164` después) |
| Otras instalaciones del teléfono | **No se tocaron:** la app normal y las de otros ensayos siguen igual |
| Ajuste del teléfono | `stay_on_while_plugged_in` se fijó en 3 durante el ensayo y se restauró a su valor previo |
| Servidor | **SIMULADO:** un transporte HTTP de prueba con respuestas de la forma INT-09 v1. **No se usó un backend real.** La app exige HTTPS y el túnel temporal no está autorizado; no se buscó otra vía |
| Ejecución | `flutter test integration_test/f12_est_07_estimation_device_test.dart -d cc14247a`, de 00:34:02Z a 00:39:13Z del 2026-11-03 |
| Resultado | **5/5** («All tests passed!») |

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

## 9. Límites que permanecen

- **Sin backend real en Android.** Contra el servicio real, la descarga y los perfiles están probados en Backend-Web (PostgreSQL y recorrido de la PWA). En el teléfono, las respuestas fueron simuladas.
- **El titular, no la persona.** La copia se lee con la sesión del titular vigente en la instalación. Quien use el teléfono con esa sesión puede leerla; no se añadieron PIN ni contraseñas.
- **Revocaciones sin conexión.** Sin conexión no se conocen revocaciones ni cambios de política o de fuentes. La invalidación llega con la siguiente consulta con conexión, o con el cierre de sesión o el cambio de titular en el teléfono.
- **Un borrado fallido** deja la copia ilegible solo durante esa ejecución de la app. Si SQLite no puede escribir, tampoco puede registrar la retirada; tras reiniciar, la copia se descarta en la siguiente invalidación. Es el mismo almacenamiento que sostiene todas las operaciones.
- **Cierre de sesión.** Hoy, la única salida de sesión de la app es la de una sesión ajena (F03). La regla `discard_on: SIGN_OUT` se aplica allí y al perder la identidad.
- **Documentación del servicio.** `F12_EST_07_COPIA_MOBILE.md` del servicio sigue diciendo «no implementado». Se actualizará cuando este PR se integre.
