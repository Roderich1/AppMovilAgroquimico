# Estado de la sesión C

- Dueño del worktree: proyectoagro-78 (sesión C) desde 2026-11-12 07:09
- Base incorporada: B2 (794a44b, avance rápido)

## Entregas listas

| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
|---|---|---|---|---|---|
| 4 | f8e758e | Convocatorias (`/compras-conjuntas`), Convocatoria (`/compras-conjuntas/:id`) y hoja Participar, sobre la rama F | analyze sin avisos; `e2_joint_purchase_screens_test` (16, sin adaptar), `hierarchical_navigation_test` y los 13 archivos de las entregas 1–3 (98 verdes en total) | `6.1_convocatorias*`, `6.1b_…historial*`, `6.2_convocatoria*`, `6.2b_…quien_ve*`, `6.2c_autorizar_tambien*`, `6.2d_…sin_participar*`, `6.3_participar*`, `6.3b_consentimiento*` | Ver «Entrega 4» |
| 2b | 74f5cc5 | Corrección C-2: rótulos de la tarjeta de necesidad sin «…» | ídem | `6.4_necesidad*` | — |
| 1b | 578d0c6 | Corrección C-1: Vínculos con `SegmentToggle` de B1; `BadgeTone.ok` en estados positivos (todas las pantallas de C) | analyze sin avisos; los 13 archivos de prueba de las entregas 1–3 verdes sobre B1 | todas regeneradas sobre B1 a 100/130/200 % y 360 dp | Selector aún apilado en el arnés al 100 %: solicitud 7 |
| 3 | 94a79bf | Sindicato (`union_screen.dart`, ruta `/sindicato` por cablear) y Sincronización (`/sincronizacion`, `sync_status_screen.dart`) | analyze sin avisos; `rdm_c_union_screen_test` (nueva, 4), `sync_screens_test`, `f10_mensajes_autorizacion_test`, `f10_sync_release_refresh_test`, `f10_sync_textos_confirmacion_test`, `f10_sync_version_mismatch_resume_test`, `f10_legibility_97_test`, `oe3_fab_sincronizacion_test` verdes | `1.5_sindicato*`, `7.x_sincronizacion*` | Ver «Entrega 3» |
| 2 | 7081df4 | Necesidad (`/planificacion/necesidades`) y Consumo (`/sincronizacion/consumo`) | analyze sin avisos; `sync_screens_test`, `consumption_publish_screen_test`, `uxj_c_consumo_vinculos_test` + los de la entrega 1 (23 verdes) | `6.4_necesidad*`, `6.5_consumo*`, `6.5b_consumo_final*` | Ver «Entrega 2» |
| 1 | 225acc3 | Vinculos (`/sindicato/vinculos`, `central_binding_screen.dart`), hoja Identificacion (`rdm_c_identification.dart`), hoja Etiqueta (`label_photo_sheet.dart`) | `flutter analyze` de lo tocado sin avisos; `flutter test --concurrency=2`: `e1_binding_screen_identification_test`, `e1_catalog_label_photo_test`, `f04_c2_binding_screen_test`, `uxj_c_consumo_vinculos_test`, `sync_screens_test` (21 verdes) | `flutter test tool/rediseno/capturas_c_test.dart` → `build/rediseno_capturas_c/4.4*`, `4.5*`, `4.6*` a 390×844, 130 %, 200 % y 360 dp (sin versionar, datos sintéticos) | Ver «Entrega 1» abajo |

### Entrega 1 — detalle

Comportamiento conservado (inventario previo): actualizar referencias sólo con «Actualizar»; vincular/corregir/quitar con confirmación; «Fijar fin previsto…» con sus avisos (D-F04-C2); aviso de período y detalle por fila; motivo de «ninguna opción compatible»; pedir identificación sólo sin vínculo y sin solicitud; «Enviar ahora»; «Vincular» tras la identificación con el flujo de confirmación (nunca automático); notas de pausa, del sindicato y de foto anterior; foto: tomar, elegir, reemplazar (pregunta si enviar la nueva), quitar con confirmación y retiro pendiente.

Contratos usados: E1 §5.2–§5.6 y §9 (`_wt/ET2-BE` `docs/architecture/E1_*`), textos `identificationChips`, `identificationLinkedText`, `labelPhotosNotInBackups` y `photoConsentText` (FOTO-1) sin cambios.

