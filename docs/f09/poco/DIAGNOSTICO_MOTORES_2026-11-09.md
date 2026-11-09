# F09: diagnóstico de la selección entre Vosk y Whisper base (2026-11-09)

Rama `feat/f09-diagnostico-motores`, que parte de `d5808d0`. Configuración: Vosk small-es-0.42 + Whisper base q5_1 (ADR-005, provisional). No se cambia a small, no hay servicios remotos, #17 sigue Pending y #12 no se ejecuta.

## Índice de resultados por versión

| Resultado | Tipo | APK (commit) |
|---|---|---|
| Causas C1 (vocabulario) y C2 (dato ausente = desacuerdo), instrumentación | HOST | `6adbb77` |
| D1 | DEVICE | `6adbb77` |
| Métricas por habla y silencio, pistas, «¿120 por L?» | HOST | `1b95452` |
| CAP-A, CAP-B, CTX-1 | DEVICE | `1b95452` |
| Precio sin «a» con moneda, producto sin cantidad | HOST | `02e1f8c` |
| Cifras con «millones» | HOST | `a77d03e` |
| REP-1 | DEVICE | `a77d03e` |
| Política B, comparador por campo, «de/del litro» | HOST | `ba3feb6` |
| B-1, B-2 | DEVICE | `ba3feb6` |
| «Usar la otra propuesta», coma entre importe y moneda | HOST | `932e368` |
| OP-1, CTX-2, CTX-3 / OP-2 | DEVICE | `932e368` |
| Aviso de posible repetición, emparejamiento seguro, espera de la prueba de salida | HOST | ver sección 25 |
| Compra completa: acierto inicial, correcciones, efectos y persistencia (sección 26) | DEVICE | `71e55fc` |
| Aplicación de prueba: preparación y valores iniciales (sección 27) | DEVICE | `71e55fc` |

Ningún resultado declara ganadoras a A, a B ni a la pista de dominio. Las comparaciones son diagnóstico.

## 1. Punto de partida (DEVICE, POCO X5 Pro, 2026-11-09)

En los intentos del caso 1 («Compré cinco litros de Herbicida DEMO a ciento veinte bolivianos el litro»):

- el formulario recibió el texto de Vosk;
- «Herbicida DEMO» llegó con otros nombres, fuera del catálogo;
- «bolivianos el litro» llegó incompleto o deformado;
- todas las frases salieron con veredicto `quantities` (desacuerdo numérico);
- la revisión tardó entre 2,4 y 2,9 s, sin agotar el límite.

Lo que propuso Whisper **no se conoce**: no se registra. Estos datos no demuestran que Whisper acertara, ni que no pudiera hacerlo.

## 2. Recorrido auditado (fase 1)

| Etapa | Dónde | Qué hace |
|---|---|---|
| Captura | `LocalVoiceEngine.kt`, `MicrophoneSource` | `AudioRecord` `VOICE_RECOGNITION`, 16 kHz, mono, PCM 16 bits, bloques de 100 ms; cola de hasta 3 s (si Vosk se atrasa, se descarta lo más viejo y se cuenta) |
| Segmentación | `Turn.decode` | Cada bloque se añade al búfer de la frase **antes** de pasarlo a Vosk. La frase se cierra por pausa (`acceptWaveForm` = fin de enunciado de Vosk: 0,5 s de silencio tras la voz, `model.conf` regla 2) o al detener (`finalResult`). Además, 30 s sin voz detienen el turno |
| Audio de cada motor | `Turn.close` | Whisper recibe **el mismo intervalo** que cerró Vosk: el búfer de esa frase, convertido a float con /32768 y con un máximo de 30 s. No hay remuestreo en la app |
| Whisper | `whisper_jni.c` | español, sin traducir, `no_context`, un segmento, voraz con temperatura 0, `initial_prompt` = nombres del catálogo (productos, personas, proveedores, chacos y campaña; máximo 600 caracteres) |
| Comparación | `review_selection.dart` `_compareFacts` | Lista ordenada de hechos de cada texto (`voiceQuantityFacts`: `n<milésimas>`, `u<unidad>`, `c<moneda>`). Deben tener **la misma longitud** y coincidir uno a uno |
| Selección | `chooseReviewedText` | Si todo coincide, se usa Whisper (`accepted`). Si solo cambia el formato, se usa Vosk (`format`). Con cualquier otra diferencia se usa Vosk y la frase sale marcada (`quantities`). Nunca se mezclan los dos textos |
| Interpretación | `purchase_interpreter.dart` | Interpreta solo el texto elegido |
| Borrador | `numeric_review.dart` | Con la marca, la cantidad, el precio y la moneda que cambió ese dictado (y el tipo de cambio) quedan «Revisar». El producto no se marca: sale de Vosk |

**¿La ausencia de un dato cuenta como contradicción? Sí.** Si Vosk no oye «bolivianos» o «el litro» y Whisper sí, las listas tienen distinta longitud y la frase cuenta como `quantities`. Entonces se pierde todo el texto de Whisper, incluido el nombre del producto. También cuentan como distintos la moneda delante de la cifra («Bs 120») y una cifra que el lector no entiende («$120»). Lo reproducen las pruebas `test/voice/review_discrepancy_test.dart` con pares sintéticos.

## 3. Causas demostradas e hipótesis

| # | Tipo | Hallazgo | Prueba |
|---|---|---|---|
| C1 | **Demostrada** (modelo) | «herbicida» en singular **no está en el vocabulario** de vosk-model-small-es-0.42; solo «herbicidas». Tampoco están «agroinsumos», «mancozeb», «atrazina», «paraquat», «bellator» ni «provedor». Vosk no puede escribir esas palabras y entrega las palabras más parecidas que conoce | Entradas exactas, con su longitud, de la tabla de símbolos de `graph/Gr.fst`. Sí están «fungicida», «insecticida», «glifosato», «demo», «litro», «bolivianos», «proveedor» |
| C2 | **Demostrada** (política) | La regla actual trata un dato ausente en un motor como contradicción y desecha la frase entera de Whisper | `review_discrepancy_test.dart` (veredicto actual con pares sintéticos) |
| H1 | Hipótesis | Whisper base oyó bien el producto y «bolivianos el litro» | Se verá en la vista de diagnóstico del primer caso |
| H2 | Hipótesis | Al tocar «Detener» se pierde el final de la frase: `close()` detiene y libera el `AudioRecord` sin leer lo que queda en su búfer (hasta unos 100 ms) | Métricas `cierre` y `silencioFinal` por frase |
| H3 | Hipótesis | La deformación de «bolivianos el litro» en Vosk es una confusión acústica o del modelo de lenguaje de Vosk. Las palabras correctas sí están en su vocabulario | Comparar con Whisper en la vista |

## 4. Instrumentación añadida (sin cambiar la política)

**Línea `voz diag:` por frase**, solo con códigos y números:

- turno (número efímero del proceso) y frase;
- audio: duración, nivel RMS, pico, suelo de ruido y máximo por ventana (dBFS), saturación (‰), voz detectada, silencio inicial y final (ms), audio descartado por retraso;
- cierre: `pausa`, `stoppedByUser` o `timeout`;
- Whisper: resultado (`ok`, `aborted`, `budget-exhausted`, `queue-full`, `off`, `unavailable`, `cancelled`, `error`), carga, cola e inferencia (ms);
- selección: motor elegido, regla y diferencias, con el código `campo:tipo[@lado]`.

Al cancelar se añade una línea `cancelado`. En la captura se registra la configuración real del `AudioRecord`.

**Tipos de diferencia** (`review_discrepancy.dart`): los hechos se agrupan en datos con su papel (cantidad, precio con su unidad, área, cifra, unidad, moneda) y se alinean por valor. Los tipos son:

- valor distinto;
- dato ausente en uno, indicando cuál lo trae;
- unidad distinta;
- moneda distinta;
- formato equivalente;
- extracción fallida (cifra ilegible);
- correspondencia ambigua.

Una cifra ilegible no se convierte en contradicción, y lo que no se puede alinear queda como ambiguo.

**Vista de diagnóstico** (solo con `--dart-define=AGRO_VOICE_DIAG=true`, en «Compra por voz»):

- se abre con el botón «Diagnóstico: ver lo que propuso cada motor»;
- muestra, por frase:
  - el texto de Vosk y el de Whisper, o por qué no hubo texto de Whisper;
  - el texto que se usó y la regla que lo eligió;
  - las diferencias;
  - la interpretación de cada propuesta por separado, sobre un borrador vacío;
- el contenido vive solo en memoria y se borra al cerrar la vista, al descartar o registrar el borrador y al salir de la pantalla;
- no escribe registros, archivos ni evidencia, no cambia el consentimiento y no hace escrituras de negocio.

Aplicación y planificación todavía no tienen la vista; el registro de códigos sí cubre las tres pantallas.

## 5. Captura y audio (fase 2)

| Comprobación | Resultado |
|---|---|
| Frecuencia que espera Vosk | 16 kHz (`conf/mfcc.conf`); la captura pide 16 kHz. La frecuencia real se registra desde esta versión |
| Frecuencia que espera Whisper | 16 kHz float. La conversión /32768 es correcta y no hay remuestreo |
| Canales y formato | Mono, PCM 16 bits |
| Mismo intervalo para los dos motores | Sí: el mismo búfer de la frase (código) |
| Aislamiento entre turnos y resultados tardíos | Por número de turno; ya cubierto por las pruebas del adaptador |
| Audio descartado por retraso | El aviso no aparece en el logcat disponible del POCO (2026-11-09, de 08:17 en adelante). Desde esta versión se mide por frase |
| Final de frase al detener | Hipótesis H2; se mide con `silencioFinal` |
| Audio sintético en el emulador | **No ejecutado.** El banco existente (`run_reference_check.sh`) instala en `.voz`, que no se puede tocar. Pendiente con otro paquete aislado |

