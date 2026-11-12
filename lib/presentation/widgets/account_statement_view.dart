import 'package:flutter/material.dart';

import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import 'common.dart';
import 'rdm_b_ui.dart' show IconCircle;

/// Ancho a partir del cual el importe de cada fila cabe en una columna
/// lateral junto a un concepto legible. Por debajo (teléfonos) la fila usa la
/// distribución vertical de [MovementTile].
const double statementWideWidth = 480;

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
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    final debts = statement.debts;
    final composition = creditCompositionLine(account);
    final noMovements =
        statement.lines.isEmpty && (statement.openingMinor ?? 0) == 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < statementWideWidth;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _StatementGroup(
              children: [
                Text('Deuda pendiente por origen (a hoy)', style: _heading),
                if (debts.isEmpty) const Text('Sin cargos.'),
                for (final debt in debts) ...[
                  Text(
                    originDebtLine(ledger.campaignName(debt.campaignId), debt),
                  ),
                  if (debt.releasedMinor > 0)
                    Text(
                      releasedLine(ledger.campaignName(debt.campaignId), debt),
                      style: AgroText.detail,
                    ),
                ],
                Text(
                  'Deuda pendiente total ${bob(account.pendingMinor)}',
                  style: bold,
                ),
                Text(
                  'A favor (no aplicado a deuda) ${bob(account.creditMinor)}',
                ),
                if (composition != null)
                  Text(composition, style: AgroText.detail),
                Text(netLine(account), style: bold),
                // E-15: un titular anterior conserva su consumo propio, aparte.
                if (!statement.isCurrentOwner && statement.hasOwnRecords)
                  Text(
                    formerOwnerLine(ledger.ownConsumption(account.person.id)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(statementHeader(statement), style: _heading),
            ),
            if (noMovements)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'Sin movimientos.',
              )
            else
              _StatementGroup(
                padded: false,
                children: [
                  if (period != null)
                    MovementTile(
                      narrow: narrow,
                      leading: const IconCircle(icon: Icons.history),
                      title: openingLabel(period),
                      amount: formatBob(statement.openingMinor!),
                    ),
                  for (final line in statement.lines)
                    Builder(
                      builder: (_) {
                        final entry = line.entry;
                        final amount = entry.amountMinor;
                        final status = statusText(ledger, account, entry);
                        return MovementTile(
                          narrow: narrow,
                          // Cargo: suma a la cuenta; pago o crédito: resta. El
                          // signo del importe lo dice además del icono.
                          leading: amount > 0
                              ? const IconCircle(
                                  icon: Icons.spa_outlined,
                                  background: AgroColors.ink,
                                  foreground: AgroColors.lime,
                                )
                              : const IconCircle(
                                  icon: Icons.arrow_upward,
                                  background: Color(0xFFE3F6A8),
                                  foreground: Color(0xFF24400A),
                                ),
                          title: conceptLabel(entry.concept),
                          subtitle:
                              [
                                formatDate(entry.transactionDate),
                                transactionTypeLabel(entry.type),
                                ?entry.farmName,
                                entryCampaignText(ledger, account, entry),
                              ].join(' · ') +
                              (status.isEmpty ? '' : '\n$status'),
                          amount: amount > 0
                              ? '+${formatBob(amount)}'
                              : formatBob(amount),
                          detail: 'Acumulado ${formatBob(line.balanceMinor)}',
                        );
                      },
                    ),
                  MovementTile(
                    narrow: narrow,
                    leading: const IconCircle(icon: Icons.flag_outlined),
                    title: closingLabel(statement),
                    amount: formatBob(statement.closingMinor),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Fila de un movimiento: concepto, fecha y tipo, e importe.
///
/// En pantalla ancha el importe (y su acumulado) va en una columna lateral
/// acotada, como siempre. En teléfono esa columna dejaba al concepto unos
/// 55 px y lo partía por carácter («Adelant / o», hallazgo F-1 del
/// 2026-10-30): con [narrow] el importe pasa debajo del concepto, a lo ancho
/// de la fila. Nada se recorta ni se reduce: los textos siguen la escala del
/// sistema y se parten sólo entre palabras.
class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.narrow,
    this.leading,
    required this.title,
    this.subtitle,
    required this.amount,
    this.detail,
  });

  final bool narrow;
  final Widget? leading;
  final String title;
  final String? subtitle;

  /// Importe con signo, ya formateado.
  final String amount;

  /// Línea secundaria junto al importe (p. ej. el acumulado).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(
      fontWeight: FontWeight.w700,
      color: AgroColors.ink,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    const titleStyle = TextStyle(
      fontSize: 16,
      height: 21 / 16,
      fontWeight: FontWeight.w700,
      color: AgroColors.ink,
    );
    if (!narrow) {
      return ListTile(
        leading: leading,
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: AgroText.detail),
        // Ancho acotado para el importe: sin esto la descripción se partía
        // por carácter (UIBUG-021).
        trailing: detail == null
            ? Text(amount, style: bold)
            : SizedBox(
                width: 140,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bold,
                    ),
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.detail,
                    ),
                  ],
                ),
              ),
      );
    }
    return ListTile(
      leading: leading,
      title: Text(title, style: titleStyle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) Text(subtitle!, style: AgroText.detail),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(amount, style: bold.copyWith(fontSize: 16)),
                if (detail != null) Text(detail!, style: AgroText.detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Movimientos propios» del titular (E-15 §B.2): consumo aplicado con su
/// costo FIFO y asientos de su cuenta como registro, sin saldo ni acumulado.
class OwnMovementsView extends StatelessWidget {
  const OwnMovementsView({super.key, required this.statement});

  final AccountStatement statement;

  @override
  Widget build(BuildContext context) {
    final ledger = statement.ledger;
    final own = statement.ownAccount;
    final personId = own.person.id;
    const heading = _heading;
    final total = ledger.ownConsumption(personId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < statementWideWidth;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _StatementGroup(
              children: [
                Text('Consumo aplicado (costo FIFO)', style: heading),
                for (final row in ledger.ownConsumptionByCampaign(personId))
                  if (row.consumption.activeCount > 0)
                    Text(
                      ownCampaignLine(
                        ledger.campaignName(row.campaignId),
                        row.consumption,
                      ),
                    ),
                if (total.reversedCount > 0)
                  Text(
                    'Aplicaciones revertidas: ${total.reversedCount} '
                    '(${bob(total.reversedCostMinor)})',
                  ),
                Text(
                  'Consumo aplicado · todas las campañas '
                  '${bob(total.activeCostMinor)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Asientos de su cuenta (registro, no deuda) · '
                '${ownScopeLabel(statement.period, statement.today)}',
                style: heading,
              ),
            ),
            if (statement.ownLines.isEmpty)
              const _StatementGroup(
                children: [Text('Sin asientos en su cuenta.')],
              )
            else
              _StatementGroup(
                padded: false,
                children: [
                  for (final entry in statement.ownLines)
                    Builder(
                      builder: (_) {
                        final status = statusText(
                          ledger,
                          own,
                          entry,
                          ownRecord: true,
                        );
                        return MovementTile(
                          narrow: narrow,
                          title: conceptLabel(entry.concept),
                          subtitle:
                              [
                                formatDate(entry.transactionDate),
                                transactionTypeLabel(entry.type),
                                ?entry.farmName,
                                entryCampaignText(ledger, own, entry),
                              ].join(' · ') +
                              (status.isEmpty ? '' : '\n$status'),
                          amount: entry.amountMinor > 0
                              ? '+${formatBob(entry.amountMinor)}'
                              : formatBob(entry.amountMinor),
                        );
                      },
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

const _heading = TextStyle(
  fontSize: 16,
  height: 22 / 16,
  fontWeight: FontWeight.w700,
  color: AgroColors.ink,
);

/// Grupo blanco del estado de cuenta: el resumen (con margen) o la lista de
/// movimientos (sin margen, filas separadas por una línea fina).
class _StatementGroup extends StatelessWidget {
  const _StatementGroup({required this.children, this.padded = true});
  final List<Widget> children;
  final bool padded;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: padded
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 15,
                height: 21 / 15,
                color: AgroColors.ink,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          )
        : Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AgroColors.line,
                  ),
                child,
              ],
            ],
          ),
  );
}
