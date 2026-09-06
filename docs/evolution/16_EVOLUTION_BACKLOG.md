# Backlog de evolución

Estados: `PROPOSED`, `ANALYZED`, `APPROVED`, `IN_PROGRESS`, `VERIFIED`, `DEFERRED`,
`REJECTED`.

| ID | Capability | Etapa | Estado | Pri. | Riesgo | Dependencia/nota |
|---|---|---|---|:--:|:--:|---|
| EVO-001 | Compartir backup validado | EVOLUTION-1 | DEFERRED | P2 | M | Spec analizada; no es prioridad actual |
| EVO-002 | Registrar/recordar último backup | EVOLUTION-1 | DEFERRED | P3 | L | Depende de política de recordatorio |
| EVO-003 | Diagnóstico local exportable | EVOLUTION-1 | DEFERRED | P3 | L | Redactar datos sensibles |
| EVO-004 | Modelos tipados de lectura | EVOLUTION-2 | IN_PROGRESS | P1 | M | Diez consultas tipadas; SQL sin cambios; faltan CI y Pixel 8 |
| EVO-005 | Exportación CSV | EVOLUTION-2 | IN_PROGRESS | P1 | M | Dart puro, sin dependencia; faltan CI y Pixel 8 |
| EVO-006 | Exportación PDF | EVOLUTION-2 | IN_PROGRESS | P1 | M | Escritor propio por ADR-001; faltan CI y Pixel 8 |
| EVO-007 | Duplicar plan como borrador | Futuro | PROPOSED | P3 | M | Nunca reactivar plan original |
| EVO-008 | Frontera única FIFO | Deuda | PROPOSED | P2 | H | Blocking sólo para nuevo consumidor FIFO |
| EVO-009 | Voz: captura/transcripción/preview | EVOLUTION-3 | APPROVED | P2 | H | No iniciar hasta EVOLUTION-2 verificada; no ejecuta dominio |
| EVO-010 | Voz: comando confirmado | Futuro | DEFERRED | P4 | H | Fuera de EVOLUTION-3; requiere nueva aprobación |
| EVO-011 | Protección/cifrado local | Futuro | PROPOSED | P3 | H | Threat model y recuperación |
| EVO-012 | Backup remoto | Futuro | DEFERRED | P4 | H | Red, proveedor e identidad |
| EVO-013 | Multi-dispositivo/sync | Futuro | DEFERRED | P4 | H | UUID, backend y conflictos |
| EVO-014 | Reapertura administrativa | Futuro | DEFERRED | P4 | H | Sólo con caso real y auditoría |
| EVO-015 | Limpieza/archivado de facturas | Futuro | PROPOSED | P3 | H | No borrar evidencia citada |
| EVO-016 | Proteger `main` y checks | Gobierno | ANALYZED | P1 | L | Recomendado antes de trabajo concurrente |

## Orden aprobado inmediato

1. Corregir e integrar la documentación de gobierno.
2. Proteger `main` y requerir CI si la configuración disponible lo permite.
3. Crear `evolution/evolution-2-typed-reports` desde el `main` corregido.
4. Implementar `EVO-004`, después `EVO-005` y `EVO-006`.
5. Verificar e integrar EVOLUTION-2.
6. Crear una rama nueva para `EVO-009`.
7. No implementar `EVO-010`.

