# EVO-002 — Typed Reads and Report Export

## Identity

| Campo | Valor |
|---|---|
| Feature | `EVO-002` |
| Subfeatures | `EVO-002A` typed reads; `EVO-002B` report export |
| Owner decision | Aprobada 2026-09-06 |
| Status | `IN_PROGRESS` |
| Base | `main` `f4c6510438991f4948fda921eec7c67fe2a2acc2` |
| Branch | `evolution/evo-002-typed-reports` |

## Problem and value

Las escrituras están tipadas, pero las consultas de lectura devuelven mapas con claves y casts
en widgets. Eso vuelve frágiles los cambios y no ofrece un contrato reutilizable para generar
reportes. Además, los costos, inventario y cuentas sólo se consultan dentro de la app.

EVO-002 preserva resultados y crea contratos tipados; luego genera reportes profesionales y
offline en PDF/CSV sin consultar SQLite desde generadores ni widgets.

## Scope

### EVO-002A

- Modelos inmutables y mappers para campañas, inventario, saldos, costos por producto/chaco,
  estado de cuenta, saldo de campaña y cierre/resumen de campaña.
- Métodos tipados incrementales en el repositorio, reutilizando el SQL probado.
- Migración de `InventoryScreen` y `SettlementsScreen`, incluidas sus lecturas de reportes.
- Mantener métodos legacy requeridos por pantallas/tests no tocados.

### EVO-002B

- Modelo neutral de reporte tabular.
- Composición desde typed reads.
- Generadores independientes PDF y CSV.
- Almacenamiento local independiente del generador.
- UI de exportación para inventario, costo por producto, costo por chaco, resumen de campaña y
  estado de cuenta individual.

## Non-scope

- Reescritura de `AgroRepository`, ORM, Freezed, json_serializable o state management.
- Cambiar SQL funcional, schema v6, dinero, FIFO, saldos, filtros o backup.
- XLSX: diferido; CSV compatible con hojas de cálculo cubre el intercambio inicial sin otra
  dependencia compleja.
- Compartir/transportar archivos (`EVO-001`), backend, cloud, sync, autenticación o voz.
- Implementar `EVO-003` o interpretar comandos.

## Architecture

```text
SQLite → query legacy probada → mapper → typed read model
                                      ↓
                               ReportComposer
                                      ↓
                         PDF / CSV generator → bytes
                                      ↓
                              ReportStorage → file
```

Los generadores no conocen SQLite, Riverpod, widgets ni filesystem. `ReportStorage` no conoce
el contenido. El compositor sólo recibe typed reads.

## EVO-002A requirements

| ID | Requisito |
|---|---|
| EVO-002A-REQ-001 | Cada modelo es inmutable, independiente de widgets y mapea tipos/nulls explícitamente. |
| EVO-002A-REQ-002 | La migración conserva exactamente filas, orden, filtros y valores enteros. |
| EVO-002A-REQ-003 | No se cambia SQL probado salvo defecto registrado por separado. |
| EVO-002A-REQ-004 | `InventoryScreen` deja de conocer aliases SQL. |
| EVO-002A-REQ-005 | `SettlementsScreen` usa modelos tipados para saldos y costos. |
| EVO-002A-REQ-006 | Los métodos legacy permanecen donde aún tienen consumidores. |
| EVO-002A-REQ-007 | Valores inválidos de DB fallan en el mapper con contexto, no en el widget. |

## EVO-002B requirements

| ID | Requisito |
|---|---|
| EVO-002B-REQ-001 | PDF y CSV consumen el mismo `TabularReport`. |
| EVO-002B-REQ-002 | Se implementan los cinco reportes del scope con filtro/cabecera explícitos. |
| EVO-002B-REQ-003 | PDF A4 soporta varias páginas, nombres largos, importes grandes, español, totales y fecha. |
| EVO-002B-REQ-004 | CSV es UTF-8 con BOM, separador `;`, CRLF y escaping de comillas/saltos. |
| EVO-002B-REQ-005 | Valores monetarios CSV se expresan como decimal exacto con coma y sin símbolo; cantidades incluyen unidad en columna separada. |
| EVO-002B-REQ-006 | Generación funciona offline y no solicita permisos de red. |
| EVO-002B-REQ-007 | Cancelar o fallar no modifica datos ni deja archivo parcial. |
| EVO-002B-REQ-008 | Nombre de archivo es estable, seguro e incluye reporte/fecha. |
| EVO-002B-REQ-009 | UI comunica formato, filtro, éxito, ruta y error accionable. |
| EVO-002B-REQ-010 | Generación y almacenamiento son contratos separados del transporte. |

