# 22 — Testing

> **Actualizado tras la fase de estabilización.** La suite pasó de **44 a 91 tests**. Lo que
> sigue describe el estado actual; los huecos que se cerraron se marcan como tales.

## Estado verificado

```
flutter test  →  91 tests, TODOS EN VERDE
```

### Archivos añadidos en la estabilización

| Archivo | Tests | Cubre |
|---|---:|---|
| `reports_test.dart` | 17 | Reportes, dashboard, inventario y perfiles (cierra T-03) |
| `backup_service_test.dart` | 10 | Validación y restauración de respaldos (cierra T-05) |
| `app_log_test.dart` | 6 | Registro de diagnóstico |
| `schema_equivalence_test.dart` | 4 | Equivalencia de esquema nuevo ↔ migrado (cierra T-01) |
| `navigation_test.dart` | 4 | Navegación real sobre `AgroApp` (cierra T-02) |
| `error_states_test.dart` | 3 | Un error nunca se muestra como carga (cierra T-04) |
| `destructive_actions_test.dart` | 3 | Confirmación antes de revertir |

**Los cinco huecos críticos T-01 … T-05 identificados en la auditoría anterior están
cerrados.**

13 archivos, 1 972 líneas de test frente a 8 250 de producción: una **ratio de 0,24**, que
para un proyecto sin cultura formal de testing es razonable, aunque baja para el tipo de
lógica que contiene (contabilidad y costeo).

## Inventario por archivo

| Archivo | Tests | Clasificación | Líneas |
|---|---:|---|---:|
| `repository_test.dart` | 11 | Integración (SQLite en memoria) | 408 |
| `v5_domain_test.dart` | 6 | Integración | 305 |
| `v4_repository_test.dart` | 4 | Integración | 164 |
| `regression_widget_test.dart` | 4 | Widget + repositorio real | 194 |
| `money_test.dart` | 3 | **Unitario puro** | 40 |
| `adaptive_picker_test.dart` | 2 | Widget aislado | 57 |
| `back_navigation_test.dart` | 2 | Widget (arnés replicado) | 111 |
| `migration_test.dart` | 2 | Integración con archivo real | 115 |
| `widget_test.dart` | 2 | Widget (app completa) | 35 |
| `e2e_scenario_test.dart` | 1 | End-to-end de dominio | 180 |
| `e2e_v5_test.dart` | 1 | End-to-end de dominio | 188 |
| `responsive_v5_test.dart` | 1 × 5 tamaños | Widget responsive | 77 |
| `volume_test.dart` | 1 | Rendimiento / volumen | 98 |

## Estrategia de test observada

### Sin mocks, con base de datos real en memoria

```dart
final database = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
final repo = AgroRepository(database);
addTearDown(database.close);
```

**Esta es la decisión más importante de la estrategia de test del proyecto, y es acertada.**

Ventajas reales que aporta:
- Se ejercitan las **restricciones de SQLite de verdad** (`CHECK`, `UNIQUE`, FK con
  `PRAGMA foreign_keys = ON`), no una simulación.
- Se valida el **comportamiento transaccional real**, incluido el rollback.
- El SQL crudo (~35 `rawQuery` complejas) se ejecuta contra un motor real: un error de
  sintaxis o de nombre de columna se detecta.
- Sin mocks que mantener sincronizados con la implementación.
- Corre en **cualquier escritorio, sin emulador**, en 13 segundos.

Los widget tests van más allá: inyectan ese repositorio real en la UI mediante
`repositoryProvider.overrideWithValue(repo)`. Son, de hecho, **tests de integración de
punta a punta sin dispositivo**.

### Aserciones sobre valores exactos

Los tests no se conforman con "no lanza excepción"; comprueban cifras concretas:

```dart
expect(application['total_cost_bob_minor'], 545000);              // Bs 5.450,00
expect(consumptions.map((r) => r['cost_bob_minor']),
       containsAll([200000, 345000]));                            // los dos tramos FIFO
expect(items.map((row) => row['quantity_base']), [10000, 15000]); // reparto entre lotes
expect(purchaseRow['total_bob_minor'], 5760000);
expect(plan['required_quantity_base'], 42000);
expect(balance['opening_balance'], 100000);
```

