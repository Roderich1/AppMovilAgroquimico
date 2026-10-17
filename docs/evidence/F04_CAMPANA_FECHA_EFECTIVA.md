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
   - **una, pero no la activa** (cerrada o planificada) → rechazo explícito que nombra esa campaña y dice que «no se registra en otra campaña»; no invita a cambiar la activa, no se reabre ni se reasigna. Para una campaña **cerrada** el rechazo es una **salvaguarda provisional**, no la lectura de §3.11.13: ver §4, D-F04-C1.
   Toda la comprobación ocurre dentro de la transacción, antes de escribir: un rechazo no deja cabecera, líneas, lotes, consumos, movimientos ni cuentas.
3. **El calendario se mantiene sin solapes, en el momento en que cambia y sin mover operaciones:**
   - **Alta de campaña.** La nueva debe empezar **después** del inicio de todas las existentes (las campañas se agregan en orden; no se intercalan). Si la anterior está abierta, su fin pasa a ser el día anterior al inicio de la nueva. Si esa campaña anterior ya tiene operaciones en ese día o después, el alta se rechaza, sin cambios. Si la anterior tiene un fin fijado y la nueva empieza antes o en ese día, se rechaza.
   - **Activar** sólo cambia estados. Ya no borra el `fin` de la campaña activada ni pone «hoy» como fin de la cerrada. Para bases anteriores a esta regla, si la campaña que se cierra sigue abierta, su fin pasa a ser el día anterior al inicio de la activada, con las mismas condiciones; si no se puede, se rechaza sin cambios.
   - **Cerrar sin sucesora.** Si la campaña está abierta, el usuario **elige el fin** (hoy por defecto). Se rechaza si el fin es anterior al inicio o si alguna operación tiene una fecha posterior a ese fin. Si ya tenía fin (lo fijó el alta de la siguiente), se conserva. *(Revisión de B: el «fin = hoy» fijo de la primera versión era un fin arbitrario.)*
4. **Diálogos.** El alta pide la fecha de inicio: propone hoy, o un día posterior si el orden del calendario lo exige. El cierre de una campaña abierta pide la fecha de fin. El repositorio vuelve a validar.
5. **Histórico.** No se migra ni se reasigna ninguna fila. Un solapamiento heredado no se corrige solo: sus días quedan como «ambiguos» y la operación nueva en esos días se rechaza de forma explícita.

**Fuera de alcance (sin cambio):**
- planes, porque no son operaciones con fecha efectiva (su `planned_date` es opcional);
- pagos, que cruzan campañas a propósito (saldo por persona);
- **transferencias:** RN-15 las nombra, pero en el modelo no llevan campaña. Se declara como límite;
- reversiones, que no reclasifican.
Aplicar un plan sí pasa por la regla, porque crea una aplicación. La voz también, porque confirma por el mismo repositorio.