| Lámina | App | Motivo |
|---|---|---|
| Vinculos: pasos «Solicitud enviada / Recibida / Esperando / Usted confirma» | Etiquetas con los textos de estado de E1 §5.6 («Pendiente de envío», «Recibida por el sindicato», «Esperando identificación», «Identificado como…») | «Solicitud enviada» sería falso para lo que sólo está en el teléfono; el contrato fija los textos. |
| Vinculos: pastilla «Vinculado» | Detalle vigente «X central · vigente» / «Requiere atención: …» / «Requiere vinculación» | Son los textos probados que explican el motivo en la fila; una pastilla repetiría la palabra. |
| Vinculos: botón redondo de actualizar | «Actualizar» con icono y texto | Un icono solo no dice qué hace; las pruebas y el aviso lo nombran. |
| Vinculos: sin menú por fila | Menú «Opciones de vínculo» (⋮) por fila | Conserva Vincular/Corregir/Quitar, Fijar fin previsto y Pedir identificación. |
| Identificacion: «El sindicato le dirá a qué producto suyo corresponde» | «El sindicato busca a qué producto de su catálogo equivale. El vínculo lo confirma usted después.» | No promete una respuesta; «suyo» era ambiguo. |
| Identificacion: casilla marcada, «La verá la Directiva» | Casilla **sin marcar** con el texto FOTO-1 vigente | Consentimiento nuevo sin marcar; texto del contrato. |
| Etiqueta: «Por enviar al sindicato» | Lo que tiene el sindicato con los textos de la hoja («Pendiente de envío al sindicato.», «El sindicato tiene esta foto.», …) | Estados reales de la foto. |
| Títulos a 200 % | Títulos grandes hasta 1,4×; el resto del texto al 200 % | Con 200 % «Sincronización» o «identificación» se partían por dentro en 360 dp. |
| Selector Productos · Campañas a 200 % | Opciones apiladas si no caben | El `SegmentToggle` compartido partía «Productos». |

### Entrega 2 — detalle

Conservado: declarar con fecha → campaña → producto vinculado → cantidad y confirmación expresa; cambiar cantidad (sustituye, no suma), anular con confirmación, declarar de nuevo, historial de versiones, resolver conflicto (keepMine/withdraw, «Usted decide»), aviso C-02 con «Sincronizar ahora», relectura tras cada ciclo del worker. Consumo: vista previa que no escribe, «Publicar» expreso sólo con cambios, «Sin cambios / Nuevo / Cambió (antes…)», conflicto «Enviar mi total actual», «Retirar del sindicato» con confirmación, rechazo terminal, exclusiones (familiares o terceros, revertidas, sin vínculo), relectura tras cada ciclo. Contratos: F06 §3/F06-COLL-04 (necesidad), MOB #33/F04 §2.4 (consumo expreso; F06-ADR-006 sigue Proposed: sin envío automático).

| Lámina | App | Motivo |
|---|---|---|
| Necesidad: «Invierno 2026 · no cambia su almacén» como subtítulo | Campaña en cada tarjeta; subtítulo «Lo que usted solicita… No cambia su inventario.» | Puede haber necesidades de varias campañas. |
| Necesidad: «Aceptada el 11/11/2026» | Frase vigente del envío («Aceptada por el sindicato: fecha», «Guardada, pendiente de envío», «En conflicto…») | Distingue guardado en el teléfono de aceptado por el sindicato (C-01/C-03). |
| Necesidad: «+ Declarar» flotante | «+ Declarar» en la cabecera | El FAB global ya flota abajo (solicitud 3). |
| Necesidad: «Cambiar cantidad», «Historial», ⋮ | Iguales; con conflicto sin decidir, «Resolver conflicto…» visible; «Anular» en ⋮ | El conflicto no se esconde en un menú. |
| Consumo: «Por publicar» | «Pendiente / Enviado / Requiere atención» + la frase de qué pasaría al publicar | Palabras pedidas por el autor el 2026-11-05 (UXJ-C). |
| Consumo: «No se publica 1 aplicación…» plegado | Bloque «No se publica» visible | No se oculta por qué algo no se envía. |
| Consumo: «Publicar 6 L al sindicato» fijo abajo | «Publicar consumo al sindicato» al final de la lista | No se suman litros y kilos; el FAB global tapaba un botón fijo. |
| Declarar / cambiar cantidad / historial como hojas | Siguen siendo diálogos | La lámina no los muestra; son confirmaciones probadas (bloque 5 del orquestador). |

### Entrega 3 — detalle

Conservado en Sincronización: «Sincronizar ahora» expreso; conteos por estado; última confirmación (sin «ACK»); avisos de pausa por autorización, retención por período («Revisar»), restauración («Liberar» con confirmación) y versión («Reintentar con esta versión» con confirmación); filas con qué es, estado, fechas y explicación; «Decidir…/Revisar…» hacia la pantalla de la proyección; detalle técnico plegado.

