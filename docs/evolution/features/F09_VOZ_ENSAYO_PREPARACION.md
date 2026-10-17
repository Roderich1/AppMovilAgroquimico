# F09 — Preparación del ensayo físico (sin medir)

- **Estado:** preparado el 2026-10-17 por la sesión A. **No se ha medido nada.** Faltan el SHA final (después de integrar MOB #116, D-F04-C2) y una persona que dicte.
- **Actualización del 2026-10-17 (noche).** Se aplica `CONTINUACION_TRAS_115_REVISION_116_2026-10-17.md` §4 «A»:
  - una misma persona puede escribir el conjunto y dictarlo;
  - se añade el registro por ID de los campos automáticos antes de corregir;
  - se precisa lo que hace `fingerprints.py` con los bytes;
  - se añade la comprobación física acotada de D-F04-C2;
  - se cambia el teléfono del ensayo.
  El texto anterior se conserva donde no cambia.
- **Protocolo vigente:** [F09_VOZ_ENSAYO_FISICO_PLAN.md](F09_VOZ_ENSAYO_FISICO_PLAN.md), integrado con MOB #111 (`ec69ae8`). Esta preparación **no lo cambia**: dice cómo se fijan las huellas, qué datos sintéticos se crean y cómo se registra. Mantiene D-F09-1…7.
- **Quién usa el teléfono:** sólo la sesión A. *(2026-10-17, noche)* Por indicación de Roderich, el ensayo se hace en **el teléfono nuevo conectado**, no en el POCO. Su modelo y su versión de Android se registran con `getprop` antes de medir. Por D-F09-6, el ensayo acredita **sólo ese modelo**; el POCO queda `NOT_MEASURED` para la voz, salvo que también se ensaye en él.
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #12 y #17. Para los casos de fecha efectiva, RF-03 y RN-15/RN-16 (MOB #110).

## 1. Tres cosas distintas, que no se mezclan

| Qué | Quién lo conoce | Cómo se informa |
|---|---|---|
| **Corpus expuesto** (`benchmark/voice_benchmark`, partición `aceptacion`) | Está en el repositorio; lo conoce quien ajustó el intérprete | Si se ejecuta, como **holdout expuesto**. Nunca como ciego |
| **Conjunto nuevo** (D-F09-5): 20 dictados (7 compra, 6 planificación y 7 aplicación) y 2 sin habla, **con sus expectativas** | Su autor y la sesión A, que lo oye y lo registra. El autor puede ser **la misma persona que dicta**, si no ajustó las reglas del intérprete y se declara. **No** lo conoce la sesión C, que escribió las reglas, ni se usa para ajustarlas | Como **muestra exploratoria nueva, no expuesta al implementador del intérprete**. **No es un conjunto ciego**: lo conocen su autor y el operador |
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
| `set_sha256` | Archivo del conjunto nuevo con sus expectativas. *(Precisión del 2026-10-17, noche)* El script **lee los bytes del archivo para calcular el hash**, pero no los interpreta como frases ni los imprime |

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

*(Ampliado el 2026-10-17, noche.)* El texto de la versión anterior pedía separar el reconocimiento crudo, la corrección y el negocio; aquí se concreta por ID. Cada entrada del conjunto nuevo (C1–C7, P1–P6, A1–A7, S1–S2) y cada escenario dictado de V1–V19 se registra en este orden, **antes** de tocar nada a mano:

| Paso | Qué se anota | Cómo |
|---|---|---|
| 1. Presencia de texto | Si el motor devolvió texto (sí / no / error con su código), el idioma pedido y el usado, y si había red | Sin copiar la frase. «Devolvió algún texto» **no** es precisión de reconocimiento |
| 2. Resultado automático por campo | Para cada campo de `campos_esperados`, si el borrador lo llenó **igual que la expectativa fijada** (acierto), **distinto** (fallo) o **vacío** (falta). Lo mismo con `operacion_esperada` y `debe_bloquear` | Se compara con las expectativas del archivo cuya huella se fijó, **antes de corregir**. Se anotan ID, campo y acierto / fallo / falta, sin valores |
| 3. Corrección manual | Qué campos se tocaron a mano para llegar al borrador correcto, o «ninguno» | Uno por uno |
| 4. Efecto de negocio | Conteos de `eval_counts.sh` y huella por tabla de `devdb.py dump`, antes y después, y las tablas que cambiaron | Sólo datos sintéticos |
| 5. Veredicto | Por separado: presencia de texto, campos automáticos (n aciertos / n esperados por ID) y negocio | Un PASS de negocio con correcciones **no** es un PASS de reconocimiento |

**No se hace:**
- calcular WER ni ninguna tasa de palabras, porque no se guarda la transcripción con la que compararla;
- transcripciones en logs ni en Central;
- grabar audio;
- cambiar una expectativa después de ver el resultado.

Los resultados negativos (fallo, falta, bloqueo inesperado o NOT_MEASURED) se conservan tal cual.

## 4b. Comprobación física acotada de D-F04-C2 (registro aparte)

*(2026-10-17, noche.)* Se ejecuta sólo cuando MOB #116 esté integrado en la base del ensayo, en la misma copia aislada `.f09voz`, y se registra **aparte** de F09. Son casos de producto en el teléfono, no adversariales:

| ID | Preparación | Qué se hace | Qué se comprueba |
|---|---|---|---|
| G1 | En el Central aislado, una campaña con fin previsto (finito), vía el contenedor desechable o la Web de administración, con datos sintéticos. En el teléfono, la campaña local activa **sin fin** | Vincular la campaña local con la central | Se rechaza con un mensaje que muestra **los dos períodos** y pide fijar un fin |
| G2 | — | «Fijar fin previsto…» con un fin dentro del período central | La campaña sigue **ACTIVE**; el vínculo vuelve a ser válido (recuperado); huella de `campaigns` y de `campaign_bindings` antes y después |
| G3 | Vínculo incompatible otra vez (otra campaña o un fin central anterior, refrescando las referencias) | Declarar una necesidad nueva y forzar la sincronización | La intención queda **retenida** y el log de la API aislada (o del observador) no registra ningún POST de valor para ese `operationId`. Al volver a ser compatible, sale una vez |

Los casos adversariales (resultado desconocido, «no recibido» frente a «aceptado con el ACK perdido», carrera entre la selección y el marcado) se prueban **en host**, de forma determinista, con las regresiones de #116, y **no** se etiquetan DEVICE por G1–G3.

## 5. Lo que falta antes de medir

*Antecedente:* la versión anterior pedía aquí la precisión del área (C). Está **integrada** (MOB #115 → `70aaa8d`).

1. **MOB #116 (D-F04-C2):** que se corrijan C2-R1 y C2-R2, se revise el HEAD final, se integre y la CI del `main` resultante esté en verde. Hasta entonces **no hay SHA final**, y `078d638` no se congela.
2. Que la persona que escribe el conjunto lo entregue fuera del repositorio. Puede ser la misma que dicta.
3. El entorno aislado, con el contenedor y el volumen nuevos `agro_a_f09dev_pg`/`agro_a_f09dev_pgdata` (puertos 55453, 3126 y 3127; Backend `6e4a0e2`), y la APK `.f09voz` del SHA final.
4. **El teléfono del ensayo autorizado para depuración**, con su modelo registrado.
5. **Una persona real junto al teléfono.** La sesión A no inventa frases ni expectativas, ni usa TTS para sustituirla. **Sin ella, el reconocimiento real queda `NOT_MEASURED`**, y se ejecuta sólo lo que no requiere dictado (E1–E4, G1–G3 y los escenarios de V1–V19 que no dependen del habla). HONOR, `NOT_MEASURED` (D-F09-6), salvo que sea el teléfono nuevo.
