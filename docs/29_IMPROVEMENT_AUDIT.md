# 29 — Auditoría de mejoras

> **Este documento no modifica nada.** Identifica oportunidades reales, con evidencia.
> El orden de ejecución está en [30_IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md).

## Clasificación

| Prioridad | Criterio |
|---|---|
| **P0 — Crítico** | Rompe la app hoy, bloquea la distribución, o pone en riesgo la integridad de datos |
| **P1 — Alto** | Defecto funcional visible, riesgo de datos incorrectos, o carencia operativa grave |
| **P2 — Medio** | Mantenibilidad, calidad, rendimiento perceptible |
| **P3 — Bajo** | Higiene, consistencia, funcionalidad nueva |

## Índice

| ID | Mejora | Prioridad |
|---|---|:--:|
| M-01 | Corregir la navegación rota hacia "Nueva compra" | **P0** |
| M-02 | Configurar la firma de release | **P0** |
| M-03 | Corregir la divergencia de índices entre creación y migración | **P0** |
| M-04 | Añadir test de equivalencia de esquema tras migración | **P0** |
| M-05 | Función de restauración de backup | **P1** |
| M-06 | Corregir los estados de error muertos | **P1** |
| M-07 | Corregir `productCostReport` con filtro de campaña | **P1** |
| M-08 | Añadir logging local diagnosticable | **P1** |
| M-09 | Confirmación antes de revertir | **P1** |
| M-10 | Fecha editable en operaciones | **P1** |
| M-11 | Test de navegación sobre la app completa | **P1** |
| M-12 | Corregir `Future` creado en `build()` | **P2** |
| M-13 | Extraer el motor FIFO a un único lugar | **P2** |
| M-14 | Eliminar el código muerto | **P2** |
| M-15 | Traducir `DatabaseException` en `friendlyError` | **P2** |
| M-16 | Introducir modelos de lectura tipados | **P2** |
| M-17 | Dividir `AgroRepository` | **P2** |
| M-18 | Cerrar los huecos de validación del repositorio | **P2** |
| M-19 | Tests de reportes y agregados | **P2** |
| M-20 | Integración continua | **P2** |
| M-21 | Corregir el valor de inventario truncado | **P2** |
| M-22 | Centralizar formateo de hectáreas y etiquetas de rol | **P3** |
| M-23 | Estados vacíos faltantes y primera ejecución guiada | **P3** |
| M-24 | Unificar el naming del producto | **P3** |
| M-25 | Actualizar el README | **P3** |
| M-26 | Limpiar dependencias no usadas | **P3** |
| M-27 | Trazabilidad de autoría | **P3** |
| M-28 | Decidir el futuro de la plataforma web | **P3** |

---

# P0 — Crítico

## M-01 · Corregir la navegación rota hacia "Nueva compra"

**Problema**
Dos de las tres vías de acceso al formulario de compra dejan la aplicación en una pantalla
en blanco al pulsar atrás.

**Evidencia**
Reproducido durante esta auditoría (detalle completo en [KI-01](27_KNOWN_ISSUES.md)):

```
You have popped the last page off of the stack, there are no pages left to show
'package:go_router/src/delegate.dart': line 178: 'currentConfiguration.isNotEmpty'
#7 _PurchaseFormScreenState._close.<anonymous closure>
   (purchase_form_screen.dart:110:42)
```

**Ubicación**
- `lib/presentation/app_shell.dart` — FAB "Nuevo" → `context.go('/compras/nueva')`
- `lib/presentation/screens/operations_screen.dart` — `context.go(action.path)`

**Impacto**
Alto y muy visible. La compra es la operación más frecuente; la app queda inutilizable hasta
reiniciarla.

**Riesgo actual**
Alto. Ocurre siempre por esas dos vías.

**Solución recomendada**
Usar `context.push` para las cuatro rutas de nivel superior. En `AppShell`, distinguir los
destinos de shell (que sí deben usar `go`) de las rutas de formulario. En
`OperationsScreen`, usar `push` para `/compras/nueva`.

Alternativa más robusta: declarar las rutas de formulario como hijas de sus rutas de listado
dentro del `ShellRoute`, con `parentNavigatorKey` para que se muestren a pantalla completa.

**Complejidad: Low**

**Dependencias**
Ninguna.

**Riesgo de regresión**
Bajo. Conviene añadir M-11 a la vez para blindarlo.

---

## M-02 · Configurar la firma de release

**Problema**
La build de release se firma con la clave de depuración de Android.

**Evidencia**
`android/app/build.gradle.kts`:
```kotlin
// TODO: Add your own signing config for the release build.
release { signingConfig = signingConfigs.getByName("debug") }
```

