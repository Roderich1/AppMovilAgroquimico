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

---

# Actualización 2026-10-15 — Sincronización F05 v1 (necesidad declarada)

La app sigue siendo **local primero**: toda operación individual vive en SQLite y funciona
sin red. Lo nuevo es que el agricultor puede **enviar al sindicato una proyección mínima**
—por ahora, su necesidad declarada— según los contratos del Backend
`F05_SYNC_V1_PUSH_ACK_CONTRACT.md` y `F06_COLLECTIVE_PROJECTION_CONTRACT.md`. Nada más
cruza: ni compras, ni lotes, ni personas, ni costos, ni el respaldo.

| Capacidad | Estado (v9) | Dónde |
|---|---|---|
| Cola de salida (*outbox*) | **Sí**: `sync_outbox`, escrita en la misma transacción que la necesidad declarada | `lib/data/sync/sync_outbox_store.dart` |
| Identificador global | **Sólo la intención**: `operation_id` UUID v4 generado al confirmar y persistido. Las tablas locales conservan sus claves enteras | `lib/domain/sync/operation_id.dart` |
| Reintentos | **Sí**: backoff exponencial con jitter completo (2 s, ×2, tope 15 min, mínimo 1 s), `max(backoff, Retry-After)` y presupuesto de 20 intentos por ciclo | `lib/services/sync/sync_worker.dart` |
| Orden causal | Como máximo una intención en vuelo por contribución; la sucesora espera el ACK de su antecesora | `SyncOutboxStore.readyToSend` |
| Conflictos | Sin LWW: un `CONFLICT` queda visible y **decide el agricultor** (enviar su valor o retirar), con el head y la referencia que muestra Central | `DeclaredNeedStore.resolveConflict` |
| Disparadores | Al iniciar, tras encolar, «Sincronizar ahora» y cada minuto en primer plano. Sin trabajo en segundo plano | `SyncController`, `SyncLifecycle` |
| Credencial | El access token vive **sólo en memoria** tras una verificación explícita (refresh o reautenticación). El worker nunca renueva por su cuenta; sin acceso vigente no hace llamadas de red | `lib/services/sync/sync_access.dart` |
| Restauración | Las intenciones por enviar que trae una copia quedan `RESTORE_PAUSED` hasta que el titular las libere; restaurar no publica | `lib/guarded_restore.dart` |
| Vínculo con el catálogo central | Explícito, por campaña y producto, con validación de dimensión (L↔L, KG↔KG) y sin coincidencia por nombre | `lib/data/sync/central_binding_store.dart` |

Estados locales de una intención: `PENDING`, `SENDING`, `OUTCOME_UNKNOWN`, `ACKED`,
`CONFLICT`, `REJECTED`, `FAILED`, `AUTH_PAUSED`, `OWNER_PAUSED`, `RESTORE_PAUSED`,
`VERSION_MISMATCH` y `DISCARDED` (nunca salió y dejó de tener objeto). Sólo un ACK válido de
aceptación (`APPLIED`/`ALREADY_APPLIED` con las siete claves, el mismo `operationId` y la
hora del servidor) la marca como sincronizada.

Una intención que ya salió del teléfono **no se modifica nunca** (lo impone un trigger):
corregir una cantidad crea otra intención que la tiene por antecesora. Sólo una intención que
nunca salió (`PENDING` con `attempts = 0`) puede reescribirse o descartarse.

Pendiente: el total de consumo (`CONSUMPTION_TOTAL`) y su prueba de propiedad (F06, D4).
