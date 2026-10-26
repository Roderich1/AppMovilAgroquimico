import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show UncontrolledProviderScope;
import 'package:go_router/go_router.dart';

import 'widgets/common.dart';
import 'widgets/sync_status_banner.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.transfersEnabled = true,
  });
  final String location;
  final Widget child;

  /// Falso en inventario propio: no se ofrecen transferencias entre
  /// responsables (RF-06, RF-11; #26). El router además saca de sus rutas.
  final bool transfersEnabled;

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
    '/reportes',
    '/voz',
    // «Más»: las funciones poco frecuentes, agrupadas (piloto X01).
    '/mas',
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
  ///
  /// En las pantallas de voz el micrófono ya es la acción primaria y el FAB
  /// taparía «Registrar».
  ///
  /// En Inicio (piloto X01, 2026-10-25) los cuatro accesos principales
  /// —Registrar compra, Registrar aplicación, Ver cuánto queda y Enviar al
  /// sindicato— son la acción primaria; un «Nuevo» flotante competiría con
  /// ellos. En el resto de secciones el FAB sigue.
  static const _routesWithoutGlobalFab = <String>{
    '/',
    '/catalogos',
    '/voz',
    '/compras/voz',
    '/planificacion/voz',
    '/aplicaciones/voz',
  };

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
        // Indicador de sincronización (RF-18). Sólo con estado de la app
        // disponible; sin nada pendiente deja el contenido intacto.
        child:
            context
                    .findAncestorWidgetOfExactType<
                      UncontrolledProviderScope
                    >() ==
                null
            ? child
            : SyncAwareBody(child: child),
      ),
    );
    if (wide) {
      return _withBackPolicy(
        context,
        Scaffold(
          floatingActionButton: showFab ? _newButton(context) : null,
          body: Row(
            children: [
              // **UIBUG-068 — el rail tiene que poder desplazarse.**
              // `NavigationRail` reparte su alto entre los destinos y no se
              // desplaza por su cuenta. En horizontal el alto útil son 1080 px,
              // y con la fuente al 130 % los cinco destinos con etiqueta ya no
              // caben: `RenderFlex overflowed by 90 pixels` y "Personas" y
              // "Cuentas" quedaban inalcanzables.
              //
              // Se resuelve dejándolo desplazar en vez de acotar la escala del
              // texto: en horizontal sobra sitio para desplazarse, así que las
              // etiquetas pueden seguir creciendo. (La barra inferior, con solo
              // ~90 px de alto, sí mantiene su compromiso de escala.)
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        extended: MediaQuery.sizeOf(context).width >= 1150,
                        // Sin esto, entre 900 y 1150 px (el Pixel 8 apaisado
                        // da ~914) los destinos se mostraban SOLO con iconos,
                        // sin etiqueta (UIBUG-063).
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
                    ),
                  ),
                ),
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
        // **Etiquetas de la barra ajustadas al ancho de su destino.** Con
        // cinco destinos, «Operaciones» no cabía en una línea y se partía en
        // «Operacion / es» (UIBUG-017, POCO por encima del 100 %) y en
        // «Operacione / s» (#129, HONOR de 360 dp incluso al 100 %). Antes se
        // fijaba la escala de la barra al 100 %, lo que no bastaba en 360 dp.
        // Ahora las etiquetas siguen la escala del sistema (hasta el 130 %
        // que `NavigationBar` admite) y sólo se reducen lo justo para que la
        // más larga quepa en una línea en el ancho real de su destino, medida
        // con la fuente del dispositivo. No se acorta el nombre de ninguna
        // sección y cada destino conserva su icono.
        bottomNavigationBar: LayoutBuilder(
          builder: (context, constraints) => NavigationBar(
            labelTextStyle: _fittedLabelStyle(context, constraints.maxWidth),
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

  /// Margen a cada lado de la etiqueta dentro de su destino.
  static const double _labelMargin = 4;

  /// Estilo de las etiquetas de la barra inferior para un ancho total [width]:
  /// el `labelMedium` del tema, reducido sólo si la etiqueta más larga no cabe
  /// en una línea en `width / destinos` (#129). Los colores por estado son los
  /// de Material 3.
  static WidgetStateProperty<TextStyle?> _fittedLabelStyle(
    BuildContext context,
    double width,
  ) {
    final theme = Theme.of(context);
    final base = theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12);
    // `NavigationBar` limita por sí misma la escala de sus etiquetas a 1,3.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final slot = width / destinations.length - 2 * _labelMargin;
    final widest = destinations
        .map(
          (item) => measureText(context, item.label, base, textScaler: scaler),
        )
        .fold(0.0, math.max);
    final ratio = widest > slot && slot > 0 ? slot / widest : 1.0;
    final fitted = ratio == 1.0
        ? base
        : base.copyWith(
            fontSize: (base.fontSize ?? 12) * ratio,
            letterSpacing: (base.letterSpacing ?? 0) * ratio,
          );
    final colors = theme.colorScheme;
    return WidgetStateProperty.resolveWith(
      (states) => fitted.apply(
        color: states.contains(WidgetState.disabled)
            ? colors.onSurfaceVariant.withValues(alpha: 0.38)
            : states.contains(WidgetState.selected)
            ? colors.onSurface
            : colors.onSurfaceVariant,
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
            for (final action in [
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
              if (transfersEnabled)
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
