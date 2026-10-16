# F08-BKP — E2E de recuperación en instalación limpia (MOB #36)

Procedimiento para el turno de POCO que asigna la sesión A. **Sólo A usa adb, instala o desinstala.** Reutiliza el arnés `tool/f03_res_01/` con contenedor, volumen, puertos, carpeta y paquete propios (`env.sh`):

| Pieza | Valor |
|---|---|
| Paquete aislado | `com.comunidad.agro.agroquimicos.f08bkp` («Agrocuentas F08-BKP») |
| Prohibido | La app normal `com.comunidad.agro.agroquimicos`, la demo, las copias `.f03res01`, `.f06d4` y `.f03e2b`, y sus datos. |
| PostgreSQL | `agro_c_f08e2e_pg`, volumen `agro_c_f08e2e_pgdata`, 127.0.0.1:55446 |
| API / observador | 127.0.0.1:3113 / 127.0.0.1:3116 |
| Almacenamiento privado de respaldos | `$F03_RUN_DIR/backups`, con el adaptador de disco del Backend |
| Carpeta del ensayo | `/c/Users/MSI/AppData/Local/Temp/agro_f08bkp`, fuera de cualquier worktree |
| Backend | `feat/f08-backups`, compilado con `npm ci`, `prisma generate`, `build` y `build:seed`. Antes de compilar, borrar los `*.tsbuildinfo`, porque si no `nest build` puede dejar `dist/` sin `main.js` |
| Mobile | `feat/f08-respaldo-remoto`, en un worktree desacoplado y limpio en el SHA que indique `ESTADO_C_BACKUP.md` |

**Alcance real.** Desinstalar y reinstalar el paquete aislado en el mismo POCO demuestra la recuperación en una **instalación limpia**. Lo que cambia es la base, las fotos, la identidad de instalación y el almacén seguro. No demuestra un segundo modelo de teléfono.

## 0. Entorno (una shell Git Bash **nueva**)

Use una shell que **no** haya cargado antes la configuración de F03-RES-01, D4 o E-2. `env.sh` valida todas sus variables antes de exportar ninguna; si alguna ya tiene otro valor, aborta sin cambiar nada.

> **Atención.** Para cerrar, use **siempre `tool/f08_bkp/down.sh`**, nunca `tool/f03_res_01/down.sh` directamente. En una shell sin `env.sh` cargado, el de F03 apuntaría al contenedor y al volumen **conservados** de F03-RES-01 (`agro_f03res01_pg`) y los borraría. El de F08 carga `env.sh`, comprueba que el contenedor y el volumen son `agro_c_f08e2e_pg` y `agro_c_f08e2e_pgdata` y sólo entonces delega.

`env.sh` abre la admisión de respaldos (`BACKUP_PRODUCTION_ADMISSION=enabled`) **sólo** en este entorno desechable y sintético. `up.sh` arranca la API con `NODE_ENV=production`, donde los respaldos están cerrados por defecto.

```bash
export F03_BE_DIR=<ruta>/_wt/F08-BE/Back
export F03_CLOUDFLARED=<ruta>/_wt/tools/cloudflared-2026.10.0/cloudflared-windows-amd64.exe
cd tool/f03_res_01 && source ../f08_bkp/env.sh && source ./config.sh && source ./secrets.sh
export F03_ADMIN_EMAIL F03_FARMER_D_EMAIL F03_FARMER_E2_EMAIL
mkdir -p "$BACKUP_STORAGE_DIR"
./up.sh && node ../f08_bkp/api_preflight.cjs "$(f03_api_local)"   # todo PASS; deja el almacenamiento vacío
./tunnel.sh && ./check.sh health
./build_isolated_apk.sh <worktree-mobile-desacoplado>              # anotar SHA Mobile y SHA-256 de la APK
```

El titular del ensayo es la cuenta D (`juan.perez@agro.local`). Su contraseña efímera se lee en la terminal y no se copia a la evidencia.

## 1. Instalación y datos (instalación «original»)

1. Registrar el dispositivo con `./device.sh info` y los paquetes con `./device.sh packages`. La app normal debe seguir presente y sin cambios.
2. Instalar sólo `agrocuentas-f08bkp-debug.apk`. Hay que aceptar el diálogo de MIUI.
3. Activar con D y elegir o crear el titular.
4. Crear datos sintéticos:
   - **3 compras con foto de factura**. Elegir imágenes sintéticas de la galería, enviadas antes con `adb push` a `/sdcard/Pictures/f08/`.
   - Una aplicación.
   - En Sindicato › Vínculos, vincular la campaña y dos productos.
   - Declarar la **necesidad 1** y pulsar «Sincronizar ahora»; debe quedar ACKED.
   - Con las radios apagadas (`./device.sh net off`), declarar la **necesidad 2**.
     - Si la app tiene el acceso verificado en memoria, el worker la intenta y queda **OUTCOME_UNKNOWN** (`NETWORK`, 1 intento), no PENDING. Ocurrió así en el turno 2. Sin acceso verificado queda PENDING. Las dos son válidas para el ensayo; se anota cuál fue.
     - Para que no salga al volver la red, **detener la app sin red** (`./device.sh stop`) antes de encender las radios. Así se borra el acceso en memoria. Abrir la app después, sin verificar, no envía nada (comprobarlo con `./check.sh requests`).
