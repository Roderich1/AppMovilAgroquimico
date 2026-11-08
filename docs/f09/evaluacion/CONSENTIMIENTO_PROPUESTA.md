# F09: texto de consentimiento para la evidencia de dictado, propuesta v2 (#167)

- **Fecha real:** 2026-11-08 (Bolivia, UTC−4). Rama `docs/f09-protocolo-guion`, desde `27e9a4e`.
- **Estado:** **propuesta, pendiente del autor.** No se usa con participantes sin la aprobación de Roderich.
- **Base:** lo que hace el código en `27e9a4e` (§3). Donde el texto anterior prometía algo que el código no hace, esta versión lo corrige.

## 1. Texto propuesto (v2)

Los corchetes marcan lo que depende de una decisión pendiente (§4).

> **Evaluación de la voz de Agrocuentas**
>
> Le pedimos permiso para guardar en este teléfono algunos datos de sus dictados. Sirven sólo para evaluar si la voz de la app entiende bien.
>
> **Es voluntario.** Si no acepta, puede usar la voz y los formularios igual que siempre.
>
> **Qué se guarda**, por cada dictado:
> - el texto que la app entendió;
> - lo que la app propuso (productos, cantidades, precios, chaco, personas);
> - lo que usted corrigió y lo que confirmó;
> - si se registró, se canceló o falló;
> - la fecha y la hora, el reconocedor usado y la versión de la app.
>
> **No se graba su voz.**
>
> **Quién lo ve:** sólo la persona que hace la evaluación, con este teléfono [conectado a su computadora durante la sesión]. No se envía al sindicato, no se sincroniza y no entra en los respaldos. En los informes sólo aparecen conteos y resultados, nunca lo que usted dijo.
>
> **Cuánto tiempo:** hasta terminar su sesión de evaluación, y como máximo [30] días después.
>
> **Cómo borrarlo:** en Más → Registrar por voz → Evaluación de la voz.
> - «Borrar lo guardado» borra todo y el permiso sigue.
> - «Retirar el permiso» borra todo y no se guarda nada más.
> - Desinstalar la app también lo borra.
>
> [Si en este teléfono se restaura un respaldo, la app guarda por seguridad una copia de los datos anteriores, que puede incluir esto, durante unos días.]
>
> ¿Acepta?

Botón: «Acepto». El estado y los botones de borrar se quedan como están en la pantalla.

## 2. Diferencias con el texto que muestra hoy la pantalla

Texto actual: `voiceEvidenceConsentText` en `lib/presentation/voice/voice_evidence_consent_screen.dart:24-30`, versión `F09-CONSENT-PROPUESTA-2026-11-08` (línea 22). Es el de `README.md`.

| Punto | Texto actual | Propuesta v2 | Por qué |
|---|---|---|---|
| Voluntario | No lo dice | Lo dice, y que la voz y los formularios siguen igual | Así funciona el código: el sumidero nulo no cambia nada (`voice_evidence_hook.dart`) |
| Fecha, reconocedor y versión | No los menciona | Los menciona | Se guardan `recorded_at`, `consent_granted_at`, `engine` y `app_commit` (`lib/voice_evidence/voice_evidence_store.dart:192-214`) |
| Resultado | No lo menciona | «si se registró, se canceló o falló» | Columna `outcome` |
| Quién lo ve | No lo dice | El evaluador, con este teléfono | Ninguna pantalla muestra la evidencia. Hoy sólo se lee copiando la base (A18) |
| Plazo | No lo dice | [30] días como máximo | La app no borra sola (A19) |
| Cómo borrar | «Puede retirar el permiso… se borrará todo» | Dónde está y qué hace cada botón | `revokeConsent` y `eraseAll` (`voice_evidence_store.dart:146-153`) |
| Copia previa | Implícito «se borrará todo» | Frase entre corchetes | La copia `.previo` puede conservarla (A20, [`COPIA_PREVIA_Y_EVIDENCIA.md`](COPIA_PREVIA_Y_EVIDENCIA.md)) |
| «no entran en el respaldo» | Sí | Sí | Correcto (`backup_service.dart:734-748`) |

**Lo que el texto no promete a propósito:**
- La **referencia de la ficha**: la tabla tiene la columna (`sheet_ref`), pero la app no la llena (A15). Si la coordinadora la conecta, se añade «el código de la ficha de prueba».
- El **modelo** del reconocedor: tampoco se llena.
- Los **tiempos**: tampoco.

**Lo que la pantalla tiene que cambiar cuando el autor apruebe el texto** (código de la coordinadora, no de esta rama):
1. Sustituir el texto. La pantalla muestra hoy un solo `Text`; la v2 tiene párrafos y una lista.
2. Cambiar la versión, por ejemplo `F09-CONSENT-v2-<fecha de aprobación>`. El identificador admite de 1 a 100 caracteres (`voice_evidence_store.dart:117-124`).
3. Pedir de nuevo el consentimiento en los teléfonos que aceptaron la versión anterior. `grantConsent` conserva el consentimiento existente con su versión (`:126-128`) y `record` no compara versiones, así que, si no se hace, esos teléfonos siguen guardando bajo el texto anterior (A21). Basta con «Retirar el permiso» y «Acepto» en cada teléfono, o con un cambio de código que compare la versión.

## 3. Lo que hace el código (comprobado leyendo `27e9a4e`)

| Hecho | Dónde |
|---|---|
| Sólo una compilación con `AGRO_VOICE_EVIDENCE=true` guarda algo. Sin esa opción, el sumidero es nulo y la pantalla de consentimiento no aparece | `voice_evidence_hook.dart:28` y `:76-77`; `voice_entry_screen.dart:73` |
| Sin consentimiento vigente no se guarda nada; se comprueba en la misma transacción que escribe | `voice_evidence_store.dart:185-187` |
| Un dictado que empezó antes del consentimiento no se guarda | `:188-191` |
| Una sola entrada por borrador, al salir de la pantalla (registrar, cancelar, Atrás, formulario manual). Sin ningún dictado aplicado, ninguna | `voice_evidence_hook.dart:55-72` |
| Nunca audio: no hay columna ni parámetro | `lib/data/app_database.dart:67-90` |
| Borrado con `secure_delete` | `voice_evidence_store.dart:165-177` |
| Un único consentimiento por teléfono, sin identificar a la persona | Tabla `voice_evidence_consent`, `id = 1` (`app_database.dart:68-72`) |
| La pantalla muestra «Permiso: dado. Dictados guardados: N», nunca lo dictado | `voice_evidence_consent_screen.dart:121-127` |

## 4. Decisiones pendientes del autor que afectan al texto

| Corchete | Decisión | Referencia |
|---|---|---|
| «[conectado a su computadora durante la sesión]» | Si se añade una vista de lectura en el teléfono, se quita | A18 |
| «[30] días» | Plazo de conservación | A19 |
| Frase de la copia previa | Se quita si se implementa la guarda M2 | A20 |

Otra decisión que no cambia el texto, pero sí el procedimiento: una persona por turno, y «Retirar el permiso» antes de la siguiente (A17).
