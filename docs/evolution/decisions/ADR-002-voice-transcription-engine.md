# ADR-002 — Motor de transcripción por voz

- Estado: `Proposed`.
- Fecha: 2026-09-06.
- Decisor: propietario del producto con evidencia técnica.

## Contexto

EVOLUTION-3 requiere español, nombres propios/productos, dictado continuo y respuesta rápida
en Android. La app es offline-first y el audio puede contener información financiera y
personal. Fijar Whisper o un servicio antes de medir precisión, memoria y latencia introduciría
un riesgo innecesario.

## Decisión ya aceptada

El dominio dependerá de `SpeechTranscriptionPort`, no de una API concreta. El adaptador emite
resultados parciales/finales y estados explícitos de permiso, disponibilidad, error y fin. No
conoce repositorios ni persiste audio.

## Decisión pendiente

Elegir, mediante el benchmark documentado, entre:

1. reconocimiento on-device disponible en Android;
2. `whisper.cpp` con modelo multilingüe tiny/base y cuantización viable;
3. declarar que ninguno cumple y abrir otro ADR antes de considerar procesamiento remoto.

## Criterios

Exactitud en slots críticos, falsa aceptación, español/nombres locales, latencia p95, memoria,
tamaño, batería, compatibilidad Android, modo avión, licencia, mantenimiento y facilidad de
reemplazo.

## Consecuencias

- No añadir aún una dependencia/modelo Whisper al producto.
- Los tests de UI/interpretación usan fake determinista.
- El APK no contiene dos motores después de seleccionar.
- Una opción remota requerirá consentimiento y ADR adicional; no es fallback silencioso.

## Estado del benchmark (2026-09-06)

La Fase 0 construyó el banco de pruebas y el corpus, y el propietario ejecutó el corpus de
ajuste completo con los tres motores en un **POCO X5 Pro 5G (Android 12 / API 31)**, en modo
avión verificado contra `Settings.Global.AIRPLANE_MODE_ON`. Detalle completo en
`features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md`.

**El gate del Pixel 8 / API 36 sigue pendiente.**

### Hechos medidos en teléfono real

| Criterio | Android | Whisper tiny | Whisper base |
|---|--:|--:|--:|
| Datos críticos correctos | **81,1 %** | 57,6 % | 66,3 % |
| WER mediana | **0,167** | 0,385 | 0,300 |
| Afirma texto sobre silencio | **No** | **Sí** (`[MÚSICA]`) | `NOT_MEASURED` |
| Memoria pico | **158 MiB** | 276 MiB | 328 MiB |
| Peso añadido al APK | **0 B** | +41.063.516 B | +68.618.468 B |
| Resultados parciales | **Sí**, ~1,7 s | No | No |
| Latencia tras detener p50 | **17 ms** | 1228 ms | 2944 ms |

1. **`es-BO` no existe**: error 12 `LANGUAGE_NOT_SUPPORTED`. `es-ES` da error 13
   `LANGUAGE_UNAVAILABLE` — existe pero no estaba instalado. Sólo funcionó `es-US`, el único
   paquete presente. La aplicación debe usar el idioma que haya y **no puede prometer español
   boliviano**.
2. **El modo offline del Candidato A funciona**, vía **SODA**, el reconocedor local de Google.
   Confirmado en `logcat` con las radios apagadas.
3. **`isOnDeviceRecognitionAvailable()` devuelve `false` en ese mismo aparato.** La API no
   sirve como garantía de offline; hay que intentar la transcripción y observar el resultado.
4. **Ningún motor reconoce los nombres de producto** — 5/17 el mejor. Paraquat, Mancozeb,
   Lambdacialotrina, Germi-100 y Expansive fallan en los tres. Es trabajo de `EVO-010` contra
   la base local, no del motor.
5. **Whisper comete errores numéricos que Android no comete**: «dos mil setecientos» dio
   `2017, 100` en tiny y `17,200` en base.
6. **Repetibilidad baja**: las mismas 40 frases dictadas dos veces coincidieron sólo en el
   33,3 %, y una cantidad cambió entre tomas (`doce` leído como `12` y como `dos`).
7. **No requiere wrapper de terceros.** El puente JNI es código de este repositorio, con
   whisper.cpp compilado desde un commit fijado. El escape hatch es borrar `benchmark/`.

### Recomendación técnica

**Candidato A como motor primario**, por no inventar sobre silencio, por acertar más en datos
críticos y por no costar nada en distribución. **Whisper queda como reserva**, no descartado:
es el único que no depende de Google y el único que garantiza offline sin paquete previo.

Ninguno alcanza el listón de `EVO-009` por sí solo: la transcripción cruda no puede precargar
un borrador de compra, y la frontera de confirmación de `ADR-003` pasa de precaución a
mecanismo necesario.

### Lo que sigue sin medirse

CPU y batería atribuidas al motor, temperatura bajo carga sostenida, silencio en Whisper base,
lifecycle e interrupciones en dispositivo, y el **Pixel 8 / API 36**. El corpus de aceptación
sigue intacto a propósito.

La exactitud de intención, la completitud del borrador y la falsa aceptación no pertenecen a
esta fase: se definen sobre el borrador tipado de `EVO-010`, que no existe todavía. Medirlas
sobre texto crudo daría un número falso.

## Evidencia para pasar a Accepted

| Requisito | Estado |
|---|---|
| Android de gama media o baja | **Cumplido** — POCO X5 Pro, API 31 |
| **Pixel 8 / API 36** | **Pendiente** |
| Comportamiento verificado en modo avión | **Cumplido** — verificado contra el sistema, no declarado |
| Locale realmente utilizado y qué pasa con `es-BO` | **Cumplido** — sólo `es-US`; `es-BO` no existe |
| Impacto en el tamaño de distribución aceptado por el propietario | **Pendiente** — decisión suya |
| Ausencia de errores sistemáticos en datos críticos | **No cumplido** — los nombres de producto fallan sistemáticamente en los tres motores |

Mientras falte cualquiera de estos puntos, este ADR sigue `Proposed`. No se elige un motor
provisional.

El último punto merece una lectura precisa: **no bloquea la elección de motor**, porque ningún
motor lo resuelve. Bloquea la idea de que la transcripción alcance para precargar datos. La
decisión de `ADR-002` puede tomarse aceptando explícitamente que el reconocimiento de productos
y personas se resuelve en `EVO-010`.
