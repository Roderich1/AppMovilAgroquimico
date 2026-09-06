# EVOLUTION-2 — Trazabilidad de la implementación

> **Estado: `IN_PROGRESS`.** Este documento registra lo implementado y las evidencias
> obtenidas. **No es una verificación final** y no debe leerse como cierre: faltan gates
> declarado en §8. `EVOLUTION-2_FINAL_VERIFICATION.md` no existe todavía, y no debe crearse
> hasta que ese gate esté cubierto con evidencia real.

## 1. Identidad

| Campo | Valor |
|---|---|
| Etapa | `EVOLUTION-2` |
| Features | `EVO-004`, `EVO-005`, `EVO-006` |
| Rama | `evolution/evolution-2-typed-reports` |
| SHA base | `44c2e792aa3d96a601428777a3a0419568a77ac1` (`origin/main` sin avanzar) |
| Baseline inmutable | `v1.0.0-base-stable` → `f4c6510438991f4948fda921eec7c67fe2a2acc2` (no se movió) |
| Flutter / Dart | 3.47.2 / 3.13.2 |
| Java local | Temurin **21.0.10**; el CI ejecuta con Temurin **17** (§7) |
| Esquema SQLite | `6`, **sin cambios** |
| Formato de respaldo | `1`, **sin cambios** |
| Dependencias | **sin cambios**; `pubspec.yaml` y `pubspec.lock` idénticos al SHA base |

## 2. Arquitectura implementada

```text
SQLite ── consultas ya probadas de AgroRepository (SIN TOCAR)
   │
   ├─ data/typed_reads.dart ......... adaptadores tipados (extensión, no reescritura)
   │      │
   │      └─ domain/read_models.dart  modelos inmutables + mappers validados
   │             │
   │             ├─ pantallas migradas (inventario, inicio, liquidación, persona, catálogos)
   │             │
   │             └─ domain/reports/report_composer.dart ── compositor de los 5 reportes
   │                        │
   │                        └─ domain/reports/report_table.dart ── modelo tabular NEUTRAL
   │                                   │
   │                                   ├─ services/reports/csv_report_generator.dart
   │                                   └─ services/reports/pdf_report_generator.dart
   │                                              │
   └─ services/reports/report_export_service.dart ─┴─ services/reports/report_storage.dart
```

Aislamiento comprobado en los `import` de cada archivo:

| Capa | Puede ver | NO ve |
|---|---|---|
| `report_table` / `report_composer` | dominio puro | `dart:io`, Flutter, sqflite |
| `csv_report_generator` | `dart:convert`, `dart:typed_data`, modelo neutral | filesystem, SQLite, widgets |
| `pdf_writer` / `pdf_report_generator` | `dart:convert`, `dart:typed_data`, modelo neutral | filesystem, SQLite, widgets |
| `report_storage` | `dart:io`, `path`, `path_provider` | el contenido del reporte |

## 3. Requisitos y evidencia

### EVO-004 — Modelos tipados de lectura

| ID | Cómo se cumple | Test |
|---|---|---|
| REQ-001 | Diez modelos inmutables en `domain/read_models.dart`, con tipos y nulabilidad explícitos | `read_models_test.dart` |
| REQ-002 | Cada método tipado llama al legacy y sólo mapea | `typed_reads_parity_test.dart` (13 tests) |
| REQ-003 | `lib/data/agro_repository.dart` y `lib/data/app_database.dart` con **cero líneas de diff** | `git diff origin/main...HEAD` |
| REQ-004 | Inventario, Inicio, Liquidación, detalle de persona y Catálogos sin aliases SQL de las lecturas migradas | `reports_screen_test.dart`, suite previa |
| REQ-005 | `applications`, `personProfile`, `personStockSummary`, `farmsForPerson` y catálogos siguen en el camino legacy | compilación y suite previa |
| REQ-006 | `RowReader` distingue columna ausente, nulo indebido y tipo erróneo; el mensaje nombra consulta y columna y **nunca el valor** | `read_models_test.dart` |

Consultas tipadas: `campaigns`, `people`, `inventorySummary`, `settlements`, `topSettlements`,
`productCostReport`, `farmCostReport`, `campaignCloseSummary`, `personCampaignBalance`,
`detailedStatement`.

### EVO-005 — CSV

