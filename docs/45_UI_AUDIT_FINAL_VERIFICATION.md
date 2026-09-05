# 45 — Verificación final de la auditoría de interfaz

Cierre de la fase de corrección del backlog UIBUG y auditoría de regresión completa sobre
Pixel 8.

Fecha: **2026-09-05** · Rama: `hardening/stabilization`

> **Nota de numeración.** El encargo pedía este documento como `44`, pero ese número ya lo
> ocupa [`44_NUMERIC_INPUT_SPEC.md`](44_NUMERIC_INPUT_SPEC.md), referenciado desde
> `lib/domain/numeric_input.dart`, desde `common.dart` y desde dos suites de test. Renumerarlo
> habría roto esas referencias, así que este cierre va como **45**.

---

## 1. Entorno

| | |
|---|---|
| Emulador | AVD **`Pixel_8`** (`emulator-5554`, `sdk_gphone16k_x86_64`) |
| Android | **16 (API 36)** |
| Resolución | **1080 × 2400**, densidad **420 dpi** |
| Orientación | Vertical (y horizontal para UIBUG-063) |
| Escala de fuente | 1.0 y **1.3** |
| Binario | `app-debug.apk` (el modo donde UIBUG-005 se manifestaba) |
| Lectura de base | `bash tool/pull_device_db.sh` + SQL local |
| Ajustes restaurados | `font_scale 1.0`, `user_rotation 0`, `accelerometer_rotation 1` ✅ |

## 2. Dataset

El mismo de [`36_UI_AUDIT_DATASET.md`](36_UI_AUDIT_DATASET.md), esquema **v5**, recargado con
`bash tool/ui_audit_push.sh --apk` (RESET → SEED → AUDIT) antes de la regresión y varias veces
durante ella. 7 personas · 8 chacos · 22 productos · 4 proveedores · 3 campañas · 10 compras ·
7 transferencias · 12 aplicaciones · 5 planes, con una compra, una aplicación y una
transferencia **revertidas**.

## 3. Tests

| Métrica | Antes de la auditoría | Antes de esta fase | **Ahora** |
|---|---:|---:|---:|
| Tests | 91 | 139 | **170** |
| Archivos de test | 20 | 24 | **25** |

Suites nuevas de esta fase:

| Archivo | Qué fija |
|---|---|
| `test/hierarchical_navigation_test.dart` | 004A/004B/062 · Atrás en detalles, subrutas y destinos raíz; contrato de `PageFrame` (flecha de salida y reserva bajo el FAB) |
| `test/formatting_and_labels_test.dart` | 016/019/024/025/026/027/056 · hectáreas, fechas, FIFO, resúmenes, etiquetas de dominio y búsqueda sin tildes |

De fases anteriores: `numeric_input_test.dart`, `payment_dialog_test.dart`,
`backup_android_semantics_test.dart`, `purchases_access_test.dart`.

**Resultado**: `flutter analyze` 0 issues · `dart format` limpio · `flutter test` **170/170** ·
`flutter build apk --release` ✅ (59,8 MB, sin firmar por falta de keystore).

## 4. Rutas auditadas — **17 / 17**

| # | Ruta | Pantalla | Resultado |
|---|---|---|---|
| UI-01 | `/` | Dashboard | ✅ búsqueda sobre todo el inventario, sin columna de casillas, FAB no tapa la última fila |
| UI-02 | `/operaciones` | Operaciones | ✅ cinco tarjetas que nombran su destino |
| UI-03 | `/catalogos` | Catálogos | ✅ última fila (`Zinc Quelatado`) completa y operable |
| UI-04 | `/planificacion` | Planificación | ✅ el botón deja libre el indicador de despliegue |
| UI-05 | `/planificacion/nueva` | Plan (form) | ✅ selector legible; validación por condición |
| **UI-06** | `/compras` | **Compras** | ✅ **auditada por completo, por primera vez** (ver §5) |
| UI-07 | `/compras/nueva` | Compra (form) | ✅ precarga es-BO; inset del sistema respetado |
| UI-08 | `/aplicaciones` | Aplicaciones | ✅ "Revertida" marcada; cantidades formateadas |
| UI-09 | `/aplicaciones/nueva` | Aplicación (form) | ✅ elegir agrega; fila desplegada; stock negativo en rojo |
| UI-10 | `/liquidacion` | Liquidación | ✅ tarjetas legibles, alcance del saldo declarado |
| UI-11 | `/inventario` | Inventario | ✅ búsqueda sin tildes |
| UI-12 | `/inventario/:id` | Inventario detalle | ✅ alcanzable y con retorno |
| UI-13 | `/personas` | Personas | ✅ buscador y recarga; ADMIN marcado |
| UI-14 | `/personas/:id` | Persona detalle | ✅ pestañas alcanzables, saldo acumulado, retorno |
| UI-15 | `/chacos/:id` | Bitácora | ✅ FIFO legible, fechas locales, barra resalta Personas |
| UI-16 | `/transferencias` | Transferencias | ✅ fecha por movimiento, cantidades formateadas |
| UI-17 | `/transferencias/nueva` | Transferencia (form) | ✅ selectores legibles, campo sin `0` pegado |

