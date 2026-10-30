# D-04 y E-15 · Cuentas: imputación de pagos entre campañas y consumo propio del titular

- **Estado:** revisión 2. La revisión cruzada de la revisión 1 (`09963b4`) concluyó «listo con ajustes»: recalculó los 19 ejemplos y confirmó las cifras «hoy». Esta revisión incorpora sus hallazgos, añade los ejemplos M-1 a M-10 y la sección 7, «Criterios de aplicación y puntos que el autor puede revisar». Es la referencia de la implementación (fase 2).
- **Decisiones de origen:** D-04 y E-15 son **decisiones del autor del proyecto, Roderich Rendón, del 2026-10-27** (`_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`). No se atribuye aprobación al tutor ni a la Directiva.
- **Criterios de §7:** los fija el coordinador para aplicar esas decisiones sin salir de lo aprobado. No son decisiones nuevas del autor, y el autor puede revisarlos.
- **Base verificada:** Mobile `main` `ed9c55c`. Las cifras «hoy» salen de leer el código en esa base, y la revisión cruzada las comprobó.
- **Organización:** un solo documento. La parte A es D-04, que va en la rama `feat/d04-imputacion-pagos-campanas`. La parte B (anexo) es E-15, que va en `feat/e15-consumo-propio-titular`, apilada sobre D-04.
- **Trazabilidad (Cap. III):** RF-06/CU-05 (modo propio y compartido), RF-12/CU-09 (aplicaciones con costeo FIFO, base del costo propio), RF-13/CU-17 (reversiones), RF-03 (operaciones tardías), DAT. Las cuentas, pagos y adelantos no tienen un RF propio en el Cap. III: ver C-01.
- **Numeración de reglas:** «RN-nn» se refiere a `docs/15_BUSINESS_RULES.md`, como en la propia decisión del autor. Esa numeración no coincide con la del Cap. III, por eso no se usa en la trazabilidad.

---

## 1. Comportamiento actual verificado (`ed9c55c`)

### 1.1 Escritura

| # | Hecho | Dónde |
|---|---|---|
| H-01 | `account_transactions`: positivo = cargo, negativo = pago, adelanto o crédito; `campaign_id` admite NULL. `payment_allocations(payment_transaction_id, charge_transaction_id, amount_bob_minor > 0)` es `UNIQUE` por par. Ninguna de las dos tablas tiene triggers de inmutabilidad | `lib/data/app_database.dart:466-476` |
| H-02 | La migración a v3 crea `payment_allocations` sin rellenar imputaciones para los pagos que ya existían | `lib/data/app_database.dart:549-564` |
| H-03 | Cargo por compra (`PURCHASE_ALLOCATION_CHARGE`) sólo con política `BY_PURCHASE_ALLOCATION`, con la campaña y la fecha de la compra | `lib/data/agro_repository.dart:1139-1149` |
| H-04 | Cargo por consumo (`USAGE_CHARGE`) por el costo FIFO total sólo con la política **actual** `BY_ACTUAL_USAGE`, con la campaña y la fecha de la aplicación | `lib/data/agro_repository.dart:1392-1401` |
| H-05 | Compras y aplicaciones exigen campaña (`NOT NULL`): todo cargo tiene campaña de origen | `lib/data/app_database.dart:419,452` |
| H-06 | `addAccountPayment` inserta el pago con el `campaign_id` recibido (puede ser NULL). Imputa a los cargos con importe > 0 de la persona, ordenados por `transaction_date` (instante) y `id`, con pendiente = importe − Σ imputaciones. **No resta las reversiones** (D-15). El sobrante queda sin imputar. Pago y adelanto son idénticos | `lib/data/agro_repository.dart:1920-1967` |
| H-07 | En modo propio sólo se registran pagos del titular | `lib/data/agro_repository.dart:1931-1933` |
| H-08 | La reversión de una aplicación inserta, por cada `USAGE_CHARGE`, un `CREDIT_ADJUSTMENT` negado, con la campaña del cargo, la fecha de hoy y `reversal_of_id`. No toca las imputaciones | `lib/data/agro_repository.dart:2061-2083` |
| H-09 | La reversión de una compra hace lo mismo con los `PURCHASE_ALLOCATION_CHARGE` y anula los `provider_payments` (RN-45), que no son asientos de cuenta | `lib/data/agro_repository.dart:2163-2168, 2236-2265` |
| H-10 | **No existe la reversión de un pago o adelanto de cuenta** | búsqueda en `lib/` |
| H-11 | El titular se crea `FAMILY` con `BY_ACTUAL_USAGE`. Un `ADMIN` histórico puede ser titular con confirmación (`MANUAL`) y un tercero no puede serlo. La UI nunca fija la política (RN-01) | `lib/data/owner_binding_store.dart:230-258`; `lib/domain/person_roles.dart:45-49` |

### 1.2 Lectura y pantallas

