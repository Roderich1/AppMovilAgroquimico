# F09: preguntas pendientes de la evaluación, clasificadas (#12, #167)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08 (Bolivia, UTC−4) |
| Rama | `docs/f09-protocolo-guion`, desde `27e9a4e`. Sin push |
| Qué hace | Clasifica A1–A14 de [`PROTOCOLO_Y_UMBRALES.md`](PROTOCOLO_Y_UMBRALES.md) §4 y las preguntas nuevas A15–A24. Resuelve las técnicas, con su justificación. Formula las del autor con su consecuencia |
| Qué no hace | **No cambia ningún valor de c-12** (§2 del protocolo). No escribe frases de aceptación. Cada valor nuevo es una **propuesta, pendiente del autor**, hasta que Roderich lo registre en #12 antes de la primera toma |
| Procedencia | Lectura de documentos y del código en `27e9a4e`. Nada medido |

**Clases:**
- **(a) técnica:** se resuelve leyendo las fuentes o el código. Va con su justificación.
- **(b) alcance del autor:** decide Roderich. Va la pregunta, su consecuencia y, si procede, una propuesta.
- **(c) participantes o dispositivos:** sólo se resuelve con personas o teléfonos.

Algunas tienen dos clases: se indica qué parte es de cada una.

## 1. Resumen

| # | Tema | Clase | Estado |
|---|---|---|---|
| A1 | ADR-004 `Proposed` | (a) | Resuelta: los umbrales valen por F1 |
| A2 | Whisper small o base | (b) | Propuesta P-A2 |
| A3 | WER | (a) | Resuelta: sólo dato, nunca criterio |
| A4 | Tamaño del holdout | (b) | Propuesta P-A4 |
| A5 | Número de participantes | (b) + (c) | Propuesta P-A5 |
| A6 | Muestras de rechazo | (b) + (c) | Propuesta P-A6 |
| A7 | Método de percentil | (a) | Resuelta técnicamente; registrar (P-A7) |
| A8 | Margen de «no inferior» | (b) | Propuesta P-A8 |
| A9 | Grabar audio para D6 | (b) | Propuesta P-A9 |
| A10 | Transcripción en la evidencia versionada | (b) | Propuesta P-A10 |
| A11 | Definición operativa de «útil» | (a) + (b) | Resuelta en lo principal; P-A11 para los campos ambiguos |
| A12 | Datos de sesión | (a) + (c) | Métodos propuestos (P-A12); medir exige teléfono |
| A13 | Teléfonos | (c) | Sin cambios: POCO y HONOR, por separado |
| A14 | RF-41 y DAT-21 | (a) | Verificados en la copia local del documento entregado |
| A15 | La evidencia no guarda ficha, modelo ni tiempos | (a) + (b) | Hallazgo de código; decisión P-A15 |
| A16 | Primer parcial y RTF sin instrumento | (a) + (b) | Hallazgo; P-A16 |
| A17 | Un consentimiento por teléfono, varias personas | (b) | Propuesta P-A17 |
| A18 | Cómo lee el evaluador la evidencia | (a) + (b) | Hallazgo; P-A18 |
| A19 | Plazo de conservación | (b) | Propuesta P-A19 |
| A20 | Copia `.previo` con evidencia | (b) | Ver [`COPIA_PREVIA_Y_EVIDENCIA.md`](COPIA_PREVIA_Y_EVIDENCIA.md) |
| A21 | Cambio del texto de consentimiento | (a) + (b) | Hallazgo; P-A21 |
| A22 | Qué es una «sesión» para la estabilidad | (b) | Propuesta P-A22 |
| A23 | «Modo avión desde una instalación limpia» con activación en línea | (b) | Propuesta P-A23 |
| A24 | Quién escribe las fichas y quién dicta | (c) | Sin persona: `NOT_MEASURED` |

## 2. (a) Técnicas resueltas

**A1. ADR-004 sigue `Proposed`.**
- Resolución: los umbrales se aplican a #12 porque F1 es una decisión del autor registrada en #12 antes de medir. No hace falta aceptar ADR-004 para medir.
- Justificación: F1 cita a ADR-004 como **fundamento**, no como condición. ADR-004, línea 7, sólo impide que sustituya a ADR-002.
- Lo que no se deduce: que #12 acepte ADR-004. Aceptarlo sigue siendo una decisión aparte.

