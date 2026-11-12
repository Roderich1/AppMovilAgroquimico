# Rediseño móvil — coordinación de sesiones

Documento del **orquestador** (sesión que trabaja en `_wt/RDM-MOB`). Sólo el orquestador lo edita. Cada sesión escribe en su propio archivo de estado (`docs/rediseno/estado/<A|B|C>.md`, en su rama). Leer también `CLAUDE.md` (raíz de `ProyectoAgro`), `docs/rediseno/REDISENO_MOVIL_CONTINUIDAD.md` e `INVENTARIO_PROTOTIPO_FLUTTER.md`.

## Base común

- **Base B0:** el commit de `feat/rediseno-movil` que introdujo este documento (ver `git log --diff-filter=A -- docs/rediseno/COORDINACION.md`). Contiene la base funcional `01b2576` + bloque 1 (tema, `agro_ui.dart`, compra) + el esqueleto `union_screen.dart`.
- Comprobado el 2026-11-12: no hay trabajo funcional Mobile posterior a `01b2576` en ninguna rama local.
- **Rama funcional externa (sesión F, `_wt/ET2-MOB`, `feat/etapa2-historial-colaboradores`, encargo del autor del 2026-11-12):** retira CSV (Excel como única exportación) y separa el consentimiento de las cantidades en convocatorias (P-C, compatibilidad N7, esquema v18). Toca `lib/services/reports/*`, `screens/reports_screen.dart` (sólo el selector de formato), `lib/data/**`, servicios de convocatorias, `widgets/joint_purchase_texts.dart`, y en `screens/joint_purchase_detail_screen.dart` / `screens/joint_purchases_screen.dart` sólo acciones, estados y mensajes. Se integrará **sólo** cuando avise con el SHA terminado; el orquestador la fusiona en `feat/rediseno-movil` y la publica como base nueva. No hay corrección de «responsable» de aplicaciones en ninguna rama.
- **Prototipo:** artefacto `https://claude.ai/artifact/CddqjNWu6qNar1Xb8HZgvi` y copia local, no versionada, en `ProyectoAgro/_artefactos/rediseno/prototipo/*.dc.html`. Renderizar láminas a 390×844 (2×): `bash ProyectoAgro/_artefactos/rediseno/herramientas/render_laminas.sh <salida> Aplicacion1 VozPlan …`. Lado a lado: `python -I …/herramientas/side_by_side.py <salida.png> Prototipo=<a.png> App=<b.png>`.
- El prototipo define la apariencia; el código vigente y los contratos aceptados definen el comportamiento.

## Sesiones, ramas y worktrees

Una sesión por worktree. Nadie edita el worktree de otra. Si un worktree ya tiene dueño en su archivo de estado, otra sesión no lo toma.

| Sesión | Alcance | Rama | Worktree | Láminas |
|---|---|---|---|---|
| **Orquestador** | integración, compartidos, navegación, acceso, ajustes, respaldos, reportes, confirmaciones, compra | `feat/rediseno-movil` | `_wt/RDM-MOB` | Registrar, Ajustes, Datos, Campanas, PeriodoHistorico, Reportes, Pin, Respaldo, ModoUso, Tardias, TardiaRegistrar, Activar, Reautenticar, Recuperar, Titular, Revertir, RevertirMotivo, Descartar, Compra* |
| **A** | aplicación y planificación, con su voz | `feat/rediseno-movil-a` | `_wt/RDM-A` | Aplicacion1–3, VozAplicacion, Plan, VozPlan (estados de voz de referencia: VozEscuchando, VozProcesando, VozListo, VozRevisar) |
| **B** | Inicio, Actividad, Almacén, Personas, con detalles y cuentas | `feat/rediseno-movil-b` | `_wt/RDM-B` | Main (Inicio), Actividad, CompraDetalle, Almacen, Producto, Avisos, Estimacion, Personas, Persona, Cuenta, Pago, Transferencia, Propios, CostosChaco, Bitacora |
| **C** | Sindicato, convocatorias, vínculos, identificación con foto | `feat/rediseno-movil-c` | `_wt/RDM-C` | Sindicato, Convocatorias, Convocatoria, Participar, Necesidad, Consumo, Vinculos, Identificacion, Etiqueta |

