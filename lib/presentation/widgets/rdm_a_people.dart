/// Piezas de presentación de la sesión A para el grupo Personas (personas,
/// persona, cuentas, movimientos propios, costos por chaco y bitácora). No
/// guardan datos ni deciden reglas: cada pantalla les pasa lo que muestran.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'rdm_b_ui.dart' show BigFigure;

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// «Noviembre 2026» para un día `aaaa-mm-dd`.
String rdmAMonthLabel(String day) {
  final month = int.parse(day.substring(5, 7));
  final name = _months[month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${day.substring(0, 4)}';
}

/// «nov» para un día `aaaa-mm-dd`.
String rdmAMonthShort(String day) =>
    _months[int.parse(day.substring(5, 7)) - 1].substring(0, 3);

/// «Volver» de una página apilada: respeta el `PopScope` de la página (como
/// `PageFrame`); si el Navigator no puede retroceder, retrocede el router.
void rdmABack(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.maybePop();
  } else {
    GoRouter.maybeOf(context)?.pop();
  }
}

/// Si la página tiene a dónde volver (pila del router).
bool rdmACanPop(BuildContext context) =>
    GoRouter.maybeOf(context)?.canPop() ?? false;

/// Cabecera oscura del prototipo (Persona, Bitácora, Personas): «Volver» si
/// hay a dónde, un rótulo breve, acciones redondas, el título grande en
/// blanco, una línea de contexto y lo que la pantalla ponga debajo (cifras,
/// selector). Esquinas inferiores redondeadas.
class RdmAHero extends StatelessWidget {
  const RdmAHero({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleKey,
    this.overline,
    this.actions = const [],
    this.children = const [],
    this.showBack,
  });

  final String title;
  final String? subtitle;
  final Key? subtitleKey;

  /// Rótulo breve junto a «Volver» («Bitácora»).
  final String? overline;
  final List<Widget> actions;
  final List<Widget> children;

  /// Fuerza mostrar u ocultar «Volver»; por omisión, si el router puede
  /// retroceder.
  final bool? showBack;

  static const subtitleStyle = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    color: AgroColors.onInkMuted,
  );

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null || showBack != null) {
      return _build(context, showBack ?? false);
    }
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _build(context, router.canPop()),
    );
  }

  Widget _build(BuildContext context, bool back) => Container(
    decoration: const BoxDecoration(
      color: AgroColors.ink,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      12 + MediaQuery.paddingOf(context).top,
      20,
      20,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (back || overline != null || actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                if (back) ...[
                  CircleIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Volver',
                    background: AgroColors.inkSoft,
                    foreground: AgroColors.onInk,
                    onPressed: () => rdmABack(context),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: overline == null
                      ? const SizedBox.shrink()
                      : Text(
                          overline!,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.onInkMuted,
                          ),
                        ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: 8),
                  action,
                ],
              ],
            ),
          ),
        Semantics(
          header: true,
          child: Text(
            title,
            key: const Key('page-frame-title'),
            style: const TextStyle(
              fontFamily: AgroFonts.display,
              fontSize: 30,
              height: 36 / 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, key: subtitleKey, style: subtitleStyle),
          ),
        if (children.isNotEmpty) ...[const SizedBox(height: 16), ...children],
      ],
    ),
  );
}

/// Recuadro de una cifra dentro de la cabecera oscura («Aplicado 720,00
/// Bs»).
class RdmAStatTile extends StatelessWidget {
  const RdmAStatTile({
    super.key,
    required this.label,
    required this.number,
    required this.unit,
    this.numberKey,
    this.note,
  });

  final String label;
  final String number;
  final String unit;
  final Key? numberKey;

  /// Aclaración breve bajo la cifra («todas las campañas»).
  final String? note;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AgroColors.inkSoft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RdmAHero.subtitleStyle),
        const SizedBox(height: 2),
        BigFigure(
          number: number,
          unit: unit,
          size: 26,
          color: Colors.white,
          numberKey: numberKey,
        ),
        if (note != null)
          Text(
            note!,
            style: const TextStyle(
              fontSize: 12,
              height: 16 / 12,
              color: AgroColors.onInkMuted,
            ),
          ),
      ],
    ),
  );
}

/// Dos [RdmAStatTile] lado a lado; si no caben a la letra actual, una debajo
/// de la otra.
class RdmAStatPair extends StatelessWidget {
  const RdmAStatPair({super.key, required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth / 2 >= 150 * scale) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: first),
              const SizedBox(width: 10),
              Expanded(child: second),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 10), second],
      );
    },
  );
}

/// Día de un movimiento: el número grande y el mes abreviado debajo.
class RdmADayBadge extends StatelessWidget {
  const RdmADayBadge({super.key, required this.day});

  /// `aaaa-mm-dd`.
  final String day;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${int.parse(day.substring(8, 10))}',
          style: const TextStyle(
            fontFamily: AgroFonts.display,
            fontSize: 22,
            height: 26 / 22,
            fontWeight: FontWeight.w800,
            color: AgroColors.ink,
          ),
        ),
        Text(
          rdmAMonthShort(day),
          style: const TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w700,
            color: AgroColors.muted,
          ),
        ),
      ],
    ),
  );
}
