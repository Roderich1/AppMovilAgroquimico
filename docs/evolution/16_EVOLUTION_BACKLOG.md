# Backlog de evolución

Estados: `PROPOSED`, `ANALYZED`, `APPROVED`, `IN_PROGRESS`, `VERIFIED`, `DEFERRED`,
`REJECTED`.

| ID | Capability | Etapa | Estado | Pri. | Riesgo | Dependencia/nota |
|---|---|---|---|:--:|:--:|---|
| EVO-001 | Compartir backup validado | EVOLUTION-1 | DEFERRED | P2 | M | Spec analizada; no es prioridad actual |
| EVO-002 | Registrar/recordar último backup | EVOLUTION-1 | DEFERRED | P3 | L | Depende de política de recordatorio |
| EVO-003 | Diagnóstico local exportable | EVOLUTION-1 | DEFERRED | P3 | L | Redactar datos sensibles |
| EVO-004 | Modelos tipados de lectura | EVOLUTION-2 | VERIFIED | P1 | M | Diez consultas tipadas; SQL sin cambios; CI y Pixel 8 verdes |
| EVO-005 | Exportación CSV | EVOLUTION-2 | VERIFIED | P1 | M | Dart puro; propietario comprobó el resultado |
| EVO-006 | Exportación PDF | EVOLUTION-2 | VERIFIED | P1 | M | Escritor propio por ADR-001; Android y propietario verificados |
| EVO-007 | Duplicar plan como borrador | Futuro | PROPOSED | P3 | M | Nunca reactivar plan original |
| EVO-008 | Frontera única FIFO | Deuda | PROPOSED | P2 | H | Blocking sólo para nuevo consumidor FIFO |
| EVO-009 | Voz: captura/transcripción/preview | EVOLUTION-3 | APPROVED | P1 | H | Primera feature tras benchmark; no ejecuta dominio. Fase 0 en curso: banco de pruebas listo, `ADR-002` sin resolver |
| EVO-010 | Voz: intención y borradores tipados | EVOLUTION-3 | APPROVED | P1 | H | Sin escrituras; ADR-003 |
| EVO-011 | Protección/cifrado local | Futuro | PROPOSED | P3 | H | Threat model y recuperación |
| EVO-012 | Backup remoto | Futuro | DEFERRED | P4 | H | Red, proveedor e identidad |
| EVO-013 | Multi-dispositivo/sync | Futuro | DEFERRED | P4 | H | UUID, backend y conflictos |
| EVO-014 | Reapertura administrativa | Futuro | DEFERRED | P4 | H | Sólo con caso real y auditoría |
| EVO-015 | Limpieza/archivado de facturas | Futuro | PROPOSED | P3 | H | No borrar evidencia citada |
| EVO-016 | Proteger `main` y checks | Gobierno | ANALYZED | P1 | L | Recomendado antes de trabajo concurrente |
| EVO-017 | Compra mediante borrador de voz | EVOLUTION-3 | APPROVED | P1 | H | Catálogo + compra atómica; confirmación táctil |
| EVO-018 | Aplicar planificación por voz | EVOLUTION-3 | APPROVED | P1 | H | Reusar `confirmApplication()` y FIFO |
| EVO-019 | Pago de cuenta mediante voz | EVOLUTION-3 | APPROVED | P1 | H | No convertir excedente en adelanto sin decisión |
| EVO-020 | Consultas de sólo lectura por voz | Futuro | DEFERRED | P3 | H | Usar typed reads; nunca lenguaje natural a SQL |

## Orden aprobado inmediato

1. Cerrar documentalmente EVOLUTION-2 con la evidencia ya revisada por el propietario.
2. Ejecutar benchmark y aceptar/rechazar candidatos en `ADR-002`.
   **En curso.** El banco de pruebas, el corpus y las herramientas están construidos y
   verificados; falta la ejecución en teléfonos reales por parte del propietario. Ver
   `features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md` y
   `features/EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md`. Ningún `EVO-*` cambió de estado: el
   benchmark no implementa funcionalidad de producto.
3. Implementar `EVO-009` en una rama/PR propia.
4. Implementar `EVO-010` sin escrituras.
5. Implementar, cada una por separado, `EVO-017`, `EVO-018` y `EVO-019`.
6. Mantener `EVO-020` fuera de alcance hasta verificar la base.
