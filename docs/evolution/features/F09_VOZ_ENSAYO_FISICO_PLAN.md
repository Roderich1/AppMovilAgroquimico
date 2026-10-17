# F09 — Plan del ensayo físico de voz

- **Estado:** plan preparado el 2026-10-17 por la sesión C. **No se ha ejecutado.**
- **Quién lo ejecuta:** la sesión A (es la única que usa el POCO), con turno.
- **Requisito no negociable:** **dictado real de una persona** junto al teléfono. Un texto inyectado, el fake o un audio sintético prueban la lógica, no el motor. Sin una persona que dicte, el reconocimiento queda `NOT_MEASURED`.
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #12 y #17, con #11, #14, #15 y #16.

## 1. Qué se necesita antes

1. **Una versión candidata.** El APK debe salir de un SHA que ya tenga la captura (PR #99), los borradores (PR #100, #101 y el de #15) y la **conexión con las rutas y los formularios**, que A integra después de F04. Se anotan el SHA, el SHA-256 del APK y si es debug, profile o release.
2. **Datos sintéticos de catálogo, sin datos reales:**
   - productos «Bellator», «Belator» (para la ambigüedad), «Glifosato» (L) y «Expansive» (KG);
   - el proveedor «Agro Norte»;
   - los chacos «Sur» y «Norte»;
   - una campaña activa;
   - stock de Glifosato para el titular.
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

Los resultados negativos se conservan tal cual.

## 3. Banco de voz y holdout (#12, `docs/evolution/features/F09_VOZ_03_HOLDOUT_FISICO_EVIDENCE.md`)

- **Banco:** `benchmark/voice_benchmark`, con los mismos registros por toma que ya exporta: no-speech, hashes, candidate IDs, p50, p95, RTF y slots.
- **Holdout actual: expuesto.** La partición `aceptacion` (60 frases) está en el repositorio y es visible. Si se ejecuta, **se informa como holdout expuesto**, no como ciego.
- **Holdout ciego nuevo (D-F09-5, pendiente):**
  - lo escribe una persona que no ajustó las reglas (propuesta: Roderich), fuera del repositorio;
  - su SHA-256 y este protocolo se fijan **antes** de la primera toma;
  - no se usa para ajustar nada;
  - se publica después de medir.
- **Dispositivos:**
  - POCO X5 Pro (A1).
  - HONOR JDY-LX3P: si no está disponible para la sesión, **`NOT_MEASURED`** (D-F09-6). No se sustituye por un emulador ni por el mismo POCO.
  - Pixel 8 / API 36: `WAIVED_BY_OWNER` (ADR-002), sin cambios.
- **Resultados:** por dispositivo, sin promediar. Lo no medido figura como `NOT_MEASURED`, nunca como cero ni como PASS.

## 4. Lo que este ensayo no decide

- No cambia ningún gate. La decisión de GATE-F09 (#17) es de Roderich, con el acta que redacte C.
- No mide la falsa aceptación sobre texto crudo (ADR-002, «Lo que sigue sin medirse»).
