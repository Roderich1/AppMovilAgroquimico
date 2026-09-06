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
- Estado: `VERIFIED`; PR #5 fusionada y resultado CSV/PDF aceptado por el propietario. Detalle
  en `features/EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md` y
  `features/EVOLUTION-2_FINAL_VERIFICATION.md`.
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

- IDs: `EVO-009`, `EVO-010`, `EVO-017`, `EVO-018`, `EVO-019`.
- Estado: `APPROVED` para implementación incremental.
- Precondición: EVOLUTION-2 integrada y cierre documental coherente con la validación aceptada
  por el propietario.
- Flujo común:

```text
Micrófono → transcripción → intención → draft editable → validar → confirmar táctilmente
```

- Orden interno: benchmark/ADR-002 → captura (`EVO-009`) → interpretación (`EVO-010`) → compra
  (`EVO-017`) → aplicación planificada (`EVO-018`) → pago (`EVO-019`).
- Captura e interpretación nunca escriben. Las tres operaciones sólo llaman los casos de uso
  existentes después de una confirmación táctil específica.
- Requiere benchmark local, corpus, privacidad, modo avión, Pixel 8 y equipo de menor capacidad.
- No incluye transferencias, reversiones, cierres, borrado, palabra de activación ni consultas.

## Evoluciones posteriores no aprobadas

- `EVO-020`: consultas de sólo lectura por voz sobre typed reads/reportes.
- Sync/multi-dispositivo, identidad, backup remoto, cifrado e IA.
- Requieren nuevas specs, decisiones y aprobación. No son extensión implícita de EVOLUTION-3.

## Gates entre EVOLUTION-2 y EVOLUTION-3

La primera rama productiva de EVOLUTION-3 no comienza hasta que EVOLUTION-2 tenga:

- implementación integrada;
- format/analyze/test/build verdes;
- CI del SHA final;
- verificación Pixel 8 y prueba CSV/PDF aceptada por el propietario;
- cierre documental coherente con la evidencia;
- ninguna regresión crítica/alta abierta.
