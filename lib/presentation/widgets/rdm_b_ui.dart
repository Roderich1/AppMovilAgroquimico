/// Piezas de presentación de la sesión B del rediseño (Inicio, Actividad,
/// Almacén, Personas). Como `agro_ui.dart`, no leen datos ni deciden reglas:
/// cada pantalla les pasa lo que muestran. El orquestador decide si alguna
/// pasa a `agro_ui.dart`.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import 'common.dart' show ContentInsets;

/// Importe en bolivianos partido en cifra y unidad («610,00» y «Bs»), con el
/// mismo formato que [formatBob].
({String number, String unit}) splitBob(int minor) {
  final text = formatBob(minor).replaceAll(' ', ' ').trim();
  if (text.endsWith('Bs')) {
    return (number: text.substring(0, text.length - 2).trim(), unit: 'Bs');
  }
  if (text.startsWith('Bs')) {
    return (number: text.substring(2).trim(), unit: 'Bs');
  }
  return (number: text, unit: '');
}

/// Cantidad partida en cifra y unidad («10» y «L»), con el mismo formato que
/// [formatQuantity].
({String number, String unit}) splitQuantity(int base, String unit) {
  final text = formatQuantity(base, unit).replaceAll(' ', ' ').trim();
  final space = text.lastIndexOf(' ');
  if (space <= 0) return (number: text, unit: '');
  return (number: text.substring(0, space), unit: text.substring(space + 1));
}

/// Cifra grande con su unidad más pequeña al lado («610,00 Bs», «10 L»). Si
/// no cabe, se reduce entera (nunca se corta ni se parte).
class BigFigure extends StatelessWidget {
  const BigFigure({
    super.key,
    required this.number,
    required this.unit,
    this.size = 32,
    this.color = AgroColors.ink,
    this.unitColor,
    this.alignment = Alignment.centerLeft,
    this.numberKey,
  });

  final String number;
  final String unit;
  final double size;
  final Color color;
  final Color? unitColor;
  final Alignment alignment;
  final Key? numberKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: unit.isEmpty ? number : '$number $unit',
    excludeSemantics: true,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            number,
            key: numberKey,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AgroFonts.display,
              fontSize: size,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: size >= 40 ? -1.5 : -0.3,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit.isNotEmpty) ...[
            SizedBox(width: size / 8),
            Text(
              unit,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AgroFonts.display,
                fontSize: (size * 0.45).clamp(14, 24).toDouble(),
                fontWeight: FontWeight.w700,
                color: unitColor ?? color,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Título grande de una pantalla principal («Almacén») con acciones
/// redondas a la derecha. Si no caben, las acciones bajan de línea: el
/// título no se parte dentro de una palabra.
class ScreenTitleBar extends StatelessWidget {
  const ScreenTitleBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.subtitle,
    this.compact = false,
  });

  final String title;

  /// Título de 26 px para pantallas apiladas («Avisos de inventario»); las
  /// principales usan 32.
  final bool compact;
  final List<Widget> actions;
  final Widget? leading;

  /// Contexto breve sobre el título («Cuenta · Invierno 2026»).
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null || subtitle != null)
          Row(
            children: [
              if (leading != null) leading!,
              if (leading != null && subtitle != null) const SizedBox(width: 8),
              if (subtitle != null)
                Expanded(child: Text(subtitle!, style: AgroText.detail)),
            ],
          ),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  key: const Key('page-frame-title'),
                  style: TextStyle(
                    fontFamily: AgroFonts.display,
                    fontSize: compact ? 26 : 32,
                    height: compact ? 32 / 26 : 38 / 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AgroColors.ink,
                  ),
                ),
              ),
              if (actions.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Tono del punto de una [LinkRow]. El texto dice siempre lo mismo que el
/// color.
enum DotTone { danger, caution, neutral, ok }

Color dotColor(DotTone tone) => switch (tone) {
  DotTone.danger => AgroColors.danger,
  DotTone.caution => const Color(0xFFC77700),
  DotTone.neutral => AgroColors.muted,
  DotTone.ok => AgroColors.link,
};

/// Fila de un [AgroGroup] que lleva a otra pantalla: punto o icono, texto,
/// detalle opcional, dato a la derecha y flecha.
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.title,
    this.subtitle,
    this.dot,
    this.icon,
    this.trailing,
    this.onTap,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final DotTone? dot;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        child: Row(
          children: [
            if (dot != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor(dot!),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
            ] else if (icon != null) ...[
              IconCircle(icon: icon!),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style:
                        titleStyle ??
                        const TextStyle(
                          fontSize: 15,
                          height: 20 / 15,
                          fontWeight: FontWeight.w500,
                          color: AgroColors.ink,
                        ),
                  ),
                  if (subtitle != null) Text(subtitle!, style: AgroText.detail),
                ],
              ),
            ),
            // Flexible: con letra grande el dato de la derecha se acomoda
            // (parte línea) en vez de desbordar la fila.
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Flexible(child: trailing!),
            ],
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AgroColors.muted,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Círculo de 40 px con un icono (tipo de operación, acceso).
class IconCircle extends StatelessWidget {
  const IconCircle({
    super.key,
    required this.icon,
    this.background = AgroColors.chip,
    this.foreground = AgroColors.ink,
    this.size = 40,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(icon, size: size * 0.55, color: foreground),
  );
}

/// Pastilla de filtro («Todo», «Compras»). La elegida, en verde oscuro con
/// negrita y marca: no se distingue sólo por color.
class FilterPill extends StatefulWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<FilterPill> {
  bool get selected => widget.selected;
  String get label => widget.label;
  VoidCallback get onSelected => widget.onSelected;

