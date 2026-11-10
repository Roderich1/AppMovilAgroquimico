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

## 7a. Primera sesión: dos turnos en el POCO (Whisper base, APK `e9b3d66`, 2026-11-09 23:2x)

Esta sesión es **anterior a la ronda R1–R6** y no se suma a sus resultados.

Condiciones: experimento encendido, variante **base**, pista = catálogo + términos del dominio, borrador nuevo. Roderich dictó; esta sesión leyó sólo los campos y los tiempos. Los dos turnos se conservan **separados**.

| Turno | Audio | Habla | Nivel | Carga | Transcripción | «Terminar» → borrador |
|---|---|---|---|---|---|---|
| 1 | 25,1 s | 5,9 s | −35 dBFS | 0 ms (precargado al abrir: 117 ms) | 2 881 ms | ≈3 s |
| 2 | 7,2 s | 4,3 s | −32 dBFS | 0 ms | 2 657 ms | ≈3 s |

**Turno 1 (caso previsto: 2 L de Fungicida DEMO a 50 Bs/L).** Producto Fungicida DEMO ✓ dictado; cantidad 2 L ✓; moneda BOB ✓; **precio 50 «Ambiguo: elija»**: entre la cifra y la unidad el modelo escribió otra palabra y la app preguntó «¿50 Bs por L?». Acierto inicial: **3 de 4 campos correctos sin revisión; precio correcto pero pendiente; 0 incorrectos sin aviso; 0 líneas adicionales en este turno.** Correcciones que harían falta: confirmar «Por L» y elegir el proveedor (no se dictó).

**Turno 2 — no evaluable.** Fue otro dictado cuyos valores esperados no se pueden reconstruir con certeza; no se inventan y no se valora (decisión del autor, 2026-11-10). Sólo se anota lo que mostró el borrador: Una línea nueva: producto «Ambiguo: elija» (sin resolver), cantidad 5 L dictada, precio 120 «Ambiguo» (misma pregunta), moneda «por revisar» (sin «a» antes de la cifra). Tiempo igual al del turno 1. No se mezcla con los campos del turno 1.

**No se registró la compra.** El borrador se descartó por la interfaz («Cancelar») y la base de `.f09w` quedó con 0 compras, 0 lotes, 0 movimientos, 0 cuentas. Al volver a entrar, el borrador empieza vacío.

### Ambigüedad del precio: ¿intérprete o transcripción?

Comprobado con frases **escritas** (`compra_frases_turno_completo_test.dart`, grupo 7, 22/22):

- Con texto correcto («… a cincuenta bolivianos por litro / el litro / cada litro / por el litro») el precio queda **resuelto**: 50 Bs/L. El problema **no se reproduce con texto correcto**: en el turno 1 sólo tenemos evidencia de una palabra intercalada en la transcripción, y la app hizo lo previsto (preguntar, sin aceptar cualquier palabra ni asumir unitario).
- Con una palabra intercalada entre importe y unidad («… cincuenta bolivianos haciendo litro / haciendo el litro») el precio queda **ambiguo** con el importe conservado; con artículo delante de la unidad, la pregunta es «¿50 Bs por L?». Nunca se resuelve solo.
- «… a cien bolivianos en total» se reconoce como **total** (no unitario).
- **Defecto encontrado y anotado** (corregido después de las dos rondas, en otra versión: §9): «… por un total de cien bolivianos» no se toma como unitario (bien), pero el importe sale **1,00** en vez de 100,00: «un» se lee como la cifra. Comprobado el 2026-11-10 sobre `4a2f324`, campo por campo: importe extraído **1,00**; tipo **total**, pendiente («Ambiguo»); el campo «Precio por L» **vacío** (un total no se muestra ahí); además, el resto de la frase quedaba como «precio suelto no colocado»; y tras tocar «Total de la línea», **0,50 Bs/L resuelto** (valor erróneo después de una confirmación). Una nota de seguimiento anterior decía «1,00 Bs por L»: era inexacta; nunca quedó como precio por litro antes de confirmar. Durante las rondas, el caso de precio total usó la forma «… en total».
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

### Resultados de la ronda, Whisper base (APK `e9b3d66`, POCO, 2026-11-09/10)

Cada fila es un turno real; se conservan los fallos. «Pendiente» = valor correcto pero marcado «Revisar/Ambiguo»; «incorrecto sin aviso» = valor erróneo aceptado como resuelto.

| Caso | Turno | Audio / habla | Transcripción | «Terminar»→borrador | Correctos sin corrección | Pendientes o ambiguos | Incorrectos sin aviso | Líneas de más | Correcciones necesarias |
|---|---|---|---|---|---|---|---|---|---|
| R1 | 3 | 9,3 s / 5,7 s (−35 dBFS) | 2 913 ms | ≈3 s | cantidad 3 L | producto («Ambiguo: elija», no resuelto); precio 120 («¿120 Bs por L?», palabra extra entre cifra y unidad); moneda BOB («Revisar», sin «a» antes de la cifra) | 0 | 0 | elegir producto, confirmar «Por L», confirmar BOB, elegir proveedor |
| R2 (intentos previos) | 4, 5, 6 | 9,0 s / 5,9 s · 1,8 s / 0,5 s · 6,3 s / 4,6 s | 2 637 · 2 778 · 2 684 ms | ≈3 s | — | Descartados por el autor antes de la lectura (cada uno con «Cancelar»); sólo se conservan los tiempos. El turno 5 fue una apertura muy corta | — | — | — |
| R2 | 7 | 11,9 s / 5,7 s (−31 dBFS) | 2 788 ms | ≈3 s | cantidad **1,5 L**; moneda BOB | producto («Falta»: el nombre transcrito no está en el catálogo, sin aproximar); precio 50 («¿50 Bs por L?», palabra extra) | 0 | 0 | elegir producto, confirmar «Por L», elegir proveedor |
| R3 (**mezclado, no cuenta para base**) | 8 (base) + 9 (**small**) | 10,9 s / 4,9 s · 6,7 s / 4,4 s | base **2 691 ms** · small **10 140 ms** | ≈3 s · ≈10 s | — | El borrador recibió los dos turnos (el selector pasó a small entre ellos): producto Insecticida DEMO dictado, 2 L dictado, precio «Ambiguo: se dijo un importe total», moneda BOB dictada. Los campos no se pueden atribuir a un modelo; se repite R3 con base | 0 | 0 | — |
| R3 (repetido) | 10 | 10,3 s / 6,2 s (−36 dBFS) | 2 704 ms | ≈3 s | cantidad 2 L | producto («Ambiguo: elija», no resuelto); **precio «Falta»** y **moneda «Falta»**: en este turno no se extrajo ningún importe | 0 | 0 | elegir producto, escribir el precio total y la moneda, elegir proveedor |
| R4 | 11 | 8,5 s / 5,9 s (−36 dBFS) | 3 123 ms | ≈3 s | producto Fungicida DEMO; cantidad 2 L; moneda BOB; **una sola línea pese a la pausa** | precio 50 («¿50 Bs por L?», palabra extra) | 0 | 0 | confirmar «Por L», elegir proveedor |
| R5 | 12 | 6,9 s / 5,4 s (−36 dBFS) | 2 748 ms | ≈3 s | cantidad 2 L; moneda BOB | producto («Ambiguo: elija»: no se resolvió, y **tampoco se tomó otro producto parecido**); precio 90 («¿90 Bs por L?», palabra extra) | 0 | 0 | elegir producto, confirmar «Por L», elegir proveedor |
| R6 | 13 | 5,7 s / 2,5 s (−32 dBFS) | 2 585 ms | ≈3 s | — (no se inventó nada) | **ninguna línea**: «No cambió el borrador: no se reconoció nada que completar»; la app pide «Añada al menos un producto» y el proveedor | 0 | 0 | añadir la línea a mano (producto, cantidad, precio, moneda) y el proveedor |

