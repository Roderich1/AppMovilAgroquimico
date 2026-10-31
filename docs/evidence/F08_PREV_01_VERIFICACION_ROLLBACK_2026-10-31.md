# F08-PREV-01 · comprobación del estado recuperado tras un rollback (2026-10-31)

| | |
|---|---|
| Issue | Mobile #172 (F08-PREV-01). Trazabilidad del issue: RU-11, CU-15, RF-27, RNF-10, DAT-14; diseño 3.12.4.6, diferencia registrada en 3.14.5 |
| Rama | `fix/f08-prev-01-verificar-rollback` desde Mobile `main` `6aaeeea` (merge de #163) |
| HEAD de código probado y revisado | **`32a18976f833681e9a543e5996a7d4fd01e1eade`** |
| HEAD documental | El commit que añade esta versión del archivo y la redacción de F08-ADR-003. Sólo cambia `docs/` (§7) |
| Fecha real | 2026-10-31 |
| Dónde se observó | **HOST**: Windows 11, Flutter 3.47.2 / Dart 3.13.2, `sqflite_common_ffi`. **EMULADOR** y **DEVICE**: no ejecutados (§6) |
| Datos | Sintéticos: bases creadas por las pruebas en carpetas temporales y bytes de fotografía generados. Ningún dato real |

## 1. Defecto

Tras una restauración fallida, `BackupService._restoreExclusively` deshacía la sustitución:
- la copia previa volvía a ser la base activa;
- la copia de las fotografías volvía a la carpeta de facturas;
- la copia previa quedaba `rolledBack` en cuanto el rollback terminaba sin excepción, sin comprobar el estado recuperado.

`rolledBack` no está protegida: entra en el plazo de 7 días y en la cota de 2 (F08-ADR-003 §7.2). El error mostrado era el original, que en el caso de la comprobación final dice «sus datos anteriores se conservan».

## 2. Corrección

### 2.1 Comprobación del estado recuperado (`_checkRecoveredState`)

| Qué | Regla | Resultado si falla |
|---|---|---|
| `-wal` | No debe quedar ninguno con contenido (marcos pendientes) | No coincide |
| `-wal` vacío o `-shm` | El rollback los retira; si siguen, no se pudieron retirar o algo reabrió la base | No concluyente |
| `-journal` | El que SQLite aplicaría al abrir (§3.2) debe ser el mismo que antes de restaurar, normalmente ninguno | No coincide |
| Base | SHA-256 de la base cerrada que se aseguró al preparar la copia previa, o no existir si no la había | No coincide |
| Carpeta de fotografías (contenedor) | Si no había carpeta, no debe haberla. Si la había, debe tener los archivos y tamaños anotados al preparar y el SHA-256 de su copia previa | No coincide |
| Copia previa de las fotografías | Si había carpeta, la copia debe seguir con los archivos y tamaños anotados | No concluyente |
| Cualquier excepción durante la comprobación | — | No concluyente |

Nada se borra para pasar la comprobación. Las huellas SHA-256 de las fotografías sólo se calculan al comprobar un rollback. Al preparar sólo se listan nombres y tamaños; el SHA-256 de la base ya se calculaba y ahora se reutiliza.

### 2.2 Si no coincide o no es concluyente

- La entrada pasa a `interrupted`: protegida del plazo y de la cota, y bloquea otra restauración. También se conserva la copia de las fotografías.
- El error dice: «No pudimos confirmar que sus datos anteriores se recuperaron correctamente. Conservamos la copia de seguridad. Antes de restaurar otro respaldo, elija qué hacer en «Copias previas a restauraciones».»
  - Sin base ni fotografías que copiar se omite «Conservamos la copia de seguridad».
- El aviso se muestra aunque la pantalla se desmonte al recalcular el acceso.
- El log local anota sólo el motivo y el tipo de la causa, nunca su texto, que puede llevar rutas de fotografías.
- El bloqueo posterior dice: «Una restauración anterior no terminó o no pudimos confirmar que sus datos anteriores se recuperaron correctamente. Conservamos la copia de seguridad. Antes de restaurar otro respaldo, elija qué hacer en «Copias previas a restauraciones». No se modificó nada.» Ya no dice que «lo más probable es que sus datos actuales estén bien».

### 2.3 Dos decisiones separadas (antes, «Mantener los actuales»)

| Acción en «Copias previas a restauraciones» | Desde | Resultado |
|---|---|---|
| «Decidir» → «Seguir con los actuales» (`continueWithCurrentData`) | `interrupted` | `retained`: deja de bloquear, sigue **protegida**, sin `resolvedAt`; ni el plazo ni la cota la retiran |
| «Mis datos están bien» (`confirmRecovery`) | `interrupted` o `retained` | `rolledBack` con fecha: reglas normales |

- No se añade ninguna forma de borrar una copia protegida.
- El diálogo sólo dice que se conserva la copia si sigue en disco (`hasFiles`).
- Las acciones valen para toda `interrupted`, también la de un proceso muerto. Motivo: si no se pudo guardar el estado de un rollback sin comprobar, el mantenimiento lo deja igual que una restauración cortada, y no se distinguen con seguridad.
- Tras una restauración remota fallida, la sección se recarga para poder decidir.

**No cambian:**
- las reglas del §7.2 (2 copias, 7 días);
- el cifrado y la propiedad/identidad;
- la pausa de la outbox (`GuardedRestore` sólo cambia un comentario).

## 3. Estado estable y diarios de SQLite

### 3.1 Cuándo se cierran las conexiones y se toman las huellas

1. **Exclusión.** Toda la restauración corre en `DatabaseReplacementGuard.replace`.
   - Las escrituras nuevas se rechazan (`DatabaseReplacementInProgressException`).
   - Las que estaban en curso terminan antes.
   - Las lecturas de fuera esperan en `whenReadable` sin abrir el archivo.
   - La app tiene una sola `AppDatabase` (`app.dart`) y ningún isolate que abra la base.
2. **Preparación.** `_secureCurrentDatabase` consolida (checkpoint `TRUNCATE` si está en WAL) y cierra la única conexión. Comprueba además que `-wal` está vacío. Con la base ya cerrada:
   - calcula el SHA-256 de la base, el mismo con el que coteja la copia;
   - anota el `-journal` aplicable;
   - lista las fotografías.
3. **Rollback.** Cierra la conexión de la base restaurada, retira `-wal`/`-shm` y copia la copia previa sobre la base.
4. **Comprobación.** Corre justo después, todavía dentro de la exclusión y antes de que nada reabra la base. Lo único que la reabre después es el recálculo del acceso en `GuardedRestore`.

Lo prueba «lecturas y escrituras de fuera durante la comprobación». Desde fuera de la zona de la sustitución:
- una lectura queda en espera y no termina durante la comprobación;
- una escritura se rechaza;
- la copia queda `rolledBack` y la lectura devuelve después los datos de antes, sin la escritura intrusa.

### 3.2 Tratamiento de los diarios

- **`-wal` y `-shm`** son de la base restaurada. El rollback los retira (comportamiento anterior, no añadido aquí): aplicados a la base anterior la corromperían. La comprobación no borra nada: sólo clasifica lo que encuentra.
- **`-journal`.** El rollback no lo toca: uno anterior pertenece a la base anterior. SQLite sólo revierte un diario «caliente», que exige no estar vacío y tener la cabecera válida, entre otras condiciones (https://www.sqlite.org/atomiccommit.html, «Hot Rollback Journals»).
  - Se trata como aplicable todo `-journal` con cabecera válida (`d9 d5 05 f9 20 a1 63 d7`), sin mirar bloqueos ni diario maestro, que sólo podrían descartarlo.
  - Uno vacío (lo que deja `TRUNCATE`) o con la cabecera a ceros (lo que deja `PERSIST`) no se aplica y se admite.
- **Pruebas:**
  - `-journal` aplicable sintético: no coincide y no se borra.
  - `-journal` vacío o a ceros: `rolledBack`, el diario sigue y la base abre íntegra (`integrity_check` = `ok`) con los datos de antes.
  - Bases reales en modo `PERSIST` y `TRUNCATE`: la anterior y la restaurada escriben en ese modo y el diario existe al comprobar; sin falso positivo.
  - `-wal` con contenido: no coincide. `-wal` vacío o `-shm`: no concluyente.
  - En WAL real lo cubre la prueba existente `f10_restore_wal_rollback_test.dart`, que espera el error original.

### 3.3 Carpeta de fotografías ausente frente a vacía

- **Al preparar** se anota la lista de archivos (nombre y tamaño), o `null` si no había carpeta. Con eso se distingue:
  - **instalación sin fotografías**: carpeta vacía, como la crea siempre `resolveInvoicesDirectory`, con su copia vacía. Se resuelve bien (prueba «instalación sin fotografías»);
  - **copia faltante o incompleta**: había archivos y la copia no los tiene. No concluyente;
  - **carpeta desaparecida tras el rollback**: no coincide;
  - **no había carpeta y el rollback deja una**: no coincide. Fallo seguro, que sólo se alcanza con la carpeta inyectada (§7).
- Una carpeta ausente nunca se toma por vacía.

## 4. HOST · reproducción sobre la base anterior

`test/f08_prev_01_reproduccion_test.dart` usa sólo la API que existía en `6aaeeea`. Simula que la copia previa cambia por otra base válida después de asegurarla y que la restauración falla tras sustituir.

**Sobre `6aaeeea`**, en un worktree desacoplado con el archivo tal como está en `32a1897` (sin cambios desde `a3ce67e`):
```
flutter test test/f08_prev_01_reproduccion_test.dart
Expected: throws <Instance of 'BackupException'> with `message`: contains 'No pudimos confirmar'
  Which: threw BackupException:<simulado>
Some tests failed.
```
Un diagnóstico temporal del mismo caso, que no se commitea y se ejecutó sobre `6aaeeea` y `da1d0f5`, dio esto:

| | `6aaeeea` | Corrección |
|---|---|---|
| Error informado | `simulado` (el original) | No se confirmó la recuperación |
| Estado de la copia | `rolledBack` | `interrupted` |
| Productos en la base activa | `[Producto otro]`, que no es la base anterior | `[Producto otro]` |
| ¿Bloquea otra restauración? | No | Sí |
| ¿Sigue la copia tras el mantenimiento a +8 días? | **No: se borró** | Sí |

La corrección no repara una copia previa alterada. Lo que hace es impedir que se dé por resuelta, que se borre y que se afirme que la recuperación terminó bien.

## 5. HOST · pruebas

`test/f08_prev_01_rollback_verification_test.dart` tiene 30 casos, más el de reproducción:

| Grupo | Casos |
|---|---|
| Recuperación correcta (8) | Base idéntica byte a byte; con fotografías; instalación sin fotografías; `-journal` vacío; `-journal` a ceros; bases reales `PERSIST` y `TRUNCATE`; lecturas y escrituras de fuera durante la comprobación |
| Sin base anterior (2) | El rollback retira la base y la entrada se descarta; queda una base donde no la había: no coincide y el mensaje no nombra una copia inexistente |
| No coincide (7) | SHA-256 distinto; `-wal` con contenido; `-journal` aplicable (no se borra); foto alterada (su copia se conserva); foto sobrante; carpeta desaparecida; carpeta creada donde no la había |
| No concluyente (5) | La comprobación no puede completarse (bloquea); `-wal` vacío; `-shm`; copia de fotografías desaparecida; copia incompleta |
| Registro (1) | `markInterrupted` no puede guardar: queda `preparing` fuera de la restauración en curso; al poder escribir, el mantenimiento la pasa a `interrupted` y bloquea |
| Decisiones (5) | Seguir con los actuales no desprotege y sobrevive a la cota (3 finalizadas posteriores) y al plazo (4 meses); sólo confirmar la lleva a las reglas normales y se retira a los 8 días; confirmar desde interrumpida; ninguna acción cambia una resuelta; una retenida se relee igual tras reabrir |
| `hasFiles` (1) | Sin archivos, sólo `.part`, con base y con fotografías |
| Limpieza (1) | Sin decisión, la copia sobrevive a la cota y al plazo y bloquea |

**Ejecuciones de la suite completa** (`flutter test --reporter json`; registros locales en `_evidencias_locales/F08_PREV_01_host_full*.jsonl`, fuera del repositorio):

| HEAD | Correctas | Omitidas por la propia suite | Fallos |
|---|---|---|---|
| `da1d0f5` | 2112 | 3 | 0 |
| `b70404e` | 2117 | 3 | 0 |
| `e43d769` | 2118 | 3 | 0 |
| `a3ce67e` | 2132 | 3 | 0 |
| `ea02a93` | 2135 | 3 | 0 |
| **`32a1897`** | **2135** (184 archivos, 104 s) | 3 | **0** |

`flutter analyze` sobre `32a1897`: `No issues found!`.

## 6. EMULADOR y DEVICE

**No ejecutados (NOT_MEASURED).** El rollback sólo ocurre si la restauración falla después de sustituir la base, y la app no puede provocarlo sin un gancho de prueba. Ensayarlo en Android exigiría una de dos cosas, y ninguna existe en este bloque:
- una prueba de integración con `sqflite` de Android y fallo inyectado;
- una versión de diagnóstico.

Por tanto no se han observado en Android:
- el modo de diario por defecto de la plataforma;
- el borrado de `-wal`/`-shm`;
- la copia de archivos en el almacenamiento privado;
- los diálogos nuevos.

## 7. Revisión cruzada

Cada pasada la hizo otro agente de la misma sesión, sólo con lectura del diff y sin ejecutar pruebas. **No es una revisión independiente.**

| Pasada | Revisor | Rango revisado | Resultado | Qué se hizo |
|---|---|---|---|---|
| 1 | A | `6aaeeea..da1d0f5` | Sin bloqueantes; 3 a corregir | `b70404e` |
| 2 | A | `da1d0f5..b70404e` | 1 a corregir | `e43d769` |
| 3 | B (nuevo, sin el contexto de A) | **Diff completo** `6aaeeea..a3ce67e -- lib test` | Sin bloqueantes; 3 a corregir y 9 menores | `ea02a93`; el resto, en §8 |
| 4 | B | `a3ce67e..ea02a93` | 3 menores | `32a1897` |
| 5 | B | `ea02a93..32a1897` | Sin hallazgos | — |

- Todo el código de la rama, hasta `32a1897`, está cubierto por alguna pasada.
- **No revisados:** el commit documental (esta evidencia y la redacción de F08-ADR-003). La pasada 3 leyó la versión anterior del ADR, la de `ebe9a26`, y señaló que contradecía el código; la redacción actual corrige esos puntos, pero nadie la ha revisado.
- **HEAD de código y HEAD documental.** El documental sólo añade cambios en `docs/`. `git diff 32a1897 <HEAD documental> -- lib test` está vacío, así que lo probado y revisado es el código del HEAD documental.

## 8. Límites declarados

- **La copia de las fotografías no se verifica contra el original.** Al prepararla sólo se anotan nombres y tamaños. La carpeta recuperada se compara por SHA-256 con la copia, no con el contenido original. Una copia del mismo tamaño pero contenido corrupto pasaría. Esta corrección **no elimina ese riesgo**, que es anterior a ella. La base sí se coteja con el SHA-256 del original.
- **Tras un rollback sin confirmar, `GuardedRestore` reabre la base para recalcular el acceso.** Si se detectó un `-journal` aplicable o un `-wal` con contenido, SQLite los aplicará entonces, antes de que la persona decida. La copia previa sigue protegida.
- **Las copias `retained` se acumulan sin cota.** Cada una es una base completa más sus fotografías, hasta que se confirma la recuperación. Es consecuencia de no añadir borrados.
- **Versiones anteriores de la app.** Una que lea un `registro.json` con `retained` no conoce ese estado y trata el registro como ilegible: bloquea las restauraciones y ofrece «Apartar», sin borrar copias.
- **Restauración cortada por un proceso muerto.** Su flujo cambia: «Seguir con los actuales» ya no pasa la copia a la limpieza. El mensaje ya no dice que lo más probable es que los datos estén bien.
- **Contenedor sin carpeta de fotografías previa.** Siempre da «no coincide», porque el rollback no retira la carpeta creada. Sólo se alcanza con la carpeta inyectada.
- **`-journal`.** No se evalúan el bloqueo ni el diario maestro: se toma como aplicable todo diario con cabecera válida.
- **Subcarpetas de la carpeta de fotografías.** No se copian ni se comprueban, igual que antes.
- **Diálogos de «Copias previas a restauraciones».** No tienen pruebas de widget: se comprobaron con `flutter analyze` y la revisión, y la lógica de los estados tiene pruebas en la capa de datos.
- **Manual de usuario (Backend `docs/manuals/F11_MANUAL_USUARIO.md`).** Sigue citando «Mantener los actuales». Es otro repositorio y no se tocó.
- **Lo que no cambia en este bloque:** la diferencia de 3.14.5 sigue en el documento entregado, que no se modificó; tampoco GATE-F08 (#41) ni la política de retención de `.previo` (Backend #151, punto 10). Recuperar el contenido de una copia protegida desde la interfaz sigue fuera de alcance (F08-ADR-003 §7.2).
