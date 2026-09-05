# UIBUG-065 - verificacion en Pixel 8

**Un importe no interpretable se convierte en 0 y produce un mensaje engañoso**

Estado: `OPEN` -> `FIXED_NOT_DEVICE_VERIFIED` -> **`VERIFIED`**

## Entorno de verificacion

| | |
|---|---|
| **Fecha** | 2026-09-05 |
| **AVD** | `Pixel_8` (`emulator-5554`, `sdk_gphone16k_x86_64`) |
| **Android** | 16 (API 36) |
| **Resolucion** | 1080 x 2400 - 420 dpi - vertical |
| **Escala de fuente** | 1.0 |
| **Build mode** | `debug` (`app-debug.apk`) - es el modo donde UIBUG-005 se manifestaba |
| **Dataset** | `36_UI_AUDIT_DATASET.md`, esquema v5, recargado con `bash tool/ui_audit_push.sh` |
| **Lectura de base** | `bash tool/pull_device_db.sh` + consulta SQL local |


## Causa raiz corregida

Doble defecto: (a) un `catch (_) {}` vacio e inalcanzable que confundia a quien
leyera el codigo, y (b) la coercion silenciosa a `0`, que convertia un error de
formato en un error de importe.

Correccion: el dialogo usa `parseNumericInput` y distingue `empty` / `ambiguous` /
`malformed` / `valid`, mostrando el mensaje que corresponde a cada caso. El
`catch` muerto desaparecio con la reescritura.


## Pasos ejecutados en el dispositivo

1. Cuentas -> ⋮ de una persona -> *Registrar pago*.
2. Teclear `abc` -> **Registrar**.
3. Repetir con `1,500` (ambiguo).


## Resultado

Con `abc` el dialogo permanece abierto y muestra, bajo el campo:

    Escriba el numero como 1.500,25: use la coma para los decimales
    y el punto para los miles.

Con `1,500`:

    "1,500" es ambiguo: escriba 1.500 si son miles, o 1,5 si es decimal.

**Ya no aparece "El importe debe ser mayor a cero"** para una cadena no
interpretable, y no se escribe nada en la base (verificado: el numero de filas de
`account_transactions` no cambia).

Capturas: `after-mensaje-formato.png`, `after-mensaje-ambiguo.png`.

El mensaje "El importe debe ser mayor a cero." se conserva para el caso que
realmente lo merece: un importe valido igual a cero.


## Tests relacionados

- `test/payment_dialog_test.dart`: *"un importe no interpretable no dice 'mayor a
  cero'"* comprueba las tres cosas: que ese texto **no** aparece, que si aparece la
  explicacion de formato, y que **no se escribio ninguna fila**.
- `test/numeric_input_test.dart` cubre la clasificacion `malformed` / `ambiguous`.


## Evidencia anterior

Ver `before-reference.txt` en esta misma carpeta. Las capturas originales de la auditoria **no se han borrado**: siguen en `artifacts/ui-audit/UI-*/`.
