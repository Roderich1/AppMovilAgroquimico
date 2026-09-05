# 39 — Trazabilidad de la auditoría de interfaz


> **Estado del backlog (2026-09-05).** Los defectos de este documento se han corregido en su mayor parte: **38 `VERIFIED`** en Pixel 8, **16** corregidos y cubiertos por tests, **9** MEDIUM/LOW abiertos con justificación, **2** pendientes de decisión de producto y **1** `WONT_FIX`. Este documento conserva la **observación original**; el estado vigente está en [`43_UIBUG_FIX_TRACEABILITY.md`](43_UIBUG_FIX_TRACEABILITY.md) y el cierre en [`45_UI_AUDIT_FINAL_VERIFICATION.md`](45_UI_AUDIT_FINAL_VERIFICATION.md).

Cada UIBUG enlazado con la pantalla donde se observó, la funcionalidad y la regla de negocio
afectadas, la evidencia capturada, los archivos probablemente implicados y su estado.

Todas las rutas de evidencia son relativas a `artifacts/ui-audit/`.
Todos los hallazgos están en estado **OPEN**: en esta fase **no se corrigió ninguno**.

## Conteo

| Severidad | IDs | Nº |
|---|---|---:|
| CRITICAL | 001–004 | 4 |
| HIGH | 005–021 | 17 |
| MEDIUM | 022–056 | **35** |
| LOW | 057–065 | 9 |
| **Total** | **001–065** | **65** |

Coincide con `38` y `40`. Con la subdivisión de `UIBUG-004` (ver abajo) el backlog vigente
tiene **66 entradas** sobre estos **65 IDs**. Ninguna evidencia referenciada falta:
108 referencias a PNG, **0 rotas**, 119 archivos en `artifacts/ui-audit/`.

> **Backlog vigente**: [41_UIBUG_MASTER_BACKLOG.md](41_UIBUG_MASTER_BACKLOG.md).
> Seguimiento de la corrección: [43_UIBUG_FIX_TRACEABILITY.md](43_UIBUG_FIX_TRACEABILITY.md).

## Tabla maestra

