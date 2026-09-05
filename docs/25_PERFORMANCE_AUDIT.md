# 25 — Auditoría de rendimiento

> Análisis estático. **No se aplicó ninguna optimización.** No se ejecutó *profiling* en
> dispositivo real; donde eso limita las conclusiones, se indica explícitamente.

## Contexto: escala esperada

Antes de valorar nada, hay que dimensionar el problema. Este es un producto para **una
familia**: un puñado de personas, decenas de productos, unas cuantas campañas al año.

`volume_test.dart` establece la escala que el propio proyecto considera representativa:

| Entidad | Volumen del test |
|---|---:|
| Productos | 100 |
| Aplicaciones | 1 000 |
| Compras | 300 |

A esa escala, **SQLite es holgadamente suficiente** y la mayoría de los hallazgos siguientes
tienen impacto imperceptible. Se documentan porque algunos escalan mal y porque uno de ellos
(P-01) sí es perceptible hoy.

---

## Hallazgos

### 🔴 P-01 · `Future` creado dentro de `build()` — el problema real

**Ubicación**: `PersonsScreen`, `PersonDetailScreen`, `InventoryDetailScreen`,
`FarmLogbookScreen`.

```dart
class PersonDetailScreen extends ConsumerWidget {
  Future<_PersonData> _load(WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    return (
      profile:      await repo.personProfile(personId),
      farms:        await repo.farmsForPerson(personId),
      applications: await repo.applications(personId: personId),
      stock:        await repo.personStockSummary(personId),
      statement:    await repo.detailedStatement(personId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<_PersonData>(future: _load(ref), builder: ...);  // ⚠️
}
```

**Qué ocurre**: `build()` se ejecuta muchas veces (rotación, aparición del teclado, cambios
de `MediaQuery`, reconstrucciones del padre). Cada una crea un `Future` nuevo, lo que:

1. Relanza **todas** las consultas.
2. Devuelve `snapshot.hasData == false` → la pantalla **parpadea al spinner** y pierde la
   posición de scroll.

| Pantalla | Consultas por reconstrucción |
|---|---:|
| `PersonDetailScreen` | **5** |
| `InventoryDetailScreen` | **3** |
| `FarmLogbookScreen` | 2 |
| `PersonsScreen` | 1 |

**Impacto**: es el hallazgo con **efecto visible para el usuario hoy**, no una preocupación
teórica. En `PersonDetailScreen`, cambiar de pestaña dentro del `DefaultTabController` o
girar el dispositivo dispara 5 consultas y un parpadeo.

**Agravante**: `detailedStatement` y `applications` son de las consultas más pesadas del
repositorio.

**Corrección**: convertir a `ConsumerStatefulWidget` con `late Future` en `initState`, como
ya hacen correctamente las otras nueve pantallas. Esfuerzo bajo, patrón ya presente en el
proyecto (e incluso protegido por un test de regresión).

---

### 🟠 P-02 · Consultas secuenciales donde podrían ser paralelas

`_load` de `DashboardScreen` y `PersonDetailScreen` encadena `await`:

```dart
return (
  summary:      await repo.dashboard(),          // espera
  inventory:    await repo.inventorySummary(5),  // luego espera
  applications: await repo.applications(5),      // luego espera
  debts:        await repo.topSettlements(5),    // luego espera
  campaigns:    await repo.campaigns(),          // luego espera
);
```

`dashboard()` es a su vez **seis consultas escalares secuenciales** internamente. El
dashboard hace por tanto ~10 idas y venidas a SQLite en serie.

**Contraste**: `CatalogsScreen._load` y `PurchaseFormScreen._loadCatalogs` **sí** usan
`Future.wait`, es decir, el patrón correcto ya se conoce.

**Impacto real**: bajo con SQLite local (cada consulta son microsegundos). Sería
significativo si alguna vez hubiera red. Se registra como inconsistencia más que como
problema urgente.

---

### 🟠 P-03 · El stock siempre se calcula agregando la tabla de movimientos

Ninguna tabla guarda un saldo. **Toda** consulta de stock hace
`SUM(inventory_movements.quantity_signed)` con `GROUP BY`.

```sql
SELECT l.*, COALESCE(SUM(m.quantity_signed), 0) AS available
FROM inventory_lots l JOIN inventory_movements m ON m.lot_id = l.id
WHERE l.product_id = ? AND l.owner_person_id = ? AND l.reversed_at IS NULL
GROUP BY l.id HAVING available > 0 ORDER BY l.acquired_date, l.id
```

