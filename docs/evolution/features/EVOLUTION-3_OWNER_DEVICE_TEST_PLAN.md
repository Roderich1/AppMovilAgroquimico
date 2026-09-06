# EVOLUTION-3 — Plan de pruebas en teléfonos reales

## Para quién es esto

Para el propietario del producto. No hace falta saber programar: hay que
instalar tres aplicaciones, hablarles y exportar un archivo.

**Nada de lo que haga aquí toca Agrocuentas.** Las tres aplicaciones de prueba
son independientes, se instalan al lado de la aplicación real, no abren su base
de datos y no pueden registrar compras, aplicaciones ni pagos. Lo único que
piden es el micrófono.

## Qué se está decidiendo

Cuál motor de voz usará Agrocuentas: el que trae Android o `whisper.cpp` con un
modelo propio. `ADR-002` sigue **sin decidir** y no se decidirá hasta tener estos
resultados. Si ninguno sirve, se dirá que ninguno sirve.

## Lo que hay que entregar al final

Un archivo exportado por cada aplicación y por cada teléfono, más la tabla del
final de este documento. Con eso se completa
`EVOLUTION-3_OWNER_DEVICE_TEST_RESULTS_TEMPLATE.md`.

---

## 1. Los tres archivos que va a instalar

| Aplicación | Archivo | Qué mide |
|---|---|---|
| **Voz · Android** | `voice-benchmark-android-arm64.apk` | El reconocimiento que trae el teléfono |
| **Voz · Whisper tiny** | `voice-benchmark-whisper-tiny-arm64.apk` | Whisper con el modelo pequeño |
| **Voz · Whisper base** | `voice-benchmark-whisper-base-arm64.apk` | Whisper con el modelo mediano |

Los tres se pueden tener instalados a la vez. En el teléfono aparecen con esos
nombres.

Los modelos de Whisper ya vienen **dentro** del archivo: esas dos aplicaciones no
necesitan Internet en ningún momento.

## 2. Habilitar la instalación

Estos archivos no vienen de la tienda, así que Android pide permiso una vez.

1. Copie los tres archivos al teléfono (cable USB, o envíeselos a usted mismo).
2. Ábralos con el explorador de archivos del teléfono.
3. Al tocar el primero, Android dirá que esa app no puede instalar aplicaciones
   desconocidas. Toque **Configuración** y active el permiso para el explorador
   de archivos.
4. Vuelva atrás y toque **Instalar**.
5. Si aparece un aviso de Play Protect, elija **Instalar de todos modos**: el
   archivo no está firmado para la tienda, y eso es deliberado.

Repita con los otros dos.

> Si prefiere hacerlo por cable desde una computadora con las herramientas de
> Android: `adb install -r <archivo>.apk`

## 3. Conceder (y denegar) el micrófono

La primera vez que toque **Grabar**, el teléfono pedirá el micrófono.

Haga las dos cosas, en este orden, **en la aplicación Voz · Android**:

1. **Deniegue** el permiso la primera vez. Anote qué muestra la pantalla. Debe
   decir un error claro, no quedarse trabada ni cerrarse.
2. Vuelva a tocar **Grabar** y ahora **conceda** el permiso.

Anote lo que ocurrió en cada caso. Con las otras dos aplicaciones basta conceder.

## 4. Cómo es la pantalla

De arriba abajo:

- **Disponibilidad del motor**: si hay reconocimiento, si funciona sin Internet,
  qué idioma pidió y **qué idioma va a usar realmente**. Si aparece un recuadro
  amarillo diciendo que el motor no usa `es-BO`, **anótelo**: es uno de los
  puntos que hay que decidir.
- **Corpus** (`ajuste` o `aceptación`) y **Locale**.
- **Estoy en MODO AVIÓN**: actívelo cuando pruebe sin red, para que quede
  marcado en cada resultado.
- **Grabar / Detener / Cancelar / Repetir**.
- **La frase que debe leer en voz alta**, con su número (`AJ-001`, `AC-014`…).
- **Estado, parcial, final y error**.
- **Latencias** y el botón para guardar la medición.

## 5. Ejecutar el corpus

Para cada frase:

1. Toque **Grabar**.
2. Lea la frase **en voz alta, tal como está escrita**.
3. Toque **Detener**.
4. Espere el resultado final. Con Whisper puede tardar varios segundos y **no
   mostrará texto parcial**: es normal, ese motor no lo produce.
5. Si algo salió mal por culpa suya (se trabó, tosió, sonó el teléfono), toque
   **Repetir** y hágalo otra vez.
6. Escriba una observación si hace falta.
7. Toque **Guardar medición y pasar a la siguiente**.

Empiece por el corpus de **ajuste** (40 frases) para agarrarle la mano. El que
decide es el de **aceptación** (60 frases).