No se corrigió nada de la captura, porque todavía no hay ningún defecto demostrado.

## 6. Vocabulario y contexto (fase 5, solo comprobaciones)

- **Vosk:** el grafo es de tipo *lookahead* (`HCLr.fst` + `Gr.fst`), así que admite gramática en tiempo de ejecución, pero **solo con palabras de su vocabulario**. No puede aprender «herbicida». Una gramática no resolvería C1 y además forzaría el audio hacia frases conocidas. No se añaden equivalencias como «vicia = Herbicida».
- **Whisper:** ya recibe los nombres del catálogo como contexto inicial, y «Herbicida DEMO» va en esa pista. Probar un contexto con unidades y monedas es un experimento posterior, aparte.

## 7. Resultados HOST

| Comprobación | Resultado |
|---|---|
| `dart format` | Sin cambios pendientes |
| `flutter analyze lib test/voice` | Sin problemas |
| Pruebas nuevas | `review_discrepancy_test` +19, `diagnostico_motores_test` +6 |
| Suites de voz (`test/voice`, `test/voice_draft`, `test/*voice*`) | +703, sin fallos |

Todas usan transcripciones sintéticas escritas a mano, ninguna del holdout de #12. No prueban el reconocimiento.

## 8. APK de diagnóstico

| Dato | Valor |
|---|---|
| Archivo | `agrocuentas-f09diag-6adbb77-arm64-v8a-profile.apk` (profile, ARM64) |
| Commit | `6adbb77b555fba30507cc54caa8e4f638d26e8ee` |
| SHA-256 | `ebd938a24f41ae4e6ae88923c0663698acacb89e40c0bd8c28448d14df764839` (162 353 304 B) |
| Paquete y etiqueta | `com.comunidad.agro.agroquimicos.f09`, «AC F09», versionCode 2001 |
| Definiciones | `AGRO_VOICE_EVIDENCE=true`, `AGRO_VOICE_DIAG=true`, `AGRO_APP_COMMIT`, origen HTTPS del túnel (no se publica) |
| Modelos | Vosk small-es-0.42 + `ggml-base-q5_1.bin` (sin small) |
| Comprobado | Los textos nuevos están en `libapp.so` y en el código Kotlin. Las entradas comprimidas suman lo mismo que en `d5808d0`; el archivo pesa unos 14 MB más por bytes del zip que ninguna entrada usa (empaquetado incremental de Gradle) |
| Límites | Sin cambios: revisión 5 000 ms, guarda de capacidad 1 700 MiB para base |

## 9. Orden de los experimentos (actualizado tras D1)

Se cambia una variable a la vez, y la referencia es Vosk + Whisper base con la regla actual (A) y la pista del catálogo:

1. **Captura:** distancia habitual frente a unos 15 cm, con las métricas de habla y silencio separadas. No se convierte la distancia en un requisito de uso.
2. **Pista de Whisper:** sin pista, catálogo y dominio + catálogo, sobre el mismo audio en memoria (precisión). El rendimiento se mide aparte, con la comparación apagada.
3. **Política B frente a A:** primero calculada en la vista; aplicada al formulario solo en una variante experimental separada.
4. **Whisper solo (C):** requiere una segmentación propia (sección 11).
5. **Dictado dirigido a un campo** y **audio sintético en el emulador** (en un paquete aislado nuevo).

## 10. DEVICE: caso D1 (POCO, 2026-11-09 10:17, APK `6adbb77`)

Roderich dictó la frase del caso 1 una vez, con un segundo de silencio antes de detener, y revisó la vista en pantalla. Su contenido no se conserva. Aquí solo van el registro de códigos, el texto que llegó al formulario (visible en «Lo último que se oyó») y el formulario.

| Etapa | Resultado |
|---|---|
| Texto de Whisper (el que llegó al formulario) | Producto y cantidad correctos; donde se dijo «bolivianos» escribió otra palabra que no es moneda (Roderich lo cita en sus instrucciones; no se copia aquí) |
| Texto de Vosk | No se registra. Roderich lo vio en la vista |
| Datos extraídos | Los dos textos dieron la **misma lista** de cifras, unidades y monedas, **sin ninguna moneda** |
| Comparador | Sin diferencias, veredicto `accepted` |
| Propuesta seleccionada | Whisper |
| Captura | 16 000 Hz reales, mono, PCM 16 bits; sin audio descartado. La frase se cerró por pausa |
| Whisper | Terminó en 2 707 ms (carga 209 ms al entrar en la pantalla) |
| Formulario | Herbicida DEMO resuelto; 5 L resuelto; precio 120 «Ambiguo: elija»; moneda «Falta». **No se aceptó ningún valor incorrecto sin aviso** |

**Corrección (2026-11-09):** la primera lectura de este caso decía que «ninguno de los dos motores tiene una palabra de moneda». Es una conclusión que no se sostiene. Que el lector no extrajera una moneda del texto de Vosk **no demuestra** que Vosk no transcribiera una palabra de moneda: pudo escribir una variante que el lector no admite como moneda. Eso solo se puede verificar en la vista. El fallo demostrado de este intento es de **Whisper**: escribió otra palabra en lugar de «bolivianos», y su texto fue el seleccionado. No se atribuye a Vosk.

**Nivel de la señal:** el RMS de −39 dBFS se calculó sobre las 8,8 s del intervalo. De ellas, 1,45 s eran de silencio inicial y 5,1 s de silencio final, así que la media está dominada por el silencio y **no mide el nivel del habla**. El pico (−20 dBFS) y la ventana más alta (−25 dBFS) tampoco bastan para atribuir el error al nivel. H4 queda abierta, sin evidencia a favor ni en contra.

**Los 5,1 s de silencio final pertenecen al intervalo enviado a Whisper.** Las métricas se calculan sobre el mismo búfer que recibe Whisper (`Turn.close`): desde el cierre de la frase anterior hasta que Vosk detecta el final del enunciado. Lo que se capturó después, hasta tocar «Detener», no se envió a Whisper.

## 11. Etapa `1b95452`: medir la captura y preparar experimentos

### Cambios

| Área | Cambio |
|---|---|
| Captura (código) | Nivel **durante el habla** y **durante el silencio**, por separado. El método (`v50ms-p10-12dB`): ventanas de 50 ms, suelo de ruido = percentil 10 de las ventanas, y es habla toda ventana que supera el suelo en 12 dB. También: duración con voz, audio capturado en el turno (todo va a Vosk), audio enviado a Whisper y tiempo desde el cierre de la frase hasta su entrega. Siguen pico, saturación, audio descartado, cierre, carga e inferencia. **No se añadió ganancia, normalización ni recorte** |
| Whisper (verificado) | El modelo `ggml-base-q5_1` es multilingüe (vocabulario de 51 865). Idioma `es` explícito y `translate=false`. `initial_prompt` sí se usa en whisper.cpp `52a939a`: se tokeniza y se conservan como mucho los últimos 224 tokens (`n_text_ctx/2`). `no_context=true` vacía el contexto en cada llamada, así que no queda nada de capturas anteriores |
| Experimento de pistas (solo diagnóstico) | Interruptor «Diagnóstico: comparar pistas de Whisper», apagado por defecto. Encendido, cada frase se vuelve a transcribir sobre el **mismo audio en memoria**, sin pista y con la pista de dominio y catálogo, **después** de entregarla. Los textos solo van a la vista. La pista principal (catálogo) y el resto de parámetros no cambian |
| Pista de dominio | Términos fijos sin cifras ni frases (bolivianos, dólares, litro, litros, kilo, kilos, hectárea, hectáreas, herbicida, fungicida, insecticida, proveedor), seguidos de los nombres del catálogo de la cuenta actual, sin repetir. Máximo 600 caracteres. No lleva instrucciones |
| Vista | Separa el texto de cada motor, los datos extraídos de cada uno, las diferencias del comparador, la regla actual (A), qué llegó al formulario, lo que haría la política B (calculada, **sin aplicar**) y las transcripciones alternativas con su interpretación |
| Política B | `review_policy_b.dart`, solo cálculo. Si la salida de Whisper es válida, usa su texto entero y deja «Revisar» cada campo con una diferencia relevante. Si no es válida o llegó tarde, usa Vosk y da el motivo |
| Intérprete (fase 5) | Con una sola palabra desconocida entre el importe y «el/por/cada» + unidad, sin moneda («a 120 volviendo el litro»), el precio queda «Ambiguo» con «¿120 por L?» y la moneda pendiente. La palabra no se sustituye. «a ciento veinte el litro» ya daba 120 por L con la moneda pendiente, y «a ciento veinte» sigue ambiguo (sin cambios). No hay moneda por defecto |

### Dependencia de Vosk para un «Whisper solo» (C)

Hoy **Vosk segmenta**:

- la frase se cierra cuando Vosk detecta el final del enunciado (`acceptWaveForm`);
- si Vosk no reconoce ninguna palabra, la frase **no existe** y Whisper no la ve (`close` sale con texto vacío);
- los parciales en pantalla también son de Vosk.

Una prueba «Whisper solo» necesita otra segmentación (por energía, o un único tramo hasta «Detener»). Además hay que comprobar que Vosk no se carga. **Todavía no está implementada.**

### Resultados HOST (`1b95452`)

| Comprobación | Resultado |
|---|---|
| `flutter analyze lib test/voice test/voice_draft` | Sin problemas |
| Pruebas nuevas | `precio_moneda_unidad_test` +10, `experimentos_motores_test` +10 |
| Suites de voz con `-j 4` | +723, sin fallos |
| Suites de voz con la concurrencia por defecto (24) | En 2 de 3 ejecuciones falló **una** prueba de salida de compra de `voice_draft_exit_test` (en cada ejecución, una distinta). La escritura fue única, pero la pantalla aún no había salido al comprobarlo. Aislada pasa 3 de 3, y con `-j 4` pasa. **Intermitente bajo carga**, declarado y no resuelto |