**Ubicación**
`android/app/build.gradle.kts`

**Impacto**
- Google Play **rechaza** el binario: hoy el producto no se puede publicar.
- La clave de depuración es pública: cualquiera puede firmar una "actualización" que el
  sistema aceptará como legítima.

**Riesgo actual**
Alto si el APK se distribuye de cualquier forma (incluido enviarlo por mensajería). Medio si
solo se instala desde el equipo de desarrollo.

**Solución recomendada**
Keystore fuera del repositorio; `android/key.properties` añadido a `.gitignore`;
`signingConfigs.create("release")` que lo lea. Documentar con placeholders
(`storePassword=<REQUIRED>`), **nunca** con valores reales.

**Complejidad: Low**

**Dependencias**
`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ¿existe ya un keystore? ¿Se pretende publicar en
Play o solo distribuir el APK internamente?

**Riesgo de regresión**
Ninguno sobre el código; sí operativo: **perder el keystore impide publicar actualizaciones
para siempre**. Debe custodiarse con copia de seguridad.

---

## M-03 · Corregir la divergencia de índices entre creación y migración

**Problema**
Dos índices son `UNIQUE` en instalaciones nuevas y **no únicos** en instalaciones migradas.

**Evidencia**
`lib/data/app_database.dart`:

| Índice | `_createSchema` | `_upgradeSchema` (v4) |
|---|---|---|
| `idx_application_item_unique` | `CREATE UNIQUE INDEX` | `CREATE INDEX` |
| `idx_plan_item_unique` | `CREATE UNIQUE INDEX` | `CREATE INDEX` |

Además, `app_settings` se crea solo en `_createSchema`.

**Ubicación**
`lib/data/app_database.dart` — `_createSchema` y `_upgradeSchema`.

**Impacto**
Alto. Existen **dos esquemas distintos en producción**. Cualquier razonamiento sobre
garantías del motor es falso para los usuarios migrados, que dependen solo de la validación
en Dart (RN-18, RN-23).

**Riesgo actual**
Medio. Hoy la validación en Dart cubre ambos casos, así que no hay corrupción observable.
El riesgo se materializa si alguna vez se abre una vía que la eluda.

**Solución recomendada**
Nueva versión de esquema (v5) cuyo tramo de migración:
1. Compruebe si existen filas duplicadas (y las resuelva o aborte con un mensaje claro).
2. `DROP INDEX` + `CREATE UNIQUE INDEX` para ambos índices.
3. Cree `app_settings` si no existe.

**Complejidad: Medium** — la corrección del `CREATE INDEX` es trivial; la reparación de bases
ya migradas no lo es.

**Dependencias**
Debe hacerse junto con M-04.

**Riesgo de regresión**
**Medio-alto.** Toca migraciones sobre datos reales de usuarios. Requiere M-04 antes de
desplegarse.

---

## M-04 · Añadir test de equivalencia de esquema tras migración

**Problema**
Ningún test compara el esquema resultante de una migración con el de una base creada desde
cero. Por eso M-03 pasó desapercibido.

**Evidencia**
`test/migration_test.dart` tiene dos tests que verifican **tablas y columnas** (v1→v2 y
v3→v4 parcial), pero **nunca consultan `PRAGMA index_list`**, por lo que no pueden detectar
una diferencia en el atributo `unique`. La migración v2→v3 no se prueba en absoluto.

**Ubicación**
`test/migration_test.dart`

**Impacto**
Alto: es la salvaguarda que evita corromper datos reales de usuarios en actualizaciones
futuras.

**Riesgo actual**
Alto — es exactamente el hueco que ya produjo un defecto.

**Solución recomendada**
Un test que, para cada versión de origen (1, 2, 3):
1. Cree una base con el esquema de esa versión.
2. La abra con `AppDatabase` (disparando la migración).
3. Extraiga tablas (`sqlite_master`), columnas (`PRAGMA table_info`) e índices con su
   atributo `unique` (`PRAGMA index_list` + `PRAGMA index_info`).
4. Compare **el conjunto completo** con el de una base recién creada.

Un solo test así cubre todas las migraciones presentes y futuras.

**Complejidad: Medium**

**Dependencias**
Ninguna. **Debe hacerse antes que M-03.**

**Riesgo de regresión**
Ninguno: solo añade tests.

---

# P1 — Alto

## M-05 · Función de restauración de backup

**Problema**
Se puede exportar la base, pero **no importarla**. Un backup que la app no puede leer sirve
de poco al usuario final.

**Evidencia**
`exportBackup()` existe en `agro_repository.dart`. No hay ningún método de importación en las
1 862 líneas del repositorio.

Además, `exportBackup` copia **solo el `.db`**: las fotos de `invoices/` quedan fuera.

**Ubicación**
`lib/data/agro_repository.dart`, `lib/presentation/screens/settlements_screen.dart`

**Impacto**
**El mayor riesgo operativo del producto.** Toda la contabilidad vive en un archivo, en un
teléfono, sin respaldo automático. Perder el dispositivo = perder el histórico completo.

**Riesgo actual**
Alto. No es hipotético: los teléfonos se pierden y se rompen.

**Solución recomendada**
Por fases:
1. **Restaurar**: selector de archivo, validación del esquema, confirmación explícita
   ("esto reemplazará todos los datos actuales"), copia de seguridad de la base actual antes
   de sustituir, reinicio de la app.
2. **Empaquetar**: exportar un ZIP con el `.db` **y** la carpeta `invoices/`.
3. **Compartir**: usar el *share sheet* del sistema en lugar de escribir en Descargas
   (resuelve además [S-03](23_SECURITY_AUDIT.md)).
4. **Recordar**: guardar la fecha del último backup (la tabla `app_settings`, hoy muerta,
   existe exactamente para esto) y avisar si hace mucho.

**Complejidad: Medium**

**Dependencias**
La fase 3 requiere `share_plus` o equivalente; el resto no requiere dependencias nuevas.

**Riesgo de regresión**
**Alto en la fase 1**: una restauración es destructiva. Debe hacer copia previa y validar el
archivo antes de sustituir nada.

---

## M-06 · Corregir los estados de error muertos

**Problema**
Dos pantallas se quedan con el spinner indefinidamente cuando su consulta falla.

**Evidencia**
- `settlements_screen.dart`: **no tiene** `if (snapshot.hasError)`.
- `purchases_screen.dart`: la tiene, pero **después** de `if (!snapshot.hasData)`, que la
  hace inalcanzable.

**Ubicación**
`lib/presentation/screens/settlements_screen.dart`, `lib/presentation/screens/purchases_screen.dart`

**Impacto**
Medio-alto: el usuario ve una pantalla cargando para siempre, sin explicación ni salida.

**Riesgo actual**
Medio.

**Solución recomendada**
Comprobar `hasError` antes que `hasData` en ambas, usando `friendlyError` (lo que resuelve
también parte de M-15 y [KI-15](27_KNOWN_ISSUES.md)).

**Complejidad: Low**

**Riesgo de regresión**
Muy bajo.

---

## M-07 · Corregir `productCostReport` con filtro de campaña

**Problema**
Al filtrar por campaña, los productos sin consumo **desaparecen** del reporte en lugar de
mostrarse en cero.

**Evidencia**
```sql
LEFT JOIN applications a ON a.id=i.application_id AND a.reversed_at IS NULL
${campaignId == null ? '' : 'WHERE a.campaign_id=?'}
```
La condición en el `WHERE` sobre una tabla `LEFT JOIN` la convierte en `INNER JOIN`.

`farmCostReport`, tres métodos más arriba, **lo hace bien** poniendo la condición en el `ON`.

**Ubicación**
`lib/data/agro_repository.dart` → `productCostReport`

**Impacto**
Medio: el reporte "Costo consumido por producto" da una imagen incompleta, y de forma
inconsistente con el reporte de al lado.

**Riesgo actual**
Medio — ocurre siempre que se filtra por campaña.

**Solución recomendada**
Mover la condición al `ON`, replicando exactamente el patrón de `farmCostReport`.

**Complejidad: Low**

**Dependencias**
Conviene hacerlo junto con M-19 (tests de reportes).

**Riesgo de regresión**
Bajo, pero **cambia cifras visibles**: conviene un test que fije el comportamiento esperado
antes de tocarlo.

---

## M-08 · Añadir logging local diagnosticable

**Problema**
Cero observabilidad. Si un usuario reporta un error, no hay **ninguna** información que
consultar.

**Evidencia**
Ni una sentencia de logging en 8 250 líneas de `lib/`. Sin `FlutterError.onError`, sin
`runZonedGuarded`, sin crash reporting.

**Ubicación**
Todo el proyecto; punto de entrada natural en `lib/main.dart`.

**Impacto**
Alto para el mantenimiento a largo plazo. Cada incidencia obliga a reproducir el problema a
ciegas.

**Riesgo actual**
Medio, creciente con el tiempo de vida del producto.

**Solución recomendada**
Un **log local rotativo** en el directorio de la app, exportable junto con el backup:
- `FlutterError.onError` y `PlatformDispatcher.instance.onError` escribiendo al archivo.
- Registrar las `BusinessRuleException` y su contexto.
- Rotación por tamaño (p. ej. 2 archivos de 1 MB).
- **Sin datos personales ni importes** en el log; solo tipo de operación, método y traza.

Esto evita la tensión con la postura offline: **no requiere el permiso `INTERNET`**, a
diferencia del crash reporting en la nube.

**Complejidad: Low-Medium**

**Dependencias**
Ninguna obligatoria (`dart:io` basta). Encaja bien con M-05 fase 2 (exportar el log con el
backup).

**Riesgo de regresión**
Bajo. Cuidado con no registrar información sensible.

---

## M-09 · Confirmación antes de revertir

**Problema**
Un solo toque revierte una operación contable, sin confirmación y sin posibilidad de deshacer.

**Evidencia**
`ApplicationsScreen` y `TransfersScreen` llaman a `reverse(id)` directamente desde un
`IconButton`. `PurchasesScreen` lo hace desde un `PopupMenuItem`. **Ninguna pide confirmación.**

En `ApplicationsScreen`, el icono ↩ está en el `trailing` junto al importe: zona fácil de
tocar por accidente al desplazarse.

**Ubicación**
`applications_screen.dart`, `transfers_screen.dart`, `purchases_screen.dart`

**Impacto**
Medio-alto: una reversión accidental ajusta inventario y saldos, y **no hay "des-revertir"**
en la interfaz.

**Riesgo actual**
Medio.

**Solución recomendada**
`AlertDialog` de confirmación que muestre qué se va a revertir y su efecto (importe, stock
que vuelve). El proyecto ya tiene el patrón bien implementado en el diálogo de cierre de
campaña, que muestra un resumen antes de actuar — replicarlo.

Opcionalmente, permitir escribir el motivo: los tres métodos ya aceptan `reason` y hoy la UI
manda un literal fijo (*"Reversión solicitada por usuario"*).

**Complejidad: Low**

**Riesgo de regresión**
Muy bajo.

---

## M-10 · Fecha editable en operaciones

**Problema**
No se puede registrar una compra, aplicación o transferencia con fecha pasada.

**Evidencia**
Los tres métodos del repositorio **aceptan** fecha, pero las pantallas envían siempre
`DateTime.now()`:
```dart
purchaseDate: DateTime.now(),   // purchase_form_screen.dart
appliedAt: DateTime.now(),      // application_form_screen.dart
```

**Ubicación**
`purchase_form_screen.dart`, `application_form_screen.dart`, `transfer_form_screen.dart`

**Impacto**
Medio-alto, y con efecto sobre los datos: `acquired_date` gobierna el **orden FIFO**. Cargar
el lunes una compra del viernes anterior puede alterar qué lote se consume primero y, por
tanto, el costo imputado a una persona.

**Riesgo actual**
Alto en la práctica: en trabajo de campo es habitual registrar las operaciones más tarde.

**Solución recomendada**
Añadir un `showDatePicker` con `DateTime.now()` por defecto y `lastDate: now`. La capa de
dominio **ya lo soporta**: es puro trabajo de interfaz.

Considerar validar que la fecha caiga dentro del rango de la campaña activa.

**Complejidad: Low**

**Riesgo de regresión**
Bajo, pero **conviene un test** que confirme que el orden FIFO sigue siendo correcto con
fechas retroactivas.

---

## M-11 · Test de navegación sobre la app completa

**Problema**
Ningún test ejercita el enrutado real, lo que permitió que M-01 llegara a producción.

**Evidencia**
- `back_navigation_test.dart` prueba `_DirtyFormHarness`, una **réplica** definida en el
  propio archivo de test, no las pantallas reales.
- Los tests de formularios los montan con `MaterialApp(home: PlanFormScreen())`, **fuera del
  `GoRouter`**.
- `widget_test.dart` monta `AgroApp` pero solo comprueba etiquetas.

**Ubicación**
`test/back_navigation_test.dart`, `test/widget_test.dart`

**Impacto**
Alto: sin esto, cualquier corrección de M-01 puede volver a romperse.

**Riesgo actual**
Alto — ya se materializó.

**Solución recomendada**
Un test que monte `AgroApp` completo con un repositorio en memoria y recorra:
FAB → cada destino → atrás; y lista → formulario → atrás. Verificando
`tester.takeException()` nulo y que la pantalla de origen reaparece.

Durante esta auditoría, un test de ~30 líneas con ese enfoque bastó para reproducir el
defecto.

Sustituir además `_DirtyFormHarness` por los formularios reales.

**Complejidad: Medium** — la sincronización de widget tests con `FutureBuilder` requiere el
patrón `runAsync` + `pump` que el proyecto ya tiene en `regression_widget_test.dart`.

**Dependencias**
Debe acompañar a M-01.

**Riesgo de regresión**
Ninguno.

---

# P2 — Medio

## M-12 · Corregir `Future` creado en `build()`

**Problema**
Cuatro pantallas relanzan sus consultas en cada reconstrucción, provocando parpadeo al
spinner y pérdida del scroll.

**Evidencia**
`PersonDetailScreen` (5 consultas), `InventoryDetailScreen` (3), `FarmLogbookScreen` (2),
`PersonsScreen` (1) llaman `_load(ref)` dentro de `build()`.

**Impacto**
Medio, **visible para el usuario hoy**: girar el dispositivo o cambiar de pestaña en
`PersonDetailScreen` dispara 5 consultas y un parpadeo.

**Solución recomendada**
Convertir a `ConsumerStatefulWidget` con `late Future` en `initState`, exactamente como ya
hacen las otras nueve pantallas. Aprovechar para añadir botón de refresco, del que estas
cuatro carecen.

**Complejidad: Low** — el patrón correcto ya existe en el proyecto y está protegido por un
test de regresión.

**Riesgo de regresión**
Bajo.

---

## M-13 · Extraer el motor FIFO a un único lugar

**Problema**
El algoritmo FIFO está implementado **cuatro veces**, y la consulta SQL de lotes disponibles
**tres veces**.

**Evidencia**
`confirmApplication`, `transferProductsFifo`, `transferProductFifoV3Legacy` (muerto) y
`estimateFifoCost`. Ya hay **divergencia**: la primera usa `JOIN inventory_movements`, la
segunda `LEFT JOIN`.

**Impacto**
Alto para la mantenibilidad: un cambio de política de costeo exige cuatro ediciones
coherentes.

**Solución recomendada**
1. Ejecutar M-14 primero (elimina la copia muerta, quedan tres).
2. Extraer `_availableLots(txn, personId, productId)` — una sola consulta.
3. Extraer `_consumeFifo(lots, quantity, onTake)` con una devolución de llamada, para que
   cada llamador haga lo suyo (consumo, lote destino, o solo sumar).

**Complejidad: Medium**

**Dependencias**
Hacer después de M-14.

**Riesgo de regresión**
**Medio** — es el corazón del costeo. Mitigado por los tests existentes, que verifican
cifras exactas (Bs 5 450, reparto `[10000, 15000]`, conservación del físico total).

---

## M-14 · Eliminar el código muerto

**Problema**
~400 líneas que no se ejecutan nunca.

**Evidencia**

| Elemento | Ubicación | Líneas |
|---|---|---:|
| `_PurchaseDialog` + estado + `_AllocationInput` + `_select` | `purchases_screen.dart` | ~350 |
| `transferProductFifoV3Legacy` | `agro_repository.dart` | ~110 |
| `transferStockLegacy` | `agro_repository.dart` | ~73 |
| `_farmOwner` | `application_form_screen.dart` | 4 |
| Parámetro `people` sin usar | `purchase_form_screen.dart` | 1 |

**Impacto**
Medio: `purchases_screen.dart` aparenta 658 líneas cuando su contenido real son ~300.

**Solución recomendada**
Eliminar. En el caso de `_farmOwner`, sustituir la condición por `farmId = null;` directo,
o implementar de verdad la comprobación de propietario que el nombre sugiere.

**Complejidad: Low**

**Dependencias**
`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: los dos métodos `@Deprecated` no tienen llamadas
en `lib/` ni en `test/`. Confirmar que no se conservan por una razón externa antes de
borrarlos.

