# Rediseño móvil: segunda ronda de correcciones (revisión del autor del 2026-11-12)

Lo edita sólo el orquestador. Esta ronda prevalece sobre la tabla de `COORDINACION.md` (las sesiones A/B/C anteriores y sus worktrees `_wt/RDM-A|B|C` no participan). Las reglas funcionales de `COORDINACION.md` siguen vigentes, salvo donde el autor las cambió en esta revisión (abajo).

## Base y ramas

- **Base:** `77deb95` (`feat/rediseno-movil`; código instalado `fc12123`). Árbol limpio, comprobado el 2026-11-12.
- **Orquestador:** `_wt/RDM-MOB`, `feat/rediseno-movil` (integración, emulador `emulator-5556`, API 3370, `_wt/RDM-BE`).
- **A:** `_wt/RDM2-A`, `feat/rdm-correcciones-a`. **B:** `_wt/RDM2-B`, `feat/rdm-correcciones-b`. **C:** `_wt/RDM2-C`, `feat/rdm-correcciones-c`.

## Archivos exclusivos

Rutas bajo `lib/presentation/` salvo indicación. Nadie edita archivos de otro. Pruebas nuevas: `test/rdm2_<a|b|c>_*.dart`; ayudantes `test/support_rdm2/<a|b|c>_*.dart`; capturas `tool/rediseno/capturas_rdm2_<a|b|c>_test.dart`. Una sesión puede adaptar pruebas existentes que rompan sus cambios (cómo se llega o un texto renombrado, nunca lo que se comprueba) y lo declara.

| Sesión | Alcance | Archivos |
|---|---|---|
| **A** | Hoja de producto de Compra (fondo, capa, teclado, letra) y lotes en la entrada de la compra | `screens/purchase_form_screen.dart`; la clase `InPageSheet` de `widgets/agro_ui.dart` (sólo esa clase, sólo en esta ronda: sólo la usa Compra). `screens/purchase_form_voice.dart` sólo lectura. |
| **B** | Detalle de producto de Almacén, avisos y presentación de lotes | `screens/inventory_detail_screen.dart`, `screens/inventory_alerts_screen.dart`, `screens/inventory_screen.dart`, `screens/purchase_detail_screen.dart` (sólo la presentación de lotes), `widgets/rdm_b_ui.dart`, nuevos `widgets/rdm2_b_*.dart`. |
| **C** | Personas: pago al titular, buscador, Cuentas/Costos, detalles unificados, PDF del estado de cuenta | `screens/persons_screen.dart`, `screens/person_detail_screen.dart`, `screens/settlements_screen.dart`, `screens/farm_logbook_screen.dart`, `widgets/account_statement_view.dart`, `widgets/rdm_a_payment.dart`, nuevos `widgets/rdm2_c_*.dart`; `lib/services/reports/pdf_report_generator.dart` y `pdf_writer.dart` (maquetación); la validación que impide un pago de cuenta personal al titular en la capa donde se registra (una guarda + pruebas, sin cambiar cálculos ni esquema). |
| **Orquestador** | Inicio/Sindicato, compartidos, rutas, integración | `lib/app.dart`, `app_shell.dart`, `theme/**`, `widgets/agro_ui.dart` (salvo `InPageSheet`), `screens/dashboard_screen.dart`, `screens/union_screen.dart`, `screens/sync_status_screen.dart`, `widgets/sync_*`, `test/support/**`, `tool/rediseno/capturas_arnes_test.dart`, `tool/rediseno/rdm_*`, documentos de `docs/rediseno/`. |

Cambios de rutas (`app.dart`) o de componentes compartidos: se piden al orquestador en el informe de la entrega; mientras tanto, widget privado en el archivo propio.

## Decisiones del autor en esta revisión (2026-11-12)

- **Titular:** no se le registra un pago de cuenta personal («cobro» a sí mismo). Revisa el criterio Q-2 (C-12, #26), que era un criterio de aplicación revisable. No afecta a sus deudas y pagos a proveedores. No se borran ni reclasifican asientos históricos; los incompatibles se informan.
- **Lotes:** el identificador interno no se muestra en la vida diaria; el número del fabricante es opcional, real y secundario («Más datos del envase»); nunca se genera uno.
- **Sindicato:** una sola pantalla principal para la pestaña y para «Enviar al sindicato» de Inicio; entrar no envía.
- **Personas:** dos áreas, Cuentas y Costos; una sola lista de personas; exportación Excel o PDF (sin CSV).

## Recursos

- Por sesión: un proceso `flutter` a la vez; `flutter analyze` de lo tocado; `flutter test <archivos> --concurrency=2`. Sin suites completas, sin APK, sin emulador ni `adb`, sin servicios ni túneles, sin `flutter pub upgrade`.
- Suites completas, compilación, instalación y recorridos: sólo el orquestador.
- Commits locales con la identidad git configurada, sin trailers. Sin push, PR ni fusiones a main.
