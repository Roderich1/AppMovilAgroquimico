# Integración de la presentación para el jurado: bloques A, B y C (2026-11-05)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-05 (Bolivia, UTC−4) |
| Rama de integración | `feat/uxj-integracion`, desde `f534015` (#191, que contiene #188 `76fd298` y Mobile `main` `279b46b`) |
| Commit verificado | `b80f236` |
| Procedencia | **HOST** (Windows 11, Flutter 3.47.2 stable, la versión de la CI) y **EMULADOR** (Pixel_8, Android 16, x86_64). Nada de esta página es DEVICE |
| Fuera de alcance | Reconocimiento de voz y «AC VOZ»; la DEMO; la política de publicación del consumo |

## 1. Ramas de los bloques

| Bloque | Rama | SHA | Evidencia |
|---|---|---|---|
| A, textos, «+» y navegación | `feat/uxj-a-textos-mas-navegacion` | `5f6e770` | este documento §3 |
| B, altas en el formulario y aviso de lote vencido | `feat/uxj-b-altas-vencimiento` | `8285d80` | `UXJ_B_ALTAS_VENCIMIENTO_2026-11-05.md` |
| C, estados del consumo, motivos en Vínculos y decisión de alcance | `feat/uxj-c-consumo-vinculos` | `f7919db` | `UXJ_C_CONSUMO_VINCULOS_2026-11-05.md`, `docs/adr/F06-ADR-006-envio-automatico-consumo.md` (Proposed) |

Cada bloque tuvo un único responsable por archivo y se fusionó sin conflictos.
- A: `app.dart`, `app_shell.dart`, `catalogs_screen.dart`, Operaciones, Inicio, Más, Inventario y los listados.
- B: los formularios, el selector, los diálogos de catálogo y `agro_repository.dart`.
- C: Vínculos, Consumo y `lib/data/sync/`.

Commits propios de la integración:
- `f7af0d4`: la previsión de lotes cita sólo RN-31 de la tesis (vencimiento); RN-32 es existencia baja.
- `63f8a72`: al cerrar un selector el teclado no se reabre (§4.1).
- `b80f236`: sin flecha «Volver» muerta al volver de un formulario (§4.2).

## 2. Envío automático del consumo: no activado

El contrato vigente lo impide sin una enmienda que sólo puede aprobar Roderich:
- Mobile `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §2.4: «la publicación de consumo sigue siendo una acción expresa del agricultor».
- BE F06 §2: «No se exige publicar si el agricultor no ha emitido una intención autorizada». No dice si una autorización permanente por campaña lo es (D-1 de `Refs Roderich1/Agro_Sindicato_Backend-Web#202`).

La decisión de alcance está registrada en `docs/adr/F06-ADR-006-envio-automatico-consumo.md` (Proposed). «Publicar» sigue siendo la única forma de enviar.

## 3. Pruebas HOST

| Comando | Resultado |
|---|---|
| `dart format --set-exit-if-changed lib test` | 0 cambiados |
| `flutter analyze` | No issues found |
| `flutter test` completo sobre `b80f236` | `04:17 +2321 ~3 -2` |
| Las 2 fallidas, aisladas (`f04_admin_owner_restore_ui_test`, `f12_est_07_estimation_ui_test`) | `+11: All tests passed!` |
| `flutter test` completo sobre `f7af0d4` (antes de §4) | `11:15 +2318 ~3 -3`; las 3 (`f10_x01_pago_datos`, `f10_x01_pago_revision` ×2) pasan aisladas y dos veces más junto con las pruebas de los bloques (`+42`, `+42`) |
| Pruebas de formularios y selectores tras §4.1 (33 archivos) | `01:12 +271: All tests passed!` |

Pruebas nuevas:
- **A, `uxj_a_navegacion_test` (8):**
  - Campañas y Reportes marcan Operaciones en la barra inferior, y Atrás vuelve a Operaciones;
  - «Ir a campañas» llega a Campañas;
  - el panel del «+» en 360×800, al 100 % y al 200 %: orden, filas enteras en pantalla y de al menos 48 de alto;
  - el «+» no tapa ninguna tarjeta de Operaciones en 393×873;
  - las tarjetas de Operaciones llevan icono y nombre;
  - (f) no queda una flecha «Volver» muerta.
- **B, `uxj_b_altas_vencimiento_test` (14):** ver su evidencia.
- **C, `uxj_c_consumo_vinculos_test` (10):** ver su evidencia.
- **Integración, `ux_altas_en_contexto_test` (i):** al elegir o crear en un selector, el foco no vuelve al precio.

Las pruebas (f) e (i) fallan sin su corrección y pasan con ella; se comprobó quitando la corrección y volviéndola a aplicar.

Las fallidas en la suite completa son intermitencias por tiempo bajo carga, anotadas ya en #188 y en las evidencias de B y C. Esta vez no fallaron las mismas.

## 4. Recorrido en el emulador (EMULADOR)

**Entorno:**
- Central DEMO con su túnel HTTPS temporal; el origen no se publica.
- Paquete aislado `.uxpres`, «AC UX». No toca `.voz` («AC VOZ») ni `.demo`.
- Cuenta sintética `agricultor2`, titular «Beto Mamani UX», modo compartido.
- Datos sembrados con `seed_demo_mobile.dart` y `DEMO_DATE=2026-11-03`, la fecha de siembra del Central. Con la fecha de hoy la siembra se negó sin tocar la base: la campaña local terminaba después que la central.
- Teclado en pantalla (`hw.keyboard=no`).

**Recorrido de la demo.**

| Paso | Resultado | Captura (`docs/evidence/uxj_emu/`) |
|---|---|---|
| Operaciones | Siete tarjetas con icono y nombre; Campañas con «Actual: Invierno 2026 (DEMO)»; el «+» sin tapar nada | `01_operaciones.png` |
| «+» | «Registrar operación»: Compra, Aplicación y Planificación; separador; Pago («En Cuentas») y Transferencia | `02_panel_registrar.png` |
| Compra | Herbicida DEMO, 4 L a 60 Bs (subtotal 240 Bs) | — |
| «Crear proveedor» con otro ya elegido | «Guardar» por encima del teclado. «Agro Sur DEMO» queda elegido; se conservan producto, cantidad, precio, subtotal y fecha | `03_nuevo_proveedor_teclado.png`, `04_…` |
| «Añadir otro producto» y «Crear producto» en la línea 2 | «Mancozeb DEMO» (KG) elegido en la línea 2; la línea 1 y el proveedor intactos | `05_compra_linea2_producto_creado.png` |
| Revisión | Total una sola vez (400,00 Bs); «¿Ya pagaste al proveedor?» | `06_revision_compra.png` |
| Confirmar («No, todavía no») | Vuelve a Operaciones | `07_…` (antes de §4.2), `08_…` (después) |
| Campañas y Reportes desde Operaciones | Se abren; Atrás (sistema) vuelve a Operaciones | `09_campanas.png`, `10_reportes.png` |

### 4.1 Defecto: el teclado se reabría al cerrar un selector

- **Commit de la APK:** `f7af0d4`.
- **Qué pasaba:** al elegir en la hoja del selector, o al crear desde ella, el foco volvía al último campo de texto (el precio). El teclado se reabría y tapaba «Continuar» (`04_compra_tras_crear_proveedor_DEFECTO_teclado.png`).
- **Corrección (`63f8a72`):** el selector quita el foco antes de abrir la hoja.
- **Comprobación en el emulador con `63f8a72`:** con el teclado abierto en el precio, se eligió un proveedor; después `mInputShown=false` y «Continuar» quedó visible.

### 4.2 Defecto: flecha «Volver» muerta en Operaciones

- **Commit de la APK:** `63f8a72`.
- **Qué pasaba:** tras confirmar una compra abierta con el «+», Operaciones mostraba «Volver» y la flecha no hacía nada (`07_operaciones_DEFECTO_volver.png`). Es anterior a esta rama.
- **Causa:** `PageFrame` leía `router.canPop()` sólo al construirse.
- **Corrección (`b80f236`):** la cabecera escucha la pila del router.
- **Comprobación en el emulador con `b80f236`:** misma compra, y Operaciones queda sin flecha (`08_operaciones_tras_compra_corregido.png`).

### 4.3 Observaciones sin corregir

- La revisión de compra usa «tú» («¿Ya pagaste…?», «Elige una opción…», «Puedes anotarlo…»), y el resto de la app usa «usted». El «tú» viene del texto pedido para la pregunta; falta decidir el registro.
- El aviso de lote vencido de Aplicación y Vínculos/Consumo no se recorrieron en el emulador. Están cubiertos sólo por las pruebas HOST de B y C.

## 5. APK para la demo

Paquete `com.comunidad.agro.agroquimicos.uxpres` («AC UX»), perfil `profile`, desde `b80f236`. Lleva compilado el origen del túnel DEMO del 2026-11-05: si el túnel se cierra, hay que recompilar desde el mismo commit.

| Destino | Archivo (local, no versionado) | SHA-256 |
|---|---|---|
| Emulador (x86_64) | `%TEMP%\agro_uxpres\apk\agrocuentas.uxpres-profile-x64.apk` | `0533da28341159127e3e5cffc3f083ab5bf73ccb2b65044cc80e668b6a884245` |
| POCO (ARM64) | `%TEMP%\agro_uxpres\apk\agrocuentas.uxpres-profile-arm64.apk` | `358bb6c69b5c0a9f643465c9b521165e45939dd79b8efaeb3936495a6b53b8b6` |

La APK ARM64 no se instaló en ningún teléfono.

## 6. Pendiente

- Recorrido en el POCO (DEVICE).
- Envío automático del consumo: depende de F06-ADR-006 y de #202.
- Push, PR y fusión: los decide el autor. Ninguna rama se ha publicado.
