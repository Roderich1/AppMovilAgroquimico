# EVO-002 — Final Verification

## Estado

`IMPLEMENTED_NOT_VERIFIED` — 2026-09-06.

La implementación está preparada en `evolution/evo-002-typed-reports`, pero este documento no
declara cierre ni release. El entorno bloqueó la ejecución de Flutter/Dart al detectar un acceso
inesperado al endpoint de metadatos de instancia durante la preparación del SDK. Se eligió
continuar sólo con implementación y revisión estática.

`EVO-003` permanece bloqueada. No se añadió micrófono, permiso, plugin, transcripción, intención
ni acción de voz.

## Evidencia implementada

| Área | Evidencia |
|---|---|
| Lecturas tipadas | `lib/domain/read_models.dart`; adaptadores en `AgroRepository` sin cambiar SQL |
| Consumidores | dashboard, inventario y liquidaciones usan los modelos migrados |
| Modelo neutral | `lib/domain/report_models.dart` y `ReportComposer` |
| Formatos | `CsvReportGenerator` y `PdfReportGenerator`, sin acceso a SQLite/filesystem |
| Orquestación | `ReportExportService`: typed reads → compositor → generador → storage |
| Persistencia | archivo `.partial`, rename final, nombre seguro y sin sobrescritura silenciosa |
| UX | selector PDF/CSV, campaña, cinco reportes, ruta final y aviso de datos sensibles |
| Tests añadidos | mappers, paridad query/model, compositor, CSV, PDF largo y storage |
| Datos | schema `6`, backup format `1`, FIFO/dinero/escrituras sin cambios |

## Revisión estática realizada

- `git diff --check`: sin whitespace errors.
- Búsqueda de consumidores migrados: no quedan accesos por alias SQL para inventario, campañas,
  saldos ni costos en las tres pantallas objetivo.
- CSV: BOM UTF-8, `;`, CRLF, comillas/saltos, decimal con coma y neutralización de fórmulas.
- PDF: `MultiPage`, A4 horizontal, headers/footers, filtros, tabla y totales.
- Guardado: temporal en el mismo directorio, publicación por rename y sufijo ante colisión.

Esta revisión no sustituye análisis, tests, build ni ejecución en Android.

## Gates pendientes obligatorios

| Gate | Estado | Comando/evidencia requerida |
|---|---|---|
| Lockfile | PENDIENTE | `flutter pub get`; revisar y versionar `pubspec.lock` |
| Formato | PENDIENTE | `dart format --output=none --set-exit-if-changed lib test` |
| Análisis | PENDIENTE | `flutter analyze` |
| Tests | PENDIENTE | `flutter test` incluyendo la suite nueva |
| APK release | PENDIENTE | `flutter build apk --release` |
| CI de rama/PR | PENDIENTE | ejecución verde del workflow `Flutter CI` |
| Pixel 8 API 36 | PENDIENTE | matriz manual siguiente |

## Matriz Pixel 8 requerida

1. Exportar inventario PDF y CSV con cero filas y con dataset real.
2. Exportar costo por producto y por chaco con todas las campañas y una campaña concreta.
3. Exportar resumen de campaña activa y cerrada.
4. Exportar estado de cuenta con saldo inicial, cargos, pagos y caracteres `ñ/á/é`.
5. Abrir PDF largo multipágina; verificar cabecera, pie, saltos, totales e importes grandes.
6. Abrir CSV en hoja de cálculo; verificar columnas, decimal con coma, comillas y saltos.
7. Verificar nombres muy largos, fuente Android 130 %, navegación atrás y cancelación.
8. Confirmar que fallar/cancelar no escribe SQLite ni deja `.partial`.
9. Confirmar modo avión durante toda la generación.

## Criterio de desbloqueo de EVO-003

Sólo cambiar este estado a `VERIFIED` y desbloquear `EVO-003` cuando todos los gates anteriores
estén verdes, la evidencia Pixel 8 esté registrada y no haya regresiones P0/P1/P2 abiertas.
