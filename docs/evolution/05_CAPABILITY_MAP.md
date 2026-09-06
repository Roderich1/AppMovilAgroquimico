# Mapa de capacidades

Readiness: `STABLE`, `IMPROVABLE`, `PROPOSED`, `OUT`.

| Capacidad | Propósito | Clase | Datos/dependencias | Riesgo | Impacto arquitectónico |
|---|---|---|---|---|---|
| Catálogos y campañas | Configurar operación por periodos | STABLE | SQLite, constraints | Medio | Bajo si se conservan reglas |
| Compras multiproducto/multimoneda | Ingresar stock/costo | STABLE | dinero, lotes, fotos | Alto contable | Núcleo protegido |
| Inventario y FIFO | Conocer y costear existencias | STABLE | lotes/movimientos | Crítico | Núcleo protegido |
| Aplicaciones multiproducto | Registrar consumo agrícola | STABLE | inventario/cuentas | Crítico | Núcleo protegido |
| Planes one-shot | Preparar una aplicación | STABLE | schema v6 | Alto | Índice + transacción |
| Transferencias multiproducto | Cambiar propiedad del stock | STABLE | FIFO/lotes | Crítico | Núcleo protegido |
| Cuentas, pagos y reversiones | Liquidar sin borrar historia | STABLE | asientos inmutables | Crítico | Núcleo protegido |
| Backup DB + fotos | Recuperar el conjunto operativo | STABLE | filesystem, ZIP, SHA-256 | Alto | Servicio aislado |
| Lecturas tipadas | Hacer contratos compilables | IMPROVABLE | queries/UI | Medio acumulativo | Adopción consulta a consulta |
| Repositorios por capacidad | Reducir acoplamiento | IMPROVABLE | `AgroRepository` | Medio | Extracción oportunista |
| Diagnóstico local exportable | Investigar fallos | PROPOSED | `AppLog`, archivos | Bajo | Servicio pequeño |
| Compartir backup fuera del sandbox | Sacar una copia del equipo | PROPOSED | share/document picker | Medio nativo | `BackupTransport` |
| Informes CSV/PDF | Usar resultados externamente | PROPOSED | reporting/files | Medio | Query models + exporter |
| Duplicar plan aplicado | Repetir intención sin reabrirla | PROPOSED | planes | Bajo-medio | Caso de uso sin reabrir plan |
| Recordatorios locales | Evitar olvidos operativos | PROPOSED | planes/backup, permisos | Medio nativo | Scheduler aislado |
| Voz: captura y vista previa | Reducir tecleo en campo | PROPOSED | micrófono/transcriptor | Alto | Subsistema Voice |
| Voz: ejecutar comandos | Registrar desde intención hablada | PROPOSED | intents + casos de uso | Muy alto | Confirmación y auditoría |
| Cifrado/bloqueo local | Reducir exposición física | PROPOSED | DB/backup/biometría | Alto | ADR + migración/recuperación |
| Multi-dispositivo/sync | Compartir estado coherente | PROPOSED | UUID, backend, conflictos | Muy alto | Nuevo subsistema |
| Autenticación cloud | Identificar operadores remotos | OUT por ahora | backend/identidad | Muy alto | Sólo si sync lo requiere |
| IA predictiva agrícola | Predecir decisiones/consumo | OUT por ahora | datos/modelo/cloud | Muy alto | Sin requisito aprobado |

## Confirmado frente a recomendado

- Confirmado: preservar y evolucionar la aplicación estable; la voz es una dirección futura
  mencionada por el propietario, pero su modo de operación aún no está aprobado.
- Recomendado: compartir el backup fuera de la carpeta de la app como primera evolución de
  producto, por valor de recuperación y cambio acotado.
- Ideas futuras: sync, cifrado, autenticación e IA predictiva. Permanecen fuera de alcance.

## Criterio de promoción

Una capacidad pasa de `PROPOSED` a `ANALYZED` al tener problema, flujos, non-scope, riesgos y
criterios; a `APPROVED` sólo por decisión explícita del propietario.
