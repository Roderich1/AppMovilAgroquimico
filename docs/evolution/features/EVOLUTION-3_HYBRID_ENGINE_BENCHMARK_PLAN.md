# EVOLUTION-3 — Plan de benchmark para motor híbrido local

## Estado

`PROPOSED`. Este benchmark debe ejecutarse antes de introducir los motores en la aplicación de
producción o aceptar `ADR-004`.

## Preguntas que debe responder

1. ¿Vosk ofrece parciales suficientemente rápidos para que la app se sienta inmediata?
2. ¿Whisper small mejora realmente productos, personas, cantidades, montos y frases largas?
3. ¿El beneficio justifica tamaño, memoria, batería y temperatura?
4. ¿Ambos funcionan sin red desde una instalación limpia?
5. ¿La combinación reduce o aumenta falsas afirmaciones sobre silencio y ruido de campo?
6. ¿Puede ejecutarse con seguridad en API 31 y API 36?

## Matriz de candidatos

| ID | Parciales | Final | Propósito |
|---|---|---|---|
| C0 | Android `SpeechRecognizer` | Android | baseline histórico |
| C1 | Vosk small es 0.42 | Vosk small es 0.42 | medir Vosk aislado |
| C2 | ninguno | Whisper base q5_1 | baseline Whisper anterior |
| C3 | ninguno | Whisper small q5_1 | medir mejora por tamaño |
| C4 | Vosk small es 0.42 | Whisper small q5_1 | propuesta híbrida |

No incorporar un candidato adicional sin registrar nombre exacto, fuente, licencia, versión,
tamaño comprimido/descomprimido y SHA-256.

## Dispositivos obligatorios

| Dispositivo | API | Razón |
|---|---:|---|
| POCO X5 Pro 5G | 31 | comparación directa con benchmark anterior |
| HONOR JDY-LX3P | 36 | dispositivo donde falló la dependencia de modelos del sistema |

Registrar SoC, ABI, RAM total/disponible, versión Android, fabricante, temperatura inicial,
estado de batería, modo de energía y si el teléfono está conectado al cargador.

## Condiciones controladas

- APK release o profile con código nativo optimizado; no medir inferencia nativa sin optimizar.
- Mismo commit, modelos y argumentos en ambos teléfonos.
- Modo avión verificado mediante sistema/ADB.
- Batería entre 30 % y 85 %, sin cargador durante batería/temperatura.
- Pantalla con brillo fijo.
- Sin otras aplicaciones activas relevantes.
- Cinco minutos de estabilización antes de memoria y temperatura.
- Warm-up separado y no contado como muestra.
- Tres tomas por frase como mínimo.
- Orden de motores aleatorizado para reducir sesgo por práctica y temperatura.

## Corpus

Reutilizar el corpus versionado de Fase 0 sin modificar el conjunto de aceptación. Añadir un
corpus nuevo, versionado y separado:

### A. Acciones cortas

- registrar compra;
- aplicar planificación;
- registrar pago;
- continuar hablando, corregir y descartar.

### B. Dictado largo de compras

- 1, 2, 4 y 8 productos;
- litros, kilos y unidades;
- BOB y USD;
- precios enteros y decimales;
- proveedor, campaña y propietario antes o después de los ítems.

### C. Aplicaciones y planificación

- nombres de chaco;
- plan único y planes ambiguos;
- cambio entre cantidad planeada y real;
- insuficiencia de stock expresada en lenguaje natural.

### D. Pagos

- nombres simples y homónimos;
- cientos, miles y decimales;
- pago normal, excedente y posible adelanto.

### E. Catálogo agrícola

Incluir productos reales, aliases y variantes de pronunciación, manteniendo separados ajuste y
aceptación. Al menos:

- Bellator;
- Germispa;
- Germi-100 / “germi cien” / “germi uno cero cero”;
- Expansive / “expansiv”;
- Paraquat;
- Mancozeb;
- Lambdacialotrina.

### F. Negaciones y correcciones

- “no fueron doce, fueron dos”;
- “borra Bellator”;
- “el precio no es ciento ochenta, es ciento ochenta y seis”;
- pausas y autocorrecciones.

### G. No-habla y adversarial

- silencio 3, 10 y 30 segundos;
- viento;
- tractor o motor;
- conversación de fondo;
- radio/música;
- golpe de micrófono;
- palabra aislada fuera del dominio.

## Métricas

### Exactitud

- WER mediana y p95;
- exactitud por slot crítico: acción, producto, persona, chaco, cantidad, unidad, moneda,
  precio, monto, proveedor y campaña;
- recall de productos del catálogo;
- tasa de discrepancia crítica entre Vosk y Whisper;
- repetibilidad entre tomas;
- falsas afirmaciones en muestras sin habla.

### Rendimiento

- tiempo hasta primer parcial p50/p95;
- tiempo desde fin de habla hasta texto final p50/p95;
- real-time factor por duración;
- tiempo de carga fría y caliente de cada modelo;
- RAM Java, nativa y total pico;
- CPU media/pico;
- temperatura inicial, máxima y recuperación;
- batería por 10 minutos y por sesión;
- APK/AAB y tamaño instalado;
- tiempo de instalación y primer arranque.

### Robustez

- 30 sesiones consecutivas;
- cancelación durante Vosk y Whisper;
- segundo plano, bloqueo, llamada e interrupción de audio;
- doble toque;
- poca memoria simulada;
- rotación y cambio de escala;
- proceso destruido y reapertura;
- modelo faltante, corrupto o versión incompatible.

## Evaluación híbrida

No fusionar textos por mayoría de palabras. Conservar dos resultados y sus tiempos.

- El parcial Vosk es únicamente visual.
- Whisper produce el final propuesto.
- Un comparador normaliza sólo formato superficial; nunca altera números.
- Si difieren tokens críticos, producir `criticalDisagreement` con ambas alternativas.
- El usuario elige o escribe; ningún algoritmo decide silenciosamente.

## Evidencia mínima

- JSON/CSV crudo por toma, sin audio personal versionado;
- versión/hash de app, motores y modelos;
- configuración exacta de threads, VAD y decoder;
- medición de memoria/CPU/temperatura;
- capturas de fallos de lifecycle;
- informe reproducible generado por herramienta;
- resultados separados por dispositivo;
- lista explícita `NOT_MEASURED`.

## Regla de decisión

`ADR-004` no se acepta porque C4 gane el promedio. Debe cumplir todos los guardrails críticos,
los umbrales de rendimiento y cero falsas aceptaciones de no-habla. Si Whisper small mejora
exactitud pero no latencia, considerar Vosk-only o Whisper base antes de ampliar el alcance.