**Riesgo de regresión**
Muy bajo. `flutter analyze` y los 44 tests lo confirmarían de inmediato.

---

## M-15 · Traducir `DatabaseException` en `friendlyError`

**Problema**
Las violaciones de restricciones de SQLite llegan al usuario en crudo.

**Evidencia**
Reproducible: `/catalogos` → Chacos → Agregar, con texto no numérico en "Superficie (ha)":
```
DatabaseException(CHECK constraint failed: area_m2 > 0) sql 'INSERT INTO farms ...'
```

**Ubicación**
`lib/presentation/widgets/common.dart` → `friendlyError`

**Impacto**
Medio: mala experiencia y filtración de detalles internos del esquema.

**Solución recomendada**
Añadir ramas para `CHECK constraint failed`, `UNIQUE constraint failed` y
`FOREIGN KEY constraint failed`, mapeadas a mensajes de negocio.

Complementariamente, validar la superficie **antes** de enviarla, para dar el mensaje
correcto en origen.

Y unificar el uso de `friendlyError` en `CatalogsScreen` y `PurchasesScreen`, que hoy usan
`toString()` crudo ([KI-15](27_KNOWN_ISSUES.md)).

**Complejidad: Low**

**Riesgo de regresión**
Muy bajo.

---

## M-16 · Introducir modelos de lectura tipados

