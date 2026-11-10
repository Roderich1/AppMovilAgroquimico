# F09: formulario único con «Completar por voz» (2026-11-10)

Rama `feat/f09-voz-formulario-unico` (worktree `_wt/F09-UNI`), creada desde `5665496` (rama `feat/f09-compra-voz-small`: la integración verificada e instalada en `.f09`). Sin push, sin PR, sin cambios en issues ni en el documento de grado.

## 1. Qué cambia

Antes había, para cada operación, un formulario normal y una pantalla de voz aparte con su propio borrador, campos y botón de registro. Ahora hay **un solo formulario por operación** («Nueva compra», «Nueva aplicación», «Nueva planificación»), con sus títulos, pasos, validaciones y guardado de siempre, y una acción **«Completar por voz»** que abre un panel compacto. Lo dictado aparece en los campos y líneas habituales; nada se guarda solo.

- `Registrar por voz` y los atajos `/compras/voz`, `/planificacion/voz`, `/aplicaciones/voz` abren el formulario normal con el panel visible; el micrófono no se abre hasta pulsar «Hablar». Los formularios aceptan `?voz=1`.
- Se retiraron las tres pantallas de borrador por voz, `voice_alternative.dart` y los widgets que sólo ellas usaban.

## 2. Motores (sin cambios)

| Operación | Puerto | Motor y parámetros |
|---|---|---|
| Compra | `purchaseSpeechPortFactoryProvider` → turno entero | Whisper small q5_1, haz de 5, `es`, temperatura 0, sin reintentos, pista breve de la compra (≤ 400 caracteres) |
| Aplicación | `speechPortFactoryProvider` | Vosk por frases + revisión de Whisper base (la de siempre) |
| Planificación | `speechPortFactoryProvider` | Vosk por frases + revisión de Whisper base |

No se cambiaron modelos, cuantización, pistas ni parámetros. El panel adapta el texto de ayuda al motor («diga la compra completa y pulse Terminar» / «hable por frases cortas»), sin nombres técnicos.

## 3. Arquitectura

- `lib/voice_draft/form/voice_form_merge.dart` (Dart puro, sin interfaz ni persistencia): fotos del formulario por ranuras, propuesta de un dictado, `planVoiceMerge` (reglas de §4) y `planVoiceUndo` (deshacer).
- `lib/presentation/voice/voice_form_dictation.dart`: `VoiceFormDictation` (sesión de voz de siempre + ciclo de un dictado), `VoiceFormPanel` (Hablar, Terminar, Cancelar dictado, estados, errores, deshacer) y `VoiceSlotMark` / `VoiceMissingMark` (estado de cada campo).
- Un puente por operación, como `part` del formulario (`purchase_form_voice.dart`, `plan_form_voice.dart`, `application_form_voice.dart`): foto canónica del formulario, sombra con el **intérprete de siempre** (`interpretPurchase`, `interpretPlan`, `interpretApplication`) y aplicación del plan sobre los controles del formulario.

Ciclo de un dictado: «Hablar» toma una **foto del formulario** y empieza una interpretación propia del dictado (la sombra, que acumula las frases); nada cambia en el formulario mientras se graba o procesa; al terminar el turno se compara lo dictado con la foto y con el formulario actual y se aplica el plan. Cancelar descarta la sombra. Al salir del formulario se libera el micrófono.

## 4. Reglas de combinación

| Caso | Regla |
|---|---|
| Campo vacío y valor inequívoco | Se completa y se marca «Por voz» |
| Mismo valor | Se conserva, sin duplicar |
| Otro valor | «Elegir»: «Mantener» o «Usar lo dictado»; nunca se sobrescribe solo |
| Ambiguo o por revisar | «Revisar» con sus opciones (p. ej. «Por L» / «Total de la línea»); el campo no cambia hasta elegir |
| Información ausente | Se conserva lo que había |
| Editado mientras se procesaba | Gana la persona; se informa |
| Línea dictada con producto | Usa la primera línea completamente vacía que ya existía; si no, se añade (se ve como nueva) |
| Línea empezada a mano (producto sin cantidad o precio/dosis) | Si el dictado **nombra** ese producto, completa esa línea (comportamiento del intérprete de siempre); lo que ya tiene sigue la regla «Otro valor» |
| Cantidad dictada sin nombrar producto | No se asigna a ciegas; el intérprete lo avisa |
| Producto repetido | Nunca se suman ni fusionan líneas; la línea nueva queda con el producto «por revisar» |
| Negación, otra intención, ruido | Ningún cambio; se dice por qué |
| Nuevas líneas | Se muestran con «Por voz» y «Falta: …» de lo obligatorio que falte |

