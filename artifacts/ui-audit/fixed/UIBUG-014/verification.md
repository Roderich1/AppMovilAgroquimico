# UIBUG-014 - verificacion en Pixel 8

**Registrar un pago no muestra ningun mensaje de exito**

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

`_record` llamaba a `addAccountPayment` y refrescaba sin `showSuccess`, a
diferencia de `_backup()` en la misma pantalla, que si lo usaba.


## Pasos ejecutados en el dispositivo

1. Cuentas -> ⋮ de Jose Luis -> *Registrar pago*.
2. Teclear `1.500` -> **Registrar**.


## Resultado

Aparece el snackbar:

    Pago de 1.500,00 Bs registrado a Jose Luis Ñañez Alvarez.

con el importe **ya formateado y la persona nombrada**, de modo que el propio
acuse delata cualquier malinterpretacion del importe.

Capturas: `after-snackbar-exito.png`, `after-snackbar-crop.png`.


## Tests relacionados

- `test/payment_dialog_test.dart`: *"registrar un pago muestra mensaje de exito"*,
  comprobando que existe un `SnackBar` y que contiene el importe formateado.
- El mismo test cubre el adelanto, que produce "Adelanto de ... registrado a ...".


## Evidencia anterior

Ver `before-reference.txt` en esta misma carpeta. Las capturas originales de la auditoria **no se han borrado**: siguen en `artifacts/ui-audit/UI-*/`.
