# EVOLUTION-3 — Cómo dictar el corpus híbrido, frase por frase

Para el propietario. Se ejecuta en el **HONOR JDY-LX3P** (Android 16 / API 36) y
en el **POCO X5 Pro 5G** (Android 12 / API 31). Los dos son obligatorios y no se
promedian: cada uno llena su propia tabla.

> **Nada de lo que dicte se guarda en Agrocuentas.** El banco es una aplicación
> aparte, con su propio icono, que no abre la base de datos ni registra ninguna
> compra, pago ni aplicación. El audio no se escribe en el teléfono y no sale de
> él: el único permiso que pide es el micrófono.

## Antes de empezar

1. **Batería entre 30 % y 85 %, y el cargador desconectado.** Con el teléfono
   enchufado no se puede medir batería ni temperatura, y así se perdió esa
   medición en la Fase 0.
2. **Cinco minutos de reposo** antes de la primera frase, con la pantalla
   encendida y el brillo fijo. El teléfono tiene que estar frío.
3. **Cierre las demás aplicaciones.**
4. **Active el modo avión** desde los ajustes del sistema, no desde el banco.
5. En el banco, encienda el interruptor «Estoy en MODO AVIÓN». Si el teléfono no
   está realmente en modo avión, aparecerá un aviso rojo: **no siga hasta que
   desaparezca**. Una tanda mal etiquetada no prueba nada sobre funcionamiento
   sin Internet.

## Elegir qué se va a medir

Arriba del todo hay tres menús. **El banco arranca sin corpus y no deja grabar
hasta que elija uno.**

1. **Corpus** → `Híbrido A–G (54 frases)`.
   Es el único con el que C1, C3 y C4 son comparables entre sí. El de la Fase 0
   sirve para repetir lo ya medido en el POCO, no para esta comparación.
2. **Partición** → empiece por `Ajuste`.
3. **Locale** → `es-BO`.

Debajo, la tarjeta **«Qué se va a medir»** tiene que decir:

| Campo | Lo que debe decir |
|---|---|
| Corpus | `Híbrido A–G (54 frases) · hibrido-ag` |
| Versión | `hybrid-1.0.0` |
| SHA-256 | `52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0` |
| Partición | `Ajuste` (21 frases) · `Aceptación` (25) · `Técnicas / sin habla` (8) |
| Candidato | `C1 · Vosk small es 0.42 aislado` o `C3 · Whisper small q5_1 aislado` |

**Si la tarjeta está en rojo, no grabe.** Dice por qué. Si el SHA-256 no es el de
arriba, el APK no es el que se preparó: avíseme antes de seguir.

## Cómo se dicta cada frase

Para **cada** frase, en este orden:

1. Lea la frase en voz alta **para usted**, en silencio, antes de tocar nada.
   Así no se graba la duda del primer intento.
2. Toque **Grabar**. Espere a que diga «escuchando».
3. Diga la frase **completa**, a velocidad normal, sin deletrear ni exagerar.
   Es el habla que va a existir en el chaco lo que hay que medir.
4. Toque **Detener** en cuanto termine de hablar. No espere.
   - Con **C1** el texto aparece casi enseguida.
   - Con **C3** dirá «processing» un rato: Whisper transcribe al final, no
     mientras habla. Es normal y **ese tiempo es parte de lo que se mide**.
5. Mire el resultado:
   - Si sale un recuadro rojo **«EL MOTOR MARCA ESTE TEXTO COMO DUDOSO»**,
     déjelo así. Es información: significa que el motor sospecha de lo que
     acaba de decir. No repita para «arreglarlo».
   - Si el texto está mal, tampoco lo repita para mejorarlo. Un error del motor
     es exactamente lo que hay que registrar.
6. Escriba una observación **sólo si pasó algo raro** (un ruido, se trabó, tardó
   muchísimo). No hace falta describir el resultado: el banco ya lo guarda.
7. Toque **Guardar medición y pasar a la siguiente**.

### Tres tomas por frase

