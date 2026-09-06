# Contrato de partida — baseline actual

Verificado el 2026-09-06 contra GitHub y la copia exacta del repositorio.

## Identidad

| Elemento | Valor verificado |
|---|---|
| Repositorio | `Roderich1/AppMovilAgroquimico` |
| `main` | `f4c6510438991f4948fda921eec7c67fe2a2acc2` |
| Tag inmutable | `v1.0.0-base-stable` → mismo commit |
| PR de cierre | `#4` |
| Estado desarrollo | `READY FOR EVOLUTION` |
| Estado tienda | `NOT READY — KEYSTORE REQUIRED` |

## Toolchain y datos

| Elemento | Valor |
|---|---|
| Flutter / Dart | `3.47.2` / `3.13.2` |
| Java CI | Temurin 17 |
| `pubspec` | `1.0.0+1` |
| SQLite | schema `6`, 22 tablas |
| Backup | formato `1`, `.agrobackup` + lectura legacy `.db` |
| Pruebas de cierre | 253/253 |
| CI actual | GitHub Actions verde, run `34003453897` sobre el SHA de `main` |
| Dispositivo de regresión | Pixel 8, Android 16/API 36, 1080×2400, 420 dpi |
| Rutas | 17/17 auditadas |
| UIBUG abiertos | 0 |

La ejecución local no pudo repetirse en el entorno documental porque no contiene el SDK de
Flutter. La evidencia vigente es el workflow exitoso del mismo SHA, además de la congelación
documentada. Una futura implementación sí debe ejecutar los gates en su entorno/CI.

## Arquitectura observada

- `main.dart`: bootstrap.
- `app.dart`: cuatro providers de inyección y `GoRouter`.
- `domain/`: drafts tipados, dinero, entrada numérica es-BO, etiquetas y búsqueda.
- `data/`: `AppDatabase`, `AgroRepository`, `BackupService`, almacenamiento de facturas y log.
- `presentation/`: `AppShell`, 17 rutas/pantallas y widgets compartidos.
- Estado: Riverpod como DI; carga principalmente con `FutureBuilder` y estado local.
- Persistencia: SQLite local; no existe cliente HTTP ni backend.

## Invariantes nucleares

1. Roles: `ADMIN`, `FAMILY`, `THIRD_PARTY` son roles contables, no autorización.
2. `FAMILY` se carga por consumo real; `THIRD_PARTY`, por asignación; `ADMIN`, manual.
3. Stock = suma de movimientos por persona + producto + lote; nunca negativo.
4. FIFO ordena por fecha de adquisición y luego ID; conserva costo histórico.
5. Compras, aplicaciones y transferencias multiproducto son atómicas.
6. Transferir cambia propietario, no costo histórico.
7. Sólo una campaña `ACTIVE`; `CLOSED` es terminal.
8. Un plan representa una aplicación: `PLANNED → APPLIED`, una sola vez.
9. Revertir preserva historia; no reactiva el plan ni borra el hecho.
10. Dinero y cantidades usan enteros; entrada es-BO central y ambigüedades se rechazan.
11. Backup/restauración trata base y fotografías como un conjunto, con rollback.

## Fronteras que ya funcionan

Conservar: drafts de escritura tipados, funciones exactas de dinero, transacciones SQLite,
constraints/índices de invariantes, `BackupService`, `InvoiceStorage`, DI simple, navegación
jerárquica y widgets adaptativos.

## Limitaciones aceptadas del punto de partida

- Sin keystore de release.
- Monodispositivo, sin red ni identidad de operador.
- Base, fotografías y backup sin cifrado.
- El backup queda en carpeta de la app y debe copiarse antes de desinstalar.
- Lecturas basadas en `Map<String,Object?>` y `AgroRepository` grande.
- Android verificado; iOS/web presentes pero no certificados como producto.
- Rama `main` no protegida en GitHub: CI existe, pero la API reporta `protected=false`.
