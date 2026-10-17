# #97: títulos legibles con la fuente al 100 % y al 130 % (A1-F)

Refs #97. Trazabilidad: RNF-08, INT-01.

**Origen:** la evaluación de compatibilidad F10 dio **A1-F = no compatible** por M8 («sin textos cortados»). Fue en el POCO X5 Pro 5G, con Mobile `dff6802`, el 2026-10-17 a las 04:35Z ([F10_COMPATIBILIDAD_MOBILE.md](F10_COMPATIBILIDAD_MOBILE.md)). Esa evaluación se conserva con su versión. Este cambio corrige la causa; **no repite la evaluación**, que queda para F10 sobre la versión candidata.

## Identidad de la ejecución

| Elemento | Valor |
|---|---|
| Fecha | 2026-10-17 |
| Rama | `fix/f10-legibilidad-97`, apilada sobre `feat/f04-modo-ui` (`7ac7153`) porque toca el mismo formulario |
| Commit verificado | `3257ae3` |
| Entorno | Windows 11 Home 10.0.26200, Flutter 3.47.2 |
| Tipo de prueba | Widgets (`flutter test`), **sin dispositivo** |
| Ejecución | Sesión A de Claude Code, por delegación técnica |

## Causa y corrección

| Pantalla | Causa | Corrección |
|---|---|---|
| «Sincronización» (y cualquier `PageFrame` con acción) | Título y acción iban en una fila y la acción dejaba al título sólo el ancho sobrante: «Sincronizació / n» | Título y acción en un `Wrap`. El título conserva su ancho y, si no caben los dos, la acción baja a la línea siguiente. El subtítulo va debajo |
| «Nueva compra» | «Confirmar» compartía la barra superior con el título: «Nueva com…» al 130 % | «Confirmar compra» va en una barra inferior fija, como en Aplicación y Planificación |
| «Asignaciones» de la compra | Persona y cantidad en una fila 3:2: «Titular F1…» | Por debajo de 480 dp, la persona va arriba a todo el ancho y la cantidad debajo |

No se oculta ninguna acción, no se acorta ningún nombre y no se limita la escala del texto.

## Prueba: `test/f10_legibility_97_test.dart` (8 casos)

- **Configuraciones:** 360 y 392 dp (ancho del POCO), fuente 1,0 y 1,3.
- **Comprobaciones:**
  - «Sincronización» y «Sincronizar ahora»;
  - «Nueva compra», «Confirmar compra» y el nombre «Titular F1 Mamani» elegido en una asignación.
- **Criterio de cada texto:**
  - una sola línea real (cajas de selección con un único `top`);
  - sin puntos suspensivos (`didExceedMaxLines` falso);
  - la acción dentro del ancho de la pantalla.
- **Fuente:** se mide con **Roboto** del SDK de Flutter (`bin/cache/artifacts/material_fonts`).
  - Con la fuente de prueba por defecto, cada glifo es un cuadrado del tamaño de la letra: «Sincronización» mide 336 px a 24 px y no cabe en ninguna disposición a 360 dp.
  - Si no encuentra Roboto, la prueba falla con un mensaje; no se omite.

| Sobre | Resultado |
|---|---|
| `7ac7153` (antes de la corrección; archivo temporal copiado y borrado) | **1 pasa, 7 fallan**: Sincronización partida en 3 de 4 configuraciones; «Nueva compra» truncada al 130 %; sin «Confirmar compra». La única que pasaba es Sincronización a 392 dp al 100 % |
| `3257ae3` | **8 de 8 pasan** |
| `3257ae3`, suite completa | `dart format` 0 cambiados · `flutter analyze` sin issues · `flutter test` **1097 pasan, 2 omitidas, 0 fallos** |

Cambio en una prueba de F04: el botón de confirmar la compra deja de ser un `TextButton` en la barra superior y pasa a `FilledButton`. `personal_mode_flows_test` lo busca ahora como `ButtonStyleButton` por su clave; lo que comprueba no cambia.

## Límites

- **Sin dispositivo.** En el POCO, «Sincronización» se partía también al 100 %, con la fuente del sistema de MIUI. Con Roboto, a 392 dp y al 100 %, no se reproduce, así que la fuente del teléfono no está representada en la prueba. **Hace falta la comprobación en el POCO al 100 % y al 130 %** antes de cerrar #97 (criterio de cierre propuesto en la issue).
- La matriz de compatibilidad A1-F de F10 no cambia con este PR. Se vuelve a medir en F10, sobre la versión candidata.

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-17.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
