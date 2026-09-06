# EVOLUTION-3 — Plan de implementación

## Estado

`APPROVED` como secuencia. No autoriza saltar gates ni implementar toda la evolución en una
sola PR.

## Precondiciones

- EVOLUTION-2 integrada y cierre documental coherente con la evidencia aceptada.
- `main` actualizado, tests y CI verdes.
- Rama por incremento creada desde el `main` vigente.
- ADR-002 resuelto después del benchmark; ADR-003 aceptado.
- Corpus inicial aprobado y datos de voz con consentimiento/anonimización.

## Secuencia y ramas sugeridas

| Fase | Alcance | Rama sugerida | Escritura de negocio |
|---:|---|---|:--:|
| 0 | Benchmark y ADR del motor | `evolution/evolution-3-voice-benchmark` | No |
| 1 | `EVO-009` captura/transcripción/preview | `evolution/evo-009-safe-transcription` | No |
| 2 | `EVO-010` intención/resolución/drafts | `evolution/evo-010-typed-voice-drafts` | No |
| 3 | `EVO-017` compra por borrador | `evolution/evo-017-voice-purchase` | Sólo al confirmar |
| 4 | `EVO-018` aplicación planificada | `evolution/evo-018-voice-plan-application` | Sólo al confirmar |
| 5 | `EVO-019` pago de cuenta | `evolution/evo-019-voice-payment` | Sólo al confirmar |
| 6 | Piloto, métricas y cierre | rama de documentación/correcciones | Según defecto |

No iniciar la fase siguiente si la anterior tiene regresiones críticas/altas o su frontera no
está verificada.

## Fase 0 — Decisión técnica

- Crear `SpeechTranscriptionPort` mínimo y dos spikes descartables.
- Ejecutar `EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_PLAN.md`.
- Revisar licencia, mantenimiento, tamaño, Android lifecycle y modo avión.
- Actualizar `ADR-002` con decisión y evidencia.

## Fase 1 — Captura segura

- Entrada grande y visible desde Operaciones.
- Permiso contextual, estados de sesión, texto parcial/final editable.
- Cancelar/descartar y lifecycle completo.
- Fake determinista; sin clasificador ni acceso a dominio.

## Fase 2 — Interpretación tipada

- Intenciones cerradas y DTO/drafts inmutables.
- Parser de números/unidades/dinero reutilizado.
- Resolución de catálogos, aliases y desambiguación.
- Parches conversacionales y edición manual compartida.
- Validator por tipo de draft; cero repositorios de escritura.

## Fases 3 a 5 — Operaciones

Cada feature añade una pantalla/flujo de revisión y un adaptador al caso de uso existente. El
orden compra → aplicación → pago puede cambiar sólo mediante decisión documentada. Cada PR
incluye caracterización del flujo manual, paridad, atomicidad, doble toque y dispositivo.

## UI mínima

- Micrófono en menú Operaciones y acceso al formulario manual como fallback.
- Encabezado con acción detectada y estado.
- Transcripción colapsable/editable, campos estructurados y lista de faltantes.
- Candidatos seleccionables para ambigüedades.
- Botones `Seguir hablando`, `Editar`, `Descartar` y confirmación específica.
- Resumen completo desplazable en vertical/horizontal, 130 % y teclado visible.

## Gates por PR

- `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`.
- `flutter build apk --release` y CI sobre SHA final.
- Sin reducción/skip de tests previos.
- Test rojo antes de cada corrección encontrada.
- Pixel 8/API 36; prueba adicional en hardware de menor capacidad para motor/modelo.
- Modo avión, permiso denegado, llamada/interrupción, background/foreground y cancelación.
- Evidencia de cero escrituras antes de confirmación y cero efectos parciales.

## Cierre

Crear `EVOLUTION-3_FINAL_VERIFICATION.md` sólo después de completar las cinco features
aprobadas y reunir evidencia real. Debe incluir SHAs/PRs/runs, motor y versión, corpus,
métricas, dispositivos, permisos, privacidad, conteo de tests, riesgos residuales y decisión
del propietario.

