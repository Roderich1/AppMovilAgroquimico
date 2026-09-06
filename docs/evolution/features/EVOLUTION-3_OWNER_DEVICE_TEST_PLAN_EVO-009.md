# EVO-009 — Plan de prueba en teléfono para el propietario

## Qué se prueba

La pantalla **`Ingresar datos por voz`** de Agrocuentas: hablar, ver el texto,
corregirlo y entregarlo.

**Lo que esta pantalla NO hace, y no hay que buscarlo:** no registra compras, ni
pagos, ni aplicaciones; no cambia el inventario ni las cuentas; no reconoce los
nombres de los productos. `ADR-002` midió 5 de 17 productos correctos, y
resolverlos contra el catálogo local es trabajo de `EVO-010`, que **no existe
todavía**. Aquí la voz entrega **texto**, y punto.

## Aparato

| Campo | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G (el mismo del benchmark) |
| Android | 12 / API 31 |
| Pixel 8 / API 36 | `WAIVED_BY_OWNER — residual compatibility risk accepted`. **No se prueba y no se declara probado** |

Si aparece un aparato API 36, esta misma lista se ejecuta como **regresión
adicional**, no como condición.

## Instalación

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Se usa el APK **debug** porque el de release queda sin firmar mientras no exista
`android/key.properties`, y un APK sin firmar no se instala.

## Antes de empezar

1. Desinstala cualquier versión anterior, para que el permiso de micrófono se
   pida de cero.
2. Abre **Operaciones** y comprueba que aparece la tarjeta
   `Ingresar datos por voz`.
3. Ten a mano una frase larga para dictar, por ejemplo:
   *«quiero registrar una compra de cincuenta litros de producto a ciento
   ochenta bolivianos el litro para el chaco grande»*.

## Cómo anotar

Para cada punto: **esperado / observado / veredicto** (`OK`, `FALLA`, `DUDOSO`) y
una nota. Si algo falla, anota lo que se ve en pantalla, incluido el `Código:`
que muestra el recuadro de error. **No hace falta copiar lo que dictaste**, y es
mejor que no lo hagas: el objetivo es que las frases no viajen a ninguna parte.

## Los veinte puntos

| # | Prueba | Qué hacer | Qué debe pasar |
|---:|---|---|---|
| 1 | **Permiso** | Toca el micrófono por primera vez | Android pide permiso **en ese momento**, no al abrir la app. Antes se ve el aviso de privacidad |
| 2 | **Escucha** | Concede el permiso | Aparece `Escuchando` y el aviso `Micrófono abierto`. El botón se vuelve rojo con un cuadrado |
| 3 | **Parciales** | Habla despacio | El texto aparece **mientras hablas**, en el recuadro `Escuchando (todavía puede cambiar)`, separado del campo de abajo |
| 4 | **Sesión continua** | Habla, calla dos segundos, sigue hablando | El micrófono se vuelve a abrir solo y el texto **se suma**. Nada de lo anterior se pierde |
| 5 | **Edición** | Toca el campo de texto y corrige una palabra | Se puede escribir, borrar y corregir. Aparece `editado a mano` |
| 6 | **Seguir hablando** | Tras corregir, pulsa `Seguir hablando` y dicta más | Lo nuevo se añade **al final**. **Tu corrección sigue ahí** |
| 7 | **Detener** | Pulsa `Detener` | El micrófono se cierra, el indicador desaparece y el texto queda editable |
| 8 | **Descartar** | Pulsa `Descartar` | El campo queda vacío, el estado dice `Sesión descartada` y el micrófono está libre |
| 9 | **Modo avión** | Activa modo avión **desde los ajustes del sistema** y dicta | La pantalla dice `Modo avión: activado`. Si transcribe, después dice `Comprobado: aquí se transcribió con el modo avión activado`. Si **no** transcribe, muestra un error accionable — ambas cosas son resultados válidos, anota cuál pasó |
| 10 | **Idioma** | Mira el bloque de idioma en cualquier momento | Siempre se ven **dos** líneas: `Idioma solicitado: es-BO` y `Idioma utilizado: …`. Lo esperable aquí es que el utilizado **no** sea `es-BO` |
| 11 | **Error por idioma** | Si el teléfono no tiene ningún español, o quitas el paquete de idioma | Estado `Sin español disponible en el motor`, con instrucciones. **No debe descargar nada por su cuenta** |
| 12 | **Background / foreground** | Con el micrófono abierto, pulsa Inicio; vuelve a la app | El micrófono **se suelta al salir**. Al volver, el texto sigue ahí y el micrófono está cerrado |
| 13 | **Navegación** | Con el micrófono abierto, pulsa Atrás | Vuelve a Operaciones. El micrófono se libera: el punto rojo de grabación del sistema **debe desaparecer** |
| 14 | **Rotación** | Gira el teléfono con texto en pantalla | No se pierde el texto, no hay recuadros rojos ni contenido cortado. Se puede desplazar |
| 15 | **Fuente 130 %** | Ajustes de Android → tamaño de fuente al máximo; vuelve a la pantalla | Todo sigue legible y alcanzable desplazando. Sin texto cortado ni botones inaccesibles |
| 16 | **Texto largo** | Dicta varias frases hasta llenar la pantalla | El campo crece, la página se desplaza y los botones siguen alcanzables |
| 17 | **Silencio** | Toca el micrófono y no digas nada | **No debe inventar texto.** Tras unos intentos deja de escuchar solo y no se queda en bucle |
| 18 | **Ruido** | Dicta con ruido de fondo | Puede equivocarse —es esperable—, pero no debe colgarse ni proponer nada |
| 19 | **Liberación del micrófono** | Tras cada salida: detener, descartar, entregar, atrás, Inicio | El indicador de micrófono del sistema (punto/icono en la barra superior) **no debe quedarse encendido** |
| 20 | **Sin crash ni ANR** | Durante toda la sesión | Ninguna pantalla en blanco, ningún «la aplicación no responde», ningún cierre inesperado |