**Resumen de la ronda con Whisper base** (turnos válidos 3, 7, 10, 11, 12, 13; el turno 8 queda fuera por mezcla con small; los turnos 4–6 se descartaron sin leer; la primera sesión, §7a, no se suma):

| Medida | Resultado |
|---|---|
| Transcripción del turno entero | 2 585–3 123 ms (mediana ≈2,75 s) con 5,7–11,9 s de audio; «Terminar»→borrador ≈3 s |
| Incorrectos aceptados sin aviso | **0** en los 6 casos |
| Líneas de más | **0** (la pausa de R4 no partió la línea) |
| Producto resuelto sin corrección | **1 de 5** en R1–R5 (R4); ambiguo 3 (R1, R3, R5); falta 1 (R2, fuera de catálogo); R6 sin línea. (El turno 1 de la primera sesión también lo resolvió, pero es otra sesión.) |
| Cantidad | correcta en los 5 casos que la tenían, incluida **1,5 L** |
| Precio unitario | nunca resuelto solo: en los 4 casos con precio unitario la cifra llegó bien pero con una palabra extra entre la cifra y la unidad (pregunta «¿N Bs por L?») |
| Precio total (R3) | en el turno válido no se extrajo importe; en el turno mezclado sí se reconoció como total. Nunca se tomó como unitario |
| Moneda | correcta en 4, «Revisar» en 1, falta en 1 |

Patrón dominante: la cifra del precio llega, pero no la forma «a N bolivianos el litro». Como el intérprete resuelve bien el texto correcto (grupo 7 de las pruebas), la causa está en lo que llega transcrito, no en el intérprete; con esta ronda no se puede decir si es la voz, el modelo o la pista. No se cambió nada durante la ronda.

### Resultados de la ronda, Whisper small (misma APK, mismas condiciones; sólo cambia el modelo)

Repetir las frases de viva voz **no es el mismo audio**: las diferencias pueden venir también de cómo se dijo cada frase. Carga de small al cambiar de modelo: 451 ms (copiado y verificado antes).

| Caso | Turno | Audio / habla | Transcripción | «Terminar»→borrador | Correctos sin corrección | Pendientes o ambiguos | Incorrectos sin aviso | Líneas de más | Correcciones necesarias |
|---|---|---|---|---|---|---|---|---|---|
| R1 | 14 | 7,0 s / 5,5 s (−36 dBFS) | **9 644 ms** | ≈10 s | producto **Herbicida DEMO**; cantidad 3 L; moneda BOB | precio 120 («¿120 Bs por L?», palabra extra) | 0 | 0 | confirmar «Por L», elegir proveedor |
| — | — | — | — | — | Reinicio de la app fuera de la vista entre R1 y R2 (proceso nuevo): el experimento se apagó, el selector volvió a base y se perdieron las métricas en memoria. Se reactivó, se eligió small y se comprobó en las métricas del turno siguiente (`variante=small`). La numeración de turnos vuelve a 1 | — | — | — |
| R2 | 1 (tras el reinicio) | 8,3 s / 3,9 s (−37 dBFS) | **9 853 ms** (carga 0 ms: small ya cargado al elegirlo) | ≈10 s | producto **Fungicida DEMO**; cantidad **1,5 L**; moneda BOB | precio 50 («¿50 Bs por L?», palabra extra) | 0 | 0 | confirmar «Por L», elegir proveedor |
| R3 | 2 (tras el reinicio) | 7,7 s / 4,6 s (−37 dBFS) | **9 732 ms** | ≈10 s | moneda BOB | producto («Ambiguo: elija», no resuelto); **cantidad «Falta»** (no se extrajo; sin leer el texto no se atribuye causa); precio «Ambiguo: se dijo un importe total» con el campo vacío: se reconoció como total, no como precio por L, pero el importe no puede comprobarse en pantalla mientras falte la cantidad | 0 | 0 | elegir producto, escribir 2 L, tocar «Total de la línea» y comprobar 100, elegir proveedor |
| R4 | 3 (tras el reinicio) | **23,0 s** / 3,6 s (−37 dBFS) | **9 617 ms** | ≈10 s | cantidad 2 L; moneda BOB; **una sola línea pese a la pausa** | producto («Ambiguo: elija», no resuelto); precio 50 («¿50 Bs por L?», palabra extra) | 0 | 0 | elegir producto, confirmar «Por L», elegir proveedor |
| R5 | 4 (tras el reinicio) | 8,1 s / 1,5 s (−32 dBFS) | **9 624 ms** | ≈10 s | producto **Insecticida DEMO** (no otro parecido); cantidad 2 L; moneda BOB | precio 90 («¿90 Bs por L?», palabra extra «que no es una moneda») | 0 | 0 | confirmar «Por L», elegir proveedor |
| R6 | 5 (tras el reinicio) | 5,0 s / 0,9 s (−29 dBFS) | **9 384 ms** | ≈10 s | — (no se inventó nada) | **ninguna línea**: «No cambió el borrador: no se reconoció nada que completar»; la app pide «Añada al menos un producto» y el proveedor | 0 | 0 | añadir la línea a mano (producto, cantidad, precio, moneda) y el proveedor |