El plan pide **como mínimo tres tomas de cada frase**. Después de guardar, toque
**Anterior** para volver a la misma y repita los pasos 2 a 7. El banco numera los
intentos solo; no hay que anotar nada.

Repetir la misma frase dos veces y obtener datos distintos **es un resultado**,
no un fallo suyo: en la Fase 0 una cantidad cambió de `12` a `dos` entre dos
tomas (`RISK-027`).

## La partición «Técnicas / sin habla»

Son ocho muestras donde **no hay que decir nada**. La pantalla dice qué producir
en «condiciones». Cada una se «dicta» tocando Grabar, produciendo la condición, y
tocando Detener:

| Condición | Qué hacer |
|---|---|
| `silencio_3s` | Grabar, contar tres segundos en silencio, Detener |
| `silencio_10s` | Igual, diez segundos |
| `silencio_30s` | Igual, treinta segundos |
| `ruido_viento` | Al aire libre con viento, o soplando **lejos** del micrófono |
| `ruido_tractor` | Cerca de un motor en marcha |
| `ruido_conversacion` | Con gente hablando de fondo, sin dirigirse al teléfono |
| `ruido_radio` | Con una radio o música sonando |
| `golpe_microfono` | Un golpe seco en el teléfono, sin hablar |

**Esta es la partición que decide el guardrail más importante.** Cualquier texto
que el motor acepte aquí sin marcarlo como dudoso es una afirmación sobre algo
que nadie dijo. Ya sabemos que va a pasar con C3: en el emulador devolvió
`[MÚSICA]` sobre silencio. Lo que hace falta es medir **cuántas veces** pasa en
el teléfono, y si la marca lo atrapa siempre.

## Orden de las tandas

Por cada teléfono, y **en este orden**:

1. C1 · Ajuste (21 frases × 3 tomas)
2. C1 · Técnicas / sin habla (8)
3. C3 · Ajuste (21 × 3)
4. C3 · Técnicas / sin habla (8)

**La partición de aceptación no se toca todavía.** Se ejecuta una sola vez, al
final, conmigo presente, y después no se puede repetir sin invalidar la
comparación.

Descanse cinco minutos entre una tanda y la siguiente para que el teléfono
recupere temperatura. Si nota que se calienta mucho, anótelo: la temperatura es
una de las métricas de `ADR-004`.

## Al terminar cada tanda

1. Baje hasta la última tarjeta.
2. Deje **«Incluir las transcripciones»** encendido. El corpus es texto
   inventado; no hay datos reales que proteger. Apáguelo sólo si en algún
   momento dictó algo suyo de verdad.
3. Toque **Exportar JSON** y después **Exportar CSV**.
4. El banco dice dónde quedó el archivo. Páselos al computador por cable.

No borre las mediciones entre tandas del mismo teléfono: exportar dos veces la
misma tanda no es un problema, el agregador descarta lo repetido.

## Qué anotar aparte

El banco no puede leer esto solo:

- SoC, RAM total y RAM disponible del POCO (del HONOR ya están: MediaTek
  `MT6769V/CZ`, 5.918.284 kB);
- temperatura al empezar y al terminar cada tanda, si puede medirla;
- porcentaje de batería al empezar y al terminar;
- si el teléfono se calentó o se puso lento;
- cualquier vez que la aplicación se cerró sola.

## Lo que NO hay que hacer

- No dictar la partición de **aceptación** sin mí.
- No repetir una frase porque el motor se equivocó.
- No cambiar de corpus a mitad de una tanda.
- No conectar el cargador durante una tanda.
- No editar el corpus. Si encuentra una frase mal escrita, avíseme: se versiona
  un corpus nuevo y se dice qué mediciones invalida. Cambiarla en el sitio
  rompería el SHA-256 y el banco dejaría de arrancar, que es justamente la
  protección.

## Cuando termine

Deme:

- los `.json` y `.csv` de cada tanda;
- las notas de arriba;
- cualquier captura de algo que le pareciera raro.

Con eso genero el informe. **Ninguna métrica está medida todavía**: la matriz de
aceptación sigue entera en `PENDING` y `ADR-004` sigue `Proposed`.
