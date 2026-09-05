# UIBUG-002 - verificacion en Pixel 8

**La pantalla de historial de compras es inalcanzable**

Estado: `OPEN` -> `FIXED_NOT_DEVICE_VERIFIED` -> **`VERIFIED`**

## Entorno de verificacion

| | |
|---|---|
| **Fecha** | 2026-09-05 |
| **AVD** | `Pixel_8` (`emulator-5554`, `sdk_gphone16k_x86_64`) |
| **Android** | 16 (API 36) |
| **Resolucion** | 1080 x 2400 - 420 dpi - vertical |
| **Escala de fuente** | 1.0 |
| **Build mode** | `debug` (`app-debug.apk`) |
| **Dataset** | `36_UI_AUDIT_DATASET.md`, esquema v5, recargado con `bash tool/ui_audit_push.sh --apk` |

## Causa raiz corregida

La ruta `/compras` estaba declarada en `lib/app.dart:62` pero **ninguna de las 16
llamadas de navegacion de `lib/` apuntaba a ella**. `PurchasesScreen` ya estaba
completa y probada -- con su boton "Nueva compra", su refresco y su mensaje de
exito -- pero no habia forma de llegar.

### Decision de diseno tomada

La tarjeta **"Registrar compra"** de Operaciones saltaba directamente al
formulario (`/compras/nueva`, `isForm: true`), a diferencia de las de
aplicaciones y transferencias, que abren su **listado**.

Se hace que la tarjeta abra el **listado**, como las otras dos:

```
Operaciones -> Compras -> Nueva compra
```

Es la opcion mas coherente con la UX existente y **no duplica rutas**: hay una
sola puerta a `/compras` y una sola al formulario. Ademas:

- devuelve al usuario a un sitio donde **la compra recien creada aparece**, que
  es lo que faltaba para **UIBUG-011** (confirmar una compra no daba acuse
  porque `OperationsScreen` descartaba el resultado del formulario);
- reduce el problema de **UIBUG-051** en una tarjeta: el titulo pasa de
  "Registrar compra" (que prometia un formulario y ahora abriria un listado) a
  **"Compras · Historial, facturas y pagos a proveedor"**, que describe lo que
  hace. La armonizacion del resto de tarjetas sigue pendiente en el lote J.

El FAB "Nuevo -> Compra" **se deja como estaba** (apila el formulario con
`push`): es una accion de creacion explicita y su comportamiento de retorno ya
estaba cubierto por el test de STAB-001.

## Pasos ejecutados en el dispositivo

1. Operaciones -> comprobar que existe la tarjeta **Compras**.
2. Abrirla -> historial de compras.
3. Menu ⋮ de una compra -> **Ver factura**.
4. Menu ⋮ -> **Registrar pago** (pago a proveedor).
5. Menu ⋮ -> **Revertir compra**.
6. Atras desde `/compras`.

## Resultado

| # | Criterio | Resultado |
|---|---|---|
| 1 | Entrada visible en Operaciones | **OK** - tarjeta "Compras · Historial, facturas y pagos a proveedor" |
| 2 | Historial alcanzable | **OK** - `after-historial-compras.png`. **UI-06 auditada por primera vez**: filtro por campaña, buscador, 10 compras con proveedor, factura, totales, pagado y estado (Confirmada / Revertida) |
| 3 | Visor de factura | **OK** - `after-visor-factura.png`. Muestra la imagen del dataset. Nunca antes habia sido alcanzable |
| 4 | Pago a proveedor | **OK** - `after-pago-proveedor.png`. Dialogo con pagador, importe y "Maximo 20.000,00 Bs" |
| 5 | Reversion | **OK** - `after-revertir-compra.png`. Confirmacion con nombre, factura, total, consecuencias y boton rojo. **No se ejecuto** para no destruir el dataset |
| 6 | Volver atras | **PENDIENTE de UIBUG-004A** (ver abajo) |

### Regresion encontrada y corregida durante esta verificacion

El dialogo **Pago al proveedor** precargaba el importe con
`(maxMinor / 100).toStringAsFixed(2)` = **`20000.00`**, en convenio ingles,
mientras la etiqueta contigua decia "Maximo 20.000,00 Bs".

Con la regla de entrada centralizada de UIBUG-003 ese texto es **invalido** (el
punto es separador de miles), de modo que el campo quedaba precargado con un
valor que la propia aplicacion ya no sabia leer. **Lo introdujo el lote A y solo
aparecio al abrir esta pantalla, que hasta ahora era inalcanzable.**

Corregido con `formatForInput` (`lib/domain/numeric_input.dart`), que escribe el
valor como el usuario podria teclearlo. Se aplico a los **tres** puntos que
precargaban campos con `toStringAsFixed`:

- `purchases_screen.dart:312` (importe del pago a proveedor)
- `application_form_screen.dart:145` (area en hectareas)
- `plan_form_screen.dart:66` (area en hectareas)

Ahora el campo precarga **`20000`**. Verificado en dispositivo.

### Lo que NO quedo resuelto

Pulsar **Atras** desde `/compras` sigue cerrando la aplicacion:

```
$ adb shell dumpsys window | grep mCurrentFocus
mCurrentFocus=Window{... com.google.android.apps.nexuslauncher ...}
```

Es **UIBUG-004A**, no UIBUG-002: `/compras` es una ruta del shell y se alcanza
con `context.go`, que reemplaza la pila. Se corrige en el lote D. El retorno
*dentro* del flujo (formulario -> listado) si funciona y esta cubierto por
`navigation_test.dart`.

## Tests relacionados

- `test/purchases_access_test.dart` (**nuevo**), 3 tests que fallaban antes:
  - se llega al historial desde Operaciones y **abre el listado, no el
    formulario**;
  - desde el historial se abre el formulario ("Operaciones -> Compras -> Nueva
    compra");
  - **guardia estructural**: ninguna ruta declarada en `app.dart` queda sin
    origen en `lib/`. Antes del fix senalaba exactamente `['/compras']`. Impide
    que vuelva a colarse funcionalidad inalcanzable.
- `test/navigation_test.dart`: el test de STAB-001 que recorria
  "Operaciones -> Registrar compra" se actualizo al recorrido real
  "Operaciones -> Compras -> Nueva compra". **El invariante y el helper de
  asercion son los mismos** (volver atras deja pantalla utilizable y sin
  excepciones); la prueba cubre ahora un salto mas.
- `test/numeric_input_test.dart`: grupo nuevo `formatForInput` con la invariante
  `parseNumericInput(formatForInput(v)).value == v`, que es lo que habria
  detectado la regresion del precargado sin necesidad del dispositivo.

## Evidencia anterior

Ver `before-reference.txt`. Las capturas originales de la auditoria no se han
borrado.