### Intentos cancelados, no evaluables y mezclados (se conservan, no se cuentan)

| Turno(s) | Modelo | Qué pasó | Tratamiento |
|---|---|---|---|
| Primera sesión, turno 2 | base | Otro dictado; valores esperados no reconstruibles | No evaluable (§7a) |
| 4, 5, 6 (intentos previos de R2) | base | Cancelados por el autor antes de la lectura; el 5, apertura muy corta | Sólo tiempos |
| 8 + 9 (R3) | base + **small** | El selector cambió entre los dos turnos y el borrador recibió ambos | No cuenta para ninguno de los dos modelos; R3 se repitió con base (turno 10) y luego con small |
| — (entre R1 y R2 de small) | small | Reinicio de la app fuera de la vista: experimento apagado, selector en base, métricas en memoria perdidas | Se reactivó y se comprobó `variante=small` en cada turno siguiente; la numeración volvió a 1 |

### Comparación exploratoria base ↔ small (R1–R6, un intento contado por caso y modelo)

**No es una evaluación formal ni declara un ganador.** Seis frases, un hablante (el autor), un teléfono, un intento contado por caso y modelo. Repetir las frases de viva voz **no es el mismo audio**: cambian el ritmo, las pausas, el volumen y la pronunciación (habla detectada de 0,9 a 6,2 s según el turno), y la ronda small se hizo después de la base (efecto de orden). Las diferencias pueden venir del audio y no del modelo.

| Medida | Whisper base | Whisper small |
|---|---|---|
| Campos correctos sin corrección (R1–R5, 4 campos cada uno = 20) | **9 / 20** | **12 / 20** |
| Producto resuelto solo | 1 / 5 (R4) | 3 / 5 (R1, R2, R5) |
| Cantidad dictada | 5 / 5 | 4 / 5 (R3: «Falta») |
| Moneda dictada | 3 / 5 (R1 «Revisar», R3 «Falta») | 5 / 5 |
| Precio | nunca resuelto solo; 4 / 5 con el valor correcto pendiente de «Por L»; R3 sin importe | nunca resuelto solo; 4 / 5 con el valor correcto pendiente de «Por L»; R3 reconocido como **total**, valor no comprobable mientras falte la cantidad |
| R6 (incompleta) | sin línea | sin línea |
| Incorrectos aceptados sin aviso | **0** | **0** |
| Líneas de más | **0** | **0** |
| Correcciones de la línea (sin contar proveedor y «¿ya pagaste?»), R1–R5 | 11 (3 · 2 · 3 · 1 · 2) | 8 (1 · 1 · 3 · 2 · 1) |
| R6: corrección | la línea entera a mano | la línea entera a mano |
| Transcripción del turno | 2 585 – 3 123 ms (≈3 s) | 9 384 – 9 853 ms (≈10 s) |
| «Terminar» → borrador | ≈3 s | ≈10 s (unas 3,3–3,8 veces más) |

**Intervención por campo (R1–R5, 20 campos por modelo).** Una confirmación manual cuenta como intervención de la persona, no como reconocimiento correcto.

| Categoría | Whisper base | Whisper small |
|---|---|---|
| Correcto sin intervención | 9 | 12 |
| Correcto, sólo hay que **confirmarlo** (valor a la vista y correcto, marcado «Ambiguo» o «Revisar») | 5 — precio R1, R2, R4, R5 («¿N Bs por L?»); moneda R1 («Revisar») | 5 — precio R1, R2, R4, R5; precio R3 (total reconocido, pero **la cifra no se veía** en pantalla hasta la versión de §9) |
| Valor **incorrecto que hay que editar** | 0 | 0 |
| **Ausente**: hay que elegir o escribir (Falta, o Ambiguo sin valor) | 6 — producto R1, R2, R3, R5; precio R3; moneda R3 | 3 — producto R3, R4; cantidad R3 |

R6 (sólo producto esperado): en los dos modelos el borrador quedó **sin línea**; el producto quedó ausente.

Lectura prudente:

- En esta ronda small dejó más campos útiles sin tocar, sobre todo el **producto** (3 frente a 1) y la **moneda** (5 frente a 3). Base fue mejor en R4 (resolvió el producto) y en R3 (sacó la cantidad). Caso a caso: small mejor en R1, R2, R5; base mejor en R4; empate en R3 (1 y 1, en campos distintos) y R6.
- **Ninguno aceptó un dato erróneo sin aviso** ni creó líneas de más: los fallos quedaron como «Falta» o «Ambiguo». Esto es lo que protege el borrador, con cualquiera de los dos.
- El **precio por unidad no se resuelve solo con ninguno de los dos**: la palabra extra entre la cifra y la unidad aparece en los dos modelos, así que no se atribuye a uno de ellos (§7a); queda la decisión de diseño de cómo tratarla, sin aceptar cualquier palabra intermedia.
- R6 no dio el producto con ninguno. Con texto escrito («Compré fungicida demo», con y sin punto, en mayúsculas o sin tilde) el recorrido intérprete → línea → borrador → pantalla **sí** deja una línea incompleta (§9): el fallo no está en el intérprete con ese texto, y sigue **pendiente localizarlo en el recorrido real**. Sin leer lo transcrito no se atribuye causa.
- El coste de small es la **espera**: unos 7 s más por turno en el POCO, y 185 MB más de APK.
- Para decidir haría falta más intentos por caso, el mismo audio grabado (con consentimiento) o más hablantes; con un intento por caso la diferencia de 3 campos puede ser ruido.

## 9. Corrección del intérprete de precios y diagnóstico de borradores incompletos (2026-11-10)

**Versión nueva**, posterior a las dos rondas: las mediciones anteriores (§7a, R1–R6 base y small) se hicieron con `e9b3d66` y **no se recalculan**. Las mediciones con esta versión van aparte (§9.4). Modelo provisional para las pruebas siguientes: **Whisper base**, por su menor espera; small sigue empaquetado y seleccionable, sin declararlo mejor ni peor.

### 9.1 Qué se corrigió (con prueba que lo reproducía antes)

Seis pruebas de reproducción se ejecutaron primero contra el código de `4a2f324` (**las seis fallaron**) y después contra el corregido (pasaron). Quedaron incorporadas en `test/voice_draft/compra_precio_total_test.dart` (unidad, 22 pruebas) y `compra_precio_total_pantalla_test.dart` (pantalla con puerto simulado, 4 pruebas).

