# EVOLUTION-2 — Lecturas tipadas y exportación de reportes

## Identidad

| Campo | Valor |
|---|---|
| Etapa | `EVOLUTION-2` |
| Features | `EVO-004` typed reads; `EVO-005` CSV; `EVO-006` PDF |
| Decisión del propietario | Aprobada el 2026-09-06 |
| Estado | `APPROVED` |
| Base mínima | `main` incluye `bdd7b82f3e06d9943749a571284db8f94194c3b3` |
| Rama prevista | `evolution/evolution-2-typed-reports` |

`APPROVED` no significa implementada. El estado sólo pasa a `IN_PROGRESS` cuando exista una
rama real con cambios de implementación.

## Problema y valor

Las escrituras están tipadas, pero varias consultas devuelven `Map<String,Object?>` y fuerzan
claves/casts dentro de widgets. Esto vuelve frágil la evolución y no ofrece un contrato reusable
para reportes. Además, costos, inventario y cuentas sólo se consultan dentro de la aplicación.

EVOLUTION-2 conserva los resultados actuales, introduce typed reads incrementales y genera
reportes profesionales offline en CSV/PDF sin consultar SQLite desde generadores o widgets.

## Alcance

### EVO-004 — Modelos tipados de lectura

- Modelos inmutables y mappers para campañas, inventario, saldos, costos por producto/chaco,
  estado de cuenta y resumen de campaña.
- Métodos tipados incrementales que reutilizan las consultas probadas.
- Migración sólo de consumidores necesarios para reportes y pantallas tocadas.
- Métodos legacy permanecen mientras tengan consumidores.

### EVO-005 — CSV

- Modelo neutral de reporte tabular.
- Composición desde typed reads.
- Generador CSV puro e independiente de SQLite, widgets y filesystem.
- UTF-8 con BOM, separador `;`, CRLF, escaping y neutralización de fórmulas.

### EVO-006 — PDF

- Generación A4 multipágina desde el mismo modelo neutral.
- Encabezados, filtros, fecha, totales, nombres largos, español e importes grandes.
- Generador independiente de SQLite, widgets y filesystem.

### Orquestación y UX

- Almacenamiento independiente del generador.
- Escritura temporal y publicación final sin sobrescritura silenciosa.
- Selección de reporte, filtros y formato.
- Estados vacío, progreso, éxito, cancelación y error accionable.
- Advertencia de información sensible.

## Fuera de alcance

- Reescritura de `AgroRepository`, ORM, Freezed, `json_serializable` o state management global.
- Cambiar SQL funcional, schema v6, dinero, cantidades, FIFO, saldos o backup.
- XLSX salvo decisión posterior con justificación real.
- Compartir/transportar archivos, backend, cloud, sync, autenticación o voz.
- Implementar `EVO-009` o `EVO-010`.

## Arquitectura

```text
SQLite → query probada → mapper → typed read model
                                  ↓
                           ReportComposer
                                  ↓
                      CSV / PDF generator → bytes
                                  ↓
                          ReportStorage → file
```

Los generadores no conocen SQLite, Riverpod, widgets ni filesystem. `ReportStorage` no conoce
el contenido. El compositor recibe modelos tipados.

## Requisitos EVO-004

| ID | Requisito |
|---|---|
| EVO-004-REQ-001 | Cada modelo es inmutable, independiente de widgets y mapea tipos/nulls explícitamente. |
| EVO-004-REQ-002 | La migración conserva filas, orden, filtros y valores enteros. |
| EVO-004-REQ-003 | No se cambia SQL probado salvo defecto registrado por separado. |
| EVO-004-REQ-004 | Pantallas migradas dejan de conocer aliases SQL. |
| EVO-004-REQ-005 | Los métodos legacy permanecen donde tengan consumidores. |
| EVO-004-REQ-006 | Una fila inválida falla en el mapper con contexto seguro, no en el widget. |

## Requisitos EVO-005

