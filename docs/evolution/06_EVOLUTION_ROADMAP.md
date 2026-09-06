# Roadmap de evolución

No contiene fechas inventadas. El orden reduce primero riesgo operativo y crea seams antes de
subsystems más complejos.

## EVOLUTION-0 — Gobierno y contrato

- Objetivo: establecer este paquete, IDs, backlog, DoD y plantillas.
- Valor: cada feature inicia con alcance verificable.
- Riesgo/datos: bajo/ninguno.
- Salida: documentos consistentes, ninguna feature marcada aprobada.

## EVOLUTION-1 — Portabilidad y diagnóstico

- Candidatas: compartir/exportar `.agrobackup`, registrar última copia, exportar diagnóstico.
- Valor: el usuario puede sacar la única copia completa antes de perder/desinstalar el equipo.
- Dependencias: frontera `BackupTransport`; selección tecnológica posterior.
- Riesgo: plugins Android, exposición de archivo sin cifrar.
- Datos: sin schema si sólo comparte; `app_settings` si registra fecha.
- Tests: servicio, fallos, archivo incompleto, Android/device, recuperación.
- Salida: backup compartido y revalidado; baseline compatible.

## EVOLUTION-2 — Lecturas/exportación operativa

- Candidatas: modelos tipados para inventario/reportes, CSV y luego PDF si aporta valor.
- Valor: información utilizable fuera de la app y seam seguro para nuevas interfaces.
- Riesgo: semántica de saldos/columnas y archivos grandes.
- Datos: normalmente ninguno; consultas e índices sólo con evidencia.
- Salida: totales equivalentes a UI/DB y exportaciones verificadas.

## EVOLUTION-3 — Voz segura

- Fase A: capturar → transcribir → mostrar intención, sin ejecutar.
- Fase B: convertir a comando tipado y pedir confirmación explícita.
- Fase C: ejecutar mediante casos de uso existentes y guardar auditoría.
- Dependencias: decisión local/cloud, idioma, conectividad, privacidad y costos.
- Riesgo: reconocimiento incorrecto de producto/persona/cantidad; muy alto en escritura.
- Salida: ninguna operación silenciosa; offline degradable; escenarios adversos aprobados.

## EVOLUTION-4 — Capacidades distribuidas, sólo si se aprueban

- Sync/multi-dispositivo, identidad/autenticación, backup remoto.
- Precondiciones: ADR, modelo de amenazas, UUID, versionado de registros, conflictos,
  observabilidad y plan de migración/rollback.
- No debe empezar como «subir el SQLite» ni compartir un archivo entre escritores.

## Priorización común

Puntuar valor, riesgo, complejidad, dependencias, impacto en datos/arquitectura/UX y
reversibilidad. Una feature de alto riesgo puede ir antes sólo si reduce un riesgo mayor y
tiene un corte seguro.

## Recomendación

Primera candidata: `EVO-001`, compartir un backup validado fuera del sandbox. Es visible,
acotada, no altera contabilidad ni schema y reduce la limitación operativa más importante. La
voz debería seguir después de crear su spec y resolver decisiones de privacidad/operación.
