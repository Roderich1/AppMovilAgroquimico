import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../data/typed_reads.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_a_payment.dart';
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show BigFigure, RdmScrollPage, splitBob;

typedef _PersonsData = (List<Map<String, Object?>>, AccountLedger);

/// Personas (lámina Personas): lo que le deben en todas las campañas y una
/// tarjeta por persona con su cifra, «Registrar pago» y «Ver cuenta». El
/// titular muestra su consumo propio (no es deuda). Desde aquí se llega a
/// Cuentas (`/liquidacion`): filtro por campaña, costos y respaldos.
class PersonsScreen extends ConsumerStatefulWidget {
  const PersonsScreen({super.key});
  @override
  ConsumerState<PersonsScreen> createState() => _PersonsScreenState();
}

class _PersonsScreenState extends ConsumerState<PersonsScreen> {
  late Future<_PersonsData> profiles;
  String query = '';

  /// E-15: el libro dice quién es el titular y su consumo propio. Sólo dos
  /// lecturas: más consultas al cargar rompen las pruebas de espera fija.
  static Future<_PersonsData> _load(AgroRepository repo) async => (
    await repo.personProfiles(),
    await repo.accountLedger(withDetails: false),
  );

  @override
  void initState() {
    super.initState();
    profiles = _load(ref.read(repositoryProvider));
  }

  void _refresh() {
    final next = _load(ref.read(repositoryProvider));
    setState(() {
      profiles = next;
    });
  }

  /// La campaña de registro es la activa, como en Cuentas; se lee al pagar.
  Future<void> _pay(AccountLedger ledger, int personId) async {
    final campaigns = await ref.read(repositoryProvider).campaignsTyped();
    if (!mounted) return;
    final recorded = await recordAccountPayment(
      context,
      ref,
      person: AccountSummary(
        account: ledger.account(personId),
        campaignId: null,
      ),
      campaign: campaigns.where((campaign) => campaign.isActive).firstOrNull,
    );
    if (recorded && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PersonsData>(
    future: profiles,
    builder: (context, snapshot) {
      final data = snapshot.data;
      return RdmScrollPage(
        header: _header(data?.$2),
        children: [
          if (snapshot.hasError)
            EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            )
          else if (data == null)
            const Center(child: CircularProgressIndicator())
          else
            ..._content(context, data),
        ],
      );
    },
  );

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
      showBack: false,
      // Personas era la única lista sin buscador ni recarga (UIBUG-052).
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

  List<Widget> _content(BuildContext context, _PersonsData data) {
    final (profilesRows, ledger) = data;
    final owner = ledger.ownerPersonId;
    final personal = ref.watch(operationModeProvider) == OperationMode.personal;
    final rows = profilesRows
        .where((row) => matchesSearch(row['name'] as String, query))
        .toList();
    return [
      TextField(
        onChanged: (value) => setState(() => query = value.trim()),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: 'Buscar persona',
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      // Cuentas ya no es pestaña: se llega desde aquí (B1).
      AgroGroup(
        children: [
          ValueRow(
            key: const Key('persons-open-accounts'),
            label: 'Cuentas',
            value: 'Por campaña, costos y respaldos',
            onTap: () => context.push('/liquidacion'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        EmptyState(
          icon: query.isEmpty
              ? Icons.people_alt_outlined
              : Icons.search_off_outlined,
          message: query.isEmpty
              ? 'Aún no hay personas registradas.'
              : 'Ninguna persona coincide con "$query".',
        )
      else
        for (final row in rows)
          _PersonCard(
            key: Key('person-card-${row['id']}'),
            row: row,
            ledger: ledger,
            isOwner: row['id'] == owner,
            // Al titular no se le registran pagos de cuenta (decisión del
            // autor del 2026-11-12) y en inventario propio nadie los recibe.
            onPay: row['id'] == owner || row['role'] == 'ADMIN' || personal
                ? null
                : () => _pay(ledger, row['id']! as int),
            onStatement: row['role'] == 'ADMIN'
                ? null
                : () => row['id'] == owner
                      ? showOwnMovements(
                          context,
                          ref,
                          personId: row['id']! as int,
                          name: row['name'] as String,
                        )
                      : showAccountStatement(
                          context,
                          ref,
                          personId: row['id']! as int,
                          name: row['name'] as String,
                        ),
            onOpen: () => context.push('/personas/${row['id']}'),
          ),
    ];
  }
}

/// Tarjeta de una persona: nombre, rol y superficie, su cifra a la derecha y
/// sus acciones. Tocarla abre su detalle.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    super.key,
    required this.row,
    required this.ledger,
    required this.isOwner,
    required this.onPay,
    required this.onStatement,
    required this.onOpen,
  });

  final Map<String, Object?> row;
  final AccountLedger ledger;
  final bool isOwner;
  final VoidCallback? onPay;
  final VoidCallback? onStatement;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final admin = row['role'] == 'ADMIN';
    final id = row['id']! as int;
    final net = ledger.account(id).netMinor;
    const amountStyle = TextStyle(
      fontFamily: AgroFonts.display,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w700,
      color: AgroColors.ink,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              onTap: onOpen,
              title: Text(
                row['name'] as String,
                style: AgroText.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // El administrador no participa en la liquidación: se marca en
              // vez de mostrarle superficie y saldo a cero como si fuera un
              // familiar más (UIBUG-057).
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOwner
                        ? '${personRoleLabel(row['role'])} · titular · '
                              '${formatHectares(row['area_m2'] as int)}'
                        : admin
                        ? '${personRoleLabel(row['role'])} · no participa en la '
                              'liquidación'
                        : '${personRoleLabel(row['role'])} · '
                              '${formatHectares(row['area_m2'] as int)}',
                    style: AgroText.detail,
                  ),
                  // E-15: el titular no es deudor de sí mismo; se muestra su
                  // consumo propio, no un saldo. En su propia línea: a la
                  // derecha no cabía con la letra ampliada.
                  if (isOwner)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Consumo propio '
                        '${bob(ledger.ownConsumption(id).activeCostMinor)}',
                        style: amountStyle.copyWith(fontSize: 16),
                      ),
                    ),
                ],
              ),
              // E-15 (A2): el neto por cobrar del libro, sin lo propio de quien
              // fue titular. Ancho acotado: se reduce entera si no cabe.
              trailing: isOwner || admin
                  ? null
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              net > 0
                                  ? 'Debe'
                                  : net < 0
                                  ? 'A favor'
                                  : 'Sin saldo',
                              style: AgroText.label,
                            ),
                            Text(formatBob(net), style: amountStyle),
                          ],
                        ),
                      ),
                    ),
            ),
            if (onPay != null || onStatement != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onPay != null)
                      FilledButton(
                        key: Key('person-pay-$id'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          textStyle: const TextStyle(
                            fontFamily: AgroFonts.body,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: onPay,
                        child: const Text('Registrar pago'),
                      ),
                    if (onStatement != null)
                      TextButton(
                        key: Key('person-statement-$id'),
                        style: TextButton.styleFrom(
                          foregroundColor: AgroColors.link,
                          minimumSize: const Size(0, 44),
                          textStyle: const TextStyle(
                            fontFamily: AgroFonts.body,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: onStatement,
                        child: Text(
                          isOwner ? 'Ver movimientos propios' : 'Ver cuenta',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
