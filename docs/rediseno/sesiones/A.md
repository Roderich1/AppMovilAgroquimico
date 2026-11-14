# Sesión A — aplicación y planificación (con voz)

Leer antes `sesiones/COMUN.md` y `COORDINACION.md`.

- Láminas: Aplicacion1, Aplicacion2, Aplicacion3, VozAplicacion, Plan, VozPlan. Estados de voz de referencia: VozEscuchando, VozProcesando, VozListo, VozRevisar (la compra ya los implementa con `VoiceFormPanel(docked:)`, `VoiceResultBanner`, `VoiceSlotMark(onWriteOther:)`).
- Rutas: `/aplicaciones/nueva`, `/planificacion/nueva`, `/aplicaciones`, `/planificacion` (listas).
- Primera tarea, antes de tocar el paso 1: determinar en código y contratos qué es «Persona» en la aplicación (`application_form_screen.dart`; en propio «Aplica el titular»; la voz pone al dueño del chaco; ver `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md`, `15_BUSINESS_RULES.md`, `D04_E15_*`). Si es el responsable del chaco, usar «Responsable del chaco» o el término vigente; no crear un campo nuevo ni cambiar su efecto. Anotar la conclusión con referencias en tu estado.
- Voz: Vosk + revisión Whisper base, sin cambios de motores, puertos, intérprete ni reglas de mezcla. `voice_form_dictation.dart` es del orquestador: si el panel necesita algo nuevo (p. ej. un ejemplo de frase distinto), ya acepta `example:` y `engineHint:`; para más, solicitud.
- Avisos a conservar: lote vencido, falta de existencias, cambio de chaco, cantidades pendientes. Crear un plan no descuenta inventario ni genera cargos.
- Pasos con un único borrador; volver no pierde datos; «¿Descartar cambios?» al salir con datos.
