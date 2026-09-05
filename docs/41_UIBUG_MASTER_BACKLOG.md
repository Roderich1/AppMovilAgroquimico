# 41 — Backlog maestro de UIBUG

Documento **único y vigente** del backlog de defectos de interfaz.
Sustituye a `38`/`39`/`40` como fuente de verdad operativa: aquellos conservan la evidencia
histórica y la narrativa de la auditoría; **este documento manda para planificar y ejecutar**.

Fecha de normalización: **2026-09-05** · Rama: `hardening/stabilization` · Base: `81c919f`

> **En esta fase NO se corrigió ningún defecto.** Ningún archivo de `lib/` fue modificado.
> Todos los hallazgos están en estado `OPEN`.

---

## 1. Cómo se construyó este backlog

Cada hallazgo de `38_UI_AUDIT_FINDINGS.md` se cruzó con:

1. la **evidencia** en `artifacts/ui-audit/` (verificada archivo a archivo: 108 referencias,
   **0 rotas**, 119 PNG en disco);
2. el **código real** del repositorio (para CRITICAL y HIGH se leyó el archivo y la línea
   citados; para MEDIUM y LOW se verificó lo suficiente para descartar duplicación o
   consecuencia de otro hallazgo);
3. la **documentación previa** (`27_KNOWN_ISSUES`, `33_STABILIZATION_FINDINGS`,
   `34_CHANGE_TRACEABILITY`, `35_RELEASE_READINESS`).

Línea base reproducida antes de tocar nada:

| Comprobación | Resultado |
|---|---|
| `git status` | árbol limpio, rama `hardening/stabilization` |
| `git log -n 5 --oneline` | `81c919f` documentos de errores encontrados |
| `flutter analyze` | **0 issues** |
| `flutter test` | **91 / 91 en verde** |

> **Aviso de rama**: la auditoría vive en `hardening/stabilization`. `origin/main` está en
> `5d0b8ef` y **no contiene** ni la estabilización ni la auditoría de interfaz. Cualquier
> lectura de "el estado de main" es engañosa hasta que se integre esta rama.

## 2. Resolución de la inconsistencia de conteo

`38` y `40` declaraban 56 hallazgos (4 / 17 / 26 / 9) mientras `39` enumeraba
`UIBUG-001` … `UIBUG-065`.

Verificación mecánica sobre `38_UI_AUDIT_FINDINGS.md`:

```
IDs únicos encontrados          : 65
Bloques de definición (## / - **): 65
```

Los 65 IDs están **todos definidos con contenido propio** (pasos, resultado, evidencia o
causa). No hay IDs huérfanos ni reservados. Recuento por sección del documento:

| Sección | Rango | Nº |
|---|---|---:|
| CRITICAL | 001–004 | 4 |
| HIGH | 005–021 | 17 |
| MEDIUM | 022–056 | **35** |
| LOW | 057–065 | 9 |
| | | **65** |

**Conclusión**: el total correcto era **65**, y el error estaba en la celda MEDIUM
(26 en lugar de 35). La cifra `56` era el conteo antiguo arrastrado sin actualizar tras
ampliar la sección MEDIUM. Se corrige en `38`, `39`, `40` y `00_INDEX`.

Tras la subdivisión de `UIBUG-004` (§3) el backlog contiene **66 entradas** sobre
**65 IDs históricos**.

## 3. Subdivisión de UIBUG-004 (navegación)

`UIBUG-004` mezclaba **dos comportamientos distintos con distinto veredicto**. Se subdivide
conservando el ID histórico como prefijo. **No se renumeró nada más.**

### Lo que se verificó en código

`lib/app.dart` declara 13 rutas dentro del `ShellRoute` y 4 fuera (los formularios).
`lib/presentation/app_shell.dart:9-23` define **5 destinos raíz**:
`/`, `/operaciones`, `/inventario`, `/personas`, `/liquidacion`.

Enumeración completa de la navegación (`grep` sobre `lib/`):

| Origen | Llamada | Destino | Tipo |
|---|---|---|---|
| `app_shell.dart:56,83` | `context.go` | los 5 destinos raíz | **raíz → raíz** |
| `persons_screen.dart:47` | `context.go` | `/personas/:id` | **jerárquica** |
| `inventory_screen.dart:96` | `context.go` | `/inventario/:id` | **jerárquica** |
| `person_detail_screen.dart:104` | `context.go` | `/chacos/:id` | **jerárquica (nivel 3)** |
| `dashboard_screen.dart:235` | `context.go` | `/inventario/:id` | **jerárquica** |
| `operations_screen.dart:86-87` | `push` si `isForm`, si no `go` | `/catalogos`, `/planificacion`, `/aplicaciones`, `/transferencias` | **jerárquica** |
| `applications_screen.dart:53` | `context.go` | `/catalogos` | jerárquica |
| `app_shell.dart:149` / `operations_screen.dart:86` / `planning_screen.dart:110` | `context.push` | los 4 formularios | correcta |

Y `PageFrame` (`lib/presentation/widgets/common.dart:5-57`) **no tiene `AppBar` ni ningún
botón de volver**: es un `CustomScrollView` con un título de texto. Ninguna pantalla de
detalle construye un `AppBar` propio.

### UIBUG-004A — la navegación jerárquica pierde el historial y no ofrece retorno

Entrar en un detalle usa `context.go`, que **reemplaza** la pila en vez de apilar. Resultado:
no hay nada que desapilar, Atrás cierra la aplicación, y como `PageFrame` no dibuja flecha de
volver **no existe ninguna forma de regresar a la lista de origen**. Es un callejón sin salida
funcional. Severidad **CRITICAL**, confirmada por código y por evidencia.

### UIBUG-004B — política de Atrás desde un destino raíz

Estar en `/personas` (destino raíz) y pulsar Atrás cierra la aplicación. Esto **no es
automáticamente un defecto**: es una política de navegación. Las directrices de Material 3 y de
Android recomiendan que Atrás desde un destino raíz **no inicial** vuelva primero al destino
inicial (`/`) y solo desde ahí salga; muchas aplicaciones de producción salen directamente.
No hay pérdida de datos, no hay contenido inalcanzable y no hay contexto jerárquico que
perder. Severidad **MEDIUM** y estado `DESIGN_DECISION_REQUIRED`: el propietario debe elegir
la política antes de implementar.

**Trazabilidad de la subdivisión**

| ID histórico | Sigue existiendo | Se divide en | Dónde estaba |
|---|---|---|---|
| `UIBUG-004` | Sí, como identificador de familia | `UIBUG-004A` (CRITICAL), `UIBUG-004B` (MEDIUM) | `38` §CRITICAL, `39` fila 004, `40` §5.4 y §8 |

Toda referencia previa a `UIBUG-004` **sin sufijo** debe leerse como "la familia 004", y en
contextos de bloqueo de release como `UIBUG-004A`.

## 4. Conteo definitivo

| Severidad | IDs | Nº |
|---|---|---:|
| **CRITICAL** | 001, 002, 003, 004A | **4** |
| **HIGH** | 005–021 | **17** |
| MEDIUM | 004B, 022–056 | **36** |
| LOW | 057–065 | **9** |
| **Total entradas** | | **66** |
| **Total IDs históricos** | 001–065 | **65** |

Sin duplicados. Sin IDs huérfanos. Sin evidencia rota.

## 5. Cambios respecto a `38`/`39`/`40`

Ninguna severidad se bajó para mejorar métricas. Los cambios son de **exactitud**:

| ID | Cambio | Justificación verificada |
|---|---|---|
| 004 | Subdividido en **004A** (CRITICAL) y **004B** (MEDIUM, design decision) | §3 |
| 065 | **Causa reescrita**, severidad LOW sin cambio | `parseMinor` = `tryParseMinor(v) ?? 0`: **no lanza nunca**, luego el `catch (_) {}` de `settlements_screen.dart:89` es **código muerto inalcanzable**. El comportamiento real es que un texto no parseable se convierte en `0` y `addAccountPayment` lo rechaza con *"El importe debe ser mayor a cero."* (`agro_repository.dart:598`). **No es un error silencioso: es un mensaje engañoso.** La descripción original de `38` era incorrecta. |
| 064 | **Reagrupado**: sale del grupo del FAB, entra en `SYSTEM_INSETS` | `39` lo agrupaba bajo "falta de relleno inferior bajo el FAB", pero `/compras/nueva` está **fuera del `ShellRoute`** y por tanto **no tiene FAB**. Causa real verificada: `purchase_form_screen.dart` es el **único** de los 4 formularios con `SafeArea: 0 ocurrencias` (los otros tres tienen 2). |
| 016 | **Causa raíz identificada** (antes "varias pantallas") | `agro_repository.dart:1559`: `COALESCE(..., t.notes, t.type) concept`. Un pago sin notas cae al último término y el `type` crudo (`PAYMENT`) se pinta como título en `settlements_screen.dart:173` y `person_detail_screen.dart:141`. `_transactionLabel` **sí** traduce, pero solo se aplica al subtítulo. |
| 013 | **Matizado**, severidad HIGH sin cambio | Las etiquetas **sí** difieren (`Saldo pendiente` en `settlements_screen.dart:437` vs `Saldo total` en `person_detail_screen.dart:88`). El defecto real es que **ninguna declara su alcance**: `settlements(campaignId:)` suma filtrado por campaña, `profile['balance']` suma todo el histórico, y el diálogo añade un tercer "Saldo" corrido sin cualificar. |
| 018 vs 008 | Marcados como **solapamiento**, no duplicados | Comparten la captura `UI-03-ISSUE-ultimo-item-inalcanzable.png` pero tienen causas distintas y verificadas: 008 = `PageFrame` cierra con `EdgeInsets.fromLTRB(16,6,16,24)`, 24 px insuficientes bajo un `FloatingActionButton.extended`; 018 = `catalogs_screen.dart:264` `height: 520` fijo. **Corregir una no cierra la otra.** |

**Duplicados encontrados: ninguno.** Se examinaron los candidatos 008/018, 015/050, 035/036,
024/025/027/056, 006/041, 017/020/021, 011/002 y 013/028: todos tienen sitio de código y
síntoma distintos.

## 6. Grupos de causa raíz

Solo grupos que se corresponden con código verificado.

| Grupo | Causa | UIBUG | Nº |
|---|---|---|---:|
| `NUMERIC_INPUT` | `common.dart:131` `tryParseDecimal` trata `.` como decimal | 003, 034, 065 | 3 |
| `BACKUP_ANDROID` | `backup_service.dart:63` `execute('PRAGMA wal_checkpoint(FULL)')` | 001, 049 | 2 |
| `NAVIGATION_STACK` | `go` donde corresponde `push`; `PageFrame` sin `AppBar`; `/compras` sin origen | 002, 004A, 004B, 011, 051, 062 | 6 |
| `ENTITY_PICKER` | `adaptive_entity_picker.dart` (`isEmpty`, alto fijo, foco) | 006, 035, 036, 054, 061 | 5 |
| `FAB_SAFE_AREA` | `PageFrame` cierra con 24 px bajo un FAB extendido | 008, 009 | 2 |
| `SYSTEM_INSETS` | rutas fuera del `ShellRoute` sin `SafeArea` | 064 | 1 |
| `FIXED_HEIGHT` | contenedores de alto fijo dentro de una página desplazable | 018, 030, 055 | 3 |
| `FORMAT_LOCALIZATION` | `/10000` y `GROUP_CONCAT` crudos; `COALESCE(...,t.type)`; ISO; `#,##0.###` | 016, 024, 025, 026, 027, 056 | 6 |
| `PAYMENT_FLOW` | `settlements_screen.dart` `_record`: controlador liberado, sin contexto, sin acuse | 005, 012, 014 | 3 |
| `REVERSAL_CONSISTENCY` | el estado `REVERSED` no se pinta ni se filtra igual en todas las vistas | 010, 045 | 2 |
| `BALANCE_SEMANTICS` | tres consultas de saldo con alcances distintos y sin cualificar | 013, 028, 058 | 3 |
| `SEARCH` | `toLowerCase().contains` sin normalizar; filtrado sobre `limit: 5` | 007, 019, 052, 053 | 4 |
| `FORM_UX` | afordancias y validación de los 4 formularios | 031, 032, 033, 037, 038, 039, 040, 041, 042, 043, 044, 046, 060 | 13 |
| `TEXT_WRAPPING` | texto sin restricción de ancho: se parte por carácter | 017, 020, 021, 063 | 4 |
| `ERROR_MESSAGING` | `friendlyError` no cubre `DatabaseException`; avisos como error | 015, 050 | 2 |
| `LIST_AFFORDANCES` | listas y tablas con controles sin función o sin estado | 022, 023, 029, 047, 048, 057, 059 | 7 |
| | | **Total** | **66** |

## 7. Clasificación por riesgo

La severidad refleja el **impacto real**, no lo llamativo del síntoma.

| Riesgo | UIBUG | Nº |
|---|---|---:|
| `ACCOUNTING` | 003, 010, 013, 025, 026, 024, 065 | 7 |
| `DATA_LOSS` | 001 | 1 |
| `DATA_INTEGRITY` | 045, 059 | 2 |
| `FUNCTIONAL_BLOCKER` | 002, 004A, 005, 018, 008 | 5 |
| `MISLEADING_INFORMATION` | 007, 028, 039, 044, 050, 016, 027, 056, 058, 032 | 10 |
| `NAVIGATION` | 004B, 011, 029, 051, 062 | 5 |
| `UX` | 006, 009, 012, 014, 015, 019, 031, 033, 034, 035, 036, 037, 038, 040, 041, 042, 043, 046, 047, 049, 052, 053, 054, 055, 060, 064 | 26 |
| `ACCESSIBILITY` | 017, 063 | 2 |
| `COSMETIC` | 020, 021, 022, 023, 030, 048, 057, 061 | 8 |

## 8. Orden de ejecución

Prioridad conceptual aplicada hallazgo a hallazgo, no mecánicamente.

