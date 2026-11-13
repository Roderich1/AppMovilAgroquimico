/// Piezas de presentación de «Chacos» del modo individual (sesión C,
/// 2026-11-13; láminas I-40 a I-43). No leen datos ni deciden reglas: cada
/// pantalla les pasa lo que muestran.
library;

import 'package:flutter/material.dart';

import '../../data/ind_c_chacos_reads.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'rdm_b_ui.dart' show BigFigure, splitBob;

/// «Invierno 2026» o «todas las campañas».
String indCScopeName(IndCCampaign? campaign) =>
    campaign?.name ?? 'todas las campañas';

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// «2 aplicaciones · 1 plan por hacer» o «Sin aplicaciones en esta campaña».
String indCFarmActivityLine(IndCFarm farm, IndCCampaign? campaign) {
  final parts = <String>[
    if (farm.applicationCount > 0)
      _plural(farm.applicationCount, 'aplicación', 'aplicaciones')
    else
      campaign == null
          ? 'Sin aplicaciones registradas'
          : 'Sin aplicaciones en esta campaña',
    if (farm.pendingPlanCount > 0)
      _plural(farm.pendingPlanCount, 'plan por hacer', 'planes por hacer'),
  ];
  return parts.join(' · ');
}

/// Por qué no hay costo por hectárea; `null` si se puede calcular.
String? indCPerHectareUnavailableReason(IndCFarm farm) {
  if (!farm.hasArea) return 'Falta registrar la superficie del chaco.';
  if (farm.applicationCount == 0) {
    return 'Sin aplicaciones en este alcance: no hay costo que repartir.';
  }
  if (farm.costPerHectareMinor == null) {
    return 'No se puede calcular con los datos guardados.';
  }
  return null;
}

/// «Superficie tratada acumulada: 4 ha en 2 aplicaciones». Si alguna no
/// tiene superficie registrada, lo dice; sin ninguna, `null`.
String? indCTreatedAreaLine(IndCFarm farm) {
  if (farm.applicationCount == 0 || farm.applicationsWithTreatedArea == 0) {
    return null;
  }
  final base =
      'Superficie tratada acumulada: ${formatHectares(farm.treatedAreaM2)}';
  if (farm.applicationsWithTreatedArea == farm.applicationCount) {
    return '$base en '
        '${_plural(farm.applicationCount, 'aplicación', 'aplicaciones')}';
  }
  return '$base en ${farm.applicationsWithTreatedArea} de '
      '${_plural(farm.applicationCount, 'aplicación', 'aplicaciones')} '
      '(las demás no tienen superficie registrada)';
}

/// Tarjeta oscura con una cifra grande (I-40 «Costos · Invierno 2026», I-42
/// «Costo de productos aplicados»). Con [number] nulo muestra [emptyText] en
/// vez de un cero.
class IndCDarkFigureCard extends StatelessWidget {
  const IndCDarkFigureCard({
    super.key,
    required this.label,
    required this.number,
    required this.note,
    this.emptyText,
    this.onTap,
    this.numberKey,
  });

