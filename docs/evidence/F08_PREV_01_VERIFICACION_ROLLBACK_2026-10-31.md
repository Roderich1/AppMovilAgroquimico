# F08-PREV-01 · comprobación del estado recuperado tras un rollback (2026-10-31)

| | |
|---|---|
| Issue | Mobile #172 (F08-PREV-01). Trazabilidad del issue: RU-11, CU-15, RF-27, RNF-10, DAT-14; diseño 3.12.4.6, diferencia registrada en 3.14.5 |
| Rama | `fix/f08-prev-01-verificar-rollback` desde Mobile `main` `6aaeeea` (merge de #163) |
| HEAD de código probado | **`e82cbde21cb0a9d3dccb507ad36d95a3646ef653`** |
| HEAD final | El commit documental que añade esta versión del archivo y de F08-ADR-003. Sólo cambia `docs/` (§7) |
| Fecha real | 2026-10-31 |
| Dónde se observó | **HOST**: Windows 11, Flutter 3.47.2 / Dart 3.13.2, `sqflite_common_ffi`. **CI**: la del PR, con sus resultados registrados allí (§5). **EMULADOR** y **DEVICE**: no ejecutados (§6) |
| Datos | Sintéticos: bases creadas por las pruebas en carpetas temporales, bytes de fotografía generados y un servicio remoto simulado. Ningún dato real |

## 1. Defecto

Tras una restauración fallida, `BackupService._restoreExclusively` deshacía la sustitución:
- la copia previa volvía a ser la base activa;
- la copia de las fotografías volvía a la carpeta de facturas;
- la copia previa quedaba `rolledBack` en cuanto el rollback terminaba sin excepción, sin comprobar el estado recuperado.

`rolledBack` no está protegida: entra en el plazo de 7 días y en la cota de 2 (F08-ADR-003 §7.2). El error mostrado era el original, que en el caso de la comprobación final dice «sus datos anteriores se conservan».

## 2. Corrección

### 2.1 Comprobación del estado recuperado (`_checkRecoveredState`)

| Qué | Regla | Si falla |
|---|---|---|
| `-wal` | No debe quedar ninguno con contenido (marcos pendientes) | No coincide |
| `-wal` vacío o `-shm` | El rollback los retira; si siguen, no se pudieron retirar o algo reabrió la base | No concluyente |
| `-journal` | El que SQLite aplicaría al abrir, porque empieza por la cabecera válida (§3.2), debe ser el mismo que antes de restaurar, normalmente ninguno. Uno que no empieza por ella no cuenta | No coincide |
| Base | SHA-256 de la base cerrada que se aseguró al preparar la copia previa, o no existir si no la había | No coincide |
| Carpeta de fotografías (sólo formato contenedor) | Si no había carpeta, no debe haberla. Si la había, debe tener los archivos y tamaños anotados al preparar y el SHA-256 de su copia previa | No coincide |
| Copia previa de las fotografías (contenedor) | Si había carpeta, la copia debe seguir con los archivos y tamaños anotados | No concluyente |
| Cualquier excepción durante la comprobación | — | No concluyente |

Nada se borra para pasar la comprobación. Las huellas SHA-256 de las fotografías sólo se calculan al comprobar un rollback. Al preparar sólo se listan nombres y tamaños; el SHA-256 de la base ya se calculaba y ahora se reutiliza.

### 2.2 Si no coincide o no es concluyente

- La entrada pasa a `interrupted`: protegida del plazo y de la cota, y bloquea otra restauración. También se conserva la copia de las fotografías.
- **Error inmediato:** «No pudimos confirmar que sus datos anteriores se recuperaron correctamente. Conservamos la copia de seguridad. Antes de restaurar otro respaldo, elija qué hacer en «Copias previas a restauraciones».»
  - Si no había base ni fotografías que copiar, se omite «Conservamos la copia de seguridad.».
  - El aviso se muestra aunque la pantalla se desmonte al recalcular el acceso: se usa `showErrorOn` con el `ScaffoldMessenger` capturado antes de esperar, en la restauración local y en la remota.
  - `recomputeAfterReplacement` captura sus propios errores (deja el acceso en null), así que no sustituye este error por otro.
- **Restauración remota fallida:** si la pantalla sigue abierta, la sección «Copias previas a restauraciones» se recarga para poder decidir.
- **Log local:** anota sólo el motivo y el tipo de la causa, nunca su texto, que puede llevar rutas de fotografías.
- **Bloqueo posterior** (`RestoreBlockedException.unresolved`): «Una restauración anterior no terminó o no pudimos confirmar que sus datos anteriores se recuperaron correctamente. Si se guardó una copia de sus datos de entonces, sigue protegida. Antes de restaurar otro respaldo, elija qué hacer en «Copias previas a restauraciones». No se cambiaron sus datos.»
  - No dice que los datos estén bien ni afirma que haya copia: una entrada puede no tenerla.
  - Dice «No se cambiaron sus datos», no «No se modificó nada»: antes de bloquear se aplica el mantenimiento, que puede retirar copias vencidas.

### 2.3 Dos decisiones separadas (antes, «Mantener los actuales»)

En «Copias previas a restauraciones»:

| Estado | Etiqueta | Botón | Qué hace |
|---|---|---|---|
| `interrupted` | «RESTAURACIÓN SIN RESOLVER: copia protegida; bloquea otra restauración» | «Decidir» | Abre «Restauración sin resolver», con «Cancelar», «Seguir con los actuales» y «Mis datos están bien». Sólo dice «Conservamos la copia de seguridad de los datos que había entonces» si la copia sigue en disco (`hasFiles`); si no, «En este teléfono no quedó ninguna copia de los datos de entonces» |
| `retained` | «Recuperación sin confirmar: copia protegida» | «Mis datos están bien» | Pide la confirmación de abajo |

| Acción | Desde | Resultado |
|---|---|---|
| «Seguir con los actuales» (`continueWithCurrentData`) | `interrupted` | `retained`: deja de bloquear, sigue **protegida** y sin `resolvedAt`; ni el plazo ni la cota la retiran |
| «Mis datos están bien» (`confirmRecovery`) | `interrupted` o `retained` | Siempre tras el diálogo de confirmación «¿Sus datos actuales están bien?» (desde «Decidir» es un segundo diálogo; desde el botón de una `retained`, el único), que explica que la copia (o la entrada, si no hay copia) dejará de estar protegida y puede retirarse en la próxima limpieza. Confirmado: `rolledBack` con fecha y reglas normales |
| «Cancelar», tocar fuera o el botón atrás en cualquiera de los dos diálogos | — | Nada cambia. Probados «Cancelar» y tocar fuera; el botón atrás de Android no tiene prueba |

- El texto de ayuda de la sección dice ahora: «La de una restauración sin resolver, o cuya recuperación no se confirmó, no se borra.»
- No se añade ninguna forma de borrar una copia protegida ni una purga de `retained`.
- Las acciones valen para toda `interrupted`, también la de un proceso muerto. Si no se pudo guardar el estado de un rollback sin comprobar, el mantenimiento lo deja igual que una restauración cortada, y no se distinguen con seguridad.

**Excepción a la retención:** las copias sin resolver (`interrupted`) o conservadas expresamente (`retained`) permanecen protegidas fuera del plazo y de la cota hasta que el titular confirma la recuperación.

**No cambian:**
- el plazo (7 días) ni la cota (2) del §7.2;
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
  - Se trata como aplicable todo `-journal` cuyos 8 primeros bytes son la cabecera (`d9 d5 05 f9 20 a1 63 d7`), sin mirar bloqueos ni diario maestro, que sólo podrían descartarlo.
  - Uno que no empieza por ella (vacío, como deja `TRUNCATE`; a ceros, como deja `PERSIST`; o más corto) no se aplica y no cuenta.
- **Pruebas:**
  - `-journal` aplicable sintético: no coincide y no se borra.
  - `-journal` vacío o a ceros: `rolledBack`, el diario sigue y la base abre íntegra (`integrity_check` = `ok`) con los datos de antes.
  - Bases reales en modo `PERSIST` y `TRUNCATE`: la anterior y la restaurada escriben en ese modo y el diario existe al comprobar; sin falso positivo.
  - `-wal` con contenido: no coincide. `-wal` vacío o `-shm`: no concluyente.
  - En WAL real lo cubre la prueba existente `f10_restore_wal_rollback_test.dart`, que espera el error original.

### 3.3 Carpeta de fotografías ausente frente a vacía

- **Al preparar** se anota la lista de archivos (nombre y tamaño), o `null` si no había carpeta. Con eso se distingue:
  - **instalación sin fotografías**: carpeta vacía, como la crea siempre `resolveInvoicesDirectory`, con su copia vacía. Se resuelve bien;
  - **copia faltante o incompleta**: había archivos y la copia no los tiene. No concluyente;
  - **carpeta desaparecida tras el rollback**: no coincide;
  - **no había carpeta y el rollback deja una**: no coincide. Fallo seguro, que sólo se alcanza con la carpeta inyectada (§8).
- Una carpeta ausente nunca se toma por vacía.

## 4. HOST · reproducción sobre la base anterior

`test/f08_prev_01_reproduccion_test.dart` usa sólo la API que existía en `6aaeeea`. Simula que la copia previa cambia por otra base válida después de asegurarla y que la restauración falla tras sustituir.

**Sobre `6aaeeea`**, en un worktree desacoplado con el archivo tal como está desde `a3ce67e` (sin cambios hasta `e82cbde`):
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

## 5. HOST y CI · pruebas

### 5.1 Capa de datos

`test/f08_prev_01_rollback_verification_test.dart` tiene 30 casos; los nombres de grupo son los de `group()`:

| Grupo | Casos |
|---|---|
| «recuperación correcta» (8) | Base idéntica byte a byte; con fotografías; instalación sin fotografías; `-journal` vacío; `-journal` a ceros; bases reales `PERSIST` y `TRUNCATE`; lecturas y escrituras de fuera durante la comprobación |
| «sin base anterior» (2) | El rollback retira la base y la entrada se descarta; queda una base donde no la había: no coincide y el mensaje no nombra una copia inexistente |
| «recuperación incorrecta» (7) | SHA-256 distinto; `-wal` con contenido; `-journal` aplicable (no se borra); foto alterada (su copia se conserva); foto sobrante; carpeta desaparecida; carpeta creada donde no la había |
| «recuperación no concluyente» (5) | La comprobación no puede completarse (bloquea); `-wal` vacío; `-shm`; copia de fotografías desaparecida; copia incompleta |
| «el registro no se puede escribir al marcarla» (1) | Queda `preparing` fuera de la restauración en curso; al poder escribir, el mantenimiento la pasa a `interrupted` y bloquea |
| «seguir con los datos actuales y confirmar la recuperación» (5) | Seguir no desprotege y sobrevive a la cota y al plazo; sólo confirmar la lleva a las reglas normales; confirmar desde interrumpida; ninguna acción cambia una resuelta; una retenida se relee igual tras reabrir |
| «hasFiles» (1) | Sin archivos, sólo `.part`, con base y con fotografías |
| «protección frente a la limpieza» (1) | Sin decisión, la copia sobrevive a la cota y al plazo y bloquea |

### 5.2 Interfaz

`test/f08_prev_01_previo_ui_test.dart` tiene 8 casos: pantalla «Respaldo en la nube» real, registro real sobre archivos temporales, servicio remoto simulado y un espía que anota las acciones que pide la interfaz.

| Caso | Comprueba |
|---|---|
| El mensaje del bloqueo | No dice que los datos estén bien, ni «Conservamos la copia», ni «Lo más probable», ni «No se modificó nada» |
| El aviso con la pantalla desmontada | Restauración remota que falla con «No pudimos confirmar…» después de que la pantalla se desmonta (simulado con un `ValueNotifier`, como al recalcular el acceso; no intervienen el router ni `GuardedRestore`): el aviso se presenta. Con el comportamiento anterior (mostrarlo sólo si la pantalla sigue montada) esta prueba falla; comprobado en un worktree temporal, sin commitear |
| El aviso con la pantalla abierta | Aviso, y la sección recargada con la etiqueta de sin resolver y «Decidir» |
| «Seguir con los actuales» | Acción `continueWithCurrentData` y sólo ésa; la copia queda `retained`, protegida, sin `resolvedAt` y en disco; la etiqueta cambia; ya no bloquea |
| Cancelar o cerrar | «Cancelar» y tocar fuera, en «Decidir» y en la confirmación: cada diálogo se cierra, no hay ninguna acción y sigue `interrupted` |
| «Mis datos están bien» | Sin acción hasta el segundo diálogo, que dice «dejará de estar protegida», «puede retirarse en la próxima limpieza» y «como máximo dos, durante siete días»; al confirmar, `confirmRecovery` y `rolledBack` con fecha |
| Sin copia en disco | No dice «Conservamos la copia»; dice que no quedó ninguna, y la confirmación habla de la entrada «sin copia en este teléfono» |
| Desde `retained` | Misma confirmación; cancelar no cambia nada; confirmar la pasa a `rolledBack` |

### 5.3 Ejecuciones

**HOST, suite completa** (`flutter test --reporter json`; registros locales en `_evidencias_locales/F08_PREV_01_host_full*.jsonl`, fuera del repositorio). «Correctas» son las ejecutadas que pasaron; las 3 omitidas por la propia suite no cuentan como correctas. *Corrección del 2026-10-31:* versiones anteriores de esta tabla sumaban las omitidas a las correctas (2112, 2117, 2118, 2132, 2135, 2135 y 2143).

| HEAD | Correctas | Omitidas | Fallos |
|---|---|---|---|
| `da1d0f5` | 2109 | 3 | 0 |
| `b70404e` | 2114 | 3 | 0 |
| `e43d769` | 2115 | 3 | 0 |
| `a3ce67e` | 2129 | 3 | 0 |
| `ea02a93` | 2132 | 3 | 0 |
| `32a1897` | 2132 | 3 | 0 |
| `08138d5` | 2140 | 3 | 0 |
| **`e82cbde`** | **2140** (185 archivos, 121 s; 39 de F08-PREV-01) | 3 | **0** |

- Las ejecuciones de `08138d5` y `e82cbde` se hicieron en un worktree desacoplado con ese commit (`_wt/F08-PREV-01-UI`), con `--timeout 120s`.
- Allí mismo: `dart format --output=none --set-exit-if-changed lib test` sin cambios y `flutter analyze` con `No issues found!`.

**CI:** el workflow `Flutter CI` del repositorio ejecuta, sobre el HEAD final del PR, formato, análisis, la suite completa (en Ubuntu), las pruebas de fechas en `America/La_Paz` y el build de release. Su resultado se registra literalmente en el PR, porque es posterior a este commit.

## 6. EMULADOR y DEVICE

**No ejecutados (NOT_MEASURED).** El rollback sólo ocurre si la restauración falla después de sustituir la base, y la app no puede provocarlo sin un gancho de prueba. Ensayarlo en Android exigiría una de dos cosas, y ninguna existe en este bloque:
- una prueba de integración con `sqflite` de Android y fallo inyectado;
- una versión de diagnóstico.

Por tanto no se han observado en Android:
- el modo de diario por defecto de la plataforma;
- el borrado de `-wal`/`-shm`;
- la copia de archivos en el almacenamiento privado;
- los diálogos nuevos (las pruebas de widget corren en HOST).

## 7. Revisión cruzada

Cada pasada la hizo otro agente de la misma sesión, sólo con lectura y sin ejecutar pruebas. **No es una revisión independiente.**

| Pasada | Revisor | Revisó | Resultado | Qué se hizo |
|---|---|---|---|---|
| 1 | A | `6aaeeea..da1d0f5` | Sin bloqueantes; 3 a corregir | `b70404e` |
| 2 | A | `da1d0f5..b70404e` | 1 a corregir | `e43d769` |
| 3 | B (nuevo, sin el contexto de A) | **Diff completo** `6aaeeea..a3ce67e -- lib test` | Sin bloqueantes; 3 a corregir y 9 menores | `ea02a93`; el resto, en §8 |
| 4 | B | `a3ce67e..ea02a93` | 3 menores | `32a1897` |
| 5 | B | `ea02a93..32a1897` | Sin hallazgos | — |
| 6 | C (nuevo) | **ADR y evidencia en `a078679`**, contrastados con el código | 2 errores, 4 imprecisiones y 7 menores | Corregidos en el ADR y en esta versión de la evidencia. El mensaje del bloqueo, que afirmaba una copia que podía no existir, se corrigió en `f6e6a9d`. El aviso de la evidencia de que el recálculo del acceso podría sustituir el error se descartó: lo captura |
| 7 | D (nuevo) | `32a1897..987bb5a` (texto del bloqueo, pruebas de widget y documentos) | Sin bloqueantes; 3 a corregir y 5 menores | `e82cbde` y el commit de esta versión: recuentos sin omitidas, confirmación desde `retained`, cierre de diálogos comprobado, llamadas no previstas del simulado, texto del bloqueo y límites del arnés |
| 8 | D | `987bb5a..` HEAD final | Se registra en el PR | — |

- Todo el código hasta `08138d5` está revisado (pasadas 1 a 7).
- `e82cbde` y esta versión del ADR y de la evidencia corresponden a la pasada 8, cuyo resultado se registra en el PR porque es posterior a este commit.
- **HEAD de código y HEAD final.** El final sólo añade `docs/`. `git diff e82cbde <HEAD final> -- lib test` está vacío, así que la CI del PR, que corre sobre el HEAD final, prueba el mismo código.

## 8. Límites declarados

- **La copia de las fotografías no se verifica contra el original.** Al prepararla sólo se anotan nombres y tamaños. La carpeta recuperada se compara por SHA-256 con la copia, no con el contenido original. Una copia del mismo tamaño pero contenido corrupto pasaría. Esta corrección **no elimina ese riesgo**, que es anterior a ella. La base sí se coteja con el SHA-256 del original.
- **Tras un rollback sin confirmar, `GuardedRestore` reabre la base para recalcular el acceso.** Si se detectó un `-journal` aplicable o un `-wal` con contenido, SQLite los aplicará entonces, antes de que la persona decida. La copia previa sigue protegida.
- **Las copias `retained` se acumulan sin cota.** Cada una es una base completa más sus fotografías, hasta que se confirma la recuperación. Es la excepción declarada a la retención: no hay purga de `retained`.
- **Versiones anteriores de la app.** Una que lea un `registro.json` con `retained` no conoce ese estado y trata el registro como ilegible: bloquea las restauraciones y ofrece «Apartar», sin borrar copias.
- **Restauración cortada por un proceso muerto.** Su flujo cambia: «Seguir con los actuales» ya no pasa la copia a la limpieza. El mensaje ya no dice que lo más probable es que los datos estén bien.
- **Contenedor sin carpeta de fotografías previa.** Siempre da «no coincide», porque el rollback no retira la carpeta creada. Sólo se alcanza con la carpeta inyectada.
- **`-journal`.** No se evalúan el bloqueo ni el diario maestro: se toma como aplicable todo diario que empieza por la cabecera.
- **Subcarpetas de la carpeta de fotografías.** No se copian ni se comprueban, igual que antes.
- **Pruebas de widget.** Cubren «Respaldo en la nube». El aviso de la restauración local (`settlements_screen.dart`, mismo `showErrorOn`) no tiene prueba de widget propia.
  - No pasan por `BackupService.restore` ni por `markInterrupted`: el error remoto se inyecta con un servicio simulado, y la entrada `interrupted` la crea la propia prueba con `begin` y un «proceso nuevo».
  - Para no bloquear `runAsync`, la prueba prepara y lee el registro con instancias propias. El registro de la pantalla y el de la prueba no comparten cola, así que la serialización entre la interfaz y una restauración en curso no queda probada aquí. La cubren las pruebas de la capa de datos, con un solo estado por proceso.
- **Manual de usuario (Backend `docs/manuals/F11_MANUAL_USUARIO.md`).** Sigue citando «Mantener los actuales». Queda pendiente de actualizar después de integrar este PR: es otro repositorio.
- **Lo que no cambia en este bloque:** la diferencia de 3.14.5 sigue en el documento entregado, que no se modificó; tampoco GATE-F08 (#41) ni la política de retención de `.previo` (Backend #151, punto 10). Recuperar el contenido de una copia `interrupted` o `retained` desde la interfaz sigue fuera de alcance (F08-ADR-003 §7.2).
