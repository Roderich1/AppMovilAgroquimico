# F09: verificación en el EMULADOR sobre `a51d409` (2026-11-08)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08, 14:15–14:45 (Bolivia, UTC−4) |
| Procedencia | **EMULADOR**: `Pixel_8` (`emulator-5554`), `sdk_gphone16k_x86_64`, API 36, TZ GMT. **No es DEVICE**: no hubo dictado real ni audio inyectado |
| Código | `a51d409` (`feat/f09-integracion`). Herramientas: `tool/f09_emu/f09emu.sh` de `_wt/F09-INT` |
| APK | `agrocuentas-f09-a51d409-x86_64-profile.apk`. SHA-256 `eab0e3ccb950af8e023bdd27f67e455f80afe8e418682170ba12291280564b1b`, la **misma** que la instalada (`pm path` + `sha256sum`). Paquete `.f09` («AC F09»), Vosk small-es 0.42 + whisper base q5_1, `AGRO_VOICE_EVIDENCE=true` |
| Estado previo | La coordinadora la dejó instalada, activada con `agricultor5` (titular «Ana Quispe F09», modo compartido) y sembrada (`DEMO_DATE=2026-11-03`). Túnel DEMO vivo, sin cerrarlo |
| Base | Copias de sólo lectura por `run-as` (`f09emu.sh base`). Sin transcripciones |
| Capturas | `%TEMP%\agro_f09_emu\capturas\vNN_*.png` (SHA-256 en §3). Seis reducidas en `capturas_a51d409/` |

## 1. Resultados

