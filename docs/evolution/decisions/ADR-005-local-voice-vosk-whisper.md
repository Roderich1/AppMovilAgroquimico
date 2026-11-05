# ADR-005 — Voz local: Vosk en vivo y segunda pasada whisper.cpp

- Estado: **`Proposed`**. Lo decide Roderich Rendón; este documento no lo acepta.
- Fecha: 2026-11-05.
- Relación: `ADR-002` (Android `SpeechRecognizer`, `Accepted`) sigue siendo la base productiva hasta que se decida esto. `ADR-004` (`Proposed`, rama `evolution/evolution-3-hybrid-voice-benchmark`) queda como antecedente sin modificarse. NO_GO_C4 (#59) se cita como resultado histórico: no se reinterpreta.
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

## Decisión pendiente

Aceptar, rechazar o reformular, sobre la evidencia de `docs/evidence/F09_VOZ_LOCAL_2026-11-05.md` y la prueba con voz real del autor.
