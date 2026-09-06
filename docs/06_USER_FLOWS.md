# 06 — Flujos de usuario

Reconstruidos a partir del código de las pantallas y del repositorio. Cada flujo indica su
punto de entrada real y las llamadas concretas que ejecuta.

---

## UF-01 · Apertura de la aplicación

```mermaid
flowchart LR
    A["main()"] --> B["ProviderScope"]
    B --> C["AgroApp / MaterialApp.router"]
    C --> D["GoRouter initialLocation '/'"]
    D --> E["AppShell + DashboardScreen"]
    E --> F["dashboard() + inventorySummary(5) + applications(5) + topSettlements(5) + campaigns()"]
```

1. **Entrada**: `main.dart` → `WidgetsFlutterBinding.ensureInitialized()` → `runApp`.
2. **No hay splash screen propia** (solo la `LaunchTheme` nativa de Android/iOS).
3. **No hay onboarding, ni comprobación de sesión, ni migración visible al usuario.**
4. La base de datos se abre **de forma perezosa**: `AppDatabase._open()` se dispara con la
   primera consulta, que es la del dashboard. Las migraciones `onUpgrade` corren aquí, de
   forma invisible.
5. **Estado loading**: `CircularProgressIndicator` centrado mientras resuelve el `Future`.
6. **Estado error**: si la apertura de la BD o cualquier consulta falla,
   `EmptyState(icon: error_outline, message: friendlyError(...))`.
7. **Finalización**: dashboard poblado, o con la tabla de inventario vacía y el banner
   "Campaña activa: Sin campaña activa".

> **Primera ejecución real**: la base está vacía. No hay datos semilla. El dashboard se ve
> a ceros y **no hay ninguna guía que lleve al usuario a crear su primera campaña**. Es la
> mayor carencia de UX detectada. Ver [20](20_BUILD_AND_CONFIGURATION.md) y [29](29_IMPROVEMENT_AUDIT.md).

---

## UF-02 · Configuración inicial (orden obligatorio)

El orden **no es opcional**: las dependencias de claves foráneas y las guardias de campaña
lo imponen.

```mermaid
flowchart TD
    S(["Base vacía"]) --> P["1. Crear personas<br/>(al menos 1 ADMIN + 1 FAMILY/THIRD_PARTY)"]
    P --> C["2. Crear campaña<br/>(la primera queda ACTIVE automáticamente)"]
    P --> F["3. Crear chacos<br/>(requiere propietario)"]
    C --> PR["4. Crear productos"]
    PR --> SU["5. Crear proveedores"]
    SU --> OK(["Listo para operar"])
    F --> OK
```

- **Punto de entrada**: `/catalogos` (desde Operaciones → "Administrar datos").
- **Regla que fuerza el orden**: `addFarm` requiere `ownerId` válido (FK a `persons`);
  `confirmPurchase`, `addPlanMulti` y `confirmApplication` llaman `_ensureCampaignActive`.
- **Detalle importante**: `addCampaign` (`agro_repository.dart:74-88`) cuenta las campañas
  activas dentro de una transacción; si no hay ninguna, la nueva nace `ACTIVE`; si ya hay
  una, nace `PLANNED`. **La primera campaña que se crea queda activa sin intervención.**
- **Sin ADMIN no se puede pagar al proveedor**: `PurchasesScreen._pay` avisa "Registra una
  persona administradora para pagar al proveedor."

---

## UF-03 · Planificar una aplicación

**Entrada**: `/planificacion` → botón "Nuevo plan" (o FAB "Nuevo" → "Planificación").

