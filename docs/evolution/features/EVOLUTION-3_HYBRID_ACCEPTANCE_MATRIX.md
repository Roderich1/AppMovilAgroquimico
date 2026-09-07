# EVOLUTION-3 — Matriz de aceptación del motor híbrido

## Identidad de la corrida

| Campo | Valor |
|---|---|
| Rama de benchmark | `evolution/evolution-3-hybrid-voice-benchmark` |
| Commit de benchmark | `093a6ba` — el que llevan dentro los APK y que exportan en cada resultado |
| Corpus | `hibrido-ag` · `hybrid-1.0.0` · SHA-256 `52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0` |
| Commit whisper.cpp | `52a939a2a762224e255d366c1182b2af4dd1a032` — el mismo de la Fase 0, para que `base` y `small` sean comparables |
| Vosk API | `com.alphacephei:vosk-android:0.3.75`, AAR SHA-256 `ab2f8b91ac8051561aa325546b35fed9a68b36b8121bac5c6fb927525c4adfad`. Sin tag público equivalente: ver `RISK-033` |
| Vosk model ID/SHA-256 | `vosk-model-small-es-0.42` · `09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f` (zip de 39.817.833 B) |
| Whisper model ID/SHA-256 | `ggml-small-q5_1.bin` · `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` (190.085.487 B) |
| APK/SHA-256 | Ver la tabla de binarios, abajo |
| POCO fecha/operador | `PENDING` |
| HONOR fecha/operador | `PENDING` |

## Binarios construidos

Todos del commit `093a6ba`, con `--dart-define=BENCH_COMMIT=093a6ba`. Los de
`arm64-v8a` son los que se instalan en los teléfonos; los de `x86_64` existen
**sólo** para el gate de páginas de 16 KB y no producen mediciones.

| APK | ABI | Bytes | SHA-256 |
|---|---|--:|---|
| C1 · Vosk | `arm64-v8a` | 88.184.272 | `0a88f684886ee95f3abc0d67f814a35c5b75dffc68adfec5dd6cb3b2ff94babb` |
| C3 · Whisper small | `arm64-v8a` | 210.809.078 | `77b70da5acb98d05211d158b7789fcfb9bbbfb1e3ecb46c17693f2c1bbfd17b1` |
| C1 · Vosk (emulador) | `x86_64` | 89.852.836 | `fa19c57acd9ae0c3740d064e60982a79c9142414cdd0198e505f03e103f993cc` |
| C3 · Whisper small (emulador) | `x86_64` | 212.413.380 | `645071f0b554f36df1c5ecc065cde9c77f045ef565d12102a58000ba9ef64cd4` |

Comprobado sobre cada uno: **una sola ABI**; todas las librerías nativas
alineadas a 16 KB (4 en C1, 6 en C3); `zipalign -c -P 16 -v 4` correcto; único
permiso `RECORD_AUDIO`; el corpus A–G dentro del APK con el digest fijado; C1
sin una línea de Whisper y C3 sin una línea de Vosk.

Las librerías de `whisper.cpp` se reconstruyeron desde el commit fijado
`52a939a2a762224e255d366c1182b2af4dd1a032` con NDK `28.2.13676358` y CMake
`3.22.1`, en vez de reutilizar las de la Fase 0: están despojadas de símbolos y
no hay forma de comprobar en el binario de qué commit salieron. La aplicación
muestra ese commit en su cabecera.

Procedencia verificada en fuente primaria el 2026-09-07 y detallada en
`benchmark/voice_benchmark/THIRD_PARTY.md`. **No existe un modelo español de Vosk de 180 MB**:
la lista oficial sólo publica el móvil de 39 MB y uno de 1,4 GB para servidor; los ~180 MB
corresponden al modelo de Whisper.

## Aparatos obligatorios, tal como están

| Campo | POCO X5 Pro 5G | HONOR JDY-LX3P |
|---|---|---|
| API | 31 (Android 12) | 36 (Android 16) |
| ABI | `arm64-v8a` | `arm64-v8a` |
| SoC | `PENDING` | MediaTek `MT6769V/CZ` (plataforma `mt6768`) |
| RAM total | `PENDING` | 5.918.284 kB |
| Tamaño de página | `PENDING` | 4096 B |

Ninguno de los dos aparatos obligatorios tiene páginas de 16 KB, así que ese
gate **no se puede ejecutar en ellos**. Se ejecutó en un emulador de API 36 con
`getconf PAGE_SIZE` = `16384`: ver
`EVOLUTION-3_HYBRID_16KB_GATE_EVIDENCE.md`. C1 y C3 pasaron; C4 queda
pendiente.

