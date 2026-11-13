/// Detalle de una cuenta (ronda 2, sesión C, P2): «Estado de cuenta» de una
/// persona y «Movimientos propios» del titular con la MISMA estructura:
/// cabecera (la del diálogo), resumen con la cifra principal y sus acciones,
/// filtro de período, el desglose y los movimientos.
///
/// El contenido es distinto. Otras personas: cargos, pagos, saldo y, si se
/// puede, «Registrar pago». Titular: consumo y costos propios, sin deuda ni
/// «Registrar pago». Textos y cifras de D-04/E-15 sin cambios; los términos
/// técnicos (FIFO, imputación, asientos) quedan como información secundaria.
///
/// Cambiar el período recalcula con el libro ya leído
/// (`AccountLedger.statement`): no hay consultas nuevas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../theme/agro_theme.dart';
import 'account_statement_view.dart';
import 'agro_ui.dart';
import 'rdm_a_payment.dart';
import 'rdm_b_ui.dart' show BigFigure, splitBob;

/// Lo que pasó mientras el detalle estuvo abierto.
class Rdm2cDetailOutcome {
  bool recorded = false;
}

class Rdm2cAccountDetail extends ConsumerStatefulWidget {
  const Rdm2cAccountDetail({
    super.key,
    required this.statement,
    required this.campaignId,
    required this.own,
    required this.outcome,
    this.canPay = false,
    this.onExport,
  });

  final AccountStatement statement;
  final int? campaignId;

  /// `true`: movimientos propios del titular.
  final bool own;
  final Rdm2cDetailOutcome outcome;

  /// Se ofrece «Registrar pago» (nunca al titular ni en inventario propio).
  final bool canPay;

  /// Exportar con el período elegido; nulo sin acceso a Reportes.
  final void Function(int? campaignId)? onExport;

  @override
  ConsumerState<Rdm2cAccountDetail> createState() => _Rdm2cAccountDetailState();
}

class _Rdm2cAccountDetailState extends ConsumerState<Rdm2cAccountDetail> {
  late AccountStatement statement = widget.statement;
  late int? campaignId = widget.campaignId;

  int get personId => statement.account.person.id;

  void _setPeriod(int? next) => setState(() {
    campaignId = next;
    statement = statement.ledger.statement(personId, campaignId: next);
  });

  Future<void> _pay() async {
    final recorded = await recordAccountPayment(
      context,
      ref,
      person: AccountSummary(
        account: statement.account,
        campaignId: campaignId,
      ),
      campaign: statement.ledger.campaign(campaignId),
    );
    if (!recorded || !mounted) return;
    widget.outcome.recorded = true;
    final next = await ref
        .read(repositoryProvider)
        .accountStatement(personId, campaignId: campaignId);
    if (mounted) setState(() => statement = next);
  }

  @override
  Widget build(BuildContext context) {
    final leading = [
      _summary(),
      const SizedBox(height: 12),
      _periodFilter(),
      const SizedBox(height: 16),
    ];
    return widget.own
        ? OwnMovementsView(statement: statement, leading: leading)
        : AccountStatementView(statement: statement, leading: leading);
  }

  Widget _periodFilter() => DropdownButtonFormField<int?>(
    key: const Key('detail-period'),
    initialValue: campaignId,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Período'),
    items: [
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('Todas las campañas'),
      ),
      for (final campaign in statement.ledger.campaigns)
        DropdownMenuItem<int?>(value: campaign.id, child: Text(campaign.name)),
    ],
    onChanged: _setPeriod,
  );

  Widget _summary() {
    final String caption;
    final int amount;
    final String? note;
    if (widget.own) {
      final consumption = statement.ownConsumption;
      caption =
          'Consumo propio · '
          '${statement.period?.name ?? 'todas las campañas'}';
      amount = consumption.activeCostMinor;
      note = ownApplicationsLine(consumption);
    } else {
      final net = statement.account.netMinor;
      caption = net > 0
          ? 'Debe · todas las campañas'
          : net < 0
          ? 'A favor · todas las campañas'
          : 'Al día · todas las campañas';
      amount = net.abs();
      note = null;
    }
    return Container(
      key: const Key('detail-summary'),
      decoration: BoxDecoration(
        color: AgroColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.own) ...[
            const StatusBadge(label: 'No es deuda', tone: BadgeTone.ok),
            const SizedBox(height: 8),
          ],
          Text(
            caption,
            style: const TextStyle(
              fontSize: 14,
              height: 20 / 14,
              color: AgroColors.onInkMuted,
            ),
          ),
          BigFigure(
            number: splitBob(amount).number,
            unit: 'Bs',
            size: 36,
            color: AgroColors.lime,
            numberKey: const Key('detail-amount'),
          ),
          if (note != null)
            Text(
              note,
              style: const TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: AgroColors.onInk,
              ),
            ),
          if (widget.canPay || widget.onExport != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.canPay && !widget.own)
                  FilledButton(
                    key: const Key('detail-pay'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AgroColors.lime,
                      foregroundColor: AgroColors.ink,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _pay,
                    child: const Text('Registrar pago'),
                  ),
                if (widget.onExport != null)
                  OutlinedButton.icon(
                    key: const Key('detail-export'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AgroColors.onInkMuted),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => widget.onExport!(campaignId),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Exportar'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
