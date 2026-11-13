# Modo individual — continuidad

Leer `COORDINACION.md` y `ENTREGA.md`, y comprobar `git -C _wt/IND-INT log --oneline -5` antes de seguir.

- **Orquestador:** `proyectoagro-52`. Sesión externa: `proyectoagro-cb` (permisos, consentimiento y K=3; `_wt/ACC-MOB` y `_wt/ACC-INT`).
- **Base:** `507efc8`. **Último código:** `b8248fb`. Las sesiones A, B y C están cerradas e integradas.
- **Dependencia abierta:** el SHA estable de ACC-MOB y el Backend de `feat/acceso-rol-sin-k` (contrato 4). Hasta entonces no se fusiona `9da5054`. Al fusionar:
  - activar el aviso de Inicio (ver ENTREGA §Pendiente);
  - correr la suite completa;
  - compilar la APK única. Para eso hace falta un túnel nuevo autorizado por el autor y una Central con el Backend de ACC-INT: ajustar `BE`/`RICA`/`GATE_JS` en `tool/rediseno/ind_env.sh`.
- **Servicios:**
  - `emulator-5556` (`RDM_Pixel8`) **encendido**, con `.ind` (candidata) y `.rdm` (sin tocar).
  - Central `agro_ind_pg`/API 3390 **detenida**, con el volumen conservado (`ind_env.sh up` la vuelve a levantar).
  - Túnel **cerrado**.
- **Herramientas:**
  - `tool/rediseno/ind_env.sh`: Central, túnel, compilación e instalación de `.ind`.
  - `tool/rediseno/ind_ui.sh`: toques con la guarda de primer plano de `.ind`.
  - `_artefactos/modo_individual/ftest.sh`: candado de `flutter`.
- **Trampas:**
  - con el teclado abierto, las hojas suben y las coordenadas cambian; comprobar con una captura antes de teclear;
  - `ind_ui.sh tap "Activar"` toca el título, así que hay que usar coordenadas;
  - el permiso del micrófono abre el diálogo del sistema (la guarda aborta): tocar «Only this time» por coordenadas;
  - `dart format lib test tool` reformatea archivos ajenos: limitarlo a los archivos tocados.