Esto es lo que convierte la suite en una **red de seguridad real** para el motor de costeo.

## Cobertura por área funcional

| Área | Cobertura | Detalle |
|---|:--:|---|
| **Aritmética monetaria** | 🟢 Excelente | 3 tests con valores exactos: FX 7, FX 12,10 y BOB sin FX |
| **Costeo FIFO** | 🟢 Excelente | Consumo multi-lote con costos distintos, verificado tramo a tramo |
| **Compras multiproducto y multi-moneda** | 🟢 Excelente | 1 factura con 3 productos BOB/USD; otra con 12 líneas |
| **Distinción familiar vs tercero** | 🟢 Excelente | Dos tests dedicados que confirman el modelo de deuda |
| **Reversiones** | 🟢 Buena | Aplicación (restaura stock y cargo), compra bloqueada por consumo, transferencia con reapertura de plan |
| **Atomicidad transaccional** | 🟢 Excelente | 3 tests de rollback: compra con persona inexistente, transferencia multiproducto insuficiente, transferencia simple insuficiente |
| **Campañas** | 🟢 Buena | Unicidad de activa, conflicto tipado, continuidad de stock y deuda al cambiar |
| **Transferencias FIFO** | 🟢 Excelente | Multi-lote, multiproducto, conservación de costo y de físico total |
| **Duplicados** | 🟢 Buena | Un test cubre aplicación, plan y transferencia a la vez |
| **Planificación** | 🟡 Parcial | Se verifica el cálculo de necesidad y la unidad; no hay test del "comprometido"/"proyectado" |
| **Migraciones** | 🟡 Parcial | Se prueban **v1→v2** y **v3→v4 (solo transferencias)**. Sin cobertura de v2→v3 ni de propiedades de índice. Ver T-01 |
| **Pagos a proveedor** | 🟡 Parcial | Se verifica que se registra; **no se prueba el tope de RN-16** |
| **Imputación de pagos** | 🟡 Parcial | Un test del cruce entre campañas; no se prueba el reparto entre varios cargos ni el sobrepago |
| **Formularios (UI)** | 🟡 Parcial | 4 tests de regresión sobre casos puntuales, no sobre los flujos completos |
| **Responsive** | 🟢 Buena | 5 resoluciones × `textScaleFactor` 1.4, más un test a 360 px × 1.6 |
| **Navegación** | 🔴 **Insuficiente** | Ver hueco crítico abajo |
| **Manejo de errores en la UI** | 🔴 Ausente | Ningún test comprueba que un error se muestre correctamente |
| **Reportes** | 🔴 Ausente | `farmCostReport`, `productCostReport`, `campaignCloseSummary`, `dashboard` sin tests |
| **Backup / imágenes** | 🔴 Ausente | `exportBackup` y `storeInvoiceImage` sin tests |

## Huecos críticos

### 🔴 T-01 · Las migraciones están probadas solo de forma superficial

`migration_test.dart` contiene dos tests, y **ambos sí prueban migraciones reales**:

| Test | Qué hace | Qué verifica |
|---|---|---|
| *"migración V1 a V2 conserva filas y agrega planificado vs real"* | Crea una base v1 con una sola tabla (`application_items`, 5 columnas) y una fila | Aparecen `treated_area_m2`, `dose_base_per_ha`, `theoretical_quantity_base`; la fila conserva `quantity_base` |
| *"migración V3 a V4 agrega items de transferencia sin perder historial"* | Crea una base v3 con `transfers` y `transfer_lot_items` y una transferencia | La fila `id=9` sobrevive; `transfer_lot_items` gana `transfer_item_id`; existe la tabla `transfer_items` |

Lo que **no** cubren:

1. **La migración v2 → v3 no se prueba**: creación de `payment_allocations`, los siete
   índices condicionales y —lo más delicado— el `UPDATE` correctivo que cierra campañas
   activas duplicadas dejando solo la más reciente.
