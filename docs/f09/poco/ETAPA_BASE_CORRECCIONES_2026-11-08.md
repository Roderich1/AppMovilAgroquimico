# F09 con Whisper base: correcciones tras las pruebas en el POCO (2026-11-08)

## 1. Decisión del autor y alcance

Roderich probó Whisper small en el POCO y percibió mayor lentitud sin una mejora suficiente. Decidió:

- **Whisper base** sigue como configuración de trabajo (ADR-005, provisional);
- el trabajo de optimización de small se detiene.

Esta decisión **no es una validación formal de base contra small**. La comparación se hizo con dictados distintos y sin audio grabado. #166 pide small y queda **pendiente de conciliar su alcance**: no se cierra como si small estuviera validado. #12 no se ejecuta y #17 sigue Pending.

## 2. Observaciones exploratorias con small (no son un resultado de #166)

Variante aislada `.f09sm` («AC F09 Small»):

- **APK:** `agrocuentas-f09sm-2684947-arm64-v8a-profile.apk`, SHA-256 `20af99effc14e6df2ca5fd1bc9a3144e8b98ca6b01ffd8b26b9a9d8b99a2a440`.
- **Modelo:** `ggml-small-q5_1.bin`, SHA-256 `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb`, licencia MIT.
- **Mismo código que la base:** `libapp.so` y las librerías nativas son idénticas a las de la base `2684947`. Solo cambian el modelo, su manifiesto, el paquete y la etiqueta.
- **Teléfono:** POCO X5 Pro `22101320G`, sin red. Dictó Roderich entre las 22:55 y las 22:57 (hora del teléfono). Registro técnico sin contenido dictado.

| Medida | Resultado |
|---|---|
| Guarda de capacidad | `review-ok`: el teléfono tiene 7,0 GiB de memoria total y small exige 3 400 MiB |
| Preparación en frío | Copia y verificación del modelo de 190 MB: unos 2,4 s. Carga: 242 ms |
| Frases | 6 |
| Límite de 5 000 ms | **Agotado en las 6.** El formulario recibió el texto de Vosk (`timedOut`) |
| Resultado de small | Llegó entre 4,5 y 5,8 s **después** de agotarse el límite, y se descartó como tardío |
| Valor del límite | Sin cambios |

**La inferencia sigue después de agotarse el límite.** Causa comprobada en el código de whisper.cpp `52a939a` (`src/whisper.cpp`):

- el aborto solo se consulta al terminar el codificador (línea 2504) y entre pasos de decodificación (línea 3026);
- el grafo del codificador se calcula sin función de aborto (`ggml_graph_compute_helper(sched, …)`, líneas 2440, 2480 y 2496).

Por eso, al agotarse el límite, el codificador sigue hasta acabar y ocupa la CPU unos segundos más. **El formulario no se ve afectado**: el resultado tardío se descarta.

Con base, la revisión tardó entre 2,6 y 3,5 s en todas las frases medidas el 2026-11-08, sin agotar el límite. Queda como limitación: no se parchea whisper.cpp en esta etapa.

**Propuesta, no ejecutada:** una prueba diagnóstica separada de small con un límite mayor, solo para medir la inferencia completa. Iría claramente separada de la configuración candidata para uso normal.

## 3. Defectos de esta etapa: diagnóstico por etapas

Las etapas son: captura → transcripción → interpretación → catálogo → formulario → persistencia. Todo lo de esta tabla se reprodujo con **texto inyectado** al intérprete o a la pantalla; ningún caso se da por superado en el teléfono por esto.

