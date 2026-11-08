# F09: la copia previa a la restauración (`.previo`) y la evidencia de dictado (A20)

- **Fecha real:** 2026-11-08 (Bolivia, UTC−4). Rama `docs/f09-protocolo-guion`, desde `27e9a4e`.
- **Procedencia:** lectura del código en `27e9a4e`. **No se ejecutó nada.** Las líneas citadas son de ese commit.
- **Esta rama no cambia código.** Las mitigaciones son **propuestas para la coordinadora, pendientes del autor**.

## 1. Qué es

Antes de restaurar un respaldo (local, o remoto F08), la app guarda una copia exacta de la base activa para poder deshacer la restauración (F08-ADR-003 §7).

| Pregunta | Respuesta | Dónde |
|---|---|---|
| ¿Qué contiene? | **La base activa entera, byte a byte**: el archivo `agroquimicos_v2.db` copiado tras un checkpoint `TRUNCATE`, y su SHA-256 comparado con el original. Si había evidencia de dictado y consentimiento, **también están** | `lib/data/backup_service.dart:1394-1433` (copia en `:1416`); checkpoint en `:236-259` |
| ¿Qué más? | Una copia de la carpeta de fotografías de facturas, si el respaldo es un contenedor | `backup_service.dart:1055-1062`; `lib/data/restore_safety_copies.dart:66` (`<id>.facturas`) |
| ¿Dónde? | En `previo/`, junto a la base: `<carpeta de bases de la app>/previo/copia.previo-<fecha UTC>.db`, con un registro `registro.json` | `restore_safety_copies.dart:191-195` y `:263-285` |
| ¿Quién puede leerla? | La propia app (almacenamiento privado). Desde fuera, sólo con root o, en una APK depurable como las *profile* de evaluación, con `adb run-as` y el teléfono conectado. La app no ofrece abrirla ni exportarla | Ninguna pantalla la lee; `lib/presentation/screens/remote_backup_screen.dart` sólo muestra su estado |
| ¿Viaja en un respaldo F08? | **No.** El respaldo se arma desde la base activa (`backup_service.dart:357`) y de esa copia se borran la evidencia y el consentimiento, y se compacta con `VACUUM` (`:734-748`) | |
| ¿Viaja en el auto-backup de Android? | **No.** El dominio `database` está excluido entero, y además `previo` por nombre, en la copia en la nube y en la transferencia entre dispositivos | `android/app/src/main/res/xml/backup_rules.xml`; `data_extraction_rules.xml` |
| ¿Cuándo se crea? | En cada restauración, antes de sustituir nada | `backup_service.dart:1003` (`ensureCanStartRestore`), `:1028` (`begin`), `:1047` |

## 2. Cuándo y cómo se elimina

Cada copia tiene un estado en el registro (`restore_safety_copies.dart:25-49`). Retirar una copia borra exactamente sus archivos, nunca por patrones (`:418-428`).

| Estado | Cuándo | ¿Se elimina sola? |
|---|---|---|
| `finalized` | La restauración terminó bien (`backup_service.dart:1150`) | Sí: a los **7 días** de resolverse, o antes si hay más de **2** resueltas (`restore_safety_copies.dart:146-149`, `:385-397`) |
| `rolledBack` | La restauración falló y se deshizo con éxito (`:1223`) | Igual que `finalized`. La base activa vuelve a ser la anterior, con su evidencia |
| `preparing`, `interrupted`, `retained` | En curso; rollback fallido o no comprobado; o el titular siguió sin confirmar la recuperación | **Nunca**: están protegidas (`isProtected`, `:68-71`). Sólo salen del estado por una acción expresa del titular (`confirmRecovery`, `:346-356`) |

**El plazo de 7 días no es automático.** El mantenimiento (`maintain`) sólo corre:
- al empezar y al terminar una restauración (`backup_service.dart:1003`, `:1369`);
- al abrir la pantalla de respaldos (`remote_backup_screen.dart:54`).

Si nadie abre esa pantalla ni restaura, una copia vencida sigue en el teléfono más de 7 días.

Desinstalar la app borra la carpeta privada y, con ella, `previo/`.