## 12. DEVICE: CAP-A, distancia habitual (POCO, 2026-11-09 12:00–12:04, APK `1b95452`)

Comparación de pistas apagada. **Modo avión desactivado** durante estos dictados: lo cambió Roderich, no esta sesión. El procesamiento es local igualmente. Hubo 3 turnos y 5 frases: el turno 1 es el caso CAP-A; el resto son dictados adicionales de Roderich.

| Turno.frase | Audio a Whisper | Voz | Nivel habla / silencio | Pico | Silencio inicial / final | Cierre | Inferencia / entrega | Selección | Diferencias |
|---|---|---|---|---|---|---|---|---|---|
| 1.0 (CAP-A) | 6 900 ms | 4 750 ms | −36 / −54 dBFS | −16 dBFS | 150 / 600 ms | pausa | 2 767 / 2 812 ms | Vosk (`quantities`) | `price:extractionFailed` |
| 2.0 | 4 300 ms | 2 450 ms | −32 / −53 dBFS | −16 dBFS | 150 / 1 250 ms | pausa | 2 746 / 2 747 ms | Whisper | ninguna |
| 3.0 | 7 400 ms | 5 450 ms | −36 / −56 dBFS | −18 dBFS | 150 / 1 300 ms | pausa | 2 710 / 2 712 ms | Whisper | ninguna |
| 3.1 | 4 500 ms | 2 150 ms | −35 / −58 dBFS | −16 dBFS | 1 000 / **0** ms | pausa | 2 498 / 2 499 ms | Whisper | ninguna |
| 3.2 | 5 100 ms | 2 850 ms | −36 / −56 dBFS | −19 dBFS | **0** / 1 500 ms | pausa | 2 920 / 2 922 ms | Whisper | ninguna |

En todas: 16 kHz reales, sin saturación, sin audio descartado, carga de Whisper 201 ms. Límite de 5 s no agotado.

**Lectura de CAP-A (turno 1):**

- Llegó al formulario el texto de Vosk.
- **Vosk sí transcribió una palabra de moneda** que el lector extrae como BOB. El producto llegó con un nombre fuera del catálogo (C1).
- La diferencia fue una **cifra de precio que el lector no pudo leer en el texto de Whisper** (`price:extractionFailed`). Qué escribió Whisper lo vio Roderich en la vista; no se conserva.
- En el formulario, la cantidad 5 L y la moneda BOB quedaron «Revisar»; el precio 120, «Ambiguo» (faltaba «el» delante de la unidad); y el producto, «Falta».

**Nivel de captura:** a la distancia habitual, el habla llega a entre −32 y −36 dBFS RMS y el silencio a entre −53 y −58 dBFS, unos 20 dB por encima del silencio, sin saturación. **No hay evidencia de que el nivel cause los fallos.** Falta CAP-B para comparar, y un solo intento no basta.

**Observación (H6, hipótesis):** entre las frases 3.1 y 3.2 no hay silencio medido en el límite (0 ms al final de una y 0 ms al principio de la otra). La 3.1 terminó con un fragmento de nombre de producto, y la 3.2 empezó con el nombre completo. Puede que el corte entre frases cayera dentro del habla. Pero el umbral de voz (suelo + 12 dB, unos −49 dBFS) también lo supera un ruido leve, así que **no está demostrado**.

**Defecto de interpretación (demostrado con texto inyectado):** una frase con un producto del catálogo, sin «compré» y sin cantidad, seguida de un precio, no cambió el borrador y no explicó por qué. Si la única línea tiene otro producto oído sin resolver, el sistema no puede saber si es la misma línea, y debe **preguntar**, no ignorarlo en silencio. Sin corregir todavía.

## 13. DEVICE: CAP-B, unos 15 cm (POCO, 2026-11-09 12:42–12:44, APK `1b95452`)

Dos turnos de una frase cada uno. La vista mostraba solo la última frase, y Roderich la dejó abierta para analizarla. Su contenido no se conserva aquí.

| Turno | Audio a Whisper | Voz | Nivel habla / silencio | Pico | Silencio inicial / final | Cierre | Inferencia / entrega | Selección | Diferencias |
|---|---|---|---|---|---|---|---|---|---|
| 4 | 7 600 ms | 5 550 ms | −35 / −52 dBFS | −19 dBFS | 150 / 1 450 ms | pausa | 2 585 / 2 587 ms | Whisper | ninguna |
| 5 | 7 200 ms | 3 350 ms | −34 / −48 dBFS | −15 dBFS | 200 / 1 600 ms | pausa | 3 100 / 3 102 ms | Whisper | ninguna |

**Captura, CAP-A frente a CAP-B:**

- el nivel del habla casi no cambia: −36 dBFS a la distancia habitual, −34/−35 dBFS a unos 15 cm;
- el silencio sube un poco en el turno 5 (−48 dBFS);
- no hay saturación ni pérdidas en ninguno.

**Conclusión:** no hay evidencia de que la captura (nivel, recorte o pérdida de audio) cause los fallos observados. Se da por suficiente para pasar al experimento siguiente. Son pocos intentos y la distancia no se convierte en requisito.

**Etapas de la frase visible (turno 5, por el orden de la vista):**

| Etapa | Resultado |
|---|---|
| Vosk | Producto con otro nombre (C1); precio y moneda presentes, sin «el» antes de la unidad |
| Whisper | Producto **correcto**, cantidad, cifra, moneda y unidad correctas. Faltaba la «a» delante del precio (en su lugar, una coma) y había una palabra de más antes de «el litro» |
| Datos extraídos | Iguales en los dos: 5, litro, 120, BOB, litro |
| Comparador | Sin diferencias, `accepted`. La política B haría lo mismo |
| Formulario | Producto y cantidad resueltos. **Precio «No válido» y moneda «Falta»**, aunque la moneda estaba en el texto |

**Causa demostrada (interpretación):** sin conector («a», «al», «por») delante de la cifra, el intérprete solo da el precio por revisable si la cláusula está completa y limpia («120 bolivianos el litro»). Si no, lo deja no válido y no toma la moneda. Esa regla existe porque una «a» perdida puede comerse parte de un número dicho con palabras («a ciento» → otra palabra). Aquí la cifra venía en dígitos, pero la palabra de más antes de «el litro» invalidó la cláusula. Sin corregir: es una decisión de regla (ver la entrega).

## 14. Etapa `02e1f8c`: correcciones del intérprete aprobadas (HOST)

### Por qué el comparador y el formulario no coincidían

| Pieza | Regla | Qué hace con «, 120 Bolivianos en el litro» |
|---|---|---|
| Comparador (`voiceQuantityFacts`) | **Extracción por tokens**, sin estructura: cifra, unidad, moneda, en orden | 120 · BOB · litro |
| Intérprete, extracción (`_readClause`) | Estructura: conector, cifra, moneda, forma de la unidad, palabra extraña | Cifra 120 y moneda BOB; «en el litro» no tenía forma reconocida y no hay conector |
| Intérprete, validación (`_priceFields`), antes | Sin conector y sin forma limpia → no válido **y moneda descartada** | Precio no válido, moneda «Falta» |

Las dos piezas usan los mismos lectores (`readNumberAt`, `currencyWord`, `unitWord`). La incompatibilidad estaba en la **validación, que descartaba lo extraído**.

### Corrección

Extracción y validación siguen separadas. La validación ya no descarta nada:

- **Moneda.** Si se dijo, se conserva siempre: queda dicha con conector y «Revisar» sin él. Una duda sobre el tipo de precio no la quita.
- **Palabra de más antes de «el/por/cada» + unidad** («en el litro» o una palabra desconocida), con o sin «a» y con o sin moneda. Importe y moneda quedan a la vista y el precio pasa a «Ambiguo» con «¿120 Bs por L?». Nada se confirma solo.
- **Sin «a»:**
  - con una palabra extraña pegada delante («haciendo veinte») o la moneda deformada, **no válido y sin valor** (no se reconstruye nada);
  - con estructura completa («ciento veinte bolivianos por litro»), «Revisar» con el valor;
  - en los demás casos, «Ambiguo» con la cifra a la vista.
  - Nunca queda resuelto ni aceptado solo.
- **Producto dicho sin cantidad**, con o sin «compré» y con o sin precio:
  - va a la única línea que espera producto, o a la única línea de ese producto (lo puesto a mano no cambia);
  - con varias líneas del producto, o con líneas de producto oído sin resolver, no aplica nada y **pide elegir la línea**, nombrando lo oído en ella;
  - si no, abre una línea que espera la cantidad;
  - un nombre suelto sin «compré» ni precio **avisa sin crear**;
  - un nombre fuera del catálogo sin «compré» sigue la vía del precio suelto, que lo marca como mal oído;
  - la unidad del precio distinta de la del producto no se pone y se informa.

### Vocabulario de Vosk: verificación documental

`tool/voice_local/vosk_vocab_check.py` busca la entrada exacta (longitud + texto) en la tabla de símbolos de `graph/Gr.fst`. El `Gr.fst` es el mismo en el manifiesto, en el APK y **en el POCO** (`no_backup/voice/…`, leído con `run-as … sha256sum`): SHA-256 `0ddc8aacbc80b2e8d470060a429eb26706b2ae1d32615a499befd60cc86a0304`.

| Estado | Palabras |
|---|---|
| **Ausentes** (Vosk no las puede escribir nunca) | herbicida, agroinsumos, mancozeb, atrazina, paraquat, bellator |
| **Presentes** (si salen mal, es un error de reconocimiento) | herbicidas, fungicida, insecticida, glifosato, demo, litro, litros, kilo, kilos, hectárea, hectáreas, bolivianos, boliviano, dólares, el, por, compré, compre, proveedor |

