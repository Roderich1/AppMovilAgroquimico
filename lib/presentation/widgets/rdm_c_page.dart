/// Piezas de presentación de la sesión C del rediseño (Sindicato, vínculos,
/// identificación, necesidad, consumo, sincronización). Candidatas a
/// promoverse a `agro_ui.dart` si el orquestador lo decide; mientras tanto
/// sólo las usan las pantallas de la sesión C. No guardan datos ni deciden
/// reglas: cada pantalla les pasa su estado.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/sync/sync_types.dart' show OutboxStatus;
import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'common.dart' show ContentInsets, measureText;

/// Escala de la letra para un título grande (30 o 26 px) en [maxWidth]:
/// sigue la del teléfono hasta 1,4× y, si aun así la palabra más larga
/// («Sincronización», «identificación») no cabe entera en la línea, baja
/// sólo lo necesario para que no se parta por dentro. El texto del
/// contenido sigue la escala completa del teléfono.
TextScaler rdmCTitleScaler(
  BuildContext context,
  String title,
  TextStyle style,
  double maxWidth,
) {
  final phone = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
  if (!maxWidth.isFinite) return phone;
  var longest = 0.0;
  for (final word in title.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final width = measureText(
      context,
      word,
      style,
      textScaler: TextScaler.noScaling,
    );
    if (width > longest) longest = width;
  }
  if (longest == 0) return phone;
  final fit = (maxWidth - 1) / longest;
  final current = phone.scale(1);
  return fit >= current ? phone : TextScaler.linear(fit);
}

/// Título grande que nunca parte una palabra por dentro (ver
/// [rdmCTitleScaler]).
class RdmCTitle extends StatelessWidget {
  const RdmCTitle(this.title, {super.key, required this.style, this.textKey});
  final String title;
  final TextStyle style;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Text(
      title,
      key: textKey,
      style: style,
      textScaler: rdmCTitleScaler(context, title, style, constraints.maxWidth),
    ),
  );
}

/// [SegmentToggle] que, si con la letra actual algún rótulo no cabe en su
/// mitad sin partir una palabra, apila las opciones una debajo de otra con
/// el mismo aspecto (elegida en verde oscuro, negrita y marca).
class RdmCToggle<T> extends StatelessWidget {
  const RdmCToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<ToggleOption<T>> options;
  final T? selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  static const _style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // 8 de la pista, 4 entre opciones, 16 de relleno y 20 de la marca.
      final segment =
          (constraints.maxWidth - 8 - 4 * (options.length - 1)) /
              options.length -
          36;
      final fits = options.every(
        (option) => measureText(context, option.label, _style) <= segment,
      );
      if (fits) {
        return SegmentToggle<T>(
          options: options,
          selected: selected,
          onChanged: onChanged,
          semanticLabel: semanticLabel,
        );
      }
      return Semantics(
        label: semanticLabel,
        container: true,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AgroColors.track,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                _stacked(options[i]),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _stacked(ToggleOption<T> option) {
    final on = option.value == selected;
    return Semantics(
      key: option.key,
      button: true,
      selected: on,
      inMutuallyExclusiveGroup: true,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        color: on ? AgroColors.ink : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(option.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

/// Página de consulta con la cabecera del prototipo: «Volver» redondo a la
/// izquierda, una acción breve a la derecha y el título grande debajo.
///
/// Conserva el comportamiento de `PageFrame`: la flecha sólo aparece si el
/// router puede retroceder, respeta el `PopScope` de la página y el
/// contenido termina por encima del FAB global y del teclado.
class RdmCPage extends StatelessWidget {
  const RdmCPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;

  /// Acción breve de la cabecera («Actualizar», «Declarar»). Lleva texto:
  /// un icono solo no dice qué hace.
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
                      // de «Volver» y, si con la letra ampliada no cabe, baja
                      // a la línea siguiente sin partir su rótulo.
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
                    child: RdmCTitle(
                      title,
                      textKey: const Key('page-frame-title'),
                      style: AgroText.h1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: AgroText.detail),
                  ],
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

/// Acción breve de cabecera: borde redondeado, icono y texto, 44 px.
class RdmCHeaderAction extends StatelessWidget {
  const RdmCHeaderAction({
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
      backgroundColor: AgroColors.surface,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
    ),
    icon: Icon(icon, size: 20),
    label: Text(label),
  );
}

/// Fila de un grupo blanco: título, detalle, etiquetas de estado, acciones y
/// un menú de opciones o una flecha a la derecha. El estado siempre va en
/// palabras (las etiquetas y el detalle), nunca sólo en el color.
class RdmCRow extends StatelessWidget {
  const RdmCRow({
    super.key,
    required this.title,
    this.detail,
    this.badges = const [],
    this.notes = const [],
    this.actions = const [],
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? detail;
  final List<Widget> badges;

  /// Avisos breves debajo del detalle (texto ya redactado por la pantalla).
  final List<String> notes;
  final List<Widget> actions;

  /// Menú de opciones; sin él y con [onTap], una flecha.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, 14, trailing == null ? 12 : 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AgroText.value),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail!, style: AgroText.detail),
                  ),
                if (badges.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, children: badges),
                  ),
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      note,
                      style: AgroText.detail.copyWith(color: AgroColors.ink),
                    ),
                  ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right, color: AgroColors.muted),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    // Material propio: dentro de un grupo blanco la tinta del toque se ve.
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Menú «Opciones» de una fila (los tres puntos del prototipo), con nombre
/// accesible.
class RdmCOptionsMenu extends StatelessWidget {
  const RdmCOptionsMenu({
    super.key,
    required this.tooltip,
    required this.items,
    required this.onSelected,
  });

  final String tooltip;
  final List<PopupMenuEntry<String>> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tooltip,
    icon: const Icon(Icons.more_vert, color: AgroColors.ink),
    onSelected: onSelected,
    itemBuilder: (_) => items,
  );
}

/// Abre una hoja inferior con el fondo del rediseño. El contenido suele ser
/// un [RdmCSheetBody].
Future<T?> showRdmCSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  backgroundColor: AgroColors.canvas,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: builder,
);

/// Cuerpo de una hoja: título grande con «Cerrar», subtítulo, contenido que
/// se desplaza y acciones abajo.
class RdmCSheetBody extends StatelessWidget {
  const RdmCSheetBody({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;

  /// Por defecto cierra la hoja sin resultado.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      namesRoute: true,
                      child: RdmCTitle(title, style: AgroText.sheetTitle),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: AgroText.detail),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CircleIconButton(
                icon: Icons.close,
                tooltip: 'Cerrar',
                onPressed: onClose ?? () => Navigator.maybePop(context),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            // Cada acción ocupa todo el ancho si no caben dos: con la letra
            // ampliada no se cortan los rótulos.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = actions.length == 1
                    ? constraints.maxWidth
                    : _halfOrFull(context, constraints.maxWidth);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final action in actions)
                      SizedBox(width: width, child: action),
                  ],
                );
              },
            ),
          ),
      ],
    ),
  );

  static double _halfOrFull(BuildContext context, double width) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final half = (width - 10) / 2;
    return half >= 150 * scale ? half : width;
  }
}