| Frase escrita (sintética) | Antes (`4a2f324`) | Ahora |
|---|---|---|
| «dos litros … por un total de cien bolivianos» | importe 1,00, total, pendiente; precio suelto sobrante; «Total de la línea» → 0,50 Bs/L | importe **100,00**, total, pendiente, con la cifra a la vista («Importe total oído: 100 Bs (sin confirmar)»); «Total de la línea» → **50 Bs/L**, origen *confirmado* |
| «dos litros … a cien bolivianos en total» | total 100, pendiente; el aviso no decía la cifra | igual, y el aviso dice la cifra |
| «dos litros … a cincuenta bolivianos por litro» | 50 Bs/L resuelto, total 100 | sin cambios |
| «un litro y medio … a cincuenta bolivianos por litro» | 1,5 L, 50 Bs/L, total 75 | sin cambios |
| «dos litros … a cien bolivianos» (sin unidad ni «total») | candidato 100 pendiente; «Por L» o «Total de la línea» | sin cambios (las dos salidas son intervención de la persona) |
| «… por un total de cien bolivianos el litro» (los dos tipos a la vez) | — | candidato 100 **sin tipo**, pendiente: la persona elige |
| «a cincuenta bolivianos el litro por un total de ciento veinte» (no cuadran) | **50 Bs/L resuelto** en la línea y un aviso aparte | precio **ambiguo y sin valor**: «Se oyeron dos importes que no cuadran»; no se puede registrar |
| «a cincuenta bolivianos el litro, en total cien» (cuadran con 2 L) | 50 resuelto y aviso aparte | 50 Bs/L resuelto (los dos importes coinciden) |
| «dos litros de A y cuatro litros de B por un total de doscientos» | total 1,00 en la línea de B | **ninguna línea recibe el total**: B queda ambiguo y sin valor («no se sabe si es de esta línea o de toda la compra») |
| «Total de la línea» con la cantidad aún vacía | el precio pasaba a no válido **y se perdía la cifra** (lo que ocurrió en R3 con small) | la cifra se conserva como candidata; con la cantidad escrita, se reparte |

Reglas que no cambian: un total nunca se registra como precio por unidad; se reparte sólo si da centavos exactos (no se redondea); no se acepta cualquier palabra entre el importe y la unidad (la «palabra extra» sigue preguntando «¿N Bs por L?»); un importe que no se sabe si es unitario o total sigue pidiendo elegir. «un» fuera de «un total» sigue siendo la cifra 1 («a un boliviano el litro»). Dos importes seguidos se comparan sólo si el primero está completo (moneda, unidad o «total»): «a 45, 50 bolivianos el litro» sigue tratándose como antes (prueba existente).

**Confirmación en pantalla** (revisada): «Por L» (precio por litro) y «Total de la línea» aparecen cuando el precio tiene una cifra candidata sin tipo; con un total dicho sólo aparece «Total de la línea»; «corregir importe» es escribir en el campo «Precio por L» (queda *corregido a mano*). Ninguna de las tres es reconocimiento automático: el campo queda con origen *confirmado* o *manual* y así se cuenta en las rondas.

### 9.2 R6: «Compré fungicida demo» con texto escrito

Recorrido intérprete → propuesta de línea → incorporación → pantalla, con «Compré fungicida demo», «Compré fungicida demo.», «Compré Fungicida DEMO.» y «compre fungicida demo»: en todos queda **una línea** con Fungicida DEMO, cantidad, precio y moneda pendientes, «Aplicado al borrador» y el registro deshabilitado. «compré fungicida de mo» (nombre partido) no abre línea y avisa que no está en el catálogo. Por tanto, **con ese texto el fallo no está en el intérprete**, y sigue pendiente localizarlo en el recorrido real (transcripción u otro paso).

Diagnóstico añadido, **sin texto** (sólo en compilaciones de diagnóstico): por cada dictado aplicado, una línea `voz compra:` con número de palabras (0 = transcripción vacía), operación reconocida, cantidades y precios sueltos encontrados, por cada línea propuesta la coincidencia en el catálogo (`unico`, `varios`, `ninguno`, `sin-nombre`) y su destino (`nueva`, `existente`, `aviso`), el resultado del «producto sin cantidad» (`unico-nueva`, `ninguno-aviso`, `descartado`, `no-aplica`…), campos aplicados y conservados, y un código de motivo (`ok`, `vacio`, `otra-operacion`, `sin-linea`, `aviso`, `precio-no-colocado`, `sin-cambios`). Una prueba comprueba que la línea no lleva el nombre del producto ni lo dictado.

### 9.3 Validación (HOST)

`flutter analyze` sin avisos; `test/voice`, `test/voice_draft` y `test/voice_evidence`: **748/748**. Suite completa de la app (`flutter test --timeout 120s`, 2026-11-10 08:31–08:34, código de `8afead0`): **2849 pasan, 3 omitidas, 0 fallan** (otras rutas de voz —aplicación, planificación, salida del borrador— incluidas). Un primer intento de la suite completa quedó detenido sin consumir CPU durante más de una hora y se canceló; al repetirlo con límite por prueba terminó sin fallos. Se actualizaron tres pruebas que fijaban el comportamiento anterior: el defecto anotado (ahora 100,00), el total sin cantidad (ahora conserva la cifra) y el texto exacto del aviso de total (ahora lleva la cifra).

### 9.4 Ronda posterior a la corrección (APK `64d6c5a`, **sólo Whisper base**, POCO, 2026-11-10 08:40–09:22)

**Otra versión y otra ronda**: no se suma a §7a ni a R1–R6. APK aislada `.f09w` compilada de `64d6c5a` (SHA-256 `cce5313da852f11208556a737ada507d92158ca313a16632a81b2efe28a2b035`, 347 558 137 B; mismos 174 archivos y mismos modelos que `e9b3d66`, sólo cambia `libapp.so`), instalada encima con `pm install -r` conservando datos; `.f09` sin tocar. Experimento encendido, **base** comprobado en el selector y en cada turno (`variante=base`). Con small no se hizo ninguna ronda con esta versión. Se conservan todos los intentos. 0 compras registradas.

