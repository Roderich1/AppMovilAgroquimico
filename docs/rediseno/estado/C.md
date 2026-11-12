# Estado de la sesión C

- Dueño del worktree: proyectoagro-78 (sesión C) desde 2026-11-12 07:09
- Base incorporada: B0 (33e581f)

## Entregas listas

| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
|---|---|---|---|---|---|
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

## En curso

- Entrega 2: Necesidad (`/planificacion/necesidades`) y Consumo (`/sincronizacion/consumo`).
- Después: Sindicato (`union_screen.dart`) y Sincronización (`/sincronizacion`).
- **Esperando base nueva** (rama de la sesión F): Convocatorias, Convocatoria, Participar (`joint_purchases_screen.dart`, `joint_purchase_detail_screen.dart`). No se tocan.

## Solicitudes al orquestador

1. **Promoción opcional** de `RdmCPage` (cabecera de consulta: Volver redondo, acción breve, título grande), `RdmCSheetBody`/`showRdmCSheet` (hoja con título y Cerrar), `RdmCRow`, `RdmCToggle` (selector que se apila si no cabe) y `rdmCTitleScaler` (títulos hasta 1,4×) a `agro_ui.dart`, si sirven a A/B.
2. **`SegmentToggle` a 200 %** parte palabras en la mitad del ancho («Producto/s»). Propuesta: apilar las opciones si no caben (como `RdmCToggle`).
3. **FAB global** en `/planificacion/necesidades`, `/sincronizacion/consumo` y `/sindicato/vinculos`: compite con la acción propia de la pantalla («Declarar», «Publicar») y tapa el final de la lista. Pedir que se oculte en esas rutas (y en `/sindicato`) cuando llegue la barra nueva (B1). Mientras tanto, «Declarar» y «Publicar» quedan en el contenido, no flotantes.
4. **Ruta `/sindicato`**: el esqueleto ya está en `union_screen.dart`; falta cablearla (B1).

## Bloqueos y decisiones del autor

- Convocatorias, Convocatoria y Participar: bloqueadas hasta integrar la rama de la sesión F (consentimiento separado de cantidades, P-C, N7, esquema v18) y el texto exacto de CONV-2 (N5) pendiente del autor.

## Hallazgos fuera de alcance

- Ninguno por ahora.
