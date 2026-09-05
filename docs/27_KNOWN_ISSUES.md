# 27 — Defectos conocidos

> **Actualizado tras la fase de estabilización (2026-09-05).** Los defectos
> corregidos se marcan ✅ CORREGIDO con su test de regresión. El detalle de cada
> corrección está en [33_STABILIZATION_FINDINGS](33_STABILIZATION_FINDINGS.md) y
> la trazabilidad completa en [34_CHANGE_TRACEABILITY](34_CHANGE_TRACEABILITY.md).

Defectos concretos y observables encontrados durante la auditoría. Cada uno indica su
**nivel de confirmación**:

- **CONFIRMADO** — reproducido durante esta auditoría, con evidencia adjunta.
- **VERIFICADO EN CÓDIGO** — la lectura del código lo demuestra sin ambigüedad.
- **PROBABLE** — la lectura lo sugiere fuertemente, pero no se reprodujo.

Ningún defecto fue corregido: esta fase es solo de inspección.

---

## ✅ KI-01 · Volver atrás desde "Nueva compra" rompe la aplicación — CORREGIDO

**Estado: CONFIRMADO — reproducido durante esta auditoría.**

### Reproducción

1. Abrir la app.
2. Pulsar el FAB **"Nuevo"**.
3. Elegir **"Compra"**.
4. En el formulario, pulsar el botón atrás (o el gesto de retroceso del sistema).

### Resultado observado

Se lanza una aserción de go_router y **la pantalla queda en blanco**: ni el formulario ni el
inicio están en el árbol de widgets.

```
EXCEPTION CAUGHT BY SCHEDULER LIBRARY
The following assertion was thrown during a scheduler callback:
You have popped the last page off of the stack, there are no pages left to show
'package:go_router/src/delegate.dart':
Failed assertion: line 178 pos 7: 'currentConfiguration.isNotEmpty'

#2  GoRouterDelegate._debugAssertMatchListNotEmpty (delegate.dart:178:7)
#3  GoRouterDelegate._completeRouteMatch (delegate.dart:199:5)
#4  GoRouterDelegate._handlePopPageWithRouteMatch (delegate.dart:153:7)
#5  _CustomNavigatorState._handlePopPage (builder.dart:437:42)
#6  NavigatorState.pop (navigator.dart:5654:28)
#7  _PurchaseFormScreenState._close.<anonymous closure>
    (package:agroquimicos/presentation/screens/purchase_form_screen.dart:110:42)
```

### Causa raíz

`AppShell._newButton` navega con **`context.go('/compras/nueva')`**. Como `/compras/nueva`
está declarada **fuera del `ShellRoute`** (`lib/app.dart`), `go` **reemplaza toda la pila**
por esa única ruta. Cuando `PurchaseFormScreen._close()` ejecuta
`Navigator.of(context).pop()`, no queda ninguna página debajo.

### Rutas afectadas

| Origen | Método | ¿Falla? |
|---|---|:--:|
| FAB "Nuevo" → "Compra" (`app_shell.dart`) | `context.go('/compras/nueva')` | ✅ **Sí** |
| Operaciones → "Registrar compra" (`operations_screen.dart`) | `context.go('/compras/nueva')` | ✅ **Sí** |
| `/compras` → "Nueva compra" (`purchases_screen.dart`) | `context.push('/compras/nueva')` | ❌ No |

Los otros tres formularios (`/planificacion/nueva`, `/aplicaciones/nueva`,
`/transferencias/nueva`) **solo** se alcanzan con `push`, por lo que están a salvo.

### Impacto

Alto y muy visible: dos de las tres vías de acceso al formulario de compra dejan la app
inutilizable hasta reiniciarla. La compra es la operación más frecuente del producto.

### Por qué no lo detectó ningún test

Los tests de formularios los montan directamente con `MaterialApp(home: PlanFormScreen())`,
sin `GoRouter`. `widget_test.dart` monta `AgroApp` pero solo comprueba las etiquetas de
navegación. Ver [22_TESTING](22_TESTING.md) T-02.

---

## ✅ KI-02 · Divergencia de índices entre instalación nueva e instalación migrada — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

`lib/data/app_database.dart`:

| Índice | En `_createSchema` | En `_upgradeSchema` (v4) |
|---|---|---|
| `idx_application_item_unique` | `CREATE UNIQUE INDEX` | `CREATE INDEX` |
| `idx_plan_item_unique` | `CREATE UNIQUE INDEX` | `CREATE INDEX` |

