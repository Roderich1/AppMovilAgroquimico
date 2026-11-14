# Rediseño móvil · sesión B · entrega 1 (Inicio y Almacén)

- **Fecha real:** 2026-11-12.
- **Rama / commits:** `feat/rediseno-movil-b`; código `950ce19` + `e79d422` sobre la base B1 (`0a2e321`, fusión `20ed54a`).
- **Entorno:** arnés de pruebas de Flutter 3.47.2 en Windows (no es un teléfono ni el emulador). Base sintética de `test/support_rdm/b_seed.dart`; fuentes empaquetadas (DM Sans, Bricolage Grotesque) e iconos de Material.
- **Comando:** `flutter test tool/rediseno/capturas_b_test.dart` con `RDM_TEXT_SCALE=1.0 | 2.0` y `RDM_TEXT_SCALE=1.3 RDM_WIDTH=360`; lado a lado con `_artefactos/rediseno/herramientas/side_by_side.py` frente a las láminas renderizadas (`Main`, `Almacen`).
- **Datos:** sintéticos, sin datos reales.

## Archivos

| Archivo | Qué muestra |
|---|---|
| `lado_inicio.png` | lámina 1.2 frente a Inicio compartido (arriba y final) y propio |
| `lado_almacen.png` | lámina 1.4 frente a Almacén (arriba, final y sin compras) |
| `B_1.2_inicio*.png` | Inicio compartido: 390 dp, 200 %, 130 % a 360 dp; `_fin` = final del desplazamiento |
| `B_1.2_inicio_propio*.png` | Inicio en inventario propio |
| `B_1.2_inicio_vacio.png` | instalación sin operaciones («Sin saldos por cobrar», «Nada pendiente por ahora») |
| `B_1.4_almacen*.png` | Almacén: 390 dp, 200 %, 130 % a 360 dp; búsqueda sin resultados; sin compras |

## Resumen de la salida

- Capturas: 5 pruebas del arnés en verde en cada una de las tres escalas.
- Pruebas focalizadas en verde (ver `docs/rediseno/estado/B.md`, entrega 1).

## Limitaciones

- No se recorrió en el emulador ni en un teléfono (lo hace el orquestador).
- La barra inferior y el botón flotante son los de B1 (del orquestador).
