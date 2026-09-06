import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/money.dart';
import '../../domain/read_models.dart';
import '../widgets/common.dart';

typedef _PersonData = ({
  // Perfil, chacos, aplicaciones y stock por persona no alimentan ninguno de
  // los cinco reportes de EVOLUTION-2: siguen en el camino legacy.
  Map<String, Object?> profile,
  List<Map<String, Object?>> farms,
  List<Map<String, Object?>> applications,
  List<Map<String, Object?>> stock,
  List<StatementEntryRead> statement,
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
      statement: await repo.detailedStatementTyped(personId),
    );
  }

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<_PersonData>(
    future: _load(ref),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return PageFrame(
          title: 'Persona',
          child: EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          ),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final d = snapshot.data!;
      return _PersonTabs(
        data: d,
        builder: (context, tabs, body) => PageFrame(
          title: d.profile['name'] as String,
          subtitle:
              '${personRoleLabel(d.profile['role'])} · saldo total '
              '${formatBob(d.profile['balance'] as int)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tabs,
              body([
                _Section(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.landscape_outlined),
                      title: const Text('Superficie'),
                      trailing: Text(
                        formatHectares(d.profile['area_m2'] as int),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      // Esta cifra suma TODO el histórico, mientras la
                      // de Liquidación puede estar filtrada por campaña:
                      // son conceptos distintos y ahora cada uno lo dice
                      // (UIBUG-013).
                      title: const Text('Saldo total · todas las campañas'),
                      trailing: Text(formatBob(d.profile['balance'] as int)),
                    ),
                  ],
                ),
                _Section(
                  children: [
                    for (final farm in d.farms)
                      ListTile(
                        title: Text(farm['name'] as String),
                        subtitle: Text(formatHectares(farm['area_m2'] as int)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/chacos/${farm['id']}'),
                      ),
                  ],
                ),
                _Section(
                  children: [
                    for (final app in d.applications)
                      ListTile(
                        title: Text(app['farm_name'] as String),
                        subtitle: Text(
                          '${app['campaign_name']} · ${formatDate(app['applied_at'])}',
                        ),
                        trailing: Text(
                          formatBob(app['total_cost_bob_minor'] as int),
                        ),
                      ),
                  ],
                ),
                _Section(
                  children: [
                    for (final row in d.stock)
                      ListTile(
                        title: Text(row['product_name'] as String),
                        subtitle: Text(
                          'Consumido ${formatQuantity(row['consumed_base'] as int, row['unit'] as String)}',
                        ),
                        trailing: Text(
                          formatQuantity(
                            row['available_base'] as int,
                            row['unit'] as String,
                          ),
                        ),
                      ),
                  ],
                ),
                // La pestaña listaba los movimientos sin saldo corrido ni
                // total, mientras el estado de cuenta de Liquidación sí lo
                // calculaba: dos vistas del mismo dato con distinto nivel
                // de información (UIBUG-028).
                _Section(
                  children: [
                    for (final line in StatementLine.runningBalance(
                      d.statement,
                    ))
                      ListTile(
                        title: Text(conceptLabel(line.entry.concept)),
                        subtitle: Text(formatDate(line.entry.transactionDate)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatBob(line.entry.amountBobMinorSigned),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Acumulado ${formatBob(line.balanceMinor)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      );
    },
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
      child: children.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              message: 'Sin registros.',
            )
          : Column(children: children),
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
/// barra es desplazable y todas se alcanzan tocándolas.
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
              ),
            ),
        ],
      ),
    ),
    (sections) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: sections[index],
    ),
  );
}