**Problema**
Toda la capa de lectura devuelve `Map<String, Object?>` y la UI hace casts por cadena
literal. Los errores son de runtime, no de compilación.

**Evidencia**
Patrón `row['product_name'] as String` en las 17 pantallas. El contrato de
`availableProductsForOwner` (6 columnas) existe solo en la cadena SQL y en los casts de tres
pantallas; `application_form_screen.dart` llega a construir un `Map` literal a mano para
imitarlo.

**Impacto**
Alto: es el techo de mantenibilidad del proyecto. Renombrar un alias SQL compila y revienta
al ejecutar.

**Solución recomendada**
**Incremental**, no de golpe:
1. Empezar por las 5–6 consultas más usadas (`inventorySummary`, `availableProductsForOwner`,
   `settlements`, `applications`, `purchases`).
2. Una clase por consulta con constructor `fromRow(Map<String, Object?>)`, que centraliza los
   casts y el manejo de `null`.
3. Cambiar la firma del método del repositorio para devolver la clase.
4. El analizador señalará todos los sitios a actualizar.

**Complejidad: High** (~20 clases en total), pero **divisible en incrementos seguros**.

**Dependencias**
Facilita M-17. Conviene hacerlo antes.

**Riesgo de regresión**
Medio, pero **el compilador es el aliado**: cada paso rompe la compilación hasta estar
completo, lo que es mucho más seguro que fallar en runtime.

