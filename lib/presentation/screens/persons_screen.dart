import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class PersonsScreen extends ConsumerStatefulWidget {
  const PersonsScreen({super.key});
  @override
  ConsumerState<PersonsScreen> createState() => _PersonsScreenState();
}

class _PersonsScreenState extends ConsumerState<PersonsScreen> {
  late Future<(List<Map<String, Object?>>, AccountLedger)> profiles;
  String query = '';

  /// E-15: el libro dice quién es el titular y su consumo propio.
  static Future<(List<Map<String, Object?>>, AccountLedger)> _load(
    AgroRepository repo,
  ) async => (
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

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Personas',
    subtitle: 'Perfil operativo, chacos, inventario y cuenta.',
    // Personas era la única lista sin buscador ni recarga, mientras Inicio,
    // Inventario, Aplicaciones, Compras y Liquidación sí los tenían
    // (UIBUG-052).
    action: IconButton.filledTonal(
      onPressed: _refresh,
      icon: const Icon(Icons.refresh),
      tooltip: 'Recargar',
    ),
    child: FutureBuilder<(List<Map<String, Object?>>, AccountLedger)>(
      future: profiles,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final (profilesRows, ledger) = snapshot.data!;
        final owner = ledger.ownerPersonId;
        final rows = profilesRows
            .where((row) => matchesSearch(row['name'] as String, query))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (value) => setState(() => query = value.trim()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar persona',
                isDense: true,
              ),
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
              Card(
                child: Column(
                  children: [
                    for (final row in rows)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            (row['name'] as String).characters.first
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(
                          row['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // El administrador no participa en la liquidación: se
                        // marca en vez de mostrarle superficie y saldo a cero
                        // como si fuera un familiar más (UIBUG-057).
                        subtitle: Text(
                          row['id'] == owner
                              ? '${personRoleLabel(row['role'])} · titular · '
                                    '${formatHectares(row['area_m2'] as int)}'
                              : row['role'] == 'ADMIN'
                              ? '${personRoleLabel(row['role'])} · no participa '
                                    'en la liquidación'
                              : '${personRoleLabel(row['role'])} · '
                                    '${formatHectares(row['area_m2'] as int)}',
                        ),
                        // E-15: el titular no es deudor de sí mismo; se
                        // muestra su consumo propio, no un saldo.
                        trailing: row['id'] == owner
                            ? Text(
                                'Consumo propio '
                                '${bob(ledger.ownConsumption(owner!).activeCostMinor)}',
                              )
                            : row['role'] == 'ADMIN'
                            ? null
                            // E-15 (A2): el neto por cobrar del libro, sin
                            // lo propio de quien fue titular.
                            : Text(
                                formatBob(
                                  ledger.account(row['id']! as int).netMinor,
                                ),
                              ),
                        onTap: () => context.push('/personas/${row['id']}'),
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
