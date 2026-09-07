# EVO-009 — Plan de migración hacia motor híbrido

## Principio

No desechar la implementación actual. La PR #8 ya aporta UI, permiso, lifecycle, continuidad,
edición, estados, guardas y `SpeechTranscriptionPort`. El giro debe sustituir la infraestructura
de transcripción sin mezclar `EVO-010` ni escrituras de negocio.

## Estado inicial

- PR #8 abierta y sin fusionar.
- `EVO-009` `IN_PROGRESS`.
- Android `SpeechRecognizer` implementado.
- Fallo reproducido en HONOR API 36 por ausencia de modelos españoles del sistema.
- `ADR-004` todavía `Proposed`.

## Secuencia recomendada

### Fase P0 — Congelar evidencia

- Registrar DEFECTO-004/005 y logs del HONOR.
- No borrar los tests ni el adaptador Android.
- Etiquetar o guardar el SHA estable previo al giro.
- Actualizar PR #8 indicando que la elección de motor está en revisión.

### Fase P1 — Benchmark aislado

- Crear `evolution/evolution-3-hybrid-voice-benchmark` desde el `origin/main` vigente, no desde
  la rama de PR #8.
- Abrir una PR documental/benchmark separada contra `main`; PR #8 permanece congelada.
- Extender el banco de Fase 0, no la app productiva.
- Integrar Vosk small español y Whisper small-q5_1 en sabores separados.
- Añadir el candidato híbrido con una única captura.
- Ejecutar corpus en POCO API 31 y HONOR API 36.
- Mantener `ADR-004 Proposed`.

### Fase P2 — Decisión del propietario

- Comparar contra Android, Whisper base y umbrales predefinidos.
- Elegir híbrido, Vosk-only, Whisper-only o conservar Android con fallback.
- Aceptar/rechazar `ADR-004` explícitamente.
- No modificar retrospectivamente resultados de `ADR-002`.

### Fase P3 — Integración en EVO-009

Sólo si `ADR-004` es aceptado:

- fusionar primero la PR del benchmark/ADR y actualizar o rebasar limpiamente la rama de PR #8;
- conservar `SpeechTranscriptionPort` como frontera;
- introducir un capturador PCM nativo único;
- implementar estados `loadingModels`, `streamingPartial`, `finalizing`,
  `modelUnavailable`, `modelCorrupt`, `thermalLimited` si la evidencia los exige;
- adaptar la composición para que parciales no sobrescriban texto manual;
- añadir cancelación real de la inferencia final;
- conservar Android como adaptador opcional o retirar su selección automática según ADR.

### Fase P4 — Distribución

- implementar únicamente la alternativa aceptada por la spec de distribución;
- verificar hashes, licencias, instalación atómica y rollback;
- producir APK/AAB y tamaño instalado real.

### Fase P5 — Verificación física

- repetir los 26 puntos existentes;
- añadir carga fría/caliente, 30 sesiones, temperatura, batería, modelo corrupto y modo avión;
- verificar POCO API 31 y HONOR API 36;
- mantener PR sin fusionar hasta revisión del propietario y CI final.

## Contrato recomendado

El puerto no debe exponer clases de Vosk o Whisper. Conceptualmente debe poder emitir:

```text
VoiceEvent.sessionStarted
VoiceEvent.partial(text, engine, sequence)
VoiceEvent.finalCandidate(text, engine, timing, qualityFlags)
VoiceEvent.noSpeech(engine)
VoiceEvent.modelStatus(engine, version, state)
VoiceEvent.error(code, recoverable)
VoiceEvent.sessionEnded(reason)
```

`qualityFlags` puede informar `criticalDisagreement`, `possibleHallucination`, `lowSpeechRatio`
o `truncated`; nunca debe convertir texto en una compra/pago/aplicación.

## Tests obligatorios antes de producción

- contrato común de motores;
- una sola captura de audio;
- orden y deduplicación de eventos;
- callback tardío de sesión anterior ignorado;
- cancelación durante finalización;
- liberación nativa idempotente;
- Vosk parcial + Whisper final;
- discrepancia de número marcada;
- silencio no agregado;
- ruido no agregado;
- edición manual preservada;
- OOM/fallo nativo simulado;
- modelo faltante/corrupto;
- límite de duración/buffer;
- segundo plano/llamada/bloqueo;
- guardas de cero SQL, repositorios, red y disco de audio.

## Rollback

- Mantener el adaptador Android compilable hasta verificar el reemplazo.
- Feature flag sólo de desarrollo para elegir candidato durante benchmark.
- El producto no distribuye dos caminos sin política explícita.
- Si el híbrido falla, volver al último SHA de EVO-009 funcional sin migración de datos.

## Definition of Done

- ADR aceptado con evidencia de ambos dispositivos;
- motores/modelos reproducibles y licenciados;
- umbrales críticos cumplidos;
- tests y CI verdes;
- pruebas físicas completas;
- documentación y riesgos actualizados;
- cero escritura de negocio y cero audio persistido;
- aprobación explícita del propietario.
