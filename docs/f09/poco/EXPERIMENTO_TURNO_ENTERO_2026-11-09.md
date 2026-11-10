# F09: experimento «un solo transcriptor por turno» en la compra por voz (2026-11-09)

Ensayo exploratorio, no una evaluación formal con usuarios. Rama `feat/f09-diagnostico-motores`, sobre el estado local donde se hicieron las pruebas anteriores (`bf3d022`); código del experimento en `e9b3d66`. Sin push, sin PR, sin cambios en issues ni en el documento de grado. Las frases que aparecen aquí son **escritas y sintéticas** (pruebas automatizadas); de los dictados reales sólo se anotan modelo, campos correctos/incorrectos/pendientes, correcciones, tiempos y códigos de error.

## 1. Estado de partida (revisado antes de tocar nada)

| Qué | Dónde | Estado |
|---|---|---|
| Rama y commit | `feat/f09-diagnostico-motores`, `bf3d022` | Árbol limpio; 13 commits propios desde `d5808d0` |
| Captura | `android/.../LocalVoiceEngine.kt` (`MicrophoneSource`, `Turn.capture`) | `AudioRecord` `VOICE_RECOGNITION`, 16 kHz mono PCM16, bloques de 100 ms, cola de 3 s |
| Segmentación | `Turn.decode` | **Vosk** cierra cada frase en las pausas (`acceptWaveForm`) y al detener; su audio (hasta 30 s) va a la revisión |
| Vosk | `vosk-model-small-es-0.42` (grafo *lookahead*), `vosk-android 0.3.75` | Sin «herbicida» en singular (causa C1) |
| Whisper | `whisper.cpp 52a939a` por `libagro_whisper.so`; modelo `ggml-base-q5_1.bin` (SHA-256 `422f1ae4…8898`) | **Sólo corre si Vosk cerró una frase con texto** y dentro del tope de 5 000 ms por frase; `language=es`, `translate=false`, greedy, `no_context`, `single_segment`, pista = nombres del catálogo |
| Selección | `lib/voice/port/review_selection.dart` (`chooseReviewedText`, regla A) | Si los hechos numéricos difieren, se entrega Vosk; política B sólo en diagnóstico |
| Intérprete de compras | `lib/voice_draft/purchase/purchase_interpreter.dart` | Determinista; recibe el texto cerrado de la sesión |
| Modelo small | Caché local `AgroVoiceModels/dl/ggml-small-q5_1.bin` (SHA-256 `ae85e4a9…11bb`) | Existía (medición HOST del 2026-11-08); no se empaquetaba |

**Qué se reutiliza:** la captura, la cola, el puente JNI de whisper.cpp (idioma, sin traducción, pista), la copia verificada de modelos, el hilo único de inferencia con tope y aborto, las métricas `PcmStats`, los canales de plataforma y el `NativeEventHub`, el contrato `SpeechTranscriptionPort`, la sesión (`VoiceSessionController`), el intérprete, el borrador y la confirmación.

**Qué dependencia de Vosk se retira de este recorrido:** en el modo experimental Vosk **no se carga ni se usa**: no segmenta el audio, no produce parciales y no condiciona si Whisper corre. El micrófono graba el turno entero en memoria y Whisper lo transcribe de una vez al terminar. Vosk sigue en el proyecto y en los demás recorridos (aplicación, planificación y la compra con el experimento apagado).

## 2. El intérprete, probado con frases escritas (sin micrófono)

`test/voice_draft/compra_frases_turno_completo_test.dart`, 17 casos, catálogo que imita al del POCO. **Todos pasan; no hubo que corregir el intérprete.**

| Caso | Resultado |
|---|---|
| «Compré un litro y medio de fungicida demo» (4 variantes, con y sin «un», con «1») | Producto Fungicida DEMO; **1,5 L** (1 500 mL); «y medio» no entra en el producto; precio pendiente, sin inventar |
| «Compré dos litros de fungicida demo a cincuenta bolivianos por litro / el litro» | 2 L, 50,00 Bs/L, BOB, total 100,00 Bs |
| «… a cien bolivianos en total» | Total de 100 Bs, **distinto del unitario**: queda «Revisar» para elegir «Total de la línea»; no se registra como precio por litro |
| «… a cien bolivianos por todo» | «por todo» **no es una forma reconocida** de total: el precio queda sin resolver (no se toma como unitario) y el importe se conserva. Limitación anotada, sin cambio |
| Frase incompleta («compré tres litros de herbicida demo»; «compré herbicida demo»; «compré fungicida demo a cincuenta bolivianos el litro») | Lo no dicho queda **pendiente** (precio, moneda, proveedor, cantidad); nada se rellena solo |
| Producto ambiguo («fungicida» con dos fungicidas en el catálogo) | **Pide elegir** entre los dos; la cantidad dicha se conserva |
| Nombre fuera del catálogo («fungisida») | Sin coincidencia aproximada: falta el producto |
| Frase completa con proveedor | Línea completa y total 100,00; el proveedor resuelto o propuesto, nunca otro |