  final String label;
  final String? number;
  final String note;
  final String? emptyText;
  final VoidCallback? onTap;
  final Key? numberKey;

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.ink,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 22 / 15,
                      color: AgroColors.onInkMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (number != null)
                    BigFigure(
                      number: number!,
                      unit: 'Bs',
                      size: 44,
                      color: Colors.white,
                      unitColor: AgroColors.lime,
                      numberKey: numberKey,
                    )
                  else
                    Text(
                      emptyText ?? '',
                      style: const TextStyle(
                        fontFamily: AgroFonts.display,
                        fontSize: 20,
                        height: 26 / 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 22 / 15,
                      color: AgroColors.onInk,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AgroColors.lime),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Tarjeta blanca de un chaco en la lista (I-40).
class IndCFarmCard extends StatelessWidget {
  const IndCFarmCard({
    super.key,
    required this.farm,
    required this.campaign,
    required this.showOwner,
    required this.onTap,
  });

  final IndCFarm farm;
  final IndCCampaign? campaign;

  /// En el modo con varias personas se dice de quién es el chaco.
  final bool showOwner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final area = farm.hasArea ? formatHectares(farm.areaM2) : null;
    // Con la letra muy ampliada la superficie va debajo del nombre: a la
    // derecha dejaba una palabra por línea en los nombres largos.
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 15;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('ind-chaco-${farm.farmId}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        farm.name,
                        style: const TextStyle(
                          fontSize: 19,
                          height: 25 / 19,
                          fontWeight: FontWeight.w700,
                          color: AgroColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (showOwner) farm.ownerName,
                          indCFarmActivityLine(farm, campaign),
                        ].join(' · '),
                        style: AgroText.detail.copyWith(fontSize: 15),
                      ),
                      if (stacked && area != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          area,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.ink,
                          ),
                        ),
                      ],
                      if (!farm.hasArea) ...[
                        const SizedBox(height: 6),
                        const StatusBadge(
                          key: Key('ind-chaco-sin-superficie'),
                          label: 'Falta la superficie',
                          tone: BadgeTone.review,
                        ),
                      ],
                    ],
                  ),
                ),
                if (area != null && !stacked) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: BigFigure(
                      number: area.substring(0, area.length - 3),
                      unit: 'ha',
                      size: 26,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AgroColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Estado vacío de Chacos (I-43).
class IndCNoFarms extends StatelessWidget {
  const IndCNoFarms({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 8),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AgroColors.ink,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.grid_on, color: AgroColors.lime, size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          'Agregue su primer chaco',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AgroFonts.display,
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.w800,
            color: AgroColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Con el nombre y la superficie podrá registrar aplicaciones y ver '
          'sus costos por chaco.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 24 / 16,
            color: AgroColors.muted,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('ind-chacos-agregar'),
          onPressed: onAdd,
          style: FilledButton.styleFrom(
            backgroundColor: AgroColors.lime,
            foregroundColor: AgroColors.ink,
            minimumSize: const Size(180, 56),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            textStyle: const TextStyle(
              fontFamily: AgroFonts.body,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Agregar chaco', textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}

/// Fila «etiqueta … valor» de una tarjeta de costos (I-42). El valor se va
/// debajo si no cabe al lado.
class IndCCostLine extends StatelessWidget {
  const IndCCostLine({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = AgroColors.ink,
    this.valueKey,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(label, style: AgroText.detail.copyWith(fontSize: 15)),
        Text(
          value,
          key: valueKey,
          style: TextStyle(
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

/// Tarjeta de un chaco en «Costos › Por chaco» (I-42).
class IndCFarmCostCard extends StatelessWidget {
  const IndCFarmCostCard({
    super.key,
    required this.farm,
    required this.showOwner,
    this.onTap,
  });

  final IndCFarm farm;
  final bool showOwner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final perHectare = farm.costPerHectareMinor;
    final reason = indCPerHectareUnavailableReason(farm);
    final treated = indCTreatedAreaLine(farm);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('ind-costo-chaco-${farm.farmId}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      farm.name,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 25 / 19,
                        fontWeight: FontWeight.w700,
                        color: AgroColors.ink,
                      ),
                    ),
                    if (farm.applicationCount > 0)
                      BigFigure(
                        number: splitBob(farm.appliedCostMinor).number,
                        unit: 'Bs',
                        size: 24,
                        alignment: Alignment.centerRight,
                        numberKey: Key('ind-costo-chaco-total-${farm.farmId}'),
                      )
                    else
                      Text(
                        'Sin aplicaciones',
                        style: AgroText.detail.copyWith(fontSize: 15),
                      ),
                  ],
                ),
                if (showOwner || !farm.active)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (showOwner) farm.ownerName,
                        if (!farm.active) 'Chaco archivado',
                      ].join(' · '),
                      style: AgroText.detail,
                    ),
                  ),
                IndCCostLine(
                  label: perHectare == null
                      ? 'Costo por hectárea'
                      : 'Costo por hectárea · sobre '
                            '${formatHectares(farm.areaM2)} del chaco',
                  value: perHectare == null
                      ? 'No disponible'
                      : formatBob(perHectare),
                  valueColor: perHectare == null
                      ? AgroColors.caution
                      : AgroColors.ink,
                  valueKey: Key('ind-costo-ha-${farm.farmId}'),
                ),
                if (reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 22 / 15,
                        color: AgroColors.caution,
                      ),
                    ),
                  ),
                if (treated != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      treated,
                      style: AgroText.detail.copyWith(fontSize: 15),
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

/// Fila «nombre … cifra» dentro de un [AgroGroup], con detalle opcional.
class IndCValueRow extends StatelessWidget {
  const IndCValueRow({
    super.key,
    required this.title,
    required this.value,
    this.detail,
    this.struck = false,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String value;
  final String? detail;
  final bool struck;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    height: 24 / 18,
                    fontWeight: FontWeight.w700,
                    color: struck ? AgroColors.muted : AgroColors.ink,
                    decoration: struck ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (detail != null)
                  Text(detail!, style: AgroText.detail.copyWith(fontSize: 15)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 17,
                height: 24 / 17,
                fontWeight: FontWeight.w700,
                color: struck ? AgroColors.muted : AgroColors.ink,
                decoration: struck ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    ),
  );
}
