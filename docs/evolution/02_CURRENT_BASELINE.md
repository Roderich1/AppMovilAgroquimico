# Contrato de partida — baseline y HEAD documental

Verificado el 2026-09-06 contra GitHub y el repositorio.

## Identidad

| Elemento | Valor verificado |
|---|---|
| Repositorio | `Roderich1/AppMovilAgroquimico` |
| Baseline funcional | `f4c6510438991f4948fda921eec7c67fe2a2acc2` |
| Tag inmutable | `v1.0.0-base-stable` → `f4c6510438991f4948fda921eec7c67fe2a2acc2` |
| PR de cierre | `#4` |
| HEAD documental posterior | `bdd7b82f3e06d9943749a571284db8f94194c3b3` |
| Diferencia respecto de la baseline | Sólo documentación; sin cambios en código, tests, dependencias, Android o SQLite |
| CI del HEAD documental | Run `34009811737`, exitoso |
| Estado desarrollo | `READY FOR EVOLUTION` |
| Estado tienda | `NOT READY — KEYSTORE REQUIRED` |

El tag y el commit de baseline no se actualizan cuando cambia documentación. Una rama de
implementación debe partir del `main` vigente, no directamente del tag histórico.

## Toolchain y datos de la baseline

| Elemento | Valor |
|---|---|
| Flutter / Dart | `3.47.2` / `3.13.2` |
| Java CI | Temurin 17 |
| `pubspec` | `1.0.0+1` |
| SQLite | schema `6`, 22 tablas |
| Backup | formato `1`, `.agrobackup` + lectura legacy `.db` |
| Pruebas de cierre | 253/253 |
| CI de baseline | Run `34003453897`, exitoso |
| Dispositivo | Pixel 8, Android 16/API 36, 1080×2400, 420 dpi |
| Rutas | 17/17 auditadas |
| UIBUG abiertos | 0 |

## Arquitectura observada

- `main.dart`: bootstrap.
- `app.dart`: inyección Riverpod y `GoRouter`.
- `domain/`: drafts tipados, dinero, entrada numérica es-BO, etiquetas y búsqueda.
- `data/`: `AppDatabase`, `AgroRepository`, `BackupService`, facturas y log.
- `presentation/`: `AppShell`, rutas/pantallas y widgets compartidos.
- Persistencia: SQLite local; no existe cliente HTTP ni backend.

## Invariantes nucleares

1. `ADMIN`, `FAMILY` y `THIRD_PARTY` son roles contables, no autorización.
2. `FAMILY` se carga por consumo; `THIRD_PARTY`, por asignación; `ADMIN`, manual.
3. Stock por persona, producto y lote; nunca negativo.
4. FIFO conserva orden y costo histórico.
5. Compras, aplicaciones y transferencias multiproducto son atómicas.
6. Transferir cambia propietario, no costo histórico.
7. Sólo una campaña `ACTIVE`; `CLOSED` es terminal.
8. Un plan representa una aplicación: `PLANNED → APPLIED`, una sola vez.
9. Revertir preserva historia y no reactiva el plan.
10. Dinero y cantidades usan enteros; entrada es-BO central.
11. Backup/restauración trata base y fotografías como un conjunto, con rollback.

## Limitaciones aceptadas

- Sin keystore de release.
- Monodispositivo, sin red ni identidad de operador.
- Base, fotografías y backup sin cifrado.
- Lecturas basadas en `Map<String,Object?>` y `AgroRepository` grande.
- Android verificado; iOS/web no certificados como producto.
- `main` no protegido; debe protegerse antes de trabajo concurrente.

