import 'package:flutter/material.dart';

import '../../../domain/campaign_calendar.dart';
import '../../../domain/money.dart';
import '../../theme/agro_theme.dart';
import '../../widgets/agro_ui.dart';
import '../../widgets/application_expiry_notice.dart';
import 'application_form_state.dart';
import 'application_products_step.dart' show ApplicationKeyedNotice;

String _chargeText(
  ApplicationFormState state,
  Map<String, Object?>? person,
  int totalCost, {
  String? farmName,
}) {
  final name = person?['name']?.toString() ?? '';
  final policy = person?['settlement_policy'];
  if (state.personalMode) {
    final farm = (farmName == null || farmName.isEmpty)
        ? 'este chaco'
        : farmName;
    final usage = policy == 'BY_ACTUAL_USAGE'
        ? ' Queda anotado como consumo propio.'
        : '';
    return 'Se suma a los costos de $farm en esta campaña. '
        'No es una deuda.$usage';
  }
  if (person != null && person['id'] == state.ownerPersonId) {
    return policy == 'BY_ACTUAL_USAGE'
        ? 'Costo propio: ${formatBob(totalCost)} (queda anotado en la '
              'cuenta de $name)'
        : 'Costo propio: ${formatBob(totalCost)}';
  }
  return switch (policy) {
    'BY_ACTUAL_USAGE' => 'Se cargará a $name: ${formatBob(totalCost)}',
    'BY_PURCHASE_ALLOCATION' =>
      'Esta aplicación no genera cargo a $name: su política cobra al '
          'asignar compras.',
    _ => 'No genera cargo automático: la cuenta de $name se ajusta a mano',
  };
}

String _personalReviewSubtitle(
  ApplicationFormState state,
  Map<String, Object?>? farm,
) {
  final total = farm?['area_m2'];
  final of = total is int && total > 0 ? ' de ${formatHectares(total)}' : '';
  return '${applicationDayLabel(state.effectiveDay)} · superficie tratada: '
      '${formatHectares(state.areaM2)}$of';
}

List<Widget> buildApplicationReviewStep(
  BuildContext context, {
  required ApplicationFormState state,
  required ApplicationCatalogs data,
  required TextEditingController notesController,
  required VoidCallback onToggleCostHelp,
  required ValueChanged<String> onNotesChanged,
}) {
  final person = state.person(data);
  final farm = state.farm(data);
  final totalCost = state.lines.fold<int>(0, (sum, line) => sum + line.cost);
  const divider = Divider(height: 1, color: AgroColors.line);
  return [
    Semantics(
      header: true,
      child: const Text('Revise y confirme', style: AgroText.h1),
    ),
    const SizedBox(height: 12),
    if (state.loadingPreview)
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      )
    else
      ApplicationExpiryNotice(
        uses: expiringLotUses(
          applicationDay: state.effectiveDay,
          lines: [
            for (final line in state.lines)
              (
                productName: line.product['product_name'].toString(),
                unit: line.unit,
                lots: state.lotPreview[line.product['product_id']] ?? const [],
              ),
          ],
        ),
        applicationDay: state.effectiveDay,
        isToday: state.effectiveDay == localDay(DateTime.now()),
      ),
    Card(
      key: const Key('application-review'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              state.personalMode
                  ? '${farm?['name'] ?? ''}'
                  : '${farm?['name'] ?? ''} · '
                        '${formatHectares(state.areaM2)} tratadas',
              key: const Key('application-review-farm'),
              style: AgroText.value,
            ),
            Text(
              state.personalMode
                  ? _personalReviewSubtitle(state, farm)
                  : '${person?['name'] ?? ''} · '
                        '${applicationDayLabel(state.effectiveDay)}',
              key: const Key('application-review-person'),
              style: AgroText.detail,
            ),
            const SizedBox(height: 12),
            divider,
            const SizedBox(height: 8),
            if (state.personalMode)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'SALE DE SU ALMACÉN',
                  key: Key('application-review-from-store'),
                  style: AgroText.label,
                ),
              ),
            for (final line in state.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: AmountAside(
                  amount: formatBob(line.cost),
                  amountKey: Key('application-review-cost-${line.keyId}'),
                  amountStyle: AgroText.amount.copyWith(fontSize: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${line.product['product_name']} · '
                        '${formatQuantity(line.quantityBase, line.unit)}',
                        style: const TextStyle(
                          fontSize: 16,
                          height: 22 / 16,
                          fontWeight: FontWeight.w500,
                          color: AgroColors.ink,
                        ),
                      ),
                      if (state.personalMode &&
                          line.quantityBase <= line.available)
                        Text(
                          'Tiene ${formatQuantity(line.available, line.unit)}'
                          ' · le quedarán ${formatQuantity(line.available - line.quantityBase, line.unit)}',
                          key: Key(
                            'application-review-remaining-${line.keyId}',
                          ),
                          style: AgroText.detail,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            divider,
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Costo estimado',
                      style: TextStyle(
                        fontSize: 15,
                        height: 20 / 15,
                        color: AgroColors.muted,
                      ),
                    ),
                    IconButton(
                      key: const Key('application-cost-help'),
                      tooltip: '¿Cómo se calcula el costo?',
                      isSelected: state.showCostHelp,
                      color: AgroColors.muted,
                      icon: const Icon(Icons.help_outline),
                      selectedIcon: const Icon(Icons.help),
                      onPressed: onToggleCostHelp,
                    ),
                  ],
                ),
                Text(
                  formatBob(totalCost),
                  key: const Key('application-review-cost'),
                  style: AgroText.total,
                ),
              ],
            ),
            if (state.showCostHelp)
              Text(
                'Se calcula con el precio de las compras de '
                '${state.personalMode ? 'el titular' : 'esta persona'} que se '
                'irán usando, las más antiguas primero. Cada producto '
                'cuesta la cantidad usada por el precio de su compra; si '
                'una compra no alcanza, se sigue con la siguiente. Es una '
                'estimación: el costo final se fija al confirmar.',
                key: const Key('application-cost-help-text'),
                style: AgroText.detail,
              ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 12),
    ApplicationKeyedNotice(
      textKey: const Key('application-review-charge'),
      text: _chargeText(
        state,
        person,
        totalCost,
        farmName: farm?['name']?.toString(),
      ),
    ),
    const SizedBox(height: 12),
    Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('application-notes'),
          title: const Text(
            'Notas (opcional)',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AgroColors.ink,
            ),
          ),
          iconColor: AgroColors.ink,
          collapsedIconColor: AgroColors.muted,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: notesController,
              onChanged: onNotesChanged,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
      ),
    ),
  ];
}