## Archivos asignados

Rutas bajo `lib/presentation/`. Una sesión sólo edita los suyos y las pruebas que cubren sus pantallas.

**A:** `screens/application_form_screen.dart`, `screens/application_form_voice.dart`, `screens/applications_screen.dart`, `screens/plan_form_screen.dart`, `screens/plan_form_voice.dart`, `screens/planning_screen.dart`, `widgets/application_expiry_notice.dart`.

**B:** `screens/dashboard_screen.dart`, `screens/operations_screen.dart`, `screens/purchases_screen.dart`, `screens/purchase_detail_screen.dart`, `screens/inventory_screen.dart`, `screens/inventory_detail_screen.dart`, `screens/inventory_alerts_screen.dart`, `screens/estimation_screen.dart`, `screens/persons_screen.dart`, `screens/person_detail_screen.dart`, `screens/settlements_screen.dart`, `screens/transfers_screen.dart`, `screens/transfer_form_screen.dart`, `screens/farm_logbook_screen.dart`, `widgets/account_statement_view.dart`.

**C:** `screens/union_screen.dart` (esqueleto del orquestador; el contenido es de C), `screens/joint_purchases_screen.dart`, `screens/joint_purchase_detail_screen.dart`, `screens/declared_needs_screen.dart`, `screens/consumption_publish_screen.dart`, `screens/central_binding_screen.dart`, `screens/sync_status_screen.dart`, `widgets/label_photo_sheet.dart`. Textos funcionales `widgets/joint_purchase_texts.dart` e `widgets/identification_texts.dart`: **sólo lectura** (son textos de consentimiento y permisos vigentes; no se reescriben desde el prototipo).

**Reservados al orquestador (nadie más los edita):** `lib/app.dart`, `presentation/app_shell.dart`, `presentation/theme/**`, `widgets/agro_ui.dart`, `widgets/common.dart`, `widgets/adaptive_entity_picker.dart`, `widgets/catalog_dialogs.dart`, `widgets/campaign_actions.dart`, `widgets/mode_notice.dart`, `widgets/sync_status_banner.dart`, `widgets/sync_lifecycle.dart`, `widgets/owner_reversal_flow.dart`, `widgets/provider_payment_fields.dart`, `presentation/voice/**` (incluido `voice_form_dictation.dart`), `screens/purchase_form_*.dart`, las pantallas de acceso, ajustes, catálogos, campañas, reportes, respaldos, modo, tardías y PIN, `lib/licenses/**`, `pubspec.yaml`/`pubspec.lock`, `assets/**`, `android/**`, `test/support/**`, `tool/rediseno/capturas_arnes_test.dart`, `tool/rediseno/rdm_*.sh`, `docs/rediseno/COORDINACION.md`, `REDISENO_MOVIL_CONTINUIDAD.md`, `INVENTARIO_PROTOTIPO_FLUTTER.md`.

**Fuera del alcance de todos (no se toca):** `lib/domain/**`, `lib/data/**`, `lib/services/**`, `lib/voice/**`, `lib/voice_draft/**` (cálculos, saldos, inventario, pagos, esquema, sincronización, API, motores e intérpretes de voz), Backend/Web, documento de grado.

Si una sesión necesita algo de un archivo reservado o fuera de alcance (un componente nuevo en `agro_ui.dart`, una ruta, un dato que hoy no expone ningún proveedor), **no lo edita**: lo pide en «Solicitudes al orquestador» de su estado y, mientras tanto, usa un widget privado en su propio archivo (`_Algo` dentro de su pantalla). Componentes nuevos que puedan servir a otras sesiones: archivo propio `widgets/rdm_<a|b|c>_*.dart`; el orquestador decide si lo promueve a `agro_ui.dart`.

