# D-04 y E-15 · Cuentas: imputación de pagos entre campañas y consumo propio del titular

- **Estado:** fase 1, sólo ejemplos y diseño. No hay código de producción en esta rama. Los ejemplos pasan por revisión cruzada antes de implementar.
- **Decisiones de origen:** D-04 y E-15 son **decisiones del autor del proyecto, Roderich Rendón, del 2026-10-27** (`_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`). No se atribuye aprobación al tutor ni a la Directiva.
- **Base verificada:** Mobile `main` `ed9c55c`, rama `feat/d04-imputacion-pagos-campanas`. Las cifras «hoy» salen de leer el código en esa base. No se ejecutó `flutter test` ni ninguna prueba.
- **Organización:** un solo documento. La parte A es D-04 y la parte B (anexo) es E-15. Se eligió así porque E-15 se apila sobre D-04 y usa su mismo modelo de lectura y los mismos datos de ejemplo; la revisión cruzada es una sola. La rama E-15 (`feat/e15-consumo-propio-titular`) todavía no existe.
- **Trazabilidad (Cap. III):** RF-06 y CU-05 (modo propio y compartido), RF-12 y CU-09 (aplicaciones con costeo FIFO, base del costo propio), RF-13 y CU-17 (reversiones), RF-03 (operaciones tardías), DAT. Las cuentas, pagos y adelantos **no tienen un RF propio** en el Cap. III: ver la contradicción C-01 (§6).
- **Numeración de reglas:** en este documento «RN-nn» se refiere a `docs/15_BUSINESS_RULES.md`, como en la propia decisión del autor. Esa numeración no coincide con la del Cap. III. Por eso no se usa en la línea de trazabilidad.

---

## 1. Comportamiento actual verificado (`ed9c55c`)

### 1.1 Escritura

| # | Hecho | Dónde |
|---|---|---|
| H-01 | Asientos en `account_transactions`: positivo = cargo, negativo = pago/adelanto/crédito. `campaign_id` admite NULL. `payment_allocations(payment_transaction_id, charge_transaction_id, amount_bob_minor > 0)`, `UNIQUE` por par. No hay triggers de inmutabilidad en ninguna de las dos tablas. | `lib/data/app_database.dart:466-476` |
| H-02 | La migración a v3 crea `payment_allocations` y **no** rellena imputaciones para los pagos que ya existían. | `lib/data/app_database.dart:549-564` |
| H-03 | Cargo por compra (`PURCHASE_ALLOCATION_CHARGE`) sólo si la política de la persona es `BY_PURCHASE_ALLOCATION`, con la campaña y la fecha de la compra. | `lib/data/agro_repository.dart:1139-1149` |
| H-04 | Cargo por consumo (`USAGE_CHARGE`) por el costo FIFO total sólo si la política **actual** es `BY_ACTUAL_USAGE`, con la campaña y la fecha de la aplicación. | `lib/data/agro_repository.dart:1392-1401` |
| H-05 | Compras y aplicaciones exigen campaña (`campaign_id NOT NULL`): todo cargo tiene campaña de origen. | `lib/data/app_database.dart:419,452` |
| H-06 | `addAccountPayment` inserta el pago o adelanto con el `campaign_id` recibido (puede ser NULL) y la fecha de ahora. Luego imputa a los cargos de la persona con importe > 0, ordenados por `transaction_date, id`, con pendiente = `importe − SUM(imputaciones)`. **No resta las reversiones** (D-15) y no filtra por campaña. El sobrante queda sin imputar. Pago y adelanto son idénticos. | `lib/data/agro_repository.dart:1920-1967` (consulta en 1944-1951) |
| H-07 | En modo propio, sólo se registran pagos del titular. | `lib/data/agro_repository.dart:1931-1933` |
| H-08 | Reversión de aplicación: por cada `USAGE_CHARGE` inserta un `CREDIT_ADJUSTMENT` negado, con la **campaña del cargo**, la **fecha de hoy** y `reversal_of_id`. **No toca** las imputaciones del cargo revertido. | `lib/data/agro_repository.dart:2061-2083` |
| H-09 | Reversión de compra: lo mismo para los `PURCHASE_ALLOCATION_CHARGE`. Además anula los `provider_payments` (RN-45), que no son asientos de cuenta. | `lib/data/agro_repository.dart:2163-2168, 2236-2265` |
| H-10 | **No existe la reversión de un pago o adelanto de cuenta.** No hay ningún método `PAYMENT_REVERSAL` ni equivalente; `addAccountPayment` sólo lo llama `settlements_screen.dart`. | búsqueda en `lib/` |
| H-11 | El titular se crea como `FAMILY` con `BY_ACTUAL_USAGE`. Un `ADMIN` histórico puede ser titular con confirmación (`owner_role = ADMIN`); su política por defecto es `MANUAL`. Un tercero no puede serlo. La UI nunca fija la política: sale del rol (RN-01). | `lib/data/owner_binding_store.dart:230-258`; `lib/domain/person_roles.dart:45-49`; `lib/data/agro_repository.dart:254-276` |

### 1.2 Lectura y pantallas

