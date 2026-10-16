# Evidencia F06-COLL-04 — Registrar y sincronizar necesidad declarada (parte local)

Issue [#34](https://github.com/Roderich1/AppMovilAgroquimico/issues/34). El detalle está en [F05_MOBILE_SYNC](F05_MOBILE_SYNC.md). Ejecutado con Claude Code el 2026-10-15 sobre `30c04b63a43dbd610414d81e58b2e5ad556a3dbe` (base `main` `3eecb2d`), en host y sin dispositivo.

**Alcance de esta entrega:** registro local, versiones y encolado de la versión vigente. La verificación colectiva (consolidación en Central y Web, D4/F07) queda fuera; por eso el PR usa `Refs #34`.

F06 §3: la necesidad sólo nace de una declaración expresa, con la confirmación «Declarar al sindicato: X L de … para …». No se infiere de planes, stock ni consumo, y `application_plans` no se toca.

| Criterio | Prueba | Resultado |
| --- | --- | --- |
| Activado y sin conexión, declarar guarda la necesidad en la campaña de su fecha de referencia sin cambiar existencias | `declared_need_test.dart` «declarar sin conexión…» (volcado completo de las demás tablas igual) | PASS |
| Modificar conserva la versión anterior; sólo la nueva queda vigente por agricultor, campaña y producto | «modificar conserva la versión anterior…»; `UNIQUE(owner_binding_id, campaign_id, product_id)` | PASS |
| Retirar: deja de estar vigente, conserva el historial y queda pendiente de envío | «retirar: deja de estar vigente…» (CANCEL sin cantidad) | PASS |
| Cero explícito es distinto de no declarar | «cero es una declaración explícita…» | PASS |
| El contenido a enviar sólo lleva los campos autorizados | `need_sync_payload_test.dart` (envelope de seis claves; payload con la whitelist exacta; nada privado) | PASS |
| Sin campaña determinable, no se asigna en silencio | «sin campaña determinable no se asigna en silencio» (ninguna o más de una); «una campaña sin vínculo vigente pide vincular» | PASS |

Comandos: `flutter test test/declared_need_test.dart test/need_sync_payload_test.dart` y `flutter test` (947/947).

Limitación: la necesidad pertenece al titular vinculado (contribución por Member, F06 §4). Sin titular no se declara.

**Nota del 2026-10-15 (dispositivo).** El E2E en el POCO encontró un fallo de este criterio que las pruebas de host no veían. Una campaña creada después de las 20:00 en La Paz se guardaba con el día UTC siguiente y no cubría su propio día (D3-DATE). Se corrigió en `023a47b`, con un test de regresión, y se repitió en el dispositivo. Ver [F05_MOBILE_SYNC_DEVICE](F05_MOBILE_SYNC_DEVICE.md) §4.

**Nota del 2026-10-16 (D4, consolidación en Central).** La reconciliación del dataset controlado ejercitó las necesidades declaradas contra Central:

- un cero explícito (F2, Urea) cuenta como aportante, y por eso la celda alcanza el umbral;
- una retirada ya sincronizada llega como `CANCELLED` y no suma (F2, Glifosato);
- ambas campañas se resuelven por fecha de referencia.

Central coincidió con el oráculo a mano (26/26 aportaciones) y el agregado por celda dio diferencia 0 en las dos ejecuciones. Ver `Agro_Sindicato_Backend-Web/docs/evidence/F06_RECONCILIATION.md` y [`F06_RUN_20261016/`](F06_RUN_20261016/).

Retirar una declaración **que nunca se envió** sólo la descarta en la outbox, y Central no llega a verla: es el comportamiento de D3. La vista Web de estas cifras es de F07 (#23–#25).
