# Estrategia de pruebas

## Pirámide específica

| Nivel | Protege | Cuándo es obligatorio |
|---|---|---|
| Unit | dinero, parser, mappers, policies | Toda lógica pura |
| Domain | invariantes y comandos | Operación contable/inventario |
| Repository | transacciones sobre SQLite real en memoria | Toda escritura compuesta |
| Database | constraints e índices | Cambio SQL |
| Migration | transformación y anomalías | Cambio de schema |
| Schema equivalence | fresh = migrated | Cada nueva versión SQLite |
| Widget | validación, estados, confirmación | Cambio de formulario/UX |
| Navigation | pila, regreso y rutas | Cambio de flujo |
| Integration | DB + filesystem/plugin | Backup, fotos, exportación |
| Device | semántica Android real | Plugin, permisos, filesystem, lifecycle |
| Exploratory | comportamiento de campo | Antes de cerrar feature visible |

## Matriz mínima por feature crítica

- Happy path.
- Entrada inválida y ambigua.
- Límites: cero, máximo razonable, agotamiento de stock, lista grande.
- Atomicidad: fallo en el paso N no deja efectos parciales.
- Failure: I/O, SQLite, plugin, timeout o respuesta externa.
- Recovery/retry sin duplicar operaciones.
- Regresión de las invariantes adyacentes.

## Reglas por riesgo

- Dinero/cantidad: enteros exactos, redondeo, BOB/USD y round-trip de formato.
- Inventario: conservación de cantidad y costo por lote; nunca negativo.
- SQLite: migración, equivalencia e integridad.
- Reversión: asientos/movimientos compensatorios y trazabilidad.
- Filesystem/plugin: fake determinista + prueba Android real.
- Voz: falsos positivos, entidades homónimas, ruido, desconexión y confirmación.

## Gates

En cada PR: `flutter pub get`, format, analyze, test y APK release. No reducir aserciones ni
excluir tests para obtener verde. Añadir el test que habría fallado antes del cambio.

## Dispositivo de referencia

Pixel 8, Android 16/API 36 sigue siendo regresión principal conocida; no define por sí solo el
universo de soporte. Probar vertical, horizontal, 130 %, teclado, listas voluminosas y doble
interacción si la feature toca esos escenarios.

## Evidencia

Cada `EVO-*` enlaza test automatizado, run CI y, cuando corresponda, evidencia de dispositivo
con entorno, pasos, resultado esperado/observado y SHA.
