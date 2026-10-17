# Evidencia — Línea base del trabajo reconstruido Mobile (REC)

- Fecha de ejecución: 2026-10-15
- Commit: `278cbd32dc59b26824f59fcefb77bebbc3cecb95` (`origin/main`, worktree limpio)
- Entorno: Windows 11 Home 10.0.26200, Flutter 3.47.2 (stable). Sin dispositivo: pruebas de host (unit/widget).
- Comando 1 (raíz): `flutter test --reporter json` — 690 tests OK, 0 fallos, 53 archivos, 95.6 s.
- Comando 2 (subpaquete): `cd benchmark/voice_benchmark && flutter test --reporter json` — 56 tests OK, 0 fallos, 3 archivos, 4.3 s.
- Los resultados por archivo de la tabla provienen de esas dos corridas completas; para re-ejecutar un archivo: `flutter test <archivo>`.
- Ejecutado el 2026-10-15 con Claude Code en el equipo del autor. La verificación del autor (Roderich Rendón) queda registrada al aprobar el PR que incorpora este archivo; la revisión del tutor se registra aparte en GOV-01.

Criterio: `Verified` solo cuando los tests existentes cubren los comportamientos clave del alcance del issue; en otro caso `Partial`, con lo que falta.

| Issue | REC | Archivos principales | Tests que lo cubren | Resultado (2026-10-15) | Cobertura | Evidence |
|---|---|---|---|---|---|---|
| [#38](https://github.com/Roderich1/AppMovilAgroquimico/issues/38) <a id="rec-38"></a> | REC-002 | `lib/main.dart`<br>`lib/app.dart`<br>`lib/presentation/app_shell.dart`<br>`lib/presentation/widgets/common.dart`<br>`lib/data/app_database.dart`<br>`lib/data/agro_repository.dart` | `test/widget_test.dart`: 2/2 OK<br>`test/navigation_test.dart`: 4/4 OK<br>`test/hierarchical_navigation_test.dart`: 11/11 OK<br>`test/responsive_v5_test.dart`: 5/5 OK<br>`test/ui_polish_test.dart`: 19/19 OK | OK | full | Verified |
| [#39](https://github.com/Roderich1/AppMovilAgroquimico/issues/39) <a id="rec-39"></a> | REC-003 | `lib/data/app_database.dart`<br>`docs/10_DATA_MODEL.md`<br>`docs/13_LOCAL_STORAGE.md` | `test/migration_test.dart`: 2/2 OK<br>`test/schema_equivalence_test.dart`: 4/4 OK<br>`test/plan_lifecycle_test.dart`: 14/14 OK | OK | partial | Partial |
| [#40](https://github.com/Roderich1/AppMovilAgroquimico/issues/40) <a id="rec-40"></a> | REC-004 | `lib/presentation/screens/catalogs_screen.dart`<br>`lib/data/agro_repository.dart`<br>`lib/data/app_database.dart`<br>`lib/presentation/screens/persons_screen.dart` | `test/ui_polish_test.dart`: 19/19 OK<br>`test/report_reads_characterization_test.dart`: 19/19 OK<br>`test/e2e_v5_test.dart`: 1/1 OK | OK | partial | Partial |
| [#41](https://github.com/Roderich1/AppMovilAgroquimico/issues/41) <a id="rec-41"></a> | REC-005 | `lib/data/agro_repository.dart`<br>`lib/presentation/screens/catalogs_screen.dart`<br>`lib/data/typed_reads.dart`<br>`lib/domain/read_models.dart`<br>`lib/domain/labels.dart` | `test/campaign_lifecycle_test.dart`: 10/10 OK<br>`test/campaign_lifecycle_ui_test.dart`: 5/5 OK<br>`test/reports_test.dart`: 17/17 OK<br>`test/typed_reads_parity_test.dart`: 13/13 OK<br>`test/v4_repository_test.dart`: 4/4 OK<br>`test/v5_domain_test.dart`: 6/6 OK<br>`test/e2e_v5_test.dart`: 1/1 OK<br>`test/formatting_and_labels_test.dart`: 21/21 OK | OK | full | Verified |
| [#42](https://github.com/Roderich1/AppMovilAgroquimico/issues/42) <a id="rec-42"></a> | REC-006 | `lib/data/agro_repository.dart`<br>`lib/data/app_database.dart`<br>`lib/domain/models.dart`<br>`lib/domain/read_models.dart`<br>`lib/presentation/screens/planning_screen.dart`<br>`lib/presentation/screens/plan_form_screen.dart`<br>… | `test/plan_lifecycle_test.dart`: 14/14 OK<br>`test/plan_lifecycle_ui_test.dart`: 5/5 OK<br>`test/v5_domain_test.dart`: 6/6 OK<br>`test/e2e_v5_test.dart`: 1/1 OK<br>`test/e2e_scenario_test.dart`: 1/1 OK<br>`test/repository_test.dart`: 11/11 OK<br>`test/reports_test.dart`: 17/17 OK<br>`test/regression_widget_test.dart`: 4/4 OK | OK | full | Verified |
| [#43](https://github.com/Roderich1/AppMovilAgroquimico/issues/43) <a id="rec-43"></a> | REC-007 | `lib/data/agro_repository.dart`<br>`lib/domain/models.dart`<br>`lib/domain/money.dart`<br>`lib/presentation/screens/purchase_form_screen.dart` | `test/repository_test.dart`: 11/11 OK<br>`test/e2e_scenario_test.dart`: 1/1 OK<br>`test/e2e_v5_test.dart`: 1/1 OK<br>`test/money_test.dart`: 3/3 OK<br>`test/ui_polish_test.dart`: 19/19 OK<br>`test/regression_widget_test.dart`: 4/4 OK | OK | partial | Partial |
| [#44](https://github.com/Roderich1/AppMovilAgroquimico/issues/44) <a id="rec-44"></a> | REC-008 | `lib/data/invoice_storage.dart`<br>`lib/data/agro_repository.dart`<br>`lib/data/backup_service.dart`<br>`lib/presentation/screens/purchase_form_screen.dart`<br>`lib/presentation/screens/purchases_screen.dart` | `test/backup_container_test.dart`: 27/27 OK<br>`test/repository_test.dart`: 11/11 OK<br>`test/e2e_scenario_test.dart`: 1/1 OK | OK | partial | Partial |
| [#46](https://github.com/Roderich1/AppMovilAgroquimico/issues/46) <a id="rec-46"></a> | REC-010 | `lib/data/agro_repository.dart`<br>`lib/data/app_database.dart`<br>`lib/data/typed_reads.dart`<br>`lib/domain/read_models.dart`<br>`lib/presentation/screens/inventory_screen.dart`<br>`lib/presentation/screens/inventory_detail_screen.dart` | `test/reports_test.dart`: 17/17 OK<br>`test/repository_test.dart`: 11/11 OK<br>`test/typed_reads_parity_test.dart`: 13/13 OK<br>`test/read_models_test.dart`: 23/23 OK<br>`test/v5_domain_test.dart`: 6/6 OK<br>`test/v4_repository_test.dart`: 4/4 OK<br>`test/e2e_v5_test.dart`: 1/1 OK<br>`test/set_state_contract_test.dart`: 3/3 OK | OK | partial | Partial |
| [#47](https://github.com/Roderich1/AppMovilAgroquimico/issues/47) <a id="rec-47"></a> | REC-011 | `lib/data/agro_repository.dart`<br>`lib/domain/models.dart`<br>`lib/presentation/screens/application_form_screen.dart`<br>`lib/presentation/screens/applications_screen.dart`<br>`lib/data/app_database.dart` | `test/repository_test.dart`: 11/11 OK<br>`test/v5_domain_test.dart`: 6/6 OK<br>`test/e2e_v5_test.dart`: 1/1 OK<br>`test/e2e_scenario_test.dart`: 1/1 OK<br>`test/plan_lifecycle_test.dart`: 14/14 OK | OK | partial | Partial |
| [#48](https://github.com/Roderich1/AppMovilAgroquimico/issues/48) <a id="rec-48"></a> | REC-012 | `lib/data/agro_repository.dart`<br>`lib/domain/models.dart`<br>`lib/presentation/screens/transfer_form_screen.dart`<br>`lib/presentation/screens/transfers_screen.dart` | `test/v4_repository_test.dart`: 4/4 OK<br>`test/v5_domain_test.dart`: 6/6 OK<br>`test/repository_test.dart`: 11/11 OK<br>`test/e2e_v5_test.dart`: 1/1 OK<br>`test/ui_polish_test.dart`: 19/19 OK<br>`test/responsive_v5_test.dart`: 5/5 OK | OK | partial | Partial |
| [#50](https://github.com/Roderich1/AppMovilAgroquimico/issues/50) <a id="rec-50"></a> | REC-014 | `lib/data/agro_repository.dart`<br>`lib/presentation/screens/applications_screen.dart`<br>`lib/presentation/screens/purchases_screen.dart`<br>`lib/presentation/screens/transfers_screen.dart` | `test/repository_test.dart`: 11/11 OK<br>`test/v4_repository_test.dart`: 4/4 OK<br>`test/destructive_actions_test.dart`: 3/3 OK<br>`test/typed_reads_parity_test.dart`: 13/13 OK<br>`test/plan_lifecycle_test.dart`: 14/14 OK<br>`test/v5_domain_test.dart`: 6/6 OK<br>`test/reports_test.dart`: 17/17 OK<br>`test/e2e_v5_test.dart`: 1/1 OK | OK | partial | Partial |
| [#51](https://github.com/Roderich1/AppMovilAgroquimico/issues/51) <a id="rec-51"></a> | REC-015 | `lib/presentation/screens/dashboard_screen.dart`<br>`lib/presentation/screens/person_detail_screen.dart`<br>`lib/presentation/screens/farm_logbook_screen.dart`<br>`lib/data/agro_repository.dart`<br>`lib/data/typed_reads.dart`<br>`lib/domain/read_models.dart` | `test/reports_test.dart`: 17/17 OK<br>`test/report_reads_characterization_test.dart`: 19/19 OK<br>`test/read_models_test.dart`: 23/23 OK<br>`test/typed_reads_parity_test.dart`: 13/13 OK<br>`test/ui_polish_test.dart`: 19/19 OK<br>`test/repository_test.dart`: 11/11 OK<br>`test/hierarchical_navigation_test.dart`: 11/11 OK | OK | partial | Partial |
| [#52](https://github.com/Roderich1/AppMovilAgroquimico/issues/52) <a id="rec-52"></a> | REC-016 | `lib/domain/read_models.dart`<br>`lib/data/typed_reads.dart`<br>`lib/domain/reports/report_composer.dart`<br>`lib/domain/reports/report_table.dart`<br>`lib/services/reports/report_export_service.dart` | `test/typed_reads_parity_test.dart`: 13/13 OK<br>`test/report_reads_characterization_test.dart`: 19/19 OK<br>`test/read_models_test.dart`: 23/23 OK<br>`test/report_composer_test.dart`: 37/37 OK<br>`test/report_export_service_test.dart`: 27/27 OK<br>`test/regression_widget_test.dart`: 4/4 OK | OK | full | Verified |
| [#53](https://github.com/Roderich1/AppMovilAgroquimico/issues/53) <a id="rec-53"></a> | REC-017 | `lib/services/reports/csv_report_generator.dart`<br>`lib/services/reports/report_export_service.dart`<br>`lib/services/reports/report_storage.dart`<br>`lib/domain/reports/report_table.dart`<br>`lib/domain/reports/report_composer.dart`<br>`lib/presentation/screens/reports_screen.dart` | `test/report_csv_test.dart`: 23/23 OK<br>`test/report_export_service_test.dart`: 27/27 OK<br>`test/report_storage_test.dart`: 18/18 OK<br>`test/reports_screen_test.dart`: 22/22 OK<br>`test/report_composer_test.dart`: 37/37 OK | OK | partial | Partial |
| [#54](https://github.com/Roderich1/AppMovilAgroquimico/issues/54) <a id="rec-54"></a> | REC-018 | `lib/services/reports/pdf_writer.dart`<br>`lib/services/reports/pdf_report_generator.dart`<br>`lib/services/reports/report_export_service.dart`<br>`lib/services/reports/report_storage.dart`<br>`lib/domain/reports/report_composer.dart`<br>`lib/domain/reports/report_table.dart`<br>… | `test/report_pdf_test.dart`: 24/24 OK<br>`test/report_export_service_test.dart`: 27/27 OK<br>`test/report_storage_test.dart`: 18/18 OK<br>`test/reports_screen_test.dart`: 22/22 OK<br>`test/report_composer_test.dart`: 37/37 OK | OK | full | Verified |
| [#55](https://github.com/Roderich1/AppMovilAgroquimico/issues/55) <a id="rec-55"></a> | REC-019 | `lib/data/backup_service.dart`<br>`lib/data/invoice_storage.dart`<br>`lib/presentation/screens/settlements_screen.dart`<br>`lib/app.dart` | `test/backup_container_test.dart`: 27/27 OK<br>`test/backup_service_test.dart`: 10/10 OK<br>`test/backup_android_semantics_test.dart`: 3/3 OK<br>`test/installation_client_id_store_test.dart`: 11/11 OK<br>`test/secure_session_store_test.dart`: 19/19 OK | OK | partial | Partial |
| [#56](https://github.com/Roderich1/AppMovilAgroquimico/issues/56) <a id="rec-56"></a> | REC-020 | `lib/presentation/app_shell.dart`<br>`lib/presentation/widgets/common.dart`<br>`lib/app.dart`<br>`lib/presentation/screens/purchase_form_screen.dart`<br>`lib/presentation/screens/transfer_form_screen.dart`<br>`lib/presentation/screens/plan_form_screen.dart`<br>… | `test/ui_polish_test.dart`: 19/19 OK<br>`test/navigation_test.dart`: 4/4 OK<br>`test/hierarchical_navigation_test.dart`: 11/11 OK<br>`test/error_states_test.dart`: 3/3 OK<br>`test/set_state_contract_test.dart`: 3/3 OK<br>`test/destructive_actions_test.dart`: 3/3 OK<br>`test/responsive_v5_test.dart`: 5/5 OK<br>`test/regression_widget_test.dart`: 4/4 OK<br>`test/widget_test.dart`: 2/2 OK<br>`test/purchases_access_test.dart`: 3/3 OK | OK | partial | Partial |
| [#57](https://github.com/Roderich1/AppMovilAgroquimico/issues/57) <a id="rec-57"></a> | REC-021 | `.github/workflows/flutter-ci.yml`<br>`docs/46_BASELINE_FINAL_FREEZE.md`<br>`analysis_options.yaml` | `test/regression_widget_test.dart`: 4/4 OK<br>`test/set_state_contract_test.dart`: 3/3 OK<br>`test/plan_lifecycle_test.dart`: 14/14 OK<br>`test/campaign_lifecycle_test.dart`: 10/10 OK<br>`test/e2e_scenario_test.dart`: 1/1 OK<br>`test/schema_equivalence_test.dart`: 4/4 OK<br>`test/backup_container_test.dart`: 27/27 OK | OK | partial (tests); CI verificado | Verified — ver [REC_021_CI.md](REC_021_CI.md) |
| [#58](https://github.com/Roderich1/AppMovilAgroquimico/issues/58) <a id="rec-58"></a> | REC-022 | `benchmark/voice_benchmark/lib/bench/bench_controller.dart`<br>`benchmark/voice_benchmark/lib/bench/bench_export.dart`<br>`benchmark/voice_benchmark/lib/bench/bench_result.dart`<br>`benchmark/voice_benchmark/lib/bench/corpus.dart`<br>`benchmark/voice_benchmark/lib/bench/bench_platform.dart`<br>`benchmark/voice_benchmark/lib/port/base_transcription_port.dart`<br>… | `test/voice_benchmark_report_test.dart`: 48/48 OK<br>`benchmark/voice_benchmark/test/bench_controller_test.dart`: 19/19 OK<br>`benchmark/voice_benchmark/test/corpus_and_isolation_test.dart`: 15/15 OK<br>`benchmark/voice_benchmark/test/speech_transcription_port_test.dart`: 22/22 OK | OK | partial | Partial |
| [#59](https://github.com/Roderich1/AppMovilAgroquimico/issues/59) <a id="rec-59"></a> | REC-024 | `tool/voice_benchmark/main.dart`<br>`tool/voice_benchmark/aggregator.dart`<br>`tool/voice_benchmark/report.dart`<br>`tool/voice_benchmark/result_parser.dart`<br>`tool/voice_benchmark/text_normalizer.dart`<br>`benchmark/voice_benchmark/lib/bench/bench_controller.dart`<br>… | `test/voice_benchmark_report_test.dart`: 48/48 OK | OK | partial | Partial |

## Pendiente por REC (cobertura parcial)

### #39 REC-003

1) La equivalencia entre el esquema de una base nueva y el de una migrada solo se prueba desde V3. Faltan pruebas equivalentes desde V1, V2, V4 y V5. 2) No hay pruebas de los CHECK del esquema (persons.role, products.unit/base_unit, farms.area_m2 > 0, amount_bob_minor > 0, transfers from_person_id <> to_person_id, transfer_items.quantity_base > 0). Tampoco las hay del efecto de PRAGMA foreign_keys = ON ni de idx_campaign_single_active ante una inserción directa en SQLite; campaign_lifecycle_test.dart prueba la campaña activa única solo a través del repositorio. volume_test.dart solo comprueba que existen algunos índices. 3) No hay prueba de duplicados preexistentes en application_plan_items al migrar a v5; solo se prueba application_items. 4) Ninguna prueba de este alcance cubre la ausencia de efectos parciales ante una escritura SQLite fallida (RNF-02). Fuera del alcance del esquema, v4_repository_test.dart («transferencia insuficiente hace rollback completo») comprueba que una BusinessRuleException no deja transferencias ni altera el saldo. Eso es validación de repositorio, no un fallo de escritura a mitad de una transacción. 5) La evidencia docs/evidence/REC_MOBILE_BASELINE.md no existe en el worktree; tampoco existe docs/evidence/. Hay que crearla después de ejecutar la suite. 6) El worktree está en b95d3c3 (rama docs/rebaseline-fases-2026-10-15). Respecto de 278cbd3 solo cambian docs/00_INDEX.md y docs/adr/ADR-002-renumeracion-fases.md; lib/ y test/ son idénticos.

### #40 REC-004

Para pasar a Verified faltan:
(a) Un test que archive una persona, un chaco, un producto y un proveedor con archiveCatalog. Debe comprobar tres cosas: que el registro desaparece de people/farms/products/suppliers, que la fila sigue en la tabla con active=0 y que se conservan las compras, aplicaciones y movimientos que lo referencian. Así quedaría probado que el archivado es lógico y conserva la historia.
(b) Un test de renameCatalog que pruebe la edición del nombre y el rechazo del nombre vacío (BusinessRuleException).
(c) Validaciones de los diálogos de persona y de producto. Hoy solo se prueban el de proveedor y el de chaco.
(d) Un test de persistencia local con aserciones sobre los catálogos. plan_lifecycle_test.dart ('el estado sobrevive a cerrar y reabrir la base') crea personas, chacos, productos y proveedores en una base de archivo y la reabre, pero solo hace aserciones sobre plans(). Las pruebas de respaldo y restauración leen people(), pero no prueban el catálogo como tal.
(e) El archivo de evidencia docs/evidence/REC_MOBILE_BASELINE.md no existe en el repo; tampoco existe el directorio docs/evidence.
(f) En trazabilidad, RF-04 (productos), RF-05 (parcelas/chacos) y CU-04 sí corresponden. Pero ningún ID del Cap. III cubre de forma expresa los catálogos de personas y de proveedores; el proveedor solo aparece dentro de RF-07, que trata de compras. Lo dejo para revisión, sin cambiar los refs asignados.

### #43 REC-007

Ningún test ejercita los rechazos de confirmPurchase. Faltan cinco casos, todos con BusinessRuleException implementada en lib/data/agro_repository.dart:
1. Asignaciones que no suman la cantidad comprada.
2. Línea USD sin tipo de cambio o con tipo de cambio <= 0.
3. Línea BOB con tipo de cambio.
4. Productos repetidos dentro de la compra.
5. Compra sin líneas, o con cantidad o precio <= 0.

Busqué con rg en test/ y no hay ninguna expectativa de error sobre confirmPurchase.

Para RF-08 falta comprobar que purchase_items e inventory_lots de una compra USD conserven currency_code, original_unit_price_minor y exchange_rate_scaled. Hoy solo se comprueba el total en BOB y, en una transferencia, original_unit_price_minor de una compra BOB.

Tampoco hay un test de widget que envíe el formulario de compra y compruebe sus mensajes de validación (tipo de cambio sin seleccionar, suma asignada distinta de la comprada).

El archivo de evidencia docs/evidence/REC_MOBILE_BASELINE.md, citado en «Evidencia esperada», no existe en el worktree MOB (HEAD b95d3c3): hay que crearlo o corregir la referencia.

En esta verificación no se ejecutó flutter test. Origen queda pendiente del resultado de la suite.

### #44 REC-008

Para llegar a Verified faltan:
1. Un test unitario de AgroRepository.storeInvoiceImage con path_provider sustituido. Debe comprobar que copia el archivo a <documentos>/invoices con nombre invoice_<marca><ext>, que el origen no cambia y que la ruta devuelta es la que se guarda en la compra.
2. Un test de widget de PurchaseFormScreen que simule la selección desde cámara y desde galería y compruebe la vista previa y el resumen de factura adjunta.
3. Un test de widget de PurchasesScreen: la opción 'invoice' solo aparece si hay invoice_image_path, y al elegirla se abre el visor o, si el archivo no existe, se avisa.
4. Un test o una evidencia explícita de que la fotografía queda fuera de la información colectiva (RF-30, RN-08). En lib/ no encontré ningún módulo de sincronización que la exponga, pero ningún test lo comprueba.
5. Hay una contradicción en la documentación. docs/13_LOCAL_STORAGE.md (sección «Limitacion conocida (sin resolver)») sigue diciendo que el respaldo contiene solo la base de datos, mientras que docs/46_BASELINE_FINAL_FREEZE.md §9 dice que incluye las fotografías. Hay que corregir docs/13.
6. Sobre la evidencia del dispositivo: docs/46 §11 recoge la regresión en el AVD Pixel_8 (un emulador, no un teléfono físico). No hay un documento de evidencia propio de esta capacidad; el docs/evidence/REC_MOBILE_BASELINE.md que proponía el mapeo no existe.

### #46 REC-010

1. No hay tests para `inventoryProductHeader` (físico, comprometido y valor por producto), `inventoryProductDistribution` (reparto por persona) ni `inventoryProductLots` (lotes vigentes con filtros por persona, proveedor y campaña, y exclusión de lotes revertidos).
2. No hay tests de widget que comprueben el contenido de `InventoryScreen` o `InventoryDetailScreen`; falta verificar que muestran físico, comprometido y proyectado por separado y con su unidad. Hoy solo existe la prueba de humo de `set_state_contract_test.dart`.
3. RF-10 está cubierto solo en parte. No existe una consulta de historial de movimientos por producto o saldo; la procedencia se ve únicamente por lote (compra, proveedor, campaña, `parent_lot_id`). Ningún test comprueba la relación de un saldo con sus compras, aplicaciones, transferencias y reversiones.
4. Ningún test comprueba de forma explícita la visibilidad autorizada (RF-10/RN-12) en las consultas de inventario.
5. La evidencia `docs/evidence/REC_MOBILE_BASELINE.md` no existe todavía en el repositorio. Hay que crearla o sustituirla antes de pasar a Verified.

### #47 REC-011

1) Ningún test comprueba variance_quantity_base, la cantidad real menos la teórica, en application_items. Los tests pasan theoreticalQuantityBase, pero no hacen ninguna aserción sobre la variación. 2) AgroRepository.estimateFifoCost, que usa el formulario, no tiene test directo. 3) Falta un test de atomicidad (RN-04) para una aplicación multiproducto cuya segunda línea no tenga stock. Debe verificar que no persisten la aplicación, los ítems, los consumos ni los movimientos de la primera línea. Ese test hoy solo existe para transferencias, en v4_repository_test. 4) El rechazo por stock insuficiente (21000 contra 20000) solo comprueba la excepción, no que el stock quede intacto. 5) Ningún test rechaza una cantidad igual o menor que cero, aunque agro_repository.dart lo valida en confirmApplication. 6) No hay widget tests de ApplicationFormScreen. destructive_actions_test.dart solo prueba la reversión desde ApplicationsScreen. 7) Ningún test lee directamente los movimientos APPLICATION_OUT ni la fila USAGE_CHARGE; ambos se infieren por el stock y el saldo. 8) docs/evidence/REC_MOBILE_BASELINE.md no existe en el worktree; hay que crearlo con la salida real de la suite. Nota: el HEAD del worktree es b95d3c3 (docs ADR-002, sobre b9ee014 y 278cbd3), y git diff 278cbd3..HEAD no muestra cambios en lib/ ni en test/.

### #48 REC-012

1. No hay test del rechazo cuando el origen y el destino son la misma persona (BusinessRuleException 'El origen y el destino deben ser diferentes.', en agro_repository.dart l. 929-932). Es el primer criterio de aceptación del issue original.
2. No hay test de reverseTransfer sobre una transferencia multiproducto. Lo confirmé leyendo el código (l. 1094-1113): reverseTransfer inserta todos los movimientos de reversión con 'product_id': transfer['product_id'], que es el producto del primer ítem. Con más de un producto, los movimientos TRANSFER_REVERSAL_* de los demás ítems quedan con un product_id incorrecto. Falta un test que lo demuestre y la corrección correspondiente.
3. No hay test de que la reversión se rechace cuando el lote destino ya tuvo movimientos ('El stock transferido ya tuvo movimientos…'). Tampoco de la doble reversión ('La transferencia ya fue revertida o no existe.').
4. No se comprueba que el lote derivado conserve currency_code, exchange_rate_scaled, acquired_date y parent_lot_id. Solo se verifican el costo unitario y el precio original.
5. No se comprueba que TRANSFER_OUT y TRANSFER_IN usen la fecha efectiva indicada (parámetro date). Es un atributo exigido por RF-11.
6. Faltan dos widget tests: uno que confirme una transferencia desde TransferFormScreen y otro que la revierta desde TransfersScreen.
7. Ni transfer_form_screen.dart ni transfers_screen.dart tienen una condición que las limite al modo compartido. RF-11 aplica a ese modo, y su habilitación queda en RF-06 (fuera del alcance). No hay test al respecto.
8. La evidencia docs/evidence/REC_MOBILE_BASELINE.md no existe en el worktree (no hay carpeta docs/evidence). Hay que crearla o reemplazar la referencia antes de pasar a Verified.

### #50 REC-014

Faltan tests para estos comportamientos:
1. Reversión exitosa de una compra: los movimientos PURCHASE_REVERSAL, que los lotes queden en reversed_at, el CREDIT_ADJUSTMENT, que los pagos a proveedor queden en reversed_at y que la compra pase a status REVERSED. Hoy solo se prueba la guardia de lotes consumidos.
2. Guardia de la transferencia: el error cuando el stock transferido ya tuvo movimientos. Tampoco hay aserción sobre el status REVERSED de la transferencia ni sobre los movimientos TRANSFER_REVERSAL_IN/OUT.
3. Guardia de la compra cuando un lote fue transferido o ajustado.
4. Doble reversión. RF-13 dice: «una misma reversión no deberá producir dos restituciones». Ningún test invoca dos veces reverseApplication, reversePurchase o reverseTransfer para comprobar que la segunda lanza BusinessRuleException y no duplica la restitución.
5. Que el motivo (notes) y reversal_of_id se persistan.
6. Responsable de la reversión: RF-13 pide registrarlo, y agro_repository.dart no guarda quién revierte (no hay campo de actor ni reversed_by). Hay que confirmar si esa parte se cubre en otro lugar, por ejemplo con RF-25, o dejarla como pendiente.
7. Confirmación en la interfaz al revertir compras y transferencias (PurchasesScreen, TransfersScreen). destructive_actions_test solo cubre ApplicationsScreen.
8. El archivo de evidencia docs/evidence/REC_MOBILE_BASELINE.md no existe en el worktree, porque falta la carpeta docs/evidence. Hay que crearlo después de ejecutar la suite.

### #51 REC-015

1) Ninguna prueba de test/ llama a AgroRepository.farmLogbook() ni a farmProfile(), y ninguna monta FarmLogbookScreen (/chacos/:id solo aparece en el test de selectedIndex). Quedan sin cubrir los filtros por campaña y producto de farmLogbook, la columna fifo_lots y el comportamiento con aplicaciones revertidas. 2) FarmLogbookScreen llama a farmLogbook(farmId) sin filtros y no muestra controles de filtrado. El criterio de filtrado se reformuló para atribuirlo a la consulta del repositorio, no a la pantalla. 3) PersonDetailScreen se renderiza en test/hierarchical_navigation_test.dart, pero ninguna prueba verifica lo que muestra (chacos, aplicaciones, stock ni estado de cuenta con saldo acumulado), y farmsForPerson() y applications(personId:) no tienen aserciones de valor. 4) Las pruebas de DashboardScreen solo comprueban la tabla y las tarjetas de inventario; no cubren las tarjetas de resumen, las últimas aplicaciones, las deudas principales ni las campañas. 5) docs/evidence/REC_MOBILE_BASELINE.md no existe en este commit (tampoco existe docs/evidence/) y hay que crearlo. El repo tampoco tiene en archivo la evidencia del recorrido de rutas en Pixel 8 que cita el issue.

### #53 REC-017

1) Falta un widget test que pulse 'Cancelar' durante una exportación en curso, por ejemplo con _GatedStorage, y compruebe dos cosas: que aparece el mensaje 'Exportación cancelada. No se guardó ningún archivo.' y que la carpeta reportes/ queda vacía.
2) Faltan los resultados de ejecutar flutter test sobre las cinco rutas en el commit verificado (se rellenarán en {{ORIGEN}}).
3) docs/evidence/REC_MOBILE_BASELINE.md no existe en el worktree; tampoco existe el directorio docs/evidence.
4) Según cap3_refs.md, RF-31 no corresponde al contenido. RF-31 trata de conservar la consulta histórica de campañas y operaciones al finalizar un período, no de exportar en CSV, así que se marca «(verificar)». cap3_refs.md no contiene ningún ID que mencione exportación, CSV o reportes. El mapa no asigna casos de uso ni reglas de negocio.
5) El diálogo de éxito con nombre y carpeta solo se comprueba con PDF; con CSV solo se comprueba la extensión .csv.
6) Opcional: ningún test analiza el CSV con un parser externo (ida y vuelta); el escapado se comprueba por subcadenas.

