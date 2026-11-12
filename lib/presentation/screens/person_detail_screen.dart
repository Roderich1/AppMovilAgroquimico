import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import '../widgets/common.dart';
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show BigFigure, RdmScrollPage, splitBob;

typedef _PersonData = ({
  // Perfil, chacos, aplicaciones y stock por persona no alimentan ninguno de
  // los cinco reportes de EVOLUTION-2: siguen en el camino legacy.
  Map<String, Object?> profile,
  List<Map<String, Object?>> farms,
  List<Map<String, Object?>> applications,
  List<Map<String, Object?>> stock,
  // D-04/E-15: la cuenta sale del libro (una consulta). Para el titular, sus
  // asientos propios se muestran como registro, sin acumulado.
  AccountStatement statement,
});

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.personId});
  final int personId;
  Future<_PersonData> _load(WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    return (
      profile: await repo.personProfile(personId),
      farms: await repo.farmsForPerson(personId),
      applications: await repo.applications(personId: personId),
      stock: await repo.personStockSummary(personId),
      statement: await repo.accountStatement(personId),
    );
  }

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<_PersonData>(
    future: _load(ref),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return RdmScrollPage(
          header: const RdmAHero(title: 'Persona'),
          children: [
            EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final d = snapshot.data!;
      final s = d.statement;
      final ownCost = s.ledger.ownConsumption(personId).activeCostMinor;
      final net = s.account.netMinor;
      return _PersonTabs(
        data: d,
        builder: (context, tabs, body) => RdmScrollPage(
          header: RdmAHero(
            title: d.profile['name'] as String,
            subtitle: s.isCurrentOwner
                ? '${personRoleLabel(d.profile['role'])} · titular · consumo '
                      'propio ${bob(ownCost)}'
                // E-15 (A2): el neto por cobrar del libro, sin lo propio.
                : '${personRoleLabel(d.profile['role'])} · saldo total '
                      '${formatBob(net)}',
            children: [
              const Divider(height: 1, color: AgroColors.inkSoft),
              const SizedBox(height: 14),
              // E-15: el titular no se debe a sí mismo; se muestra su
              // consumo propio, que no es deuda.
              Text(
                s.isCurrentOwner
                    ? 'Consumo propio · no es deuda'
                    : net > 0
                    ? 'Debe · todas las campañas'
                    : net < 0
                    ? 'A favor · todas las campañas'
                    : 'Sin saldo · todas las campañas',
                style: RdmAHero.subtitleStyle,
              ),
              BigFigure(
                number: splitBob(s.isCurrentOwner ? ownCost : net.abs()).number,
                unit: 'Bs',
                size: 40,
                color: AgroColors.lime,
                numberKey: const Key('person-headline-amount'),
              ),
            ],
          ),
          children: [tabs, body(_sections(context, d, s, ownCost))],
        ),
      );
    },
  );

  List<Widget> _sections(
    BuildContext context,
    _PersonData d,
    AccountStatement s,
    int ownCost,
  ) => [
    _Section(
      children: [
        _row(
          title: 'Superficie',
          trailing: formatHectares(d.profile['area_m2'] as int),
        ),
        // Esta cifra suma TODO el histórico, mientras la de Liquidación puede
        // estar filtrada por campaña: son conceptos distintos y cada uno lo
        // dice (UIBUG-013).
        _row(
          title: s.isCurrentOwner
              ? 'Consumo aplicado (costo FIFO) · todas las campañas'
              : 'Saldo total · todas las campañas',
          trailing: s.isCurrentOwner
              ? formatBob(ownCost)
              : formatBob(s.account.netMinor),
        ),
        if (!s.isCurrentOwner && s.hasOwnRecords)
          _row(
            title: 'Consumo propio mientras fue titular',
            trailing: formatBob(ownCost),
          ),
      ],
    ),
    _Section(
      children: [
        for (final farm in d.farms)
          ListTile(
            title: Text(farm['name'] as String, style: _title),
            subtitle: Text(
              formatHectares(farm['area_m2'] as int),
              style: _detail,
            ),
            trailing: const Icon(Icons.chevron_right, color: AgroColors.muted),
            onTap: () => context.push('/chacos/${farm['id']}'),
          ),
      ],
    ),
    _Section(
      children: [
        for (final app in d.applications)
          ListTile(
            title: Text(app['farm_name'] as String, style: _title),
            subtitle: Text(
              '${app['campaign_name']} · ${formatDate(app['applied_at'])}',
              style: _detail,
            ),
            trailing: Text(
              formatBob(app['total_cost_bob_minor'] as int),
              style: _amount,
            ),
          ),
      ],
    ),
    _Section(
      children: [
        for (final row in d.stock)
          ListTile(
            title: Text(row['product_name'] as String, style: _title),
            subtitle: Text(
              'Consumido neto ${formatQuantity(row['consumed_base'] as int, row['unit'] as String)}',
              style: _detail,
            ),
            trailing: Text(
              formatQuantity(
                row['available_base'] as int,
                row['unit'] as String,
              ),
              style: _amount,
            ),
          ),
      ],
    ),
    // La pestaña listaba los movimientos sin saldo corrido ni total, mientras
    // el estado de cuenta de Liquidación sí lo calculaba: dos vistas del mismo
    // dato con distinto nivel de información (UIBUG-028).
    _Section(
      children: [
        for (final line in s.lines)
          ListTile(
            title: Text(conceptLabel(line.entry.concept), style: _title),
            subtitle: Text(
              formatDate(line.entry.transactionDate),
              style: _detail,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatBob(line.entry.amountMinor), style: _amount),
                Text(
                  'Acumulado ${formatBob(line.balanceMinor)}',
                  style: _detail,
                ),
              ],
            ),
          ),
        for (final entry in s.ownLines)
          ListTile(
            title: Text(conceptLabel(entry.concept), style: _title),
            subtitle: Text(
              '${formatDate(entry.transactionDate)} · propio, no es deuda',
              style: _detail,
            ),
            trailing: Text(formatBob(entry.amountMinor), style: _amount),
          ),
      ],
    ),
  ];

  static const _title = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    color: AgroColors.ink,
  );
  static const _detail = AgroText.detail;
  static const _amount = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w700,
    color: AgroColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static Widget _row({required String title, required String trailing}) =>
      ListTile(
        title: Text(title, style: _title),
        trailing: Text(trailing, style: _amount),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;
  @override
  // Sin scroll propio: el desplazamiento es el de la página. Antes cada sección
  // vivía dentro de un área de altura fija y tenía que desplazarse por dentro
  // (UIBUG-030).
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: children.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              message: 'Sin registros.',
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
    ),
  );
}

