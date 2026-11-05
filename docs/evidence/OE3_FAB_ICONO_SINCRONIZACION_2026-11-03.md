# OE3: «+» sin etiqueta y sin botón flotante en Sincronización (2026-11-03)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-03, de ~23:00Z a 23:58Z (UTC; en Bolivia, UTC−4, de ~19:00 a 19:58) |
| Procedencia | **HOST** (§1–§4: Windows 11, Flutter 3.47.2 stable, Dart 3.13.2, `sqflite_common_ffi`) y **EMULADOR** (§5, 2026-11-04). Nada de esta página es DEVICE |
| Rama | `fix/fab-icono-sincronizacion`, creada desde Mobile `origin/main` `279b46b` |
| Commit de código | `8bc034436d290cfb88dc3038de5fed9d8624b0a3` (los commits posteriores sólo cambian `docs/`) |
| Origen del defecto | Sesión en el POCO X5 Pro del 2026-11-03: en Sincronización el FAB «Nuevo» tapaba «Reintentar con esta versión» y el toque abría el menú de creación |
| Seguimiento | Refs Roderich1/Agro_Sindicato_Backend-Web#200 |

## 1. Qué cambia

Archivos cambiados:

| Archivo | Cambio |
|---|---|
| `lib/presentation/app_shell.dart` | `'/sincronizacion'` en `_routesWithoutGlobalFab`, con el motivo; `_newButton` pasa de `FloatingActionButton.extended` «Nuevo» a `FloatingActionButton` con `child: Icon(Icons.add)` y `tooltip: 'Registrar operación'`; título de la hoja «Nuevo» → «Registrar operación»; comentarios de `fabReserve` y `hidesGlobalFab` |
| `test/oe3_fab_sincronizacion_test.dart` | Nuevo: 15 casos (§2 y §3) |
| `test/personal_mode_flows_test.dart` | `openNewSheet` tocaba `find.text('Nuevo')`; ahora `find.byTooltip('Registrar operación')`. Mismas aserciones sobre el menú |

- Ruta de Sincronización: `/sincronizacion` (`lib/app.dart`, `GoRoute` dentro del `ShellRoute`, `SyncStatusScreen`). `AppShell.location` recibe `state.uri.path`.
- Siguen sin FAB todas las rutas ya excluidas: `/`, `/catalogos`, `/voz`, `/compras/voz`, `/planificacion/voz`, `/aplicaciones/voz`, `/inventario/avisos`, `/inventario/estimacion` y `/compras/detalle/*`.
- `/sincronizacion/consumo` (Publicar consumo) **no** se tocó: la decisión del autor nombra sólo Sincronización. Sigue con el «+».
- Misma acción y mismas opciones del menú: Planificación, Compra, Aplicación, Pago y, en inventario compartido, Transferencia. Mismas rutas (`go`/`push`).
- Título de la hoja: se cambió a «Registrar operación» para que el título que se ve y se oye al abrir el menú coincida con el nombre del botón que lo abrió. No se tocó ninguna otra aparición de «Nuevo/Nueva» (p. ej. «Nueva compra», «Nuevo proveedor»).
- `late_operations_screen.dart`: su `FloatingActionButton.extended` dice «Período histórico» y abre el diálogo de crear un período histórico. Es una función específica, no el botón de creación global: **se deja igual**.
- Espacio inferior (`AppShell.fabReserve = 88`, publicado por `ContentInsets` y aplicado en `PageFrame`): **sin cambio de valor**. El FAB normal mide 56×56, el mismo alto que el extendido (M3: 56); sólo es más estrecho. Se actualizó el comentario.

## 2. Reproducción en `279b46b` (antes de corregir)

Comando: `flutter test test/oe3_fab_sincronizacion_test.dart -r expanded` con `lib/presentation/app_shell.dart` de `origin/main` (`git show origin/main:lib/presentation/app_shell.dart`) y la prueba nueva.

Resultado: **15 de 15 fallan** (`+0 -15: Some tests failed.`).

| Caso | Aserción que falla |
|---|---|
| `hidesGlobalFab` por ruta | `/sincronizacion`: `Expected: true, Actual: <false>` |
| App real, `go('/sincronizacion')` | `Expected: no matching candidates` — hay 1 `FloatingActionButton` |
| Sincronización 360×800, 130 % | **Solape:** el centro `Offset(180.0, 676.0)` de «Reintentar con esta versión» queda dentro del FAB `Rect.fromLTRB(135.5, 648.0, 344.0, 704.0)` |
| Sincronización 412×915, 130 % | **Solape:** el centro `Offset(206.0, 791.0)` queda dentro del FAB `Rect.fromLTRB(187.5, 763.0, 396.0, 819.0)` |
| Sincronización 360×800 y 412×915, 100 % y 200 % | En esas posiciones el centro no quedó bajo el FAB y el toque abrió la confirmación; falla después: hay 1 `FloatingActionButton` en la ruta |
| «+» en una sección con FAB, 6 casos (2 tamaños × 3 escalas) | `find.text('Nuevo')`: `Found 1 widget` |
| App real: «+» → «Compra» | No hay ningún botón con el tooltip «Registrar operación» |