Los 7 fallos de la primera ejecución eran errores de tipo de las propias aserciones (unidad dicha frente a unidad de catálogo; conversión a mililitros que exige el producto resuelto), no del intérprete.

## 3. El modo experimental

```text
Hablar ─► graba el turno en memoria (≤ 30 s) ─► Terminar ─► Whisper (base | small) sobre todo el audio ─► un segmento ─► intérprete ─► borrador ─► revisar y corregir ─► Registrar compra
Cancelar ─► descarta el audio, aborta la inferencia, el borrador no cambia
```

### Nativo (Kotlin)

- `LocalVoiceEngine.start(... mode, variant, turnMaxMs, turnTimeoutMs)`: con `mode="whole"` crea un `WholeTurn`. `ActiveTurn` es la interfaz común con el `Turn` por frases, que sigue igual (la lectura del micrófono se compartió en `pump`).
- `WholeTurn`: graba en un `PcmBuffer` hasta `turnMaxMs` (30 s, la ventana de Whisper; al llegar termina solo, sin perder lo oído); al cerrarse el micrófono transcribe en el hilo de revisión con tope `turnTimeoutMs` (45 s) y aborto; emite `onTurnText(gen, text, ms, outcome, info)` con métricas (`PcmStats`, `audioMs`, `loadMs`, `inferenceMs`, `variant`, `model`, `closedBy`) y luego `onEnded`. Cancelar aborta y no emite nada. El audio y los flotantes se sueltan al terminar.
- `ensureWhisper(variant)`: **una sola variante en memoria**; pedir otra libera la cargada. El modelo se empieza a cargar al abrir el turno, mientras se habla. Un fallo de carga queda ligado a su variante (`whisperFailedVariant`), para que un fallo de small no apague la revisión con base.
- `LocalVoiceModels.whisperVariants` / `whisperOrNull(variant)`: la variante principal (`whisper`, la de la revisión) y las alternativas (`whisperAlternatives`). `describe()` informa `reviewVariants` y `reviewModels`.
- `LocalVoiceBridge`: argumentos `mode`, `variant`, `turnMaxMs`, `turnTimeoutMs`; evento `turnText`.

### Dart (`lib/voice`)

- `WholeTurnTranscriptionAdapter` (`engineId` `single-transcriber-turn`): mismos canales y misma pista (`hintText`, tope 600 caracteres) que el puerto por frases; números de turno compartidos (`nextGeneration`) para que ningún evento se confunda. Un turno entrega como mucho **un** segmento. Vacío → «nada reconocido»; tope agotado → «tiempo»; error del modelo → fallo con código y sesión recuperable; cancelado → nada, aunque el texto llegue después; un turno anterior nunca toca el actual. Plazo de grabación (30 s) y guarda de cierre (45 s + 20 s).
- `experimentSpeechPortFactoryProvider`: sólo lo usa **Compra por voz**; aplicación y planificación siguen con `speechPortFactoryProvider`.
- `VoiceExperiment.singleTranscriberTurn` / `turnVariant` / `turnMetrics`: la elección se hace en «Registrar por voz» antes de abrir la compra y no se borra con `reset()`; vive en memoria y se pierde al cerrar la app. Las métricas no llevan texto.
- Interfaz: el botón dice **«Terminar»**; estados «Grabando el turno (máximo 30 s)», «Terminando la grabación», «Transcribiendo el turno completo»; botón «Cancelar este turno (descarta el audio)»; sin texto provisional (y se dice); «Revisar cada frase» no aparece. Tarjeta del experimento: selector **Whisper base / Whisper small** (sólo con el micrófono cerrado) y últimos turnos con tiempos y códigos.

### Lo que NO cambia

Captura y tratamiento del audio (misma fuente, misma tasa, mismo PCM), idioma (`es`, sin traducción), parámetros de búsqueda de Whisper (greedy, temperatura 0, `single_segment`, `no_context`), intérprete de compras, borrador, validaciones y confirmación. Aplicación y planificación no se tocaron. Vosk sigue en el APK y en la ruta por frases.