**Cobertura 17/17.** La única pantalla que la auditoría original no pudo auditar (UI-06) ya no
tiene ningún bloqueo.

## 5. UI-06 `/compras` — auditada por primera vez

| Comprobación | Resultado |
|---|---|
| Historial | ✅ 10 compras con proveedor, factura, totales, pagado y estado |
| Filtro por campaña y buscador | ✅ presentes |
| Detalle de una compra (menú ⋮) | ✅ tres acciones |
| **Foto de factura** | ✅ visor abre la imagen del dataset — **nunca antes alcanzable** |
| **Pago a proveedor** | ✅ diálogo con pagador, importe y máximo |
| **Reversión** | ✅ confirmación con nombre, factura, total y consecuencias |
| Scroll | ✅ sin cortes |
| Back | ✅ vuelve a Operaciones |

## 6. Flujos auditados

Los 22 originales de [`37`](37_UI_SCREEN_INVENTORY.md) §3 más los habilitados por `/compras`:

| Área | Resultado |
|---|---|
| Entrada numérica | ✅ `1.500` → 1.500,00 Bs; `15.000` → 15.000 KG; `1,500` rechazado |
| Backup / restore | ✅ ciclo completo verificado (fase anterior) |
| Compras | ✅ historial, factura, pago a proveedor, reversión |
| Navegación Atrás | ✅ jerárquica y raíz (§9) |
| Pago | ✅ contexto, validación, acuse |
| Búsqueda | ✅ sin tildes y sobre todos los registros |
| Operaciones revertidas | ✅ marcadas en las tres vistas |
| Cambio de campaña | ✅ confirmación intacta |
| Aplicación / transferencia / inventario | ✅ sin regresiones |
| Reportes | ✅ cifras coherentes con las listas |
| Formularios | ✅ criterio único de descarte y validación |
| Teclado | ✅ el FAB se aparta; el campo queda visible |
| Scroll | ✅ ninguna fila queda inalcanzable |
| Fuente 130 % | ✅ §10 |
| Horizontal | ✅ rail con etiquetas |
| Interacción rápida | ✅ sin excepciones en logcat |

## 7. Bugs iniciales, corregidos, verificados y restantes

| Estado | Nº | |
|---|---:|---|
| Backlog inicial | **66** | (65 IDs; `004` subdividido) |
| **`VERIFIED`** | **38** | corregidos y comprobados en Pixel 8 |
| `FIXED_NOT_DEVICE_VERIFIED` | **16** | corregidos, cubiertos por tests, sin captura dedicada |
| `OPEN` | **9** | §8 |
| `DESIGN_DECISION_REQUIRED` | **2** | 045, 059 |
| `WONT_FIX` | **1** | 058, con justificación |

**Corregidos en total: 54 de 66 (82 %).** Los 4 CRITICAL y los 17 HIGH están cerrados.

## 8. UIBUG que permanecen abiertos, y por qué no bloquean

Los nueve son **MEDIUM/LOW cosméticos o de conveniencia**, sin riesgo contable, sin pérdida de
datos y sin bloqueo funcional. Ninguno impide operar.

| UIBUG | Qué queda | Por qué no bloquea |
|---|---|---|
| 023 | La tabla del inicio pierde el nombre del producto al desplazarse en horizontal | Con la columna de casillas eliminada (022) la tabla cabe mejor; el dato está en `/inventario` |
| 031 | Guardar un catálogo vacío no explica por qué | No escribe nada; el diálogo permanece abierto |
| 037 | "Precio BOB/" sin unidad hasta elegir producto | Cosmético, se resuelve solo al elegir |
| 038 | Campo de cantidad de asignación sin etiqueta | La validación al confirmar sí es explícita |
| 039 | "asignado" antes de elegir persona | La validación al confirmar lo detecta |
| 040 | Campos truncados en la compra | El valor completo está en el selector |
| 041 | Etiqueta "Producto" recortada por la cabecera | Cosmético |
| 047 | Dos puntos de creación en Catálogos | Ambos funcionan; la ambigüedad es de estilo |
| 060 | Un `0` sin explicación antes de elegir origen | Se resuelve al elegir origen |

