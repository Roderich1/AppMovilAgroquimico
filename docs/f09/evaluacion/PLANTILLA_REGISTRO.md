# F09: plantilla de registro por toma y por sesión (#12)

- **Versión:** 2026-11-08, rama `feat/f09-c-evidencia` desde `49108ba`. **Plantilla vacía: no contiene ninguna medición.**
- **Archivo:** [`registro_tomas_PLANTILLA.csv`](registro_tomas_PLANTILLA.csv), una fila por toma. Lo lee [`metricas/f09_metricas.py`](metricas/f09_metricas.py).
- **Definiciones y umbrales:** [`PROTOCOLO_Y_UMBRALES.md`](PROTOCOLO_Y_UMBRALES.md) (copia literal de c-12). Esta plantilla no añade criterios.

## 1. Reglas de llenado

1. Un valor que no se midió se escribe `NOT_MEASURED`; una condición que no se ejecutó no tiene filas y el script la informa como `NOT_RUN`. **Nunca** se deja un cero en lugar de un dato ausente.
2. Se llena **antes de corregir nada a mano** lo que la voz propuso (columnas `campo_*`), comparado con la ficha cuya huella se fijó antes (D1: la referencia es la ficha, no lo confirmado).
3. **No se copia la frase dictada ni la transcripción** en este archivo ni en `docs/evidence/`, salvo que el autor decida otra cosa (ver A10 del protocolo). Si la app recogió evidencia con consentimiento, se anota sólo su `id` local en `evidencia_app_id`.
4. Errores de **transcripción** y de **interpretación** se separan en `causa_errores`: el motor oyó mal (transcripción), o el texto contenía el dato y el intérprete lo leyó mal (interpretación), o ambos. Si no se puede saber, se deja vacío y el script lo cuenta como `sin_causa`.
5. Teléfono y condición nunca se mezclan en una fila. Una toma en el emulador no sustituye a un teléfono (A13).

## 2. Columnas de `registro_tomas_PLANTILLA.csv`

| Columna | Qué se anota | Valores |
|---|---|---|
| `toma_id` | Identificador único de la toma | texto |
| `sesion_id` | Sesión de medición (enlaza con §3) | texto |
| `fecha_hora_local` | Fecha y hora real, America/La_Paz | `aaaa-mm-dd hh:mm` |
| `participante` | Código seudónimo; nunca el nombre | texto o vacío |
| `telefono` | `POCO X5 Pro`, `HONOR JDY-LX3P` o `HOST` (sólo escenarios sin confirmación) | texto |
| `modelo_dispositivo` | `getprop ro.product.model` | texto |
| `android_version` | `getprop ro.build.version.release` | texto |
| `apk_sha256` | SHA-256 del APK instalado | hex |
| `commit` | SHA completo del código del APK | hex |
| `motor` | `local` o `android` | texto |
| `modelo_motor` | Por ejemplo, el modelo Vosk y su versión | texto |
| `segunda_pasada` | `si`, `no` | texto |
| `modelo_segunda_pasada` | Modelo de la segunda pasada (small o base: A2) | texto |
| `condicion` | `tranquilo`, `ruido` (D4); `silencio_sin_voz`, `ruido_sin_voz` (rechazo); `sin_confirmacion` (escenarios de escritura) | texto |
| `escenario` | Sólo con `sin_confirmacion`: `cancelar`, `no_hablar`, `microfono_denegado`, `resultado_tardio` | texto |
| `fuente_ruido` | Fuente y descripción, registrada **antes** de ejecutar (D4) | texto |
| `nivel_ruido` | Medido con instrumento, o `NOT_MEASURED` (D4: sin cifras supuestas) | número o `NOT_MEASURED` |
| `modo_avion` | `si`, `no`, verificado antes de la toma | texto |
| `ficha_id` | Identificador de la ficha del holdout (o de la muestra de rechazo o del escenario) | texto |
| `operacion` | `compra`, `aplicacion`, `planificacion` | texto |
| `audio_id` | Sólo si hubo grabación con el consentimiento específico de D6; si no, vacío | texto |
| `duracion_audio_ms` | Duración del habla | entero o `NOT_MEASURED` |
| `primer_parcial_ms` | Desde el inicio del habla hasta el primer texto parcial | entero o `NOT_MEASURED` |
| `final_ms` | Desde «Detener» hasta que el texto llega al borrador | entero o `NOT_MEASURED` |
| `segunda_pasada_ms` | Tiempo de la segunda pasada | entero o `NOT_MEASURED` |
| `estado_motor` | `ok`, `vacio`, `error`, `cancelado`, `timeout` | texto |
| `texto_aceptado` | Sólo en rechazo: `si` si llegó algún texto al borrador | `si`, `no` |
| `campo_producto` · `campo_cantidad` · `campo_unidad` · `campo_parcela_o_persona` | Por tipo de campo, frente a la ficha y **antes de corregir** | `correcto`, `incorrecto`, `falta`, `no_esperado`, `NOT_MEASURED` |
| `campos_indebidos` | Campos que la ficha no espera y la voz añadió (D1, aparte) | entero |
| `causa_errores` | `tipo:causa` separados por `;` (por ejemplo `cantidad:interpretacion`) | `transcripcion`, `interpretacion`, `ambos` |
| `campos_corregidos` | Campos tocados a mano para llegar al borrador correcto | lista separada por `;` o vacío |
| `resultado` | `confirmado`, `descartado`, `fallido` | texto |
| `escrituras_sin_confirmacion` · `sobrescrituras` | Sólo con `sin_confirmacion`: conteos de escrituras de negocio y de ediciones sobrescritas (umbral 0) | entero o `NOT_MEASURED` |
| `evidencia_app_id` | `id` de la fila de `voice_evidence` en el teléfono, si se recogió con consentimiento | entero o vacío |
| `observaciones` | Lo que no cabe en otra columna, **sin la frase dictada** | texto |

## 3. Registro por sesión (no lo calcula el script)

Una tabla por teléfono y sesión, en el informe de evidencia:

| Dato | Umbral de c-12 | Cómo se registra |
|---|---|---|
| Memoria pico total con los dos motores cargados | ≤ 1,2 GB | Valor y método, o `NOT_MEASURED` |
| Estabilidad | 0 caídas, ANR u OOM en 30 sesiones consecutivas | Sesiones contadas, incidentes, o `NOT_RUN` |
| Térmico y batería en 10 min de uso repetido | Sin umbral: registro obligatorio | Valores y método, o `NOT_MEASURED` |
| Modo avión desde una instalación limpia | Sí | `si` / `no` / `NOT_RUN`, con cómo se verificó la red |
| Huellas fijadas antes de la primera toma | — | `fingerprints.py` (ver `FRASES_Y_HOLDOUT.md` §3) |
| Configuración y versión de cada motor (D6) | — | Texto |

## 4. Cálculo

```
python -I -B docs/f09/evaluacion/metricas/f09_metricas.py REGISTRO.csv --json resultado.json
```

El script separa por teléfono, condición y motor; informa numerador, denominador y tamaño del conjunto junto a cada porcentaje; conserva `NOT_MEASURED` y `NOT_RUN`; y declara el método de percentil (A7). Sus pruebas usan sólo [datos sintéticos](metricas/datos_sinteticos/tomas_SINTETICAS.csv), marcados como tales.