2. **La mitad del tramo v4 queda fuera**: el test solo cubre la parte de transferencias.
   No se verifica el `ALTER TABLE application_items` (`unit`, `variance_quantity_base`,
   `fifo_estimated_cost_bob_minor`, `notes`) ni el de `applications`
   (`treated_area_m2`, `plan_id`).
3. **No se comparan propiedades de índice**: los tests comprueban que las *tablas* y las
   *columnas* existen, pero nunca consultan `PRAGMA index_list` / `PRAGMA index_info`.

Ese tercer punto es el que importa: la divergencia `CREATE UNIQUE INDEX` vs `CREATE INDEX`
en `idx_application_item_unique` e `idx_plan_item_unique` (documentada en
[10_DATA_MODEL](10_DATA_MODEL.md)) **no la detectan estos tests**, porque ninguno compara el
esquema resultante de una migración con el de una base creada desde cero. Un solo test que
hiciera esa comparación —tablas, columnas **e índices con su atributo `unique`**— habría
encontrado el defecto.

Una migración defectuosa corrompe datos reales de usuarios y no hay forma de deshacerlo, así
que reforzar aquí es prioridad **P0** en [29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md).

### 🔴 T-02 · La navegación real no está probada

`back_navigation_test.dart` **no prueba ninguna pantalla del proyecto**. Prueba un widget
llamado `_DirtyFormHarness`, definido en el propio archivo de test, que **replica** el
contrato `PopScope` de los formularios:

```dart
/// Réplica aislada del contrato PopScope compartido por los formularios V5.
class _DirtyFormHarness extends StatefulWidget { ... }
```

Es un test del *patrón*, no del *código*. Si un formulario real dejara de aplicar ese
patrón, el test seguiría en verde.

**Y hay una consecuencia concreta y demostrada**: el fallo de navegación
`go('/compras/nueva')` → botón atrás → *"You have popped the last page off of the stack"*
(ver [08_NAVIGATION](08_NAVIGATION.md) y [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md)) **no lo
detecta ningún test**, porque:

- `widget_test.dart` monta `AgroApp` pero solo comprueba que se ven las etiquetas de
  navegación;
- ningún test recorre FAB → "Compra" → atrás;
- los tests de formularios los montan **directamente** con `MaterialApp(home: PlanFormScreen())`,
  fuera del `GoRouter`, por lo que nunca ejercitan el enrutado real.

Durante esta auditoría bastó un test de ~30 líneas montando `AgroApp` completo para
reproducir el fallo. Prioridad **P0**.

### 🟡 T-03 · Reportes y agregados sin cobertura

Sin un solo test: `dashboard()`, `farmCostReport()`, `productCostReport()`,
`campaignCloseSummary()`, `inventorySummary()` en sus columnas derivadas
(`committed_base`, `projected_base`, `available_value_bob_minor`),
`personProfiles()`, `detailedStatement()`.

Son consultas SQL largas con `COALESCE`, subconsultas correlacionadas y `GROUP BY`. Es
exactamente el tipo de código donde un error es silencioso: **muestra un número equivocado
sin fallar**. El defecto de `productCostReport` con `WHERE` sobre `LEFT JOIN`
(ver [27](27_KNOWN_ISSUES.md)) es precisamente de esta clase.

### 🟡 T-04 · Sin cobertura de errores en la interfaz

Ningún test verifica que:
- un `BusinessRuleException` produzca un snackbar con el mensaje correcto;
- `friendlyError` limpie el prefijo;
- las pantallas muestren el `EmptyState` de error.

Es lo que permitió que pasaran desapercibidos los estados de error muertos de
`SettlementsScreen` y `PurchasesScreen`.

### 🟡 T-05 · Sin cobertura de sistema de archivos

`exportBackup()` y `storeInvoiceImage()` no tienen tests, pese a ser probables con
directorios temporales (como ya hace `migration_test.dart`).

### 🟡 T-06 · Sin medición de cobertura

No hay `coverage/`, ni informe, ni umbral. `flutter test --coverage` funcionaría, pero nadie
lo ejecuta de forma sistemática (no hay CI).

## Calidad de los tests existentes

### Fortalezas

