import 'package:flutter/material.dart';

import '../../theme/agro_theme.dart';

/// Botón de borde punteado para añadir un elemento a una lista.
class DashedAddButton extends StatelessWidget {
  const DashedAddButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    excludeSemantics: true,
    child: CustomPaint(
      painter: _DashedBorderPainter(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, color: AgroColors.ink),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AgroColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Panel con borde punteado que se toca entero (p. ej. «Completar por voz»
/// en la hoja «Registrar»). El contenido lo pone quien lo usa.
class DashedPanel extends StatelessWidget {
  const DashedPanel({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorderPainter(),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Tono de una [ActionTile].
/// `surface`: blanco con el icono en verde oscuro (la segunda acción de
/// Inicio, como en la lámina; pedido por la sesión B).
enum ActionTileTone { lime, ink, surface }

/// Botón grande de acción principal (lámina «Inicio» y «Registrar»): icono en
/// un círculo arriba y el nombre de la acción abajo, en lima o en verde
/// oscuro. Dos por fila cuando caben; si no, uno debajo del otro
/// ([ActionTileRow]).
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = ActionTileTone.lime,
    this.minHeight = 140,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final ActionTileTone tone;
  final double minHeight;

  /// Fila baja con el icono a la izquierda: la usa [ActionTileRow] cuando
  /// apila las acciones (letra grande o pantalla estrecha), para que la hoja
  /// «Registrar» siga mostrando todas sus opciones.
  final bool compact;

  ActionTile _compact() => ActionTile(
    key: key,
    icon: icon,
    label: label,
    onTap: onTap,
    tone: tone,
    minHeight: minHeight,
    compact: true,
  );

  @override
  Widget build(BuildContext context) {
    final (background, foreground, circle, glyph) = switch (tone) {
      ActionTileTone.lime => (
        AgroColors.lime,
        AgroColors.ink,
        AgroColors.ink,
        AgroColors.lime,
      ),
      ActionTileTone.ink => (
        AgroColors.ink,
        AgroColors.onInk,
        AgroColors.lime,
        AgroColors.ink,
      ),
      ActionTileTone.surface => (
        AgroColors.surface,
        AgroColors.ink,
        AgroColors.ink,
        AgroColors.lime,
      ),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Builder(
            builder: (context) {
              final badge = CircleAvatar(
                radius: 22,
                backgroundColor: circle,
                child: Icon(icon, color: glyph),
              );
              final text = Text(
                label,
                style: TextStyle(
                  fontFamily: AgroFonts.body,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: foreground,
                ),
              );
              if (compact) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        badge,
                        const SizedBox(width: 16),
                        Expanded(child: text),
                      ],
                    ),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [badge, const SizedBox(height: 16), text],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Dos [ActionTile] lado a lado si cada una tiene al menos 150 px por la
/// escala de la letra; si no, apiladas.
class ActionTileRow extends StatelessWidget {
  const ActionTileRow({super.key, required this.tiles});
  final List<ActionTile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final perTile =
          (constraints.maxWidth - 12 * (tiles.length - 1)) / tiles.length;
      if (perTile >= 150 * scale) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            tiles[i]._compact(),
          ],
        ],
      );
    },
  );
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AgroColors.muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    ).deflate(0.75);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
