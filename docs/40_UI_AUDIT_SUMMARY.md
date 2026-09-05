# 40 — Resumen ejecutivo de la auditoría de interfaz

Auditoría de las vistas y flujos de la aplicación **ejecutándola realmente** sobre un emulador
Pixel 8. Fecha: **2026-09-05**.

> **NO SE CORRIGIÓ NINGÚN UIBUG DURANTE ESTA FASE.** Ver §17.

## 1. Dispositivo utilizado

| | |
|---|---|
| Emulador | AVD **`Pixel_8`** (`emulator-5554`, `sdk_gphone16k_x86_64`) |
| Android | **16 (API 36)** |
| Resolución | **1080 × 2400**, densidad **420 dpi** |
| Orientación principal | Vertical (se comprobó además horizontal) |
| Escala de fuente | 1.0 (se comprobó además 1.3) |
| Binario auditado | `app-debug.apk`; además `app-profile.apk` para un contraste concreto |

## 2. Dataset

Generado de forma determinista con los métodos reales del repositorio
(`36_UI_AUDIT_DATASET.md`):

| | | | |
|---|---:|---|---:|
| Personas | 7 | Compras | 10 |
| Chacos | 8 | Transferencias | 7 |
| Productos | 22 | Aplicaciones | 12 |
| Proveedores | 4 | Planes | 5 |
| Campañas | 3 | Pagos a proveedor | 4 |
| Fotos de factura | 1 (2 compras) | Pagos de cuenta | 5 |

Incluye una compra, una aplicación y una transferencia **revertidas**, un producto **nunca
comprado**, otro **consumido al 100 %**, cantidades de 0,125 a 99 999,750 y un importe de
9 999 999,99 Bs.

## 3. Cobertura

| | |
|---|---|
| Pantallas encontradas | **17** (rutas declaradas) + 15 vistas secundarias |
| Pantallas auditadas | **16 de 17** |
| Pantalla no auditada | `/compras` — **inalcanzable desde la interfaz** (UIBUG-002) |
| Flujos auditados | **22** (`37_UI_SCREEN_INVENTORY.md` §3) |
| Capturas conservadas | **119**, organizadas por pantalla en `artifacts/ui-audit/` |

## 4. Hallazgos

| Severidad | Nº |
|---|---:|
| **CRITICAL** | **4** |
| **HIGH** | **17** |
| MEDIUM | 26 |
| LOW | 9 |
| **Total** | **56** |

Por categoría: LAYOUT 13 · UX 12 · DATA 8 · TEXT 8 · NAVIGATION 5 · FUNCTIONAL 5 ·
FORM 4 · SCROLL 4 · CONSISTENCY 3 · ERROR_HANDLING 3 · VALIDATION 2 · ACCESSIBILITY 2.

## 5. Los problemas de mayor impacto

1. **UIBUG-003 — Escribir un importe como lo muestra la app lo divide por mil.**
   Tecleando `1.500` en *Registrar pago* se guardaron **1,50 Bs**. Verificado leyendo la base
   del dispositivo. En una aplicación de contabilidad familiar es el riesgo más grave, porque no
   hay confirmación ni mensaje que lo delate.

2. **UIBUG-001 — La exportación de backup falla siempre en Android.**
   `PRAGMA wal_checkpoint(FULL)` ejecutado con `execute()` es rechazado por Android. La única
   protección de datos de la app no funciona en la plataforma real; la restauración, en
   consecuencia, nunca encuentra nada. Los tests no lo detectan porque corren sobre escritorio.

3. **UIBUG-002 — El historial de compras no tiene ninguna puerta de entrada.**
   Con él quedan inaccesibles los pagos a proveedor posteriores, el visor de facturas y la
   reversión de compras: funcionalidad implementada y probada que nadie puede alcanzar.

4. **UIBUG-004 — El botón Atrás cierra la aplicación desde cualquier pantalla**, y las
   pantallas de detalle no tienen flecha de volver: son callejones sin salida.

5. **UIBUG-007 — El buscador del inicio dice "Aún no hay inventario"** cuando el producto
   existe pero no está entre las 5 filas precargadas.

6. **UIBUG-005 — Registrar un pago rompe la interfaz** (pantalla roja) en compilación de
   depuración, que es la única instalable hoy.

7. **UIBUG-006 — Los cuatro formularios abren con las etiquetas superpuestas** e ilegibles.

## 6. Inconsistencias visuales

- Etiqueta y valor superpuestos en todos los selectores sin selección (UIBUG-006).
- El FAB tapa de forma permanente el último elemento de seis listas, incluidos menús ⋮ y botones
  de reversión (UIBUG-008, 018).
- Nombres largos que se parten palabra a palabra o **a mitad de palabra** (UIBUG-020, 021).
- Alturas fijas que cortan contenido: pestañas de persona (480 px), lista de catálogos (520 px),
  productos de la transferencia (48 %) (UIBUG-030, 018, 055).
- Casillas de selección sin función en la tabla del inicio (UIBUG-022).