| # | Defecto | Etapa | Causa comprobada | Corrección | Prueba |
|---|---|---|---|---|---|
| 1 | Caso A en el POCO (`2684947`): el precio quedó «¿por litro o kilo?» | Transcripción, probable | La frase escrita tal cual da 120 Bs/L y 600 Bs (`compra_interpretacion_test`). En el teléfono, lo reconocido no traía una unidad clara. **No se atribuye a un motor:** Roderich comprobará en pantalla si lo oído contiene «el litro» | Ninguna en el intérprete. En el formulario, elección breve (#3) | — |
| 2 | «a … bolivianos por cada litro» quedaba ambiguo | Interpretación | `_readClause` solo aceptaba «el/la/por/cada» + unidad | «por cada» y «por el/la» + unidad son precio por unidad | `compra_lineas_y_precio_test` («por el kilo», «por cada kilo») |
| 3 | Un precio sin unidad solo ofrecía «Sí, es el precio por L»; un total dicho quedaba no válido, sin opción | Formulario | Faltaba la alternativa «total» | Botones «Por L/kg» y «Total de la línea». El total se reparte entre la cantidad solo si salen centavos exactos; si no, el precio queda no válido con el motivo, sin redondear. Un total dicho no se muestra como precio por unidad. Nunca se supone por unidad por la unidad del producto | `compra_lineas_y_precio_test`, `integracion_pantallas_poco_test` (unidad del precio) |
| 4 | Decimales con palabras («setenta y cinco coma cincuenta») | Interpretación | `readNumberAt` solo leía una cifra tras «coma» | Dos cifras como centavos («coma veinticinco», «coma cero cinco»). Más de dos cifras no se leen | `compra_lineas_y_precio_test` (decimales) |
| 5 | Cada repetición de una cantidad sin producto añadía una línea vacía (POCO, líneas 4 y 5) | Interpretación | Toda línea sin producto resuelto era nueva | Va a la única línea que espera producto. Si no hay, completa la única línea con producto y sin cantidad. Si hay varias, avisa sin cambiar nada. «tres litros de» sigue esperando un producto nuevo | `compra_lineas_y_precio_test`, `integracion_pantallas_poco_test` |
| 6 | Repetir un producto fuera del catálogo lo duplicaba | Interpretación | Igual que #5 | Va a la única línea con lo mismo oído y sin resolver | ídem; `lineas_aplicacion_plan_test` |
| 7 | El mismo producto dos veces en una frase se fundía en silencio (la segunda sobrescribía la primera) | Interpretación | Se buscaba la línea del producto también entre las creadas por la misma frase | Dos líneas, bloqueadas como «producto repetido» (regla del formulario) | `compra_lineas_y_precio_test`, `lineas_aplicacion_plan_test` |
| 8 | «y otros dos litros de …» sobrescribía la cantidad de la línea existente | Interpretación | No se distinguía añadir de corregir | «otro/otra/otros/otras» pide una línea nueva. Nombrar el producto sin eso corrige su línea (regla existente). Con varias líneas del producto, se avisa | `compra_lineas_y_precio_test` |
| 9 | «compré herbicida demo», sin cantidad, se perdía | Interpretación | Las líneas solo nacían de una cantidad | Completa la línea que espera producto o abre una que espera la cantidad. Fuera del catálogo no abre nada y avisa | `compra_lineas_y_precio_test` |
| 10 | Un precio confirmado con un botón no se reflejaba en el campo de texto | Formulario | `_sync` no reescribía campos «Confirmado» | Solo lo tecleado a mano no se reescribe | `integracion_pantallas_poco_test` |
| 11 | El sistema no avisaba de una cantidad o un producto que no se aplicaron a ninguna línea | Formulario | No había canal de aviso | `lineNotice`, que se muestra en `voz-linea-sin-aplicar` | `compra_lineas_y_precio_test` |

**Comprobados sin cambios:** ya estaban corregidos y verificados en HOST.

- Moneda BOB por revisar: se ve marcada y se puede confirmar (`2684947`).
- «Faltan X L».
- «Confirmado» frente a «Corregido a mano», y elegir otra vez la misma opción no cuenta como cambio.
- Dosis normalizada, y dosis × área.
- Desacuerdo numérico marcado solo en los campos que cambia el dictado.
- Un mismo texto cerrado no se aplica dos veces (`VoiceSegmentFeed`; el adaptador no reentrega una frase).
- Los resultados de un turno cancelado o anterior se ignoran (`local_speech_transcription_adapter_test`).
- Cero escrituras antes de confirmar, y confirmación única con doble toque.

**Sin cambios y declarados:** no hay un sistema general de órdenes de voz («selecciona», «elimina»). Tampoco hay alias de nombres: «publicidad» no se convierte en ningún producto.

## 4. Resultados en HOST (2026-11-09, sobre los cambios de esta etapa)

| Comprobación | Resultado |
|---|---|
| `dart format --set-exit-if-changed` (lib, pruebas de voz) | Sin cambios |
| `flutter analyze` | Sin problemas |
| Suites de voz (`test/voice_draft`, `test/voice` y pruebas de borradores de voz) | +672, sin fallos |
| Pruebas nuevas | `compra_lineas_y_precio_test` +18, `lineas_aplicacion_plan_test` +5, `integracion_pantallas_poco_test` +10 (4 nuevas) |
| Suite completa (`flutter test`) | +2656 ~3 −1. El fallo es `f08_prev_01_previo_ui_test` («Mis datos están bien» exige confirmarlo…), de respaldo y no tocado aquí. Aislado pasa dos veces (+8): **intermitente bajo carga**, declarado y no resuelto |

Todo es texto inyectado: el reconocimiento real se prueba en el POCO con Roderich.
