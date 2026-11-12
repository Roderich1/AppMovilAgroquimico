/// Presentación de las compras conjuntas en el rediseño (sesión C). Los
/// textos de estado, consentimiento y alcance son los vigentes de
/// `joint_purchase_texts.dart` (CONV-3, E2 §10.6); aquí sólo se dibujan.
library;

import 'package:flutter/material.dart';

import '../theme/agro_theme.dart';
import 'agro_ui.dart';

/// Tono de una etiqueta de convocatoria o de participación. El texto dice el
/// estado; el tono sólo lo acompaña: abierta, nueva o recibido → verde;
/// pendiente → ámbar; fuera de plazo o rechazada → rojo; cerrada, cancelada
/// o sin efecto → gris.
BadgeTone jointPurchaseChipTone(String chip) {
  if (chip.startsWith('Rechazada') || chip == 'Fuera de plazo') {
    return BadgeTone.missing;
  }
  if (chip.startsWith('Pendiente')) return BadgeTone.review;
  if (chip == 'Nueva' ||
      chip == 'Abierta' ||
      chip.endsWith('recibida') ||
      chip.endsWith('recibido')) {
    return BadgeTone.ok;
  }
  return BadgeTone.neutral;
}

/// Etiquetas de estado en fila (se parten en varias líneas si no caben).
class JointBadges extends StatelessWidget {
  const JointBadges(this.chips, {super.key});
  final List<String> chips;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final chip in chips)
        StatusBadge(label: chip, tone: jointPurchaseChipTone(chip)),
    ],
  );
}

/// Línea con icono y un texto ya redactado (con su clave, para que las
/// pruebas lean el texto exacto).
class JointInfoLine extends StatelessWidget {
  const JointInfoLine({
    super.key,
    required this.text,
    required this.textKey,
    this.icon = Icons.info_outline,
    this.strong = false,
  });

  final String text;
  final Key textKey;
  final IconData icon;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: AgroColors.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            key: textKey,
            style: strong
                ? AgroText.detail.copyWith(
                    color: AgroColors.ink,
                    fontWeight: FontWeight.w700,
                  )
                : AgroText.detail.copyWith(color: AgroColors.ink),
          ),
        ),
      ],
    ),
  );
}