```mermaid
flowchart TD
    A["PlanningScreen.add()"] --> B{"activeCampaign() != null?"}
    B -->|no| E1["showError: 'Active una campaña antes de planificar.'"]
    B -->|sí| C["push /planificacion/nueva"]
    C --> D["PlanFormScreen._load(): activeCampaign + farms + products"]
    D --> F["Usuario elige chaco"]
    F --> G["Precarga área en ha desde farms.area_m2/10000<br/>+ personStockSummary(propietario)"]
    G --> H["Agrega productos y teclea dosis"]
    H --> I["Por línea muestra: necesita X · stock Y · cubierto/comprar Z"]
    I --> J["Guardar planificación"]
    J --> K{"chaco y >=1 producto?"}
    K -->|no| E2["showError: 'Seleccione chaco y al menos un producto.'"]
    K -->|sí| L{"todas las dosis > 0?"}
    L -->|no| E3["showError: 'Todas las dosis deben ser mayores a cero.'"]
    L -->|sí| M["addPlanMulti(...)"]
    M --> N["INSERT application_plans + application_plan_items"]
    N --> O["pop(true) → PlanningScreen.refresh()"]
```

- **Validaciones de UI**: chaco seleccionado, ≥ 1 producto, dosis > 0, producto no repetido
  ("El producto ya está agregado.").
- **Validaciones de repositorio** (defensa en profundidad, mismas reglas): área > 0, ítems
  no vacíos, productos únicos, dosis > 0, campaña activa.
- **Cambio de estado**: plan creado con `status = 'PLANNED'`; el inventario pasa a mostrar
  esa cantidad como **"comprometida"** en `inventorySummary` y en el detalle de producto.
- **Errores posibles**: campaña inactiva, dosis inválida, producto duplicado.
- **Fin**: vuelve a la lista de planificación, agrupada por plan, con botón "Aplicar".

---

## UF-04 · Registrar una compra

**Entrada**: `/compras` → "Nueva compra"; o Operaciones → "Registrar compra";
o FAB "Nuevo" → "Compra" **(esta última ruta tiene un defecto confirmado, ver abajo)**.

```mermaid
flowchart TD
    A["PurchaseFormScreen"] --> B["_loadCatalogs(): suppliers + campaigns + products + people<br/>preselecciona la campaña ACTIVE"]
    B --> C["Sección Factura: proveedor, campaña, nº, foto"]
    C --> D["Sección Productos: N líneas"]
    D --> D1["Por línea: producto, cantidad, moneda, precio, TC si USD"]
    D1 --> D2["Por línea: 1..N asignaciones persona + cantidad"]
    D2 --> D3["Subtítulo en vivo: cantidad · subtotal · pendiente por asignar"]
    D3 --> E["Sección Pago al proveedor (switch + pagador ADMIN)"]
    E --> F["Confirmar"]
    F --> G{"validaciones de UI"}
    G -->|falla| E1["showError específico por ítem"]
    G -->|ok| H["storeInvoiceImage() si hay foto"]
    H --> I["confirmPurchase(PurchaseDraft)"]
    I --> J["TRANSACCIÓN: purchases → purchase_items → allocations → lots → movements → cargos"]
    J --> K{"payProvider?"}
    K -->|sí| L["addProviderPayment(total) — TRANSACCIÓN SEPARADA"]
    K -->|no| M["pop(true)"]
    L --> M
    M --> N["PurchasesScreen refresca + snackbar de éxito"]
```

**Validaciones de UI, en orden** (`purchase_form_screen.dart` `_confirm`):

1. Proveedor y campaña seleccionados.
2. Al menos una línea.
3. Por línea: producto, cantidad > 0 y precio > 0 → *"Complete producto, cantidad y precio del ítem N."*
4. Por línea USD: TC > 0 → *"Seleccione un tipo de cambio para el ítem N."*
5. Toda asignación tiene persona → *"Seleccione la persona de cada asignación."*
6. Suma asignada == cantidad → *"La suma asignada supera…"* o *"Falta asignar parte…"* (mensaje distinto según el signo).
7. Si el switch de pago está activo, pagador seleccionado.

**Cambios de estado y almacenamiento**: ver [F-04 en 05_FEATURES](05_FEATURES.md).
Para el **familiar** no se crea deuda; para el **tercero** sí, por el importe de su asignación.

**Protección de salida**: `PopScope(canPop: !dirty && !saving)` → diálogo
"¿Descartar cambios?" con "Seguir editando" / "Descartar".