| Turno | Caso previsto | Palabras | Diagnóstico (`voz compra:`) | Producto | Cantidad | Precio | Moneda | Intervención necesaria | Habla / audio | Transcripción |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | — (no previsto) | 3 | compra; sin línea; `mencion=descartado` | — | — | — | — | — | 1,65 / 4,62 s | 2 866 ms |
| 2 | **C1** precio unitario (Fungicida, 2 L, 50 Bs/L) | 15 | `unico/nueva`, `ok` | ✓ | ✓ 2 L | **✓ 50 Bs/L resuelto** | ✓ BOB | ninguna (total 100,00) | 5,15 / 10,36 s | 2 691 ms |
| 3 | **C2** total, intento 1 (Fungicida, 2 L, «por un total de» 100) | 11 | intención **none**; `medidas=0`; `precios-sueltos=0`; `sin-verbo-aviso` | ausente (aviso) | ausente | ausente | ausente | la línea entera | 4,70 / 8,24 s | 2 809 ms |
| 4 | **C2** total, intento 2 | 14 | `unico/nueva`, `ok`; `precios-sueltos=0` | ✓ | ✓ 2 L | **ausente** | **ausente** | escribir el precio, elegir la moneda | 6,00 / 15,18 s | 2 814 ms |
| 5 | — (no coincide con C3) | 12 | `sin-nombre/nueva` | ausente | dictada | ausente | ausente | — | 4,30 / 14,54 s | 2 745 ms |
| 6 | — (mismo borrador que 5) | 12 | `varios/nueva` | ambiguo | dictada | dictado | dictada | — | 5,75 / 9,32 s | 3 042 ms |
| 7 | **C3** sólo producto (Fungicida) | 7 | compra; `medidas=0`; **`sin-verbo-aviso`** | ausente (aviso, sin línea) | — | — | — | la línea entera | 2,25 / 5,70 s | 2 593 ms |
| 8 | **C3** repetido (borrador limpio) | 8 | compra; `medidas=0`; **`sin-verbo-aviso`** | ausente (aviso, sin línea) | — | — | — | la línea entera | 2,95 / 4,48 s | 2 898 ms |

Lectura:

- **C1** es el primer precio por unidad resuelto solo en el teléfono (4 de 4 campos sin intervención).
- **C2**: la corrección del total **no se ha observado en el teléfono**: en ningún intento se reconoció un importe. El autor confirmó que lo oído no llevaba «$»; la causa no está localizada (sondas escritas en §9.5).
- **C3**: la intención de compra se reconoció, pero el producto se rechazó con `sin-verbo-aviso`. Con frases sintéticas esa combinación sólo aparece si el verbo no es la primera palabra o no es «compré/compre/compramos» (§9.5). Qué variante hubo en el teléfono: sin verificar.
- Turnos 1, 5 y 6: fuera del guion; se conservan y no se cuentan.

### 9.5 Sondas escritas posteriores (sintéticas, sin texto del teléfono, sobre `64d6c5a`)

| Forma escrita | Resultado en `64d6c5a` |
|---|---|
| «por un total de 100Bs» (unidad pegada) | precio no válido, sin moneda |
| «por un total de 100.00 bolivianos» (punto decimal) | precio no válido |
| «en un total de 100 bolivianos» | importe suelto, sin colocar |
| «para / con un total de 100 bolivianos» | el producto pasa a «varios» y el precio no es válido |
| «por un total de $100» | precio y moneda ausentes (la única forma que reproducía C2; descartada por el autor) |
| «Hoy / Bueno / Yo compré fungicida demo» | sin línea, `sin-verbo-aviso` |
| «Compra / Comprar / He comprado fungicida demo» | sin línea, `sin-verbo-aviso` |
| «Compré el / un fungicida demo», «Compré fungicida demo hoy / para la campaña» | producto ambiguo |

## 10. Whisper small como transcriptor del turno entero (2026-11-10)

**Decisión del autor** (2026-11-10): seguir con Whisper small en el modo de turno entero, por prioridad de precisión aunque la espera sea mayor. **No es una superioridad demostrada**: la comparación de §7a/R1–R6 es exploratoria y no se continúa. Versiones separadas: intérprete `b673523`; decodificación y pista `339a6ce`.

### 10.1 Intérprete (`b673523`)

Las formas de §9.5 se reprodujeron primero con pruebas escritas (**36 fallaban** sobre `da2aca0`) y después se corrigieron:

| Forma (sintética) | Ahora |
|---|---|
| «100Bs», «50Bs.», «50 Bs. el litro» | cifra y sigla se separan; el punto de «Bs.» no es una pausa |
| «100.00», «1.5» | punto con una o dos cifras = decimal (no puede separar miles). «1.500» sigue siendo 1 500 (es-BO) y «1,500» sigue **sin leerse** (ambiguo) |
| «en / con / para / por un total de N» | total de la línea, **por confirmar**; con varias líneas no se asigna a ninguna; «para el chaco» no cambia |
| «el / un / la fungicida demo» | sin el artículo inicial **sólo si** así coincide exactamente con un único producto |
| «fungicida demo hoy / ayer / esta mañana» | sin la expresión de tiempo final, con la misma condición; «para la campaña» no se quita |
| «Hoy / Bueno / Yo compré …», «He comprado …», «Compra (de) …» | el verbo puede no ser la primera palabra (sólo tras muletillas, tiempo o sujeto) y vale en las formas que ya reconocía la intención |
| «Compré fungicida demo» (y las anteriores) | línea incompleta; no se puede registrar |

Controles añadidos: «no compré», «nunca compramos», «quiero / voy a / tengo que / necesito comprar» y «compraré» no anotan nada y lo dicen (`motivo=negacion` / `intencion-futura`); «No, compré …» (con pausa) sí es una compra. Nombres parecidos («Fungicida DEMO» / «Fungicida DEMO Plus») y nombres con palabras aparentemente prescindibles («El Tigre», «Total 500», «Fungicida Hoy», «Ahora Plus») resuelven al producto correcto; «fungicida» solo sigue pidiendo elegir. Cifras contradictorias siguen sin valor. Sólo en la compra: `tokenize` y `readNumberAt` compartidos no cambian (al cambiarlos fallaron 4 pruebas de la revisión por frases, que trata «1.5» como no legible a propósito; el ajuste se movió al intérprete de compras).

Pruebas separadas: intérprete `compra_formas_transcritas_test.dart` (57), controlador del borrador `compra_formas_borrador_test.dart` (6), pantalla `compra_formas_pantalla_test.dart` (3).

### 10.2 Configuración real de small (`339a6ce`)

