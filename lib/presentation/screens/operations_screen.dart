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
            title: 'Planificar aplicación',
            subtitle: 'Calcular necesidades por chaco',
            path: '/planificacion',
            icon: Icons.event_note_outlined,
            isForm: false,
          ),
          (
            title: 'Registrar compra',
            subtitle: 'Factura, productos y asignaciones',
            path: '/compras/nueva',
            icon: Icons.shopping_bag_outlined,
            isForm: true,
          ),
          (
            title: 'Registrar aplicación',
            subtitle: 'Consumo real con FIFO',
            path: '/aplicaciones',
            icon: Icons.agriculture_outlined,
            isForm: false,
          ),
          (
            title: 'Transferir inventario',
            subtitle: 'Mover stock entre personas',
            path: '/transferencias',
            icon: Icons.swap_horiz,
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
                      onTap: () => action.isForm
                          ? context.push(action.path)
                          : context.go(action.path),
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