| ID | Requisito |
|---|---|
| EVO-005-REQ-001 | CSV y PDF consumen el mismo modelo neutral. |
| EVO-005-REQ-002 | CSV usa UTF-8 BOM, `;`, CRLF y escaping de comillas/saltos. |
| EVO-005-REQ-003 | Los importes se expresan como decimal exacto sin pérdida de precisión. |
| EVO-005-REQ-004 | Cantidad y unidad ocupan columnas separadas cuando corresponda. |
| EVO-005-REQ-005 | Campos peligrosos para fórmulas se neutralizan. |
| EVO-005-REQ-006 | Generar funciona offline y no modifica datos. |

## Requisitos EVO-006

| ID | Requisito |
|---|---|
| EVO-006-REQ-001 | PDF A4 soporta múltiples páginas y tablas largas. |
| EVO-006-REQ-002 | Incluye título, fecha, filtros, encabezados repetidos y totales. |
| EVO-006-REQ-003 | Soporta nombres largos, importes grandes, `ñ` y tildes. |
| EVO-006-REQ-004 | Generar funciona offline y no modifica datos. |
| EVO-006-REQ-005 | Fallar/cancelar no deja archivo final parcial. |

## Reportes obligatorios

| Reporte | Datos mínimos | Filtros/totales |
|---|---|---|
| Inventario | producto, unidad, físico, comprometido, proyectado, valor | total de valor; global |
| Costo por producto | producto, cantidad, unidad, costo | costo total; campaña/todas |
| Costo por chaco | chaco, propietario, área, costo, costo/ha | costo total; campaña/todas |
| Resumen de campaña | compras, aplicaciones, planes y cuentas | campaña obligatoria |
| Estado de cuenta | fecha, concepto, cargo, crédito, acumulado | persona y campaña/todas |

## Dependencias

- Candidato PDF: [`pdf`](https://pub.dev/packages/pdf) `^3.13.0`, Apache-2.0, multipágina.
- CSV puede implementarse en Dart puro; una dependencia adicional exige beneficio demostrado.
- No incorporar `printing`, `open_filex` o share plugin dentro de este alcance sin aprobarlo.
- Ejecutar `flutter pub get` y comprobar compatibilidad real antes de cerrar la selección.

## Datos, seguridad y errores

- Schema `6`; ninguna migración prevista.
- Sólo lectura de datos operativos.
- PDF/CSV no cifrados; la UI advierte que contienen información sensible.
- Sin Internet, analytics, identidad ni permisos amplios nuevos.
- Sin filas: producir reporte con cabeceras/filtros y estado vacío coherente.
- Filtro inexistente: error tipado antes de generar.
- Fallo de generación o storage: no escribir destino final ni tocar SQLite.

## Pruebas mínimas

- Mappers válidos, null esperado y tipo inválido.
- Paridad legacy/typed de cada consulta migrada.
- Filtros, ceros, reversiones, nombres largos y números grandes.
- CSV: BOM, `;`, CRLF, comillas, saltos, tildes y fórmulas.
- PDF: `%PDF`, español, varias páginas, cabeceras y totales.
- Compositor: mismos valores enteros que los typed reads.
- Storage: extensión, nombre, temporal, fallo y colisión.
- Widget: selector, vacío, progreso, éxito/error y navegación atrás.
- Regresión completa y Pixel 8.

## Aceptación

- [ ] Cinco reportes generan CSV y PDF offline.
- [ ] UI y exportación comparten typed reads y valores exactos.
- [ ] No quedan casts por alias SQL en consumidores migrados.
- [ ] Schema, backup y reglas contables permanecen sin cambios.
- [ ] Format, analyze, test, APK, CI y Pixel 8 están verdes o pendientes declarados.
- [ ] Trazabilidad y documentación final actualizadas.

## Rollback

Retirar UI, generadores y métodos tipados conservando métodos legacy. No existe downgrade de
datos porque no se prevé cambio de schema.

