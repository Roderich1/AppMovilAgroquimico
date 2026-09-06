# EVO-002 — Implementation Plan

## Guardrails

Base `f4c6510`; branch `evolution/evo-002-typed-reports`; schema v6, backup 1 y tag estable
inmutables. No voz, cloud, sync, auth, transporte de archivos ni refactor masivo.

## Batch A — Typed models and mappers

- Crear `lib/domain/read_models.dart`.
- Cubrir mappers, nulls y tipos inválidos.
- Añadir adaptadores tipados a `AgroRepository` sin cambiar SQL.
- Salida: paridad map/model para campañas, inventario, saldos, costos y cuenta.

## Batch B — Typed consumers

- Migrar `InventoryScreen` y carga/render de `SettlementsScreen`.
- Reemplazar record tuple ilegible por `SettlementScreenData` tipado.
- Conservar operaciones de pago usando IDs/valores tipados.
- Salida: pantallas sin claves SQL para lecturas migradas; widget tests verdes.

## Batch C — Neutral reporting core

- Crear `lib/domain/report_models.dart`.
- Crear `lib/application/report_composer.dart`.
- Un `TabularReport` alimenta ambos formatos.
- Salida: tests de cinco reportes, filtros, vacíos y paridad.

## Batch D — CSV and PDF generators

- `lib/services/csv_report_generator.dart`: Dart puro, UTF-8 BOM, `;`, CRLF, escaping.
- `lib/services/pdf_report_generator.dart`: `pdf ^3.13.0`, A4 multipágina y tablas.
- Generadores devuelven bytes y no acceden a SQLite/filesystem.
- Salida: unit tests y dataset largo.

## Batch E — Storage and orchestration

- `lib/services/report_storage.dart`: archivo temporal + publicación final.
- `lib/application/report_export_service.dart`: consulta/composición/generación/storage.
- Providers de DI en `app.dart`.
- Salida: fallos no dejan archivo final parcial.

## Batch F — Export UX

- Selector de reporte/formato en Liquidación.
- Exportar estado de cuenta desde su diálogo/persona.
- Estados busy, empty, success, error y advertencia de contenido sensible.
- Salida: navegación/back/teclado/layout no regresan.

## Batch G — Regression and documentation

- `dart format`, `flutter analyze`, `flutter test`, APK release.
- Pixel 8 API 36: cinco reportes, PDF/CSV, vacíos, largos, nombres/importes grandes, back,
  cancelación y 130 %.
- Actualizar spec, backlog, capability map, roadmap, risks, traceability y crear
  `EVO-002_FINAL_VERIFICATION.md`.

## Commit strategy

1. `docs: approve and specify EVO-002`
2. `refactor: add typed report read models`
3. `feat: add offline PDF and CSV report generation`
4. `feat: expose report export UX`
5. `test/docs: verify EVO-002`

Cada commit debe ser coherente y no debilitar la suite. Debido al bloqueo del entorno actual,
la implementación podrá prepararse estáticamente, pero no se marcará `VERIFIED` hasta que CI
y Pixel 8 aporten evidencia real.
