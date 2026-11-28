import 'package:flutter/material.dart';

import '../../domain/agro_gateway.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/sync/campaign_period_check.dart';
import 'common.dart';

Future<bool> editCampaignPeriodFlow(
  BuildContext context,
  AgroGateway repository,
  CampaignPeriod local, {
  String? preferredEnd,
}) async {
  final proposed = await showCampaignPeriodEditor(
    context,
    local,
    local,
    preferredEnd: preferredEnd,
  );
  if (proposed == null || !context.mounted) return false;
  await repository.setCampaignPeriod(local, proposed);
  if (context.mounted) showSuccess(context, 'Período actualizado.');
  return true;
}

/// Revisa inicio y fin antes de guardar o vincular. Las reglas de calendario
/// se vuelven a comprobar dentro de la transacción que aplica el cambio.
Future<CampaignPeriod?> showCampaignPeriodEditor(
  BuildContext context,
  CampaignPeriod local,
  CampaignPeriod initial, {
  CentralPeriod? central,
  String? centralName,
  String? preferredEnd,
}) => showDialog<CampaignPeriod>(
  context: context,
  builder: (context) => _PeriodDialog(
    local: local,
    initial: initial,
    central: central,
    centralName: centralName,
    preferredEnd: preferredEnd,
  ),
);

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({
    required this.local,
    required this.initial,
    this.central,
    this.centralName,
    this.preferredEnd,
  });

  final CampaignPeriod local;
  final CampaignPeriod initial;
  final CentralPeriod? central;
  final String? centralName;
  final String? preferredEnd;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late var _start = widget.initial.startDay;
  late var _end = widget.initial.endDay;

  Future<void> _pickDate({required bool isStart}) async {
    final current =
        (isStart ? _start : _end ?? widget.preferredEnd) ??
        localDay(DateTime.now());
    final min = isStart
        ? widget.central?.startDay ??
              (current.compareTo('1900-01-01') < 0 ? current : '1900-01-01')
        : _start;
    final max =
        (isStart ? _end : null) ??
        widget.central?.endDay ??
        (current.compareTo('2100-12-31') > 0 ? current : '2100-12-31');
    final firstDate = startOfLocalDay(min);
    final lastDate = startOfLocalDay(max);
    final date = startOfLocalDay(current);
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isBefore(firstDate)
          ? firstDate
          : date.isAfter(lastDate)
          ? lastDate
          : date,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: isStart ? 'Fecha de inicio' : 'Fin previsto',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = localDay(picked);
      } else {
        _end = localDay(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.local;
    final central = widget.central;
    final end = _end;
    final proposed = local.withDates(startDay: _start, endDay: end);
    final endOnly =
        central != null &&
        local.endDay == null &&
        widget.initial.startDay == local.startDay;
    return AlertDialog(
      scrollable: true,
      title: Text(
        central == null
            ? 'Editar período'
            : endOnly
            ? 'Fijar fin previsto y vincular'
            : 'Ajustar fechas y vincular',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('«${local.name}» · Actualmente ${local.describe}'),
          if (central != null)
            Text('«${widget.centralName}» del sindicato · ${central.describe}'),
          ListTile(
            key: const Key('campaign-period-start'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Inicio'),
            subtitle: Text(displayDay(_start)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            key: const Key('campaign-period-end'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Fin previsto'),
            subtitle: Text(end == null ? 'Sin fecha de fin' : displayDay(end)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _pickDate(isStart: false),
          ),
          if (local.status == 'ACTIVE' &&
              !proposed.contains(localDay(DateTime.now())))
            const Text('La fecha de hoy queda fuera del período propuesto.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('campaign-period-confirm'),
          onPressed: local.matchesPeriod(proposed)
              ? null
              : () => Navigator.pop(context, proposed),
          child: Text(
            central == null ? 'Guardar período' : 'Confirmar fecha y vínculo',
          ),
        ),
      ],
    );
  }
}
