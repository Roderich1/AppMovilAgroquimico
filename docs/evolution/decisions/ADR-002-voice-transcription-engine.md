# ADR-002 — Motor de transcripción por voz

- Estado: `Accepted`.
- Fecha: 2026-09-06.
- Aceptado por: propietario del producto, sobre la evidencia de la Fase 0.
- Decisor: propietario del producto con evidencia técnica.

## Contexto

EVOLUTION-3 requiere español, nombres propios/productos, dictado continuo y respuesta rápida
en Android. La app es offline-first y el audio puede contener información financiera y
personal. Fijar Whisper o un servicio antes de medir precisión, memoria y latencia introduciría
un riesgo innecesario.

## Decisión ya aceptada

El dominio dependerá de `SpeechTranscriptionPort`, no de una API concreta. El adaptador emite
resultados parciales/finales y estados explícitos de permiso, disponibilidad, error y fin. No
conoce repositorios ni persiste audio.

## Decisión

**Motor productivo inicial: el reconocimiento de Android (`android.speech.SpeechRecognizer`).**

**`whisper.cpp` queda como reserva técnica documentada y no se distribuye** en la primera
implementación productiva de `EVO-009`. No se descarta: se conserva medido, construible y
sustituible detrás de `SpeechTranscriptionPort`.

No se introduce ningún servicio remoto.

## Criterios

Exactitud en slots críticos, falsa aceptación, español/nombres locales, latencia p95, memoria,
tamaño, batería, compatibilidad Android, modo avión, licencia, mantenimiento y facilidad de
reemplazo.

## Consecuencias

- **No se añade ninguna dependencia ni modelo Whisper al producto.** El APK productivo no
  crece.
- Los tests de UI/interpretación siguen usando el fake determinista.
- El APK no contiene dos motores: se distribuye uno.
- Una opción remota requerirá consentimiento y un ADR adicional; nunca es fallback silencioso.
- `EVO-009` queda obligado por la política productiva de este ADR, y en particular a conservar
  el **ingreso manual** siempre disponible.

## Razones de la elección

Medido sobre un teléfono físico, corpus de ajuste completo, modo avión verificado contra el
sistema.

| Razón | Valor |
|---|--:|
| Datos críticos correctos | **81,1 %** |
| Cantidades | **17/17** |
| Precios unitarios | **8/8** |
| Montos de pago | **6/7** |
| WER mediana | **0,167** |
| Resultados parciales | **sí** |
| Latencia p50 tras detener | **17 ms** |
| Memoria pico | **158 MiB** |
| Crecimiento del APK | **0 B** |
| Silencio | **`noMatch`**, no texto inventado |

La última fila es la razón que ninguna otra compensa. Whisper devolvió `[MÚSICA]` ante tres
segundos sin habla y lo marcó como resultado válido, sin error. Un motor que afirma texto que
nadie dijo puede afirmar un producto o un monto sobre ruido de campo, y el usuario lo vería
como dato propuesto. Android, ante la misma entrada, no afirma nada.

## Limitaciones aceptadas con esta decisión

1. **Productos reconocidos correctamente: 5 de 17.** El motor no reconoce el catálogo agrícola.
2. **`es-BO` no está disponible** — error 12 `LANGUAGE_NOT_SUPPORTED`.
3. **`es-ES` no estaba instalado** en el dispositivo probado — error 13 `LANGUAGE_UNAVAILABLE`.
4. **El funcionamiento efectivo se obtuvo con `es-US`**, el único paquete presente.
5. **Puede requerirse un modelo de idioma** descargado previamente; sin él no hay dictado.
6. **Las APIs de disponibilidad no son garantía.** `isOnDeviceRecognitionAvailable()` devolvió
   `false` en el mismo aparato donde el modo offline funcionó vía SODA.
7. **El modo offline debe comprobarse intentando transcribir**, no preguntando a la API.
8. **El comportamiento depende del dispositivo, del OEM, de la aplicación de Google y de los
   modelos instalados.**
9. **No existe garantía de funcionamiento idéntico en API 36.**

## Gate Pixel 8 / Android 16 / API 36

Estado: **`WAIVED_BY_OWNER — residual compatibility risk accepted`**

No es `VERIFIED`, no es `PASSED` y no es `NOT_APPLICABLE`. El gate no se ejecutó.

Justificación registrada por el propietario:

- las pruebas se realizaron en **hardware físico Android 12 / API 31**;
- **API 31 representa el límite inferior real probado**;
- el propietario **prioriza continuar la evolución** antes que esperar el aparato;
- **API 36 permanece sin evidencia directa**;
- la aplicación **tendrá siempre ingreso manual como alternativa**;
- **un problema en API 36 no debe impedir usar las funciones manuales**;
- si posteriormente aparece un dispositivo API 36, **la prueba se ejecutará como regresión
  adicional**, no como condición para esta decisión.