### Condiciones de la comparación base ↔ small

Idénticas salvo el archivo del modelo: misma captura, misma pista, mismo intérprete, mismos topes, un modelo por turno, sin cascada ni combinación. **Frente al recorrido anterior** (Vosk + revisión por frases) cambian dos cosas, y se declaran: (1) la segmentación: turno entero en vez de frases cerradas por Vosk; (2) la pista: además de los nombres del catálogo lleva los términos del dominio (unidades, monedas, familias de producto; `voiceDomainContextHints`, medida antes como «nunca peor» en CTX-1…3), **sin cantidades ni precios**. Modelo (base), cuantización (q5_1) y parámetros de búsqueda son los mismos.

## 4. Pruebas ejecutadas (HOST, Windows 11, Flutter)

| Prueba | Resultado |
|---|---|
| `flutter analyze` | Sin avisos |
| `dart format --set-exit-if-changed lib test` | Sin cambios |
| `test/voice_draft/compra_frases_turno_completo_test.dart` | 17/17 |
| `test/voice/turno_entero_adapter_test.dart` (puerto con canales simulados: argumentos del `start`, un segmento por turno, vacío, tope, modelo no disponible, cancelación, turno anterior, dos turnos, audio máximo, guarda de cierre, plazo de grabación, tope de métricas) | 13/13 |
| `test/voice/turno_entero_seleccion_test.dart` (sólo compra, sólo diagnóstico, `reset()` conserva la elección) | 5/5 |
| `test/voice_draft/turno_entero_pantalla_test.dart` (interruptor, tarjeta, selector, métricas sin texto, panel de siempre sin cambios) | 4/4 |
| Guardas de arquitectura (`test/voice/voice_architecture_guard_test.dart`, `test/voice_draft/voice_draft_architecture_guard_test.dart`) | Pasan (el puerto nuevo se añadió a la lista de adaptadores que pueden hablar con la plataforma; `lib/voice` sigue sin nombrar compras ni proveedores) |
| Suites completas `test/voice` + `test/voice_draft` | **689/689**, una sola ejecución limpia |

No hay prueba instrumentada nueva del `WholeTurn` (haría falta el emulador con audio sintético); su comportamiento se comprueba en el teléfono (sección 7).

## 5. APK aislada

| Dato | Valor |
|---|---|
| Archivo | `%TEMP%\agro_f09\apk_wt_e9b3d66\agrocuentas-f09wt-e9b3d66-arm64-v8a-profile.apk` |
| Paquete / etiqueta | `com.comunidad.agro.agroquimicos.f09w` / **«AC F09 WT»** (no sustituye a `.f09` «AC F09» ni toca sus datos) |
| Código | `e9b3d66` (`AGRO_APP_COMMIT`), `AGRO_VOICE_DIAG=true`, `AGRO_VOICE_EVIDENCE=true`, origen del Central del túnel abierto |
| SHA-256 | `0fd6107a8d33e3d3985feaab4da40ac58b796e36716346b631b9dffafaf73259` · 333 200 964 B |
| Modelos (comprobado en el ZIP) | `vosk-model-small-es-0.42`; `whisper-base-q5_1/ggml-base-q5_1.bin` (59 707 625 B); `whisper-small-q5_1/ggml-small-q5_1.bin` (190 085 487 B); manifiesto con `whisper.variant=base` y `whisperAlternatives.small` |
| Librerías | `libagro_whisper.so`, `libggml*.so`, `libvosk.so` (arm64-v8a) |
| Script | scratchpad `f09/build_f09wt_apk.sh` (derivado de `tool/voice_local/build_voice_apk.sh`); modelos con `fetch_voice_models.sh both` |

Que el selector carga el modelo indicado se comprueba en el teléfono con la métrica del turno (`modelo=whisper-small-q5_1`, `carga=…ms`, visible en la tarjeta y en el registro técnico con códigos) y con el tiempo de inferencia, que en small es varias veces el de base.

## 6. Instalar y activar

