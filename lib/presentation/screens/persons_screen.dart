import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../data/ind_c_chacos_reads.dart' show IndCChacosReads;
import '../../data/typed_reads.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/operation_mode.dart';
import '../../domain/read_models.dart';
import '../../domain/reports/report_composer.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm2_c_accounts.dart';
import '../widgets/rdm2_c_person_search.dart';
import '../widgets/rdm_a_payment.dart';
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show BigFigure, RdmScrollPage, splitBob;

typedef _PersonsData = (List<Map<String, Object?>>, AccountLedger);
typedef _CostsData = (List<FarmCostRead>, List<ProductCostRead>);

/// Personas (ronda 2, sesión C): una sola pantalla con dos áreas.
///
/// * **Cuentas:** la única lista de personas, con búsqueda y filtro de
///   campaña. Cada persona con sus cifras D-04 del alcance, «Registrar pago»
///   y «Ver cuenta»; el titular con su consumo propio (no es deuda); ADMIN,
///   fuera de la liquidación. Tocar una tarjeta abre la persona.
/// * **Costos:** costo por chaco y hectárea y por producto del alcance, con
///   su exportación.
///
/// Antes la misma lista se repetía en `/liquidacion` («Por campaña, costos y
/// respaldos») con tarjetas más largas; esa ruta muestra ahora esta misma
/// pantalla. Los respaldos (copias de seguridad) viven en Ajustes ›
/// Respaldos.
///
/// Lecturas al abrir: perfiles y el libro de cuentas (dos, como antes en
/// Personas: más consultas rompen las pruebas de espera fija). Los costos se
/// leen al abrir el área «Costos».
class PersonsScreen extends ConsumerStatefulWidget {
  const PersonsScreen({super.key, this.initialArea = PersonsArea.accounts});

  final PersonsArea initialArea;

  @override
  ConsumerState<PersonsScreen> createState() => _PersonsScreenState();
}

class _PersonsScreenState extends ConsumerState<PersonsScreen> {
  late Future<_PersonsData> data;
  Future<_CostsData>? costs;
  late PersonsArea area = widget.initialArea;
  String query = '';

  /// Campaña del filtro (nulo = todas). Empieza en la activa (D-04 H-12) y
  /// es también la campaña en que se registra un pago (§2.4).
  int? campaignId;
  bool campaignInitialized = false;

  static Future<_PersonsData> _load(AgroRepository repo) async => (
    await repo.personProfiles(),
    await repo.accountLedger(withDetails: false),
  );

  @override
  void initState() {
    super.initState();
    data = _load(ref.read(repositoryProvider));
  }

  void _refresh() {
    final next = _load(ref.read(repositoryProvider));
    setState(() {
      data = next;
      if (costs != null) costs = _loadCosts();
    });
  }

  Future<_CostsData> _loadCosts() async {
    final repo = ref.read(repositoryProvider);
    return (
      // Mismo alcance que la exportación «Costo por chaco» (decisión C).
      (await repo.farmCostLines(campaignId: campaignId)).lines,
      await repo.productCostReportTyped(campaignId: campaignId),
    );
  }

  void _setArea(PersonsArea next) => setState(() {
    area = next;
    if (next == PersonsArea.costs) costs ??= _loadCosts();
  });

  void _setCampaign(int? next) => setState(() {
    campaignId = next;
    if (costs != null) costs = _loadCosts();
  });

  /// Registra un pago en la campaña del filtro (sólo la de registro: la
  /// imputación va a la deuda más antigua de cualquier campaña, D-04).
  Future<void> _pay(AccountLedger ledger, int personId) async {
    final recorded = await recordAccountPayment(
      context,
      ref,
      person: AccountSummary(
        account: ledger.account(personId),
        campaignId: campaignId,
      ),
      campaign: ledger.campaign(campaignId),
    );
    if (recorded && mounted) _refresh();
  }

  Future<void> _statement(
    AccountLedger ledger,
    int personId,
    bool canPay,
  ) async {
    final recorded = await showAccountStatement(
      context,
      ref,
      personId: personId,
      name: ledger.account(personId).person.name,
      campaignId: campaignId,
      canPay: canPay,
    );
    if (recorded && mounted) _refresh();
  }