**Decisiones de producto pendientes** (no son defectos de implementación):

- **045** — ¿un plan se puede aplicar más de una vez? Exige estado de plan (posible migración v6).
- **059** — ¿se puede reabrir una campaña cerrada? Afecta a la invariante de campaña única activa.
- **058** — `WONT_FIX`: el signo del asiento es **contablemente correcto**; invertirlo
  contradiría el modelo. Se decide junto con el vocabulario de saldos.

## 9. Resultados de navegación

| Escenario | Antes | Ahora |
|---|---|---|
| `/personas/:id` → Atrás | cerraba la app | **vuelve a Personas** |
| `/inventario/:id` → Atrás | cerraba la app | vuelve a Inventario |
| `/chacos/:id` → Atrás | cerraba la app | vuelve al detalle de persona |
| Subrutas de Operaciones → Atrás | cerraban la app | **vuelven a Operaciones** |
| Destino raíz → Atrás | cerraba la app | **vuelve a Inicio** (decisión 004B) |
| Inicio → Atrás | cerraba la app | cede el gesto al sistema (correcto) |
| Pantallas de detalle | sin salida visible | **flecha de volver en la cabecera** |
| Barra en `/chacos/:id` | resaltaba "Inicio" | resalta **Personas** |

Verificado con `dumpsys window`: `mCurrentFocus` permanece en
`com.comunidad.agro.agroquimicos/MainActivity` (la auditoría registraba `…nexuslauncher…`).

## 10. Resultados de accesibilidad (130 %)

| Comprobación | Resultado |
|---|---|
| Tarjetas de liquidación | ✅ el nombre trunca con elipsis, **no se parte a mitad de palabra** |
| Cifras contables | ✅ **completas**: `20.160,00 Bs`, `800,50 Bs`, `19.359,50 Bs` |
| Columnas | ✅ no se solapan |
| Barra de navegación | ✅ las cinco etiquetas en una línea |
| `RenderFlex overflow` en logcat | ✅ **ninguno** |

**Compromiso deliberado y documentado**: las etiquetas de la barra inferior se mantienen en su
cuerpo base (`MediaQuery.withClampedTextScaling(maxScaleFactor: 1)`). Con cinco destinos en
1080 px, "Operaciones" no cabe en una línea por encima del 100 %. Cada destino lleva icono y
**el resto de la aplicación sí escala** hasta el 130 %. La alternativa era acortar el nombre de
una sección principal.

## 11. Capturas

- **Originales, intactas**: `artifacts/ui-audit/UI-*/` — **119 PNG**, ninguno sustituido.
- **Posteriores por defecto**: `artifacts/ui-audit/fixed/UIBUG-<ID>/` con `verification.md`,
  `before-reference.txt` y capturas *after* (fases anteriores: 001, 002, 003, 005, 012, 014, 065).
- **Regresión de esta fase**: `artifacts/ui-audit/fixed/regression/` — recorrido de las rutas
  con la evidencia posterior.

## 12. Nuevos UIBUG encontrados

**Ninguno preexistente.** La regresión no destapó defectos que ya estuvieran en el producto.

Sí se detectaron y corrigieron **tres regresiones introducidas durante esta misma fase**, antes
de cerrarla (detalle en el informe de la sesión):

1. Precarga de campos en convenio inglés (`20000.00`, `80.0`) que el parser es-BO rechazaba —
   apareció al abrir `/compras`, hasta entonces inalcanzable.
2. `DateFormat` con locale sin `initializeDateFormatting`, que habría lanzado
   `LocaleDataException` en tres pantallas. **Lo detectó un test antes de llegar al dispositivo.**
3. Importe de liquidación truncado (`19.359,…`) al repartir el ancho de la tarjeta. Detectado en
   el dispositivo y corregido con reducción de cuerpo en vez de recorte.

Queda registrado un defecto **latente y ajeno al backlog**, visible en el log de los tests:
`setState() callback argument returned a Future` en `_ApplicationsScreenState`. No produce
error visible ni afecta a los datos; se deja anotado para una fase posterior.

## 13. Estado de release

Ver [`35_RELEASE_READINESS.md` § POST-BACKLOG STATUS](35_RELEASE_READINESS.md).

**Veredicto: `RELEASE CANDIDATE`** — con un único bloqueo externo (keystore) y nueve MEDIUM/LOW
cosméticos justificados.
