# F09: integración de la compra por voz con Whisper small (candidata, 2026-11-10)

Rama `feat/f09-compra-voz-small` (worktree `_wt/F09-COMPRA`), creada desde `c097234` (cierre del bloque experimental, rama `feat/f09-diagnostico-motores`). Sin push, sin PR, sin cambios en issues ni en el documento de grado. **La instalación de demostración no se reemplaza** en este paso.

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

### Nuevas (sobre esta rama)

Código y pruebas en `bd8e972`; la candidata se compiló desde `f71be3f` (sólo añade documentación). Todo el 2026-11-10, en HOST (Windows, Flutter del proyecto):

| Comprobación | Sobre | Resultado |
|---|---|---|
| `flutter analyze` | `f71be3f` | sin avisos |
| `dart format --set-exit-if-changed lib test` | `bd8e972` | sin cambios |
| Suites de voz: `test/voice`, `test/voice_draft`, `test/voice_evidence` y `test/voice_*_test.dart` (incluye la guarda de arquitectura, la selección del puerto de la compra, la ocultación de controles y la tarjeta de diagnóstico) | `f71be3f` | **983/983** |
| Suite completa, 1.ª ejecución (`--timeout 120s`) | código de `bd8e972` antes del commit | 2937 superadas, **2 fallidas**, 3 omitidas: ambas en `test/f12_est_07_estimation_ui_test.dart` (una aserción y un tope de tiempo) |
| Suite completa, 2.ª ejecución | ídem | **incompleta**: 2909 superadas y 1 fallida (la misma prueba de `f12_est_07`, otra aserción) cuando dejó de avanzar; detenida tras más de una hora sin salida y sin uso de CPU, con el servidor Dart del editor en ≈7,4 GB. No hay resultado de suite completa terminada sin fallos |
| `test/f12_est_07_estimation_ui_test.dart` aislada | `bd8e972` (×2) y `f71be3f` | 4/4 cada vez |
| Inspección del APK candidato | `f71be3f` | ver §6 |

Lectura del fallo de `f12_est_07`: aparece sólo bajo la carga de la suite completa, pasa aislada y ni la prueba ni la pantalla de estimación cambian en esta rama (`git diff c097234` vacío para ellas). No se demostró si también falla con la suite completa sobre `c097234`; queda como fallo intermitente **no explicado**, no como superado.

### Reutilizadas (no se repiten aquí)

- Intérprete, borrador y pantalla de P1–P4, negaciones, ambigüedad, total, cancelación y resultados tardíos: pruebas de `98d4132` (incluidas en la suite de arriba, sin cambios salvo el puerto simulado de la compra).
- Comportamiento en el teléfono con small + haz de 5 (P1–P4 y una compra registrada con efectos, sin duplicados y con persistencia): `.f09w` con `a340bbb`, `EXPERIMENTO_TURNO_ENTERO_2026-11-09.md` §10.6 y §11. **No se repitió con esta compilación candidata**: lo que cambia respecto de `a340bbb` es el cableado (sin interruptor) y lo visible, no el motor ni el intérprete.

## 6. Compilación candidata aislada

| Qué | Valor |
|---|---|
| APK | `%LOCALAPPDATA%\Tempgro_f09pk_f09c_f71be3fgrocuentas-f09c-f71be3f-arm64-v8a-profile.apk` (fuera del repositorio) |
| SHA-256 | `c14fa4dddbb4d29bfab3660b7a2b251d9c6d21ae648be346d1881a53c6840b0e` · 333 200 896 B |
| Paquete y etiqueta | `com.comunidad.agro.agroquimicos.f09c`, «AC F09 C» (aislado: no toca `.f09` ni `.f09w`) |
| Compilación | profile, arm64-v8a, clave de depuración; `AGRO_VOICE_EVIDENCE=true`, **sin** `AGRO_VOICE_DIAG`; `AGRO_API_BASE_URL` del túnel vigente (no impreso; no aparece en el registro de compilación) |
| Modelos dentro | Vosk small-es 0.42; `whisper-base-q5_1` (SHA-256 `422f1ae4…8898`); `whisper-small-q5_1` (`ae85e4a9…11bb`, 190 085 487 B); manifiesto: revisión `base`, alternativa `small` |
| Librería | `libagro_whisper.so` (arm64, SHA-256 `155ad01a…`), exporta `transcribe` y `transcribeWith` |
| `build.gradle.kts` y manifiesto | restaurados tras compilar (árbol limpio) |
| Instalada | **no**. Sin datos copiados de `.f09w` |

No se probó en el teléfono: el comportamiento con voz es el de `a340bbb` (§5, reutilizadas).

## 7. Actualizar después la demostración conservando sus datos

1. Comprobar con Roderich el momento; **no** desinstalar `.f09` (borraría sus datos).
2. Exportar una copia de seguridad desde la app (Cuentas → menú de la carpeta → exportar) y anotar conteos de compras, aplicaciones, planes y existencias.
3. Desde esta rama (o su sucesora), con `fetch_voice_models.sh` (por defecto `both`) y `build_whisper_libs.sh`, compilar con el sufijo **`.f09`** y la etiqueta «AC F09» (el mismo paquete), la misma clave de firma de depuración y las mismas opciones que la demo actual **salvo** `AGRO_VOICE_DIAG` (la integración no lo necesita; si se quiere conservar la vista de diagnóstico, añadirlo). `AGRO_API_BASE_URL` del túnel vigente, sin imprimirlo.
4. Instalar **encima** (`adb push` + `pm install -r`, aceptando «Instalar» de MIUI): conserva base, ajustes, vínculo y consentimiento. No copiar datos de `.f09w`.
5. Verificar: SHA-256 instalado; mismos conteos que en el paso 2; «Compra por voz» muestra «Reconocedor: … (whisper-small-q5_1)» y estados de turno entero; aplicación y planificación siguen con Vosk + base. La primera compra por voz copia small (190 MB) al almacenamiento de la app.
6. Volver atrás si hiciera falta: instalar encima la APK anterior (`8a323bd1…d849`, mismo paquete y firma) — sin cambios de esquema, los datos se conservan.

## 7a. Limitaciones

- Small con haz de 5 se usó con voz humana (P1–P4 y el registro final en `.f09w`, un intento por caso): no hay tasa de acierto. Falta medir el beneficio **aislado** del haz y de la pista. **Q8_0 y F16 no fueron evaluados.**
- La espera de la compra por voz es de ≈10–12 s por turno en el POCO tras pulsar «Terminar» (sin texto provisional mientras se habla). La ruta por frases anterior no se midió de la misma forma: no se comparan.
- El APK arm64 pesa 333 200 896 B (≈318 MiB), de los que 190 085 487 B (≈181 MiB) son el modelo small.
- Pendiente del autor y fuera de este bloque: holdout, consentimiento v2, #17 (Pending) y #12 (sin ejecutar).
