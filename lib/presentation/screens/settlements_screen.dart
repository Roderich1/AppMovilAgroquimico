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
import '../theme/agro_theme.dart';
import '../widgets/account_statement_view.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_a_payment.dart';
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show BigFigure, RdmScrollPage, splitBob;
import '../widgets/identification_texts.dart' show labelPhotosNotInBackups;

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
      await repo.accountLedger(withDetails: false),
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

  /// Un único «Registrar pago» (bloque de experiencia, 2026-10-30): pago y
  /// adelanto tienen la misma mecánica (RN-39) y sólo cambiaba el `type`
  /// guardado. Lo nuevo se guarda como PAYMENT; los ADVANCE históricos se
  /// conservan y se siguen leyendo como «Adelanto». Si no hay deuda, el pago
  /// queda a favor, que es lo que el agricultor llamaba adelanto.
  Future<void> _record(
    AccountSummary person, {
    required List<CampaignRead> campaigns,
    bool ownRecord = false,
  }) async {
    // El diálogo es dueño de su propio TextEditingController y lo libera en
    // `State.dispose()`. Antes el controlador se creaba aquí y se liberaba al
    // volver de `showDialog`, mientras el diálogo aún se animaba al cerrarse:
    // el TextField seguía montado y volvía a suscribirse a un controlador ya
    // liberado (UIBUG-005).
    final selected = _selectedPeriod(campaigns);
    final result = await showAccountPaymentSheet(
      context,
      personName: person.name,
      registration: registrationText(selected, DateTime.now()),
      netMinor: person.account.netMinor,
      ownRecord: ownRecord,
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
      builder: (dialogContext) => _FullScreenSheet(
        overline: 'Cuenta',
        title: 'Estado de cuenta · ${person.name}',
        child: AccountStatementView(statement: statement),
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
      builder: (dialogContext) => _FullScreenSheet(
        overline: 'Titular · no es deuda',
        title: 'Movimientos propios · $name',
        child: OwnMovementsView(statement: statement),
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
    final summary = AccountSummary(
      account: ledger.account(ownerId),
      campaignId: selectedCampaignId,
    );
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StatusBadge(label: 'No es deuda', tone: BadgeTone.ok),
                    const SizedBox(height: 8),
                    Text(
                      ownCardTitle,
                      style: const TextStyle(
                        fontFamily: AgroFonts.display,
                        fontSize: 20,
                        height: 26 / 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      person.name,
                      style: onInk.copyWith(color: AgroColors.onInkMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ownConsumptionLine(
                        consumption,
                        campaignName: _campaignName(campaigns),
                      ),
                      style: onInk.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(ownApplicationsLine(consumption), style: onInk),
                    Text(
                      ownRecordsLine(
                        ledger.ownAccount(ownerId),
                        period: _selectedPeriod(campaigns),
                      ),
                      style: onInk,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones de lo propio',
                iconColor: AgroColors.onInk,
                onSelected: (value) {
                  switch (value) {
                    case 'detail':
                      _ownMovements(ownerId, person.name);
                    case 'export':
                      _exportStatement(summary);
                    default:
                      _record(summary, campaigns: campaigns, ownRecord: true);
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
                  // Criterio Q-2: el titular conserva su pago (#26); se
                  // registra aparte, nunca como cobro.
                  PopupMenuItem(value: 'pay', child: Text('Registrar pago')),
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
    final caption = filtered
        ? pendingCaption(campaignName ?? 'campaña')
        : netCaptionAll;
    // En inventario propio sólo el titular registra pagos (#26).
    final canPay = !personal || row.personId == ownerPersonId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // El nombre ocupa su propia fila, entero, con el menú al lado
              // (F-2 del 2026-10-30; antes UIBUG-020 y UIBUG-017).
              Row(
                children: [
                  Expanded(child: Text(row.name, style: AgroText.value)),
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones de ${row.name}',
                    onSelected: (value) {
                      switch (value) {
                        case 'detail':
                          _statement(row);
                        default:
                          _exportStatement(row);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'detail',
                        child: Text('Ver detalle cronológico'),
                      ),
                      // El estado de cuenta se exporta desde donde se consulta.
                      PopupMenuItem(
                        value: 'export',
                        child: Text('Exportar estado de cuenta'),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _AccountFigures(
                  lines: lines,
                  caption: caption,
                  amount: amount,
                ),
              ),
              const SizedBox(height: 10),
              if (canPay)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: Key('account-pay-${row.personId}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      textStyle: const TextStyle(
                        fontFamily: AgroFonts.body,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => _record(row, campaigns: campaigns),
                    child: const Text('Registrar pago'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Inventario propio: pagos sólo del titular',
                    key: Key('account-pay-blocked-${row.personId}'),
                    style: AgroText.detail,
                  ),
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
        'Respaldo guardado en ${result.path} (base de datos y $photos). '
        '$labelPhotosNotInBackups',
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
              'fotografía(s) de factura. $labelPhotosNotInBackups';

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
    final errorColor = Theme.of(context).colorScheme.error;
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
      // También si la pantalla ya no está: un «No pudimos confirmar…» no
      // puede perderse (F08-PREV-01).
      showErrorOn(messenger, errorColor, error);
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

  Widget _page(BuildContext context) => RdmScrollPage(
    header: RdmAHero(
      overline: 'Cuentas',
      title: 'Liquidación y cuentas',
      subtitle: 'Cargos, pagos, adelantos y saldos sin borrar el historial.',
      actions: [
        Material(
          color: AgroColors.inkSoft,
          shape: const CircleBorder(),
          child: PopupMenuButton<String>(
            tooltip: 'Copias de seguridad',
            // Carpeta, no nube (UIBUG-049): el menú es del respaldo local. La
            // copia en el servidor (F08) es una entrada aparte y explícita.
            icon: const Icon(Icons.folder_outlined, color: AgroColors.onInk),
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
              // Copia privada en el servidor: acción explícita, no
              // sincronización.
              PopupMenuItem(
                value: 'remote',
                child: ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('Respaldo en la nube'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    children: [
      FutureBuilder(
        future: data,
        builder: (context, snapshot) {
          // El error se comprueba ANTES que los datos: si no, un fallo se
          // presenta como "cargando" y la pantalla gira indefinidamente.
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (ledger, farmCosts, productCosts, campaigns) = snapshot.data!;
          final settlements = ledger.summaries(campaignId: selectedCampaignId);
          final ownerId = ledger.ownerPersonId;
          final personal =
              ref.watch(operationModeProvider) == OperationMode.personal;
          final visibleSettlements = settlements.where((row) {
            return personQuery.isEmpty || matchesSearch(row.name, personQuery);
          }).toList();
          if (settlements.isEmpty && ownerId == null) {
            return const Card(
              child: EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                message:
                    'Registra familiares o terceros para ver su liquidación.',
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: selectedCampaignId,
                // Ocupa el ancho del campo y parte el nombre si no cabe: sin
                // esto se desbordaba 77 px a 360 dp con letra ×1,3
                // (2026-10-30).
                isExpanded: true,
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
              const SizedBox(height: 16),
              if (ownerId != null)
                _ownCard(context, ledger, ownerId, campaigns),
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
              const SizedBox(height: 12),
              const Text('Costo por chaco y hectárea', style: AgroText.h2),
              const SizedBox(height: 10),
              for (final row in farmCosts) _FarmCostCard(row: row),
              const SizedBox(height: 12),
              const Text('Costo consumido por producto', style: AgroText.h2),
              const SizedBox(height: 10),
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
            ],
          );
        },
      ),
    ],
  );
}

/// Costo de un chaco (lámina Costos por chaco): el costo por hectárea en
/// grande y el total, con su responsable y superficie.
class _FarmCostCard extends StatelessWidget {
  const _FarmCostCard({required this.row});
  final FarmCostRead row;

  @override
  Widget build(BuildContext context) {
    final perHectare = row.costPerHectareMinor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
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
                      ? const Text('sin superficie', style: AgroText.detail)
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
    );
  }
}

/// Estado de cuenta o movimientos propios a pantalla completa (láminas
/// Cuenta y Propios), con «Cerrar» arriba. Es un diálogo: no cambia la
/// navegación y se cierra como antes.
class _FullScreenSheet extends StatelessWidget {
  const _FullScreenSheet({
    required this.overline,
    required this.title,
    required this.child,
  });

  final String overline;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: AgroColors.canvas,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(overline, style: AgroText.detail)),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AgroColors.ink,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                    ),
                  ],
                ),
                Semantics(header: true, child: Text(title, style: AgroText.h2)),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

/// Cifras de la tarjeta de persona: las líneas contables y el importe con su
/// rótulo. Con sitio (≥ [wideWidth]) van lado a lado; en teléfono el importe
/// pasa debajo de las líneas, a lo ancho, para que ni el nombre ni el importe
/// compitan por columnas estrechas (F-2, 2026-10-30). El rótulo dice qué es
/// la cifra; el color no es lo único que lo dice.
class _AccountFigures extends StatelessWidget {
  const _AccountFigures({
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
    // Sin recorte: son cifras contables, no un subtítulo decorativo.
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
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideWidth) {
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
          children: [detail, const SizedBox(height: 8), figure],
        );
      },
    );
  }
}