Cómo se monta la reproducción de Sincronización: `seedSyncFixture` (titular vinculado y campaña), una necesidad declarada pausada por versión (`markSending` + `recordVersionMismatch`, el 422) y otra pausada por restauración (`pauseAfterRestore`), de modo que la pantalla muestra «Liberar» y «Reintentar con esta versión». `AppShell(location: '/sincronizacion', child: SyncStatusScreen())` con el tema de la app (Material 3, densidad compacta, español). Se desplaza la página hasta dejar el centro del botón a la altura del centro del FAB (16 de margen + 28), acotado a lo que la página permite. El transporte HTTP falla si algo intenta enviarse.

## 3. Tras la corrección (`8bc0344`)

`flutter test test/oe3_fab_sincronizacion_test.dart -r expanded` → **15 pasan** (`+15: All tests passed!`).

| Caso | Qué comprueba |
|---|---|
| `hidesGlobalFab` por ruta | `/sincronizacion` y las 9 ya excluidas ocultan el FAB; `/operaciones`, `/inventario`, `/personas` y `/liquidacion` lo muestran |
| App real (router, base en archivo) | En `/operaciones` hay un FAB; en `/sincronizacion` no hay ninguno |
| Sincronización, 2 tamaños × 3 escalas | No hay FAB; el centro de «Reintentar con esta versión» no queda bajo ningún FAB; el toque en ese centro abre la confirmación «Reintentar con esta versión» y no el menú de creación; sin excepciones ni desbordes |
| «+», 2 tamaños × 3 escalas | Un solo FAB, `isExtended == false`, icono `Icons.add`, ningún `Text` dentro y ningún «Nuevo»; tamaño ≥ 48×48 y `androidTapTargetGuideline`; en el árbol semántico «Registrar operación» aparece **en un solo nodo** y «Nuevo» en ninguno; el nodo del botón tiene `tooltip` «Registrar operación», `label` vacío, es botón y tiene acción de toque; con la página desplazada al final, la última de 30 filas termina por encima del FAB; el hit-test en el centro del «+» llega al botón; el toque abre la hoja con Planificación, Compra, Aplicación, Pago y Transferencia dentro de la hoja; sin excepciones ni desbordes |
| App real: «+» → «Compra» | Desde `/operaciones`, el «+» abre el menú y «Compra» abre `PurchaseFormScreen`, como antes |

Escalas y tamaños comprobados (HOST):

| Tamaño lógico (DPR) | 100 % | 130 % | 200 % |
|---|---|---|---|
| 360×800 (2,0) | Pasa | Pasa | Pasa |
| 412×915 (2,625) | Pasa | Pasa | Pasa |

La escala se fija con `tester.platformDispatcher.textScaleFactorTestValue`; el tamaño, con `tester.view.physicalSize` y `devicePixelRatio`. El FAB normal mide 56×56 lógicos en todos los casos (el estándar de Material 3; no depende de la escala de texto).

## 4. Pruebas existentes y comprobaciones globales

Pruebas existentes que tocan el FAB o el shell (búsqueda de `Nuevo`, `FloatingActionButton`, `hidesGlobalFab`, `app_shell`, `fabReserve` en `test/`):

- Modificada sólo `test/personal_mode_flows_test.dart`: tocaba el texto «Nuevo» del botón para abrir el menú. Ahora toca el botón por su tooltip; las aserciones sobre las opciones (sin «Transferencia» en propio, con ella en compartido) no cambian. Se ajustó el nombre del caso («Operaciones y el «+» no ofrecen transferencias»).
- Sin cambios (sus aserciones no dependen de la etiqueta): `f04_av_inventory_alerts_ui_test`, `f10_compat_129_presentacion_test`, `f10_x01_inicio_mas_test`, `hierarchical_navigation_test`, `ui_polish_test`, `voice_draft/voice_wiring_test`, `widget_test`, `purchases_access_test`, `sync_screens_test`, `f10_sync_version_mismatch_resume_test`. Los comentarios que mencionan el antiguo «Nuevo» describen la historia de cada caso y se dejaron.

Ejecución conjunta de esos 11 archivos (en paralelo): 93 pasan y 1 falla: `personal_mode_flows_test` «catálogos: no se agregan responsables y el chaco nuevo es del titular sin elegirlo» (no encontró `farm-personal-owner`). Es `/catalogos`, que ya no tenía FAB antes de este cambio. El archivo solo, a continuación: **20/20 pasan**.

| Comando | Resultado |
|---|---|
| `dart format --set-exit-if-changed lib test` | 374 archivos, 0 cambiados |
| `flutter analyze` | «No issues found!» |
| `flutter test` (suite completa, sobre `8bc0344`, de ~23:27Z a 23:40Z) | **2265 pasan, 3 omitidas, 11 fallan**; salida 1. Ninguna falla es de `oe3_fab_sincronizacion_test` |