### #55 REC-019

(1) Identidad y propiedad (RF-26, RF-27, RN-11): el manifiesto que genera export() solo registra application ('agrocuentas'), versiones, createdAt, base y adjuntos, y no asocia la copia a un propietario. _validateContainer solo rechaza una copia "ajena" si es de otra aplicación; no rechaza la de otro agricultor. No hay implementación ni test de ese rechazo. (2) Fallo de generación (RF-26): export() trabaja en una carpeta temporal (agro_backup_stage_) y valida antes de mover al destino, pero ningún test simula un fallo de exportación ni comprueba que una copia válida previa no se sustituya por un artefacto incompleto. (3) El test «restaurar un respaldo de esquema antiguo dispara la migración» (backup_service_test.dart) solo llama a validate() y comprueba schemaVersion 3; no ejecuta restore() ni comprueba la migración. (4) error_states_test, payment_dialog_test y regression_widget_test renderizan SettlementsScreen, pero ninguno ejerce los flujos de exportar o restaurar de la interfaz; InvoiceStorage no tiene test propio. (5) El ciclo físico en dispositivo citado en el issue (docs/46_BASELINE_FINAL_FREEZE.md, que sí existe) es evidencia documental, no automatizada. (6) En esta tarea los tests solo se leyeron, no se ejecutaron, y docs/evidence/REC_MOBILE_BASELINE.md aún no existe en el worktree (no hay carpeta docs/evidence). (7) El HEAD local del worktree es b95d3c3: es el commit 278cbd3 más dos commits que solo tocan documentación (b9ee014 y b95d3c3, en docs/00_INDEX.md y docs/adr/ADR-002-renumeracion-fases.md). git diff 278cbd3 HEAD no muestra cambios en lib/ ni en test/.