**A3. WER.**
- Resolución: no es criterio. Si se calcula, va como dato, separado de los veredictos.
- Justificación: ningún umbral de F1 usa WER, y F4 (línea 82) dice que no se calcula. `f09_metricas.py` no lo calcula.

**A7. Método de percentil.**
- Resolución técnica: **rango más cercano, sin interpolar**, el que ya usa `f09_metricas.py` (líneas 112-118).
- Justificación:
  - devuelve siempre un tiempo observado, nunca uno inventado entre dos tomas;
  - con pocas tomas es el lado prudente para umbrales «≤»: con menos de 20 valores, el p95 es el máximo;
  - es una definición estándar (Hyndman y Fan, tipo 1).
- **P-A7 (propuesta, pendiente del autor):** registrarlo en #12 junto a los umbrales, antes de medir. No cambia ningún valor.

**A11. Transcripción útil (D2).** Resuelta en lo principal:
- 3.13.3 del documento entregado (párrafo «Protocolo de voz (RNF-14)»): «Una transcripción es útil si permite proponer los campos esperados sin reescribirla». Coincide con D2 de F1.
- `f09_metricas.py` (`_es_util`, líneas 153-168) ya lo aplica así: motor terminado bien y todos los campos esenciales que la ficha espera, correctos frente a la ficha.
- Lo que falta decidir va en P-A11 (§3).

**A14. RF-41 y DAT-21.** Verificados; detalle en [`TRAZABILIDAD_RF41_DAT21.md`](TRAZABILIDAD_RF41_DAT21.md).

**Partes técnicas de A12, A15, A16, A18 y A21:** son hallazgos del código. Están en §3, junto a la decisión que piden.

## 3. (b) Decisiones del autor

Cada propuesta es **propuesta, pendiente del autor**. Ninguna vale hasta que Roderich la registre en #12 antes de la primera toma.

**A2. Whisper small o base.**
- Pregunta: ¿con qué segunda pasada se evalúa #12?
- Consecuencia:
  - Con **base** (la de la APK de integración), los umbrales de la segunda pasada, escritos para small, quedan **sin veredicto**: se informan aparte.
  - Con **small**, en HOST la inferencia tardó unos 2,7 s de mediana frente a 0,73 s con base (`docs/f09/whisper/WHISPER_SMALL_HOST_2026-11-08.md`). En el teléfono no se ha medido.
- **P-A2:**
  - evaluar #12 con la configuración que se entregaría: base, con «Revisar cada frase» según decida el autor;
  - medir small en el POCO en una sesión técnica aparte, sin participantes, sólo para decidir si se habilita;
  - declarar la diferencia como limitación.

**A4. Tamaño del holdout.**
- Pregunta: ¿el holdout de #12 es el conjunto de F3?
- Consecuencia: sin decidirlo no se puede fijar el hash.
- **P-A4:** adoptar F3: 20 fichas (7 de compra, 6 de planificación y 7 de aplicación) más las muestras de rechazo de P-A6, por teléfono y condición.
- Justificación:
  - ya está fijado (D-F09-5) y tiene plantilla (`tool/f09_device/conjunto_plantilla.csv`);
  - con 20 dictados, un 90 % admite como mucho 2 errores por tipo de campo;
  - el intervalo de Wilson al 95 % para 18/20 va de 0,70 a 0,97. D5 obliga a declarar ese tamaño junto a cada porcentaje.

**A5. Número de participantes.**
- Consecuencia: con una sola persona, el resultado describe su voz y nada más (D5).
- **P-A5:** al menos **3** personas adultas voluntarias, que no ajustaron el intérprete, con datos sintéticos. Si sólo dicta el autor, se declara «1 participante (autor)» como limitación.
- Justificación: hacen falta varias voces para ver la variación entre hablantes; 3 es el mínimo que la muestra.
- Coste estimado: 20 fichas × 2 condiciones por teléfono, unos 40 dictados por persona y teléfono.
- Parte (c): conseguir a las personas.

**A6. Muestras de rechazo.**
- **P-A6:** por teléfono, **5 de silencio sin voz y 5 de ruido sin voz**, de unos 10 s cada una. F3 pedía 2; 2 es el mínimo.
- Justificación: el umbral es 0 textos aceptados, así que más muestras lo ponen más a prueba. No necesitan participantes y cuestan poco.
- La fuente del ruido se describe antes, como en D4.

