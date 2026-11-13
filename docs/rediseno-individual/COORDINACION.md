# Modo individual — coordinación

Encargo del autor del 2026-11-13: vistas del **modo individual** (`OperationMode.personal`) a partir de las 28 láminas «Agrocuentas — Rediseño de pantallas clave» (I-01…I-53). Sin push, PR, fusión a main, despliegue ni cambios en la DEMO.

## Ramas y worktrees

| Papel | Worktree | Rama | Base |
|---|---|---|---|
| Orquestador (integración) | `_wt/IND-INT` | `feat/modo-individual` | `507efc8` (`feat/rediseno-movil`, código `b5df71d`) + base común |
| Sesión A — Operaciones y voz | `_wt/IND-A` | `feat/modo-individual-a` | base común |
| Sesión B — Almacén y actividad | `_wt/IND-B` | `feat/modo-individual-b` | base común |
| Sesión C — Chacos y costos | `_wt/IND-C` | `feat/modo-individual-c` | base común |
| Externa: permisos/consentimiento/K=3 (`proyectoagro-cb`) | `_wt/ACC-MOB` | `feat/acceso-rol-sin-k-mob` | `507efc8` |

Base común: ver `git log` de `feat/modo-individual` (commit «base común»). Láminas (no versionadas): `ProyectoAgro/_artefactos/modo_individual/laminas/I-NN.png`.

## Propietario único por archivo

Un archivo sólo lo edita su propietario. Si otra sesión necesita un cambio, lo pide al orquestador (que reasigna aquí **antes** de que se edite). Los archivos nuevos van con prefijo `ind_<a|b|c>_`.

| Propietario | Archivos |
|---|---|
| ORQ | `lib/app.dart`, `lib/presentation/app_shell.dart`, `lib/operation_mode_controller.dart`, `dashboard_screen.dart`, `register_sheet.dart`, `more_screen.dart`, `operation_mode_screen.dart`, `owner_setup_screen.dart`, `widgets/agro_ui.dart`, `widgets/common.dart`, `theme/**`, `widgets/mode_notice.dart`, `widgets/sync_status_banner.dart`, `lib/data/agro_repository.dart` y `lib/domain/**` (fuera de `domain/sync`), `pubspec.*` |
| A | `purchase_form_screen.dart`, `purchase_form_voice.dart`, `application_form_screen.dart`, `application_form_voice.dart`, `plan_form_screen.dart`, `plan_form_voice.dart`, `applications_screen.dart`, `planning_screen.dart`, `widgets/provider_payment_fields.dart`, `widgets/rdm_a_list.dart`, `widgets/label_photo_sheet.dart`, `lib/presentation/voice/**`, `lib/voice/**`, `lib/voice_draft/**`, `test/support/purchase_form_driver.dart` |
| B | `inventory_screen.dart`, `inventory_detail_screen.dart`, `inventory_alerts_screen.dart`, `estimation_screen.dart`, `operations_screen.dart`, `purchases_screen.dart`, `purchase_detail_screen.dart`, `transfers_screen.dart`, `transfer_form_screen.dart`, `widgets/rdm_b_ui.dart`, `widgets/rdm_b_purchase_actions.dart`, `widgets/rdm2_b_lotes.dart`, `widgets/application_expiry_notice.dart` |
| C | `ind_chacos_screen.dart`, `farm_logbook_screen.dart`, `catalogs_screen.dart`, `widgets/catalog_dialogs.dart`, `campaigns_screen.dart`, `widgets/campaign_actions.dart`, `persons_screen.dart`, `person_detail_screen.dart`, `settlements_screen.dart`, `widgets/rdm_a_people.dart`, `widgets/rdm_a_payment.dart`, `widgets/rdm2_c_*.dart`, `widgets/account_statement_view.dart`, `lib/domain/reports/**`, `lib/services/reports/**` |
| Reservado `proyectoagro-cb` | `union_screen.dart`, `joint_purchase*_screen.dart`, `widgets/joint_purchase_*.dart`, `widgets/rdm_c_joint.dart`, `widgets/rdm_c_identification.dart`, `widgets/identification_texts.dart`, `central_binding_screen.dart`, `declared_needs_screen.dart`, `consumption_publish_screen.dart`, `lib/data/sync/**`, `lib/services/sync/**`, `lib/domain/sync/**`; textos de consentimiento, K=3 y versión mínima |
| Cruces pendientes con `proyectoagro-cb` | `inventory_screen.dart` (B), `purchase_form_screen.dart` (A), `reports_screen.dart` (C), `sync_status_screen.dart` (ORQ), `app.dart` (ORQ): `cb` avisará funciones/líneas antes de tocarlas; si es sólo texto de K=3, lo aplica el propietario con el texto que pase `cb`. |