**Consecuencia**: una instalación **nueva** tiene la restricción de unicidad a nivel de
motor; una instalación **migrada** desde v1/v2/v3 **no la tiene** y depende únicamente de la
validación en Dart (RN-18, RN-23).

Hoy la validación en Dart sí cubre ambos casos, así que no hay corrupción observable. El
problema es que existen **dos esquemas distintos en producción**, lo que hace que cualquier
razonamiento sobre garantías del motor sea falso para la mitad de los usuarios.

**Relacionado**: la tabla `app_settings` se crea en `_createSchema` pero **en ninguna ruta de
migración**. Al no usarse, hoy es inocuo.

**Corrección**: requiere un tramo de migración a v5 que elimine y recree los índices, previa
comprobación de que no existan filas duplicadas.

---

## ✅ KI-03 · Dos pantallas se quedan cargando para siempre ante un error — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

### `SettlementsScreen` — sin rama de error

```dart
builder: (context, snapshot) {
  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
  final (settlements, farmCosts, productCosts, campaigns) = snapshot.data!;
  ...
}
```

**No existe `if (snapshot.hasError)`.** Si el `Future` falla, `hasData` es `false` y la
pantalla muestra el spinner indefinidamente, sin mensaje ni forma de recuperarse.

### `PurchasesScreen` — rama de error inalcanzable

```dart
if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
if (snapshot.hasError) return EmptyState(...);   // ← nunca se alcanza
```

Ante un error, `hasData` es `false`, así que la primera condición captura el caso y la
segunda es **código muerto**. Mismo síntoma.

**Corrección**: comprobar `hasError` **antes** que `hasData` en ambas.

---

## ✅ KI-04 · `productCostReport` filtrado por campaña oculta productos — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

```sql
FROM products p
LEFT JOIN application_items i ON i.product_id = p.id
LEFT JOIN applications a ON a.id = i.application_id AND a.reversed_at IS NULL
${campaignId == null ? '' : 'WHERE a.campaign_id=?'}
GROUP BY p.id ORDER BY p.name
```

Poner una condición sobre la tabla del `LEFT JOIN` en el `WHERE` **lo convierte en
`INNER JOIN`**: las filas donde `a.campaign_id` es `NULL` (productos sin aplicaciones en esa
campaña) se descartan.

**Síntoma para el usuario**: en "Costo consumido por producto" de `/liquidacion`:
- con **"Todas las campañas"**: aparecen todos los productos, los no consumidos en Bs 0,00;
- con **una campaña seleccionada**: los productos sin consumo en esa campaña **desaparecen
  de la lista** en lugar de mostrarse en cero.

**Corrección**: mover la condición al `ON` del `LEFT JOIN`, como ya se hace correctamente en
`farmCostReport`:

```sql
LEFT JOIN applications a ON a.farm_id=f.id AND a.reversed_at IS NULL
${campaignId == null ? '' : 'AND a.campaign_id=?'}
```

`farmCostReport` lo hace bien; `productCostReport` no. La inconsistencia entre dos métodos
contiguos hace muy probable que sea un descuido.

---

## 🟠 KI-05 · Los asientos sin campaña no cuentan en el saldo inicial

**Estado: VERIFICADO EN CÓDIGO.**

`personCampaignBalance`:

```sql
COALESCE(SUM(CASE WHEN c.start_date < ? THEN t.amount_bob_minor_signed ELSE 0 END),0)
  opening_balance,
...
FROM account_transactions t LEFT JOIN campaigns c ON c.id = t.campaign_id
WHERE t.person_id = ?
```

`account_transactions.campaign_id` es **nullable**, y se rellena con `NULL` cuando se
registra un pago con **"Todas las campañas"** seleccionado en `SettlementsScreen` (que pasa
`campaignId: selectedCampaignId`, y ese valor es `null` en ese caso).

Para esas filas, el `LEFT JOIN` deja `c.start_date` en `NULL`, la comparación `NULL < ?` no
es verdadera, y el asiento **no se suma al saldo inicial**, aunque **sí** se suma a
`total_balance` (que no filtra).

**Síntoma**: en el diálogo de estado de cuenta filtrado por campaña, el "Saldo inicial de
campaña" puede no cuadrar con la suma de movimientos anteriores, si alguno se registró sin
campaña.

**Impacto**: medio. Solo afecta al valor informativo del saldo inicial; los saldos totales de
`settlements()` son correctos.

---

## 🟠 KI-06 · La compra y su pago no son atómicos