Pruebas: cada sesión adapta las pruebas que rompan sus propios cambios (cambia cómo se llega a un campo o un texto renombrado, nunca lo que se comprueba) y lo declara en su estado. Ayudantes de prueba propios: `test/support_rdm/<a|b|c>_*.dart`. Capturas propias: `tool/rediseno/capturas_<a|b|c>_test.dart` (puede copiar el arranque de `capturas_arnes_test.dart`).

## Reglas funcionales (todas las sesiones)

- Motores y configuración de voz intactos: compra Whisper small haz 5 turno entero; aplicación/plan Vosk + revisión Whisper base. Abrir el panel no enciende el micrófono; nunca se registra solo; se conservan datos no mencionados; conflictos con resolución; lo manual gana; cancelar descarta resultados tardíos; deshacer no borra ediciones manuales posteriores; no se fusionan productos repetidos; validaciones intactas.
- Un único borrador por formulario; volver entre pasos no pierde datos.
- Durante la transcripción: «Procesando tu voz» + «Cancelar». Sin texto final antes de que el motor lo dé; si se muestra, «Texto reconocido». **No** guardar audio ni transcripciones en evidencia, registros o capturas.
- Revisión de voz: opciones del intérprete + «Escribir otro valor»; sin alternativas inventadas; precio por unidad ≠ total de la línea; «Deshacer último dictado» se conserva.
- Avisos que se conservan: productos vencidos, falta de existencias, cambio de chaco, cantidades pendientes, precio ambiguo.
- **«Previsto en planes»** sustituye a «Reservado» (en código es `committedBase`, no una reserva real). Crear un plan no descuenta inventario ni genera cargos.
- **«Persona» en aplicaciones:** su significado se determina en código y contratos (sesión A) antes de rotularla; no se convierte en «Quién aplicó» sin comprobarlo ni en un campo nuevo.
- **Consentimientos:** los textos y permisos vigentes (`joint_purchase_texts.dart`, `identification_texts.dart`), nunca «la Directiva verá…» del prototipo. Consentimientos nuevos sin marcar; distinguir aceptación previa válida de una nueva. Foto opcional; compartirla requiere autorización.
- Compras conjuntas: estados distintos (pendiente local, recibido, modificación pendiente, fuera de plazo, cerrada, cancelada); participar no crea compra, deuda ni inventario.
- **Exportación:** Excel como única exportación visible la hace la rama funcional externa (sesión F). Nadie más implementa exportaciones; `reports_screen.dart` no se rediseña hasta integrar esa rama.
- No cambiar cálculos, saldos, inventario, pagos, esquema ni API por motivos visuales. Sin funciones perdidas: lo que el prototipo no muestra se conserva en un lugar accesible.
- Accesibilidad: letra al 130 % y 200 %, 360 dp de ancho, nombres largos, importes grandes, decimales y unidades; estados no sólo por color; nada de párrafos explicativos permanentes ni tarjetas enormes ni muchos botones de igual peso.
- Una lámina de estado no es una ruta; las hojas son hojas.

## Recursos y pruebas

- Las sesiones A/B/C: `flutter analyze` de sus archivos y **pruebas focalizadas** (`flutter test test/<archivo>`, de a pocas, `--concurrency=2`). **No** suites completas, **no** APK, **no** emulador, **no** servicios ni túneles, **no** `flutter pub upgrade`. Una prueba pesada a la vez por sesión.
- `flutter pub get` sólo la primera vez en el worktree (no cambia `pubspec.lock`).
- Suites completas, compilaciones, instalación y recorridos en el emulador: sólo el orquestador, uno a la vez.
- Commits locales, autor Roderich1, **sin trailers** (`Co-Authored-By`, «Generated with…»). Sin push, PR, fusiones a main, publicación de capturas ni despliegues.
- Sin datos reales: capturas y pruebas con datos sintéticos.

## Mecanismo de entrega