> **Importante:** no cambie las frases para que el motor acierte. Si una frase
> sale mal, ese es el resultado.

## 6. Con Internet

Haga una pasada completa del corpus de aceptación con Wi-Fi o datos activos, con
**MODO AVIÓN desactivado** en la aplicación. Exporte.

## 7. En modo avión

1. Active el modo avión **del teléfono** (el de verdad, desde los ajustes).
2. Active también el interruptor **Estoy en MODO AVIÓN** dentro de la aplicación.
3. Toque **Comprobar** en la tarjeta de disponibilidad y anote si cambió algo.
4. Haga al menos 15 frases del corpus de aceptación con cada aplicación.
5. Exporte.

Esto es lo que decide si la voz sirve en el chaco sin señal. Si una aplicación
deja de funcionar en modo avión, **ese es el hallazgo más importante de toda la
prueba**.

## 8. En un lugar silencioso

Las frases marcadas con condición `silencio` deben hacerse en interior, sin ruido
de fondo. Es la medición de referencia.

## 9. Con ruido

Las frases marcadas con condición `ruido` deben hacerse con ruido real de campo:
motor encendido, viento, gente hablando cerca. Si no puede reproducir ruido real,
dígalo en las observaciones en lugar de hacerlas en silencio.

## 10. Interrupción o llamada

Con una aplicación grabando:

1. Pida que lo llamen, o baje la persiana de notificaciones y active algo.
2. Anote qué pasó: si la aplicación soltó el micrófono, si se quedó trabada, si
   dio un error claro.
3. Vuelva a la aplicación y compruebe que puede grabar de nuevo.

Repita bloqueando la pantalla con el botón de encendido mientras graba.

## 11. Segundo plano y regreso

1. Empiece a grabar.
2. Salga a la pantalla de inicio sin detener.
3. Espere unos segundos y vuelva a la aplicación.
4. Anote si el micrófono quedó tomado (¿sigue el indicador del sistema
   encendido?) y si la aplicación quedó utilizable.

## 12. Exportar los resultados

Al final de la pantalla:

- **Incluir las transcripciones**: déjelo activado. Desactívelo sólo si dictó
  algo real por accidente (un nombre verdadero, un monto verdadero); entonces el
  archivo saldrá sin el texto.
- Toque **Exportar JSON**. Si además quiere abrirlo en una planilla, toque
  también **Exportar CSV**.

Aparecerá abajo un mensaje con la ruta exacta del archivo.

## 13. Dónde está el archivo

En el almacenamiento interno del teléfono:

```
Android/data/com.comunidad.agro.voicebench.android/files/
Android/data/com.comunidad.agro.voicebench.whispertiny/files/
Android/data/com.comunidad.agro.voicebench.whisperbase/files/
```

Los archivos se llaman `voicebench_<motor>_<fecha>.json`.

Conéctelo por cable y cópielos a la computadora, o compártalos desde el
explorador de archivos del teléfono.

> Por cable, desde una computadora con herramientas de Android:
> `adb pull /sdcard/Android/data/com.comunidad.agro.voicebench.android/files/`

## 14. Desinstalar y limpiar

Al terminar:

1. Ajustes → Aplicaciones → **Voz · Android** → Desinstalar.
2. Lo mismo con **Voz · Whisper tiny** y **Voz · Whisper base**.

Desinstalar borra el modelo copiado y todo lo demás. **No queda audio guardado
en ningún momento**: las aplicaciones no lo escriben a disco ni durante la
prueba.

Si además quiere revocar el permiso de instalar aplicaciones desconocidas que dio
en el paso 2, hágalo en Ajustes → Aplicaciones → el explorador de archivos.

---

## Tabla a completar (una por teléfono y por motor)

| Campo | Resultado |
| --------------------- | --------- |
| Marca y modelo        |           |
| Procesador            |           |
| RAM                   |           |
| Android/API           |           |
| Motor                 |           |
| Modelo Whisper        |           |
| Tamaño APK            |           |
| Instalación correcta  |           |
| Funciona sin Internet |           |
| Locale solicitado     |           |
| Locale utilizado      |           |
| Frases correctas      |           |
| Frases con errores    |           |
| Latencia percibida    |           |
| Calentamiento         |           |
| Consumo de batería    |           |
| Errores observados    |           |
| Archivo de resultados |           |

## Los dos teléfonos que hacen falta

| Equipo | Por qué |
|---|---|
| **Pixel 8 / Android 16 / API 36** | Es el dispositivo de regresión del proyecto; todo lo anterior se verificó ahí |
| **Un Android de gama media o baja** | El que de verdad usan los usuarios. Whisper puede andar bien en un Pixel y ser inusable en un teléfono de 3 GB de RAM |

Mientras falte el segundo, el benchmark **no está completo** y `ADR-002` no
puede aceptarse. No se sustituye con un emulador ni con una estimación.
