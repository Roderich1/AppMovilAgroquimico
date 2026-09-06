# Evidencia de dispositivo — EVOLUTION-2

Capturas del gate Pixel 8 de `EVO-004/005/006`, tomadas sobre el AVD `Pixel_8`
(`emulator-5554`, `sdk_gphone16k_x86_64`), Android 16 / API 36, 1080 × 2400, 420 dpi, con el
dataset determinista de [`36_UI_AUDIT_DATASET`](../../../docs/36_UI_AUDIT_DATASET.md)
regenerado por `tool/ui_audit_push.sh`.

El recorrido completo, con resultados y gates, está en
[`EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md` §8](../../../docs/evolution/features/EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md).

## Recorrido normal

| Captura | Qué demuestra |
|---|---|
| `EV2-01-inicio.png` | Inicio con lecturas tipadas: inventario, saldos y campaña activa |
| `EV2-02-operaciones.png` | La tarjeta "Reportes" en Operaciones |
| `EV2-03-reportes.png` | Los cinco reportes, filtros y formatos; barra inferior en "Operaciones" |
| `EV2-04-atras-a-operaciones.png` | Atrás devuelve a Operaciones |
| `EV2-05-boton-exportar.png` | Aviso de datos sensibles y ruta real de Android en pantalla |
| `EV2-06-aviso-sensible.png` | Confirmación explícita antes de escribir |
| `EV2-07-guardado.png` | Nombre y carpeta del archivo generado |
| `EV2-08-inventario-csv.png` | Mismo reporte en CSV |
| `EV2-09-costo-producto-filtros.png` | Filtro de campaña con la campaña activa preseleccionada |
| `EV2-12-selector-persona.png` | Lista de personas con rol, ñ y tildes |
| `EV2-13-persona-elegida.png` | Nombre largo recortado con elipsis; botón habilitado |
| `EV2-14-estado-cuenta-guardado.png` | Estado de cuenta exportado |
| `EV2-15-colision.png` | Segunda exportación del mismo día: `… (2).csv` |
| `EV2-16-intento-cancelar.png` | Estado "Generando…" con barra de progreso y Cancelar |
| `EV2-17-cancelado.png` | Tras cancelar: sin archivo nuevo y sin temporal |

## Los archivos, abiertos en el teléfono

| Captura | Qué demuestra |
|---|---|
| `EV2-18-pdf-en-visor.png` | PDF de inventario en el visor de Android: cabeceras, alineación, tildes, total |
| `EV2-19-pdf-multipagina-p1.png` | PDF largo, primera página |
| `EV2-20-pdf-multipagina-p2.png` | Páginas 2 y 3: cabeceras repetidas, pies numerados, total sólo al final |

## Accesibilidad y orientación

| Captura | Qué demuestra |
|---|---|
| `EV2-21-reportes-130.png` | Reportes al 130 % |
| `EV2-22-operaciones-130.png` | Operaciones al 130 % |
| `EV2-23-reportes-130-abajo.png` | Aviso y botón al 130 %, sin desbordes |
| `EV2-24-reportes-130-horizontal.png` | Horizontal + 130 %, con rail de navegación |
| `EV2-25-horizontal-boton.png` | Botón de exportar alcanzable en horizontal |
| `EV2-27-horizontal-operaciones.png` | Operaciones en horizontal |
| `EV2-28-horizontal-boton.png` | Reportes en horizontal tras corregir los desbordes |
| `EV2-30-aviso-horizontal-desplazado.png` | El aviso se desplaza y se lee entero |
| `EV2-32-aviso-horizontal-final.png` | Aviso completo con el armazón ya corregido |
| `EV2-33-aviso-horizontal-desplazado.png` | Última frase del aviso alcanzable |
| `EV2-35-guardado-horizontal.png` | Diálogo de éxito completo en horizontal al 130 % |

## Defectos encontrados en el dispositivo

Estas dos capturas son el **antes**: documentan fallos que sólo se vieron en el teléfono y que
esta misma rama corrige, cada uno con su test de regresión.

| Captura | Defecto |
|---|---|
| `EV2-10-DEFECTO-desborde-persona-47px.png` | `RIGHT OVERFLOWED BY 47 PIXELS` en el desplegable de persona: `DropdownButtonFormField` se dimensiona por su elemento más ancho y sin `isExpanded` no cabe |
| `EV2-26-DEFECTO-aviso-recortado-horizontal-130.png` | En horizontal y al 130 % el aviso de consentimiento aparecía recortado: el usuario podía aceptar sin haber podido leerlo |

Un tercer defecto —la barra inferior resaltaba "Inicio" estando en `/reportes`— se corrigió
antes de tomar `EV2-03`, comparando con `EV2-02`.
