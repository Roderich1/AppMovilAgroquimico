import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const destinations = <({String path, IconData icon, String label})>[
    (path: '/', icon: Icons.space_dashboard_outlined, label: 'Inicio'),
    (path: '/operaciones', icon: Icons.task_alt_outlined, label: 'Operaciones'),
    (
      path: '/inventario',
      icon: Icons.inventory_2_outlined,
      label: 'Inventario',
    ),
    (path: '/personas', icon: Icons.people_alt_outlined, label: 'Personas'),
    (
      path: '/liquidacion',
      icon: Icons.account_balance_wallet_outlined,
      label: 'Cuentas',
    ),
  ];

  int get selectedIndex {
    if ({
      '/catalogos',
      '/planificacion',
      '/compras',
      '/aplicaciones',
      '/transferencias',
    }.any((path) => location == path || location.startsWith('$path/'))) {
      return 1;
    }
    final exact = destinations.indexWhere((item) => item.path == location);
    if (exact >= 0) return exact;
    final nested = destinations.indexWhere(
      (item) => item.path != '/' && location.startsWith('${item.path}/'),
    );
    return nested < 0 ? 0 : nested;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = SafeArea(child: child);
    if (wide) {
      return Scaffold(
        floatingActionButton: _newButton(context),
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1150,
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  context.go(destinations[index].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircleAvatar(
                  radius: 24,
                  child: Icon(Icons.eco_outlined),
                ),
              ),
              destinations: [
                for (final item in destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      floatingActionButton: _newButton(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(destinations[index].path),
        destinations: [
          for (final item in destinations)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }

  Widget _newButton(BuildContext context) => FloatingActionButton.extended(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text(
                'Nuevo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            // `isForm` distingue las rutas declaradas FUERA del ShellRoute
            // (formularios a pantalla completa). Esas deben apilarse con
            // `push`: con `go` se reemplaza toda la pila y el botón atrás del
            // formulario deja la aplicación sin ninguna página que mostrar.
            for (final action in const [
              (
                label: 'Planificación',
                icon: Icons.event_note_outlined,
                path: '/planificacion',
                isForm: false,
              ),
              (
                label: 'Compra',
                icon: Icons.shopping_bag_outlined,
                path: '/compras/nueva',
                isForm: true,
              ),
              (
                label: 'Aplicación',
                icon: Icons.agriculture_outlined,
                path: '/aplicaciones',
                isForm: false,
              ),
              (
                label: 'Pago',
                icon: Icons.payments_outlined,
                path: '/liquidacion',
                isForm: false,
              ),
              (
                label: 'Transferencia',
                icon: Icons.swap_horiz,
                path: '/transferencias',
                isForm: false,
              ),
            ])
              ListTile(
                leading: Icon(action.icon),
                title: Text(action.label),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    if (action.isForm) {
                      context.push(action.path);
                    } else {
                      context.go(action.path);
                    }
                  });
                },
              ),
          ],
        ),
      ),
    ),
    icon: const Icon(Icons.add),
    label: const Text('Nuevo'),
  );
}