  void _openPerson(int personId) =>
      GoRouter.maybeOf(context)?.push('/personas/$personId');

  void _report(ReportKind kind, {int? personId}) =>
      GoRouter.maybeOf(context)?.push(
        '/reportes?tipo=${kind.name}'
        '${personId == null ? '' : '&persona=$personId'}'
        '${campaignId == null ? '' : '&campana=$campaignId'}',
      );

  @override
  Widget build(BuildContext context) {
    // Si la modalidad cambia con la pantalla abierta (p. ej. al restaurar una
    // copia con otro titular), se recargan los datos y el titular.
    ref.listen(operationModeProvider, (previous, next) {
      if (previous != next) _refresh();
    });
    return FutureBuilder<_PersonsData>(
      future: data,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded != null && !campaignInitialized) {
          campaignInitialized = true;
          campaignId = loaded.$2.campaigns
              .where((campaign) => campaign.status == 'ACTIVE')
              .firstOrNull
              ?.id;
        }
        return RdmScrollPage(
          header: _header(loaded?.$2),
          children: [
            if (snapshot.hasError)
              EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(snapshot.error!),
              )
            else if (loaded == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              SegmentToggle<PersonsArea>(
                semanticLabel: 'Área de Personas',
                options: const [
                  ToggleOption(
                    PersonsArea.accounts,
                    'Cuentas',
                    key: Key('persons-area-accounts'),
                  ),
                  ToggleOption(
                    PersonsArea.costs,
                    'Costos',
                    key: Key('persons-area-costs'),
                  ),
                ],
                selected: area,
                onChanged: _setArea,
              ),
              const SizedBox(height: 12),
              _campaignFilter(loaded.$2.campaigns),
              const SizedBox(height: 12),
              if (area == PersonsArea.accounts)
                ..._accounts(context, loaded)
              else
                _costs(loaded.$2),
            ],
          ],
        );
      },
    );
  }

  /// Cabecera oscura: «Le deben · todas las campañas», el mismo dato que
  /// Inicio (`receivableByRole`, familiares y terceros, sin ADMIN ni lo
  /// propio del titular).
  Widget _header(AccountLedger? ledger) {
    final family = ledger?.receivableByRole('FAMILY').receivableMinor ?? 0;
    final third = ledger?.receivableByRole('THIRD_PARTY').receivableMinor ?? 0;
    final debtors = ledger == null
        ? 0
        : ledger.persons
              .where(
                (p) => p.role != 'ADMIN' && ledger.account(p.id).netMinor > 0,
              )
              .length;
    return RdmAHero(
      title: 'Personas',
      actions: [
        CircleIconButton(
          icon: Icons.refresh,
          tooltip: 'Recargar',
          background: AgroColors.inkSoft,
          foreground: AgroColors.onInk,
          onPressed: _refresh,
        ),
      ],
      children: [
        if (ledger != null) ...[
          Text(
            'Le deben · todas las campañas · '
            '$debtors ${debtors == 1 ? 'persona' : 'personas'}',
            style: RdmAHero.subtitleStyle,
          ),
          BigFigure(
            number: splitBob(family + third).number,
            unit: 'Bs',
            size: 44,
            color: AgroColors.lime,
            numberKey: const Key('persons-receivable'),
          ),
        ],
      ],
    );
  }

  Widget _campaignFilter(List<CampaignPeriod> campaigns) =>
      DropdownButtonFormField<int?>(
        key: const Key('persons-campaign'),
        initialValue: campaignId,
        // Ocupa el ancho del campo y parte el nombre si no cabe (2026-10-30).
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Filtrar por campaña'),
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
        onChanged: _setCampaign,
      );

  List<Widget> _accounts(BuildContext context, _PersonsData loaded) {
    final (profileRows, ledger) = loaded;
    final profiles = {for (final row in profileRows) row['id']! as int: row};
    final owner = ledger.ownerPersonId;
    final personal = ref.watch(operationModeProvider) == OperationMode.personal;
    final period = ledger.campaign(campaignId);
    final campaignName = period?.name;
    final filtered = campaignId != null;
    // Una sola regla de búsqueda (P1b), también para el titular.
    final rows = [
      for (final row in ledger.summaries(campaignId: campaignId))
        if (row.personId != owner && matchesPersonSearch(row.name, query)) row,
    ];
    final ownerVisible =
        owner != null &&
        matchesPersonSearch(ledger.account(owner).person.name, query);
    final admins = [
      for (final row in profileRows)
        if (row['role'] == 'ADMIN' &&
            row['id'] != owner &&
            matchesPersonSearch(row['name']! as String, query))
          row,
    ];
    final anyone =
        owner != null ||
        ledger.summaries().isNotEmpty ||
        profileRows.isNotEmpty;
    final receivables = ledger.summaries().where((r) => r.personId != owner);
    return [
      Rdm2cPersonSearchField(
        query: query,
        onChanged: (value) => setState(() => query = value),
      ),
      const SizedBox(height: 16),
      if (!anyone)
        const Card(
          child: EmptyState(
            icon: Icons.people_alt_outlined,
            message: 'Registra familiares o terceros para ver su liquidación.',
          ),
        )
      else if (!ownerVisible && rows.isEmpty && admins.isEmpty)
        Rdm2cNoPersonMatches(query: query)
      else ...[
        if (ownerVisible)
          Rdm2cOwnCard(
            ledger: ledger,
            ownerId: owner,
            profile: profiles[owner],
            campaignId: campaignId,
            campaignName: campaignName,
            recordsLine: ownRecordsLine(
              ledger.ownAccount(owner),
              period: period,
            ),
            onMovements: () => showOwnMovements(
              context,
              ref,
              personId: owner,
              name: ledger.account(owner).person.name,
              campaignId: campaignId,
            ),
            onExport: () =>
                _report(ReportKind.accountStatement, personId: owner),
            onOpen: () => _openPerson(owner),
          ),
        if (receivables.isEmpty && query.trim().isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: personal
                  ? 'En modo individual no hay cuentas por cobrar.'
                  : 'Registra familiares o terceros para ver su liquidación.',
            ),
          ),
        for (final row in rows)
          Rdm2cAccountCard(
            key: Key('person-card-${row.personId}'),
            row: row,
            profile: profiles[row.personId],
            campaignName: campaignName,
            filtered: filtered,
            // Al titular no se le registran pagos de cuenta (decisión del
            // autor del 2026-11-12) y en inventario propio nadie los recibe.
            // El repositorio los rechaza igual.
            onPay: personal ? null : () => _pay(ledger, row.personId),
            blockedNote: personal
                ? 'Modo individual: sin pagos de cuenta'
                : null,
            onStatement: () => _statement(ledger, row.personId, !personal),
            onExport: () =>
                _report(ReportKind.accountStatement, personId: row.personId),
            onOpen: () => _openPerson(row.personId),
          ),
        for (final row in admins)
          Rdm2cAdminCard(
            key: Key('person-card-${row['id']}'),
            name: row['name']! as String,
            profile: row,
            onOpen: () => _openPerson(row['id']! as int),
          ),
      ],
    ];
  }

  Widget _costs(AccountLedger ledger) => FutureBuilder<_CostsData>(
    future: costs,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return EmptyState(
          icon: Icons.error_outline,
          message: friendlyError(snapshot.error!),
        );
      }
      final loaded = snapshot.data;
      if (loaded == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Rdm2cCostsArea(
        scope: ledger.campaign(campaignId)?.name ?? 'todas las campañas',
        farmCosts: loaded.$1,
        productCosts: loaded.$2,
        onOpenFarm: (farmId) =>
            GoRouter.maybeOf(context)?.push('/chacos/$farmId'),
        onExportFarms: () => _report(ReportKind.farmCost),
        onExportProducts: () => _report(ReportKind.productCost),
      );
    },
  );
}
