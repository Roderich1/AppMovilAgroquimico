# Rediseño móvil · integración de las sesiones A, B, C y F — evidencia

- **Fecha real:** 2026-11-12 (UTC−4), tarde y noche.
- **Rama / worktree:** `feat/rediseno-movil` en `_wt/RDM-MOB` (rama de integración). Sin push.
- **Commits verificados:** `6b397c9` (suite completa; APK de `e01`–`e24` y `f01`–`f13`) y **`d6c4c4d`** (corrige el defecto de Actividad hallado en el recorrido; pruebas focalizadas; APK de `f14`–`f17`, **la instalada para la revisión**). Entre `6b397c9` y `06d805e` sólo cambió documentación. Coordinación y entregas integradas: `docs/rediseno/COORDINACION.md`.
- **Dispositivo:** emulador **propio** `RDM_Pixel8` (`emulator-5556`, imagen `android-36.1 google_apis_playstore_ps16k x86_64`, datos de 8 GB, arrancado **sin audio**), creado el 2026-11-12 para no depender del espacio del `Pixel_8` compartido. El POCO no estaba disponible.
- **Back:** worktree congelado propio `_wt/RDM-BE` en `5b394f2` (contrato de convocatorias 2 y migración P-C de la rama F), `npm ci` + `prisma generate` + `nest build`; migraciones aplicadas con `prisma migrate deploy` (bootstrap) en el contenedor propio `agro_rdm_pg`; API 3370; túnel temporal (origen no publicado), **cerrado** al terminar.
- **Datos:** exclusivamente sintéticos (cuenta `agricultor15`, «Rosa Vargas (sintética)»). No se tocó la DEMO (`.demo`), ni `.et1`/`.et1o`, ni el `Pixel_8` compartido.

## Pruebas

| Qué | Comando | Resultado |
|---|---|---|
| Análisis | `flutter analyze` | sin avisos |
| Suite completa sobre `e6d72b3` | `flutter test --concurrency=4` | 3042 pasan, 3 omitidas, 0 fallan (05:35) |
| Suite completa sobre `6b397c9` | `flutter test --concurrency=4` | **3044 pasan, 3 omitidas, 0 fallan** (06:34) |
| Focalizadas sobre `d6c4c4d` (Actividad, Almacén, «+ Registrar»; 19 archivos) | `flutter test --concurrency=4 …` | 159 pasan, 0 fallan |
| Focalizadas de P-A tras fusionar (`91f2e73`) | e2_*, migration, rec_039, reportes | 177 pasan, 0 fallan |
| Suite completa sobre `91f2e73` (con P-A, esquema v19) | `flutter test --concurrency=4` | **3055 pasan, 3 omitidas, 0 fallan** (07:08) |
| Focalizadas sobre `9264191` (FAB y convocatorias; 15 archivos) | `flutter test --concurrency=4 …` | 184 pasan, 0 fallan |
| Suite completa sobre `79de523` (mismo código que `9264191`; después sólo `docs/`) | `flutter test --concurrency=4` | **3055 pasan, 3 omitidas, 0 fallan** (07:11) |
| Pruebas focalizadas tras cada fusión | ver `COORDINACION.md` | verdes |

## APK

- `rdm_env.sh build-app` sobre `6b397c9` (árbol limpio): APK profile x86_64 `com.comunidad.agro.agroquimicos.rdm` («AC RDM»), SHA-256 `8dec42ebc6bc63c51fad8a967bd803b1c8f16aedcd72081bd267573e0822dfb0`, 376 MB (con los modelos de voz verificados el 2026-11-12).
- **Instalada en `emulator-5556`** como actualización de `c1e2639` (instalada primero, SHA-256 `5940c96a…5584`): `Success`; la activación, el titular y los datos se conservaron (`e09` en adelante tras actualizar).
- **Atada al túnel del 2026-11-12, ya cerrado:** funciona sin conexión; para sincronizar hay que abrir otro túnel y recompilar desde el mismo SHA.
- El `Pixel_8` compartido (`emulator-5554`) conserva una `.rdm` **antigua** (`2d6aa0d`, bloque 1); ese emulador terminó solo (código 139) tras el uso de la sesión F y no se volvió a arrancar. Ver «Pendiente».