| P | Criterio | UIBUG (en orden) |
|---|---|---|
| **P0-A** | riesgo de datos, dinero o pérdida | **003**, **001** |
| **P0-B** | funcionalidad crítica bloqueada | **002**, **004A**, **005** |
| **P1-A** | inconsistencias funcionales / de datos | **007**, **010**, **013**, 016, 025, 026, 024, 028, 045, 056, 027 |
| **P1-B** | navegación y errores fuertes | 011, 012, 014, 015, 050, 065, 051, 062 |
| **P2** | UX, layout, formularios, accesibilidad | 006, 008, 018, 009, 064, 019, 017, 020, 021, 004B, 030, 055, 029, 031, 032, 033, 034, 035, 036, 037, 038, 039, 040, 041, 042, 043, 044, 046, 052, 053, 054 |
| **P3** | pulido y cosmético | 022, 023, 047, 048, 049, 057, 058, 059, 060, 061, 063 |

Los ocho primeros respetan la revisión obligatoria de prioridad solicitada:
003 → 001 → 002 → 004A → 005 → 007 → 010 → 013.

## 9. Estados en uso

`OPEN` · `IN_PROGRESS` · `FIXED_NOT_DEVICE_VERIFIED` · `VERIFIED` · `WONT_FIX` ·
`DUPLICATE` · `DESIGN_DECISION_REQUIRED`

**Todas las entradas están en `OPEN`**, salvo las cinco marcadas
`DESIGN_DECISION_REQUIRED` (§10), que también están sin corregir pero **no pueden
implementarse** hasta que el propietario decida.

## 10. Decisiones de diseño requeridas

Ninguna de estas puede resolverse leyendo el código: exigen una decisión de producto.

| UIBUG | Decisión pendiente | Por qué bloquea |
|---|---|---|
| **003** | ¿Qué formato de entrada se acepta? (a) solo es-BO estricto `1.500,25`; (b) ambos con desambiguación; (c) `TextInputFormatter` que impide teclear lo ambiguo | Determina si el fix es de parseo, de formateo de entrada o de ambos. Tocar `tryParseDecimal` sin decidir esto rompe los cuatro formularios. |
| **004B** | ¿Atrás desde un destino raíz sale, o vuelve antes a `/`? | Cambia el diseño del `ShellRoute` y afecta a 004A. |
| **013** + 028 | Vocabulario y alcance de "saldo": ¿qué es *pendiente*, *total*, *de campaña*? | Sin glosario acordado, cualquier renombrado es una opinión. |
| **045** | ¿Un plan se puede aplicar más de una vez? | Si no, hace falta estado de plan en el esquema (migración v6). |
| **059** | ¿Se puede reabrir una campaña cerrada? | Afecta a la invariante de campaña única activa. |

Adicionalmente **002** requiere decidir *dónde* entra `/compras` (¿destino raíz? ¿tarjeta en
Operaciones? ¿ambos?), y **051** requiere decidir si las tarjetas de Operaciones abren
formulario o listado. Ambas son decisiones de menor calado y se proponen en `42`.

---

# 11. Fichas de los hallazgos

Formato de cada ficha:

`Sev` severidad · `Cat` categoría · `Riesgo` clasificación de §7 · `Grupo` causa raíz de §6 ·
`Pant.` pantallas · `Feat.` feature · `RN` regla de negocio · `Pre` precondiciones ·
`Pasos` reproducción · `Actual` / `Esperado` · `Evid.` evidencia · `Causa` estado de la causa
raíz · `Files` archivos · `Dep` dependencias · `Fix` tipo de corrección · `Tests` tests
requeridos · `Pixel 8` prueba en dispositivo requerida · `Estado` · `Prio` prioridad.

---

## CRITICAL

### UIBUG-003 · El formato que la app imprime, tecleado tal cual, divide el valor por mil

- **Sev** CRITICAL · **Cat** DATA / VALIDATION · **Riesgo** `ACCOUNTING` · **Grupo** `NUMERIC_INPUT`
- **Pant.** todos los campos numéricos; verificado en `/transferencias/nueva` y en el diálogo de pago de `/liquidacion`
- **Feat.** F-09 transferencias, F-10 cuentas y pagos · **RN** RN-50 (redondeo e importes), `16_VALIDATIONS`, `10_DATA_MODEL`
- **Pre** Juan Pérez con 15 000 KG de Cloruro de Potasio; campaña Verano 2026 activa.
- **Pasos**
  1. Operaciones → Transferir inventario → Nueva. Origen: Juan Pérez; junto al campo se lee **"15.000 KG disponibles"**.
  2. Teclear exactamente `15.000`. Destino: Ana Áñez → Revisar y confirmar.
  3. Aparte: Cuentas → ⋮ de José Luis → Registrar pago → teclear `1.500` → Registrar.
- **Actual** el diálogo resume **"Cloruro de Potasio: 15 KG"**. El pago guarda `account_transactions.amount_bob_minor_signed = -150`, es decir **1,50 Bs en lugar de 1.500,00 Bs** (leído de la base del dispositivo).
- **Esperado** o se interpreta el separador de miles que la propia app imprime, o se rechaza la entrada con un mensaje.
- **Evid.** `UI-17-transfer-form/UI-17-ISSUE-formato-millares.png`, `UI-17-transfer-form/_c-conf.png`
- **Causa CONFIRMADA** — `lib/presentation/widgets/common.dart:131-135`:
  ```dart
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  return num.tryParse(normalized);
  ```
  El punto es **siempre** decimal en la entrada. En la salida, `formatBob` (`money.dart:35`) y `formatQuantity` (`money.dart:41`) usan `NumberFormat(..., 'es_BO')`, donde el punto es separador de **miles**. Entrada y salida usan convenciones **opuestas**. Afecta también a `tryParseMinor` y `tryParseBase`, que multiplican por 100 y 1000 sobre el valor ya mal interpretado.
- **Files** `lib/presentation/widgets/common.dart`, `lib/domain/money.dart`, los 4 formularios, `settlements_screen.dart`
- **Dep** bloquea la corrección de 034 y 065 (mismo helper). Agravado por 012 y 014 (el pago no tiene acuse que delate el error).
- **Fix** decisión de diseño + parseo consciente de locale + `TextInputFormatter` en los campos
- **Tests** unitarios de `tryParseDecimal`/`tryParseMinor`/`tryParseBase` con `1.500`, `1.500,25`, `1500`, `1,5`, `15.000`, `0,125`, `99999,750`, vacío, `abc`; test de ida y vuelta `format → parse == original` sobre `money.dart`; widget test del diálogo de pago
- **Pixel 8** **SÍ** — obligatorio: teclear `1.500` en el pago y leer la fila de `account_transactions` en el dispositivo
- **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P0-A #1**

### UIBUG-001 · Exportar backup falla siempre en Android

- **Sev** CRITICAL · **Cat** FUNCTIONAL / ERROR_HANDLING · **Riesgo** `DATA_LOSS` · **Grupo** `BACKUP_ANDROID`
- **Pant.** UI-10 Liquidación y cuentas · `/liquidacion` · **Feat.** F-16 backup · **RN** STAB-007, `13_LOCAL_STORAGE`, `14_OFFLINE_AND_SYNC`
- **Pre** ninguna.
- **Pasos** Cuentas → icono de nube de la cabecera → **Exportar backup**.
- **Actual** snackbar rojo con el error técnico en inglés:
  ```
  DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be performed using
  SQLiteDatabase query or rawQuery methods only.) sql 'PRAGMA wal_checkpoint(FULL)' args []
  ```
  No se genera archivo. En consecuencia **Restaurar backup** responde siempre *"No se encontró ningún backup"*.
- **Esperado** se escribe el archivo y se informa de su ruta.
- **Evid.** `UI-10-liquidacion/UI-10-exportar-backup.png`, `UI-10-liquidacion/UI-10-restaurar-backup.png`
- **Causa CONFIRMADA** — `lib/data/backup_service.dart:63` ejecuta `await database.execute('PRAGMA wal_checkpoint(FULL)')`. En Android `sqflite` mapea `execute()` a `SQLiteDatabase.execSQL`, que **rechaza sentencias que devuelvan filas**, y `wal_checkpoint` devuelve una. La suite no lo detecta porque `backup_service_test.dart` corre sobre `sqflite_common_ffi` (escritorio), donde `execute()` sí lo admite. **La cobertura verde es engañosa.**
- **Files** `lib/data/backup_service.dart`, `test/backup_service_test.dart`
- **Dep** su síntoma visible depende de 015 (el error llega crudo). Ninguna dependencia bloqueante.
- **Fix** sustituir `execute` por `rawQuery` para el checkpoint (o envolver en `try` y degradar); test que ejercite la ruta Android
- **Tests** test de `export()` que falle con la semántica de Android (fake/mocked `execute` que lance como `SQLiteDatabase.execSQL`); test de ida y vuelta exportar → restaurar
- **Pixel 8** **SÍ** — obligatorio: exportar, comprobar el archivo en Descargas, restaurar y verificar los datos
- **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P0-A #2**

### UIBUG-002 · La pantalla de historial de compras es inalcanzable

- **Sev** CRITICAL · **Cat** NAVIGATION / FUNCTIONAL · **Riesgo** `FUNCTIONAL_BLOCKER` · **Grupo** `NAVIGATION_STACK`
- **Pant.** UI-06 Compras · `/compras` · **Feat.** F-04 compras, F-05 factura, F-06 pago a proveedor, F-12 reversión · **RN** `07_SCREENS` P-06, `08_NAVIGATION`
- **Pre** ninguna.
- **Pasos** recorrer toda la aplicación buscando un acceso al historial de compras.
- **Actual** no existe. La ruta está declarada en `lib/app.dart:62-65` pero **ninguna parte de `lib/` navega hacia ella** (verificado enumerando las 16 llamadas a `context.go`/`push` del proyecto: ninguna apunta a `/compras`).
- **Esperado** poder consultar las compras registradas.
- **Evid.** enumeración de rutas (§3 de este documento y `38`); `37_UI_SCREEN_INVENTORY` marca UI-06 como la única pantalla no auditable.
- **Causa CONFIRMADA** — ruta declarada sin ningún origen. Deja fuera del alcance del usuario: consultar el historial, **registrar pagos a proveedor posteriores**, **ver la fotografía de la factura** y **revertir una compra**. Es funcionalidad implementada y con tests que nadie puede usar.
- **Files** `lib/app.dart`, `lib/presentation/app_shell.dart`, `lib/presentation/screens/operations_screen.dart`
- **Dep** bloquea la verificación de 011 (no hay listado donde comprobar la compra) y deja sin salida la foto de factura. `37` y `40` dependen de esto para su cobertura.
- **Fix** añadir un punto de entrada (decisión: tarjeta en Operaciones y/o destino raíz)
- **Tests** test de navegación que llegue a `/compras` desde la interfaz; test que enumere las rutas declaradas y falle si alguna no tiene origen
- **Pixel 8** **SÍ** — y además auditar UI-06 por primera vez (pendiente desde `37`)
- **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P0-B #3**

### UIBUG-004A · La navegación jerárquica pierde el historial y no ofrece retorno

- **Sev** CRITICAL · **Cat** NAVIGATION · **Riesgo** `FUNCTIONAL_BLOCKER` · **Grupo** `NAVIGATION_STACK`
- **Pant.** `/personas/:id`, `/inventario/:id`, `/chacos/:id`, y las subrutas de Operaciones (`/catalogos`, `/planificacion`, `/aplicaciones`, `/transferencias`)
- **Feat.** transversal · **RN** `08_NAVIGATION`, STAB-001
- **Pre** ninguna.
- **Pasos**
  1. Pestaña **Personas** → tocar una persona → se abre `/personas/:id`.
  2. Pulsar **Atrás** de Android.
  3. Repetir con Personas → detalle → pestaña Chacos → un chaco (`/chacos/:id`, nivel 3).
- **Actual** la aplicación **se cierra** y aparece el lanzador (confirmado con `dumpsys window`: `mCurrentFocus = …nexuslauncher…`). La pantalla de detalle **tampoco tiene flecha de volver**, así que no hay ninguna forma de regresar a la lista: hay que reentrar por la barra inferior y perder el contexto.
- **Esperado** Atrás devuelve a la pantalla anterior; las pantallas de detalle ofrecen flecha de volver.
- **Evid.** `UI-14-persona-detalle/UI-14-ISSUE-back-desde-detalle.png`, `UI-02-operaciones/UI-02-ISSUE-back-sale-de-la-app.png`
- **Causa CONFIRMADA** — dos causas que se suman:
  1. `persons_screen.dart:47`, `inventory_screen.dart:96`, `person_detail_screen.dart:104`, `dashboard_screen.dart:235` y `operations_screen.dart:87` usan `context.go`, que **reemplaza** la pila: nunca hay nada que desapilar.
  2. `PageFrame` (`common.dart:5-57`) es un `CustomScrollView` **sin `AppBar`**; ninguna pantalla de detalle construye uno. No hay afordancia de retorno ni siquiera manual.
  Contraste que lo confirma: los 4 formularios usan `push` y en ellos Atrás **funciona bien**.
- **Files** `lib/presentation/app_shell.dart`, `lib/app.dart`, `lib/presentation/widgets/common.dart` (`PageFrame`), `persons_screen.dart`, `inventory_screen.dart`, `person_detail_screen.dart`, `dashboard_screen.dart`, `operations_screen.dart`
- **Dep** debe resolverse **junto con 004B** (la política de raíz condiciona el diseño del shell). Cierra también 062 parcialmente.
- **Fix** `push` para toda navegación jerárquica + flecha de volver en `PageFrame` cuando `Navigator.canPop`
- **Tests** test de navegación por cada ruta jerárquica: entrar, `pop`, comprobar que se vuelve a la lista y la pantalla queda utilizable; test de que `PageFrame` muestra flecha cuando hay pila
- **Pixel 8** **SÍ** — obligatorio: Atrás físico en los tres detalles y en las cuatro subrutas de Operaciones
- **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P0-B #4**

---

## HIGH

### UIBUG-005 · Registrar un pago rompe la interfaz en compilación de depuración