### Resultados HOST (`02e1f8c`)

| Comprobación | Resultado |
|---|---|
| `dart format --set-exit-if-changed` (voz) | Sin cambios |
| `flutter analyze lib test/voice test/voice_draft` | Sin problemas |
| Pruebas nuevas | `precio_y_producto_sin_cantidad_test` +23, que incluye la coherencia entre comparador y formulario en 5 frases |
| Prueba actualizada | `compra_interpretacion_test` («variantes sin "a"»): con palabra extraña o moneda deformada sigue no válido; con estructura incompleta, ambiguo con la cifra a la vista, nunca aceptado. Es el cambio aprobado |
| Suites de voz | +746, sin fallos, con `-j 4` y con la concurrencia por defecto (una ejecución de cada) |

### APK

| Dato | Valor |
|---|---|
| Archivo | `agrocuentas-f09diag-02e1f8c-arm64-v8a-profile.apk` (`.f09`, «AC F09», AGRO_VOICE_DIAG) |
| Commit | `02e1f8c1588b0f25b65f99e75857da659dc3285f` |
| SHA-256 | `9bb25ebb5dfa79cca8fe41a38c28b0846a30203c6c154da791013a840940f116` (162 418 840 B) |
| Modelos | Vosk small-es-0.42 + `ggml-base-q5_1.bin`; mismos límites |
| Estado | **Sin instalar**: CTX-1 se hace con `1b95452` para no mezclar las mejoras del intérprete con las del contexto |

## 15. DEVICE: CTX-1, pistas de Whisper sobre el mismo audio (POCO, 2026-11-09 14:19, APK `1b95452`)

Comparación encendida, distancia habitual, una frase. Roderich dejó la vista abierta para analizarla; su contenido no se conserva aquí.

**Orden de ejecución** (hilo único de revisión):

1. Vosk en vivo.
2. Whisper con la pista del catálogo, que es lo que llega al formulario: 2 680 ms, entregado a los 2 683 ms del cierre.
3. Whisper sin pista: 2 404 ms.
4. Whisper con la pista de dominio y catálogo: 2 913 ms.

Las transcripciones 3 y 4 empiezan **después** de entregar la frase, así que sus tiempos **no** representan la espera normal.

**Captura:** audio de 9 200 ms con 4 000 ms de voz; habla −41 dBFS y silencio −57 dBFS; pico −26 dBFS; 3 350 ms de silencio inicial; cierre por pausa. Es la señal más baja de la sesión y no tuvo saturación.

| Propuesta (mismo audio) | Producto | Precio y unidad | Moneda | Datos extraídos |
|---|---|---|---|---|
| Vosk | Otro nombre (C1) | Una cifra en millones donde se dijo el importe | Ninguna palabra de moneda | 5 · litro · 120 · litro (**mal leída**, ver abajo) |
| Whisper, pista del catálogo | **Correcto** | 120, con «de litro» en lugar de «el litro» | Palabra deformada (no es moneda) | 5 · litro · 120 · litro |
| Whisper, sin pista | **Incompleto**: el nombre perdió «DEMO» y se mezcló con el precio | Sin precio (sin «a») | Igual de deformada | 5 · litro · 120 · litro |
| Whisper, dominio + catálogo | **Correcto** | Igual que con la pista del catálogo | **Igual de deformada**, aunque la pista llevaba «bolivianos» | 5 · litro · 120 · litro |

Selección: Whisper (`accepted`, sin diferencias). Formulario: Herbicida DEMO, 5 L, precio 120 «Ambiguo» y moneda «Falta». No se aceptó ningún valor incorrecto sin aviso.

**Lectura exploratoria (un solo intento):**

- la pista del catálogo ayudó al nombre del producto, porque sin pista se perdió;
- la pista de dominio **no cambió** la palabra de moneda ni «de litro»;
- no se atribuye ninguna mejora al contexto.

**Defecto demostrado (lector numérico):** «… millones» no se leía. El lector se paraba delante y la cifra valía 120, así que el comparador dio por iguales una cifra en millones y «120». Corregido en `a77d03e`: una cifra seguida de «millón/millones» queda no válida, con lo oído a la vista. `numeros_millones_test` +3.

**Sin corregir (decisión pendiente):** «120 <palabra> de litro» no ofrece «¿120 por L?», porque «de litro» no se acepta como forma de la unidad del precio (regla de 2026-11-08).

## 16. APK corregida `a77d03e` (HOST)

| Dato | Valor |
|---|---|
| Contenido | `02e1f8c` (precio sin «a» con importe y moneda conservados; producto sin cantidad) + `a77d03e` (millones) |
| Archivo | `agrocuentas-f09diag-a77d03e-arm64-v8a-profile.apk` (`.f09`, «AC F09», AGRO_VOICE_DIAG) |
| Commit | `a77d03e1d7137179399ba80e7881cbdce794eb81` |
| SHA-256 | `91fbed9d233f3932dddaff2d86935f00a0787072eeee94dedd4356c7efe7a561` (162 418 840 B) |
| Modelos y límites | Vosk small-es-0.42 + Whisper base q5_1; revisión 5 000 ms; sin cambios |
| HOST | analyze limpio. Suites de voz +749 con `-j 4`. En una ejecución falló una vez `voice_draft_exit_test` («planificación confirmar sale…»); aislado pasa 3 de 3 y la repetición completa pasa (+749). **Intermitente**, declarado |

## 17. DEVICE: REP-1 con el intérprete corregido (POCO, 2026-11-09 14:37–14:40, APK `a77d03e`)

Comparación de pistas apagada. Cuatro turnos con descartes entre medias. La vista conservaba las frases de los turnos 3 y 4, y Roderich la dejó abierta para analizarla; su contenido no se conserva aquí.

| Turno.frase | Voz / audio | Habla / silencio | Inferencia | Selección (A) | Diferencias | Política B (calculada) |
|---|---|---|---|---|---|---|
| 1.0 | 4 950 / 7 600 ms | −34 / −51 dBFS | 3 104 ms | Vosk (`quantities`) | `unit:missing@revision` | — |
| 2.0 | 4 250 / 6 900 ms | −37 / −54 dBFS | 3 168 ms | Vosk (`quantities`) | `currency:missing@revision`, `unit:missing@revision`, `quantity:missing@vosk` | — |
| 2.1 | 1 350 / 5 500 ms | −39 / −57 dBFS | 2 969 ms | Whisper | ninguna | — |
| 2.2 | 1 100 / 5 100 ms | −43 / −58 dBFS | 4 635 ms | Vosk (`degenerate`) | — | — |
| 3.0 | 4 300 / 7 900 ms | −34 / −49 dBFS | 3 201 ms | Vosk (`quantities`) | `quantity:extractionFailed` | Whisper; revisaría cantidad |
| 4.0 | 4 050 / 7 600 ms | −34 / −47 dBFS | 3 488 ms | Vosk (`quantities`) | `currency:missing@revision`, `unit:missing@revision` | Whisper; revisaría moneda y unidad |

Sin saturación ni audio perdido en ninguna. Límite de 5 s no agotado; la frase 2.2 llegó a 4 635 ms.

### Turno 4 (la frase completa del caso)

| Etapa | Resultado |
|---|---|
| Vosk | Escribió la forma plural del nombre (palabra que sí está en el vocabulario, véase C1), que la app deja **ambiguo**. El importe sí llega; **no hay moneda** y la unidad llegó deformada (no es unidad) |
| Whisper | **Producto, cantidad, importe, moneda y unidad correctos**; solo «del litro» en lugar de «el litro» |
| Comparador | A Vosk le faltan la moneda y la unidad: `missing@revision`. **No es una contradicción de valores** |
| Regla A | Lo trata como desacuerdo y **entrega Vosk**: se pierde todo lo que Whisper trajo bien |
| Política B | Habría entregado Whisper, con moneda y unidad por revisar |
| Interpretación de Whisper (vista) | Herbicida DEMO, 5 L, 120 «Ambiguo» («del litro» no es forma clara de la unidad), **BOB conservada** |

**C2 queda demostrada en el teléfono, no solo con pares sintéticos.** En este turno, la regla actual desechó una propuesta de Whisper que tenía todos los datos, porque a Vosk le faltaban dos.

### Turno 3

Whisper escribió el importe pegado a una letra («120V»): el lector no lo entiende (`extractionFailed`) y se entregó Vosk.

Limitación del clasificador: una cifra seguida de unidad y sin moneda se toma por **cantidad**. Aquí era el precio, así que la etiqueta «cantidad» de esa diferencia es imprecisa.

### Lo que hizo el intérprete corregido

- Con el texto de Vosk que llegó al formulario: moneda pendiente e importe ambiguo. Correcto, no se supone nada.
- Con el de Whisper: la moneda dicha se conserva.
- Sigue sin resolver la forma «de/del litro», que está pendiente de decisión (sección 15).

## 18. Etapa `ba3feb6`: política B experimental, comparador por campo y «de/del litro» (aprobado por el autor)

### Política B (solo diagnóstico, interruptor «Diagnóstico: política B», apagado por defecto)

| Situación | Qué llega al borrador | Qué queda «Revisar» |
|---|---|---|
| Whisper válido, sin diferencias | Whisper | Nada (igual que A) |
| Whisper válido; un dato que solo trae Whisper | **Whisper entero** | Ese campo, con el mensaje «lo entregó un solo reconocedor» |
| Whisper válido; un dato que solo trae Vosk | Whisper entero (el dato no se inserta: queda pendiente) | Ese campo, si llega |
| Whisper válido; cifra ilegible en uno de los dos | Whisper entero | El campo de esa cifra, con el mensaje de un solo reconocedor |
| Valor, unidad o moneda distintos; correspondencia ambigua | Whisper entero | Ese campo, con el mensaje «oyeron cifras distintas» |
| Whisper vacío, no-habla, degenerado o sin comprobar | Vosk | Nada; el motivo va al registro (`voz diag politicaB`) |
| Whisper tarde | Vosk por tope; lo tardío se descarta (igual que A) | Nada |

