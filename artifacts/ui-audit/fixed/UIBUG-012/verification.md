# UIBUG-012 - verificacion en Pixel 8

**El dialogo Registrar pago no dice a quien se le esta pagando**

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

El `AlertDialog` recibia `person` como parametro pero no lo usaba ni en el titulo
ni en el contenido. Correccion incluida en la reescritura de
`_RecordPaymentDialog` (ver UIBUG-005).


## Pasos ejecutados en el dispositivo

1. Cuentas (filtro **Verano 2026**) -> menu ⋮ de **Jose Luis Ñañez Alvarez**.
2. *Registrar pago*.


## Resultado

El dialogo muestra ahora, antes del campo de importe:

- **Jose Luis Ñañez Alvarez** (destacado)
- **Campaña Verano 2026**
- **Saldo pendiente 19.359,50 Bs**

y un texto de ayuda con el formato esperado (`1.500,25`).

Captura: `after-dialogo-con-contexto.png`.

El flujo sigue siendo rapido: un solo campo, sin pasos adicionales.


## Tests relacionados

- `test/payment_dialog_test.dart`: *"el dialogo identifica persona, campaña y
  saldo"*, con los buscadores acotados al `AlertDialog` (la pantalla de fondo
  tambien contiene el nombre y la palabra "Saldo", asi que buscar en toda la
  pantalla daria un falso positivo).


## Evidencia anterior

Ver `before-reference.txt` en esta misma carpeta. Las capturas originales de la auditoria **no se han borrado**: siguen en `artifacts/ui-audit/UI-*/`.
