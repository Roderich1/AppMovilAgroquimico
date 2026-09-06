# EVOLUTION-2 — Trazabilidad de la implementación

> **Estado: `IN_PROGRESS`.** Todos los gates exigidos por la especificación están cubiertos
> con evidencia real: gates locales, CI del SHA final y prueba en Pixel 8 (§8). Lo único que
> queda sin ejercitar es abrir el CSV en una hoja de cálculo **del teléfono**, porque la
> imagen del emulador no trae ninguna; el archivo se validó byte a byte en su lugar.
>
> El estado sigue en `IN_PROGRESS` y `EVOLUTION-2_FINAL_VERIFICATION.md` no se crea porque
> declarar `VERIFIED` es una decisión del propietario tras revisar el PR, no del implementador.

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

## 8. Gate Pixel 8

Ejecutado el 2026-09-06 sobre el AVD `Pixel_8` (`emulator-5554`,
`sdk_gphone16k_x86_64`), **Android 16 / API 36, 1080 × 2400, 420 dpi**, el mismo entorno de
referencia que la baseline. Ajustes de partida y de salida: `font_scale 1.0`,
`user_rotation 0`, `accelerometer_rotation 1`.

Procedimiento RESET → SEED → AUDIT con `tool/ui_audit_push.sh`, es decir el dataset
determinista de `36_UI_AUDIT_DATASET` regenerado en esquema v6: 7 personas · 22 productos ·
8 chacos · 4 proveedores · 3 campañas · 10 compras · 7 transferencias · 12 aplicaciones ·
5 planes.

Evidencia: 32 capturas en [`artifacts/ui-audit/evolution-2/`](../../../artifacts/ui-audit/evolution-2),
con su índice en el `README.md` de esa carpeta.

### Resultado por punto

| # | Punto | Resultado |
|:--:|---|---|
| 1 | `/reportes` desde Operaciones; Atrás vuelve allí | ✅ y `dumpsys window` confirma que el foco sigue en la aplicación |
| 2 | Los cinco reportes en CSV y PDF con datos reales | ✅ 10 archivos escritos |
| 3 | Carpeta real de Android y nombre mostrado | ✅ `/storage/emulated/0/Android/data/com.comunidad.agro.agroquimicos/files/Download/reportes`, declarada antes de exportar y repetida al terminar |
| 4 | Abrir el CSV en una hoja de cálculo del teléfono | ⚠️ **no ejercitado**: la imagen del AVD no tiene ninguna aplicación que declare `text/csv` ni `text/plain`. Ver compensación abajo |
| 5 | Abrir el PDF en un visor: varias páginas, cabeceras repetidas y totales | ✅ con el visor de Android (`com.google.android.apps.viewer.PdfViewerActivity`) |
| 6 | Colisión de nombres el mismo día | ✅ `… (2).csv`, `… (3).pdf`, `… (5).pdf`; el original conserva su contenido |
| 7 | Cancelar durante la generación | ✅ sin archivo nuevo y sin temporal `.parcial` |
| 8 | 130 %, horizontal y listas largas | ✅ tras corregir dos desbordes (abajo) |
| 9 | `logcat` sin `RenderFlex` ni avisos de `setState` | ✅ **0 y 0** en el recorrido final |

### Punto 4 — qué se hizo en su lugar

La imagen del emulador sólo trae Google Drive, que registra un visor de PDF pero ningún
lector de hojas de cálculo ni de texto plano. En vez de dar el punto por bueno, los archivos
se **extrajeron del dispositivo byte a byte** (`adb exec-out cat`) y se comprobó sobre esos
bytes lo que el punto pretende asegurar:

- BOM `EF BB BF` al inicio;
- terminadores CRLF y separador `;`;
- `ñ`, tildes y diéresis correctas (`Físico`, `Agrícola`, `Cooperativa Agrícola San Julián`);
- columnas alineadas con las cabeceras y decimales exactos.