- **Sin mezclas:** una sola transcripción por frase.
- **Lo editado a mano** nunca se marca ni se sobrescribe (`markForReview` y `mergeField`).
- **Cambiar entre A y B** vale solo para los dictados siguientes: lo ya aplicado no se reaplica.
- **Al salir de la pantalla** vuelve a A.
- **La vista** dice si el texto llegó al formulario con la política B activa.

### Comparador por campo

`voiceFieldFacts` marca como **precio** la cifra que va tras «a/al/precio», o que va seguida de una moneda o de «el/la/de/del/por/cada» + unidad, con una palabra de más como mucho.

- «120V de litro» es un **precio ilegible** (`price:extractionFailed`): la «V» no se toma por moneda ni se limpia.
- Si la moneda está en uno solo de los dos, cuenta como **ausente**, no como «moneda distinta».
- La regla A sigue con `voiceQuantityFacts`, sin cambios.

Campos de la compra según el papel:

| Papel | Campo |
|---|---|
| cantidad | cantidad |
| precio, unidad del precio | precio |
| moneda | moneda |
| cifra sin papel | cantidad y precio |

### «de/del litro» tras el importe

Solo dentro de un precio (con «a» o con moneda): importe y moneda se conservan y se pregunta «¿120 Bs por L?». Sin moneda, «¿120 por L?» y la moneda pendiente (no se supone BOB). Si la unidad oída no es la del producto, no se pregunta por ella. El «de» de una cantidad no cambia.

### A frente a B con las mismas propuestas sintéticas (HOST, `politica_b_test`)

Cinco pares Vosk/Whisper escritos a mano, cuatro campos por caso (producto, cantidad, precio, moneda):

| Caso | A: correctos / pendientes / incorrectos sin aviso | B: correctos / pendientes / incorrectos sin aviso |
|---|---|---|
| 1. Whisper completo, Vosk sin moneda ni unidad | 0 / 4 / 0 | 2 / 2 / 0 |
| 2. Los dos correctos | 4 / 0 / 0 | 4 / 0 / 0 |
| 3. Whisper con el precio equivocado (simulado) | 1 / 3 / 0 | 3 / 1 / 0 (el precio queda como conflicto) |
| 4. Whisper sin precio (simulado) | 1 / 3 / 0 | 2 / 2 / 0 |
| 5. Whisper con la cifra ilegible | 1 / 3 / 0 | 2 / 2 / 0 |
| **Total** | **7 / 13 / 0** | **13 / 7 / 0** |

Son **pares sintéticos**: aíslan el comportamiento de las políticas, no miden el reconocimiento. No declaran ganadora a B.

### Resultados HOST

| Comprobación | Resultado |
|---|---|
| `dart format --set-exit-if-changed`, `flutter analyze` | Sin cambios / sin problemas |
| Pruebas nuevas | `politica_b_test` +19 |
| Suites de voz | +768 pasan con `-j 4` en las ejecuciones limpias |
| Intermitente | `voice_draft_exit_test` («confirmar sale con el éxito…»), visto desde la etapa `1b95452`, falla a veces en la suite completa: en compra, planificación y aplicación, siempre con la escritura ya hecha una vez y la pantalla todavía sin salir. Aislado pasa siempre (8 de 8). **Sin resolver**: no se ha demostrado si es anterior a estos cambios |

### APK

| Dato | Valor |
|---|---|
| Archivo | `agrocuentas-f09diag-ba3feb6-arm64-v8a-profile.apk` (`.f09`, «AC F09», AGRO_VOICE_DIAG) |
| Commit | `ba3feb620b5916058ea024ae7812b9afb99663bb` |
| SHA-256 | `392022a5be7ee6acacf4984a9f19097e2fe162c2e9f119d71cac40314d82dc0c` (162 484 376 B) |
| Modelos y límites | Vosk small-es-0.42 + Whisper base q5_1; 5 000 ms; guardas sin cambios |
| Instalación | 2026-11-09 15:20, sin borrador abierto; conteos iguales antes y después (3/4/2/0, consentimiento 0, integridad ok) |

## 19. DEVICE: B-1 (POCO, 2026-11-09 15:26–15:34, APK `ba3feb6`)

Siete turnos, ocho frases. La política B estuvo **apagada** en los turnos 1 y 2 y **encendida** del 3 al 7 (línea `voz diag politicaB`). El turno 4 tuvo además la comparación de pistas encendida. La vista conservaba solo la última frase (turno 7); Roderich la dejó abierta para analizarla, y su contenido no se conserva aquí.

| Turno.frase | Política | Habla / silencio | Inferencia / entrega | Regla A habría elegido | Entregado | Campos «Revisar» por B |
|---|---|---|---|---|---|---|
| 1.0 | A | −34 / −47 dBFS | 3 242 / 3 294 ms | Whisper (`accepted`) | Whisper | — |
| 2.0 | A | −32 / −48 dBFS | 3 194 / 3 198 ms | Vosk (`currency`, `unit` solo en Whisper) | Vosk | — |
| 3.0 | **B** | −33 / −53 dBFS | 3 075 / 3 077 ms | Vosk (`price:extractionFailed`) | **Whisper** | precio (un solo reconocedor) |
| 3.1 | **B** | −38 / −56 dBFS | 3 476 / 3 479 ms | Vosk (`currency:missing@vosk`) | **Whisper** | moneda (un solo reconocedor; Whisper no la trae, queda pendiente) |
| 4.0 | B (+ pistas) | −35 / −54 dBFS | 3 067 / 3 069 ms; extra: sin pista 2 778 ms, dominio 3 467 ms | Whisper | Whisper | — |
| 6.0 | B | −34 / −56 dBFS | 3 115 / 3 117 ms | Whisper | Whisper | — |
| 7.0 | B | −33 / −50 dBFS | 3 279 / 3 281 ms | Whisper | Whisper | — |

Sin saturación ni audio perdido; ninguna frase agotó el límite.

**Turno 7 (vista):**

- Vosk escribió bien todo el precio (importe, moneda y «el litro»), pero el producto llegó en plural (palabra que sí está en el vocabulario), que la app deja ambiguo.
- Whisper trajo el producto correcto y el mismo importe y moneda. Perdió la «a» (puso una coma) y escribió «de litro».
- Las listas coinciden, así que A y B eligen lo mismo: Whisper.
- Interpretación de Whisper: Herbicida DEMO y 5 L resueltos; precio 120 pendiente («de litro» tras la moneda, que lleva a la pregunta «¿… por L?» de `ba3feb6`); BOB en «Revisar», por faltar la «a».
- La vista no muestra el mensaje del campo. Que el formulario pregunte «¿120 Bs por L?» queda **por comprobar en la pantalla**.

**Lectura (exploratoria):**

- En 5 de las 6 frases dictadas con B, Whisper fue válido; en todas se entregó su texto.
- B cambió el resultado frente a A en 2 frases (3.0 y 3.1): marcó solo el campo afectado y, en 3.1, no insertó la moneda que solo traía Vosk.
- **No se sabe si esos campos eran correctos:** el contenido de las frases 3.0 y 3.1 no se conserva, y la exactitud por campo requiere lo que Roderich vio.

## 20. DEVICE: B-2, frase de Fungicida (POCO, 2026-11-09 16:03–16:05, APK `ba3feb6`)

Cuatro turnos, una frase cada uno. B estuvo activa en los turnos 9 y 12; en el 10 no hay registro de B, así que actuó la regla A. Pistas comparadas en los turnos 11 y 12. Primero se leyó el formulario y después la vista, que abrió Roderich; su contenido no se conserva aquí.

Resultado por campo frente a lo dictado (producto Fungicida DEMO, 3 L, 45 por L, BOB). «Pendiente» quiere decir sin resolver o en «Revisar».

| Turno | Entregado | Producto | Cantidad | Precio | Moneda | Qué habría hecho la otra política |
|---|---|---|---|---|---|---|
| 9 | Whisper (B) | fuera del catálogo | **correcta** | pendiente con «¿45 por L?» (palabra desconocida antes de «el litro») | pendiente (solo la oyó Vosk; no se insertó) | A: Vosk, con cantidad, 45 por L y BOB, **los tres en «Revisar»** y producto fuera del catálogo |
| 10 | Vosk (A) | — | — | — | — | Nada aplicado. B: Whisper, con producto ambiguo (Fungicida candidato), sin cantidad y precio pendiente |
| 11 | Whisper (A = B) | ambiguo (otro nombre) | **correcta** | pendiente (sin moneda unida al importe) | falta | — |
| 12 | Whisper (B) | — | — | — | — | **Whisper perdió la cantidad** y no se aplicó nada (se pidió elegir la línea). A: Vosk, con 3 L, 45 y BOB en «Revisar» y producto fuera del catálogo |

**No se aceptó ningún valor incorrecto sin aviso** en ningún turno.

### Hallazgos

