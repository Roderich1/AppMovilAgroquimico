# F09: frases de ajuste, frases de aceptación y procedimiento del holdout (#12)

- **Versión:** 2026-11-08, rama `feat/f09-c-evidencia` desde `49108ba`.
- **Regla de partida (c-12 y F3):** el holdout de #12 es nuevo, **sin frases del ajuste**, y se congela con su hash **antes de la primera ejecución**. Quien ajusta las reglas del intérprete no lo escribe.
- **Este documento no contiene ninguna frase de aceptación.** La sesión que lo redacta trabaja sobre el intérprete y los borradores, así que no puede escribirlas. Escribirlas es un paso del autor o de un tercero (§3).

## 1. Frases de AJUSTE (expuestas): no pueden usarse para aceptar

Todo lo que ya está en el repositorio, en un informe o en un vídeo es **expuesto**: lo vieron quienes ajustaron el intérprete y los motores.

| Conjunto | Dónde | Huella (blob en `49108ba`) | Nota |
|---|---|---|---|
| Corpus del benchmark, particiones `ajuste` (40) y `aceptacion` (60) | `benchmark/voice_benchmark/assets/corpus.json` | SHA-256 `7a891fd1a6aa2d9c4f122cc79a9f7fac646ce52f634bc51dcc59a7c9683f6b6b` | La partición `aceptacion` es un **holdout expuesto** (F3 §3): si se ejecuta, se informa así, nunca como ciego. c-12: «no se reutiliza el holdout expuesto del benchmark» |
| Frases de referencia del audio sintético, f01–f16 | `tool/voice_local/reference_phrases.tsv` | SHA-256 `9f560d523d2a863f37fa72c4cf2e6cd65682f10edd02ffbfc96b036f28d8e090` | Escritas para la comprobación con audio sintético (`F09_VOZ_LOCAL_2026-11-05.md`) |
| Guion del ensayo en el POCO (2026-11-05) | `docs/evidence/F09_VOZ_LOCAL_POCO_2026-11-05.md`, §1 | — | «Compré un litro y medio de Glifosato por ciento ochenta bolivianos», «Pagué ciento cincuenta bolivianos y todavía debo ochenta», «Apliqué doscientos cincuenta mililitros… de Mancozeb» y las variantes de §2 |
| Frases de las pruebas de HOST | `test/voice_*_draft_test.dart`, `test/voice_draft/**`, `test/voice/**` | — | Cualquier frase que aparezca en una prueba es de ajuste por definición |
| Cualquier frase de un issue, PR o comentario | GitHub | — | Expuesta |

Si una frase candidata a aceptación coincide (o casi) con alguna de estas, se descarta. La comprobación se hace **sin mostrar las frases del holdout a quien ajusta** (§3, paso 4).

## 2. Frases de ACEPTACIÓN

**Vacío a propósito.** Las escribe el autor (Roderich) o un tercero que no haya ajustado las reglas del intérprete, fuera del repositorio, con [`tool/f09_device/conjunto_plantilla.csv`](../../../tool/f09_device/conjunto_plantilla.csv) (columnas `id, tipo, frase, operacion_esperada, campos_esperados, debe_bloquear, nota`), que ya prevé 7 de compra, 6 de planificación, 7 de aplicación y 2 sin habla (F3, línea 78; ver A4 del protocolo).

Para cada ficha, además de la frase, se fijan **antes de dictar** (c-12, D3):
- los campos esperados por tipo (producto, cantidad, unidad y parcela o persona si la ficha los exige);
- los alias admitidos de producto, parcela y persona (sólo los registrados en la ficha);
- las equivalencias de unidades y cantidades de D3, sin añadir otras después.

## 3. Procedimiento del holdout (paso del autor o del tercero)

| Paso | Quién | Qué | Dónde queda |
|---|---|---|---|
| 1 | Autor o tercero | Declara por escrito que no ajustó las reglas del intérprete (`lib/voice_draft/**`) ni los motores | Acta de la sesión |
| 2 | Autor o tercero | Escribe las fichas en una copia de `conjunto_plantilla.csv`, **fuera del repositorio** y fuera de cualquier carpeta sincronizada que lean las sesiones de desarrollo | Su equipo |
| 3 | Autor o tercero | Calcula el SHA-256 de los bytes exactos del archivo **antes de la primera toma**: `python -I -X utf8 tool/f09_device/fingerprints.py <worktree> <apk> <conjunto> fijado.json` (no lee ni imprime las frases), o, sólo para el conjunto, `certutil -hashfile <conjunto> SHA256` en Windows / `sha256sum <conjunto>` | `fijado.json` |
| 4 | Autor o tercero | Comprueba que ninguna frase coincide con las de §1. Lo hace él mismo, sin entregar las frases a quien ajusta | Acta: «sin coincidencias» o las fichas retiradas antes de fijar el hash |
| 5 | Autor | Publica **sólo el hash** y la fecha real antes de medir: un comentario en #12 o un commit con `fijado.json` (que no contiene frases) | #12 o el repositorio |
| 6 | Autor | Además, fija el SHA-256 de este protocolo en el commit de la evaluación: `git show <sha>:docs/f09/evaluacion/PROTOCOLO_Y_UMBRALES.md \| sha256sum`. `fingerprints.py` sólo fija `F09_VOZ_ENSAYO_FISICO_PLAN.md`; ampliarlo es un cambio de `tool/` que esta sesión no hace | `fijado.json` o el acta |
| 7 | Autor | Guarda el archivo **sellado**: una copia de sólo lectura fuera del repositorio (por ejemplo, un ZIP cifrado con contraseña que sólo conoce el autor, o un medio extraíble). Nadie que ajuste las reglas lo abre hasta terminar la evaluación | Custodia del autor |
| 8 | Quien mide | Antes de cada sesión, recalcula el SHA-256 y lo compara con el publicado. Si no coincide, es otro conjunto: se declara y no se mezcla | Acta de la sesión |
| 9 | Autor | Publica las frases **después** de medir, si lo decide (F3, línea 76) | Repositorio |

**Lo que el holdout no es:** si el autor del conjunto también dicta u opera, lo conocen él y el operador; se declara como «muestra no expuesta al implementador del intérprete», no como ciego (F4 §1).

**Sin persona que escriba las fichas, o sin persona que dicte, el holdout queda `NOT_MEASURED`.** No se lee con TTS ni se inyecta como texto (F3, línea 88).
