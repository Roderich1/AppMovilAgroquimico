# F09 — Plan del ensayo físico de voz

- **Estado:** plan preparado el 2026-10-17 por la sesión C. **No se ha ejecutado.**
- **Quién lo ejecuta:** la sesión A (es la única que usa el POCO), con turno.
- **Requisito no negociable:** **dictado real de una persona** junto al teléfono. Un texto inyectado, el fake o un audio sintético prueban la lógica, no el motor. Sin una persona que dicte, el reconocimiento queda `NOT_MEASURED`.
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #12 y #17, con #11, #14, #15 y #16.
- **Actualización del 2026-10-17 (tarde), sesión A, antes de medir.** Recoge las decisiones D-F09-1…7, ya tomadas (BE `docs/evaluation/F01_F09_MATRIZ_OPERATIVA.md`, § «Decisiones D-F09-1 a D-F09-7», `main` `e4b9c29`), los escenarios de **aplicar un plan pendiente** (D-F09-4) y el **conjunto nuevo** (D-F09-5). El texto anterior se conserva; lo que cambia se marca «*(2026-10-17)*». Este protocolo y el SHA-256 del conjunto nuevo se fijan **antes de la primera toma** y no se modifican durante la medición.

## 1. Qué se necesita antes

1. **Una versión candidata.** El APK debe salir de un SHA que ya tenga la captura (PR #99), los borradores (PR #100, #101 y el de #15) y la **conexión con las rutas y los formularios**, que A integra después de F04. Se anotan el SHA, el SHA-256 del APK y si es debug, profile o release.
   - *(2026-10-17)* También el incremento de **aplicar un plan pendiente por voz** (D-F09-4, de C) y el criterio 5 de GATE-F04 (MOB #110: la campaña por fecha efectiva). El SHA se fija cuando los dos estén integrados y la CI de ese HEAD exacto esté en verde.
   - Se instala como **copia aislada nueva** (otro `applicationId`), con datos sintéticos. La app normal y la demo no se tocan.
2. **Datos sintéticos de catálogo, sin datos reales:**
   - productos «Bellator», «Belator» (para la ambigüedad), «Glifosato» (L) y «Expansive» (KG);
   - el proveedor «Agro Norte»;
   - los chacos «Sur» y «Norte»;
   - una campaña activa; *(2026-10-17)* con la regla de MOB #110, su período tiene que contener el día del ensayo, o las operaciones se rechazan por fecha;
   - stock de Glifosato para el titular;
   - *(2026-10-17)* para los escenarios de plan pendiente: **dos planes pendientes en «Sur»** (para comprobar que no se elige solo entre varios), uno en «Norte», uno **ya aplicado** y uno de **otra campaña**. Este último se crea antes de cambiar de campaña, con fechas que no se solapen.
3. **Conteos de la base** antes y después de cada escenario, con el mismo método que `tool/f10_eval/eval_counts.sh`: compras, ítems, lotes, movimientos, aplicaciones, planes, productos y proveedores.
4. **Privacidad:**
   - no se graba audio;
   - **no se copian las frases dictadas a la evidencia**: se anotan el número de escenario, el resultado y los códigos;
   - las capturas de pantalla, si las hay, sólo con datos sintéticos.

## 2. Escenarios de la app (`docs/evidence/F09_VOZ_DEVICE.md`)

| ID | Qué se hace | Qué se comprueba | Resultado posible |
|---|---|---|---|
| V1 | Abrir una pantalla de voz y tocar el micrófono por primera vez | El permiso se pide en contexto; con «Denegar», la pantalla explica la salida y deja escribir | PASS / FAIL |
| V2 | Dictar en la configuración del teléfono | Se muestran el idioma pedido y el utilizado; no se promete `es-BO` | PASS / FAIL, con el idioma utilizado |
| V3 | Modo avión activado e intento de dictar | El modo sin conexión se afirma sólo si transcribe; si no, se informa sin bloquear | Lo observado, sin generalizar |
| V4 | Si no hay español local | Aparece el aviso de que el reconocedor del sistema «podría usar Internet» y se pide consentimiento antes de cambiar (D-F09-7) | PASS / FAIL / NOT_APPLICABLE si el español local funciona |
| V5 | Compra: dictar dos líneas con precio, proveedor y persona | Cada campo con su estado; el total calculado; nada escrito antes de confirmar | PASS / FAIL y conteos |
| V6 | Dictar «Belator» o una variante | Queda ambiguo con las dos opciones y bloquea «Registrar compra» | PASS / FAIL |
| V7 | Corregir a mano una cantidad y volver a dictar el producto | La corrección se conserva | PASS / FAIL |
| V8 | Cancelar con el micrófono abierto | El indicador de micrófono se apaga; los conteos no cambian | PASS / FAIL y conteos |
| V9 | Confirmar tocando dos veces seguidas | Una sola compra (+1) | PASS / FAIL y conteos |
| V10 | Planificación dictada y creada | +1 plan; inventario sin cambios | PASS / FAIL y conteos |
| V11 | Aplicación de dos productos | Stock proyectado visible; +1 aplicación; stock descontado como en el formulario | PASS / FAIL y conteos |
| V12 | Ir a Inicio del sistema con el micrófono abierto, y volver | El micrófono se suelta; no hay escritura | PASS / FAIL |
| V13 | Atrás con el micrófono abierto | El micrófono se suelta y el borrador se descarta | PASS / FAIL y conteos |
| V14 | Con la voz no disponible o el permiso denegado | El formulario manual completa la misma operación | PASS / FAIL |

*(2026-10-17)* **Aplicar un plan pendiente por voz (D-F09-4).** Las condiciones de la decisión:
- se elige el plan de forma explícita, por el flujo manual existente;
- sólo se ofrecen planes pendientes de la campaña y el chaco elegidos;
- nunca se elige solo entre varios;
- nada cambia en el plan, el stock ni FIFO antes de confirmar.

| ID | Qué se hace | Qué se comprueba | Resultado posible |
|---|---|---|---|
| V15 | Dictar la aplicación de un plan en «Sur», que tiene dos pendientes | No se elige solo: se muestran los dos y hay que tocar uno. Sin elegir, no se puede confirmar | PASS / FAIL y conteos |
| V16 | Elegir un plan y confirmar | +1 aplicación ligada al plan, que pasa a aplicado; stock y FIFO como en el formulario | PASS / FAIL y conteos |
| V17 | Intentar aplicar el plan ya aplicado, o el de otro chaco o el de otra campaña | No se ofrece o se rechaza con un mensaje; nada se escribe | PASS / FAIL y conteos |
| V18 | Cancelar o volver con un plan elegido | El plan sigue pendiente; los conteos no cambian | PASS / FAIL y conteos |
| V19 | Confirmar el plan con dos toques seguidos | Una sola aplicación (+1); el plan no se aplica dos veces | PASS / FAIL y conteos |

**Registro por separado** *(2026-10-17)*. En cada escenario dictado se anotan tres cosas distintas:
1. el **reconocimiento crudo**: si el motor devolvió texto, con su idioma, sin copiar la frase;
2. las **correcciones manuales** que hicieron falta, por campo;
3. el **resultado de negocio**, con los conteos.
Un PASS de negocio con correcciones no es un PASS de reconocimiento.

Los resultados negativos se conservan tal cual.

## 3. Banco de voz y holdout (#12, `docs/evolution/features/F09_VOZ_03_HOLDOUT_FISICO_EVIDENCE.md`)

- **Banco:** `benchmark/voice_benchmark`, con los mismos registros por toma que ya exporta: no-speech, hashes, candidate IDs, p50, p95, RTF y slots.
- **Holdout actual: expuesto.** La partición `aceptacion` (60 frases) está en el repositorio y es visible. Si se ejecuta, **se informa como holdout expuesto**, no como ciego.
- **Holdout ciego nuevo (D-F09-5, pendiente):**
  - lo escribe una persona que no ajustó las reglas (propuesta: Roderich), fuera del repositorio;
  - su SHA-256 y este protocolo se fijan **antes** de la primera toma;
  - no se usa para ajustar nada;
  - se publica después de medir.
- *(2026-10-17)* **D-F09-5 decidida: conjunto nuevo para la aceptación exploratoria.**
  - **Composición:** 20 dictados nuevos (7 de compra, 6 de planificación y 7 de aplicación) y 2 entradas sin habla.
  - **Quién lo escribe:** una persona que no ajustó las reglas, fuera del repositorio.
  - **Qué se fija antes de la primera toma:**
    - el SHA del código y del intérprete;
    - este protocolo;
    - las expectativas por entrada (operación, campos y si debe bloquear);
    - los criterios;
    - el **SHA-256 del conjunto**.
  - No se ajusta nada con él.
  - **Lo que no es:** el corpus expuesto sigue expuesto y no se presenta como ciego. El conjunto nuevo es una **muestra exploratoria**, no una certificación general, y no hay resultados mientras no se ejecute.
  - **Sin persona que dicte**, el conjunto queda `NOT_MEASURED`. No se lee con TTS ni se inyecta como texto.
- *(2026-10-17)* **D-F09-7 decidida:**
  - el local va primero;
  - el reconocedor del sistema que podría usar Internet se permite sólo con consentimiento visible, **una vez por sesión y sin guardarlo**;
  - `EXTRA_PREFER_OFFLINE` es una preferencia, no prueba de operación sin red;
  - negarse conserva el formulario manual;
  - sin audio ni transcripciones en logs ni en Central (el logcat se revisa con `logcat_scan.sh`).
- *(2026-10-17)* **D-F09-1 y D-F09-2 decididas:** el streaming de #10 queda fuera, y no se crean productos ni proveedores por voz.
- **Dispositivos:**
  - POCO X5 Pro (A1).
  - HONOR JDY-LX3P: si no está disponible para la sesión, **`NOT_MEASURED`** (D-F09-6). No se sustituye por un emulador ni por el mismo POCO.
  - Pixel 8 / API 36: `WAIVED_BY_OWNER` (ADR-002), sin cambios.
- **Resultados:** por dispositivo, sin promediar. Lo no medido figura como `NOT_MEASURED`, nunca como cero ni como PASS.

## 4. Lo que este ensayo no decide

- No cambia ningún gate. La decisión de GATE-F09 (#17) es de Roderich, con el acta que redacte C.
- No mide la falsa aceptación sobre texto crudo (ADR-002, «Lo que sigue sin medirse»).