**Estado: VERIFICADO EN CÓDIGO.**

`PurchaseFormScreen._confirm`:

```dart
final purchaseId = await repo.confirmPurchase(draft);   // transacción 1: COMMIT
if (payProvider) {
  await repo.addProviderPayment(...);                   // transacción 2, SEPARADA
}
```

Si la segunda operación falla, la compra ya está confirmada pero sin su pago. El usuario ve
un snackbar de error y el formulario **no hace `pop`**, por lo que puede creer que nada se
guardó e intentar de nuevo, **duplicando la compra**.

**Probabilidad de que ocurra**: baja — el total lo calcula la misma fórmula en la UI y en el
repositorio, así que RN-16 no debería dispararse. Pero la inconsistencia estructural existe.

---

## ✅ KI-07 · `_farmOwner` siempre devuelve `null` — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

`lib/presentation/screens/application_form_screen.dart`:

```dart
int? _farmOwner(int? id) {
  if (id == null) return null;
  return null;              // única salida
}
```

Usado en `selectPerson`:

```dart
if (_farmOwner(farmId) != id) farmId = null;
```

La condición es siempre verdadera. **El efecto neto es el deseado** (limpiar el chaco al
cambiar de persona), así que **no hay defecto funcional observable**. Se registra porque el
código aparenta una comprobación que no realiza y es una trampa para futuros lectores.

---

## 🟡 KI-08 · Superficies mostradas sin formatear

**Estado: VERIFICADO EN CÓDIGO.**

Ocho ocurrencias del patrón:

```dart
'${(row['area_m2'] as int) / 10000} ha'
```

Al ser división en coma flotante sin `NumberFormat`, la salida es `28.0 ha` en el mejor caso
y `2.8000000000000003 ha` con valores no redondos.

Afecta a: `PersonsScreen`, `PersonDetailScreen` (resumen y chacos), `FarmLogbookScreen`,
`CatalogsScreen`, `PlanningScreen`, `SettlementsScreen`, `ApplicationFormScreen` (subtítulo
del selector de chaco).

Contrasta con el resto de la app, que formatea con rigor mediante `formatBob` y
`formatQuantity`.

---

## ✅ KI-09 · `CASE` muerto y truncamiento en el valor de inventario — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

`inventorySummary`:

```sql
COALESCE(SUM(CASE WHEN m.quantity_signed > 0
                  THEN m.quantity_signed * l.unit_cost_bob_minor_per_major_unit
                  ELSE m.quantity_signed * l.unit_cost_bob_minor_per_major_unit
             END) / 1000, 0) available_value_bob_minor
```

Dos problemas:

1. **Las dos ramas del `CASE` son idénticas**: el condicional no hace nada.
2. La división `/1000` es **entera en SQLite** (truncamiento), mientras que **todo el resto
   del proyecto** usa `divideRoundedHalfUp` (redondeo mitad arriba). El valor de inventario
   mostrado en el dashboard y en `/inventario` puede diferir en céntimos del que se
   obtendría con la aritmética canónica del proyecto.

**Impacto**: bajo en magnitud (céntimos), pero es una **inconsistencia de la regla de
redondeo**, que en un sistema contable conviene mantener uniforme.

---

## 🟡 KI-10 · `int.parse` sin validar en parámetros de ruta

**Estado: VERIFICADO EN CÓDIGO.**

```dart
GoRoute(path: '/inventario/:id',
  builder: (_, state) => InventoryDetailScreen(
    productId: int.parse(state.pathParameters['id']!)));
```

Igual en `/personas/:id` y `/chacos/:id`. Un id no numérico lanza `FormatException` durante
la construcción de la ruta, sin `errorBuilder` que lo recoja.

**No alcanzable hoy**: no hay deep links configurados y todas las llamadas pasan enteros.
`/aplicaciones/nueva` **sí** usa `int.tryParse`, lo que muestra que el patrón correcto ya se
conoce en el proyecto.

---

## 🟡 KI-11 · Notas de aplicación no marcan el formulario como sucio

**Estado: VERIFICADO EN CÓDIGO.**

`ApplicationFormScreen`:

```dart
TextField(
  controller: notes,
  onChanged: (_) => dirty = true,     // ← sin setState
  ...
)
```

Todos los demás campos usan `setState(() => dirty = true)`. Aquí se asigna la variable pero
no se reconstruye, por lo que `PopScope.canPop` conserva su valor anterior hasta la
siguiente reconstrucción por otro motivo.