/// Rótulo de sección pequeño en mayúsculas («SE ENVIARÁ SÓLO ESTO»).
class RdmCOverline extends StatelessWidget {
  const RdmCOverline(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AgroColors.muted,
        ),
      ),
    ),
  );
}

/// «Rótulo ……… valor» de sólo lectura dentro de un [AgroGroup]. Si no cabe
/// en una línea, el valor baja debajo del rótulo.
class RdmCInfoRow extends StatelessWidget {
  const RdmCInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(label, style: AgroText.detail.copyWith(fontSize: 15)),
        Text(
          value,
          key: valueKey,
          style: AgroText.value.copyWith(fontSize: 16),
        ),
      ],
    ),
  );
}

/// Tono de la etiqueta del estado de un envío al sindicato. La palabra la
/// pone la pantalla (`outboxStatusPhrase`…); el tono sólo la acompaña:
/// aceptado → verde; en camino o pausado → ámbar; conflicto o rechazo →
/// rojo; sin envío o descartado → gris.
BadgeTone rdmCOutboxTone(OutboxStatus? status) => switch (status) {
  OutboxStatus.acked => BadgeTone.voice,
  OutboxStatus.conflict ||
  OutboxStatus.rejected ||
  OutboxStatus.failed => BadgeTone.missing,
  null || OutboxStatus.discarded => BadgeTone.neutral,
  _ => BadgeTone.review,
};

/// Fila gris que lleva a otra pantalla: una frase y la flecha.
class RdmCLinkRow extends StatelessWidget {
  const RdmCLinkRow({
    super.key,
    required this.text,
    required this.onTap,
    this.semanticsHint,
  });

  final String text;
  final VoidCallback onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    hint: semanticsHint,
    child: Material(
      color: AgroColors.track,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      color: AgroColors.ink,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AgroColors.muted),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Estado vacío breve dentro de un grupo blanco.
class RdmCEmpty extends StatelessWidget {
  const RdmCEmpty({super.key, required this.message, this.icon});
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => AgroGroup(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon ?? Icons.inbox_outlined, color: AgroColors.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: AgroText.detail)),
          ],
        ),
      ),
    ],
  );
}
