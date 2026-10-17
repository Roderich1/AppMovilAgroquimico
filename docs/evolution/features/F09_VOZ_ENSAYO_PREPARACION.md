# F09 — Preparación del ensayo físico (sin medir)

- **Estado:** preparado el 2026-10-17 por la sesión A. **No se ha medido nada.** Faltan el SHA final y una persona que dicte.
- **Protocolo vigente:** [F09_VOZ_ENSAYO_FISICO_PLAN.md](F09_VOZ_ENSAYO_FISICO_PLAN.md), integrado con MOB #111 (`ec69ae8`). Esta preparación **no lo cambia**: dice cómo se fijan las huellas, qué datos sintéticos se crean y cómo se registra. Mantiene D-F09-1…7.
- **Quién usa el POCO:** sólo la sesión A.
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #12 y #17. Para los casos de fecha efectiva, RF-03 y RN-15/RN-16 (MOB #110).

## 1. Tres cosas distintas, que no se mezclan

| Qué | Quién lo conoce | Cómo se informa |
|---|---|---|
| **Corpus expuesto** (`benchmark/voice_benchmark`, partición `aceptacion`) | Está en el repositorio; lo conoce quien ajustó el intérprete | Si se ejecuta, como **holdout expuesto**. Nunca como ciego |
| **Conjunto nuevo** (D-F09-5): 20 dictados (7 compra, 6 planificación y 7 aplicación) y 2 sin habla, **con sus expectativas** | Su autor y la sesión A, que lo oye y lo registra. **No** lo conoce la sesión C, que escribió las reglas del intérprete, ni se usa para ajustarlas | Como **muestra exploratoria nueva, no expuesta al implementador del intérprete**. **No es un conjunto ciego**: lo conocen su autor y el operador |
| **Resultado** | — | Se registra después, contra las expectativas fijadas antes. Las expectativas no se cambian al ver el resultado |

**Autor del conjunto:** una persona que no ajustó las reglas del intérprete (propuesta: Roderich). Lo escribe fuera del repositorio con `tool/f09_device/conjunto_plantilla.csv`:
- `frase`: lo que se dictará;
- `operacion_esperada`;
- `campos_esperados` (producto, cantidad, unidad, precio, proveedor, chaco o plan, según el caso);
- `debe_bloquear`: sí o no.

La sesión A **no** escribe frases ni expectativas. Si nadie ajeno a las reglas lo escribe, el conjunto nuevo queda `NOT_MEASURED`.

## 2. Lo que se fija antes de la primera toma

Se fijan con `tool/f09_device/fingerprints.py <worktree> <apk> <conjunto> fijado.json`, después de que esté integrada la corrección de la precisión del área (sesión C) y de que la CI del HEAD exacto esté en verde:

| Huella | Origen |
|---|---|
| `mobile_sha` | HEAD completo del `main` Mobile del ensayo |
| `interpreter_tree` | Árbol git de `lib/voice_draft` en ese HEAD |
| `protocol_sha256` | SHA-256 del protocolo en ese HEAD |
| `apk_sha256` | APK aislada nueva, de paquete `com.comunidad.agro.agroquimicos.f09voz` (`F03_APP_ID_SUFFIX=.f09voz`, `build_isolated_apk.sh`) |
| `set_sha256` | Archivo del conjunto nuevo con sus expectativas, sin abrirlo (el script no lo lee ni lo muestra) |

**Reglas:**
- Si D-F04-C2 (sesión B) cambia el binario **antes** de la primera toma, se congela la nueva base y se vuelven a fijar las huellas.
- Si llega **después**, se conservan las atribuciones a esta base y sólo se repiten los casos afectados por el delta.
- La app normal y la demo no se tocan.

## 3. Datos sintéticos

Se crean desde la interfaz de la copia aislada, activada contra el entorno aislado, antes de medir. T es el día del ensayo, en `America/La_Paz`:

| Paso | Qué | Para qué |
|---|---|---|
| 1 | Catálogo del protocolo: «Bellator», «Belator», «Glifosato» (L), «Expansive» (KG); el proveedor «Agro Norte»; los chacos «Sur» y «Norte» | V5–V14 |
| 2 | «Campaña ensayo 1», desde T−30 (activa) | Plan de otra campaña |
| 3 | En la campaña 1: una compra de Glifosato fechada en T−10 (stock del titular) y un plan pendiente en «Sur» | El stock pasa a la campaña siguiente; el plan **no** debe ofrecerse después |
| 4 | Alta de «Campaña ensayo 2», desde T−5. La 1 termina en T−6, porque su última operación es de T−10. Después se activa la 2 | Calendario sin solapes (#110) |
| 5 | En la campaña 2: dos planes pendientes en «Sur», uno en «Norte» y uno aplicado (aplicación manual fechada en T−2) | V15–V19 |

**Casos físicos de fecha efectiva (#110).** Se registran con la huella de las tablas antes y después (`tool/f04_device/devdb.py <paquete> dump`):

| ID | Qué se hace | Qué se comprueba |
|---|---|---|
| E1 | Compra manual fechada en T (dentro del período de la campaña 2) | Se registra en la campaña 2 |
| E2 | Compra manual fechada en T−5 (primer día de la campaña 2: frontera) | Se registra en la campaña 2 |
| E3 | Compra manual fechada en T−6 (último día de la campaña 1, cerrada) | Rechazo que nombra «Campaña ensayo 1»; las huellas de **todas** las tablas son idénticas |
| E4 | Compra manual fechada en T−31 (antes de toda campaña) | Rechazo «no está dentro de ninguna campaña»; huellas idénticas |

## 4. Registro de cada escenario dictado

| Campo | Qué se anota | Qué no se anota |
|---|---|---|
| Reconocimiento crudo | Si devolvió texto, el idioma pedido y el usado, sin red o con ella, y el código de error | La frase |
| Corrección manual | Los campos que hubo que tocar, uno por uno, o «ninguno» | Valores privados (sólo hay sintéticos) |
| Resultado de negocio | Los conteos de `eval_counts.sh`, la huella por tabla de `devdb.py dump` antes y después, y las tablas que cambiaron | — |
| Veredicto | PASS / FAIL / NOT_MEASURED, por separado para el reconocimiento y para el negocio | Un PASS de negocio con correcciones **no** es un PASS de reconocimiento |

## 5. Lo que falta antes de medir

1. Que la sesión C entregue la precisión del área, se revise, se integre y la CI del HEAD esté en verde.
2. Que la persona que escribe el conjunto lo entregue fuera del repositorio.
3. El entorno aislado (`tool/f03_res_01/up.sh`), con un volumen nuevo, y la APK `.f09voz`.
4. Una persona que dicte junto al POCO. **Sin ella, el reconocimiento real queda `NOT_MEASURED`.** HONOR, `NOT_MEASURED` (D-F09-6).