| # | Hecho | Dónde |
|---|---|---|
| H-12 | Cuentas arranca filtrada por la campaña activa; «Todas las campañas» es la opción NULL | `settlements_screen.dart:62-67, 507-526` |
| H-13 | Registrar un pago pasa `campaignId: selectedCampaignId`. El diálogo muestra «Campaña X» o «Todas las campañas» y «Saldo pendiente» con el saldo **filtrado** | `settlements_screen.dart:85-126, 805-821` |
| H-14 | `settlements({campaignId})` con filtro suma sólo los asientos con `t.campaign_id = K`, sin ADMIN (RN-41), y ordena por saldo descendente | `agro_repository.dart:3294-3303` |
| H-15 | Tarjeta: «Cargos X · pagos/créditos Y» · «Pendiente · K» o «A favor · K» | `settlements_screen.dart:563-604` |
| H-16 | `personCampaignBalance`: saldo inicial = asientos de campañas que empiezan antes de K (los NULL no cuentan, KI-05) | `agro_repository.dart:3196-3219` |
| H-17 | Detalle: «Saldo inicial de campaña» y filas con `campaign_id = K` | `settlements_screen.dart:128-237`; `agro_repository.dart:3321-3337` |
| H-18 | Exportación del estado de cuenta con las mismas lecturas; totales «Total de cargos», «Total de créditos», «Saldo final» | `report_export_service.dart:168-196`; `report_composer.dart:255-322` |
| H-19 | Inicio: «Familias/Terceros por cobrar» = suma con signo por `role`; «Pagos recibidos» = PAYMENT + ADVANCE; «Principales saldos» = `topSettlements` | `agro_repository.dart:3361-3410`; `dashboard_screen.dart:171-183, 401-427` |
| H-20 | El titular `FAMILY` entra en «Familias por cobrar» y en «Principales saldos» (C-09) | `agro_repository.dart:3380` |
| H-21 | Resumen de campaña: «Saldo por cobrar» = suma con signo de `campaign_id = K`, sin filtro de rol | `agro_repository.dart:3190-3192`; `report_composer.dart:231-247`; `catalogs_screen.dart:204` |
| H-22 | Costo por chaco y por producto: aplicaciones no revertidas, filtradas por `a.campaign_id` | `agro_repository.dart:3339-3359` |
| H-23 | Personas y su detalle muestran la suma con signo; la pestaña Cuenta lleva «Acumulado» | `person_detail_screen.dart:31, 56-83, 133-160`; `persons_screen.dart:99-108` |
| H-24 | Formulario de aplicación. En modo propio: «Costo propio: X (queda anotado en la cuenta de T)». En compartido: «Se cargará a T: X», o «No genera cargo: T ya pagó estos productos al comprarlos» con `BY_PURCHASE_ALLOCATION`. Ese texto es falso si la compra sigue impaga (M-7) | `application_form_screen.dart:847-866` |
| H-25 | La publicación de consumo al sindicato lee cantidades, no cuentas | `lib/data/sync/consumption_publisher.dart:302-304` |
| H-26 | En modo propio, el menú ofrece pago y adelanto sólo al titular (#26) | `settlements_screen.dart:613-662` |
| H-27 | La leyenda «Incluye operaciones tardías confirmadas» que pide F04 §2.3 no está implementada en ninguna vista de cuentas | búsqueda en `lib/` |

---

## 2. Definiciones

### 2.1 Clasificación de los asientos y conceptos

Para una persona *p* (importes enteros en centavos), cada fila de `account_transactions` cae en una sola clase:

| Clase | Condición | Hoy |
|---|---|---|
| **Cargo** *c* | importe > 0 y `reversal_of_id IS NULL` | `USAGE_CHARGE`, `PURCHASE_ALLOCATION_CHARGE` |
| **Reversión de cargo** | importe < 0 y `reversal_of_id` apunta a un cargo | `CREDIT_ADJUSTMENT` de RN-46 |
| **Crédito** *q* | importe < 0 y no es reversión de cargo | `PAYMENT`, `ADVANCE`; un `CREDIT_ADJUSTMENT` sin cargo de origen |
| **Compensación de un crédito** *x* | importe > 0 y `reversal_of_id IS NOT NULL` | no existe hoy. Una futura reversión de un pago caería aquí y nunca se tomaría por deuda |

Las definiciones salen de esa clasificación, no de una lista cerrada de tipos. Un tipo futuro cae en una de las cuatro clases y las identidades siguen valiendo.

- **Revertido(c)** = −Σ de sus reversiones. **Neto(c)** = importe − revertido.
- **Imputado(c)** = Σ de las imputaciones guardadas hacia *c*. **Pagos aplicados(c)** = min(imputado, neto). **Liberado por reversión(c)** = imputado − aplicados. **Deuda pendiente(c)** = neto − aplicados ≥ 0.
- **Campaña de origen** de la deuda: `c.campaign_id`. **Campaña de registro** de un crédito: `q.campaign_id`, que puede ser NULL. La de registro **no** decide qué deuda cancela.
- **Sin imputar(q)** = |importe(q)| − Σ de sus imputaciones.
- **A favor (no aplicado a deuda)** *F* = *u* + *L* − *X*, donde *u* = Σ sin imputar(q) («pagos sin imputar»), *L* = Σ liberado («liberado por reversión») y *X* = Σ compensaciones («otros ajustes»). *F* no se atribuye a ninguna campaña.
- **Deuda pendiente** *P* = Σ deuda pendiente(c). **Saldo neto** *N* = *P* − *F*.
- **Identidad:** *N* = suma con signo de los asientos de *p*. Se demuestra con la clasificación: Σ neto(c) = *P* + Σ aplicados, y Σ\|q\| = Σ imputaciones + *u*.

Por campaña de origen K: cargos_K − revertidos_K − aplicados_K = deuda pendiente_K.

### 2.2 Dos cálculos distintos, con etiquetas distintas

| | Desglose por campaña de origen de la deuda | Estado de cuenta cronológico con apertura |
|---|---|---|
| Pregunta | ¿Cuánto falta pagar **hoy** de lo cargado en K? | ¿Cómo evolucionó el saldo en el **período** de K? |
| Asientos | cargos con `campaign_id = K`, sus reversiones y sus imputaciones guardadas | todos los asientos cuyo **día local** cae en el período de K (`CampaignPeriod.contains`), de cualquier campaña o NULL |
| Apertura | no tiene | Σ de los asientos con día anterior al inicio |
| Etiquetas | «Deuda pendiente por origen (a hoy)», «Deuda pendiente por origen · K», «Pendiente a hoy {p}» | «Estado de cuenta cronológico · período de K (dd/mm/aaaa – dd/mm/aaaa\|hoy)», «Saldo al inicio del período (dd/mm/aaaa)», «Saldo al cierre del período (dd/mm/aaaa)», «Saldo a hoy» |

- Orden siempre por día local efectivo y luego `id` (F04 §2.3), también en la imputación (D-R1).
- **Fin del período** (revisión cruzada 2): el período de K terminó si `endDay` existe y es anterior a hoy, **sea cual sea el estado**. Entonces el cronológico corta en el fin y se rotula «Saldo al cierre del período (fin)». Una campaña ACTIVA con fin pasado (la sucesora se creó y no se activó, #125) entra en este caso. I-4 se lee así: con el período abierto, «Saldo a hoy» = *N*; con el período terminado, el cierre = Σ de los asientos con día hasta el fin.
- La campaña de registro y la campaña de una reversión no mueven ninguna fila del cronológico: manda la fecha.
- Un asiento con fecha en un hueco entre campañas entra en la apertura del período siguiente y en «Todas».
- **Operaciones tardías (H-27):** una tardía confirmada en una campaña cerrada añade filas con fecha dentro de ese período. Por eso el «Saldo al cierre del período» de esa campaña **puede cambiar después de confirmarla** (M-4), y la deuda por origen también. La leyenda «Incluye operaciones tardías confirmadas» falta hoy y D-04 **no** la añade. Queda declarada como carencia previa (C-13).

### 2.3 Cuentas (lista): textos exactos

Notación: `{x}` es `formatBob(x)` sin el espacio final, por ejemplo «81,00 Bs». «revertidos» sólo aparece si es > 0. Con cargos = 0 en el alcance, la línea 1 es «Sin cargos.».

**«Todas las campañas»:**
- línea 1: «Cargos {C} · revertidos {R} · pagos aplicados {A}»;
- línea 2: «Deuda pendiente {P} · a favor (no aplicado a deuda) {F}»;
- derecha: «Saldo neto · todas las campañas» y {N} (naranja si > 0, verde si ≤ 0);
- orden por *N* descendente y luego nombre.

**Campaña K:**
- línea 1: «Cargos de K {C_K} · revertidos {R_K} · pagos aplicados {A_K}»;
- línea 2: «Saldo neto · todas las campañas {N}»;
- línea 3, sólo si F ≠ 0: «A favor (no aplicado a deuda) {F} (sin campaña)»;
- derecha: «Deuda pendiente por origen · K» y {P_K};
- orden por P_K descendente y luego nombre.

Se listan todas las personas no ADMIN, como hoy. En E-15, sin el titular vigente (§B).

### 2.4 Diálogo de pago o adelanto

- **Líneas:**
  - nombre;
  - campaña de registro: «Se registra en: K»; si el período de K ya terminó (fin anterior a hoy, el mismo criterio de §2.2), «Se registra en: K (cerrada). En el estado cronológico aparecerá por su fecha, {dd/mm/aaaa de hoy}», o «(período terminado el {fin})» en lugar de «(cerrada)» si la campaña sigue ACTIVA; o «Se registra sin campaña»;
  - saldo: «Saldo neto · todas las campañas: debe {N}» (N > 0), «… : a favor {−N}» (N < 0) o «… : al día» (N = 0);
  - «Se aplica primero a la deuda más antigua, de cualquier campaña.».
- **Al guardar,** el mensaje se arma con las imputaciones **escritas:** «{Pago|Adelanto} de {x} registrado a {persona}.», seguido de « Imputado: {K1} {a1} · {K2} {a2}.» si se imputó algo y de « Sin imputar: {u} (queda a favor).» si sobró.
- **Formato de «Imputado:»:** suma por campaña de origen; las campañas en el orden FIFO en que se imputaron (día del cargo y luego `id`); separador « · ».
- No se exige elegir campaña. La de registro sale del filtro, y es NULL con «Todas».

### 2.5 Detalle: textos exactos

Título «Estado de cuenta · {persona}».

1. **«Deuda pendiente por origen (a hoy)»** (o «Sin cargos.»):
   - una línea por campaña con cargos, por inicio de campaña: «{K}: cargos {C_K} · revertidos {R_K} · pagos aplicados {A_K} · pendiente {P_K}»;
   - si L_K > 0: «{L_K} imputados a cargos revertidos de {K} quedan a favor»;
   - «Deuda pendiente total {P}»;
   - «A favor (no aplicado a deuda) {F}» y, si F ≠ 0, su composición: «pagos sin imputar {u} · liberado por reversión {L} · otros ajustes {−X}», sólo los términos ≠ 0;
   - «Saldo neto · todas las campañas {N}».
2. **Estado cronológico:**
   - cabecera: «Estado de cuenta cronológico · todas las campañas», o «Estado de cuenta cronológico · período de K ({inicio} – {fin|hoy})» seguida de «Saldo al inicio del período ({inicio}) {O}»;
   - cada fila: concepto; «{fecha} · {tipo} · {chaco} · {campaña del asiento}»; línea de estado; importe; «Acumulado {X}»;
     **Distribución (F-1, 2026-10-30):** en pantalla ancha (contenido ≥ 480 px) el importe y «Acumulado» van en una columna lateral de 140 px; en teléfono van debajo del concepto, a lo ancho de la fila, para que el concepto no se parta por carácter. Los textos no cambian;
   - cierre: «Saldo al cierre del período ({fin}) {X}» si K está cerrada, y «Saldo a hoy {X}» si está abierta o con «Todas»;
   - sin filas ni apertura: «Sin movimientos.».
   - **Campaña del asiento:** el nombre de su campaña. En los créditos, «registrado en K» o «registrado sin campaña».
   - **Estado de un cargo:** «Pendiente a hoy {p}», «Pagado» o «Revertido el {fecha}».
   - **Estado de una reversión de cargo:** «Revierte el cargo del {fecha}».
   - **Estado de un crédito:** los tramos que correspondan, unidos por « · ».
     1. «Imputado: {K1} {a1} · …», con el formato de §2.4;
     2. por cada cargo revertido que recibió imputación: «Imputado a un cargo revertido ({K}, {fecha del cargo}): {x}. Queda a favor.»;
     3. si u > 0 y no tiene ninguna imputación: «Sin imputación registrada: {u} (queda a favor, sin campaña)»;
     4. si u > 0 y tiene imputaciones: «sin imputar {u} (queda a favor, sin campaña)».
     - Un `CREDIT_ADJUSTMENT` sin cargo de origen: «Crédito sin cargo de origen registrado: {x} (queda a favor, sin campaña)».

### 2.6 Exportación del estado de cuenta

- **Columnas:** Fecha · Concepto · Chaco · Campaña del asiento · Cargo (Bs) · Crédito (Bs) · Imputación · Acumulado (Bs). «Imputación» lleva la línea de estado de §2.5.
- **Filtros:** Persona y Campaña («K (período dd/mm/aaaa – dd/mm/aaaa|hoy)» o «Todas las campañas»).
- **Con K:** primera fila «Saldo al inicio del período (dd/mm/aaaa)». Totales:
  - «Saldo al inicio del período (Bs)»;
  - «Total de cargos (Bs)» y «Total de créditos (Bs)»;
  - «Saldo al cierre del período (Bs)» o «Saldo a hoy (Bs)»;
  - «Deuda pendiente por origen · K (Bs)»;
  - «A favor (no aplicado a deuda) (Bs)»;
  - «Saldo neto · todas las campañas (Bs)».
- **Con «Todas»:** totales:
  - «Total de cargos (Bs)», «Total de créditos (Bs)» y «Saldo a hoy (Bs)»;
  - una fila «Deuda pendiente por origen · {K} (Bs)» por campaña con cargos;
  - «Deuda pendiente total (Bs)»;
  - «A favor (no aplicado a deuda) (Bs)»;
  - «Saldo neto · todas las campañas (Bs)».
- CSV y PDF salen del mismo `ReportTable`.

### 2.7 Inicio, Personas y resumen de campaña

- **«Familias por cobrar»** = Σ, sobre las personas `FAMILY`, de max(0, P − F); debajo, «A favor de familias: {Σ max(0, F − P)}» si es > 0. **Terceros** igual con `THIRD_PARTY`. «Conservan sus reglas» se refiere a las políticas de cargo, no a esta agregación (§7).
- **«Pagos recibidos»** = Σ \|PAYMENT + ADVANCE\| (en E-15, sin los del titular). **«Principales saldos»** = N por persona.
- **Personas:** sin cambio en D-04. La cifra sigue siendo la suma con signo, igual a *N*. En E-15 cambia la del titular.
- **Resumen de campaña** (reporte y diálogo de cierre): «Saldo por cobrar» pasa a «Deuda pendiente por origen» = Σ P_K sobre las personas no ADMIN (en E-15, sin los asientos propios del titular).

### 2.8 Invariantes

| | Invariante |
|---|---|
| I-1 | Σ_K deuda pendiente_K = *P* |
| I-2 | *P* − *F* = *N* = suma con signo de los asientos = cifra de Personas (D-04) |
| I-3 | Σ imputaciones guardadas = aplicados + liberado, y Σ\|q\| = Σ imputaciones + *u* |
| I-4 | Cronológico del período abierto: «Saldo a hoy» = *N*. Con «Todas», el último acumulado = *N* |
| I-5 | «Familias por cobrar» = Σ max(0, P − F) de las tarjetas «Todas» de personas FAMILY (E-15: sin asientos propios) |
| I-6 | Resumen de K = Σ «Deuda pendiente por origen · K» de la lista filtrada por K |
| I-7 | Σ_K Resumen_K = Σ_personas *P* |
| I-8 | Ninguna fila existente de `payment_allocations` cambia ni se borra. Las imputaciones nuevas sólo las crea `addAccountPayment`, y sólo para el pago que registra. Ninguna lectura crea imputaciones, tampoco para el crédito liberado de D04-06/07h |

---

## 3. Ejemplos con resultados esperados

### 3.0 Datos comunes

- **Campañas:** «Verano 2026» (V), del 01/01/2026 al 30/06/2026, CERRADA. «Invierno 2026» (I), desde el 01/07/2026, ACTIVA.
- **Personas:** «Titular» (FAMILY, `BY_ACTUAL_USAGE`, titular vigente); «Familiar Demo» (FAMILY, `BY_ACTUAL_USAGE`); «Tercero Demo» (THIRD_PARTY, `BY_PURCHASE_ALLOCATION`).
- **Chacos:** «Chaco Norte» (Titular) y «Chaco Familiar» (Familiar Demo), de 1 ha cada uno. **Modo:** COMPARTIDA, salvo que se diga otra cosa.
- **Fechas y bases:** las fechas de los pagos se fijan con el parámetro `date` de `addAccountPayment`. Los cargos de los ejemplos D04 se siembran con su fecha y su campaña. Las reversiones y las tardías llevan la fecha real de la prueba (posterior a los pagos del ejemplo, salvo donde se indica). En las pruebas, «25/10/2026» se lee «el día de la prueba».
- En los ejemplos D04 el titular no tiene asientos: sale con 0,00 y desaparece de la lista en E-15. Tercero Demo tiene 0,00 salvo donde se indica.
- «Hoy» es `ed9c55c`. «Esperado» es tras D-04, o tras E-15 en la parte B.

### D04-01 · Ejemplo obligatorio: pago global de 50 Bs

**Entrada (Familiar Demo):**
- c1: 15/03, V, `USAGE_CHARGE` +81,00.
- c2: 10/08, I, +40,00.
- q1: 20/10, `PAYMENT` −50,00. **1a**: con «Todas» (NULL). **1b**: con el filtro I.
- Imputación: q1 → c1, 50,00.

| Vista | Hoy | Esperado (1a = 1b salvo «registrado…») |
|---|---|---|
| Cuentas · Todas | «Cargos 121,00 Bs · pagos/créditos 50,00 Bs» · «Pendiente · todas las campañas» 71,00 | «Cargos 121,00 Bs · pagos aplicados 50,00 Bs» · «Deuda pendiente 71,00 Bs · a favor (no aplicado a deuda) 0,00 Bs» · «Saldo neto · todas las campañas» **71,00** |
| Cuentas · V | «Pendiente · Verano 2026» 81,00 | «Cargos de Verano 2026 81,00 Bs · pagos aplicados 50,00 Bs» · «Saldo neto · todas las campañas 71,00 Bs» · «Deuda pendiente por origen · Verano 2026» **31,00** |
| Cuentas · I | 1a 40,00 · 1b «A favor · Invierno 2026» −10,00 | «Cargos de Invierno 2026 40,00 Bs · pagos aplicados 0,00 Bs» · «Saldo neto · todas las campañas 71,00 Bs» · **40,00** |
| Detalle · origen | (no existe) | «Verano 2026: cargos 81,00 Bs · pagos aplicados 50,00 Bs · pendiente 31,00 Bs»; «Invierno 2026: cargos 40,00 Bs · pagos aplicados 0,00 Bs · pendiente 40,00 Bs»; «Deuda pendiente total 71,00 Bs»; «A favor (no aplicado a deuda) 0,00 Bs»; «Saldo neto · todas las campañas 71,00 Bs» |
| Cronológico Todas | +81 (81), +40 (121), −50 (71) | +81 («Pendiente a hoy 31,00 Bs»), +40 («Pendiente a hoy 40,00 Bs»), −50 («registrado sin campaña» / «registrado en Invierno 2026»; «Imputado: Verano 2026 50,00 Bs»); «Saldo a hoy 71,00 Bs» |
| Cronológico I | inicial 81,00; 1a: +40 → 121 · 1b: … → 71 | «Saldo al inicio del período (01/07/2026) 81,00 Bs»; +40 (121); −50 (71); «Saldo a hoy 71,00 Bs» |
| Cronológico V | inicial 0,00; +81 (81) | inicio 0,00; +81; «Saldo al cierre del período (30/06/2026) 81,00 Bs» |
| Exportación · I | 1a: 40,00 · 0,00 · «Saldo final» 121,00 | inicio 81,00 · cargos 40,00 · créditos 50,00 · «Saldo a hoy» 71,00 · «Deuda pendiente por origen · Invierno 2026» 40,00 · a favor 0,00 · «Saldo neto · todas las campañas» 71,00 |
| Inicio | Familias 71,00 · Pagos recibidos 50,00 | igual, sin línea de «A favor de familias» |
| Resumen | V 81,00 · I 1a 40,00 / 1b −10,00 | «Deuda pendiente por origen»: V **31,00** · I **40,00** |
| Diálogo antes de q1 (filtro I) | «Campaña Invierno 2026» · «Saldo pendiente 40,00 Bs» | «Se registra en: Invierno 2026» · «Saldo neto · todas las campañas: debe 121,00 Bs» · «Se aplica primero a la deuda más antigua, de cualquier campaña.» Al guardar: «Pago de 50,00 Bs registrado a Familiar Demo. Imputado: Verano 2026 50,00 Bs.» |
| Costo por chaco / producto | Chaco Familiar: Todas 121 · V 81 · I 40 | sin cambio |

**Resultado exigido:** Verano 31, Invierno 40, total 71.

### D04-02 · Pago registrado en la campaña nueva que cancela deuda antigua

**Entrada:** c1 15/03, V, +81. q1 20/10, −81, registrado en I. Imputación: q1 → c1, 81.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Pendiente · todas» 0,00 | «Cargos 81,00 Bs · pagos aplicados 81,00 Bs» · «Deuda pendiente 0,00 Bs · a favor (no aplicado a deuda) 0,00 Bs» · **0,00** |
| Cuentas · V | 81,00 | «Cargos de Verano 2026 81,00 Bs · pagos aplicados 81,00 Bs» · **0,00** |
| Cuentas · I | «A favor · Invierno 2026» −81,00 | «Sin cargos.» · «Saldo neto · todas las campañas 0,00 Bs» · **0,00** |
| Cronológico I | inicial 81; −81 (0) | inicio 81,00; −81 (0,00; «registrado en Invierno 2026 · Imputado: Verano 2026 81,00 Bs»); «Saldo a hoy 0,00 Bs» |
| Cronológico V | inicial 0; +81 | inicio 0,00; +81 («Pagado»); «Saldo al cierre del período (30/06/2026) 81,00 Bs» |
| Inicio | Familias 0 · Pagos recibidos 81 | igual |
| Resumen | V 81 · I −81 | V **0,00** · I **0,00** |

### D04-03 · Un pago repartido entre dos campañas

**Entrada:** c1 15/03, V, +81. c2 10/08, I, +40. q1 20/10, −100, registrado en I. Imputaciones: q1 → c1 81 y q1 → c2 19.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | 21,00 | «Cargos 121,00 Bs · pagos aplicados 100,00 Bs» · «Deuda pendiente 21,00 Bs · a favor (no aplicado a deuda) 0,00 Bs» · **21,00** |
| Cuentas · V | 81,00 | «… pagos aplicados 81,00 Bs» · **0,00** |
| Cuentas · I | −60,00 | «Cargos de Invierno 2026 40,00 Bs · pagos aplicados 19,00 Bs» · **21,00** |
| Cronológico I | 81; 121; 21 | igual en cifras, con «Imputado: Verano 2026 81,00 Bs · Invierno 2026 19,00 Bs» |
| Inicio | Familias 21 · Pagos recibidos 100 | igual |
| Resumen | V 81 · I −60 | V **0,00** · I **21,00** |

### D04-04 · Exceso de pago

**Entrada:** c1 15/03, V, +81. q1 20/10, −100, registrado sin campaña. Imputación: q1 → c1, 81; quedan 19 sin imputar.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «A favor · todas» −19,00 | «Cargos 81,00 Bs · pagos aplicados 81,00 Bs» · «Deuda pendiente 0,00 Bs · a favor (no aplicado a deuda) 19,00 Bs» · **−19,00** |
| Cuentas · V | 81,00 | «Cargos de Verano 2026 81,00 Bs · pagos aplicados 81,00 Bs» · «Saldo neto · todas las campañas -19,00 Bs» · «A favor (no aplicado a deuda) 19,00 Bs (sin campaña)» · **0,00** |
| Cuentas · I | 0,00 | «Sin cargos.» · «Saldo neto · todas las campañas -19,00 Bs» · «A favor (no aplicado a deuda) 19,00 Bs (sin campaña)» · **0,00** |
| Detalle · origen | — | V: cargos 81,00 · aplicados 81,00 · pendiente 0,00; «Deuda pendiente total 0,00 Bs»; «A favor (no aplicado a deuda) 19,00 Bs»; «pagos sin imputar 19,00 Bs»; «Saldo neto · todas las campañas -19,00 Bs» |
| Cronológico I | sólo «Saldo inicial de campaña 81,00» | inicio 81,00; −100 (−19,00; «registrado sin campaña · Imputado: Verano 2026 81,00 Bs · sin imputar 19,00 Bs (queda a favor, sin campaña)»); «Saldo a hoy -19,00 Bs» |
| Inicio | **Familias −19,00** · Pagos recibidos 100 | Familias **0,00** · «A favor de familias: 19,00 Bs» · Pagos recibidos 100 |
| Resumen | V 81 · I 0 | V **0,00** · I **0,00** |

### D04-05 · Anticipo seguido de cargos posteriores

**Entrada (Tercero Demo):**
- q1: 05/07, `ADVANCE` −300, registrado en I, con `date` de prueba. Sin cargos, no se imputa.
- c1: 10/07, compra en I, `PURCHASE_ALLOCATION_CHARGE` +250.
- c2: 15/08, +120.
- Paso **5b**: q2, 20/10, −70, registrado en I → imputación q2 → c1, 70.

| Vista | Hoy (5a / 5b) | Esperado (5a / 5b) |
|---|---|---|
| Cuentas · Todas | 70,00 / 0,00 | 5a: «Cargos 370,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 370,00 Bs · a favor (no aplicado a deuda) 300,00 Bs» · **70,00**. 5b: «… pagos aplicados 70,00 Bs» · «Deuda pendiente 300,00 Bs · a favor … 300,00 Bs» · **0,00** |
| Cuentas · I | 70,00 / 0,00 | 5a: «Cargos de Invierno 2026 370,00 Bs · pagos aplicados 0,00 Bs» · «Saldo neto · todas las campañas 70,00 Bs» · «A favor … 300,00 Bs (sin campaña)» · **370,00**. 5b: … · **300,00** |
| Cronológico I | inicial 0; −300, +250, +120 [5b: −70] | igual en cifras. q1 «Sin imputación registrada: 300,00 Bs (queda a favor, sin campaña)»; c1 «Pendiente a hoy 250,00 Bs» (5b: 180,00 Bs); c2 «Pendiente a hoy 120,00 Bs»; q2 «Imputado: Invierno 2026 70,00 Bs» |
| Inicio | Terceros 70 / 0 · Pagos recibidos 300 / 370 | Terceros 70 / 0 (I-5: max(0, 370 − 300) / max(0, 300 − 300)) · igual |
| Resumen I | 70 / 0 | **370,00 / 300,00** |

Por el criterio Q-1 de §7, el crédito queda separado: la deuda por cargo no se reduce con un anticipo sin imputación.

### D04-06 · Reversión de un cargo que ya tenía un pago imputado

**Entrada:**
- c1: 15/03, V, +81 (aplicación a1).
- c2: 10/08, I, +40.
- q1: 20/10, −50, sin campaña → imputación q1 → c1, 50.
- Día de la prueba (25/10): se revierte a1 → r1 −81 (V).

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | −10,00 | «Cargos 121,00 Bs · revertidos 81,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 40,00 Bs · a favor (no aplicado a deuda) 50,00 Bs» · **−10,00** |
| Cuentas · V | 0,00 | «Cargos de Verano 2026 81,00 Bs · revertidos 81,00 Bs · pagos aplicados 0,00 Bs» · «Saldo neto · todas las campañas -10,00 Bs» · «A favor … 50,00 Bs (sin campaña)» · **0,00** |
| Cuentas · I | 40,00 | «Cargos de Invierno 2026 40,00 Bs · pagos aplicados 0,00 Bs» · neto -10,00 · a favor 50,00 · **40,00** |
| Detalle · origen | — | «Verano 2026: cargos 81,00 Bs · revertidos 81,00 Bs · pagos aplicados 0,00 Bs · pendiente 0,00 Bs»; «50,00 Bs imputados a cargos revertidos de Verano 2026 quedan a favor»; I … pendiente 40,00; total 40,00; a favor 50,00 («liberado por reversión 50,00 Bs»); neto −10,00 |
| Cronológico Todas | 81, 121, 71, −10 | c1 «Revertido el {día de la prueba}»; q1 «Imputado a un cargo revertido (Verano 2026, 15/03/2026): 50,00 Bs. Queda a favor.»; r1 «Revierte el cargo del 15/03/2026»; «Saldo a hoy -10,00 Bs» |
| Cronológico I | inicial 0,00; +40 → 40 (no cuadra) | inicio 81,00; 121; 71; −10; «Saldo a hoy -10,00 Bs» |
| Inicio | Familias −10 | Familias **0,00** · «A favor de familias: 10,00 Bs» |
| Resumen | V 0 · I 40 | V 0,00 · I 40,00 |

El crédito liberado no se reimputa a c2: criterio Q-1, I-8.

### D04-07 · Cargo revertido antes del pago (D-15) y su histórico

**Entrada:** c1 15/03, V, +81 (a1). c2 10/08, I, +40. Se revierte a1 → r1 −81. Después, q1 −50, registrado en I.
- **D04-07:** pago registrado con D-04 → imputación q1 → c2 40; 10 sin imputar.
- **D04-07h:** la base guardada por el código anterior, con la imputación q1 → c1 50. Se conserva.

| Vista | Hoy | Esperado D04-07 | Esperado D04-07h |
|---|---|---|---|
| Imputaciones guardadas | q1 → c1 50 | q1 → c2 40 | q1 → c1 50 (sin tocar) |
| Cuentas · Todas | −10,00 | «Cargos 121,00 Bs · revertidos 81,00 Bs · pagos aplicados 40,00 Bs» · «Deuda pendiente 0,00 Bs · a favor … 10,00 Bs» · **−10,00** | «… pagos aplicados 0,00 Bs» · «Deuda pendiente 40,00 Bs · a favor … 50,00 Bs» · **−10,00** |
| Cuentas · I | −10,00 | «… pagos aplicados 40,00 Bs» · **0,00** | «… pagos aplicados 0,00 Bs» · **40,00** |
| Estado del pago | — | «Imputado: Invierno 2026 40,00 Bs · sin imputar 10,00 Bs (queda a favor, sin campaña)» | «Imputado a un cargo revertido (Verano 2026, 15/03/2026): 50,00 Bs. Queda a favor.» |
| Inicio | Familias −10 | 0,00 · «A favor de familias: 10,00 Bs» | 0,00 · «A favor de familias: 10,00 Bs» |
| Resumen I | −10 | **0,00** | **40,00** |

### D04-08 · Reversión de la compra de un tercero con pago imputado; reversión de pagos

**Entrada (Tercero Demo):**
- c1: 05/03, compra en V, +250.
- q1: 10/04, −100, registrado en V → imputación q1 → c1, 100.
- Día de la prueba: se revierte la compra → r1 −250.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | −100,00 | «Cargos 250,00 Bs · revertidos 250,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 0,00 Bs · a favor … 100,00 Bs» · **−100,00** |
| Cuentas · V | −100,00 | «Cargos de Verano 2026 250,00 Bs · revertidos 250,00 Bs · pagos aplicados 0,00 Bs» · neto −100 · a favor 100 · **0,00** |
| Cronológico V | 0; 250; 150; −100 | inicio 0,00; +250; −100 (150, «Imputado a un cargo revertido (Verano 2026, 05/03/2026): 100,00 Bs. Queda a favor.»); «Saldo al cierre del período (30/06/2026) 150,00 Bs» |
| Cronológico I | sólo inicial −100 | inicio 150,00; −250 (−100); «Saldo a hoy -100,00 Bs» |
| Inicio | Terceros −100 | Terceros **0,00** · «A favor de terceros: 100,00 Bs» |
| Resumen V | −100 | **0,00** |

La reversión de pagos de cuenta no existe (H-10) y D-04 no la añade. Si algún día existe, su fila caerá en la clase «compensación de un crédito» de §2.1 y nunca se tomará por deuda.

### D04-09 · Históricos sin imputación comprobable

- **09a:** es D04-01 1a.
- **09b, pago sin imputaciones** (base anterior a v3): c1 15/03, V, +81. q1 01/04, −50, registrado en V, sin filas en `payment_allocations`.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | 31,00 | «Cargos 81,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 81,00 Bs · a favor … 50,00 Bs» · **31,00** |
| Cuentas · V | 31,00 | «… pagos aplicados 0,00 Bs» · neto 31,00 · «A favor … 50,00 Bs (sin campaña)» · **81,00** |
| Cronológico V | 0; 81; 31 | q1 «registrado en Verano 2026 · Sin imputación registrada: 50,00 Bs (queda a favor, sin campaña)»; «Saldo al cierre del período (30/06/2026) 31,00 Bs» |
| Inicio | Familias 31 | **31,00** |
| Resumen V | 31 | **81,00** |

- **09c:** es D04-04.
- **09d:** un crédito sin cargo de origen suma a *u* («Crédito sin cargo de origen registrado: …»).

### Casos adicionales M-1 a M-10

En estos casos la revisión sólo trajo la lista: las cifras de abajo son mías. Cada caso dice qué fija.

| Id | Entrada | Hoy | Esperado |
|---|---|---|---|
| **M-1** Pago exacto | c1 10/08, I, +40. q1 21/10, −40, en I → q1 → c1 40 | Todas 0,00 · I 0,00 | Todas «Cargos 40,00 Bs · pagos aplicados 40,00 Bs» · «Deuda pendiente 0,00 Bs · a favor … 0,00 Bs» · 0,00; I **0,00**; c1 «Pagado»; q1 «Imputado: Invierno 2026 40,00 Bs»; Inicio 0,00 sin línea a favor |
| **M-2** Varios pagos sobre el mismo cargo | c1 15/03, V, +81. q1 01/09, −30, en I; q2 15/09, −30, sin campaña; q3 20/10, −30, en I → c1 ← 30, 30 y 21; q3 deja 9 sin imputar | Todas −9,00 · V 81,00 · I −60,00 · Resumen V 81 / I −60 | Todas «Cargos 81,00 Bs · pagos aplicados 81,00 Bs» · «Deuda pendiente 0,00 Bs · a favor … 9,00 Bs» · −9,00; V **0,00**; I **0,00**; q3 «Imputado: Verano 2026 21,00 Bs · sin imputar 9,00 Bs (queda a favor, sin campaña)»; Resumen V 0 / I 0; Inicio 0,00 · «A favor de familias: 9,00 Bs» |
| **M-2r** Variante revertida | Como M-2, pero tras q1 y q2 (c1 ← 60) se revierte c1 (r1 −81) y luego se registra q3 −30 | El código viejo imputa q3 → c1 21 (cargo revertido) | q3 **no** se imputa (c1 no es deuda). Todas «Cargos 81,00 Bs · revertidos 81,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 0,00 Bs · a favor … 90,00 Bs» (liberado 60,00 + sin imputar 30,00) · −90,00; q3 «Sin imputación registrada: 30,00 Bs (queda a favor, sin campaña)» |
| **M-3** Cargos del mismo día | c1 10/08, I, +30 (id menor, instante 18:00). c2 10/08, I, +20 (id mayor, instante 00:00, registrado después con selector de día). q1 21/10, −25, en I | Imputa c2 20 y c1 5 (orden por instante) | Imputa **c1 25** (día y luego id). c1 «Pendiente a hoy 5,00 Bs», c2 «Pendiente a hoy 20,00 Bs»; I **25,00** en los dos casos. El cronológico muestra c1 antes que c2 |
| **M-4** Cargo tardío en una campaña cerrada | c1 15/03, V, +81. c2 10/08, I, +40. q1 20/10, −50, en I (c1 ← 50). Tardía confirmada con fecha 20/06 en V → c3 +30. Después q2 −40, en I | V 111 · I −50 · Todas 61 | q2 imputa c1 31 y c3 9 (c3 tiene día 20/06, antes que c2). V **21,00** (c3 «Pendiente a hoy 21,00 Bs»), I **40,00**, Todas 61,00. El cronológico de V cierra en **111,00** tras la tardía (81,00 antes de confirmarla) |
| **M-4b** Pago registrado con el filtro en una campaña cerrada | c1 15/03, V, +81. c2 10/08, I, +40. Filtro V; q1 hoy, −50, registrado en V → c1 ← 50 | V 31 · I 40 · cronológico V 31 (el pago aparece en V) | Diálogo: «Se registra en: Verano 2026 (cerrada). En el estado cronológico aparecerá por su fecha, {hoy}». V **31,00** · I **40,00**. Cronológico V cierra en **81,00** (el pago no cae en su período); cronológico I: inicio 81 → 121 → 71, con q1 «registrado en Verano 2026» |
| **M-5** Adelanto sin cargos | q1 05/07, `ADVANCE` −100, en I | Todas «A favor» −100 · I −100 · Inicio Familias −100 · Resumen I −100 | Todas «Sin cargos.» · «Deuda pendiente 0,00 Bs · a favor … 100,00 Bs» · −100,00; I «Sin cargos.» · **0,00**; detalle origen «Sin cargos.»; Inicio **0,00** · «A favor de familias: 100,00 Bs»; Resumen I **0,00** |
| **M-6** Redondeo por lote | Dos compras de 0,25 L de un fungicida a 10,10 Bs/L, asignadas a Familiar (01/07 y 02/07). Aplicación de 0,5 L el 10/08 → 2,53 + 2,53 = **5,06** (0,5 × 10,10 = 5,05 sin redondeo por lote). q1 21/10, −5,05, en I | Todas 0,01 · I 0,01 | El cargo es **5,06 Bs**; c1 «Pendiente a hoy 0,01 Bs»; I **0,01**; costo del producto 5,06. Ningún importe se recalcula |
| **M-7** Tercero `BY_PURCHASE_ALLOCATION` | Compra 10/07 en I de 2 L de Glifosato a 45,00 para Tercero → +90. El tercero aplica 1 L el 15/08 (sin cargo; costo 45). q1 20/10, −60, sin campaña → c1 ← 60 | Todas 30 · I **90** · Terceros 30. Formulario: «No genera cargo: Tercero Demo ya pagó estos productos al comprarlos» (falso: debe 30) | Todas 30,00; I **30,00**; Terceros 30,00. Costo por chaco 45,00 sin cambio. En E-15 el formulario dice «Esta aplicación no genera cargo a Tercero Demo: su política cobra al asignar compras.» |
| **M-8** Exportación CSV/PDF | D04-01 1a, filtro I | Columnas Fecha, Concepto, Chaco, Cargo, Crédito, Acumulado; «Saldo final» 121,00 | Columnas de §2.6. Filas: «Saldo al inicio del período (01/07/2026)» 81,00; 10/08 cargo 40,00, «Pendiente a hoy 40,00 Bs», 121,00; 20/10 «Pago», «registrado sin campaña», crédito 50,00, «Imputado: Verano 2026 50,00 Bs», 71,00. Totales de §2.6: 81,00 · 40,00 · 50,00 · 71,00 · 40,00 · 0,00 · 71,00. CSV y PDF con las mismas cifras |
| **M-9** Titular con FIFO de varios lotes (E-15) | El Titular compra Glifosato 1 L a 45,00 (01/07) y 1 L a 38,00 (05/07) y aplica 2 L el 20/10 en I → 45 + 38 = **83,00** (`USAGE_CHARGE` 83). Variante: se revierte | Titular «Pendiente 83,00»; tras revertir 0,00 | Tarjeta «Consumo aplicado (costo FIFO) · todas las campañas 83,00 Bs» · «1 aplicación vigente». Tras revertir: «Consumo aplicado … 0,00 Bs» · «Sin aplicaciones vigentes · 1 revertida (83,00 Bs, no cuenta)» |
| **M-10** Transferencia del titular (E-15) | El Titular compra 2 L de Glifosato a 45,00 (01/07). Transfiere 1 L a Familiar el 05/08 (sin cargo, RN-35). El Titular aplica 1 L el 10/08 (+45). Familiar aplica el litro recibido el 12/08 (+45) | Inicio Familias **90** (Titular 45 + Familiar 45) | Tarjeta: consumo **45,00 Bs** (lo transferido no es consumo propio); Familiar: deuda 45,00; Inicio Familias **45,00** |

### D04-10 · Consistencia

Cada prueba comprueba, sobre las mismas filas, las invariantes de §2.8 en la lista de Cuentas («Todas» y cada campaña), el detalle, la exportación, Inicio y el resumen de campaña. Costo por chaco y por producto no cambian en ningún ejemplo D04 ni M.

---

## 4. Históricos sin imputación comprobable

| Situación | Cómo se reconoce | Texto | Dónde cuenta |
|---|---|---|---|
| Crédito sin ninguna imputación | u = \|importe\| | «Sin imputación registrada: {u} (queda a favor, sin campaña)» | *u* |
| Crédito parcialmente imputado | 0 < u < \|importe\| | «Imputado: … · sin imputar {u} (queda a favor, sin campaña)» | aplicados + *u* |
| Imputación guardada a un cargo revertido | imputado(c) > neto(c) | «Imputado a un cargo revertido ({K}, {fecha}): {x}. Queda a favor.» | *L* |
| Crédito con `campaign_id` NULL | NULL | «registrado sin campaña» | cronológico por fecha |
| `CREDIT_ADJUSTMENT` sin cargo de origen | sin `reversal_of_id` | «Crédito sin cargo de origen registrado: {x} (queda a favor, sin campaña)» | *u* |

- No se distingue un anticipo de un pago anterior a v3: no hay dato que lo pruebe.
- **Imputaciones guardadas por instante.** Hasta D-04, `addAccountPayment` ordenaba los cargos por instante (`transaction_date`) y no por día local y luego `id`. Esas imputaciones se conservan tal cual (I-8). Por eso una base histórica puede tener imputaciones que no siguen el FIFO por día (caso M-3), y la vista las muestra como se guardaron.
- Nada se reasigna, nada se imputa con retroactividad y no se edita ninguna fila (I-8).

---

## 5. Cambios previstos

### 5.1 D-04 (`feat/d04-imputacion-pagos-campanas`)

**Repositorio:**

| Id | Cambio |
|---|---|
| D-R1 | `addAccountPayment` (y un nuevo `registerAccountPayment` que devuelve las imputaciones escritas). Los candidatos son los **cargos** de §2.1 con pendiente = importe − revertido − imputado. El orden es **día local y luego id**. Sólo afecta a pagos nuevos. Sin esquema nuevo |
| D-R2 | `accountLedger({personId})`: **una** consulta (`UNION ALL` de campañas, personas, asientos e imputaciones). La clasificación y los cálculos de §2.1 se hacen en Dart puro (`lib/domain/account_ledger.dart`), con los días locales de `campaign_calendar.dart` |
| D-R3 | `accountSummaries({campaignId})` sobre D-R2: C, R, A y P del alcance, más *P* total, *u*, *L*, *X*, *F* y *N* también con filtro K, sin ADMIN y con el orden de §2.3 |
| D-R4 | `accountStatement(personId, {campaignId})` sobre D-R2: desglose por origen, cronológico por período con apertura y cierre, y textos de estado (§2.5). Una consulta |
| D-R5 | `dashboard()`: las cifras de familias, terceros y pagos recibidos salen de **una** lectura de D-R2 (sustituye tres consultas por una), con «A favor de …» |
| D-R6 | `campaignCloseSummary.receivable_bob_minor` = Σ P_K, sin ADMIN (D-R2 sustituye a una consulta) |
| D-R7 | Las lecturas heredadas `settlements`, `topSettlements`, `detailedStatement`, `personCampaignBalance` y `statement` y sus versiones tipadas **se conservan sin cambios** para sus consumidores de prueba (caracterización de EVO-004). Llevan el comentario «Heredada: sólo caracterización». `ReportComposer.accountStatement` también. Las pantallas dejan de usarlas, con dos excepciones en D-04: `topSettlements` sigue en Inicio y `detailedStatementTyped` en Personas (pestaña Cuenta). Las dos pasan al libro en E-15 |
| D-R8 | `accountLedger(withDetails: false)` no resuelve concepto ni chaco (sin `GROUP_CONCAT`). La usan `accountSummaries`, `dashboard()` y `campaignCloseSummary` |

**Pantallas y servicios:**
- `settlements_screen.dart`: §2.3–§2.5. El número de consultas de `_load` no cambia (5).
- `report_export_service.dart:168-196` y `report_composer.dart`: §2.6 y rótulo del resumen.
- `catalogs_screen.dart:204`: rótulo del diálogo de cierre.
- `dashboard_screen.dart`: línea «A favor de …».
- Selector de Reportes: sin cambio en D-04.
- `person_detail_screen.dart:31`: sin cambio en D-04.

**Pruebas:**
- Un archivo con los ejemplos sobre las lecturas nuevas.
- Otro sobre las API que ya existían en `ed9c55c` (imputaciones, `dashboard`, `campaignCloseSummary`, textos de Cuentas y de Inicio, exportación), que falla por aserción en la base.
- `regression_widget_test` cambia su repositorio falso porque la pantalla lee otra fuente (decisión D-04, D04-01).

**Documentos:** RN-37 a RN-42, F-10/F-11, KI-05.

### 5.2 E-15 (`feat/e15-consumo-propio-titular`)

| Id | Cambio |
|---|---|
| E-R1 | D-R2 añade a la **misma** consulta los vínculos (`owner_bindings`) y las aplicaciones de las personas que han sido titulares. Un asiento es propio según el criterio de clase de §7 (Q-3) |
| E-R4 | **Escritura (A1):** `registerAccountPayment` imputa un pago nuevo sólo a cargos de su misma clase: el pago de un asiento no propio va a cargos no propios y el de uno propio, a cargos propios. **Lectura:** una imputación guardada entre clases distintas no cuenta como aplicada; queda sin imputar en la cuenta del crédito, con el texto «Imputado a un cargo propio de cuando era titular: X. Queda a favor.» (o, en un registro propio, «Imputado a un cargo por cobrar: X. No cuenta como cobro.») |
| E-R5 | Personas y su detalle muestran el neto por cobrar del libro, sin lo propio (A2). El paso a modo propio se bloquea sólo por el saldo neto no propio de las demás personas (`OperationModeStore`, hallazgo 4), con la misma regla N ≠ 0. La consulta única vive en `lib/data/account_ledger_query.dart` y la usan el repositorio y el store |
| E-R2 | Consumo propio = aplicaciones no revertidas del titular dentro de su intervalo, con su costo FIFO, más las revertidas aparte. Va **dentro** de D-R2: no se añade ninguna consulta a `_load` de Cuentas |
| E-R3 | Los asientos propios salen de cuentas por cobrar, Inicio («por cobrar», «Pagos recibidos», «Principales saldos», que pasa a leerse de D-R2 en `dashboard()`) y resumen de campaña. No cambia ninguna escritura |

**Pantallas:**
- Tarjeta «Consumo y costos propios».
- «Movimientos propios» y su exportación.
- Personas y su detalle (`person_detail_screen.dart:31` pasa a D-R4).
- `application_form_screen.dart` (hallazgos 6 y 17).
- El selector de Reportes conserva a la persona; la exportación del titular se compone como «Movimientos propios del titular».

**Documentos:** RN-27, RN-41, F-10, F-15.

---

## 6. Contradicciones con contratos y reglas existentes

| Id | Regla o contrato | Contradicción | Tratamiento |
|---|---|---|---|
| **C-01** | `BRIEF_00_Rebaseline_Project3.md:244`: MOB #49 (REC-013) quedó fuera de alcance, «se conserva sin evolución» | D-04 y E-15 la evolucionan; no hay RF en el Cap. III | Se deja constancia aquí: REC-013 se evoluciona por decisión del autor del 2026-10-27. **No se toca el Project** (orden expresa del autor) |
| **C-02** | RN-38: pendiente = cargo − Σ imputaciones, ordenado por fecha. `01_DECISIONES:47` decía, para D-15, que no se cambiaba nada | Un pago nuevo deja de imputarse a cargos revertidos y se ordena por día y luego id | Criterio Q-5 (§7) |
| **C-03** | RN-42, F-10 «Continuidad» y F-11: la apertura se calcula por campaña | La apertura pasa a calcularse por fecha | Criterio Q-4. Se reescriben RN-42 y F-10/F-11 |
| **C-04** | RN-37 en la UI: «Saldo pendiente» o «Saldo a favor» con y sin filtro | Con filtro, la cifra es la deuda por origen (≥ 0) | §2.3 |
| **C-05** | RN-39: el adelanto previo «compensa» por suma | La deuda por cargo y el a favor se muestran por separado | Criterio Q-1 |
| **C-06** | RN-41: el ADMIN nunca aparece en Cuentas | El titular ADMIN aparece en «Consumo y costos propios», fuera de la liquidación | Precisión de RN-41 en E-15 |
| **C-07** | RN-27/RN-01 | Los cargos por consumo del titular no son deuda | Precisión en E-15 |
| **C-08** | F04 §2.3: orden por día efectivo y luego id | Hoy el orden es por instante | Gana el contrato: vistas e imputación nueva |
| **C-09** | `01_DECISIONES` §5: «Inicio no lo suma» | El código lo suma (H-20) | Confirmado en el código; se comprobará en el emulador en la verificación integrada |
| **C-10** | `01_DECISIONES` §2 recomendaba exigir campaña | La decisión del autor lo sustituye | Se sigue la decisión |
| **C-11** | F-15: «por cobrar» = suma con signo por rol | Σ max(0, P − F) por persona, con línea «A favor de …» | Criterio C-11 de §7 |
| **C-12** | #26: en modo propio, pago y adelanto sólo al titular | Se conserva (criterio Q-2) | Sin cambio |
| **C-13** | F04 §2.3 pide la leyenda «Incluye operaciones tardías confirmadas» | No está implementada (H-27) y D-04 no la añade | Carencia previa declarada; el cierre del período puede cambiar (M-4) |

No hay contradicción con F03, con F04 §1 (no se toca la escritura de las reversiones) ni con el contrato de sincronización (H-25).

---

## 7. Criterios de aplicación y puntos que el autor puede revisar

Estos criterios los fija el coordinador, el 2026-10-27, para aplicar las decisiones del autor de esa misma fecha sin salir de lo aprobado. **No son decisiones nuevas atribuidas a Roderich Rendón**, y él puede revisarlos.

| Punto | Criterio | Razón |
|---|---|---|
| **Q-5 / C-02** | Un pago **nuevo** no se imputa a cargos revertidos y se ordena por día local y luego id. Las imputaciones guardadas no se tocan y se muestran como en D04-07h | RN-38 imputa a **deudas**, y un cargo revertido no es deuda pendiente. `01_DECISIONES:47` daba D-15 por «sólo informativo» porque nadie leía las imputaciones. D-04 las convierte en la fuente de «qué deuda quedó pagada» (decisión del autor), así que imputar a un cargo revertido falsearía el desglose (D04-07, M-2r) |
| **Q-1** | Opción A: el crédito sin imputar y el liberado por reversión quedan separados. Ninguna imputación se crea fuera de `addAccountPayment` (I-8) | La decisión prohíbe atribuir un anticipo a una campaña y fabricar asignaciones |
| **Q-4 / C-03** | El estado cronológico es por fecha. Se actualizan RN-42 y F-10/F-11 | Es el único que cuadra con los NULL sin asignarles campaña |
| **Q-2 / C-12** | **No** se quita al titular el pago ni el adelanto: no está aprobado y cambiaría #26. Esos asientos se muestran en «Consumo y costos propios» como «pagos y ajustes registrados», nunca como cobro ni como «Pagos recibidos» de Inicio | — |
| **Q-3 (revisión 2: criterio de clase)** | Un asiento o una aplicación es «propio» si su persona es el **titular vigente** (todos sus asientos, también los anteriores a su vínculo) **o** si su persona era titular el día local del asiento: día(`bound_at`) ≤ día < día(`ended_at`). Lo anterior al primer vínculo es del primer titular. Sustituye a la forma de intervalos sola de la revisión 2 del documento, que dejaba al titular vigente como deudor de lo anterior a su vínculo | Aplica de forma literal «el titular no figura como deudor de sí mismo» y «un cargo propio no es deuda». El titular anterior conserva como propios sólo los asientos de su intervalo. Es un supuesto de presentación y de imputación (A1): no reescribe datos guardados. La tarjeta muestra al titular vigente y el detalle de un titular anterior, «Consumo propio mientras fue titular» |
| **Hallazgo 4 (punto para el autor)** | El paso a modo propio se bloquea por el saldo neto no propio ≠ 0 de las demás personas | Una persona con deuda por cargo y crédito iguales (D04-05 5b: P = 300, F = 300, N = 0) **no** bloquea el paso, como hasta ahora. El autor puede preferir bloquear también ese caso |
| **C-11** | Inicio: «por cobrar» = Σ max(0, P − F) por persona, más «A favor de familias/terceros: X» si X > 0 | «Conservan sus reglas» se refiere a las políticas de cargo, no a la agregación |
| **C-01 / Q-6** | No se toca el Project; sólo se deja constancia en este documento | Orden expresa del autor |
| **C-09** | Confirmado en el código; se comprobará en el emulador en la verificación integrada | — |

---

## 8. Origen de las decisiones

D-04 y E-15 son **decisiones del autor del proyecto, Roderich Rendón, del 2026-10-27**. Este documento las desarrolla. Los criterios de §7 son criterios de aplicación del coordinador y el autor puede revisarlos. No se atribuye ninguna aprobación al tutor ni a la Directiva.

---

# Parte B (anexo) · E-15 · Consumo y costos propios del titular

### B.1 Definición

- **Titular:** en la tarjeta, el vínculo vigente de `owner_bindings`. La propiedad de cada asiento sigue el criterio de clase de §7 (Q-3). No se usa `persons.role`: el titular puede ser FAMILY o ADMIN.
- **Consumo aplicado (costo FIFO):** Σ `applications.total_cost_bob_minor` de las aplicaciones de la persona dentro de su intervalo y con `reversed_at IS NULL`, filtradas por la campaña de la aplicación. La política de cargo no interviene.
  - Las revertidas se informan aparte.
  - Las compras asignadas no son costo hasta que se aplican.
  - Lo transferido a otros no es consumo propio (M-10).
- **Asientos propios:** se conservan y se muestran como registro: cargos anotados, créditos por reversión y pagos y ajustes registrados. No entran en pendientes, en «por cobrar», en «Pagos recibidos», en «Principales saldos» ni en el resumen de campaña.

### B.2 Textos exactos

- **Tarjeta (encima de la lista):** cabecera «Consumo y costos propios» y el nombre del titular.
  - Consumo: «Consumo aplicado (costo FIFO) · {todas las campañas | K} {X}».
  - Aplicaciones: «1 aplicación vigente», «{n} aplicaciones vigentes» o, con n = 0, «Sin aplicaciones vigentes». Si hay revertidas, se añade « · 1 revertida ({y}, no cuenta)» o « · {m} revertidas ({y}, no cuentan)».
  - Asientos, con su ámbito: «Asientos en su cuenta · {todas las campañas | período de K (inicio – fin|hoy)} (no son deuda): cargos anotados {c} · créditos por reversión {r} · pagos y ajustes registrados {q}», o «Sin asientos en su cuenta · {ámbito}.». Con K, los asientos con día dentro de su período.
  - El diálogo del pago propio no lleva «Se aplica primero a la deuda más antigua…» ni saldo: dice «Pago propio: se registra aparte y no es un cobro ni una deuda.». En «Movimientos propios», lo no imputado se rotula «Sin imputar: X», sin «queda a favor».
  - Menú: «Ver movimientos propios», «Exportar movimientos propios», «Registrar pago», «Registrar adelanto» (Q-2). Desde el 2026-10-30, un único «Registrar pago» (RN-39); los adelantos guardados se conservan.
- **Lista sin otras personas:** en modo propio, «En inventario propio no hay cuentas por cobrar.»; en compartido, el texto actual. La tarjeta se muestra igual.
- **«Movimientos propios · {titular}»:**
  - sección «Consumo aplicado (costo FIFO)», con «{K}: {x} ({n} aplicación|aplicaciones)», «Aplicaciones revertidas: {m} ({y})» y «Consumo aplicado · todas las campañas {X}»;
  - sección «Asientos de su cuenta (registro, no deuda)», con filas cronológicas **sin «Acumulado» ni líneas de saldo**. En los cargos no se muestra «Pendiente a hoy» ni «Pagado», sólo «Revertido el …» si procede.
- **Exportación «Movimientos propios del titular»:** columnas Fecha · Concepto · Chaco · Campaña del asiento · Cargo (Bs) · Crédito (Bs); totales «Consumo aplicado, costo FIFO (Bs)», «Cargos anotados (Bs)», «Créditos por reversión (Bs)», «Pagos y ajustes registrados (Bs)».
- **Personas:** fila del titular vigente con subtítulo «{rol} · titular · {superficie}» y cifra «Consumo propio {X}». Detalle con subtítulo «{rol} · titular · consumo propio {X}», tile «Consumo aplicado (costo FIFO) · todas las campañas» y pestaña Cuenta sin «Acumulado» para los asientos propios. Un titular anterior muestra además «Consumo propio mientras fue titular {X}».
- **Formulario de aplicación:**
  - para el titular, en cualquier modo y con cualquier política: «Costo propio: {X}», con «(queda anotado en la cuenta de {T})» si es `BY_ACTUAL_USAGE`;
  - para cualquier persona `BY_PURCHASE_ALLOCATION` que no sea el titular vigente: «Esta aplicación no genera cargo a {T}: su política cobra al asignar compras.». No se afirma que pagó ni que se le cargó: el producto pudo llegarle por transferencia (RN-35).

### B.3 Ejemplos

Precios: Glifosato a 45,00 Bs/L, Bellator a 180,00 Bs/L y Cipermetrina a 80,00 Bs/L. Todo lo del titular vigente es propio (criterio de clase de §7). Con un filtro de campaña, la línea de asientos dice «· período de Invierno 2026 (01/07/2026 – hoy)»; las cifras de abajo son de «Todas» («· todas las campañas»).

| Id | Entrada | Hoy | Esperado |
|---|---|---|---|
| **E15-01** USAGE_CHARGE, compartido | Titular aplica el 20/10 en I: Glifosato 1 L y Bellator 0,2 L → +81. Familiar aplica Cipermetrina 0,25 L el 18/10 → +20 | Cuentas: «Titular … Pendiente · todas 81,00» primero. **Inicio Familias 101,00**; Principales saldos con Titular 81. Resumen I 101 | Tarjeta: «Consumo aplicado (costo FIFO) · todas las campañas 81,00 Bs» · «1 aplicación vigente» · «Asientos en su cuenta · todas las campañas (no son deuda): cargos anotados 81,00 Bs · créditos por reversión 0,00 Bs · pagos y ajustes registrados 0,00 Bs». Lista sin el Titular: Familiar 20. Inicio Familias **20,00**; Principales saldos sin el Titular; Resumen I **20,00**; Personas «Consumo propio 81,00 Bs». Costos sin cambio |
| **E15-02a** Titular ADMIN | La base tiene un **titular ADMIN** (`MANUAL`, vinculado con confirmación) que aplica 81 el 20/10. No hay asientos | El titular no aparece en Cuentas (RN-41) | Tarjeta «Consumo aplicado … 81,00 Bs» · «1 aplicación vigente» · «Sin asientos en su cuenta · todas las campañas.». Inicio sin efecto |
| **E15-02b** Titular `BY_PURCHASE_ALLOCATION` | Base de prueba (la UI no lo produce). Compra 2 L de Glifosato el 05/07 → +90. Aplica 1 L el 20/10 → costo 45, sin asiento | «Titular · Pendiente 90,00» · Inicio incluye 90 | Tarjeta «Consumo aplicado … **45,00** Bs» · «cargos anotados 90,00 Bs». Inicio lo excluye |
| **E15-03** Aplicación revertida | a1 81 el 15/10 → +81; se revierte (−81); a2 Glifosato 1 L el 20/10 → +45 | «Cargos 126 · pagos/créditos 81 · Pendiente 45» | Tarjeta «Consumo aplicado … **45,00** Bs» · «1 aplicación vigente · 1 revertida (81,00 Bs, no cuenta)» · «cargos anotados 126,00 Bs · créditos por reversión 81,00 Bs · pagos y ajustes registrados 0,00 Bs» |
| **E15-04** Pago propio | a_t 81 el 20/10 → +81. El 21/10, «Registrar pago» al Titular por 81 **con el filtro I** → `PAYMENT` −81 en I, imputado a su cargo | **Inicio Pagos recibidos 81,00** | Tarjeta: consumo **81,00 Bs** · «pagos y ajustes registrados 81,00 Bs». Inicio Pagos recibidos **0,00**. Movimientos propios: «Pago · registrado en Invierno 2026», con «Imputado: Invierno 2026 81,00 Bs» y sin acumulado |
| **E15-05** Modo propio | Modo PROPIO; Familiar con saldo 0; Titular aplica 81 el 20/10 | Titular «Pendiente 81» con pago y adelanto; Familiar con el menú deshabilitado; Inicio Familias 81 | Tarjeta con consumo 81 y pago y adelanto (Q-2); Familiar 0,00 con el menú deshabilitado; Inicio Familias **0,00**. Sólo el titular: «En inventario propio no hay cuentas por cobrar.» |
| **E15-06** Cambio de titular (criterio de clase) | P1 titular desde la activación aplica el 10/08 → +81. P2 aplicó el 05/08 → +20. Luego `changeOwner` → P2 | Inicio Familias 101 | El 81 de P1 es propio de su intervalo: P1 en la lista con 0,00 y en su detalle «Consumo propio mientras fue titular 81,00 Bs». El 20 de P2 **es propio**, porque P2 es el titular vigente: P2 no figura en la lista y su tarjeta dice «1 aplicación vigente» y «cargos anotados 20,00 Bs». Inicio Familias **0,00**. (La revisión 2 del documento, sólo con intervalos, daba 20,00) |
| **E15-07** Pago de P1 tras el cambio (A1) | E15-06 sin el 20 de P2. P1 registra hoy un pago de 81 | D-04: el pago se imputa al cargo de 81 y P1 queda en 0,00. E-15 `fd39326` (defecto alto de la revisión cruzada): la misma imputación dejaba a P1 en neto 0,00 con −81 en sus asientos no propios, lo que rompía I-2, y el pago desaparecía | **No se imputa** (el cargo propio no es deuda): P1 neto **−81,00** (a favor), igual a la suma de sus asientos no propios (I-2). Familias 0,00 · «A favor de familias: 81,00 Bs». Con fecha dentro de su intervalo, el pago es propio y va a su cargo propio: P1 neto 0,00 |
| **E15-08** Inverso (A1) | P1, ya no titular, aplica hoy 45 (cargo por cobrar). Registra un pago con fecha de su intervalo (propio) de 45 | D-04: el pago va al cargo más antiguo (el de 81) y P1 queda en 81. E-15 `fd39326`: igual en la escritura, pero un pago propio podía cancelar un cargo por cobrar | El pago va a su cargo **propio** de 81: P1 neto **45,00**; Familias 45,00 |
| **E15-09** Imputación cruzada histórica | Pago de P1 de hoy de 81 con una imputación guardada a su cargo propio | E-15 `fd39326`: P1 neto 0,00 (rompía I-2) | No cuenta como aplicada: «Imputado a un cargo propio de cuando era titular: 81,00 Bs. Queda a favor.»; P1 neto −81,00 (I-2) |
| **M-9** | Ver la tabla M | | |
| **M-10** | Ver la tabla M | | |

---

*Revisión 2, 2026-10-27. Las cifras «hoy» se verificaron sobre `ed9c55c` por lectura del código y por la revisión cruzada.*
