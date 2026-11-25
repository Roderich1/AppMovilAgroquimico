import 'package:flutter/material.dart';

import '../../theme/agro_theme.dart';
import 'agro_buttons.dart';

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