> ⚠️ **Defecto confirmado y reproducido**: si se entra por el FAB "Nuevo" → "Compra", el
> `AppShell` usa `context.go('/compras/nueva')`, que **reemplaza toda la pila**. Al pulsar
> atrás, `Navigator.pop()` dispara la aserción de go_router
> *"You have popped the last page off of the stack, there are no pages left to show"* y la
> pantalla queda en blanco. Entrando desde `/compras` (que usa `context.push`) no ocurre.
> Detalle y reproducción en [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md).

---

## UF-05 · Registrar una aplicación (desde cero)

**Entrada**: `/aplicaciones` → "Registrar".

```mermaid
flowchart TD
    A["ApplicationsScreen.add()"] --> B{"activeCampaign()?"}
    B -->|no| C["Diálogo 'Falta una campaña activa'<br/>botón → /catalogos"]
    B -->|sí| D["push /aplicaciones/nueva"]
    D --> E["_load(): people (sin ADMIN) + farms + campaña activa"]
    E --> F["Elegir persona"]
    F --> G["availableProductsForOwner(persona) → stock con lotes y costo FIFO"]
    G --> H["Elegir chaco (filtrado al propietario) → precarga área en ha"]
    H --> I["Agregar productos de la mezcla"]
    I --> J["Por producto: dosis y cantidad real"]
    J --> K["estimateFifoCost() en vivo al teclear cantidad"]
    K --> L["Confirmar aplicación"]
    L --> M{"persona, chaco y >=1 línea?"}
    M -->|no| E1["'Seleccione persona, chaco y al menos un producto.'"]
    M -->|sí| N{"cada real > 0 y <= stock?"}
    N -->|no| E2["'Revise las cantidades: todos los productos deben tener stock suficiente.'"]
    N -->|sí| O["confirmApplication(ApplicationDraft)"]
    O --> P["TRANSACCIÓN: applications → items → consumo FIFO por lote → movements(APPLICATION_OUT)"]
    P --> Q{"política = BY_ACTUAL_USAGE?"}
    Q -->|sí| R["INSERT account_transactions USAGE_CHARGE"]
    Q -->|no| S["sin cargo"]
    R --> T["pop(true) + snackbar 'Aplicación multiproducto confirmada.'"]
    S --> T
```

**Comportamiento acoplado persona↔chaco**: al elegir un chaco cuyo propietario difiere de
la persona actual, `selectFarm` **cambia automáticamente la persona** al propietario y
recarga su stock. Al cambiar de persona, el chaco se limpia siempre.

**Detalle técnico observado**: la limpieza del chaco se decide con
`if (_farmOwner(farmId) != id) farmId = null;`, pero `_farmOwner` **siempre devuelve `null`**
(`application_form_screen.dart`), de modo que la condición es siempre verdadera. El efecto
neto es correcto, pero el método es código muerto engañoso. Ver [26](26_TECHNICAL_DEBT.md).

---

## UF-06 · Aplicar desde un plan (flujo preferente)

**Entrada**: `/planificacion` → expandir un plan → botón "Aplicar".
Navega a `/aplicaciones/nueva?planId=N` (con `context.push`).

```mermaid
sequenceDiagram
    participant U as Usuario
    participant P as PlanningScreen
    participant A as ApplicationFormScreen
    participant R as AgroRepository
    U->>P: pulsa "Aplicar" en un plan
    P->>A: push /aplicaciones/nueva?planId=N
    A->>R: activeCampaign()
    A->>R: planForApplication(N)
    R-->>A: filas del plan (chaco, propietario, área, productos, dosis, requerido)
    alt plan.campaign_id != campaña activa
      A-->>U: "El plan no pertenece a la campaña activa."
    end
    A->>A: precarga persona = propietario, chaco, área en ha
    A->>R: availableProductsForOwner(propietario)
    loop por cada producto del plan
      A->>A: crea línea con dosis y cantidad = requerido
      A->>R: estimateFifoCost(...)
    end
    U->>A: ajusta cantidades reales y confirma
    A->>R: confirmApplication(planId: N)
    R->>R: UPDATE application_plans SET status='COMPLETED'
    A-->>U: pop(true)
```

