# F09: integración de la compra por voz con Whisper small (candidata, 2026-11-10)

Rama `feat/f09-compra-voz-small` (worktree `_wt/F09-COMPRA`), creada desde `c097234` (cierre del bloque experimental, rama `feat/f09-diagnostico-motores`). Sin push, sin PR, sin cambios en issues ni en el documento de grado. La demostración `.f09` se actualizó el 2026-11-10 tras las comprobaciones de este informe (§7.5).

Decisión del autor (2026-11-10): Whisper small con haz de 5 para la compra por voz, con revisión explícita antes del registro. Es una elección por precisión, no una superioridad demostrada.

## 1. Versión de demostración actual y diferencias

| Qué | Valor |
|---|---|
| Instalación de demostración | `.f09` «AC F09» en el POCO (`cc14247a`), instalada el 2026-11-09 18:09:22 |
| Código | `71e55fc` (rama `feat/f09-diagnostico-motores`), compilación **de diagnóstico** (`AGRO_VOICE_DIAG=true`, `AGRO_VOICE_EVIDENCE=true`), profile, arm64 |
| APK | `apk_diag_71e55fc/agrocuentas-f09diag-71e55fc-arm64-v8a-profile.apk`, SHA-256 `8a323bd1881417e0d094cb3f073e5dfcd88c1abf30c0244071eb09ebc993d849` (coincide con lo instalado, comprobado hoy) |
| Modelos en esa APK | Vosk small-es 0.42 + Whisper base q5_1 (sin small) |

`71e55fc` es ancestro de la rama experimental. Entre ambos (`71e55fc..c097234`), clasificado:

| Tipo | Commits | Qué |
|---|---|---|
| **Correcciones necesarias** | `8afead0`, `b673523`, `a340bbb` | Intérprete de compras: «por un total de», importes pegados y con punto, «en/con/para un total de», artículo y tiempo junto al nombre, verbo no inicial y pegado, negación e intención futura |
| **Capacidad nueva usada por la compra** | `e9b3d66` (modo nativo `whole`, `WholeTurnTranscriptionAdapter`), `339a6ce` (small por defecto, haz de 5 vía `transcribeWith`, pista breve con tope de tokens, métricas de captura) | Turno entero con un solo transcriptor |
| **Instrumentos de diagnóstico** | de `e9b3d66`: interruptor «Experimento…» en «Registrar por voz» y tarjeta con selector base/small y métricas | En la integración: el interruptor **se retira**; la tarjeta queda **sólo** en la compilación de diagnóstico |
| Documentación y pruebas | `344ee9b` … `c097234` (salvo los anteriores) | Informe del experimento y pruebas |

Sin cambios de datos, esquema, servicios, sincronización ni Gradle/manifiesto entre `71e55fc` y la integración (comprobado con `git diff --name-only`): sólo voz (Dart y nativo) y `tool/voice_local`.

## 2. Cambios de la integración

- **La compra usa siempre el turno entero** con small y haz de 5: `purchaseVoiceWholeTurn = true` y `purchaseSpeechPortFactoryProvider` en `lib/presentation/voice/voice_purchase_port.dart`; en `lib/voice` queda un proveedor neutro `wholeTurnPortFactoryProvider` (la guarda de arquitectura impide nombrar compras en `lib/voice`). Sin interruptores ni compilación de diagnóstico.
- **Retirado** el interruptor del experimento de «Registrar por voz».
- **Ocultos en la compra** (también en diagnóstico) los controles que no tienen efecto con un solo transcriptor: «política B», «comparar pistas de Whisper», «ver lo que propuso cada motor» y «usar la otra propuesta». Siguen en la ruta por frases (`VoicePurchaseDraftScreen(wholeTurn: false)`, que sólo usan sus pruebas).
- La tarjeta del turno entero (modelo, decodificación, métricas sin texto) se titula «Diagnóstico: …» y sólo aparece con `AGRO_VOICE_DIAG=true`.
- **Se conservan**: revisión del borrador, edición, confirmación con un toque, cancelación del turno (descarta el audio y aborta la inferencia), protección contra resultados tardíos (turno anterior, cancelado o fuera de tiempo), estados «Grabando el turno (máximo 30 s)», «Terminando la grabación», «Transcribiendo el turno completo», y los topes (30 s de audio; 45 s de transcripción + 20 s de guarda).
- `fetch_voice_models.sh`: el valor por defecto pasa de `base` a `both` (la compra necesita small; aplicación y planificación siguen necesitando Vosk y base). README de `tool/voice_local` actualizado.
- Aplicación y planificación: **sin cambios** de motor ni de pantalla.