**Síntoma**: si el usuario **solo** escribe notas y pulsa atrás, puede perderlas sin el
diálogo "¿Descartar cambios?".

---

## ✅ KI-12 · Reversiones sin confirmación — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

| Pantalla | Acción | ¿Confirma? |
|---|---|:--:|
| `ApplicationsScreen` | Icono ↩ por fila | ❌ **No** |
| `TransfersScreen` | Icono ↩ por fila | ❌ **No** |
| `PurchasesScreen` | Menú ⋮ → "Revertir compra" | ❌ **No** |

Un solo toque ejecuta una operación contable que ajusta inventario y saldos. **No existe
"des-revertir"** desde la interfaz.

En `ApplicationsScreen` el icono está en el `trailing` de un `ListTile`, junto al importe —
una zona de toque fácil de pulsar por accidente al desplazarse.

Contrasta con el cuidado puesto en otras confirmaciones: descartar cambios, cerrar campaña,
cambiar campaña activa y confirmar transferencia **sí** tienen diálogo.

---

## 🟡 KI-13 · Imágenes de factura huérfanas y sin limpiar

**Estado: VERIFICADO EN CÓDIGO.**

Dos situaciones:

1. **Huérfanas por fallo**: `_confirm` llama a `storeInvoiceImage` **antes** de
   `confirmPurchase`. Si la compra falla, el archivo ya está copiado y sin referencia.
2. **Huérfanas por reversión**: `reversePurchase` no borra la imagen asociada.

Además, en iOS se guarda una **ruta absoluta**, y el UUID del contenedor de la app cambia
entre reinstalaciones, invalidando todas las rutas almacenadas.