**A8. Margen de «no inferior» frente a Android.**
- **P-A8:**
  - margen **0**: el número de cantidades y unidades correctas del motor local debe ser mayor o igual que el de Android, con los mismos audios;
  - se informan además los pares discordantes (local bien y Android mal, y al revés), sin prueba estadística ni valor p.
- Justificación:
  - F1 y ADR-004 no fijan tolerancia, y añadir una ahora aflojaría el criterio;
  - con unos 20 pares, ninguna prueba tiene potencia: la comparación es descriptiva, como dice D6.
- Sin los mismos audios, el resultado es **NO DEMOSTRADO** (ver A9).

**A9. Grabar audio para D6.**
- Consecuencia: la app no tiene dónde guardar audio. Grabar exige otra herramienta, otro consentimiento y otra tarea.
- **P-A9:** no grabar en esta evaluación y declarar «no inferior a Android: NO DEMOSTRADO» como limitación. La alternativa (grabar) queda para una tarea propia, si el autor la abre.

**A10. Transcripción en la evidencia versionada.**
- **P-A10:**
  - la transcripción se queda en el teléfono, con consentimiento;
  - en el repositorio y en `docs/evidence/` sólo van códigos, conteos y veredictos;
  - las frases del holdout se publican después de medir, si el autor lo decide (F3, línea 76).

**A11 (resto). Campo ambiguo.**
- Pregunta: un campo que la app deja **ambiguo** con la opción correcta entre las candidatas, ¿es correcto?
- **P-A11:** cuenta como **incorrecto**, con la causa anotada.
- Justificación: D1 dice «obtenidos correctamente», y un campo ambiguo no se obtuvo: bloquea el registro hasta que la persona elige, igual que una corrección.

**A12. Datos de sesión: métodos.**
- La parte técnica es elegir un método reproducible. **P-A12:**
  - **Memoria pico:** muestrear `adb shell dumpsys meminfo <paquete>` cada 2 s durante el dictado con los dos motores cargados, y tomar el máximo de `TOTAL PSS`. Se declara que es PSS muestreado, no un pico exacto.
  - **Térmico y batería:** `adb shell dumpsys battery` (`temperature`, `level`) al empezar y a los 10 min de uso repetido, con el teléfono desenchufado durante el tramo.
  - Sin estos datos, `NOT_MEASURED`.
- Medirlos exige el teléfono: parte (c).

**A15. La evidencia no guarda ficha, modelo ni tiempos (hallazgo de código).**
- Qué pasa: `finishVoiceEvidence` (`lib/presentation/voice/voice_evidence_hook.dart`) sólo pasa el motor y el commit. `sheetRef`, `model`, `firstPartialMs` y `finalMs` existen en la entrada y en la tabla, pero quedan siempre vacíos (`null`).
- Consecuencia: el evaluador tiene que emparejar cada entrada con su ficha por orden y hora, a mano. Los tiempos no salen de la evidencia.
- **P-A15:** antes de #12, que la coordinadora:
  - permita indicar el código de la ficha antes de dictar, sólo en la compilación de evaluación;
  - pase el modelo (`vosk-model-small-es-0.42`, más el de la revisión).

  Si no se hace, se declara el emparejamiento manual y su riesgo de error.

**A16. Primer texto parcial y RTF sin instrumento (hallazgo de código).**
- Qué pasa:
  - la app sólo registra el tiempo de la revisión de cada frase (`revision=…ms`, `lib/voice/port/local_speech_transcription_adapter.dart:437-440`);
  - no registra cuándo llega el primer parcial de Vosk ni cuánto dura el audio de cada frase.
- Consecuencia: los umbrales «primer parcial p50 ≤ 800 ms / p95 ≤ 1 500 ms» y «RTF p95 ≤ 0,50» quedarían `NOT_MEASURED`.
- Además, «desde el inicio del habla» no se puede saber sin audio.
- **P-A16:**
  - definir operativamente el primer parcial como el tiempo desde que el micrófono pasa a «Escuchando» hasta el primer texto provisional no vacío, y declararlo así;
  - que la coordinadora lo registre, junto con la duración de cada frase que ya conoce el motor nativo, como códigos y milisegundos, sin texto.