| UIBUG | Sev. | Categoría | Pantalla · Ruta | Feature | Regla / doc | Evidencia | Archivo probable |
|---|---|---|---|---|---|---|---|
| 001 | CRITICAL | FUNCTIONAL | UI-10 · `/liquidacion` | F-16 Exportación de backup | STAB-007 · `13_LOCAL_STORAGE` | `UI-10-liquidacion/UI-10-exportar-backup.png` | `data/backup_service.dart:63` |
| 002 | CRITICAL | NAVIGATION | UI-06 · `/compras` | F-04, F-05, F-06, F-12 | `07_SCREENS` P-06 · `08_NAVIGATION` | enumeración de rutas en `38` | `app.dart:63`, `app_shell.dart`, `operations_screen.dart` |
| 003 | CRITICAL | DATA | UI-17, UI-10 y todo campo numérico | F-09, F-10 | RN-50 · `16_VALIDATIONS` | `UI-17-transfer-form/UI-17-ISSUE-formato-millares.png`, `_c-conf.png` | `widgets/common.dart:132`, `domain/money.dart` |
| **004A** | CRITICAL | NAVIGATION | UI-13/14/12/15 y subrutas de Operaciones (**jerárquica**) | — | `08_NAVIGATION` · STAB-001 | `UI-14-persona-detalle/UI-14-ISSUE-back-desde-detalle.png` | `app_shell.dart`, `widgets/common.dart` (`PageFrame`), `persons_screen.dart`, `inventory_screen.dart`, `person_detail_screen.dart`, `dashboard_screen.dart`, `operations_screen.dart` |
| **004B** | MEDIUM | NAVIGATION | los 5 destinos **raíz** | — | `08_NAVIGATION` | `UI-02-operaciones/UI-02-ISSUE-back-sale-de-la-app.png` | `app_shell.dart:56,83`, `app.dart` |
| 005 | HIGH | FUNCTIONAL | UI-10 · `/liquidacion` | F-10 Cuentas y pagos | — | `UI-10-ISSUE-pago-vacio.png`, `UI-10-pago-valido.png`, `UI-10-pago-en-PROFILE-sin-asserts.png` | `settlements_screen.dart:71,98` |
| 006 | HIGH | LAYOUT | UI-05, UI-07, UI-09, UI-17 | F-17 Selector adaptativo | — | `UI-05-plan-form/UI-05-ISSUE-etiqueta-superpuesta.png` | `widgets/adaptive_entity_picker.dart:76,100` |
| 007 | HIGH | FUNCTIONAL | UI-01 · `/` | F-15 Dashboard | KI-17 (estado vacío) | `UI-01-dashboard/UI-01-busqueda-resultado.png` | `dashboard_screen.dart` |
| 008 | HIGH | LAYOUT | UI-01, 03, 08, 10, 11, 16 | — | — | `UI-01-ISSUE-fab-tapa-ultima-fila.png`, `UI-03-ISSUE-ultimo-item-inalcanzable.png` | `app_shell.dart`, `widgets/common.dart` |
| 009 | HIGH | LAYOUT/FORM | UI-01 · `/` | F-15 | — | `UI-01-dashboard/UI-01-busqueda-teclado.png` | `app_shell.dart`, `dashboard_screen.dart` |
| 010 | HIGH | DATA | UI-08, UI-01 | F-12 Reversiones | RN de reversión · `15_BUSINESS_RULES` | `UI-02-registrar-aplicacion-destino.png`, `UI-01-scroll1.png` | `applications_screen.dart`, `dashboard_screen.dart`, `agro_repository.dart` |
| 011 | HIGH | UX | UI-07 · `/compras/nueva` | F-04 | — | `UI-07-purchase-form/UI-07-confirmada.png` | `operations_screen.dart`, `app_shell.dart` |
| 012 | HIGH | UX/DATA | UI-10 · `/liquidacion` | F-10 | — | `UI-10-dialogo-registrar-pago.png` | `settlements_screen.dart` |
| 013 | HIGH | CONSISTENCY | UI-10, UI-13, diálogo | F-10, F-11 | — | `UI-10-lista.png`, `UI-10-estado-de-cuenta.png`, `UI-13-lista.png` | `settlements_screen.dart`, `persons_screen.dart`, `agro_repository.dart` |
| 014 | HIGH | UX | UI-10 · `/liquidacion` | F-10 | — | `UI-10-pago-en-PROFILE-sin-asserts.png` | `settlements_screen.dart` |
| 015 | HIGH | ERROR_HANDLING | UI-10 · `/liquidacion` | F-16 | **KI-16** `DatabaseException` sin traducir | `UI-10-exportar-backup.png` | `widgets/common.dart:150` |
| 016 | HIGH | TEXT | UI-03, UI-07, UI-14, UI-10 | F-01, F-02, F-04, F-11 | — | `UI-03-menu-campana.png`, `UI-07-picker-persona2.png` | `catalogs_screen.dart`, `purchase_form_screen.dart`, `person_detail_screen.dart` |
| 017 | HIGH | ACCESSIBILITY | Global (peor en UI-10) | — | — | `UI-23-fontscale/UI-23-liquidacion-130.png` | `settlements_screen.dart`, `app_shell.dart` |
| 018 | HIGH | SCROLL | UI-03 · `/catalogos` | F-01 | — | `UI-03-ISSUE-ultimo-item-inalcanzable.png` | `catalogs_screen.dart` |
| 019 | HIGH | FUNCTIONAL | Selectores + buscadores | F-17 | — | `UI-05-ISSUE-busqueda-sin-tildes.png` | `adaptive_entity_picker.dart`, pantallas con buscador |
| 020 | HIGH | LAYOUT | UI-10 · `/liquidacion` | F-10 | — | `UI-10-lista.png` | `settlements_screen.dart` |
| 021 | HIGH | LAYOUT/TEXT | UI-10 (diálogo) | F-11 | — | `UI-10-estado-de-cuenta.png` | `settlements_screen.dart` |
| 022 | MEDIUM | LAYOUT | UI-01 · `/` | F-15 | — | `UI-01-inicio.png` | `dashboard_screen.dart:235` |
| 023 | MEDIUM | SCROLL | UI-01 · `/` | F-15 | — | `UI-01-tabla-scroll-horizontal.png` | `dashboard_screen.dart` |
| 024 | MEDIUM | TEXT | UI-10, UI-13, UI-15, UI-04 | F-13, F-14 | KI (formato de superficie) | `UI-10-ISSUE-mezcla-separadores.png` | `settlements_screen.dart`, `persons_screen.dart`, `farm_logbook_screen.dart:70` |
| 025 | MEDIUM | TEXT | UI-08, UI-16 | F-08, F-09 | — | `UI-08-aplicaciones/_zoom-cantidad.png` | `agro_repository.dart` (`GROUP_CONCAT`) |
| 026 | MEDIUM | DATA | UI-15 · `/chacos/:id` | F-14 Bitácora | RN de trazabilidad FIFO | `UI-15-ISSUE-fifo-crudo.png` | `farm_logbook_screen.dart:70` |
| 027 | MEDIUM | TEXT | UI-14, UI-15, UI-10 | F-11, F-14 | — | `UI-15-entrada-expandida.png` | varias pantallas |
| 028 | MEDIUM | DATA | UI-14 · `/personas/:id` | F-11 | — | `UI-14-ISSUE-pestana-cuenta-inalcanzable.png` | `person_detail_screen.dart` |
| 029 | MEDIUM | NAVIGATION | UI-14 · `/personas/:id` | — | `07_SCREENS` P-14 | `UI-14-ISSUE-tabbar-recortado.png` | `person_detail_screen.dart` |
| 030 | MEDIUM | LAYOUT | UI-14 · `/personas/:id` | — | `07_SCREENS` P-14 (480 px fijos) | `UI-15-pestana-chacos.png` | `person_detail_screen.dart` |
| 031 | MEDIUM | VALIDATION | UI-03 · `/catalogos` | F-01 | `16_VALIDATIONS` | `UI-03-catalogos/_crop-guardar-vacio.png` | `catalogs_screen.dart` |
| 032 | MEDIUM | TEXT | UI-05 · `/planificacion/nueva` | F-03 | `16_VALIDATIONS` | `_c-UI-05-guardar-sin-productos.png` | `plan_form_screen.dart` |
| 033 | MEDIUM | UX | UI-05, 07, 09, 17 | — | STAB-010 (criterio de acción destructiva) | `_c-UI-05-descartar-cambios.png` | los 4 formularios |
| 034 | MEDIUM | FORM | UI-17 · `/transferencias/nueva` | F-09 | — | `UI-17-transfer-form/_zoom-cero.png` | `transfer_form_screen.dart` |
| 035 | MEDIUM | FORM/SCROLL | Selectores | F-17 | — | `UI-05-picker-chaco.png` | `adaptive_entity_picker.dart` |
| 036 | MEDIUM | LAYOUT | Selectores | F-17 | — | `UI-05-plan-form/_crop-sinres.png` | `adaptive_entity_picker.dart` |
| 037 | MEDIUM | TEXT | UI-07 · `/compras/nueva` | F-04 | — | `UI-07-ISSUE-precio-sin-unidad.png` | `purchase_form_screen.dart` |
| 038 | MEDIUM | FORM | UI-07 · `/compras/nueva` | F-04 | RN de asignación | `UI-07-ISSUE-asignacion-sin-etiqueta.png` | `purchase_form_screen.dart` |
| 039 | MEDIUM | TEXT/DATA | UI-07 · `/compras/nueva` | F-04 | — | `UI-07-teclado-campo-inferior.png` | `purchase_form_screen.dart` |
| 040 | MEDIUM | LAYOUT | UI-07 · `/compras/nueva` | F-04 | — | `UI-07-factura-con-teclado.png` | `purchase_form_screen.dart` |
| 041 | MEDIUM | LAYOUT | UI-07 · `/compras/nueva` | F-04 | — | `UI-07-ISSUE-etiqueta-producto-recortada.png` | `purchase_form_screen.dart` |
| 042 | MEDIUM | UX | UI-09 · `/aplicaciones/nueva` | F-08 | — | `UI-09-linea-producto.png` | `application_form_screen.dart` |
| 043 | MEDIUM | UX/FORM | UI-09 · `/aplicaciones/nueva` | F-08 | — | `UI-09-application-form/_c-fila.png`, `_c-fila1.png` | `application_form_screen.dart:467` |
| 044 | MEDIUM | UX | UI-09 · `/aplicaciones/nueva` | F-08 | RN de stock suficiente | `UI-09-application-form/_c-val.png` | `application_form_screen.dart` |
| 045 | MEDIUM | DATA | UI-04 · `/planificacion` | F-03 | RN de plan | `UI-04-lista.png` | `planning_screen.dart`, `agro_repository.dart` |
| 046 | MEDIUM | UX | UI-04 · `/planificacion` | F-03 | — | `UI-04-plan-expandido.png` | `planning_screen.dart` |
| 047 | MEDIUM | UX | UI-03 · `/catalogos` | F-01 | — | `UI-03-personas.png` | `catalogs_screen.dart`, `app_shell.dart` |
| 048 | MEDIUM | DATA | UI-03 · `/catalogos` | F-02 | — | `UI-03-menu-campana.png` | `catalogs_screen.dart` |
| 049 | MEDIUM | UX/TEXT | UI-10 · `/liquidacion` | F-16 | — | `UI-10-menu-backup.png` | `settlements_screen.dart` |
| 050 | MEDIUM | UX | UI-10 · `/liquidacion` | F-16 | — | `UI-10-restaurar-backup.png` | `settlements_screen.dart` |
| 051 | MEDIUM | UX/NAVIGATION | UI-02 · `/operaciones` | — | `08_NAVIGATION` | `UI-02-registrar-aplicacion-destino.png` | `operations_screen.dart` |
| 052 | MEDIUM | UX | UI-13 · `/personas` | — | KI-17 | `UI-13-lista.png` | `persons_screen.dart` |
| 053 | MEDIUM | DATA/UX | UI-16 · `/transferencias` | F-09 | — | `UI-16-lista.png` | `transfers_screen.dart` |
| 054 | MEDIUM | CONSISTENCY | UI-17 · `/transferencias/nueva` | F-09, F-17 | — | `UI-17-picker-origen.png`, `UI-17-picker-destino.png` | `transfer_form_screen.dart`, `purchase_form_screen.dart` |
| 055 | MEDIUM | SCROLL | UI-17 · `/transferencias/nueva` | F-09 | `07_SCREENS` P-17 (48 % de alto) | `UI-17-productos-disponibles.png` | `transfer_form_screen.dart` |
| 056 | MEDIUM | TEXT | UI-11 · `/inventario` | F-07 | — | `UI-11-lista.png` | `domain/money.dart` (`#,##0.###`) |
| 057 | LOW | UX | UI-13 · `/personas` | — | — | `UI-13-lista.png` | `persons_screen.dart` |
| 058 | LOW | UX | UI-10 (diálogo) | F-11 | — | `UI-10-estado-de-cuenta.png` | `settlements_screen.dart` |
| 059 | LOW | UX | UI-03 · `/catalogos` | F-02 | KI-18 | `UI-03-menu-campana.png` | `catalogs_screen.dart` |
| 060 | LOW | UX | UI-17 · `/transferencias/nueva` | F-09 | — | `UI-17-inicial.png` | `transfer_form_screen.dart` |
| 061 | LOW | LAYOUT | Selectores | F-17 | — | `UI-07-picker-proveedor.png` | `adaptive_entity_picker.dart` |
| 062 | LOW | NAVIGATION | UI-15 · `/chacos/:id` | F-14 | `08_NAVIGATION` (índice por defecto 0) | `UI-15-entrada-expandida.png` | `app_shell.dart` |
| 063 | LOW | ACCESSIBILITY | Global horizontal | — | `08_NAVIGATION` (umbral 1150 px) | `UI-22-horizontal-bitacora.png` | `app_shell.dart` |
| 064 | LOW | LAYOUT | UI-07 · `/compras/nueva` | F-04 | — | `UI-07-purchase-form/_c-confirmar.png` | `purchase_form_screen.dart` |
| 065 | LOW | ERROR_HANDLING | UI-10 · `/liquidacion` | F-10 | `17_ERROR_HANDLING` | — (revisión de código) | `settlements_screen.dart:89` |

