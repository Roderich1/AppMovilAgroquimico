import 'package:flutter/material.dart';

import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/money.dart';
import 'common.dart';

/// Estado de cuenta de una persona (D-04 §2.5): «Deuda pendiente por origen
/// (a hoy)» y el estado cronológico con apertura. Son dos cálculos distintos y
/// cada uno lleva su etiqueta.
class AccountStatementView extends StatelessWidget {
  const AccountStatementView({super.key, required this.statement});

  final AccountStatement statement;

  @override
  Widget build(BuildContext context) {
    final account = statement.account;
    final ledger = statement.ledger;
    final period = statement.period;
    final theme = Theme.of(context);
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    final debts = statement.debts;
    final composition = creditCompositionLine(account);
    final noMovements =
        statement.lines.isEmpty && (statement.openingMinor ?? 0) == 0;
    return ListView(
      children: [
        Text(
          'Deuda pendiente por origen (a hoy)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (debts.isEmpty) const Text('Sin cargos.'),
        for (final debt in debts) ...[
          Text(originDebtLine(ledger.campaignName(debt.campaignId), debt)),
          if (debt.releasedMinor > 0)
            Text(
              releasedLine(ledger.campaignName(debt.campaignId), debt),
              style: theme.textTheme.bodySmall,
            ),
        ],
        Text('Deuda pendiente total ${bob(account.pendingMinor)}', style: bold),
        Text('A favor (no aplicado a deuda) ${bob(account.creditMinor)}'),
        if (composition != null)
          Text(composition, style: theme.textTheme.bodySmall),
        Text(netLine(account), style: bold),
        const Divider(height: 24),
        Text(
          statementHeader(statement),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (noMovements)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'Sin movimientos.',
          )
        else ...[
          if (period != null)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(openingLabel(period)),
              trailing: Text(formatBob(statement.openingMinor!), style: bold),
            ),
          for (final line in statement.lines)
            Builder(
              builder: (_) {
                final entry = line.entry;
                final amount = entry.amountMinor;
                final status = statusText(ledger, account, entry);
                return ListTile(
                  leading: Icon(
                    amount > 0
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: amount > 0 ? Colors.orange : Colors.green,
                  ),
                  title: Text(
                    conceptLabel(entry.concept),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                          formatDate(entry.transactionDate),
                          transactionTypeLabel(entry.type),
                          ?entry.farmName,
                          entryCampaignText(ledger, account, entry),
                        ].join(' · ') +
                        (status.isEmpty ? '' : '\n$status'),
                  ),
                  // Ancho acotado para el importe: sin esto la descripción
                  // se partía por carácter (UIBUG-021).
                  trailing: SizedBox(
                    width: 140,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          amount > 0
                              ? '+${formatBob(amount)}'
                              : formatBob(amount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bold,
                        ),
                        Text(
                          'Acumulado ${formatBob(line.balanceMinor)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(closingLabel(statement)),
            trailing: Text(formatBob(statement.closingMinor), style: bold),
          ),
        ],
      ],
    );
  }
}