`widgets/rdm_c_page.dart` (de la sesión C del rediseño anterior): se usa sin editar; si hace falta, lo pide al ORQ.

## Reglas de trabajo

- **Pruebas:** sólo focalizadas, siempre con el candado común: `bash /c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro/_artefactos/modo_individual/ftest.sh test <archivos>` (y `… analyze <rutas>`). Nada de suite completa, APK, Gradle ni emulador en las sesiones: lo hace el ORQ.
- **Capturas:** arnés con fuentes reales (`tool/rediseno/capturas_ind_<x>_test.dart`, patrón de `capturas_rdm2_*`) a 1,0/1,3/2,0 y 900 dp; salida en `docs/evidence/rediseno-individual/2026-11-13/<x>/`.
- **Modo con varias personas:** no se borran pantallas, tablas ni funciones; cada cambio de presentación se condiciona al modo y lleva una prueba de que el modo compartido no cambió.
- **Reglas en el repositorio:** el titular implícito ya se valida al guardar (`_readWriteContext`, `_requireOwnerInPersonal`, `_requireOwnerFarmInPersonal`, `_rejectTransferInPersonal` en `agro_repository.dart`). No se añade otra bandera ni otro titular.
- **Commits:** identidad git de Roderich1, sin trailers `Co-Authored-By` ni «Generated with». Entregas con `docs/rediseno-individual/estado/<X>.md` (commits, archivos, láminas, pruebas, capturas, diferencias, pendientes).

## Servicios y emulador

- Emulador: `RDM_Pixel8` (`emulator-5556`), del ORQ. Paquete propio `.ind`; la instalación `.rdm` (modo con varias personas) no se toca.
- API/PG del ORQ, si hacen falta: 3390 / 15438 (sintéticos). No tocar 3350, 5177, 5175, 15434 (`proyectoagro-cb`).

## Entregas y revisiones

| Fecha | Sesión | Commit | Resultado de la revisión |
|---|---|---|---|
| 2026-11-13 | ORQ | `cfaadc6`, `2796943` | Inicio I-01/I-02, Registrar I-03, Ajustes I-50, Modo I-51/I-52, envíos I-53; `ind_orq_test` 11/11; capturas `orq/`. |
| 2026-11-13 | C | `64ce789` → merge `652889d` | Revisada: lista, detalle, costos y vacío según láminas; Bs/ha sobre `farms.area_m2`, «No disponible» sin cero. Peticiones aplicadas en `727f819` (ruta `/chacos/costos`, sin flotante en Chacos sólo en modo individual). |
| 2026-11-13 | A | `b563eef` → merge `025d32e` | Revisada: compra sin destinatario, revisión con saldo al proveedor, aplicación «Sale de su almacén», plan con revisión, voz Escuchando/Procesando/Cancelar. Pendiente del autor: ¿mismo panel de voz en el modo con varias personas? |
| 2026-11-13 | B | `6f9d0e0` → merge `a4a2c76` | Revisada: Almacén sin persona, detalle, Actividad sin repetir titular, Proveedores con «Pagar» (efecto en `provider_payments`, sin `account_transactions`). Peticiones aplicadas en `1f46a9c` (ruta `/proveedores`, textos de `mode_notice`). P-3 (id del titular en movimientos) no aplicada: comparación por nombre declarada. |
| 2026-11-13 | ORQ | `1f46a9c` | Mensajes del repositorio y almacenes con «modo individual»; `flutter analyze` sin avisos; suite completa en curso. |

## Reasignaciones

- Tras cerrar cada sesión, sus archivos pasan al ORQ para la integración (p. ej. `ind_c_chaco_costs_screen.dart`: `openIndCCosts` usa ya la ruta).
