import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

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
      builder: (_) => _NameDialog(
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

  Future<void> _archive(Map<String, Object?> row) async {
    const tables = ['persons', 'farms', 'products', 'suppliers', 'campaigns'];
    try {
      await ref
          .read(repositoryProvider)
          .archiveCatalog(tables[tabs.index], row['id']! as int);
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _campaignAction(String action, Map<String, Object?> row) async {
    final repo = ref.read(repositoryProvider);
    try {
      if (action == 'activate') {
        try {
          await repo.activateCampaign(row['id'] as int);
        } on CampaignConflictException catch (conflict) {
          if (!mounted) return;
          final replace = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Cambiar campaña activa'),
              content: Text(
                'Está activa ${conflict.activeCampaignName}. ¿Desea cerrarla y activar ${row['name']}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Cerrar y activar'),
                ),
              ],
            ),
          );
          if (replace == true) {
            await repo.activateCampaign(row['id'] as int, closeCurrent: true);
          }
        }
      } else if (action == 'close') {
        final summary = await repo.campaignCloseSummary(row['id'] as int);
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('¿Cerrar ${row['name']}?'),
            // Cerrar dejó de ser reversible desde la aplicación (UIBUG-059),
            // así que la confirmación tiene que decirlo antes, no después:
            // qué campaña, desde cuándo, qué deja de admitir y que no podrá
            // reactivarse.
            content: Text(
              'Periodo: desde ${formatDate(row['start_date'])}.\n\n'
              'Compras: ${summary['purchases_count']} · aplicaciones: ${summary['applications_count']}\n'
              'Planes pendientes: ${summary['pending_plans']}\n'
              'Saldo por cobrar: ${formatBob(summary['receivable_bob_minor'] as int)}\n\n'
              'La campaña dejará de admitir nuevas compras, aplicaciones, '
              'transferencias y planes.\n\n'
              'Una campaña cerrada NO se puede volver a activar desde la '
              'aplicación. Si necesita seguir operando, cree una campaña '
              'nueva.\n\n'
              'El inventario físico no se elimina y seguirá disponible en la próxima campaña.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                // Mismo criterio visual de acción irreversible que las
                // reversiones (UIBUG-033).
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Cerrar definitivamente'),
              ),
            ],
          ),
        );
        if (confirm == true) await repo.closeCampaign(row['id'] as int);
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
          final result = await showDialog<(String, PersonRole)?>(
            context: context,
            builder: (_) => const _PersonDialog(),
          );
          if (result != null)
            await repo.addPerson(name: result.$1, role: result.$2);
        case 1:
          final people = await repo.people();
          if (!mounted) return;
          final result = await showDialog<(int, String, int)?>(
            context: context,
            builder: (_) => _FarmDialog(people: people),
          );
          if (result != null)
            await repo.addFarm(
              ownerId: result.$1,
              name: result.$2,
              areaM2: result.$3,
            );
        case 2:
          final result = await showDialog<(String, String, String)?>(
            context: context,
            builder: (_) => const _ProductDialog(),
          );
          if (result != null)
            await repo.addProduct(
              name: result.$1,
              activeIngredient: result.$2,
              unit: result.$3,
            );
        case 3:
          final name = await showDialog<String?>(
            context: context,
            builder: (_) => const _NameDialog(
              title: 'Nuevo proveedor',
              label: 'Nombre del proveedor',
            ),
          );
          if (name != null) await repo.addSupplier(name: name);
        case 4:
          final name = await showDialog<String?>(
            context: context,
            builder: (_) => const _NameDialog(
              title: 'Nueva campaña',
              label: 'Nombre de campaña',
            ),
          );
          if (name != null)
            await repo.addCampaign(name: name, start: DateTime.now());
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

  @override
  Widget build(BuildContext context) => PageFrame(
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
    action: FilledButton.icon(
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
                return row.values.any(
                  (value) => matchesSearch(value.toString(), query),
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
                        '${row['active_ingredient'] ?? 'Sin ingrediente'} · ${row['unit']}',
                        Icons.science_outlined,
                      ),
                      3 => (
                        row['name'].toString(),
                        row['phone']?.toString() ?? 'Proveedor',
                        Icons.storefront_outlined,
                      ),
                      _ => (
                        row['name'].toString(),
                        '${campaignStatusLabel(row['status'])} · '
                            '${formatDate(row['start_date'])}'
                            '${row['end_date'] == null ? '' : ' – ${formatDate(row['end_date'])}'}',
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
                            : const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
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

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label, this.initial});
  final String title;
  final String label;
  final String? initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

/// Mensaje de validación común a los diálogos de catálogo (UIBUG-031).
///
/// Antes, "Guardar" con el campo vacío simplemente no hacía nada: ni guardaba,
/// ni cerraba, ni explicaba por qué. El botón parecía averiado. Ahora cada
/// diálogo es un `Form` con `validator`, así que el error aparece **en línea
/// bajo el campo que falta** y sigue sin escribirse nada en la base.
String? _requiredText(String? value, String what) =>
    (value ?? '').trim().isEmpty ? 'Escriba $what.' : null;

class _NameDialogState extends State<_NameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(context, controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: formKey,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        validator: (value) => _requiredText(value, widget.label.toLowerCase()),
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}

class _PersonDialog extends StatefulWidget {
  const _PersonDialog();
  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  final name = TextEditingController();
  final formKey = GlobalKey<FormState>();
  PersonRole role = PersonRole.family;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(context, (name.text.trim(), role));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva persona'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (value) => _requiredText(value, 'el nombre'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(
                value: PersonRole.admin,
                child: Text('Administrador'),
              ),
              DropdownMenuItem(
                value: PersonRole.family,
                child: Text('Familiar · cobro por uso'),
              ),
              DropdownMenuItem(
                value: PersonRole.thirdParty,
                child: Text('Tercero · cobro por asignación'),
              ),
            ],
            onChanged: (value) => setState(() => role = value!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}