El SoC del HONOR es de gama de entrada. Es información relevante antes de medir, no una excusa
después: si Whisper small no alcanza el factor de tiempo real allí, el resultado es el
resultado.

## Resultado comparativo

| Métrica | Android baseline | Vosk | Whisper small | Híbrido | Umbral | Estado |
|---|---:|---:|---:|---:|---:|---|
| Datos críticos correctos | 81,1 % | PENDING | PENDING | PENDING | > 81,1 % | PENDING |
| Productos correctos | 5/17 | PENDING | PENDING | PENDING | >= 12/17 | PENDING |
| Cantidades correctas | 17/17 | PENDING | PENDING | PENDING | >= 17/17 | PENDING |
| Precios correctos | 8/8 | PENDING | PENDING | PENDING | >= 8/8 | PENDING |
| Montos correctos | 6/7 | PENDING | PENDING | PENDING | >= 6/7 | PENDING |
| WER mediana | 0,167 | PENDING | PENDING | PENDING | <= 0,167 | PENDING |
| Primer parcial p50 | 1741 ms | PENDING | N/A | PENDING | <= 800 ms | PENDING |
| Primer parcial p95 | PENDING | PENDING | N/A | PENDING | <= 1500 ms | PENDING |
| Final p50 <=20 s | 17 ms | PENDING | PENDING | PENDING | <= 2500 ms | PENDING |
| Final p95 <=20 s | PENDING | PENDING | PENDING | PENDING | <= 5000 ms | PENDING |
| RTF p95 <=60 s | PENDING | PENDING | PENDING | PENDING | <= 0,50 | PENDING |
| RAM pico total | 158 MiB | PENDING | PENDING | PENDING | <= 1,2 GB | PENDING |
| Texto sobre no-habla | 0 | PENDING | PENDING | PENDING | 0 | PENDING |
| Crash/ANR/OOM 30 sesiones | 0 | PENDING | PENDING | PENDING | 0 | PENDING |
| Funciona limpio en modo avión | depende del sistema | PENDING | PENDING | PENDING | Sí | PENDING |

Completar una tabla por dispositivo además del resumen; no mezclar POCO y HONOR en un promedio
que esconda fallos por OEM/API.

## Lo que ya se sabe antes de medir

Dos cosas salieron de construir y ejecutar, no de dictar el corpus. No son
métricas y no ocupan una celda de la tabla, pero condicionan cómo se lee:

1. **`ggml-small-q5_1` afirma texto sobre silencio.** En el emulador de 16 KB,
   con 5177 ms sin habla, devolvió `[MÚSICA]`. Es `RISK-026` otra vez y **el
   modelo `small` no lo arregla**. El guardrail «cero texto aceptado sobre
   no-habla» se decide en la partición `sin_habla` de los dos teléfonos, y hoy
   la expectativa razonable para C3 es que **no lo cumpla**. Vosk, con el mismo
   silencio, respondió `noMatch`.
2. **La carga fría de C3 es cara.** La primera ejecución copia 190 MB de assets,
   carga el modelo y después infiere. En el emulador eso agotó el tope de 60
   segundos de sesión. El emulador no mide rendimiento, pero conviene vigilar el
   arranque en frío en el aparato real.

## Guardrails binarios

| Gate | POCO API 31 | HONOR API 36 | Evidencia |
|---|---|---|---|
| Instalación limpia | PENDING | PENDING | |
| Modelo auténtico y hash válido | PENDING | PENDING | |
| Primera ejecución sin red | PENDING | PENDING | |
| Una sola captura de audio | PENDING | PENDING | |
| Audio nunca escrito | PENDING | PENDING | |
| Cancelación libera micrófono | PENDING | PENDING | |
| Lifecycle/interrupciones | PENDING | PENDING | |
| Silencio/ruido no producen texto aceptado | PENDING | PENDING | |
| Edición manual preservada | PENDING | PENDING | |
| Inventario y cuentas sin cambios | PENDING | PENDING | |
| CPU/batería/temperatura medidos | PENDING | PENDING | |
| Licencias/atribuciones completas | PENDING | PENDING | |

## Decisión

| Campo | Valor |
|---|---|
| Candidato recomendado | `PENDING` |
| Umbrales incumplidos | `PENDING` |
| Riesgos aceptados | `PENDING` |
| ADR-004 | `Proposed` |
| Decisión del propietario | `PENDING` |
| Fecha | `PENDING` |

No cambiar `ADR-004` a `Accepted` si quedan métricas críticas `NOT_MEASURED`, si existe texto
aceptado sobre no-habla o si sólo uno de los dos dispositivos obligatorios fue probado.