## 3. Configuración de voz por recorrido

| Recorrido | Puerto | Segmentación | Transcripción | Revisión | Modelos |
|---|---|---|---|---|---|
| **Compra** | `WholeTurnTranscriptionAdapter` (turno entero) | ninguna: todo el turno (≤ 30 s) al pulsar «Terminar» | Whisper **small** q5_1, haz de 5, `es`, sin traducir, temperatura 0, sin reintentos, `no_context`, pista breve (productos, unidades, monedas, expresiones de precio; ≤ 400 caracteres) | borrador revisado y confirmado por la persona | small |
| **Aplicación** | `LocalSpeechTranscriptionAdapter` | Vosk cierra cada frase | Vosk | «Revisar cada frase» (encendido por defecto): Whisper **base** q5_1, voraz, tope 5 s por frase, regla A | Vosk + base |
| **Planificación** | igual que aplicación | igual | igual | igual | Vosk + base |

## 4. Empaquetado y disponibilidad sin conexión

`fetch_voice_models.sh` (por defecto `both`): Vosk small-es 0.42 (`09b23988…511f`), Whisper base q5_1 (`422f1ae4…8898`, revisión de aplicación y planificación) y Whisper small q5_1 (`ae85e4a9…11bb`, compra), 310 079 710 B de modelos, verificados por SHA-256 al prepararlos. Ningún modelo sobra: Vosk y base los usan aplicación y planificación; small, la compra. La app los copia del APK a su almacenamiento y los verifica antes de usarlos; el dictado no usa la red. Si un APK se compilara sin small (`fetch_voice_models.sh base`), la compra por voz diría «no disponible» (`variant-missing:small`) y quedaría el formulario; las otras rutas seguirían igual. `libagro_whisper.so` (arm64-v8a y x86_64) recompilada desde whisper.cpp `52a939a`; exporta `transcribe` (voraz, frases) y `transcribeWith` (haz, turno entero).

## 5. Comprobaciones

Todas en HOST (Windows, 24 hilos, 23,7 GB de RAM; Flutter del proyecto) el 2026-11-10, salvo §6a (POCO).

### 5.1 Pruebas de voz (nuevas)

| Comprobación | Sobre | Resultado |
|---|---|---|
| `flutter analyze` | `f71be3f` | sin avisos |
| `dart format --set-exit-if-changed lib test` | `bd8e972` | sin cambios |
| Suites de voz: `test/voice`, `test/voice_draft`, `test/voice_evidence` y `test/voice_*_test.dart` (guarda de arquitectura, puerto de la compra, ocultación de controles, tarjeta de diagnóstico) | `f71be3f` | **983/983** |
| Las mismas, dentro de la suite completa | `86cbac1` | todas superadas (el único fallo de esa ejecución es de F03, §5.4) |
| Configuración que llega al canal nativo desde el puerto de la **compra** (por defecto): `mode=whole`, `variant=small`, `beamSize=5`; desde el puerto general: ruta por frases sin variante ni haz (`turno_entero_seleccion_test.dart`, petición sintética, sin texto) | `9ab203f` | 5/5 |
| Todas, dentro de la suite completa | `025c2ef` | superadas (§5.2, ejecución 5) |

Entre `86cbac1` y `025c2ef` sólo cambian pruebas, documentación y herramientas: el código de la app (`lib/`, `android/`) es el de la candidata instalada.

### 5.2 Suite completa

Comando base: `flutter test --timeout 120s` (sin `-j`: concurrencia por defecto). Cada fila es una ejecución, sin repetir hasta obtener éxito.