---

## M-17 · Dividir `AgroRepository`

**Problema**
1 862 líneas y seis responsabilidades en una sola clase.

**Evidencia**
Ver [24_CODE_QUALITY_AUDIT](24_CODE_QUALITY_AUDIT.md) Q-02.

**Impacto**
Alto: es el archivo que toca cualquier cambio funcional.

**Solución recomendada**
División en la que **los grupos ya están agrupados físicamente** en el archivo, lo que la
hace mecánicamente sencilla:

| Clase propuesta | Contenido |
|---|---|
| `CatalogRepository` | Personas, chacos, productos, proveedores |
| `CampaignService` | Ciclo de vida de campañas |
| `PurchaseService` | Compras y pagos a proveedor |
| `InventoryService` | FIFO, aplicaciones, transferencias |
| `AccountingService` | Asientos, pagos, imputación |
| `ReportRepository` | Las ~30 consultas de lectura |

Compartiendo `AppDatabase` y, si hace falta, un ejecutor transaccional común.

**Complejidad: High**

**Dependencias**
Hacer **después** de M-13 (FIFO extraído) y preferiblemente de M-16 (tipos).

**Riesgo de regresión**
Medio-alto por el volumen, pero mitigado por los 44 tests que cubren los tres motores
críticos. **No abordar sin ellos en verde.**