### #56 REC-020

1. No hay tests de accesibilidad semántica. Ningún archivo de test/ usa Semantics, semanticLabel ni meetsGuideline: faltan el tamaño de los objetivos táctiles, el contraste y las etiquetas para lectores de pantalla.
2. RNF-07 exige un estudio de usabilidad: éxito de tareas, errores y ayudas, y SUS con umbrales fijados antes de ejecutarlo. No hay ningún artefacto de ese estudio en el repo.
3. El recorrido en el Pixel 8 y los 67 UIBUG verificados son evidencia manual en docs/, por ejemplo docs/45_UI_AUDIT_FINAL_VERIFICATION.md y docs/46_BASELINE_FINAL_FREEZE.md. Ningún test los reproduce.
4. El contrato de descartar cambios (PopScope + confirmDiscard en purchase/transfer/plan/application_form_screen.dart) solo se prueba sobre un harness aislado (test/back_navigation_test.dart). Ningún test lo ejercita sobre las pantallas reales.
5. El archivo de evidencia indicado, docs/evidence/REC_MOBILE_BASELINE.md, no existe todavía. Tampoco existe el directorio docs/evidence/.
6. El issue no dice cuál es la «limitación residual documentada» que menciona el historial.

### #57 REC-021

- Ningún test ni script automatizado comprueba que el workflow conserve los pasos exigidos ni que la versión fijada de Flutter coincida con la baseline.
- La congelación solo se comprueba a mano con git: el tag v1.0.0-base-stable resuelve a bd3289f.
- `docs/46_BASELINE_FINAL_FREEZE.md` no registra el SHA del tag, solo el commit de partida c36e5b7.
- `docs/evidence/REC_MOBILE_BASELINE.md` no existe: el directorio docs/evidence no está en el worktree.
- Falta el resultado de una ejecución local de la suite sobre 278cbd3, que está a cargo de otra tarea. Solo consta la ejecución verde de CI 37231657078.
- Sigue abierta como riesgo histórico la discrepancia entre el SHA del tag y la metadata del merge que señala el issue.
- El worktree está en la rama docs/rebaseline-fases-2026-10-15, en HEAD b95d3c3. Son 278cbd3 más dos commits que solo tocan documentación: b9ee014 y b95d3c3, sobre docs/00_INDEX.md y docs/adr/ADR-002-renumeracion-fases.md. lib/ y test/ son idénticos a 278cbd3.