| # | Sobre | Comando | Duración | Resultado |
|---|---|---|---|---|
| 1 | código de `bd8e972` antes del commit | base | 11 min 5 s | 2937 superadas, **2 fallidas**, 3 omitidas: `f12_est_07` «con conexión…» (línea 230) y, en cascada, «un rechazo de política…» (`'!inTest'`), tras el tope de 10 min de la primera |
| 2 | ídem | base | detenida a mano tras > 1 h sin salida | **incompleta**: 2909 superadas, 1 fallida (`f12_est_07`, línea 230); el archivo `f12_est_07` no terminó |
| 3 | **`c097234`** (antes de la integración, worktree aparte, mismo PC y comando) | base | 3 min 56 s | 2939 superadas, **1 fallida**: `f12_est_07` «un rechazo de política…» (línea 264) |
| 4 | `86cbac1` (con la corrección de §5.3) | `flutter test -j 8 --timeout 120s`, tope externo de 30 min, sin otras pruebas en paralelo | 3 min 41 s | 2938 superadas, **1 fallida**, 3 omitidas: `test/f03_access_recovery_app_test.dart:439` (esperado `activatedSessionUnavailable`, obtenido `identityMismatch`). `f12_est_07` superada; sin bloqueos |
| 5 | **`025c2ef`** (con las correcciones de §5.3 y §5.4) | `flutter test -j 8 --timeout 120s`, tope externo de 30 min, sin otras pruebas en paralelo; `flutter analyze` sin avisos | 3 min 23 s | **2940 superadas, 0 fallidas**, 3 omitidas; sin bloqueos |

Cambio de configuración documentado: la ejecución 4 fija `-j 8` (las anteriores usaban la concurrencia por defecto) para acotar la carga; no se cambió ningún tope de prueba.

La ejecución 5 es **una** ejecución completa sin fallos; no demuestra que no queden pruebas intermitentes (queda la de §5.3, «sin copia»).

### 5.3 Fallo de estimación `f12_est_07`: causa comprobada

- **Error exacto** (ejecuciones 1 y 2): `Expected: exactly one matching candidate / Actual: _TextWidgetFinder:<Found 0 widgets with text "Copia guardada en este teléfono.": []>` en `test/f12_est_07_estimation_ui_test.dart:230`; en la 1, después, `TimeoutException after 0:10:00.000000: Test timed out after 10 minutes` y `Failed assertion: … '!inTest': is not true` en la prueba siguiente. Ejecución 3: `Found 0 widgets with key [<'estimation-blocked'>]` en la línea 264.
- **Causa.** La pantalla de estimación marca consultar, elegir campaña y descargar con una barra **lineal** (`busy` → `LinearProgressIndicator`), y el auxiliar `settle()` sólo espera indicadores **circulares** (sale a las 9 vueltas si no hay ninguno). Bajo la carga de la suite completa, la descarga (HTTP simulado + escritura real en SQLite) o el borrado tras el rechazo terminan después de esa ventana y la prueba mira antes de tiempo. Si en ese momento hay una transacción abierta, el cierre de la base (`addTearDown(database.close)`) la espera y sqflite avisa `database has been locked for 0:00:10.000000`: el archivo queda colgado (tope de 10 min en la ejecución 1; sin terminar en la 2).
- **Reproducción determinista** (copia temporal de la prueba, retirada; retraso inyectado en las respuestas simuladas de resultados y descarga):

  | Retraso | Prueba anterior (`c097234`) | Prueba corregida |
  |---|---|---|
  | 0 ms | 4/4 | 4/4 |
  | 400 ms | falla la línea 230; **bloqueo** («database has been locked»): el archivo tardó 4 min 51 s y 6 min 36 s en terminar en dos ejecuciones y no terminó en 7 min en una tercera | 4/4 |
  | 1000 ms | 2 fallidas (líneas de resultados y 264) | 4/4 |
  | 2000 ms | 2 fallidas | 4/4 |

- **No es de la integración:** falla también sobre `c097234` (ejecución 3); la prueba, sus auxiliares y la pantalla son idénticos en ambas revisiones; cada archivo de prueba corre en su propio isolate.
- **No se atribuye a la memoria del editor:** el bloqueo de la ejecución 2 coincide con el archivo `f12_est_07` sin terminar tras el mismo fallo, que es el mecanismo reproducido.
- **Corrección** (`86cbac1`, commit aparte): tras cada operación la prueba espera la condición real (que desaparezca la barra lineal) con el auxiliar existente `waitUntil`, que falla con el motivo si no se cumple. No se quitan aserciones ni se añaden esperas fijas. Pruebas relacionadas: `f12_est_07_*` y `ux_f12_estado_cuenta_y_nombres_test.dart` 52/52.
- **Lo que no discrimina:** 12 copias del archivo en paralelo (`-j 12`) pasan 48/48 tanto con la versión anterior como con la corregida: esa carga no iguala la de la suite completa.
- **Pendiente aparte, no explicado ni corregido («sin copia»):** en una de las ejecuciones con 400 ms falló una vez la prueba «sin copia: «sin copia descargada» y ninguna cifra» (línea 193: no encontró el texto «Sin copia descargada…» tras abrir la pantalla). Esa prueba no usa el servidor simulado ni la barra lineal, así que **la corrección de `86cbac1` no la explica**. 72 repeticiones instrumentadas con `-j 12` no lo reprodujeron. Posible relación con el tope silencioso de 40 vueltas de `settle()`, **sin demostrar**.
- **Riesgo restante del arnés:** si una prueba de estas falla con una escritura en curso, el cierre de la base puede volver a colgar el archivo; no se cambió `openDb`.

