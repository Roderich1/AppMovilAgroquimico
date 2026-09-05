# 24 — Auditoría de calidad del código

Se distingue rigurosamente entre **problema objetivo** (afecta a corrección, seguridad de
tipos, mantenibilidad o rendimiento de forma demostrable) y **preferencia estilística**
(discutible, sin impacto medible). Las preferencias se listan al final y **no se
recomienda actuar sobre ellas**.

## Punto de partida: métricas objetivas

| Métrica | Valor | Valoración |
|---|---|---|
| `flutter analyze` | **0 problemas** | 🟢 Excelente |
| `dart format --set-exit-if-changed` | **0 archivos modificados** | 🟢 Excelente |
| `flutter test` | **44/44 en verde** | 🟢 Excelente |
| Líneas en `lib/` | 8 250 | — |
| Líneas en `test/` | 1 972 | Ratio 0,24 |
| Archivo mayor | `agro_repository.dart`, **1 862 líneas** | 🔴 Problema |
| Pantalla mayor | `purchase_form_screen.dart`, **772 líneas** | 🟠 Problema |
| Método mayor | `confirmApplication`, **~140 líneas** | 🟠 Problema |
| Código muerto identificado | **~400 líneas** | 🟠 Problema |
| Comentarios en `lib/` | Prácticamente ninguno | 🟡 Ver Q-08 |

---

## Problemas objetivos

### 🔴 Q-01 · Ausencia total de tipado en la capa de lectura

**El problema estructural más importante del proyecto.**

Todas las consultas devuelven `List<Map<String, Object?>>` y la UI extrae valores con
*casts* por cadena literal:

```dart
row['product_name'] as String
row['available_base'] as int
row['total_cost_bob_minor']! as int
(row['area_m2'] as int) / 10000
row['treated_area_m2'] as int? ?? 0
```

**Consecuencias medibles:**

1. **Errores de runtime, no de compilación.** Renombrar un alias en una consulta SQL
   (`AS available_base` → `AS available`) compila perfectamente y revienta al ejecutar. El
   analizador no puede ayudar.
2. **Imposible refactorizar con seguridad.** No hay forma de encontrar todos los usos de una
   columna: hay que buscar cadenas de texto.
3. **Contratos implícitos y frágiles.** `availableProductsForOwner` devuelve
   `product_id`, `product_name`, `unit`, `available_base`, `lot_count`,
   `next_fifo_cost_minor`. Ese contrato solo existe en la cadena SQL y en los casts de tres
   pantallas distintas. En `application_form_screen.dart` hay incluso un `Map` literal
   construido a mano para imitarlo cuando un producto del plan no tiene stock — evidencia
   directa de que el contrato es real pero no está expresado.
4. **`null` no controlado.** Un `LEFT JOIN` sin coincidencia produce `null` y el cast falla.
   La defensa actual es el uso disciplinado de `COALESCE(..., 0)` en SQL, que funciona pero
   es **convención, no garantía**.

**Contraste revelador**: la capa de **escritura** sí está bien tipada (`PurchaseDraft`,
`ApplicationDraft`, etc., inmutables y explícitos). La asimetría sugiere que el patrón se
conoce y simplemente no se aplicó a la lectura.

**Alcance de la corrección**: alto. Requiere ~20 clases de lectura con constructores
`fromRow`. Puede hacerse **incrementalmente**, empezando por las consultas más usadas. Ver
[30_IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md).

---

### 🔴 Q-02 · `AgroRepository` viola responsabilidad única a gran escala

1 862 líneas y ~60 métodos públicos que abarcan **seis responsabilidades distintas**:

| Responsabilidad | Métodos representativos |
|---|---|
| CRUD de catálogos | `addPerson`, `addFarm`, `addProduct`, `addSupplier`, `renameCatalog`, `archiveCatalog` |
| Ciclo de vida de campañas | `addCampaign`, `activateCampaign`, `closeCampaign`, `campaignCloseSummary` |
| Motor de compras | `confirmPurchase`, `addProviderPayment`, `reversePurchase` |
| Motor de inventario y FIFO | `confirmApplication`, `transferProductsFifo`, `estimateFifoCost`, `reverseApplication`, `reverseTransfer` |
| Motor contable | `addAccountPayment`, `settlements`, `statement`, `detailedStatement`, `personCampaignBalance` |
| Capa de reportes | `dashboard`, `farmCostReport`, `productCostReport`, `inventorySummary`, `personProfiles`, … |
| Sistema de archivos | `exportBackup`, `storeInvoiceImage` |