1. **Instalada el 2026-11-09 22:30** en el POCO (`cc14247a`) sin desinstalar nada: `.f09` «AC F09» conserva su `lastUpdateTime` (18:09:22). Con `adb install` MIUI canceló dos veces sin mostrar diálogo (`INSTALL_FAILED_USER_RESTRICTED`); funcionó `adb push` a `/data/local/tmp` + `pm install -r`, que sí abre «Instalar vía USB» (`com.miui.permcenter.install.AdbInstallActivity`), aceptado tocando «Instalar» en (310, 2102). El archivo temporal se borró del teléfono.
2. **Activada el 2026-11-09 hacia las 23:05** con `agricultor3` de la DEMO (varias instalaciones por cuenta están permitidas). La contraseña de un solo uso la tecleó `demo.sh credential agricultor3 cc14247a` en el campo enfocado (se verificó antes que el foco estaba en la clave); no se anota. Dos tropiezos documentados: (a) el primer intento falló con «No se pudo confirmar la operación remota» porque el teléfono estaba en LTE **sin Internet** (red con `CAPTIVE_PORTAL`, sin `VALIDATED`); se encendió el Wi-Fi (`svc wifi enable`), que validó, y se reinició la app porque la pantalla bloquea un segundo intento tras un resultado remoto incierto; (b) `demo.sh credential` falla con «Cannot find module …/demo-central.cjs» si `MSYS_NO_PATHCONV=1` está exportado en Git Bash (Node recibe una ruta `C:/c/Users/…`); hay que ejecutarlo sin esa variable. Titular «Rosa Mamani WT», modo **Compartido**, sin PIN.
3. Datos sintéticos creados en Catálogos: productos «Herbicida DEMO», «Fungicida DEMO», «Insecticida DEMO» (litros); proveedor **«Agro insumos DEMO»** (el teclado del teléfono insertó un espacio al teclear por adb; se deja así y se anota); campaña «Invierno 2026 WT», activa desde el 09/11/2026. Sin chaco ni existencias previas: la compra no los necesita.
4. Operaciones → Más → Registrar por voz: encender **«Experimento: compra con un solo transcriptor (Whisper) por turno»**. Entrar en **Compra por voz**: la tarjeta «Experimento activo» muestra el modelo del próximo turno (base por defecto).
4b. Comprobado al abrir «Compra por voz» con el experimento encendido: tarjeta «Experimento activo», selector Whisper base / Whisper small, «Reconocedor: modelo de voz de la aplicación (whisper-base-q5_1)», sin «Revisar cada frase»; registro técnico `voz turno: variante=base disponible=si variantes=base/small`.
5. Hablar → dictar → **Terminar** → esperar «Transcribiendo el turno completo» → revisar y corregir → Registrar compra (sólo cuando se decida registrar).

El experimento se apaga al cerrar la app. Aplicación y planificación no cambian.

## 7. Comprobaciones en el teléfono (pendientes de ejecutar con el autor)

Casos: dictado completo con pausas · silencio · cancelación · dos turnos consecutivos · error al cargar el modelo (variante ausente o memoria) · campos incompletos · revisión y confirmación sin duplicados · sin conexión (modo avión) con los modelos ya copiados. Y la comparación base ↔ small sobre las mismas frases (producto, cantidad, unidad, precio unitario/total, moneda, líneas adicionales, correcciones manuales, tiempo desde «Terminar» hasta el borrador). Se conservan los intentos fallidos. La coincidencia entre modelos no vale como acierto: cada campo se contrasta con lo que debía registrarse.

## 7a. Primeros dos turnos en el POCO (Whisper base, APK `e9b3d66`, 2026-11-09 23:2x)

Condiciones: experimento encendido, variante **base**, pista = catálogo + términos del dominio, borrador nuevo. Roderich dictó; esta sesión leyó sólo los campos y los tiempos. Los dos turnos se conservan **separados**.

| Turno | Audio | Habla | Nivel | Carga | Transcripción | «Terminar» → borrador |
|---|---|---|---|---|---|---|
| 1 | 25,1 s | 5,9 s | −35 dBFS | 0 ms (precargado al abrir: 117 ms) | 2 881 ms | ≈3 s |
| 2 | 7,2 s | 4,3 s | −32 dBFS | 0 ms | 2 657 ms | ≈3 s |

**Turno 1 (caso previsto: 2 L de Fungicida DEMO a 50 Bs/L).** Producto Fungicida DEMO ✓ dictado; cantidad 2 L ✓; moneda BOB ✓; **precio 50 «Ambiguo: elija»**: entre la cifra y la unidad el modelo escribió otra palabra y la app preguntó «¿50 Bs por L?». Acierto inicial: **3 de 4 campos correctos sin revisión; precio correcto pero pendiente; 0 incorrectos sin aviso; 0 líneas adicionales en este turno.** Correcciones que harían falta: confirmar «Por L» y elegir el proveedor (no se dictó).