---

## M-18 · Cerrar los huecos de validación del repositorio

**Problema**
Tres reglas viven solo en la interfaz y no en el repositorio.

**Evidencia** ([16_VALIDATIONS](16_VALIDATIONS.md))

| Hueco | Detalle |
|---|---|
| H-01 | `confirmApplication` no verifica que `farm.owner_person_id == person_id` |
| H-02 | `confirmApplication` no verifica que el plan pertenezca a la campaña activa |
| H-03 | Se puede confirmar una aplicación con área tratada 0 |

**Impacto**
Medio: hoy inalcanzables desde la UI, pero un cambio futuro en las pantallas podría producir
datos incoherentes.

**Solución recomendada**
Añadir las comprobaciones dentro de la transacción de `confirmApplication`, con mensajes de
negocio en el estilo del resto del proyecto.

Para H-03, decidir explícitamente si el área es obligatoria; si lo es, validarla en ambos
niveles.

**Complejidad: Low**

**Riesgo de regresión**
Bajo, **salvo que existan datos históricos que violen las nuevas reglas**. Comprobar antes de
aplicar.

---

## M-19 · Tests de reportes y agregados

**Problema**
Las consultas de reporte no tienen ni un test, pese a ser el tipo de código donde un error
es **silencioso**: muestra un número equivocado sin fallar.

**Evidencia**
Sin cobertura: `dashboard()`, `farmCostReport()`, `productCostReport()`,
`campaignCloseSummary()`, las columnas derivadas de `inventorySummary()`
(`committed_base`, `projected_base`, `available_value_bob_minor`), `personProfiles()`,
`detailedStatement()`.

