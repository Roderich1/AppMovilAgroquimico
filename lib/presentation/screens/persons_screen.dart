import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class PersonsScreen extends ConsumerWidget {
  const PersonsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Personas',
    subtitle: 'Perfil operativo, chacos, inventario y cuenta.',
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(repositoryProvider).personProfiles(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return Card(
          child: Column(
            children: [
              for (final row in snapshot.data!)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      (row['name'] as String).characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(
                    row['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${row['role'] == 'FAMILY'
                        ? 'Familiar'
                        : row['role'] == 'THIRD_PARTY'
                        ? 'Tercero'
                        : 'Administrador'} · ${(row['area_m2'] as int) / 10000} ha',
                  ),
                  trailing: Text(formatBob(row['balance'] as int)),
                  onTap: () => context.go('/personas/${row['id']}'),
                ),
            ],
          ),
        );
      },
    ),
  );
}