## Recorrido real en el emulador (`e01`–`e24`)

1. Arranque sin activar (`e01`) → «Activar en línea» (`e02`): correo sintético tecleado; la contraseña de un solo uso la tecleó `demo-rica.cjs credential-adb` en el campo enfocado; la captura `e03` se tomó con el campo ya enmascarado (sin carácter visible).
2. Titular (`e04`–`e06`): «Crear el titular», «Rosa Vargas», compartido. **Hallazgo corregido** en `1a04963`: el texto decía «Operaciones › Más › Modo de uso» (camino de la barra antigua). PIN (`e07`): «Ahora no»; el mismo texto viejo, corregido.
3. Inicio vacío (`e08`) con la cabecera de B, «Sin campaña activa» y el engranaje.
4. Actualización a `6b397c9` sin perder datos. Campaña «Invierno 2026» creada desde el selector de campaña de Inicio (`e09`, diálogo con el estilo nuevo; `e10`, tarjeta oscura «Campaña actual»).
5. **Compra manual SIN CONEXIÓN** (`svc wifi disable` + `svc data disable`; `ping` sin respuesta): proveedor y producto creados desde los selectores (`e12`–`e15`); con el teclado abierto un toque fuera del precio cerró la hoja, Atrás ofreció «¿Descartar cambios?» y «Seguir editando» devolvió el borrador con la cantidad (`e16`–`e17`); 5 L × 80 Bs = **400,00 Bs** (`e18`); «Una persona» → Rosa Vargas; paso 2 sin respuesta de pago por defecto (`e19`); «Todavía no» y «Confirmar compra» (`e20`).
6. **Persistencia:** `am force-stop` y relanzar → Actividad muestra la compra, 400,00 Bs, «Sin pagar» (`e21`).
7. **Efectos en la base local** (copia de sólo lectura con `run-as`; esquema **18**): 1 compra `CONFIRMED`, `total_bob_minor` 40000; 1 línea 5000 unidades base × 8000 centavos; 1 asignación a la persona 1 (`BY_ACTUAL_USAGE`); **0** pagos al proveedor; 1 lote de 5 L; 1 movimiento de inventario; `sync_outbox` vacío (las compras no se envían al sindicato).
8. Red restaurada; Sindicato, Almacén, Personas y Actividad en el dispositivo (`e22`–`e24`, `e21`).

## Segundo recorrido (`f01`–`f17`, tarde del 2026-11-12)

Lecturas de la base antes y después de cada operación (copia de sólo lectura con `run-as`, esquema 18). Datos sintéticos: se añadieron Juan Mamani (familiar) y los chacos «Chaco Rio» (Juan, 2 ha) y «Chaco Norte» (Rosa, 3 ha) desde Ajustes › Datos.