1. Cada sesión mantiene `docs/rediseno/estado/<X>.md` en su rama (plantilla abajo) y lo commitea con cada entrega.
2. Una entrega es un commit (o serie) **terminado**: compila, `flutter analyze` sin avisos en lo tocado, pruebas focalizadas verdes, capturas del arnés comparadas con la lámina. Se anota en «Entregas listas» con el SHA final, pantallas, pruebas corridas, capturas y diferencias con el prototipo.
3. El orquestador sólo integra SHAs anotados como listos (fusión local `--no-ff` en `feat/rediseno-movil`). No integra trabajo en curso.
4. Correcciones del orquestador a una entrega: en `docs/rediseno/revisiones/<X>-<n>.md` en `feat/rediseno-movil` y por mensaje a la sesión. La sesión responde con otra entrega.
5. Cuando el orquestador publica una base nueva (Bn) con compartidos, la anota abajo; la sesión la incorpora con `git merge <sha-Bn>` en su rama **cuando esté entre entregas** (nunca rebase de lo ya entregado).

### Plantilla de estado

```
# Estado de la sesión <X>
- Dueño del worktree: <nombre de la sesión> desde <fecha hora>
- Base incorporada: <B0|B1…> (<sha>)
## Entregas listas
| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
## En curso
## Solicitudes al orquestador
## Bloqueos y decisiones del autor
## Hallazgos fuera de alcance
```

## Bases publicadas

| Base | SHA | Contenido |
|---|---|---|
| B0 | `33e581f` | bloque 1 + coordinación + esqueleto Sindicato |
| B1 | `475494b` | barra Inicio · Actividad · Almacén · Personas · Sindicato, hoja «Registrar», ruta `/sindicato`; `SegmentToggle` que se apila, `ValueRow`/`AdaptiveEntityPicker(rowStyle:)` con `hint:`, `BadgeTone.ok`, `ActionTile`, `DashedPanel`; sin espaciado extra de letras; sin «+ Registrar» en Necesidad, Consumo, Vínculos, Aplicaciones y Planificación; entregas A1, A2 y C1 integradas. Arnés: `shot()` captura la vista entera (hojas y flotante) con sombras reales: copiarlo. |

## Dependencias y bloqueos

- Barra nueva y hoja «Registrar»: **hechas en B1**. Cuentas (`/liquidacion`) ya no es pestaña: cuelga de Personas (B pone el acceso dentro de Personas; la ruta se conserva). Más (`/mas`), Catálogos y Campañas cuelgan de Inicio: **B** pone en Inicio el acceso a Ajustes (`/mas`, engranaje de la lámina) y a Campañas (selector de campaña de la lámina) antes de quitar esas tarjetas de Actividad.
- Listas `/aplicaciones` y `/planificacion`: las rediseña **A** con el lenguaje del bloque 1 (sin lámina propia); Actividad (B) enlaza a ellas o filtra, sin duplicar sus funciones (registrar, aplicar un plan, revertir).
- Exportación Excel: espera el SHA de la sesión F (reportes, orquestador).
- **C no reescribe `joint_purchase_detail_screen.dart` ni `joint_purchases_screen.dart`** hasta que la rama de la sesión F esté integrada y publicada como base nueva (acciones de consentimiento, estados y mensajes nuevos). Mientras tanto C hace Sindicato, Necesidad, Consumo, Vínculos, Identificación, Etiqueta y sincronización.
- Componentes compartidos nuevos: por solicitud.

## Entregas integradas

| Fecha | Sesión | SHA de la entrega | Fusión en integración | Revisión | Estado |
|---|---|---|---|---|---|
| 2026-11-12 | A | `14f2792` (entrega 1: `/aplicaciones/nueva`) | `a2c3eae` | `revisiones/A-1.md` | implementado · probado automáticamente (focalizadas tras fusionar) · **no** recorrido en emulador · no revisado por el usuario |
| 2026-11-12 | C | `dfc1967` (entrega 1: vínculos, identificación, etiqueta) | `665833f` | `revisiones/C-1.md` | implementado · probado automáticamente · no recorrido · no revisado por el usuario |
| 2026-11-12 | A | `41f7e03` (entrega 2: `/planificacion/nueva`) | `475494b` | `revisiones/A-1.md` | implementado · probado automáticamente · no recorrido · no revisado por el usuario |

Estados posibles de una pantalla: implementado · probado automáticamente · recorrido en emulador · revisado por el usuario. Sólo el autor marca «revisado por el usuario».