«Deshacer último dictado» revierte sólo lo atribuible a ese dictado (campos que siguen con el valor que puso la voz y líneas que añadió sin tocar); lo editado después se conserva y se informa.

Mientras hay un dictado en curso o algo por elegir o revisar, el botón de avance del formulario («Continuar», «Guardar planificación») se deshabilita y se dice por qué.

## 5. Reglas de cada operación que la voz no esquiva

- **Compra**: proveedor, destinatario por línea (en compartido, «Toda para una persona»; en propio, el titular: la persona dictada se ignora y se avisa), precio por unidad frente a total de la línea, pago y campaña como siempre; un solo registro con «Confirmar compra». No se puede repetir un producto en dos líneas (regla del formulario).
- **Aplicación**: el responsable es el dueño del chaco; un chaco de otra persona con una persona ya elegida se pregunta (cambiarlo vacía la mezcla). Las líneas usan las existencias del responsable y su costo FIFO; sin existencias, el aviso de siempre lo rechaza. Un plan pendiente pedido por voz abre el recorrido de siempre «Aplicar este plan» (tras confirmar si hay cambios). Nada cambia inventario ni cuentas antes de «Confirmar aplicación».
- **Planificación**: chaco, área y dosis por hectárea (no cantidad total); el chaco dictado no pisa un área escrita; una línea dictada cuyo producto queda por elegir muestra su selector y «Guardar planificación» no la acepta así. Un plan no toca inventario ni cuentas. «Guardar» ignora un segundo toque (antes sólo se deshabilitaba el botón).

## 6. Diagnóstico, evidencia y privacidad

- Diagnóstico sólo con `AGRO_VOICE_DIAG=true`: tarjeta de turno entero (modelo, métricas sin texto) en la compra; «Política B», «Comparar pistas» y propuestas por motor en aplicación y planificación. «Usar la otra propuesta» se retiró con la pantalla de compra por frases.
- Evidencia (#167) sin cambios de consentimiento: con consentimiento y compilación de evaluación, una entrada por formulario (CONFIRMED / DISCARDED / FAILED) con lo que propuso el último dictado y los tiempos de la sesión; sin consentimiento, nada.
- Lectura de pantallas (`tool/f09_emu`): los formularios unificados se reconocen y se leen sólo con la lista blanca; las capturas se bloquean en ellos; autoprueba sintética ampliada.

## 7. Pruebas (texto inyectado sintético: integración, no precisión)

- `test/voice_draft/form_merge_test.dart`: reglas de combinación y deshacer (Dart puro).
- `test/voice_draft/compra_formulario_unico_test.dart`, `plan_formulario_unico_test.dart`, `aplicacion_formulario_unico_test.dart`: manual, vacío, mixto, conflicto, edición durante el procesamiento, repetido, deshacer, cancelación y resultados tardíos, ambiguo, negación, registro único con efectos, plan sin inventario ni cuentas, existencias, chaco de otra persona, plan por voz, salida que libera el micrófono.
- `test/voice_draft/formulario_unico_accesos_test.dart`: accesos con panel y micrófono cerrado, botón del formulario, inventario propio y los casos del POCO P1–P4 dentro del formulario.
- `test/voice_evidence/voice_evidence_wiring_test.dart`: evidencia con y sin consentimiento, portada al formulario.

## 8. Limitaciones y pendientes

- Sin comprobación en el teléfono hasta la APK candidata (§9 del informe de entrega).
- `VoiceDraftGateway` (sus `confirm*`) y `VoiceDraftController` ya no los usa la app; se conservan porque los usan pruebas de dominio de los borradores de voz; retirarlos exige reescribirlas.
- `lib/voice/ui/voice_capture_screen.dart` (`VoiceListeningPanel`, `VoiceCaptureScreen`) quedó sin uso en la app; el panel nuevo no ofrece el consentimiento del reconocedor del sistema (sólo aplica si el motor local no está disponible y se permite el del sistema). Pendiente de decisión.
- La evidencia compara lo que propuso el último dictado, no las correcciones hechas en el formulario.
- La aplicación no admite dictar sobre un plan ya cargado (`?planId`): persona, chaco y productos vienen del plan.