/// Pestañas del detalle de persona que **se ajustan a su contenido**.
///
/// Antes el área era un `TabBarView` de 480 px fijos: con dos filas dejaba más
/// de media pantalla en blanco y con muchas obligaba a un scroll interno
/// (UIBUG-030). Al pintar sólo la pestaña activa, la altura la marca el
/// contenido y el desplazamiento es el de la página.
///
/// Se pierde el gesto de deslizar entre pestañas, que además era la única forma
/// de alcanzar las últimas y no se anunciaba en ninguna parte (UIBUG-029): la
/// barra es desplazable y todas se alcanzan tocándolas. La elegida va en verde
/// oscuro con su marca: no se distingue sólo por color.
class _PersonTabs extends StatefulWidget {
  const _PersonTabs({required this.data, required this.builder});

  final _PersonData data;
  final Widget Function(
    BuildContext context,
    Widget tabs,
    Widget Function(List<Widget> sections) body,
  )
  builder;

  @override
  State<_PersonTabs> createState() => _PersonTabsState();
}

class _PersonTabsState extends State<_PersonTabs> {
  static const _labels = [
    'Resumen',
    'Chacos',
    'Aplicaciones',
    'Inventario',
    'Cuenta',
  ];
  int index = 0;

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_labels[i]),
                selected: index == i,
                onSelected: (_) => setState(() => index = i),
                showCheckmark: true,
                checkmarkColor: AgroColors.lime,
                selectedColor: AgroColors.ink,
                backgroundColor: AgroColors.surface,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                labelStyle: TextStyle(
                  fontFamily: AgroFonts.body,
                  fontSize: 14,
                  fontWeight: index == i ? FontWeight.w700 : FontWeight.w500,
                  color: index == i ? Colors.white : AgroColors.ink,
                ),
              ),
            ),
        ],
      ),
    ),
    (sections) => sections[index],
  );
}