| # | Etapa | Hallazgo |
|---|---|---|
| 1 | Interpretación | **Una coma entre el importe y la moneda** («45, Bolivianos el litro») separa la moneda del precio: precio sin unidad y moneda «Falta». Es puntuación de Whisper; sin corregir |
| 2 | Selección (B) | **Cuando Whisper pierde un dato que Vosk sí trae** (turno 12: la cantidad; turno 9: la moneda), B entrega menos que A. No hay error sin aviso, pero el dato de Vosk solo se ve en la vista de diagnóstico; el formulario no ofrece elegir la otra propuesta |
| 3 | Transcripción (Whisper) | Fundió «compré tres litros» en una sola palabra en dos turnos: se pierde la cantidad |
| 4 | Transcripción (Vosk) | Esta vez escribió «fungicida» (palabra de su vocabulario), pero «DEMO» llegó como dos palabras que el lector toma como la cifra 1. Esa cifra de más hizo la alineación ambigua. No se corrige: sería suponer |
| 5 | Pista de Whisper (exploratorio) | Turno 11: con la pista del catálogo, otro nombre; con la de dominio y catálogo, **«Fungicida DEMO» correcto** (sobre el mismo audio). Turno 12: las dos pistas dieron lo mismo. Sin conclusión con dos intentos |
| 6 | Producto | «Fungicida» falló también en Whisper (dos nombres distintos), aunque está en el vocabulario de Vosk: no es solo un problema de vocabulario |

**Captura:** habla entre −32 y −37 dBFS; sin saturación ni pérdidas. Inferencia entre 3,0 y 3,2 s; las comparaciones, después de la entrega, entre 2,8 y 3,2 s.

**Lectura:** B no es mejor de forma general. Gana cuando Vosk pierde datos (turno 4 de REP-1, turno 10) y pierde cuando es Whisper quien los pierde (turnos 9 y 12). En las dos políticas, lo que falta queda pendiente y no se acepta nada mal.

## 21. Etapa `932e368`: «usar la otra propuesta» y coma entre importe y moneda (aprobado por el autor)

### Coma entre importe y moneda

Una coma **suelta** entre la cifra y una palabra de moneda se salta como puntuación del reconocedor. Así, «45, Bolivianos el litro» da 45 por L y BOB.

No cambian:

- la coma decimal: «45,50» es una sola cifra;
- una coma seguida de otra cifra: «45, 50 bolivianos» queda en 45 pendiente, sin juntar las cifras;
- una coma seguida de la unidad, sin moneda: «45, el litro» no inventa moneda;
- la coma entre productos, que sigue separando líneas.

### Usar la otra propuesta (solo diagnóstico, con la política B activa)

- **Identidad.** Cada segmento lleva su turno y su número de frase hasta la pantalla. Solo se anota lo que aportó una frase, como borrador de antes y de después, si lo nuevo es **exactamente una frase**.
- **Cuándo se ofrece.** Solo si la otra propuesta de esa frase, interpretada sobre el borrador de antes y con las mismas marcas, **trae algún dato que falta**.
- **Vista previa.** Lista qué se recuperaría, qué cambiaría, qué quedaría pendiente y qué se conserva por haberse tocado después, señalando lo corregido a mano. Dice expresamente que la otra propuesta **no es necesariamente mejor**.
- **Al confirmar:**
  - se usa el texto **completo** del otro motor;
  - campo a campo, solo se sustituye lo que la frase dejó y **nadie tocó después**;
  - lo editado o confirmado a mano y lo que aportaron otras frases se conserva;
  - las líneas nuevas se emparejan por orden y las que sobren toman claves libres;
  - las marcas de conflicto y de dato único se mantienen y nada se confirma solo.
- **Bloqueos, con corrección a mano:**
  - una línea de esa frase que se quitó;
  - una línea de esa frase que se tocó después y que la otra propuesta no trae;
  - un producto que quedaría repetido y antes no lo estaba.
- **Una vez por frase.** Después de usarla, el botón desaparece. Antes de aplicar, se vuelve a planificar sobre el borrador de ese momento.
- **Propuestas borradas.** El texto alternativo solo existe en la memoria del diagnóstico. Si se borró con «Cerrar y borrar», el botón queda deshabilitado («propuestas borradas»). No se recupera de ningún registro ni archivo.
- **Alcance de «Cerrar y borrar».** Borra todas las propuestas guardadas en memoria de esta pantalla, las mostradas en la vista.

### Pruebas (HOST, texto inyectado)

| Archivo | Casos |
|---|---|
| `otra_propuesta_test` (+15) | recupera la cantidad y pierde la moneda; recupera la moneda y cambia el producto; corrección a mano conservada; frase posterior conservada sin duplicar; clave libre para una línea nueva; línea quitada → bloqueo; repetido nuevo → bloqueo; dos líneas del mismo producto que ya existían no bloquean; propuesta igual → no se ofrece; aplicar sobre su propio resultado no reaplica; conflictos siguen pendientes; coma separadora, coma decimal, negativos, coma entre productos |
| `otra_propuesta_pantalla_test` (+3) | vista previa, sustitución sin línea duplicada, precio corregido a mano conservado, botón que desaparece tras usarlo y **cero escrituras**; cancelar no cambia nada; propuestas borradas → deshabilitado |

Suites de voz: +786 con `-j 4`, sin fallos. Análisis y formato limpios. La confirmación única y la salida sin escrituras previas siguen cubiertas por `voice_draft_exit_test` y `voice_draft_no_side_effects_test`, sin cambios en la escritura.

### APK

| Dato | Valor |
|---|---|
| Archivo | `agrocuentas-f09diag-932e368-arm64-v8a-profile.apk` (`.f09`, «AC F09», AGRO_VOICE_DIAG) |
| Commit | `932e368e4cf0a3ae01df5d8154e7d222b62c11d0` |
| SHA-256 | `7c34bff7ac746c14b56444a8167306c4de90ad08fe6b53b7d8ddad227f3655b7` (162 484 376 B; mismo tamaño que `ba3feb6` por la alineación del empaquetado. `libapp.so` es distinto y lleva los textos nuevos) |
| Instalación | 2026-11-09 16:29, tras cerrar Roderich la vista y descartar el borrador de B-2; conteos iguales antes y después (3/4/2/0, consentimiento 0, integridad ok) |

## 22. DEVICE: OP-1 (POCO, 2026-11-09 16:56–16:57, APK `932e368`)

La política B y la comparación de pistas estaban activas. En un mismo turno hubo dos frases, la compra dicha dos veces. Roderich dejó la vista previa abierta para analizarla y después la canceló. El contenido dictado no se conserva aquí.

| Frase | Entregado (B) | Diferencias | Aportación al borrador |
|---|---|---|---|
| 1 | Whisper | Cantidad, moneda y unidad, que solo trae Vosk | **Ninguna**: el texto de Whisper no tenía cantidad y el producto no estaba en el catálogo. «No cambió el borrador» |
| 2 | Whisper | Cantidad en conflicto (alineación ambigua) | Línea 1: 3 L en «Revisar» (conflicto); precio 45 con **«¿45 por L?»** (palabra desconocida + «del litro», regla de `ba3feb6` vista en el teléfono); moneda pendiente |

**Correcciones a mano de Roderich, en la línea 1:** eligió el producto Fungicida DEMO y la moneda. Las dos se ven como «Corregido a mano».

**Usar la otra propuesta (frase 1):**

- Se ofreció porque Vosk traía datos que faltaban.
- La vista previa mostró una **línea nueva**: producto fuera del catálogo, y 3, 45 y BOB, todo pendiente. «Se conservan» salió vacío, lo que es correcto porque las correcciones están en la línea de la frase 2, que esta sustitución no toca.
- **No se aplicó.** Con la frase 2, esa línea habría sido la **misma compra por segunda vez**. No se bloquea porque los productos oídos son distintos y el sistema no puede saber, sin suponer, que es la misma compra.

**Hallazgo:** cuando la otra propuesta crearía una línea nueva y el borrador ya tiene otras líneas, la vista previa debería **avisar del riesgo de duplicar la compra**, sin decidir por la persona. Sin corregir.

**Sustitución sin duplicar y conservación de una corrección a mano:** el caso no se dio de forma natural en el teléfono. La mecánica está probada en HOST con datos simulados (`otra_propuesta_pantalla_test`), no en DEVICE.

**Captura y tiempos:** habla −36/−37 dBFS; inferencia y entrega de unos 3,1–3,3 s; las comparaciones, después, en 2,8–3,2 s.

### Pistas de Whisper en OP-1 (mismo audio; Roderich dejó la vista abierta para analizarla)

| Frase | Pista del catálogo (entregada) | Sin pista | Dominio + catálogo |
|---|---|---|---|
| 1 | Producto ✗, cantidad ✗, moneda ✗ | Producto ✗, cantidad ✓, precio perdido (leído como una segunda cantidad) | **Producto ✓, moneda ✓**, cantidad ✗ |
| 2 | Producto ✗, cantidad ✓, moneda ✗ | Producto ✗, cantidad ✓, moneda ✗ | Igual que con la pista del catálogo |

### Pista de dominio: acumulado exploratorio (CTX-1, B-2 turnos 11 y 12, OP-1; 5 frases, mismo audio en cada una)

| Dato | Dominio mejor | Igual | Dominio peor |
|---|---|---|---|
| Producto | 2 | 3 | 0 |
| Palabra de moneda | 1 | 4 | 0 |
| Cantidad | 0 | 5 | 0 |

**Productos no dichos:** en estas 5 frases la pista de dominio **no propuso ningún producto que no se hubiera dicho**. Pero todas nombraban un producto del catálogo, así que falta el caso negativo: un producto que no está en el catálogo. Son 5 frases de 2 productos, sin conclusión general.

## 23. DEVICE: CTX-2, producto que no está en el catálogo (POCO, 2026-11-09 17:08, APK `932e368`)

La política B y la comparación de pistas estaban activas, con una sola frase. Roderich dejó la vista abierta para analizarla; su contenido no se conserva aquí.

