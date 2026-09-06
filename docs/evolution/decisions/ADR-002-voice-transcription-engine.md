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

## Evidencia para pasar a Accepted

Adjuntar resultados reproducibles del plan de benchmark, versiones, dispositivos, corpus,
licencia, impacto del APK y razones para descartar las alternativas.

