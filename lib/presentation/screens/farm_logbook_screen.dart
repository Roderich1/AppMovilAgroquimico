import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

typedef _FarmData = ({
  Map<String, Object?> farm,
  List<Map<String, Object?>> entries,
});

class FarmLogbookScreen extends ConsumerWidget {
  const FarmLogbookScreen({super.key, required this.farmId});
  final int farmId;
  Future<_FarmData> _load(WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    return (
      farm: await repo.farmProfile(farmId),
      entries: await repo.farmLogbook(farmId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<_FarmData>(
    future: _load(ref),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return PageFrame(
          title: 'Bitácora',
          child: EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          ),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final d = snapshot.data!;
      return PageFrame(
        title: d.farm['name'] as String,
        subtitle:
            'Bitácora · ${d.farm['owner_name']} · ${(d.farm['area_m2'] as int) / 10000} ha',
        child: d.entries.isEmpty
            ? const EmptyState(
                icon: Icons.agriculture_outlined,
                message: 'Todavía no hay aplicaciones en este chaco.',
              )
            : Card(
                child: Column(
                  children: [
                    for (final row in d.entries)
                      ExpansionTile(
                        leading: const Icon(Icons.agriculture_outlined),
                        title: Text(row['product_name'] as String),
                        subtitle: Text(
                          '${row['applied_at'].toString().substring(0, 10)} · ${row['campaign_name']} · ${row['person_name']}',
                        ),
                        trailing: Text(
                          formatQuantity(
                            row['quantity_base'] as int,
                            row['unit'] as String,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Área ${(row['treated_area_m2'] as int? ?? 0) / 10000} ha · dosis ${formatQuantity(row['dose_base_per_ha'] as int? ?? 0, row['unit'] as String)}/ha\nTeórico ${formatQuantity(row['theoretical_quantity_base'] as int? ?? 0, row['unit'] as String)} · real ${formatQuantity(row['quantity_base'] as int, row['unit'] as String)} · costo ${formatBob(row['cost_bob_minor'] as int)}\nFIFO: ${row['fifo_lots'] ?? 'sin detalle'}',
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      );
    },
  );
}