| # | Comprobación | Resultado | Detalle |
|---|---|---|---|
| 1a | Apertura e Inicio | **PASS** | Inicio con la campaña «Invierno 2026 (DEMO)» y los totales sembrados. Aviso: «Cuenta vinculada… El estado en línea aún no fue verificado.» (v01) |
| 1b | «Verificar acceso en línea» por el túnel | **PASS** | Mensaje: «Acceso en línea verificado para esta sesión.» (v02). En el observador del túnel: exactamente `POST /api/v1/auth/v2/refresh 200` |
| 2 | Más › Licencias | **PASS** | Hay 209 entradas. Están las pedidas:<br>• Vosk (vosk-android 0.3.75)<br>• Kaldi, OpenFST, OpenBLAS 0.3.20 y CLAPACK 3.2.1 con libf2c («incluidos en Vosk»)<br>• JNA 5.18.1, whisper.cpp y ggml<br>• los modelos Vosk small-es-0.42 y Whisper (ggml)<br>• diez de integration_test («compilación profile»): AndroidX Test/Espresso, Animal Sniffer, Checker compat-qual, Guava/failureaccess, Hamcrest, J2ObjC, JUnit 4.12, JavaWriter, el plugin integration_test y javax.inject<br>Abrí «Vosk» y se ve su texto Apache 2.0 con la nota de los componentes incluidos (v06). Volví con «Atrás» dos veces sin problemas |
| 3a | Registrar por voz: las cuatro entradas | **PASS** | Compra, Planificación, Aplicación y «Evaluación de la voz / Permiso para guardar lo dictado» (v07) |
| 3b | Consentimiento | **PASS** | Antes: «Permiso: no dado. No se guarda nada.» (v08). Tras «Acepto»: «Permiso: dado. Dictados guardados: 0.» (v09). En la base, `voice_evidence_consent` pasa de 0 a 1 y `voice_evidence` queda en 0 |
| 4a | Compra por voz: motor y modelo | **PASS** (con observación O1) | Muestra:<br>• «Reconocedor: modelo de voz de la aplicación (vosk-model-small-es-0.42)»<br>• «Idioma: español»<br>• «Revisión de cada frase: whisper-base-q5_1»<br>• «Funciona sin conexión: el modelo está instalado con la aplicación y el audio no sale del teléfono.»<br>• el interruptor «Revisar cada frase»<br>• «Modo avión: desactivado.»<br>Ver O1 sobre la primera apertura |
| 4b | Hablar → permiso → **denegar** | **PASS** | Aparece el diálogo del sistema «Allow AC F09 to record audio?» (v11). Tras «Don't allow»: «Estado: Permiso de micrófono denegado» y el aviso «Sin permiso de micrófono no se puede dictar. Puedes concederlo y volver a intentarlo, o escribir el texto a mano. / Código: permissionDenied» (v12). El micrófono no llega a abrirse: `Inputs (0)` |
| 4c | Continuidad manual en el borrador | **PASS** | Compra completada a mano:<br>• proveedor «Agroinsumos DEMO»<br>• recibe «Ana Quispe F09»<br>• producto «Herbicida DEMO» con el selector, 2 L a 150 BOB<br>• «¿Ya pagaste?» = «No, todavía no»<br>• total 300,00 Bs (v14)<br>«Registrar compra» vuelve a «Registrar por voz» (v15) |
| 4d | Conteos tras registrar | **PASS** | `purchases` 3→**4** y `purchase_items` 4→5: exactamente una compra nueva. `voice_evidence` 0→**0** (sin dictado aplicado no hay evidencia). `sync_outbox` 0 |
| 5 | Abrir y cerrar compra, plan y aplicación por voz | **PASS** | Las tres abren con «Estado: Listo para empezar». «Volver» las cierra sin atascos, y después hay `Inputs (0)` y 0 grabaciones del uid. Con el permiso concedido también se probó salir **mientras escuchaba**: antes `Inputs (1)`, después de «Volver» `Inputs (0)` |
| 6a | Conceder el permiso (diálogo, sólo `.f09`) | **PASS** | En un nuevo «Hablar», elegí «While using the app». Resultado: `RECORD_AUDIO granted=true`, y la escucha empieza: «Estado: Escuchando», «Detener. El micrófono está escuchando.», `Inputs (1)` (v16) |
| 6b | «Cancelar» durante la apertura | **NOT_RUN** | No aparece ninguna fase de apertura observable. Con el modelo ya cargado, al volcar la interfaz justo después de tocar ya se lee «Escuchando» (< 1 s) |
| 6c | Silencio (sin audio del host) | **PASS** (con observación O2) | No aparece texto y el borrador queda vacío (v17, v18). La escucha se cierra sola: `appops` mide una duración de 30,1 s. La base no cambia: `purchases`=4, `voice_evidence`=0. El micrófono queda libre: `Inputs (0)` |
| 6d | «Detener» durante la escucha | **PASS** | Vuelve a «Hablar». Ni texto ni escrituras. `Inputs (0)` (v19) |
| 7a | «Cancelar» un borrador con datos manuales | **PASS** | Con el proveedor elegido a mano, «Cancelar» sale sin escribir: `purchases`=4 y `voice_evidence`=0 (v23) |
| 7b | Atrás con un borrador empezado pregunta | **PASS** con el Atrás del sistema; **FAIL** con el botón «Volver» de la app (D1) | Atrás del sistema: «¿Descartar el borrador? No se registró nada. Lo dictado y lo corregido se pierden.», con «Cancelar» y «Descartar». «Cancelar» conserva el borrador (v21). Botón «Volver»: sale y descarta el borrador **sin preguntar** (v20, v22). Reproducido en compra y en aplicación |
| 7c | Tras registrar no aparece «¿Descartar el borrador?» (#120) | **PASS** | En compra, aplicación y plan, al registrar se vuelve directamente a «Registrar por voz» sin el diálogo (v15, v27, v29) |
| 8 | Edición manual preservada | **PASS** (con observación O3) | Cantidad escrita a mano: 7 L de «Fungicida DEMO». Al abrir y cerrar el selector «Recibe la compra», sigue en 7. Desde el selector de proveedor creé «Proveedor F09 Emu»: el borrador se conserva (7 L), y el proveedor nuevo queda **elegido** y marcado como «Corregido a mano» (v24, v25). `suppliers` 1→2. Después cancelé el borrador: `purchases`=4 |
| 9a | Aplicación por voz, a mano | **PASS** | «Chaco Norte DEMO»: el área de 3 ha la propone el chaco. «Herbicida DEMO», 1 L: «Stock actual 13 L · quedaría 12 L» (v26). `applications` 2→**3** y `application_items` 2→3. `voice_evidence`=0 |
| 9b | Planificación por voz, a mano | **PASS** | «Chaco Norte DEMO», 3 ha, «Fungicida DEMO» a 1 L/ha (v28). «Crear plan» da `application_plans` 0→**1** y `application_plan_items` 0→1. `voice_evidence`=0 (v29) |
| — | Reconocimiento con voz | **NOT_RUN** | Hace falta dictado real o audio inyectado |
| — | Resultado tardío tras cancelar o cambiar de pantalla con voz | **NOT_RUN** | Ídem |
| — | «Un litro y medio» y frase partida por una pausa | **NOT_RUN** | Ídem |
| — | Tope de la segunda pasada (5 000 ms) | **NOT_RUN** | Ídem |
| — | Tiempos (primer parcial, final, RTF) | **NOT_RUN** | Ídem. Además, uiautomator no mide tiempos |
| — | Evidencia con dictado (filas `CONFIRMED`/`DISCARDED`) | **NOT_RUN** | Sin texto reconocido, ningún borrador llevó voz aplicada. En toda la sesión `voice_evidence` = 0 |

**Conteos finales** (frente a la siembra):

| Tabla | Antes | Después | Diferencia |
|---|---|---|---|
| `purchases` | 3 | 4 | +1 |
| `purchase_items` | 4 | 5 | +1 |
| `applications` | 2 | 3 | +1 |
| `application_items` | 2 | 3 | +1 |
| `application_plans` | 0 | 1 | +1 |
| `application_plan_items` | 0 | 1 | +1 |
| `suppliers` | 1 | 2 | +1 («Proveedor F09 Emu») |
| `voice_evidence_consent` | 0 | 1 | +1 |
| `voice_evidence` | 0 | 0 | 0 |
| `sync_outbox` | 0 | 0 | 0 |

`user_version` = 14 y `quick_check` = ok.

**Peticiones por el túnel durante la verificación:** sólo `GET /api/v1/health 200`, que es el `estado` del script, y `POST /api/v1/auth/v2/refresh 200`. Antes figuran las de la activación de la coordinadora: `clients 201`, `session/client 201` y `me 200`.

## 2. Fallos y observaciones (sin corregir en código)

**D1 (FAIL): el botón «Volver» de las pantallas de borrador por voz descarta sin preguntar.**
- Con un borrador empezado (proveedor o chaco elegido a mano), el icono «Volver» de la cabecera sale y pierde el borrador. El Atrás del sistema sí pregunta.
- **Pasos:** Registrar por voz › Compra por voz › elegir proveedor › tocar «Volver» (arriba a la izquierda) → «Registrar por voz», sin diálogo. Volver a entrar muestra el borrador vacío.
- **Causa probable**, por lectura de código y sin comprobar:
  - `PageFrame` (`lib/presentation/widgets/common.dart:106-110`) llama a `router!.pop()`, que no consulta el `PopScope`.
  - El diálogo de `VoiceDraftExit` (`lib/presentation/voice/voice_draft_widgets.dart:67-100`) sólo se dispara con un pop que lo respete, como el Atrás del sistema o `maybePop`.
- No hay escrituras: los conteos no cambian. Lo que se pierde es lo editado.
- **Afecta** al criterio «Atrás con borrador empezado pregunta antes de descartar». Reproducido en compra y en aplicación. Por construcción, la planificación usa el mismo `PageFrame`.

**O1:** en la **primera** apertura de «Compra por voz», antes de pedir el permiso, se lee «Modo avión: no se pudo comprobar.» y no aparecen el nombre del modelo ni la línea de revisión (v10). Después del primer «Hablar» se ven «vosk-model-small-es-0.42», «whisper-base-q5_1» y «Modo avión: desactivado.».

**O2:** tras una escucha **sin texto**, por silencio o por «Detener», el estado dice «Texto listo para revisar» aunque no hay texto. La base y el borrador no cambian, pero el mensaje puede confundir.

**O3:** en los selectores en hoja inferior, el nodo «Cerrar» que expone la accesibilidad (encima del título) no cerró la hoja al tocarlo con `input tap`. Se cerró tocando fuera («Sombreado»). Puede ser el asa de arrastre. No lo comprobé con el dedo.

**Script (`f09emu.sh ir`).**
- **Fallos encontrados:**
  - las pestañas exponen «Operaciones / Pestaña 2 de 5», así que `^Operaciones$` no coincidía;
  - las expresiones con letras no ASCII («Más», «Aplicación») no llegan bien de Git Bash a Python;
  - «Registrar por voz» queda bajo el pliegue de «Más».
- **Corregido en `_wt/F09-EMU`:** uso `.` en lugar de esas letras y añadí un deslizamiento con guarda. Probado: Inicio › `ir plan` → «Planificación por voz». La copia de `F09-INT` sigue sin ese ajuste.

## 3. Capturas (SHA-256 del PNG original, 1080×2400)

| Archivo | SHA-256 |
|---|---|
| v01_inicio | `272a9a9cd00e29cbf17ee94c9907139362388e0bc1d810ace7907ff3c4b3bc1b` |
| v02_verificar_acceso | `cb8831b42036b4e565fe91d42f29dfcdfbb498d04c4686f51f9160c1adac4ed0` |
| v03_mas | `b21bf72807969661fc28534b8ba52bd724fb84f3cf46d90a55beacb4d9c679a0` |
| v04_mas_licencias_entrada | `82eeb761756afd2ea2c35b8b3f87a1a18ebbbe55d1e5dd3a131be507a98e9d60` |
| v05_licencias | `05abfb3ced0c9b7e9fc952ac827a032e4bd811f304763865c71c074975824fcd` |
| v06_licencia_vosk | `23697eeade0dbb9c0d30780fcc367a95ab1f49ddac3b65d98f668c0d3744c388` |
| v07_registrar_por_voz | `44d847e70d90b6b9dfc96e1d56f6046bbf542d982a2a8855c309530334479da9` |
| v08_consentimiento_antes | `1649c0818026ce1827df1aa1552f9c2c5b1a1a0081145ecd2aee8e90176b5e79` |
| v09_consentimiento_dado | `eee1a15fb394c9ea456e03065083e043e8c238646aaf86ca17c4431e3b4d2d86` |
| v10_compra_voz_inicio | `b0696f239afb814792622a96a2805e3f5fca0996b24ec26c6d762e93e88d3ec2` |
| v11_dialogo_permiso | `88ff6f53c6a09d6712a99ca1d846cf52fadd4f90ad2829bc7a7389b1c89db777` |
| v12_permiso_denegado | `2bacb5a35704dfc4dd57c0bbcf57f221894bf8c700b0a3459117e4fe194a34cb` |
| v13_selector_proveedor | `46576099ae4e126467c91029380624ed3d0e0d5aaad3ac1b7d9d7269570cd286` |
| v14_compra_manual_lista | `7d87e93fb9581c24acf512de328bc6022d8515a49f568b125ab5ce193df8ecbc` |
| v15_compra_registrada | `bb0bcaa4cced5a343ac3733e3b2d0324d09ee4c13c6cdb0cbf168632b880f4a4` |
| v16_hablar_con_permiso | `9c02dccf96d9bbeae992464644a7147b12d28c542bb25e803560d4f904d7c14b` |
| v17_tras_silencio | `c81835001e09d08a8de0de335ea0578fe6003fe24e45e837d0cd515c811a6b63` |
| v18_borrador_tras_silencio | `5067756518c502934b1db25ac2797a5efda78fd1e9998236db4360d7bd9e11b3` |
| v19_tras_detener | `2b5f9e9b8cc04c3cee25a67a1d59762249840e6b994b652922e7cea8a6677dc4` |
| v20_volver_con_borrador | `06dffdeaa3bf6423a66b227035069c8026fc6d473b2c68d5c1e23e8986d2f0ff` |
| v21_atras_sistema_con_borrador | `6ff9959856b98e57e4b002fe0b5b1e4bfb91a695c8f05a020d8bc26a4f226438` |
| v22_volver_app_con_borrador | `7b1ad9d3186e4c0152f08bdab56d0b101b5a4bd512f1da1370fbcee4d1676a43` |
| v23_cancelar_borrador | `fe7b7ead56c0ddba9ce6a8c0603ac6a8eaa4804790712202fbe96734b442d010` |
| v24_crear_proveedor | `cdc8bf5e0d7be2ab3e8fd3a9498dabaa505da5e3a5cf19a041686875fd260c92` |
| v25_tras_crear_proveedor | `03b13c39b7a8479b619f5b055234cc09b836b3449d9d8803bb82cd8e1878545a` |
| v26_aplicacion_lista | `0df933d6197b08a617e1fbc133ea78ee4dd6fd1c5115333f7923393a67e11280` |
| v27_aplicacion_registrada | `80024cc730acdcdd2a448c2999db005c2a581076349be4e810901f687e19a54a` |
| v28_plan_listo | `936fa44d8dba95da73018642d01812a657a17c9cc2b8067450a1511886451965` |
| v29_plan_registrado | `b483629af2df34e45dd06ac28d7a911f9e7ae1d1e4fe976f817242dbf51ca298` |

`capturas_a51d409/` contiene copias JPEG a 360 px de v02, v09, v12, v18, v21 y v25.

## 4. Estado en que queda el emulador

- `.f09`:
  - está en Inicio y en primer plano;
  - tiene el permiso de micrófono **concedido** (paso 6), y el micrófono está libre (`Inputs (0)`);
  - tiene el consentimiento de evaluación dado, con 0 dictados;
  - conserva sus datos más lo registrado aquí (§1).
- No toqué otros paquetes, el túnel ni el Central.
- No usé la entrada de audio del host. Partí del supuesto de que «Virtual microphone uses host audio input» estaba apagado. Lo confirma que la escucha sólo entregó silencio.
- Para volver a probar #119 con el permiso denegado, hay que revocarlo **sólo** en `.f09`, en sus ajustes o con `pm revoke com.comunidad.agro.agroquimicos.f09 android.permission.RECORD_AUDIO`. Esta sesión no lo hizo.

## 5. Alcance

Todo es EMULADOR, con la APK `a51d409`. No sustituye la evidencia DEVICE (POCO y HONOR), ni el criterio de #119 en el HONOR, ni la evaluación #12. Las filas NOT_RUN quedan pendientes de dictado real o de audio inyectado, que necesita la aprobación del autor.
