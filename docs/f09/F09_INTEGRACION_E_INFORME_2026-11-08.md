# F09: integración de las sesiones, matriz e informe (2026-11-08)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08 (Bolivia, UTC−4) |
| Rama | `feat/f09-integracion`, en `_wt/F09-INT`. Sin push, sin PR |
| Commit verificado | `db674e8` (este documento va en el commit siguiente) |
| Procedencia | **HOST** (Windows 11, Flutter 3.47.2 stable). **Nada de este documento es EMULADOR ni DEVICE**, y no hay evaluación con usuarios |
| Plan y diagnóstico | `F09_DIAGNOSTICO_Y_PLAN_2026-11-08.md` |

## 1. Integración

Las entregas se fusionaron una a una en la rama de integración, y después de cada una se ejecutaron el formato, el análisis y las pruebas relacionadas.

| Orden | Commit | Entrega | Pruebas después de integrar |
|---|---|---|---|
| — | `49108ba` | Base: UX del jurado `828b4dc` + voz local `742f005`, más `dart format` | 23 archivos: `+386` |
| 1 | `8d20788` | Sesión C `24e5897`: evidencia con consentimiento y preparación de #12 | Evidencia, esquema, respaldo y restauración: `+284` |
| 2 | `0873932` | Sesión A `757bb8a`: #119, turnos numerados, modelo inválido y plazo de apertura | Voz, borradores y evidencia: `+417` |
| 3 | `178d417` | Sesión B `5a35d24`: borradores con la UX, pago, #120, «y medio» y pausas | `+500 -2` (ver §1.1) |
| 4 | `b47880a` | Ajustes de prueba de la integración | `+502`; formularios manuales y pago: `+76` |
| 5 | `fc6478d` | Evidencia conectada a los tres borradores y pantalla de consentimiento | `+514` |
| 6 | `db674e8` | Sesión A, segunda etapa `c2d4081`: Whisper small seleccionable (#166) | `+546` |

El orden previsto en el plan (B, A, C) se cambió a C, A, B porque C terminó primero y sus archivos no se cruzan con los de A ni B.

**Comandos** (en `db674e8`):
- `dart format --set-exit-if-changed lib test`: 0 cambios.
- `flutter analyze`: sin problemas.
- `timeout 1500 flutter test test/voice test/voice_draft test/voice_evidence test/voice_application_draft_test.dart test/voice_draft_flow_test.dart test/voice_plan_application_draft_test.dart test/voice_planning_draft_test.dart test/voice_purchase_draft_test.dart test/ux_altas_en_contexto_test.dart test/uxj_b_altas_vencimiento_test.dart test/uxj_a_navegacion_test.dart`: `01:20 +546: All tests passed!`.
- La suite completa no se ejecutó: no termina en este HOST, tampoco en `main` (diagnóstico §2.7).

### 1.1 Fallos encontrados al integrar

- **`voice_draft_no_side_effects_test` (3 compras):** la sesión B añadió la respuesta obligatoria a «¿Ya pagaste al proveedor?» y la prueba de A no la respondía. Corregido en `b47880a`.
- **`voice_purchase_complete_test`: «Crear proveedor» y «Crear producto» fallaron en la ejecución combinada (`+500 -2`).** La fila ya estaba en la base, pero la pantalla todavía no se había reconstruido.
  - Aislado: `+7` dos veces.
  - Corregido en `b47880a`: la prueba espera con un tope (50 × 20 ms) y mantiene la comprobación. Después: `+502` y `+514`.
  - Es una intermitencia de la prueba por carga. Se deja registrada, no oculta.
- **`voice_evidence_exclusion_test` (guarda de Sync):** prohibía nombrar `voice_evidence` en todo `lib`, y el cableado lo importa. Se precisó en dos reglas:
  - fuera del esquema, el respaldo y el propio módulo, nadie nombra las tablas;
  - Sync y los servicios no nombran la evidencia.

  Un archivo sonda temporal en `lib/data/sync` fue detectado por las dos reglas y después se borró.
- **Prueba nueva de cableado:** al quitar la entrega fallan las 2 pruebas positivas y las 2 negativas siguen pasando.

## 2. APK

| Archivo (local, sin versionar) | Commit | Configuración | SHA-256 | Estado |
|---|---|---|---|---|
| `%TEMP%\agro_f09\apk\agrocuentas-f09-fc6478d-x86_64-profile.apk` | `fc6478d` | Paquete `.f09` («AC F09»), profile. Vosk small-es 0.42 + whisper **base** q5_1. `AGRO_VOICE_EVIDENCE=true`, `AGRO_APP_COMMIT=fc6478d`. **Sin origen del Central** | `46d5174ebd640f05efe0f03634c19e2c101c8cbb9b4f96fd23e198f4899eb427` (149 959 290 B) | Sólo compilada. **No instalada:** sin origen HTTPS no se puede activar |
| Escritorio de la sesión A2: `agrocuentas-voz-b24dca0-x86_64-review-small-profile.apk` | `b24dca0` | whisper **small** | `5cfcd25b…5a5d` (277 655 352 B) | Sólo compilada, para medir el tamaño |

Hace falta una APK desde `db674e8` (o el commit final) con el origen del túnel de la DEMO para activarla. El túnel lo abre el autor.

## 3. Matriz

Leyenda: **PASS-HOST** = pruebas automatizadas en HOST con adaptador falso o eventos nativos simulados, **no** reconocimiento real.

| Requisito o criterio | Implementación | Prueba | Resultado | Evidencia | Pendiente |
|---|---|---|---|---|---|
| Cero escrituras antes de confirmar (#17, #165) | `VoiceDraftController`, `VoiceDraftGateway` | `voice_draft_no_side_effects_test`, `voice_purchase_complete_test` | PASS-HOST | §1 | EMULADOR y DEVICE |
| Registro único con el caso de uso del formulario | `confirm()` una sola vez; `confirmPurchase`, `addPlanMulti`, `confirmApplication` | `voice_draft_exit_test` (doble toque), `voice_purchase_complete_test` | PASS-HOST | §1 | EMULADOR y DEVICE |
| Cancelar no escribe | `discard()`, `VoiceDraftExit` | `voice_draft_exit_test`, `voice_evidence_wiring_test` | PASS-HOST | §1 | EMULADOR y DEVICE |
| Edición manual frente a un resultado tardío | `applyVoice` conserva los campos manuales; turnos numerados (A) | `review_draft_end_to_end_test`, pruebas del controlador | PASS-HOST | §1 | EMULADOR y DEVICE |
| Aislamiento entre capturas | `gen` en Kotlin y Dart, `native_event_hub` (A) | Pruebas de los adaptadores y de la sesión | PASS-HOST; el Kotlin sólo está compilado | Informe de A | Prueba JVM; EMULADOR y DEVICE |
| #119, micrófono denegado | A: dos rutas, plazo de apertura, «Cancelar» | `voice_session_permission_119_test`, pruebas de los adaptadores | PASS-HOST | §1 | **Repetición en el HONOR** (criterio de #119) |
| #120, diálogo de descarte tras registrar | B: `VoiceDraftExit` | `voice_draft_exit_test` (3 pantallas) | PASS-HOST | §1 | Repetición física |
| Vía manual con micrófono denegado o motor no disponible | Formularios sin cambios; «Usar el formulario manual» | `voice_purchase_complete_test`, `voice_wiring_test` | PASS-HOST | §1 | DEVICE |
| Modelo ausente o inválido | A: `LocalVoiceModels`, «no disponible» | `local_voice_model_and_session_test` | PASS-HOST | §1 | DEVICE |
| Compatibilidad con la UX (selectores, «Crear…», pago, lote vencido) | B | `voice_purchase_complete_test`, `voice_application_plan_ux_test` | PASS-HOST | §1 | EMULADOR |
| No inventar ni crear entidades por voz | Intérpretes; las altas sólo las pide la persona | Pruebas de B («la voz no crea nada») | PASS-HOST | §1 | — |
| «Un litro y medio» y frase partida por una pausa (POCO §2.1 y §2.2) | B: intérpretes | `voice_medio_test`, `voice_pausa_test` (frases de **ajuste**) | PASS-HOST | §1 | Volver a dictarlo con voz real |
| Segunda pasada condicional, una transcripción por frase, tope por frase (#166) | A2: `ReviewCapabilityPolicy`, evento `phrase`, `AGRO_VOICE_REVIEW_TIMEOUT_MS` (5 000) | `review_capability_test`, `local_review_second_pass_test` | PASS-HOST | §1 | EMULADOR y DEVICE |
| Whisper small: coste y exactitud | Seleccionable al compilar; por defecto **base** | `host_compare.py` (54 frases sintéticas de ajuste) | **Medido sólo en HOST**: small 42/45 productos frente a 38/45 con base; inferencia p50 ≈2,7 s frente a ≈0,73 s; RTF p95 1,13–1,16 | `docs/f09/whisper/WHISPER_SMALL_HOST_2026-11-08.md` | **NOT_MEASURED en el teléfono**; decisión del autor |
| Evidencia sólo con consentimiento (#167; RF-41 y DAT-21 según #167) | C + cableado; `AGRO_VOICE_EVIDENCE` | `voice_evidence_store_test`, `voice_evidence_wiring_test` | PASS-HOST | §1 | EMULADOR; texto de consentimiento aprobado por el autor; RF-41 y DAT-21 en el Cap. III |
| Evidencia fuera del respaldo F08 y de Sync v1 | C: `discardVoiceEvidence` al exportar y al restaurar | `voice_evidence_exclusion_test` | PASS-HOST | §1 | Limitación: la copia `.previo` de la restauración sí la contiene durante 7 días |
| Sin audio | Sin columna binaria; la API no recibe audio | Esquema y pruebas de C | PASS-HOST (estructural) | — | — |
| Transcripción sin conexión en un teléfono en modo avión (#165) | Motor local | — | **NOT_RUN sobre la integración.** Antecedente: POCO con `03124a0` (diez intentos, voz humana; no es #12) | `F09_VOZ_LOCAL_POCO_2026-11-05.md` | DEVICE, POCO y HONOR |
| Primer hito funcional (9 pasos, compra) | Todo lo anterior | — | **NOT_RUN** en el emulador por falta del origen del túnel | — | Túnel, APK, recorrido |
| Evaluación #12 (holdout, POCO y HONOR, umbrales) | Protocolo y plantilla versionados (C) | `f09_metricas.py`, sólo con datos sintéticos | **NOT_RUN** | `docs/f09/evaluacion/` | Holdout escrito por el autor o un tercero; participantes; teléfonos |
| Avisos de licencia de Vosk, JNA, whisper.cpp y ggml en la APK | — | — | **Falta** | `tool/voice_local/THIRD_PARTY.md` | Incluir los textos |

## 4. Informe

**Qué funciona, verificado en HOST:**
- El recorrido dictado → borrador → revisión → confirmación → registro único, en compra, aplicación y planificación, con la UX del jurado.
- Las correcciones de #119 y #120.
- La segunda pasada condicional, con tope por frase.
- La evidencia con consentimiento, excluida del respaldo y de Sync.

**Qué se midió:**
- Sólo en HOST: pruebas automatizadas, y el coste y la exactitud de base frente a small con audio sintético.
- En un teléfono, nada sobre esta integración.

**Qué falta:**
- El recorrido en el emulador (primer hito).
- Todo lo de DEVICE: POCO, HONOR, modo avión, #119 en el HONOR.
- La evaluación #12 y la evaluación con usuarios.
- Los avisos de licencia.

**Qué requiere intervención del autor:**
1. Abrir el túnel de la DEMO para activar «AC F09».
2. Elegir Whisper **base o small**.
3. Escribir el holdout de #12, o designar quién lo escribe, y fijar participantes y tamaño.
4. Aprobar el texto de consentimiento.
5. Confirmar RF-41 y DAT-21 en el Cap. III.
6. Responder las preguntas A1–A14 de `docs/f09/evaluacion/PROTOCOLO_Y_UMBRALES.md`.
7. Conectar el POCO y el HONOR.
8. Decidir el push, los PR y la fusión.

**¿Basta la evidencia para proponer el cierre de #17?** **No.** #17 exige evidencia con procedencia para cada ítem, o su exclusión declarada, y la lectura de #12 contra sus umbrales. Hoy todo es HOST, #12 no se ha ejecutado y #119 exige además la repetición en el HONOR. El gate sigue `Pending`, y su estado no lo cambia Claude.

## 5. Capítulo

Ningún texto del capítulo debe dar por validada la voz. Con lo que hay hoy sólo se puede afirmar:
- que existe la implementación;
- las pruebas automatizadas en HOST;
- las mediciones en HOST con audio sintético, como tales.

Lo de teléfono y usuarios queda como trabajo pendiente o limitación hasta que haya evidencia DEVICE y resultados de #12.
