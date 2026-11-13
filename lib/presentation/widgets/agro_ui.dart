/// Componentes compartidos del rediseño móvil (2026-11-12).
///
/// Piezas de presentación del prototipo: cabecera de un registro por pasos,
/// filas de valor, tarjetas de línea, selectores de dos opciones, panel
/// inferior con la acción principal y la hoja dentro de la página. No
/// guardan datos ni deciden reglas: cada pantalla les pasa su estado.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/agro_theme.dart';
import 'common.dart' show measureText;

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

/// Cabecera de un registro: Volver, «Paso n de m» y una acción opcional.
class FlowTopBar extends StatelessWidget {
  const FlowTopBar({
    super.key,
    required this.onBack,
    this.backKey,
    this.backTooltip = 'Volver',
    this.label,
    this.labelKey,
    this.trailing,
  });

  final VoidCallback? onBack;
  final Key? labelKey;
  final Key? backKey;
  final String backTooltip;
  final String? label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      children: [
        CircleIconButton(
          key: backKey,
          icon: Icons.arrow_back,
          tooltip: backTooltip,
          onPressed: onBack,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: label == null
              ? const SizedBox.shrink()
              : Text(
                  label!,
                  key: labelKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w700,
                    color: AgroColors.muted,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        trailing ?? const SizedBox(width: 44),
      ],
    ),
  );
}

/// Barra de pasos: un segmento por paso; los hechos y el actual, oscuros.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Paso $step de $total',
    child: ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i <= step ? AgroColors.ink : AgroColors.trackStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
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

/// Grupo blanco de filas separadas por una línea fina.
class AgroGroup extends StatelessWidget {
  const AgroGroup({super.key, required this.children, this.borderColor});
  final List<Widget> children;

  /// Borde de 2 px para un grupo que pide atención; nulo sin borde.
  final Color? borderColor;

  @override
  // `Material` (no un `Container` con color): así las filas tocables pintan
  // su respuesta al toque sobre el fondo del grupo y `ListTile` no queda
  // tapado por una decoración.
  Widget build(BuildContext context) => Material(
    color: AgroColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: borderColor == null
          ? BorderSide.none
          : BorderSide(color: borderColor!, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Fila «rótulo pequeño + valor grande + flecha» que abre un selector.
///
/// Sin valor muestra [placeholder] en gris. [badge] va antes de la flecha
/// (por ejemplo «Por voz»).
class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Elegir',
    this.badge,
    this.trailing,
    this.minHeight = 64,
    this.labelKey,
    this.valueKey,
    this.errorText,
    this.hint,
    this.hintKey,
  });

  final String label;
  final Key? labelKey;
  final Key? valueKey;

  /// Línea secundaria bajo el valor, en gris (p. ej. «Responsable del chaco
  /// · se usan sus productos»). Pedida por la sesión A (2026-11-12).
  final String? hint;
  final Key? hintKey;

  /// Error de validación debajo del valor, con icono (no sólo color).
  final String? errorText;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final Widget? badge;
  final Widget? trailing;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final empty = value == null || value!.isEmpty;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: label,
      value: empty ? 'Sin elegir' : value,
      hint: hint,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, key: labelKey, style: AgroText.label),
                      Text(
                        empty ? placeholder : value!,
                        key: valueKey,
                        style: empty
                            ? AgroText.value.copyWith(color: AgroColors.muted)
                            : AgroText.value,
                      ),
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            hint!,
                            key: hintKey,
                            style: AgroText.detail,
                          ),
                        ),
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: AgroColors.danger,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  errorText!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AgroColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (badge != null) ...[const SizedBox(width: 8), badge!],
                const SizedBox(width: 4),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      color: onTap == null
                          ? AgroColors.handle
                          : AgroColors.muted,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tono de una etiqueta de estado. Cada tono lleva además un texto: el color
/// nunca es lo único que dice el estado.
enum BadgeTone { voice, review, missing, neutral, ok }