**Consecuencias**:
- Es el archivo que toca **cualquier** cambio funcional: máximo riesgo de conflicto y de
  regresión.
- Imposible razonar sobre una parte sin cargar el resto.
- La lógica de negocio no se puede probar sin base de datos (aunque el proyecto lo resuelve
  bien con SQLite en memoria).

**División natural evidente** (los grupos ya están agrupados físicamente en el archivo):
`CatalogRepository`, `CampaignService`, `PurchaseService`, `InventoryService`,
`AccountingService`, `ReportRepository`, `BackupService`.

**Riesgo de la corrección**: medio-alto. Es una refactorización amplia, pero la suite de 44
tests cubre bien el comportamiento de los tres motores críticos, lo que la hace viable.

---

### 🟠 Q-03 · Código muerto: ~400 líneas

| Elemento | Ubicación | Líneas | Verificación |
|---|---|---:|---|
| `_PurchaseDialog` + `_PurchaseDialogState` + `_AllocationInput` + `_select` | `purchases_screen.dart` | **~350** | Cero referencias en `lib/` y `test/`. Sustituido por `PurchaseFormScreen` |
| `transferProductFifoV3Legacy` | `agro_repository.dart` | ~110 | `@Deprecated`; cero llamadas |
| `transferStockLegacy` | `agro_repository.dart` | ~73 | `@Deprecated`; cero llamadas |
| `_farmOwner` | `application_form_screen.dart` | 4 | **Siempre devuelve `null`** (ver Q-04) |
| Parámetro `people` de `_confirm` | `purchase_form_screen.dart` | — | Recibido y nunca usado |
| Columna `price_major_unit` | `app_database.dart` | — | Declarada; nunca escrita ni leída |
| Tabla `app_settings` | `app_database.dart` | — | Creada; nunca usada. Ni siquiera se crea en las migraciones |
| Columna `application_items.notes` | `app_database.dart` | — | Añadida en v4; nunca usada |
| Estado `ARCHIVED` de campaña | `agro_repository.dart` | — | Se comprueba; nunca se escribe |
| Estado `DRAFT` de plan | `app_database.dart` | — | Valor por defecto de la columna; ninguna ruta lo escribe |

El caso de `_PurchaseDialog` es especialmente costoso: **infla `purchases_screen.dart` de
~300 a 658 líneas**, haciéndolo parecer la segunda pantalla más compleja cuando en realidad
es de complejidad media.

---

### 🟠 Q-04 · Método que siempre devuelve `null` usado en una condición

**Ubicación**: `lib/presentation/screens/application_form_screen.dart`

```dart
int? _farmOwner(int? id) {
  if (id == null) return null;
  return null;              // ← única salida posible
}
```

Se usa en:

```dart
if (_farmOwner(farmId) != id) farmId = null;
```

Como `_farmOwner` devuelve siempre `null`, la condición es `null != id`, que es verdadera
para cualquier `id` no nulo. El efecto neto —limpiar el chaco al cambiar de persona— **es el
deseado**, así que no hay bug observable. Pero el código:

- sugiere una intención (comprobar el propietario del chaco) que **no implementa**;
- es una trampa para quien lo lea: parece condicional y no lo es;
- probablemente es un TODO abandonado.

**Clasificación**: problema objetivo de mantenibilidad, no defecto funcional.

---

### 🟠 Q-05 · Métodos demasiado largos

| Método | Archivo | Líneas aprox. | Responsabilidades mezcladas |
|---|---|---:|---|
| `confirmApplication` | `agro_repository.dart` | ~140 | Validar, consultar lotes, insertar aplicación e ítems, ejecutar FIFO, insertar consumos y movimientos, calcular costes, generar cargo, actualizar el plan |
| `transferProductsFifo` | `agro_repository.dart` | ~135 | Validar, recorrer productos, ejecutar FIFO, crear lotes destino, insertar movimientos y trazabilidad, acumular costes |
| `confirmPurchase` | `agro_repository.dart` | ~140 | Validar, calcular totales, insertar compra, ítems, asignaciones, lotes, movimientos y cargos |
| `reversePurchase` | `agro_repository.dart` | ~92 | Verificar guardias, revertir lotes, revertir cargos, revertir pagos |
| `build` de `PurchaseFormScreen` | `purchase_form_screen.dart` | ~200 | Toda la estructura de la pantalla en un solo árbol |
| `build` de `_LineCard` | `purchase_form_screen.dart` | ~180 | Producto, cantidad, moneda, precio, FX, subtotales y asignaciones |
| `build` de `DashboardScreen` | `dashboard_screen.dart` | ~230 | Banner, tarjetas, tabla, dos listas |

