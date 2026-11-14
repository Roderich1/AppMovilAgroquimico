# Instrucciones comunes a las sesiones A, B y C

1. Trabajas **sólo** en tu worktree (`_wt/RDM-<X>`, rama `feat/rediseno-movil-<x>`). Antes de nada, abre `docs/rediseno/estado/<X>.md`: si ya tiene dueño, no sigas y avisa al orquestador. Si está libre, escribe tu nombre de sesión, fecha y hora, y commitea.
2. Lee `CLAUDE.md` (raíz de `ProyectoAgro`), `docs/rediseno/COORDINACION.md` (manda sobre este archivo), `REDISENO_MOVIL_CONTINUIDAD.md` e `INVENTARIO_PROTOTIPO_FLUTTER.md`.
3. Mira cómo quedó la compra (`purchase_form_screen.dart`) y los componentes de `widgets/agro_ui.dart` y `theme/agro_theme.dart`: es el lenguaje visual aprobado para seguir. Reutilízalos; no copies ni dupliques el tema.
4. Para cada pantalla: inventaria lo que hace hoy (funciones, estados, avisos, guardas) **antes** de cambiarla; compárala con su lámina (renderízala con `_artefactos/rediseno/herramientas/render_laminas.sh`); implementa conservando todo; captura con el arnés a 390×844, 130 %, 200 % y 360 dp; compara lado a lado.
5. Lo que la lámina no muestra pero la app hace, se conserva en un lugar accesible. Las láminas de estado no son rutas.
6. Pruebas: `flutter analyze` y pruebas focalizadas de tus pantallas, una a la vez, `--concurrency=2`. Nada de suites completas, APK, emulador, túneles ni servicios.
7. Archivos reservados o fuera de alcance: no se editan; se piden en tu estado («Solicitudes al orquestador»). Avisa al orquestador por mensaje cuando haya una solicitud que te bloquee.
8. Entrega = commits terminados + estado actualizado con el SHA en «Entregas listas». Avisa al orquestador (mensaje a la sesión que trabaja en `_wt/RDM-MOB`). Entrega por pantalla o grupo pequeño de pantallas, no todo al final.
9. Commits locales con la identidad git configurada, **sin** `Co-Authored-By` ni «Generated with…». Sin push, PR, fusiones ni publicación de capturas. Sin datos reales.
10. Si una decisión cambia reglas de negocio, permisos o efectos de una operación: no la tomes; anótala en «Bloqueos y decisiones del autor» y sigue con otra pantalla. Decisiones visuales rutinarias: tómalas y decláralas en «Diferencias con la lámina».
11. No declares precisión de voz con texto inyectado ni silencio. No guardes audio ni transcripciones.