El riesgo residual queda en `RISK-028`.

## Política productiva derivada, obligatoria para `EVO-009`

1. La aplicación **solicita preferentemente** reconocimiento offline / on-device.
2. **No confía únicamente** en `isRecognitionAvailable()`, en
   `isOnDeviceRecognitionAvailable()` ni en la lista de idiomas instalados.
3. **Debe intentar la operación y observar el resultado real.**
4. Debe mostrar: **locale solicitado**, **locale utilizado**, si el **modo offline** está
   disponible, si **falta un modelo** y si el **error es recuperable**.
5. **No puede prometer `es-BO`.**
6. Debe usar el **mejor español instalado o soportado**, con el fallback **visible**.
7. Si no hay reconocimiento disponible: **no bloquear** la aplicación, **no reintentar
   infinitamente**, **no descargar silenciosamente**, **mostrar instrucciones** y **mantener la
   edición manual**.
8. **La voz nunca confirma operaciones.**
9. **Los resultados parciales son sólo texto provisional.**
10. Todo texto pasa después por `EVO-010`: resolución local, validación y borrador editable.

## Whisper como reserva

No se añade al APK productivo de `EVO-009`. Se conserva medido:

| | tiny `q5_1` | base `q5_1` |
|---|--:|--:|
| Peso añadido al APK | +39,2 MiB | +65,4 MiB |
| Datos críticos | 57,6 % | 66,3 % |
| Memoria pico | 276 MiB | 328 MiB |

Además: **sin resultados parciales**, **mayor latencia** (1,2 s y 2,9 s p50 tras detener) y
**riesgo de alucinación sobre silencio**. A cambio: **funciona sin el modelo del sistema** y es
**independiente del servicio de Google**.

### Disparadores para reconsiderarlo

- `SpeechRecognizer` no disponible en una parte relevante de los dispositivos reales;
- funcionamiento offline insuficiente en campo;
- cambios del servicio de Google que degraden o condicionen el reconocimiento;
- mejora comprobada de Whisper o de sus modelos futuros;
- necesidad de independencia tecnológica respecto de Google;
- existencia de un mecanismo fiable de detección de silencio y de alucinaciones.

## Hallazgo de productos: no resuelto

Esta decisión **no resuelve** el reconocimiento del catálogo agrícola, y no debe presentarse
como si lo hiciera.

- **Ningún motor reconoce adecuadamente el catálogo agrícola.** Paraquat, Mancozeb,
  Lambdacialotrina, Germi-100 y Expansive fallan en los tres.
- **Android sólo logró 5/17.**
- Se aborda en **`EVO-010`**, no en el motor.
- Los productos se resolverán **contra el catálogo local y sus aliases**.
- Las **coincidencias ambiguas bloquean el borrador**.
- **Un producto nuevo nunca se crea silenciosamente.**
- Las **cantidades inestables requieren confirmación visible**: la misma frase dictada dos veces
  devolvió `12` y `dos`.
- **La voz entrega texto, no datos confiables.**

## Estado del benchmark (2026-09-06)

La Fase 0 construyó el banco de pruebas y el corpus, y el propietario ejecutó el corpus de
ajuste completo con los tres motores en un **POCO X5 Pro 5G (Android 12 / API 31)**, en modo
avión verificado contra `Settings.Global.AIRPLANE_MODE_ON`. Detalle completo en
`features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md`.

**El gate del Pixel 8 / API 36 no se ejecutó**: `WAIVED_BY_OWNER` (ver arriba).

### Hechos medidos en teléfono real

| Criterio | Android | Whisper tiny | Whisper base |
|---|--:|--:|--:|
| Datos críticos correctos | **81,1 %** | 57,6 % | 66,3 % |
| WER mediana | **0,167** | 0,385 | 0,300 |
| Afirma texto sobre silencio | **No** | **Sí** (`[MÚSICA]`) | `NOT_MEASURED` |
| Memoria pico | **158 MiB** | 276 MiB | 328 MiB |
| Peso añadido al APK | **0 B** | +41.063.516 B | +68.618.468 B |
| Resultados parciales | **Sí**, ~1,7 s | No | No |
| Latencia tras detener p50 | **17 ms** | 1228 ms | 2944 ms |

1. **`es-BO` no existe**: error 12 `LANGUAGE_NOT_SUPPORTED`. `es-ES` da error 13
   `LANGUAGE_UNAVAILABLE` — existe pero no estaba instalado. Sólo funcionó `es-US`, el único
   paquete presente. La aplicación debe usar el idioma que haya y **no puede prometer español
   boliviano**.
2. **El modo offline del Candidato A funciona**, vía **SODA**, el reconocedor local de Google.
   Confirmado en `logcat` con las radios apagadas.
3. **`isOnDeviceRecognitionAvailable()` devuelve `false` en ese mismo aparato.** La API no
   sirve como garantía de offline; hay que intentar la transcripción y observar el resultado.
