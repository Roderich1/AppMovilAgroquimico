# Prueba exploratoria de voz en el POCO con «AC F09» `c080b9a` (2026-11-08)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-08, 17:03–17:50 (hora del teléfono, `America/La_Paz`) |
| Teléfono | POCO X5 Pro 5G `22101320G`, Android 12 (MIUI V140), `arm64-v8a`, 7,0 GiB |
| APK | `agrocuentas-f09-c080b9a-arm64-v8a-profile.apk`, SHA-256 `4dd970139d7babc34799991206460decf7e7f862bf20d1d85f1d11cdc100f181`, código `c080b9ae6f6e878ff30c4b05f75ec04c7e5969ac`, paquete `.f09` |
| Configuración | Vosk 0.3.75 + `vosk-model-small-es-0.42`; revisión whisper.cpp + `ggml-base-q5_1` (base); tope de revisión 5 000 ms; evidencia compilada pero **consentimiento no aceptado** (0 dictados guardados) |
| Quién dictó | Roderich, con datos sintéticos de la DEMO (`agricultor4`, titular sintético) |
| Naturaleza | Exploratoria. **No es #12**, no usa frases reservadas, no cierra #17 |

Estos resultados son de **esta** versión. Las correcciones posteriores no los convierten en aprobados: los casos se repiten con la versión nueva y se anotan aparte.

Este documento no contiene transcripciones. Los fallos se describen por su efecto.

## Preparación (comprobación técnica)

- Instalación nueva de `.f09` (no existía), sin tocar otras instalaciones. Activación en línea por el túnel DEMO; siembra DEMO con `f09emu.sh sembrar agricultor4`.
- Motor y modelos incluidos en la APK; Vosk copiado al teléfono; comprobación de capacidad `review-ok`.
- Whisper base **cargado** una vez (137 ms) y **ejecutado** en todas las frases.
- Todo el recorrido de voz, sin red: modo avión activado, Wi‑Fi y datos apagados, sin red por defecto.

## Resultados

| Caso | Dictado de Roderich | Comprobación técnica | Resultado |
|---|---|---|---|
| A. Compra | Sí, varias frases | 12 frases revisadas: 8 con el texto de Whisper y 4 con el de Vosk porque Whisper leía otras cifras; revisión entre 3,1 y 4,1 s. Ninguna compra creada, borrador descartado | **Falla.** El precio de la primera frase se transcribió mal y el intérprete lo metió en el nombre del producto (producto ambiguo, precio vacío). El proveedor quedó ambiguo porque la siembra lo llama «Agroinsumos DEMO (sintético)». No se interpretaron la persona dicha con «va para …», la palabra «proveedor» mal transcrita ni un precio dicho por separado |
| E. «Un litro y medio» y pausa | Sí | Las dos líneas quedaron con su producto y su cantidad | Cantidad 1,5 y continuación tras la pausa: **pasan**. El precio de la línea 1,5 L quedó a confirmar (unitario o total) |
| F. Aplicación | Sí, 3 frases | Las 3 con el texto de Whisper. Chaco, dueño, área y dos productos correctos. El tercer producto se bloqueó por falta de stock del titular, que es lo correcto | Interpretación **pasa**. Registro **no ejecutado**: borrador descartado y aplicaciones sin cambios. Observaciones: el déficit se mostraba como «quedaría 0 L», y elegir otra vez la misma opción mostraba «Corregido a mano» |
| G. Planificación | Sí | 10 frases: 9 con el texto de Whisper y 1 revisión anómala descartada. Chaco, área, una línea con dosis y necesidad correctas | **Falla** en la transcripción de un producto. Las frases con órdenes («selecciona», «elimina») no cambian nada, como está diseñado. La dosis de la línea sin producto mostraba el texto oído. El micrófono se liberó al pasar a segundo plano. Plan **no creado** |
| B, C, D | — | — | No ejecutados |

## Hallazgos que pasan a corrección (decisión del autor: mantener Whisper base)

1. La cláusula de precio acaba dentro del nombre del producto cuando no se oye el conector.
2. «Va para …» o «es para …» no se reconoce como la persona que recibe la compra.
3. «Proveedor» mal transcrito no se reconoce.
4. Un precio dicho por separado no se aplica, ni se avisa.
5. Cuando Vosk y Whisper discrepan en una cifra, se conserva Vosk en silencio.
6. El déficit de existencias se muestra como «quedaría 0 L».
7. Confirmar la misma opción se etiqueta «Corregido a mano».
8. La dosis de una línea sin producto muestra el texto oído en vez del valor.
9. No hay ninguna indicación de cómo corregir cuando la voz no cambia nada.
10. Error del guion: el proveedor sintético se llama «Agroinsumos DEMO (sintético)».

Mejora independiente, no se implementa en esta etapa: órdenes de edición por voz («selecciona», «elimina», «borra»).
