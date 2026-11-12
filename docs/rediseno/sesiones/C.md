# Sesión C — Sindicato, convocatorias, vínculos, identificación con foto

Leer antes `sesiones/COMUN.md` y `COORDINACION.md`.

- Láminas: Sindicato, Convocatorias, Convocatoria, Participar, Necesidad, Consumo, Vinculos, Identificacion, Etiqueta.
- Rutas: `/sindicato` (nueva, la cablea el orquestador hacia `union_screen.dart`; el contenido es tuyo), `/sincronizacion`, `/compras-conjuntas`, `/compras-conjuntas/:id`, `/planificacion/necesidades`, `/sincronizacion/consumo`, `/sindicato/vinculos`; hojas de identificación y foto de etiqueta.
- **Esperar** para `joint_purchase_detail_screen.dart` y `joint_purchases_screen.dart`: la sesión F (`_wt/ET2-MOB`) añade acciones de consentimiento, estados y mensajes. Se rediseñan cuando el orquestador publique la base con esa rama.
- Consentimientos y permisos: textos vigentes de `joint_purchase_texts.dart` e `identification_texts.dart` (sólo lectura), nunca «la Directiva verá…». Nuevos sin marcar; aceptación previa válida ≠ nueva. Foto opcional; compartir requiere autorización. Participar no crea compra, deuda ni inventario. Estados de convocatoria distintos y no sólo por color.
- Contratos: E1 (identificación y foto) y E2 (convocatorias, §10) en Back/Web `_wt/ET2-BE` (`docs/`), y la continuidad de `_wt/ET2-MOB`. Solo lectura.
