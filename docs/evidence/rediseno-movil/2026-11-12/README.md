# Rediseño móvil · bloque 1 (estilos compartidos y compra) — evidencia

- **Fecha real:** 2026-11-12 (UTC−4), sesión de trabajo del rediseño.
- **Rama / worktree:** `feat/rediseno-movil` en `_wt/RDM-MOB`, desde `01b2576`. Sin push.
- **Commits:** `2b4e2ec` (tema, componentes, compra), `1214c2e`/`59037b6` (pruebas y ajustes), `e68a200` (importe con letra ampliada), `2d6aa0d` (script), `15bc23e` (margen bajo la barra de pasos, capturas 2.5).
- **Dispositivo:** emulador `sdk_gphone16k_x86_64` (Pixel_8), API 36, densidad 420, 1080×2400. El POCO no estaba disponible.
- **Flutter:** 3.47.2.
- **Datos:** exclusivamente sintéticos, en un entorno propio (`tool/rediseno/rdm_env.sh`: contenedor `agro_rdm_pg` 15436, API 3370, túnel temporal cuyo origen no se publica, paquete `.rdm` «AC RDM», cuenta `agricultor15` «Rosa Vargas (sintética)»). No se tocó la DEMO (`.demo`, 3330/5190) ni el entorno ET2 (`.et1`, 15434/3350).

## Qué compilación aparece en cada captura del emulador

| Capturas `emulador/` | Compilación instalada en `.rdm` |
|---|---|
| `c01`–`c19` | `2b4e2ec` (el «+cambios» de su rótulo eran sólo pruebas sin commit; `lib/` = `2b4e2ec`) |
| `d01`–`d03` | `e68a200`, **sin** modelos de voz (por eso `d03` dice «La voz no está disponible en este teléfono»: es el estado de error real) |
| `d04`–`d08` | `2d6aa0d`, con los modelos de voz copiados de `_wt/F09-UNI` y verificados contra su manifiesto (15 archivos, 0 diferencias de SHA-256). APK SHA-256 `68eff3c3aee87e2ea846bce095e618c0d9d3f8ddbf81529a64e2df8ac05e9ca9` |

`15bc23e` sólo añade un margen de 8 dp bajo la barra de pasos (verificado en `arnes/`). Su APK (SHA-256 `266a9ff2ff9385814a3e410eec16f69e0baf652f99bf2a7203d373fb93377621`, 376 MB con modelos) **no se pudo instalar**: al emulador le quedan 802 MB y la actualización pide más («Requested internal only, but not enough space»). No se borró nada para hacer sitio.

## Recorrido real en el emulador (compra manual, `c01`–`c19`)

1. Activación de `.rdm` con la cuenta sintética; titular «Rosa Vargas», modalidad compartida; PIN «Ahora no». Campaña creada desde Campañas. La contraseña de un solo uso la tecleó `demo-rica.cjs credential-adb` tras comprobar que el campo enfocado era de contraseña; una captura tomada mientras Android mostraba su último carácter se borró en el acto y no forma parte de esta evidencia.
2. Paso 1 vacío (`c01`): coincide con la lámina 2.1. «Crear proveedor» desde el selector (`c03`) queda elegido.
3. Hoja «Producto 1» (`c04`), «Crear producto» queda elegido; con el teclado abierto el campo y los botones siguen a la vista (`c08`). 12 L × 118,50 Bs = **1.422,00 Bs** (subtotal correcto).
4. Un toque en el velo con el teclado abierto cerró la hoja: el borrador conservó producto y cantidad (`c13`).
5. Producto 2 con nombre largo, en kg, con datos mal escritos: «Continuar» abre su hoja con el problema arriba y el error en el campo (`c14`); al corregir, 2,5 kg × 1.234,56 Bs = **3.086,40 Bs** (`c15`). Luego pidió la persona; elegida, el paso 1 suma **4.508,40 Bs** (`c16`).
6. Paso 2 (`c17`), Atrás vuelve al paso 1 con todo y «Continuar» conserva la respuesta de pago; «Sí, pagué todo», «Efectivo» (`c18`).
7. **Doble toque** deliberado en «Confirmar compra» → «Compra guardada.» (`c19`).
8. Efectos leídos de la base local de `.rdm` (copia de sólo lectura con `run-as`): **1** compra; **2** líneas (12000 y 2500 unidades base, BOB, 11850 y 123456 centavos); **2** asignaciones a la titular; **1** pago al proveedor de **450840** centavos (4.508,40 Bs), `CASH`, pagado por la titular; **2** lotes de inventario a su nombre, sin vencimiento supuesto. Inicio muestra 4.508,40 Bs comprados y pagados.
9. Actualizar la candidata (`e68a200` sobre `2b4e2ec`, y `2d6aa0d` encima) conservó los datos (`d01`).