5. Ir a Liquidación › Copias de seguridad › **Respaldo en la nube** › «Subir respaldo» y confirmar. El mensaje debe indicar que el servidor confirmó la copia.
6. Ejecutar `../f08_bkp/server_state.sh`. Esperado: 1 AVAILABLE con «archivo íntegro» y staging vacío.
7. Ejecutar `../f08_bkp/device_snapshot.sh antes` sin tocar nada más en la app.
8. Hacer captura de la lista de copias en la nube.

## 2. Instalación limpia y recuperación

1. Desinstalar **sólo el paquete aislado**: `adb uninstall com.comunidad.agro.agroquimicos.f08bkp`.
2. Reinstalar la misma APK. Comprobar que `./device.sh packages` sigue mostrando la app normal sin cambios.
3. Marcar el inicio con `m=$(./check.sh mark)`.
4. Activar con D y crear un titular provisional; lo reemplazará la copia.
5. Ir a Respaldo en la nube › «Ver copias en el servidor» › Restaurar. La app descarga la copia, verifica el SHA-256 exterior y la valida por dentro antes de pedir confirmación. Confirmar.
6. Ejecutar `./check.sh requests "$m"`. Esperado: login, registro de cliente, `GET /api/v1/me/backups`, `GET .../content` y **ningún `POST /api/v1/sync/v1/push`**.
7. Cerrar y reabrir la app (`./device.sh stop && ./device.sh start`) y repetir `./check.sh requests "$m"`. Abrirla tampoco debe enviar nada.
8. En Sincronización debe aparecer «Pausado: restauración: 1». Hacer captura.
9. Ejecutar `../f08_bkp/device_snapshot.sh despues`.
10. Ejecutar `../f08_bkp/device_snapshot.sh compare antes despues`. Esperado `Resultado: PASS`, con IGUAL en todas las tablas y las fotos (las 3, por nombre y SHA-256), salvo las transformaciones previstas por el protocolo:
    - `app_settings`: sólo `activated_installation_ref`.
    - `sync_outbox`: ACKED se mantiene; lo enviable (PENDING u OUTCOME_UNKNOWN) pasa a RESTORE_PAUSED, con la misma operación, cantidad y causalidad. `compare` sólo admite cambios en `status` y `updated_at`.
    - `purchases`: sólo cambia la carpeta de `invoice_image_path`.

## 3. Reanudar con la verificación del titular

1. En Sincronización › «Liberar envíos restaurados», confirmar. La app verifica el acceso en línea de la cuenta del titular.
2. Ejecutar `./check.sh requests "$m"`. Esperado: un único `POST /api/v1/sync/v1/push 200`, el de la necesidad 2, con su **mismo `operationId`**. Si estaba OUTCOME_UNKNOWN, liberar la devuelve a OUTCOME_UNKNOWN (ya tuvo un intento) y se reenvía el mismo sobre.
3. Ejecutar `./check.sh sync`. La contribución de la necesidad 1 no se duplica y la de la necesidad 2 queda una sola vez.
4. En la app, la necesidad 2 debe aparecer como «Sincronizado» en la lista de Sincronización **sin salir de la pantalla**, no sólo en el resumen (corregido en F10).

## 4. Cierre

- Ejecutar `./logcat_scan.sh`. Sólo imprime conteos de JWT, UUID, contraseñas y FATAL; todos deben ser 0.
- Detener la API, el observador y el túnel. Lo que se conserva o se borra lo decide A:
  - **Conservar** (decisión de A para el turno 2): `docker stop agro_c_f08e2e_pg` y mantener el volumen y `$F03_RUN_DIR`, con el almacenamiento de respaldos y las instantáneas.
  - **Eliminar** cuando ya no hagan falta: `../f08_bkp/down.sh` (nunca el `down.sh` de F03) borra sólo `agro_c_f08e2e_pg` y su volumen. Después hay que borrar `$BACKUP_STORAGE_DIR` y `$F03_RUN_DIR/snap_*`; los `dump.json` contienen datos sintéticos de negocio.
- Borrar las imágenes sintéticas del teléfono: `MSYS_NO_PATHCONV=1 adb shell rm -r /sdcard/Pictures/f08`.
- Restaurar las radios y el ajuste `stay_on`.
- Dejar el paquete aislado detenido o desinstalarlo, a decisión de A. La app normal no se toca.
- La evidencia (SHA Backend y Mobile, SHA-256 de la APK, dispositivo, salidas de `server_state.sh`, `check.sh` y `compare`, y capturas revisadas) se registra en `docs/evidence/F08_MOBILE_RESTORE.md`. Los `dump.json` no se publican.

Duración estimada: 45–60 min.