/// Etiqueta pequeña con punto y texto («Por voz», «Revise el precio»).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});
  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      BadgeTone.voice => (const Color(0xFFE3F6A8), const Color(0xFF24400A)),
      BadgeTone.review => (AgroColors.warnBg, const Color(0xFF5A3A00)),
      BadgeTone.missing => (const Color(0xFFFFDAD6), const Color(0xFF8C1D18)),
      BadgeTone.neutral => (AgroColors.track, AgroColors.ink),
      // Estado conforme («Cubierto», «Vinculado»): mismo lima suave que «Por
      // voz»; el texto dice el estado.
      BadgeTone.ok => (const Color(0xFFE3F6A8), const Color(0xFF24400A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 18 / 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de sección con un dato a la derecha («Productos de esta compra 2»).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: AgroText.h2),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w700,
              color: AgroColors.muted,
            ),
          ),
      ],
    ),
  );
}

/// Texto a la izquierda y un importe a la derecha; si con la letra actual no
/// queda ancho para el texto sin partir palabras, el importe baja debajo,
/// alineado a la derecha.
class AmountAside extends StatelessWidget {
  const AmountAside({
    super.key,
    required this.child,
    required this.amount,
    this.amountStyle = AgroText.amount,
    this.amountKey,
    this.minTextWidth = 150,
  });

  final Widget child;
  final String? amount;
  final TextStyle amountStyle;
  final Key? amountKey;

  /// Ancho mínimo del texto (a letra 100 %) para dejar el importe al lado.
  final double minTextWidth;

  @override
  Widget build(BuildContext context) {
    final value = amount;
    if (value == null) return child;
    final text = Text(value, key: amountKey, style: amountStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final amountWidth = measureText(context, value, amountStyle);
        final side =
            constraints.maxWidth - amountWidth - 10 >= minTextWidth * scale;
        if (side) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: child),
              const SizedBox(width: 10),
              text,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            child,
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: text),
          ],
        );
      },
    );
  }
}

/// Tarjeta de una línea de la operación: nombre, detalle, importe y flecha.
///
/// [footer] va debajo, dentro de la misma tarjeta (lo que falta o hay que
/// revisar). [attention] le pone el borde ámbar de «pide atención».
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.subtitleStyle,
    this.amount,
    this.badge,
    this.footer = const [],
    this.attention = false,
    this.semanticsHint,
  });

  final String title;
  final String? subtitle;
  final TextStyle? subtitleStyle;
  final String? amount;
  final Widget? badge;
  final List<Widget> footer;
  final bool attention;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: attention
          ? const BorderSide(color: Color(0xFFC77700), width: 2)
          : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: onTap != null,
          hint: semanticsHint,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(
                children: [
                  Expanded(
                    child: AmountAside(
                      amount: amount,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AgroText.value.copyWith(height: 22 / 17),
                          ),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
                                style: subtitleStyle ?? AgroText.detail,
                              ),
                            ),
                          if (badge != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: badge!,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: AgroColors.muted),
                ],
              ),
            ),
          ),
        ),
        if (footer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: footer,
            ),
          ),
      ],
    ),
  );
}

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