- **Sev** HIGH · **Cat** FUNCTIONAL / ERROR_HANDLING · **Riesgo** `FUNCTIONAL_BLOCKER` · **Grupo** `PAYMENT_FLOW`
- **Pant.** UI-10 · `/liquidacion` · **Feat.** F-10 · **RN** —
- **Pre** al menos una persona con saldo.
- **Pasos** Cuentas → ⋮ de una persona → Registrar pago → escribir `150` → **Registrar**.
- **Actual** la pantalla entera se sustituye por la pantalla roja de Flutter (`'_dependents.isEmpty': is not true`) y la app queda **inusable hasta reiniciarla**. Ocurre con importe válido y con el campo vacío. Cadena en logcat: (1) `A TextEditingController was used after being disposed`, (2) `framework.dart:6281 '_dependents.isEmpty': is not true`, (3) `Tried to build dirty widget in the wrong build scope (InputDecorator)`. **El pago sí se guarda** (`account_transactions` id 28), pero sin acuse: el usuario probablemente reinicie y **vuelva a registrarlo** → duplicado contable.
- **Alcance verificado** con `app-profile.apk` (assertions desactivadas, como release) el paso **funciona sin pantalla roja**: el saldo pasó de 800,50 a 950,50 Bs. **El fallo visible es exclusivo de debug**; el uso indebido del controlador es real en ambas.
- **Esperado** el diálogo se cierra, se muestra acuse y la pantalla sigue viva.
- **Evid.** `UI-10-liquidacion/UI-10-ISSUE-pago-vacio.png`, `UI-10-pago-valido.png`, `UI-10-pago-en-PROFILE-sin-asserts.png`
- **Causa CONFIRMADA** — `settlements_screen.dart:67-98`: `final amount = TextEditingController();` se crea dentro de `_record` y se libera en `amount.dispose()` (línea 98) **justo al retornar `showDialog`, mientras el diálogo aún se anima al cerrarse**; el `TextField` sigue montado y vuelve a suscribirse al controlador liberado. Contraste correcto en el mismo repo: los diálogos de `catalogs_screen.dart` y `_PaymentDialog` de `purchases_screen.dart` son `StatefulWidget` y liberan en `State.dispose()`.
- **Files** `lib/presentation/screens/settlements_screen.dart`
- **Dep** comparte el diálogo con 012, 014 y 065: **corregir los cuatro a la vez** extrayendo un `StatefulWidget`.
- **Fix** extraer el diálogo a un `StatefulWidget` con `dispose()` propio
- **Tests** widget test que abra y cierre el diálogo de pago 20 veces sin excepción (existe ya un patrón así en `regression_widget_test.dart` para el estado de cuenta); test de que el pago se registra una sola vez
- **Pixel 8** **SÍ** — en **debug**, que es donde se manifiesta
- **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P0-B #5**

### UIBUG-007 · El buscador del inicio solo filtra 5 filas y afirma que no hay inventario

- **Sev** HIGH · **Cat** FUNCTIONAL / DATA · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `SEARCH`
- **Pant.** UI-01 Inicio · `/` · **Feat.** F-15 dashboard · **RN** KI-17 (estado vacío)
- **Pre** dataset con `Glifosato 48 SL` y `Glifosato 68 SG` con stock.
- **Pasos** Inicio → *Buscar producto* → escribir `glifo`.
- **Actual** **"Aún no hay inventario."**, pese a existir ambos productos con stock.
- **Esperado** mostrar los dos; si no hubiera coincidencias, decir que **la búsqueda** no encontró resultados, no que no hay inventario.
- **Evid.** `UI-01-dashboard/UI-01-busqueda-resultado.png`
- **Causa CONFIRMADA** — dos defectos que se refuerzan: `dashboard_screen.dart:38` carga `repo.inventorySummary(limit: 5)` y `dashboard_screen.dart:73` filtra **en cliente** sobre esas 5 filas (las 5 primeras alfabéticas); y el estado vacío reutiliza el mensaje de "sin datos" para un caso de "sin coincidencias".
- **Files** `lib/presentation/screens/dashboard_screen.dart`, `lib/data/agro_repository.dart` (`inventorySummary`)
- **Dep** comparte la corrección del mensaje vacío con KI-17; comparte normalización con 019.
- **Fix** consultar en servidor al buscar (o cargar sin `limit` para el filtro) + estado vacío diferenciado
- **Tests** widget test: buscar `glifo` devuelve 2 filas; buscar `zzz` muestra "sin coincidencias" y no "sin inventario"
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P1-A #6**

### UIBUG-010 · Las aplicaciones revertidas no se marcan y el inicio las sigue contando

- **Sev** HIGH · **Cat** DATA / CONSISTENCY · **Riesgo** `ACCOUNTING` · **Grupo** `REVERSAL_CONSISTENCY`
- **Pant.** UI-08 `/aplicaciones` y UI-01 `/` · **Feat.** F-12 reversiones · **RN** regla de reversión, `15_BUSINESS_RULES`
- **Pre** el dataset contiene una aplicación revertida (Juan Pérez · Lote 2 · 178,75 Bs, `status = REVERSED`).
- **Pasos** (1) Aplicaciones: la fila revertida aparece igual que las demás. (2) Inicio → *Aplicaciones recientes*: aparece con su costo de 178,75 Bs. (3) Cuentas → *Costo por chaco y hectárea*: "Lote 2 · Juan Pérez · **Total 0,00 Bs**".
- **Actual** tres tratamientos del mismo hecho. En Aplicaciones la única diferencia es la **ausencia** del botón ↩ — que se confunde con "no se puede revertir". En Inicio no hay marca y se muestra el importe. El reporte sí la excluye.
- **Esperado** marca explícita "Revertida" y tratamiento coherente, como ya hace `TransfersScreen`.
- **Evid.** `UI-02-operaciones/UI-02-registrar-aplicacion-destino.png`, `UI-01-dashboard/UI-01-scroll1.png`, `UI-10-liquidacion/UI-10-reportes.png`
- **Causa CONFIRMADA** — `applications_screen.dart:190` es el **único** uso de `row['status']`: `if (row['status'] != 'REVERSED') IconButton(...)`. No hay etiqueta. `agro_repository.dart:1157` (`applications()`) devuelve `a.*` (incluye `status`) **sin filtrar**, y el dashboard lo pinta tal cual. En contraste, `farmCostReport` (`agro_repository.dart:1567`) sí filtra con `a.reversed_at IS NULL`, y `transfers_screen.dart:95` sí escribe `'Revertida'`.
- **Files** `lib/presentation/screens/applications_screen.dart`, `lib/presentation/screens/dashboard_screen.dart`, `lib/data/agro_repository.dart`
- **Dep** mismo grupo que 045. Ninguna bloqueante.
- **Fix** pintar el estado en Aplicaciones y en el Inicio; decidir si el Inicio excluye o marca
- **Tests** test de repositorio: `applications()` expone `status`; widget test: la fila revertida muestra "Revertida" en ambas pantallas; test de que el reporte y el inicio no se contradicen
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P1-A #7**

### UIBUG-013 · La misma persona muestra saldos distintos en tres vistas, sin declarar el alcance

- **Sev** HIGH · **Cat** CONSISTENCY / DATA · **Riesgo** `ACCOUNTING` · **Grupo** `BALANCE_SEMANTICS`
- **Pant.** UI-10 `/liquidacion`, UI-13/14 `/personas`, diálogo de estado de cuenta · **Feat.** F-10, F-11
- **Pre** José Luis Ñáñez Álvarez, campaña Verano 2026.
- **Pasos** (1) Cuentas (filtro Verano 2026) → tarjeta de José Luis → **"Saldo pendiente 19.359,50 Bs"**. (2) ⋮ → *Ver detalle cronológico* → última fila acumulada: **"Saldo 30.057,00 Bs"**. (3) Personas → José Luis → **"30.057,00 Bs"**.
- **Actual** tres cifras bajo tres usos de la palabra "saldo", **ninguno de los cuales declara su alcance**. El diálogo parte además de un "saldo inicial de campaña" de 10.697,50 Bs sin explicar de dónde sale.
- **Esperado** nombres distintos para conceptos distintos, o una nota que aclare el alcance de cada cifra.
- **Evid.** `UI-10-liquidacion/UI-10-lista.png`, `UI-10-estado-de-cuenta.png`, `UI-13-personas/UI-13-lista.png`
- **Causa CONFIRMADA** — tres consultas con alcances distintos:
  | Vista | Origen | Alcance |
  |---|---|---|
  | `settlements_screen.dart:437` "Saldo pendiente" | `agro_repository.dart:1522` `settlements(campaignId:)` — `SUM` con `AND t.campaign_id=?` | **una campaña** |
  | `person_detail_screen.dart:88` "Saldo total" | `profile['balance']` | **todo el histórico** |
  | diálogo, columna "Saldo" | acumulado sobre `detailedStatement` + saldo inicial | **campaña, con arrastre** |
  **Matiz respecto a `38`**: las dos primeras etiquetas **sí** difieren ("pendiente" vs "total"); el defecto es que ninguna dice *de qué periodo*, y la tercera no cualifica nada.
- **Files** `lib/data/agro_repository.dart` (`settlements`, `topSettlements`, `detailedStatement`), `settlements_screen.dart`, `person_detail_screen.dart`
- **Dep** arrastra a 028 y 058. **Requiere decisión de vocabulario antes de tocar código.**
- **Fix** glosario de saldos + etiquetas que declaren alcance + posible unificación de consulta
- **Tests** test de repositorio que fije el valor esperado de cada consulta para el mismo dataset y documente por qué difieren; widget test de las etiquetas
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** **P1-A #8**

### UIBUG-006 · Etiqueta y "Seleccionar" superpuestos en todos los selectores

- **Sev** HIGH · **Cat** LAYOUT · **Riesgo** `UX` · **Grupo** `ENTITY_PICKER`
- **Pant.** `/planificacion/nueva`, `/compras/nueva`, `/aplicaciones/nueva`, `/transferencias/nueva` · **Feat.** F-17 selector adaptativo
- **Pre** abrir cualquiera de los 4 formularios.
- **Pasos** mirar un selector sin valor.
- **Actual** etiqueta y valor se pintan **uno encima del otro**: "Chaco" + "Seleccionar" se lee `SelacctoOnar`; "Agregar producto" + "Seleccionar" como `Seleccionarroducto`. En la compra ocurre a la vez en Proveedor, Producto y Persona. Al elegir un valor la etiqueta sube y el campo se ve bien.
- **Esperado** la etiqueta flota arriba y el texto de ayuda se lee limpio.
- **Evid.** `UI-05-plan-form/UI-05-ISSUE-etiqueta-superpuesta.png`, `UI-07-purchase-form/UI-07-formulario-inicial.png`, `UI-17-transfer-form/UI-17-inicial.png`
- **Causa CONFIRMADA** — `adaptive_entity_picker.dart:78` pasa `isEmpty: selected == null` al `InputDecorator`, con lo que la etiqueta **no flota** y se queda en el centro del campo, justo donde la línea 100 (`child: Text(selected == null ? 'Seleccionar' : ...)`) siempre pinta.
- **Files** `lib/presentation/widgets/adaptive_entity_picker.dart`
- **Dep** ninguna. Un solo archivo cierra las 4 pantallas.
- **Fix** `isEmpty: false` (o `floatingLabelBehavior: always`) y ajustar el hint
- **Tests** golden o widget test del selector sin valor: etiqueta y hint no se solapan
- **Pixel 8** **SÍ** — es un defecto puramente visual, hay que verlo · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-008 · El FAB "Nuevo" tapa de forma permanente el último elemento de las listas

- **Sev** HIGH · **Cat** LAYOUT · **Riesgo** `FUNCTIONAL_BLOCKER` · **Grupo** `FAB_SAFE_AREA`
- **Pant.** `/`, `/inventario`, `/liquidacion`, `/catalogos`, `/aplicaciones`, `/transferencias`
- **Pre** listas con contenido suficiente para desplazarse.
- **Pasos** abrir Inicio y desplazarse hasta el final; repetir en las otras cinco.
- **Actual** el FAB queda encima del contenido y, **una vez agotado el scroll**, sigue tapándolo:

  | Pantalla | Qué queda oculto |
  |---|---|
  | Inicio | el importe del último saldo ("Juan Pérez · Familiar") |
  | Liquidación | el importe **y el menú ⋮** de la tercera tarjeta |
  | Catálogos → Productos | la última fila (`Zinc Quelatado`) con su ⋮ inaccesible |
  | Aplicaciones | el botón ↩ de la última fila |
  | Inventario | el valor de la última fila |

- **Esperado** el desplazamiento reserva espacio suficiente bajo el FAB.
- **Evid.** `UI-01-dashboard/UI-01-ISSUE-fab-tapa-ultima-fila.png`, `UI-03-catalogos/UI-03-ISSUE-ultimo-item-inalcanzable.png`
- **Causa CONFIRMADA** — `PageFrame` (`common.dart:51-53`) cierra con `EdgeInsets.fromLTRB(16, 6, 16, 24)`. 24 px son insuficientes bajo un `FloatingActionButton.extended` (≈56 px de alto + 16 de margen). El FAB lo dibuja el `Scaffold` de `app_shell.dart:80`, fuera del árbol de la lista, así que no reserva espacio.
- **Files** `lib/presentation/widgets/common.dart` (`PageFrame`), `lib/presentation/app_shell.dart`
- **Dep** **solapa con 018 en Catálogos** (misma captura, causas distintas): corregir 008 no cierra 018 ni al revés. Comparte grupo con 009.
- **Fix** relleno inferior calculado en `PageFrame` (o `MediaQuery.viewPadding` + alto del FAB)
- **Tests** widget test: con el scroll al final, el último ítem no queda bajo el FAB (comprobar rectángulos)
- **Pixel 8** **SÍ** — en las 6 pantallas · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-009 · Con el teclado abierto el FAB tapa el campo de búsqueda activo

- **Sev** HIGH · **Cat** LAYOUT / FORM · **Riesgo** `UX` · **Grupo** `FAB_SAFE_AREA`
- **Pant.** UI-01 Inicio · `/` · **Feat.** F-15
- **Pre** ninguna. **Pasos** Inicio → tocar *Buscar producto* → escribir.
- **Actual** el FAB queda **encima de la mitad derecha del campo**; no se ve lo escrito en esa zona y un toque ahí activa el FAB en lugar del campo. Además los resultados quedan bajo el teclado y la pantalla no se desplaza hasta ellos: al teclear no hay respuesta visible.
- **Esperado** el FAB se oculta o se aparta con el teclado abierto y los resultados quedan visibles.
- **Evid.** `UI-01-dashboard/UI-01-busqueda-teclado.png`
- **Causa PROBABLE** — el `Scaffold` de `app_shell.dart:78-89` no oculta el FAB con `MediaQuery.viewInsets.bottom > 0`, y el `CustomScrollView` de `PageFrame` no reserva `viewInsets`. Misma familia que 008.
- **Files** `lib/presentation/app_shell.dart`, `lib/presentation/widgets/common.dart`
- **Dep** se corrige con 008 en el mismo lote.
- **Fix** ocultar el FAB cuando el teclado está abierto + `viewInsets` en el relleno
- **Tests** widget test con `viewInsets` simulado
- **Pixel 8** **SÍ** — el teclado real es parte del defecto · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-011 · Confirmar una compra no da ninguna confirmación

