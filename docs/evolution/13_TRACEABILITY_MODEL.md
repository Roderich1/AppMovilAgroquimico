# Modelo de trazabilidad

## Identificadores

| Prefijo | Uso | Ejemplo |
|---|---|---|
| `EVOLUTION` | Etapa del roadmap | `EVOLUTION-2` |
| `EVO` | Capacidad/feature única del backlog | `EVO-004` |
| `REQ` | Requisito dentro de una feature | `EVO-004-REQ-001` |
| `BR` | Regla de negocio | `BR-INV-01` |
| `ADR` | Decisión arquitectónica | `ADR-001` |
| `RISK` | Riesgo | `RISK-004` |
| `MIG` | Migración de datos | `MIG-007` |
| `TEST` | Escenario/evidencia | `EVO-004-TEST-001` |

`EVOLUTION-N` y `EVO-NNN` no son alias. Una etapa puede agrupar varias features:

- `EVOLUTION-2` → `EVO-004`, `EVO-005`, `EVO-006`.
- `EVOLUTION-3` → `EVO-009`.

## Cadena mínima

`EVOLUTION → EVO → REQ/BR → decisión/diseño → archivos/commit → TEST → CI/device → docs`.

## Registro por feature

| Campo | Contenido |
|---|---|
| Identidad | ID, nombre, decisión y estado |
| Alcance | incluido/no incluido |
| Reglas | IDs existentes/nuevos |
| Cambio | commits, PR y archivos |
| Datos | schema, migración y backup impact |
| Verificación | tests, CI y dispositivo |
| Riesgo | mitigado/aceptado |
| Cierre | versión, documentación y DoD |

## Reglas de integridad

- IDs únicos y estables; no reutilizar un ID para otro significado.
- `APPROVED` no significa `IN_PROGRESS`.
- `IN_PROGRESS` requiere una rama real con implementación iniciada.
- `FINAL_VERIFICATION` sólo existe cuando hay implementación y evidencia que verificar.
- `VERIFIED` exige evidencia; un merge no basta.
- Un test puede cubrir varios requisitos si la relación se declara.