/// Panel blanco fijo abajo, con las esquinas superiores redondeadas: total y
/// acción principal de un registro.
class BottomPanel extends StatelessWidget {
  const BottomPanel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AgroColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [
        BoxShadow(
          color: Color(0x1A0F2A1D),
          blurRadius: 16,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// «Total · 2 productos ……… 2.016,00 Bs». Si no cabe en una línea, el
/// importe baja debajo del rótulo.
class TotalLine extends StatelessWidget {
  const TotalLine({
    super.key,
    required this.label,
    required this.amount,
    this.amountKey,
    this.muted = false,
  });
  final String label;
  final String amount;
  final Key? amountKey;
  final bool muted;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 12,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          height: 20 / 15,
          color: AgroColors.muted,
        ),
      ),
      Text(
        amount,
        key: amountKey,
        style: muted
            ? AgroText.total.copyWith(color: AgroColors.muted)
            : AgroText.total,
      ),
    ],
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

/// Una opción de [SegmentToggle].
class ToggleOption<T> {
  const ToggleOption(this.value, this.label, {this.key});
  final T value;
  final String label;
  final Key? key;
}

/// Selector de dos o tres opciones sobre una pista gris. La elegida va en
/// verde oscuro, en negrita y con una marca: no se distingue sólo por color.
/// Con [selected] nulo no hay ninguna elegida.
class SegmentToggle<T> extends StatelessWidget {
  const SegmentToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    this.height = 48,
  });

  final List<ToggleOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onChanged;
  final String? semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Si con la letra actual algún rótulo no cabe en su parte sin partir
        // una palabra, las opciones se apilan con el mismo aspecto
        // (propuesta de la sesión C, 2026-11-12). 8 de la pista, 4 entre
        // opciones, 16 de relleno y 20 de la marca de elegida.
        final segment = constraints.hasBoundedWidth
            ? (constraints.maxWidth - 8 - 4 * (options.length - 1)) /
                      options.length -
                  36
            : double.infinity;
        final fits = options.every(
          (option) =>
              measureText(context, option.label, _labelStyle) <= segment,
        );
        return Semantics(
          label: semanticLabel,
          container: true,
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AgroColors.track,
              borderRadius: BorderRadius.circular(fits ? height : 24),
            ),
            child: fits
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < options.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(child: _segment(options[i], scaler)),
                        ],
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        _segment(options[i], scaler),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  // Con la familia de la app: sin ella se medía con la fuente por defecto
  // del motor y el selector se apilaba aunque cupiera (sesión C).
  static const _labelStyle = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  Widget _segment(ToggleOption<T> option, TextScaler scaler) {
    final on = option.value == selected;
    return Semantics(
      key: option.key,
      button: true,
      selected: on,
      inMutuallyExclusiveGroup: true,
      enabled: onChanged != null,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        color: on ? AgroColors.ink : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(option.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (on) ...[
                  const Icon(Icons.check, size: 16, color: AgroColors.lime),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 18 / 14,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? Colors.white : AgroColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una respuesta de [ChoiceCards].
class ChoiceCardOption<T> {
  const ChoiceCardOption(this.value, this.label, this.icon, {this.key});
  final T value;
  final String label;
  final IconData icon;
  final Key? key;
}

/// Respuestas grandes a una pregunta («¿Ya pagó al proveedor?»). Sin
/// respuesta por defecto si [selected] es nulo. La elegida lleva borde
/// grueso, fondo lima y la marca de radio llena.
class ChoiceCards<T> extends StatelessWidget {
  const ChoiceCards({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<ChoiceCardOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onChanged;
  final String? semanticLabel;

  /// Ancho mínimo de cada respuesta para ir lado a lado; si no, apiladas.
  static const double _minCardWidth = 150;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    container: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final side =
            constraints.maxWidth / options.length >= _minCardWidth * scale;
        if (!side) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _card(context, options[i]),
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _card(context, options[i])),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _card(BuildContext context, ChoiceCardOption<T> option) {
    final on = option.value == selected;
    return Semantics(
      key: option.key,
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      enabled: onChanged != null,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        color: on ? const Color(0xFFEFF9CF) : AgroColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: on ? AgroColors.ink : AgroColors.fieldBorder,
            width: on ? 2 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(option.value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(option.icon, color: AgroColors.ink),
                      const Spacer(),
                      Icon(
                        on
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: on ? AgroColors.ink : AgroColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    option.label,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tono de [NoticeBox].
enum NoticeTone { info, warning, danger }

/// Aviso breve con icono y texto, dentro del contenido.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    this.tone = NoticeTone.info,
    this.icon,
    this.action,
  });
  final String text;
  final NoticeTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, defaultIcon) = switch (tone) {
      NoticeTone.info => (AgroColors.track, AgroColors.ink, Icons.info_outline),
      NoticeTone.warning => (
        AgroColors.warnBg,
        AgroColors.warnInk,
        Icons.report_gmailerrorred_outlined,
      ),
      NoticeTone.danger => (
        const Color(0xFFFFDAD6),
        const Color(0xFF6B0F0A),
        Icons.error_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(fontSize: 14, height: 20 / 14, color: fg),
                ),
                if (action != null) ...[const SizedBox(height: 6), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior dentro de la misma página: el borrador sigue siendo uno
/// solo y lo que se escribe en la hoja ya está en él. Encima de la página,
/// que se sigue viendo detrás atenuada por un velo semitransparente (el mismo
/// que el de las hojas modales de Aplicación); tocar el velo o «Cerrar» la
/// cierra sin perder nada. Quien la usa deja la página inerte mientras está
/// abierta (sin toques, foco ni semántica), porque la página no es parte de
/// la hoja.
///
/// La altura se ajusta al contenido y al espacio que queda (teclado
/// incluido): el título y las acciones quedan fijos y el contenido se
/// desplaza.
class InPageSheet extends StatelessWidget {
  const InPageSheet({
    super.key,
    required this.title,
    required this.onClose,
    required this.children,
    this.actions = const [],
    this.closeKey,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final List<Widget> actions;
  final Key? closeKey;

  /// Velo sobre la página: negro al 54 %, como el de `showModalBottomSheet`
  /// (Aplicación › Añadir producto). Sin desenfoque: en teléfonos modestos
  /// cuesta un fotograma y no aporta.
  static const Color veilColor = Colors.black54;

  /// Clave del velo, para las pruebas.
  static const Key veilKey = ValueKey('in-page-sheet-veil');

  @override
  Widget build(BuildContext context) {
    // Con el teclado abierto fuera de un `Scaffold` que ya se encoja, la
    // hoja sube por encima de él.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          child: ModalBarrier(
            key: veilKey,
            color: veilColor,
            dismissible: true,
            onDismiss: onClose,
            semanticsLabel: 'Cerrar $title',
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Nunca bajo la barra de estado, y siempre con una franja de
              // la página a la vista arriba: se ve que es una hoja.
              final height = constraints.maxHeight;
              final maxHeight = math.max(
                0.0,
                math.min(height * 0.92, height - top - 24),
              );
              return Align(
                alignment: Alignment.bottomCenter,
                child: BlockSemantics(child: _sheet(maxHeight)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sheet(double maxHeight) => Material(
    color: AgroColors.canvas,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AgroColors.handle,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    namesRoute: true,
                    child: Text(title, style: AgroText.sheetTitle),
                  ),
                ),
                CircleIconButton(
                  key: closeKey,
                  icon: Icons.close,
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          if (actions.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Barra superior de las pantallas fuera de las pestañas (acceso, titular,
/// PIN, tardías): «Volver» redondo si se puede volver y el título grande con
/// la letra de los títulos (láminas «Activar», «Reautenticar», «Recuperar»,
/// «PIN del titular», «Operaciones tardías»). Sustituye a `AppBar` sin
/// cambiar qué hace Atrás.
class AgroAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AgroAppBar({super.key, required this.title, this.actions});
  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      toolbarHeight: 72,
      backgroundColor: AgroColors.canvas,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: canPop ? 68 : 0,
      leading: canPop
          ? Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: CircleIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Volver',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            )
          : null,
      titleSpacing: canPop ? 12 : 16,
      title: Text(
        title,
        maxLines: 2,
        style: const TextStyle(
          fontFamily: AgroFonts.display,
          fontSize: 24,
          height: 30 / 24,
          fontWeight: FontWeight.w800,
          color: AgroColors.ink,
        ),
      ),
      actions: actions,
    );
  }
}
