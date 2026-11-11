import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/campaign_actions.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import '../widgets/label_photo_sheet.dart';

class CatalogsScreen extends ConsumerStatefulWidget {
  const CatalogsScreen({super.key});
  @override
  ConsumerState<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends ConsumerState<CatalogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabs;
  late Future<List<List<Map<String, Object?>>>> data;
  String query = '';

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 5, vsync: this)..addListener(_onTabChanged);
    data = _load();
  }

  @override
  void dispose() {
    tabs.removeListener(_onTabChanged);
    tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<List<List<Map<String, Object?>>>> _load() async {
    final repo = ref.read(repositoryProvider);
    return Future.wait([
      repo.people(),
      repo.farms(),
      repo.products(),
      repo.suppliers(),
      repo.campaigns(),
    ]);
  }

  void _refresh() {
    final next = _load();
    setState(() {
      data = next;
    });
  }

  Future<void> _edit(Map<String, Object?> row) async {
    final value = await showDialog<String?>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Editar nombre',
        label: 'Nombre',
        initial: row['name']! as String,
      ),
    );
    if (value == null) return;
    const tables = ['persons', 'farms', 'products', 'suppliers', 'campaigns'];
    try {
      await ref
          .read(repositoryProvider)
          .renameCatalog(tables[tabs.index], row['id']! as int, value);
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Archivar oculta el registro de listas y formularios y conserva su
  /// historial; no es un borrado y `archiveCatalog` no cambia. Como no se
  /// deshace desde la aplicación, pide confirmación informada y avisa el
  /// resultado (A-05).
  Future<void> _archive(Map<String, Object?> row) async {
    const tables = ['persons', 'farms', 'products', 'suppliers', 'campaigns'];
    final name = row['name'].toString();
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Archivar $name?',
      detail:
          'Dejará de aparecer en las listas y formularios; su historial se '
          'conserva.',
      confirmLabel: 'Archivar',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .archiveCatalog(tables[tabs.index], row['id']! as int);
      if (mounted) showSuccess(context, 'Se archivó $name.');
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// «Foto de la etiqueta» (E1 §5.1). La hoja guarda por su cuenta; al
  /// cerrarla se relee la lista.
  Future<void> _labelPhoto(Map<String, Object?> row) async {
    await showLabelPhotoSheet(
      context,
      productId: row['id']! as int,
      productName: row['name'].toString(),
    );
    if (mounted) _refresh();
  }

  Future<void> _campaignAction(String action, Map<String, Object?> row) async {
    final repo = ref.read(repositoryProvider);
    try {
      if (action == 'activate') {
        await activateCampaignFlow(context, repo, row);
      } else if (action == 'close') {
        await closeCampaignFlow(context, repo, row);
      } else {
        await _edit(row);
        return;
      }
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _add() async {
    final repo = ref.read(repositoryProvider);
    try {
      switch (tabs.index) {
        case 0:
          // En propio no se agregan responsables (#26); el botón no se
          // muestra, pero la regla no depende de él.
          if (_personal) return;
          final result = await showDialog<(String, PersonRole)?>(
            context: context,
            builder: (_) => const PersonDialog(),
          );
          if (result != null)
            await repo.addPerson(name: result.$1, role: result.$2);
        // Chaco, producto y proveedor: las mismas altas que ofrecen los
        // selectores de los formularios (catalog_dialogs.dart). En modo propio
        // los chacos son del titular, que se aplica sin elegirlo (#26).
        case 1:
          await createFarmFromDialog(context, repo);
        case 2:
          await createProductFromDialog(context, repo);
        case 3:
          await createSupplierFromDialog(context, repo);
        case 4:
          await addCampaignFlow(context, repo);
      }
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Qué crea el botón primario en la sección abierta (UIBUG-047).
  ///
  /// "Agregar" a secas no decía si iba a crear una persona o una campaña, lo
  /// que empataba en ambigüedad con el FAB global "Nuevo".
  String get _addLabel => switch (tabs.index) {
    0 => 'Agregar persona',
    1 => 'Agregar chaco',
    2 => 'Agregar producto',
    3 => 'Agregar proveedor',
    _ => 'Agregar campaña',
  };

  bool get _personal =>
      ref.read(operationModeProvider) == OperationMode.personal;

  @override
  Widget build(BuildContext context) {
    final personal = ref.watch(operationModeProvider) == OperationMode.personal;
    return _page(context, personal);
  }

  Widget _page(BuildContext context, bool personal) => PageFrame(
    title: 'Catálogos',
    subtitle: 'Personas, chacos, insumos y campañas.',
    // **UIBUG-047 — jerarquía de acciones en `/catalogos`.** La pantalla
    // presentaba dos acciones visualmente primarias: este botón y el FAB
    // global "Nuevo". Se conserva el botón específico, que dice **qué** va a
    // crear en la sección abierta, y `AppShell` retira el FAB en esta ruta
    // (ver `AppShell.hidesGlobalFab`). No se pierde ninguna función: el FAB
    // sólo ofrece atajos a Planificación, Compra, Aplicación, Pago y
    // Transferencia, todos alcanzables desde Operaciones y la barra inferior,
    // y ninguno crea entradas de catálogo.
    // En propio no se agregan responsables: la sección Personas queda para
    // consultar y corregir nombres (#26).
    action: personal && tabs.index == 0
        ? null
        : FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(_addLabel),
          ),
    child: Column(
      children: [
        TextField(
          onChanged: (value) => setState(() {
            query = value.trim().toLowerCase();
          }),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar en esta sección',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in const [
                'Personas',
                'Chacos',
                'Productos',
                'Proveedores',
                'Campañas',
              ].indexed)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: tabs.index == entry.$1,
                  onSelected: (_) => tabs.animateTo(entry.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (personal && tabs.index == 0) ...[
          const Card(
            key: Key('catalogs-personal-persons-notice'),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Inventario propio: registra sólo el titular. Para agregar '
                'responsables, cambie a inventario compartido en Modo de uso. '
                'Las personas ya registradas y su historial se conservan.',
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Sin altura fija: la lista participa del scroll de la página, así
        // que su última fila siempre es alcanzable (UIBUG-018).
        Builder(
          builder: (context) => FutureBuilder(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return EmptyState(
                  icon: Icons.error_outline,
                  message: friendlyError(snapshot.error!),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data![tabs.index].where((row) {
                if (query.isEmpty) return true;
                // La ruta y la huella de la foto de la etiqueta no son
                // texto que el agricultor busque.
                return row.entries.any(
                  (entry) =>
                      !entry.key.startsWith('photo_') &&
                      matchesSearch(entry.value.toString(), query),
                );
              }).toList();
              if (rows.isEmpty)
                return const EmptyState(
                  icon: Icons.add_circle_outline,
                  message: 'No hay registros. Usa Agregar para comenzar.',
                );
              return Card(
                child: ListView.separated(
                  // La lista ya no tiene altura propia: crece con su contenido
                  // y se desplaza con la página (UIBUG-018).
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    final (title, subtitle, icon) = switch (tabs.index) {
                      0 => (
                        row['name'].toString(),
                        '${_roleLabel(row['role']! as String)} · ${_policyLabel(row['settlement_policy']! as String)}',
                        Icons.person_outline,
                      ),
                      1 => (
                        row['name'].toString(),
                        '${row['owner_name']} · ${formatHectares(row['area_m2'] as int)}',
                        Icons.landscape_outlined,
                      ),
                      2 => (
                        row['name'].toString(),
                        '${row['active_ingredient'] ?? 'Sin ingrediente'} · ${row['unit']}'
                            '${row['photo_path'] == null ? '' : ' · Con foto de la etiqueta'}',
                        Icons.science_outlined,
                      ),
                      3 => (
                        row['name'].toString(),
                        row['phone']?.toString() ?? 'Proveedor',
                        Icons.storefront_outlined,
                      ),
                      _ => (
                        row['name'].toString(),
                        campaignSubtitle(row, snapshot.data![tabs.index]),
                        Icons.calendar_month_outlined,
                      ),
                    };
                    return ListTile(
                      leading: CircleAvatar(child: Icon(icon)),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => tabs.index == 4
                            ? _campaignAction(value, row)
                            : value == 'edit'
                            ? _edit(row)
                            : value == 'photo'
                            ? _labelPhoto(row)
                            : _archive(row),
                        itemBuilder: (_) => tabs.index == 4
                            ? [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                // **UIBUG-059 — una campaña cerrada es
                                // terminal.** Antes bastaba con no estar
                                // `ACTIVE` para ofrecer "Activar", así que una
                                // campaña cerrada —un periodo contable ya
                                // terminado— podía reabrirse con dos toques.
                                // Sólo se puede activar lo que aún no ha
                                // vivido: `PLANNED`. El repositorio rechaza
                                // además la reactivación, por si se llega por
                                // otro camino.
                                if (row['status'] == 'PLANNED')
                                  const PopupMenuItem(
                                    value: 'activate',
                                    child: Text('Activar'),
                                  ),
                                if (row['status'] == 'ACTIVE')
                                  const PopupMenuItem(
                                    value: 'close',
                                    child: Text('Cerrar'),
                                  ),
                              ]
                            : [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                // E1: la foto de la etiqueta, sólo en
                                // Productos.
                                if (tabs.index == 2)
                                  const PopupMenuItem(
                                    value: 'photo',
                                    child: Text('Foto de la etiqueta'),
                                  ),
                                const PopupMenuItem(
                                  value: 'archive',
                                  child: Text('Archivar'),
                                ),
                              ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  String _roleLabel(String role) => switch (role) {
    'ADMIN' => 'Administrador',
    'FAMILY' => 'Familiar',
    'THIRD_PARTY' => 'Tercero',
    _ => role,
  };

  String _policyLabel(String policy) => switch (policy) {
    'BY_ACTUAL_USAGE' => 'Cobro por consumo',
    'BY_PURCHASE_ALLOCATION' => 'Cobro por compra',
    'MANUAL' => 'Manual',
    _ => policy,
  };
}
