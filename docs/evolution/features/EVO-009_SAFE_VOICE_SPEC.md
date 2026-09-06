# EVO-009 — Voz segura: transcripción y vista previa

## Identidad

| Campo | Valor |
|---|---|
| Feature | `EVO-009` |
| Etapa | `EVOLUTION-3` |
| Decisión del propietario | Aprobada el 2026-09-06 |
| Estado | `APPROVED` con dependencia |
| Dependencia | EVOLUTION-2 integrada y verificada |
| Rama prevista | `evolution/evo-009-safe-voice` |

No comenzar implementación mientras EVOLUTION-2 no cumpla su Definition of Done.

## Objetivo

Reducir el tecleo en campo mediante captura y transcripción de voz con una vista previa
editable y control humano. Esta evolución no interpreta ni ejecuta operaciones de dominio.

## Flujo autorizado

```text
Micrófono
→ solicitar/validar permiso
→ escuchar
→ recibir texto parcial/final
→ vista previa editable
→ aceptar / editar / descartar
```

Aceptar confirma únicamente el texto de la sesión. No confirma una compra, pago, aplicación,
transferencia, reversión, cierre, cantidad ni cambio de inventario.

## Alcance

- Puerto `SpeechTranscriptionPort` o nombre equivalente.
- Adaptador de plataforma reemplazable.
- Controlador de sesión independiente de widgets y repositorio.
- Texto parcial y final.
- Vista previa editable.
- Aceptar, editar, reintentar y descartar.
- Permiso contextual de micrófono.
- Idioma principal español, preferencia `es-BO` y fallback visible.
- Manejo de lifecycle, interrupciones, denegación y servicio no disponible.
- Tests con fake y verificación real en Pixel 8.

## Fuera de alcance

- Interpretar intención o entidades agrícolas.
- Convertir texto en comandos tipados.
- Ejecutar `AgroRepository`, casos de uso, SQL o SQLite.
- Registrar compras, pagos, aplicaciones o transferencias.
- Confirmar cantidades, costos, moneda, productos, personas o chacos.
- Guardar audio o transcripciones como historial operativo.
- IA generativa, backend, sync o autenticación.
- `EVO-010`.

## Arquitectura

```text
VoiceScreen
    ↓
VoiceSessionController
    ↓
SpeechTranscriptionPort
    ↓
PlatformSpeechTranscriber
```

El puerto no expone SQLite ni operaciones agrícolas. El controlador produce un resultado de
sesión en memoria y estados observables.

## Estados mínimos

| Estado | Significado |
|---|---|
| `idle` | Sin sesión activa |
| `requestingPermission` | Esperando permiso |
| `listening` | Micrófono activo |
| `processing` | Esperando resultado final |
| `preview` | Texto editable disponible |
| `accepted` | Texto de sesión aceptado, sin ejecutar dominio |
| `cancelled` | Sesión descartada |
| `denied` | Permiso rechazado |
| `unavailable` | Servicio/locale no disponible |
| `error` | Fallo recuperable y seguro |

## Requisitos

| ID | Requisito |
|---|---|
| EVO-009-REQ-001 | La transcripción siempre pasa por una vista previa editable. |
| EVO-009-REQ-002 | Aceptar no llama repositorios, casos de uso ni SQLite. |
| EVO-009-REQ-003 | Descartar elimina el texto de sesión y libera el micrófono. |
| EVO-009-REQ-004 | El permiso se solicita en contexto y se manejan denegación temporal/permanente. |
| EVO-009-REQ-005 | Salir, ir a background o sufrir una interrupción detiene/libera recursos. |
| EVO-009-REQ-006 | Audio no se persiste por defecto. |
| EVO-009-REQ-007 | Transcripción permanece en memoria salvo acción explícita permitida. |
| EVO-009-REQ-008 | La UI muestra locale y no promete offline si el motor no lo garantiza. |
| EVO-009-REQ-009 | Plugin/SDK queda aislado detrás de un puerto testeable. |
| EVO-009-REQ-010 | Errores no modifican estado operativo ni dejan una sesión falsa aceptada. |
| EVO-009-REQ-011 | La pantalla declara que ninguna operación será ejecutada. |

## Decisiones técnicas pendientes

Antes de modificar código debe crearse un ADR que documente:

- motor local, servicio del dispositivo o remoto;
- soporte real de `es-BO`;
- necesidad de Internet;
- datos enviados y proveedor;
- licencia, mantenimiento y compatibilidad Flutter/Android API 36;
- límites de sesión, timeouts y resultados parciales;
- escape hatch para reemplazar el proveedor.

La aprobación de la feature no aprueba automáticamente un proveedor remoto.

## Privacidad

- No persistir audio.
- No incluir transcripción completa en logs.
- No enviar audio fuera del dispositivo sin decisión explícita, aviso y documentación.
- Minimizar identificadores y metadata.
- Explicar si el servicio del dispositivo puede usar red.

## Pruebas

- Permiso concedido, denegado y permanentemente denegado.
- Inicio, parcial, final y vista previa.
- Edición, aceptación y descarte.
- Servicio/locale no disponible.
- Error, timeout, doble toque e interrupción.
- Background, dispose y navegación atrás liberan el micrófono.
- Fake determinista del puerto.
- Guardas que demuestren ausencia de llamadas a SQLite/dominio.
- Fuente 130 %, transcripción larga y orientación.
- Prueba real de micrófono en Pixel 8/API 36.
- Modo avión documentando el comportamiento real.

## Criterios de aceptación

- [ ] Flujo completo produce y edita texto.
- [ ] Aceptar sólo confirma texto de sesión.
- [ ] Ningún camino escribe en SQLite o ejecuta dominio.
- [ ] Permiso, lifecycle, error y cancelación son seguros.
- [ ] Política local/remota y retención están documentadas.
- [ ] Tests, CI, build y Pixel 8 tienen evidencia.

## Rollback

Retirar ruta, UI, controlador y adaptador. No existe downgrade de datos porque EVO-009 no
cambia schema ni persiste audio/transcripciones.

