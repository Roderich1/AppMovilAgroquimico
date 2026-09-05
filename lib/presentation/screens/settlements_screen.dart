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
    String? campaignName,
  }) async {
    // El diálogo es dueño de su propio TextEditingController y lo libera en
    // `State.dispose()`. Antes el controlador se creaba aquí y se liberaba al
    // volver de `showDialog`, mientras el diálogo aún se animaba al cerrarse:
    // el TextField seguía montado y volvía a suscribirse a un controlador ya
    // liberado (UIBUG-005).
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => _RecordPaymentDialog(
        personName: person['name']! as String,
        campaignName: campaignName,
        balanceMinor: person['balance']! as int,
        advance: advance,
      ),
    );
    if (result == null || !mounted) return;
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
      if (mounted) {
        showSuccess(
          context,
          // `formatBob` termina con el espacio del símbolo ("1.500,00 Bs ").
          '${advance ? 'Adelanto' : 'Pago'} de ${formatBob(result).trim()} '
          'registrado a ${person['name']}.',
        );
      }
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
                            title: Text(
                              conceptLabel(row['concept']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${formatDate(row['transaction_date'])} · ${transactionTypeLabel(row['type'])}${row['farm_name'] == null ? '' : ' · ${row['farm_name']}'}',
                            ),
                            // Ancho acotado para el importe: sin esto la
                            // columna de descripcion quedaba tan estrecha que
                            // el texto se partia por caracter (UIBUG-021).
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Acumulado ${formatBob(entry.$2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
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

  /// Nombre de la campaña filtrada, o `null` si se están viendo todas.
  String? _campaignName(List<Map<String, Object?>> campaigns) {
    if (selectedCampaignId == null) return null;
    for (final campaign in campaigns) {
      if (campaign['id'] == selectedCampaignId) {
        return campaign['name'] as String?;
      }
    }
    return null;
  }

  Future<void> _backup() async {
    try {
      final path = await ref.read(backupServiceProvider).export();
      if (mounted) showSuccess(context, 'Respaldo guardado en $path');
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
      // No es un error: es una indicación normal la primera vez (UIBUG-050).
      showSuccess(
        context,
        'Todavía no hay ningún respaldo. Use "Exportar respaldo" para crear el '
        'primero.',
      );
      return;
    }

    final chosen = await showDialog<File>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar respaldo'),
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
      // La nube sugería sincronización remota y esta aplicación no tiene
      // ninguna función de red: el respaldo es un archivo local (UIBUG-049).
      icon: const Icon(Icons.folder_outlined),
      onSelected: (value) => value == 'export' ? _backup() : _restore(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.save_alt_outlined),
            title: Text('Exportar respaldo'),
          ),
        ),
        PopupMenuItem(
          value: 'restore',
          child: ListTile(
            leading: Icon(Icons.restore_outlined),
            title: Text('Restaurar respaldo'),
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
              matchesSearch(row['name']! as String, personQuery);
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
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['name']! as String,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Cargos ${formatBob(row['charges']! as int)} · '
                                'pagos/créditos ${formatBob(row['payments']! as int)}',
                                // Sin recorte: son cifras contables, no un
                                // subtítulo decorativo.
                                maxLines: 5,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Reparto de ancho explícito entre nombre e importe: sin
                        // esto la columna del importe se quedaba con lo que
                        // pedía y el nombre se partía por carácter al 130 %
                        // (UIBUG-020, UIBUG-017).
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${(row['balance']! as int) < 0 ? 'A favor' : 'Pendiente'} · '
                                '${selectedCampaignId == null ? 'todas las campañas' : _campaignName(campaigns) ?? 'campaña'}',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.end,
                              ),
                              // El importe NUNCA se trunca: es el dato más
                              // importante de la tarjeta. Si no cabe se reduce
                              // el cuerpo de letra, que conserva la cifra
                              // entera; recortarla con "…" perdería
                              // información crítica.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  formatBob(row['balance']! as int),
                                  maxLines: 1,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: (row['balance']! as int) > 0
                                            ? Colors.orange.shade800
                                            : Colors.green.shade700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'detail') {
                              _statement(row);
                            } else {
                              _record(
                                row,
                                advance: value == 'advance',
                                campaignName: _campaignName(campaigns),
                              );
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
                        '${row['owner_name']} · ${formatHectares(row['area_m2']! as int)} · '
                        'Total ${formatBob(row['total_cost_bob_minor']! as int)}',
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

/// Diálogo de registro de pago o adelanto.
///
/// Es un [StatefulWidget] con ownership claro de su [TextEditingController],
/// como los diálogos de `catalogs_screen.dart` y `_PaymentDialog` de
/// `purchases_screen.dart`, que ya seguían el patrón correcto.
///
/// Corrige a la vez:
///  * **UIBUG-005** — el controlador se liberaba antes de que el diálogo
///    terminara de cerrarse.
///  * **UIBUG-012** — no se decía a quién se pagaba ni sobre qué campaña.
///  * **UIBUG-065** — un importe no interpretable valía 0 y el usuario recibía
///    el engañoso *"El importe debe ser mayor a cero"*.
///  * **UIBUG-003** — el importe se interpretaba con convenio inglés.
class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({
    required this.personName,
    required this.campaignName,
    required this.balanceMinor,
    required this.advance,
  });

  final String personName;
  final String? campaignName;
  final int balanceMinor;
  final bool advance;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseNumericInput(_amount.text);
    switch (parsed.status) {
      case NumericInputStatus.empty:
        setState(() => _error = 'Escriba el importe.');
      case NumericInputStatus.ambiguous:
      case NumericInputStatus.malformed:
        // El mensaje describe el problema real y cómo escribirlo bien, en vez
        // de convertir la cadena en 0 y culpar al importe (UIBUG-065).
        setState(() => _error = parsed.message);
      case NumericInputStatus.valid:
        final minor = (parsed.value! * 100).round();
        if (minor <= 0) {
          setState(() => _error = 'El importe debe ser mayor a cero.');
          return;
        }
        Navigator.pop(context, minor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owed = widget.balanceMinor;
    return AlertDialog(
      title: Text(widget.advance ? 'Registrar adelanto' : 'Registrar pago'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Contexto de la operación: sin esto es fácil abrir el menú
          // equivocado en una lista larga y cobrar a quien no era (UIBUG-012).
          Text(
            widget.personName,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            widget.campaignName == null
                ? 'Todas las campañas'
                : 'Campaña ${widget.campaignName}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            owed < 0
                ? 'Saldo a favor ${formatBob(owed)}'
                : 'Saldo pendiente ${formatBob(owed)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Importe BOB',
              hintText: '1.500,25',
              errorText: _error,
              // Un mensaje de formato ocupa varias líneas.
              errorMaxLines: 4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Registrar')),
      ],
    );
  }
}
