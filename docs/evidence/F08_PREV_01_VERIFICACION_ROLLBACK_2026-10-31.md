# F08-PREV-01 · comprobación del estado recuperado tras un rollback (2026-10-31)

| | |
|---|---|
| Issue | Mobile #172 (F08-PREV-01). Trazabilidad del issue: RU-11, CU-15, RF-27, RNF-10, DAT-14; diseño 3.12.4.6, diferencia registrada en 3.14.5 |
| Rama | `fix/f08-prev-01-verificar-rollback` desde Mobile `main` `6aaeeea` (merge de #163) |
| Código | `808293d` (corrección) · `da1d0f5` (pruebas) · `b70404e` (ajustes de la revisión cruzada) · `e43d76997fce866b17278aba44088515d0af7d48` (ajuste de su segunda pasada; HEAD de código probado) · este archivo y la aclaración de F08-ADR-003 en el commit que los añade |
| Fecha real | 2026-10-31 |
| Dónde se observó | **HOST** = Windows 11, Flutter 3.47.2 / Dart 3.13.2, `sqflite_common_ffi`. **EMULADOR** y **DEVICE**: no ejecutados (§5) |
| Datos | Sintéticos: bases creadas por las pruebas en carpetas temporales («Producto actual», «Producto otro»…) y bytes de fotografía generados. Ningún dato real |

## 1. Defecto

Tras una restauración fallida, `BackupService._restoreExclusively` deshacía la sustitución (copia previa → base activa; copia de fotografías → carpeta de facturas) y marcaba la copia previa `rolledBack` en cuanto el rollback terminaba sin excepción. No comprobaba el estado recuperado. `rolledBack` no está protegida: entra en el plazo de 7 días y la cota de 2 (F08-ADR-003 §7.2). Además, el error que se mostraba era el original, que en el caso de la comprobación final dice «sus datos anteriores se conservan».

## 2. Corrección

Antes de marcar `rolledBack`, `_checkRecoveredState` comprueba el estado recuperado con lo que la copia previa ya garantizaba al prepararse (`_secureCurrentDatabase`: base cerrada, `-wal` vacío, copia cotejada por SHA-256):

1. no quedan `-wal` ni `-shm` junto a la base (el rollback los retira; serían de la base restaurada);
2. la base activa tiene el SHA-256 de la base cerrada que se aseguró, o no existe si no la había;
3. con contenedor, si había fotografías su copia previa sigue en disco y la carpeta recuperada tiene sus mismos archivos (nombre y SHA-256, sin subcarpetas, como copia `_copyDirectory`).

Las huellas sólo se calculan al comprobar un rollback. Las restauraciones que terminan bien no hacen ninguna lectura más que antes; el SHA-256 de la base ya se calculaba y ahora se reutiliza.

**Si no coincide (`mismatch`) o la comprobación no puede completarse (`inconclusive`):**
- la entrada pasa a `interrupted` (`markInterrupted`, el mismo camino que un rollback fallido): protegida del plazo y de la cota y bloquea otra restauración hasta «Mantener los actuales»;
- se conserva también la copia de las fotografías;
- se lanza `RestoreRecoveryUnverifiedException` («La restauración falló y no se pudo confirmar que sus datos volvieran a estar como antes…»), con el motivo, la causa y su traza;
- el log local anota sólo el motivo y el tipo de la causa, sin su texto, que puede llevar rutas de fotografías.

**No cambia:**
- los estados y las reglas de `.previo`;
- el cifrado y la propiedad/identidad;
- la pausa de la outbox (`prepareRestored` y el recálculo del acceso en `GuardedRestore`; en `guarded_restore.dart` sólo cambia un comentario);
- el camino de la restauración correcta.

## 3. HOST · reproducción sobre la base anterior

La prueba del defecto (`test/f08_restore_safety_copies_test.dart`, «la copia previa cambió después de asegurarla…») usa sólo la API que existía en `6aaeeea`. Simula el caso: tras asegurar la copia previa, ésta cambia por otra base válida; la restauración falla después de sustituir.

**Base `6aaeeea`** (worktree desacoplado, con el archivo de prueba tal como queda en esta rama, sin cambios desde `da1d0f5`): `flutter test test/f08_restore_safety_copies_test.dart` → `+18 -1: Some tests failed.` Falla exactamente la prueba nueva:
```
Expected: throws <Instance of 'BackupException'> with `message`: contains 'no se pudo confirmar'
  Which: threw BackupException:<simulado>
```
Un diagnóstico temporal del mismo caso, que no se commitea, dio esto:

| | `6aaeeea` | Esta rama |
|---|---|---|
| Error informado | `simulado` (el original) | «La restauración falló y no se pudo confirmar…» |
| Estado de la copia | `rolledBack` | `interrupted` |
| Productos en la base activa | `[Producto otro]` (no es la base anterior) | `[Producto otro]` |
| ¿Bloquea otra restauración? | No | Sí |
| ¿Sigue la copia tras el mantenimiento a +8 días? | **No: se borró** | Sí |

La corrección no repara una copia previa alterada; impide darla por resuelta, borrarla y afirmar que la recuperación terminó bien.

## 4. HOST · pruebas

`test/f08_prev_01_rollback_verification_test.dart` (13 casos) y el caso de reproducción del §3. En la tabla, «interrumpida» significa estado `interrupted` y `RestoreRecoveryUnverifiedException`.

| Grupo | Caso | Comprueba |
|---|---|---|
| Correcta | base idéntica byte a byte | `rolledBack`; SHA-256 de la base = el de la copia previa; sin `-wal`; «Producto actual»; no bloquea; el error es el original |
| Correcta | con fotografías | `rolledBack`; la foto propia, con sus mismos bytes; la copia de fotografías se retira |
| Sin base anterior | el rollback retira la base | entrada descartada; error original; no bloquea |
| Sin base anterior | queda una base donde no la había | interrumpida, `mismatch`; el mensaje no nombra una copia inexistente |
| Incorrecta | SHA-256 distinto | interrumpida, `mismatch` |
| Incorrecta | `-shm` residual | interrumpida, `mismatch` |
| Incorrecta | `-wal` residual | interrumpida, `mismatch` |
| Incorrecta | foto alterada | interrumpida; la copia de fotografías se conserva con los bytes originales |
| Incorrecta | copia de fotografías desaparecida | interrumpida, `mismatch` |
| Incorrecta | foto sobrante | interrumpida, `mismatch` |
| No concluyente | la comprobación no puede completarse | interrumpida, `inconclusive`; bloquea |
| Registro | `markInterrupted` no puede guardar | queda `preparing` fuera de la restauración en curso; al poder escribir, el mantenimiento la pasa a `interrupted` y bloquea |
| Limpieza | plazo, cota y acción expresa | sobrevive a la cota (3 finalizadas posteriores) y al plazo (61 días); bloquea; tras «Mantener los actuales» pasa a `rolledBack` y se retira a los 8 días con la regla existente |

La regresión frente a falsos positivos con fotografías que la restauración **pisa y añade** es la prueba existente `f10_restore_wal_rollback_test.dart` («copia previa de una base en WAL: fallo después de empezar la sustitución…»). Si la comprobación rechazara ese rollback correcto, lanzaría otra excepción y fallaría; pasa.

**Ejecuciones** (`flutter test --reporter json`, registro local en `_evidencias_locales/F08_PREV_01_host_full*.jsonl`, fuera del repositorio):

| HEAD | Resultado |
|---|---|
| `6aaeeea` | `f08_restore_safety_copies_test.dart` antes de cambiar nada: `+18: All tests passed!` |
| `da1d0f5` | suite completa: 2112 correctas (3 omitidas por la propia suite), 0 fallos |
| `b70404e` | suite completa: 2117 correctas (3 omitidas), 0 fallos |
| `e43d769` | **suite completa: 2118 correctas (3 omitidas), 0 fallos, 183 archivos, 106 s** |

`flutter analyze` sobre `e43d769`: `No issues found!`. `dart format` sin cambios pendientes.

## 5. EMULADOR y DEVICE

**No ejecutados (NOT_MEASURED).** El rollback sólo ocurre si la restauración falla después de sustituir la base, y la app no tiene una forma de provocarlo sin un gancho de prueba. Ensayarlo en Android exigiría:
- una prueba de integración con `sqflite` de Android y fallo inyectado, o
- una versión de diagnóstico con un gancho activable.

Ninguna de las dos existe en este bloque. Lo comprobado en HOST usa `sqflite_common_ffi` sobre Windows. El borrado de `-wal`/`-shm` y la copia de archivos en Android (`ext4`/`f2fs`, almacenamiento privado) no se han observado con este cambio. Queda pendiente, como admite el criterio de aceptación del issue.

## 6. Revisión cruzada

Hecha por otro agente de la misma sesión, sólo con lectura del diff y sin ejecutar pruebas. **No es una revisión independiente.**

| Pasada | HEAD revisado | Resultado | Qué se hizo |
|---|---|---|---|
| 1 | `da1d0f5` (`6aaeeea..da1d0f5`) | Sin bloqueantes; 3 a corregir y varios menores | Incorporados en `b70404e`: huellas sólo en el rollback, causa con traza, mensaje sin base anterior, comentarios y 5 pruebas |
| 2 | `b70404e` (`da1d0f5..b70404e`) | Sin bloqueantes; 1 a corregir (copia de fotografías desaparecida) y el ADR desfasado | Incorporados en `e43d769` y en el commit de este archivo |

**Hallazgos no aplicados, pendientes de decisión de Roderich:**
- **Texto del bloqueo.** `RestoreBlockedException.unresolved` dice «Lo más probable es que sus datos actuales estén bien». Tras un `mismatch` se sabe que no son los de antes, y «Mantener los actuales» lleva la copia al plazo de 7 días. Cambiar ese texto toca la redacción aprobada de F08-ADR-003 §7.1.
- **Rollback sin carpeta de fotografías previa.** Con contenedor y sin carpeta de fotografías previa, el rollback no retira las que se restauraron, así que la comprobación da `mismatch` y bloquea (lado seguro). En producción no se alcanza: `resolveInvoicesDirectory` crea siempre la carpeta. Corregirlo cambiaría el comportamiento del rollback.

## 7. Límites declarados

- La copia de fotografías no se coteja por SHA-256 al hacerla, igual que antes. Se compara la carpeta recuperada con esa copia, no con una huella del original.
- No se comprueba `-journal`: una base anterior en modo `persist` puede tenerlo legítimamente, y exigir que no exista daría falsos positivos.
- Las subcarpetas de la carpeta de fotografías no se copian ni se comprueban, igual que antes.
- Sin base anterior, una comprobación fallida deja una entrada `interrupted` sin archivo de base, que sólo se resuelve con «Mantener los actuales».
- Recuperar el contenido de una copia `interrupted` desde la interfaz sigue fuera de alcance (F08-ADR-003 §7.2).
- No cambian GATE-F08 (#41) ni la política de retención de `.previo` (Backend #151, punto 10).
