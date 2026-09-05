import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class PersonsScreen extends ConsumerStatefulWidget {
  const PersonsScreen({super.key});
  @override
  ConsumerState<PersonsScreen> createState() => _PersonsScreenState();
}

class _PersonsScreenState extends ConsumerState<PersonsScreen> {
  late Future<List<Map<String, Object?>>> profiles;
  String query = '';

  @override
  void initState() {
    super.initState();
    profiles = ref.read(repositoryProvider).personProfiles();
  }

  void _refresh() {
    final next = ref.read(repositoryProvider).personProfiles();
    setState(() => profiles = next);
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
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: profiles,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!
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
                          row['role'] == 'ADMIN'
                              ? '${personRoleLabel(row['role'])} · no participa '
                                    'en la liquidación'
                              : '${personRoleLabel(row['role'])} · '
                                    '${formatHectares(row['area_m2'] as int)}',
                        ),
                        trailing: row['role'] == 'ADMIN'
                            ? null
                            : Text(formatBob(row['balance'] as int)),
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
