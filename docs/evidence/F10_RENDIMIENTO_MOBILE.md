# F10 — Rendimiento Mobile (RNF-06): R1–R4 y R6 en el POCO

- **Fecha real:** 2026-10-17, de 01:49Z a 04:12Z (en America/La_Paz, del 2026-10-16 a las 21:49 al 2026-10-17 a las 00:12).
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica. Es una medición técnica automatizada.
  - Sin inspección personal de Roderich ni revisión del tutor.
  - **No es una evaluación con usuarios.**
- **Protocolo:** `docs/evaluation/F10_PROTOCOLOS_EVALUACION.md` del Backend, en la rama del PR BE #122:
  - **v1.0** `72a03be`, aprobada técnicamente antes de medir;
  - v1.1 `7581af2`;
  - **v1.2 `9292425`**: composición de R6, publicada antes de la primera repetición de R6;
  - **v1.3 `9bfcad2`**: capacidad de copias, publicada antes de S2.

  Ningún umbral ni número de repeticiones cambió después de medir.
- **Issues:** BE #48 (F10-QA-04). GATE-F10 (#49) sigue **Pending**.

## Versiones y entorno

| Elemento | Valor |
|---|---|
| Mobile medido | `main` **`dff6802ac68d647d40887a4ee298c5ff171d4937`** (código = `2f4b634`) |
| APK | Copia aislada `com.comunidad.agro.agroquimicos.f10eval` («Agrocuentas F10-EVAL»), **modo profile**, SHA-256 **`93939041348bc102d5c38f158bf2b4bfb3ff588934f74ca9f91658e897022428`**. `aapt2` 37.0.0 lee `minSdkVersion` 24, `targetSdkVersion` 36, `application-debuggable` y los ABI arm64-v8a, armeabi-v7a y x86_64. Firmada con la clave local de depuración, como el tipo `profile`: **no distribuible** |
| Backend | `main` **`ed069a695eb9f8bdc318bfd16efc0071fcdced25`**, compilado, `NODE_ENV=production`, en `agro_a_f10eval_pg` (postgres:16-alpine `sha256:4e6e670b…0d50`, PostgreSQL 16.13, 10 migraciones), API 3118 |
| Configuración de capacidad | `BACKUP_MAX_ACTIVE_PER_MEMBER` 15 y, desde las 03:10:46Z, 20 (v1.3). El cambio se hizo reiniciando **sólo la API**, con el journal todo FINAL; desde entonces la API usa JWT y clave de huella nuevos |
| Red N1 | Cloudflare quick tunnel (`cloudflared` 2026.10.0) hacia el observador `tool/f03_res_01/observer.cjs`, que registra método, ruta enmascarada, estado y hora |
| Herramientas | Mobile `feat/f10-eval-mobile`, en `tool/f10_eval/`. Por serie: `24ded8e` (R1, R2-a), `4a9c396` (R3, R2-b, R4) y `2be7789` (R6) |
| Dispositivo | POCO X5 Pro 5G `22101320G`, Android 12 (API 31), MIUI `V14.0.7.0.SMSMIXM`, 1080×2400, 440 dpi, 120 Hz |
| PC | Intel Core i7-13700HX, Windows 11 Home, ~25 GB de RAM. CPU al 7 % antes de las series. B y C no midieron, compilaron ni levantaron servicios durante la ventana, avisados por mensaje |

**Condiciones del teléfono** (`series/condiciones_n0.txt`):
- AC conectado;
- `low_power` 0;
- `Thermal Status` 0;
- `stay_on` 3 durante la ventana (valor previo 0).

**Desviación sobre la batería.** El protocolo pide ≥ 50 %, pero el sistema informó todo el tiempo valores fijos: 15 %, 3 700 mV y 50,0 °C, con un contador de 4,6 Ah. No cambiaron en más de 60 minutos, ni con la pantalla apagada ni tras `dumpsys battery reset`, y `/sys/class/power_supply` no es legible. **No se pudo verificar la carga real, y la condición queda incumplida y declarada.**

**Mitigación térmica.** El servicio térmico indicó `thermal-cpufreq-4` y `thermal-cpufreq-7` (núcleos grandes) en el nivel 3 antes de las series y en el 4 antes de S3 (4 al terminar R6), con `Thermal Status 0`. Se informa como condición; puede explicar la subida progresiva de las subidas de S2.

## Dataset DS-V (protocolo §1.4)

