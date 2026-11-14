# F09: protocolo y umbrales de la evaluación de la voz (#12, #167)

| Campo | Valor |
|---|---|
| Fecha real de esta versión | 2026-11-08 (Bolivia, UTC−4) |
| Base | `feat/f09-c-evidencia`, desde `49108ba` |
| Estado | **Preparación. No se ha medido nada.** Ningún resultado de esta evaluación existe todavía: todo lo que no se ejecute queda `NOT_RUN` y lo que no se mida, `NOT_MEASURED` |
| Qué hace este documento | Versiona, **sin cambiar ningún valor**, las definiciones y los umbrales que hasta hoy sólo estaban en un comentario de GitHub, y los pone junto a lo que dicen los documentos ya versionados. Señala lo que está `Proposed`, lo ambiguo y lo que falta decidir |
| Qué no hace | No fija valores nuevos (número de participantes, tamaño del holdout, margen de «no inferior»), no escribe frases de aceptación y no decide ningún gate |
| Trazabilidad | RU-12, CU-16, RF-28, RF-29, RNF-14, INT-07, DAT-17. RF-41 y DAT-21: verificados el 2026-11-08 en la copia local del documento entregado (Tablas 3.23 y 3.27); falta que el autor confirme que esa copia es la entregada. Ver [`TRAZABILIDAD_RF41_DAT21.md`](TRAZABILIDAD_RF41_DAT21.md) |

## 1. Fuentes, por orden de autoridad para esta evaluación

| # | Fuente | Qué fija | Estado |
|---|---|---|---|
| F1 | Comentario de Roderich en #12, [issuecomment-6547952377](https://github.com/Roderich1/AppMovilAgroquimico/issues/12#issuecomment-6547952377), creado el 2026-10-31T19:14:48Z y **sin ediciones** (`updated_at` igual a `created_at`, consultado el 2026-11-08). SHA-256 del cuerpo devuelto por la API (UTF-8, saltos CRLF): `d7fe7842536ba8925ea7ed05f9bd6ed832771737f3f79503d92575a07240cccf` | Definiciones D1–D6 y la tabla de umbrales | Decisión del autor registrada antes de medir. Se copia literal en §2 |
| F2 | `docs/evolution/decisions/ADR-004-hybrid-embedded-voice-engine.md`, rama `evolution/evolution-3-hybrid-voice-benchmark` `d5edbc9`, líneas 111-129 | Origen de casi todos los umbrales de F1 | **`Proposed`** (línea 3). No sustituye a ADR-002 mientras siga así (línea 7) |
| F3 | `docs/evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md` (en la base), §3, líneas 68-100 | Composición del conjunto nuevo (D-F09-5): 20 dictados y 2 sin habla; quién lo escribe; qué se fija antes | Plan del 2026-10-17, no ejecutado |
| F4 | `docs/evolution/features/F09_VOZ_ENSAYO_PREPARACION.md` (en la base), §1, §2 y §4 (líneas 15-46 y 69-87) | Registro por ID, huellas que se fijan antes, «no se calcula WER» | Preparación del 2026-10-17, no ejecutada |
| F5 | Cuerpo de #167 | Qué guarda la evidencia de dictado y sus exclusiones | Tarea `Live`, implementada en local en esta rama (ver `README.md`) |

## 2. Copia literal de F1 (no editar)

Se copia tal cual, incluido lo que remite a otras tarjetas. Si F1 cambia en GitHub, esta copia **no** se actualiza en silencio: se añade una versión nueva con su fecha y su hash, y se conserva esta.