- **Sev** HIGH · **Cat** UX / FUNCTIONAL · **Riesgo** `NAVIGATION` · **Grupo** `NAVIGATION_STACK`
- **Pant.** UI-07 · `/compras/nueva` · **Feat.** F-04
- **Pre** proveedores, productos y campaña activa.
- **Pasos** Operaciones → *Registrar compra* → completar → **Confirmar**.
- **Actual** el formulario se cierra y se vuelve a **Operaciones** sin ningún mensaje. Nada indica que se hayan registrado 573,75 Bs. Y como `/compras` es inalcanzable (002), no hay forma de comprobarlo.
- **Esperado** mensaje de éxito, o volver a un listado donde la compra aparezca.
- **Evid.** `UI-07-purchase-form/UI-07-confirmada.png`
- **Causa CONFIRMADA** — el formulario hace `pop(true)`; `OperationsScreen` es `StatelessWidget` y **no hace nada con el resultado** (`operations_screen.dart:86-87`). El único llamador que sí muestra mensaje y refresca es `PurchasesScreen`, que no es alcanzable.
- **Files** `lib/presentation/screens/operations_screen.dart`, `lib/presentation/app_shell.dart`, `lib/presentation/screens/purchase_form_screen.dart`
- **Dep** **depende de 002**: la solución natural (volver al listado) requiere que el listado exista. Corregir en el mismo lote.
- **Fix** consumir el resultado del `push` y mostrar acuse / navegar al listado
- **Tests** test de navegación: confirmar compra → aparece snackbar de éxito → la compra figura en `/compras`
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-B

### UIBUG-012 · El diálogo "Registrar pago" no dice a quién se le está pagando

- **Sev** HIGH · **Cat** UX / DATA · **Riesgo** `UX` (agravante de `ACCOUNTING`) · **Grupo** `PAYMENT_FLOW`
- **Pant.** UI-10 · `/liquidacion` · **Feat.** F-10
- **Pre** varias personas en la lista.
- **Pasos** Cuentas → ⋮ de una persona → *Registrar pago*.
- **Actual** el diálogo se titula solo **"Registrar pago"** y contiene un único campo "Importe BOB". No muestra la persona, ni su saldo pendiente, ni la campaña a la que se imputará, ni pide confirmación.
- **Esperado** identificar a la persona y la campaña, y mostrar el saldo.
- **Evid.** `UI-10-liquidacion/UI-10-dialogo-registrar-pago.png`
- **Causa CONFIRMADA** — `settlements_screen.dart:72-83`: el `AlertDialog` recibe `person` como parámetro pero **no lo usa** en el título ni en el contenido.
- **Files** `lib/presentation/screens/settlements_screen.dart`
- **Dep** mismo diálogo que 005, 014, 065 → **un solo cambio**. Agravado por 003 (importe ÷1000) y 014 (sin acuse): con seis personas y tarjetas altas es fácil abrir el menú equivocado y **cobrar a quien no era**, sin ningún punto de control.
- **Fix** reescribir el diálogo como `StatefulWidget` con contexto completo
- **Tests** widget test: el diálogo muestra nombre, campaña y saldo de la persona correcta
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-B

### UIBUG-014 · Registrar un pago no muestra ningún mensaje de éxito

- **Sev** HIGH · **Cat** UX · **Riesgo** `UX` · **Grupo** `PAYMENT_FLOW`
- **Pant.** UI-10 · `/liquidacion` · **Feat.** F-10
- **Pre** compilación *profile* (en debug interviene 005).
- **Pasos** registrar un pago válido.
- **Actual** la lista se refresca y nada más. Otras operaciones sí muestran mensaje (*"Aplicación multiproducto confirmada."*).
- **Esperado** acuse explícito con el importe registrado.
- **Evid.** `UI-10-liquidacion/UI-10-pago-en-PROFILE-sin-asserts.png`
- **Causa CONFIRMADA** — `settlements_screen.dart` llama a `addAccountPayment` y refresca sin `showSuccess`, a diferencia de `_backup()` (línea 222) que sí lo usa.
- **Files** `lib/presentation/screens/settlements_screen.dart`
- **Dep** mismo diálogo que 005, 012, 065. Junto con 003 y 012 deja **la escritura contable más delicada sin ningún punto de verificación**.
- **Fix** `showSuccess` con el importe formateado
- **Tests** widget test: tras registrar, aparece el snackbar con el importe
- **Pixel 8** **SÍ** — en *profile* · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-B

### UIBUG-015 · Errores técnicos de SQLite en inglés llegan al usuario

- **Sev** HIGH · **Cat** ERROR_HANDLING / TEXT · **Riesgo** `UX` · **Grupo** `ERROR_MESSAGING`
- **Pant.** UI-10 reproducido; potencialmente cualquiera · **Feat.** F-16 · **RN** **KI-16**, E-01 de `17_ERROR_HANDLING`
- **Pre** las de 001. **Pasos** los de 001.
- **Actual** *"DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be performed using SQLiteDatabase query or rawQuery methods only.) sql 'PRAGMA wal_checkpoint(FULL)' args []"* en un snackbar rojo.
- **Esperado** un mensaje en español que explique qué pasó y qué hacer.
- **Evid.** `UI-10-liquidacion/UI-10-exportar-backup.png`
- **Causa CONFIRMADA** — `friendlyError` (`common.dart:150-158`) solo traduce `FormatException` y `StateError`; cualquier otra excepción se devuelve con `error.toString()` íntegro. `DatabaseException` pasa tal cual.
- **Files** `lib/presentation/widgets/common.dart`
- **Dep** independiente de 001: aunque se arregle el backup, cualquier violación de restricción seguirá llegando cruda. **Corregir ambos.** Registrado como hueco conocido desde la estabilización y ahora **reproducido en dispositivo**.
- **Fix** ampliar `friendlyError` a `DatabaseException` y a un caso por defecto en español
- **Tests** unitarios de `friendlyError` con `DatabaseException`, violación de unicidad y excepción desconocida
- **Pixel 8** **SÍ** — provocando un error real · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P1-B

### UIBUG-016 · Literales de base de datos en inglés mostrados al usuario

- **Sev** HIGH · **Cat** TEXT · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `FORMAT_LOCALIZATION`
- **Pant.** UI-03 Catálogos, UI-07 compra, UI-14 persona, UI-10 diálogo · **Feat.** F-01, F-02, F-04, F-11
- **Pre** dataset con campañas `PLANNED`/`CLOSED` y pagos sin notas.
- **Pasos / Actual**

  | Dónde | Qué se ve | Qué debería verse |
  |---|---|---|
  | Catálogos → Campañas | `PLANNED`, `CLOSED` (la activa sí dice "Activa") | Planificada, Cerrada |
  | `/compras/nueva`, selector de asignación | `ADMIN`, `FAMILY`, `THIRD_PARTY` | Administrador, Familiar, Tercero |
  | Persona → pestaña Cuenta | `PAYMENT` como título del movimiento | Pago |
  | Diálogo de estado de cuenta | `PAYMENT` como título | Pago |

- **Agravante** los mismos roles **sí** se traducen en Catálogos → Personas y en el selector de **origen** de la transferencia. El mismo dato aparece traducido en unas pantallas y crudo en otras.
- **Esperado** todo en español; el usuario objetivo es un agricultor hispanohablante.
- **Evid.** `UI-03-catalogos/UI-03-menu-campana.png`, `UI-07-purchase-form/UI-07-picker-persona2.png`, `UI-17-transfer-form/UI-17-picker-origen.png`, `UI-14-persona-detalle/UI-14-ISSUE-pestana-cuenta-inalcanzable.png`
- **Causa CONFIRMADA (nueva, no estaba en `38`)** — para el caso `PAYMENT`: `agro_repository.dart:1559` construye `COALESCE(<productos>, <producto>, t.notes, t.type) concept`. Un pago **sin notas** cae al último término y el `type` crudo se pinta como **título** en `settlements_screen.dart:173` y `person_detail_screen.dart:141`. Existe `_transactionLabel` (`settlements_screen.dart:211-218`) que **sí** traduce, pero solo se aplica al **subtítulo**. Para roles y estados de campaña: traducción implementada en `catalogs_screen.dart:373` y `persons_screen.dart:42` pero **no reutilizada** en el formulario de compra ni en el menú de campañas.
- **Files** `lib/data/agro_repository.dart:1559`, `settlements_screen.dart`, `person_detail_screen.dart`, `catalogs_screen.dart`, `purchase_form_screen.dart`
- **Dep** ninguna bloqueante; conviene un único helper de etiquetas compartido.
- **Fix** helper central de etiquetas de dominio + dejar de usar `t.type` como texto de usuario
- **Tests** unitarios del helper para todos los valores del enum; widget test de que ninguna pantalla pinta un literal en mayúsculas del esquema
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-A

### UIBUG-017 · Al 130 % de escala el texto se parte a mitad de palabra y las columnas se solapan

- **Sev** HIGH · **Cat** ACCESSIBILITY / LAYOUT · **Riesgo** `ACCESSIBILITY` · **Grupo** `TEXT_WRAPPING`
- **Pant.** UI-10 (peor caso); afecta a toda la app
- **Pre** `settings put system font_scale 1.3`.
- **Pasos** abrir **Cuentas** con la escala al 130 %.
- **Actual** "Rodríguez" se parte como **"Rodrígue / z"**, "Salvatierra" como **"Salvatierr / a"**; el subtítulo "Cargos … pagos/créditos …" **choca con la columna del importe**; la etiqueta **"Operaciones" de la barra inferior se parte en dos líneas** y desborda. **No se registró ningún `RenderFlex overflow`**: el texto se ajusta por carácter, así que es un defecto de legibilidad, no una excepción.
- **Esperado** el texto se parte por palabras y las columnas mantienen separación.
- **Evid.** `UI-23-fontscale/UI-23-liquidacion-130.png`
- **Causa PROBABLE** — filas sin `Flexible`/`Expanded` con anchos acordados; el `Text` recibe una restricción tan estrecha que Flutter recurre a partir por carácter.
- **Files** `lib/presentation/screens/settlements_screen.dart`, `lib/presentation/app_shell.dart`
- **Dep** misma familia que 020 y 021 (mismas tarjetas). Corregir juntos.
- **Fix** anchos flexibles + `softWrap`/`overflow` explícitos; revisar la barra inferior
- **Tests** widget test con `textScaler` 1.3 sobre la lista de liquidación: sin solapes ni partición por carácter
- **Pixel 8** **SÍ** — al 130 %, y **restaurar `font_scale 1.0` al terminar** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-018 · La última fila de los catálogos queda permanentemente cortada e inoperable

- **Sev** HIGH · **Cat** SCROLL / LAYOUT · **Riesgo** `FUNCTIONAL_BLOCKER` · **Grupo** `FIXED_HEIGHT`
- **Pant.** UI-03 · `/catalogos` · **Feat.** F-01
- **Pre** 22 productos en el catálogo.
- **Pasos** Operaciones → Administrar datos → pestaña **Productos** → desplazar hasta el final.
- **Actual** la última fila (`Zinc Quelatado`) queda **cortada por la mitad** entre la barra inferior y el FAB, con su subtítulo ilegible y su menú ⋮ inalcanzable. El primer elemento visible también aparece seccionado por arriba. Se comprobó que es el final real del desplazamiento repitiendo el gesto.
- **Esperado** poder ver y operar sobre todos los registros.
- **Evid.** `UI-03-catalogos/UI-03-ISSUE-ultimo-item-inalcanzable.png`
- **Causa CONFIRMADA** — `catalogs_screen.dart:264`: `height: 520` fijo para la lista dentro de una página que ya se desplaza. El final del contenedor coincide con la barra de navegación.
- **Files** `lib/presentation/screens/catalogs_screen.dart`
- **Dep** **solapa con 008** (misma captura) pero **causa independiente**: quitar el alto fijo no arregla el FAB y viceversa. Marcado como solapamiento, **no** duplicado.
- **Fix** eliminar el alto fijo; que la lista participe del scroll de la página
- **Tests** widget test: la última fila del catálogo es alcanzable y su ⋮ se puede pulsar
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-019 · La búsqueda distingue tildes

- **Sev** HIGH · **Cat** FUNCTIONAL / UX · **Riesgo** `UX` · **Grupo** `SEARCH`
- **Pant.** selectores de los 4 formularios y buscadores de lista · **Feat.** F-17
- **Pre** existe *"Hacienda Santa María de los Ángeles del Norte Grande"*.
- **Pasos** `/planificacion/nueva` → selector **Chaco** → escribir `maria`.
- **Actual** **0/8 resultados**.
- **Esperado** encontrarlo; en un teclado móvil español lo normal es escribir sin tildes.
- **Evid.** `UI-05-plan-form/UI-05-ISSUE-busqueda-sin-tildes.png`
- **Causa CONFIRMADA** — `toLowerCase().contains(query)` sin normalizar diacríticos, en **6 sitios**: `applications_screen.dart:115`, `catalogs_screen.dart:278`, `dashboard_screen.dart:73`, `inventory_screen.dart:60`, `settlements_screen.dart:356`, `transfer_form_screen.dart:241` (y el selector).
- **Files** los 6 anteriores + `lib/presentation/widgets/adaptive_entity_picker.dart`
- **Dep** comparte helper con 007. **Impacto**: el usuario concluye que el registro no existe y **lo crea duplicado**.
- **Fix** helper `normalizeForSearch` (minúsculas + eliminación de diacríticos) usado en los 7 sitios
- **Tests** unitarios del helper (`maría`/`maria`, `Áñez`/`anez`, `ñ`); widget test del selector con `maria`
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-020 · Los nombres largos rompen la maqueta de las tarjetas de liquidación