**Caso borde manejado**: si un producto del plan **no tiene stock**, el formulario igualmente
crea la línea con un stock ficticio de 0 (`available_base: 0`), para que el usuario vea el
producto planificado; al confirmar, la validación de cantidad ≤ stock lo bloqueará.

**Reversibilidad**: si la aplicación se revierte, `reverseApplication` devuelve el plan a
`PLANNED` (confirmado por test *"aplicación desde plan conserva líneas y completa/reabre el plan"*).

---

## UF-07 · Transferir stock entre personas

**Entrada**: `/transferencias` → "Nueva".

```mermaid
flowchart TD
    A["TransferFormScreen"] --> B["people() filtrando ADMIN"]
    B --> C["1. Origen"]
    C --> D["availableProductsForOwner(origen)<br/>crea un TextEditingController por producto, inicializado en '0'"]
    D --> E["2. Productos: teclear cantidad por fila<br/>(buscador si hay >= 8 productos)"]
    E --> F["3. Destino (excluye al origen)"]
    F --> G["Revisar y confirmar"]
    G --> H{"origen, destino distintos y >=1 cantidad > 0?"}
    H -->|no| E1["'Seleccione origen, destino y al menos una cantidad válida.'"]
    H -->|sí| I{"cada cantidad <= stock?"}
    I -->|no| E2["'Una cantidad supera el stock disponible.'"]
    I -->|sí| J["Diálogo resumen: De/A + lista de productos"]
    J -->|Revisar| E
    J -->|Confirmar| K["transferProductsFifo(items)"]
    K --> L["TRANSACCIÓN por producto: lotes FIFO → lote destino con parent_lot_id<br/>+ TRANSFER_OUT/TRANSFER_IN + transfer_lot_items"]
    L --> M["pop(true) → TransfersScreen.refresh()"]
```

- **Sin efecto contable**: transferir no genera cargos ni créditos.
- **Costo preservado**: el lote destino hereda `unit_cost_bob_minor_per_major_unit`,
  `currency_code`, `original_unit_price_minor`, `exchange_rate_scaled` y `acquired_date`
  del origen — por eso el orden FIFO se mantiene coherente tras la transferencia.
- **Atomicidad**: si cualquier producto no alcanza, no se mueve ninguno.

---

## UF-08 · Registrar un pago o adelanto de una persona

**Entrada**: `/liquidacion` → menú ⋮ de la persona → "Registrar pago" / "Registrar adelanto".

```mermaid
flowchart TD
    A["SettlementsScreen._record(person, advance)"] --> B["AlertDialog con campo 'Importe BOB'"]
    B --> C["parseMinor(texto) → centavos"]
    C --> D["addAccountPayment(personId, campaignId seleccionada, importe, advance)"]
    D --> E{"importe > 0?"}
    E -->|no| F["BusinessRuleException 'El importe debe ser mayor a cero.'"]
    E -->|sí| G["INSERT account_transactions tipo PAYMENT o ADVANCE, monto NEGATIVO"]
    G --> H["SELECT cargos pendientes de la persona ORDER BY fecha, id<br/>(sin filtrar por campaña)"]
    H --> I["INSERT payment_allocations hasta agotar el importe"]
    I --> J["_refresh() → saldos recalculados"]
```

**Comportamiento notable y confirmado por test**: la imputación **cruza campañas**. Un pago
registrado en la campaña 2 cancela primero la deuda más antigua, aunque sea de la campaña 1.
Es intencional (test *"saldo inicial cruza campañas y el pago se imputa a deuda antigua"*).

**Sobrepago**: si el importe supera la deuda total, el remanente **no se imputa** a ningún
cargo, pero **sí** queda registrado como asiento negativo, produciendo saldo a favor. La UI
lo etiqueta "Saldo a favor" y lo pinta en verde.

**Ausencia de validación**: no hay tope superior. Se puede registrar un pago de cualquier
magnitud. Ver [16](16_VALIDATIONS.md).

---

## UF-09 · Consultar el estado de cuenta de una persona

**Entradas**: `/liquidacion` → ⋮ → "Ver detalle cronológico"; o `/personas/:id` → pestaña "Cuenta".

