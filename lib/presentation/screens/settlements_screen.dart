import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../domain/read_models.dart';
import '../../domain/reports/report_composer.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/local_backup_actions.dart';
import '../widgets/rdm_a_payment.dart';
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show BigFigure, RdmScrollPage, splitBob;

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
    // D-04: la campaña elegida sólo es la de registro; la imputación va a la
    // deuda más antigua de cualquier campaña.
    final recorded = await recordAccountPayment(
      context,
      ref,
      person: person,
      campaign: campaigns
          .where((campaign) => campaign.id == selectedCampaignId)
          .firstOrNull,
      ownRecord: ownRecord,
    );
    if (recorded && mounted) _refresh();
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

  Future<void> _statement(AccountSummary person) => showAccountStatement(
    context,
    ref,
    personId: person.personId,
    name: person.name,
    campaignId: selectedCampaignId,
  );

  /// «Movimientos propios» del titular (E-15 §B.2).
  Future<void> _ownMovements(int personId, String name) => showOwnMovements(
    context,
    ref,
    personId: personId,
    name: name,
    campaignId: selectedCampaignId,
  );

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
            // Mismo procedimiento que la pantalla «Respaldos»
            // (`local_backup_actions.dart`).
            onSelected: (value) => switch (value) {
              'export' => exportLocalBackup(context, ref),
              'remote' => context.push('/respaldo-remoto'),
              _ => restoreLocalBackup(context, ref, onRestored: _refresh),
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