### #58 REC-022

1) No hay tests automatizados de los adaptadores nativos: AndroidSpeechEngine.kt, WhisperEngine.kt/WhisperLib.kt/whisper_jni.c (Whisper tiny/base), SpeechBridge.kt/PlatformBridge.kt/TranscriptionEngine.kt, ni del puente MethodChannel en lib/port/platform_transcription_port.dart y lib/bench/bench_platform.dart.
2) No hay test de widget de lib/ui/bench_screen.dart.
3) La medición física en POCO X5 Pro API 31 y el gate API 36 (WAIVED_BY_OWNER) solo constan como evidencia documental en docs/evolution/decisions/ADR-002-voice-transcription-engine.md. No son reproducibles por test.
4) El criterio «la decisión conserva limitaciones y evidencia física» se verifica revisando el ADR, no con un test.
5) docs/evidence/REC_MOBILE_BASELINE.md no existe ni en 278cbd3 ni en HEAD b95d3c3 (no hay carpeta docs/evidence). Hay que crearlo.
6) Los tests del paquete benchmark/voice_benchmark exigen un `flutter test` aparte desde ese directorio; la suite raíz no los incluye. Ninguno se ejecutó en esta tarea.
7) Trazabilidad: RF-29 trata de efectos de negocio antes de la confirmación y DAT-17 de los borradores de voz, y el banco no genera borradores ni operaciones. Solo lo respaldan indirectamente los tests de aislamiento («medir no toca nada fuera de memoria» y la ausencia de imports de Agrocuentas/SQLite). Por eso los conservo con «(verificar)».