| Recorrido | APK | Antes → después en la base |
|---|---|---|
| **Transferencia** Rosa → Juan, 2 L (`f01`, `f02`) | `6b397c9` | transfers 0→1 (2000 u., 16000 cent., `CONFIRMED`); lote hijo de 2 L para Juan con el mismo costo (8000/L); movimientos `TRANSFER_OUT −2000` y `TRANSFER_IN +2000`; **account_transactions 0→0** (el formulario avisa que no genera deuda) |
| **Plan** Chaco Rio, 0,5 L/ha × 2 ha (`f03`) | `6b397c9` | application_plans 0→1 `PLANNED`, ítem 1000 u. — **defecto**: Actividad seguía en «No hay planes pendientes» hasta cambiar de pestaña |
| **Aplicación desde el plan** (`f04`) | `6b397c9` | plan → `APPLIED`; aplicación `CONFIRMED` 8000 cent.; consumo de 1 L del lote de Juan; `APPLICATION_OUT −1000`; cargo `USAGE_CHARGE +8000` a Juan («Se cargará a Juan Mamani: 80,00 Bs») |
| **Pago** de Juan, 50 Bs de 80 (`f05`–`f07`) | `6b397c9` | `PAYMENT −5000`; payment_allocations 1 (5000 al cargo); provider_payments sin cambios (0); aviso «Imputado: Invierno 2026 50,00 Bs»; saldo 30,00 Bs |
| **Excel** «Resumen de campaña» (`f08`, `f09`) | `6b397c9` | archivo `.xlsx` en la carpeta de la app; leído fuera: 1 compra 400,00; 1 aplicación 80,00; 0 planes pendientes; deuda 30,00 (coincide con la base) |
| **PDF** «Estado de cuenta» de Juan (`f10`) | `6b397c9` | cargo 80,00, crédito 50,00, saldo 30,00 (coincide). Columnas truncadas con «…» en A4 vertical: maquetación del reporte, anterior al rediseño |
| **Borrador** de aplicación (`f11`–`f13`) | `6b397c9` | Atrás → «¿Descartar cambios?»; «Seguir editando» conserva; app al fondo y vuelta conserva; paso 2 → paso 1 → paso 2 conserva la mezcla; abrir y cerrar el panel de voz sin hablar no cambia nada; «Descartar cambios» sale y el formulario se reabre vacío; **la base no cambia** |
| **Corrección** (`f14`) | `d6c4c4d` | plan para Chaco Norte guardado desde «+ Registrar» aparece en Actividad en el acto |
| Almacén (`f15`) | `d6c4c4d` | 4 L, «Previsto en planes 1,5 L · quedarán 2,5 L», valor 320,00 Bs |
| Convocatorias sin servidor (`f16`, `f17`) | `d6c4c4d` | lista vacía con su explicación; «Actualizar» sin servidor → «El resultado remoto no puede confirmarse. No se reutilizará la credencial anterior…» e Inicio ofrece «Volver a autenticar». Comportamiento previsto ante un resultado indeterminado; los datos locales no cambian. Al reconectar habrá que volver a autenticar |

**APK instalada para la revisión:** `d6c4c4d`, SHA-256 `392f2f1e19ae2c39d9fa7d1eda1ff9a64d40e2d923e44c07a1aab9f366c791d7`, actualización sobre `6b397c9` (`Success`; todos los conteos iguales antes y después). Compilada **sin túnel** (origen `https://sin-tunel.invalid`): no llega a ningún servidor.

### Bloqueo de entorno

Abrir el túnel HTTPS temporal (`rdm_env.sh tunnel`) fue **denegado** por los permisos de esta sesión (exposición externa). La app sólo acepta un origen HTTPS compilado, así que sin túnel no se pudo recorrer en el teléfono: participación en convocatorias y sus estados de envío con servidor, publicación de consumo y necesidad, vínculos, reautenticación. Esas funciones tienen cobertura automática y capturas del arnés; el recorrido queda pendiente de que el autor abra el túnel o autorice abrirlo.

**Sincronización, separada:** (1) persistencia local: verificada arriba; (2) publicación autorizada: `sync_outbox` siguió vacío durante todo el recorrido, porque compras, transferencias, aplicaciones y pagos privados no se envían al sindicato y no se publicó consumo; (3) recepción del servidor: no verificable sin túnel.

## Tercer recorrido: candidata `91f2e73` con P-A, conectada (`g01`–`g11`, noche del 2026-11-12)

Autorizado por el autor el 2026-11-12 (actualizar la candidata conservando datos, túnel temporal, cerrar el `Pixel_8` bloqueado).

**Antes de instalar.** Entre `91f2e73` y `9717983` sólo cambia documentación (5 archivos en `docs/`). Instalada: `.rdm` «AC RDM» en `emulator-5556`, APK `d6c4c4d` (SHA-256 `392f2f1e…91d7`), conservada como `agrocuentas.rdm-d6c4c4d-profile-x64.apk`. Copia de **inspección** de la base (sólo lectura, `run-as`; no es un respaldo restaurable probado): esquema 18, persons 2, farms 2, purchases 1, application_plans 2, applications 1, transfers 1, inventory_lots 2, inventory_movements 4, account_transactions 2, payment_allocations 1, sync_outbox 0.