  /// La pastilla elegida queda entera a la vista en su fila desplazable
  /// (revisión del orquestador, entrega 2).
  @override
  void didUpdateWidget(FilterPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Sólo la fila de pastillas: `Scrollable.ensureVisible` movería
        // también la página hacia arriba o abajo.
        final row = Scrollable.maybeOf(context);
        final box = context.findRenderObject();
        if (row == null || box == null) return;
        row.position.ensureVisible(
          box,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AgroColors.ink : AgroColors.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onSelected,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check, size: 16, color: AgroColors.lime),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : AgroColors.ink,
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

/// Fila de pastillas que se desplaza en horizontal.
class FilterPillBar extends StatelessWidget {
  const FilterPillBar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ],
    ),
  );
}

/// Rótulo de grupo en mayúsculas pequeñas («POR HACER», «NOVIEMBRE»).
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AgroColors.muted,
        ),
      ),
    ),
  );
}

/// Contenido desplazable de una pantalla principal del rediseño: fondo del
/// tema, márgenes de 16 y espacio final para que el botón flotante y el
/// teclado no tapen la última fila (como `PageFrame`). Construye todo el
/// contenido, como `PageFrame`: lo que queda fuera de la vista existe para
/// la accesibilidad y las pruebas.
class RdmScrollPage extends StatelessWidget {
  const RdmScrollPage({
    super.key,
    required this.children,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  /// Cabecera a todo el ancho, sin márgenes (la oscura de Inicio).
  final Widget? header;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bottom =
        24 +
        ContentInsets.of(context) +
        MediaQuery.viewInsetsOf(context).bottom;
    return CustomScrollView(
      // Siempre desplazable: «tirar para actualizar» funciona aunque el
      // contenido quepa en la pantalla.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Cabecera y contenido en un solo bloque: con letra grande la
        // cabecera puede ocupar la pantalla, y el contenido sigue existiendo
        // (para la accesibilidad y las pruebas) aunque esté debajo.
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) header!,
              Padding(
                padding: padding.copyWith(bottom: bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// «Volver» redondo para las pantallas apiladas del rediseño: sólo aparece
/// si hay adónde volver, y respeta el `PopScope` de la página como el Atrás
/// del sistema (mismo criterio que `PageFrame`).
class RdmBackButton extends StatelessWidget {
  const RdmBackButton({
    super.key,
    this.background = AgroColors.surface,
    this.foreground = AgroColors.ink,
  });

  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    // Se recalcula con cada cambio de la pila (como `PageFrame`): si no,
    // quedaba una flecha que no llevaba a ningún sitio (2026-11-05).
    if (router == null) return _build(context, null);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _build(context, router),
    );
  }

  Widget _build(BuildContext context, GoRouter? router) {
    final navigator = Navigator.maybeOf(context);
    final canPop =
        (router?.canPop() ?? false) || (navigator?.canPop() ?? false);
    if (!canPop) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _CircleBack(
        background: background,
        foreground: foreground,
        onPressed: () {
          if (navigator != null && navigator.canPop()) {
            navigator.maybePop();
          } else {
            router?.pop();
          }
        },
      ),
    );
  }
}

class _CircleBack extends StatelessWidget {
  const _CircleBack({
    required this.background,
    required this.foreground,
    required this.onPressed,
  });
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Volver',
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      minimumSize: const Size.square(44),
      fixedSize: const Size.square(44),
      padding: EdgeInsets.zero,
    ),
    icon: const Icon(Icons.arrow_back, size: 22),
  );
}