### #59 REC-024

Para Verified faltan estos puntos:

1. Traer a main con un PR el código híbrido de la rama evolution/evolution-3-hybrid-voice-benchmark (d5edbc9):
   - hybrid_comparison.dart, candidates.dart, corpus_catalog.dart, native_alignment.dart y sha256.dart;
   - tool/voice_benchmark/comparison_guard.dart y los cambios en aggregator, report, result_parser y main;
   - los motores Vosk/Whisper de las variantes voskCommon, whisperOnly y hybrid;
   - sus pruebas: benchmark/voice_benchmark/test/hybrid_comparison_test.dart, hybrid_corpus_test.dart, native_alignment_test.dart, quality_flags_test.dart, corpus_selector_test.dart y sha256_test.dart, test/voice_benchmark_comparison_guard_test.dart y la versión ampliada de test/voice_benchmark_report_test.dart.
2. Recuperar el commit local 201886c y publicar EVOLUTION-3_HYBRID_C1_C3_POCO_RESULTS.md con la decisión NO_GO_C4. No está en ninguna rama del remoto, y los documentos de la rama todavía dicen «C4 pendiente».
3. Incorporar a main ADR-004 (Proposed) y EVOLUTION-3_HYBRID_16KB_GATE_EVIDENCE.md.
4. Añadir una prueba que verifique que NO_GO_C4 se emite sin exigir que C3 pase. Hoy no existe en ninguna rama.
5. Crear docs/evidence/REC_MOBILE_BASELINE.md: todavía no existe en main ni hay carpeta docs/evidence.
6. Quedan pendientes como trabajo Live: HONOR NOT_MEASURED, el holdout expuesto y la resolución de ADR-004.
7. Verificar si corresponden RF-29 y DAT-17. Tratan de confirmación y borrador de negocio, y el benchmark es una herramienta de desarrollo sin efectos de negocio.