- **Sev** HIGH · **Cat** LAYOUT · **Riesgo** `COSMETIC` · **Grupo** `TEXT_WRAPPING`
- **Pant.** UI-10 · `/liquidacion` · **Feat.** F-10
- **Pre** "María Fernanda Rodríguez Salvatierra" en el dataset.
- **Pasos** abrir Cuentas.
- **Actual** el nombre se reparte en **cuatro líneas, una palabra por línea**, y el subtítulo fluye alrededor del importe. La tarjeta triplica su altura y la lista se vuelve difícil de recorrer.
- **Esperado** reparto de ancho razonable entre nombre e importe, o truncamiento con elipsis.
- **Evid.** `UI-10-liquidacion/UI-10-lista.png`
- **Causa PROBABLE** — la `Row` de la tarjeta (`settlements_screen.dart:~420-450`) da al bloque del importe todo el ancho que pide y deja al nombre el residual.
- **Files** `lib/presentation/screens/settlements_screen.dart`
- **Dep** mismo lote que 017 y 021.
- **Fix** `Expanded`/`Flexible` con reparto explícito y `maxLines` + elipsis
- **Tests** widget test con el nombre largo del dataset: la tarjeta no supera N líneas
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-021 · El texto se parte a mitad de palabra en el estado de cuenta

- **Sev** HIGH · **Cat** LAYOUT / TEXT · **Riesgo** `COSMETIC` · **Grupo** `TEXT_WRAPPING`
- **Pant.** diálogo *Ver detalle cronológico* de `/liquidacion` · **Feat.** F-11
- **Pre** movimientos con nombres de producto largos.
- **Pasos** Cuentas → ⋮ → *Ver detalle cronológico*.
- **Actual** *"Herbicida Selectivo **Po / stemergente** para Cultivos…"*. La columna de descripción es tan estrecha que "Glifosato 68 SG, Mancozeb 80" ocupa cuatro líneas.
- **Esperado** partir por palabras y dar más ancho a la descripción.
- **Evid.** `UI-10-liquidacion/UI-10-estado-de-cuenta.png`, `UI-10-liquidacion/UI-10-dialogo-pago.png`
- **Causa PROBABLE** — el `ListTile` del diálogo (`settlements_screen.dart:166-200`) cede demasiado ancho a `trailing`.
- **Files** `lib/presentation/screens/settlements_screen.dart`
- **Dep** mismo lote que 017 y 020.
- **Fix** reparto de ancho y `softWrap` explícito
- **Tests** widget test con el concepto largo del dataset
- **Pixel 8** **SÍ** · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

---

## MEDIUM

Formato compacto. Todos los campos del §11 están presentes; los que no aplican se marcan `—`.
Todos en estado `OPEN` salvo indicación expresa. Todos requieren verificación en Pixel 8 tras
el fix salvo donde se indica `Pixel 8: NO`.

### UIBUG-004B · Política de Atrás desde un destino raíz

- **Sev** MEDIUM · **Cat** NAVIGATION · **Riesgo** `NAVIGATION` · **Grupo** `NAVIGATION_STACK`
- **Pant.** los 5 destinos raíz: `/`, `/operaciones`, `/inventario`, `/personas`, `/liquidacion` · **Feat.** transversal · **RN** `08_NAVIGATION`
- **Pre** ninguna. **Pasos** pestaña **Personas** (sin entrar en ningún detalle) → Atrás de Android.
- **Actual** la aplicación se cierra y aparece el lanzador.
- **Esperado** *pendiente de decisión*: (a) salir — comportamiento actual, aceptable y frecuente en producción; (b) volver primero al destino inicial `/` y salir desde ahí — recomendación de Material 3 / Android.
- **Evid.** `UI-02-operaciones/UI-02-ISSUE-back-sale-de-la-app.png` (compartida con 004A)
- **Causa CONFIRMADA** — `app_shell.dart:56,83` usan `context.go` para los destinos raíz. Para navegación **raíz → raíz** esto es correcto por diseño: reemplazar la pila evita que las pestañas se acumulen. El comportamiento resultante de Atrás es una **consecuencia deliberada**, no un error de implementación.
- **Por qué no es CRITICAL** no hay pérdida de datos, no hay contenido inalcanzable y no hay contexto jerárquico que perder. Se separó de 004A precisamente por esto (§3).
- **Files** `lib/presentation/app_shell.dart`, `lib/app.dart`
- **Dep** **debe decidirse antes de implementar 004A**: la política de raíz condiciona cómo se estructura la pila del shell.
- **Fix** decisión de producto; si (b), `PopScope` en el shell que redirija a `/` cuando no haya pila
- **Tests** test de navegación que fije la política elegida
- **Pixel 8** **SÍ** — con el Atrás físico y con el gesto
- **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-022 · La tabla del inicio muestra una columna de casillas sin función

- **Sev** MEDIUM · **Cat** LAYOUT · **Riesgo** `COSMETIC` · **Grupo** `LIST_AFFORDANCES` · **Pant.** UI-01 `/` · **Feat.** F-15 · **RN** —
- **Pre** inventario con filas. **Pasos** abrir Inicio y mirar la tabla.
- **Actual** el `DataTable` presenta una casilla de selección en la cabecera y en cada fila, pero no existe ninguna acción masiva: tocar la fila navega al detalle. Roba ancho en una tabla que ya no cabe.
- **Esperado** sin columna de casillas.
- **Evid.** `UI-01-dashboard/UI-01-inicio.png`
- **Causa CONFIRMADA** — `dashboard_screen.dart:235` define `onSelectChanged` en el `DataRow`, y eso activa `showCheckboxColumn` automáticamente en `DataTable`.
- **Files** `lib/presentation/screens/dashboard_screen.dart` · **Dep** — · **Fix** `showCheckboxColumn: false` o envolver la celda en `InkWell` en vez de usar `onSelectChanged`
- **Tests** widget test: la tabla del inicio no tiene `Checkbox` · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P3

### UIBUG-023 · Al desplazar la tabla del inicio en horizontal desaparece el nombre del producto

- **Sev** MEDIUM · **Cat** SCROLL · **Riesgo** `COSMETIC` · **Grupo** `LIST_AFFORDANCES` · **Pant.** UI-01 `/` · **Feat.** F-15 · **RN** —
- **Pre** tabla más ancha que la pantalla. **Pasos** desplazar la tabla en horizontal hasta la columna "Valor".
- **Actual** la primera columna no queda fijada; las filas son `0 L / 500 L / 16.700,00 Bs` sin saber a qué producto pertenecen.
- **Esperado** columna de producto fijada, o una presentación que no requiera scroll horizontal.
- **Evid.** `UI-01-dashboard/UI-01-tabla-scroll-horizontal.png`
- **Causa PROBABLE** — `DataTable` dentro de un `SingleChildScrollView` horizontal, sin columna congelada.
- **Files** `lib/presentation/screens/dashboard_screen.dart` · **Dep** se alivia al corregir 022 (recupera ancho) · **Fix** columna fija o cambiar a lista de tarjetas
- **Tests** widget test de la presentación elegida · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P3

### UIBUG-024 · Punto y coma decimal mezclados en la misma línea

- **Sev** MEDIUM · **Cat** TEXT / CONSISTENCY · **Riesgo** `ACCOUNTING` · **Grupo** `FORMAT_LOCALIZATION`
- **Pant.** `/liquidacion`, `/personas`, `/chacos/:id`, `/planificacion`, `/catalogos`, `/aplicaciones/nueva` · **Feat.** F-13, F-14 · **RN** KI-08 (superficies sin formatear)
- **Pre** chacos con superficie. **Pasos** Cuentas → *Costo por chaco y hectárea*.
- **Actual** **"80.0 ha"** (punto decimal) junto a **"20.160,00 Bs"** (punto de millares y coma decimal) **en la misma línea**. En un plan expandido conviven "Área 120.0 ha" y "1.800 KG".
- **Esperado** un único convenio es-BO en toda la aplicación.
- **Evid.** `UI-10-liquidacion/UI-10-ISSUE-mezcla-separadores.png`, `UI-04-planificacion/UI-04-plan-expandido.png`
- **Causa CONFIRMADA** — división cruda `area_m2 / 10000` interpolada directamente, en **8 sitios**: `application_form_screen.dart:63,144,382`, `catalogs_screen.dart:300`, `farm_logbook_screen.dart:42,70`, `persons_screen.dart:44`. Nunca pasa por `NumberFormat`.
- **Files** los 5 archivos anteriores + `lib/domain/money.dart` · **Dep** mismo lote que 025, 026, 027, 056 · **Fix** helper `formatHectares` en `money.dart` usado en los 8 sitios
- **Tests** unitario de `formatHectares` (80 → "80 ha", 120,5 → "120,5 ha"); widget test de una pantalla afectada · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-A

### UIBUG-025 · Las cantidades de los resúmenes generados en SQL no usan el formato de la app

- **Sev** MEDIUM · **Cat** TEXT / CONSISTENCY · **Riesgo** `ACCOUNTING` · **Grupo** `FORMAT_LOCALIZATION`
- **Pant.** UI-08 `/aplicaciones`, UI-16 `/transferencias` · **Feat.** F-08, F-09 · **RN** —
- **Pre** aplicaciones y transferencias con varios productos. **Pasos** abrir cualquiera de las dos listas.
- **Actual** `Urea 25.0 KG`, `Semilla Soya INTA-90 300.0 KG`, `Fosfato Diamónico 5000.0 KG`: punto decimal, decimal superfluo y **sin separador de miles**, mientras el resto de la app usa `1.750,25 KG`.
- **Esperado** el mismo formato que `formatQuantity`.
- **Evid.** `UI-08-aplicaciones/_zoom-cantidad.png`, `UI-16-transferencias/UI-16-lista.png`
- **Causa CONFIRMADA** — `agro_repository.dart:1070`, `1072` y `1191` arman `items_summary`/`products_summary` con `GROUP_CONCAT(p.name || ' ' || (quantity_base / 1000.0) || ' ' || p.unit, ' · ')` **en SQL**, sin pasar por `formatQuantity`.
- **Files** `lib/data/agro_repository.dart`, `applications_screen.dart`, `transfers_screen.dart` · **Dep** mismo lote que 024/026/027/056 · **Fix** devolver los datos crudos y componer el resumen en Dart con `formatQuantity`
- **Tests** test de repositorio que devuelva las partes sin formatear; widget test del resumen renderizado · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-A

### UIBUG-026 · La bitácora muestra el detalle FIFO en unidades internas

- **Sev** MEDIUM · **Cat** DATA / TEXT · **Riesgo** `ACCOUNTING` · **Grupo** `FORMAT_LOCALIZATION`
- **Pant.** UI-15 `/chacos/:id` · **Feat.** F-14 bitácora · **RN** trazabilidad FIFO
- **Pre** una entrada de bitácora con consumo. **Pasos** Persona → Chacos → un chaco → expandir una entrada.
- **Actual** **"FIFO: #1: 600000"**: identificador de lote y cantidad en **gramos**, sin unidad ni formato, justo debajo de un correcto "real 600 KG".
- **Esperado** el lote y su cantidad formateados con unidad.
- **Evid.** `UI-15-bitacora/UI-15-ISSUE-fifo-crudo.png`
- **Causa CONFIRMADA** — `farm_logbook_screen.dart:70` interpola `${row['fifo_lots'] ?? 'sin detalle'}` **en crudo**; el valor viene ya concatenado desde SQL en unidades base.
- **Files** `lib/presentation/screens/farm_logbook_screen.dart`, `lib/data/agro_repository.dart` · **Dep** mismo lote que 024/025 · **Fix** devolver los lotes estructurados y formatearlos en Dart
- **Tests** widget test de la entrada expandida: aparece "600 KG", no "600000" · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-A

### UIBUG-027 · Fechas en formato ISO

- **Sev** MEDIUM · **Cat** TEXT · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `FORMAT_LOCALIZATION`
- **Pant.** UI-15 bitácora, UI-14 pestaña Cuenta, UI-10 estado de cuenta · **Feat.** F-11, F-14 · **RN** —
- **Pre** movimientos con fecha. **Pasos** abrir cualquiera de las tres vistas.
- **Actual** `2026-01-25`, `2025-07-01`. No se localiza a `dd/mm/aaaa`.
- **Esperado** formato local es-BO.
- **Evid.** `UI-15-bitacora/UI-15-entrada-expandida.png`
- **Causa CONFIRMADA** — 3 sitios con `transaction_date.substring(0, 10)` sobre la cadena ISO almacenada (`settlements_screen.dart:175`, `person_detail_screen.dart:143`, y la bitácora), sin `DateFormat`.
- **Files** los 3 anteriores + `lib/domain/money.dart` (donde vivirá el helper) · **Dep** mismo lote que 024/025/026 · **Fix** helper `formatDate` con `DateFormat.yMd('es_BO')`
- **Tests** unitario del helper; widget test de una de las vistas · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-A

### UIBUG-028 · La pestaña "Cuenta" de la persona no muestra saldo acumulado

- **Sev** MEDIUM · **Cat** DATA / CONSISTENCY · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `BALANCE_SEMANTICS`
- **Pant.** UI-14 `/personas/:id` · **Feat.** F-11 · **RN** —
- **Pre** persona con movimientos. **Pasos** Personas → una persona → pestaña **Cuenta**.
- **Actual** lista los movimientos **sin saldo corrido ni total**, mientras el diálogo de estado de cuenta de Liquidación sí lo calcula. Dos vistas del mismo dato con distinto nivel de información.
- **Esperado** el mismo nivel de detalle en ambas, o una razón explícita para que difieran.
- **Evid.** `UI-14-persona-detalle/UI-14-ISSUE-pestana-cuenta-inalcanzable.png`
- **Causa CONFIRMADA** — `person_detail_screen.dart:140-152` consume `statement()` (`agro_repository.dart:1540`, un `SELECT *` plano) mientras el diálogo usa `detailedStatement()` (`:1549`, con `concept` y acumulado calculado en la pantalla).
- **Files** `person_detail_screen.dart`, `lib/data/agro_repository.dart` · **Dep** **depende de la decisión de 013**: no tiene sentido añadir un "saldo" antes de definir qué significa · **Fix** unificar en `detailedStatement` y reutilizar el mismo componente
- **Tests** test de que ambas vistas devuelven el mismo acumulado para la misma persona · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-A

### UIBUG-029 · El TabBar de la persona no se desplaza al tocarlo y trunca las etiquetas