### 5.4 Fallo de F03 `f03_access_recovery_app_test.dart:439`: causa comprobada

- **Aserción exacta** (ejecución 4): `expect(c.read(installationAccessProvider), InstallationAccessState.activatedSessionUnavailable)` → `Actual: InstallationAccessState.identityMismatch`, tras «Cerrar sesión» de una cuenta ajena. Las tres aserciones anteriores (borrado de la sesión, `logout`, sesión local `noLocalSession`) se cumplieron.
- **Condición esperada:** que, cerrada la sesión ajena, la app reclasifique la instalación como «activada sin sesión».
- **Mecanismo:** `signOutForeignSession` marca la salida (`runtimeSessionTransitionProvider.signedOut()`, síncrono) y el *listener* de `InstallationAccessController` lanza `refresh(rereadSession: true)` **sin esperar**: relee la sesión y lee SQLite (`OwnerBindingStore.accessInputs`) antes de fijar el estado. La prueba comprobaba el estado tras un `settle` propio de **30 vueltas fijas** (~600 ms reales); con la suite cargada, el recálculo podía no haber terminado. No hay otra fuente de recálculo concurrente (sólo el inicial y el del *listener*); no se vio una carrera entre evaluaciones. Las otras dos pruebas del archivo dependen del mismo recálculo (tras recuperar el acceso).
- **Estado compartido, limpieza y orden:** cada prueba crea su base temporal y su `ProviderContainer` (con `addTearDown`); el archivo no tiene estado global mutable; tres órdenes aleatorios (`--test-randomize-ordering-seed` 11, 2026 y 90210) pasan 3/3.
- **Reproducción dirigida** (copia temporal, retirada): retraso **en tiempo real** (temporizador de la zona raíz) en la relectura de la sesión del recálculo.

  | Retraso | Antes de la corrección | Después |
  |---|---|---|
  | 0 ms | 3/3 | 3/3 |
  | 300 ms | 3/3 | 3/3 |
  | 800 ms | **0/3**: líneas de estado de las tres pruebas; la tercera con el **mismo** `Actual: identityMismatch` que la suite | 3/3 |
  | 2000 ms | 0/3 (igual) | 3/3 |

- **No se declara preexistente por no haber cambiado el archivo:** la causa es de sincronización de la prueba con un recálculo asíncrono de la app, independiente de la voz; se comprobó reproduciéndola, no por el historial.
- **Corrección** (`0a72587`, commit aparte): tras la acción, `waitUntil` espera a que el estado **deje de ser el anterior** (si no cambia, falla con el motivo), después el `settle` habitual deja terminar la navegación (sin él quedaba un temporizador de sqflite pendiente de la carga del Inicio) y se comprueba el valor exacto como antes. Sin quitar aserciones ni esperas fijas. Pruebas F03: 43/43.
- **No se cambió la app**: no se observó un defecto en el recálculo; sí queda que la pantalla quita el indicador antes de que el estado de acceso esté recalculado (breve, no comprobado como problema de uso).

### 5.5 Reutilizadas (no se repiten aquí)

- Intérprete, borrador y pantalla de P1–P4, negaciones, ambigüedad, total, cancelación y resultados tardíos: pruebas de `98d4132` (dentro de las suites de §5.1).
- Precisión con voz humana de small + haz de 5 (P1–P4 y una compra registrada con efectos, sin duplicados y con persistencia): `.f09w` con `a340bbb`, `EXPERIMENTO_TURNO_ENTERO_2026-11-09.md` §10.6 y §11. La comprobación de §6a es de integración, no de precisión.

## 6. Compilación candidata aislada