4. **Ningún motor reconoce los nombres de producto** — 5/17 el mejor. Paraquat, Mancozeb,
   Lambdacialotrina, Germi-100 y Expansive fallan en los tres. Es trabajo de `EVO-010` contra
   la base local, no del motor.
5. **Whisper comete errores numéricos que Android no comete**: «dos mil setecientos» dio
   `2017, 100` en tiny y `17,200` en base.
6. **Repetibilidad baja**: las mismas 40 frases dictadas dos veces coincidieron sólo en el
   33,3 %, y una cantidad cambió entre tomas (`doce` leído como `12` y como `dos`).
7. **No requiere wrapper de terceros.** El puente JNI es código de este repositorio, con
   whisper.cpp compilado desde un commit fijado. El escape hatch es borrar `benchmark/`.

### Recomendación técnica

**Candidato A como motor primario**, por no inventar sobre silencio, por acertar más en datos
críticos y por no costar nada en distribución. **Whisper queda como reserva**, no descartado:
es el único que no depende de Google y el único que garantiza offline sin paquete previo.

Ninguno alcanza el listón de `EVO-009` por sí solo: la transcripción cruda no puede precargar
un borrador de compra, y la frontera de confirmación de `ADR-003` pasa de precaución a
mecanismo necesario.

### Lo que sigue sin medirse

CPU y batería atribuidas al motor, temperatura bajo carga sostenida, silencio en Whisper base,
lifecycle e interrupciones en dispositivo, y el **Pixel 8 / API 36**. El corpus de aceptación
sigue intacto a propósito.

La exactitud de intención, la completitud del borrador y la falsa aceptación no pertenecen a
esta fase: se definen sobre el borrador tipado de `EVO-010`, que no existe todavía. Medirlas
sobre texto crudo daría un número falso.

## Evidencia con la que se aceptó

| Requisito | Estado |
|---|---|
| Android de gama media o baja | **Cumplido** — POCO X5 Pro 5G, Android 12 / API 31, hardware físico |
| **Pixel 8 / API 36** | **`WAIVED_BY_OWNER — residual compatibility risk accepted`** |
| Comportamiento verificado en modo avión | **Cumplido** — contrastado contra `Settings.Global.AIRPLANE_MODE_ON` y el log de radio, no declarado por el operador |
| Locale realmente utilizado y qué pasa con `es-BO` | **Cumplido** — sólo `es-US`; `es-BO` no existe y `es-ES` no estaba instalado |
| Impacto en el tamaño de distribución aceptado por el propietario | **Cumplido** — 0 B: el motor elegido no añade peso |
| Ausencia de errores sistemáticos en datos críticos | **No cumplido, y aceptado explícitamente** — los nombres de producto fallan en los tres motores |

El último punto se aceptó con una lectura precisa: **no bloquea la elección de motor**, porque
ningún motor lo resuelve. Bloquea la idea de que la transcripción alcance para precargar datos.
El propietario acepta que el reconocimiento de productos y personas se resuelve en `EVO-010`,
contra el catálogo local, y que hasta entonces la voz entrega texto y no datos.

## Revisión 2026-09-06 — locale solicitado (decisión del propietario)

La elección de motor **no cambia**: sigue siendo Android `SpeechRecognizer`. Lo
que se revisa es un punto de la política productiva derivada.

**Punto 5 revisado.** Donde decía «no puede prometer `es-BO`» —y en la práctica
`es-BO` era el primer locale solicitado—, el propietario decidió durante el gate
físico del HONOR JDY-LX3P que **el locale solicitado sea `es-US`**.

Evidencia sobre la que se decidió, de los dos únicos aparatos medidos:

| Aparato | Qué se observó con `es-US` |
|---|---|
| POCO X5 Pro 5G, API 31 | **El único** locale que llegó a transcribir |
| HONOR JDY-LX3P, API 36 | El sistema lo **declara** soportado y lo intenta primero; falla con error 13 porque el modelo no está descargado |

Qué **no** cambia, y sigue siendo obligatorio:

- la lista de respaldo se conserva **completa** y se recorre intentando;
- se sigue **observando el resultado real** en vez de creerle a la consulta
  (`EVO-009-REQ-014`), reforzado por el HONOR: declaró `es-US` y `es-ES` y ambos
  fallaron;
- la interfaz sigue mostrando **solicitado** y **utilizado** por separado, y
  avisa cuando difieren;
- `es-US` es el **primer intento**, no una promesa;
- `es-BO` permanece en la lista, en segunda posición, porque es el país del
  usuario.

`RISK-023` sigue abierto: dos teléfonos no describen el universo de aparatos.

## Qué invalidaría esta decisión

Cualquiera de los disparadores de reconsideración de Whisper, o evidencia en API 36 de que el
reconocimiento no funciona. En ese caso este ADR se revisa; no se sustituye el motor sin ADR.