Los tres primeros son **transacciones**, y mantenerlas juntas tiene una justificación real
(la atomicidad se lee mejor en un solo bloque). Aun así, la parte de FIFO es idéntica en
`confirmApplication` y `transferProductsFifo` y podría extraerse (ver Q-06).

---

### 🟠 Q-06 · Duplicación real

#### El bucle FIFO, tres veces

El patrón "recorrer lotes ordenados, tomar `min(pendiente, disponible)`, acumular coste"
aparece en **cuatro** lugares con variaciones mínimas:

1. `confirmApplication` — consume y registra `application_consumptions`
2. `transferProductsFifo` — consume y crea lotes destino
3. `transferProductFifoV3Legacy` — idéntico al anterior (código muerto)
4. `estimateFifoCost` — solo calcula, no escribe

Los tres primeros comparten además **la misma consulta SQL de lotes disponibles**, escrita
tres veces con diferencias cosméticas (`JOIN` vs `LEFT JOIN`, `COALESCE` en distinto sitio).

**Riesgo concreto**: un cambio en la política de costeo (por ejemplo, pasar a coste
promedio) exige modificar cuatro sitios y es fácil olvidar uno.

#### Otras duplicaciones

| Duplicación | Ubicaciones |
|---|---|
| Diálogo "¿Descartar cambios?" | 4 formularios, texto casi idéntico |
| Bloque `dirty`/`saving` + `PopScope` + `addPostFrameCallback` | 4 formularios |
| Traducción de rol a etiqueta (`'FAMILY' → 'Familiar'`) | `persons_screen`, `person_detail_screen`, `catalogs_screen`, `transfer_form_screen` — **4 implementaciones separadas** |
| `(x as int) / 10000` para mostrar hectáreas | 8 ocurrencias, sin helper compartido (contrasta con `formatBob`/`formatQuantity`, que sí están centralizados) |
| Consulta de saldo `SUM(amount_bob_minor_signed)` | `settlements`, `topSettlements`, `personProfiles`, `personProfile`, `personCampaignBalance` |

La de las hectáreas es la más llamativa: existe una capa de formateo (`money.dart`) y **no
se le añadió `formatHectares`**, dejando divisiones crudas en las pantallas que además
producen salidas inconsistentes (ver Q-09).

---

### 🟠 Q-07 · `Future` creado dentro de `build()`

Cuatro pantallas relanzan sus consultas en cada reconstrucción:

| Pantalla | Consultas por reconstrucción |
|---|---:|
| `PersonDetailScreen` | **5** |
| `InventoryDetailScreen` | **3** |
| `FarmLogbookScreen` | 2 |
| `PersonsScreen` | 1 |

Es un antipatrón conocido de Flutter. Contrasta con las otras nueve pantallas, que sí lo
hacen bien (`late Future` en `initState`) e incluso tienen un test de regresión que protege
el patrón correcto. Detalle en [25_PERFORMANCE_AUDIT](25_PERFORMANCE_AUDIT.md).

---

### 🟡 Q-08 · Ausencia casi total de comentarios y documentación

En 8 250 líneas de `lib/` hay **dos** comentarios sustantivos (los `@Deprecated`). No hay
ni un solo comentario de documentación `///`.

Esto duele especialmente en:

- **`money.dart`**: las fórmulas de conversión son correctas pero no evidentes. `subtotalMinor`
  divide entre `baseUnitsPerMajor * fxScale` sin explicar por qué.
- **Las consultas SQL largas**: `inventorySummary` tiene 20 líneas con subconsultas
  correlacionadas repetidas y ninguna explicación de qué significa "comprometido".
- **Las reglas de negocio**: por qué un familiar no genera deuda al comprar es la decisión
  central del producto, y no está escrita en ninguna parte del código.
- **Los contratos implícitos** de Q-01.

**Atenuante importante**: los **nombres de tests** cumplen parcialmente esta función
(*"asignación familiar no crea deuda; uso y pago parcial sí"*). Y ahora existe esta carpeta
`docs/`. Aun así, un `///` sobre `confirmPurchase` explicando RN-10 tendría un valor
desproporcionado respecto a su coste.