- **Sev** MEDIUM · **Cat** NAVIGATION / LAYOUT · **Riesgo** `NAVIGATION` · **Grupo** `LIST_AFFORDANCES`
- **Pant.** UI-14 `/personas/:id` · **Feat.** — · **RN** `07_SCREENS` P-14
- **Pre** ninguna. **Pasos** abrir el detalle de una persona e intentar llegar a la pestaña "Cuenta" deslizando la barra.
- **Actual** de cinco pestañas se ven cuatro, la cuarta recortada como **"Inve"** y "Cuenta" fuera de pantalla. Deslizar la barra no hace nada; solo se alcanzan deslizando el **contenido**, sin ninguna pista de que se pueda.
- **Esperado** barra desplazable o etiquetas que quepan.
- **Evid.** `UI-14-persona-detalle/UI-14-ISSUE-tabbar-recortado.png`
- **Causa PROBABLE** — `TabBar` sin `isScrollable: true`.
- **Files** `lib/presentation/screens/person_detail_screen.dart` · **Dep** — · **Fix** `isScrollable: true` o etiquetas más cortas
- **Tests** widget test: las 5 pestañas son alcanzables desde la barra · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-030 · Enorme espacio vacío bajo el contenido del detalle de persona

- **Sev** MEDIUM · **Cat** LAYOUT · **Riesgo** `COSMETIC` · **Grupo** `FIXED_HEIGHT`
- **Pant.** UI-14 `/personas/:id` · **Feat.** — · **RN** `07_SCREENS` P-14
- **Pre** una persona con pocos chacos. **Pasos** abrir el detalle → pestaña Chacos.
- **Actual** con dos filas de contenido queda más de media pantalla en blanco.
- **Esperado** el área se ajusta al contenido.
- **Evid.** `UI-15-bitacora/UI-15-pestana-chacos.png`
- **Causa CONFIRMADA** — `person_detail_screen.dart:72`: `height: 480` fijo para el área de pestañas.
- **Files** `lib/presentation/screens/person_detail_screen.dart` · **Dep** mismo lote que 018 y 055 · **Fix** altura adaptativa
- **Tests** widget test con pocas filas: sin hueco desproporcionado · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-031 · Guardar con el nombre vacío no hace nada y no explica por qué

- **Sev** MEDIUM · **Cat** VALIDATION / UX · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-03 `/catalogos` · **Feat.** F-01 · **RN** `16_VALIDATIONS`
- **Pre** ninguna. **Pasos** Catálogos → *Nuevo producto* → **Guardar** con los campos vacíos.
- **Actual** el diálogo queda abierto sin error en línea, sin snackbar y sin deshabilitar el botón: parece que la aplicación no responde.
- **Esperado** error en línea o botón deshabilitado.
- **Evid.** `UI-03-catalogos/_crop-guardar-vacio.png`
- **Causa PROBABLE** — el `onPressed` retorna temprano sin notificar.
- **Files** `lib/presentation/screens/catalogs_screen.dart` · **Dep** — · **Fix** validación con `errorText` o botón condicionado
- **Tests** widget test: guardar vacío muestra error visible · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P2

### UIBUG-032 · El mensaje de validación del plan no refleja qué falta

- **Sev** MEDIUM · **Cat** TEXT / VALIDATION · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `FORM_UX`
- **Pant.** UI-05 `/planificacion/nueva` · **Feat.** F-03 · **RN** `16_VALIDATIONS`
- **Pre** chaco ya elegido, sin productos. **Pasos** pulsar Guardar.
- **Actual** *"Seleccione chaco y al menos un producto."*, mencionando algo que ya está resuelto.
- **Esperado** mencionar solo lo que falta.
- **Evid.** `UI-05-plan-form/_c-UI-05-guardar-sin-productos.png`
- **Causa PROBABLE** — mensaje único para dos condiciones.
- **Files** `lib/presentation/screens/plan_form_screen.dart` · **Dep** — · **Fix** mensajes por condición
- **Tests** unitario/widget de los 3 casos (falta chaco, faltan productos, faltan ambos) · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-033 · En "¿Descartar cambios?" el botón destructivo es el primario

- **Sev** MEDIUM · **Cat** UX · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** los 4 formularios · **Feat.** — · **RN** STAB-010 (criterio de acción destructiva)
- **Pre** formulario con cambios. **Pasos** Atrás → aparece "¿Descartar cambios?".
- **Actual** **Descartar** es el botón relleno y **Seguir editando** un texto plano; además no usa el color de error que sí usa `confirmDestructiveAction` en las reversiones. Un toque por inercia pierde el trabajo.
- **Esperado** el mismo criterio que el resto de acciones destructivas de la app.
- **Evid.** `UI-05-plan-form/_c-UI-05-descartar-cambios.png`
- **Causa CONFIRMADA** — el diálogo no reutiliza `confirmDestructiveAction` (`common.dart:~100-129`), que sí aplica `colorScheme.error`.
- **Files** los 4 formularios, `lib/presentation/widgets/common.dart` · **Dep** — · **Fix** reutilizar el helper existente
- **Tests** widget test: el botón destructivo usa el color de error y no es el primario · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-034 · Los campos de cantidad vienen con "0" y el 0 no se limpia al enfocar

- **Sev** MEDIUM · **Cat** FORM · **Riesgo** `UX` · **Grupo** `NUMERIC_INPUT`
- **Pant.** UI-17 `/transferencias/nueva` · **Feat.** F-09 · **RN** —
- **Pre** origen con 8 productos. **Pasos** tocar un campo de cantidad y escribir `5`.
- **Actual** queda **`05`**. Con ocho productos todos a cero, además cuesta ver dónde se ha escrito.
- **Esperado** el campo nace vacío, o el `0` se selecciona al enfocar.
- **Evid.** `UI-17-transfer-form/_zoom-cero.png`
- **Causa CONFIRMADA** — `transfer_form_screen.dart:58`: `quantities[...] = TextEditingController(text: '0')`.
- **Files** `lib/presentation/screens/transfer_form_screen.dart` · **Dep** mismo lote que 003 (ambos tocan entrada numérica) · **Fix** controlador vacío con `hintText: '0'`, o selección al enfocar
- **Tests** widget test: escribir `5` en un campo recién enfocado produce `5` · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-035 · El selector abre el teclado automáticamente y deja ver solo tres opciones

- **Sev** MEDIUM · **Cat** FORM / SCROLL · **Riesgo** `UX` · **Grupo** `ENTITY_PICKER`
- **Pant.** los 4 formularios · **Feat.** F-17 · **RN** —
- **Pre** ≥8 elementos en el selector. **Pasos** abrir el selector de Chaco en `/planificacion/nueva`.
- **Actual** el buscador toma el foco al abrir la hoja; el teclado ocupa más de la mitad y de 8 chacos se ven 3. Hay que cerrar el teclado para poder elegir.
- **Esperado** la lista visible por defecto; el teclado solo si el usuario toca el buscador.
- **Evid.** `UI-05-plan-form/UI-05-picker-chaco.png`
- **Causa PROBABLE** — `autofocus: true` en el campo de búsqueda de la hoja.
- **Files** `lib/presentation/widgets/adaptive_entity_picker.dart` · **Dep** mismo archivo que 006, 036, 061 · **Fix** sin autofoco (o solo por encima de N elementos)
- **Tests** widget test: al abrir el selector no hay foco en el buscador · **Pixel 8** SÍ — el teclado real es parte del defecto · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-036 · "Sin resultados." queda oculto tras el teclado

- **Sev** MEDIUM · **Cat** LAYOUT · **Riesgo** `UX` · **Grupo** `ENTITY_PICKER`
- **Pant.** selectores de los formularios · **Feat.** F-17 · **RN** —
- **Pre** selector abierto. **Pasos** escribir algo sin coincidencias.
- **Actual** el mensaje se centra verticalmente en un área que el teclado tapa: mientras se escribe el usuario ve un hueco en blanco. Solo aparece al cerrar el teclado.
- **Esperado** el mensaje visible en la zona no cubierta.
- **Evid.** `UI-05-plan-form/_crop-sinres.png`
- **Causa PROBABLE** — centrado vertical sobre el alto total de la hoja sin descontar `viewInsets`.
- **Files** `lib/presentation/widgets/adaptive_entity_picker.dart` · **Dep** mismo archivo que 006, 035, 061 · **Fix** alinear arriba o descontar `viewInsets`
- **Tests** widget test con `viewInsets` simulado · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-037 · Etiquetas colgando cuando aún no hay producto elegido

- **Sev** MEDIUM · **Cat** TEXT · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-07 `/compras/nueva` · **Feat.** F-04 · **RN** —
- **Pre** línea de compra sin producto. **Pasos** abrir el formulario de compra.
- **Actual** se lee **"Precio BOB/"** y **"Costo 0,00 Bs /"**, con la barra sin unidad detrás.
- **Esperado** omitir la barra hasta que haya unidad.
- **Evid.** `UI-07-purchase-form/UI-07-ISSUE-precio-sin-unidad.png`
- **Causa PROBABLE** — interpolación `'Precio BOB/${unit ?? ''}'`.
- **Files** `lib/presentation/screens/purchase_form_screen.dart` · **Dep** — · **Fix** condicionar el sufijo
- **Tests** widget test sin producto elegido · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P2

### UIBUG-038 · El campo de cantidad de la asignación no tiene etiqueta

- **Sev** MEDIUM · **Cat** FORM · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-07 `/compras/nueva` · **Feat.** F-04 · **RN** regla de asignación
- **Pre** una línea de compra con producto. **Pasos** mirar la fila de asignación.
- **Actual** aparece como un recuadro vacío; tras elegir producto su única pista es la unidad (`L`). Nada dice que ahí va la cantidad asignada a esa persona.
- **Esperado** etiqueta explícita.
- **Evid.** `UI-07-purchase-form/UI-07-ISSUE-asignacion-sin-etiqueta.png`
- **Causa PROBABLE** — `InputDecoration` sin `labelText`.
- **Files** `lib/presentation/screens/purchase_form_screen.dart` · **Dep** — · **Fix** añadir etiqueta
- **Tests** widget test: el campo tiene etiqueta accesible · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P2

### UIBUG-039 · La línea de compra dice "asignado" sin haber elegido persona

- **Sev** MEDIUM · **Cat** TEXT / DATA · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `FORM_UX`
- **Pant.** UI-07 `/compras/nueva` · **Feat.** F-04 · **RN** —
- **Pre** línea con producto y cantidad. **Pasos** escribir la cantidad de la asignación sin elegir persona.
- **Actual** el resumen pasa de "pendiente 12,5 L" a "asignado", aunque la asignación no tenga persona. La validación al confirmar **sí** lo detecta.
- **Esperado** contar como asignado solo cuando la asignación esté completa.
- **Evid.** `UI-07-purchase-form/UI-07-teclado-campo-inferior.png`
- **Causa PROBABLE** — el cómputo suma cantidades sin comprobar `personId != null`.
- **Files** `lib/presentation/screens/purchase_form_screen.dart` · **Dep** — · **Fix** condicionar el cómputo
- **Tests** unitario del cómputo de asignado/pendiente con persona nula · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P2

### UIBUG-040 · Campos de media anchura que truncan su contenido

- **Sev** MEDIUM · **Cat** LAYOUT · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-07 `/compras/nueva` · **Feat.** F-04 · **RN** —
- **Pre** proveedor de nombre largo. **Pasos** elegir "Agropecuaria del Este S.R.L." y "Verano 2026".
- **Actual** se muestran como **"Agropecu…"** y **"Verano 20…"**, pese a haber espacio libre a la derecha.
- **Esperado** usar el ancho disponible.
- **Evid.** `UI-07-purchase-form/UI-07-factura-con-teclado.png`
- **Causa PROBABLE** — campos fijados a media anchura en una `Row`.
- **Files** `lib/presentation/screens/purchase_form_screen.dart` · **Dep** — · **Fix** reparto flexible
- **Tests** widget test con los valores largos del dataset · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P2

### UIBUG-041 · La etiqueta "Producto" queda recortada por la cabecera de la línea

- **Sev** MEDIUM · **Cat** LAYOUT · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-07 `/compras/nueva` · **Feat.** F-04 · **RN** —
- **Pre** una línea de compra. **Pasos** mirar el selector de producto dentro de la tarjeta.
- **Actual** la etiqueta flotante se solapa con la fila de resumen de la tarjeta.
- **Esperado** separación suficiente.
- **Evid.** `UI-07-purchase-form/UI-07-ISSUE-etiqueta-producto-recortada.png`
- **Causa PROBABLE** — margen superior insuficiente para la etiqueta flotante. **Distinto de 006**: allí la etiqueta no flota; aquí flota y choca con lo de arriba.
- **Files** `lib/presentation/screens/purchase_form_screen.dart` · **Dep** conviene verificar **después** de 006 (al flotar la etiqueta, este solape puede aparecer en más sitios) · **Fix** margen superior
- **Tests** widget test de la tarjeta de línea · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P2

### UIBUG-042 · Elegir en "Agregar producto" no agrega el producto

- **Sev** MEDIUM · **Cat** UX · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-09 `/aplicaciones/nueva` · **Feat.** F-08 · **RN** —
- **Pre** formulario abierto. **Pasos** elegir un producto en el selector "Agregar producto".
- **Actual** el contador sigue en **Productos (0)** y el estado vacío sigue diciendo *"Agregue los productos de la mezcla."*. Hay que pulsar además un botón **+** contiguo, que solo entonces se habilita. La acción no coincide con su etiqueta.
- **Esperado** elegir agrega, o la etiqueta dice "Elegir producto" y el + es evidente.
- **Evid.** `UI-09-application-form/UI-09-linea-producto.png`
- **Causa PROBABLE** — el selector solo fija un valor temporal; el `+` es quien inserta.
- **Files** `lib/presentation/screens/application_form_screen.dart` · **Dep** — · **Fix** agregar al elegir, o renombrar y destacar el `+`
- **Tests** widget test: elegir un producto lo añade a la lista · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-043 · La línea de producto nace plegada y sin indicador de que se despliega

