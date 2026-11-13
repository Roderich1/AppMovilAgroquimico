# E4 — Acceso por rol y sin K = 3: Mobile (sesión C)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-13 |
| Rama | `feat/acceso-rol-sin-k-c` (worktree `_wt/ACC-C`), desde `507efc8` |
| Código verificado | `01d80c3` (commits `6bab035`, `6ad4dd1`, `01d80c3`) |
| Contrato | `E4_ACCESO_POR_ROL_Y_SIN_UMBRAL_CONTRATO.md` y `E4_EJEMPLOS_RESPUESTAS.md` del repositorio de Backend y Web (leídos en `_wt/ACC-A/docs/architecture/`, sin modificarlos) |
| Herramientas | Flutter 3.47.2 (stable), Windows 11, pruebas en el anfitrión con `sqflite_common_ffi` |
| Dispositivo | **Ninguno.** Sin emulador, sin APK y sin servidor: no hay recorrido. |
| Estado | Implementado y probado automáticamente (pruebas focalizadas). Sin suite completa, sin recorrido, sin revisión del autor. `Gate = Pending`. |

## Qué se comprobó y cómo

### Análisis estático

```
flutter analyze --no-pub lib test tool
→ No issues found! (ran in 24.1s)          # sobre 6ad4dd1
flutter analyze --no-pub tool/rediseno/capturas_c_test.dart
→ No issues found!                          # sobre 01d80c3
```

### Pruebas focalizadas

```
flutter test test/e2_joint_purchase_store_test.dart test/e2_joint_purchase_sender_test.dart \
  test/e2_joint_purchase_screens_test.dart test/e2_joint_purchase_isolation_test.dart \
  test/e2_pa_responsible_test.dart test/migration_test.dart test/schema_equivalence_test.dart \
  test/rec_039_schema_constraints_test.dart test/rdm_c_union_screen_test.dart \
  test/backup_service_test.dart test/hierarchical_navigation_test.dart \
  test/oe3_fab_sincronizacion_test.dart --concurrency=2
→ 00:43 +172: All tests passed!             # sobre 01d80c3
```

Arnés de capturas (sólo para comprobar que corre; las imágenes no se publican): `flutter test tool/rediseno/capturas_c_test.dart --plain-name "onvocatoria"` → `+1: All tests passed!`; `--plain-name "E4: revisar"` → `+1: All tests passed!`.

La cobertura de línea no se midió en esta sesión.

### Lo que cubren las pruebas

| Exigencia (E4 §8 Mobile y brief §4.4) | Prueba |
|---|---|
| Migración v19 → v20 con datos y pendientes conservados | `migration_test.dart` «v19 → v20 conserva…» (participación `CONV-3` con autorización de P-A, confirmación y ampliación pendientes, reducción rechazada; filas y columnas idénticas, tabla nueva vacía, disparador presente) |
| Instalación nueva = migrada | `schema_equivalence_test.dart` «…desde V19…» |
| Idempotencia y `CHECK` de la cola nueva | `migration_test.dart` «la migración a v20 es idempotente…» |
| Validador del contrato 4: lista cerrada con `help`, otra versión → «Actualice», alcance desconocido → rechazo entero | `e2_joint_purchase_isolation_test.dart`, `e2_pa_responsible_test.dart` (grupo «contrato 4») |
| Emisor: los tres códigos definitivos, sin reintento ni borrado | `e2_joint_purchase_sender_test.dart` «E4 §7.2: CONSENT_VERSION_RETIRED, APP_UPDATE_REQUIRED y WIDENING_NOT_ALLOWED…», `e2_pa_responsible_test.dart` |
| Reintento infinito corregido | sender: «PARTICIPATION_REQUIRED sin confirmación por enviar → REJECTED» y «ACCEPTED con forma inválida → RECEIVED sin adoptar nada…» |
| `CONFIRM` pendiente con `CONV-3` sale tal cual | sender: «una confirmación pendiente con CONV-3 se envía tal cual…» |
| Respuesta atrasada no pisa decisión ni cantidades | store: «E4: una respuesta atrasada…»; sender: «STALE_SEQUENCE…», «una respuesta de cantidades con un alcance más viejo…» |
| Envío repetido | sender: «E4: un envío repetido devuelve lo mismo y no duplica la decisión» |
| Orden único entre las dos colas; pendiente no anunciado como aplicado | store: «una decisión anterior pendiente se conserva…», «participación anterior: modificar no lleva consentimiento…» |
| Cambio de cantidades sin consentimiento | store y sender (las dos pruebas «modificar no lleva consentimiento») |
| Consentimiento con y sin conexión | sender: «sin conexión la retirada queda pendiente…», «la primera participación aún sin aceptar…» |
| Transición abierta y cerrada; nada en cancelada | store: «en una convocatoria cerrada se revisa sin reabrirla ni tocar lo consolidado…»; screens: «E4: en una convocatoria cerrada se revisa…» |
| Retirada de la autorización conservando la participación | store: «con ADMINISTRATION aplicada se retira…»; screens: «E4: retirar la autorización…» |
| Pantallas: casilla sin marcar y «Sus cantidades no cambian» | screens y `e2_pa_responsible_test.dart` (pantalla) |
| Textos exactos (`CONV-4` y ayuda byte a byte) | comprobación con Python del texto concatenado de Dart frente a los bloques de `E4_EJEMPLOS_RESPUESTAS.md` §0 (`True True`) y pruebas de pantalla que comparan con las constantes |
| Sustitución de responsable sin autorización nueva (E4 §6.3) | `e2_pa_responsible_test.dart` «tras sustituir a la responsable no se pide autorización nueva…» |

## Limitaciones declaradas

- Sin recorrido en emulador ni dispositivo, sin servidor real (A) y sin app anterior: el recorrido conjunto de E4 §5.3 queda para el orquestador.
- Sin suite completa de Mobile ni APK (los hace el orquestador).
- Cobertura no medida.
- Las respuestas del servidor de las pruebas son simuladas a partir de `E4_EJEMPLOS_RESPUESTAS.md`, que también está escrito a mano (no son salidas reales).
