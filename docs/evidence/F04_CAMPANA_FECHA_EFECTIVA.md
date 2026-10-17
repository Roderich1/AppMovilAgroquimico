# F04 — Campaña por fecha efectiva (criterio 5 de GATE-F04, #28)

- **Origen:** Live. **Fecha real:** 2026-10-17. Sesión A de Claude Code, por la delegación técnica de Roderich.
- **Base:** Mobile `main` `8a2c5589b8ca4942d7c4800a8c54a669ecc0af8e`. **Rama:** `feat/f04-campana-fecha-efectiva`.
- **Trazabilidad:** RF-03, RF-07, RF-12, RF-17, RF-31, DAT-02; RN-15, RN-16; CU-06, CU-09, CU-19. Refs #28 (GATE-F04 sigue Pending) y Refs #41 (REC-005, que excluía RN-15 y RN-16).

## 1. Qué exige la fuente vigente

| Fuente | Texto (resumen literal) |
|---|---|
| RN-15 (Cap. III v1.5) | Toda operación asociada a una campaña se vincula con la campaña **cuyo intervalo contiene la fecha efectiva**. La fecha de creación, registro o sincronización no modifica la asignación. Si no hay campaña aplicable o la referencia es ambigua, **no se clasifica en silencio** |
| RN-16 | Como máximo **una** campaña por referencia temporal; **los períodos no pueden solaparse**; si no se puede determinar, la operación no se clasifica en una campaña incorrecta |
| RF-03 y su criterio (SRS §7.1) | Mantener períodos no solapados y asociar por fecha efectiva. «Operaciones con fechas de frontera y registros tardíos quedan asociadas al período correcto; un calendario solapado o una fecha sin clasificación válida genera una **condición explícita** en vez de asignación arbitraria» |
| RF-07 / RF-12 (criterios) | Cada línea de compra queda vinculada a la campaña de la fecha efectiva. Una aplicación multiproducto se confirma completa o no produce consumos |
| Cap. III §3.11.13 | Una sola campaña activa en el contexto local. «Las operaciones de períodos cerrados o con referencias desconocidas **requerirán revisión**, conservando su historia» |
| Cap. III, restricciones | «Ante fecha no clasificable, impedir asignación silenciosa. **Las fechas concretas son configuración**» |
| SRS §10.4 | La pertenencia se deriva de la fecha efectiva y del calendario de períodos no solapados; finalizar un período no elimina el histórico |
| Contrato F05 §153 / F06 §116 | Central rechaza publicar en una campaña no abierta (`CAMPAIGN_NOT_OPEN`); un error de campaña requiere revisión, no reapertura automática |

Las fuentes **no se contradicen**. Lo que choca con ellas es la implementación previa (REC #41, que excluyó RN-15 y RN-16 de forma expresa):

- **Selección:** compra y aplicación toman el `campaignId` de la campaña activa, sin mirar la fecha. Una compra del 10/03 registrada hoy entra en la campaña activa aunque su período empiece en julio: asignación silenciosa.
- **Calendario:** `closeCampaign` y `activateCampaign` ponen `end_date` = hoy a la campaña que se cierra, aunque la siguiente empiece antes. Con el diálogo actual, que crea la campaña con inicio = día de creación, **el día del cambio queda en dos campañas** (solapamiento).
- **Validación de fecha:** no existe para operaciones. Sí existe, con la misma lectura de días locales, para las necesidades declaradas de F05 (`DeclaredNeedStore.campaignForDate`: ninguna o ambigua → condición explícita).

## 2. Regla aplicada (propuesta para revisión)

1. **Intervalo.** Una campaña cubre `[inicio, fin]` en **días locales**, ambos inclusivos; `fin` nulo es abierto. Es la misma lectura que `campaignForDate` de F05: las fechas guardadas en UTC se pasan a la zona local antes de tomar el día.
2. **Clasificación de una compra o aplicación.** Se toma el día local de su fecha efectiva (la fecha completa se guarda igual que antes, para FIFO y el orden). Se buscan las campañas que contienen ese día:
   - **exactamente una y es la activa del borrador** → se registra;
   - **ninguna** → rechazo explícito: «La fecha dd/mm/aaaa no está dentro de ninguna campaña…»;
   - **más de una** → rechazo explícito: calendario solapado (sólo puede venir de datos anteriores a esta regla);
   - **una, pero no la activa** (cerrada o planificada) → rechazo explícito con su nombre: las operaciones de un período cerrado requieren revisión (§3.11.13); no se reabre ni se reasigna.
   Toda la comprobación ocurre dentro de la transacción, antes de escribir: un rechazo no deja cabecera, líneas, lotes, consumos, movimientos ni cuentas.
3. **El calendario se mantiene sin solapes, en el momento en que cambia y sin mover operaciones:**
   - **Alta de campaña.** La nueva debe empezar **después** del inicio de todas las existentes (las campañas se agregan en orden; no se intercalan). Si la anterior está abierta, su fin pasa a ser el día anterior al inicio de la nueva. Si esa campaña anterior ya tiene operaciones en ese día o después, el alta se rechaza, sin cambios. Si la anterior tiene un fin fijado y la nueva empieza antes o en ese día, se rechaza.
   - **Activar** sólo cambia estados. Ya no borra el `fin` de la campaña activada ni pone «hoy» como fin de la cerrada. Para bases anteriores a esta regla, si la campaña que se cierra sigue abierta, su fin pasa a ser el día anterior al inicio de la activada, con las mismas condiciones; si no se puede, se rechaza sin cambios.
   - **Cerrar sin sucesora.** Si la campaña está abierta, su fin pasa a ser hoy. Se rechaza si tiene operaciones con fecha posterior a hoy. Si ya tenía fin, se conserva.
4. **Diálogo de alta.** Pide la fecha de inicio. Por defecto propone hoy, o el día siguiente al fin de la última campaña si ese día es posterior. El repositorio vuelve a validar.
5. **Histórico.** No se migra ni se reasigna ninguna fila. Un solapamiento heredado no se corrige solo: sus días quedan como «ambiguos» y la operación nueva en esos días se rechaza de forma explícita.

**Fuera de alcance (sin cambio):**
- planes, porque no son operaciones con fecha efectiva (su `planned_date` es opcional);
- pagos, que cruzan campañas a propósito (saldo por persona);
- transferencias, que no llevan campaña;
- reversiones, que no reclasifican.
Aplicar un plan sí pasa por la regla, porque crea una aplicación.

## 3. Pendiente

Implementación, pruebas (host) y resultados: se completan en este mismo archivo cuando estén. Nada de esto es DEVICE.