Además las cifras se cruzaron con lo que la propia aplicación muestra: el inventario del CSV
coincide con las tarjetas de Inicio (`2,4-D Amina` 500 L, `16.700,00 Bs`), y el saldo final del
estado de cuenta (`312.816,70`) coincide con "Principales saldos" para esa persona. El costo
total por chaco del CSV (`71.980,50`) coincide con las aplicaciones del resumen de campaña.

Queda pendiente **abrir el archivo en una hoja de cálculo real**, que exige una imagen de
Android con una instalada o un teléfono físico.

### Defectos encontrados en el dispositivo y corregidos en esta rama

Los tres se vieron sólo en el teléfono y ninguno lo detectaba la suite; cada uno lleva ahora
su test de regresión.

| Defecto | Causa | Corrección | Test |
|---|---|---|---|
| La barra inferior resaltaba "Inicio" estando en `/reportes`, y Atrás sin pila habría ido a Inicio | `/reportes` no estaba en `AppShell.operationsSubRoutes` | añadida a ese conjunto, que gobierna destino resaltado y retroceso | `hierarchical_navigation_test.dart`: `selectedIndex` y `backFallback` |
| `RIGHT OVERFLOWED BY 47 PIXELS` en el desplegable de persona | `DropdownButtonFormField` se dimensiona por su elemento más ancho; sin `isExpanded` un nombre largo no cabe | `isExpanded: true` y elipsis en los elementos, en persona y en campaña | `reports_screen_test.dart`: nombre de persona y de campaña largos |
| En horizontal y al 130 % el aviso de consentimiento salía recortado, y el armazón del diálogo desbordaba 2,3 px | altura insuficiente para icono + título + tres párrafos + acciones | `scrollable: true` y el icono movido al título en los dos diálogos | `reports_screen_test.dart`: aviso legible entero en horizontal al 130 % |

El primero es de la misma familia que UIBUG-062 y el tercero de la de UIBUG-067/068: la
combinación horizontal + 130 % vuelve a ser la que destapa el problema.

### Comprobaciones adicionales

- El PDF multipágina se verificó con un inventario de 120 líneas producido por el **mismo
  generador**, porque el dataset determinista (22 productos) cabe en una sola página: 3
  páginas, cabeceras repetidas en todas, pies `Página N de 3` y total sólo en la última.
- El PDF renderiza en el visor de Android con tildes y `ñ` correctas, números alineados a la
  derecha y nombres largos recortados con elipsis.
- No quedó ningún archivo `.parcial` en ningún momento del recorrido.
- La copia a `/sdcard/Download` para abrir los archivos con un visor externo la hizo `adb`
  como parte de la verificación: **la aplicación no comparte ni transporta nada**.

## 9. Riesgos residuales

| Riesgo | Mitigación / estado |
|---|---|
| El escritor PDF es código propio | 24 tests de estructura y contenido; alcance acotado a tablas de texto (ADR-001) |
| Los archivos no van cifrados | aviso permanente en pantalla y confirmación explícita antes de escribir; el usuario decide |
| La carpeta de destino no sobrevive a desinstalar la aplicación | misma limitación ya documentada del respaldo (`46_BASELINE_FINAL_FREEZE` §15.7) |
| Comportamiento real del filesystem de Android | comprobado en el Pixel 8: carpeta real, colisiones numeradas y ningún temporal (§8) |
| Reportes muy grandes | probado con 250 filas en CSV y 200 en PDF, y 120 líneas en el dispositivo; no se ha medido con miles |
| CSV sin abrir en una hoja de cálculo real | el AVD no trae ninguna; validado byte a byte y cruzado con las cifras de la aplicación (§8) |

## 10. Fuera de alcance — confirmación explícita

**No se implementó** `EVOLUTION-3`, ni `EVO-009`, ni `EVO-010`, ni ninguna función de voz. Los
documentos `EVO-009_*` no se tocaron. Tampoco se añadió red, backend, cloud, sincronización,
autenticación, analytics, compartir archivos, selector de documentos, `printing`, `open_filex`
ni permisos nuevos.