## Relación con hallazgos ya registrados

| Hallazgo previo | Qué aporta esta auditoría |
|---|---|
| **KI-16** `DatabaseException` sin traducir | **Reproducido en dispositivo** → UIBUG-015 |
| **KI-17** Sin estado vacío en varias listas | Confirmado y agravado: el estado vacío del inicio **miente** → UIBUG-007 |
| **KI-18** `archiveCatalog` de campañas inalcanzable | Relacionado con UIBUG-059 (se ofrece Activar sobre una campaña cerrada) |
| **STAB-001** Navegación `go` vs `push` | Corregida solo la vía al formulario de compra; el problema de fondo (Atrás sale de la app) sigue → UIBUG-004 |
| **STAB-005** Reportes con productos en cero | ✅ **Verificado en dispositivo**: los productos sin consumo aparecen en cero |
| **STAB-007** Backup y restauración | La restauración existe pero es inútil: la exportación falla en Android → UIBUG-001 |
| **STAB-010** Confirmación de acciones destructivas | ✅ **Verificado en dispositivo**: el diálogo es correcto y completo |
| **STAB-019** "dirty" espurio del formulario de compra | **NO REPRODUCIBLE** con datos realistas (ver `38`, sección final) |
| **E-01** `friendlyError` no traduce `DatabaseException` | = UIBUG-015 |
| **P-01** `Future` creado en `build()` | No se observó parpadeo atribuible en el uso normal; no se convierte en UIBUG |