Esta consulta (o una variante) se ejecuta en `confirmApplication`, `transferProductsFifo`,
`estimateFifoCost`, `availableProductsForOwner`, `productStockInsight`,
`inventoryProductLots`, `stock`, `personStockSummary`, `inventorySummary`…

**Es la decisión de diseño correcta** (trazabilidad total, sin riesgo de desincronización
entre saldo y movimientos), y está bien soportada por `idx_lots_fifo` y `idx_movements_lot`.

**Cuándo dejaría de serlo**: `inventory_movements` crece con **cada** operación. Una compra
de 3 productos con 2 asignaciones cada uno genera 6 filas; una aplicación que toca 3 lotes,
3 filas; una transferencia, 2 filas por lote tocado. A ritmo familiar son miles de filas al
año — perfectamente manejable. Con decenas de miles convendría una tabla de saldos
materializados o una vista.

**Veredicto**: correcto hoy, con un umbral conocido.

---

### 🟠 P-04 · Consultas O(N) dentro de bucles

En `confirmPurchase`, dentro del bucle de asignaciones:

```dart
for (final allocation in item.allocations) {
  final person = (await txn.query('persons',
      where: 'id = ?', whereArgs: [allocation.personId], limit: 1)).single;
  final policy = person['settlement_policy']! as String;
  ...
}
```

Una consulta **por asignación**, para leer un dato que casi siempre se repite. Con 12 líneas
× 2 asignaciones = 24 consultas puntuales, muchas de ellas a la misma persona.

Es el patrón N+1 clásico. Se resolvería precargando las personas implicadas antes del bucle.

Ocurre lo mismo en `confirmApplication`, que consulta `products` (para leer `unit`) una vez
por línea.

**Impacto real**: bajo — son consultas por clave primaria dentro de una transacción, y el
número de líneas por factura es pequeño. Se registra por corrección técnica.

---

### 🟠 P-05 · Subconsultas correlacionadas repetidas en consultas de reporte

`inventorySummary` calcula **la misma subconsulta dos veces**:

```sql
COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
  JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
  WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0)
  committed_base,

COALESCE(SUM(m.quantity_signed),0) - COALESCE((SELECT SUM(pi.required_quantity_base)
  FROM application_plan_items pi JOIN application_plans ap ON ap.id=pi.plan_id
  JOIN campaigns c ON c.id=ap.campaign_id WHERE pi.product_id=p.id
  AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) projected_base
```

La segunda es literalmente la primera repetida. Se ejecuta **una vez por producto** en el
`GROUP BY`, y como el `LEFT JOIN` recorre `inventory_movements` completa, el coste se
multiplica.

Se resolvería con una CTE (`WITH committed AS (...)`) o calculando `projected` en Dart, que
ya tiene ambos valores.

`personProfiles` tiene un caso más raro: una subconsulta escalar con `GROUP BY ... HAVING`
dentro, para contar productos con stock.

**Impacto**: medio en el dashboard y en `/inventario`, que son las pantallas más visitadas.
No medido en dispositivo real.

---

### 🟡 P-06 · Filtrado y ordenación en cliente sobre listas completas

| Pantalla | Patrón |
|---|---|
| `ApplicationsScreen` | Trae 200 filas y filtra con `'$row'.toLowerCase().contains(query)` — **serializa el `Map` completo a texto** en cada tecla |
| `PurchasesScreen` | Trae 200 filas, filtra en memoria |
| `PlanningScreen` | Trae 400 filas y las **agrupa en Dart** con un `Map` |
| `InventoryScreen` | Trae todas y filtra en memoria |
| `CatalogsScreen` | `row.values.any((v) => v.toString().toLowerCase().contains(query))` sobre todas las filas |
| `DashboardScreen` | Filtra 5 filas (irrelevante) |
| `SettlementsScreen` | Filtra en memoria |
| `TransferFormScreen` | Filtra en memoria |
| `DashboardScreen` | `data.debts.toList()..sort(...)` — **ordena en cada `build`** una lista que ya viene ordenada por SQL (`ORDER BY balance DESC`) |

El caso de `ApplicationsScreen` es el peor: `'$row'` construye una cadena con **todo** el
mapa (incluidos ids, timestamps ISO y sumas) en cada pulsación de tecla, para 200 filas.
Además hace que la búsqueda encuentre coincidencias absurdas (buscar "2026" devuelve todo).

**Impacto**: bajo a la escala actual; degradación perceptible si las listas crecen. Se
registra sobre todo por el efecto colateral en la **calidad de la búsqueda**, no solo por
rendimiento.

