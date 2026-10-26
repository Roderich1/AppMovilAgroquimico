import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';

/// Operaciones: lo que el agricultor registra y consulta a diario. Las
/// funciones menos frecuentes (reportes, datos, modo de uso, respaldos,
/// operaciones tardías, voz) viven en «Más» (`/mas`), con todos sus accesos y
/// guardas (ajuste tras el piloto X01, 2026-10-25).
class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // En inventario propio no hay transferencias entre responsables (#26).
    final mode = ref.watch(operationModeProvider);
    final personal = mode == OperationMode.personal;
    final actions =
        <({String title, String subtitle, String path, IconData icon})>[
          // Lleva al LISTADO, no directamente al formulario (UIBUG-002): era la
          // única puerta a `/compras`, y sin ella quedaban inalcanzables el
          // historial, los pagos a proveedor posteriores, el visor de factura y
          // la reversión de compras. Desde el listado se abre el formulario con
          // "Nueva compra", que además sí acusa recibo al volver (UIBUG-011).
          // El acceso directo al formulario está en Inicio («Registrar compra»).
          (
            title: 'Compras',
            subtitle: 'Lo comprado, sus facturas y los pagos al proveedor',
            path: '/compras',
            icon: Icons.shopping_bag_outlined,
          ),
          (
            title: 'Aplicaciones',
            subtitle: 'Lo aplicado en cada chaco y cuánto costó',
            path: '/aplicaciones',
            icon: Icons.agriculture_outlined,
          ),
          (
            title: 'Planificación',
            subtitle:
                'Lo que se va a aplicar por chaco y la necesidad declarada '
                'al sindicato',
            path: '/planificacion',
            icon: Icons.event_note_outlined,
          ),
          if (!personal)
            (
              title: 'Transferencias',
              subtitle: 'Pasar productos de una persona a otra',
              path: '/transferencias',
              icon: Icons.swap_horiz,
            ),
          (
            title: 'Más',
            subtitle:
                'Reportes, datos, modo de uso, respaldos, operaciones tardías '
                'y voz',
            path: '/mas',
            icon: Icons.more_horiz,
          ),
        ];
    return PageFrame(
      title: 'Operaciones',
      subtitle: personal
          ? 'Lo del trabajo diario. Inventario propio: registra sólo '
                'el titular y no hay transferencias.'
          : 'Lo del trabajo diario.',
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
                      subtitle: Text(action.subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      // Todas las tarjetas bajan un nivel dentro de la
                      // sección Operaciones, así que se APILAN: Atrás debe
                      // devolver aquí, no cerrar la aplicación (UIBUG-004A).
                      onTap: () => context.push(action.path),
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
