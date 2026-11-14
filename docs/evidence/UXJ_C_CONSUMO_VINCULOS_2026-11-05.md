# UXJ-C: estados del consumo, motivos en Vínculos y decisión de alcance del envío automático (2026-11-05)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-05, de ~13:00 a 14:10 en Bolivia (UTC−4) |
| Procedencia | **HOST** (Windows 11, Flutter 3.47.2 stable, `sqflite_common_ffi`). Nada de esta página es EMULADOR ni DEVICE |
| Rama | `feat/uxj-c-consumo-vinculos`, desde Mobile `f534015` |
| Commit de código | `82d8ea1` |
| Decisión de alcance | `docs/adr/F06-ADR-006-envio-automatico-consumo.md`, **Proposed** (no aceptada) |
| Relacionados | Refs Roderich1/Agro_Sindicato_Backend-Web#202 (propuesta Proposed) |
| Datos | Sintéticos (fixtures de prueba) |

## 1. Qué cambia y qué no

**Cambia (sólo presentación y una retención conservadora):**
- **Vincular con el sindicato** (`central_binding_screen.dart`):
  - texto inicial «Elija el equivalente del sindicato.»;
  - en la fila afectada, el motivo de la incompatibilidad:
    - unidad del sindicato frente a la local;
    - producto inactivo;
    - período que no cabe, con los aportes aceptados y retenidos y qué hacer;
    - «ninguna opción del sindicato es compatible», calculado en memoria sobre las referencias ya leídas, sin consultas nuevas;
  - arriba queda sólo un aviso breve (`period-review`).
- **Consumo para el sindicato** (`consumption_publish_screen.dart`, `consumption_publisher.dart`):
  - cada fila dice «Pendiente», «Enviado» o «Requiere atención», derivado de la outbox:
    - las pausas (`AUTH_PAUSED`, `OWNER_PAUSED`, `RESTORE_PAUSED`, `VERSION_MISMATCH`) son «Requiere atención»;
    - el 401 pendiente se muestra con «Falta verificar el acceso»;
    - también son «Requiere atención» un conflicto, un vínculo no vigente y un rechazo;
  - una sola consulta añadida por vista previa (el último envío rechazado de cada total).
- **Rechazo `CAMPAIGN_NOT_OPEN` o `CAMPAIGN_SEALED`** (F04 §2.4):
  - se muestra con el mensaje vigente;
  - «Publicar» ya no lo vuelve a enviar. Antes la vista previa lo ofrecía otra vez como «Nuevo», porque `latestEffective` ignora los rechazados;
  - sólo deja de retenerse si las referencias actualizadas después muestran la campaña abierta otra vez. Entonces volver a publicar es otra decisión expresa.
- **Texto del motivo `NOT_LINKABLE`**: ahora cubre también el caso en que la unidad central sigue siendo L o KG pero ya no coincide con la local, que `refreshFrom` ya marcaba así.

**No cambia:**
- la publicación sigue siendo expresa con «Publicar»;
- «Retirar del sindicato» igual que antes;
- envelope y outbox;
- worker;
- Central.

**No se implementa** (pendiente de F06-ADR-006): «Vincular y compartir consumo automáticamente», el envío automático y la opción de pausarlo. Motivo: Mobile `F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §2.4, línea 137 («la publicación de consumo sigue siendo una acción expresa del agricultor») y Backend F06 §2, línea 39, y §8, línea 257 («intención autorizada», sin definir para una autorización permanente). Detalle en el ADR §2 y §3.

## 2. Comandos y resultados

Todos sobre el árbol de `82d8ea1`.

| Comando | Resultado |
|---|---|
| `dart format --set-exit-if-changed lib test` | 380 archivos, 0 cambiados, salida 0 |
| `flutter analyze` | No issues found |
| `flutter test test/uxj_c_consumo_vinculos_test.dart test/consumption_publish_screen_test.dart` | 12 superadas, 0 fallidas |
| `flutter test` de las suites afectadas (12 archivos)¹ | 121 superadas, 1 omitida, 0 fallidas |
| `flutter test` completo, una vez | **2293 superadas, 3 omitidas, 7 fallidas** (12 min 45 s) |
| Las 7 fallidas, repetidas aisladas | Los 6 archivos: 75 superadas, 0 fallidas |

¹ `sync_screens_test`, `f10_mensajes_autorizacion_test`, `f04_c2_binding_screen_test`, `collective_consumption_sync_test`, `consumption_confirmation_test`, `f04_c2_campaign_period_test`, `f04_c2_period_regression_test`, `central_reference_binding_test`, `set_state_contract_test`, `sync_code_presentation_test`, `declared_need_test` y `e15_consumo_propio_base_test`.

**Las 7 fallidas de la ejecución completa** eran tiempos de espera: tres `TimeoutException` de 30 s y uno de 10 min. Ninguna toca los archivos cambiados:
- `f04_restore_authorization_test`;
- `f08_prev_01_previo_ui_test`;
- `f10_backup_extract_limits_test`;
- `f12_est_07_estimation_copy_test`;
- `f12_est_07_estimation_ui_test` (2);
- `oe3_rec008_camara_doble_test`.

Durante la ejecución había otros procesos Dart pesados en el equipo, de otras sesiones (uno de ~1 GB). Aisladas, pasan todas. Se registran como intermitencias por carga, no como corregidas.

## 3. Pruebas nuevas (`test/uxj_c_consumo_vinculos_test.dart`, 10)

| Caso pedido | Prueba |
|---|---|
| Estados | «Pendiente» (sin publicar y en cola) y «Enviado» (aceptado), sin escrituras al mostrar |
| Sesión sin autorización | 401: «Requiere atención» y «Falta verificar el acceso.» sólo en la fila afectada. 403: cola pausada, «Pausado: el sindicato no autorizó esta cuenta» |
| Campaña cerrada o sellada | Mensajes vigentes de F04 §2.4; el de `CAMPAIGN_NOT_OPEN` no dice «sellada»; «Publicar» desactivado; la outbox no crece |
| Retención y su fin | Sin envío ni con un total nuevo; con las referencias aún cerradas, el par queda excluido; con la campaña abierta otra vez, publicar crea un `operationId` nuevo sólo al confirmar. Otro tipo de rechazo (`REFERENCE_UNAVAILABLE`) se muestra y se puede publicar otra vez de forma expresa |
| Vínculo inválido | Motivo en la fila del producto (unidad L→KG, con las dos unidades; producto inactivo) y de la campaña (período, aportes y qué hacer) |
| Sin opción compatible | Motivo en la fila sin vincular tras «Actualizar» (MockClient); leer las referencias no vincula nada |
| Texto inicial | Corto; las explicaciones largas ya no están |

**Mutaciones** (aplicadas a mano y revertidas con `git checkout`):
- retención por campaña desactivada (`campaignHold` → `false`): fallan 2 pruebas;
- etiqueta del vínculo inválido devuelta a «inválido: …»: falla 1 prueba.

## 4. Limitaciones

- **Sólo HOST.** No hay capturas ni recorrido en el emulador ni en un dispositivo.
- **Tono.** El pedido decía «Elige el equivalente del sindicato» (tú). La pantalla está entera en usted, así que se usó «Elija…». Cambiarlo es una línea.
- **Campaña de nuevo abierta en Central.** El total retenido vuelve a publicarse sólo tras actualizar las referencias en Vínculos. Si el vínculo nunca se vuelve a comprobar, el total sigue retenido.
- **Avisos fuera de esta pantalla.** El aviso de consumo sin publicar fuera de la pantalla de consumo (opción C de #202) no se hace: requiere archivos de otro bloque.