| Qué | Valor | Dónde se comprobó |
|---|---|---|
| whisper.cpp | **1.9.3-dev**, commit `52a939a2a762224e255d366c1182b2af4dd1a032` (tarball SHA-256 `6212572f…4a19`) | `build_whisper_libs.sh`; `CMakeLists.txt` del código fijado |
| Modelo | `ggml-small-q5_1.bin`, small **multilingüe**, 190 085 487 B, SHA-256 `ae85e4a9…11bb` | ZIP del APK (mismo CRC que en `e9b3d66`) |
| Idioma / tarea | `language="es"`, `detect_language=false`, `translate=false` | `whisper_jni.c` |
| Decodificación | `WHISPER_SAMPLING_BEAM_SEARCH`, `beam_size=5` (5 decodificadores), `temperature=0` | `transcribe_impl` vía `transcribeWith` (nuevo); el motor informa `haz=5` en cada turno |
| Reintentos | `temperature_inc=0`: una sola temperatura. En `whisper_full_with_state` sólo se reintenta si quedan temperaturas, así que `entropy_thold` (2,4), `logprob_thold` (−1) y `no_speech_thold` (0,6) **no provocan otra pasada**; la entropía sólo puede descartar un decodificador del haz | código fijado (bucle de temperaturas y condición de éxito) |
| Contexto | `no_context=true` (nada de un turno anterior), `initial_prompt` = pista, `carry_initial_prompt=false`, `single_segment=true`, `no_timestamps=true`, `suppress_blank`, `suppress_nst` | `whisper_jni.c` |
| Hilos | `min(4, núcleos)` | `LocalVoiceEngine.threads()` |
| Topes | grabación 30 s; transcripción 45 s con aborto + guarda de 20 s en Dart; cancelar aborta y descarta; un resultado de un turno anterior no toca el actual | sin cambios: en el teléfono la transcripción tardó 10,2–12,0 s |
| Volver atrás | `VoiceExperiment.turnDecoding = WholeTurnDecoding.greedy` (voraz, la anterior) y/o `turnVariant = 'base'`; `transcribe` voraz se conserva y la revisión por frases lo sigue usando | `voice_engine_diagnostics.dart`, `WhisperNative.kt` |

`libagro_whisper.so` se recompiló (arm64-v8a y x86_64) desde el mismo commit; exporta `transcribe` y `transcribeWith`.

### 10.3 Pista

Antes: términos del dominio (incluidas hectáreas y familias) + productos, personas, proveedores, chacos y campaña, con tope de 600 caracteres. whisper.cpp admite como mucho `n_text_ctx/2 − 1` = **223 tokens** de pista y, si se pasa, **recorta el principio en silencio**. Medido en HOST con el tokenizador real (aviso de `--carry-initial-prompt` con relleno conocido): ≈2,4 caracteres por token con nombres de productos, así que 600 caracteres ≈ 245–250 tokens (se pasaba con catálogos grandes).

Ahora (sólo turno entero de compra): productos de la cuenta, unidades de esos productos, monedas admitidas (bolivianos, dólares) y expresiones de precio («por litro», «el litro», «en total», «por un total de»); tope de 400 caracteres (≈170 tokens). Para el catálogo del POCO: «Herbicida DEMO, Fungicida DEMO, Insecticida DEMO, litro, litros, bolivianos, dólares, por litro, el litro, en total, por un total de.» = 133 caracteres ≈ **49 tokens** (la anterior: 218 caracteres ≈ 80 tokens). Sin cantidades ni precios, sin proveedores, personas ni chacos, sin nada de un turno anterior (`no_context`). Cada producto una vez: la pista orienta, no elige; el intérprete sigue sin aproximar nombres.

### 10.4 Captura (revisada, sin cambios)

`AudioRecord` `VOICE_RECOGNITION`, 16 kHz mono PCM16 (el POCO entrega 16 000 Hz reales, 1 canal, formato 2), bloques de 100 ms, cola de 3 s (si se llenara se perdería lo más viejo, y se cuenta), conversión a flotante `/32768`, sin ganancia ni filtros. Al terminar: `stop()` + `release()`; el audio vive sólo en memoria y se suelta al transcribir o cancelar. No había evidencia para tocar nada; se añadió a la métrica del turno el silencio inicial y final y el audio perdido. En la comprobación (§10.6): **0 ms perdidos** y 400–2 550 ms de silencio final en todos los turnos (ningún indicio de sílabas finales cortadas).

### 10.5 Cuantización (HOST, audio **sintético**; no es teléfono ni voz humana)

`whisper-cli` del mismo commit, 4 hilos, pista de banco, frases de compra f01, f04, f15 y f16 × 3 voces TTS de Windows = 12 grabaciones por configuración. Modelos verificados contra el oid LFS de `ggerganov/whisper.cpp`: q8_0 264 464 607 B (`49c8fb02…779f`), f16 487 601 967 B (`1be3a9b2…987b`).

| Configuración | Exactas | Producto | Cifras | Codificación | Decodificación | Total | Pico RSS |
|---|---|---|---|---|---|---|---|
| q5_1 voraz (anterior) | 6/12 | 9/12 | 12/12 | 2 168 ms | 336 ms | 2 694 ms | 390 MB |
| q5_1 haz 5, sin reintentos (**actual**) | 6/12 | 9/12 | 12/12 | 2 164 ms | 536 ms | 2 981 ms | 511 MB |
| q5_1 haz 5 con reintentos por defecto | 6/12 | 9/12 | 12/12 | 2 163 ms | 531 ms | 2 976 ms | 511 MB |
| q8_0 haz 5 | 7/12 | 10/12 | 12/12 | 1 608 ms | 473 ms | 2 465 ms | 581 MB |
| f16 haz 5 | 8/12 | 10/12 | 12/12 | 2 155 ms | 577 ms | 3 237 ms | 798 MB |

Haz 5 frente a voraz: **mismo texto en las 12**; los reintentos **no se activaron** en ninguna. q8_0 y f16 difieren en una o dos grabaciones (palabras pegadas: «Comprade», «Mancozeba»): con N = 12 sintéticas no demuestra una mejora. **Se conserva q5_1**; q8_0 (+74 MB de APK) o f16 (+298 MB) quedan como opción documentada, a comparar sobre el mismo audio grabado con consentimiento.

### 10.6 Comprobación breve en el teléfono (APK `339a6ce`, small + haz 5, POCO, 2026-11-10 10:34–11:06)

