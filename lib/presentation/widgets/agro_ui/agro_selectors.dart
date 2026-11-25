import 'package:flutter/material.dart';

import '../../theme/agro_theme.dart';
import '../common.dart' show measureText;

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
