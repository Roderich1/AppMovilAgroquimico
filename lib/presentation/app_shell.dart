import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show UncontrolledProviderScope;
import 'package:go_router/go_router.dart';

import 'widgets/common.dart';
import 'widgets/register_sheet.dart';
import 'widgets/sync_status_banner.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.transfersEnabled = true,
    this.personalMode = false,
  });
  final String location;
  final Widget child;

  /// Falso en inventario propio: no se ofrecen transferencias entre
  /// responsables (RF-06, RF-11; #26). El router además saca de sus rutas.
  final bool transfersEnabled;

  /// Modo individual (`OperationMode.personal`): la barra cambia «Personas»
  /// por «Chacos» (láminas I-01…I-53, 2026-11-13). Sólo presentación: las
  /// reglas siguen en el repositorio y en `operationModeRedirect`.
  final bool personalMode;

  /// Barra del rediseño (2026-11-12, láminas «Inicio», «Actividad»,
  /// «Almacén», «Personas» y «Sindicato»). Las rutas de siempre se conservan:
  /// «Actividad» es `/operaciones` y «Almacén» es `/inventario`. «Cuentas»
  /// (`/liquidacion`) deja de ser pestaña y vive bajo Personas; «Más» y los
  /// ajustes viven bajo Inicio. Ningún acceso se pierde: sólo cambia qué
  /// pestaña queda resaltada y a dónde vuelve Atrás.
  static const destinations =
      <({String path, IconData icon, IconData selectedIcon, String label})>[
        (
          path: '/',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Inicio',
        ),
        (
          path: '/operaciones',
          icon: Icons.notes_outlined,
          selectedIcon: Icons.notes,
          label: 'Actividad',
        ),
        (
          path: '/inventario',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          label: 'Almacén',
        ),
        (
          path: '/personas',
          icon: Icons.people_alt_outlined,
          selectedIcon: Icons.people_alt,
          label: 'Personas',
        ),
        (
          path: '/sindicato',
          icon: Icons.hub_outlined,
          selectedIcon: Icons.hub,
          label: 'Sindicato',
        ),
      ];

  /// Barra del modo individual (lámina I-01): Inicio · Actividad · Almacén ·
  /// Chacos · Sindicato. «Chacos» ocupa el lugar de «Personas».
  static const personalDestinations =
      <({String path, IconData icon, IconData selectedIcon, String label})>[
        (
          path: '/',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Inicio',
        ),
        (
          path: '/operaciones',
          icon: Icons.notes_outlined,
          selectedIcon: Icons.notes,
          label: 'Actividad',
        ),
        (
          path: '/inventario',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          label: 'Almacén',
        ),
        (
          path: '/chacos',
          icon: Icons.grid_on_outlined,
          selectedIcon: Icons.grid_on,
          label: 'Chacos',
        ),
        (
          path: '/sindicato',
          icon: Icons.hub_outlined,
          selectedIcon: Icons.hub,
          label: 'Sindicato',
        ),
      ];

  static List<
    ({String path, IconData icon, IconData selectedIcon, String label})
  >
  destinationsFor({required bool personal}) =>
      personal ? personalDestinations : destinations;

  List<({String path, IconData icon, IconData selectedIcon, String label})>
  get _items => destinationsFor(personal: personalMode);

  /// Rutas que cuelgan de cada pestaña (además de la propia raíz y sus
  /// `raíz/…`). El orden importa: `/planificacion/necesidades` es del
  /// Sindicato aunque `/planificacion` sea de Actividad.
  static const sectionRoutes = <String, List<String>>{
    '/sindicato': [
      '/sincronizacion',
      '/compras-conjuntas',
      '/planificacion/necesidades',
    ],
    '/inventario': [],
    '/personas': ['/chacos', '/liquidacion'],
    '/operaciones': [
      '/planificacion',
      '/compras',
      '/aplicaciones',
      '/transferencias',
      '/reportes',
      '/voz',
    ],
  };

  /// Subdestinos de Actividad (antes «Operaciones»). Se conserva el nombre
  /// público para quien lo consulta.
  static Set<String> get operationsSubRoutes =>
      sectionRoutes['/operaciones']!.toSet();

  static bool _under(String location, String path) =>
      location == path || location.startsWith('$path/');

  /// Raíz de la pestaña a la que pertenece [location]. Lo que no cuelga de
  /// ninguna (Más, Catálogos, Campañas, respaldos…) es de Inicio.
  static String sectionOf(String location, {bool personal = false}) {
    // En modo individual el detalle de un chaco y sus costos cuelgan de
    // «Chacos», que sustituye a «Personas» en la barra.
    // Lo que en el modo con varias personas cuelga de «Personas» (consulta
    // histórica de una persona, Cuentas) queda bajo «Chacos»: la barra no
    // tiene «Personas» y siempre debe quedar una pestaña resaltada.
    if (personal && _under(location, '/chacos')) return '/chacos';
    for (final entry in sectionRoutes.entries) {
      if (_under(location, entry.key) ||
          entry.value.any((path) => _under(location, path))) {
        return personal && entry.key == '/personas' ? '/chacos' : entry.key;
      }
    }
    return '/';
  }

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
  ///
  /// «Avisos de inventario» (F04-AV, 2026-11-01) es una consulta que no
  /// inicia operaciones (#170). En el emulador el FAB tapaba el aviso que
  /// pasaba por debajo al desplazarse; sin él, ningún aviso queda tapado.
  ///
  /// «Campañas» (2026-11-05) tiene su propia acción primaria, «Agregar
  /// campaña», igual que Catálogos.
  ///
  /// En «Sincronización» (POCO, 2026-11-03) el FAB tapaba «Reintentar con
  /// esta versión» y el toque abría el menú de creación en vez de reanudar
  /// los envíos. La pantalla ya tiene su acción, «Enviar pendientes», y no
  /// inicia operaciones.
  static const _routesWithoutGlobalFab = <String>{
    '/',
    '/catalogos',
    '/campanas',
    '/voz',
    '/compras/voz',
    '/planificacion/voz',
    '/aplicaciones/voz',
    '/inventario/avisos',
    '/inventario/estimacion',
    '/sincronizacion',
    // Sindicato: su acción es «Enviar»; no inicia operaciones. Necesidad,
    // Consumo y Vínculos tienen su propia acción («Declarar», «Publicar»,
    // «Actualizar») y el botón les tapaba el final de la lista (sesión C).
    '/sindicato',
    '/planificacion/necesidades',
    '/sincronizacion/consumo',
    '/sindicato/vinculos',
    // Las listas de Aplicaciones y Planificación tienen su propio botón de
    // registro: dos «Registrar» iguales competirían (sesión A).
    '/aplicaciones',
    '/planificacion',
    // La lista de Compras tiene «Nueva compra» (sesión B, entrega 3);
    // Transferencias, «Nueva»; Personas y Cuentas, «Registrar pago» en cada
    // tarjeta (láminas sin flotante).
    '/compras',
    '/transferencias',
    '/personas',
    '/liquidacion',
    // Ajustes y Respaldos son consultas y ajustes: no inician operaciones
    // (láminas «Ajustes» y «Respaldos», sin botón flotante).
    '/mas',
    '/respaldo-remoto',
    // Reportes tiene su propia acción, «Exportar …» (lámina sin flotante).
    '/reportes',
  };

  /// Si esta ruta oculta el FAB global. El detalle de compra es de sólo
  /// lectura (A2, 2026-10-30): un botón de creación no tiene sentido ahí.
  bool get hidesGlobalFab =>
      _routesWithoutGlobalFab.contains(location) ||
      location.startsWith('/compras/detalle/') ||
      // Detalle de un producto (lámina «Producto», sin flotante): el botón
      // tapaba sus movimientos.
      location.startsWith('/inventario/') ||
      // Convocatorias y su detalle (láminas 6.1–6.3, sin flotante): en el
      // emulador tapaba «Continuar» de la hoja de cantidades (2026-11-12).
      location == '/compras-conjuntas' ||
      location.startsWith('/compras-conjuntas/') ||
      // Chacos del modo individual (I-40 a I-43, sin flotante): la lista
      // tiene «Agregar chaco» y el detalle sus propias acciones.
      // En el modo con varias personas la bitácora de un chaco no cambia.
      (personalMode &&
          (location == '/chacos' || location.startsWith('/chacos/')));

  int get selectedIndex => _items.indexWhere(
    (item) => item.path == sectionOf(location, personal: personalMode),
  );

  /// A dónde lleva Atrás cuando no hay nada que desapilar.
  ///
  /// **UIBUG-004B — decisión de diseño.** Se adopta la guía de Material 3: desde
  /// un destino raíz **no inicial** Atrás vuelve al destino inicial, y sólo
  /// desde Inicio cede el gesto al sistema. Un toque accidental deja de cerrar
  /// la aplicación con trabajo a medias. Los subdestinos de Operaciones
  /// alcanzados sin apilar (por ejemplo desde el FAB) vuelven a Operaciones.
  String? get backFallback {
    if (location == '/') return null;
    final section = sectionOf(location, personal: personalMode);
    // Desde una raíz que no es Inicio, a Inicio; desde un subdestino, a la
    // raíz de su pestaña.
    return location == section ? '/' : section;
  }

  /// Alto del `FloatingActionButton` más su margen.
  ///
  /// El «+» (2026-11-03) mide 56×56, el mismo alto que el botón extendido
  /// «Nuevo» al que sustituye: la reserva vertical no cambia. Es más
  /// estrecho, así que tapa menos ancho del contenido.
  ///
  /// Desde el 2026-11-12 es el alto de la franja que el shell deja bajo la
  /// vista desplazable cuando hay botón (el contenido nunca pasa por detrás
  /// de él). Antes se publicaba con [ContentInsets] como relleno al final de
  /// cada página (UIBUG-008, UIBUG-009), que sólo protegía la última fila al
  /// terminar de desplazar.
  static const double fabReserve = 88;

  @override
  State<AppShell> createState() => _AppShellState();

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
    // Rediseño: 14 px y seminegrita (la lámina usa 15; 14 cabe en 360 dp).
    final base = (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    // `NavigationBar` limita por sí misma la escala de sus etiquetas a 1,3.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final slot = width / destinations.length - 2 * _labelMargin;
    // Las dos barras tienen cinco destinos; se mide la etiqueta más larga de
    // ambas para que la letra no cambie al cambiar de modo.
    final widest = [...destinations, ...personalDestinations]
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
        fontWeightDelta: states.contains(WidgetState.selected) ? 1 : 0,
      ),
    );
  }
}