**Siembra** (`seed_dsv_mobile.dart`, semilla 20261016):
- se hizo sobre la base extraída de la copia ya activada con la cuenta sintética D y su titular «Titular F10 EVAL» en modalidad propia (01:12Z);
- resultado:
  - 100 productos, 5 proveedores, 1 campaña, 300 compras / 600 líneas y 1 000 aplicaciones / 1 000 líneas;
  - 1 612 movimientos;
  - 0 saldos negativos, `integrity_check` ok y `sync_outbox` sin cambios (0 → 0);
  - `DSV-001`: 271 movimientos (260 líneas), frente a un máximo de 26 en los demás;
  - base de 901 120 B, devuelta al paquete con SHA-256 `da79969d…ea69`, igual en el host y en el dispositivo.

**Ensayo en el host antes de usarlo:** los mismos conteos en dos corridas.

**Fuera de la siembra, antes de las series:** los vínculos de la campaña DSV con «Campana Verano 2026» y de `DSV-001` con «Glifosato 48 SL», hechos por la interfaz, y 1 compra de ensayo de herramienta (R2). Las compras de R2-a y R2-b se acumulan en la misma base (301 → 321).

## Instrumento

- **Vídeo.** `screenrecord` a **720×1600** (el codificador falla a 1080×2400, err=-38), con los tiempos de presentación reales. `frames.py` calcula el inicio y el fin.
  - **Fin:** el primer cuadro desde el que la región del estado final queda estable.
  - **Inicio:** depende de la serie (tabla siguiente).
  - **Comprobación visual:** los cuadros de inicio y de fin de cada serie se revisaron a la vista.
- **Contacto visible.** En este MIUI `show_touches` **no aparece en la grabación**, comprobado.
  - Desde R3 se usa `pointer_location=1` y un toque inyectado de **80 ms** (`input swipe x y x y 80`). El contacto se ve en la barra superior desde el primer cuadro.
  - Los 80 ms de contacto forman parte del tiempo medido.
- **Persistencia y efectos.** `eval_counts.sh` lee por `run-as` los conteos de la base; `check.sh` lee el journal de Central.
- **Valores previos de los ajustes** (se restauran al terminar): `show_touches` 0, `pointer_location` sin definir, `font_scale` 1.0, modo avión 0.

| Serie | Inicio | Región del fin (px de pantalla) | Fin |
|---|---|---|---|
| R1 | Primer cuadro que cambia respecto de la pantalla de inicio tras `am start -W` (no incluye la latencia entre la orden y ese cuadro) | 0,700 – 1080×1350 | Dashboard con tarjetas e importes e inventario con filas, estable |
| R2-b | Contacto en «Confirmar» | 0,760 – 1080×760 (filas de la lista; excluye el aviso temporal) | La compra nueva aparece en la lista |
| R3 | Contacto en la fila de `DSV-001` | 0,300 – 1080×1750 | Saldo, distribución y lotes visibles |
| R4 | Contacto en «Sincronizar ahora» | 0,380 – 1080×900 | La fila de la intención pasa a «Sincronizado · … ACK» |
| R6, subida | Contacto en «Subir» del diálogo | 0,700 – 1080×800 | La copia nueva aparece en la lista con su SHA-256 (el aviso «Respaldo subido y confirmado» llega un instante antes, mientras se refresca la lista) |
| R6, descarga | Contacto en «Restaurar» de la copia | 0,850 – 1080×900 | Diálogo «¿Restaurar esta copia? … verificada con SHA-256» visible. Se cancela; la restauración completa es M7 |

## Resultados (n de aceptación; p90 por rango más cercano)

