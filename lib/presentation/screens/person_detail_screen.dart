import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

typedef _PersonData = ({
  Map<String, Object?> profile,
  List<Map<String, Object?>> farms,
  List<Map<String, Object?>> applications,
  List<Map<String, Object?>> stock,
  List<Map<String, Object?>> statement,
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
      statement: await repo.detailedStatement(personId),
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
      return DefaultTabController(
        length: 5,
        child: PageFrame(
          title: d.profile['name'] as String,
          subtitle:
              '${d.profile['role'] == 'FAMILY'
                  ? 'Familiar'
                  : d.profile['role'] == 'THIRD_PARTY'
                  ? 'Tercero'
                  : 'Administrador'} · saldo ${formatBob(d.profile['balance'] as int)}',
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Resumen'),
                  Tab(text: 'Chacos'),
                  Tab(text: 'Aplicaciones'),
                  Tab(text: 'Inventario'),
                  Tab(text: 'Cuenta'),
                ],
              ),
              SizedBox(
                height: 480,
                child: TabBarView(
                  children: [
                    _Section(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.landscape_outlined),
                          title: const Text('Superficie'),
                          trailing: Text(
                            '${(d.profile['area_m2'] as int) / 10000} ha',
                          ),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          title: const Text('Saldo total'),
                          trailing: Text(
                            formatBob(d.profile['balance'] as int),
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      children: [
                        for (final farm in d.farms)
                          ListTile(
                            title: Text(farm['name'] as String),
                            subtitle: Text(
                              '${(farm['area_m2'] as int) / 10000} ha',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/chacos/${farm['id']}'),
                          ),
                      ],
                    ),
                    _Section(
                      children: [
                        for (final app in d.applications)
                          ListTile(
                            title: Text(app['farm_name'] as String),
                            subtitle: Text(
                              '${app['campaign_name']} · ${app['applied_at'].toString().substring(0, 10)}',
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
                    _Section(
                      children: [
                        for (final row in d.statement)
                          ListTile(
                            title: Text(row['concept'].toString()),
                            subtitle: Text(
                              row['transaction_date'].toString().substring(
                                0,
                                10,
                              ),
                            ),
                            trailing: Text(
                              formatBob(row['amount_bob_minor_signed'] as int),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
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
  Widget build(BuildContext context) => SingleChildScrollView(
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
