/// Piezas de Personas (ronda 2, sesión C): las tarjetas de la única lista de
/// personas (área «Cuentas») y el análisis de costos (área «Costos»).
///
/// Antes había dos listas de las mismas personas: Personas (cifra de todas
/// las campañas) y Cuentas (`/liquidacion`, con filtro, costos y respaldos,
/// tarjetas más largas). Ahora la lista es una y estas tarjetas reúnen lo de
/// las dos. No guardan datos ni deciden reglas: textos y cifras son los de
/// D-04/E-15 (`account_texts.dart`), sin cálculos nuevos.
library;

import 'package:flutter/material.dart';

import '../../domain/read_models.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'common.dart';
import 'rdm_b_ui.dart' show BigFigure, splitBob;

/// Áreas de Personas.
enum PersonsArea { accounts, costs }

/// «Familiar · 2 ha», o la de un ADMIN, que no participa en la liquidación.
String rdm2cRoleLine(Map<String, Object?>? profile, {bool owner = false}) {
  if (profile == null) return '';
  final role = personRoleLabel(profile['role']);
  if (profile['role'] == 'ADMIN' && !owner) {
    return '$role · no participa en la liquidación';
  }
  final area = formatHectares((profile['area_m2'] as int?) ?? 0);
  return owner ? '$role · titular · $area' : '$role · $area';
}

const _actionText = TextStyle(
  fontFamily: AgroFonts.body,
  fontSize: 14,
  fontWeight: FontWeight.w700,
);

/// Tarjeta de una persona de la liquidación (D-04 §2.3): nombre y rol, las
/// líneas contables del alcance, la cifra con su rótulo y las acciones.
/// Tocarla abre la ficha de la persona.
class Rdm2cAccountCard extends StatelessWidget {
  const Rdm2cAccountCard({
    super.key,
    required this.row,
    required this.profile,
    required this.campaignName,
    required this.filtered,
    required this.onPay,
    required this.blockedNote,
    required this.onStatement,
    required this.onExport,
    required this.onOpen,
  });

  final AccountSummary row;
  final Map<String, Object?>? profile;

  /// Campaña del filtro, o nulo con «Todas las campañas».
  final String? campaignName;
  final bool filtered;

  /// Nulo si no se le pueden registrar pagos (inventario propio).
  final VoidCallback? onPay;

  /// Por qué no hay «Registrar pago», si no lo hay.
  final String? blockedNote;
  final VoidCallback onStatement;
  final VoidCallback onExport;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final account = row.account;
    final amount = filtered ? row.scope.pendingMinor : account.netMinor;
    final lines = filtered
        ? [
            chargesLine(row.scope, campaignName: campaignName),
            netLine(account),
            ?unattributedCreditLine(account),
          ]
        : [chargesLine(row.scope), pendingAndCreditLine(account)];
    final caption = filtered
        ? pendingCaption(campaignName ?? 'campaña')
        : netCaptionAll;
    final id = row.personId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: Key('account-card-$id'),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Entero: el nombre se parte, no se recorta.
                                Text(row.name, style: AgroText.value),
                                if (profile != null)
                                  Text(
                                    rdm2cRoleLine(profile),
                                    style: AgroText.detail,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Más opciones de ${row.name}',
                          onSelected: (value) => switch (value) {
                            'detail' => onStatement(),
                            _ => onExport(),
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'detail',
                              child: Text('Ver detalle cronológico'),
                            ),
                            // El estado de cuenta se exporta desde donde se
                            // consulta (Excel o PDF, en Reportes).
                            PopupMenuItem(
                              value: 'export',
                              child: Text('Exportar estado de cuenta'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Rdm2cAccountFigures(
                        lines: lines,
                        caption: caption,
                        amount: amount,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (onPay != null)
                    // Dos claves: la de Cuentas y la de Personas, que ahora
                    // son la misma tarjeta.
                    KeyedSubtree(
                      key: Key('person-pay-$id'),
                      child: FilledButton(
                        key: Key('account-pay-$id'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          textStyle: _actionText,
                        ),
                        onPressed: onPay,
                        child: const Text('Registrar pago'),
                      ),
                    ),
                  TextButton(
                    key: Key('person-statement-$id'),
                    style: TextButton.styleFrom(
                      foregroundColor: AgroColors.link,
                      minimumSize: const Size(0, 44),
                      textStyle: _actionText,
                    ),
                    onPressed: onStatement,
                    child: const Text('Ver cuenta'),
                  ),
                  if (blockedNote != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        blockedNote!,
                        key: Key('account-pay-blocked-$id'),
                        style: AgroText.detail,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cifras de la tarjeta de una persona: las líneas contables y el importe
/// con su rótulo. Con sitio (≥ [wideWidth]) van lado a lado; en teléfono el
/// importe pasa debajo, a lo ancho (F-2, 2026-10-30). El rótulo dice qué es
/// la cifra; el color no es lo único que lo dice.
class Rdm2cAccountFigures extends StatelessWidget {
  const Rdm2cAccountFigures({
    super.key,
    required this.lines,
    required this.caption,
    required this.amount,
  });

  static const double wideWidth = 420;

  final List<String> lines;
  final String caption;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines) Text(line, style: AgroText.detail)],
    );
    final figure = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(caption, style: AgroText.label, textAlign: TextAlign.end),
        Text(
          formatBob(amount),
          textAlign: TextAlign.end,
          style: AgroText.amount.copyWith(
            fontSize: 22,
            height: 28 / 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >=
            wideWidth * MediaQuery.textScalerOf(context).scale(1)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: detail),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: figure),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [detail, const SizedBox(height: 6), figure],
        );
      },
    );
  }
}

