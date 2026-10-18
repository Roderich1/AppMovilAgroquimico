# #129: legibilidad con fuente grande en pantallas estrechas (A4-F)

Refs #129, #97. Trazabilidad: INT-01, RNF-08, RU-09, RU-13.

**Origen:** la serie 2 de la evaluación de compatibilidad F10 (protocolo v1.3 `9bfcad2` §2, suplemento `F10_SUPLEMENTO_BASE_2026-10-18.md`) dio **A4-F = no compatible** por M8 («sin textos cortados») en el HONOR JDY-LX3P (720×1612 a 320 dpi), con Mobile `ad5b43d`, el 2026-10-18 ([F10_COMPATIBILIDAD_MOBILE_A4.md](F10_COMPATIBILIDAD_MOBILE_A4.md), MOB #129). Esa evaluación se conserva tal cual con su versión. Este cambio corrige la causa; **no repite la evaluación**: la repetición física de M8 queda para el POCO (A1/A1-F, #97) mientras sea el equipo conectado, y para el HONOR (A4-F) cuando vuelva a estarlo.

## Identidad de la ejecución

| Elemento | Valor |
|---|---|
| Fecha | 2026-10-18 |
| Rama | `fix/f10-compat-129-presentacion`, sobre `origin/main` `1a29869` (código = `ad5b43d`) |
| Commit verificado | `27c4654` (corrección y prueba) |
| Entorno | Windows 11 Home 10.0.26200, Flutter 3.47.2 |
| Tipo de prueba | Widgets (`flutter test`), **sin dispositivo** |
| Ejecución | Sesión C de Claude Code, por delegación técnica (encargo de Roderich Rendón del 2026-10-18) |

## Alcance

Sólo presentación, accesibilidad y disposición de controles. No cambian cantidades, cálculos, fechas, campañas, permisos, sincronización, respaldos ni voz. No se desactiva `TextScaler`, no se limita globalmente el texto ampliado, no se reducen importes ni se elimina información para obtener un PASS.

## Causa y corrección

| Dónde | Causa | Corrección |
|---|---|---|
| Campo «Producto» de la línea de compra (`AdaptiveEntityPicker`) | El valor elegido se pintaba con `maxLines: 1` y puntos suspensivos: «DSV-002 Producto si…»; el nombre completo sólo se leía en la cabecera de la línea | El valor salta de línea por palabra y el campo crece en alto. Se muestra el nombre completo; nada se abrevia ni se oculta. El `Semantics` del campo ya exponía etiqueta y valor completos |
| Cabecera «Productos (n)» de la compra | Título en `Expanded` junto al botón «Agregar producto»: el botón tomaba su ancho natural y al título le quedaba el resto, insuficiente para la palabra: «Producto / s (1)» | `SectionHeading` (nuevo, en `widgets/common.dart`): título y acción en un `Wrap` a todo el ancho, como el título de `PageFrame` (#97). El título conserva su ancho y la acción baja de línea si no caben los dos |
| Encabezados del Inicio («Inventario proyectado», «Aplicaciones recientes», «Principales saldos» con «Ver todos/todas») | Mismo patrón `Expanded` + botón | `SectionHeading` |
| Tarjetas de importes del Inicio («Pagado proveedores») | Dos columnas fijas por debajo de 600 dp: en 360 dp con la fuente al 130 % la etiqueta disponía de ~102 dp y «proveedores» se partía: «Pagado pr / oveedores» | El número de columnas se decide midiendo (`measureText`, `TextPainter`) la palabra más larga de las etiquetas con la fuente y la escala **reales** del dispositivo, más el margen de la tarjeta, el relleno, el icono y la separación. Si a una tarjeta no le cabe su palabra más larga, se quitan columnas hasta una. Al 100 % en 360 dp siguen siendo dos columnas; al 130 % pasa a una, con etiqueta e importe enteros y a la izquierda |
| Botón «Nuevo» sobre importes | Al 130 % la cuarta tarjeta («Terceros por cobrar», columna derecha) quedaba bajo el botón flotante hasta desplazar | Consecuencia de lo anterior: con una columna los importes van a la izquierda y el botón, a la derecha, no los cubre. La reserva inferior de `ContentInsets` (UIBUG-008/009) sigue dejando el último elemento por encima del botón al final del desplazamiento |
| Barra inferior («Operaciones») | Con cinco destinos en 360 dp el destino mide 72 dp y «Operaciones» en `labelMedium` (12 sp) no cabe ni al 100 %: «Operacione / s». La escala de la barra estaba fijada al 100 % (UIBUG-017), lo que bastaba en el POCO (78,5 dp por destino) pero no en el HONOR | Las etiquetas siguen la escala del sistema (hasta el 130 % que `NavigationBar` admite por sí misma) y sólo se reducen lo justo para que la etiqueta más larga quepa en una línea en el ancho real de su destino (`width / 5 − 8 dp`), medida con la fuente del dispositivo. En 360 dp queda en ~11 sp; en 392,7 dp al 100 % no cambia (12 sp); en pantallas anchas crece con el sistema. No se acorta el nombre de ninguna sección y cada destino conserva su icono |

## Prueba: `test/f10_compat_129_presentacion_test.dart` (12 casos)

- **Configuraciones** (representadas en el `MediaQuery` con `devicePixelRatio`, `physicalSize` y `padding` reales, no sólo un ancho lógico):
  - HONOR JDY-LX3P: 720×1612 físicos, DPR 2 → 360×806 dp.
  - POCO X5 Pro: 1080×2400 físicos, DPR 2,75 → 392,7×872,7 dp.
  - Insets: barra de estado 24 dp y barra de navegación de tres botones 48 dp en ambos (valores habituales de Android; **pendientes de confirmar con las métricas reales del POCO por la sesión A**, ver Límites).
  - Fuente **1,0 y 1,3** (criterio del protocolo, A4/A4-F) y **1,45** (ajuste propio del HONOR) como exploración, no como criterio.
- **Datos:** nombres del dataset DS-V («DSV-002 Producto sintético», «Proveedor DSV 1», «Campaña DSV S2») y una compra de 123.456,00 Bs para que las tarjetas muestren cifras con miles.
- **Comprobaciones:**
  - «Nueva compra»: el valor del campo «Producto» tras elegir «DSV-002 Producto sintético» no se trunca (`didExceedMaxLines` falso) y ninguna de sus palabras se parte entre dos líneas (las cajas de selección de cada palabra tienen un único `top`); «Productos (1)» y «Agregar producto» sin palabras partidas y el botón dentro de la pantalla.
  - Inicio dentro del `AppShell`: las cinco etiquetas de tarjeta y los tres encabezados sin palabras partidas; las cinco etiquetas de la barra inferior en una sola línea; ningún importe visible sin desplazar se solapa con el rectángulo del botón «Nuevo»; tras desplazar hasta el final, la última tarjeta queda por encima del botón.
- **Fuente:** Roboto versionada en `test/fonts/` (Apache 2.0), como en #97; con la fuente de prueba por defecto cada glifo es un cuadrado y la medida no representa el teléfono.

| Sobre | Resultado |
|---|---|
| `ad5b43d` (código de `main` con `lib/` restaurado; prueba nueva copiada) | **4 pasan, 8 fallan.** Fallan: Inicio HONOR al 100 % («Operaciones» partida); Nueva compra HONOR al 130 % («Productos» partida); Inicio HONOR al 130 % («proveedores» partida); Nueva compra POCO al 130 % (campo «Producto» truncado); y los cuatro casos de exploración al 145 %. Pasan: Nueva compra al 100 % en ambos teléfonos e Inicio en el POCO al 100 % y al 130 % (coherente con la serie 1 y con la observación de A4 al 100 % en el HONOR salvo «Operaciones», que allí sí se partía) |
| `27c4654` | **12 de 12 pasan**, incluidos los de exploración al 145 % |
| `27c4654`, suite completa | `dart format` 0 cambiados · `flutter analyze` sin issues · `flutter test` **1534 pasan, 3 omitidas, 0 fallos** (todas las suites con `settle` fijo siguen pasando: no se añadió ninguna consulta SQLite a las pantallas) |

## Límites

- **Sin dispositivo.** Se mide con Roboto; las fuentes del HONOR y de MIUI no están representadas. La decisión de columnas y el ajuste de la barra inferior miden el texto con la fuente real en tiempo de ejecución, así que no dependen de Roboto, pero eso sólo lo confirma la repetición física de M8.
- **Insets supuestos.** 24 dp y 48 dp son los valores habituales; si las métricas reales del POCO (`MediaQuery.padding`) difieren, se ajustan en `_devices` de la prueba sin cambiar el criterio.
- **El botón flotante sigue flotando sobre contenido desplazable**, como define Material. Lo que se garantiza es que los importes de las tarjetas del Inicio quedan fuera de él sin desplazar en ambos teléfonos al 100 %, al 130 % y al 145 %, y que el último elemento de la página termina por encima de él. Durante el desplazamiento otros controles (por ejemplo «Ver todos») pueden pasar bajo el botón hasta seguir desplazando; no se oculta ni se mueve el botón para evitarlo.
- **Cambio de comportamiento declarado:** las etiquetas de la barra inferior dejan de estar fijadas al 100 % (UIBUG-017) y escalan con el sistema hasta donde cabe la más larga; en 360 dp se ven algo más pequeñas que antes (~11 sp frente a 12), siempre enteras.
- La matriz de compatibilidad A4-F de la serie 2 no cambia con este PR. Se vuelve a medir M8 físicamente sobre la versión candidata (POCO A1/A1-F primero; HONOR A4-F cuando esté conectado).

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-18.
- Revisión de la sesión B: pendiente.
- Revisión de Roderich Rendón: pendiente. GATE-F10 (BE #49) sigue Pending.
