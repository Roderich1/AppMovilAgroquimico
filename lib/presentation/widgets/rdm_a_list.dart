/// Piezas de presentación de la sesión A del rediseño para las listas de
/// Aplicaciones y Planificación. Candidatas a unificarse con las de otras
/// sesiones si el orquestador lo decide. No guardan datos ni deciden reglas.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'common.dart' show ContentInsets;

/// Página de lista con la cabecera del rediseño: «Volver» redondo (sólo si
/// el router puede retroceder), la acción de registro a la derecha y el
/// título grande debajo.
///
/// Conserva lo de `PageFrame`: «Volver» respeta el `PopScope` de la página y
/// el contenido termina por encima del teclado y de lo que flote abajo.
class RdmAListPage extends StatelessWidget {
  const RdmAListPage({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;

  /// Acción de la cabecera; su rótulo dice qué registra.
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return _frame(context, null, false);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _frame(context, router, router.canPop()),
    );
  }

  void _back(BuildContext context, GoRouter router) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
    } else {
      router.pop();
    }
  }

  Widget _frame(BuildContext context, GoRouter? router, bool canPop) {
    final bottom =
        24 +
        ContentInsets.of(context) +
        MediaQuery.viewInsetsOf(context).bottom;
    return ColoredBox(
      color: AgroColors.canvas,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canPop || action != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      // La acción no le quita ancho al título: va en la fila
                      // de «Volver» y, si no cabe, baja sin partir su rótulo.
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: canPop
                              ? WrapAlignment.spaceBetween
                              : WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (canPop)
                              CircleIconButton(
                                icon: Icons.arrow_back,
                                tooltip: 'Volver',
                                onPressed: () => _back(context, router!),
                              ),
                            ?action,
                          ],
                        ),
                      ),
                    ),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      key: const Key('page-frame-title'),
                      style: AgroText.h1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      ),
    );
  }
}

/// Botón de registro de la cabecera: verde oscuro, 44 px, icono y texto.
class RdmARegisterButton extends StatelessWidget {
  const RdmARegisterButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
      textStyle: const TextStyle(
        fontFamily: AgroFonts.body,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
    icon: Icon(
      Icons.add,
      size: 20,
      color: onPressed == null ? null : AgroColors.lime,
    ),
    label: Text(label),
  );
}

/// «1 producto», «3 productos».
String rdmAProducts(int count) =>
    '$count ${count == 1 ? 'producto' : 'productos'}';

/// Estado vacío breve dentro de un grupo blanco, con su icono.
class RdmAEmpty extends StatelessWidget {
  const RdmAEmpty({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => AgroGroup(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Icon(icon, color: AgroColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AgroText.detail.copyWith(color: AgroColors.ink),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
