import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common.dart';

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // `isForm` marca las rutas declaradas FUERA del ShellRoute. Deben apilarse
    // con `push`; navegar a ellas con `go` reemplaza la pila y deja el botón
    // atrás del formulario sin ninguna página a la que volver.
    const actions =
        <
          ({
            String title,
            String subtitle,
            String path,
            IconData icon,
            bool isForm,
          })
        >[
          (
            title: 'Planificación',
            subtitle: 'Necesidades por chaco y planes guardados',
            path: '/planificacion',
            icon: Icons.event_note_outlined,
            isForm: false,
          ),
          // Lleva al LISTADO, no directamente al formulario (UIBUG-002): era la
          // única puerta a `/compras`, y sin ella quedaban inalcanzables el
          // historial, los pagos a proveedor posteriores, el visor de factura y
          // la reversión de compras. Desde el listado se abre el formulario con
          // "Nueva compra", que además sí acusa recibo al volver (UIBUG-011).
          // Queda igual que las tarjetas de aplicaciones y transferencias.
          (
            title: 'Compras',
            subtitle: 'Historial, facturas y pagos a proveedor',
            path: '/compras',
            icon: Icons.shopping_bag_outlined,
            isForm: false,
          ),
          (
            title: 'Aplicaciones',
            subtitle: 'Historial y registro de consumo real con FIFO',
            path: '/aplicaciones',
            icon: Icons.agriculture_outlined,
            isForm: false,
          ),
          (
            title: 'Transferencias',
            subtitle: 'Historial y movimiento de stock entre personas',
            path: '/transferencias',
            icon: Icons.swap_horiz,
            isForm: false,
          ),
          (
            title: 'Reportes',
            subtitle: 'Exportar inventario, costos y cuentas a CSV o PDF',
            path: '/reportes',
            icon: Icons.summarize_outlined,
            isForm: false,
          ),
          (
            title: 'Administrar datos',
            subtitle: 'Campañas, chacos, productos y proveedores',
            path: '/catalogos',
            icon: Icons.settings_outlined,
            isForm: false,
          ),
        ];
    return PageFrame(
      title: 'Operaciones',
      subtitle: 'Acciones del trabajo diario.',
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
