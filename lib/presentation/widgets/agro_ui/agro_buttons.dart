import 'package:flutter/material.dart';

import '../../theme/agro_theme.dart';

/// Botón redondo de 44 px con sólo un icono (Volver, Cerrar, Ajustes).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background = AgroColors.surface,
    this.foreground = AgroColors.ink,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: background.withValues(alpha: 0.6),
      minimumSize: const Size.square(44),
      fixedSize: const Size.square(44),
      padding: EdgeInsets.zero,
    ),
    icon: Icon(icon, size: 22),
  );
}

/// Botón de borde redondeado con icono, para acciones secundarias breves
/// («Completar por voz»).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
    ),
    icon: Icon(icon, size: 20),
    label: Text(label),
  );
}

/// Acción principal de una pantalla: 56 px, verde oscuro, flecha lima. Es un
/// [FilledButton]: su clave y su `onPressed` son los del botón.
class PrimaryActionButton extends FilledButton {
  PrimaryActionButton({
    super.key,
    required String label,
    required super.onPressed,
    IconData icon = Icons.arrow_forward,
    bool iconFirst = false,
    bool busy = false,
  }) : super(
         style: FilledButton.styleFrom(
           minimumSize: const Size.fromHeight(56),
           textStyle: const TextStyle(
             fontFamily: AgroFonts.body,
             fontSize: 17,
             fontWeight: FontWeight.w700,
           ),
         ),
         child: _ActionContent(
           label: label,
           icon: busy
               ? const SizedBox.square(
                   dimension: 18,
                   child: CircularProgressIndicator(
                     strokeWidth: 2,
                     color: AgroColors.lime,
                   ),
                 )
               : Icon(icon, color: onPressed == null ? null : AgroColors.lime),
           iconFirst: iconFirst,
         ),
       );
}

/// Acción secundaria del mismo alto que la principal, con borde. Es un
/// [OutlinedButton].
class SecondaryActionButton extends OutlinedButton {
  SecondaryActionButton({
    super.key,
    required String label,
    required super.onPressed,
    IconData? icon,
  }) : super(
         style: OutlinedButton.styleFrom(
           minimumSize: const Size.fromHeight(56),
           padding: const EdgeInsets.symmetric(horizontal: 12),
         ),
         child: _ActionContent(
           label: label,
           icon: icon == null ? null : Icon(icon, size: 20),
           iconFirst: true,
         ),
       );
}

class _ActionContent extends StatelessWidget {
  const _ActionContent({
    required this.label,
    required this.icon,
    required this.iconFirst,
  });
  final String label;
  final Widget? icon;
  final bool iconFirst;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null && iconFirst) ...[icon!, const SizedBox(width: 8)],
      Flexible(child: Text(label, textAlign: TextAlign.center)),
      if (icon != null && !iconFirst) ...[const SizedBox(width: 8), icon!],
    ],
  );
}