1. **Nombres descriptivos en español, orientados al comportamiento**:
   *"asignación familiar no crea deuda; uso y pago parcial sí"*,
   *"un item insuficiente revierte toda transferencia multiproducto"*.
   Se leen como especificación ejecutable.
2. **Verifican efectos secundarios, no solo retornos**: comprueban filas de
   `inventory_movements`, `payment_allocations`, `application_consumptions`.
3. **Limpieza correcta**: `addTearDown(database.close)` sistemático; `migration_test`
   borra su directorio temporal.
4. **Casos de rollback explícitos**: tres tests dedicados a que un fallo no deje nada escrito.
5. **`e2e_v5_test.dart` prueba a escala**: 20 productos, una factura de 12 líneas,
   transferencia, plan y aplicación en un solo recorrido.
6. **`volume_test.dart`** inserta 100 productos, 1 000 aplicaciones y 300 compras mediante
   `batch` y verifica que las consultas siguen acotadas.
7. **`responsive_v5_test.dart`** cubre 5 resoluciones (incluida una apaisada de 800×420) con
   `textScaleFactor: 1.4`, y `widget_test.dart` añade 360 px con 1.6 — buena atención a la
   accesibilidad por tamaño de fuente.

### Debilidades

1. **`back_navigation_test.dart` prueba una réplica, no el código real** (T-02).
2. **Sincronización artesanal en widget tests**: el helper `settle` usa
   `runAsync(Future.delayed(150ms))` + 12 `pump(50ms)`, y en un punto un
   `Future.delayed(500ms)`. Funciona, pero es frágil y lento: es lo que hace que
   `regression_widget_test` tarde varios segundos.
3. **Un test con nombre dinámico**: `'formularios adaptables ${size.width}x${size.height}'`
   dentro de un bucle. Es útil, pero rompe herramientas que agregan por nombre literal.
4. **Sin tests parametrizados de aritmética**: `money_test.dart` tiene tres casos fijos.
   Casos de redondeo al límite (`.005`), cantidades muy grandes o FX con muchos decimales no
   están cubiertos.
5. **`widget_test.dart` usa la base de datos real del sistema** (monta `AgroApp` sin
   override). Funciona porque solo comprueba etiquetas, pero es una dependencia oculta del
   entorno.
6. **Sin fixtures compartidas**: cada archivo reconstruye su escenario. Hay duplicación
   evidente entre `repository_test`, `v4_repository_test` y `v5_domain_test` (mismo patrón
   de `setUp` con persona + proveedor + campaña + producto + chaco).

## Lo que la suite sí garantiza hoy

Un desarrollador que toque el motor de costeo, la contabilidad o las reversiones **tiene
una red de seguridad real**: si rompe el FIFO, el cálculo de deuda, la atomicidad o el
tratamiento de moneda, la suite se pone en rojo con cifras concretas.

## Lo que la suite NO garantiza

- Que una migración desde una instalación existente funcione (T-01).
- Que la navegación real de la app funcione (T-02) — **y de hecho no funciona en un caso**.
- Que los reportes muestren cifras correctas (T-03).
- Que los errores se presenten bien al usuario (T-04).
- Que el backup y las imágenes funcionen (T-05).

## Recomendaciones (para fases posteriores, no para esta)

Por orden de valor:

1. **Test de equivalencia de esquema**: migrar una base v1, v2 y v3 hasta v4 y comparar el
   resultado (`sqlite_master` + `PRAGMA index_list` con su atributo `unique` +
   `PRAGMA table_info`) contra el de una base creada desde cero. Detectaría la divergencia
   de índices actual y prevendría la próxima. Es más valioso que añadir tests puntuales por
   tramo.
2. **Test de navegación sobre `AgroApp` completo**: FAB → cada destino → atrás, verificando
   `tester.takeException()` nulo. Detectaría el defecto P0 actual.
3. **Tests de reportes** con datos conocidos y cifras esperadas.
4. **Sustituir `_DirtyFormHarness`** por los formularios reales.
5. **Extraer una fixture compartida** para reducir la duplicación de `setUp`.
6. **Medir cobertura** y establecer un umbral en CI.