| Qué | Valor |
|---|---|
| APK | `%LOCALAPPDATA%/Temp/agro_f09/apk_f09c_86cbac1/agrocuentas-f09c-86cbac1-arm64-v8a-profile.apk` (fuera del repositorio) |
| SHA-256 | `a3421a1237661d466c1cc569b2cca82d19a0e68baa42f392063ddb992be5a99d` · 347 558 137 B |
| Código | `86cbac1` (árbol limpio; `build.gradle.kts` y manifiesto restaurados tras compilar) |
| Paquete y etiqueta | `com.comunidad.agro.agroquimicos.f09c`, «AC F09 C», versionCode 2001; firmante `dd55ce96…c3dc` (clave de depuración de este PC, esquema v2) |
| Compilación | profile, arm64-v8a; `AGRO_VOICE_EVIDENCE=true`, **sin** `AGRO_VOICE_DIAG`; `AGRO_API_BASE_URL` = túnel abierto el 2026-11-10 con autorización de Roderich (no impreso; 0 apariciones en el registro de compilación); **cerrado al terminar el bloque** (18:0x): desde entonces `.f09c` funciona sin conexión pero no llega al Central |
| Modelos | Vosk small-es 0.42; `whisper-base-q5_1` (`422f1ae4…8898`); `whisper-small-q5_1` (`ae85e4a9…11bb`, 190 085 487 B) |
| Librería | `libagro_whisper.so` arm64 (`155ad01a…`), exporta `transcribe` y `transcribeWith` |

**Corrección:** la candidata anterior (`f71be3f`, `c14fa4dd…0b0e`, 333 200 896 B) se compiló con un túnel que **ya había caducado** (2026-11-10 06:04Z, «Tunnel not found»); este informe la describía como «túnel vigente», y era incorrecto. No se instaló. Ambas APK tienen las mismas 174 entradas con los mismos tamaños; la diferencia de tamaño está fuera de las entradas (alineación y firma del ZIP).

## 6a. Candidata en el teléfono (POCO `cc14247a`, 2026-11-10, comprobación de integración)

Sin audio guardado ni transcripciones: estados de la pantalla, campos del borrador y `appops`/logcat. La voz fue **sintética** (Windows, voz Helena, frase de guion de una compra de 2 L de «herbicida demo» a 50 Bs) reproducida por el altavoz del PC.

| Comprobación | Resultado |
|---|---|
| Instalación | `.f09c` nueva (16:15:20) por `adb push` + `pm install` (sin `-r`); «Instalar» de MIUI aceptado en el teléfono. SHA-256 instalado `a3421a12…`. `.f09` (`8a323bd1…`, 2026-11-09 18:09:22) y `.f09w` (`4770e821…`, 11:34:44) sin cambios |
| Arranque y acceso | Pantalla de activación → activación en línea con `agricultor3` (correo sintético; contraseña de un solo uso tecleada por `demo.sh credential`, no mostrada) → titular «Rosa Mamani C», Compartido, PIN «Ahora no» → «Cuenta vinculada en este dispositivo». Antes hubo que volver a levantar la base de la DEMO (Docker Desktop estaba detenido; contenedor recreado sobre el mismo volumen; `demo.sh verify` correcto). La siembra DEMO falló («Esa campaña del sindicato no admite nuevos aportes») sin tocar la base: `.f09c` quedó sin catálogo |
| Modelos | «Compra por voz»: «Reconocedor: modelo de voz de la aplicación (whisper-small-q5_1)», «Funciona sin conexión…»; logcat «modelo de revisión small cargado en 257 ms»; `no_backup/voice` con `whisper-small-q5_1` (y `vosk-model-small-es-0.42` tras abrir aplicación/planificación) |
| Sin diagnóstico ni controles sin efecto | «Registrar por voz» sin interruptor del experimento; en la compra, 0 coincidencias de política B, comparar pistas, propuestas por motor, otra propuesta o «Diagnóstico» en el volcado de la interfaz |
| Configuración efectiva | Registro de la app (`app_flutter/agrocuentas.log`, líneas «voz turno:» de códigos y números, leídas con un analizador de campos clave=valor): en los 5 turnos completos `variante=small modelo=whisper-small-q5_1 haz=5`; `haz` es el valor que devuelve el motor nativo (el que decide `transcribeWith`). Inferencia 14,1–16,7 s para 10,8–29,9 s de audio |
| Grabación y estados | «Micrófono abierto», «Terminar», «Cancelar este turno (descarta el audio)», «Transcribiendo el turno completo», «Texto listo para revisar». Tope de 30 s observado (`appops` 30 073 ms cuando no se pulsó el botón) |
| Turno sólo con ruido | borrador sin cambios: «No cambió el borrador: no se reconoció nada que completar» |
| Frase sintética → borrador | Producto «Falta» («no está en el catálogo… la voz no crea nada nuevo»), Cantidad 2 L «Dictado», Precio 50 Bs «Ambiguo: elija» (por L o total), Moneda BOB «Dictado». En otro turno el producto se oyó mal y quedó también «Falta»; en un tercero el precio salió «Dictado». Tres turnos sintéticos completos: el primero en un borrador que luego se canceló; los otros dos se acumularon como dos líneas en el siguiente |
| Revisión y edición | «Por L» → «Precio por L: Confirmado» |
| Cancelación del turno durante el proceso | «Terminar» a las 16:37:09,6 (micrófono 10 944 ms) y «Cancelar este turno» a las 16:37:13,6 → «Sesión descartada»; a las 16:38:2x (> 70 s) el borrador seguía con 2 líneas: **ningún resultado tardío** |
| Cancelar el borrador | «Cancelar» sale a «Registrar por voz» sin preguntar (comportamiento probado); base de `.f09c`: compras 0, líneas 0, lotes 0, movimientos 0, pagos 0, aplicaciones 0, planes 0, consentimiento 0, integridad ok |
| Aplicación y planificación | «Reconocedor: … (vosk-model-small-es-0.42)», «Revisión de cada frase: whisper-base-q5_1», 0 controles de diagnóstico. No se dictó en ellas |
| `.f09` y `.f09w` | bases **idénticas byte a byte** antes y después (copias por `run-as`, sólo lectura) |