| ID | Cómo se cumple | Test |
|---|---|---|
| REQ-001 | CSV y PDF reciben el mismo `ReportTable` con los mismos enteros | `report_pdf_test.dart` § equivalencia |
| REQ-002 | BOM `EF BB BF`, separador `;`, terminador CRLF, comillas dobladas | `report_csv_test.dart` |
| REQ-003 | `decimalFromScaled` convierte con división y módulo enteros; ningún `double` toca dinero | `report_composer_test.dart` |
| REQ-004 | Cantidad y unidad en columnas distintas | `report_csv_test.dart` |
| REQ-005 | Apóstrofo en celdas de TEXTO que empiezan por `=`, `+`, `-`, `@`, tabulador o CR, incluidos título, filtros y cabeceras | `report_csv_test.dart` |
| REQ-006 | Sin red y sin escritura: la base queda idéntica byte a byte | `report_export_service_test.dart` |

### EVO-006 — PDF

| ID | Cómo se cumple | Test |
|---|---|---|
| REQ-001 | A4 `595.28 × 841.89`, paginación calculada antes de dibujar | `report_pdf_test.dart` |
| REQ-002 | Título, fecha, filtros, cabeceras repetidas por página, numeración y totales que no se parten | `report_pdf_test.dart` |
| REQ-003 | `WinAnsiEncoding`; `ñ`, tildes y diéresis comprobadas byte a byte; nombres largos con elipsis; importes de diez cifras íntegros | `report_pdf_test.dart` |
| REQ-004 | Sólo lectura; base idéntica byte a byte tras exportar los diez reportes | `report_export_service_test.dart` |
| REQ-005 | Escritura a temporal `.parcial` y renombrado final; ante fallo se borra el temporal | `report_storage_test.dart` |

La elección de no usar el paquete `pdf` está razonada en
[`ADR-001`](../decisions/ADR-001-generacion-pdf-sin-dependencia.md).

### Reportes disponibles

| Reporte | Columnas | Filtros | Totales |
|---|---|---|---|
| Inventario | producto, unidad, físico, comprometido, proyectado, valor | global, sin campaña | valor total |
| Costo por producto | producto, cantidad, unidad, costo | campaña o todas | costo total |
| Costo por chaco | chaco, propietario, área, costo, costo/ha | campaña o todas | costo total |
| Resumen de campaña | concepto, cantidad, importe | campaña **obligatoria** | compras, aplicaciones, saldo |
| Estado de cuenta | fecha, concepto, chaco, cargo, crédito, acumulado | persona **obligatoria** + campaña o todas | cargos, créditos, saldo final |

## 4. Guardrails — comprobación sobre el diff

| Guardrail | Evidencia |
|---|---|
| Esquema y migraciones sin cambios | `lib/data/app_database.dart`: 0 líneas de diff |
| SQL funcional sin cambios | `lib/data/agro_repository.dart`: 0 líneas de diff |
| FIFO, dinero, cuentas y escrituras sin cambios semánticos | mismo archivo sin diff; suite contable previa intacta y en verde |
| Backup formato 1 sin cambios | `backup_service.dart` e `invoice_storage.dart`: 0 líneas de diff |
| Sin dependencias nuevas | `pubspec.yaml` y `pubspec.lock`: 0 líneas de diff |
| Sin voz, red, cloud, sync, analytics ni compartir | ningún `import` fuera del conjunto ya presente en la baseline |
| Dinero siempre entero | ningún `double` asociado a importes o cantidades |
| Generar reportes no escribe en SQLite | el archivo de la base queda **idéntico byte a byte** tras los diez reportes |
| Tag estable sin mover | `v1.0.0-base-stable` sigue en `f4c6510` |

## 5. Commits

| # | Commit | Contenido |
|---|---|---|
| 1 | `test: characterize report reads before typed migration` | caracterización + estado a `IN_PROGRESS` |
| 2 | `refactor: add typed report read models` | EVO-004: modelos, mappers y adaptadores |
| 3 | `refactor: migrate report consumers to typed reads` | consumidores migrados |
| 4 | `feat: add neutral report composition and CSV export` | Lote D + EVO-005 |
| 5 | `feat: add PDF report generation and storage` | EVO-006 + Lote G |
| 6 | `feat: expose report export UX` | Lote H |
| 7 | `docs: record EVOLUTION-2 implementation and PDF decision` | ADR-001 y esta trazabilidad |
| 8 | `fix: end the busy state before showing the export result` | corrección de UX detectada por un test nuevo |

## 6. Gates ejecutados localmente

Sobre el SHA base, **antes** de tocar código:

| Gate | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 0 cambios |
| `flutter analyze` | 0 issues |
| `flutter test` | **253 / 253** |
| `flutter build apk --release` | 60,6 MB, sin firmar |