## Reports

| Reporte | Datos | Totales/filtros |
|---|---|---|
| Inventario | producto, unidad, físico, comprometido, proyectado, valor | total de valor; global |
| Costo por producto | producto, cantidad, unidad, costo | costo total; campaña/todas |
| Costo por chaco | chaco, propietario, área, costo, costo/ha | costo total; campaña/todas |
| Resumen de campaña | compras, aplicaciones, planes y cuentas | campaña obligatoria |
| Estado de cuenta | fecha, concepto, tipo, cargo/crédito, acumulado | persona y campaña/todas |

## Dependencies

- `pdf ^3.13.0`: productor PDF Dart/Flutter, Apache-2.0, multipágina, compatible con Android y
  sin requerir Internet en generación.
- CSV se implementa en Dart puro para evitar una segunda dependencia por una codificación
  pequeña y completamente cubierta por tests. La alternativa `csv 8.0.0` fue evaluada.
- No se incorpora `printing`, `open_filex` ni share plugin: visualizar/transportar pertenece a
  otro alcance. La verificación abre los archivos con herramientas externas del dispositivo.

La compatibilidad definitiva queda condicionada a `flutter pub get`, analyze/test/build.

## Data, security and offline

- Schema `6`; ninguna migración.
- Sólo lectura de datos operativos.
- Archivos no cifrados: la UI indica que contienen información sensible.
- Guardado en downloads de la app o documents fallback, con escritura temporal y rename/copy
  para no dejar archivos parciales.
- Sin Internet, analytics, identidad ni permisos amplios nuevos.

## Error handling

- Sin filas: generar reporte vacío con cabeceras/filtro, no fallar.
- Campaña/persona inexistente: error tipado antes de generar.
- PDF/CSV failure: no escribir destino final.
- Storage failure: conservar datos y permitir reintento; mensaje seguro.

## Tests

- Mapper válido, null esperado y tipo inválido.
- Paridad legacy/typed de cada query.
- Filtros, ceros, reversiones y números grandes.
- CSV: BOM, `;`, CRLF, comillas, saltos, ñ/tildes y fórmula peligrosa tratada como texto.
- PDF: cabecera, multipágina, bytes `%PDF`, español y dataset largo.
- Compositor: mismos valores enteros que los typed reads.
- Storage: extensión, filename, temporal, fallo y reemplazo.
- Widgets: selector, estado vacío, éxito/error y back.
- Regresión completa + Pixel 8.

## Risks and rollback

- `RISK-006`: aliases/casts; mitigado en mapper y paridad.
- `RISK-008`: listas grandes; multipágina y pruebas de volumen.
- Dependencia PDF; aislada detrás de generador y removible.
- Rollback: retirar UI/generadores/métodos tipados; no existe downgrade de datos porque no hay
  cambio de schema.

## Acceptance and DoD

- [ ] Cinco reportes generan PDF/CSV offline con filtro visible.
- [ ] UI y export comparten typed reads y resultados exactos.
- [ ] No quedan casts por alias SQL en pantallas migradas.
- [ ] Schema, backup y reglas contables permanecen sin cambios.
- [ ] Format, analyze, test, APK release, CI y Pixel 8 están verdes/evidenciados.
- [ ] Trazabilidad y documentación final actualizadas.

## EVO-003 integration points

Los typed read models podrán alimentar contexto de vista previa en EVO-003. Ningún contrato de
voz se añade ahora y ningún reporte acepta texto libre como comando.