| Medición | Red | n | Crudos (ms, en orden) | Mediana | p90 | Máx. | Errores | Criterio | Resultado |
|---|---|---|---|---|---|---|---|---|---|
| **R1** arranque hasta el Dashboard con datos | N0 | 10 (+1 calentamiento: 1 173,4) | 1175,1 · 1140,2 · 1177,3 · 1177,5 · 1178,7 · 1185,1 · 1191,8 · 1166,7 · 1177,2 · 1182,4 | 1 177,4 | **1 185,1** | 1 191,8 | 0 | p90 ≤ 4 000 | **CUMPLE** |
| **R2-b** compra de 2 líneas (contacto visible) | N0 | 10 | 518,1 · 518,8 · 517,3 · 509,9 · 516,0 · 510,4 · 509,9 · 517,3 · 518,2 · 510,1 | 516,6 | **518,2** | 518,8 | 0 (persistencia +1 compra / +2 líneas en las 10) | p90 ≤ 1 000 | **CUMPLE** |
| **R3** saldo e historial de `DSV-001` | N0 | 10 | 474,9 · 458,2 · 473,4 · 472,8 · 467,2 · 470,8 · 470,7 · 479,8 · 472,4 · 475,1 | 472,6 | **475,1** | 479,8 | 0 | p90 ≤ 1 500 | **CUMPLE** |
| **R4** sincronización por acción explícita | N1 | 10 (+1 calentamiento: 1 910,7) | 1960,8 · 1769,8 · 1694,3 · 1894,7 · 2152,0 · 2016,2 · 1641,0 · 1967,1 · 1919,7 · 2000,2 | 1 940,2 | **2 016,2** | 2 152,0 | 0 | p90 ≤ 10 000 | **CUMPLE** |
| **R6 S1** subida (1 073 973 B) | N1 | 5 (+1 calentamiento: 2 753,0) | 3982,6 · 3478,6 · 3919,1 · 4091,8 · 3465,0 | 3 919,1 | 4 091,8 | 4 091,8 | 0 | completar y verificar dentro de los límites | **CUMPLE** |
| **R6 S1** descarga | N1 | 3 | 3130,1 · 2790,2 · 3213,8 | 3 130,1 | 3 213,8 | 3 213,8 | 0 | ídem | **CUMPLE** |
| **R6 S2** subida (10 268 992 B) | N1 | 5 (+1 calentamiento: 9 572,4, 10 268 994 B) | 10505,8 · 11112,9 · 11850,6 · 12695,6 · 12581,3 | 11 850,6 | **12 695,6** | 12 695,6 | 0 | **p90 ≤ 60 000** | **CUMPLE** |
| **R6 S2** descarga | N1 | 3 | 9068,6 · 9161,9 · 10414,9 | 9 161,9 | 10 414,9 | 10 414,9 | 0 | completar y verificar | **CUMPLE** |
| **R6 S3** subida (51 987 186 B; 2 repeticiones con ±2 B por la base) | N1 | 5 (+1 calentamiento: 52 821,8) | 55526,9 · 52694,3 · 57160,1 · 52589,5 · 53843,3 | 53 843,3 | 57 160,1 | 57 160,1 | 0 | completar y verificar dentro de los límites | **CUMPLE** |
| **R6 S3** descarga | N1 | 3 | 42596,0 · 47087,6 · 48879,2 | 47 087,6 | 48 879,2 | 48 879,2 | 0 | ídem | **CUMPLE** |

Con n = 5, el p90 por rango más cercano es el máximo; con n = 3, también. **Son descripciones muestrales.**

**Límites técnicos de R6.** Todas las subidas y descargas terminaron muy por debajo de los cortes:
- 300 s por petición en el servidor;
- 5 min por subida en el cliente;
- en la descarga, 1 min de inactividad o el tope.

El caudal de subida de S3 fue de unos 7,5 Mbit/s en la red de ensayo. **A título de cálculo, no de criterio:** a ese caudal, 100 MiB tardarían ~110 s, dentro de los 300 s.

**Bytes y conteos al cerrar** (`servidor_final.txt`):
- en el servidor, 19 copias AVAILABLE de D, 1 de E2 (C23) y 1 de S (A2); 21 objetos en disco y staging vacío;
- journal: D 12, S 1 y E2 1, todos FINAL.

**R4: estados y peticiones** (`series/r4.csv`):
- Cada intención (`40ca9b3f`, `fe9c3444`, `a47c1b96`, `14ac8a9c`, `d4e37cad`, `e7b92135`, `9913f7ff`, `cc3963da`, `5043d364`, `ee6ca961`) se declaró sin red y quedó **OUTCOME_UNKNOWN**: había acceso verificado en memoria y el primer intento falló por la red, como prevé el M6 corregido.
- Después se detuvo la app, volvió la red y, al tocar «Sincronizar ahora», salieron **exactamente 1 refresh + 1 push** (ACK en ~0,4–0,75 s desde el refresh).
- Estado final **ACKED**, con **journal 1** en Central para cada ID.
- **Sin refresh automático:** el envío sólo ocurrió tras la acción explícita.

**Red y latencia, separadas** (`series/tunel.csv`; desde el PC, 10 peticiones por vía):

| Momento | Túnel: mediana / p90 / máx. | API local: mediana / p90 / máx. | Errores |
|---|---|---|---|
| Antes de R4 | 487,9 / 681,9 / 1 302,8 ms | 2,0 / 2,8 / 16,2 ms | 0 |
| Después de R4 | 481,0 / 689,9 / 1 168,3 ms | 1,6 / 12,3 / 27,2 ms | 0 |
| Después de R6 | 462,1 / 699,9 / 1 083,6 ms | 1,5 / 2,4 / 26,5 ms | 0 |