---

### 🟡 Q-09 · Formateo inconsistente de superficies

```dart
'${(row['area_m2'] as int) / 10000} ha'
```

Ocho ocurrencias. Al ser división de coma flotante sin formatear, produce salidas como
`28.0 ha` o, con valores no redondos, `2.8000000000000003 ha`.

Contrasta con el resto del proyecto, que formatea con rigor mediante `formatBob` y
`formatQuantity` (ambos con `NumberFormat` y locale `es_BO`).

`PlanFormScreen` y `ApplicationFormScreen` sí lo hacen bien al **precargar** el campo:

```dart
hectares.toStringAsFixed(hectares == hectares.truncateToDouble() ? 0 : 2)
```

...pero esa lógica está duplicada en dos sitios y no se usa al **mostrar**.

**Corrección**: añadir `formatHectares(int areaM2)` a `money.dart` y usarlo en los ocho
sitios. Coste trivial, impacto visible para el usuario.

---

### 🟡 Q-10 · Enums unidireccionales

```dart
extension EnumCode on Enum {
  String get code => name.replaceAllMapped(RegExp(r'([A-Z])'),
      (m) => '_${m.group(1)}').toUpperCase();
}
```

Convierte `camelCase → SCREAMING_SNAKE` para escribir. **No existe la conversión inversa.**

Al leer, el código compara cadenas literales por todas partes:

```dart
person['role'] == 'ADMIN'
row['status'] == 'ACTIVE'
policy == 'BY_ACTUAL_USAGE'
policy == 'BY_PURCHASE_ALLOCATION'
```

Estas cadenas están repartidas por el repositorio y por seis pantallas. Un cambio en un
valor de enum exige encontrarlas todas a mano.

Además, `EnumCode` está declarada sobre `Enum` (todos los enums), no sobre los cuatro del
dominio, lo que la hace más amplia de lo necesario.

---

### 🟡 Q-11 · Tipos de retorno ilegibles

```dart
late Future<(List<Map<String, Object?>>, List<Map<String, Object?>>,
             List<Map<String, Object?>>, List<Map<String, Object?>>)> data;
```

En `settlements_screen.dart`, esta firma de 8 líneas aparece **dos veces** (declaración del
campo y firma de `_load`). Los cuatro elementos son posicionales: `snapshot.data!.$1` no
dice nada sobre qué contiene.

El resto del proyecto usa **records con nombre** correctamente (`_DashboardData`,
`_PersonData`, `_InventoryDetail`, …). Esta es la excepción, y se nota.

---

### 🟡 Q-12 · Desnormalización engañosa en `transfers`

`transfers.product_id` y `transfers.quantity_base` se rellenan con `validItems.first`. En
una transferencia de tres productos, la cabecera describe **solo el primero**.

La consulta `transfers()` lo compensa con un `COALESCE` que prefiere el `GROUP_CONCAT` de
`transfer_items`, pero cualquier consulta nueva que use `transfers.product_id` directamente
obtendrá un dato incorrecto.

Es deuda de la versión mono-producto que no se limpió al añadir `transfer_items` en v4.

---

### 🟡 Q-13 · Condicional muerto en SQL

`inventorySummary`:

```sql
COALESCE(SUM(CASE WHEN m.quantity_signed > 0
                  THEN m.quantity_signed * l.unit_cost_bob_minor_per_major_unit
                  ELSE m.quantity_signed * l.unit_cost_bob_minor_per_major_unit
             END) / 1000, 0) available_value_bob_minor
```

**Las dos ramas del `CASE` son idénticas.** Equivale a
`SUM(m.quantity_signed * l.unit_cost...)`.

Dos observaciones:
1. El condicional sugiere que en algún momento se pretendió tratar entradas y salidas de
   forma distinta, y quedó a medias.
2. La división `/1000` es **entera** (truncamiento), a diferencia de todo el resto del
   proyecto, que usa `divideRoundedHalfUp` (redondeo mitad arriba). Es una inconsistencia
   real en el cálculo del valor de inventario mostrado en el dashboard y en `/inventario`.

---

## Aspectos de calidad claramente buenos

Es importante registrarlos: este proyecto hace varias cosas mejor que la media.