> Conciliación con el documento entregado (`Proyecto_Grado_Rodrigo_Univalle_v1.22.1_DEPURADO.docx`), 2026-10-31. Sin cambios de estado.
>
> Esta tarjeta es la **evaluación** de la voz (OE5) y no se duplica en otra. La integración que evalúa se construye en F09-VOZ-11 (Vosk), F09-VOZ-12 (Whisper small condicional) y F09-VOZ-13 (evidencia de dictado con consentimiento, fuera del respaldo privado).
>
> - **Holdout:** el holdout ciego nuevo de esta tarjeta, congelado con hash antes de la primera ejecución y sin frases del ajuste, cumple la función de las fichas de dictado de 3.13.3 (frase y campos esperados fijados antes de hablar). No se crea otro corpus ni se reutiliza el holdout expuesto del benchmark.
> - **Métricas añadidas (RNF-14):** transcripciones útiles y campos correctos por tipo, junto con las ya previstas (no-speech, p50, p95, RTF, slots).
>
> ### Definiciones fijadas antes de medir
>
> **D1. Campos correctos.**
> - Numerador: campos esperados obtenidos correctamente.
> - Denominador: total de campos esperados de los dictados evaluados.
> - Ambos se informan por tipo de campo: producto, cantidad, unidad y parcela o persona.
> - Un campo esperado que no aparece cuenta como incorrecto.
> - Los campos añadidos indebidamente (no esperados por la ficha) no alteran el numerador, pero se registran aparte, con su conteo y el número de dictados afectados.
> - La referencia es la ficha, no lo confirmado por la persona.
>
> **D2. Transcripción útil.**
> - Es útil el dictado que produce un borrador utilizable sin corregir sus campos esenciales: producto, cantidad y unidad, más parcela o persona cuando la ficha los exige.
> - Una transcripción vacía, fallida, cancelada por error del motor o agotada por tiempo cuenta como no útil.
> - Denominador: todos los dictados con voz ejecutados en la condición, incluidos los fallidos.
>
> **D3. Equivalencias admitidas, fijadas en las fichas antes de dictar y sin añadir otras después.**
> - Unidades: L = litro(s) = 1 000 mL; kg = kilo(s) = kilogramo(s) = 1 000 g. Se compara en la unidad base.
> - Cantidades: cifras o palabras con coma o punto decimal y expresiones como «dos y medio», equivalentes cuando representan el mismo valor.
> - Producto, parcela y persona: la denominación del catálogo de la ficha o un alias registrado en ella. Un producto parecido pero distinto es incorrecto.
>
> **D4. Condiciones.**
> - **Voz en ambiente tranquilo:** dictado en interior, sin fuentes de ruido introducidas.
> - **Voz con ruido:** dictado con ruido de campo. La fuente y su descripción (por ejemplo, la reproducción de una grabación de ambiente agrícola o de un motor) se registran antes de ejecutar. El nivel se mide sólo si hay un instrumento disponible; si no, se describe cualitativamente, sin cifras supuestas.
> - **Silencio sin voz y ruido sin voz:** son pruebas de rechazo y no entran en los denominadores de D1 ni de D2.
>
> **D5. Informe.**
> - Resultados separados por teléfono y por condición, sin promediar entre ellos.
> - Junto a cada porcentaje se declaran el tamaño del conjunto (fichas y dictados), el numerador y el denominador.
> - NOT_MEASURED y NOT_RUN se conservan.
> - Los resultados describen el conjunto evaluado y no acreditan por sí solos el rendimiento en toda la población de agricultores.
>
> **D6. Comparación con Android.**
> - **Comparación reproducible:** se pasan a los dos motores los mismos audios. Exige grabarlos, con un consentimiento específico para esa finalidad: la grabación es una excepción a la regla de no guardar audio por defecto.
> - **Si no pueden usarse exactamente los mismos audios y condiciones** (por ejemplo, porque cada motor recibe un dictado distinto de la misma frase), se registra la limitación y la condición «no inferior» no se declara demostrada.
> - La configuración de cada motor y su versión se registran.
>
> ### Umbrales fijados antes de medir
>
> | Métrica | Valor | Fundamento | Dispositivo o condición | Criterio de aceptación |
> |---|---|---|---|---|
> | Primer texto parcial de Vosk | p50 ≤ 800 ms y p95 ≤ 1 500 ms | ADR-004 (criterio fijado antes del benchmark de 2026-09) | POCO X5 Pro (Android 12) y HONOR JDY-LX3P (Android 16), por separado; voz en ambiente tranquilo y voz con ruido | Cumple en ese teléfono y condición si se satisfacen ambos percentiles |
> | Final de Whisper small (frases ≤ 20 s) | p50 ≤ 2 500 ms y p95 ≤ 5 000 ms | ADR-004 | Cada teléfono con la segunda pasada activada | Condición para habilitar la segunda pasada en ese teléfono |
> | Factor de tiempo real de Whisper small (frases ≤ 60 s) | p95 ≤ 0,50 | ADR-004 | Cada teléfono con la segunda pasada activada | Condición para habilitar la segunda pasada en ese teléfono |
> | Memoria pico total | ≤ 1,2 GB | ADR-004 | Cada teléfono, con los dos motores cargados | Si se supera, la segunda pasada no se habilita en ese teléfono |
> | Estabilidad | 0 caídas, ANR u OOM en 30 sesiones consecutivas | ADR-004 | Cada teléfono | Requisito para aceptar la integración en ese teléfono |
> | Térmico y batería | Registro obligatorio en 10 min de uso repetido; sin umbral | ADR-004 (documentar); el documento pide medir el consumo | Cada teléfono | Se informa; si no se mide, consta NOT_MEASURED |
> | Rechazo: texto aceptado en silencio sin voz y en ruido sin voz | 0 muestras | ADR-004 | Muestras de rechazo, aparte de los dictados; no entran en ningún denominador de dictados | Cualquier texto aceptado es NO CUMPLE |
> | Escrituras sin confirmación (cancelar, no hablar, micrófono denegado, resultado tardío) | 0 escrituras y 0 sobrescrituras | RF-29 y #16 (criterio vigente de la voz existente) | HOST y cada teléfono | Cualquier escritura es NO CUMPLE |
> | Funcionamiento en modo avión desde una instalación limpia | Sí | ADR-004 | Cada teléfono | Requisito para aceptar la integración |
> | Cantidad y unidad correctas, frente a Android | No inferior al reconocimiento de Android | ADR-004 («no empeoran respecto del mejor baseline») | Holdout de #12, por teléfono y condición, con los mismos audios | Sólo se declara demostrado con los mismos audios (§D6); si no, se registra la limitación y la condición queda no demostrada |
> | Campos correctos por tipo (producto, cantidad, unidad, parcela o persona) | ≥ 90 % con voz en ambiente tranquilo; ≥ 80 % con voz con ruido, por tipo | Decisión del autor (2026-10-31): criterio de aceptación académico fijado antes de medir; no es una cifra obtenida experimentalmente ni un rendimiento garantizado de Vosk + Whisper small | Holdout de #12, por teléfono y condición | Cumple si cada tipo de campo alcanza el valor en ese teléfono y condición (definición en §D1) |
> | Transcripciones útiles | ≥ 80 % con voz en ambiente tranquilo; ≥ 70 % con voz con ruido | Decisión del autor (2026-10-31): criterio de aceptación académico fijado antes de medir; no es una cifra obtenida experimentalmente ni un rendimiento garantizado de Vosk + Whisper small | Holdout de #12, por teléfono y condición | Cumple si alcanza el valor en ese teléfono y condición (definición en §D2) |
>
> Los umbrales se registran en #12 antes de la primera sesión y no se cambian después de observar resultados. Una modificación previa se registra con su justificación, como exige ADR-004. El benchmark histórico (#58, #59, NO_GO_C4) es un antecedente: sus resultados y sus NOT_MEASURED se conservan y no cuentan como medición de esta evaluación.

