// Inicio del modo individual (láminas I-01 e I-02, 2026-11-13).
//
// Sólo presentación sobre cálculos que ya existen:
// - «Costo de productos aplicados» y «Compras» de la campaña activa salen de
//   `campaignCloseSummary` (las mismas sumas del cierre de campaña:
//   aplicaciones y compras no anuladas con ese `campaign_id`).
// - «Debe a proveedores» es de todas las campañas: Σ (total − pagado) de las
//   compras confirmadas con saldo, el mismo saldo que «Registrar pago al
//   proveedor» propone y que Inicio ya contaba («N compras con saldo»).
// - «Ver cuánto queda» cuenta productos con existencia positiva
//   (`inventorySummary`).
// Las cuatro cifras de dinero (compras, costo aplicado, valor del inventario
// y saldo con proveedores) nunca se suman ni se intercambian.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/agro_repository.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/read_models.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/rdm_b_ui.dart';

/// Cifras del Inicio individual. `campaign` es la campaña activa (la de la
/// pastilla de la cabecera); sin campaña activa no hay cifras de campaña.
class IndHomeFigures {
  const IndHomeFigures({
    required this.campaign,
    required this.appliedMinor,
    required this.purchasesMinor,
    required this.purchasesCount,
    required this.applicationsCount,
    required this.pendingPlans,
    required this.providerDebtMinor,
    required this.purchasesWithBalance,
    required this.productsWithStock,
    required this.farmsCount,
  });

  final CampaignRead? campaign;
  final int appliedMinor;
  final int purchasesMinor;
  final int purchasesCount;
  final int applicationsCount;
  final int pendingPlans;

  /// Todas las campañas.
  final int providerDebtMinor;
  final int purchasesWithBalance;
  final int productsWithStock;
  final int farmsCount;

  /// Lámina I-02: la campaña activa no tiene compras ni aplicaciones.
  bool get campaignEmpty =>
      campaign != null && purchasesCount == 0 && applicationsCount == 0;
}

/// Compras confirmadas cuyo total supera lo pagado al proveedor (filas de
/// `AgroRepository.purchases`).
({int count, int debtMinor}) providerBalances(
  List<Map<String, Object?>> purchases,
) {
  var count = 0;
  var debt = 0;
  for (final row in purchases) {
    if (row['status'] != 'CONFIRMED') continue;
    final pending =
        (row['total_bob_minor']! as int) - (row['paid_bob_minor']! as int);
    if (pending > 0) {
      count++;
      debt += pending;
    }
  }
  return (count: count, debtMinor: debt);
}

