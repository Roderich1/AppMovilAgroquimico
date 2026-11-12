# Rediseño móvil · sesión B · entrega 2 (Actividad)

- **Fecha real:** 2026-11-12.
- **Rama / commit de código:** `feat/rediseno-movil-b` @ `b2997b1` (base B1).
- **Entorno:** arnés de pruebas de Flutter 3.47.2 en Windows (no es un teléfono ni el emulador), con sombras reales (`debugDisableShadows = false`, revisión B-1). Base sintética `test/support_rdm/b_seed.dart`.
- **Comando:** `flutter test tool/rediseno/capturas_b_test.dart` con `RDM_TEXT_SCALE=1.0 | 2.0` y `RDM_TEXT_SCALE=1.3 RDM_WIDTH=360`; lado a lado con `side_by_side.py` frente a la lámina `Actividad`.
- **Datos:** sintéticos.

| Archivo | Qué muestra |
|---|---|
| `lado_actividad.png` | lámina 1.3 frente a Actividad: Todo (arriba y final), filtro Compras, filtro Planes |
| `B_1.3_actividad*.png` | 390 dp, 200 %, 130 % a 360 dp; `_fin` = final del desplazamiento; búsqueda sin resultados; instalación sin operaciones |
| `B_1.2_inicio.png`, `B_1.4_almacen.png` | Inicio y Almacén con sombras reales (corrección 1 de B-1) |

Limitaciones: no se recorrió en el emulador ni en un teléfono.
