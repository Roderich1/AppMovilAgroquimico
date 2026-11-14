# F09: diagnóstico inicial, base de integración y plan (2026-11-08)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08 (Bolivia, UTC−4) |
| Repositorio | `Roderich1/AppMovilAgroquimico` |
| Base de integración | `feat/f09-integracion` `49108ba`, en `_wt/F09-INT` |
| Procedencia de la base | Fusión `42ee9a6`: `feat/uxj-integracion` `828b4dc` (UX del jurado) + `feat/voz-local-continua` `742f005` (PR #190, borrador). Ambas parten de `main` `279b46b`. Sin conflictos. `49108ba` sólo aplica `dart format` a 5 archivos de voz que llegaban sin formatear desde `742f005` |
| Comprobado sobre la base (HOST) | `dart format` 0 cambios; `flutter analyze` sin problemas; 23 archivos de pruebas de voz, borradores y UX: `+386: All tests passed!` |
| Dispositivos conectados hoy | Sólo el emulador Pixel_8 (x86_64, API 36). Ni el POCO ni el HONOR |

## 1. Diagnóstico

Estados: **L** implementado en local · **I** integrado en `main` · **H** probado en HOST · **E** probado en emulador · **D** probado en teléfono con dictado real · **U** evaluado con usuarios.

| Componente | Estado comprobado | Rama/commit | Evidencia | Brecha | Siguiente acción |
|---|---|---|---|---|---|
| Puerto `SpeechTranscriptionPort` y guarda de arquitectura | L, I, H | `main` (EVO-009); ampliado en `742f005` | `test/voice/voice_architecture_guard_test.dart` | — | Lo controla la coordinadora: sólo cambios aditivos |
| Adaptador Android (`systemDefault`/`onDevice`) | L, I, H, D (ensayo de octubre) | `main` | `F09_VOZ_DEVICE.md` (7a5d288) | Es el motor donde se observaron #119 y #120 | Mantenerlo como alternativa (`AGRO_VOICE_ENGINE=android`) |
| Vosk local (#165) | L, H, E (audio sintético), D parcial (POCO, voz humana, 10 intentos) | `742f005` (sin fusionar, PR #190 en borrador) | `F09_VOZ_LOCAL_2026-11-05.md`, `F09_VOZ_LOCAL_POCO_2026-11-05.md` | Una pausa pierde un tramo («Mancozeb») en el POCO; carga y modelo inválido sin probar en el teléfono; el motor se elige al compilar | Sesión A |
| Segunda pasada whisper.cpp (#166) | L, H, E con **base**, no small | `742f005` | Mismo informe de evidencia; ADR-005 provisional | #166 y los umbrales piden **small**; la revisión se descartó por cantidades en 5 de 9 frases en el POCO; sin medir en el teléfono | Sesión A, segunda etapa |
| «AC VOZ» | APK `03124a0` (x86_64 `94bc9393…` en el emulador; ARM64 recompilada `6f1fa26e…` en el POCO), Vosk 0.3.75 + `vosk-model-small-es-0.42` + whisper.cpp `52a939a2` + `ggml-base-q5_1` | `03124a0` | `tool/voice_local/README.md`, `THIRD_PARTY.md` | Congelada para la defensa; no lleva la UX del jurado | No se toca. La APK de integración usa otro paquete |
| Intérprete y borradores (compra, aplicación, planificación) | L, I, H | `main` (#14–#16) | `test/voice_draft/*`, `test/voice_*_draft_test.dart` | «un litro y medio» → 1 L y el producto «y medio de glifosato» (POCO §2.1, reproducido en HOST). La rotulación de «Ya aplicado» induce a error (POCO §2.3) | Sesión B |
| Confirmación única por el caso de uso manual | L, I, H | `voice_draft_controller.dart`, `voice_draft_gateway.dart` | Pruebas de borrador | Una compra por voz no pregunta «¿Ya pagaste al proveedor?» y queda sin pagar; el formulario lo exige desde X01 | Sesión B |
| Compatibilidad con la UX del jurado | Sin hacer | `828b4dc` frente a `lib/presentation/voice/` | — | Los borradores usan un desplegable propio (`CatalogEntryPicker`), sin búsqueda ni «Crear…»; el texto «Añadir producto a mano» difiere de «Añadir otro producto» | Sesión B |
| #119 (atasco tras denegar el micrófono) | Corrección parcial, sólo en el motor local y sólo en el EMULADOR | `fb4a50f` | Evidencia del 05-11, l. 115-116 | Denegación permanente, cancelar durante la apertura y ruta Android sin cubrir; falta la repetición en el HONOR | Sesión A |
| #120 (diálogo de descarte tras registrar) | Sin corregir | `PopScope`/`_onBack` sin cambios desde `65f7cfc` | — | Defecto abierto en las tres pantallas de borrador | Sesión B |
| Evidencia con consentimiento (#167, RF-41, DAT-21) | Nada implementado | — | El contrato sólo está en el cuerpo de #167 | Todo | Sesión C |
| Protocolo y umbrales (#12) | Umbrales sólo en un comentario de GitHub; ningún archivo versionado los contiene | issuecomment-6547952377 (2026-10-31); ADR-004 `Proposed` | — | Ver §2 | Sesión C los versiona citando su origen, sin cambiar valores |
| Evaluación con usuarios | U: nada | — | — | Hacen falta participantes, teléfono y consentimiento | Intervención del autor |

## 2. Discrepancias registradas

1. **Whisper base o small.** #166, #13 (comentario del 2026-10-31) y los umbrales de #12 hablan de **small**. ADR-005 se aceptó provisionalmente con **base**, sólo para la demostración. Impacto: un cierre de #166 con base no cumple su texto. Decisión del autor.
2. **WER.** `F09_VOZ_ENSAYO_PREPARACION.md:82` dice que no se calcula WER. ADR-005 y el PR #190 lo informan. No hay umbral de WER. Se informa como dato, nunca como criterio de aceptación.
3. **Tamaño del holdout y participantes.** `F09_VOZ_ENSAYO_FISICO_PLAN.md:78` fija 20 dictados más 2 sin habla. El comentario de #12 no lo fija y no aclara si su holdout es ese conjunto. Ninguna fuente fija el número de participantes. No se inventa: queda como pregunta al autor.
4. **Audio.** El plan del ensayo dice «no se graba audio». El comentario de #12 (D6) admite grabarlo con un consentimiento específico. El valor por defecto sigue siendo no grabar.
5. **RF-41 y DAT-21.** No aparecen en ningún documento versionado de Mobile ni del Backend. Sólo los cita #167. Hay que confirmarlos en el Cap. III antes de usarlos en `Requirement refs`.
6. **#165 depende de #119 y #120,** que siguen abiertas.
7. **Suite completa.** No termina en este HOST, tampoco en `main` (`database has been locked`). Se ejecutan archivos aislados con `timeout` y se declara.

## 3. Plan

### 3.1 Sesiones

Cada sesión trabaja en su worktree, parte de `49108ba` y no hace push.

| Sesión | Worktree / rama | Responsable de | Archivos propios | Sólo lectura |
|---|---|---|---|---|
| Coordinadora | `_wt/F09-INT` `feat/f09-integracion` | Contratos comunes, integración, APK, emulador, documentación de cierre | `docs/f09/F09_DIAGNOSTICO_*`, `lib/app.dart`, el cableado de la evidencia en las pantallas tras la entrega de B y C | — |
| A, motor local | `_wt/F09-A` `feat/f09-a-motor` | #165, #119; después #166 | `lib/voice/**`, `android/**/LocalVoiceBridge.kt` y el resto del Kotlin de voz, `tool/voice_local/**`, `test/voice/**` | `lib/voice_draft/**`, `lib/presentation/voice/**` |
| B, borradores y formularios | `_wt/F09-B` `feat/f09-b-borradores` | Recorrido de compra, aplicación y planificación; #120; compatibilidad con la UX | `lib/presentation/voice/**`, `lib/voice_draft/**`, `test/voice_draft/**`, `test/voice_*_draft_test.dart`, `test/voice_draft_flow_test.dart` | `lib/presentation/widgets/**`, `lib/presentation/screens/*_form_screen.dart`, `lib/data/agro_repository.dart` |
| C, evidencia y evaluación | `_wt/F09-C` `feat/f09-c-evidencia` | #167; preparación de #12 | `lib/voice_evidence/**` (nuevo), `lib/data/app_database.dart` (migración), la exclusión en `lib/data/backup_service.dart`, `test/voice_evidence/**`, `docs/f09/evaluacion/**` | Todo lo demás |

### 3.2 Contratos comunes, con un único propietario

- **`SpeechTranscriptionPort`:** coordinadora. A sólo puede hacer cambios aditivos; los propone y la coordinadora los acepta antes de integrar.
- **Tipos de borrador `VoiceDraft`, `DraftField` y `FieldOrigin`:** B. C los lee para derivar los campos propuestos, las correcciones y los confirmados.
- **Interfaz de evidencia `VoiceEvidenceSink`:** C. Se llama al confirmar o descartar un borrador. Sin consentimiento es un sumidero nulo. B no la llama: la conecta la coordinadora al integrar.
- **Componentes de la UX (`AdaptiveEntityPicker`, diálogos de catálogo):** B los usa sin modificarlos. Si necesita cambiarlos, lo pide a la coordinadora.

### 3.3 Orden de integración

1. **B** (compra completa), y después aplicación y planificación.
2. **A** (motor, #119).
3. **C** (evidencia).
4. **Cableado de la evidencia,** a cargo de la coordinadora.
5. **Pruebas,** después de cada paso.
6. **APK de integración** desde el SHA final: paquete aislado `.f09`, «AC F09». No toca «AC VOZ», «AC UX» ni «AC DEMO».
7. **#166 (small)** en una segunda etapa de A, sobre la integración ya estable.

### 3.4 Criterios de aceptación de cada entrega

- `dart format` y `flutter analyze` limpios.
- Pruebas propias que fallan sin el cambio y pasan con él.
- Archivos relacionados ejecutados aislados.
- Un informe con hallazgos, cambios, pruebas (con las fallidas y las intermitentes y sus ejecuciones), bloqueos, el commit de entrega y los archivos modificados.
- Ningún dato dictado en registros. Nada de audio guardado.

### 3.5 Primer hito funcional

Es el recorrido de compra de 9 pasos de la solicitud. En el emulador se ejecuta con audio sintético, o con el micrófono del PC si el autor lo activa. En el teléfono queda **NOT_RUN** hasta que haya uno conectado.

### 3.6 Fuera del alcance de las sesiones

Push, PR, merge, despliegue, cerrar issues y cambiar el Project.