---

### 🟡 P-07 · Listas sin virtualización

Varias pantallas construyen **todos** sus hijos por adelantado:

```dart
Card(child: Column(children: [ for (final row in rows) ListTile(...) ]))
```

Presente en `PersonsScreen`, `InventoryScreen`, `InventoryDetailScreen` (distribución y
lotes), `PersonDetailScreen` (`_Section`), `FarmLogbookScreen`, `CatalogsScreen` (en la
sección de campañas), `SettlementsScreen` (personas, costos por chaco, costos por producto)
y `DashboardScreen`.

Otras sí usan `ListView.separated`/`ListView.builder`, pero con
`shrinkWrap: true` + `NeverScrollableScrollPhysics`, lo que **anula la virtualización**:
construye todos los elementos igualmente.

**Escala que lo hace relevante**: `inventoryProductLots` tiene `LIMIT 500`. Quinientos
`ExpansionTile` construidos de golpe en `InventoryDetailScreen` sí sería perceptible en un
dispositivo modesto.

**Atenuante**: el proyecto tiene tests de responsive en 5 resoluciones y ninguno detecta
desbordamientos, así que el problema es de rendimiento, no de layout.

---

### 🟡 P-08 · Alturas fijas en contenedores de contenido variable

```dart
SizedBox(height: 520, child: FutureBuilder(...))   // CatalogsScreen
SizedBox(height: 480, child: TabBarView(...))      // PersonDetailScreen
SizedBox(width: 620, height: 420, ...)             // diálogo de estado de cuenta
```

No es un problema de rendimiento sino de adaptabilidad: en una pantalla apaisada corta,
520 px puede no caber; en una tableta, sobra espacio.

Los tests de responsive incluyen un caso apaisado (800×420) y no detectan desbordamiento,
probablemente porque el contenido va dentro de un scroll. Aun así, es una restricción
arbitraria.

---

### 🟡 P-09 · Estimación FIFO en cada pulsación de tecla

`ApplicationFormScreen`:

```dart
TextField(
  controller: line.real,
  onChanged: (_) { setState(() => dirty = true); estimate(line); },  // ← consulta por tecla
  ...
)
```

Y al editar el área:

```dart
onChanged: (_) {
  setState(() => dirty = true);
  for (final line in lines) { estimate(line); }   // ← N consultas por tecla
}
```

Con 5 productos en la mezcla, cada dígito tecleado en el área lanza **5 consultas** de
`estimateFifoCost`.

**Mitigación ya presente**: hay una guarda anti-carrera correcta que descarta resultados
obsoletos:

```dart
if (mounted && q == (tryParseBase(line.real.text) ?? 0)) setState(() => line.cost = cost);
```

**Lo que falta**: un *debounce*. Es el caso más claro del proyecto donde 200–300 ms de
retardo eliminarían la mayoría de las consultas sin que el usuario notara diferencia.

---

### 🟡 P-10 · Imágenes cargadas sin caché ni redimensionado

```dart
Image.file(File(invoiceImage!.path), width: 48, height: 48, fit: BoxFit.cover)   // miniatura
Image.file(file, fit: BoxFit.contain)                                            // visor
```

`Image.file` **decodifica la imagen completa en memoria** aunque se muestre a 48×48. Con
fotos de hasta 1800 px de ancho, la miniatura del formulario decodifica varios megabytes.

**Corrección estándar**: `cacheWidth`/`cacheHeight` en el constructor.

**Atenuante**: `image_picker` ya limita a `maxWidth: 1800` y `imageQuality: 82`, y solo hay
una imagen a la vez.

---

### 🟢 P-11 · Aspectos de rendimiento bien resueltos

| Aspecto | Detalle |
|---|---|
| **Índices** | 15 índices bien elegidos. `idx_lots_fifo (product_id, owner_person_id, acquired_date, id)` cubre exactamente el `WHERE` + `ORDER BY` del bucle FIFO — es el índice correcto |
| **Índice único parcial** | `idx_campaign_single_active` impone la invariante sin coste de consulta |
| **`LIMIT` en todas las consultas de lista** | 50 (transferencias), 200 (compras, aplicaciones), 400 (planes), 500 (lotes). Nada es ilimitado excepto `inventorySummary` sin argumento |
| **Transacciones** | Todas las escrituras compuestas van en una sola transacción: un solo `fsync` en lugar de N |
| **Agregación en SQL, no en Dart** | `GROUP_CONCAT`, `SUM`, `COUNT`, `COALESCE` hacen el trabajo en el motor |
| **Test de volumen** | `volume_test.dart` usa `batch()` para insertar 1 400 filas y verifica que las consultas siguen acotadas |
| **Guardas anti-carrera** | Evitan trabajo inútil y estados inconsistentes tras respuestas obsoletas |
| **`const` generalizado** | Reduce reconstrucciones innecesarias de widgets |
| **Aritmética entera** | Más rápida y exacta que coma flotante |