| Lámina | App | Motivo |
|---|---|---|
| Sindicato: «Último envío: hoy, 11/11/2026» | «Última confirmación: fecha» / «Todavía sin confirmación» | Es el dato real (`lastAcceptedAt`); no hay fecha de «último envío». |
| Sindicato: «1 envío por hacer» | «N envíos pendientes» / «Nada pendiente de envío» y «N requieren atención» | Cuenta sólo la cola de totales propios (necesidad y consumo). |
| Sindicato: tarjeta de la convocatoria abierta con «Usted pidió 12 L…» | Fila «Convocatorias» con el aviso vigente de convocatoria nueva («Nueva») | Leer convocatorias y participación exigiría consultas nuevas y la API que cambia la sesión F. Se completa cuando llegue la base nueva. |
| Sindicato: pastillas «1 aceptada», «1 por publicar», «1 en trámite» | Sin contadores por entrada | Requerirían consultas nuevas en la pestaña (y hacen frágiles las pruebas con `settle` fijo). Si se quieren, pedir un proveedor de resumen (solicitud 5). |
| Sincronización: (sin lámina propia) | Estilo de las demás pantallas de C | — |
| Títulos | Reducción mínima sólo si la palabra más larga no cabe | Las pruebas de legibilidad (#97) usan glifos cuadrados; con fuentes reales no se reduce. |

### Revisión C-1 — respuesta (commit de corrección abajo)

1. Selector Productos · Campañas: `RdmCToggle` retirado; la pantalla usa el `SegmentToggle` de B1. **Sigue saliendo apilado en el arnés al 100 %/390 dp**, y no por la pantalla: `SegmentToggle._labelStyle` no tiene `fontFamily`, así que `measureText` mide con la fuente por defecto del motor (en el arnés, la de pruebas: 1 em por letra). Sonda del 2026-11-12: «Productos · 5» negrita 14 px mide **182 px** sin familia y **89,6 px** con DM Sans; el hueco es 137 px. En el teléfono la fuente por defecto es Roboto y cabría, pero la medida debe usar la fuente con que se dibuja. Ver solicitud 7.
2. `BadgeTone.ok` en lugar de `voice` para los estados positivos (recibido, aceptado, enviado, «Nueva»).

### Entrega 4 — detalle

Conservado de la rama F y de E2: «Actualizar» y «Enviar ahora» expresos (sin notificaciones push); estados distintos (pendiente de envío, se reintentará, verifique el acceso, recibida, retiro recibido, fuera de plazo, rechazada con motivo, cerrada, cancelada, sin efecto) y nunca «recibida» para lo que sólo está en el teléfono; «El sindicato tiene: …» junto a «Pendiente de envío: …»; consolidado al cierre; historial: lo guardado se ve sin conexión, «Consultar historial», «Ver más», faltan N, fin, y los avisos de versión, sin conexión y fallo temporal (N7); abrir marca «vista» sólo en el teléfono; participar pide CONV-3 sólo la primera vez y su casilla empieza sin marcar; modificar cantidades no cambia la autorización; «Autorizar también…» (`JointPurchaseWidenDialog`, casilla sin marcar) y «Reducir a sólo la persona responsable» (confirmación) aparte de las cantidades, con la decisión pendiente que no se anuncia como aplicada y su resultado; «quién ve» según el alcance **aplicado** en el sindicato; botones desactivados en cerrada/cancelada con explicación; participar no crea compra, deuda ni inventario; la necesidad declarada sólo como referencia.

Contratos usados: E2 §5, §10.1–§10.3 y §10.6 (CONV-3, P-C, N7) en `_wt/ET2-BE` y la rama F integrada en B2; textos de `joint_purchase_texts.dart` sin tocar.

| Lámina | App | Motivo |
|---|---|---|
| Convocatorias: «Actualizado hoy, 9:30» | Sin hora de actualización | La lista no expone esa hora; no se inventa. |
| Convocatorias: «Cierra (hora del sindicato) Hoy, 21:59» | «Fecha límite: dd/mm/aaaa hh:mm (según la hora del sindicato)» | Texto vigente (E2-D4); sin «hoy» relativo. |
| Convocatorias: «Otros estados (ejemplos)» | «Terminadas hace menos de 180 días» y «Historial» | Distingue el filtro de 180 días del historial (no es un borrado). Las pendientes y fuera de plazo se ven con su convocatoria, abierta o no. |
| Convocatoria: «Coordina Directiva» | «Responsable: nombre» | Quien coordina es la persona responsable, no «la Directiva». |
| Convocatoria: «Su pedido» con cantidades por producto | «Su participación» con el texto vigente («El sindicato tiene: …», «Pendiente de envío: …») y los productos aparte | Los textos vigentes ya dicen lo aceptado y lo pendiente sin mezclarlos. |
| Convocatoria: (sin sección) | «Quién ve sus datos» con «Autorizar también…» / «Reducir…» | Autorización separada de las cantidades (P-C, rama F). |
| Participar: «¿Cuánto solicita?» con la casilla «la Directiva verá mi nombre…» marcada | Hoja «Cantidades que solicita» y, sólo la primera vez, el diálogo CONV-3 con la casilla sin marcar | Consentimiento vigente, nuevo sin marcar y aparte de las cantidades. |
| Participar: «Declaró necesitar 20 L» | «Su necesidad declarada: 20 L» | Referencia que no se suma (E2 §5.2). |

### Revisión C-2 — respuesta

1. «Cambiar cantidad…»: no era un recorte sino el carácter «…» del propio rótulo (convención de «abre un diálogo»). Quitado en «Cambiar cantidad», «Declarar de nuevo» y «Resolver conflicto» (`74f5cc5`).
2. Rama F conservada en Convocatorias, Convocatoria y Participar (entrega 4).

## En curso

- Nada en curso: las nueve láminas de C (Sindicato, Convocatorias, Convocatoria, Participar, Necesidad, Consumo, Vinculos, Identificacion, Etiqueta) y Sincronización están entregadas.
- ~~Esperando base nueva~~: desbloqueado en B2; hecho en la entrega 4.

## Solicitudes al orquestador

1. **Promoción opcional** (pendiente hasta las cabeceras de B; `RdmCToggle` ya no existe) de `RdmCPage` (cabecera de consulta: Volver redondo, acción breve, título grande), `RdmCSheetBody`/`showRdmCSheet` (hoja con título y Cerrar), `RdmCRow`, `RdmCToggle` (selector que se apila si no cabe) y `rdmCTitleScaler` (títulos hasta 1,4×) a `agro_ui.dart`, si sirven a A/B.
2. ~~`SegmentToggle` a 200 %~~: resuelto en B1.
3. ~~FAB global~~ (resuelto en B1; «Declarar» sigue en la cabecera). Texto original: **FAB global** en `/planificacion/necesidades`, `/sincronizacion/consumo` y `/sindicato/vinculos`: compite con la acción propia de la pantalla («Declarar», «Publicar») y tapa el final de la lista. Pedir que se oculte en esas rutas (y en `/sindicato`) cuando llegue la barra nueva (B1). Mientras tanto, «Declarar» y «Publicar» quedan en el contenido, no flotantes.
4. ~~Ruta `/sindicato`~~ (cableada en B1). Texto original: **Ruta `/sindicato`**: el esqueleto ya está en `union_screen.dart`; falta cablearla (B1). La pestaña no tiene «Volver» si es raíz (`canPop` falso).
5. **Contadores de la pestaña Sindicato** (opcional): un proveedor de resumen de una sola consulta con necesidades activas, totales de consumo por publicar y solicitudes de identificación en trámite, si el autor quiere las pastillas de la lámina. No lo creo yo: es `lib/services/**`/`lib/data/**`.
7. **`SegmentToggle` mide sin la fuente con que dibuja** (`agro_ui.dart`): añadir `fontFamily: AgroFonts.body` a `_labelStyle` (y lo mismo en cualquier `measureText` con estilo sin familia, p. ej. `AmountAside` usa `AgroText.amount`, que sí la tiene). Con eso el arnés muestra el selector lado a lado al 100 % y lo apila a 200 %, como se pidió.
6. **`f10_sync_textos_confirmacion_test`**: el chip anterior no seguía la escala del teléfono; la línea «Última confirmación» ahora sí (12 px escalados, fuera de la tarjeta, para caber en 2 líneas a 360 dp/130 % con la fuente de pruebas). Revisar si se prefiere otro tamaño.

## Bloqueos y decisiones del autor

- ~~Convocatorias bloqueadas~~: desbloqueadas en B2 (rama F, CONV-3).

## Hallazgos fuera de alcance

- El texto CONV-3 (`jointPurchaseConsentText`, sólo lectura) trata de «tú» («tu nombre», «solicitas», «si tú lo autorizas») mientras el resto de la app usa «usted». No lo cambio: es texto de consentimiento con versión; decisión del autor.