Future<IndHomeFigures> loadIndHomeFigures(
  AgroRepository repo, {
  required List<CampaignRead> campaigns,
  required List<Map<String, Object?>> purchases,
}) async {
  final active = campaigns.where((c) => c.isActive).firstOrNull;
  final close = active == null
      ? null
      : await repo.campaignCloseSummary(active.id);
  final balances = providerBalances(purchases);
  final stock = await repo.inventorySummary();
  final farms = (await repo.farmsAndContext()).farms;
  int value(String key) => (close?[key] as int?) ?? 0;
  return IndHomeFigures(
    campaign: active,
    appliedMinor: value('applications_bob_minor'),
    purchasesMinor: value('purchases_bob_minor'),
    purchasesCount: value('purchases_count'),
    applicationsCount: value('applications_count'),
    pendingPlans: value('pending_plans'),
    providerDebtMinor: balances.debtMinor,
    purchasesWithBalance: balances.count,
    productsWithStock: stock
        .where((row) => ((row['available_base'] as num?) ?? 0) > 0)
        .length,
    farmsCount: farms.length,
  );
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

const _muted = TextStyle(
  fontSize: 15,
  height: 21 / 15,
  color: AgroColors.onInkMuted,
);

/// Cifras de la cabecera oscura (I-01) o su estado sin registros (I-02).
class IndHomeHero extends StatelessWidget {
  const IndHomeHero({super.key, required this.figures});

  final IndHomeFigures figures;

  @override
  Widget build(BuildContext context) {
    final f = figures;
    final campaign = f.campaign;
    final debtCard = _FigureCard(
      key: const Key('ind-home-provider-debt'),
      label: 'Debe a proveedores · todas las campañas',
      minor: f.providerDebtMinor,
    );
    if (campaign == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sin campaña activa',
            key: Key('ind-home-no-campaign'),
            style: TextStyle(
              fontFamily: AgroFonts.display,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Active una campaña para ver sus compras y el costo de lo '
            'aplicado. Toque la campaña arriba.',
            style: _muted,
          ),
          const SizedBox(height: 14),
          debtCard,
        ],
      );
    }
    if (f.campaignEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Todavía no hay registros en esta campaña',
            key: Key('ind-home-empty-title'),
            style: TextStyle(
              fontFamily: AgroFonts.display,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sus costos y saldos aparecerán aquí cuando registre la primera '
            'compra o aplicación.',
            style: _muted,
          ),
          // Una deuda real de otra campaña no se oculta por estar vacía ésta.
          if (f.providerDebtMinor > 0) ...[
            const SizedBox(height: 14),
            debtCard,
          ],
        ],
      );
    }
    final applied = splitBob(f.appliedMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Costo de productos aplicados · ${campaign.name}',
          key: const Key('ind-home-applied-label'),
          style: _muted,
        ),
        BigFigure(
          numberKey: const Key('ind-home-applied'),
          number: applied.number,
          unit: applied.unit,
          size: 56,
          color: Colors.white,
          unitColor: AgroColors.lime,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final purchases = _FigureCard(
              key: const Key('ind-home-purchases'),
              label: 'Compras · ${campaign.name}',
              minor: f.purchasesMinor,
            );
            // Con letra grande o pantalla estrecha, una tarjeta debajo de la
            // otra en vez de partir las cifras.
            final scale = MediaQuery.textScalerOf(context).scale(1);
            if (constraints.maxWidth / scale < 300) {
              return Column(
                children: [purchases, const SizedBox(height: 10), debtCard],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: purchases),
                  const SizedBox(width: 10),
                  Expanded(child: debtCard),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({super.key, required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: ${formatBob(minor).trim()}',
    excludeSemantics: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AgroColors.inkSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              height: 19 / 14,
              color: AgroColors.onInkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatBob(minor).trim(),
            style: const TextStyle(
              fontSize: 19,
              height: 24 / 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

/// «Para empezar» (I-02): chaco, compra y aplicación. Un paso hecho se marca.
class IndHomeFirstSteps extends StatelessWidget {
  const IndHomeFirstSteps({
    super.key,
    required this.figures,
    required this.onFarms,
    required this.onPurchase,
    required this.onApplication,
  });

  final IndHomeFigures figures;
  final VoidCallback onFarms;
  final VoidCallback onPurchase;
  final VoidCallback onApplication;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        key: const Key('ind-home-step-farm'),
        title: figures.farmsCount == 0
            ? 'Agregue su primer chaco'
            : 'Sus chacos',
        detail: figures.farmsCount == 0
            ? 'Nombre y superficie'
            : _plural(figures.farmsCount, 'chaco', 'chacos'),
        done: figures.farmsCount > 0,
        onTap: onFarms,
      ),
      (
        key: const Key('ind-home-step-purchase'),
        title: 'Registre una compra',
        detail: 'Los productos entran a su almacén',
        done: false,
        onTap: onPurchase,
      ),
      (
        key: const Key('ind-home-step-application'),
        title: 'Registre una aplicación',
        detail: 'Verá el costo por chaco',
        done: false,
        onTap: onApplication,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Overline('Para empezar'),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AgroColors.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                key: steps[i].key,
                borderRadius: BorderRadius.circular(20),
                onTap: steps[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: steps[i].done || i < 2
                              ? AgroColors.ink
                              : AgroColors.chip,
                        ),
                        child: steps[i].done
                            ? const Icon(
                                Icons.check,
                                size: 20,
                                color: AgroColors.lime,
                                semanticLabel: 'Hecho',
                              )
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: i < 2
                                      ? AgroColors.lime
                                      : AgroColors.ink,
                                ),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].title,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 22 / 17,
                                fontWeight: FontWeight.w700,
                                color: AgroColors.ink,
                              ),
                            ),
                            Text(steps[i].detail, style: AgroText.detail),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AgroColors.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text(
            'No se muestran cifras en cero: sin registros no hay nada que '
            'sumar.',
            style: AgroText.detail,
          ),
        ),
      ],
    );
  }
}

/// Accesos de Inicio (I-01): Planes, Ver cuánto queda y Sindicato. Sindicato
/// abre el mismo centro que la pestaña y no envía nada.
class IndHomeLinks extends StatelessWidget {
  const IndHomeLinks({super.key, required this.figures, required this.onOpen});

  final IndHomeFigures? figures;
  final void Function(Future<Object?> navigation) onOpen;