Las 11 fallas son de 8 archivos. Después se ejecutó cada archivo solo, en serie, sobre el mismo código:

| Archivo | Fallas en la suite | El archivo solo |
|---|---|---|
| `f03_access_recovery_app_test` | 2 | 3/3 pasan (23:42Z) |
| `f04_admin_owner_restore_ui_test` | 2 | 7/7 pasan (23:43Z) |
| `f08_prev_01_previo_ui_test` | 1 | 1.ª vez: 7 pasan y 1 falla (23:44Z); 2.ª vez: 8/8 pasan |
| `f10_x01_aplicacion_productos_test` | 1 | 6/6 pasan (23:44Z) |
| `f10_x01_inicio_mas_test` | 1 | 4/4 pasan (23:45Z) |
| `f10_x01_pago_revision_test` | 2 | 3/3 pasan (23:45Z) |
| `f12_est_07_estimation_ui_test` | 2 | 1.ª vez: 2 pasan y 2 fallan, con un tiempo de espera de 10 min (23:45Z–23:55Z); 2.ª vez: 4/4 pasan (23:57Z) |

- **Lectura:** ninguno de estos archivos comprueba el FAB ni Sincronización. Los que fallaron alguna vez estando solos pasan al repetirlos sobre el mismo código. Es el mismo patrón de espera bajo carga que recoge `OE3_HOST_CIERRE_2026-11-03.md` para `f03_access_recovery_app_test`, `f10_x01_pago_revision_test` y `f12_est_07_estimation_ui_test`.
- **No se afirma** nada sobre su resultado en `279b46b`: allí no se ejecutaron hoy.

## 5. Emulador (2026-11-04)

Verificación del 2026-11-04, hacia las 03:15Z, hecha por la sesión de Claude Code:
- **Emulador:** `Pixel_8` (Android 16, API 36, x86_64, 1080×2400, 420 ppp), con la app de la DEMO (`com.comunidad.agro.agroquimicos.demo`) conectada al Backend real de la DEMO.
- **Rama:** APK profile x86_64 de `cf833c1` (código `8bc0344`), SHA-256 `f54ac3c846d66f7f6f3713e797e92ed192aee0ee78b250ff6c7bd5037c95a5d0`.
- **Referencia:** APK de `main` (`8c7013c` de la DEMO, mismo `lib/` que `279b46b`), SHA-256 `67306ea8…`.
- **Intención pausada por versión:** se produjo con el modo `mutate version-2` del observador. El 422 de Central es real.
- **Herramienta:** `tool/fab_emulador_check.sh`. Salida en `docs/evidence/oe3_fab_emulador/rama-comprobaciones.txt`. No es DEVICE.

**Reproducción en `main`.** A 130 %, «Nuevo» ([718,1938]–[1038,2085] px) tapa la parte derecha de «Reintentar con esta versión» ([351,2040]–[1017,2127] px): captura `oe3_fab_emulador/main-sincronizacion-130-solape.png`. El centro del botón quedó fuera y el toque abrió la confirmación. A 100 % y 200 %, en la posición de la pantalla, no hubo solape.

| Comprobación (rama) | 100 % | 130 % | 200 % |
|---|---|---|---|
| Sincronización: ningún botón flotante | Pasa | Pasa | Pasa |
| Toque en «Reintentar con esta versión»: abre su confirmación y no el menú de creación | Pasa | Pasa | Pasa |
| Operaciones: «+» de 147×147 px (56 dp), sin texto; 0 «Nuevo» visibles | Pasa | Pasa | Pasa |
| Toque en «+»: menú «Registrar operación» con Planificación, Compra, Aplicación, Pago y Transferencia | Pasa | Pasa | Pasa |
| Desplazada al final, «Más» termina por encima del «+» (1833 px < 1938 px) | Pasa | Pasa | Pasa |
| Árbol de accesibilidad de Android (uiautomator): un solo nodo con «Registrar operación» y ninguno con «Nuevo» | Pasa | Pasa | Pasa |
| Anuncio hablado de TalkBack | No medido | No medido | No medido |

**Capturas:**
- `rama-sincronizacion-130.png`;
- `rama-operaciones-200.png`;
- `rama-menu-100.png`.

**Límite:** el nombre accesible se comprobó en el árbol que expone Android, no con TalkBack encendido.

## 6. Límites

- La reproducción del solape es de HOST: geometría de Flutter con el tema de la app, no capturas del POCO. A 100 % y 200 % el centro del botón no quedó bajo el FAB en la posición de la prueba; el solape se reprodujo a 130 % en los dos tamaños.
- La semántica se comprobó en el árbol de Flutter (`tooltip`, `label`, banderas) y en el árbol de accesibilidad de Android (§5). El anuncio hablado de TalkBack no se midió.
