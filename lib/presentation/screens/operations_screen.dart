import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';

/// Operaciones: lo que el agricultor registra y consulta a diario. Las
/// funciones menos frecuentes (datos, modo de uso, respaldos, operaciones
/// tardías, voz) viven en «Más» (`/mas`), con todos sus accesos y guardas
/// (ajuste tras el piloto X01, 2026-10-25).
///
/// Campañas y Reportes tienen acceso propio aquí (2026-11-05). La tarjeta de
/// Campañas dice cuál es la actual, que es la que reciben las operaciones
/// nuevas. Registrar se hace con el «+», que abre los formularios.
class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  late Future<Map<String, Object?>?> activeCampaign = _readActive();

  Future<Map<String, Object?>?> _readActive() =>
      ref.read(repositoryProvider).activeCampaign();

  /// Todas las tarjetas bajan un nivel dentro de la sección Operaciones, así
  /// que se APILAN: Atrás debe devolver aquí, no cerrar la aplicación
  /// (UIBUG-004A). Al volver se relee la campaña actual, que pudo cambiar.
  Future<void> _open(String path) async {
    await context.push(path);
    if (!mounted) return;
    final next = _readActive();
    setState(() {
      activeCampaign = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    // En inventario propio no hay transferencias entre responsables (#26).
    final mode = ref.watch(operationModeProvider);
    final personal = mode == OperationMode.personal;
    final actions =
        <({String title, Widget subtitle, String path, IconData icon})>[
          // Lleva al LISTADO, no directamente al formulario (UIBUG-002): era la
          // única puerta a `/compras`, y sin ella quedaban inalcanzables el
          // historial, los pagos a proveedor posteriores, el visor de factura y
          // la reversión de compras. El formulario se abre con el «+» o con
          // «Registrar compra» en Inicio.
          (
            title: 'Compras',
            subtitle: const Text('Facturas y pagos al proveedor'),
            path: '/compras',
            icon: Icons.shopping_bag_outlined,
          ),
          (
            title: 'Aplicaciones',
            subtitle: const Text('Lo aplicado en cada chaco y su costo'),
            path: '/aplicaciones',
            icon: Icons.agriculture_outlined,
          ),
          (
            title: 'Planificación',
            subtitle: const Text('Planes por chaco y necesidad al sindicato'),
            path: '/planificacion',
            icon: Icons.event_note_outlined,
          ),
          if (!personal)
            (
              title: 'Transferencias',
              subtitle: const Text('Productos entre personas'),
              path: '/transferencias',
              icon: Icons.swap_horiz,
            ),
          (
            title: 'Campañas',
            subtitle: FutureBuilder<Map<String, Object?>?>(
              key: const Key('operations-current-campaign'),
              future: activeCampaign,
              builder: (context, snapshot) => Text(switch (snapshot) {
                AsyncSnapshot(hasError: true) => 'Campaña actual',
                AsyncSnapshot(:final data?) => 'Actual: ${data['name']}',
                AsyncSnapshot(connectionState: ConnectionState.done) =>
                  'Sin campaña activa',
                _ => 'Campaña actual',
              }),
            ),
            path: '/campanas',
            icon: Icons.calendar_month_outlined,
          ),
          (
            title: 'Reportes',
            subtitle: const Text('Inventario, costos y cuentas en CSV o PDF'),
            path: '/reportes',
            icon: Icons.summarize_outlined,
          ),
          (
            title: 'Más',
            subtitle: const Text(
              'Datos, modo de uso, respaldos, operaciones tardías y voz',
            ),
            path: '/mas',
            icon: Icons.more_horiz,
          ),
        ];
    return PageFrame(
      title: 'Operaciones',
      subtitle: personal
          ? 'Inventario propio: registra sólo el titular y no hay '
                'transferencias.'
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 700
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(child: Icon(action.icon)),
                      title: Text(
                        action.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: action.subtitle,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(action.path),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