| # | Hecho | Dónde |
|---|---|---|
| H-12 | Cuentas arranca filtrada por la **campaña activa**; «Todas las campañas» es la opción NULL. | `settlements_screen.dart:62-67, 507-526` |
| H-13 | «Registrar pago/adelanto» pasa `campaignId: selectedCampaignId`. El diálogo muestra «Campaña X» o «Todas las campañas» y «Saldo pendiente» con el saldo **filtrado** de la tarjeta. | `settlements_screen.dart:85-126, 805-821` |
| H-14 | `settlements({campaignId})`: con filtro, suma sólo los asientos con `t.campaign_id = K`, cargos y pagos por igual. Excluye `role = 'ADMIN'` (RN-41). Orden: saldo descendente. | `agro_repository.dart:3294-3303` |
| H-15 | Tarjeta: «Cargos X · pagos/créditos Y» y, a la derecha, «Pendiente · K» o «A favor · K» con el saldo filtrado. | `settlements_screen.dart:563-604` |
| H-16 | `personCampaignBalance`: saldo inicial = asientos cuya **campaña** empieza antes de K (los NULL no cuentan, KI-05); pagos de la campaña = `campaign_id = K`; `total_balance` sin filtro. | `agro_repository.dart:3196-3219` |
| H-17 | Detalle («Ver detalle cronológico»): «Saldo inicial de campaña» + filas de `detailedStatement` con `campaign_id = K`, acumulado desde ese saldo inicial. | `settlements_screen.dart:128-237`; `agro_repository.dart:3321-3337`; `read_models.dart:536-546` |
| H-18 | Exportación del estado de cuenta: mismas lecturas. Columnas Fecha, Concepto, Chaco, Cargo, Crédito, Acumulado. Totales «Total de cargos», «Total de créditos», «Saldo final». | `report_export_service.dart:168-196`; `report_composer.dart:255-322` |
| H-19 | Inicio: «Familias por cobrar» = suma con signo de **todos** los asientos de personas `role = 'FAMILY'`; «Terceros por cobrar» igual con `THIRD_PARTY`; «Pagos recibidos» = suma de PAYMENT y ADVANCE; «Principales saldos» = `topSettlements` (saldo neto, sin ADMIN). | `agro_repository.dart:3361-3410, 3305-3310`; `dashboard_screen.dart:171-183, 401-427` |
| H-20 | **El titular `FAMILY` entra en «Familias por cobrar» y en «Principales saldos».** La consulta filtra por `p.role = 'FAMILY'`, sin mirar `owner_bindings`. Esto contradice `01_DECISIONES_DE_NEGOCIO.md` §5 («Inicio no lo suma… ya ocurre»). Ver C-09. | `agro_repository.dart:3380` |
| H-21 | Resumen de campaña (reporte y diálogo de cierre): «Saldo por cobrar» = suma con signo de los asientos con `campaign_id = K` de todas las personas, titular incluido. | `agro_repository.dart:3190-3192`; `report_composer.dart:231-247`; `catalogs_screen.dart:204` |
| H-22 | Costo por chaco y por producto: suma `applications.total_cost_bob_minor` / `application_items.cost_bob_minor` de aplicaciones no revertidas, con filtro por `a.campaign_id`. No leen cuentas. | `agro_repository.dart:3339-3359` |
| H-23 | Personas y su detalle: «saldo total» / «Saldo total · todas las campañas» = suma con signo sin filtro. La pestaña Cuenta muestra todos los movimientos con «Acumulado». Una persona ADMIN aparece como «no participa en la liquidación». | `person_detail_screen.dart:56-83, 133-160`; `persons_screen.dart:99-108` |
| H-24 | Formulario de aplicación. En modo propio: «Costo propio: X (queda anotado en la cuenta de T)». En compartido, para cualquier `BY_ACTUAL_USAGE`, titular incluido: «Se cargará a T: X». | `application_form_screen.dart:847-866` |
| H-25 | La publicación de consumo al sindicato lee cantidades de aplicaciones, no cuentas. D-04 y E-15 no la afectan. | `lib/data/sync/consumption_publisher.dart:302-304` |
| H-26 | Menú de la tarjeta: en modo propio, «Registrar pago/adelanto» sólo para el titular; para los demás aparece deshabilitado «Inventario propio: pagos sólo del titular» (#26). | `settlements_screen.dart:613-662` |

Las cifras «hoy» de cada ejemplo (§3) se derivan de H-06 y H-14 a H-23.

---

## 2. Definiciones

### 2.1 Conceptos

Para una persona *p*, con importes en centavos y sin redondeos (todo es entero):

- **Cargo** *c*: asiento con importe > 0 y `reversal_of_id IS NULL`. Hoy son `USAGE_CHARGE` y `PURCHASE_ALLOCATION_CHARGE`. Su **campaña de origen** es `c.campaign_id` (nunca NULL, H-05).
- **Revertido(c)** = −SUM de los `CREDIT_ADJUSTMENT` con `reversal_of_id = c.id`. Vale 0 o el importe completo.
- **Neto(c)** = importe(c) − revertido(c).
- **Imputado(c)** = SUM de `payment_allocations.amount_bob_minor` con `charge_transaction_id = c.id`. Son las imputaciones guardadas, tal como están.
- **Pagos aplicados(c)** = min(imputado(c), neto(c)). Es la parte de las imputaciones que cancela deuda real.
- **Liberado por reversión(c)** = imputado(c) − pagos aplicados(c). Es lo que se imputó a un cargo que después, o antes (histórico D-15), quedó revertido. Ese dinero queda a favor.
- **Deuda pendiente(c)** = neto(c) − pagos aplicados(c). Nunca es negativa.
- **Pago** *q*: asiento `PAYMENT` o `ADVANCE`. Su **campaña de registro** es `q.campaign_id`, que puede ser NULL («registrado sin campaña»). Es un dato del registro. **No decide qué deuda cancela.**
- **Sin imputar(q)** = |importe(q)| − SUM de imputaciones con `payment_transaction_id = q.id`.
- **Crédito sin cargo de origen**: un `CREDIT_ADJUSTMENT` con `reversal_of_id IS NULL`. El código actual no los produce; si una base histórica los tuviera, cuentan como a favor sin imputar.
- **A favor sin imputar(p)** = Σ sin imputar(q) + Σ liberado por reversión(c) + Σ créditos sin cargo de origen. **No se atribuye a ninguna campaña.**
- **Saldo neto(p)** = Σ deuda pendiente(c) − a favor sin imputar(p). Es igual a la suma con signo de todos los asientos de *p*, es decir, al saldo de hoy.

Por campaña de origen K: cargos_K, revertidos_K, pagos aplicados_K y deuda pendiente_K suman sólo los cargos con `campaign_id = K`. Se cumple que cargos_K − revertidos_K − pagos aplicados_K = deuda pendiente_K.

### 2.2 Dos cálculos distintos, con etiquetas distintas

| | Desglose por campaña de origen de la deuda | Estado de cuenta cronológico con apertura |
|---|---|---|
| Pregunta | ¿Cuánto falta pagar **hoy** de lo que se cargó en K? | ¿Cómo evolucionó el saldo en el **período** de K? |
| Qué asientos entran | Cargos con `campaign_id = K`, con sus reversiones y sus imputaciones guardadas | **Todos** los asientos de la persona cuyo día local de `transaction_date` cae en el período de K (`CampaignPeriod.contains`), de cualquier `campaign_id` y también NULL |
| Apertura | No tiene | Suma de los asientos con día anterior al inicio de K |
| Resultado | Deuda pendiente de K, ≥ 0 | Saldo al cierre del período (o a hoy), con signo |
| Etiquetas | «Deuda por campaña de origen (a hoy)», «Deuda pendiente · K» | «Estado de cuenta cronológico · período de K (dd/mm/aaaa – dd/mm/aaaa)», «Saldo al inicio del período (dd/mm/aaaa)», «Saldo al cierre del período (dd/mm/aaaa)», «Saldo a hoy» |

- Con el período abierto (campaña activa), «Saldo a hoy» del cronológico es igual al saldo neto de la persona.
- Un asiento con fecha en un hueco entre campañas no aparece en ningún período. Sí entra en la apertura del período siguiente y en «Todas».
- Orden: día local efectivo y, dentro del día, `id` (F04 §2.3, ver C-08).
- La campaña de registro de un pago **sólo** se muestra como dato de la fila. No mueve ninguna cifra.
- La campaña de los `CREDIT_ADJUSTMENT` (la del cargo revertido) tampoco ubica la fila en el cronológico: manda su fecha.

### 2.3 Cuentas (lista): textos exactos

**Filtro «Todas las campañas»:**
- línea 1: «Cargos {C} · revertidos {R} · pagos aplicados {A}». El tramo «· revertidos {R}» sólo aparece si R > 0.
- línea 2: «Deuda pendiente {P} · a favor sin imputar {F}»;
- derecha: «Saldo neto · todas las campañas» y el importe {N}, naranja si N > 0, verde si N ≤ 0.
- Orden: saldo neto descendente y luego nombre.

**Filtro de campaña K:**
- línea 1: «Cargos de K {C_K} · revertidos {R_K} · pagos aplicados {A_K}», con la misma regla para «revertidos»;
- línea 2, sólo si F > 0: «A favor sin imputar {F} (sin campaña)»;
- derecha: «Deuda pendiente · K» y el importe {P_K}, naranja si > 0, verde si = 0.
- Orden: deuda pendiente_K descendente y luego nombre.

Se siguen listando todas las personas no ADMIN, aunque tengan cero (igual que hoy). En E-15 se quita al titular (§B).

### 2.4 Diálogo de pago o adelanto

- Líneas: nombre; «Se registra en: K» o «Se registra sin campaña»; «Saldo neto · todas las campañas: {N}»; «Se aplica primero a la deuda más antigua, de cualquier campaña.»
- Al guardar, el mensaje sale de las imputaciones **escritas**: «Pago de {x} registrado a {persona}. Imputado: {K1} {a1} · {K2} {a2}.» Si sobra, se añade «Sin imputar: {u} (queda a favor).» Si no se imputó nada: «Pago de {x} registrado a {persona}. Sin imputar: {x} (queda a favor).» Para un adelanto, la palabra «Pago» se cambia por «Adelanto».
- No se exige elegir campaña y la de registro sigue saliendo del filtro, NULL con «Todas».

### 2.5 Detalle: textos exactos

Título «Estado de cuenta · {persona}». Tiene dos secciones.

1. **«Deuda por campaña de origen (a hoy)»** (siempre todas las campañas con cargos):
   - una línea por campaña: «{K}: cargos {C_K} · revertidos {R_K} · pagos aplicados {A_K} · pendiente {P_K}». El tramo «revertidos» sólo aparece si es > 0.
   - si una campaña tiene importe liberado por reversión: «{L} imputados a cargos de {K} que después se revirtieron quedan a favor».
   - «Deuda pendiente total {P}», «A favor sin imputar {F}», «Saldo neto {N}».
2. **Estado de cuenta cronológico.** Con «Todas», la cabecera es «Estado de cuenta cronológico · todas las campañas» y no tiene apertura. Con K, la cabecera es «Estado de cuenta cronológico · período de K ({inicio} – {fin|hoy})», precedida de «Saldo al inicio del período ({inicio})».
   - Cada fila lleva concepto; «{fecha} · {tipo} · {chaco} · {campaña del asiento}» (en los pagos, «registrado en K» o «registrado sin campaña»); una línea de estado; el importe y «Acumulado {X}».
   - Línea de estado de un cargo: «Pendiente {p}», «Pagado» (p = 0 y no revertido) o «Revertido el {fecha}».
   - Línea de estado de un pago o adelanto: «Imputado: {K1} {a1} · {K2} {a2}», más «· sin imputar {u} (queda a favor, sin campaña)» si u > 0. Si no tiene ninguna imputación: «Sin imputación registrada: {u} (queda a favor, sin campaña)». Si una imputación apunta a un cargo revertido: «Imputado a un cargo revertido ({K}, {fecha del cargo}): {x}. Queda a favor.»
   - Cierre: «Saldo al cierre del período ({fin})» si K está cerrada, o «Saldo a hoy».

### 2.6 Exportación del estado de cuenta

- **Columnas:** Fecha · Concepto · Chaco · Campaña del asiento · Cargo (Bs) · Crédito (Bs) · Imputación · Acumulado (Bs). «Imputación» lleva la misma línea de estado de §2.5.
- **Filtro:** «Campaña: K (período dd/mm/aaaa – dd/mm/aaaa|hoy)» o «Todas las campañas».
- **Primera fila (con K):** «Saldo al inicio del período (dd/mm/aaaa)».
- **Totales del cronológico:** «Saldo al inicio del período (Bs)» (sólo con K), «Total de cargos (Bs)», «Total de créditos (Bs)», «Saldo al cierre del período (Bs)» o «Saldo a hoy (Bs)».
- **Totales del desglose, a hoy:** con K, «Deuda pendiente por origen · K (Bs)»; con «Todas», una fila «Deuda pendiente por origen · {K} (Bs)» por campaña con cargos y «Deuda pendiente total (Bs)». En los dos casos, «A favor sin imputar (Bs)» y «Saldo neto (Bs)».
- Desaparecen «Saldo inicial de campaña» y «Saldo final (Bs)».

### 2.7 Inicio, Personas y resumen de campaña

- **«Familias por cobrar»** = Σ, sobre las personas `FAMILY`, de max(0, saldo neto). **«Terceros por cobrar»** igual con `THIRD_PARTY`. El saldo a favor de una persona ya no resta la deuda de otra.
- **«Pagos recibidos»** y **«Principales saldos»** (saldo neto) no cambian en D-04.
- **Personas:** el importe es el saldo neto. El rótulo pasa a «saldo neto» y «Saldo neto · todas las campañas».
- **Resumen de campaña** (reporte y diálogo de cierre): «Saldo por cobrar» pasa a «Deuda pendiente de la campaña (por origen)» = Σ, sobre las personas, de la deuda pendiente_K. El total se rotula «Deuda pendiente de la campaña (Bs)».

### 2.8 «Consumo y costos propios» (E-15)

Definición en §B.1.

### 2.9 Invariantes que deben cumplirse en cualquier base

| | Invariante |
|---|---|
| I-1 | Σ_K deuda pendiente_K = deuda pendiente total |
| I-2 | Deuda pendiente total − a favor sin imputar = saldo neto = suma con signo de los asientos = importe de Personas |
| I-3 | Σ de todas las imputaciones guardadas = pagos aplicados + liberado por reversión. Además, Σ \|pagos\| = Σ imputaciones + Σ sin imputar(q) |
| I-4 | Cronológico de la campaña activa: «Saldo a hoy» = saldo neto. Con «Todas», el último acumulado = saldo neto |
| I-5 | «Familias por cobrar» = Σ de max(0, saldo neto) de las tarjetas «Todas» de personas `FAMILY` (en E-15, sin el titular) |
| I-6 | Resumen de K = Σ «Deuda pendiente · K» de la lista filtrada por K (en E-15, sin el titular) |
| I-7 | Ninguna fila de `payment_allocations` existente cambia ni se borra; ninguna se crea fuera de `addAccountPayment` |

---

## 3. Ejemplos con resultados esperados

### 3.0 Datos comunes

- **Campañas:** «Verano 2026» (V), del 01/01/2026 al 30/06/2026, CERRADA. «Invierno 2026» (I), desde el 01/07/2026, ACTIVA.
- **Personas:** «Titular» (FAMILY, `BY_ACTUAL_USAGE`, titular vigente en `owner_bindings`); «Familiar Demo» (FAMILY, `BY_ACTUAL_USAGE`); «Tercero Demo» (THIRD_PARTY, `BY_PURCHASE_ALLOCATION`).
- **Chacos:** «Chaco Norte» (Titular, 1 ha) y «Chaco Familiar» (Familiar Demo, 1 ha).
- **Modo:** COMPARTIDA, salvo que se diga otra cosa.
- **Fechas:** días locales de La Paz. Importes en Bs con dos decimales.
- En los ejemplos D04 el titular no tiene asientos. Su tarjeta sale «0,00» hoy y en D-04, y desaparece de la lista en E-15. Tercero Demo vale 0,00 salvo en D04-05 y D04-08. Sólo se detalla la tarjeta afectada.
- «Hoy» es la cifra que da `ed9c55c` (por lectura del código). «Esperado» es la cifra tras D-04.

### D04-01 · Ejemplo obligatorio: pago global de 50 Bs

**Entrada (Familiar Demo):**
- c1: 15/03/2026, V, `USAGE_CHARGE` +81,00 (aplicación en Chaco Familiar: Glifosato 1 L, 45,00, y Bellator 0,2 L, 36,00).
- c2: 10/08/2026, I, `USAGE_CHARGE` +40,00 (Cipermetrina 0,5 L).
- q1: 20/10/2026, `PAYMENT` −50,00. Variante **1a**: registrado con «Todas» (`campaign_id` NULL). Variante **1b**: registrado con el filtro por defecto (I).
- Imputación guardada en las dos variantes: q1 → c1, 50,00.

| Vista | Hoy | Esperado (1a y 1b iguales salvo «registrado…») |
|---|---|---|
| Cuentas · Todas | «Cargos 121,00 Bs · pagos/créditos 50,00 Bs» · «Pendiente · todas las campañas» **71,00** | «Cargos 121,00 Bs · pagos aplicados 50,00 Bs» · «Deuda pendiente 71,00 Bs · a favor sin imputar 0,00 Bs» · «Saldo neto · todas las campañas» **71,00** |
| Cuentas · V | «Cargos 81,00 · pagos/créditos 0,00» · «Pendiente · Verano 2026» **81,00** | «Cargos de Verano 2026 81,00 Bs · pagos aplicados 50,00 Bs» · «Deuda pendiente · Verano 2026» **31,00** |
| Cuentas · I | 1a: «Cargos 40,00 · pagos/créditos 0,00» · «Pendiente» **40,00**. 1b: «Cargos 40,00 · pagos/créditos 50,00» · «A favor · Invierno 2026» **−10,00** | «Cargos de Invierno 2026 40,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente · Invierno 2026» **40,00** |
| Detalle · origen | (no existe) | «Verano 2026: cargos 81,00 · pagos aplicados 50,00 · pendiente 31,00»; «Invierno 2026: cargos 40,00 · pagos aplicados 0,00 · pendiente 40,00»; «Deuda pendiente total 71,00» · «A favor sin imputar 0,00» · «Saldo neto 71,00» |
| Detalle · cronológico Todas | +81 (81), +40 (121), −50 (71) | +81 (81, «Pendiente 31,00»), +40 (121, «Pendiente 40,00»), −50 (71, «registrado sin campaña» en 1a o «registrado en Invierno 2026» en 1b; «Imputado: Verano 2026 50,00»); «Saldo a hoy 71,00» |
| Detalle · cronológico I | «Saldo inicial de campaña 81,00». 1a: +40 → **121** (no cuadra con 71). 1b: +40 (121), −50 (**71**) | «Saldo al inicio del período (01/07/2026) 81,00»; +40 (121); −50 (71); «Saldo a hoy **71,00**» en las dos variantes |
| Detalle · cronológico V | «Saldo inicial de campaña 0,00»; +81 (81) | «Saldo al inicio del período (01/01/2026) 0,00»; +81 (81); «Saldo al cierre del período (30/06/2026) 81,00». Es el saldo a esa fecha; la deuda de V **hoy** es 31,00 y lleva otra etiqueta |
| Exportación · I | 1a: cargos 40,00 · créditos 0,00 · «Saldo final» 121,00. 1b: 40,00 · 50,00 · 71,00 | inicio 81,00 · cargos 40,00 · créditos 50,00 · «Saldo a hoy» 71,00 · «Deuda pendiente por origen · Invierno 2026» 40,00 · «A favor sin imputar» 0,00 · «Saldo neto» 71,00 |
| Inicio | Familias por cobrar 71,00 · Pagos recibidos 50,00 · Principales saldos: Familiar Demo 71,00 | igual |
| Resumen de campaña | V «Saldo por cobrar» 81,00. I: 1a 40,00, 1b −10,00 | «Deuda pendiente de la campaña (por origen)»: V **31,00**, I **40,00** |
| Diálogo de pago (antes de q1, filtro I) | «Campaña Invierno 2026» · «Saldo pendiente 40,00 Bs» | «Se registra en: Invierno 2026» · «Saldo neto · todas las campañas: 121,00 Bs» · «Se aplica primero a la deuda más antigua, de cualquier campaña.» Después: «Pago de 50,00 Bs registrado a Familiar Demo. Imputado: Verano 2026 50,00 Bs.» |
| Costo por chaco / producto | Chaco Familiar: Todas 121,00, V 81,00, I 40,00 | sin cambio |

**Resultado exigido:** Verano 31, Invierno 40, total 71.

### D04-02 · Pago registrado en la campaña nueva que cancela deuda antigua

**Entrada (Familiar Demo):** c1 15/03/2026, V, +81,00. q1 20/10/2026, `PAYMENT` −81,00, registrado en I. Imputación: q1 → c1, 81,00.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Pendiente · todas» 0,00 (cargos 81,00 · pagos/créditos 81,00) | «Cargos 81,00 Bs · pagos aplicados 81,00 Bs» · «Deuda pendiente 0,00 Bs · a favor sin imputar 0,00 Bs» · «Saldo neto» **0,00** |
| Cuentas · V | «Pendiente · Verano 2026» **81,00** | «Cargos de Verano 2026 81,00 Bs · pagos aplicados 81,00 Bs» · «Deuda pendiente · Verano 2026» **0,00** |
| Cuentas · I | «A favor · Invierno 2026» **−81,00** | «Cargos de Invierno 2026 0,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente · Invierno 2026» **0,00** |
| Detalle · origen | — | «Verano 2026: cargos 81,00 · pagos aplicados 81,00 · pendiente 0,00»; total 0,00 · a favor 0,00 · neto 0,00 |
| Cronológico I | inicial 81,00; −81 (0,00) | «Saldo al inicio del período (01/07/2026) 81,00»; −81 (0,00, «registrado en Invierno 2026 · Imputado: Verano 2026 81,00»); «Saldo a hoy 0,00» |
| Cronológico V | inicial 0,00; +81 (81,00) | inicio 0,00; +81 («Pagado»); «Saldo al cierre del período (30/06/2026) 81,00» |
| Inicio | Familias 0,00 · Pagos recibidos 81,00 | igual |
| Resumen | V 81,00 · I −81,00 | V **0,00** · I **0,00** |

### D04-03 · Un pago repartido entre deudas de dos campañas

**Entrada (Familiar Demo):** c1 15/03/2026, V, +81,00. c2 10/08/2026, I, +40,00. q1 20/10/2026, `PAYMENT` −100,00, registrado en I. Imputaciones: q1 → c1 81,00 y q1 → c2 19,00.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Pendiente · todas» 21,00 | «Cargos 121,00 Bs · pagos aplicados 100,00 Bs» · «Deuda pendiente 21,00 Bs · a favor sin imputar 0,00 Bs» · «Saldo neto» **21,00** |
| Cuentas · V | «Pendiente · Verano 2026» **81,00** | «Cargos de Verano 2026 81,00 · pagos aplicados 81,00» · «Deuda pendiente · Verano 2026» **0,00** |
| Cuentas · I | «A favor · Invierno 2026» **−60,00** | «Cargos de Invierno 2026 40,00 · pagos aplicados 19,00» · «Deuda pendiente · Invierno 2026» **21,00** |
| Cronológico I | inicial 81,00; +40 (121); −100 (21) | igual en cifras, con «Saldo a hoy 21,00». El pago lleva «Imputado: Verano 2026 81,00 · Invierno 2026 19,00» |
| Inicio | Familias 21,00 · Pagos recibidos 100,00 | igual |
| Resumen | V 81,00 · I −60,00 | V **0,00** · I **21,00** |

### D04-04 · Exceso de pago

**Entrada (Familiar Demo):** c1 15/03/2026, V, +81,00. q1 20/10/2026, `PAYMENT` −100,00, registrado sin campaña. Imputación: q1 → c1, 81,00. Sin imputar: 19,00.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «A favor · todas las campañas» **−19,00** | «Cargos 81,00 Bs · pagos aplicados 81,00 Bs» · «Deuda pendiente 0,00 Bs · a favor sin imputar 19,00 Bs» · «Saldo neto · todas las campañas» **−19,00** (verde) |
| Cuentas · V | «Pendiente · Verano 2026» **81,00** | «Cargos de Verano 2026 81,00 · pagos aplicados 81,00» · «A favor sin imputar 19,00 Bs (sin campaña)» · «Deuda pendiente · Verano 2026» **0,00** |
| Cuentas · I | «Pendiente · Invierno 2026» 0,00 | «Cargos de Invierno 2026 0,00 · pagos aplicados 0,00» · «A favor sin imputar 19,00 Bs (sin campaña)» · «Deuda pendiente · Invierno 2026» **0,00** |
| Detalle · origen | — | V: cargos 81,00 · aplicados 81,00 · pendiente 0,00; total 0,00 · «A favor sin imputar 19,00» · «Saldo neto −19,00» |
| Cronológico I | sólo «Saldo inicial de campaña 81,00», sin filas (el pago NULL no aparece) | «Saldo al inicio del período (01/07/2026) 81,00»; −100 (−19,00; «registrado sin campaña · Imputado: Verano 2026 81,00 · sin imputar 19,00 (queda a favor, sin campaña)»); «Saldo a hoy −19,00» |
| Inicio | **Familias por cobrar −19,00** · Pagos recibidos 100,00 | Familias por cobrar **0,00** · Pagos recibidos 100,00 |
| Resumen | V 81,00 · I 0,00 | V **0,00** · I **0,00** |

### D04-05 · Anticipo seguido de cargos posteriores

**Entrada (Tercero Demo):**
- q1: 05/07/2026, `ADVANCE` −300,00, registrado en I. No hay cargos, así que no se imputa nada.
- c1: 10/07/2026, compra en I asignada al tercero, `PURCHASE_ALLOCATION_CHARGE` +250,00.
- c2: 15/08/2026, otra compra, +120,00.
- Paso **5b**: q2, 20/10/2026, `PAYMENT` −70,00, registrado en I → imputación q2 → c1, 70,00.

Hoy no se crea ninguna imputación al llegar un cargo (RN-39, «detalle fino»).

| Vista | Hoy (5a / 5b) | Esperado, diseño base (5a / 5b) |
|---|---|---|
| Cuentas · Todas | «Pendiente · todas» 70,00 / 0,00 | 5a: «Cargos 370,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 370,00 Bs · a favor sin imputar 300,00 Bs» · «Saldo neto» **70,00**. 5b: «Cargos 370,00 · pagos aplicados 70,00» · «Deuda pendiente 300,00 · a favor sin imputar 300,00» · «Saldo neto» **0,00** |
| Cuentas · I | 70,00 / 0,00 | 5a: «Cargos de Invierno 2026 370,00 · pagos aplicados 0,00» · «A favor sin imputar 300,00 Bs (sin campaña)» · «Deuda pendiente · Invierno 2026» **370,00**. 5b: «… pagos aplicados 70,00» · «A favor sin imputar 300,00 Bs (sin campaña)» · **300,00** |
| Cronológico I | inicial 0,00; −300 (−300), +250 (−50), +120 (70) [5b: −70 (0)] | igual en cifras. El adelanto lleva «Sin imputación registrada: 300,00 (queda a favor, sin campaña)»; c1 «Pendiente 250,00» (5b: 180,00); c2 «Pendiente 120,00»; q2 «Imputado: Invierno 2026 70,00»; «Saldo a hoy 70,00» / «0,00» |
| Inicio | Terceros por cobrar 70,00 / 0,00 · Pagos recibidos 300,00 / 370,00 | igual |
| Resumen I | 70,00 / 0,00 | **370,00 / 300,00** |
| Si se aprueba Q-1 B (§7) | — | El cargo nuevo consume el crédito disponible al registrarse: c1 ← q1 250,00 y c2 ← q1 50,00. 5a: deuda 70,00 · a favor 0,00 · neto 70,00 · Resumen I 70,00. 5b: q2 → c2 70,00; deuda 0,00 · neto 0,00 · Resumen I 0,00 |

El diseño base cumple la decisión aprobada: no fabrica imputaciones y no atribuye el anticipo a Invierno. Pero deja «Deuda pendiente · Invierno 2026: 300,00» a una persona con saldo neto 0,00. Por eso se plantea Q-1.

### D04-06 · Reversión de un cargo que ya tenía un pago imputado

**Entrada (Familiar Demo):**
- c1: 15/03/2026, V, +81,00 (aplicación a1).
- c2: 10/08/2026, I, +40,00.
- q1: 20/10/2026, −50,00, registrado sin campaña → imputación q1 → c1, 50,00.
- 25/10/2026: se revierte a1 → r1 `CREDIT_ADJUSTMENT` −81,00, campaña V, fecha 25/10/2026, `reversal_of_id = c1`.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «A favor · todas» −10,00 (cargos 121,00 · pagos/créditos 131,00) | «Cargos 121,00 Bs · revertidos 81,00 Bs · pagos aplicados 0,00 Bs» · «Deuda pendiente 40,00 Bs · a favor sin imputar 50,00 Bs» · «Saldo neto» **−10,00** |
| Cuentas · V | «Pendiente · Verano 2026» 0,00 (cargos 81,00 · pagos/créditos 81,00) | «Cargos de Verano 2026 81,00 · revertidos 81,00 · pagos aplicados 0,00» · «A favor sin imputar 50,00 Bs (sin campaña)» · **0,00** |
| Cuentas · I | «Pendiente · Invierno 2026» 40,00 | «Cargos de Invierno 2026 40,00 · pagos aplicados 0,00» · «A favor sin imputar 50,00 Bs (sin campaña)» · **40,00** |
| Detalle · origen | — | «Verano 2026: cargos 81,00 · revertidos 81,00 · pagos aplicados 0,00 · pendiente 0,00»; «50,00 imputados a cargos de Verano 2026 que después se revirtieron quedan a favor»; «Invierno 2026: … pendiente 40,00»; total 40,00 · a favor 50,00 · neto −10,00 |
| Cronológico Todas | +81 (81), +40 (121), −50 (71), −81 (−10) | igual en cifras. c1 «Revertido el 25/10/2026»; q1 «Imputado a un cargo revertido (Verano 2026, 15/03/2026): 50,00. Queda a favor.»; r1 «Crédito por reversión · Verano 2026»; «Saldo a hoy −10,00» |
| Cronológico I | inicial **0,00** (c1 + r1, de campaña V); +40 → **40,00**. No cuadra con −10 | inicio (01/07/2026) 81,00; +40 (121); −50 (71); −81 (−10); «Saldo a hoy −10,00» |
| Cronológico V | inicial 0,00; +81 (81), −81 (0) | inicio 0,00; +81; «Saldo al cierre del período (30/06/2026) 81,00». r1 tiene fecha de octubre y no cae en V |
| Inicio | **Familias −10,00** · Pagos recibidos 50,00 | Familias **0,00** · Pagos recibidos 50,00 |
| Resumen | V 0,00 · I 40,00 | V 0,00 · I 40,00 |
| Costo por chaco | Chaco Familiar: Todas 40,00 · V 0,00 · I 40,00 (a1 revertida no cuenta) | sin cambio |

### D04-07 · Cargo revertido antes del pago (D-15) y su histórico

**Entrada (Familiar Demo):**
- c1: 15/03/2026, V, +81,00 (a1).
- c2: 10/08/2026, I, +40,00.
- r1: 18/10/2026, reversión de a1, −81,00 (campaña V).
- q1: 20/10/2026, −50,00, registrado en I.

Con el código de hoy (H-06), el pendiente de c1 es 81 − 0 = 81, porque la reversión no se resta. La imputación queda q1 → c1, 50,00: se imputa a un cargo ya revertido.

**D04-07 (pago registrado tras D-04):** la imputación nueva resta las reversiones (§5, D-R1) y queda q1 → c2, 40,00, con 10,00 sin imputar.

**D04-07h (histórico):** la misma base, pero con la imputación q1 → c1 50,00 ya guardada por el código anterior. Se conserva.

| Vista | Hoy | Esperado D04-07 | Esperado D04-07h |
|---|---|---|---|
| Cuentas · Todas | «A favor · todas» −10,00 | «Cargos 121,00 · revertidos 81,00 · pagos aplicados 40,00» · «Deuda pendiente 0,00 · a favor sin imputar 10,00» · neto **−10,00** | «Cargos 121,00 · revertidos 81,00 · pagos aplicados 0,00» · «Deuda pendiente 40,00 · a favor sin imputar 50,00» · neto **−10,00** |
| Cuentas · I | «A favor · Invierno 2026» −10,00 | «Cargos de Invierno 2026 40,00 · pagos aplicados 40,00» · «A favor sin imputar 10,00 Bs (sin campaña)» · **0,00** | «… pagos aplicados 0,00» · «A favor sin imputar 50,00 Bs (sin campaña)» · **40,00** |
| Cronológico I | inicial 0,00 (c1 + r1); +40 (40); −50 (−10) | inicio 81,00; +40 (121) [10/08]; −81 (40) [18/10]; −50 (−10) [20/10, «Imputado: Invierno 2026 40,00 · sin imputar 10,00»]; «Saldo a hoy −10,00» | iguales cifras; q1 «Imputado a un cargo revertido (Verano 2026, 15/03/2026): 50,00. Queda a favor.» |
| Inicio | Familias −10,00 | 0,00 | 0,00 |
| Resumen I | −10,00 | **0,00** | **40,00** |

El saldo neto es el mismo; el desglose no. La diferencia se debe a que no se reescriben las imputaciones guardadas, como manda la decisión. La base histórica muestra lo que de verdad se guardó.

### D04-08 · Reversión de compra de un tercero con pago imputado; reversión de pagos

**Entrada (Tercero Demo):**
- c1: 05/03/2026, compra en V asignada al tercero, +250,00.
- q1: 10/04/2026, `PAYMENT` −100,00, registrado en V → imputación q1 → c1, 100,00.
- 22/10/2026: se revierte la compra (sin consumos) → r1 −250,00 (V, `reversal_of_id = c1`). Sus `provider_payments` quedan anulados (RN-45, sin efecto en cuentas).

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «A favor · todas» −100,00 | «Cargos 250,00 · revertidos 250,00 · pagos aplicados 0,00» · «Deuda pendiente 0,00 · a favor sin imputar 100,00» · neto **−100,00** |
| Cuentas · V | «A favor · Verano 2026» −100,00 | «Cargos de Verano 2026 250,00 · revertidos 250,00 · pagos aplicados 0,00» · «A favor sin imputar 100,00 Bs (sin campaña)» · **0,00** |
| Cronológico V | inicial 0,00; +250 (250), −100 (150), −250 (−100) | inicio 0,00; +250 (250); −100 (150, «Imputado a un cargo revertido (Verano 2026, 05/03/2026): 100,00. Queda a favor.»); «Saldo al cierre del período (30/06/2026) 150,00» |
| Cronológico I | sólo «Saldo inicial de campaña −100,00», sin filas | inicio (01/07/2026) 150,00; −250 (−100, «Crédito por reversión · Verano 2026»); «Saldo a hoy −100,00» |
| Inicio | **Terceros −100,00** · Pagos recibidos 100,00 | Terceros **0,00** · Pagos recibidos 100,00 |
| Resumen V | −100,00 | **0,00** |

**Reversión de un pago o adelanto de cuenta:** hoy no existe (H-10). Un pago registrado por error no se puede anular desde la app. D-04 **no** la añade, porque no está en lo aprobado; queda como limitación declarada. El diseño la deja preparada: §2.1 define cargo como importe > 0 **y** `reversal_of_id IS NULL`, así que una futura fila compensatoria positiva de un pago nunca se tomaría como deuda imputable.

### D04-09 · Registros históricos sin imputación comprobable

- **09a. Pago NULL antiguo con imputación:** es D04-01 1a. Se muestra «registrado sin campaña» con su imputación real.
- **09b. Pago sin imputaciones** (base anterior a v3, H-02). Familiar Demo: c1 15/03/2026, V, +81,00; q1 01/04/2026, −50,00, registrado en V, **sin filas en `payment_allocations`**.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Pendiente · todas» 31,00 | «Cargos 81,00 · pagos aplicados 0,00» · «Deuda pendiente 81,00 · a favor sin imputar 50,00» · neto **31,00** |
| Cuentas · V | «Pendiente · Verano 2026» 31,00 | «Cargos de Verano 2026 81,00 · pagos aplicados 0,00» · «A favor sin imputar 50,00 Bs (sin campaña)» · **81,00** |
| Cronológico V | inicial 0,00; +81 (81), −50 (31) | inicio 0,00; +81 («Pendiente 81,00»); −50 (31, «registrado en Verano 2026 · Sin imputación registrada: 50,00 (queda a favor, sin campaña)»); «Saldo al cierre del período (30/06/2026) 31,00» |
| Inicio | Familias 31,00 | Familias **31,00** (max(0, 31)) |
| Resumen V | 31,00 | **81,00** |

No se crea ninguna imputación retroactiva: sería fabricar una asignación que nunca se guardó.

- **09c. Pago NULL parcialmente imputado:** es D04-04.
- **09d. Crédito sin cargo de origen** (`CREDIT_ADJUSTMENT` sin `reversal_of_id`): el código actual no lo produce. Si aparece, suma a «A favor sin imputar» y su fila dice «Crédito sin cargo de origen registrado: {x} (queda a favor, sin campaña)».

### D04-10 · Consistencia entre vistas

Para cada ejemplo, las pruebas de la fase 2 comprueban las invariantes I-1 a I-7 de §2.9 sobre las mismas filas: lista de Cuentas («Todas» y cada campaña), detalle, exportación (CSV y PDF desde el mismo `ReportTable`), Inicio, Personas y resumen de campaña. Costo por chaco y por producto no cambian en ningún ejemplo D04.

---

## 4. Históricos sin imputación comprobable: qué se muestra

| Situación en la base | Cómo se reconoce | Texto | Dónde cuenta |
|---|---|---|---|
| Pago o adelanto sin ninguna imputación (anticipo sin deuda, o base anterior a v3) | `sin imputar(q)` = importe | «Sin imputación registrada: {x} (queda a favor, sin campaña)» | A favor sin imputar |
| Pago parcialmente imputado | 0 < `sin imputar(q)` < importe | «Imputado: {K} {a} · sin imputar {u} (queda a favor, sin campaña)» | Imputado en su campaña; el resto, a favor |
| Imputación guardada a un cargo revertido (D-15 o reversión posterior) | `imputado(c)` > `neto(c)` | «Imputado a un cargo revertido ({K}, {fecha}): {x}. Queda a favor.» | Liberado por reversión → a favor |
| Pago con `campaign_id` NULL | `q.campaign_id IS NULL` | «registrado sin campaña» | Ninguna campaña; manda su fecha en el cronológico |
| Crédito sin cargo de origen | `CREDIT_ADJUSTMENT` con `reversal_of_id IS NULL` | «Crédito sin cargo de origen registrado: {x} (queda a favor, sin campaña)» | A favor sin imputar |

No se distingue un anticipo sin deuda de un pago anterior a v3: no hay dato que lo pruebe y no se adivina. No se reasignan los NULL, no se crean imputaciones retroactivas y no se edita ninguna fila (I-7).

---

## 5. Cambios previstos

### 5.1 D-04 (`feat/d04-imputacion-pagos-campanas`)

**Repositorio (`lib/data/agro_repository.dart`):**

| Id | Cambio |
|---|---|
| D-R1 | `addAccountPayment`: el cargo candidato pasa a ser «importe > 0 y `reversal_of_id IS NULL`», con pendiente = importe − revertido − imputado (subconsulta a los `CREDIT_ADJUSTMENT` con `reversal_of_id`). El orden sigue siendo `transaction_date, id` (RN-38). Devuelve las imputaciones escritas para el mensaje de §2.4. Sin cambios de esquema |
| D-R2 | Nueva lectura de desglose por persona (y por campaña de origen): cargos, revertidos, pagos aplicados, liberado, deuda pendiente, a favor sin imputar y saldo neto. Va en **una** consulta con CTE: lo exige el límite de consultas de las pruebas de pantalla con *settle* fijo |
| D-R3 | `settlements({campaignId})` sobre D-R2, con las columnas nuevas. «Todas» ordena por saldo neto y K por deuda_K |
| D-R4 | `personCampaignBalance` se sustituye por una lectura de período: apertura por día local < inicio, filas del período, cierre. Usa `CampaignPeriod.contains` y ordena por día y luego `id` (F04 §2.3) |
| D-R5 | `detailedStatement`: filtro por período en lugar de `campaign_id`; añade el nombre de la campaña del asiento y, para pagos y cargos, su estado de imputación (§2.5) |
| D-R6 | `dashboard()`: «Familias/Terceros por cobrar» = Σ max(0, neto) por rol, sin aumentar el número de consultas |
| D-R7 | `campaignCloseSummary.receivable_bob_minor` = Σ deuda pendiente_K por origen |
| D-R8 | `statement()` (sólo lo usan pruebas) queda igual |

**Modelos (`lib/domain/read_models.dart`, `typed_reads.dart`):** `SettlementRead` con los campos nuevos; `PersonCampaignBalanceRead` pasa a ser una lectura de período; `StatementEntryRead` gana el nombre de campaña y la imputación. `StatementLine.runningBalance` no cambia.

**Pantallas y reportes:**
- `settlements_screen.dart`: tarjeta §2.3, diálogo §2.4, detalle §2.5.
- `report_composer.dart`: estado de cuenta §2.6 y rótulo del resumen §2.7.
- `catalogs_screen.dart:204`: rótulo del diálogo de cierre.
- `person_detail_screen.dart` y `persons_screen.dart`: rótulo «saldo neto».

**Pruebas:**
- Una prueba de repositorio por ejemplo, D04-01 a D04-09, con las invariantes de §2.9.
- Una prueba de widget de la tarjeta y del detalle con los textos exactos, y otra de exportación.
- Hay que actualizar, con nota, las caracterizaciones que fijan el comportamiento viejo: `v4_repository_test` («saldo inicial cruza campañas…»: la apertura por fecha sigue dando 100 000, pero `campaign_payments` desaparece), `report_reads_characterization_test`, `typed_reads_parity_test`, `reports_test`, `report_composer_test`, `report_export_service_test`, `e2e_*`.

**Documentos:**
- `docs/15_BUSINESS_RULES.md` RN-38, RN-39, RN-40, RN-42.
- `docs/05_FEATURES.md` F-10, F-11, F-15.
- `docs/27_KNOWN_ISSUES.md` KI-05 (resuelto).
- `docs/31_TRACEABILITY_MATRIX.md`.

### 5.2 E-15 (`feat/e15-consumo-propio-titular`, apilada sobre D-04)

| Id | Cambio |
|---|---|
| E-R1 | D-R2 recibe el titular vigente (`owner_bindings` con `ended_at IS NULL`, en la misma consulta) y lo excluye de las cuentas por cobrar: `settlements`, `topSettlements`, «Familias/Terceros por cobrar», «Pagos recibidos» y el resumen de campaña. Sin titular vinculado, todo queda como en D-04 |
| E-R2 | Nueva lectura de consumo propio: desde `applications` del titular con `reversed_at IS NULL` (costo FIFO de `application_consumptions`, ya volcado en `total_cost_bob_minor`), con filtro por la campaña de la aplicación. Cuenta las vigentes y las revertidas (número e importe). Resume los asientos de su cuenta por tipo. Una sola consulta |
| E-R3 | No cambia ninguna escritura. El titular conserva su política y sigue recibiendo `USAGE_CHARGE`, y sus imputaciones se siguen creando |

**Pantallas:**
- `settlements_screen.dart`: tarjeta «Consumo y costos propios» encima de la lista; el titular sale de la lista; menú según Q-2; textos de lista vacía (§B.2).
- `dashboard_screen.dart`: sin cambio de código; las cifras vienen de E-R1.
- `persons_screen.dart` y `person_detail_screen.dart` para el titular.
- `application_form_screen.dart` `_chargeText` para el titular en modo compartido.
- `report_composer.dart`: variante «Movimientos propios del titular».

**Pruebas:**
- E15-01 a E15-06.
- Hay que revisar `personal_mode_flows_test` («liquidación: pagos y adelantos sólo del titular», según Q-2) y `f04_historical_admin_owner_test` (el conjunto de `settlements()` no cambia porque sigue sin ADMIN; la tarjeta nueva sí incluye al titular ADMIN).

**Documentos:** RN-27, RN-41 y F-10/F-15 (precisión por titularidad).

---

## 6. Contradicciones con contratos y reglas existentes

| Id | Regla o contrato | Contradicción | Tratamiento propuesto |
|---|---|---|---|
| **C-01** | `_briefs/BRIEF_00_Rebaseline_Project3.md:244`: MOB #49 `[REC-013] Cuentas, pagos, adelantos y saldos` se clasificó «fuera-de-alcance-tesis… Se conserva sin evolución» (Cap. I, 1.7) | D-04 y E-15 **evolucionan** esa funcionalidad. No hay RF del Cap. III que la cubra | Es una decisión del autor del 2026-10-27. Hay que dejar constancia en el Project o el issue (operación GitHub fuera de esta fase) y no inventar un RF. Ver Q-6 |
| **C-02** | RN-38: pendiente = `cargo − SUM(imputaciones)` | D-R1 resta además las reversiones y excluye los positivos con `reversal_of_id` (corrige D-15). Cambia qué cargo cancela un pago futuro cuando hay cargos revertidos (D04-07) | Se trata como precisión de RN-38: se conservan el FIFO de deuda y el cruce de campañas. Necesita confirmación (Q-5) |
| **C-03** | RN-42, F-10 «Continuidad entre campañas» y F-11: la apertura por campaña es la suma de los asientos **de campañas** que empiezan antes | El cronológico con apertura pasa a ser **por fecha** (§2.2). Cambian cifras, por ejemplo el cronológico de I en D04-06: 0,00 pasa a 81,00 | Resuelve KI-05 y la decisión exige separar los dos cálculos. Necesita confirmación (Q-4) |
| **C-04** | RN-37, interpretación en la UI: saldo > 0 «Saldo pendiente», ≤ 0 «Saldo a favor», con o sin filtro | Con filtro, la cifra grande es la deuda pendiente por origen (≥ 0). «A favor» sólo existe a nivel de persona | Rótulos de §2.3 |
| **C-05** | RN-39 («detalle fino»: el adelanto previo «compensa» el cargo por suma) | El saldo neto sigue siendo 0, pero el desglose muestra deuda pendiente 250 y a favor 250 por separado (D04-05) | Consecuencia directa de «no fabricar». Q-1 |
| **C-06** | RN-41: el ADMIN «nunca aparece en la pantalla de cuentas» | En E-15, un titular ADMIN aparece en Cuentas, en «Consumo y costos propios», pero no en la liquidación | Precisión de RN-41: sigue fuera de la liquidación |
| **C-07** | RN-27 / RN-01: «el familiar paga por lo que usa»; la política sale del rol | El titular FAMILY sigue con `BY_ACTUAL_USAGE` y `USAGE_CHARGE`, pero esos cargos no son deuda | Precisión por titularidad (E-15); no se cambia la política |
| **C-08** | F04 §2.3: las vistas privadas de saldo e historial ordenan por **día efectivo** y luego `id` | `detailedStatement` ordena hoy por `transaction_date` completo (instante) y `id` | Gana el contrato: D-R4 y D-R5 ordenan por día y luego `id` |
| **C-09** | `01_DECISIONES_DE_NEGOCIO.md` §5: «Inicio no lo suma en Familias por cobrar (ya ocurre)» | Por lectura, el titular FAMILY **sí** se suma (H-20). No es un contrato, sino un dato del análisis previo | E15-01 fija la cifra. Se recomienda confirmarlo en el emulador en la fase 2 |
| **C-10** | `01_DECISIONES_DE_NEGOCIO.md` §2: recomendaba exigir campaña al pagar y una línea «Pagos sin campaña asignada» | La decisión del autor la sustituye: no se exige campaña y se usan las imputaciones | Se sigue la decisión del autor |
| **C-11** | F-15 / Inicio: «Familias por cobrar» como suma de saldos con signo | Pasa a Σ max(0, neto) por persona. En E-15, además, sin el titular | §2.7 |
| **C-12** | #26 y `personal_mode_flows_test`: en modo propio sólo se ofrece pago o adelanto al titular | Si se acepta Q-2, al titular no se le ofrece; en propio no quedaría ninguna acción de pago | Q-2 |

No se encontró contradicción con F03, con F04 §1 (RF-13, reversiones auditadas: no se toca su escritura) ni con F04 §2 (las tardías añaden cargos con su fecha y su campaña cerrada; aparecen en el período y en el origen correctos). Tampoco con el contrato de sincronización (H-25).

---

## 7. Dudas que cambian materialmente lo aprobado

| Id | Duda | Opciones | Recomendación |
|---|---|---|---|
| **Q-1** | Crédito sin imputar cuando llegan cargos posteriores (D04-05) | **A** (diseño base): no se imputa nunca; la deuda por cargo y el «a favor» se muestran por separado. **B:** al crear un cargo (compra, aplicación, tardía), imputar en la misma transacción el crédito disponible más antiguo, con una imputación real que cambia RN-39. **C:** acción explícita «Aplicar saldo a favor» | A para D-04. B como mejora posterior, si el autor la aprueba |
| **Q-2** | ¿Se sigue ofreciendo «Registrar pago/adelanto» al titular? | Quitarla (el titular no es deudor) frente a mantenerla como «pago propio» | Quitarla. Los históricos se siguen viendo. Cambia #26 y su prueba |
| **Q-3** | ¿Quién es «el titular» en el tiempo? | Sólo el vínculo vigente: tras `changeOwner`, el titular anterior aparece como deudor de sus propios consumos y las deudas previas del nuevo pasan a consumo propio. Por intervalos: un asiento es propio si su fecha cae dentro de un vínculo de esa persona | Vínculo vigente en E-15 (simple y fiel a `owner_bindings`), con E15-06 como caso declarado |
| **Q-4** | Cronológico por **fecha** en lugar de por `campaign_id` (C-03) | Por fecha (propuesta) frente a por campaña de registro más una línea de pagos NULL | Por fecha |
| **Q-5** | Corregir la imputación nueva para no imputar a cargos revertidos (C-02, D-15) | Sí, en D-04 (D-R1), frente a dejarlo como está | Sí. Sin esto, el desglose nuevo mostraría pagos «perdidos» en cargos revertidos |
| **Q-6** | Alcance (C-01) | Registrar en el Project que REC-013 se evoluciona por decisión del autor, o tratarlo sólo en este documento | Registrar, con el dry-run del bloque |

La reversión de pagos de cuenta (H-10) no se plantea como duda: no está en lo aprobado y queda como limitación.

---

## 8. Origen de las decisiones

D-04 y E-15 son **decisiones del autor del proyecto, Roderich Rendón, del 2026-10-27**. Este documento las desarrolla en ejemplos y diseño para su revisión cruzada. No se atribuye ninguna aprobación al tutor ni a la Directiva. Las opciones de §7 están pendientes de decisión del autor.

---

# Parte B (anexo) · E-15 · Consumo y costos propios del titular

### B.1 Definición

- **Titular:** `owner_bindings.person_id` con `ended_at IS NULL` (Q-3). No se usa `persons.role`: un titular puede ser FAMILY o ADMIN. Si no hay titular vinculado, no hay tarjeta y todo sigue como en D-04.
- **Consumo aplicado (costo FIFO):** Σ `applications.total_cost_bob_minor` de las aplicaciones con `person_id` = titular y `reversed_at IS NULL`, con filtro por `applications.campaign_id`. Es el costo FIFO real de los lotes consumidos, sea cual sea su política (H-04 no interviene).
  - Las aplicaciones revertidas se informan aparte y no cuentan.
  - Las compras asignadas al titular **no** son costo hasta que se aplican; están en Inventario.
  - Lo que el titular transfiere a otra persona no es consumo suyo (RN-35, D-07).
- **Asientos de su cuenta:** sus cargos, créditos por reversión y pagos o adelantos se conservan y se muestran como registro, **no como deuda**. No entran en pendientes, en totales por cobrar, en «Pagos recibidos», en «Principales saldos» ni en el resumen de campaña.

### B.2 Textos exactos

- **Tarjeta (encima de la lista):** «Consumo y costos propios · {titular}». Contenido:
  - «Consumo aplicado (costo FIFO) · {todas las campañas | K}» {X};
  - «{n} aplicación vigente» o «{n} aplicaciones vigentes» y, si m > 0, «· {m} revertida(s) ({y}, no cuentan)», con singular o plural según el número;
  - «Asientos en su cuenta, todas las campañas (no son deuda): cargos {c} · créditos por reversión {r} · pagos y adelantos propios {q}», o «Sin asientos en su cuenta.».
  - Menú: «Ver movimientos propios» y «Exportar movimientos propios»; pago y adelanto según Q-2.
- **Lista vacía sin el titular:** en modo propio, «En inventario propio no hay cuentas por cobrar.»; en compartido, el texto actual. La tarjeta del titular se muestra igual.
- **«Movimientos propios · {titular}»:**
  - sección «Consumo aplicado (costo FIFO)», con una línea por campaña «{K}: {x} ({n} aplicaciones)» y «Aplicaciones revertidas: {m} ({y})»;
  - sección «Asientos de su cuenta (registro, no deuda)», con las filas del cronológico de §2.5 **sin «Acumulado» ni líneas de saldo**.
- **Exportación «Movimientos propios del titular»:** columnas Fecha · Concepto · Chaco · Campaña del asiento · Cargo (Bs) · Crédito (Bs); totales «Consumo aplicado, costo FIFO (Bs)», «Cargos anotados (Bs)», «Créditos por reversión (Bs)», «Pagos y adelantos propios (Bs)». Sin «Acumulado» ni «Saldo».
- **Personas:** fila del titular «Titular · consumo propio {X}». Detalle: subtítulo «{rol} · titular · consumo propio {X}»; tile «Consumo aplicado (costo FIFO) · todas las campañas»; pestaña Cuenta sin «Acumulado».
- **Formulario de aplicación, modo compartido, titular `BY_ACTUAL_USAGE`:** «Costo propio: {X} (queda anotado en la cuenta de {titular}; no es deuda)». En modo propio, el texto actual (H-24).

### B.3 Ejemplos

Datos de §3.0. Productos: Glifosato a 45,00 Bs/L, Bellator a 180,00 Bs/L y Cipermetrina a 80,00 Bs/L, todos de lotes FIFO a ese costo.

#### E15-01 · Titular con `USAGE_CHARGE` (compartido)

**Entrada:**
- a_t: 20/10/2026, I, el Titular aplica en Chaco Norte Glifosato 1 L (45,00) y Bellator 0,2 L (36,00) → `USAGE_CHARGE` +81,00.
- Familiar Demo: 18/10/2026, I, aplica Cipermetrina 0,25 L → +20,00.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | 1.º «Titular · Cargos 81,00 · pagos/créditos 0,00 · Pendiente · todas 81,00»; Familiar Demo 20,00; Tercero 0,00 | Tarjeta: «Consumo aplicado (costo FIFO) · todas las campañas 81,00» · «1 aplicación vigente» · «Asientos…: cargos 81,00 · créditos por reversión 0,00 · pagos y adelantos propios 0,00». Lista: Familiar Demo neto 20,00; Tercero 0,00 (sin Titular) |
| Cuentas · I | igual que Todas | Tarjeta «Consumo aplicado (costo FIFO) · Invierno 2026 81,00»; Familiar Demo «Deuda pendiente · Invierno 2026» 20,00 |
| Inicio | **Familias por cobrar 101,00** (Titular + Familiar) · Principales saldos: Titular 81,00 «Familiar», Familiar Demo 20,00, Tercero 0,00 | Familias por cobrar **20,00** · Principales saldos: Familiar Demo 20,00, Tercero 0,00 |
| Resumen I | «Saldo por cobrar» 101,00 | «Deuda pendiente de la campaña (por origen)» **20,00** («Aplicaciones registradas» 101,00, sin cambio) |
| Personas | Titular 81,00 | «Titular · consumo propio 81,00» |
| Exportación del Titular | «Estado de cuenta» … «Saldo final» 81,00 | «Movimientos propios del titular»: consumo aplicado 81,00 · cargos anotados 81,00 · créditos por reversión 0,00 · pagos propios 0,00 |
| Costo por chaco / producto | Chaco Norte 81,00 · Chaco Familiar 20,00; Glifosato 45,00 · Bellator 36,00 · Cipermetrina 20,00 | sin cambio |

#### E15-02 · Titular con política sin cargo por consumo

**E15-02a, titular ADMIN (`MANUAL`, H-11):** aplica el 20/10/2026 en I, en Chaco Norte, por 81,00. No se crea ningún asiento.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas | El titular no aparece (RN-41); su costo sólo se ve en «Costo por chaco» (Chaco Norte 81,00) | Tarjeta «Consumo aplicado (costo FIFO) · todas las campañas 81,00» · «1 aplicación vigente» · «Sin asientos en su cuenta.» |
| Inicio | sin efecto | sin efecto |
| Personas | «Administrador · no participa en la liquidación» | «Titular · consumo propio 81,00» |

**E15-02b, titular FAMILY con `BY_PURCHASE_ALLOCATION`:** sólo en una base histórica o de prueba; la UI no lo produce (RN-01). Compra el 05/07/2026 en I de 2 L de Glifosato asignados al titular → `PURCHASE_ALLOCATION_CHARGE` +90,00. Aplica 1 L el 20/10/2026 → costo 45,00, sin asiento.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Titular · Pendiente · todas 90,00» | Tarjeta «Consumo aplicado (costo FIFO) · todas las campañas **45,00**» · «Asientos…: cargos 90,00 · créditos por reversión 0,00 · pagos y adelantos propios 0,00» |
| Inicio | Familias por cobrar incluye 90,00 | lo excluye |
| Inventario | 1 L de Glifosato, valor 45,00 | igual (no es costo) |

#### E15-03 · Titular con aplicación revertida

**Entrada (Titular FAMILY):**
- a1: 15/10/2026, I, 81,00 → +81,00.
- 18/10/2026: se revierte a1 → `CREDIT_ADJUSTMENT` −81,00.
- a2: 20/10/2026, Glifosato 1 L → +45,00.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Titular · Cargos 126,00 · pagos/créditos 81,00 · Pendiente 45,00» | Tarjeta «Consumo aplicado (costo FIFO) · todas las campañas **45,00**» · «1 aplicación vigente · 1 revertida (81,00, no cuenta)» · «Asientos…: cargos 126,00 · créditos por reversión 81,00 · pagos y adelantos propios 0,00» |
| Inicio | Familias por cobrar incluye 45,00 | lo excluye |
| Costo por chaco | Chaco Norte 45,00 | sin cambio |

El consumo sale de las aplicaciones. Con `BY_ACTUAL_USAGE` coincide con cargos − créditos por reversión (126 − 81), pero no se calcula así.

#### E15-04 · Titular con pago propio

**Entrada (Titular FAMILY, compartido o propio):** a_t, 20/10/2026, 81,00 → +81,00. El 21/10/2026, «Registrar pago» al Titular por 81,00 → `PAYMENT` −81,00, imputado a su cargo.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas · Todas | «Titular · Cargos 81,00 · pagos/créditos 81,00 · Pendiente 0,00» | Tarjeta «Consumo aplicado (costo FIFO) · todas las campañas **81,00**» (el pago no reduce el costo) · «Asientos…: cargos 81,00 · créditos por reversión 0,00 · pagos y adelantos propios 81,00» |
| Inicio | **Pagos recibidos 81,00** · Familias 0,00 | Pagos recibidos **0,00** · Familias 0,00 |
| Movimientos propios | — | El pago aparece como «Pago · registrado en Invierno 2026 · Imputado: Invierno 2026 81,00», sin acumulado |

Si se acepta Q-2, este caso sólo puede salir de datos históricos.

#### E15-05 · Modo propio

**Entrada:** modo PROPIO, Titular FAMILY y Familiar Demo con saldo 0 (condición para pasar a propio). El Titular aplica el 20/10/2026 por 81,00 → +81,00.

| Vista | Hoy | Esperado |
|---|---|---|
| Cuentas | «Titular · Pendiente 81,00» con «Registrar pago/adelanto»; «Familiar Demo 0,00» con «Inventario propio: pagos sólo del titular» deshabilitado | Tarjeta «Consumo aplicado (costo FIFO) · todas las campañas 81,00»; lista: Familiar Demo «Saldo neto 0,00», con el mismo menú deshabilitado. Al titular no se le ofrece pago si se acepta Q-2 |
| Cuentas, base con sólo el titular | Tarjeta del titular con 81,00 | Tarjeta del titular; debajo, «En inventario propio no hay cuentas por cobrar.» |
| Inicio | Familias por cobrar 81,00 | **0,00** |
| Formulario de aplicación | «Costo propio: 81,00 Bs (queda anotado en la cuenta de Titular)» | sin cambio |

El modo propio con titular ADMIN es E15-02a.

#### E15-06 · Cambio de titular (caso declarado de Q-3)

**Entrada:** P1 (FAMILY) es titular y aplica el 10/08/2026 por 81,00 → +81,00. P2 (FAMILY) debía 20,00 por una aplicación suya del 05/08/2026. El 22/10/2026, `changeOwner` → P2 pasa a ser el titular.

| Vista | Hoy | Esperado con el vínculo vigente (propuesta) | Si se eligiera «por intervalos» |
|---|---|---|---|
| Cuentas | P1 81,00 y P2 20,00, ambos «Pendiente» | Tarjeta de P2: «Consumo aplicado (costo FIFO) · todas las campañas 20,00»; «Asientos…: cargos 20,00 · créditos por reversión 0,00 · pagos y adelantos propios 0,00». Lista: P1 neto **81,00** (deudor) | P1: 81,00 como consumo propio de un titular anterior (fuera de la lista); P2: 20,00 en la lista hasta resolverlo |
| Inicio | Familias 101,00 | Familias **81,00** | Familias **20,00** |

---

*Documento de diseño, fase 1. Verificado sobre `ed9c55c` el 2026-10-27 por lectura del código; sin ejecución de pruebas.*
