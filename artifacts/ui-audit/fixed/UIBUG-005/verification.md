# UIBUG-005 - verificacion en Pixel 8

**Registrar un pago rompe la interfaz en compilacion de depuracion**

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

`settlements_screen.dart` creaba `final amount = TextEditingController()` dentro
del metodo `_record` y lo liberaba en la linea siguiente al retorno de
`showDialog`, **mientras el dialogo aun se animaba al cerrarse**: el `TextField`
seguia montado y volvia a suscribirse al controlador ya liberado.

Correccion: el dialogo pasa a ser `_RecordPaymentDialog`, un `StatefulWidget` con
ownership claro de su controlador, que libera en `State.dispose()`. Es el patron
que ya seguian correctamente `catalogs_screen.dart` y `_PaymentDialog` de
`purchases_screen.dart`: se copio, no se invento.


## Pasos ejecutados en el dispositivo

1. Cuentas -> menu ⋮ de una persona -> *Registrar pago*.
2. Escribir un importe valido -> **Registrar**.
3. Repetir abriendo y cerrando el dialogo varias veces, y con el campo vacio.


## Resultado

No aparece la pantalla roja en **ninguna** repeticion. La pantalla sigue viva y
utilizable tras cerrar el dialogo.

Comprobacion de logcat tras registrar un pago en **debug**:

```
adb logcat -d -s flutter:* AndroidRuntime:E | grep -iE "disposed|_dependents|dirty widget"
(sin coincidencias)
```

Capturas: `after-dialogo-sin-pantalla-roja.png`, `after-registro-sin-error.png`.


## Tests relacionados

- `test/payment_dialog_test.dart`: *"abrir y cerrar el dialogo de pago 20 veces
  no rompe la pantalla"*, con `expect(tester.takeException(), isNull)`.
  Antes del fix este test reproducia las tres excepciones de logcat.


## Evidencia anterior

Ver `before-reference.txt` en esta misma carpeta. Las capturas originales de la auditoria **no se han borrado**: siguen en `artifacts/ui-audit/UI-*/`.
