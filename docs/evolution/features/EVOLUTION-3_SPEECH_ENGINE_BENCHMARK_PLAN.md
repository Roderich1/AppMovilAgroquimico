# EVOLUTION-3 — Plan de selección y benchmark del motor de voz

## Estado

Obligatorio antes de fijar una dependencia de producción. La arquitectura usa
`SpeechTranscriptionPort`; el proveedor se decide con evidencia, no por preferencia.

## Candidatos mínimos

1. Reconocimiento en dispositivo ofrecido por Android cuando esté disponible.
2. `whisper.cpp` con modelos multilingües `tiny` y `base`, incluyendo variantes cuantizadas
   compatibles.

No se aprueba un servicio remoto en este benchmark. Si ningún candidato local cumple, se
detiene la implementación y se abre un ADR específico para remoto.

## Entornos

- Pixel 8 / Android 16 API 36, referencia de regresión.
- Al menos un Android de gama media/baja acorde al usuario real.
- Modo avión y condiciones normales.
- Sesiones cortas y dictado continuo de compras con varias líneas.

## Corpus

Mínimo 100 muestras anonimizadas o sintéticas representativas, separadas de tests de ajuste:

- las tres intenciones;
- productos y alias reales autorizados;
- nombres de personas, proveedores y chacos ficticios/anonimizados;
- cantidades, unidades, BOB/USD, precios y fechas;
- ruido de campo, pausas, correcciones y acentos de usuarios objetivo.

No conservar voz de una persona real sin consentimiento y política de eliminación.

## Métricas

| Métrica | Cómo se evalúa |
|---|---|
| Exactitud de intención | intención correcta / muestras |
| Exactitud de slots críticos | persona/producto/cantidad/unidad/precio/moneda/plan exactos |
| Draft completo | porcentaje listo sin tecleo, sin ocultar ambigüedades |
| Falsa aceptación | draft marcado listo con dato crítico incorrecto |
| Latencia parcial/final | p50/p95 desde audio a actualización/final |
| Memoria pico | captura + modelo + interpretación |
| Tamaño APK/modelo | bytes instalados y descargados |
| CPU/batería/temperatura | sesión sostenida definida |
| Offline | resultado en modo avión |
| Lifecycle | pausa/interrupción/liberación de micrófono |

## Umbrales de decisión

Antes del piloto se fijan números con producto. Como guardrail, falsa aceptación crítica debe
ser `0` en el corpus de aceptación: un dato dudoso debe quedar bloqueado, no adivinado. Metas
provisionales de UX para medir, no promesas: actualización del draft en menos de 200 ms después
de recibir texto parcial y resultado final visible en menos de 2 s p95 tras detener el habla en
Pixel 8.

## Procedimiento

1. Implementar adaptadores spike fuera del flujo de escritura.
2. Ejecutar el mismo corpus y protocolo en todos los candidatos.
3. Registrar versiones, modelo, cuantización, dispositivo, temperatura y configuración.
4. Comparar precisión crítica antes que velocidad/tamaño.
5. Elegir en `ADR-002` o documentar que ninguno cumple.
6. Eliminar dependencias/modelos del candidato descartado antes de la PR de producto.

## Evidencia requerida

CSV/JSON de resultados sin audio sensible, resumen reproducible, SHA, comandos, licencias,
impacto en APK, comportamiento offline y recomendación. Los números no se incorporan a este
documento hasta haber sido medidos.

