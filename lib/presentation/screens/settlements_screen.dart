import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class SettlementsScreen extends ConsumerStatefulWidget {
  const SettlementsScreen({super.key});
  @override
  ConsumerState<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends ConsumerState<SettlementsScreen> {
  late Future<
    (
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
    )
  >
  data;
  int? selectedCampaignId;
  bool campaignInitialized = false;
  String personQuery = '';
  @override
  void initState() {
    super.initState();
    data = _load();
  }

  Future<
    (
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
    )
  >
  _load() async {
    final repo = ref.read(repositoryProvider);
    final campaigns = await repo.campaigns();
    if (!campaignInitialized) {
      final active = campaigns.where((row) => row['status'] == 'ACTIVE');
      selectedCampaignId = active.isEmpty ? null : active.first['id'] as int;
      campaignInitialized = true;
    }
    return (
      await repo.settlements(campaignId: selectedCampaignId),
      await repo.farmCostReport(campaignId: selectedCampaignId),
      await repo.productCostReport(campaignId: selectedCampaignId),
      campaigns,
    );
  }

  void _refresh() {
    final next = _load();
    setState(() {
      data = next;
    });
  }

  Future<void> _record(
    Map<String, Object?> person, {
    required bool advance,
  }) async {
    final amount = TextEditingController();
    final result = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(advance ? 'Registrar adelanto' : 'Registrar pago'),
        content: TextField(
          controller: amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Importe BOB'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(context, parseMinor(amount.text));
              } catch (_) {}
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    amount.dispose();
    if (result == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .addAccountPayment(
            personId: person['id']! as int,
            campaignId: selectedCampaignId,
            amountBobMinor: result,
            advance: advance,
          );
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _statement(Map<String, Object?> person) async {
    final repo = ref.read(repositoryProvider);
    final rows = await repo.detailedStatement(
      person['id']! as int,
      campaignId: selectedCampaignId,
    );
    final campaignBalance = selectedCampaignId == null
        ? null
        : await repo.personCampaignBalance(
            person['id']! as int,
            selectedCampaignId!,
          );
    if (!mounted) return;
    var balance = campaignBalance?['opening_balance'] as int? ?? 0;
    final rowsWithBalance = <(Map<String, Object?>, int)>[];
    for (final row in rows) {
      balance += row['amount_bob_minor_signed']! as int;
      rowsWithBalance.add((row, balance));
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Estado de cuenta · ${person['name']}'),
        content: SizedBox(
          width: 620,
          height: 420,
          child:
              rows.isEmpty &&
                  (campaignBalance == null ||
                      campaignBalance['opening_balance'] == 0)
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'Sin movimientos.',
                )
              : ListView(
                  children: [
                    if (campaignBalance != null)
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Saldo inicial de campaña'),
                        trailing: Text(
                          formatBob(campaignBalance['opening_balance'] as int),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (campaignBalance != null) const Divider(height: 1),
                    for (final entry in rowsWithBalance)
                      Builder(
                        builder: (_) {
                          final row = entry.$1;
                          final amount = row['amount_bob_minor_signed']! as int;
                          return ListTile(
                            leading: Icon(
                              amount > 0
                                  ? Icons.add_circle_outline
                                  : Icons.remove_circle_outline,
                              color: amount > 0 ? Colors.orange : Colors.green,
                            ),
                            title: Text(row['concept']! as String),
                            subtitle: Text(
                              '${(row['transaction_date']! as String).substring(0, 10)} · ${_transactionLabel(row['type']! as String)}${row['farm_name'] == null ? '' : ' · ${row['farm_name']}'}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  amount > 0
                                      ? '+${formatBob(amount)}'
                                      : formatBob(amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Saldo ${formatBob(entry.$2)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _transactionLabel(String type) => switch (type) {
    'USAGE_CHARGE' => 'Cargo por consumo',
    'PURCHASE_ALLOCATION_CHARGE' => 'Cargo por compra',
    'PAYMENT' => 'Pago',
    'ADVANCE' => 'Adelanto',
    'CREDIT_ADJUSTMENT' => 'Crédito por reversión',
    _ => type,
  };

  Future<void> _backup() async {
    try {
      final path = await ref.read(backupServiceProvider).export();
      if (mounted) showSuccess(context, 'Backup guardado en $path');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Restauración: valida el archivo, avisa de que reemplaza todo y solo
  /// entonces sustituye la base. La copia previa se conserva siempre.
  Future<void> _restore() async {
    final service = ref.read(backupServiceProvider);
    final List<File> backups;
    try {
      backups = await service.listAvailableBackups();
    } catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    if (backups.isEmpty) {
      showError(
        context,
        'No se encontró ningún backup. Exporte uno primero o copie el archivo '
        'a la carpeta de descargas del dispositivo.',
      );
      return;
    }

    final chosen = await showDialog<File>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: ListView(
            children: [
              for (final file in backups)
                ListTile(
                  leading: const Icon(Icons.restore_page_outlined),
                  title: Text(p.basename(file.path)),
                  subtitle: Text(
                    '${file.statSync().modified.toString().substring(0, 16)} · '
                    '${(file.statSync().size / 1024).round()} KB',
                  ),
                  onTap: () => Navigator.pop(dialogContext, file),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final validation = await service.validate(chosen.path);
    if (!mounted) return;
    if (!validation.isValid) {
      showError(context, validation.problem!);
      return;
    }

    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Restaurar este backup?',
      detail:
          '${p.basename(chosen.path)}\n'
          'Esquema versión ${validation.schemaVersion}\n\n'
          'TODOS los datos actuales se reemplazarán por los del backup. '
          'Se guardará automáticamente una copia de los datos actuales por si '
          'necesita volver atrás.',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) return;

    try {
      final safetyCopy = await service.restore(chosen.path);
      if (!mounted) return;
      _refresh();
      showSuccess(
        context,
        'Backup restaurado. Copia de los datos anteriores: $safetyCopy',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Liquidación y cuentas',
    subtitle: 'Cargos, pagos, adelantos y saldos sin borrar el historial.',
    action: PopupMenuButton<String>(
      tooltip: 'Copias de seguridad',
      icon: const Icon(Icons.backup_outlined),
      onSelected: (value) => value == 'export' ? _backup() : _restore(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.save_alt_outlined),
            title: Text('Exportar backup'),
          ),
        ),
        PopupMenuItem(
          value: 'restore',
          child: ListTile(
            leading: Icon(Icons.restore_outlined),
            title: Text('Restaurar backup'),
          ),
        ),
      ],
    ),
    child: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        // El error se comprueba ANTES que los datos: si no, un fallo se
        // presenta como "cargando" y la pantalla gira indefinidamente.
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final (settlements, farmCosts, productCosts, campaigns) =
            snapshot.data!;
        final visibleSettlements = settlements.where((row) {
          return personQuery.isEmpty ||
              (row['name']! as String).toLowerCase().contains(personQuery);
        }).toList();
        if (settlements.isEmpty)
          return const Card(
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message:
                  'Registra familiares o terceros para ver su liquidación.',
            ),
          );
        return Column(
          children: [
            DropdownButtonFormField<int?>(
              initialValue: selectedCampaignId,
              decoration: const InputDecoration(
                labelText: 'Filtrar por campaña',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todas las campañas'),
                ),
                for (final campaign in campaigns)
                  DropdownMenuItem<int?>(
                    value: campaign['id']! as int,
                    child: Text(campaign['name']! as String),
                  ),
              ],
              onChanged: (value) {
                selectedCampaignId = value;
                _refresh();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() {
                personQuery = value.trim().toLowerCase();
              }),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar persona',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            for (final row in visibleSettlements)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          child: Text(
                            (row['name']! as String).characters.first
                                .toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['name']! as String,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Cargos ${formatBob(row['charges']! as int)} · pagos/créditos ${formatBob(row['payments']! as int)}',
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              (row['balance']! as int) < 0
                                  ? 'Saldo a favor'
                                  : 'Saldo pendiente',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              formatBob(row['balance']! as int),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: (row['balance']! as int) > 0
                                        ? Colors.orange.shade800
                                        : Colors.green.shade700,
                                  ),
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'detail') {
                              _statement(row);
                            } else {
                              _record(row, advance: value == 'advance');
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'detail',
                              child: Text('Ver detalle cronológico'),
                            ),
                            PopupMenuItem(
                              value: 'pay',
                              child: Text('Registrar pago'),
                            ),
                            PopupMenuItem(
                              value: 'advance',
                              child: Text('Registrar adelanto'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Costo por chaco y hectárea',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  for (final row in farmCosts)
                    ListTile(
                      leading: const Icon(Icons.landscape_outlined),
                      title: Text(row['name']! as String),
                      subtitle: Text(
                        '${row['owner_name']} · ${(row['area_m2']! as int) / 10000} ha · Total ${formatBob(row['total_cost_bob_minor']! as int)}',
                      ),
                      trailing: Text(
                        '${formatBob(divideRoundedHalfUp((row['total_cost_bob_minor']! as int) * 10000, row['area_m2']! as int))}/ha',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Costo consumido por producto',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  for (final row in productCosts)
                    ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: Text(row['name']! as String),
                      subtitle: Text(
                        formatQuantity(
                          row['quantity_base']! as int,
                          row['unit']! as String,
                        ),
                      ),
                      trailing: Text(
                        formatBob(row['total_cost_bob_minor']! as int),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
