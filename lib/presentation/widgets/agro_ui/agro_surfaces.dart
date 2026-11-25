import 'package:flutter/material.dart';

import '../../theme/agro_theme.dart';
import '../common.dart' show measureText;

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