No medido: la espera total desde «Terminar» hasta el borrador (los volcados de pantalla tardan ~4 s); sí la inferencia, en el registro.

Incidencia de privacidad en esta comprobación: una salida de herramienta mostró una vez la línea «Lo último que se oyó» de un turno de **ruido ambiente**; no se guardó en ningún archivo. Las capturas del borrador tomadas en §6a contienen sólo lo oído de la **frase sintética**. Corregido con §8.

## 6b. Candidata con catálogo (POCO, 2026-11-10 17:50–17:54)

- **Datos sintéticos mínimos, sólo en `.f09c`:** la siembra de la DEMO no es admisible (la campaña del Central ya no admite aportes) y no se reabrió ni se eludió nada; se dio de alta por la interfaz de la app (Operaciones › Más › Administrar datos › Productos) un producto **«Herbicida DEMO», ingrediente «sintetico», litros**. Sin proveedor ni campaña. `.f09` no se tocó.
- **Audio:** la misma frase **sintética** de guion (Windows, Helena) por el altavoz del PC. Lectura de la pantalla sólo con la lista blanca de §8.
- **Borrador** (leído por la lista blanca): Producto 1 «**Herbicida DEMO**» (del catálogo) «Dictado»; Cantidad (L) **2** «Dictado»; Precio por L **50** «Dictado»; Moneda **BOB** «Dictado». Estados «Terminando la grabación» → «Texto listo para revisar».
- **Turno:** `variante=small modelo=whisper-small-q5_1 haz=5`, audio 11 560 ms, inferencia 14 244 ms.
- **Revisión y cancelación:** «Cancelar» → «Registrar por voz». **Copia de inspección: compras 0**, líneas 0, lotes 0, movimientos 0, pagos 0, aplicaciones 0, planes 0, consentimiento 0, integridad ok.


## 7. Actualizar después `.f09` conservando sus datos

### 7.1 Requisitos comprobados (2026-11-10)

| Requisito | `.f09` instalada | Candidata | ¿Se cumple? |
|---|---|---|---|
| Paquete | `com.comunidad.agro.agroquimicos.f09` | `.f09c` (habría que compilar con sufijo `.f09` y etiqueta «AC F09») | sí, al recompilar |
| Firma | `dd55ce96…c3dc` (Android Debug) | `dd55ce96…c3dc` | sí (misma clave de depuración de **este** PC; otro PC no podría actualizarla) |
| versionCode | 2001 | 2001 | sí: `pm install -r` acepta la misma versión |
| Datos | esquema 14 | esquema 14; sin `CREATE`/`ALTER` ni datos persistentes nuevos entre `71e55fc` y `86cbac1` (sólo voz y su copia de modelos en `no_backup/voice`) | sí |
| Espacio | `/data` 152 GB libres | temporal ~348 MB en `/data/local/tmp` + APK instalado ~348 MB + copia de small 190 MB (Vosk y base ya copiados) | sí, con margen |
| Origen del Central | el de su APK caducó el 2026-11-10 06:04Z: hoy `.f09` **no** puede verificar en línea ni sincronizar (sí funciona sin conexión) | se compila con el túnel vigente | al actualizar, el origen nuevo durará lo que dure ese túnel |
| Diagnóstico | `.f09` es de diagnóstico (`AGRO_VOICE_DIAG=true`) | sin diagnóstico | decidir: sin él desaparecen las vistas de diagnóstico de los tres recorridos |