## 3. ¿Contradice la exclusión de la evidencia del respaldo?

**De la letra de #167, no.** #167 pide dos cosas, y las dos se cumplen:
- que la evidencia no entre en el **archivo de respaldo**: el respaldo F08 se arma sin ella (§1);
- que **una restauración no la recupere**: la base restaurada se limpia (`backup_service.dart:1136-1138`).

La copia `.previo` no es un respaldo F08: no se exporta, no se sube, no se restaura como respaldo y no sale del teléfono.

**De la promesa de borrado, sí, en parte.** El texto actual del consentimiento dice «Puede retirar el permiso cuando quiera y se borrará todo lo guardado», y #167 incluye el «borrado a petición». Tras una restauración:
1. la base activa queda **sin** evidencia y **sin** consentimiento, porque la restaurada se limpia;
2. la copia `.previo` sí conserva la evidencia y el consentimiento anteriores;
3. la pantalla «Evaluación de la voz» dice «Permiso: no dado» y no hay nada que retirar: la persona no tiene forma de saber que queda una copia ni de borrarla;
4. `revokeConsent` y `eraseAll` sólo borran en la base activa (`lib/voice_evidence/voice_evidence_store.dart:146-153`).

La evidencia sigue así en el teléfono al menos hasta que la copia venza (7 días tras el siguiente mantenimiento). Si la copia queda protegida, sigue sin límite. La limitación ya estaba declarada en `README.md`, pero sin estos dos matices: el plazo depende del mantenimiento, y las copias protegidas no vencen.

**Otro resto, menor:** al exportar, la base se copia primero a un directorio temporal de la caché (`agro_backup_stage_*`, `backup_service.dart:354-357`) y después se le borra la evidencia (`:362`). La carpeta se borra al terminar (`:460`). Si la app muere entre medias, queda en la caché, que Android no respalda y puede vaciar.

## 4. Mitigaciones (propuestas para la coordinadora, pendientes del autor)

Por orden de sencillez.

| # | Propuesta | Coste | Efecto | Riesgo |
|---|---|---|---|---|
| M1 | **Procedimiento:** en un teléfono de evaluación no se restaura ningún respaldo mientras haya evidencia. Si hace falta restaurar, antes se pulsa «Retirar el permiso» (borra todo) | Ninguno | No se crea ninguna copia con evidencia | Depende de que se cumpla. Va en el guion del POCO |
| M2 | **Guarda antes de restaurar:** si `voice_evidence` tiene filas o hay consentimiento, la restauración se niega con «Retire el permiso de la evaluación de la voz antes de restaurar», antes de `safetyCopies.begin()` | Pequeño: una consulta y un mensaje, sólo antes de `backup_service.dart:1028` | La copia nunca contiene evidencia | Obliga a borrar la evidencia antes de restaurar. Sólo afecta a quien dio el consentimiento: en la práctica, a la compilación de evaluación |
| M3 | **Al retirar el permiso o borrar lo guardado:** borrar también la evidencia de las copias `finalized` y `rolledBack` (con `secure_delete` y `VACUUM`, sobre una copia temporal que después se renombra) | Medio | La promesa «se borrará todo» vuelve a ser cierta para las copias no protegidas | No puede tocar las copias protegidas sin romper la comprobación por SHA-256 de la recuperación. Para esas, la pantalla debería avisar de que queda una copia |
| M4 | Avisar en la pantalla de consentimiento si existe alguna copia `.previo` posterior al consentimiento | Pequeño | Transparencia, sin cambiar los datos | No borra nada |

**Recomendación (propuesta):** M1 ya en el guion, y M2 antes de #12, porque mantiene intactas las invariantes de F08 (la copia sigue siendo exacta y comprobable) y elimina el caso. M3 sólo si el autor quiere conservar la posibilidad de restaurar con evidencia guardada.

## 5. Texto del consentimiento

Mientras M2 no exista, la propuesta de [`CONSENTIMIENTO_PROPUESTA.md`](CONSENTIMIENTO_PROPUESTA.md) incluye una frase sobre esta copia. Si se implementa M2, la frase se quita.
