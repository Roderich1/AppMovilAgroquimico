# Ronda 2 del rediseño móvil · sesión A — hoja de producto de Compra y lotes

- **Fecha real:** 2026-11-12 (UTC−4).
- **Rama / worktree:** `feat/rdm-correcciones-a` en `_wt/RDM2-A`, base `77deb95`. Sin push.
- **Código capturado en `despues/`:** commit `3ea2191` (fondo en `da43854`, lotes en `3ea2191`) (el de este README sólo añade la evidencia).
- **Código capturado en `antes/`:** la base `77deb95`, con la misma prueba de capturas antes de cambiar `lib/`.
- **Dónde:** arnés de pruebas de Flutter 3.47.2 en Windows (no un teléfono ni el emulador), app real sobre base SQLite sintética; tipografías empaquetadas; 390×844 dp (letra 1.0, 1.3 y 2.0) y 900×844 dp (letra 1.0). Sin teclado real: el teclado se simula con `viewInsets` de 336 dp (zona en blanco abajo en `a4_*`).
- **Datos:** sintéticos (proveedor «Agroinsumos del Valle», Glifosato 12 L × 118 Bs, «Hermana», número de envase inventado para la prueba `GL-2611-07`, vencimiento = fecha del día).

## Cómo se generaron

```
RDM_SHOTS=docs/evidence/rediseno-movil/2026-11-12/ronda2/A/<antes|despues> \
RDM_TEXT_SCALE=<1.0|1.3|2.0> RDM_WIDTH=<390|900> \
flutter test --no-pub tool/rediseno/capturas_rdm2_a_test.dart
```

Las 8 ejecuciones (4 antes, 4 después) terminaron con `All tests passed!`.

## Capturas (sufijo `_x13`, `_x20` = letra 1.3/2.0; `_w900` = ancha)

| Archivo | Qué muestra | Antes | Después |
|---|---|---|---|
| `a1_hoja_vacia` | Hoja «Producto 1» vacía | Superficie plana verde-gris opaca arriba | La página de Compra real detrás, atenuada (negro 54 %) |
| `a2_hoja_con_datos` | Producto, cantidad, precio, persona, vencimiento | «Vencimiento y lote (opcional)» plegado | «Vencimiento (opcional)» a la vista + «Más datos del envase» plegado |
| `a3_hoja_con_datos_abajo` | Número del envase escrito | Fecha y número dentro de la misma sección | Número en «Más datos del envase», con «Lote del envase …» |
| `a4_hoja_teclado` | Cantidad enfocada, teclado simulado | La hoja llegaba al borde superior | Franja de la página a la vista; título y «Listo»/«Añadir otro» fijos; campos desplazables |
| `a5_paso1_resumen` | Tarjeta de la línea | Cantidad · persona | Cantidad · persona · vencimiento |
| `a6_revision` | Revisión | «Vence el … · lote …» (el código base decía «sin número de lote» / «Sin fecha de vencimiento» cuando faltaba uno; no aparece en estas capturas) | «Vence el … · Lote del envase …»; sin frases de ausencia |

## Límites

- Sin desenfoque (decisión: costo de fotograma en teléfonos modestos; el velo basta).
- Sin animación de entrada/salida de la hoja (como antes).
- No verificado en emulador ni en teléfono físico (fuera del alcance de la sesión A).