1. `detailedStatement(personId, campaignId)` trae los asientos enriquecidos con `concept` y `farm_name`.
2. Si hay campaña seleccionada, `personCampaignBalance` aporta el `opening_balance`.
3. La UI acumula el saldo movimiento a movimiento y lo muestra bajo cada importe.
4. Iconografía por signo: naranja `+` para cargos, verde `−` para pagos/créditos.
5. **Empty**: "Sin movimientos." solo si no hay filas **y** el saldo inicial es 0.

---

## UF-10 · Revertir una operación

| Operación | Entrada | Confirmación previa | Guardias |
|---|---|---|---|
| Compra | `/compras` → ⋮ → "Revertir compra" | **Ninguna** | Lotes no consumidos y saldo de lote intacto |
| Aplicación | `/aplicaciones` → botón ↩ | **Ninguna** | Ninguna: siempre procede |
| Transferencia | `/transferencias` → botón ↩ | **Ninguna** | Lote destino sin movimientos posteriores |

```mermaid
flowchart TD
    A["Usuario pulsa revertir"] --> B["repo.reverseXxx(id, reason)"]
    B --> C{"guardias de integridad"}
    C -->|falla| D["catch → showError con el mensaje de negocio"]
    C -->|ok| E["TRANSACCIÓN"]
    E --> F["movimientos compensatorios de inventario"]
    F --> G["CREDIT_ADJUSTMENT con reversal_of_id"]
    G --> H["status='REVERSED' + reversed_at"]
    H --> I["refresh() de la lista"]
```

**Mensajes de guardia reales**:
- *"La compra tiene lotes consumidos. Revierta primero las aplicaciones relacionadas."*
- *"El lote fue transferido o ajustado; requiere reversión consistente previa."*
- *"El stock transferido ya tuvo movimientos. Reviértalos antes de continuar."*
- *"La aplicación ya fue revertida o no existe."*

**Riesgo de UX**: la ausencia de diálogo de confirmación en aplicaciones y transferencias
hace que un toque accidental sobre el icono ↩ ejecute una operación contable irreversible
desde la UI (no hay "des-revertir"). Ver [29](29_IMPROVEMENT_AUDIT.md).

---

## UF-11 · Cerrar una campaña y abrir la siguiente

```mermaid
flowchart TD
    A["/catalogos → pestaña Campañas"] --> B["⋮ → Cerrar (solo si status = ACTIVE)"]
    B --> C["campaignCloseSummary(id)"]
    C --> D["Diálogo con compras, aplicaciones, planes pendientes, saldo por cobrar<br/>+ aviso: 'El inventario físico no se elimina'"]
    D -->|Cancelar| A
    D -->|Cerrar campaña| E["closeCampaign(id): UPDATE status='CLOSED', end_date=now"]
    E --> F["Ya no hay campaña activa"]
    F --> G["⋮ → Activar sobre otra campaña"]
    G --> H{"¿hay otra ACTIVE?"}
    H -->|sí| I["CampaignConflictException → diálogo 'Cerrar y activar'"]
    H -->|no| J["activateCampaign: status='ACTIVE', end_date=NULL"]
    I -->|acepta| K["activateCampaign(closeCurrent: true)"]
    K --> J
```