APK `.f09w` SHA-256 `f5a25a37b5c46bedbfd8a8dc8554c6c513442189ef303c83783fd88681f9e6c5` (347 558 137 B), instalada con `pm install -r` conservando datos; `.f09` sin tocar. Experimento encendido tras reiniciar la app; selector en small; «Decodificación: haz de 5». Cada intento se anota; **ninguno se repitió hasta acertar**. 0 compras registradas.

| Turno | Caso | Producto | Cantidad | Precio | Moneda | Intervención | Errores sin aviso | Transcripción |
|---|---|---|---|---|---|---|---|---|
| 1 | (sin leer; mismo borrador que el 2) | único en catálogo (código) | dictada | — | — | — | — | 10 993 ms |
| 2 | (sin leer; descartado por el autor) | ambiguo (código) | dictada | — | — | — | — | 11 552 ms |
| 3 | **P1** unitario (Fungicida, 2 L, 50/L) | ✓ | ✓ 2 L | 50 ✓ **por confirmar** (preposición entre cifra y unidad) | ✓ | confirmar «Por L» | 0 | 11 126 ms |
| 4 | **P2** total (Insecticida, 2 L, «por un total de» 100) | ✓ | ✓ 2 L | **«Importe total oído: 100 Bs (sin confirmar)»** ✓ | ✓ | «Total de la línea» → 50 Bs/L confirmado ✓ | 0 | 11 516 ms |
| 5 | **P3** decimal y nombre (Herbicida, 1,5 L, 80/L) | ✓ | ✓ 1,5 L | ✓ 80 resuelto | ✓ | ninguna (total 120,00 ✓) | 0 | 12 004 ms |
| 6 | **P4** sólo producto (Fungicida) | **ausente** (sin línea) | — | — | — | la línea entera | 0 | 10 205 ms |
| 1 (APK `a340bbb`) | **P4** repetido tras corregir el verbo pegado (§10.8) | ✓ Fungicida DEMO, **una** línea | falta | falta | falta | — (línea incompleta, como se esperaba; no se puede registrar) | 0 | 10 564 ms |

P2 entró en el mismo borrador que P1 (no se descartó entre ambos): fue la línea 2 y la línea 1 no cambió. El toque de «Total de la línea» lo hizo la sesión por adb, sin registrar; cuenta como intervención. P4: 3 palabras, **ningún verbo de compra reconocido** y el nombre sin coincidencia ni aproximada (`mencion=descartado`): lo transcrito no coincide con la frase prevista ni en el verbo ni en el producto; sin leer el texto no se atribuye causa.

### 10.7 Comprobado y por comprobar

- **Comprobado (texto escrito)**: los defectos de §9.5 y los controles de §10.1.
- **Observado una vez en el teléfono**: el total por confirmar con su cifra y el reparto a 50 Bs/L (P2); 1,5 L y un precio por unidad resuelto sin preguntar (P3). Un intento por caso: no es una tasa.
- **P4 (sólo producto)**: con `339a6ce` quedó sin línea porque el verbo y el producto llegaron en **una sola palabra** (el autor lo confirmó mirando lo oído, sin copiarlo); corregido en `a340bbb` (§10.8) y, repetido una vez, dio la línea incompleta esperada.
- **Hipótesis**: que haz 5, la pista nueva o q8_0/f16 mejoren el reconocimiento con voz humana. En HOST, con voz sintética, haz 5 no cambió nada y la cuantización mayor cambió 1–2 de 12.
- **Coste comprobado**: 10,2–12,0 s de transcripción por turno en el POCO con small + haz 5 (small voraz en R1–R6: 9,4–9,9 s; otra ronda y otro audio).

### 10.8 Verbo pegado a la palabra siguiente (`a340bbb`)

Causa de P4 en `339a6ce`, dicha por el autor con un sí/no sobre lo oído (sin copiar el texto): el verbo y el producto llegaron como **una sola palabra** y «demo» aparte; la intención no se reconoció y el nombre no se parecía a ningún producto (`mencion=descartado`). En HOST, con voz sintética, ya se había visto «Comprade». Corrección (sólo en la compra): una palabra que empieza por una forma del verbo («compraron», «compramos», «comprado», «compre», «compra») se separa **sólo** si lo que sigue es exactamente una palabra de un producto del catálogo de la cuenta, «de/del», un artículo, un número o una unidad. «Comprador», «comprender» o «comprefungi» no se parten; «No comprefungicida demo» sigue siendo una negación. Reproducido antes con 6 pruebas que fallaban; ahora 64/64 del intérprete, pantalla incluida; suite completa 2932 pasan, 3 omitidas, 0 fallan. APK `.f09w` `a340bbb`, SHA-256 `4770e8210ba0340e84771226f045c6b58851cbc727743f089568ed79c3daacb8`, instalada a las 11:34:44 (datos conservados; `.f09` sin tocar). Un intento de P4 en el teléfono: línea incompleta correcta (§10.6).

## 11. Cierre del bloque: versión final y prueba de registro (2026-11-10)

**Configuración elegida por el autor** (2026-11-10): Whisper small con haz de 5 para la compra por voz en turno entero. Se deja de experimentar con modelos, cuantizaciones y parámetros. Es una decisión por prioridad de precisión, **no una superioridad demostrada**.

### 11.1 Versión final

| Qué | Commit / archivo |
|---|---|
| Código con todas las correcciones | **`a340bbb`** (incluye `8afead0`, `b673523`, `339a6ce`) |
| Prueba P1–P4 sobre la versión final (sólo pruebas) | `98d4132` |
| Documentación | `5ce3fdb` y este apartado (sólo `docs/`) |
| Instalada en `.f09w` «AC F09 WT» | APK de `a340bbb`, SHA-256 `4770e8210ba0340e84771226f045c6b58851cbc727743f089568ed79c3daacb8` (comprobado en el teléfono); `.f09` sin tocar (18:09:22 del 09-11) |

Entre `a340bbb` y el último commit sólo cambian `docs/` y `test/`: lo instalado es el código final.

### 11.2 Pruebas automatizadas (HOST)

| Prueba | Resultado |
|---|---|
| `compra_p1_p4_final_test.dart`: P1 resuelto con «el litro» y por confirmar con preposición («Por L» = intervención); P2 total por confirmar → «Total de la línea» = 50 Bs/L, total 100, sin redondear lo inexacto; P3 1,5 L × 80 = 120 (tres formas); P4 línea incompleta, registro bloqueado, sin escritura (dos formas); el verbo pegado da los mismos campos en P1–P3 | pasa |
| P1–P4 junto con negaciones, ambigüedad, total, pantalla, cancelación y resultados tardíos del turno entero, salida del borrador (12 archivos) | **211/211** |
| Suite completa de la app (`flutter test --timeout 120s`, código `a340bbb` + prueba P1–P4) | **2940 pasan, 3 omitidas, 0 fallan** |