| Propuesta (mismo audio) | Producto | Cantidad | Importe | Palabra de moneda | Unidad del precio |
|---|---|---|---|---|---|
| Vosk | El nombre llega, pero falta la cifra de cantidad | ✗ | ✓ | deformada | deformada |
| Whisper, pista del catálogo (entregada con B) | **Fuera del catálogo, como se dijo** | ✓ 2 kg | ✓ 30 | deformada | deformada («del …») |
| Whisper, sin pista | Fuera del catálogo | ✓ | ✓ | deformada | deformada |
| Whisper, dominio + catálogo | Fuera del catálogo | ✓ | ✓ | **deformada**, aunque la pista lleva «bolivianos» | deformada |

- **Caso negativo superado:** ninguna pista convirtió el producto en uno del catálogo. El borrador lo deja como «Falta», sin elegir ninguno conocido.
- **Política B:** entregó Whisper (2 kg, 30 pendiente, moneda pendiente). La regla A habría entregado Vosk, que no completa nada. Es un caso a favor de B, sin errores sin aviso en ninguna de las dos.
- **Moneda:** en las 6 frases medidas con la pista de dominio, la palabra «bolivianos» solo salió bien una vez.

**Acumulado de la pista de dominio** (6 frases, exploratorio):

| Dato | Dominio mejor | Igual | Dominio peor |
|---|---|---|---|
| Producto | 2 | 4 | 0 |
| Moneda | 1 | 5 | 0 |
| Cantidad | 0 | 6 | 0 |

Productos no dichos que propuso: **0**, incluido el caso negativo.

**Captura:** habla −32 dBFS, sin saturación. Inferencia 3,2 s (entregada); comparaciones 3,0 y 3,2 s.

## 24. DEVICE: OP-2, «usar la otra propuesta» sobre una línea existente (POCO, 2026-11-09 17:19–17:30, APK `932e368`)

Frase de CTX-3, con la política B y la comparación de pistas activas. Los dos motores coincidían en las cifras (`accepted`), así que llegó Whisper. Con él, el producto quedó **ambiguo** (nombre mal oído, varias candidatas): 1,5 L dictado, 85 pendiente entre «Por L» y «Total de la línea» (no se dijo la unidad, y es lo correcto) y BOB dictado.

La otra propuesta (Vosk) resolvía el producto. Por eso se ofreció el botón, aun sin diferencias de cifras.

| Paso | Resultado en el teléfono |
|---|---|
| Corrección a mano | Roderich tocó «Por L»: precio «Confirmado» |
| Vista previa | Recuperaría: «Línea 1, producto: Insecticida DEMO». Se conserva: «Línea 1, precio (corregido a mano)». Sin líneas nuevas |
| Usar esta propuesta | Línea 1: **Insecticida DEMO**, 1,5 L, **85 «Confirmado»** (la corrección sigue), BOB. **Una sola línea**; el botón desapareció |
| Escrituras | Ninguna: compras 3, ítems 4, aplicaciones 2, consentimiento 0, integridad ok |

**Comprobado en DEVICE:** la vista previa, la sustitución sin duplicar, la conservación de una corrección a mano, el uso único y la ausencia de escrituras.

Es **un solo caso** y no dice que la otra propuesta sea mejor en general. Aquí lo fue para el producto porque Vosk tiene «insecticida» en su vocabulario.

### Pistas de Whisper en CTX-3 (mismo audio; Roderich dejó la vista abierta para analizarla)

| Propuesta | Producto | 1,5 L | 85 | Moneda |
|---|---|---|---|---|
| Vosk | **Insecticida DEMO, resuelto** | ✓ | ✓ (sin unidad, pendiente) | ✓ |
| Whisper, catálogo (entregada) | Ambiguo (mal escrito) | ✓ | ✓ | ✓ |
| Whisper, sin pista | Fuera del catálogo | ✓ | ✓ | ✓ |
| Whisper, dominio + catálogo | Ambiguo (mal escrito) | ✓ | ✓ | ✓ |

- **Las dos reglas eligieron mal en el producto:** A y B entregaron Whisper porque las cifras coincidían, pero aquí Vosk tenía todo correcto. «Usar la otra propuesta» (OP-2) lo recuperó.
- La transcripción con la pista de dominio fue la más lenta (3 732 ms, frente a 2 802 sin pista y 3 102 con la del catálogo), pero corrió después de la entrega.

**Acumulado de la pista de dominio** (7 frases, exploratorio):

| Dato | Dominio mejor | Igual | Dominio peor |
|---|---|---|---|
| Producto | 2 | 5 | 0 |
| Moneda | 1 | 6 | 0 |
| Cantidad | 0 | 7 | 0 |

Productos no dichos que propuso: **0**.

## 25. Cierre de riesgos del recorrido (HOST)

### Aviso de posible repetición (pendiente de OP-1)

- La vista previa separa **«Líneas que se añadirían»**.
- Si el borrador ya tiene otras líneas, avisa: «Las líneas añadidas podrían repetir algo que ya dictó. Revíselas: no se fusiona ni se quita nada.»
- No afirma que exista una compra repetida y no fusiona, quita ni reemplaza líneas por su cuenta.

### Emparejamiento de líneas sin suponer (antes era por orden)

Las líneas que creó la frase se emparejan con las de la otra propuesta así:

1. **Por producto del catálogo resuelto**, en cualquier orden. Con varias líneas de un mismo producto, solo si hay las mismas en los dos lados y ninguna se tocó después; si no, se bloquea.
2. Lo que queda, solo si queda **una línea en cada lado** (por ejemplo, un producto sin resolver frente al mismo resuelto). Varias en los dos lados → bloqueo.
3. Una línea de la frase que la otra no trae se quitaría solo si nadie la tocó; si se tocó → bloqueo.
4. **Una corrección hecha después nunca pasa a otro producto:** si el producto de una línea cambiaría y otro campo de esa línea se tocó después → bloqueo.

Pruebas (`otra_propuesta_test` +11): la otra omite un producto (sin tocar se quitaría; corregido a mano bloquea), otro orden (cada corrección se queda en su producto), dos líneas del mismo producto (en orden si nada se tocó; tocada → bloqueo), número distinto de un mismo producto → bloqueo, cambio de producto con corrección en otro campo → bloqueo, sin resolver frente a resuelto (una por lado) → se emparejan, varias sin resolver → bloqueo, aviso con borrador no vacío, sin aviso en borrador vacío, vista previa con el aviso.

### Fallo intermitente al salir tras registrar

| | |
|---|---|
| **Síntoma** | En la suite completa, a veces la pantalla del borrador seguía abierta al comprobarlo, con la escritura ya hecha una sola vez |
| **Causa demostrada (sincronización de la prueba)** | La espera `_finishTransition` solo bombeaba diez cuadros de reloj falso, y `settle` deja a lo sumo unos 160 ms de tiempo real si no ve un indicador de progreso. La escritura real en SQLite y la navegación posterior no avanzan sin tiempo real. Con la escritura retenida y después liberada, la prueba con la espera antigua **no terminó en más de 400 s**; con la nueva, termina |
| **No es** | Navegación ni persistencia: la escritura fue única en todos los fallos, y la salida ocurre en cuanto la escritura termina |
| **Corrección** | Solo en la prueba: espera condicionada (tiempo real + reloj, hasta que la pantalla sale, con tope). La app no cambia |
| **Doble pulsación con la pantalla abierta** | Prueba nueva por operación (compra, planificación, aplicación): la escritura retenida, el botón deshabilitado mientras escribe, tres pulsaciones más → **una sola llamada** al registro y **una sola** operación |
| **Resultado** | 5 ejecuciones completas con la concurrencia por defecto sin que vuelva este fallo |

**Otras pruebas de navegación** (`voice_wiring_test`, `voice_draft_back_arrow_test`) fallaron **una vez** en 1 de 3 ejecuciones completas con la concurrencia por defecto, y pasan aisladas (2 de 2). Usan la misma espera común `settle` (`test/support/f04_mode_ui_harness.dart`), compartida con otras partes del proyecto. No se cambia aquí y se declara como fragilidad de sincronización de pruebas, no resuelta.

### Resultados HOST

| Comprobación | Resultado |
|---|---|
| `dart format --set-exit-if-changed`, `flutter analyze` | Limpios |
| Suites de voz, concurrencia por defecto | 2 de 3 limpias (+800); 1 con los dos fallos de navegación descritos |
| Suites de voz, `-j 4` | +800 |

## 26. DEVICE: compra completa (POCO, 2026-11-09 18:14–18:30, APK `71e55fc`)

APK `agrocuentas-f09diag-71e55fc-arm64-v8a-profile.apk`, SHA-256 `8a323bd1881417e0d094cb3f073e5dfcd88c1abf30c0244071eb09ebc993d849`. Configuración normal (regla A, interruptores de diagnóstico apagados al empezar). Datos sintéticos de la DEMO. Roderich dictó, corrigió y registró con su pulsación; tras registrar, autorizó a esta sesión a usar el teléfono para comprobar la persistencia.

**Frase de prueba:** compra de 2 L de Fungicida DEMO a 50 Bs por L.

### Acierto inicial del reconocimiento (antes de corregir)

Hubo 5 dictados (18:14–18:17), con veredicto `quantities` en los 5 (A entregó Vosk; en uno estuvieron encendidas B y la comparación de pistas). Revisión de Whisper entre 3,1 y 3,6 s, sin agotar el límite. Se valora el borrador del **último**; los anteriores se descartaron y no se pueden valorar.

| Campo | Estado tras el dictado | Valoración |
|---|---|---|
| Producto | «Falta», nombre fuera del catálogo | ✗ |
| Cantidad | 2 L en «Revisar» (conflicto entre motores) | Valor correcto, pendiente |
| Precio | «No válido» (palabra extraña delante de la cifra) | ✗, sin suponer |
| Moneda | BOB en «Revisar» (sin «a» delante) | Valor correcto, pendiente |

**0 de 4 campos correctos sin revisión, 2 correctos pendientes, 2 no reconocidos, 0 incorrectos sin aviso.**

