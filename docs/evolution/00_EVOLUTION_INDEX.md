# Agrocuentas — Índice de evolución

## Propósito

`docs/evolution/` gobierna las capacidades incorporadas después de la baseline congelada
`v1.0.0-base-stable`. No reemplaza `docs/00_INDEX.md` ni reescribe evidencia histórica.

## Identidad de estado

| Elemento | Valor |
|---|---|
| Baseline funcional inmutable | `f4c6510438991f4948fda921eec7c67fe2a2acc2` |
| Tag | `v1.0.0-base-stable` |
| `main` analizado para este paquete | `2fd0ccbd7f06e5384eaf84a625e7ee8249c9add5` |
| `main` vigente | `ff38c48a2b26b2c9a147b689fc4eeca1a9ec76e0` (merge del PR #7: banco de pruebas de la Fase 0) |
| Evolución integrada | EVOLUTION-2 mediante PR #5 |

## Dos niveles de identificadores

- `EVOLUTION-N`: etapa del roadmap que agrupa capacidades relacionadas.
- `EVO-NNN`: ítem único y estable del backlog.

No son intercambiables. `EVOLUTION-2` agrupa `EVO-004`, `EVO-005` y `EVO-006`.
`EVOLUTION-3` agrupa `EVO-009`, `EVO-010`, `EVO-017`, `EVO-018` y `EVO-019`.
`EVO-003` ya identifica diagnóstico local exportable y no debe reutilizarse para voz.

## Orden de lectura

1. `01_EVOLUTION_VISION.md`
2. `02_CURRENT_BASELINE.md`
3. `03_EVOLUTION_PRINCIPLES.md`
4. `04_TARGET_ARCHITECTURE.md`
5. `05_CAPABILITY_MAP.md`
6. `06_EVOLUTION_ROADMAP.md`
7. Estrategias `07` a `12`
8. Gobierno `13` a `18`
9. Specs y planes en `features/`
10. Plantillas en `templates/`
11. ADR aceptados en `decisions/`

## Registro de features

| Alcance | IDs | Documento | Estado |
|---|---|---|---|
| Compartir backup | `EVO-001` | `features/EVO-001_SHARE_BACKUP_SPEC.md` | `DEFERRED` |
| Typed reads + reportes | `EVO-004/005/006` | `features/EVOLUTION-2_TYPED_READS_AND_REPORT_EXPORT_SPEC.md` | `VERIFIED` |
| Plan de EVOLUTION-2 | `EVO-004/005/006` | `features/EVOLUTION-2_IMPLEMENTATION_PLAN.md` | Ejecutado |
| Trazabilidad de EVOLUTION-2 | `EVO-004/005/006` | `features/EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md` | Evidencia de implementación |
| Cierre de EVOLUTION-2 | `EVO-004/005/006` | `features/EVOLUTION-2_FINAL_VERIFICATION.md` | `VERIFIED` |
| Visión de EVOLUTION-3 | `EVO-009/010/017/018/019` | `features/EVOLUTION-3_VOICE_VISION_AND_SCOPE.md` | `APPROVED` |
| Captura/transcripción | `EVO-009` | `features/EVO-009_SAFE_VOICE_SPEC.md` | `APPROVED` |
| Interpretación tipada | `EVO-010` | `features/EVO-010_TYPED_VOICE_INTERPRETATION_SPEC.md` | `APPROVED` |
| Compra por voz | `EVO-017` | `features/EVO-017_VOICE_PURCHASE_DRAFT_SPEC.md` | `APPROVED` |
| Aplicar planificación por voz | `EVO-018` | `features/EVO-018_VOICE_PLAN_APPLICATION_DRAFT_SPEC.md` | `APPROVED` |
| Pago por voz | `EVO-019` | `features/EVO-019_VOICE_PAYMENT_DRAFT_SPEC.md` | `APPROVED` |
| Consultas por voz | `EVO-020` | `features/EVO-020_VOICE_READ_QUERIES_SPEC.md` | `DEFERRED` |
| Plan y trazabilidad | `EVOLUTION-3` | `features/EVOLUTION-3_IMPLEMENTATION_PLAN.md` y `features/EVOLUTION-3_TRACEABILITY_MATRIX.md` | `APPROVED` |
| Resultados del benchmark | `EVOLUTION-3` Fase 0 | `features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md` | `DECIDED` |
| Pruebas en teléfonos | `EVOLUTION-3` Fase 0 | `features/EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md` | Ejecutado en API 31; vigente como regresión |
| Devolución de esas pruebas | `EVOLUTION-3` Fase 0 | `features/EVOLUTION-3_OWNER_DEVICE_TEST_RESULTS_TEMPLATE.md` | Plantilla |
| Motor híbrido local | `EVOLUTION-3` Fase 0-bis | `decisions/ADR-004-hybrid-embedded-voice-engine.md` | `Proposed` |
| Benchmark del híbrido | `EVOLUTION-3` Fase 0-bis | `features/EVOLUTION-3_HYBRID_ENGINE_BENCHMARK_PLAN.md` | `PROPOSED` |
| Distribución y seguridad de modelos | `EVOLUTION-3` Fase 0-bis | `features/EVOLUTION-3_MODEL_DISTRIBUTION_SECURITY_SPEC.md` | `PROPOSED` |
| Aceptación del híbrido | `EVOLUTION-3` Fase 0-bis | `features/EVOLUTION-3_HYBRID_ACCEPTANCE_MATRIX.md` | `PENDING` (sin medir) |
| Migración de `EVO-009` al híbrido | `EVO-009` | `features/EVO-009_HYBRID_ENGINE_MIGRATION_PLAN.md` | `PROPOSED`, condicionado a `ADR-004` |

Los documentos `FINAL_VERIFICATION` sólo se crean después de implementar y reunir evidencia
real de tests, CI y dispositivo. Su ausencia antes de esa fase es correcta.

`EVOLUTION-2` fue fusionada mediante PR #5, sus gates están verdes, el gate Pixel 8 corrigió
tres defectos y el propietario comprobó CSV/PDF. El cierre está en
`features/EVOLUTION-2_FINAL_VERIFICATION.md`.

## Precedencia

Ante contradicciones: código de la rama analizada → tests → `docs/46_BASELINE_FINAL_FREEZE.md`
→ documentación final de evolución → documentación funcional → documentación histórica.

## Decisión vigente del propietario

1. EVOLUTION-2 fue revisada y aceptada por el propietario; mantener su cierre documental
   coherente con la evidencia real.
2. Implementar EVOLUTION-3 por PRs: benchmark, `EVO-009`, `EVO-010`, `EVO-017`, `EVO-018` y
   `EVO-019`.
3. Voz sólo prepara drafts; compra, aplicación y pago requieren confirmación táctil.
4. `EVO-020`, consultas por voz, permanece `DEFERRED` hasta cerrar la base transaccional.
5. La Fase 0 de EVOLUTION-3 está **cerrada**: el propietario ejecutó el corpus de ajuste con
   los tres motores en un POCO X5 Pro 5G (Android 12 / API 31) y `ADR-002` quedó **`Accepted`**
   con Android `SpeechRecognizer` como motor productivo; Whisper es reserva no distribuida. El
   gate Pixel 8 / API 36 quedó `WAIVED_BY_OWNER` (`RISK-028`) y **no se afirma que API 36 haya
   sido probado**. El banco vive en `benchmark/voice_benchmark`, no forma parte de la
   aplicación y se borra eliminando esa carpeta.
6. `EVO-009` está **`IN_PROGRESS`** en la PR #8, abierta y sin fusionar.
7. **Fase 0-bis, abierta.** El gate físico en un HONOR JDY-LX3P (Android 16 / API 36) encontró
   que ese aparato no tiene **ningún** modelo de español para reconocimiento —ni en el
   reconocedor local ni en el servicio del sistema— y que no existe una ruta exportada para
   instalarlo desde la aplicación. Eso cumple el primer disparador de reconsideración de
   `ADR-002`. Se evalúa una canalización local propia (Vosk para parciales, Whisper small para
   el final) en `ADR-004`, que permanece **`Proposed`**. `ADR-002` sigue `Accepted` y su
   evidencia no se toca: sólo queda **bajo revisión**. `EVO-010` no ha comenzado.