### 7.2 Copia para inspección y respaldo recuperable (no son lo mismo)

| | Copia para inspección (`tool/f09_emu/respaldo_pkg.sh`) | Respaldo de la app (F08) |
|---|---|---|
| Para qué | comparar conteos e integridad antes y después de instalar | recuperar los datos |
| Qué lleva | `databases/` (base y su diario), `shared_prefs/` (ajustes; lo de `flutter_secure_storage` va cifrado con el Keystore de **esa** instalación), `app_flutter/` (registro de la app: códigos y números, 0 líneas con «» en `.f09` y `.f09c`), `files/` | lo que define la app (archivo cifrado con clave de recuperación) |
| Qué no lleva | `no_backup/` (modelos de voz copiados del APK), `cache/`, `code_cache/` | — |
| Consistencia | dos pasadas seguidas; sólo se acepta si la base y su diario son idénticos byte a byte (si no, reintenta 3 veces y aborta); informa si el diario está ACTIVO o inerte (en `.f09c`: 512 B inerte; en `.f09`: ausente); integridad sobre una copia de trabajo aparte | — |
| Restaurar | **no probado**; no serviría tras desinstalar ni en otra instalación (Keystore) | **no probado en este bloque** |

### 7.3 Instalar encima y volver: lo comprobado

Ida y vuelta **en `.f09c`** (nunca en `.f09`), con el mismo firmante y versionCode 2001, `pm install -r` y copia para inspección en cada paso:

| Paso | APK en `.f09c` | Resultado |
|---|---|---|
| Inicial | candidata `86cbac1` (`a3421a12…`) | productos 1, personas 1, vínculos 1, esquema 14, compras 0, integridad ok |
| Volver al código de la demo | `71e55fc` con sufijo `.f09c` (`f8025f04…`, misma firma) | instalada encima sin diálogo; «Cuenta vinculada en este dispositivo»; compra por voz con Vosk + revisión base; **mismo resumen**, esquema 14; la copia de small queda en `no_backup/voice` |
| Actualizar otra vez | candidata `86cbac1` | instalada encima; «Cuenta vinculada…»; compra con whisper-small; **resumen idéntico al inicial** |

`.f09` (`8a323bd1…`, 2026-11-09 18:09:22) y `.f09w` sin cambios en todo el proceso.

**Condiciones verificadas, no garantía de recuperación:**
- Misma clave de firma (`dd55ce96…c3dc`, la de depuración de **este** PC) y versionCode igual: `pm install -r` acepta en los dos sentidos. Con un versionCode mayor instalado, volver exigiría `-d` (sólo con APK depurable).
- Mismo esquema (14) en `71e55fc` y en la candidata; sin datos persistentes nuevos. Una versión futura que migre la base dejaría de admitir la vuelta sin restaurar.
- Probado con los pocos datos de `.f09c` (sin compras); `.f09` tiene más datos y es de diagnóstico: el comportamiento esperado es el mismo, **no está probado sobre `.f09`**.
- El APK anterior de la demo lleva el origen del túnel caducado: tras volver, sin verificación en línea ni sincronización.
- Desinstalar borra los datos y lo cifrado con el Keystore; no se prueba ni se recomienda.

### 7.4 Presentación frente a pruebas

- **Presentación** (la que reemplazaría a `.f09`): compilación **sin** `AGRO_VOICE_DIAG`. Comprobado en `.f09c`: sin interruptor del experimento, sin controles sin efecto en la compra, 0 controles de diagnóstico en aplicación y planificación.
- **Pruebas:** con `--dart-define=AGRO_VOICE_DIAG=true` siguen disponibles la tarjeta del turno entero (modelo y métricas sin texto) y los instrumentos de la ruta por frases; no se eliminó ninguno (pruebas de §5.1). No se compiló una APK de diagnóstico de esta rama en este bloque.

### 7.5 Pasos para actualizar `.f09`