### Recorrido con correcciones

- **A mano:** producto, precio, proveedor y quién recibe (Beto Mamani (DEMO)).
- **Con «Confirmar este valor»:** cantidad y moneda.
- **¿Ya pagaste?:** «No, todavía no».
- **Total calculado:** 100,00 Bs.
- **Base de datos idéntica** desde la instalación hasta justo antes de registrar: cero escrituras durante el dictado y las correcciones.

### Efectos tras registrar (una pulsación)

| Comprobación | Antes | Después |
|---|---|---|
| Compras | 3 | **4** (n.º 4, Agroinsumos DEMO (sintético), 100,00 Bs, confirmada) |
| Líneas de compra | 4 | **5** (Fungicida DEMO, 2 L, 50 Bs/L, BOB, 100,00 Bs) |
| Reparto | — | 2 L para Beto, política `BY_ACTUAL_USAGE` |
| Lotes / movimientos de inventario | 6 / 9 | **7 / 10** (lote de Beto, 2 L a 50 Bs/L; `PURCHASE_IN` +2 L) |
| Existencias de Fungicida de Beto | 2 L | **4 L** (las demás, sin cambios) |
| Pagos a proveedor | 2 (3 000,00 Bs) | Sin cambios |
| Movimientos de cuentas | 5 | **5, sin cambios.** Es lo correcto según la configuración: Beto es familiar con liquidación `BY_ACTUAL_USAGE`, y el cargo (`USAGE_CHARGE`) se escribe al **aplicar**, no al comprar (`_insertApplication`, `lib/data/agro_repository.dart`). Ver «Expectativa corregida» |
| Integridad | ok | ok |

### Persistencia (cierre forzado y nueva apertura)

| Pantalla | Resultado |
|---|---|
| Inicio | Compras 4 985,00 Bs (antes 4 885,00); pagado a proveedores 3 000,00; familias por cobrar 400,00, sin cambios |
| Operaciones → Compras | La compra nueva arriba: 1 producto, total 100,00 Bs, pagado 0,00, confirmada |
| Inventario | Fungicida DEMO, físico 12 L (antes 10); detalle por persona: Beto 4 L |
| Base de datos | Idéntica a la de justo después de registrar |

**Conclusión:** el **recorrido** se completó con éxito, con una sola escritura y efectos correctos y persistentes. El **reconocimiento** no acertó la compra: hicieron falta correcciones en 4 de los 6 datos de la compra (producto, precio, proveedor y receptor) y confirmar los otros 2. No se presenta como dictado acertado.

### Expectativa corregida

Antes de registrar, la indicación de esta sesión al autor anunció como efecto esperado un **cargo a Beto en Cuentas**. Era errónea: con `BY_ACTUAL_USAGE` la compra no genera cargo; el cargo llega con la aplicación, por el costo FIFO consumido. Lo esperado correcto, y lo observado, es: sin movimiento de cuentas por la compra. El guion versionado (`GUION_PRUEBA_VOZ_POCO.md`) no contenía ese cargo; se le añade una nota sobre los efectos en cuentas según la política (2026-11-09).

### Observación del usuario y comprobación técnica final (19:22–19:26)

- **Observación del usuario (Roderich, 2026-11-09):** cerró y reabrió «AC F09» por su cuenta y la información seguía guardada.
- **Comprobación técnica,** sin crear operaciones: copia de solo lectura de la base a las 19:22, **idéntica** a la de justo después de registrar y a la de tras el cierre forzado (mismos conteos, existencias, compras y cuentas; integridad ok). Inicio: compras 4 985,00 Bs; pagado a proveedores 3 000,00; familias por cobrar 400,00; terceros por cobrar 210,00; pagos recibidos 350,00. Compras: la n.º 4 arriba, 100,00 Bs, pagado 0,00.
- **Nota de precisión:** a las 19:26 el proceso de la app era el iniciado a las 18:33:39, tras el cierre forzado hecho por esta sesión. El cierre del usuario no terminó el proceso (MIUI puede conservarlo al cerrar la ventana). La prueba técnica de persistencia entre procesos es la del cierre forzado; la observación del usuario confirma lo mismo en la interfaz.

### Caso cerrado: compra asistida con correcciones

Completado. Una sola compra de 100,00 Bs; entrada de 2 L de Fungicida DEMO para Beto; existencias finales de Beto 4 L; sin pago nuevo; sin cargo por la compra, porque Beto liquida por uso real. Éxito del **registro**; fallo del **reconocimiento inicial** (0 de 4 campos correctos sin revisión).

## 27. DEVICE: aplicación de prueba (POCO, 2026-11-09, APK `71e55fc`): preparación

Misma APK y configuración que la sección 26 (regla A; modelos, política y contexto sin cambios). Estado inicial leído a las 19:22–19:26 de una copia de solo lectura y de la interfaz.

### Reglas que aplican (comprobadas en el código y en la base)

| Regla | Dónde | Consecuencia para el caso |
|---|---|---|
| Modalidad | `app_settings` sin ajuste → `OperationMode.defaultMode` = compartido | Cualquier persona activa puede aplicar en su chaco |
| Titular | `owner_bindings` vigente: Rosa Mamani F09 (FAMILY, `BY_ACTUAL_USAGE`) | Su consumo es «Consumo y costos propios», fuera de «Familias por cobrar» (E-15) |
| Quién aplica | La aplicación por voz fija la persona = dueño del chaco (`voice_application_draft.dart`) y sólo cuenta su stock | Chaco Río DEMO → Beto; Chaco Norte DEMO → Rosa |
| Consumo | `_lotsAvailableNow`: lotes de esa persona y producto con saldo, por `acquired_date`, `id` (FIFO). **No salta lotes vencidos** | Hay que elegir un producto cuyo primer lote FIFO no esté vencido |
| Aviso de vencimiento | Pantalla de voz: sólo lotes previstos que vencen antes o el mismo día de la aplicación | Con lote no vencido, sin aviso |
| Cargo | Con `BY_ACTUAL_USAGE`, un `USAGE_CHARGE` por el costo FIFO total | Beto: cargo por el costo consumido |

### Lotes con saldo y vencimiento (hoy 2026-11-09)

| Lote | Producto | Dueño | Adquirido | Vence | Costo | Saldo | ¿Apto? |
|---|---|---|---|---|---|---|---|
| 6 | Fungicida DEMO | Beto | 24/10 | 03/11 | 150 Bs/L | 2 L | **Vencido**; es el primero FIFO de Beto |
| 7 | Fungicida DEMO | Beto | 09/11 | — | 50 Bs/L | 2 L | Sólo se usaría después del 6 |
| 3 | Fungicida DEMO | Rosa | 24/10 | 03/11 | 150 Bs/L | 8 L | **Vencido** |
| 2 | Herbicida DEMO | Beto | 19/10 | 18/11 | 120 Bs/L | 3 L | Sí (no vencido) |
| 1 | Herbicida DEMO | Rosa | 19/10 | 18/11 | 120 Bs/L | 6 L | Sí |
| 5 | Herbicida DEMO | Rosa | 29/10 | — | 125 Bs/L | 5 L | Sí |
| 4 | Insecticida DEMO | Carmen | 24/10 | 02/11 | 90 Bs/L | 4 L | **Vencido**; Carmen no tiene chaco |

El Fungicida comprado en la sección 26 **no** sirve para este recorrido normal: cualquier aplicación de Fungicida de Beto consume primero el lote 6, vencido.

### Caso elegido

**Beto aplica 1 L de Herbicida DEMO en Chaco Río DEMO (2 ha), hoy, campaña Invierno 2026 (DEMO).** Beto es el dueño del chaco y el responsable; se usan sus propias existencias (lote 2, no vencido); como familiar con uso real, la aplicación le genera un cargo. Comprobado en HOST con el catálogo del teléfono: la frase prevista se interpreta como Chaco Río DEMO, Beto, 2 ha, Herbicida DEMO 1 L (prueba temporal, no versionada). Vosk no tiene «herbicida» en singular en su vocabulario (C1, sección 1): un fallo en el producto es esperable y no se corrige ahora.

### Valores iniciales

| Comprobación | Valor |
|---|---|
| Conteos | aplicaciones 2, ítems 2, consumos 2, movimientos de inventario 10, lotes 7, cuentas 5, compras 4, pagos a proveedor 2, planes 0, consentimiento 0; integridad ok |
| Herbicida DEMO | Beto 3 L (lote 2); Rosa 11 L (lotes 1 y 5); total 14 L |
| Cuentas | Beto: cargos 600,00, pagos 200,00, saldo 400,00; Carmen 210,00; Rosa (titular): 720,00 en asientos propios, «no son deuda» |
| Inicio | Familias por cobrar 400,00; terceros por cobrar 210,00; pagos recibidos 350,00; compras 4 985,00 |

### Efectos esperados al registrar (una pulsación)

| Comprobación | Antes | Después esperado |
|---|---|---|
| Aplicaciones / ítems / consumos | 2 / 2 / 2 | **3 / 3 / 3**: chaco 2, persona Beto, 2 ha, costo 120,00 Bs; consumo lote 2, 1 L, 120,00 Bs |
| Movimientos de inventario | 10 | **11**: `APPLICATION_OUT` −1 L del lote 2, dueño Beto |
| Lotes | 7 | 7 (sin lotes nuevos) |
| Herbicida DEMO | Beto 3 L, total 14 L | **Beto 2 L, total 13 L**; Rosa sin cambios |
| Cuentas | 5 | **6**: `USAGE_CHARGE` +120,00 Bs a Beto, campaña 1, referencia a la aplicación |
| Saldo de Beto / Familias por cobrar | 400,00 | **520,00** |
| Compras, pagos, terceros, planes | — | Sin cambios |