| Aspecto | Evidencia |
|---|---|
| **Aritmética monetaria** | Enteros en todo el sistema, redondeo mitad arriba único y centralizado. Cero `double` en cálculos de dinero. Ejemplar |
| **Uso de transacciones** | Todas las escrituras compuestas están dentro de `db.transaction`. Rollback verificado por tres tests |
| **Parametrización SQL** | 100 % de los valores van por `?`. Ni una interpolación |
| **`PRAGMA foreign_keys = ON`** | Activado explícitamente; SQLite lo desactiva por defecto |
| **Gestión de `TextEditingController`** | `dispose()` correcto en los 5 editores; sin fugas detectadas |
| **Guardas de `mounted`** | `if (!mounted) return;` sistemático tras cada `await`, antes de `setState` y `showError` |
| **Guardas contra carreras** | `if (fromId != id) return;`, `if (q == tryParseBase(...))` — protecciones reales contra respuestas obsoletas |
| **Parseo tolerante** | `tryParse*` nunca lanza; acepta coma decimal. Con test de regresión |
| **Mensajes de error** | Específicos, en español, orientados a la acción. Ver [16](16_VALIDATIONS.md) |
| **Nombres de columna** | Sufijos semánticos rigurosos (`_base`, `_minor`, `_scaled`, `_m2`, `_signed`) aplicados sin excepción |
| **Contabilidad inmutable** | Nunca se hace `UPDATE`/`DELETE` de asientos; se compensa. Diseño correcto |
| **Importaciones selectivas** | `import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor, Sqflite;` |
| **`const` generalizado** | Uso amplio y correcto de constructores constantes |
| **Excepción tipada con datos** | `CampaignConflictException` lleva `activeCampaignId`/`activeCampaignName`, permitiendo a la UI ofrecer una salida |
| **Diseño adaptativo** | `LayoutBuilder`/`MediaQuery` en 9 pantallas, con tests en 5 resoluciones |

---

## Preferencias estilísticas — NO se recomienda actuar

Estas observaciones son **discutibles y sin impacto medible**. Se listan para dejar claro
que se consideraron y se descartaron deliberadamente.

| Observación | Por qué NO es un problema |
|---|---|
| `if` sin llaves (`if (x) return y;`) | Desactivado a propósito en `analysis_options.yaml`. Es una elección consciente y **consistente** en todo el proyecto |
| Cuerpos de expresión (`=>`) en `build` largos | Idiomático en Dart moderno; el propio equipo de Flutter lo usa |
| Nombres de variable cortos (`s`, `d`, `c`, `l`, `p`) en algunas pantallas | Ámbito muy corto (dentro de un `builder`); legible en contexto |
| Todo en español | **Correcto y deseable**: el dominio, los usuarios y el equipo son hispanohablantes. Mezclar idiomas sería peor |
| Clases privadas de UI en el mismo archivo | Idiomático en Flutter para widgets no reutilizables |
| Ausencia de `part`/`part of` | Preferencia; el proyecto es pequeño |
| Cadenas literales de SQL multilínea con `'''` | Legible y adecuado |
| Uso de records posicionales en diálogos (`(int, int)`) | Ámbito local y corto; aceptable (distinto del caso Q-11, que es un campo de clase) |

---

## Resumen de problemas objetivos

| ID | Problema | Impacto | Esfuerzo |
|---|---|---|---|
| Q-01 | Sin tipado en la capa de lectura | **Alto** | Alto |
| Q-02 | Repositorio monolítico (1 862 líneas) | **Alto** | Alto |
| Q-03 | ~400 líneas de código muerto | Medio | **Bajo** |
| Q-04 | `_farmOwner` siempre devuelve `null` | Bajo | **Trivial** |
| Q-05 | Métodos y `build` demasiado largos | Medio | Medio |
| Q-06 | Bucle FIFO duplicado 4 veces | **Alto** | Medio |
| Q-07 | `Future` en `build()` en 4 pantallas | Medio | **Bajo** |
| Q-08 | Sin comentarios ni documentación de código | Medio | Bajo |
| Q-09 | Formateo inconsistente de hectáreas | Bajo | **Trivial** |
| Q-10 | Enums sin conversión inversa | Medio | Bajo |
| Q-11 | Tipo de retorno ilegible en `SettlementsScreen` | Bajo | **Trivial** |
| Q-12 | Desnormalización engañosa en `transfers` | Medio | Medio |
| Q-13 | `CASE` muerto y división truncada en `inventorySummary` | Medio | **Trivial** |