**A17. Un solo consentimiento por teléfono.**
- Qué pasa: la tabla admite una sola fila (`id = 1`). Las entradas no identifican a la persona, y «Retirar el permiso» borra **todas** las entradas.
- Consecuencia: si dos personas usan el mismo teléfono, la segunda no puede dar su permiso sin que antes se borre lo de la primera. Tampoco se puede separar lo de cada una.
- **P-A17:** una persona por turno:
  1. la persona acepta;
  2. dicta;
  3. el evaluador lee y codifica su evidencia (P-A18);
  4. se pulsa «Retirar el permiso», que borra todo, antes de la siguiente.

  El código seudónimo de la persona va en el registro del evaluador, no en la app.

**A18. Cómo lee el evaluador la evidencia (hallazgo de código).**
- Qué pasa: ninguna pantalla llama a `VoiceEvidenceStore.readAll`. La de consentimiento sólo muestra el número de dictados guardados.
- Con una APK *profile* (depurable), la única vía es copiar **toda** la base con `adb exec-out run-as`. Eso incluye los demás datos del teléfono, que en la evaluación son sintéticos.
- **P-A18:** que la coordinadora añada, sólo en la compilación de evaluación, una vista de lectura de la evidencia en el propio teléfono, sin exportarla.
  - Mientras no exista, el procedimiento es copiar la base al equipo del evaluador, leer sólo las tablas `voice_evidence*` y borrar la copia al terminar.
  - El consentimiento debe decirlo (ver [`CONSENTIMIENTO_PROPUESTA.md`](CONSENTIMIENTO_PROPUESTA.md)).

**A19. Plazo de conservación.**
- Qué pasa: la app no borra la evidencia sola.
- **P-A19:** se borra al terminar el turno de cada persona, una vez codificada (P-A17), y como máximo **30 días** después de su sesión.
- Justificación: la finalidad acaba al codificar; los 30 días cubren una repetición de la sesión si falla algo.

**A20. La copia `.previo` contiene evidencia.** Ver [`COPIA_PREVIA_Y_EVIDENCIA.md`](COPIA_PREVIA_Y_EVIDENCIA.md).

**A21. Cambio del texto de consentimiento (hallazgo de código).**
- Qué pasa: `grantConsent` conserva el consentimiento que ya existía, con su versión (`lib/voice_evidence/voice_evidence_store.dart:126-128`), y `record` no compara la versión.
- Consecuencia: un teléfono que aceptó el texto anterior sigue guardando bajo ese texto aunque la pantalla muestre el nuevo.
- **P-A21:**
  - al aprobar el texto, cambiar la versión (`voiceEvidenceConsentTextVersion`);
  - en cada teléfono, «Retirar el permiso» y volver a aceptar;
  - o que el código pida aceptar de nuevo cuando la versión no coincida.

**A22. Qué es una «sesión» para la estabilidad.**
- **P-A22:** una sesión es abrir una pantalla de voz, hacer al menos un dictado y salir (registrando o cancelando). Se cuentan 30 seguidas por teléfono, y valen las del holdout.
- Una caída, un ANR o un OOM se registran con su hora.

**A23. «Modo avión desde una instalación limpia».**
- Qué pasa: la app necesita conectarse al Central por HTTPS una vez para activarse. La voz no usa la red.
- **P-A23:** el orden es:
  1. instalación limpia;
  2. activación en línea, el único paso con red;
  3. modo avión con Wi‑Fi y datos apagados;
  4. la primera apertura de la voz (copia y verificación del modelo) y todos los dictados, sin red.

  Se declara así.

## 4. (c) Participantes o dispositivos

| # | Qué falta | Mientras falte |
|---|---|---|
| A5 | Personas que dicten | `NOT_MEASURED` |
| A6, A12 | Sesión en cada teléfono | `NOT_MEASURED` / `NOT_RUN` |
| A13 | POCO X5 Pro y HONOR JDY-LX3P, por separado | El otro teléfono o el emulador **no** lo sustituyen |
| A24 | Una persona que escriba las fichas sin haber ajustado el intérprete (`FRASES_Y_HOLDOUT.md` §3) | Holdout `NOT_MEASURED` |

## 5. Qué no cambia

- Los umbrales y las definiciones de c-12 (protocolo §2).
- Los NOT_MEASURED, NOT_RUN y NO CUMPLE se conservan.
- El gate #17 sigue `Pending`; su estado no lo cambia Claude.
