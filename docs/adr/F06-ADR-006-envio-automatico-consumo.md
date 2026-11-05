# F06-ADR-006 — Envío automático del consumo con autorización por campaña: decisión de alcance

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-05 (America/La_Paz), redacción |
| Estado | **Proposed.** Propuesta para que Roderich Rendón decida. No es una decisión, no activa ningún envío y no cambia ningún gate |
| Autor | Redactado por Claude Code a pedido de Roderich, bloque UXJ-C (rama `feat/uxj-c-consumo-vinculos`, desde Mobile `f534015`) |
| Base de lectura | Mobile `f534015`. Backend/Web `main` `5973b49`: los contratos se leyeron en la rama `docs/propuesta-consumo-automatico` (`82960a2`), cuya carpeta `docs/architecture/` es idéntica a la de `5973b49` |
| Trazabilidad | RF-16, RF-18, RF-24, RF-03, RN-15, RN-16, CU-05, CU-11, CU-13 |
| Relacionados | Refs Roderich1/Agro_Sindicato_Backend-Web#202 (propuesta `docs/evaluation/F06_PUBLICACION_AUTOMATICA_CONSUMO_PROPUESTA_2026-11-05.md`, Proposed, decisiones D-1 a D-15). Mobile #33 (publicación del consumo) y #31 (worker). Mobile `docs/evidence/F06-COLL-03_sincronizacion_consumo_colectivo.md` |

