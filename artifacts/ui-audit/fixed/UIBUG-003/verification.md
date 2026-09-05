# UIBUG-003 - verificacion en Pixel 8

**El formato que la app imprime, tecleado tal cual, divide el valor por mil**

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

`lib/presentation/widgets/common.dart:131` normalizaba `,` -> `.` y trataba el
punto como separador decimal, mientras `formatBob`/`formatQuantity`
(`lib/domain/money.dart:35,41`) imprimen con `NumberFormat(..., 'es_BO')`, donde el
punto separa miles. **Entrada y salida usaban convenciones opuestas.**

Correccion: regla unica y centralizada en `lib/domain/numeric_input.dart`
(especificada en `docs/44_NUMERIC_INPUT_SPEC.md`), con la que `common.dart` ahora
delega. Ninguna pantalla analiza numeros por su cuenta.


## Pasos ejecutados en el dispositivo

### A. Pago (la via sin red de seguridad)

1. Cuentas -> menu ⋮ de **Jose Luis Ñañez Alvarez** -> *Registrar pago*.
2. Teclear `1.500` -> **Registrar**.
3. Repetir con `1.500,25`, `0,125` y `1,500`.

### B. Transferencia (la via que el usuario puede detectar)

1. Operaciones -> *Transferir inventario* -> **Nueva**.
2. Origen: **Juan Perez**. El campo se rotula **"15.000 KG disponibles"**.
3. Teclear exactamente `15.000` en Cloruro de Potasio.
4. Destino: **Ana Añez** -> **Revisar y confirmar** -> **Confirmar**.


## Resultado

### A. Pago - leido de la base del dispositivo

| Tecleado | `amount_bob_minor_signed` | En Bs | Veredicto |
|---|---:|---|---|
| `1.500` | **-150000** | 1.500,00 Bs | correcto (antes -150) |
| `1.500,25` | **-150025** | 1.500,25 Bs | correcto |
| `0,125` | **-13** | 0,13 Bs | correcto (redondeo half-up de 12,5) |
| `1,500` | *(ninguna fila)* | — | **rechazado por ambiguo, no escribe nada** |

El saldo pasa de 19.359,50 a 17.859,50 Bs: exactamente 1.500,00 Bs.
Captura: `after-pago-1500-registrado.png`, `after-ambiguo-rechazado.png`.

### B. Transferencia - leido de la base del dispositivo

El dialogo de confirmacion resume **"Cloruro de Potasio: 15.000 KG"**
(la auditoria registro "15 KG"). Captura: `after-transferencia-15000-kg.png`.

```sql
SELECT ti.quantity_base FROM transfers t
JOIN transfer_items ti ON ti.transfer_id=t.id ORDER BY t.id DESC LIMIT 1;
-- 15000000  = 15.000,000 KG   (con el codigo anterior habria sido 15000 = 15 KG)
```

**Ningun error en logcat** (`disposed`, `_dependents`, `dirty widget`: 0 coincidencias).


## Tests relacionados

- `test/numeric_input_test.dart` - 31 tests de la especificacion completa
  (`docs/44_NUMERIC_INPUT_SPEC.md`), incluida la **invariante de ida y vuelta**
  `format -> parse == original`, que es la garantia anti-regresion.
- `test/payment_dialog_test.dart` - escritura real en `account_transactions`
  sobre base en memoria (no mockeada): `1.500` -> -150000, `1.500,25` -> -150025,
  `1,500` -> no escribe nada.


## Evidencia anterior

Ver `before-reference.txt` en esta misma carpeta. Las capturas originales de la auditoria **no se han borrado**: siguen en `artifacts/ui-audit/UI-*/`.
