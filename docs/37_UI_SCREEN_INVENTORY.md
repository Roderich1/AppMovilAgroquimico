# 37 — Inventario de pantallas y cobertura de la auditoría

Inventario **real** de vistas, obtenido de las 17 rutas declaradas en `lib/app.dart` y
verificado recorriendo la aplicación sobre el emulador Pixel 8.

## 1. Pantallas

| Screen ID | Ruta | Pantalla | Punto de entrada real | Datos necesarios | Probada |
|---|---|---|---|---|:--:|
| UI-01 | `/` | `DashboardScreen` | Ruta inicial · pestaña **Inicio** | Inventario, aplicaciones, saldos, campaña activa | ✅ |
| UI-02 | `/operaciones` | `OperationsScreen` | Pestaña **Operaciones** | Ninguno (estática) | ✅ |
| UI-03 | `/catalogos` | `CatalogsScreen` | Operaciones → *Administrar datos* | 5 catálogos | ✅ |
| UI-04 | `/planificacion` | `PlanningScreen` | Operaciones → *Planificar aplicación* · FAB → *Planificación* | Planes + campañas | ✅ |
| UI-05 | `/planificacion/nueva` | `PlanFormScreen` | Planificación → **Nuevo plan** | Campaña activa, chacos, productos, stock | ✅ |
| UI-06 | `/compras` | `PurchasesScreen` | Operaciones → **Compras** *(añadido al corregir UIBUG-002)* | Compras, personas | ✅ |
| UI-07 | `/compras/nueva` | `PurchaseFormScreen` | Operaciones → *Registrar compra* · FAB → *Compra* | Proveedores, campañas, productos, personas | ✅ |
| UI-08 | `/aplicaciones` | `ApplicationsScreen` | Operaciones → *Registrar aplicación* · FAB → *Aplicación* · Inicio → *Ver todos* | Aplicaciones + campaña activa | ✅ |
| UI-09 | `/aplicaciones/nueva` | `ApplicationFormScreen` | Aplicaciones → **Registrar** · Planificación → **Aplicar** | Campaña activa, personas, chacos, stock | ✅ |
| UI-10 | `/liquidacion` | `SettlementsScreen` | Pestaña **Cuentas** · FAB → *Pago* · Inicio → *Ver todos* | Saldos, campañas, reportes | ✅ |
| UI-11 | `/inventario` | `InventoryScreen` | Pestaña **Inventario** · Inicio → *Ver todos* | Resumen de inventario | ✅ |
| UI-12 | `/inventario/:id` | `InventoryDetailScreen` | Inventario → fila · Inicio → fila de la tabla | Producto con lotes | ✅ |
| UI-13 | `/personas` | `PersonsScreen` | Pestaña **Personas** | Perfiles | ✅ |
| UI-14 | `/personas/:id` | `PersonDetailScreen` | Personas → fila | Perfil + 5 consultas | ✅ |
| UI-15 | `/chacos/:id` | `FarmLogbookScreen` | Persona → pestaña **Chacos** → fila (**única vía**) | Bitácora del chaco | ✅ |
| UI-16 | `/transferencias` | `TransfersScreen` | Operaciones → *Transferir inventario* · FAB → *Transferencia* | Transferencias | ✅ |
| UI-17 | `/transferencias/nueva` | `TransferFormScreen` | Transferencias → **Nueva** | Personas + stock por persona | ✅ |

**17 de 17 pantallas auditadas** (actualizado el 2026-09-05).

> En la auditoría original eran 16 de 17: UI-06 no podía auditarse porque **no existía ninguna
> forma de llegar a ella**, lo cual era en sí mismo el hallazgo UIBUG-002. Corregido ese
> defecto, la pantalla se auditó por completo —historial, visor de factura, pago a proveedor y
> reversión— y el resultado está en
> [`45_UI_AUDIT_FINAL_VERIFICATION.md` §5](45_UI_AUDIT_FINAL_VERIFICATION.md).

### Vistas secundarias auditadas

No son rutas, pero sí superficies con lógica propia:

| Vista | Dónde | Probada |
|---|---|:--:|
| Hoja del FAB "Nuevo" (5 accesos) | Global | ✅ |
| Hoja selectora de entidad (`AdaptiveEntityPicker`) | 4 formularios | ✅ |
| Diálogo *Nuevo producto* / *Nueva persona* / … | `/catalogos` | ✅ |
| Menú ⋮ de catálogo (Editar / Archivar / Activar / Cerrar) | `/catalogos` | ✅ |
| Diálogo *Cambiar campaña activa* | `/catalogos` | ✅ |
| Menú ⋮ de persona (detalle / pago / adelanto) | `/liquidacion` | ✅ |
| Diálogo *Ver detalle cronológico* | `/liquidacion` | ✅ |
| Diálogo *Registrar pago* / *Registrar adelanto* | `/liquidacion` | ✅ |
| Menú de copias de seguridad (Exportar / Restaurar) | `/liquidacion` | ✅ |
| Diálogo *Confirmar transferencia* | `/transferencias/nueva` | ✅ |
| Diálogo *¿Revertir esta transferencia?* | `/transferencias` | ✅ |
| Diálogo *¿Descartar cambios?* | 4 formularios | ✅ |
| Visor de factura (`InteractiveViewer`) | `/compras` | ✅ *(alcanzable desde 2026-09-05)* |
| Diálogo *Registrar pago a proveedor* | `/compras` | ✅ *(alcanzable desde 2026-09-05)* |
| Diálogo *Falta una campaña activa* | `/aplicaciones` | ❌ no provocable con el dataset |

## 2. Matriz de cobertura visual

Leyenda: ✅ probado · ⚠️ parcial · N/A no aplica · ❌ no probado

| Screen | Open | Data | Empty | Error | Form | Keyboard | Scroll | Back | CRUD | Screenshot |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| UI-01 Inicio | ✅ | ✅ | ⚠️ | ❌ | N/A | ✅ | ✅ | ✅ | N/A | ✅ |
| UI-02 Operaciones | ✅ | N/A | N/A | N/A | N/A | N/A | N/A | ✅ | N/A | ✅ |
| UI-03 Catálogos | ✅ | ✅ | ❌ | ❌ | ✅ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ |
| UI-04 Planificación | ✅ | ✅ | ❌ | ❌ | N/A | N/A | ✅ | ✅ | N/A | ✅ |
| UI-05 Plan (form) | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| UI-06 Compras | ✅ | ✅ | ❌ | ❌ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| UI-07 Compra (form) | ✅ | ✅ | N/A | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| UI-08 Aplicaciones | ✅ | ✅ | ❌ | ❌ | N/A | ❌ | ✅ | ✅ | ⚠️ | ✅ |
| UI-09 Aplicación (form) | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| UI-10 Liquidación | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| UI-11 Inventario | ✅ | ✅ | ❌ | ❌ | N/A | ❌ | ✅ | ✅ | N/A | ✅ |
| UI-12 Inventario detalle | ✅ | ✅ | N/A | ❌ | N/A | N/A | ✅ | ✅ | N/A | ✅ |
| UI-13 Personas | ✅ | ✅ | ❌ | ❌ | N/A | N/A | ✅ | ✅ | N/A | ✅ |
| UI-14 Persona detalle | ✅ | ✅ | ⚠️ | ❌ | N/A | N/A | ⚠️ | ✅ | N/A | ✅ |
| UI-15 Bitácora de chaco | ✅ | ✅ | ❌ | ❌ | N/A | N/A | ✅ | ✅ | N/A | ✅ |
| UI-16 Transferencias | ✅ | ✅ | ❌ | ❌ | N/A | N/A | ✅ | ✅ | ⚠️ | ✅ |
| UI-17 Transferencia (form) | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |

### Por qué quedan ❌ importantes

| Columna | Motivo |
|---|---|
| **Error** en 12 pantallas | Provocar el fallo de una consulta exige corromper la base o inyectar un repositorio que lance, lo que **modificaría el código o los datos** más allá de lo permitido en esta fase. El estado de error **sí** se observó de forma natural en UI-10 (UIBUG-001). Los estados de error están cubiertos por `test/error_states_test.dart`. |
| **Empty** en 9 pantallas | Requiere un dataset vacío, es decir una segunda ejecución completa con otro seed. El vacío **sí** se observó en UI-01 (por filtro), UI-05, UI-09 y en el selector ("Sin resultados."). |
| **Keyboard** en UI-08/UI-11 | Sus buscadores usan el mismo patrón ya auditado en UI-01, donde se detectaron UIBUG-009 y UIBUG-036. |
| **CRUD** parcial | Se crearon una compra y dos pagos reales, y se abrieron los diálogos de reversión. No se ejecutaron reversiones ni archivados definitivos para no destruir el dataset base más veces de las necesarias; el RESET permite repetirlo cuando se quiera. |
| ~~**UI-06 completo**~~ | ~~Inalcanzable (UIBUG-002).~~ **Resuelto el 2026-09-05**: auditada por completo, ver `45` §5. |

## 3. Matriz de flujos