**Back aislado.** `_wt/RDM-BE` pasó de `5b394f2` a `49ed870` (P-A): volcado previo `agro_demo_antes_49ed870.dump` (en la carpeta del entorno, no versionado); `prisma generate` y `nest build` con la API parada; la migración `20261112180000_e2_pa_responsible_substitution` se aplicó (23 migraciones, ninguna fallida); conteos iguales (17 usuarios, 12 campañas, 11 productos, 0 convocatorias); API 3370 health 200.

**APK instalada.** Compilada con el árbol en `91f2e73` (limpio, el commit de la suite 3055/3/0), origen = túnel temporal (no se publica). SHA-256 **`6e82fd2b969caa66360ffad0f85a4256275dc3d9aa4824807e61b1c2dbeeda88`**, igual en el archivo compilado y en el `base.apk` del dispositivo; `lastUpdateTime=2026-11-12 17:53:29` (`firstInstallTime` 13:11:32: misma instalación, actualizada). Conservada como `agrocuentas.rdm-91f2e73-profile-x64.apk`. El texto del commit no es legible dentro de `libapp.so` (AOT); la procedencia se apoya en el árbol al compilar y el SHA-256.

**Migración y datos.** Tras abrir: esquema **19** (columnas `responsible_version` y `authorize_responsible`), todos los conteos iguales a la copia previa; Inicio sin pedir activación; Actividad y Almacén con los mismos datos. «Volver a autenticar» con la cuenta sintética (contraseña de un solo uso tecleada por `rdm_env.sh credential`, sin capturas ni volcados mientras estaba en pantalla): correcto.

**P-A, lista del autor** (salidas de la API en `pa_api.txt`):

| | Resultado |
|---|---|
| a. Sustitución por persona autorizada | 200, versión 1 → 2, «Sucesora PA», sigue OPEN |
| b. Autosustitución | 422 `SUCCESSOR_NOT_ELIGIBLE`, versión sigue en 1 |
| c. Delegaciones suspendidas | eventos `SUSPENDED:PARTICIPANTS` y `SUSPENDED:MANAGE`; la sucesora tiene 2 delegaciones por revisar |
| d. Datos restringidos hasta autorizar | la sucesora ve 0 participantes y 3 pendientes; el teléfono muestra «La persona responsable … cambió» y «Revisar autorización» (`g05`) |
| e. Autorizar ≠ cantidades | Modificar 10 → 12 KG no autoriza (versión autorizada 1, la tarjeta sigue: `g06`); autorizar (`g07`) deja 12 KG y pasa a versión 2; «Su última decisión … está aplicada en el sindicato» (`g08`) |
| f. Convocatoria cerrada | sustitución con la convocatoria CLOSED; autorizar desde el teléfono (`g09`, `g10`) no la reabre; consolidado guardado 4 L / 1 participante; respuesta del consolidado idéntica a la del cierre (huellas `e3212a90…`, `f9e9c5db…`) |

**g. App anterior (contrato 2)** — recorrida por la **sesión F** en su entorno (Pixel_8, API 3350, Back `49ed870`; APK de `e1f6e25`, SHA-256 `229a002f…80c0`), **no** por el orquestador. Según su evidencia (`_wt/ET2-BE`, commit `361416a`, `docs/evidence/E2_PA_SUSTITUCION_2026-11-12.md` §7.3 y `docs/evidence/e2_pa_2026-11-12/emu_app_anterior/`): lista y participa (5 L); tras la sustitución muestra «Responsable: Sucesora PA» pero su texto dice que la sucesora «puede ver su nombre y sus cantidades», **más permisivo que lo real** (el servidor le muestra 0 participantes y el total RESTRICTED); «Modificar» a 7 L: PUT 200 y la autorización sigue en la versión 1; «Autorizar también»: 409 `AUTHORIZATION_REQUIRED`, sin reintentos, con «no aplicó su última decisión… Rige lo que se indica arriba», sin cambios en el servidor. Conclusión de F: la app anterior no expone datos, pero no puede autorizar a la sucesora y su texto informa de más; hay que actualizarla.