## 7. Inconsistencias funcionales

- Una aplicación revertida se marca en Transferencias, **no** en Aplicaciones, se muestra
  con su importe en el Inicio y se excluye del reporte: tres tratamientos del mismo hecho
  (UIBUG-010).
- La misma persona muestra **dos saldos distintos** en tres pantallas (UIBUG-013).
- Dos selectores contiguos de la misma pantalla muestran datos distintos, y el mismo rol aparece
  traducido en una pantalla y en inglés crudo en otra (UIBUG-054, 016).
- Los planes ya aplicados siguen ofreciendo **Aplicar** sin ningún estado (UIBUG-045).

## 8. Navegación

- Atrás sale de la aplicación desde cualquier ruta del shell (UIBUG-004) — **CRITICAL**.
- Las pantallas de detalle no tienen botón de volver (UIBUG-004).
- `/compras` no tiene entrada (UIBUG-002) — **CRITICAL**.
- Las tarjetas de Operaciones prometen una acción y llevan a un listado (UIBUG-051).
- La barra inferior resalta "Inicio" mientras se está en la bitácora de un chaco (UIBUG-062).
- Las pestañas 4.ª y 5.ª del detalle de persona no se alcanzan tocando la barra (UIBUG-029).
- ✅ En los cuatro formularios (que usan `push`) Atrás funciona correctamente.

## 9. Formularios

- Etiquetas superpuestas (006), etiquetas colgando "Precio BOB/" (037), campo sin etiqueta (038),
  campos truncados (040).
- Búsqueda sensible a tildes: `maria` no encuentra `María` (019).
- El selector abre el teclado y deja ver 3 de 8 opciones (035); "Sin resultados." queda tras el
  teclado (036).
- Cantidades pre-rellenadas con `0` que no se limpian: escribir `5` deja `05` (034).
- Elegir en "Agregar producto" no agrega (042); la línea añadida nace plegada sin indicarlo (043).
- Guardar con nombre vacío no hace nada ni explica por qué (031).
- En "¿Descartar cambios?" el botón destructivo es el primario (033).
- ✅ **Correcto**: cálculo en vivo exacto, validaciones de negocio claras y en español, el
  teclado no tapa el campo activo en el formulario de compra, y el diálogo de confirmación de
  reversión es ejemplar.

## 10. Scroll y layout

- El FAB invade el contenido en seis pantallas (008, 009, 018, 064).
- Contenedores de altura fija que cortan el primer y el último elemento (018, 055).
- La tabla del inicio scrollea en horizontal pero pierde la columna de producto (023).
- **No se registró ni un solo `RenderFlex overflow` en logcat** durante toda la auditoría,
  incluso al 130 % de escala de fuente: los problemas son de recorte y solapamiento, no de
  desbordes de Flutter.

## 11. Datos y reportes

- ✅ Los cálculos son correctos: 12,5 L × 45,90 = 573,75 Bs; 18,75 USD × 6,96 = 130,50 Bs/L;
  la compra se propaga al inventario (500 L → 512,5 L).
- ✅ STAB-005 verificado en dispositivo: los productos sin consumo aparecen en cero.
- ❌ El formato de entrada y el de salida son incompatibles (003).
- ❌ Punto y coma decimal mezclados en la misma línea (024).
- ❌ Los resúmenes armados en SQL ignoran el formateador (025).
- ❌ La bitácora muestra el detalle FIFO en gramos y sin unidad: `FIFO: #1: 600000` (026).
- ❌ Fechas en ISO (027).

## 12. UX

Los defectos de UX más costosos son los que dejan al usuario sin saber qué ha pasado:
confirmar una compra no dice nada (011); registrar un pago no dice nada (014) y ni siquiera dice
a quién se le paga (012). Combinados con UIBUG-003 y UIBUG-005, la operación contable más
delicada de la aplicación carece por completo de puntos de verificación.

## 13. Errores y logs

Se monitorizó `logcat` filtrado por el PID de la aplicación durante toda la auditoría.

| Evento | Origen |
|---|---|
| `DatabaseException … PRAGMA wal_checkpoint(FULL)` | UIBUG-001 |
| `A TextEditingController was used after being disposed` | UIBUG-005 |
| `'_dependents.isEmpty': is not true` | UIBUG-005 |
| `Tried to build dirty widget in the wrong build scope` | UIBUG-005 |
| `[ERROR] Error mostrado al usuario \| error: El importe debe ser mayor a cero.` | validación correcta |

**Ningún `RenderFlex overflow`. Ninguna excepción tras 30 cambios rápidos de pestaña.**

El registro local añadido en la fase de estabilización (STAB-009) funcionó como se esperaba:
capturó los tres errores no controlados con marca de tiempo y traza, y fue lo que permitió
diagnosticar UIBUG-005 sin adivinar.

## 14. Pantallas sin problemas propios encontrados

