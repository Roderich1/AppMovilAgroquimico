# EVOLUTION-3 — Matriz de trazabilidad inicial

Estado documental: `APPROVED`; evidencia de implementación: pendiente.

| Requisito/capacidad | Diseño/autoridad | Evidencia mínima para cierre |
|---|---|---|
| Captura, permiso y lifecycle | `EVO-009`, ADR-002 | unit/widget/device, modo avión e interrupciones |
| Sesión continua y preview editable | `EVO-009` | corpus + widget + Pixel 8 |
| Intención y draft tipado | `EVO-010`, ADR-003 | corpus separado, unit y paridad |
| Ambigüedad bloqueante | `EVO-010`, política de confirmación | homónimos, aliases, baja confianza |
| Compra por voz | `EVO-017` | repository atomicity + paridad UI/inventario |
| Crear catálogo + compra atómica | `EVO-017` | fallo inducido en cada paso, base sin diff |
| Aplicar plan por voz | `EVO-018` | planes 0/1/N, FIFO, stock, one-shot |
| Pago por voz | `EVO-019` | saldos, excedente/adelanto, homónimos |
| Cero escritura preconfirmación | Política + todos los specs | spy/repository/database snapshot |
| Privacidad de audio/texto | Política + ADR-002 | inspección de storage/logs y lifecycle |
| Performance/offline | Plan de benchmark | resultados versionados en dos dispositivos |
| Consultas futuras | `EVO-020` | No aplica; estado `DEFERRED` |

## Registro de implementación a completar por PR

| Feature | Rama | PR | SHA final | CI | Device | Estado |
|---|---|---|---|---|---|---|
| EVO-009 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-010 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-017 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-018 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |
| EVO-019 | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | APPROVED |

No sustituir `Pendiente` por evidencia supuesta. Un merge sin run/dispositivo no completa la
fila.