**Defecto hallado:** en Convocatorias y su detalle, el «+ Registrar» del shell tapaba «Continuar» de la hoja de cantidades (`g02`). Corregido en la rama (`9264191`, regresión en `oe3_fab_sincronizacion_test.dart`); **no** está en la APK instalada.

## Candidata `d9893bc` (noche del 2026-11-12, `h02`–`h05`)

Autorizado por el autor en esta sesión: instalar la candidata con `9264191` y, antes, (b) «¿De quién son los productos?» y (c) «sólo la persona titular puede aprobar».

- **Código:** `d9893bc` = `79de523` (suite completa 3055/3/0, código de `9264191`) + `d9893bc` (sólo rótulos de (b) y (c) y las pruebas que buscaban el selector por «Persona»). Pruebas focalizadas tras (b)/(c): 49/0 + 2/0 (`rdm_textos_autor_test.dart`); análisis sin avisos. Sin suite completa sobre `d9893bc` (cambio de rótulos; decisión del autor de no repetirla si el código es el mismo — aquí no es idéntico, se declara).
- **Túnel:** el temporal anterior murió en el corte de internet (Cloudflare: «Tunnel not found»); se cerró y se abrió otro.
- **APK:** compilada con el árbol limpio en `d9893bc`; SHA-256 **`3630ff1d11948008b1682f5fdc0619cf09fbb0b7d3de9412bc15f27466270b65`**, igual en el archivo y en el `base.apk` del dispositivo; `lastUpdateTime=2026-11-12 20:12:54` (misma instalación, `firstInstallTime` 13:11:32). Conservada como `agrocuentas.rdm-d9893bc-profile-x64.apk`; las anteriores (`d6c4c4d`, `91f2e73`) siguen guardadas.
- **Datos:** esquema 19 y conteos idénticos antes y después de instalar y tras reiniciar el emulador (incluidas 2 convocatorias, 3 operaciones de participación y 2 de consentimiento).
- **Emulador sin DNS tras el corte:** resolvía nada (llegaba por IP). Se reinició `RDM_Pixel8` (sin wipe) con `-dns-server 8.8.8.8,1.1.1.1`; la app se cerró con `am force-stop` (sin borrar datos) para salir del estado «resultado remoto sin confirmar» que la instantánea había conservado; se volvió a autenticar con la cuenta sintética.
- **Convocatorias → hoja de cantidades:** sin «+ Registrar» en la lista, el detalle ni la hoja (`h02`, `h03`); con el teclado abierto «Continuar» queda entero sobre el teclado (`h04`); Atrás (oculta el teclado y luego cierra) y «Cerrar» cierran la hoja sin enviar (servidor 8000/12000/12000, 3 operaciones en el teléfono; al reabrir muestra lo del sindicato).
- **Almacén ancho (d):** capturas del arnés sobre la rama a 900 y 1280 dp con nombres largos, L y KG, vencimientos, previsto y avisos (`almacen_ancho_w900.png`, `almacen_ancho_w1280.png`, búsqueda vacía `almacen_ancho_busqueda_*`): conserva búsqueda, actualizar, avisos, estimación, cantidades con unidad, valor y etiquetas; filas a todo el ancho; el «+ Registrar» tapa la existencia del último producto con la lista arriba (solicitud 2 de B; **corregido en `fc12123`**, ver abajo). Aceptación visual pendiente del autor.
- **Abierta en Inicio** al terminar (`h05`), con el túnel abierto.

## Candidata `fc12123` (noche del 2026-11-12, `j01`–`j06`)

Encargo del autor: «+ Registrar» no debe tapar la cantidad ni las acciones del último producto; corregir el espacio de la lista sin ocultar información ni retirar la acción; mejorar la distribución ancha sin restaurar la tabla.