**Autoridad de las fechas.** Es un ajuste de la gestión local de campañas que ya existía (REC #41: alta, activación y cierre en Catálogos), no una autoridad nueva. Hoy las fechas son locales, aunque la campaña esté vinculada a una central (ver D-F04-C2).

## 3. Implementación y resultados (HOST; nada de esto es DEVICE)

**Commits** (rama `feat/f04-campana-fecha-efectiva`):
- `27bd501`: regla;
- `232fc25`: código, diálogos y fixtures;
- `297d045`: prueba de activación;
- `13f0933`: imports;
- `85929c2`: revisión de B sobre `6554be7`. Las necesidades declaradas cuentan como registros fechados de su campaña, y el cierre no admite un fin futuro;
- `f37200d`: revisión de B sobre `d932e61`. Si la campaña activa todavía no empezó, el diálogo de cierre propone y admite como fin su día de inicio.

| Archivo | Cambio |
|---|---|
| `lib/domain/campaign_calendar.dart` (nuevo) | Día local, período inclusivo, solape. Misma lectura que `DeclaredNeedStore.campaignForDate` (F05), que no se toca |
| `lib/data/agro_repository.dart` | `_ensureEffectiveDateInCampaign` en `confirmPurchase` y `confirmApplication`, dentro de la transacción y antes de escribir. `CampaignDateException` (`none`, `ambiguous`, `closed`, `planned`) y `CampaignCalendarException`. Cambian `addCampaign` (orden y fin de la anterior), `activateCampaign` (sólo estados; caso heredado) y `closeCampaign(end:)`. Nuevo `suggestedCampaignStart` |
| `lib/presentation/screens/catalogs_screen.dart` | Diálogo de alta con «Empieza el» y diálogo de cierre con «Termina el» |

**Pruebas nuevas:**
- `test/f04_campaign_effective_date_test.dart`, 15 casos:
  - límites inclusivos en día local (primer y último minuto) en los dos modos;
  - compra y aplicación **multiproducto** en propio y en compartido, conservadas tras cerrar y reabrir la base, con la campaña y la **fecha completa**;
  - rechazo de «ninguna», «ambigua» (solape heredado) y «cerrada», y de «planificada», en compra y aplicación, con el volcado de **todas** las tablas idéntico;
  - FIFO con lotes del mismo día: sale antes el de la mañana, aunque se registrara después;
  - calendario: no se intercala ni se repite un inicio; un fin anterior al inicio se rechaza; el alta no deja operaciones fuera; cierre con fin elegido (inclusivo, no antes del inicio, sin dejar operaciones fuera); base heredada al activar; activar conserva el fin ya fijado; propuesta de inicio. Además, el alta y el cierre no dejan fuera una **necesidad declarada ni sus versiones** (F05), y el cierre no admite un **fin futuro**.
- `test/f04_campaign_dialogs_ui_test.dart`, 4 casos: el alta propone hoy y la anterior termina el día previo; el cierre pide el fin y lo guarda; un fin ya fijado se muestra y no cambia; una campaña activa que todavía no empezó se cierra con su día de inicio como fin.

**Fixtures ajustadas.** Sólo cambian datos que creaban períodos solapados, que RF-03 prohíbe. Las aserciones son las mismas, salvo la de `report_reads`, que se traslada:

| Prueba | Antes | Ahora |
|---|---|---|
| `campaign_lifecycle_test` («CLOSED es terminal») | Cerraba con fin = hoy y daba de alta otra que empezaba antes | Cierre con fin anterior al alta siguiente |
| `campaign_lifecycle_ui_test` | Ídem | Ídem |
| `v5_domain_test` («catálogo, stock y deuda…») | «Invierno» desde junio, con operaciones de hoy en «Primavera» | «Invierno» desde mañana |
| `declared_need_test` («sin campaña determinable…») | Fabricaba el solape con `addCampaign` | El solape es una fila heredada insertada a mano. La prueba de F05 sigue igual |
| `report_reads_characterization_test` (`end_date` nulo) | La campaña 1 seguía abierta | La 1 tiene fin y la 2, abierta, conserva `end_date` nulo |

**Mutaciones** (`camp_mutations.py`, en el scratchpad de la sesión), sobre `85929c2`. Las 18 se detectan:
- sin comprobar la fecha en compra o en aplicación;
- fin o inicio exclusivos;
- día UTC en vez de local (sólo discrimina con una zona distinta de UTC; esta máquina está en America/La_Paz);
- aceptar una fecha ambigua si incluye la activa;
- alta sin orden o sin control de operaciones;
- cierre sin control de operaciones o ignorando el fin elegido;
- activar volviendo a abrir la activada, o sin control de solape;
- fin = día de inicio de la nueva;
- diálogos que no pasan la fecha;
- sin las necesidades declaradas o sin sus versiones;
- cierre que admite un fin futuro.

**Resultados en local** (Windows 11, Flutter 3.47.2, America/La_Paz):

| Comando | Sobre | Resultado |
|---|---|---|
| `flutter test` (suite completa) | `f37200d` | **1421 pasan, 2 omitidas, 0 fallos** |
| `flutter test` (suite completa) | `85929c2` | 1420 pasan, 2 omitidas |
| `flutter test` (suite completa, antes de la revisión) | `297d045` | 1418 pasan, 2 omitidas |
| `flutter analyze lib test` | `85929c2` | `No issues found!` (en `297d045` había 2 imports sin uso en la prueba nueva, que `13f0933` quita) |
| `dart format --set-exit-if-changed lib test` | `85929c2` | exit 0 |
| `flutter test` de las dos pruebas nuevas | `85929c2` | 18 pasan |

**CI (GitHub Actions):** 39058618715 sobre `d932e61`: SUCCESS, 1419 pasan y 3 omitidas (dato de B). La CI del HEAD final consta en el PR. En CI se omite una prueba más que en local, por plataforma.

## 4. Límites y decisiones para Roderich

- **D-F04-C1: registros tardíos de un período cerrado.** RF-03, en su criterio, dice «registros tardíos quedan asociadas al período correcto»; Cap. III §3.11.13, «requerirán revisión, conservando su historia». Hoy se **rechazan** como salvaguarda, así que esa parte de **RF-03 no está cumplida**. Opciones:
  - (A) un estado «requiere revisión»: la operación se guarda en la campaña cerrada de su fecha, visible, sin reabrir, sin reasignar y sin publicarse a Central. Antes hay que decidir quién revisa, qué resultados tiene y qué efecto tiene en el inventario. Las fuentes no lo definen y no se construyó por intuición;
  - (B) aceptar el rechazo como límite del alcance académico.
- **D-F04-C2: período local frente al central.** `CentralBindingStore` lee las fechas de la campaña central, pero no comprueba que el período local quepa en ellas. Si no cabe, el consumo publicado por `campaign_ref` puede llevar días fuera del período central (contra RN-15). Afecta a los vínculos futuros y también al **consumo ya publicado** con fechas locales que no caben. Opciones:
  - comprobarlo al vincular y señalar lo ya publicado (F05);
  - o aceptarlo como límite.
- **Un período pasado que no está en el calendario no se puede representar:** las campañas se agregan en orden, así que sus registros tardíos caen en «ninguna».
- **Solapes heredados:** no se corrigen solos. Sus días quedan como «ambiguos».
- **Transferencias:** sin campaña en el modelo.
- **Sólo host:** el teléfono no ejecutó esta regla. La sesión física del 2026-10-17 fue anterior.

## 5. Revisiones

- **Regla:** sesión B, sobre `27bd501`. NO LISTO en un punto (el rechazo de una campaña cerrada como «lectura de §3.11.13»), que se declara ahora como D-F04-C1 y como incumplimiento de RF-03 en esa parte. Los demás puntos, LISTO. Los riesgos (a)–(f) se recogen en §2 y §4.
- **Código y pruebas:** sesión B, sobre `6554be7`. LISTO, con un hallazgo medio (las necesidades declaradas no contaban como registros fechados) y dos menores (fin futuro; `end` ignorado si ya hay fin). Corregidos o documentados en `85929c2`. **Delta `6554be7..d932e61`: LISTO**, con la CI 39058618715 en verde y un menor nuevo (cerrar una campaña activa que aún no empezó), corregido en `f37200d`.
- **Revisión de Roderich Rendón:** pendiente. GATE-F04 sigue **Pending**.
