import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/operation_mode.dart';
import '../../licenses/third_party_licenses.dart';
import '../../operation_mode_controller.dart';
import '../widgets/agro_ui.dart';
import '../widgets/rdm_c_page.dart';

/// «Ajustes y datos» (`/mas`, rediseño, lámina «Ajustes»): las funciones que
/// se usan de vez en cuando, en tres grupos (Datos, Seguridad, Uso). Se abre
/// desde el engranaje de Inicio. Aquí sólo se navega: cada pantalla conserva
/// sus guardas.
///
/// Respecto de la lámina: Reportes no se repite (está en la cabecera de
/// Actividad, decisión del 2026-11-05); «Vínculos» y «Compras conjuntas»
/// viven en la pestaña Sindicato; no se muestran estados («Verificado», «Sin
/// clave») que exigirían consultas nuevas al abrir la pantalla.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const _data = <_Entry>[
    _Entry(
      key: 'more-catalogs',
      title: 'Personas, chacos, productos y proveedores',
      path: '/catalogos',
    ),
    _Entry(key: 'more-campaigns', title: 'Campañas', path: '/campanas'),
    // RF-03: compras y aplicaciones con fecha de una campaña cerrada,
    // pendientes de que el titular las confirme o las rechace.
    _Entry(
      key: 'more-late',
      title: 'Operaciones tardías',
      detail: 'De campañas cerradas, en revisión',
      path: '/operaciones/tardias',
    ),
  ];

  static const _security = <_Entry>[
    _Entry(key: 'more-access', title: 'Acceso en línea', path: '/acceso'),
    _Entry(
      key: 'more-pin',
      title: 'PIN del titular',
      detail: 'Autoriza reversiones en este teléfono',
      path: '/titular/pin',
    ),
    _Entry(
      key: 'more-backups',
      title: 'Respaldos',
      detail: 'En la nube y en este teléfono',
      path: '/respaldo-remoto',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(operationModeProvider);
    final usage = <_Entry>[
      _Entry(
        key: 'more-mode',
        title: 'Modo de uso',
        detail: switch (mode) {
          OperationMode.personal => 'Ahora: inventario propio',
          OperationMode.shared => 'Ahora: inventario compartido',
          null => 'Inventario propio o compartido',
        },
        path: '/modo',
      ),
      // F09: lleva a los formularios con el panel de voz; no registra nada
      // por sí sola.
      const _Entry(key: 'more-voice', title: 'Registrar por voz', path: '/voz'),
    ];

    Widget group(String title, List<_Entry> entries, {Widget? extra}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RdmCOverline(title),
        AgroGroup(
          children: [
            for (final entry in entries)
              RdmCRow(
                key: Key(entry.key),
                title: entry.title,
                detail: entry.detail,
                // Se APILAN: Atrás vuelve aquí (UIBUG-004A).
                onTap: () => context.push(entry.path),
              ),
            ?extra,
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    return RdmCPage(
      title: 'Ajustes y datos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          group('Datos', _data),
          group('Seguridad', _security),
          group(
            'Uso',
            usage,
            // Avisos de licencia (F09): abre la página de licencias de
            // Flutter con los paquetes Dart y los componentes de la voz local
            // (lib/licenses).
            extra: RdmCRow(
              key: const Key('more-licenses'),
              title: 'Licencias',
              onTap: () => showAgroLicenses(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry({
    required this.key,
    required this.title,
    required this.path,
    this.detail,
  });
  final String key;
  final String title;
  final String? detail;
  final String path;
}