| Flow | Entrada | Pasos | Resultado | Probado | Hallazgos |
|---|---|---|---|:--:|---|
| F-1 Consultar almacén | Inicio | Inicio → tabla → fila → detalle de producto | Detalle con lotes FIFO | ✅ | UIBUG-022, 023, 008, 004 |
| F-2 Buscar un producto en el inicio | Inicio | Escribir en *Buscar producto* | Debería filtrar | ✅ | **UIBUG-007**, 009 |
| F-3 Registrar una compra | Operaciones | Proveedor → factura → producto → cantidad → precio → asignación → Confirmar | Compra creada, stock +12,5 L | ✅ | UIBUG-006, 011, 037, 038, 039, 040, 041 |
| F-4 Consultar el historial de compras | — | — | — | ❌ | **UIBUG-002** (sin entrada) |
| F-5 Pagar a un proveedor tras la compra | — | — | — | ❌ | **UIBUG-002** |
| F-6 Ver la foto de una factura | — | — | — | ❌ | **UIBUG-002** |
| F-7 Planificar una aplicación | Operaciones | Nuevo plan → chaco → área → productos → dosis → Guardar | Plan creado | ⚠️ (validación probada, no guardado) | UIBUG-006, 019, 032, 033, 035, 036 |
| F-8 Registrar una aplicación | Aplicaciones | Registrar → persona → chaco → producto → dosis/cantidad → Confirmar | Consumo FIFO + cargo | ⚠️ (validación de stock probada) | UIBUG-042, 043, 044 |
| F-9 Revertir una aplicación | Aplicaciones | ↩ → confirmar | Stock devuelto | ⚠️ (diálogo verificado) | UIBUG-010 |
| F-10 Transferir inventario | Operaciones | Nueva → origen → cantidades → destino → Revisar y confirmar | Movimiento FIFO | ✅ | **UIBUG-003**, 034, 054, 055, 060 |
| F-11 Revertir una transferencia | Transferencias | ↩ → confirmar | Stock devuelto | ⚠️ (diálogo verificado, cancelado) | — (diálogo correcto) |
| F-12 Registrar un cobro a una persona | Cuentas | ⋮ → Registrar pago → importe → Registrar | Pago asentado | ✅ | **UIBUG-005, 012, 014, 003** |
| F-13 Consultar el estado de cuenta | Cuentas | ⋮ → Ver detalle cronológico | Movimientos con saldo | ✅ | UIBUG-013, 016, 021, 027 |
| F-14 Exportar una copia de seguridad | Cuentas | Nube → Exportar backup | Archivo de respaldo | ✅ | **UIBUG-001**, 015, 049 |
| F-15 Restaurar una copia de seguridad | Cuentas | Nube → Restaurar backup | Restauración | ⚠️ (no hay backups por UIBUG-001) | UIBUG-050 |
| F-16 Cambiar de campaña activa | Catálogos | Campañas → ⋮ → Activar → confirmar | Campaña conmutada | ⚠️ (confirmado el diálogo, cancelado) | UIBUG-047, 048, 059 · diálogo **correcto** |
| F-17 Alta de catálogo | Catálogos | Agregar → nombre → Guardar | Registro creado | ⚠️ (validación de vacío probada) | UIBUG-031, 047 |
| F-18 Consultar la bitácora de un chaco | Personas | Persona → Chacos → chaco → expandir entrada | Historial con FIFO | ✅ | **UIBUG-026**, 024, 027, 062 |
| F-19 Volver atrás desde cualquier pantalla | Global | Atrás de Android | Pantalla anterior | ✅ | **UIBUG-004** |
| F-20 Cambio rápido de pestañas | Global | 30 cambios seguidos | Sin fallos | ✅ | Ninguno — correcto |
| F-21 Rotar a horizontal | Global | Rotación | Rail lateral | ✅ | UIBUG-063 |
| F-22 Escala de fuente 130 % | Global | Ajustes del sistema | Layout legible | ✅ | **UIBUG-017** |

## 4. Revisión final de cobertura

Tras recorrer todas las vistas se volvió sobre el inventario de rutas, la documentación y las
funcionalidades de `05_FEATURES.md` para localizar olvidos. Resultado:

- Las 17 rutas están contempladas; 16 auditadas y 1 declarada inalcanzable con evidencia.
- Los flujos críticos (compra, transferencia, pago, backup, navegación atrás) se repitieron al
  menos dos veces cada uno; **todos los hallazgos marcados ALWAYS se reprodujeron**.
- Áreas que no pudieron probarse y su motivo están en `40_UI_AUDIT_SUMMARY.md` §15.
