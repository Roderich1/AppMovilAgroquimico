# Mapa de capacidades

Readiness: `STABLE`, `IMPROVABLE`, `APPROVED`, `DEFERRED`, `OUT`.

| Capacidad | Propósito | Clase | ID | Riesgo | Impacto arquitectónico |
|---|---|---|---|---|---|
| Catálogos y campañas | Configurar operación por periodos | STABLE | — | Medio | Bajo si conserva reglas |
| Compras multiproducto/multimoneda | Ingresar stock/costo | STABLE | — | Alto contable | Núcleo protegido |
| Inventario y FIFO | Conocer y costear existencias | STABLE | — | Crítico | Núcleo protegido |
| Aplicaciones multiproducto | Registrar consumo agrícola | STABLE | — | Crítico | Núcleo protegido |
| Planes one-shot | Preparar una aplicación | STABLE | — | Alto | Índice + transacción |
| Transferencias multiproducto | Cambiar propiedad del stock | STABLE | — | Crítico | Núcleo protegido |
| Cuentas, pagos y reversiones | Liquidar sin borrar historia | STABLE | — | Crítico | Núcleo protegido |
| Backup DB + fotos | Recuperar el conjunto operativo | STABLE | — | Alto | Servicio aislado |
| Modelos tipados de lectura | Contratos compilables para UI/reportes | APPROVED | `EVO-004` | Medio | Adopción consulta a consulta |
| Exportación CSV | Intercambio tabular exacto | APPROVED | `EVO-005` | Medio | Compositor + generador |
| Exportación PDF | Visualización, archivo e impresión | APPROVED | `EVO-006` | Medio | Compositor + generador |
| Voz: captura/transcripción/preview | Entrada continua reemplazable | APPROVED | `EVO-009` | Alto | Subsistema Voice |
| Voz: intención y drafts tipados | Interpretar sin ejecutar dominio | APPROVED | `EVO-010` | Alto | Puertos + validadores |
| Compra por voz | Preparar compra editable y atómica al confirmar | APPROVED | `EVO-017` | Muy alto | Purchase case/use boundary |
| Aplicación planificada por voz | Preparar consumo real desde plan | APPROVED | `EVO-018` | Muy alto | Application + FIFO protegido |
| Pago de cuenta por voz | Preparar pago y efecto en saldo | APPROVED | `EVO-019` | Muy alto | Accounts protegido |
| Consultas por voz | Mostrar datos mediante typed reads | DEFERRED | `EVO-020` | Alto | Reporting, sólo lectura |
| Compartir backup fuera del sandbox | Sacar copia del equipo | DEFERRED | `EVO-001` | Medio | `BackupTransport` |
| Recordar último backup | Evitar copias olvidadas | DEFERRED | `EVO-002` | Bajo | Settings/scheduler |
| Diagnóstico local exportable | Investigar fallos | DEFERRED | `EVO-003` | Bajo | Servicio pequeño |
| Protección/cifrado local | Reducir exposición física | DEFERRED | `EVO-011` | Alto | ADR + migración |
| Multi-dispositivo/sync | Compartir estado coherente | DEFERRED | `EVO-013` | Muy alto | Nuevo subsistema |
| Autenticación cloud | Identificar operadores remotos | OUT | — | Muy alto | Sólo si sync lo requiere |
| IA predictiva agrícola | Predecir consumo/decisiones | OUT | — | Muy alto | Sin requisito aprobado |

## Decisión vigente

- `EVOLUTION-2` implementa `EVO-004`, `EVO-005` y `EVO-006`.
- `EVOLUTION-3` implementa en orden `EVO-009`, `EVO-010`, `EVO-017`, `EVO-018` y `EVO-019`.
- Cada operación se entrega en una PR separada y sólo escribe tras confirmación táctil.
- `EVO-020` conserva las consultas por voz para una etapa posterior.
- `EVO-001`, `EVO-002` y `EVO-003` quedan diferidas por decisión de prioridad, no rechazadas.
