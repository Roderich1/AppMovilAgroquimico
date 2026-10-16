# F10 — Comprobación focalizada de la restauración en el POCO (#36, MOB #91–#93)

- **Fecha real:** 2026-10-16, de 21:49Z a 22:36Z (17:49–18:36 America/La_Paz).
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica, en el único teléfono disponible. Es una ejecución técnica automatizada: no hubo inspección personal de Roderich ni revisión del tutor.
- **Casos:** los del turno pedido por la sesión C (`_briefs/ESTADO_C_BACKUP.md`, «TURNO_POCO_SOLICITADO (F10)»): 0, A, B, C y D. Además, C35 y C34 de #18 en el camino de restauración.
- **No cierra ningún gate.** GATE-F08 (BE #41) sigue Pending.

## Entorno

| Elemento | Valor |
|---|---|
| Dispositivo | POCO X5 Pro 5G `22101320G`, Android 12 (API 31), MIUI `V14.0.7.0.SMSMIXM` |
| Paquete | Copia aislada **nueva** `com.comunidad.agro.agroquimicos.f10bkp` («Agrocuentas F10-BKP»). No se reutilizó `.f08bkp`, para conservar los datos del turno 2. La app normal (2026-09-24 13:04:32), la demo y las copias `.f03res01`, `.f06d4`, `.f03e2b`, `.f08bkp` y `.f10s18a/b/c` no se tocaron |
| APK de preparación | Mobile `1a69d0658d1e6d4c69b6b3c2b872b21aafa68fc5` (su `lib/` es idéntico a `4f203c7`), SHA-256 `8c6bf10535460b773dceb8866fdd24cd640f47018a2e321d97a7b3cf9459c148`, instalada a las 21:49:33Z. Sólo se usó para crear los datos sintéticos |
| **APK probada** | Mobile **`2f4b6348fea9cce3399b1df93eebbddb868a42be`** (`main` con #91, #92 y #93), SHA-256 **`4cd4d9686231e57268c050701787a5478c82fb41cb75198c1c8aeb469f0e07cf`**, instalada **como actualización** sobre la anterior (`adb install -r`) a las 22:17:26Z; los datos se conservaron (3 fotos, 1 necesidad, outbox 1). Todos los casos se ejecutaron con esta APK |
| Backend | `main` `e02793809502b5da0b0638802f2fbec5be8c0f86`, compilado, en el entorno nuevo de la sesión A (`agro_a_f10int_pg`, 127.0.0.1:55447, 10 migraciones). Reconstruido desde limpio y reiniciado a las 21:41:47Z (incidente de la sesión A, ver `_briefs/PARALELO_CONTROL.md`); el journal no tenía operaciones sin finalizar |
| Herramientas | `tool/f10_s18/device_snapshot.sh` (este PR; misma lógica que el de F08, para `.f10bkp`) con `tool/f08_bkp/snapshot.py` sin cambios; `tool/f08_bkp/craft_negative.py` de `main` (`5a73bea`) |
| Datos | Cuenta sintética D; titular «Titular F10 D»; 1 proveedor, campaña y producto locales vinculados a «Campana Verano 2026» y «Glifosato 48 SL»; **3 compras con foto** (F10-001/002/003, 1.120,00 Bs) con las 3 imágenes sintéticas del turno 2, elegidas en el álbum `f10` del selector (sólo contenía esas 3); necesidad 1 de 12 L ACKED (`0ae87837`, 21:59:58Z) |

## Resultados

| Caso | Resultado | Observado (horas UTC) |
|---|---|---|
| **Preparación de la copia en la nube** | — | Necesidad 2 (`5f9aaff8`, 15 L) declarada sin red a las 22:20:31: `PENDING`, 0 intentos (tras la actualización el proceso no tenía acceso verificado). App detenida sin red; reabierta con red y sin acceso: **0 peticiones en 70 s**. Subida con un fallo de protección `hold-push-request` armado: `refresh 200` (22:24:53), **`POST /me/backups 201`** (22:24:54, 15 KB) y `GET /me/backups 200`; app detenida 5 s después; el fallo **no se consumió** (ningún push) |
| **0. Precondición WAL** | **No se cumple en este teléfono** | Con la app abierta y el producto «Reciente F10» recién confirmado (22:26:04): cabecera de `agroquimicos_v2.db` con bytes 19–20 = **`01 01`** (diario de reversión), `agroquimicos_v2.db-journal` de 512 B y **ningún `-wal`**; el archivo principal ya contenía el cambio. Por eso el caso A **no discrimina** el defecto WAL aquí: la corrección queda demostrada en host con `journal_mode=WAL` (MOB #91, `docs/evidence/F10_RESTORE_WAL_ROLLBACK.md`) |
| **A. Restauración desde la nube (ruta modificada)** | **PASS** (sin discriminar WAL) | Lista y descarga: `refresh 200`, `GET /me/backups 200`, `GET /me/backups/{id}/content 200` (22:26:45); «verificada con SHA-256. Contiene la base de datos y 3 fotografía(s)»; confirmada a las 22:27:02. Se creó `agroquimicos_v2.db.previo-2026-10-16T18-27-01.632637.db` (hora local). Extraída y consultada en el PC: **la `.previo` contiene «Reciente F10»** (2 productos, `integrity_check` ok) y la base restaurada no (1 producto). Ningún push |
| **C35** restore sin prueba de propietario | **PASS** | La intención restaurada `5f9aaff8` quedó **`RESTORE_PAUSED`**; ningún push al restaurar; tras detener y reabrir, **0 peticiones en 80 s** (hasta 22:29:01); pantalla «Pausado: restauración: 1» y «Envíos pausados por una restauración. No se publican solos…» |
| **D. Liberar y refresco de la lista (#93)** | **PASS** | «Liberar» → confirmación → `refresh 200` (22:29:33.876, verificación del titular) y **un único** `POST /sync/v1/push 200` (22:29:34.820) del **mismo** `operationId` `5f9aaff8` → APPLIED (secuencia 2, journal 1). **Sin salir de la pantalla**, la lista pasó a «Sincronizado: 2» y la fila a «Sincronizado · … ACK» |
| **B. Fallo después de sustituir, con rollback** | **PASS** | Variantes generadas con `craft_negative.py` a partir del contenedor que la app subió a las 22:24 (tomado del almacenamiento del entorno; tamaño y SHA-256 iguales a sus metadatos), porque Android 12 no dejó leer la exportación local en `/sdcard/Android/data/<paquete>/files/Download` ni con `adb` ni con `run-as` (*Permission denied*). Copiadas a `app_flutter/` del paquete con `run-as` (SHA-256 iguales a los del PC). Producto «Reciente F10-B» creado; instantánea **antes**: 29 tablas, 3 fotos. Restaurar `F10-fallo_tras_sustituir` confirmado a las 22:33:40: la app registró «Error mostrado al usuario | … no such table: sync_outbox …» (el fallo provocado después de sustituir) y **siguió operando** con «Reciente F10-B» visible. **Ninguna petición.** `compare antes despues`: **29 tablas y 3 fotos IGUAL → PASS**, incluida «Reciente F10-B». Quedó una segunda `.previo` (18-33-39, hora local) |
| **C. Negativos antes de sustituir** | **PASS** | Desde la lista local, cada uno en unos 5 s, **sin pedir confirmación**, con el mismo proceso de la app y **ninguna petición**: **alterada** → «La base de datos del respaldo no coincide con su manifiesto (SHA-256): está dañada o fue modificada. No se res[tauró]…»; **ajena** → «Esta copia pertenece a otro titular (otra cuenta o sindicato). No se restauró; sus datos actuales se conservan…»; **bomba** (306 KB que se expanden a 300 MiB) → «El respaldo supera los límites de tamaño admitidos y no se abrirá.». `compare despues despues_c`: todo IGUAL → PASS. Sin carpetas temporales de restauración en `cache` |
| **C34** IDs de otro Member | **PASS** (camino de restauración) | La copia de otro titular se rechaza antes de sustituir: sus intenciones no entran en la base ni se envían bajo la cuenta D (0 push). El cambio de cuenta al reautenticar se midió en C38 (`F05_SYNC_06_DEVICE_F10.md`) |

**Servidor al cerrar:** 2 copias AVAILABLE, ambas con el archivo presente y tamaño y SHA-256 iguales a sus metadatos; staging vacío.

**Secuencia completa de peticiones del turno** (observador; sólo método, ruta y estado):

```
21:50:37 POST /auth/v2/login 200 · POST /auth/clients 201 · POST /auth/v2/session/client 201 · GET /auth/v2/me 200
21:58:28 POST /auth/v2/refresh 200 · 21:58:45 GET /sync/v1/references 200
21:59:58 POST /sync/v1/push 200                          (necesidad 1)
22:24:53 POST /auth/v2/refresh 200 · 22:24:54 POST /me/backups 201 · 22:24:55 GET /me/backups 200
22:26:32 POST /auth/v2/refresh 200 · 22:26:33 GET /me/backups 200 · 22:26:45 GET /me/backups/{id}/content 200
22:29:33 POST /auth/v2/refresh 200 · 22:29:34 POST /sync/v1/push 200   (liberación)
```

**Logcat** (`logcat_scan.sh`, 2285 líneas): JWT 0, UUID completos 0, contraseñas 0, campos sensibles 0, valores opacos de 43+ caracteres 0, FATAL 0. Registro propio: 40 líneas, todo 0.

**Capturas** (sin barra de estado; se conservan en la carpeta del ensayo y no se publican):

| Captura | SHA-256 |
|---|---|
| `f10bkp_picker_album_f10.png` (álbum con las 3 imágenes sintéticas) | `bb4b16a503517698e813701f2eb79c7b7fa7be48d10de934d7ee4dbab36417b6` |
| `f10bkp_d_antes_liberar.png` | `d1a7f7491c9bfd37d97e77938756c4a8eb660d2b7ec0ef11f2bf9d6e6503212e` |
| `f10bkp_d_despues_liberar.png` | `7075f2d3b0218f056abf0bfedce7411c5c0aa9b773559e9aff78d2bb6a35e3fd` |
| `f10bkp_b_error_rollback.png` | `fc2b62d9a004e11ca37b309bb0597d6c26234bd153be3d4aa889602b9457df6b` |
| `f10bkp_c_alterada.png` | `dec827ca317775badb0630ff9e6607e81652e707f2de49ee800514561360591d` |
| `f10bkp_c_ajena.png` | `1a226e256d88019fffbaca4c49329549126c418283ad4e777db9d8d130e23291` |
| `f10bkp_c_bomba.png` | `dec827ca…` — **idéntica** a la de «alterada»: no recoge el mensaje de la bomba. La evidencia de ese mensaje es el volcado de texto de la pantalla citado arriba |

## Límites y observaciones

- **El defecto WAL no se reproduce en este teléfono** (diario de reversión). Lo que se comprobó en el dispositivo es la ruta modificada (copia `.previo` consistente, rollback completo tras un fallo después de sustituir, negativos antes de sustituir y liberación); la discriminación del defecto es de la prueba de host con WAL.
- **Un solo modelo de teléfono.** La APK probada se instaló como actualización de una de preparación con el mismo `lib/` que `4f203c7`.
- **Fallo provocado:** la variante sin tabla `sync_outbox` provoca el fallo después de sustituir; es un archivo fabricado, no un fallo espontáneo.
- **Copias `.previo` acumuladas:** quedan dos en el almacenamiento interno de la app (una por restauración). Su retención o limpieza no está definida; queda para #40 (retención), sin purga automática.
- **Cierre:** `stay_on` en 0; las 3 imágenes sintéticas se borraron de `/sdcard/Pictures/f10` y las copias temporales de las variantes de `/data/local/tmp`; las variantes siguen dentro de la app aislada. Túnel, observador y API detenidos; `agro_a_f10int_pg` detenido con su volumen; sin `down.sh`.
