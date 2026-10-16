# F10-S18: entorno de la sesión A para #18 y la comprobación del Backend integrado

- `env.sh`: contenedor `agro_a_f10int_pg` (127.0.0.1:55447, volumen `agro_a_f10int_pgdata`), API 3116, observador 3117, carpeta `/c/Users/MSI/AppData/Local/Temp/agro_a_f10int`, respaldos abiertos **sólo** en este entorno desechable. Copias aisladas `.f10s18a`, `.f10s18b` y `.f10s18c` con `F10_COPY=a|b|c`, y `.f10bkp` con `F10_COPY=bkp` para la comprobación de restauración (no se reutiliza `.f08bkp`, para conservar los datos del turno 2). Se carga en una shell nueva antes de `tool/f03_res_01/config.sh`; si la shell ya tiene otro valor, aborta sin cambiar nada.
- `api_headers_check.cjs`: comprueba que el 415 de la guarda de respaldos lleva las cabeceras de CORS y helmet (cambio de `main.ts` entre `a45ab83` y `ba51c70`). Complementa a `tool/f08_bkp/api_preflight.cjs`, que no se modifica.
- No incluye `down.sh`: el entorno se detiene sin borrar su volumen ni su carpeta (`docker stop agro_a_f10int_pg`, y detener API, observador y túnel por sus `.pid`).
- Sin secretos: las contraseñas son de un solo uso (`credential.sh`) y los secretos de la API sólo viven en el proceso.