### 11.3 Verificación en el teléfono (POCO, small + haz 5)

Clasificación por campo. Una confirmación o una elección es **intervención de la persona**, no reconocimiento automático. «Corrección de valor» = cambiar un valor dictado que estaba mal.

| Caso (APK) | Resueltos automáticamente | Confirmaciones o elecciones manuales | Correcciones de valores | Ausentes |
|---|---|---|---|---|
| P1 unitario (`339a6ce`, turno 3) | producto, cantidad, moneda | **precio: confirmar «Por L»** (50 correcto, preguntado) | 0 | — |
| P2 total (`339a6ce`, turno 4) | producto, cantidad, moneda | **precio: elegir «Total de la línea»** (100 → 50 Bs/L) | 0 | — |
| P3 decimal y nombre (`339a6ce`, turno 5) | producto, 1,5 L, 80 Bs/L, moneda | — | 0 | — |
| P4 sólo producto (`339a6ce`, turno 6) | — | — | 0 | la línea entera (verbo pegado; §10.8) |
| P4 sólo producto (`a340bbb`, turno 1) | producto | — | 0 | cantidad, precio, moneda (lo esperado) |
| **Registro final** (`a340bbb`, 12:23–12:30) | producto Herbicida DEMO, 2 L, 50 Bs/L, BOB (total 100,00) | **proveedor elegido** (Agro insumos DEMO); **«Sí, pagué todo»**; destinatario Rosa Mamani WT y campaña aceptados como los propuso la app; medio de pago sin elegir | 0 | — |

Errores aceptados sin aviso: 0 en todos. Líneas de más: 0.

**Prueba de registro.** Datos sintéticos de `.f09w` (titular Rosa Mamani WT, compartido, BY_ACTUAL_USAGE; proveedor Agro insumos DEMO; campaña Invierno 2026 WT). Antes: todas las tablas en 0. Efectos esperados, fijados antes de confirmar, y obtenidos tras un solo toque de «Registrar compra» (12:30:23):

| Tabla | Esperado | Obtenido |
|---|---|---|
| `purchases` | 1: proveedor 1, campaña 1, BOB, 10 000, CONFIRMED | igual |
| `purchase_items` | 1: Herbicida, 2 000 mL, 5 000 → 10 000 | igual |
| `purchase_allocations` | 1: Rosa, 2 000, BY_ACTUAL_USAGE, sin importe | igual |
| `inventory_lots` | 1: Rosa, 2 000, 5 000 por L | igual (sin vencimiento ni número de lote) |
| `inventory_movements` | 1: PURCHASE_IN +2 000 | igual |
| `account_transactions` | 0 (el cargo llega al aplicar) | 0 |
| `provider_payments` | 1: titular, 10 000, misma fecha | igual (medio UNSPECIFIED) |

Sin duplicados; `sync_outbox` 0; `integrity_check` ok. **Persistencia**: se cerró la app (`force-stop`, sin proceso) y se volvió a abrir (proceso nuevo): Inicio con Compras 100,00 Bs y Pagado proveedores 100,00 Bs, por cobrar 0,00; Inventario con Herbicida DEMO «Físico 2 L» (y el aviso «1 sin fecha registrada», por no indicarse vencimiento); la base, con los mismos conteos.

### 11.4 Turnos no evaluables (se conservan, no se valoran)

No se reconstruyen sus valores esperados: primera sesión, turno 2 (§7a); base `e9b3d66`, turnos 4–6 y la mezcla 8 + 9 (§7a); base `64d6c5a`, turnos 1, 5 y 6 (§9.4); small `339a6ce`, turnos 1 y 2 (§10.6).

### 11.5 Privacidad

No se guardó audio ni transcripción real: sólo campos, códigos (`voz turno:`, `voz compra:`), tiempos y respuestas sí/no del autor. Los textos de este informe son frases previstas o sintéticas.

## 8. Limitaciones conocidas

- Sin texto provisional en el modo experimental: el usuario no ve nada hasta «Terminar».
- 30 s por turno; con más audio el turno termina solo.
- small pesa 190 MB: el APK pasa de 148 a 333 MB y la primera carga del modelo tarda más (se mide en el teléfono).
- «por todo» no se reconoce como total (sí «en total»).
- El experimento no se guarda: hay que encenderlo en cada arranque de la app.
- No hay prueba instrumentada del turno entero con audio de referencia.
- Los interruptores de diagnóstico «política B» y «comparar pistas» siguen visibles en la pantalla de compra pero **no tienen efecto** en el modo experimental (actúan sólo sobre la ruta por frases).
- (§9) Dos importes que no cuadran se detectan sólo si van **seguidos** en la misma línea; un importe dicho más lejos (otra frase, otro producto en medio) no se compara.
- (§9) Un total dicho al final de un dictado con **varias líneas** nunca se asigna: queda sin valor y la persona escribe el precio de cada línea. No se reparte entre líneas.
- (§9) El total se reparte sólo si da centavos exactos; si no, se pide el precio por unidad (no se redondea).
- (§10) La pista limita su tamaño por caracteres (400 ≈ 170 tokens), no por tokens reales: un catálogo de nombres muy raros podría acercarse al límite de 223.
- (§10) El transcriptor a veces pega palabras («Comprade», «Mancozeba», en HOST con voz sintética): el intérprete no las separa.
- (§10) Un artículo o una expresión de tiempo sólo se quitan en los extremos del nombre; otras palabras («para la campaña») siguen pidiendo elegir.
- (§10) «1,500» sigue sin leerse y «1.500» se lee como mil quinientos, como en los formularios.
- (§10) El verbo pegado sólo se separa si lo que sigue es exactamente una palabra conocida (producto del catálogo, enlace, artículo, número o unidad); un producto mal transcrito pegado al verbo sigue sin línea.
- (§9) R6: con texto escrito el recorrido funciona; la causa en el recorrido real **no está localizada**. El diagnóstico `voz compra:` existe sólo en compilaciones de diagnóstico y no lleva texto, así que distingue «transcripción vacía», «producto no encontrado» o «línea no incorporada», pero no qué palabras se oyeron.