Sobre la rama, al terminar:

| Gate | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 0 cambios sobre 86 archivos |
| `flutter analyze` | 0 issues |
| `flutter test` | **456 / 456** (253 previos + 203 nuevos) |
| Desglose de los nuevos | caracterización 19 · mappers 23 · paridad 13 · compositor 37 · CSV 23 · PDF 24 · storage 18 · orquestación 27 · pantalla 19 |
| `flutter build apk --release` | 61,1 MB, sin firmar |
| `git diff --check` | limpio |

Ningún test previo se debilitó, se borró ni se marcó `skip`. El único cambio en un test
existente completa una fixture: `_SettlementFakeRepository.detailedStatement` devolvía una fila
sin `campaign_id`, `notes` ni `reversal_of_id`, columnas que la consulta real sí trae. El mapper
tipado lo detectó; el doble quedó **más** fiel al contrato, no menos exigente.

## 7. CI sobre el SHA final

| Campo | Valor |
|---|---|
| SHA | `2b40955109b6588eb05173f9b54351beed618b8c` |
| Run | [`34014442336`](https://github.com/Roderich1/AppMovilAgroquimico/actions/runs/34014442336) |
| Workflow | `Flutter CI` (`.github/workflows/flutter-ci.yml`), Flutter 3.47.2 · JDK Temurin 17 |
| Resultado | **success** |
| Pasos | Formato ✅ · Análisis estático ✅ · Tests ✅ · Build de release sin firmar ✅ |

El CI ejecuta los cuatro gates con **Java 17**, que es el toolchain de referencia; el entorno
local usó Temurin 21, y por eso el gate que cuenta para Java es éste.

Un run anterior sobre `d9ad2e2` quedó `cancelled` por la política de `concurrency` del
workflow al llegar el commit siguiente. No es un fallo: el run válido es el del SHA final.

## 8. Gate PENDIENTE

No se declara `VERIFIED` y no se crea `FINAL_VERIFICATION` porque falta:

| Gate | Estado | Motivo |
|---|---|---|
| Verificación en Pixel 8 / Android 16 (API 36) | **PENDIENTE** | no había dispositivo ni emulador disponible en el entorno de implementación |

Este gate no es una formalidad para esta feature: `EVO-006` escribe archivos en el
almacenamiento de Android a través de `path_provider`, y la carpeta real, los permisos y el
comportamiento de `rename` sólo se comprueban de verdad en el dispositivo. La suite usa
carpetas temporales del equipo de desarrollo.

Lo que la prueba de dispositivo tiene que cubrir cuando se ejecute:

1. `/reportes` alcanzable desde Operaciones; Atrás vuelve a Operaciones.
2. Los cinco reportes en CSV y en PDF, con datos reales del dataset determinista.
3. Carpeta de destino real en Android y nombre mostrado al usuario.
4. Abrir el CSV en una hoja de cálculo del teléfono: `ñ`, tildes y columnas correctas.
5. Abrir el PDF en un visor: varias páginas, cabeceras repetidas y totales.
6. Colisión de nombres: exportar dos veces el mismo reporte el mismo día.
7. Cancelar durante la generación: no queda archivo ni temporal.
8. Texto al 130 %, horizontal y listas largas.
9. `logcat` sin `RenderFlex` ni avisos de `setState`.

## 9. Riesgos residuales

| Riesgo | Mitigación / estado |
|---|---|
| El escritor PDF es código propio | 24 tests de estructura y contenido; alcance acotado a tablas de texto (ADR-001) |
| Los archivos no van cifrados | aviso permanente en pantalla y confirmación explícita antes de escribir; el usuario decide |
| La carpeta de destino no sobrevive a desinstalar la aplicación | misma limitación ya documentada del respaldo (`46_BASELINE_FINAL_FREEZE` §15.7) |
| Comportamiento real del filesystem de Android | **pendiente** de la prueba de dispositivo (§8) |
| Reportes muy grandes | probado con 250 filas en CSV y 200 en PDF; no se ha medido con miles |

## 10. Fuera de alcance — confirmación explícita

**No se implementó** `EVOLUTION-3`, ni `EVO-009`, ni `EVO-010`, ni ninguna función de voz. Los
documentos `EVO-009_*` no se tocaron. Tampoco se añadió red, backend, cloud, sincronización,
autenticación, analytics, compartir archivos, selector de documentos, `printing`, `open_filex`
ni permisos nuevos.
