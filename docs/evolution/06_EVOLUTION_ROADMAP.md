# Roadmap de evolución

El orden vigente proviene de una decisión explícita del propietario. No contiene fechas
inventadas y ninguna etapa se considera implementada por existir su documentación.

## EVOLUTION-0 — Gobierno y contrato

- Estado: `VERIFIED` documental.
- Resultado: paquete de evolución, IDs, backlog, DoD y plantillas.
- No añadió funcionalidad de producción.

## EVOLUTION-1 — Portabilidad y diagnóstico

- IDs: `EVO-001`, `EVO-002`, `EVO-003`.
- Estado: `DEFERRED`.
- Incluye compartir `.agrobackup`, recordar última copia y exportar diagnóstico.
- Puede retomarse después mediante decisión explícita.

## EVOLUTION-2 — Lecturas tipadas y exportación de reportes

- IDs: `EVO-004`, `EVO-005`, `EVO-006`.
- Estado: `IN_PROGRESS` en `evolution/evolution-2-typed-reports`. Los siete puntos del orden
  interno están implementados y el CI del SHA final está en verde; falta la verificación en
  Pixel 8. Detalle y gate pendiente en
  `features/EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md`.
- Orden interno:
  1. typed read models y mappers incrementales;
  2. migración de consumidores necesarios;
  3. compositor neutral de reportes;
  4. CSV;
  5. PDF;
  6. almacenamiento y UX;
  7. CI y Pixel 8.
- Datos: no debe requerir cambio de schema salvo hallazgo independiente y justificado.
- Salida: resultados equivalentes a UI/DB, exportaciones offline y trazabilidad completa.
- No incluye compartir archivos, voz, cloud, sync ni refactor masivo.

## EVOLUTION-3 — Voz segura

- ID: `EVO-009`.
- Estado: `APPROVED`, bloqueada hasta que EVOLUTION-2 esté integrada y verificada.
- Único alcance:

```text
Micrófono → transcripción → vista previa editable → aceptar/editar/descartar
```

- Aceptar confirma el texto de sesión, no una operación agrícola o contable.
- No escribe SQLite, no llama casos de uso y no ejecuta compras, pagos, transferencias,
  aplicaciones, reversiones ni cierres.
- Requiere decisión técnica documentada sobre motor local/remoto, conectividad, idioma,
  privacidad y retención.

## Evoluciones posteriores no aprobadas

- `EVO-010`: convertir voz en comando tipado y confirmado.
- Sync/multi-dispositivo, identidad, backup remoto, cifrado e IA.
- Requieren nuevas specs, decisiones y aprobación. No son extensión implícita de EVOLUTION-3.

## Gates entre EVOLUTION-2 y EVOLUTION-3

EVOLUTION-3 no comienza hasta que EVOLUTION-2 tenga:

- implementación integrada;
- format/analyze/test/build verdes;
- CI del SHA final;
- verificación Pixel 8 o estado pendiente declarado honestamente;
- `FINAL_VERIFICATION` coherente con evidencia;
- ninguna regresión crítica/alta abierta.