- **Causa:** el botón flotante del shell se dibuja encima del contenido y su espacio sólo se reservaba como relleno al **final** de cada página (`ContentInsets`, 24 + 88). Al final del desplazamiento nada quedaba tapado, pero en cualquier otra posición —incluida la inicial, como en `almacen_ancho_w900.png`— la tarjeta que pasaba por detrás perdía su existencia. Es común a todas las pantallas del shell que muestran el botón (Almacén, Actividad y los detalles que no lo ocultan).
- **Corrección en el componente común (`6c86451`, `app_shell.dart`):** la vista desplazable termina por encima de una franja de 88 (margen 16 + botón 56 + aire 16), dentro del área segura y sobre la barra inferior: el contenido ya no pasa por detrás del botón en ninguna posición. `ContentInsets` publica 0 (las páginas ya no lo necesitan). El alto del botón no crece con la letra (Material lo fija en 56).
- **Almacén ancho (`6c86451` + `fc12123`, `inventory_screen.dart`):** las tarjetas van de dos en dos cuando la lista mide al menos 640 × la escala de la letra (el Pixel 8 en horizontal da ~700): la existencia queda junto al nombre. No es una tabla; cada tarjeta conserva nombre, previsto, valor, avisos y toque. Con letra ampliada vuelve a una columna para que la tarjeta quepa entera en la vista horizontal (a 200 %, en dos columnas medía 355 de alto frente a 324 de vista).
- **Pruebas:** `test/rdm_flotante_no_tapa_test.dart` (app real con la siembra de la sesión B: nombre largo, L y KG, vencimientos; Almacén y Actividad; 360×800, 412×915, 915×412 y 1280×800; letra 100/130/200 %; en **todas** las posiciones del desplazamiento ninguna tarjeta visible se cruza con el botón; la última se ve entera y el toque en su existencia llega a la tarjeta; columnas según el ancho): 24/24, y **falla 8/8** (letra 100 %) con el shell anterior. Conjunto de 46 archivos que montan el shell, Almacén, Actividad o la app real: 371 superadas y 1 fallo, `rdm_a_personas_pago_test` «Persona: … cabecera» (muestra 200,00 en vez de 160,00 tras el pago). El **mismo** conjunto con el código anterior también falla en esa prueba (y en `f10_x01_pago_datos_test`: 346 superadas, 2 fallos); aislada pasa 6 de 6 y pasó en las tres suites completas anteriores: intermitencia bajo carga **ajena a este cambio, abierta**. Tras `fc12123`: inventario, botón y navegación 88/0; análisis sin avisos. **Sin suite completa** sobre `fc12123`.
- **APK:** `6c86451` se instaló a las 21:50:34 (SHA-256 `32c06cee…4307`) y la reemplazó **`fc12123`**: SHA-256 **`ba6c45606866c083be6c809569cb7889643c12771fc775a85abf22222f297582`**, igual en el archivo y en el `base.apk` del dispositivo; `lastUpdateTime=2026-11-12 21:57:23`, `firstInstallTime` 13:11:32 (misma instalación). Conservadas `agrocuentas.rdm-6c86451-…` y `agrocuentas.rdm-fc12123-…` junto a las anteriores.
- **Datos:** copias de inspección (`run-as`, sólo lectura; no son respaldos) antes de `6c86451`, antes de `fc12123` y después: esquema 19 y todos los conteos idénticos (incluidos `sync_outbox` 0, 2 convocatorias, 3 operaciones de participación y 2 de consentimiento).
- **Emulador:** `RDM_Pixel8` se cerró solo a las 17:43 (hora local) mientras corrían las pruebas pesadas; su registro termina en un apagado normal. La sesión P-A informa que el `Pixel_8` (5554) también terminó solo (código 0). Causa no determinada; nadie los cerró desde estas sesiones. Se arrancó en frío (`-no-snapshot-load`, sin wipe) con `-dns-server 8.8.8.8,1.1.1.1`.
- **Recorrido en el emulador:** Inicio, Actividad y Almacén en vertical con letra normal (los datos del teléfono caben sin desplazar: `j05`); Almacén con letra al 200 % en vertical, al final de la lista (`j01`, sobre `6c86451`, mismo shell) y en horizontal (`j02`, una columna); `fc12123` en horizontal con letra normal: arriba la lista termina sobre el botón (`j03`) y al final la tarjeta va en dos columnas con la existencia junto al nombre (`j04`). Escala de letra y rotación automática restauradas (1,0 y automática).
- **Conectada:** «Actualizar» en Convocatorias renovó la sesión (`POST /auth/v2/refresh` 200) y leyó la lista (`GET /me/joint-purchase-calls` 200) a las 21:59 UTC; servidor sin cambios (5 operaciones distintas, 4 decisiones, 12000 G y 4000 ML). **Abierta en Inicio** (`j06`), con el túnel abierto para la revisión inmediata del autor.