El defecto M-07 es exactamente de esta clase.

**Impacto**
Medio-alto: son las cifras que el usuario usa para tomar decisiones.

**Solución recomendada**
Un archivo `report_test.dart` con un escenario conocido y aserciones sobre cifras exactas,
en el estilo ya establecido por `repository_test.dart`. Incluir los casos de filtro por
campaña, que es donde está el defecto M-07.

**Complejidad: Medium**

**Dependencias**
Hacer **antes** de M-07, para fijar el comportamiento esperado.

**Riesgo de regresión**
Ninguno.

---

## M-20 · Integración continua

**Problema**
No hay CI. Nada garantiza que los cuatro comandos de verificación del README se ejecuten.

**Evidencia**
Sin `.github/workflows/`, `.gitlab-ci.yml`, `codemagic.yaml` ni `Jenkinsfile`.

**Impacto**
Medio, creciente con el número de personas que toquen el código.

**Solución recomendada**
Un flujo que en cada cambio ejecute exactamente lo que el README ya define:
```
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --coverage
flutter build apk --debug
```
Los cuatro **ya pasan hoy**, así que el flujo nace en verde. Añadir informe de cobertura.

**Complejidad: Low**

**Dependencias**
`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: dónde está el repositorio real
([KI-20](27_KNOWN_ISSUES.md)) y qué plataforma de CI se prefiere.

**Riesgo de regresión**
Ninguno.

---

## M-21 · Corregir el valor de inventario truncado

**Problema**
`inventorySummary` calcula el valor con división entera truncada, y con un `CASE` cuyas dos
ramas son idénticas.

**Evidencia**
```sql
COALESCE(SUM(CASE WHEN m.quantity_signed>0
    THEN m.quantity_signed*l.unit_cost_bob_minor_per_major_unit
    ELSE m.quantity_signed*l.unit_cost_bob_minor_per_major_unit END)/1000, 0)
```

**Impacto**
Bajo en magnitud (céntimos), pero es una **inconsistencia en la regla de redondeo**: todo el
resto del sistema usa `divideRoundedHalfUp`, y en contabilidad conviene que la regla sea
uniforme.

**Solución recomendada**
Eliminar el `CASE` y, o bien replicar el redondeo mitad arriba en SQL
(`(x + 500) / 1000`), o devolver la suma sin dividir y aplicar `costForBaseQuantity` en Dart.
La segunda opción es preferible: mantiene una única implementación del redondeo.

**Complejidad: Low**

**Dependencias**
Hacer con M-19 (para fijar la cifra esperada con un test).

**Riesgo de regresión**
Bajo, pero **cambia cifras visibles**.

---

# P3 — Bajo

## M-22 · Centralizar formateo de hectáreas y etiquetas de rol

**Problema**
`(x as int) / 10000` en 8 sitios produce `28.0 ha` o `2.8000000000000003 ha`. La traducción
de rol a etiqueta está implementada **4 veces**.

**Evidencia**
Ver [24_CODE_QUALITY_AUDIT](24_CODE_QUALITY_AUDIT.md) Q-06 y Q-09.

**Impacto**
Bajo, pero **visible para el usuario**.

**Solución recomendada**
Añadir a `domain/money.dart`:
```
formatHectares(int areaM2)   // usando NumberFormat, locale es_BO
```
Y un helper de etiquetas de rol y de política en un único lugar. La capa de formateo
centralizada **ya existe**; solo hay que completarla.

**Complejidad: Low**

**Riesgo de regresión**
Muy bajo.

---

## M-23 · Estados vacíos faltantes y primera ejecución guiada

**Problema**
En una base vacía —la primera ejecución— el dashboard muestra tarjetas grises sin ninguna
indicación de qué hacer. Cinco listas no tienen estado vacío.

**Evidencia**
Sin `EmptyState`: `PersonsScreen`; "Distribución por persona" y "Lotes disponibles" de
`InventoryDetailScreen`; "Aplicaciones recientes" y "Principales saldos" de
`DashboardScreen`.

Además, la app **exige** un orden de configuración inicial (personas → campaña → chacos →
productos) que no está documentado ni guiado en ninguna parte.

**Impacto**
Medio para la adopción, bajo para el uso diario.

**Solución recomendada**
1. Añadir los cinco `EmptyState` que faltan.
2. En el dashboard, cuando no haya campaña activa **ni** datos, mostrar una tarjeta de
   bienvenida con los pasos y un acceso directo a `/catalogos`.

El proyecto ya tiene 14 estados vacíos bien redactados: solo hay que completar la serie.

**Complejidad: Low**

**Riesgo de regresión**
Ninguno.

---

## M-24 · Unificar el naming del producto

**Problema**
El usuario ve "agroquimicos" bajo el icono en Android, "Agroquimicos" en iOS y "Agrocuentas"
dentro de la app.

**Evidencia**
Ver [26_TECHNICAL_DEBT](26_TECHNICAL_DEBT.md) DT-10.

**Solución recomendada**
Decidir un nombre (aparentemente **Agrocuentas**) y aplicarlo en `android:label`,
`CFBundleDisplayName`, `CFBundleName` y `MaterialApp.title`.

**Complejidad: Low**

**Dependencias**
`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ¿cuál es el nombre comercial definitivo?