**Qué sobrevive al cambio de campaña** (confirmado por el test *"catálogo, stock y deuda
permanecen al cambiar campaña"*):

- Catálogos completos.
- **Inventario físico**: los lotes y su saldo se conservan íntegros.
- **Deuda**: los saldos de las personas no se reinician.

**Qué cambia**: las nuevas compras, aplicaciones y planes se asocian a la nueva campaña, y
los reportes filtrados por campaña muestran solo lo nuevo. El "saldo inicial de campaña"
en el estado de cuenta expone lo arrastrado.

---

## UF-12 · Exportar backup

**Entrada**: `/liquidacion` → "Exportar backup".

1. `PRAGMA wal_checkpoint(FULL)` — vuelca el WAL al archivo principal.
2. Comprueba que `appDatabase.openedPath` no sea nulo ni `:memory:`.
3. Copia a `getDownloadsDirectory()` (o Documentos) como `agroquimicos_backup_<ISO>.db`.
4. Snackbar con la ruta completa.

**Fin del flujo**: no hay compartir, ni subir, ni verificar. El usuario debe encontrar el
archivo por sí mismo. **No existe el flujo inverso de restauración.**

---

## Flujos que NO existen

Buscados y no encontrados en el código: registro de usuario, login, recuperación de
contraseña, logout, edición de perfil propio, onboarding, sincronización, resolución de
conflictos, actualización forzada de versión, calificación en tienda, soporte/contacto,
términos y condiciones, exportación selectiva, restauración de backup.

---

# Actualización 2026-09-06 — Flujos afectados por el cierre de la baseline

## Aplicar un plan (una sola vez)

```
Operaciones -> Planificación
  la lista muestra sólo planes PENDIENTES
  tocar la fila -> se despliega -> "Aplicar este plan"
    -> formulario de aplicación precargado (persona, chaco, área, productos, dosis)
    -> Confirmar aplicación
      -> aplicación creada
      -> el plan pasa a APPLIED
      -> al volver, la lista se recarga y el plan YA NO ESTÁ
  "Mostrar planes aplicados" -> aparece marcado "Aplicado", sin acción de aplicar
```

Si se intenta aplicar otra vez por cualquier vía —pantalla desactualizada, doble toque, llamada
indirecta— el repositorio lo rechaza: *"Este plan ya fue aplicado y no puede volver a
aplicarse. Cree un plan nuevo si necesita repetir la aplicación."* No se crea una segunda
aplicación ni se gasta stock.

**Revertir la aplicación no devuelve el plan a pendiente.** Para repetir la planificación se
crea un plan nuevo.

## Cerrar una campaña (irreversible)

```
Operaciones -> Administrar datos -> Campañas -> menú de la campaña ACTIVA -> Cerrar
  -> confirmación que declara:
       periodo desde qué fecha
       compras y aplicaciones registradas
       planes pendientes
       saldo por cobrar
       que dejará de admitir compras, aplicaciones, transferencias y planes
       que NO podrá reactivarse desde la aplicación
  -> "Cerrar definitivamente" (en color de acción irreversible)
     -> la campaña queda Cerrada, con su rango de fechas
     -> su menú pasa a ofrecer sólo "Editar"
```

Sólo una campaña `PLANNED` ofrece "Activar". Para seguir operando se crea una campaña nueva.

## Respaldar y restaurar con fotografías

```
Cuentas -> icono de carpeta -> Exportar respaldo
  -> archivo .agrobackup en la carpeta de descargas de la aplicación
  -> el acuse dice cuántas fotografías incluye
  -> si alguna factura ya no tiene su foto en el teléfono, se avisa (no se oculta)

Cuentas -> icono de carpeta -> Restaurar respaldo
  -> lista de respaldos disponibles (contenedores nuevos y .db históricos)
  -> elegir uno -> la confirmación declara ANTES de aceptar:
       versión de esquema
       si trae fotografías y cuántas, o que es formato histórico y no las trae
       que TODOS los datos actuales se reemplazan
       que se guardará una copia de los datos actuales
  -> Restaurar
     -> base restaurada, fotografías devueltas a su carpeta, rutas reapuntadas
     -> el acuse indica cuántas fotografías se restauraron y dónde quedó la copia previa
     -> si hubo discrepancias, se muestran
     -> el historial de compras abre la fotografía restaurada
```

Ante cualquier fallo a mitad, se deshace **el conjunto**: no queda una base nueva con las fotos
viejas ni al revés.

## Crear una entrada de catálogo

```
Operaciones -> Administrar datos -> elegir sección
  -> "Agregar persona" / "chaco" / "producto" / "proveedor" / "campaña"
     (una sola acción primaria: en esta ruta no hay FAB)
  -> Guardar con un campo obligatorio vacío
     -> el campo se marca y aparece el motivo BAJO él
     -> el diálogo NO se cierra y NO se escribe nada
```