---

## Fugas de memoria y ciclo de vida

Revisión específica, **sin hallazgos**:

| Recurso | Estado |
|---|---|
| `TextEditingController` | ✅ `dispose()` correcto en los 5 editores (`_PurchaseLineEditor`, `_AllocationEditor`, `_ApplicationLineEditor`, `_PlanLine`, y el `Map` de `TransferFormScreen`). El de `TransferFormScreen` incluso libera los antiguos al cambiar de origen |
| `TabController` | ✅ `CatalogsScreen` hace `removeListener` **y** `dispose()` |
| `AnimationController` | ⬜ Ninguno |
| `StreamSubscription` | ⬜ Ninguna: no hay streams en el proyecto |
| `Timer` | ⬜ Ninguno |
| Conexión SQLite | ✅ `ref.onDispose(database.close)` |
| `addPostFrameCallback` | ✅ Todos comprueban `mounted` antes de actuar |
| Diálogos | ✅ Test de regresión dedicado: *"estado de cuenta abre y cierra 20 veces sin perder la pantalla"* |

**La gestión de recursos es correcta.** No se detectó ninguna fuga.

---

## Arranque

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AgroApp()));
}
```

Arranque mínimo: no hay inicializaciones bloqueantes. La base de datos se abre de forma
**perezosa** con la primera consulta del dashboard.

**Efecto secundario a tener en cuenta**: las migraciones `onUpgrade` se ejecutan en ese
primer acceso, dentro del `FutureBuilder` del dashboard. En una actualización con muchos
datos, el usuario vería el spinner del dashboard durante la migración, **sin ninguna
indicación de qué está pasando**. No es un problema hoy (las migraciones son ligeras), pero
conviene saberlo antes de escribir una migración pesada.

---

## Riesgo específico: enteros en Web

`subtotalMinor` multiplica tres enteros antes de dividir:

```dart
final numerator = quantityBase * unitPriceMinor * (fxScaled ?? fxScale);
```

Con 420 000 × 1 600 × 7 000 000 ≈ **4,7 × 10¹⁵**.

- En VM nativa (`int` de 64 bits, límite ~9,2 × 10¹⁸): **correcto**.
- En Flutter Web (`int` es `double` de 53 bits, límite ~9 × 10¹⁵): **al borde de perder
  precisión**. Una compra un orden de magnitud mayor daría resultados incorrectos.

Hoy es inofensivo porque la app no funciona en web por otras razones
([13_LOCAL_STORAGE](13_LOCAL_STORAGE.md)). Debe recordarse si alguna vez se plantea la
plataforma web.

---

## Resumen priorizado

| ID | Hallazgo | Impacto hoy | Escala mal | Esfuerzo |
|---|---|---|:--:|---|
| P-01 | `Future` en `build()` (4 pantallas) | **Visible** | Sí | **Bajo** |
| P-09 | Estimación FIFO sin *debounce* | Medio | Sí | **Bajo** |
| P-05 | Subconsulta duplicada en `inventorySummary` | Medio | Sí | **Bajo** |
| P-06 | Búsqueda con `'$row'` en `ApplicationsScreen` | Bajo | Sí | **Bajo** |
| P-07 | Listas sin virtualización | Bajo | Sí | Medio |
| P-10 | Imágenes sin `cacheWidth` | Bajo | No | **Trivial** |
| P-02 | Consultas secuenciales | Bajo | No | Bajo |
| P-04 | N+1 en bucles de transacción | Bajo | Leve | Bajo |
| P-03 | Stock agregado siempre | Ninguno hoy | Sí, con umbral alto | Alto |
| P-08 | Alturas fijas | Ninguno (adaptabilidad) | No | Bajo |

**Conclusión**: el único hallazgo con efecto perceptible para el usuario hoy es **P-01**, y
su corrección es de esfuerzo bajo con un patrón que el propio proyecto ya aplica bien en
nueve pantallas. El resto son mejoras de higiene o preparación para escalas que este
producto probablemente nunca alcance.