## Hallazgos que cruzan varias pantallas

Estos defectos tienen **una sola causa** pero se manifiestan en muchos sitios. Corregir la causa
cierra todas las manifestaciones:

| Causa única | UIBUG | Pantallas afectadas |
|---|---|---|
| `isEmpty: selected == null` en el selector (`adaptive_entity_picker.dart:78`) | 006 | 4 formularios |
| `context.go` en navegación **jerárquica** + `PageFrame` sin `AppBar` | 004A | 3 detalles + 4 subrutas de Operaciones |
| `context.go` entre destinos **raíz** (por diseño; política a decidir) | 004B | 5 destinos raíz |
| `tryParseDecimal` trata el punto como decimal (`common.dart:131`) | 003, 034, 065 | todos los campos numéricos |
| `PageFrame` cierra con 24 px bajo un FAB extendido (`common.dart:52`) | 008, 009 | 6 pantallas |
| Contenedores de **alto fijo** (`catalogs:264` 520 px · `person_detail:72` 480 px · `transfer_form:296` 48 %) | 018, 030, 055 | 3 pantallas |
| Rutas **fuera del `ShellRoute` sin `SafeArea`** | 064 | `/compras/nueva` |
| Resúmenes construidos en SQL (`agro_repository.dart:1070,1072,1191`) | 025 | 2 pantallas |
| Enums sin traducir + `COALESCE(..., t.type) concept` (`agro_repository.dart:1559`) | 016 | 4 pantallas |
| Superficies sin `NumberFormat` (`area_m2 / 10000` crudo) | 024 | 8 sitios en 5 pantallas |
| `toLowerCase().contains` sin normalizar diacríticos | 019 | 6 pantallas + selector |

> **Correcciones a esta tabla (2026-09-05), verificadas en código:**
>
> - **064 sale del grupo del FAB.** `/compras/nueva` está **fuera del `ShellRoute` y por tanto
>   no tiene FAB**. La causa real es la ausencia de `SafeArea`: recuento verificado por
>   formulario — `purchase_form_screen.dart` **0**, `application_form_screen.dart` 2,
>   `plan_form_screen.dart` 2, `transfer_form_screen.dart` 2. Es el único sin ella.
> - **018 se separa de 008.** Comparten la captura de Catálogos pero tienen causas distintas
>   (alto fijo de 520 px vs. relleno bajo el FAB): **corregir una no cierra la otra**.
>   No son duplicados; están marcados como *solapamiento* en `41` §5.
> - **004 se divide** en 004A y 004B (ver tabla maestra y `41` §3).
>
> Agrupación completa por causa raíz —16 grupos que cubren los 66 hallazgos— en
> [`41` §6](41_UIBUG_MASTER_BACKLOG.md).