**Turno 2 (otro dictado; sus valores esperados se fijarán con el autor, no se valora aquí).** Una línea nueva: producto «Ambiguo: elija» (sin resolver), cantidad 5 L dictada, precio 120 «Ambiguo» (misma pregunta), moneda «por revisar» (sin «a» antes de la cifra). Tiempo igual al del turno 1. No se mezcla con los campos del turno 1.

**No se registró la compra.** El borrador se descartó por la interfaz («Cancelar») y la base de `.f09w` quedó con 0 compras, 0 lotes, 0 movimientos, 0 cuentas. Al volver a entrar, el borrador empieza vacío.

### Ambigüedad del precio: ¿intérprete o transcripción?

Comprobado con frases **escritas** (`compra_frases_turno_completo_test.dart`, grupo 7, 22/22):

- Con texto correcto («… a cincuenta bolivianos por litro / el litro / cada litro / por el litro») el precio queda **resuelto**: 50 Bs/L. El problema **no se reproduce con texto correcto**: en el turno 1 sólo tenemos evidencia de una palabra intercalada en la transcripción, y la app hizo lo previsto (preguntar, sin aceptar cualquier palabra ni asumir unitario).
- Con una palabra intercalada entre importe y unidad («… cincuenta bolivianos haciendo litro / haciendo el litro») el precio queda **ambiguo** con el importe conservado; con artículo delante de la unidad, la pregunta es «¿50 Bs por L?». Nunca se resuelve solo.
- «… a cien bolivianos en total» se reconoce como **total** (no unitario).
- **Defecto encontrado y anotado, sin corregir todavía:** «… por un total de cien bolivianos» no se toma como unitario (bien), pero el importe sale **1,00** en vez de 100,00: «un» se lee como la cifra. Se corregirá después de la ronda, con su propia versión, para no cambiar el intérprete entre mediciones. Mientras, el caso de precio total de la ronda usa la forma «… en total».
- No se atribuye la ambigüedad al modelo sin más: una palabra intercalada puede venir del habla o de la transcripción; sólo se anota como «palabra extra entre cifra y unidad».

### Ronda exploratoria con Whisper base (6 casos, condiciones constantes)

| # | Caso | Frase prevista | Esperado |
|---|---|---|---|
| R1 | Compra sencilla, precio unitario | «Compré tres litros de herbicida demo a ciento veinte bolivianos el litro» | Herbicida DEMO · 3 L · 120 Bs/L · BOB · total 360,00 |
| R2 | Cantidad decimal | «Compré un litro y medio de fungicida demo a cincuenta bolivianos el litro» | Fungicida DEMO · 1,5 L · 50 Bs/L · BOB · total 75,00 |
| R3 | Precio total | «Compré dos litros de insecticida demo a cien bolivianos en total» | Insecticida DEMO · 2 L · precio **total** 100 Bs («elija Total de la línea»), nunca 100 Bs/L |
| R4 | Pausa natural | «Compré dos litros de fungicida demo» … pausa ≈2 s … «a cincuenta bolivianos el litro» | Una sola línea: Fungicida DEMO · 2 L · 50 Bs/L · BOB · 100,00 |
| R5 | Nombre parecido | «Compré dos litros de insecticida demo a noventa bolivianos el litro» | Insecticida DEMO (no Herbicida ni Fungicida) · 2 L · 90 Bs/L · 180,00 |
| R6 | Incompleta | «Compré fungicida demo» | Fungicida DEMO; cantidad, precio y moneda pendientes; proveedor falta; no se puede registrar |

Por intento se anota: correctos sin corrección · pendientes/ambiguos · incorrectos aceptados sin aviso · líneas adicionales · correcciones manuales · tiempo «Terminar» → borrador. Se conservan fallos y repeticiones. Luego, small con los mismos casos: repetir las frases de viva voz **no es el mismo audio**; se compara utilidad de los campos, errores sin aviso, correcciones y espera, sin declarar ganador por un acierto.

## 8. Limitaciones conocidas

- Sin texto provisional en el modo experimental: el usuario no ve nada hasta «Terminar».
- 30 s por turno; con más audio el turno termina solo.
- small pesa 190 MB: el APK pasa de 148 a 333 MB y la primera carga del modelo tarda más (se mide en el teléfono).
- «por todo» no se reconoce como total (sí «en total»).
- El experimento no se guarda: hay que encenderlo en cada arranque de la app.
- No hay prueba instrumentada del turno entero con audio de referencia.
- Los interruptores de diagnóstico «política B» y «comparar pistas» siguen visibles en la pantalla de compra pero **no tienen efecto** en el modo experimental (actúan sólo sobre la ruta por frases).
