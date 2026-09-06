# EVOLUTION-2 — Plan de implementación

## Estado y guardrails

Estado: `IN_PROGRESS`. Implementación iniciada en `evolution/evolution-2-typed-reports`
sobre `44c2e792aa3d96a601428777a3a0419568a77ac1`.

La rama se crea desde el `main` vigente después de integrar la corrección documental:

`evolution/evolution-2-typed-reports`

Conservar schema v6, backup format 1 y tag estable. No voz, cloud, sync, autenticación,
transporte de archivos ni refactor masivo.

## Batch A — Baseline y pruebas de caracterización

- Confirmar SHA, árbol limpio, toolchain, tests y CI.
- Identificar queries/consumidores exactos.
- Añadir caracterización cuando falte una protección de paridad.
- Salida: contrato medido antes de refactor.

## Batch B — EVO-004 modelos y mappers

- Crear modelos de lectura en `domain/` o ubicación coherente con el código real.
- Cubrir tipos, nulls y filas inválidas.
- Añadir adaptadores tipados sin cambiar SQL funcional.
- Salida: paridad para campañas, inventario, saldos, costos y cuenta.

## Batch C — Consumidores tipados

- Migrar sólo dashboard/inventario/liquidaciones y consumidores necesarios.
- Conservar operaciones de escritura y métodos legacy no migrados.
- Salida: pantallas objetivo sin claves SQL de las lecturas migradas.

## Batch D — Núcleo neutral de reporting

- Crear modelo tabular neutral y compositor de cinco reportes.
- El compositor consume typed reads, no SQLite.
- Salida: tests de filtros, vacíos, totales y paridad.

## Batch E — EVO-005 CSV

- Generador puro: UTF-8 BOM, `;`, CRLF, escaping y neutralización de fórmulas.
- No filesystem, SQLite ni widgets.
- Salida: tests con caracteres españoles y dataset largo.

## Batch F — EVO-006 PDF

- Validar `pdf ^3.13.0` con el toolchain real.
- Implementar A4 multipágina, encabezados, filtros, totales y fuentes.
- No filesystem, SQLite ni widgets.
- Salida: tests de estructura y volumen.

## Batch G — Storage y orquestación

- Archivo temporal y publicación final.
- Nombre seguro, extensión correcta y colisiones sin sobrescritura silenciosa.
- Servicio de exportación coordina lectura, composición, generación y storage.
- Salida: los fallos no dejan archivos finales parciales.

## Batch H — UX

- Selector de reporte, formato y filtros.
- Exportar estado de cuenta desde un punto coherente con la navegación actual.
- Estados busy, empty, success, cancelación y error.
- Advertencia de datos sensibles.

## Batch I — Cierre

Ejecutar:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

Después:

- publicar rama;
- abrir PR;
- esperar CI verde;
- verificar Pixel 8/API 36;
- actualizar backlog, roadmap, riesgos, DoD y trazabilidad;
- crear `EVOLUTION-2_FINAL_VERIFICATION.md` con evidencia real.

## Estrategia de commits

1. `test: characterize report reads before typed migration`
2. `refactor: add typed report read models`
3. `feat: add neutral report composition and CSV export`
4. `feat: add PDF report generation and storage`
5. `feat: expose report export UX`
6. `test/docs: verify EVOLUTION-2`

No declarar `VERIFIED` si falta un gate. Si no hay dispositivo, usar un estado honesto como
`IMPLEMENTED_NOT_DEVICE_VERIFIED` sólo si la política de estados se actualiza explícitamente;
de otro modo mantener `IN_PROGRESS` y registrar el gate pendiente.