## 3. Lo que dicen los documentos ya versionados (citas literales)

**F2, ADR-004 (`Proposed`), líneas 113-126 y 128-129:**

> El ADR sólo puede pasar a `Accepted` si el benchmark demuestra en POCO API 31 y HONOR API 36:
>
> - Vosk entrega primer parcial p50 <= 800 ms y p95 <= 1500 ms;
> - Whisper small finaliza p50 <= 2500 ms y p95 <= 5000 ms para frases de hasta 20 s;
> - factor de tiempo real de Whisper p95 <= 0,50 en frases de hasta 60 s;
> - memoria pico total <= 1,2 GB;
> - ninguna caída, ANR u OOM en 30 sesiones consecutivas;
> - aumento térmico y throttling documentados en 10 minutos de uso repetido;
> - cero texto aceptado en todas las muestras de silencio y ruido sin voz;
> - mejora estadísticamente visible en datos críticos frente a Android del corpus anterior;
> - cantidades, montos y unidades no empeoran respecto del mejor baseline;
> - modelos, binarios, licencias, versiones y hashes son reproducibles;
> - funcionamiento en modo avión desde una instalación limpia;
> - ingreso manual y cero escrituras de negocio conservados.
>
> Los umbrales pueden cambiar antes del benchmark, pero no después de ver los resultados sin
> registrar y justificar la modificación.

**F3, plan del ensayo físico, línea 78:**

> - **Composición:** 20 dictados nuevos (7 de compra, 6 de planificación y 7 de aplicación) y 2 entradas sin habla.

**F4, preparación, líneas 81-82:**

> **No se hace:**
> - calcular WER ni ninguna tasa de palabras, porque no se guarda la transcripción con la que compararla;

## 4. Lo que está `Proposed`, es ambiguo o falta decidir

Ninguno de estos puntos se resuelve aquí. Cada uno es una pregunta para Roderich (o lo resuelve un documento suyo) **antes** de la primera toma.