class _AppShellState extends State<AppShell> {
  /// «+ Registrar» se recoge a «+» mientras se desplaza hacia abajo (no tapa
  /// las cifras de la derecha) y vuelve a extenderse al subir o al cambiar
  /// de pantalla (sesión B, 2026-11-12).
  bool _fabExtended = true;

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _fabExtended = true;
  }

  bool _onScroll(UserScrollNotification n) {
    final extended = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabExtended,
    };
    if (n.metrics.axis == Axis.vertical && extended != _fabExtended) {
      setState(() => _fabExtended = extended);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // El FAB desaparece con el teclado abierto (UIBUG-009) y en las rutas que
    // ya tienen su propia acción primaria (UIBUG-047).
    final showFab = !keyboardOpen && !widget.hidesGlobalFab;
    // **La lista termina por encima de «+ Registrar» (2026-11-12, revisión
    // del autor).** Antes el contenido pasaba por detrás del botón y sólo se
    // reservaba su alto al FINAL de la página (`ContentInsets`): con la lista
    // arriba, el botón tapaba la existencia de la tarjeta que quedaba debajo
    // (Almacén, Actividad). Ahora la zona del botón —su margen de 16, sus 56
    // de alto y 16 de aire— queda fuera de la vista desplazable, dentro del
    // área segura y por encima de la barra inferior: ninguna fila pasa por
    // detrás, en ninguna posición del desplazamiento. El alto del botón no
    // crece con la letra (Material fija 56), así que la franja tampoco.
    // Las páginas ya no necesitan reservarlo al final (`bottomReserve: 0`).
    final content =
        context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() ==
            null
        ? widget.child
        // Indicador de sincronización (RF-18). Sólo con estado de la app
        // disponible; sin nada pendiente deja el contenido intacto.
        : SyncAwareBody(child: widget.child);
    final body = NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: ContentInsets(bottomReserve: 0, child: content)),
            if (showFab)
              const SizedBox(
                key: Key('shell-registrar-zona'),
                height: AppShell.fabReserve,
              ),
          ],
        ),
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
                        selectedIndex: widget.selectedIndex,
                        onDestinationSelected: (index) =>
                            context.go(widget._items[index].path),
                        leading: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: CircleAvatar(
                            radius: 24,
                            child: Icon(Icons.eco_outlined),
                          ),
                        ),
                        destinations: [
                          for (final item in widget._items)
                            NavigationRailDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.selectedIcon),
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
            labelTextStyle: AppShell._fittedLabelStyle(
              context,
              constraints.maxWidth,
            ),
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: (index) =>
                context.go(widget._items[index].path),
            destinations: [
              for (final item in widget._items)
                NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Aplica la política de Atrás de [widget.backFallback] (UIBUG-004B).
  ///
  /// Sólo actúa cuando no hay nada que desapilar: si se llegó apilando, el
  /// `Navigator` desapila normalmente y este `PopScope` no interviene.
  Widget _withBackPolicy(BuildContext context, Widget scaffold) {
    final fallback = widget.backFallback;
    return PopScope(
      canPop: fallback == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || fallback == null) return;
        context.go(fallback);
      },
      child: scaffold,
    );
  }

  /// Botón flotante «Registrar» (rediseño, lámina «Actividad»): lima, con
  /// el icono «+» y el nombre visible, que es también su nombre accesible.
  /// Abre la hoja «Registrar» (lámina «Registrar»).
  ///
  /// Sin `Hero`: ningún formulario tiene un «+» al que animarlo, y al
  /// ocultarse y volver con el teclado durante una transición coincidían dos
  /// con la etiqueta por defecto (aserción de depuración, 2026-11-05).
  Widget _newButton(BuildContext context) => Semantics(
    // Recogido sigue llamándose «Registrar».
    label: _fabExtended ? null : 'Registrar',
    child: FloatingActionButton.extended(
      key: const Key('shell-registrar'),
      heroTag: null,
      isExtended: _fabExtended,
      extendedIconLabelSpacing: _fabExtended ? 8 : 0,
      extendedPadding: _fabExtended
          ? null
          : const EdgeInsets.symmetric(horizontal: 16),
      onPressed: () => showRegisterSheet(
        context,
        transfersEnabled: widget.transfersEnabled,
        personalMode: widget.personalMode,
      ),
      icon: const Icon(Icons.add),
      label: const Text('Registrar'),
    ),
  );
}