**Numeración.** 006 evita chocar con `BE-ADR-002` y `F08-ADR-003` (esta carpeta) y con `ADR-004` y `ADR-005` de voz (`docs/evolution/decisions/`, ramas de voz). El prefijo F06 dice qué proyección toca. Si Roderich prefiere otro número al aceptarla (D-15 de #202), se renombra sin cambiar el contenido.

## 0. Lo que este documento no hace

- **No activa el envío automático.** No hay código, bandera, tabla ni configuración nueva para eso.
- **No añade** la opción «Vincular y compartir consumo automáticamente» ni la de pausar el envío automático: sin envío automático no hay nada que pausar.
- **No enmienda** F06, F05 ni F04. Describe las enmiendas que harían falta (§4) para que Roderich las decida.
- La política vigente sigue igual: el consumo se publica sólo cuando el agricultor pulsa «Publicar» (Mobile #33).

## 1. Pedido del autor (2026-11-05), resumido

1. Distinguir «Vincular» de «Vincular y compartir consumo automáticamente». La segunda, con una confirmación que diga qué total se comparte y si el primer envío incluye el consumo ya registrado en la campaña. Los vínculos anteriores no cambian. Limitado a la campaña autorizada.
2. Con autorización, una aplicación confirmada del titular o su reversión recalcula el total por campaña, producto y unidad. El envío pendiente se guarda y se recupera tras un cierre de la app. Se reutilizan la cola, los ids, los reintentos y la sustitución. El servidor recibe el nuevo total una sola vez.
3. En Vínculos, un texto inicial corto y los motivos de incompatibilidad en la fila afectada. En Consumo, los estados «Pendiente», «Enviado» y «Requiere atención», y una opción para pausar el envío automático, distinta de retirar un total ya aceptado.
4. Conservar el alcance (total del titular por campaña, producto y unidad), la separación entre necesidad declarada y consumo, los controles del servidor y los datos sintéticos. **Si el contrato vigente impide el envío automático con esa autorización, identificar la cláusula exacta y registrar la decisión de alcance antes de activar el cambio.**

## 2. Cláusulas vigentes

Texto literal, con archivo, sección y línea en la base de lectura.

| # | Archivo, sección y línea | Texto literal | Efecto sobre el pedido |
|---|---|---|---|
| M-1 | Mobile `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §2.4, línea 137 | «**Una confirmación tardía es privada:** **no se publica automáticamente**, y la publicación de consumo sigue siendo una acción expresa del agricultor.» | **Lo impide.** Es una decisión del autor del 2026-10-23 y dice, sin excepción, que publicar el consumo es una acción expresa. Una autorización previa por campaña no es una acción expresa sobre cada total. |
| M-2 | Mobile `F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §2.3, línea 124 | «confirmar una operación tardía **no encola nada**: ningún PUBLISH ni SUPERSEDE automático hacia una campaña cerrada o sellada;» | **Compatible.** Las tardías son de campañas `CLOSED` y quedan fuera del alcance (sólo campañas activas y autorizadas). Se conserva sin cambios. |
| M-3 | Mobile `F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §2.4, línea 140 | «lo trata como un **fallo terminal que requiere intervención**: sin backoff ni reintentos, sin reasignar a otra campaña. **Tampoco se reenvía al reiniciar la app**» | **Restricción de diseño.** Un productor automático no puede volver a enviar tras `CAMPAIGN_NOT_OPEN` o `CAMPAIGN_SEALED`. |
| B-1 | Backend `docs/architecture/F06_COLLECTIVE_PROJECTION_CONTRACT.md` §2, línea 39 | «No se exige publicar si el agricultor no ha emitido una intención autorizada.» | **No lo define.** Admite una intención *autorizada*, pero no dice si una autorización permanente, revocable y por campaña lo es. Es D-1 de #202. |
| B-2 | F06 §8, línea 257 | «Sync transporta únicamente intención autorizada sobre la whitelist; backup sirve para recuperación privada del propietario.» | Igual que B-1: depende de D-1. |
| B-3 | F06 §8, línea 263 | «Restaurar SQLite, fotos o identidades locales no autoriza re-publicación masiva. Cualquier publicación posterior exige intención explícita, referencias centrales, autorización y causalidad verificadas.» | **Restricción de diseño.** Una autorización guardada en SQLite viaja en el respaldo: tras restaurar no puede reactivarse sola. |
| B-4 | F06 §1, línea 11 | «No hay réplica de SQLite, […] operación individual desde Web ni publicación implícita desde backup.» | Igual que B-3. |
| B-5 | F06 §6, línea 119 (fila `CONSUMPTION_TOTAL`) | «Recalcular localmente y sustituir el total mediante causalidad válida. Una reversión puede disminuirlo legítimamente.» | **A favor.** El recálculo y la sustitución ya son el modelo del contrato; no hace falta cambiar el wire ni Central. |
| B-6 | F06 §6, línea 123 | «Una transición a cerrada impide una nueva publicación/sustitución ordinaria; el error requiere revisión del contexto, no reapertura automática.» | **Restricción de diseño**, la misma que M-3 en Central. |
| B-7 | Backend `docs/architecture/F05_SYNC_V1_PUSH_ACK_CONTRACT.md` §5, línea 110 | «Generar UUID v4 una vez al confirmar una intención y persistirla duraderamente. […] Una corrección/decisión humana nueva obtiene otro ID; el worker no genera uno para escapar a conflicto, rechazo o incertidumbre.» | **Hay que aclararlo.** No dice si un total recalculado por una regla autorizada es una «intención confirmada». Un productor automático nunca debe generar un ID tras `REJECTED`, `FAILED` o `CONFLICT` de la misma contribución. |
| B-8 | F06 §4, línea 78 | «No se inventa un servicio de consentimiento, ni se afirma que existe consentimiento formal implementado. Si una aprobación legal/académica exige consentimiento formal, F10 #45 debe precisar la regla antes de habilitar el uso afectado.» | Es D-4 de #202: ¿basta la autorización local o hace falta un consentimiento formal? |

Además, la evidencia Mobile `docs/evidence/F06-COLL-03_sincronizacion_consumo_colectivo.md` (línea 130) declara como limitación: «No hay publicación automática: sólo la acción explícita del titular.» No es un contrato, pero habría que actualizarla con fecha si se acepta la enmienda.

## 3. Por qué no se puede activar hoy

1. **M-1 lo prohíbe de forma literal.** Mientras F04 §2.4 diga que la publicación del consumo es «una acción expresa del agricultor», enviar un total sin que el agricultor actúe sobre él contradice el contrato Mobile. Según `CLAUDE.md`, gana el contrato.
2. **B-1 y B-2 no lo autorizan.** El contrato del Backend admite sólo «intención autorizada», y no dice que una autorización previa lo sea. Esa lectura la tiene que decidir Roderich (D-1 de #202); no se puede suponer.
3. **B-3, B-4, M-3, B-6 y B-7** no lo prohíben, pero obligan a reglas que hoy no existen: suspender la autorización tras restaurar, no reenviar tras un rechazo por campaña y no generar ids para escapar de un rechazo.

**Lo que el contrato sí permite sin enmienda** (se describe; no se activa nada nuevo):
- Recalcular localmente y mostrar si un total está pendiente (B-5). Este bloque lo hace con el estado «Pendiente».
- Un recordatorio de consumo sin publicar (opción C de #202 §5.3). Para mostrarlo fuera de la pantalla de consumo habría que tocar `app_shell.dart` o el resumen de sincronización, que son de otro bloque.
- Nada de esto cambia Central: el wire ya admite un total que sustituye al anterior (B-5).

## 4. Decisión de alcance propuesta

**Hasta que Roderich apruebe las enmiendas de §5:**

- (a) **No se activa** el envío automático. No se añaden «Vincular y compartir consumo automáticamente» ni la opción de pausar.
- (b) **Se implementa** sólo lo que no depende del envío automático (Mobile, rama `feat/uxj-c-consumo-vinculos`, commit `82d8ea1`):
  - **Vínculos:** texto inicial corto y los motivos de incompatibilidad en la fila afectada: unidad distinta, producto inactivo, período que no cabe (con aportes aceptados y retenidos) y «ninguna opción del sindicato es compatible».
  - **Consumo:** estados «Pendiente», «Enviado» y «Requiere atención» por fila, derivados de la outbox. «Publicar» sigue siendo la única forma de enviar, y «Retirar del sindicato» no cambia.
  - Un rechazo `CAMPAIGN_NOT_OPEN` o `CAMPAIGN_SEALED` se muestra como «Requiere atención» con el mensaje vigente de F04 §2.4, y «Publicar» no lo vuelve a enviar (M-3). Sólo deja de retenerse si las referencias actualizadas después muestran la campaña abierta otra vez; entonces volver a publicar es otra decisión expresa del titular.
- (c) **Si se aprueban las enmiendas**, se implementa el diseño de §6 en un bloque propio, con sus pruebas y su evidencia.

## 5. Enmiendas que harían falta

Fechadas y sin borrar el texto anterior, como las enmiendas previas de esos contratos.

| Dónde | Texto propuesto (resumen) |
|---|---|
| Backend F06 §2 y §8 (por #202) | En `CONSUMPTION_TOTAL`, una autorización **vigente, por campaña y revocable** del titular, dada con su PIN, cuenta como intención autorizada para los totales de esa campaña. No vale para `DECLARED_NEED` (F06 §3). No sobrevive a una restauración ni a un cambio de titular. |
| Backend F05 §5 (por #202) | Un productor automático genera un `operationId` sólo para un total nuevo de una contribución sin rechazo ni conflicto pendiente. Nunca tras `REJECTED`, `FAILED` o `CONFLICT` de la misma contribución. |
| Mobile F04 §2.4, línea 137 | Añadir, fechado: «Salvo una autorización vigente del titular para la campaña (F06-ADR-006), la publicación de consumo es una acción expresa del agricultor. La confirmación de una tardía nunca publica (§2.3)». |
| Mobile `F06-COLL-03` (evidencia, línea 130) | Nota fechada que remita a la enmienda; no se reescribe lo verificado. |

## 6. Qué se implementaría tras aprobarlas (diseño breve)

### 6.1 «Vincular» y «Vincular y compartir consumo automáticamente»

- En la fila de la campaña, dos acciones. «Vincular…» queda igual. «Vincular y compartir consumo automáticamente…» vincula y, en el mismo paso, pide la autorización.
- La confirmación muestra:
  - el total actual por producto vinculado, en su unidad;
  - si el primer envío incluye el consumo ya registrado en la campaña (D-5 de #202). El total es acumulado (F06 §2, línea 36), así que lo incluye: no existe un total «desde hoy»;
  - qué no se envía: familiares, terceros, aplicaciones revertidas y productos sin vincular;
  - cómo pausar y cómo retirar.
- Se confirma con el PIN del titular, con un propósito nuevo de un solo uso, por ejemplo `AUTHORIZE_AUTO_CONSUMPTION`, y `subjectRef = campaign:<id>` (D-3).
- **Vínculos anteriores:** sin autorización. Nada cambia hasta que el titular la dé.
- **Alcance:** sólo esa campaña, `ACTIVE` en el teléfono y con vínculo vigente. Nunca campañas cerradas, selladas ni períodos históricos.

### 6.2 Autorización por campaña

- Tabla local nueva, por ejemplo `auto_publication_authorizations` (migración propia):
  - vínculo de titular, campaña local y `campaign_ref`;
  - `granted_at`, `ended_at` y motivo de fin (`PAUSED_BY_OWNER`, `OWNER_CHANGED`, `RESTORED`, `CAMPAIGN_CLOSED`);
  - actor y enrolamiento, como en `reversal_audit` (F04 §1.2).
- Es inmutable salvo para cerrarla. No viaja a Central y no amplía la whitelist.
- Termina con el cambio de titular. Tras restaurar queda suspendida y reanudarla pide el PIN (B-3).

### 6.3 Recálculo

- **Disparador.** El pedido dice que lo dispara la aplicación confirmada o su reversión. #202 recomienda recalcular en el ciclo del worker, no dentro de la transacción de la aplicación, para que un fallo del planner nunca deshaga una aplicación.
- **Propuesta.** Mezcla de las dos (D-8 y DM-3):
  - la aplicación no escribe nada de Sync;
  - al terminar su transacción se pide un ciclo del worker;
  - el ciclo recalcula las campañas autorizadas con el mismo `_compute`, en una transacción bajo `DatabaseReplacementGuard`, y aplica `planIntention` sólo donde el total cambió, como `publish()`.
- Pedir el ciclo lo tiene que hacer la capa que confirma la aplicación. Es un cambio en archivos de otro bloque (`agro_repository.dart` o los formularios).

### 6.4 Persistencia del pendiente

- El total es una función determinista de SQLite. Entre la aplicación y el ciclo, el pendiente se puede derivar siempre, también tras un cierre forzado.
- El ciclo de arranque lo recalcula y lo encola.
- Una vez encolado, la outbox lo persiste como hoy: `PENDING`, `SENDING` u `OUTCOME_UNKNOWN`, con `markSending` antes de enviar.

### 6.5 Una sola vez: idempotencia por sustitución

- Sin cambios en el wire. Se reutilizan:
  - `planIntention`: una intención no enviada se reescribe con el mismo id, o se descarta si vuelve al valor aceptado;
  - una sola intención en vuelo por contribución;
  - el mismo envelope en cada reintento;
  - la deduplicación de Central por `operationId`;
  - `SUPERSEDE` de totales, nunca deltas. Una reversión baja el total, y si se revirtió todo, el total pasa a 0, sin CANCEL.
- **Parada por contribución:** si el último envío terminó en `REJECTED`, `FAILED` o `CONFLICT`, o el vínculo está retenido por período, el productor automático no planifica nada en ella (B-7, M-3). Usa la misma señal que este bloque ya calcula (`ConsumptionPreviewRow.lastRejection` y `ConsumptionChange.rejected`).

### 6.6 Pausar frente a retirar

- **Pausar** el envío automático cierra la autorización (`PAUSED_BY_OWNER`):
  - corta los envíos futuros en la misma transacción;
  - lo que nunca salió se descarta con la lista a la vista (D-9);
  - lo que ya salió se concilia con el mismo id.
  
  **Reanudar** es una autorización nueva, con la confirmación de §6.1.
- **Retirar del sindicato** es otra decisión: un CANCEL expreso, con confirmación, del total aceptado (D-10 y D-11). Pausar nunca retira lo aceptado.
- En Consumo, los estados de este bloque no cambian: «Pendiente», «Enviado» y «Requiere atención».

### 6.7 Pruebas

Las H1 a H16 de #202 §10.1, más las de este bloque: vínculo inválido, sesión sin autorización y campaña cerrada o sellada (`test/uxj_c_consumo_vinculos_test.dart`). En el dispositivo, los recorridos de #202 §10.3.

## 7. Discrepancias anotadas

- **El disparador** (pedido, punto 2, frente a #202 §5.3). Se resuelve con D-8 y DM-3.
- **La pausa** (pedido, punto 3). #202 habla de revocar. Aquí se propone que pausar sea cerrar la autorización y reanudar sea autorizar de nuevo (DM-2).
- **«Vincular y compartir»** (pedido, punto 1). #202 propone un interruptor en la pantalla del vínculo y en la de publicación. El pedido pide una segunda acción al vincular. Las dos formas encajan con §6.1; decide Roderich (D-2).

## 8. Decisiones que sólo puede tomar Roderich

- **D-1 a D-15** de #202. D-1 bloquea las demás.
- **DM-1.** ¿Se enmienda Mobile F04 §2.4, línea 137, como en §5?
- **DM-2.** ¿Pausar es cerrar la autorización, y reanudar pide de nuevo la confirmación con PIN?
- **DM-3.** ¿El disparador es pedir un ciclo del worker al confirmar o revertir, en lugar de escribir en la transacción de la aplicación?

## 9. Compatibilidad y vuelta atrás

- No se activó nada, así que no hay nada que revertir.
- Lo implementado en este bloque es compatible con cualquier respuesta a D-1:
  - es presentación sobre la outbox existente;
  - además, no reenvía un total tras un rechazo terminal por el estado de la campaña, que es lo que ya pide M-3.
- Si D-1 es «no», este documento pasa a `Rejected` y la publicación sigue siendo sólo manual.