## F03 — MOB #18 (cliente HTTP y autenticación)

- `test/auth_v2_api_test.dart`: 20/20 OK
- `test/remote_session_coordinator_test.dart`: 52/52 OK
- `test/first_activation_screen_test.dart`: 28/28 OK

Cubre: test/auth_v2_api_test.dart es el único archivo dedicado al alcance de #18. Tiene 20 casos con MockClient y comprueba lib/services/auth/{api_endpoint_config,auth_http_client,auth_v2_api,auth_v2_models,auth_api_exception}.dart:
(1) ApiEndpointConfig acepta solo un origen HTTPS: rechaza http, userInfo, ruta base, query, fragmento y puerto 0, sin repetir el valor recibido en el error.
(2) Las seis rutas V2 se resuelven exactamente: login, clients, session/client, me, refresh y logout.
(3) Se rechazan URL absoluta, autoridad externa con //, traversal en claro o codificado (%2e%2e, %2f), query/fragmento, rutas fuera de alcance, barra final y %6cogin.
(4) Las seis operaciones envían followRedirects=false; 302, 303 y 307 se rechazan sin exponer Location ni secretos y sin un segundo envío, tanto vía AuthV2Api como vía AuthHttpClient.
(5) Login serializa {email,password,refreshTransport:BODY} sin cookie ni authorization y parsea la respuesta tipada; toString queda redactado.
(6) registerClient, bindSessionClient y currentContext usan las rutas, los métodos, Bearer y los DTO exactos.
(7) Refresh y logout son contratos BODY sin estado, incluido logout sin credencial (204).
(8) Los HTTP 400/401/409/429/500 se mapean a categorías seguras, solo en login.
(9) Un fallo de conexión da network y un timeout da timeout, ambos sin filtrar secretos.
(10) Se rechazan JSON inválido, UTF-8 inválido, campos faltantes, refreshTransport COOKIE, refreshToken null y contexto incompleto.
(11) Un 401 remoto deja intacto un dato SQLite local (AppDatabase con sqflite_ffi).
En el código hay además `<uses-permission android:name="android.permission.INTERNET"/>` en android/app/src/main/AndroidManifest.xml. La trazabilidad Cap. III v1.5 de lo cubierto es RF-01 (parcial: contrato de identidad), CU-01/CU-02 (capa base), INT-04, RNF-11 (HTTPS sin texto plano ni secretos en errores) y RNF-09.

