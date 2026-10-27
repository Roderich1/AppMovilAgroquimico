import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../domain/read_models.dart';
import '../../domain/reports/report_composer.dart';
import '../../domain/restore_ownership.dart';
import '../../guarded_restore.dart';
import '../../operation_mode_controller.dart';
import '../widgets/account_statement_view.dart';
import '../widgets/common.dart';

class SettlementsScreen extends ConsumerStatefulWidget {
  const SettlementsScreen({super.key});
  @override
  ConsumerState<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends ConsumerState<SettlementsScreen> {
  late Future<
    (
      AccountLedger,
      List<FarmCostRead>,
      List<ProductCostRead>,
      List<CampaignRead>,
    )
  >
  data;
  int? selectedCampaignId;
  bool campaignInitialized = false;
  String personQuery = '';

  /// Titular vigente, para no ofrecer en inventario propio pagos ni
  /// adelantos a otras personas (#26). El repositorio los rechaza igual.
  int? ownerPersonId;
  @override
  void initState() {
    super.initState();
    data = _load();
  }

  Future<
    (
      AccountLedger,
      List<FarmCostRead>,
      List<ProductCostRead>,
      List<CampaignRead>,
    )
  >
  _load() async {
    final repo = ref.read(repositoryProvider);
    // En paralelo con el resto: no añade una espera en cadena. `ignore()`
    // evita un error sin observar si una lectura anterior falla antes de
    // esperarlo; esperarlo después sigue propagando su error.
    final operating = repo.operatingContext()..ignore();
    final campaigns = await repo.campaignsTyped();
    if (!campaignInitialized) {
      final active = campaigns.where((row) => row.isActive);
      selectedCampaignId = active.isEmpty ? null : active.first.id;
      campaignInitialized = true;
    }
    final result = (
      // D-04: deuda por campaña de origen y saldo neto, de las imputaciones
      // guardadas. Sigue siendo una sola consulta.
      // E-15: el mismo libro trae lo propio del titular; no se añade
      // ninguna consulta a esta carga (pruebas con settle fijo).
      await repo.accountLedger(),
      await repo.farmCostReportTyped(campaignId: selectedCampaignId),
      await repo.productCostReportTyped(campaignId: selectedCampaignId),
      campaigns,
    );
    ownerPersonId = (await operating).ownerPersonId;
    return result;
  }

  void _refresh() {
    final next = _load();
    setState(() {
      data = next;
    });
  }

  Future<void> _record(
    AccountSummary person, {
    required bool advance,
    required List<CampaignRead> campaigns,
    bool ownRecord = false,
  }) async {
    // El diálogo es dueño de su propio TextEditingController y lo libera en
    // `State.dispose()`. Antes el controlador se creaba aquí y se liberaba al
    // volver de `showDialog`, mientras el diálogo aún se animaba al cerrarse:
    // el TextField seguía montado y volvía a suscribirse a un controlador ya
    // liberado (UIBUG-005).
    final selected = _selectedPeriod(campaigns);
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => _RecordPaymentDialog(
        personName: person.name,
        registration: registrationText(selected, DateTime.now()),
        netMinor: person.account.netMinor,
        ownRecord: ownRecord,
        advance: advance,
      ),
    );
    if (result == null || !mounted) return;
    try {
      // D-04: la campaña elegida sólo es la de registro; la imputación va a
      // la deuda más antigua de cualquier campaña.
      final payment = await ref
          .read(repositoryProvider)
          .registerAccountPayment(
            personId: person.personId,
            campaignId: selectedCampaignId,
            amountBobMinor: result,
            advance: advance,
          );
      _refresh();
      if (mounted) showSuccess(context, payment.message(person.name));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  CampaignPeriod? _selectedPeriod(List<CampaignRead> campaigns) {
    for (final campaign in campaigns) {
      if (campaign.id == selectedCampaignId) {
        return CampaignPeriod.fromRow({
          'id': campaign.id,
          'name': campaign.name,
          'status': campaign.status,
          'start_date': campaign.startDate,
          'end_date': campaign.endDate,
        });
      }
    }
    return null;
  }

  Future<void> _statement(AccountSummary person) async {
    final statement = await ref
        .read(repositoryProvider)
        .accountStatement(person.personId, campaignId: selectedCampaignId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Estado de cuenta · ${person.name}'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: AccountStatementView(statement: statement),
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

  /// «Movimientos propios» del titular (E-15 §B.2).
  Future<void> _ownMovements(int personId, String name) async {
    final statement = await ref
        .read(repositoryProvider)
        .accountStatement(personId, campaignId: selectedCampaignId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Movimientos propios · $name'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: OwnMovementsView(statement: statement),
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

  /// Tarjeta «Consumo y costos propios» del titular vigente (E-15 §B.2).
  /// No es una cuenta por cobrar: no lleva pendiente ni saldo.
  Widget _ownCard(
    BuildContext context,
    AccountLedger ledger,
    int ownerId,
    List<CampaignRead> campaigns,
  ) {
    final person = ledger.account(ownerId).person;
    final consumption = ledger.ownConsumption(
      ownerId,
      campaignId: selectedCampaignId,
    );
    final theme = Theme.of(context);
    final summary = AccountSummary(
      account: ledger.account(ownerId),
      campaignId: selectedCampaignId,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('own-consumption-card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(child: Icon(Icons.agriculture_outlined)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownCardTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(person.name, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      ownConsumptionLine(
                        consumption,
                        campaignName: _campaignName(campaigns),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(ownApplicationsLine(consumption)),
                    Text(ownRecordsLine(ledger.ownAccount(ownerId))),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'detail':
                      _ownMovements(ownerId, person.name);
                    case 'export':
                      _exportStatement(summary);
                    default:
                      _record(
                        summary,
                        advance: value == 'advance',
                        campaigns: campaigns,
                        ownRecord: true,
                      );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'detail',
                    child: Text('Ver movimientos propios'),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: Text('Exportar movimientos propios'),
                  ),
                  // Criterio Q-2: el titular conserva el pago y el adelanto
                  // (#26); se registran aparte, nunca como cobro.
                  PopupMenuItem(value: 'pay', child: Text('Registrar pago')),
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
    );
  }

  /// Abre Reportes ya situado en el estado de cuenta de esta persona, con la
  /// campaña que se está mirando.
  void _exportStatement(AccountSummary person) {
    final campaign = selectedCampaignId;
    context.push(
      '/reportes?tipo=${ReportKind.accountStatement.name}'
      '&persona=${person.personId}'
      '${campaign == null ? '' : '&campana=$campaign'}',
    );
  }

  /// Nombre de la campaña filtrada, o `null` si se están viendo todas.
  String? _campaignName(List<CampaignRead> campaigns) {
    if (selectedCampaignId == null) return null;
    for (final campaign in campaigns) {
      if (campaign.id == selectedCampaignId) return campaign.name;
    }
    return null;
  }

  /// Tarjeta de una persona (D-04 §2.3).
  Widget _accountCard(
    BuildContext context,
    AccountSummary row,
    List<CampaignRead> campaigns,
    bool personal,
  ) {
    final campaignName = _campaignName(campaigns);
    final filtered = selectedCampaignId != null;
    final account = row.account;
    final amount = filtered ? row.scope.pendingMinor : account.netMinor;
    final lines = filtered
        ? [
            chargesLine(row.scope, campaignName: campaignName),
            netLine(account),
            ?unattributedCreditLine(account),
          ]
        : [chargesLine(row.scope), pendingAndCreditLine(account)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(
                  row.name.isEmpty
                      ? '?'
                      : row.name.characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Sin recorte: son cifras contables, no un subtítulo
                    // decorativo.
                    for (final line in lines) Text(line, maxLines: 5),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Reparto de ancho explícito entre nombre e importe: sin esto la
              // columna del importe se quedaba con lo que pedía y el nombre se
              // partía por carácter al 130 % (UIBUG-020, UIBUG-017).
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      filtered
                          ? pendingCaption(campaignName ?? 'campaña')
                          : netCaptionAll,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.end,
                    ),
                    // El importe NUNCA se trunca: es el dato más importante de
                    // la tarjeta. Si no cabe se reduce el cuerpo de letra.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatBob(amount),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: amount > 0
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
                  switch (value) {
                    case 'detail':
                      _statement(row);
                    case 'export':
                      _exportStatement(row);
                    default:
                      _record(
                        row,
                        advance: value == 'advance',
                        campaigns: campaigns,
                      );
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: Text('Ver detalle cronológico'),
                  ),
                  // El estado de cuenta se exporta desde donde se consulta.
                  const PopupMenuItem(
                    value: 'export',
                    child: Text('Exportar estado de cuenta'),
                  ),
                  // En inventario propio sólo el titular registra pagos y
                  // adelantos (#26).
                  if (!personal || row.personId == ownerPersonId) ...[
                    const PopupMenuItem(
                      value: 'pay',
                      child: Text('Registrar pago'),
                    ),
                    const PopupMenuItem(
                      value: 'advance',
                      child: Text('Registrar adelanto'),
                    ),
                  ] else
                    const PopupMenuItem(
                      enabled: false,
                      child: Text('Inventario propio: pagos sólo del titular'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _backup() async {
    try {
      final result = await ref.read(backupServiceProvider).export();
      if (!mounted) return;
      final photos = result.attachmentCount == 1
          ? '1 fotografía de factura'
          : '${result.attachmentCount} fotografías de factura';
      showSuccess(
        context,
        'Respaldo guardado en ${result.path} (base de datos y $photos).',
      );
      // Una discrepancia no puede quedarse en silencio: si una factura ya no
      // tiene su foto en el teléfono, el usuario tiene que enterarse ahora y
      // no el día que necesite restaurar.
      if (result.hasWarnings) await _showNotices('Respaldo', result.warnings);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Avisos que acompañan a una operación que sí terminó.
  Future<void> _showNotices(String title, List<String> notices) async {
    if (!mounted || notices.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final notice in notices) Text('· $notice')],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Restauración: valida el archivo, comprueba de quién es, avisa de que
  /// reemplaza todo y sólo entonces sustituye la base, en exclusiva y
  /// recalculando la autorización (`GuardedRestore`). La copia previa se
  /// conserva siempre.
  Future<void> _restore() async {
    final service = ref.read(backupServiceProvider);
    final guarded = ref.read(guardedRestoreProvider);
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

    // De quién es la copia, antes de pedir confirmación. Una copia ajena o
    // ilegible no llega a ofrecerse (y la restauración lo vuelve a comprobar).
    final RestoreOwnershipVerdict ownership;
    try {
      ownership = await guarded.preview(chosen.path);
    } on Object catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    if (!ownership.accepted) {
      showError(context, ownership.message);
      return;
    }

    // Qué trae exactamente el archivo, antes de reemplazar nada. El formato
    // histórico sólo guarda la base: conviene saberlo ANTES de aceptar.
    final contents = validation.isLegacyWithoutPhotos
        ? 'Formato histórico: contiene la base de datos, pero NO las '
              'fotografías de factura. Las fotografías actuales del teléfono '
              'se conservan.'
        : 'Contiene la base de datos y ${validation.attachmentCount} '
              'fotografía(s) de factura.';

    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Restaurar este respaldo?',
      detail:
          '${p.basename(chosen.path)}\n'
          'Esquema versión ${validation.schemaVersion}\n'
          '$contents\n'
          '${ownership.message}\n\n'
          'TODOS los datos actuales se reemplazarán por los del respaldo. '
          'Se guardará automáticamente una copia de los datos actuales por si '
          'necesita volver atrás.',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) return;

    // El aviso sobrevive a la navegación: si la base restaurada no habilita
    // operaciones, el router lleva a la pantalla de acceso.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = (await guarded.restore(chosen.path)).result;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Respaldo restaurado (${result.restoredAttachments} '
            'fotografía(s)). Copia de los datos anteriores: '
            '${result.safetyCopyPath}',
          ),
        ),
      );
      if (!mounted) return;
      _refresh();
      if (result.warnings.isNotEmpty) {
        await _showNotices('Restauración', result.warnings);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Defensivo: si la modalidad cambia con la pantalla abierta (p. ej. al
    // restaurar una copia con otro titular), se recargan los datos y con ellos
    // el titular que decide el menú (#26). Hoy el menú ya cambia sin esto,
    // porque `personal` sale de ref.watch y el titular se leyó al cargar.
    ref.listen(operationModeProvider, (previous, next) {
      if (previous != next) _refresh();
    });
    return _page(context);
  }

  Widget _page(BuildContext context) => PageFrame(
    title: 'Liquidación y cuentas',
    subtitle: 'Cargos, pagos, adelantos y saldos sin borrar el historial.',
    action: PopupMenuButton<String>(
      tooltip: 'Copias de seguridad',
      // Carpeta, no nube (UIBUG-049): el menú es del respaldo local. La copia
      // en el servidor (F08) es una entrada aparte y explícita del menú.
      icon: const Icon(Icons.folder_outlined),
      onSelected: (value) => switch (value) {
        'export' => _backup(),
        'remote' => context.push('/respaldo-remoto'),
        _ => _restore(),
      },
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
        // Copia privada en el servidor: acción explícita, no sincronización.
        PopupMenuItem(
          value: 'remote',
          child: ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Respaldo en la nube'),
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
        final (ledger, farmCosts, productCosts, campaigns) = snapshot.data!;
        final settlements = ledger.summaries(campaignId: selectedCampaignId);
        final ownerId = ledger.ownerPersonId;
        final personal =
            ref.watch(operationModeProvider) == OperationMode.personal;
        final visibleSettlements = settlements.where((row) {
          return personQuery.isEmpty || matchesSearch(row.name, personQuery);
        }).toList();
        if (settlements.isEmpty && ownerId == null)
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
                    value: campaign.id,
                    child: Text(campaign.name),
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
            if (ownerId != null) _ownCard(context, ledger, ownerId, campaigns),
            if (settlements.isEmpty)
              Card(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  message: personal
                      ? 'En inventario propio no hay cuentas por cobrar.'
                      : 'Registra familiares o terceros para ver su '
                            'liquidación.',
                ),
              ),
            for (final row in visibleSettlements)
              _accountCard(context, row, campaigns, personal),
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
                      title: Text(row.farmName),
                      subtitle: Text(
                        '${row.ownerName} · ${formatHectares(row.areaM2)} · '
                        'Total ${formatBob(row.totalCostBobMinor)}',
                      ),
                      trailing: Text(
                        row.costPerHectareMinor == null
                            ? 'sin superficie'
                            : '${formatBob(row.costPerHectareMinor!)}/ha',
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
                      title: Text(row.productName),
                      subtitle: Text(
                        formatQuantity(row.quantityBase, row.unit),
                      ),
                      trailing: Text(
                        formatBob(row.totalCostBobMinor),
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
///
/// D-04 (§2.4): la campaña es sólo la de registro y el saldo de referencia es
/// el neto de todas las campañas, no el de la campaña filtrada.
class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({
    required this.personName,
    required this.registration,
    required this.netMinor,
    required this.advance,
    this.ownRecord = false,
  });

  final String personName;
  final String registration;
  final int netMinor;
  final bool advance;

  /// E-15: pago propio del titular. No hay saldo que cobrar (criterio Q-2).
  final bool ownRecord;

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
            widget.registration,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            widget.ownRecord
                ? ownPaymentDialogText
                : dialogNetText(widget.netMinor),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(dialogFifoText, style: Theme.of(context).textTheme.bodySmall),
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