**Ejecutados el 2026-11-10** con autorización de Roderich, desde `9d2fb1a`: `docs/evidence/F09_ACTUALIZACION_DEMO_COMPRA_VOZ_2026-11-10.md`.


1. Acordar el momento con Roderich; `.f09` en una pantalla sin borrador. **No** desinstalar.
2. Copia para inspección: `F09_SERIAL=<serie> bash tool/f09_emu/respaldo_pkg.sh com.comunidad.agro.agroquimicos.f09 <carpeta fuera del repositorio>` (debe terminar con «pasadas coincidentes» e integridad ok). Si Roderich lo quiere, además el respaldo de la app (F08).
3. Túnel: abrirlo **sólo con autorización expresa** y comprobar `health 200`.
4. Compilar desde esta rama (`fetch_voice_models.sh` por defecto `both`, `build_whisper_libs.sh`) con sufijo **`.f09`**, etiqueta «AC F09», misma clave de depuración, `AGRO_VOICE_EVIDENCE=true`, **sin** `AGRO_VOICE_DIAG`, `AGRO_API_BASE_URL` del túnel vigente sin imprimirlo; comprobar paquete, firma y versionCode con `aapt`/`apksigner`.
5. `adb push` + `pm install -r` (aceptar «Instalar» de MIUI si aparece, comprobando que es «AC F09»).
6. Verificar: SHA-256 instalado; nueva copia para inspección y `diff` de `resumen.txt` con la del paso 2; «Cuenta vinculada…»; compra con whisper-small, aplicación y planificación con Vosk + base; leer pantallas de voz sólo con `f09emu.sh voz`.
7. Si algo falla: instalar encima el APK anterior (`8a323bd1…d849`) — condiciones y límites en §7.3.
8. Cerrar el túnel al terminar.

## 8. Privacidad de las herramientas de lectura

- **Problema:** las lecturas de pantalla imprimían todos los textos y se filtraba lo oído quitando líneas entre «»; dos veces salió contenido reconocido («Lo último que se oyó» de ruido ambiente; antes, en el bloque experimental).
- **Corrección** (`025c2ef`): `f09emu.py estado` (y `f09emu.sh voz`) imprime **sólo una lista blanca**: estado y configuración del motor, etiquetas fijas de campo, fichas «<campo>: <estado>» con campo y estado de listas cerradas, valores **numéricos** de los campos, el elemento de **catálogo** elegido en un selector y botones conocidos; un elemento de varias líneas se evalúa línea a línea; todo lo demás se cuenta como omitido, y se rechaza además cualquier elemento con «», «Oído» o «Lo último que se oyó». `f09emu.py ui` cambia solo a esa lista en pantallas de voz; `f09emu.sh captura` se niega en pantallas de voz.
- **Comprobación:** `tool/f09_emu/test_f09emu_privacidad.py` con un volcado **sintético** que contiene 9 contenidos prohibidos (lo transcrito sin comillas, entre comillas, en «Oído», en una ficha con forma de campo, en un elemento de varias líneas, texto libre de un campo y un campo de contraseña): ninguno sale por `estado` ni por `ui`, y salen los 13 elementos permitidos esperados. Se verificó que los 9 están de verdad en la entrada.
- **Registro de la app:** sus líneas de voz son, por diseño, códigos y números (`_safe`); se leen con un analizador de pares clave=valor.
- Sin cambios de consentimiento; sin audio real.

## 9. Limitaciones

- Small con haz de 5 se usó con voz humana (P1–P4 y el registro final en `.f09w`, un intento por caso): no hay tasa de acierto. Falta medir el beneficio **aislado** del haz y de la pista. **Q8_0 y F16 no fueron evaluados.**
- Espera: ≈10–12 s por turno tras «Terminar» medidos en `.f09w`; en `.f09c` la inferencia registrada fue de 14,1–16,7 s (con audio de 10,8–29,9 s, voz sintética por altavoz). La ruta por frases anterior no se midió de la misma forma: no se comparan.
- El APK arm64 pesa 347 558 137 B, de los que 190 085 487 B son el modelo small.
- Suite completa: una ejecución sin fallos (`025c2ef`); queda la prueba intermitente «sin copia» (§5.3) sin explicar.
- Ida y vuelta probada sólo en `.f09c`; restaurar una copia no está probado.
- Pendiente del autor y fuera de este bloque: holdout, consentimiento v2, #17 (Pending) y #12 (sin ejecutar).