Ninguna afecta a la integridad de los datos financieros; son ocupación de espacio e imágenes
que dejan de mostrarse (con un mensaje correcto, eso sí: *"La imagen de factura ya no está
disponible en este dispositivo."*).

---

## 🟡 KI-14 · No se puede registrar una operación con fecha pasada

**Estado: VERIFICADO EN CÓDIGO.**

`confirmPurchase`, `confirmApplication` y `transferProductsFifo` **aceptan** una fecha, pero
las tres pantallas envían siempre `DateTime.now()`:

```dart
purchaseDate: DateTime.now(),   // purchase_form_screen.dart
appliedAt: DateTime.now(),      // application_form_screen.dart
// transfer_form_screen.dart no pasa fecha → el repositorio usa DateTime.now()
```

**Impacto funcional real**: si el usuario registra el lunes una compra hecha el viernes
anterior, esa fecha queda mal. Y como `acquired_date` gobierna el **orden FIFO**, una carga
retrasada puede alterar qué lote se consume primero, y por tanto el costo imputado.

Es una limitación de interfaz sobre una capacidad que el dominio ya soporta.

---

## ✅ KI-15 · Uso inconsistente de `friendlyError` — CORREGIDO

**Estado: VERIFICADO EN CÓDIGO.**

`CatalogsScreen` y `PurchasesScreen` muestran `snapshot.error.toString()` en crudo; las otras
once pantallas usan `friendlyError(snapshot.error!)`.

En esas dos, un `BusinessRuleException` se mostraría con el prefijo
`BusinessRuleException: ` incluido en el texto visible al usuario.

---

## 🟡 KI-16 · `DatabaseException` sin traducir

**Estado: VERIFICADO EN CÓDIGO.**

`friendlyError` cubre `BusinessRuleException`, `FormatException` y `StateError`, pero no las
excepciones de SQLite.

**Reproducción**: en `/catalogos` → Chacos → Agregar, escribir texto no numérico en
"Superficie (ha)". `tryParseDecimal` devuelve `null` → se envía `areaM2: 0` → el
`CHECK(area_m2 > 0)` falla → el usuario ve:

```
DatabaseException(CHECK constraint failed: area_m2 > 0) sql 'INSERT INTO farms ...'
```

---

## 🟡 KI-17 · Sin estado vacío en varias listas

**Estado: VERIFICADO EN CÓDIGO.**

| Ubicación | Comportamiento con lista vacía |
|---|---|
| `PersonsScreen` | Renderiza una `Card` vacía, sin mensaje |
| `InventoryDetailScreen` → "Distribución por persona" | `Card` vacía |
| `InventoryDetailScreen` → "Lotes disponibles" | `Card` vacía |
| `DashboardScreen` → "Aplicaciones recientes" | `Card` vacía |
| `DashboardScreen` → "Principales saldos" | `Card` vacía |

Especialmente relevante en la **primera ejecución**, cuando la base está vacía: el dashboard
muestra tarjetas grises sin ninguna indicación de qué hacer.

---

## 🟡 KI-18 · `archiveCatalog` para campañas es inalcanzable

**Estado: VERIFICADO EN CÓDIGO.**

`agro_repository.archiveCatalog` tiene una rama específica para `'campaigns'`
(`status = 'CLOSED'`), pero `CatalogsScreen` nunca la invoca:

```dart
onSelected: (value) => tabs.index == 4
    ? _campaignAction(value, row)      // ← campañas SIEMPRE por aquí
    : value == 'edit' ? _edit(row) : _archive(row),
```

Y `_campaignAction` solo maneja `'activate'`, `'close'` y (por defecto) `_edit`. La rama de
campañas de `archiveCatalog` es código muerto.

---

## 🟡 KI-19 · La app no funciona en web

**Estado: VERIFICADO EN CÓDIGO.**

La carpeta `web/` existe y `.metadata` declara la plataforma, pero:

1. `AppDatabase._platformFactory()` en `kIsWeb` cae a `mobile.databaseFactory`, que no
   funciona en navegador.
2. `agro_repository.dart`, `purchase_form_screen.dart` y `purchases_screen.dart` importan
   `dart:io`, que no existe en web.

`flutter build web` compilaría, pero la aplicación fallaría al abrir la base de datos.

---

## ✅ KI-20 · El directorio de trabajo no está bajo control de versiones — YA NO APLICA

**Estado: CONFIRMADO.**

`git rev-parse` falla: **este directorio no es un repositorio Git**.

**Consecuencias para esta auditoría**:
- No fue posible ejecutar `git diff` como pedía el paso de validación final.
- No hay historial de commits que consultar para entender decisiones pasadas.
- La verificación de "solo se añadió documentación" se hizo comparando el inventario de
  archivos antes y después de la auditoría (ver [00_INDEX](00_INDEX.md)).

Existe un `.gitignore` completo y correcto, lo que sugiere que el proyecto **sí está bajo
Git en otra copia**.

`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ubicación del repositorio real y si esta copia
está sincronizada con él.

---

## Resumen

| ID | Defecto | Severidad | Confirmación |
|---|---|---|---|
| KI-01 | Atrás desde "Nueva compra" rompe la app | 🔴 Alta | ✅ **CORREGIDO** (STAB-001) |
| KI-02 | Divergencia de índices creación vs migración | 🔴 Alta | ✅ **CORREGIDO** (STAB-002, migración v5) |
| KI-03 | Dos pantallas cargan para siempre ante error | 🟠 Media | ✅ **CORREGIDO** (STAB-004, 4 pantallas) |
| KI-04 | `productCostReport` oculta productos al filtrar | 🟠 Media | ✅ **CORREGIDO** (STAB-005) |
| KI-05 | Asientos sin campaña fuera del saldo inicial | 🟠 Media | Verificado en código |
| KI-06 | Compra y pago no atómicos | 🟠 Media | Verificado en código |
| KI-07 | `_farmOwner` siempre `null` | 🟡 Baja | ✅ **CORREGIDO** (STAB-012) |
| KI-08 | Superficies sin formatear | 🟡 Baja | Verificado en código |
| KI-09 | `CASE` muerto y truncamiento en valor de inventario | 🟡 Baja | ✅ **CORREGIDO** (STAB-011) |
| KI-10 | `int.parse` en rutas | 🟡 Baja | Verificado en código |
| KI-11 | Notas no marcan como sucio | 🟡 Baja | Verificado en código |
| KI-12 | Reversiones sin confirmación | 🟡 Baja | ✅ **CORREGIDO** (STAB-010) |
| KI-13 | Imágenes huérfanas | 🟡 Baja | Verificado en código |
| KI-14 | Sin fecha editable en operaciones | 🟡 Baja | Verificado en código |
| KI-15 | `friendlyError` inconsistente | 🟡 Baja | ✅ **CORREGIDO** (STAB-004) |
| KI-16 | `DatabaseException` sin traducir | 🟡 Baja | Verificado en código |
| KI-17 | Sin estado vacío en 5 listas | 🟡 Baja | Verificado en código |
| KI-18 | `archiveCatalog` de campañas inalcanzable | 🟡 Baja | Verificado en código |
| KI-19 | La app no funciona en web | 🟡 Baja | Verificado en código |
| KI-20 | Sin control de versiones en esta copia | ⚪ Info | ✅ **YA NO APLICA**: repo Git activo |
