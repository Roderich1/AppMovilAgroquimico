# Presentación móvil: altas en el selector, Campañas y Reportes en Operaciones (2026-11-05)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-05, de ~13:40Z a 14:35Z (en Bolivia, UTC−4, de ~09:40 a 10:35) |
| Procedencia | **HOST** (Windows 11, Flutter 3.47.2 stable, `sqflite_common_ffi`). Nada de esta página es EMULADOR ni DEVICE (ver §5) |
| Rama | `feat/ux-presentacion-altas`, creada desde `fix/fab-icono-sincronizacion` (#188) `76fd298`, que contiene Mobile `main` `279b46b` |
| Commit de código | `2de5aec` |
| Base de comparación | `76fd298` (#188, el «+» sin etiqueta) |
| Fuera de alcance | Reconocimiento de voz (sin cambios), «AC VOZ», la DEMO, la política de publicación de consumo |

## 1. Qué cambia

| Área | Cambio |
|---|---|
| Selector (`adaptive_entity_picker.dart`) | Alta opcional en la hoja: primera fila «Crear …», también con la lista vacía. Lo creado queda elegido; si el alta se cancela o falla, nada del formulario cambia |
| Compra | «Crear proveedor» y «Crear producto» (en cada línea) |
| Planificación | «Crear chaco» y «Crear producto» |
| Aplicación | «Crear chaco» con la persona ya elegida como dueña. Los productos salen de las existencias: **sin** alta |
| Diálogos (`catalog_dialogs.dart`) | Los diálogos de Catálogos pasan a un archivo compartido; Catálogos y los formularios usan las mismas validaciones y los mismos métodos del repositorio. Son desplazables con el teclado abierto |
| Campañas (`/campanas`, `campaigns_screen.dart`) | Pantalla propia: la campaña actual arriba y las demás debajo. Activar, «Cerrar y activar», cerrar con resumen y fin efectivo, sin reactivar una cerrada: mismas funciones que Catálogos (`campaign_actions.dart`). Sin «+» (tiene «Agregar campaña») |
| Operaciones | Accesos a **Campañas** (subtítulo «Actual: …» o «Sin campaña activa») y **Reportes**. Subtítulos más cortos; sin «Lo del trabajo diario.». El aviso de inventario propio se conserva |
| Más | Ya no repite Reportes |
| «+» (de #188) | El panel «Registrar operación» abre directamente los formularios de Planificación, Compra, Aplicación y Transferencia. Pago sigue en Cuentas. Avisa al volver con la operación guardada |
| Textos | Sin los subtítulos de Compras («Precio original, FX histórico…»), Aplicaciones («Eventos de fumigación…») y Planificación («Necesidad, cobertura…»), que repetían la tarjeta de Operaciones. Sin «Agregue los productos de la planificación.» bajo el selector «Agregar producto». El «+» del plan se anuncia «Agregar al plan» |

**Se conservan:**
- validaciones de formulario y de repositorio;
- estados de sincronización (`SyncAwareBody` sin cambios);
- avisos de modalidad, campaña activa, pago y operaciones tardías;
- nombres accesibles existentes;
- la sección Campañas de Catálogos.

## 2. Defecto encontrado y corregido durante el trabajo

Primera versión: tras crear un proveedor (o un chaco), el formulario cambiaba su `Future` de catálogos por `Future.value(next)`.

1. Durante un fotograma el `FutureBuilder` seguía con la lista vieja.
2. El selector no encontraba lo recién elegido y quedaba vacío.
3. Con una sola opción vieja, la autoselección (`autoSelectSingle`) la elegía encima de lo creado.

Las pruebas (b) y (f) de `ux_altas_en_contexto_test.dart` lo detectaron:
- se esperaba `'Agro Sur UX'` y quedaba `'Proveedor'`;
- se esperaba `'Chaco Bajo UX'` y quedaba `'Chaco hermana'`.

Corrección: `SynchronousFuture(next)`, que `FutureBuilder` admite de forma explícita. Con ella la lista nueva entra en la misma reconstrucción. Tras la corrección pasan las 8.

## 3. Pruebas HOST

| Comando | Resultado |
|---|---|
| `flutter test test/ux_altas_en_contexto_test.dart` | **8 pasan** |
| `flutter test test/ux_altas_teclado_test.dart` | **6 pasan** |
| `flutter test` sobre los 51 archivos que montan las pantallas tocadas (incluye el nuevo de §3.1) | **370 pasan, 0 fallan** (`01:29 +370: All tests passed!`) |
| `flutter analyze` | sin issues |
| `dart format --set-exit-if-changed lib test tool/ux_pres` | 0 cambiados |

**`ux_altas_en_contexto_test.dart`** (app completa, repositorio real, base en archivo, modalidad compartida):

- **(a) Compra, «Crear producto» en la línea 2.**
  - Queda elegido con su unidad (KG).
  - La línea 1 conserva Glifosato, cantidad 2 y precio 45; se conservan también el proveedor, la fecha «(hoy)» y «Productos (2)».
- **(b) Compra, «Crear proveedor».** Queda elegido; la línea no cambia.
- **(c) Compra, cancelar el alta.** El borrador queda igual y `suppliers` no cambia.
- **(d) Compra, alta que falla** (repositorio que lanza `BusinessRuleException`). Se muestra el aviso, el borrador queda igual y se sigue en el paso 1.
- **(e) Planificación.**
  - «Crear chaco» queda elegido y precarga el área (2,5).
  - «Crear producto» queda elegido para agregar, y el chaco se conserva.
- **(f) Aplicación.**
  - «Crear chaco» muestra «Propietario: Hermana», sin elegir dueño.
  - El chaco se guarda con `owner_person_id` de la hermana.
  - En el paso de productos, ningún selector ofrece altas.
- **(g) Operaciones.**
  - Muestra «Campañas» con «Actual: Campaña 1», y «Reportes».
  - «Más» ya no tiene «Reportes».
  - Campañas tiene su tarjeta actual y «Agregar campaña», sin «+».
- **(h) El «+».** «Aplicación» abre «Nueva aplicación».

**`ux_altas_teclado_test.dart`** (360×800, letra al 100 % y al 200 %, teclado de 300 px; se mide el rectángulo y la prueba de toque):

- **(a)** «Guardar» y «Cancelar» del alta de producto quedan por encima del teclado y reciben el toque.
- **(b)** «Crear proveedor» de la hoja queda por encima del teclado.
- **(c)** En Operaciones el «+» desaparece con el teclado y vuelve sin él.

**Pruebas existentes actualizadas al nuevo diseño:**
- `f10_x01_inicio_mas_test.dart`: Operaciones incluye Campañas y Reportes, y Más ya no incluye Reportes.
- `reports_screen_test.dart`: se llega a Reportes desde Operaciones y Atrás vuelve allí.

En una primera pasada fallaron, además, `f03_access_recovery_app_test`, `f04_activation_app_policy_test` (2) y `f04_admin_owner_restore_ui_test` (2). En las dos pasadas siguientes de los mismos 51 archivos pasaron sin cambios en ellos. Son las intermitencias ya anotadas en #188 (§4 de su evidencia).

## 4. Capturas comparables (HOST)

Herramienta: `tool/ux_pres/capturas_host_test.dart`.
- Usa la app real con los mismos datos sintéticos: el hogar del arnés F04, más Mancozeb (KG), una compra y una aplicación.
- Fuente Roboto real e iconos Material; 393×873 dp a 2,75, el ancho del POCO.
- «Antes» es la base `76fd298` y «Después» es `2de5aec`.
- En `docs/evidence/ux_pres_host/` cada imagen tiene el antes a la izquierda y el después a la derecha. Un panel gris indica una vista que no existe en la base.

| Imagen | Vista |
|---|---|
| `01_operaciones.png` | Operaciones: Campañas («Actual: Campaña 1») y Reportes; sin subtítulo genérico |
| `02_operaciones_mas_registrar.png` | Panel del «+» (mismas opciones; ahora abren el formulario) |
| `03_mas.png` | Más sin Reportes |
| `04_compras.png`, `05_aplicaciones.png`, `06_planificacion.png` | Listados sin el subtítulo repetido |
| `07_catalogos.png` | Catálogos (sin cambio visible) |
| `08_campanas.png` | Campañas, pantalla nueva |
| `10_compra.png` | Formulario de compra (sin cambio visible en el paso 1) |
| `11_compra_selector_producto.png` | Hoja del selector con «Crear producto» |
| `12_compra_crear_producto.png` | Diálogo «Nuevo producto» sobre el borrador |
| `13_planificacion_form.png`, `14_aplicacion_form.png` | Formularios de plan y de aplicación |

**Incidencia de entorno.** En un worktree nuevo de la base, `flutter test` no pudo construir el recurso nativo de `sqlite3`: «Hash of downloaded file sqlite3.x64.windows.dll is bef140a1…, expected 2bf39f2a…», repetido dos veces. No se forzó. El «antes» se capturó en el worktree de la rama, que tiene el recurso ya verificado en caché:
1. se separó temporalmente en `76fd298` (`git switch --detach`);
2. se capturó;
3. se volvió a la rama.

## 5. Pendiente: recorrido en el emulador y APK para el POCO

**No se hizo.** El recorrido en el emulador y la APK aislada necesitan:
- el Central DEMO, que quedó levantado;
- el túnel HTTPS temporal (`demo-mobile.sh tunnel`): `ApiEndpointConfig` exige HTTPS y una instalación nueva se activa contra el Central.

El control de permisos de la sesión rechazó abrir el túnel, y no se eludió. Con el túnel autorizado, el plan es:
1. Compilar dos APK desde `2de5aec` como paquete aislado **`.uxpres`, «AC UX»**, una x86_64 para el emulador y otra ARM64 para el POCO. No reemplaza «AC VOZ» (`.voz`) ni «AC DEMO» (`.demo`).
2. Activarla con una cuenta sintética libre de la DEMO (`agricultor2`) y sembrar los datos locales con `seed_demo_mobile.dart`.
3. Recorrer en el emulador:
   - Compra con «Crear producto» y «Crear proveedor», incluidos cancelar y fallo;
   - Planificación y Aplicación con «Crear chaco»;
   - Campañas;
   - Reportes;
   - el «+».
4. Tomar capturas con la base `76fd298` instalada antes, sobre los mismos datos.

## 6. Qué no cambia

- Rutas y reglas de compra, aplicación, plan, transferencia y pago.
- Reglas de campaña: mismas funciones y mismos mensajes.
- Reconocimiento de voz y pantallas de voz: sin FAB, sin cambios.
- `AppShell.fabReserve` y la política de Atrás.
- Esta rama no se fusiona.
