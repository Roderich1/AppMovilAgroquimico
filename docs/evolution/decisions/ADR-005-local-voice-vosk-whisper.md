# ADR-005 — Voz local: Vosk en vivo y segunda pasada whisper.cpp

- Estado: **`Accepted` provisionalmente, sólo para la demostración** (Roderich Rendón, 2026-11-05). Ver «Decisión del autor». No es la aceptación definitiva.
- Fecha: 2026-11-05.
- Relación: `ADR-002` (Android `SpeechRecognizer`, `Accepted`) no se sustituye. La aceptación provisional cubre la demostración, no la decisión definitiva del motor. `ADR-004` (`Proposed`, rama `evolution/evolution-3-hybrid-voice-benchmark`) queda como antecedente sin modificarse. NO_GO_C4 (#59) se cita como resultado histórico: no se reinterpreta.
- Issues: #13 (registro de la decisión), #165 (Vosk), #166 (segunda pasada). GATE-F09 (#17) no cambia.

## Contexto

`ADR-002` depende de un reconocedor y de paquetes de idioma del sistema que la app no controla. En el HONOR (API 36) no había ningún español instalado (`DEFECTO-004`). La conciliación del 2026-10-31 fijó como diseño seleccionado Vosk para la transcripción progresiva y Whisper small como segunda pasada condicional (3.12.4.7).

## Diseño implementado en la rama `feat/voz-local-continua`

```text
AudioRecord 16 kHz ─► cola acotada (3 s) ─► Vosk small-es 0.42 ─► parciales en vivo
                                               └─► frase cerrada ─► whisper.cpp base q5_1 + pista ─► una sola transcripción
```

- **Todo dentro de la app.** Los modelos viajan en el APK, verificados por SHA-256 al prepararlos y al copiarlos. Ni la voz ni el texto pasan por la red.
- **Un turno a través de las pausas.** Cada pausa cierra una frase numerada, pero el micrófono sigue abierto hasta que el usuario detiene.
- **Segunda pasada sólo sobre voz.** Whisper revisa una frase en la que Vosk ya oyó palabras, nunca silencio. Su texto se acepta sólo si el lector numérico de la app obtiene exactamente las mismas cantidades, unidades y monedas que con el texto de Vosk; si no, queda el de Vosk (`lib/voice/port/review_selection.dart`).
- **Vocabulario.** El *prompt* de Whisper lleva los nombres del catálogo (productos, personas, proveedores, chacos y campaña). Vosk no admite añadir palabras a su léxico: Bellator, Mancozeb, Paraquat, Atrazina, Cipermetrina y Tebuconazol no existen en el modelo small-es (comprobado con su gramática).

## Diferencia con el diseño seleccionado: Whisper base, no small

| Configuración (HOST, 51 frases sintéticas) | WER medio | Productos | Cantidades | Tiempo por frase en el PC |
|---|--:|--:|--:|--:|
| Vosk solo | 0,154 | 21/45 | 51/51 | — |
| Whisper base q5_1 + pista | 0,057 | 39/45 | 49/51 | 0,77 s (mediana) |
| Whisper small q5_1 + pista | 0,025 | 42/45 | 51/51 | 2,28 s (mediana) |

Small es más preciso, pero tarda unas tres veces más. En el POCO, `ADR-002` midió base en 2,9 s (p50) tras detener; small sería del orden de tres veces eso, lo que impide una experiencia fluida. Esta entrega usa **base**, con `fetch_voice_models.sh small` disponible para compilar la variante small. **No cumple el diseño «Whisper small»**: es una desviación registrada, no su cumplimiento. Los números del PC no describen un teléfono.

## Lo que este ADR no afirma

- Ninguna precisión con voces reales ni en un teléfono. La evaluación es la de #12, con umbrales fijados antes de medir; el holdout no se tocó.
- Ningún rendimiento, memoria, batería ni temperatura en teléfono: `NOT_MEASURED`.
- RNF-14: no se declara cumplido.

## Consecuencias

- **APK:** unos 150 MB en x86_64 con base (modelos de 120 MB).
- **Cadena de suministro:** Vosk Android 0.3.75 y JNA 5.18.1 fijados por SHA-256 en Gradle (la firma PGP de Vosk sigue sin verificarse, `RISK-033`); whisper.cpp compilado desde el commit `52a939a2`, con el SHA-256 del código.
- **Entrada manual:** sigue siempre disponible; sin modelo, la pantalla lo dice y no descarga nada.
- **Android `SpeechRecognizer`:** se conserva detrás del mismo puerto (`--dart-define=AGRO_VOICE_ENGINE=android`); la app nunca cambia de motor por su cuenta.

## Decisión del autor (2026-11-05)

Roderich Rendón acepta **provisionalmente** Vosk + whisper.cpp `ggml-base-q5_1` para la demostración de Agrocuentas.

- **Motivo:** la elección prioriza la **fluidez de la demostración**. No afirma que base sea más preciso que small, que en HOST fue más preciso pero unas 3 veces más lento.
- **Versión de demostración:** la APK probada, `03124a0`, instalada en el paquete aislado «AC VOZ». Si el ensayo con su voz funciona bien, esa versión se conserva para la defensa, sin cambiar de modelo ni añadir funciones en este lote.
- **Errores que reporte con su voz:** se corrigen primero los que alteren cantidades, unidades o productos, y los que dupliquen texto o pierdan el borrador.

**Sigue pendiente:**
- la comparación definitiva con `small`;
- el rendimiento en un teléfono (`NOT_MEASURED`);
- la evaluación de #12.

**Lo que esta aceptación no cambia:** GATE-F09 (#17) sigue igual, RNF-14 no se declara cumplido y el PR Mobile #190 sigue en borrador, sin fusionar a `main`.

## Nota de actualización (2026-11-13)

Configuración vigente, comprobada en el código de `main` (`34e9926`) el 2026-11-13. El estado de este ADR no cambia.

- **Compra:** turno entero con un solo transcriptor, **Whisper small** q5_1 con **haz de 5** (`purchaseVoiceWholeTurn = true` y `purchaseSpeechPortFactoryProvider` en `lib/presentation/voice/voice_purchase_port.dart`; `defaultTurnVariant = 'small'` y `defaultTurnDecoding = WholeTurnDecoding.beam5` en `lib/voice/port/voice_engine_diagnostics.dart`). Es la decisión del autor del 2026-11-10, por precisión y no por una superioridad demostrada (`docs/f09/INTEGRACION_COMPRA_VOZ_SMALL_2026-11-10.md`; diagnóstico de motores en `docs/f09/poco/DIAGNOSTICO_MOTORES_2026-11-09.md` y `docs/f09/poco/EXPERIMENTO_TURNO_ENTERO_2026-11-09.md`). En la compra, por tanto, ya no rige la elección de base de la «Decisión del autor (2026-11-05)».
- **Aplicación y planificación:** sin cambios respecto de este ADR: **Vosk** small-es 0.42 por frases con **Whisper base** q5_1 como segunda pasada (`speechPortFactoryProvider` en `lib/voice/voice_providers.dart`, `LocalSpeechTranscriptionAdapter`, tope de revisión de 5 s por frase con `AGRO_VOICE_REVIEW_TIMEOUT_MS`; regla de aceptación de `lib/voice/port/review_selection.dart`).
- **Modelos y bibliotecas fuera de Git:** `android/app/voice-models/` y `android/app/src/main/jniLibs/` están en `.gitignore`. Se obtienen con `tool/voice_local/fetch_voice_models.sh` (por defecto `both`: Vosk + base + small, verificados por SHA-256) y `tool/voice_local/build_whisper_libs.sh` (whisper.cpp `52a939a`). La frase «Los modelos viajan en el APK» del diseño se refiere a las APK de prueba compiladas tras esos dos pasos (`tool/voice_local/build_voice_apk.sh`, perfil *profile*).
- **APK de release:** la compilación de release del repositorio (`flutter build apk --release` en `.github/workflows/flutter-ci.yml`) no ejecuta esos pasos y sale **sin modelos**; sin ellos la app compila y la voz se declara no disponible, con la entrada manual intacta. Esto lo asegura el procedimiento, no la configuración: `android/app/build.gradle.kts` añade `voice-models` a los *assets* de `main` para todos los tipos de compilación, de modo que una release compilada en una máquina con esa carpeta preparada los incluiría.
- **Sin cambios** en lo que este ADR no afirma: ninguna precisión con voces reales ni rendimiento en teléfono medidos aquí (`NOT_MEASURED`), RNF-14 no declarado cumplido y GATE-F09 (#17) igual.