No cubre: (a) No hay ningún archivo de evidencia en docs/evidence/: el directorio no existe en 278cbd3. Lo más cercano es docs/evolution/features/F03_MOB_AUTH_01_HTTP_FOUNDATION.md. Ese documento cita comandos y resultados locales (20/20 auth, 539/539 suite, analyze, build release), pero solo da el SHA base (main@9e9cb23…), no el SHA del HEAD medido ni la fecha de ejecución. Tampoco recoge la salida literal, y la CI queda remitida «por separado».
(b) Los códigos 403→forbidden y 404→notFound están en lib/services/auth/auth_v2_api.dart:88-89, pero test/auth_v2_api_test.dart no los prueba. Solo aparecen de forma indirecta en first_activation_screen_test.dart (403) y remote_session_coordinator_test.dart (404), que pertenecen a #19/#22.
(c) El mapeo de errores HTTP solo se prueba sobre login. No se prueba en register, bind, me, refresh ni logout.
(d) ApiEndpointConfig.fromEnvironment (AGRO_API_BASE_URL ausente o inválida) no tiene test.
(e) Ningún test comprueba el permiso INTERNET ni el build release; según el documento se revisaron con aapt, fuera de la suite.
(f) E2E_MOBILE_BACKEND y F03_DEVICE quedan como NOT_MEASURED: MockClient no demuestra red real, TLS en dispositivo ni 401/429 reales.
(g) Quedan fuera del alcance de #18 el almacenamiento seguro (#20, secure_session_store_test.dart), el refresh y la reautenticación (#22, refresh_guard_test.dart y remote_session_coordinator_test.dart), la UI de activación (#19) y la apertura offline (#21).

