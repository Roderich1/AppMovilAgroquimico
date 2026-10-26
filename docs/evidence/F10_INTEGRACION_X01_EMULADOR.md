# Integración de las correcciones X01 y comprobación de la candidata en EMULADOR

- **Fecha real:** 2026-10-26 (America/La_Paz). Sesión A, por delegación de Roderich.
- **Qué es:** el registro de los merges autorizados (Mobile #149, Backend #169), del PR separado de lenguaje de sincronización (#150) y de la comprobación técnica, en el **emulador** del equipo, de la base candidata para X02. **No es una sesión de usabilidad** ni sustituye a X02; no se atribuye a ningún participante; sus tiempos no se comparan con los del POCO. Las evidencias de teléfono físico (`F10_X01_CORRECCIONES_22E4E45.md`) y de emulador (`F10_X01_PAGO_DATOS_EMULADOR_0F1E15F.md`) se conservan separadas.

## 1. Merges (autorización literal: «con merge commit y sin borrar ramas»)

| PR | HEAD revisado | Comprobación previa | Merge | Rama |
|---|---|---|---|---|
| Mobile **#149** `fix/x01-pagador-productos-inicio` | `fba4d84` (sin cambios desde la revisión y los checks) | «Formato · análisis · tests · build» pass (11m50s); `mergeable=MERGEABLE` | **`5131e6a`** en `main`, 2026-10-26 19:25:25Z, merge commit, autor Roderich1 | conservada |
| Backend **#169** `docs/f10-piloto-x01` | `9483c97` (sin cambios) | «SonarCloud Code Analysis» pass; `mergeable=MERGEABLE` | **`383be48`** en `main`, 2026-10-26 19:25:32Z, merge commit | conservada |

**Checks de `main` tras los merges (literales):** Mobile `5131e6a`: «Flutter CI» completed · success. Backend `383be48`: «SonarCloud Code Analysis» completed · neutral (el merge sólo toca `docs/`; `backend-f02` y `web` no se ejecutan por sus filtros de ruta). El clon principal del Backend se actualizó con `git pull --ff-only` a `383be48`; el clon principal Mobile no se tocó (trabajo «demo» sin commitear).

## 2. PR separado: lenguaje de sincronización (#150, rama `fix/sync-textos-confirmacion` desde `5131e6a`)

Autorizado y limitado a los textos visibles de ACK en `sync_status_screen.dart`:

| Antes | Ahora |
|---|---|
| «Sin ACK todavía» | «Todavía sin confirmación» |
| «Último ACK: fecha» | «Última confirmación: fecha» |
| «ACK fecha» (fila) | «Confirmado: fecha» |

El estado real no cambia (la chip sigue leyendo `lastAcceptedAt` = `MAX(acked_at)`; la fila, `ackedAt`); nada en el worker, los estados, la cola ni los códigos. «Todavía sin confirmación» no afirma que Central no recibiera el envío.

Commits: `9e06f56` (textos y prueba) y `8ddbbe9` (revisión cruzada). **Revisión cruzada independiente** del diff: 5 hallazgos, atendidos así:

| # | Gravedad | Hallazgo | Respuesta |
|---|---|---|---|
| 1 | Media | La prueba no demostraba que la chip cupiera: el `Chip` desvanece sin error lo que no cabe en una línea, y con la fuente de pruebas la medida no vale | Prueba con la **Roboto real** (`test/fonts`) a 360 y 392 px y escala 1,0 y 1,3, midiendo el `RenderParagraph`. Con ella se vio que «Última confirmación: dd/mm/aaaa» a 1,3 en 360 px **no cabía** (275 px de texto en 239 px de caja): la etiqueta de la chip admite ahora **dos líneas**, nunca truncada ni con palabras partidas. Es el único cambio no literal del PR y existe para que el texto prescrito quepa |
| 2 | Baja | `MediaQuery(data: MediaQueryData(...))` sustituía toda la `MediaQueryData` | Patrón del repo: `MediaQuery.of(context).copyWith(textScaler:)` en `builder` |
| 3 | Baja (fuera del alcance) | El código interno `INVALID_ACK` puede verse en la fila como `last_code` (igual que `AUTH_REQUIRED` u `HTTP_500`) | Es un código, no un texto, y la autorización excluye los códigos: se declara como límite conocido |
| 4 | Baja | `expectNoAck` sólo mira `Text.data` | Anotado; la pantalla no usa `Text.rich` ni tooltips |
| 5 | Informativa | Comentario de la clase decía «último ACK» | Corregido |

Pruebas: `test/f10_sync_textos_confirmacion_test.dart` (8 casos: sin/con confirmación × 360/392 px × 1,0/1,3) y `sync_screens_test` adaptada; `flutter analyze` y `dart format` limpios.

**Operaciones en GitHub de este bloque:** 1 merge #149, 2 merge #169, 3 push de la rama, 4 creación de #150, 5 push de `8ddbbe9`. El merge de #150 sería la sexta: **queda pendiente del dry-run y de la aprobación de Roderich** (regla de más de cinco cambios).

## 3. Base candidata para X02

| Pieza | Valor |
|---|---|
| Mobile `main` | **`5131e6a`** (integra #149). Con #150 integrado, el `main` resultante será la base definitiva; su contenido es exactamente `8ddbbe9` (= `5131e6a` + los dos commits de #150), que es lo que se compiló y comprobó aquí |
| Backend/Web `main` | **`383be48`** (código `4bcb1ea`; #169 sólo documentación) |
| Generadores DS-UX | `tool/f10_ux/` (sin cambios desde `1d77c14`); `Back/scripts/f10-dsux-central-seed.cjs` de `383be48` (= `1cc439b`) |
| Instrumentos | protocolo v1.5 `b4d0f4c`; TAR-2, SEQ-ES-1, SUS-ES-1; **GUION-3 candidato** (se fija después del piloto) |

## 4. Comprobación en el EMULADOR (sólo integración y textos nuevos)

Por indicación de Roderich no se repiten los 28 recorridos de `F10_X01_PAGO_DATOS_EMULADOR_0F1E15F.md` (los merges no cambian el código ya probado: #149 se integró tal cual y #150 sólo toca tres textos y una etiqueta de chip); se comprueban la integración y los textos nuevos.

| Elemento | Valor |
|---|---|
| Emulador | AVD `Pixel_8`: Android 16 (API 36), x86_64, 1080 × 2400, 420 dpi; `hw.keyboard=no` durante la comprobación y restaurado; zona horaria America/La_Paz. **No es el POCO**; sin comparación de tiempos |
| Paquete | `com.comunidad.agro.agroquimicos.intemu` («Agrocuentas INT emu»), profile x86_64, aislado (la app normal y la `.f10eval` del emulador no se tocaron). **Desinstalado al terminar**; APK conservada en `%TEMP%\agro_a_intemu\` |
| APK | Worktree limpio en **`8ddbbe9`** (= `main` `5131e6a` + los dos commits de #150), túnel del día. SHA-256 **`ea705d227d47a8dbda20f1cb3a03922f94577ddc9d29bf756c0ef0603cb4f1f4`**, igual al `base.apk` instalado |
| Central | Contenedor nuevo `agro_a_intemu_pg` (postgres:16-alpine, 127.0.0.1:55481), 13 migraciones; API del `dist` de Backend `4bcb1ea` (= código de `main` `383be48`) en el 3166, `NODE_ENV=development`, `COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic`, `COLLECTIVE_SEALING=disabled`, `SYNC_V1_PRODUCTION_ADMISSION=enabled`; observador en el 3167; quick tunnel `cloudflared` 2026.10.0. Al terminar: API, túnel y observador parados; contenedor conservado |
| Siembra Central | `f10-dsux-central-seed.cjs`, destino `movil`, etiqueta `INTEMU`, S = 2026-10-26, cuentas T01 y T02 (tenant `f10ux-movil-intemu`); referencias `same_tenant_as_accounts: true` |
| Siembra Mobile | `seed_dsux_mobile.dart` de `8ddbbe9`, S = 2026-10-26, **T02 en COMPARTIDA**: base `0b561bd8…` igual en PC y emulador; oráculo inicial 5 000 = 5 000 y 1 000 = 1 000, `consistent: true` |
| Contraseña | De un solo uso, asignada por `stdin` (bcrypt) y tecleada por el arnés; no se mostró ni escribió |

### 4.1 Recorridos

Capturas en `%TEMP%\agro_a_intemu\capturas\` (SHA-256, 16 hex).

| # | Recorrido | Resultado | Captura |
|---|---|---|---|
| I1 | Inicio tras la siembra | **PASS.** Cuatro accesos; «Campaña activa: Verano Demo»; «Compras 405,00 Bs» | `9f74dee2b621a842` |
| I2 | «Enviar al sindicato» con la cola vacía | **PASS.** «Sincronización», «Sincronizar ahora», chip **«Todavía sin confirmación»**, «Todavía no hay nada que enviar al sindicato.»; ninguna petición al tocar el acceso | `da4fdf4b0b6004cd` |
| I3 | Necesidades declaradas › Declarar: Glifosato Demo 3 L → «Declarar» | **PASS.** «Necesidad declarada.»; en Sincronización: «Pendiente: 1», «Todavía sin confirmación», fila «Necesidad declarada · Publicar · 3 L · Pendiente · creada 26/10/2026» | — |
| I4 | «Sincronizar ahora» (push real a la Central desechable) | **PASS.** Observador: `POST /auth/v2/refresh 200`, `POST /sync/v1/push 200`. Pantalla: «Sincronizado: 1», chip **«Última confirmación: 26/10/2026»**, fila «… Sincronizado · creada 26/10/2026 · **Confirmado: 26/10/2026**». Ningún texto con «ACK» | `218cdd675dceaf13` |
| I5 | La misma pantalla al **130 %** | **PASS.** Las dos chips y la fila enteras, sin truncar; la fila pasa a dos líneas en un espacio | `3cec620303ab661a` |
| I6 | Registrar compra: Glifosato Demo 2 L a 45, Titular 2 L → «Sí, pagué todo» sin tocar más → Confirmar | **PASS.** «Compras 495,00 Bs», «Pagado proveedores 90,00 Bs»; base: compra 3 (9 000), pago 1 (pagador 1 = Titular, `UNSPECIFIED`, fecha = la de la compra) | `db26a236bc66557c` |
| I7 | Registrar aplicación: Titular, Norte, Glifosato Demo 1 L → Confirmar | **PASS.** «Aplicación guardada.»; base: 1 aplicación, 1 línea de 1 000 mL | `2c7249e0e3a56461` |
| I8 | `adb logcat` desde el arranque, al 100 % y al 130 % | **0** `overflowed by` / `RenderFlex` | — |

**Oráculo final T02** (`oracle_dsux_mobile.dart`, sólo lectura), base `18599a7a…`: Glifosato Demo 5 000 + 2 000 − 1 000 = 6 000 = 6 000; Bellator 1 000; `consistent: true`; la necesidad de 3 L queda `ACKED` en la cola. Lo mismo que dieron el POCO y el emulador para el mismo recorrido.

## 5. Límites

- Comprobación por un solo operador en un emulador con datos sintéticos: **no mide usabilidad**, no sustituye a X02, y no reemplaza lo que sólo un teléfono muestra (teclado del fabricante, cámara, red móvil). El día de X02 se compila la `.f10ux` desde el SHA integrado definitivo, con el túnel del día, y se repite el preflight corto DS-UX.
- Sólo se comprobó la modalidad compartida en esta pasada; la propia quedó comprobada sobre `0f1e15f` (misma base de código que `5131e6a` para esas pantallas).
- Si X02 se hiciera con el emulador, antes hay que adaptar y aprobar el protocolo (equipo e interacción distintos del POCO) y registrarlo por separado; ver `_briefs/PILOTO_X02_PREP_2026-10-26.md` §4 bis.
- Código interno `INVALID_ACK` en `last_code` (revisión, hallazgo 3): no es un texto de interfaz y queda fuera de esta autorización.
