# 14 — Modo offline y sincronización

## Conclusión

La aplicación es **offline-only**, no *offline-first*. La distinción importa:

- *Offline-first* implica que existe un servidor y que la app opera sin él, sincronizando
  cuando hay conexión.
- *Offline-only* significa que **no existe servidor en absoluto**. Es el caso aquí.

El README describe la app como "offline-first", pero el código no contiene ninguna
infraestructura de sincronización. Ver [11_API_INTEGRATION](11_API_INTEGRATION.md).

## Matriz de capacidades

| Capacidad | Estado | Evidencia |
|---|---|---|
| Funciona sin conexión | **Sí, siempre** | Todas las operaciones van a SQLite local |
| Detección de conectividad | **No existe** | Sin `connectivity_plus` ni equivalente |
| Caché de respuestas remotas | **No aplica** | No hay respuestas remotas |
| Cola de operaciones pendientes | **No existe** | Ninguna tabla de *outbox*; los `INSERT` son definitivos |
| Reintentos | **No existe** | Ningún `retry`, `backoff` ni bucle de reintento |
| Sincronización | **No existe** | Sin cliente, sin endpoint, sin planificador |
| Resolución de conflictos | **No aplica** | Un solo escritor por instalación |
| Trabajo en segundo plano | **No existe** | Sin `workmanager`, `BGTaskScheduler` ni `WorkManager` |
| Marcas de sincronización (`synced_at`, `dirty`, `version`) | **Ninguna** en las 22 tablas | `app_database.dart` |
| Identificadores globales (UUID) | **No**: todas las PK son `INTEGER AUTOINCREMENT` locales | `app_database.dart` |

## Consecuencia estructural: los identificadores son locales

Todas las claves primarias son `INTEGER PRIMARY KEY AUTOINCREMENT`. Dos instalaciones
distintas generarán el id `1` para personas diferentes.

Esto significa que **fusionar dos bases de datos es imposible sin un rediseño**: no hay
identificadores globalmente únicos ni relojes lógicos. Si en el futuro se quiere
multi-dispositivo, la migración a UUID debe hacerse **antes** de que existan volúmenes
grandes de datos en producción. Es una decisión arquitectónica con fecha de caducidad, y
está registrada como tal en [30_IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md).

## Lo único parecido a un respaldo: `exportBackup`

`agro_repository.dart` → `exportBackup()`:

```
PRAGMA wal_checkpoint(FULL)
  → comprueba que openedPath no sea null ni ':memory:'
  → copia el .db a getDownloadsDirectory() (o Documentos como respaldo)
  → nombre: agroquimicos_backup_<ISO8601 con ':' sustituido por '-'>.db
  → devuelve la ruta, que la UI muestra en un snackbar
```

Limitaciones confirmadas:

1. **No hay importación ni restauración.** Solo se puede exportar. Recuperar una copia exige
   sustituir el archivo manualmente por medios externos a la app.
2. **Las fotos de factura no se incluyen.** Viven en `<documentos>/invoices/` y el backup
   solo copia el `.db`. Una restauración dejaría las rutas apuntando a archivos inexistentes.
3. **Sin cifrado.** El archivo resultante queda en Descargas, legible por cualquier app con
   acceso a ese directorio. Ver [23_SECURITY_AUDIT](23_SECURITY_AUDIT.md).
4. **Sin verificación.** No se comprueba integridad ni se informa del tamaño.
5. **Sin automatismo.** Depende de que el usuario recuerde pulsar el botón.

## Riesgo operativo real

Este es, en opinión de esta auditoría, **el mayor riesgo del producto**, por encima de
cualquier hallazgo de seguridad o de calidad de código:

> Toda la contabilidad de la familia vive en **un único archivo, en un único teléfono**, sin
> respaldo automático. Si el dispositivo se pierde, se rompe o la app se desinstala, se
> pierde el histórico completo de compras, inventario y deudas.

Tanto en Android como en iOS, desinstalar la aplicación borra su directorio de datos. La
copia manual en Descargas sobrevive en Android (está fuera del sandbox), pero solo si el
usuario la generó.

Mitigaciones propuestas, por orden de coste creciente, en
[30_IMPROVEMENT_ROADMAP](30_IMPROVEMENT_ROADMAP.md):

1. Recordatorio de backup y función de **restauración** (bajo coste, gran impacto).
2. Incluir la carpeta `invoices/` en un backup empaquetado (ZIP).
3. Exportar a una ubicación elegida por el usuario mediante *share sheet*.
4. Sincronización con un servicio de almacenamiento (cambio arquitectónico mayor).

## Qué ocurre hoy con varios dispositivos

`REQUIERE INFORMACIÓN DEL DESARROLLADOR`: el código no permite saber si el producto se usa
en un solo dispositivo o en varios. Si fueran varios, **cada uno tendría una contabilidad
distinta e irreconciliable**, porque no existe ningún mecanismo de unión.

---

# Actualización 2026-09-06 — El respaldo como único mecanismo de portabilidad

El modelo sigue siendo **offline-only y monodispositivo**: no hay red, ni cuentas, ni
sincronización. Lo que cambia es que el respaldo dejó de ser una copia parcial.

Antes, mover los datos a otro teléfono conservaba las cuentas y **perdía todas las
fotografías de factura**, porque viven en el sistema de archivos y no en SQLite. Ahora el
contenedor `.agrobackup` lleva las dos cosas y, al restaurar, **reconstruye las rutas** para el
dispositivo de destino: la base guarda rutas absolutas del teléfono de origen, que en otro
equipo no existirían.

Eso convierte el respaldo en un mecanismo de **portabilidad** real, no sólo de recuperación
ante fallo, dentro de los límites del modelo:

| | |
|---|---|
| Sirve para | recuperar tras un fallo, y mover los datos a otro teléfono |
| No sirve para | trabajar en dos dispositivos a la vez. La restauración **reemplaza** todo; no fusiona |
| Conflictos | no existen, porque no hay dos fuentes de verdad simultáneas |

Compartir el archivo con el selector del sistema —para llevarlo fuera del teléfono sin
cable— es evolución diferida ([`46` sección 16](46_BASELINE_FINAL_FREEZE.md)).

Detalle del formato: [`13_LOCAL_STORAGE`](13_LOCAL_STORAGE.md).
