# F09: voz local, observaciones del autor al dictar

**Qué es.** Lo que Roderich observe al dictar con su propia voz en la versión de demostración.

**Qué no es.**
- Los resultados con muestras sintéticas están en `F09_VOZ_LOCAL_2026-11-05.md` y no se mezclan con este archivo.
- No es la evaluación de #12: no fija umbrales ni usa el holdout.
- No mide en ningún teléfono.

**Estado:** sin observaciones en el emulador todavía.

**POCO físico con voz humana (2026-11-05):** el primer ensayo en el teléfono se registra aparte, en `F09_VOZ_LOCAL_POCO_2026-11-05.md`. Allí está el hallazgo reproducido de «un litro y medio» (cantidad y producto, §2.1) y el caso de la pausa antes de «Mancozeb», pendiente de repetir (§2.2).

| Dato | Valor |
|---|---|
| Versión | APK `agrocuentas-voz-03124a0-x86_64-profile.apk`, SHA-256 `94bc939344d0850fd2951c6e10b60d4e98ce5f5c8c4f662dbf495f8560dec3d9` |
| Instalación | «AC VOZ» (`com.comunidad.agro.agroquimicos.voz`) en el emulador `Pixel_8` |
| Motor | Vosk `small-es-0.42` + whisper.cpp `ggml-base-q5_1` (ADR-005, aceptado provisionalmente para la demostración) |
| Procedencia del audio | Micrófono del PC hacia el emulador, activado por Roderich. Es voz humana, pero no audio de teléfono |

## Cómo registrar

Una fila por intento. El texto dictado se escribe sólo si es una frase de prueba; nada personal.

**Tipo de error:**
- `cantidad`, `unidad`, `producto`, `duplicado` o `borrador perdido` se corrigen primero;
- `otro` es cualquier otro error, por ejemplo una palabra que no es un producto;
- `ninguno`.

**Reproducible:** sí o no. Sólo se corrige lo reproducible.

| Fecha | Pantalla | Red | «Revisar cada frase» | Lo que dijo | Lo que quedó en el borrador | Tipo de error | Reproducible | Nota |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

## Correcciones derivadas

Cada corrección se registra con el commit y la prueba que la cubre, y se vuelve a comprobar con la misma frase.

| Observación | Commit | Prueba | Comprobado |
|---|---|---|---|
| «un litro y medio» → 1 L y producto «y medio de …» (POCO §2.1) | pendiente: no se corrige en este lote | — | — |
