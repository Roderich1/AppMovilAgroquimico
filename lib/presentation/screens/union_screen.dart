import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common.dart';

/// «Sindicato» (rediseño, lámina «Sindicato»): punto de entrada a lo que se
/// comparte con el sindicato. Esqueleto creado por el orquestador para que la
/// pestaña tenga destino; su contenido y su diseño son de la sesión C
/// (`docs/rediseno/COORDINACION.md`). Sólo navega: cada pantalla conserva sus
/// guardas y sus reglas.
class UnionScreen extends StatelessWidget {
  const UnionScreen({super.key});

  static const entries =
      <({String key, String title, String subtitle, String path})>[
        (
          key: 'union-sync',
          title: 'Envíos al sindicato',
          subtitle: 'Sincronización y lo que falta enviar',
          path: '/sincronizacion',
        ),
        (
          key: 'union-joint-purchases',
          title: 'Compras conjuntas',
          subtitle: 'Convocatorias del sindicato y su participación',
          path: '/compras-conjuntas',
        ),
        (
          key: 'union-needs',
          title: 'Necesidad declarada',
          subtitle: 'Lo que solicita para la campaña',
          path: '/planificacion/necesidades',
        ),
        (
          key: 'union-consumption',
          title: 'Consumo',
          subtitle: 'Totales de lo que usted aplicó',
          path: '/sincronizacion/consumo',
        ),
        (
          key: 'union-links',
          title: 'Productos y campañas',
          subtitle: 'Sus equivalentes en el sindicato',
          path: '/sindicato/vinculos',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Sindicato',
      child: Column(
        children: [
          for (final entry in entries)
            Card(
              child: ListTile(
                key: Key(entry.key),
                title: Text(entry.title),
                subtitle: Text(entry.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(entry.path),
              ),
            ),
        ],
      ),
    );
  }
}