Evidence: **Partial**.

## Estado posterior en `main` (nota añadida el 2026-10-17)

Lo de arriba se registró el 2026-10-15 sobre `278cbd3` y **no se reescribe**. La sesión A añade esta nota antes de integrar el archivo.

- **El recuento de 690 pruebas** coincide con la CI independiente 37231657078 sobre `278cbd3` («690 tests passed»). Los 56 del banco de voz los ejecutó localmente esa sesión; la CI no corre ese subpaquete.
- **Las listas «Pendiente por REC» se escribieron al revisar un worktree sin `docs/evidence/`.** Por eso repiten que este archivo «no existe en el worktree»: ese punto queda resuelto al integrarlo.
- **El marcador `{{ORIGEN}}` (#53, punto 2)** es una plantilla que no se rellenó. Los resultados de esas rutas son los de la corrida completa de arriba (690 pruebas, 0 fallos); se deja como estaba para no alterar el registro.

**Resuelto después del 2026-10-15, en `main`:**

| REC | Punto de arriba | Resolución |
|---|---|---|
| #48 | 2: `reverseTransfer` multiproducto con el producto de la cabecera | F04-BUG-01, PR #75, merge `905e67c` (`F04_BUG_01.md`) |
| #48 | 7: transferencias no limitadas al modo compartido | El repositorio las rechaza en propio desde #77. La interfaz las oculta desde #102 (merge `cf3d510`; `F04-MODE-03_flujos_modo_personal.md`) |
| #50 | Revertir la compra tras revertir su transferencia (hallazgo) | F04-BUG-02, PR #79, merge `505c230` (`F04_BUG_02.md`, que incluye «la compra se revierte una sola vez») |
| #55 | 1: identidad y propiedad de la copia | Restauración protegida que comprueba Member y tenant antes de sustituir: `812fe49` (#78), `F04_CORRECCIONES_REVISION.md` parte B. En el teléfono: `F10_RESTORE_DEVICE.md`, caso C |
| #55 | 2: un fallo de exportación no deja artefacto ni sustituye la copia válida | `6c6a1a2` (#90), `F08_MOBILE_RESTORE.md` §1 |

**Sigue pendiente**, sin cambio respecto de arriba: el resto de cada lista, y en #55 el punto 3 (restaurar de verdad un esquema antiguo y comprobar la migración).