| Pantalla | Comentario |
|---|---|
| **UI-02 Operaciones** | Maqueta limpia y correcta. Sus dos hallazgos (051 y el Atrás) son de navegación, no de la pantalla. |
| **UI-12 Inventario detalle** | Las seis métricas, la distribución por persona y los lotes se muestran correctamente; los importes cuadran. Solo le afecta el Atrás global (004). |

Ninguna otra pantalla quedó completamente libre de hallazgos.

## 15. Áreas que no pudieron probarse, y por qué

| Área | Motivo |
|---|---|
| **UI-06 `/compras`** y sus tres diálogos | Inalcanzable desde la interfaz (UIBUG-002). Probarla exigiría añadir una ruta o un botón, es decir **modificar el código de producción**, prohibido en esta fase. |
| **Estado de error** en 12 pantallas | Requiere corromper la base o inyectar un repositorio que lance. Ambas cosas modificarían datos o código. El estado de error sí se observó de forma natural en Liquidación. |
| **Estado vacío** en 9 pantallas | Requiere un segundo dataset vacío. Se observó en Inicio (por filtro), Plan, Aplicación y en los selectores. |
| **Cámara y galería** (F-05) | Exige conceder permisos y una imagen en el emulador; además su resultado solo se puede consultar desde `/compras`, inalcanzable. |
| **Diálogo "Falta una campaña activa"** | Exigiría cerrar la campaña activa y dejar el dataset sin ninguna, alterando el estado base. |
| **Estado `LOADING`** | Con una base local de 192 KB las consultas resuelven antes de que se pueda capturar el spinner. |
| **Reversión efectiva de compra/aplicación** | Se verificaron los diálogos de confirmación; no se ejecutaron todas las reversiones para no destruir el dataset repetidamente. Reproducible con el RESET. |
| **Otros tamaños de pantalla** | Fuera del alcance pedido (Pixel 8). Existe cobertura en `responsive_v5_test.dart`. |

## 16. Archivos generados

| Archivo | Tipo | ¿Conservar? |
|---|---|---|
| `docs/36_UI_AUDIT_DATASET.md` | Documentación | Sí |
| `docs/37_UI_SCREEN_INVENTORY.md` | Documentación | Sí |
| `docs/38_UI_AUDIT_FINDINGS.md` | Documentación | Sí |
| `docs/39_UI_AUDIT_TRACEABILITY.md` | Documentación | Sí |
| `docs/40_UI_AUDIT_SUMMARY.md` | Este documento | Sí |
| `test/support/ui_audit_seed.dart` | **Herramienta de desarrollo** | Sí — reutilizable, no se compila en la app |
| `tool/seed_ui_audit.dart` | **Herramienta de desarrollo** | Sí — generador del dataset |
| `tool/ui_audit_push.sh` | **Herramienta de desarrollo** | Sí — RESET → SEED → AUDIT |
| `artifacts/ui-audit/**` | Evidencia (119 capturas) | Sí mientras los UIBUG estén abiertos |
| `build/ui_audit/*` | Artefactos generados | No — se regeneran |

Los tres archivos de herramienta **no son referenciados desde `lib/`** y no entran en la
compilación de la aplicación. `test/support/ui_audit_seed.dart` no coincide con `*_test.dart`,
por lo que `flutter test` no lo ejecuta como suite; `tool/seed_ui_audit.dart` solo se ejecuta
invocándolo explícitamente.

## 17. Confirmación

**NO SE CORRIGIERON LOS UIBUGS DURANTE ESTA FASE.**

- No se hicieron refactors, cambios visuales, correcciones funcionales, cambios de navegación,
  cambios de base de datos, cambios de UX, eliminación de código ni actualización de
  dependencias.
- **Ningún archivo de `lib/` fue modificado.** Las únicas escrituras fueron: los tres archivos
  de herramienta de auditoría, los cinco documentos `36`–`40` y las capturas de evidencia.
- Los datos que la auditoría escribió en el dispositivo (una compra, dos pagos) se eliminaron
  recargando el dataset con `bash tool/ui_audit_push.sh --no-seed`.
- Las opciones del emulador que se modificaron para las fases 22 y 23 (rotación y escala de
  fuente) se restauraron a sus valores originales (`user_rotation 0`,
  `accelerometer_rotation 1`, `font_scale 1.0`).

### Validación posterior

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **91 / 91 en verde** |
| `git status --porcelain lib/` | **salida vacía** — ni un solo archivo de producción modificado |

Los dos primeros son idénticos a la línea base tomada antes de empezar. El tercero es la prueba
objetiva de que la restricción principal de esta fase se respetó: `lib/` está intacto.

Capturas conservadas: **119** archivos PNG en `artifacts/ui-audit/`.

## Siguiente paso sugerido

Antes de corregir, conviene decidir el orden. Los cuatro CRITICAL son independientes entre sí y
tres de ellos (001, 002, 004) son cambios acotados. UIBUG-003 es el más delicado porque toca el
parseo de **todos** los campos numéricos y exige decidir primero qué formato de entrada se acepta;
merece su propia discusión y sus propios tests antes de tocar `common.dart`.