/// Tarjeta del titular vigente en la misma lista (E-15 §B.2): su consumo y
/// costos propios, que no son deuda. Sin «Registrar pago» (decisión del
/// autor del 2026-11-12). Tocarla abre su ficha.
class Rdm2cOwnCard extends StatelessWidget {
  const Rdm2cOwnCard({
    super.key,
    required this.ledger,
    required this.ownerId,
    required this.profile,
    required this.campaignId,
    required this.campaignName,
    required this.recordsLine,
    required this.onMovements,
    required this.onExport,
    required this.onOpen,
  });

  final AccountLedger ledger;
  final int ownerId;
  final Map<String, Object?>? profile;
  final int? campaignId;
  final String? campaignName;

  /// «Asientos en su cuenta · …» del alcance (E-15 §B.2).
  final String recordsLine;
  final VoidCallback onMovements;
  final VoidCallback onExport;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final person = ledger.account(ownerId).person;
    final consumption = ledger.ownConsumption(ownerId, campaignId: campaignId);
    const onInk = TextStyle(
      fontSize: 14,
      height: 20 / 14,
      color: AgroColors.onInk,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('own-consumption-card'),
        color: AgroColors.ink,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name,
                              style: AgroText.value.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            if (profile != null)
                              Text(
                                rdm2cRoleLine(profile, owner: true),
                                style: onInk.copyWith(
                                  color: AgroColors.onInkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones de lo propio',
                      iconColor: AgroColors.onInk,
                      onSelected: (value) => switch (value) {
                        'detail' => onMovements(),
                        _ => onExport(),
                      },
                      // Sin «Registrar pago»: el titular no se debe a sí
                      // mismo (decisión del autor del 2026-11-12).
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'detail',
                          child: Text('Ver movimientos propios'),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text('Exportar movimientos propios'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const StatusBadge(label: 'No es deuda', tone: BadgeTone.ok),
                    Text(
                      ownCardTitle,
                      style: onInk.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    ownConsumptionLine(consumption, campaignName: campaignName),
                    style: onInk.copyWith(
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(ownApplicationsLine(consumption), style: onInk),
                // Información secundaria: el registro de su cuenta.
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 2),
                  child: Text(
                    recordsLine,
                    style: onInk.copyWith(
                      fontSize: 13,
                      height: 18 / 13,
                      color: AgroColors.onInkMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: Key('person-statement-$ownerId'),
                    style: TextButton.styleFrom(
                      foregroundColor: AgroColors.lime,
                      minimumSize: const Size(0, 44),
                      textStyle: _actionText,
                    ),
                    onPressed: onMovements,
                    child: const Text('Ver movimientos propios'),
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

/// Persona ADMIN: está en Personas pero no en la liquidación (RN-41).
class Rdm2cAdminCard extends StatelessWidget {
  const Rdm2cAdminCard({
    super.key,
    required this.name,
    required this.profile,
    required this.onOpen,
  });

  final String name;
  final Map<String, Object?>? profile;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        onTap: onOpen,
        title: Text(name, style: AgroText.value),
        subtitle: Text(
          rdm2cRoleLine(profile ?? const {'role': 'ADMIN'}),
          style: AgroText.detail,
        ),
        trailing: const Icon(Icons.chevron_right, color: AgroColors.muted),
      ),
    ),
  );
}

/// Área «Costos»: costo por chaco y hectárea y costo por producto del
/// alcance elegido (aplicaciones no revertidas, H-22), con acceso a su
/// exportación. Los datos los lee la pantalla.
class Rdm2cCostsArea extends StatelessWidget {
  const Rdm2cCostsArea({
    super.key,
    required this.scope,
    required this.farmCosts,
    required this.productCosts,
    required this.onOpenFarm,
    required this.onExportFarms,
    required this.onExportProducts,
  });

  /// «Invierno 2026» o «todas las campañas».
  final String scope;
  final List<FarmCostRead> farmCosts;
  final List<ProductCostRead> productCosts;
  final ValueChanged<int> onOpenFarm;
  final VoidCallback onExportFarms;
  final VoidCallback onExportProducts;

  @override
  Widget build(BuildContext context) {
    final total = farmCosts.fold<int>(
      0,
      (sum, row) => sum + row.totalCostBobMinor,
    );
    return Column(
      key: const Key('persons-costs'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aplicaciones de $scope (sin las revertidas)',
          style: AgroText.detail,
        ),
        const SizedBox(height: 12),
        const Text('Costo por chaco y hectárea', style: AgroText.h2),
        const SizedBox(height: 10),
        if (farmCosts.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.grass_outlined,
              message: 'No hay chacos registrados.',
            ),
          ),
        for (final row in farmCosts)
          Rdm2cFarmCostCard(row: row, onTap: () => onOpenFarm(row.farmId)),
        if (farmCosts.isNotEmpty && total == 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Sin aplicaciones en este alcance.',
              style: AgroText.detail,
            ),
          ),
        const SizedBox(height: 12),
        const Text('Costo consumido por producto', style: AgroText.h2),
        const SizedBox(height: 10),
        if (productCosts.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Sin productos aplicados en este alcance.',
            ),
          )
        else
          AgroGroup(
            children: [
              for (final row in productCosts)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: AmountAside(
                    amount: formatBob(row.totalCostBobMinor),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.productName, style: AgroText.value),
                        Text(
                          formatQuantity(row.quantityBase, row.unit),
                          style: AgroText.detail,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 16),
        // Exportación de lo que se ve, con el mismo alcance (Excel o PDF).
        AgroGroup(
          children: [
            ValueRow(
              key: const Key('costs-export-farms'),
              label: 'Exportar · Excel o PDF',
              value: 'Costo por chaco',
              onTap: onExportFarms,
            ),
            ValueRow(
              key: const Key('costs-export-products'),
              label: 'Exportar · Excel o PDF',
              value: 'Costo por producto',
              onTap: onExportProducts,
            ),
          ],
        ),
      ],
    );
  }
}

/// Costo de un chaco: costo por hectárea en grande y el total, con su
/// responsable y superficie. Tocarla abre su bitácora.
class Rdm2cFarmCostCard extends StatelessWidget {
  const Rdm2cFarmCostCard({super.key, required this.row, this.onTap});
  final FarmCostRead row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final perHectare = row.costPerHectareMinor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.farmName, style: AgroText.value),
                Text(
                  '${row.ownerName} · ${formatHectares(row.areaM2)}',
                  style: AgroText.detail,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    perHectare == null
                        ? Text(
                            // Modo individual: sin aplicaciones no hay costo
                            // que repartir (como «Costos › Por chaco»).
                            row.applicationCount == 0
                                ? 'sin aplicaciones'
                                : 'sin superficie',
                            style: AgroText.detail,
                          )
                        : BigFigure(
                            number: splitBob(perHectare).number,
                            unit: 'Bs por ha',
                            size: 28,
                          ),
                    Text(
                      'Total ${formatBob(row.totalCostBobMinor)}',
                      style: const TextStyle(
                        fontSize: 15,
                        height: 22 / 15,
                        fontWeight: FontWeight.w700,
                        color: AgroColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
