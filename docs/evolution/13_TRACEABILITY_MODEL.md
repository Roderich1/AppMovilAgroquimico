# Modelo de trazabilidad

## Identificadores

| Prefijo | Uso | Ejemplo |
|---|---|---|
| `EVO` | Capacidad/feature | `EVO-001` |
| `REQ` | Requisito dentro de feature | `EVO-001-REQ-03` |
| `BR` | Regla de negocio | `BR-INV-01` |
| `ADR` | Decisión arquitectónica | `ADR-001` |
| `RISK` | Riesgo | `RISK-004` |
| `MIG` | Migración de datos | `MIG-007` |
| `TEST` | Escenario/evidencia | `EVO-001-TEST-05` |

No crear un ID para cada párrafo. Usarlo cuando se necesite enlazar artefactos o evidencia.

## Cadena mínima

`EVO → REQ/BR → decisión/diseño → archivos/commit → TEST → CI/device → documentación`.

## Registro por feature

| Campo | Contenido |
|---|---|
| Identidad | ID, nombre, owner decision, estado |
| Alcance | incluido/no incluido |
| Reglas | IDs existentes/nuevos |
| Cambio | commit/PR y archivos |
| Datos | schema/MIG/backup impact |
| Verificación | tests, CI, dispositivo |
| Riesgo | RISK mitigados/aceptados |
| Cierre | versión, docs y DoD |

## Reglas de integridad

- IDs únicos y estables; no reciclar rechazados.
- Un test puede cubrir varios requisitos si la relación se declara.
- `VERIFIED` exige evidencia; un merge no basta.
- Una recomendación sin aprobación permanece `PROPOSED` o `ANALYZED`.