## Voz en el emulador (`d02`–`d08`)

Integración de estados con el **motor real** de la compra (Whisper small, turno entero), sin dictado de una persona: el micrófono del emulador no permite medir reconocimiento.

- Panel listo, sin abrir el micrófono (`d02`); permiso pedido sólo al pulsar «Hablar», con «Abriendo el micrófono…» y «Cancelar» (`d04`); concedido «sólo esta vez».
- «Escuchando · Micrófono encendido», «Terminar» y «Cancelar», sin texto parcial (`d05`).
- «Procesando tu voz · Micrófono apagado», barra indeterminada, «Cancelar», «Lo que ya escribió a mano se conserva.», sin transcripción (`d06`).
- Resultado con silencio: el panel se cierra y el aviso dice «No cambió el formulario: no se reconoció nada que completar.» con «Dictar más» (`d07`).
- «Cancelar» durante el procesamiento: «Dictado cancelado: el formulario no cambió.»; 20 s después el mensaje seguía igual y el formulario sin cambios (el resultado tardío no se aplicó) (`d08`).
- No se guardó audio ni transcripción en ningún archivo, registro o captura. La compilación no es de evaluación (sin `AGRO_VOICE_EVIDENCE`).

**No verificado:** precisión del reconocimiento con voz humana en este diseño (pendiente de un teléfono físico).

## Arnés (`arnes/`, `tool/rediseno/capturas_arnes_test.dart`)

La app real sobre una base sintética, con las tipografías empaquetadas, a 390×844 dp (el tamaño de las láminas) y también a 130 % y 200 % de letra y a 360 dp con 130 %. Sin desbordamientos en ninguna variante. `2.5_*` usa un turno **sintético** (texto inyectado por el puerto falso): muestra la presentación de la revisión, no la precisión.

## Comparativas (`comparativas/`)

Láminas del prototipo renderizadas a 390×844 a 2× (Edge sin interfaz, sin el motor del lienzo) frente al arnés y al emulador a la misma altura. «Antes» son las capturas del 2026-11-11 de la rama `evidence/ui-actual-2026-11-11` (`c99123b`).

## Pruebas

- `flutter analyze` (proyecto entero): sin avisos.
- Suite completa (`flutter test`, 02:13–02:16) sobre el árbol que se commiteó como `1214c2e`: **2.984 pasan, 3 omitidas, 1 falla**: `f08_prev_01_previo_ui_test.dart` «Decidir sobre una copia sin resolver…» (respaldos, no tocado). Aislado pasa 8/8; coincide con la intermitencia conocida (worktree `F08-PREV-01-FLAKY`).
- Tras `e68a200` y `15bc23e`: pruebas de compra, voz en compra, altas en contexto, legibilidad, compatibilidad #129, pago y propio (105 + 30) pasan.
- 21 archivos de prueba adaptados: cambia cómo se llega a los campos (`test/support/purchase_form_driver.dart`) y los textos renombrados; no lo que se comprueba.

## Limitaciones declaradas

- Candidata instalada = `2d6aa0d`; `15bc23e` sólo en APK (falta de espacio en el emulador).
- Letra ampliada y pantalla estrecha verificadas en el arnés, no cambiando la escala del emulador compartido.
- Sin conexión: no se probó en este bloque (la compra no cambia de comportamiento sin red; no se tocó la sincronización).
- Hallazgo aparte, **no corregido** (reglas de voz, fuera del rediseño): tras «Deshacer último dictado» con el precio en revisión, el aviso dice «Se conservó lo que editó después (línea 1: moneda)» y la tarjeta sigue con «Por voz», sin que la persona tocara la moneda (`arnes/2.1_paso1_lleno.png`). Viene de `planVoiceUndo` y `voiceFields`, que esta rama no cambia; no se comprobó todavía si la base `01b2576` muestra lo mismo.