class _FarmDialog extends StatefulWidget {
  const _FarmDialog({required this.people});
  final List<Map<String, Object?>> people;
  @override
  State<_FarmDialog> createState() => _FarmDialogState();
}

class _FarmDialogState extends State<_FarmDialog> {
  final name = TextEditingController();
  final area = TextEditingController();
  final formKey = GlobalKey<FormState>();
  int? owner;
  @override
  void dispose() {
    name.dispose();
    area.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(context, (
      owner!,
      name.text.trim(),
      ((tryParseDecimal(area.text) ?? 0) * 10000).round(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo chaco'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: owner,
            decoration: const InputDecoration(labelText: 'Propietario'),
            items: [
              for (final row in widget.people)
                DropdownMenuItem(
                  value: row['id']! as int,
                  child: Text(row['name']! as String),
                ),
            ],
            onChanged: (value) => setState(() => owner = value),
            validator: (value) =>
                value == null ? 'Elija un propietario.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (value) => _requiredText(value, 'el nombre del chaco'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: area,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Superficie (ha)'),
            // La superficie no sólo debe estar: debe ser un número mayor a
            // cero, porque `farms.area_m2` lo exige con un CHECK y el fallo
            // llegaba como excepción de SQLite en vez de como aviso del
            // formulario (UIBUG-031).
            validator: (value) {
              if ((value ?? '').trim().isEmpty) return 'Escriba la superficie.';
              final parsed = tryParseDecimal(value!);
              if (parsed == null) return 'Escriba la superficie en números.';
              if (parsed <= 0) return 'La superficie debe ser mayor a cero.';
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog();
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final name = TextEditingController();
  final ingredient = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String unit = 'L';
  @override
  void dispose() {
    name.dispose();
    ingredient.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(context, (name.text.trim(), ingredient.text.trim(), unit));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo producto'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Producto'),
            validator: (value) =>
                _requiredText(value, 'el nombre del producto'),
          ),
          const SizedBox(height: 12),
          // El ingrediente activo es opcional en el esquema, así que no se
          // valida: exigirlo inventaría una regla que la base no tiene.
          TextFormField(
            controller: ingredient,
            decoration: const InputDecoration(labelText: 'Ingrediente activo'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'L', label: Text('Litros')),
              ButtonSegment(value: 'KG', label: Text('Kilogramos')),
            ],
            selected: {unit},
            onSelectionChanged: (value) => setState(() => unit = value.first),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}
