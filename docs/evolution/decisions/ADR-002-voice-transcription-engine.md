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

La Fase 0 construyó el banco de pruebas, el corpus y las herramientas de análisis, y midió
todo lo que puede medirse sin un teléfono. Falta la evidencia de dispositivo, que ejecutará el
propietario. Detalle completo en `features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md`.

### Hechos ya establecidos

Sobre el Candidato A (reconocimiento de Android), tomados de lo que declara el propio stack de
Google y por lo tanto independientes del aparato de prueba:

1. **`es-BO` no existe como idioma on-device.** Los únicos españoles ofrecidos son `es-ES` y
   `es-US`. El fallback de locale que `EVO-009` preveía como excepción es el camino normal, y
   la interfaz debe declararlo siempre.
2. **El reconocimiento on-device exige descargar antes el modelo del idioma.** Una instalación
   nueva no tiene ninguno (`installedOnDeviceLanguages` vacío). Sin esa descarga, transcribir
   necesita red. Esto contradice la lectura ingenua de "on-device = offline" y es una decisión
   de producto, no técnica.

Sobre el Candidato B (`whisper.cpp`, commit `52a939a2a762…`):

3. **No produce resultados parciales.** Transcribe una grabación completa. La experiencia de
   "transcribe mientras escucha" descrita en la visión no aplica con esta integración.
4. **Impacto medido en el APK**: +41.063.516 B con `tiny-q5_1`, +68.618.468 B con `base-q5_1`,
   sobre un APK de producción que hoy pesa 64.027.725 B.
5. **Inventa texto sobre silencio**: devolvió `[Música]` sin habla. Refuerza que la frontera
   tipada de `ADR-003` es obligatoria y que recibir texto nunca equivale a un dato válido.
6. **No requiere wrapper de terceros.** El puente JNI es código de este repositorio, con
   whisper.cpp compilado desde un commit fijado. El escape hatch es borrar `benchmark/`.

### Lo que sigue sin medirse

Exactitud de transcripción y de datos críticos, latencias p50/p95, memoria, CPU, batería,
temperatura y comportamiento real en modo avión. Ninguna es obtenible sin teléfonos: el único
aparato disponible fue un emulador x86_64 cuyo servicio de reconocimiento además muere al
iniciar (`DeadObjectException`, `ERROR_CLIENT`).

La exactitud de intención, la completitud del borrador y la falsa aceptación no pertenecen a
esta fase: se definen sobre el borrador tipado de `EVO-010`, que no existe todavía. Medirlas
sobre texto crudo daría un número falso.

## Evidencia para pasar a Accepted

Adjuntar resultados reproducibles del plan de benchmark, versiones, dispositivos, corpus,
licencia, impacto del APK y razones para descartar las alternativas.

Concretamente, y sin excepciones:

- resultados del **Pixel 8 / API 36** y de un **Android de gama media o baja**;
- comportamiento verificado **en modo avión** del motor ganador, o aceptación explícita y
  escrita del propietario de que no funciona sin red;
- locale realmente utilizado y qué ocurre con `es-BO`;
- impacto en el tamaño de distribución aceptado por el propietario;
- ausencia de errores sistemáticos en datos críticos.

Si falta cualquiera de estos puntos, este ADR sigue `Proposed`. No se elige un motor
provisional.