**Riesgo de regresión**
Ninguno (el `applicationId` **no** debe cambiar).

---

## M-25 · Actualizar el README

**Problema**
Contiene afirmaciones incorrectas.

**Evidencia**

| Afirmación | Realidad |
|---|---|
| *"La versión de esquema SQLite es 2"* | Es **4** |
| *"La migración desde V1 agrega área tratada, dosis y necesidad teórica"* | Describe solo v1→v2; hay dos tramos más |
| *"offline-first"* | Es **offline-only**: no hay servidor |
| `pubspec.yaml`: `description: "A new Flutter project."` | Plantilla sin personalizar |

**Solución recomendada**
Corregir, y añadir la sección de **configuración inicial** (el orden obligatorio de creación
de datos), que hoy falta y es imprescindible para quien instala la app por primera vez.
Enlazar a `docs/`.

**Complejidad: Low**

**Riesgo de regresión**
Ninguno.

---

## M-26 · Limpiar dependencias no usadas

**Problema**
Dos dependencias declaradas y nunca importadas.

**Evidencia**
- `cupertino_icons`: ningún `import`; toda la iconografía es `Icons.*` de Material.
- `fake_async`: ningún `import` en `test/`.

**Solución recomendada**
Eliminar ambas de `pubspec.yaml`, o empezar a usar `fake_async` (haría los widget tests más
rápidos y deterministas que el actual `runAsync` + `pump`).

**Complejidad: Low**

**Riesgo de regresión**
Muy bajo; `flutter analyze` lo confirmaría.

---

## M-27 · Trazabilidad de autoría

**Problema**
No se registra **quién** creó cada operación.

**Evidencia**
Ninguna tabla tiene `created_by` ni equivalente. `account_transactions.person_id` indica a
quién afecta, no quién la introdujo.

**Impacto**
Bajo si un solo operador; **medio-alto si el dispositivo se comparte**, porque en un sistema
que maneja deudas entre familiares la falta de trazabilidad puede volverse un problema de
confianza.

**Solución recomendada**
Columna `created_by_person_id` en `purchases`, `applications`, `transfers` y
`account_transactions`, con un selector de operador (o un ajuste persistente de "quién está
usando la app"). **Da auditoría sin necesidad de implementar autenticación.**

**Complejidad: Medium** (requiere migración de esquema)

**Dependencias**
`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ¿el dispositivo lo usa una persona o varias?

**Riesgo de regresión**
Bajo si las columnas son nullable.

---

## M-28 · Decidir el futuro de la plataforma web

**Problema**
`web/` existe y `.metadata` declara la plataforma, pero **la app no funciona en navegador**.

**Evidencia**
`AppDatabase._platformFactory()` en `kIsWeb` cae a `mobile.databaseFactory`, que no funciona
en web. Y tres archivos importan `dart:io`, inexistente en web.

**Impacto**
Bajo, pero genera una expectativa falsa: alguien podría intentar `flutter build web` y
obtener un artefacto roto.

**Solución recomendada**
Una de dos, explícitamente:
- **Retirar** la plataforma web (borrar `web/`, quitarla de `.metadata`), o
- **Documentar** que es trabajo futuro y qué haría falta (`sqflite_common_ffi_web` o
  `drift` con WASM, y abstraer el acceso a archivos).

**Complejidad: Low** (retirar) / **High** (soportarla de verdad)

**Dependencias**
`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: ¿es la web un objetivo del producto?

**Riesgo de regresión**
Ninguno.

---

## Resumen por complejidad y prioridad

| | Low | Medium | High |
|---|---|---|---|
| **P0** | M-01, M-02 | M-03, M-04 | — |
| **P1** | M-06, M-07, M-09, M-10 | M-05, M-08, M-11 | — |
| **P2** | M-12, M-14, M-15, M-18, M-20, M-21 | M-13, M-19 | M-16, M-17 |
| **P3** | M-22, M-23, M-24, M-25, M-26, M-28 | M-27 | — |