**Revisión del 2026-11-08:** la clasificación de A1–A14, las preguntas nuevas A15–A24, lo resuelto técnicamente y las propuestas (pendientes del autor) están en [`PREGUNTAS_CLASIFICADAS.md`](PREGUNTAS_CLASIFICADAS.md). Esta tabla y §2 no cambian.

| # | Punto | Qué dicen las fuentes | Efecto si no se decide |
|---|---|---|---|
| A1 | ADR-004 sigue `Proposed` | F1 toma de él casi todos los umbrales; F1 es una decisión del autor registrada en #12 | Los umbrales valen como criterio de #12 (F1), no como aceptación de ADR-004 |
| A2 | Whisper **small** o **base** | F1 y ADR-004 hablan de small; ADR-005 se aceptó provisionalmente con base sólo para la demostración (plan común §2.1) | Medir con base no cumple el texto de los umbrales de la segunda pasada: se informaría aparte, sin veredicto contra ellos |
| A3 | WER | F4 dice que no se calcula; ADR-005 y el PR #190 lo informan. Ningún umbral de WER | Si se calcula, sólo como dato, nunca como criterio. `f09_metricas.py` no lo calcula |
| A4 | Tamaño del holdout | F3 fija 20 dictados y 2 sin habla (D-F09-5, 2026-10-17). F1 no fija número ni dice si su holdout es ese conjunto | No se inventa. Si no se decide, se usa lo que fije el autor del conjunto y se declara |
| A5 | Número de participantes | Ninguna fuente lo fija | No se inventa. D5 de F1 ya limita la lectura: los resultados describen el conjunto evaluado |
| A6 | Muestras de rechazo | F3: 2 entradas sin habla. F1: «silencio sin voz y ruido sin voz», sin número | Se registran las que haya; el umbral es 0 textos aceptados |
| A7 | Método de percentil | F1 y ADR-004 no lo fijan | `f09_metricas.py` usa rango más cercano, sin interpolar, y lo declara en su salida. Pendiente de confirmar |
| A8 | «No inferior» a Android | F1: «no inferior», sólo con los mismos audios (D6). ADR-004 añade «mejora estadísticamente visible», que F1 no recoge. Ninguno fija margen ni prueba | Sin los mismos audios: NO DEMOSTRADO. Con ellos, la comparación es descriptiva y se declara así |
| A9 | Grabar audio | F3 (§1.4): «no se graba audio». F1 (D6): se puede grabar con un consentimiento específico. #167: sin audio por defecto | La evidencia de la app **no tiene dónde guardar audio**. Grabar para D6 exige otra herramienta, otro consentimiento y otra tarea |
| A10 | Transcripción en la evidencia | F3/F4: no se copian las frases a la evidencia versionada y no se guarda la transcripción. #167: la evidencia local, con consentimiento, guarda la transcripción | Se mantienen separadas: la transcripción puede quedar en el teléfono (con consentimiento); a `docs/evidence/` sólo van códigos, conteos y veredictos, salvo que el autor decida otra cosa |
| A11 | Definición operativa de «transcripción útil» (D2) | F1: «borrador utilizable sin corregir sus campos esenciales» | `f09_metricas.py` lo deriva así: motor terminado bien y todos los campos esenciales esperados correctos frente a la ficha. Pendiente de confirmar |
| A12 | Datos de sesión (memoria, 30 sesiones, térmico y batería, modo avión) | F1 los fija por teléfono, no por toma | Se registran en la tabla de sesión de la plantilla; el script no los calcula |
| A13 | Teléfonos | F1: POCO X5 Pro (Android 12) y HONOR JDY-LX3P (Android 16), por separado. F3: si el HONOR no está, `NOT_MEASURED` (D-F09-6) | No se sustituye un teléfono por el emulador ni por el otro teléfono |
| A14 | RF-41 y DAT-21 | Sólo #167 los nombra | Confirmar en el Cap. III antes de usarlos |

## 5. Reglas de lectura que ya están fijadas (de F1, sin añadir nada)

- Resultados por teléfono y por condición, sin promediar (D5).
- Junto a cada porcentaje, el tamaño del conjunto (fichas y dictados), el numerador y el denominador (D5).
- `NOT_MEASURED` y `NOT_RUN` se conservan (D5); un resultado negativo es `NO CUMPLE`, no se reinterpreta.
- La referencia de D1 es la ficha, no lo confirmado por la persona.
- Los umbrales no se cambian después de observar resultados; un cambio previo se registra con su justificación.
- El benchmark histórico (#58, #59, NO_GO_C4) no cuenta como medición de esta evaluación.