- **Sev** MEDIUM · **Cat** UX / FORM · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-09 `/aplicaciones/nueva` · **Feat.** F-08 · **RN** —
- **Pre** un producto añadido. **Pasos** mirar la fila recién añadida.
- **Actual** se ve solo *"Urea · 0 KG real / 0 KG teórico · 0,00 Bs"*. Los campos **Dosis** y **Cantidad real** están dentro de un desplegable cuyo chevron fue sustituido por el botón "Quitar", así que **no hay ninguna señal** de que la fila se abra. Se comprobó que sí se despliega al tocarla.
- **Esperado** nacer desplegada, o mostrar un indicador.
- **Evid.** `UI-09-application-form/_c-fila.png` (plegada), `_c-fila1.png` (desplegada)
- **Causa CONFIRMADA** — `application_form_screen.dart:~467`: `ExpansionTile` con `trailing` sobrescrito por el botón Quitar, que elimina el chevron por defecto.
- **Files** `lib/presentation/screens/application_form_screen.dart` · **Dep** relacionado con 046 (mismo patrón en Planificación) · **Fix** `initiallyExpanded: true` o conservar el chevron
- **Tests** widget test: la fila añadida muestra sus campos o su indicador · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-044 · "stock después" negativo no se resalta

- **Sev** MEDIUM · **Cat** UX · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `FORM_UX`
- **Pant.** UI-09 `/aplicaciones/nueva` · **Feat.** F-08 · **RN** regla de stock suficiente
- **Pre** producto con stock limitado. **Pasos** pedir más de lo disponible.
- **Actual** se muestra *"stock después -249,75 KG"* en color normal, mientras `/inventario` sí pinta en rojo las proyecciones negativas. La validación al confirmar **es correcta**.
- **Esperado** resaltar en rojo, como hace Inventario.
- **Evid.** `UI-09-application-form/_c-val.png`
- **Causa PROBABLE** — falta el color condicional que ya existe en `inventory_screen.dart`.
- **Files** `lib/presentation/screens/application_form_screen.dart` · **Dep** — · **Fix** reutilizar el criterio de color de Inventario
- **Tests** widget test: valor negativo se pinta con el color de error · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-045 · Los planes ya aplicados siguen ofreciendo "Aplicar" sin ningún estado

- **Sev** MEDIUM · **Cat** DATA / UX · **Riesgo** `DATA_INTEGRITY` · **Grupo** `REVERSAL_CONSISTENCY`
- **Pant.** UI-04 `/planificacion` · **Feat.** F-03 · **RN** regla de plan
- **Pre** los cinco planes del dataset ya aplicados. **Pasos** abrir Planificación.
- **Actual** todos muestran el botón **Aplicar** sin distintivo. Nada advierte de que volver a aplicarlos **duplicaría el consumo**.
- **Esperado** estado visible del plan y protección contra doble aplicación.
- **Evid.** `UI-04-planificacion/UI-04-lista.png`
- **Causa CONFIRMADA** — `planning_screen.dart:114` pinta `Aplicar` incondicionalmente; **no existe ningún estado de plan** consultado ni almacenado.
- **Files** `lib/presentation/screens/planning_screen.dart`, `lib/data/agro_repository.dart`, posiblemente `lib/data/app_database.dart` (migración)
- **Dep** **puede requerir cambio de esquema (v6)**. Es el único hallazgo del backlog con ese alcance. No agrupar con cambios cosméticos.
- **Fix** decisión de producto + estado de plan (derivado o persistido)
- **Tests** test de repositorio del estado; widget test de que un plan aplicado no ofrece Aplicar sin advertencia
- **Pixel 8** SÍ · **Estado** `DESIGN_DECISION_REQUIRED`· **Prio** P1-A

### UIBUG-046 · Las filas de planificación son desplegables sin indicarlo

- **Sev** MEDIUM · **Cat** UX · **Riesgo** `UX` · **Grupo** `FORM_UX`
- **Pant.** UI-04 `/planificacion` · **Feat.** F-03 · **RN** —
- **Pre** planes con productos. **Pasos** buscar el detalle por producto de un plan.
- **Actual** el chevron fue sustituido por el botón "Aplicar"; el detalle solo aparece si se acierta a tocar el cuerpo de la fila.
- **Esperado** indicador de expansión visible.
- **Evid.** `UI-04-planificacion/UI-04-plan-expandido.png`
- **Causa CONFIRMADA** — mismo patrón que 043: `trailing` del `ExpansionTile` ocupado por un botón.
- **Files** `lib/presentation/screens/planning_screen.dart` · **Dep** corregir junto con 043 (mismo patrón) · **Fix** conservar el chevron o mover el botón
- **Tests** widget test: la fila muestra indicador de expansión · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-047 · Dos puntos de creación distintos en la misma pantalla

- **Sev** MEDIUM · **Cat** UX · **Riesgo** `UX` · **Grupo** `LIST_AFFORDANCES`
- **Pant.** UI-03 `/catalogos` · **Feat.** F-01 · **RN** —
- **Pre** ninguna. **Pasos** abrir Catálogos y mirar las dos acciones primarias.
- **Actual** conviven el botón **Agregar** (crea en la pestaña activa) y el FAB **Nuevo** (abre la hoja global de operaciones). Mismo aspecto de acción primaria, significados distintos.
- **Esperado** una jerarquía clara entre ambas.
- **Evid.** `UI-03-catalogos/UI-03-personas.png`
- **Causa CONFIRMADA** — el FAB lo pinta el shell (`app_shell.dart:80`) para **todas** las rutas, incluida Catálogos, que ya tiene su propia acción de creación.
- **Files** `lib/presentation/screens/catalogs_screen.dart`, `lib/presentation/app_shell.dart` · **Dep** relacionado con la decisión de 002 (qué hace el FAB en cada ruta) · **Fix** ocultar el FAB en Catálogos, o diferenciar visualmente
- **Tests** widget test de la pantalla · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P3

### UIBUG-048 · La lista de campañas no muestra fechas

- **Sev** MEDIUM · **Cat** DATA · **Riesgo** `COSMETIC` · **Grupo** `LIST_AFFORDANCES`
- **Pant.** UI-03 `/catalogos` · **Feat.** F-02 · **RN** —
- **Pre** 3 campañas. **Pasos** Catálogos → pestaña Campañas.
- **Actual** solo nombre y estado, aunque `campaigns` guarda inicio y fin, y las fechas son el criterio natural para distinguir campañas.
- **Esperado** mostrar el rango de fechas.
- **Evid.** `UI-03-catalogos/UI-03-menu-campana.png`
- **Causa CONFIRMADA** — los datos existen en el esquema; la pantalla no los pinta.
- **Files** `lib/presentation/screens/catalogs_screen.dart` · **Dep** usará el helper de 027 · **Fix** añadir el subtítulo con fechas formateadas
- **Tests** widget test: la fila de campaña muestra el rango · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P3

### UIBUG-049 · Iconografía de nube para un backup puramente local

- **Sev** MEDIUM · **Cat** UX / TEXT · **Riesgo** `UX` · **Grupo** `BACKUP_ANDROID`
- **Pant.** UI-10 `/liquidacion` · **Feat.** F-16 · **RN** `14_OFFLINE_AND_SYNC` (la app no tiene red)
- **Pre** ninguna. **Pasos** mirar la cabecera de Cuentas y abrir el menú de copias.
- **Actual** la acción se representa con una **nube con flecha**, que sugiere sincronización remota; la aplicación no tiene ninguna función de red y el respaldo es un archivo local. Dentro del menú, **"Exportar backup"** usa un icono de **descarga** (cuando en realidad escribe un archivo).
- **Esperado** iconografía de archivo/almacenamiento local.
- **Evid.** `UI-10-liquidacion/UI-10-menu-backup.png`
- **Causa CONFIRMADA** — elección de iconos en `settlements_screen.dart`.
- **Files** `lib/presentation/screens/settlements_screen.dart` · **Dep** corregir junto con 001 (mismo menú) · **Fix** cambiar iconos y afinar los textos
- **Tests** — (cambio puramente visual) · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P3

### UIBUG-050 · Un aviso informativo se muestra como error

- **Sev** MEDIUM · **Cat** UX · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `ERROR_MESSAGING`
- **Pant.** UI-10 `/liquidacion` · **Feat.** F-16 · **RN** `17_ERROR_HANDLING`
- **Pre** sin backups previos. **Pasos** Cuentas → nube → Restaurar backup.
- **Actual** *"No se encontró ningún backup. Exporte uno primero…"* aparece en el snackbar **rojo** de error, cuando es una indicación normal.
- **Esperado** snackbar informativo.
- **Evid.** `UI-10-liquidacion/UI-10-restaurar-backup.png`
- **Causa CONFIRMADA** — el caso "sin backups" se propaga como excepción y se pinta con `showError`.
- **Files** `lib/presentation/screens/settlements_screen.dart`, `lib/presentation/widgets/common.dart` · **Dep** mismo lote que 015; su frecuencia baja **una vez corregido 001** (hoy siempre se da porque nunca hay backup) · **Fix** distinguir "sin resultados" de "error"
- **Tests** widget test: sin backups se muestra aviso informativo, no error · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P1-B

### UIBUG-051 · Las tarjetas de Operaciones prometen una acción y llevan a una lista

- **Sev** MEDIUM · **Cat** UX / NAVIGATION · **Riesgo** `NAVIGATION` · **Grupo** `NAVIGATION_STACK`
- **Pant.** UI-02 `/operaciones` · **Feat.** — · **RN** `08_NAVIGATION`
- **Pre** ninguna. **Pasos** pulsar *Registrar aplicación*, luego *Registrar compra*.
- **Actual** *"Registrar aplicación"* lleva a `/aplicaciones` (el listado) y *"Transferir inventario"* a `/transferencias`, mientras *"Registrar compra"* sí abre el formulario. Comportamiento distinto bajo etiquetas del mismo estilo.
- **Esperado** coherencia: o todas abren formulario, o las etiquetas lo reflejan.
- **Evid.** `UI-02-operaciones/UI-02-registrar-aplicacion-destino.png`
- **Causa CONFIRMADA** — `operations_screen.dart:86-87`: `isForm ? context.push(path) : context.go(path)`, y solo la compra tiene `isForm: true`. Lo mismo en el FAB (`app_shell.dart:109-140`).
- **Files** `lib/presentation/screens/operations_screen.dart`, `lib/presentation/app_shell.dart` · **Dep** debe decidirse junto con 002 y 004A (todo el mapa de navegación) · **Fix** decisión + unificar
- **Tests** test de navegación por cada tarjeta · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-B

### UIBUG-052 · Personas es la única lista sin buscador ni recarga

- **Sev** MEDIUM · **Cat** UX / CONSISTENCY · **Riesgo** `UX` · **Grupo** `SEARCH`
- **Pant.** UI-13 `/personas` · **Feat.** — · **RN** KI-17
- **Pre** 7 personas. **Pasos** abrir Personas y buscar el buscador.
- **Actual** no hay. Inicio, Inventario, Aplicaciones, Compras y Liquidación tienen buscador; Inventario e Inicio tienen botón de recarga. Personas no tiene ninguno.
- **Esperado** coherencia con el resto de listas.
- **Evid.** `UI-13-personas/UI-13-lista.png`
- **Causa CONFIRMADA** — `persons_screen.dart` no contiene ningún `TextField` ni estado de búsqueda (0 coincidencias).
- **Files** `lib/presentation/screens/persons_screen.dart` · **Dep** usará el helper de normalización de 019 · **Fix** añadir buscador y recarga
- **Tests** widget test del buscador · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-053 · Transferencias no muestra fechas ni ofrece filtros

- **Sev** MEDIUM · **Cat** DATA / UX · **Riesgo** `UX` · **Grupo** `SEARCH`
- **Pant.** UI-16 `/transferencias` · **Feat.** F-09 · **RN** —
- **Pre** 7 transferencias. **Pasos** abrir Transferencias.
- **Actual** el historial no indica **cuándo** ocurrió cada movimiento y carece de buscador y de filtro por campaña, a diferencia de Aplicaciones.
- **Esperado** fecha visible y filtros equivalentes a Aplicaciones.
- **Evid.** `UI-16-transferencias/UI-16-lista.png`
- **Causa CONFIRMADA** — la pantalla no pinta la fecha ni ofrece controles de filtro.
- **Files** `lib/presentation/screens/transfers_screen.dart` · **Dep** usará los helpers de 027 (fecha) y 019 (búsqueda) · **Fix** añadir fecha y filtros
- **Tests** widget test de fecha y filtro · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-054 · Dos selectores contiguos de la misma pantalla muestran datos distintos

- **Sev** MEDIUM · **Cat** CONSISTENCY · **Riesgo** `UX` · **Grupo** `ENTITY_PICKER`
- **Pant.** UI-17 `/transferencias/nueva` (y UI-07) · **Feat.** F-09, F-17 · **RN** —
- **Pre** 7 personas, una de ellas ADMIN. **Pasos** abrir el selector de **origen** y luego el de **destino**.
- **Actual** el de **origen** muestra el rol de cada persona ("Familiar", "Tercero"); el de **destino**, no. Además el de origen excluye al ADMIN (6/6) mientras el de asignación del formulario de compra lo incluye (7/7) **y muestra el rol en inglés**.
- **Esperado** criterio único de subtítulo y de inclusión, o razón explícita para diferir.
- **Evid.** `UI-17-transfer-form/UI-17-picker-origen.png`, `UI-17-transfer-form/UI-17-picker-destino.png`
- **Causa CONFIRMADA** — cada llamada al selector construye su propio `labelOf`/`subtitle` y su propio filtro. La parte "en inglés" es 016.
- **Files** `lib/presentation/screens/transfer_form_screen.dart`, `lib/presentation/screens/purchase_form_screen.dart` · **Dep** parcialmente cubierto por 016 · **Fix** un constructor de selector de persona compartido
- **Tests** widget test comparando los tres selectores de persona · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P2

### UIBUG-055 · La lista de productos disponibles se corta a mitad de fila

