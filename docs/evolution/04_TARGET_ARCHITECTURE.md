# Arquitectura objetivo incremental

## Diagnóstico

La arquitectura actual es adecuada para el tamaño de la baseline: UI → repositorio → SQLite,
con DI ligera. Sus fortalezas son la atomicidad, el dominio numérico central y los servicios de
backup ya separados. El principal límite es que `AgroRepository` concentra catálogos,
campañas, compras, FIFO, cuentas y reporting, mientras las lecturas cruzan la UI como mapas.

No se recomienda una reescritura ni imponer Clean Architecture completa.

## Forma objetivo

```text
presentation
    ↓ comandos / consultas tipadas
application (casos de uso sólo cuando coordinan reglas)
    ↓
domain (invariantes, dinero, drafts, resultados)
    ↓ puertos necesarios
data (SQLite por capacidad, mappers, migraciones)
    ↘ services (backup, archivos, voz, red opcional)
```

La estructura es una dirección, no una migración inmediata. Una feature puede seguir usando
el repositorio actual si no añade acoplamiento peligroso.

## Capacidades y límites candidatos

| Límite | Mantiene/extrae | Momento de extracción |
|---|---|---|
| Catalog | personas, chacos, productos, proveedores | Al ampliar catálogos |
| Campaign | ciclo y cierres | Al añadir corrección administrativa |
| Purchase | compra, asignación, proveedor | Al tocar compras/reportes de proveedor |
| Inventory | lotes, movimientos, FIFO, transferencias | Antes de otra operación que consuma/mueva stock |
| Application | planes y aplicaciones | Al añadir clonación, recordatorios o voz |
| Accounts | cargos, pagos, saldos | Antes de nuevos tipos contables |
| Reporting | consultas/proyecciones/exportaciones | Primera exportación o dashboard avanzado |
| Backup | contenedor, validación y restore | Ya existe; mantener independiente |
| Voice | captura, transcripción, intención y drafts | EVOLUTION-3; aislado de SQLite/escrituras |
| Sync | identidad, cambios, conflictos y transporte | Sólo tras ADR y rediseño de IDs |

## Contratos recomendados

- Modelos de lectura inmutables por consulta crítica, con `fromRow` central.
- Resultados explícitos para warnings de backup/migración.
- `InventoryOperations` o caso de uso único para FIFO, sin duplicar cálculo.
- Puertos de plataforma: `InvoiceFiles`, `BackupTransport`, `AudioCapture`,
  `SpeechTranscriptionPort`.
- Frontera de voz: sesión → intención cerrada → entidades → resolución → draft tipado →
  validador. Sólo la confirmación táctil invoca casos de uso existentes.
- Servicios externos reciben DTO mínimos; nunca acceso directo a `Database`.

## Ruta de adopción

1. La nueva feature define su contrato.
2. Se introduce un modelo tipado sólo para las lecturas que toca.
3. Si coordina varias operaciones, se crea un caso de uso transaccional.
4. Se conserva un adaptador temporal si evita migrar toda la UI.
5. Se retira el camino anterior sólo cuando tests y consumidores hayan migrado.

## Qué sigue simple

- Riverpod como DI mientras no exista estado reactivo complejo.
- `FutureBuilder` en pantallas pequeñas sin recarga problemática.
- SQLite y SQL explícito: hoy ofrecen exactitud, constraints y pruebas reales.
- `GoRouter` actual mientras el mapa de rutas no cambie sustancialmente.

## Líneas rojas

Voz/IA/cloud no ejecuta SQL, no decide montos, no omite confirmaciones y no modifica la lógica
FIFO. STT y NLU sólo producen propuestas tipadas. La intención externa vuelve a pasar por las
mismas validaciones que la UI manual, y toda escritura exige confirmación táctil específica.
