import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/common.dart';

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

  /// Subdestinos que viven bajo la sección **Operaciones**.
  static const operationsSubRoutes = <String>{
    '/catalogos',
    '/planificacion',
    '/compras',
    '/aplicaciones',
    '/transferencias',
  };

  /// Rutas de detalle que no son destinos propios: heredan el destino desde el
  /// que se entra. `/chacos/:id` se alcanza desde Personas.
  static const _detailOwners = <String, String>{'/chacos': '/personas'};

  /// Rutas que ya tienen su propia acción primaria y donde el FAB global
  /// competiría con ella (UIBUG-047).
  ///
  /// En `/catalogos` convivían dos acciones visualmente primarias: el botón
  /// `Agregar «entidad»` de la cabecera, que crea en la sección abierta, y este
  /// FAB "Nuevo", que **no crea ninguna entrada de catálogo**: sólo lleva a
  /// Planificación, Compra, Aplicación, Pago y Transferencia. Retirarlo aquí no
  /// quita ninguna función —esos cinco destinos siguen en Operaciones y en la
  /// barra inferior— y deja una sola acción primaria por pantalla.
  static const _routesWithoutGlobalFab = <String>{'/catalogos'};

  /// Si esta ruta oculta el FAB global.
  bool get hidesGlobalFab => _routesWithoutGlobalFab.contains(location);

  int get selectedIndex {
    if (operationsSubRoutes.any(
      (path) => location == path || location.startsWith('$path/'),
    )) {
      return 1;
    }
    // Sin esto `/chacos/:id` no coincidía con nada y caía por defecto a 0, de
    // modo que la barra resaltaba "Inicio" estando en la bitácora (UIBUG-062).
    for (final entry in _detailOwners.entries) {
      if (location == entry.key || location.startsWith('${entry.key}/')) {
        return destinations.indexWhere((item) => item.path == entry.value);
      }
    }
    final exact = destinations.indexWhere((item) => item.path == location);
    if (exact >= 0) return exact;
    final nested = destinations.indexWhere(
      (item) => item.path != '/' && location.startsWith('${item.path}/'),
    );
    return nested < 0 ? 0 : nested;
  }

  /// A dónde lleva Atrás cuando no hay nada que desapilar.
  ///
  /// **UIBUG-004B — decisión de diseño.** Se adopta la guía de Material 3: desde
  /// un destino raíz **no inicial** Atrás vuelve al destino inicial, y sólo
  /// desde Inicio cede el gesto al sistema. Un toque accidental deja de cerrar
  /// la aplicación con trabajo a medias. Los subdestinos de Operaciones
  /// alcanzados sin apilar (por ejemplo desde el FAB) vuelven a Operaciones.
  String? get backFallback {
    if (location == '/') return null;
    if (operationsSubRoutes.any(
      (path) => location == path || location.startsWith('$path/'),
    )) {
      return '/operaciones';
    }
    return '/';
  }

  /// Alto del `FloatingActionButton.extended` más su margen.
  ///
  /// Se publica con [ContentInsets] para que el contenido desplazable termine
  /// por encima del FAB en TODAS las pantallas del shell, en vez de que cada una
  /// invente su relleno (UIBUG-008, UIBUG-009).
  static const double fabReserve = 88;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // El FAB desaparece con el teclado abierto (UIBUG-009) y en las rutas que
    // ya tienen su propia acción primaria (UIBUG-047).
    final showFab = !keyboardOpen && !hidesGlobalFab;
    final body = SafeArea(
      child: ContentInsets(
        // Sin FAB no hay nada que esquivar: reservar su alto dejaría un hueco
        // muerto al final de la página.
        bottomReserve: showFab ? fabReserve : 0,
        child: child,
      ),
    );
    if (wide) {
      return _withBackPolicy(
        context,
        Scaffold(
          floatingActionButton: showFab ? _newButton(context) : null,
          body: Row(
            children: [
              NavigationRail(
                extended: MediaQuery.sizeOf(context).width >= 1150,
                // Sin esto, entre 900 y 1150 px (el Pixel 8 apaisado da ~914)
                // los destinos se mostraban SOLO con iconos, sin etiqueta
                // (UIBUG-063).
                labelType: MediaQuery.sizeOf(context).width >= 1150
                    ? null
                    : NavigationRailLabelType.all,
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
        ),
      );
    }
    return _withBackPolicy(
      context,
      Scaffold(
        body: body,
        // Con el teclado abierto el FAB tapaba el campo activo (UIBUG-009).
        floatingActionButton: showFab ? _newButton(context) : null,
        // **Compromiso deliberado de accesibilidad.** Con cinco destinos en
        // 1080 px, "Operaciones" no cabe en una línea por encima del 100 % y se
        // partía en "Operacion / es" (UIBUG-017). Las etiquetas de la barra se
        // dejan en su cuerpo base: siguen siendo legibles, cada destino lleva
        // icono, y **el resto de la aplicación sí escala** hasta el 130 %.
        // La alternativa era acortar el nombre de una sección principal.
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1,
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                context.go(destinations[index].path),
            destinations: [
              for (final item in destinations)
                NavigationDestination(icon: Icon(item.icon), label: item.label),
            ],
          ),
        ),
      ),
    );
  }

  /// Aplica la política de Atrás de [backFallback] (UIBUG-004B).
  ///
  /// Sólo actúa cuando no hay nada que desapilar: si se llegó apilando, el
  /// `Navigator` desapila normalmente y este `PopScope` no interviene.
  Widget _withBackPolicy(BuildContext context, Widget scaffold) {
    final fallback = backFallback;
    return PopScope(
      canPop: fallback == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || fallback == null) return;
        context.go(fallback);
      },
      child: scaffold,
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