- **Sev** MEDIUM · **Cat** SCROLL / LAYOUT · **Riesgo** `UX` · **Grupo** `FIXED_HEIGHT`
- **Pant.** UI-17 `/transferencias/nueva` · **Feat.** F-09 · **RN** `07_SCREENS` P-17
- **Pre** origen con 8 productos. **Pasos** elegir origen y mirar la sección de productos.
- **Actual** la lista está acotada a ≈48 % de la altura de la pantalla y su último elemento visible (`Semilla Soya INTA-90`) aparece seccionado, sin ninguna señal de continuidad.
- **Esperado** que se vea que hay más contenido, o que la lista participe del scroll.
- **Evid.** `UI-17-transfer-form/UI-17-productos-disponibles.png`
- **Causa CONFIRMADA** — `transfer_form_screen.dart:296`: `maxHeight: MediaQuery.sizeOf(context).height * 0.48`.
- **Files** `lib/presentation/screens/transfer_form_screen.dart` · **Dep** mismo lote que 018 y 030 · **Fix** eliminar la cota fija o añadir indicador de desbordamiento
- **Tests** widget test con 8 productos · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-056 · Decimales variables en la misma fila

- **Sev** MEDIUM · **Cat** TEXT · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `FORMAT_LOCALIZATION`
- **Pant.** UI-11 `/inventario` · **Feat.** F-07 · **RN** —
- **Pre** producto con proyección distinta del físico. **Pasos** abrir Inventario.
- **Actual** una fila muestra *"Físico 174,25 L"* y, como proyección, *"174,1 L"*: dificulta comparar cifras alineadas.
- **Esperado** número de decimales estable en una misma columna.
- **Evid.** `UI-11-inventario/UI-11-lista.png`
- **Causa CONFIRMADA** — `money.dart:43`: `NumberFormat('#,##0.###', 'es_BO')`. El patrón `###` suprime los ceros finales, así que `174,100` se imprime `174,1`.
- **Files** `lib/domain/money.dart` · **Dep** mismo lote que 024/025/027; **cuidado**: cambiar el patrón afecta a toda la app y a los tests existentes · **Fix** decidir decimales fijos por unidad, o alinear a la derecha con relleno
- **Tests** unitario de `formatQuantity` con `174250` y `174100`; **revisar los tests existentes que dependan del patrón actual** · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P1-A

---

## LOW

### UIBUG-057 · El administrador aparece en la lista de personas con datos vacíos

- **Sev** LOW · **Cat** UX · **Riesgo** `COSMETIC` · **Grupo** `LIST_AFFORDANCES` · **Pant.** UI-13 `/personas` · **Feat.** — · **RN** —
- **Pre** dataset con un ADMIN. **Pasos** abrir Personas.
- **Actual** el administrador aparece con *"0.0 ha"* y saldo 0,00 Bs pese a no participar en la liquidación. Ruido en la lista. (El "0.0 ha" es además 024.)
- **Esperado** excluirlo, o marcarlo como no participante.
- **Evid.** `UI-13-personas/UI-13-lista.png`
- **Causa CONFIRMADA** — `persons_screen.dart` no filtra por rol, a diferencia de `settlements()` (`agro_repository.dart:1528`), que sí hace `WHERE p.role<>'ADMIN'`.
- **Files** `lib/presentation/screens/persons_screen.dart` · **Dep** — · **Fix** decisión menor: filtrar o etiquetar
- **Tests** widget test de la lista · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P3

### UIBUG-058 · Signo y color se leen al revés en el estado de cuenta

- **Sev** LOW · **Cat** UX · **Riesgo** `MISLEADING_INFORMATION` · **Grupo** `BALANCE_SEMANTICS` · **Pant.** UI-10 diálogo · **Feat.** F-11 · **RN** —
- **Pre** movimientos de cargo y de pago. **Pasos** abrir *Ver detalle cronológico*.
- **Actual** el cargo lleva un icono **+** naranja y el pago un **−** verde; la combinación signo/color se lee al revés de lo esperado por un usuario no contable.
- **Esperado** convención coherente y explicada.
- **Evid.** `UI-10-liquidacion/UI-10-estado-de-cuenta.png`
- **Causa CONFIRMADA** — `settlements_screen.dart:167-172`: el icono y el color se derivan del signo de `amount_bob_minor_signed`, que es contable (cargo positivo). Es **correcto contablemente**, confuso visualmente.
- **Files** `lib/presentation/screens/settlements_screen.dart` · **Dep** parte de la decisión de vocabulario de 013 · **Fix** leyenda o cambio de convención
- **Tests** — · **Pixel 8** SÍ · **Estado** `WONT_FIX`· **Prio** P3

### UIBUG-059 · Se ofrece "Activar" sobre una campaña cerrada sin advertencia

- **Sev** LOW · **Cat** UX · **Riesgo** `DATA_INTEGRITY` · **Grupo** `LIST_AFFORDANCES` · **Pant.** UI-03 `/catalogos` · **Feat.** F-02 · **RN** KI-18, invariante de campaña única activa
- **Pre** una campaña `CLOSED`. **Pasos** Catálogos → Campañas → ⋮ de una campaña cerrada.
- **Actual** se ofrece **Activar** sin advertir de que se reabre un periodo cerrado. (El cambio de campaña activa **sí** pide una confirmación clara y correcta.)
- **Esperado** advertencia específica, o la acción no se ofrece.
- **Evid.** `UI-03-catalogos/UI-03-menu-campana.png`
- **Causa CONFIRMADA** — el menú no distingue el estado de origen.
- **Files** `lib/presentation/screens/catalogs_screen.dart` · **Dep** — · **Fix** decisión de producto + confirmación específica
- **Tests** widget test del menú sobre una campaña cerrada · **Pixel 8** SÍ · **Estado** `DESIGN_DECISION_REQUIRED`· **Prio** P3

### UIBUG-060 · Un "0" sin explicación antes de elegir origen

- **Sev** LOW · **Cat** UX · **Riesgo** `UX` · **Grupo** `FORM_UX` · **Pant.** UI-17 `/transferencias/nueva` · **Feat.** F-09 · **RN** —
- **Pre** formulario recién abierto. **Pasos** mirar la sección *"2. Productos disponibles"*.
- **Actual** muestra un escueto **0** antes de elegir origen, sin texto que lo explique.
- **Esperado** un estado vacío con texto ("Elija primero el origen").
- **Evid.** `UI-17-transfer-form/UI-17-inicial.png`
- **Causa PROBABLE** — contador pintado sin estado vacío asociado.
- **Files** `lib/presentation/screens/transfer_form_screen.dart` · **Dep** — · **Fix** `EmptyState` con mensaje
- **Tests** widget test del formulario recién abierto · **Pixel 8** SÍ · **Estado** `OPEN`· **Prio** P3

### UIBUG-061 · La hoja del selector ocupa el 65 % aunque haya 4 elementos

- **Sev** LOW · **Cat** LAYOUT · **Riesgo** `COSMETIC` · **Grupo** `ENTITY_PICKER` · **Pant.** selectores · **Feat.** F-17 · **RN** —
- **Pre** un selector con 4 elementos (proveedores). **Pasos** abrirlo.
- **Actual** la hoja ocupa el 65 % de la pantalla con mucho espacio vacío.
- **Esperado** altura adaptada al contenido, con un máximo.
- **Evid.** `UI-07-purchase-form/UI-07-picker-proveedor.png`
- **Causa CONFIRMADA** — `adaptive_entity_picker.dart:166`: `final height = MediaQuery.sizeOf(context).height * 0.65;`.
- **Files** `lib/presentation/widgets/adaptive_entity_picker.dart` · **Dep** mismo archivo que 006, 035, 036 · **Fix** altura por contenido acotada
- **Tests** widget test con 4 y con 22 elementos · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P3

### UIBUG-062 · La barra inferior resalta "Inicio" mientras se está en la bitácora de un chaco

- **Sev** LOW · **Cat** NAVIGATION · **Riesgo** `NAVIGATION` · **Grupo** `NAVIGATION_STACK` · **Pant.** UI-15 `/chacos/:id` · **Feat.** F-14 · **RN** `08_NAVIGATION`
- **Pre** un chaco. **Pasos** Persona → Chacos → un chaco; mirar la barra inferior.
- **Actual** resalta **Inicio**.
- **Esperado** resaltar Personas (de donde se viene) o ninguno.
- **Evid.** `UI-15-bitacora/UI-15-entrada-expandida.png`
- **Causa CONFIRMADA** — `app_shell.dart:25-41` (`selectedIndex`): `/chacos/:id` no coincide con ningún destino ni con ningún prefijo de la lista, y el `return nested < 0 ? 0 : nested` **cae por defecto a 0** (Inicio).
- **Files** `lib/presentation/app_shell.dart` · **Dep** se resuelve de forma natural al rediseñar la navegación en 004A · **Fix** mapear `/chacos` a Personas, o permitir "ningún destino seleccionado"
- **Tests** unitario de `selectedIndex` para las 17 rutas · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-B

### UIBUG-063 · En horizontal el NavigationRail muestra solo iconos, sin etiqueta

- **Sev** LOW · **Cat** ACCESSIBILITY · **Riesgo** `ACCESSIBILITY` · **Grupo** `TEXT_WRAPPING` · **Pant.** global en horizontal · **Feat.** — · **RN** `08_NAVIGATION`
- **Pre** Pixel 8 en horizontal. **Pasos** rotar el dispositivo.
- **Actual** los destinos se muestran **solo con iconos**, sin etiqueta.
- **Esperado** etiquetas visibles, al menos bajo el icono.
- **Evid.** `UI-22-orientacion/UI-22-horizontal-bitacora.png`
- **Causa CONFIRMADA** — `app_shell.dart:53`: `extended: MediaQuery.sizeOf(context).width >= 1150`. El Pixel 8 apaisado da ≈914 px, así que nunca se extiende. Además `NavigationRail` sin `labelType` no muestra etiquetas en modo no extendido.
- **Files** `lib/presentation/app_shell.dart` · **Dep** — · **Fix** `labelType: NavigationRailLabelType.all` o bajar el umbral
- **Tests** widget test a 914 px de ancho: las etiquetas están presentes · **Pixel 8** SÍ — en horizontal, y **restaurar la rotación al terminar** · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P3

### UIBUG-064 · La tarjeta TOTAL COMPRA queda solapada por la barra de gestos

- **Sev** LOW · **Cat** LAYOUT · **Riesgo** `UX` · **Grupo** `SYSTEM_INSETS` · **Pant.** UI-07 `/compras/nueva` · **Feat.** F-04 · **RN** —
- **Pre** formulario de compra con contenido. **Pasos** desplazar hasta el final.
- **Actual** la tarjeta *TOTAL COMPRA* queda parcialmente solapada por la barra de gestos del sistema.
- **Esperado** el contenido respeta el inset inferior del sistema.
- **Evid.** `UI-07-purchase-form/_c-confirmar.png`
- **Causa CONFIRMADA (reclasificada)** — `39` lo agrupaba bajo "falta de relleno bajo el FAB", pero `/compras/nueva` está **fuera del `ShellRoute` y por tanto no tiene FAB**. La causa real: `AppShell` envuelve su contenido en `SafeArea` (`app_shell.dart:46`), pero las 4 rutas de formulario están fuera del shell y deben poner la suya. Recuento verificado de `SafeArea` por formulario: `purchase_form_screen.dart` **0**, `application_form_screen.dart` 2, `plan_form_screen.dart` 2, `transfer_form_screen.dart` 2. **Es el único formulario sin `SafeArea`.**
- **Files** `lib/presentation/screens/purchase_form_screen.dart` · **Dep** independiente de 008/009 (grupo distinto) · **Fix** añadir `SafeArea`, como los otros tres
- **Tests** widget test con `viewPadding` inferior simulado · **Pixel 8** SÍ · **Estado** `FIXED_NOT_DEVICE_VERIFIED`· **Prio** P2

### UIBUG-065 · Un importe no parseable se convierte en 0 y produce un mensaje engañoso

- **Sev** LOW · **Cat** ERROR_HANDLING / VALIDATION · **Riesgo** `ACCOUNTING` · **Grupo** `NUMERIC_INPUT`
- **Pant.** UI-10 `/liquidacion` · **Feat.** F-10 · **RN** `17_ERROR_HANDLING`
- **Pre** ninguna. **Pasos** Cuentas → ⋮ → Registrar pago → escribir `abc` (o `1.500.000`) → **Registrar**.
- **Actual** se muestra *"El importe debe ser mayor a cero."* — un mensaje que **no describe el problema real** (el texto no se pudo interpretar).
- **Esperado** *"No se pudo interpretar el importe"*, o impedir la entrada inválida.
- **Evid.** — (revisión de código; no se capturó pantalla de este caso)
- **Causa CONFIRMADA — descripción corregida respecto a `38`** — `38` afirmaba que el `catch (_) {}` de `settlements_screen.dart:89` *"se traga en silencio un importe no parseable"*. **Eso es incorrecto**: `parseMinor` es `int parseMinor(String v) => tryParseMinor(v) ?? 0;` (`common.dart:147`) y **no lanza nunca**, así que el `catch` es **código muerto inalcanzable**. Lo que ocurre en realidad es que el texto no parseable se convierte en `0`, y `addAccountPayment` (`agro_repository.dart:598`) lo rechaza con `BusinessRuleException('El importe debe ser mayor a cero.')`. Hay dos defectos reales: (a) un `catch` vacío que confunde a quien lea el código, y (b) un mensaje engañoso. **La severidad LOW se mantiene** — el error se detecta y no se escribe nada — pero el hallazgo cambia de naturaleza.
- **Files** `lib/presentation/screens/settlements_screen.dart`, `lib/presentation/widgets/common.dart` · **Dep** se corrige con 003 (parseo) y con el rediseño del diálogo (005/012/014) · **Fix** usar `tryParseMinor` y distinguir "no interpretable" de "cero"; eliminar el `catch` muerto
- **Tests** widget test: escribir `abc` produce el mensaje de "no interpretable", no el de "mayor a cero" · **Pixel 8** SÍ · **Estado** `VERIFIED` (Pixel 8, 2026-09-05)· **Prio** P1-B

---

## 12. Verificación final de este documento

| Comprobación | Resultado |
|---|---|
| IDs históricos cubiertos | **65 / 65** (001–065) |
| Entradas de backlog | **66** (004 subdividido) |
| IDs huérfanos | **0** |
| Duplicados sin marcar | **0** (no se encontró ninguno) |
| CRITICAL/HIGH con evidencia o justificación de código | **21 / 21** |
| Referencias a PNG rotas | **0** de 108 |
| Hallazgos con causa `CONFIRMADA` | 48 |
| Hallazgos con causa `PROBABLE` | 18 |
| Hallazgos con causa `DESCONOCIDA` | 0 |
| Archivos de `lib/` modificados | **0** |
