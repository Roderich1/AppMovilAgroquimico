# Backlog de evolución

Estados: `PROPOSED`, `ANALYZED`, `APPROVED`, `IN_PROGRESS`, `VERIFIED`, `DEFERRED`,
`REJECTED`. Ningún ítem está aprobado por la creación de este documento.

| ID | Capability | Type | Status | Pri. | Value | Risk | Complexity | Dependencies | Data | Arch. | Device | Notes |
|---|---|---|---|:--:|:--:|:--:|:--:|---|:--:|:--:|:--:|---|
| EVO-001 | Compartir backup validado | Feature | ANALYZED | P1 | H | M | M | BackupTransport/plugin por elegir | N | M | Sí | Recomendación inicial; archivo sin cifrar |
| EVO-002 | Registrar/recordar último backup | Feature | PROPOSED | P1 | H | L | M | EVO-001, scheduler opcional | L | L | Sí | Separar registro de notificación |
| EVO-003 | Diagnóstico local exportable | Quality | PROPOSED | P2 | M | L | L | AppLog, file transport | N | L | Sí | Redactar datos sensibles |
| EVO-004 | Modelos tipados de lectura | Debt | ANALYZED | P2 | M | M | Feature consumidora | N | M | No | Consulta a consulta |
| EVO-005 | Exportación CSV de reportes | Feature | PROPOSED | P2 | H | M | EVO-004, destino de archivo | N | M | Sí | Totales exactos y locale |
| EVO-006 | Exportación PDF | Feature | PROPOSED | P3 | M | M | Reportes tipados | N | M | Sí | Sólo si CSV no cubre necesidad |
| EVO-007 | Duplicar plan como nuevo borrador | Feature | PROPOSED | P2 | M | M | Plan one-shot | N/L | L | Sí | Nunca reactivar plan original |
| EVO-008 | Frontera única de operaciones FIFO | Debt | PROPOSED | P2 | M | H | M | Nueva operación de stock | N | M | No | Blocking para nuevo consumidor FIFO |
| EVO-009 | Voz: captura/transcripción/preview | Feature | PROPOSED | P2 | H | H | Decisiones voz y Audio/Transcriber | N/L | H | Sí | No ejecuta operaciones |
| EVO-010 | Voz: comando confirmado | Feature | PROPOSED | P3 | H | H | EVO-009 + casos de uso tipados | L | H | Sí | No autoejecución |
| EVO-011 | Protección/cifrado local | Security | PROPOSED | P3 | M | H | Threat model/recuperación | H | H | Sí | No asumir biometría = cifrado |
| EVO-012 | Backup remoto | Feature | DEFERRED | P3 | H | H | red, proveedor, identidad | M/H | H | Sí | Puede preceder a sync total |
| EVO-013 | Multi-dispositivo/sync | Architecture | DEFERRED | P4 | H | H | UUID, backend, conflictos | H | H | Sí | Nuevo subsistema |
| EVO-014 | Reapertura administrativa | Feature | DEFERRED | P4 | L | H | auditoría contable | M | M | Sí | Sólo si existe caso real |
| EVO-015 | Limpieza/archivado de facturas | Feature | PROPOSED | P3 | M | H | backup/ref integrity | M | M | Sí | No borrar evidencia citada |
| EVO-016 | Proteger `main` y checks | Release | ANALYZED | P1 | H | L | configuración GitHub | N | N | No | API reporta `protected=false` |

## Orden recomendado inmediato

1. Aprobar o rechazar `EVO-016` como control de integración.
2. Decidir si `EVO-001` será la primera feature.
3. Especificar `EVO-001`; introducir `EVO-004` sólo en sus lecturas si lo necesita.
4. Antes de voz, cerrar las decisiones listadas en la spec correspondiente.

Priorización no equivale a autorización.
