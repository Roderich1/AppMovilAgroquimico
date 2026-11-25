import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/agro_theme.dart';
import 'agro_buttons.dart';

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