**El tiempo del teléfono no se corrige restando la latencia del PC.** La parte de red de R4 y R6 incluye el túnel público.

**Rate limit:** ningún 429 en todas las series (observador).

## R2-a: serie conservada, con un instrumento que no cumplía la definición

- **Qué se hizo** (01:54–02:07Z): un toque **instantáneo** (`input tap`).
- **Por qué no vale como serie de aceptación:**
  - el contacto no aparece en el vídeo, así que el inicio fue la primera transición visible después de guardar, no el toque (§1.6 del protocolo);
  - el primer análisis (`series/r2.csv`, ~4,2 s) además tomó como fin la desaparición del aviso temporal «Compra multiproducto confirmada…», que no es el fin definido.
- **Reanálisis:** sobre los mismos vídeos, con la región de las filas, da 167,5–186,0 ms (mediana 180,4; `series/r2_final.csv`).
- **Comparación con R2-b:** la diferencia (~335 ms) son los 80 ms de contacto más el guardado, que en R2-a quedaban fuera.
- **Se conservan las tres tablas;** la serie de aceptación es **R2-b**, con el instrumento del protocolo. Las 20 compras (R2-a + R2-b) persistieron sin duplicados.

## Lo que esto no prueba

- **Un solo modelo de teléfono**, con MIUI, con la lectura de batería no verificable y con mitigación térmica activa. No se generaliza a la gama baja.
- **Sin carga concurrente:** un solo usuario. **No demuestra capacidad concurrente** del servidor (excluida, protocolo §1.3).
- **Servidor en un PC de desarrollo**, con túnel público. En el POCO no hay red degradada controlada.
- **R1:** el inicio en el vídeo no incluye la latencia entre `am start` y el primer cuadro de la animación. `TotalTime` (815–841 ms) se informa como auxiliar. **El primer cuadro no se declara «Dashboard utilizable».**
- **R6:** se midió con fotos sintéticas de ~0,84 MB y la base DS-V. Las descargas se cancelan en el diálogo de confirmación; la restauración completa con conteos es M7 de la compatibilidad.
- **Subidas de S2 y S3:** en S2 crecen de forma monótona (10,5 → 12,7 s) con la mitigación térmica en 3–4. No se separa ese efecto.

## Archivos

Bajo `docs/evidence/f10_eval/`:
- los CSV crudos: `r1.csv`, `r2.csv`, `r2_final.csv`, `r2b.csv`, `r3.csv`, `r4.csv`, `r6.csv` y `tunel.csv`;
- las condiciones: `condiciones_n0.txt`;
- el resultado de DS-V: `dsv_result.txt`.

**Saneado:**
- sin correos ni secretos;
- sin la URL del túnel;
- sin UUID completos: las operaciones van a 8 hex y las rutas del observador enmascaran los IDs.

**Los vídeos y cuadros no se publican.** Las grabaciones de R1 muestran la pantalla de inicio del teléfono, con iconos de aplicaciones personales. Se conservan en la carpeta del ensayo, y cada fila de CSV lleva el prefijo del SHA-256 de su vídeo.

| Archivo | SHA-256 |
|---|---|
| `condiciones_n0.txt` | `a711323baa1c7775cba379e5e479dcf5115ddc1ccb7501c477f28783f5518ade` |
| `dsv_result.txt` | `78ac433ca3039ca2a97d29801388a400f8c10b79c6baa2bae07189e3138b0a4b` |
| `r1.csv` | `2c30633e55baff485402aef6df34fc360f6d7720d12d2efdab43725459503916` |
| `r2.csv` | `30273810d6374f95ddb03f0062b8cdf7c909f8fe45350fff0d9a11f9b8dee673` |
| `r2_final.csv` | `2bb8de863d1efafc31a4502c5a742b7282946df51c84b289d0217dcf7e263f74` |
| `r2b.csv` | `4cace8ef2794703d3e710035b848435fbf9e03ce2b8c70e770b434d714034ebf` |
| `r3.csv` | `7c9d835fee61dd276af9ff9df7cc09bccbdc4960cf35a5247ad7779c26c1da5e` |
| `r4.csv` | `8d2c29b5a9fe3adfe3063c83b8167e0c13d5e38c9b1461048b34d4c57c08ca25` |
| `r6.csv` | `3178fde31370ec3e7fdfa5653d190bfdbce2689c212625f0f664116123486ac9` |
| `servidor_final.txt` | `e1215629faea7d73f4185a5b65aeb4a723e136427347112112c046e662c22ed7` |
| `tunel.csv` | `de35572e76a0b0b5ceda75fc3c130b25ab715e5bd9daf291aa043b723e3ad371` |