## Incidente «resultado remoto sin confirmar» (corte de internet, 2026-11-12)

- **Qué es:** un estado de la **sesión en línea** (`RemoteSessionPhase.outcomeUnknown`), no de una operación de datos. Lo fija `remote_session_coordinator.dart` cuando la renovación de la credencial (`refresh`) o la reautenticación (login, vínculo del cliente, `/me`) se queda sin respuesta (red, tiempo agotado o respuesta inválida) después de que la petición pudo salir. La app pone en cuarentena la credencial anterior y no la reutiliza; los datos locales no se tocan. En ese estado el botón de reautenticar queda deshabilitado hasta reiniciar el proceso de la app.
- **Qué operación:** un intento de renovación o de reautenticación durante el corte (el túnel anterior había desaparecido y el emulador no resolvía nombres). **Cuál de los dos no quedó registrado:** el registro del observador del túnel anterior se reemplazó al abrir el nuevo. No se afirma cuál fue.
- **¿Pudo aplicarse en el servidor?** No. En la Central aislada, las sesiones de la cuenta del teléfono se crearon a las 05:56, 13:12, 17:55 y 20:24 UTC, y **ningún** token de renovación se consumió entre la de 17:55 y la reautenticación de las 20:24 (el único consumo es la renovación de las 21:59 de esta comprobación). Ninguna operación de credenciales llegó al servidor durante el corte. Las sesiones anteriores siguen activas hasta caducar (no se revocan; entorno sintético).
- **Cola de envíos:** `sync_outbox` vacía antes y después. Las 5 operaciones de convocatorias del teléfono (3 de participación, 2 de consentimiento) se crearon entre las 17:57 y las 18:04 UTC, **antes** del corte, y están `RECEIVED` con **un** intento cada una. En el servidor hay exactamente 5 filas con los **mismos** `operationId`, todas `ACCEPTED`, sin duplicados (clave `callId + memberId + operationId`) y sin escrituras de ese miembro después de las 18:10 UTC. Tras el reinicio y la reautenticación, el observador sólo vio login, vínculo del cliente, `/me` y la lectura de convocatorias: **nada se reenvió, se perdió ni se duplicó**.
- Volver a iniciar sesión sólo restituyó el acceso; la comprobación de los datos es la comparación anterior (teléfono contra servidor).

## No verificado aquí (declarado)

- **Voz:** el AVD propio arrancó sin audio; la integración de estados de voz se verificó en el bloque 1 (`d02`–`d08`) y por pruebas; la precisión del reconocimiento con voz humana sigue pendiente de un teléfono físico. No se guardó audio ni transcripción.
- Letra ampliada y 360 dp: en el arnés (`tool/rediseno/capturas_*_test.dart`); en el emulador sólo Almacén con letra al 200 % (`j01`, `j02`), restaurada después a 100 %.
- Sincronización real con la Central tras la compra sin conexión (las compras no van a la cola; consumo y convocatorias no se recorrieron con red en esta sesión).
- Convocatorias con servidor (participación, estados de envío), vínculos, necesidad y consumo publicados: **bloqueados** sin túnel (ver «Bloqueo de entorno»). Aplicación, plan, pago, transferencia, reportes y borrador: recorridos en el segundo recorrido.
- Comparativas lámina | integración: `comparativas/` (49), con capturas del arnés sobre la rama integrada (`tool/rediseno/capturas_{arnes,a,b,c}_test.dart` en `6b397c9`) o del emulador cuando lo indica el rótulo.
- Nada de esto está **revisado por el usuario**.