  @override
  Widget build(BuildContext context) {
    final f = figures;
    Widget count(String text) => Text(
      text,
      textAlign: TextAlign.end,
      style: const TextStyle(fontSize: 15, color: AgroColors.muted),
    );
    return AgroGroup(
      children: [
        LinkRow(
          key: const Key('ind-home-plans'),
          title: 'Planes',
          titleStyle: _linkTitle,
          trailing: f == null || f.campaign == null
              ? null
              : count(
                  f.pendingPlans == 0
                      ? 'Ninguno por hacer'
                      : '${f.pendingPlans} por hacer',
                ),
          onTap: () => onOpen(context.push('/planificacion')),
        ),
        LinkRow(
          key: const Key('home-ver-cuanto-queda'),
          title: 'Ver cuánto queda',
          titleStyle: _linkTitle,
          trailing: f == null
              ? null
              : count(_plural(f.productsWithStock, 'producto', 'productos')),
          onTap: () => context.go('/inventario'),
        ),
        LinkRow(
          key: const Key('home-enviar-sindicato'),
          title: 'Sindicato',
          titleStyle: _linkTitle,
          onTap: () => context.go('/sindicato'),
        ),
      ],
    );
  }
}

const _linkTitle = TextStyle(
  fontSize: 17,
  height: 22 / 17,
  fontWeight: FontWeight.w700,
  color: AgroColors.ink,
);

/// «Avisos» (I-01): vencimientos y existencias en una fila y las compras con
/// saldo por pagar al proveedor. Los errores de cálculo se dicen.
class IndHomeAlerts extends StatelessWidget {
  const IndHomeAlerts({
    super.key,
    required this.alerts,
    required this.alertsError,
    required this.figures,
    required this.purchasesError,
    required this.onOpen,
  });

  final InventoryAlerts? alerts;
  final Object? alertsError;
  final IndHomeFigures? figures;
  final bool purchasesError;
  final void Function(Future<Object?> navigation) onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void avisos() => onOpen(context.push('/inventario/avisos'));
    final a = alerts;
    if (alertsError != null) {
      rows.add(
        _AlertCard(
          key: const Key('home-attention-alerts-error'),
          warn: true,
          text: 'No se pudieron calcular los avisos de inventario',
          onTap: avisos,
        ),
      );
    } else if (a != null) {
      if (a.clockLooksBehind) {
        rows.add(
          _AlertCard(
            key: const Key('home-attention-clock'),
            warn: true,
            text: 'Revise la fecha del teléfono: los avisos dependen de ella',
            onTap: avisos,
          ),
        );
      }
      // Lotes vencidos, que vencen hoy o pronto, y productos con poca
      // existencia: los mismos avisos de «Avisos de inventario».
      final total =
          a.expired.length +
          a.dueToday.length +
          a.near.length +
          a.lowStock.length;
      if (total > 0) {
        rows.add(
          _AlertCard(
            key: const Key('ind-home-inventory-alerts'),
            warn: true,
            text:
                'Vencimientos y existencias · '
                '${_plural(total, 'aviso', 'avisos')}',
            onTap: avisos,
          ),
        );
      }
    }
    if (purchasesError) {
      rows.add(
        _AlertCard(
          key: const Key('home-attention-purchases-error'),
          warn: true,
          text: 'No se pudo revisar el saldo de las compras',
          onTap: () => onOpen(context.push('/compras')),
        ),
      );
    } else if ((figures?.purchasesWithBalance ?? 0) > 0) {
      rows.add(
        _AlertCard(
          key: const Key('home-attention-provider-balance'),
          warn: false,
          text:
              '${_plural(figures!.purchasesWithBalance, 'compra pendiente', 'compras pendientes')} '
              'de pago',
          onTap: () => onOpen(context.push(indProvidersRoute)),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Overline('Avisos'),
        for (final row in rows)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: row),
      ],
    );
  }
}

/// Destino de «compras pendientes de pago». Se ajusta cuando la sesión B
/// publique la pantalla de Proveedores (I-05).
const indProvidersRoute = '/compras';

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    super.key,
    required this.text,
    required this.warn,
    required this.onTap,
  });

  final String text;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = warn ? AgroColors.warnInk : AgroColors.ink;
    return Material(
      color: warn ? AgroColors.warnBg : AgroColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: warn ? AgroColors.warnInk : AgroColors.caution,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      height: 21 / 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: AgroColors.muted,
        ),
      ),
    ),
  );
}