## Pruebas incómodas adicionales

| # | Prueba | Qué debe pasar |
|---:|---|---|
| 21 | **Denegar el permiso** | Estado `Permiso de micrófono denegado`, explicación clara y **el campo de texto sigue funcionando**: se puede escribir y pulsar `Usar este texto` |
| 22 | **Denegar para siempre** | Aparece el botón `Abrir ajustes` y lleva a la ficha de la aplicación |
| 23 | **Doble toque** | Tocar el micrófono dos veces seguidas no abre dos escuchas ni duplica texto |
| 24 | **Llamada entrante** | Si entra una llamada con el micrófono abierto, se suelta y no se queda escuchando |
| 25 | **Bloqueo de pantalla** | Bloquear con el micrófono abierto lo libera |
| 26 | **`Usar este texto`** | Aparece el recuadro `Texto de la sesión listo` y dice explícitamente que **no se registró ninguna compra, pago ni aplicación**. Comprueba en Inventario y Cuentas que **nada cambió** |

## Comprobación de privacidad

| Qué | Cómo | Esperado |
|---|---|---|
| Sin permiso de red | Ajustes → Aplicaciones → Agrocuentas → Permisos | La aplicación **no tiene** permiso de Internet |
| Sin audio guardado | Explorador de archivos, carpeta de la aplicación | Ningún archivo de audio, ni antes ni después de dictar |
| Sin transcripción guardada | Cierra la pantalla y vuelve a entrar | El campo aparece **vacío**: el texto no sobrevive a la salida |

## Qué devolver

Usa `EVOLUTION-3_OWNER_DEVICE_TEST_RESULTS_TEMPLATE.md`. Incluye:

- modelo, versión de Android y si el teléfono estaba cargando;
- idioma **utilizado** que mostró la pantalla;
- qué pasó en modo avión (punto 9), que es el único que decide si aquí funciona
  sin conexión;
- cualquier `Código:` que aparezca en un error;
- veredicto por punto.

**No copies las frases dictadas.** Con el número de punto y el código basta.

## Qué NO habilita esta prueba

Aprobar estos veintiséis puntos deja `EVO-009` listo para `VERIFIED`. **No**
aprueba `EVO-010` ni ninguna operación por voz, y **no** cierra el gate del
Pixel 8 / API 36, que sigue `WAIVED_BY_OWNER`.
