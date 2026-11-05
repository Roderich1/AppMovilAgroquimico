import 'package:flutter/material.dart';

import '../../data/agro_repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import 'common.dart';

/// Diálogos de alta de catálogo, compartidos por Catálogos, Campañas y los
/// formularios de operación («Crear producto» en el selector de una compra,
/// por ejemplo). Validan igual en todas partes y escriben con los mismos
/// métodos del repositorio.

/// Alta de producto desde un formulario: el mismo diálogo y la misma
/// escritura que en Catálogos. Devuelve el id creado, o nulo si se canceló o
/// si la escritura falló (el error ya se mostró). El formulario que llama no
/// pierde nada: el diálogo se abre encima del borrador.
Future<int?> createProductFromDialog(
  BuildContext context,
  AgroRepository repo,
) async {
  final result = await showDialog<(String, String, String)?>(
    context: context,
    builder: (_) => const ProductDialog(),
  );
  if (result == null || !context.mounted) return null;
  return _created(
    context,
    () => repo.addProduct(
      name: result.$1,
      activeIngredient: result.$2,
      unit: result.$3,
    ),
  );
}

/// Alta de proveedor desde un formulario. Igual que [createProductFromDialog].
Future<int?> createSupplierFromDialog(
  BuildContext context,
  AgroRepository repo,
) async {
  final name = await showDialog<String?>(
    context: context,
    builder: (_) => const NameDialog(
      title: 'Nuevo proveedor',
      label: 'Nombre del proveedor',
    ),
  );
  if (name == null || !context.mounted) return null;
  return _created(context, () => repo.addSupplier(name: name));
}

/// Alta de chaco desde un formulario. Con [ownerId] el dueño ya está decidido
/// (la persona elegida en una aplicación) y no se vuelve a preguntar; sin él
/// se elige entre quienes pueden tener chacos, y en inventario propio es el
/// titular, como en Catálogos (#26).
Future<int?> createFarmFromDialog(
  BuildContext context,
  AgroRepository repo, {
  int? ownerId,
}) async {
  final read = await repo.peopleAndContextFor(PersonPurpose.farmOwner);
  if (!context.mounted) return null;
  final people = ownerId == null
      ? read.people
      : read.people.where((row) => row['id'] == ownerId).toList();
  if (people.isEmpty) {
    showError(context, 'Esta persona no puede tener chacos.');
    return null;
  }
  final result = await showDialog<(int, String, int)?>(
    context: context,
    builder: (_) => FarmDialog(
      people: people,
      fixedOwner:
          ownerId != null ||
          (read.context.mode == OperationMode.personal && people.length == 1),
      fixedOwnerIsHolder: people.first['id'] == read.context.ownerPersonId,
    ),
  );
  if (result == null || !context.mounted) return null;
  return _created(
    context,
    () => repo.addFarm(ownerId: result.$1, name: result.$2, areaM2: result.$3),
  );
}

/// Alta de persona desde un formulario («Agregar persona»), con la misma
/// regla que Catálogos: sólo en inventario compartido (#26; en propio
/// registra sólo el titular). La modalidad se vuelve a leer aquí, no se
/// confía en la que tenía la pantalla. El diálogo ofrece sólo los tipos que
/// pueden cumplir [purpose] en ese formulario (`canActAs`): una persona nueva
/// nunca es el titular, así que en una aplicación no se ofrece
/// «Administrador», que no podría aplicar. Devuelve el id creado, o nulo si
/// se canceló, falló (el error ya se mostró) o la modalidad no lo permite.
Future<int?> createPersonFromDialog(
  BuildContext context,
  AgroRepository repo, {
  required PersonPurpose purpose,
}) async {
  final operating = await repo.operatingContext();
  if (!context.mounted) return null;
  if (operating.mode == OperationMode.personal) {
    showError(
      context,
      'En inventario propio registra sólo el titular. Para agregar '
      'responsables, cambie a inventario compartido en Modo de uso.',
    );
    return null;
  }
  final roles = [
    for (final role in PersonDialog.allRoles)
      if (canActAs(purpose, role: role, isOwner: false, mode: operating.mode))
        role,
  ];
  final result = await showDialog<(String, PersonRole)?>(
    context: context,
    builder: (_) => PersonDialog(roles: roles),
  );
  if (result == null || !context.mounted) return null;
  return _created(
    context,
    () => repo.addPerson(name: result.$1, role: result.$2),
  );
}

Future<int?> _created(
  BuildContext context,
  Future<int> Function() write,
) async {
  try {
    return await write();
  } catch (error) {
    if (context.mounted) showError(context, error);
    return null;
  }
}

class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.label,
    this.initial,
  });
  final String title;
  final String label;
  final String? initial;
  @override
  State<NameDialog> createState() => _NameDialogState();
}

/// Mensaje de validación común a los diálogos de catálogo (UIBUG-031).
///
/// Antes, "Guardar" con el campo vacío simplemente no hacía nada: ni guardaba,
/// ni cerraba, ni explicaba por qué. El botón parecía averiado. Ahora cada
/// diálogo es un `Form` con `validator`, así que el error aparece **en línea
/// bajo el campo que falta** y sigue sin escribirse nada en la base.
String? _requiredText(String? value, String what) =>
    (value ?? '').trim().isEmpty ? 'Escriba $what.' : null;

class _NameDialogState extends State<NameDialog> {
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
    // Con el teclado abierto el diálogo se desplaza en vez de recortar sus
    // botones: «Guardar» queda siempre alcanzable (2026-11-05).
    scrollable: true,
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

/// Alta de campaña: nombre y día de inicio (RN-15, RN-16).
class CampaignDialog extends StatefulWidget {
  const CampaignDialog({super.key, required this.suggestedStart});
  final DateTime suggestedStart;
  @override
  State<CampaignDialog> createState() => _CampaignDialogState();
}

class _CampaignDialogState extends State<CampaignDialog> {
  final name = TextEditingController();
  final formKey = GlobalKey<FormState>();
  late DateTime start = widget.suggestedStart;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => start = picked);
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(context, (name.text.trim(), start));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // Con el teclado abierto el diálogo se desplaza en vez de recortar sus
    // botones: «Guardar» queda siempre alcanzable (2026-11-05).
    scrollable: true,
    title: const Text('Nueva campaña'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const Key('campaign-name'),
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre de campaña'),
            validator: (value) => _requiredText(value, 'nombre de campaña'),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('campaign-start'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Empieza el'),
            subtitle: Text(formatDate(start.toIso8601String())),
            trailing: const Text('Cambiar'),
            onTap: _pickStart,
          ),
          const Text(
            'Las compras y aplicaciones se ubican en la campaña por su fecha. '
            'Si la campaña anterior sigue abierta, terminará el día anterior a '
            'este inicio; las operaciones desde ese día serán de la campaña '
            'nueva, que habrá que activar para registrarlas.',
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

class PersonDialog extends StatefulWidget {
  const PersonDialog({super.key, this.roles = allRoles});

  /// Tipos que ofrece el diálogo, en este orden. Catálogos ofrece todos;
  /// un formulario, sólo los que pueden cumplir su papel.
  final List<PersonRole> roles;

  static const allRoles = [
    PersonRole.admin,
    PersonRole.family,
    PersonRole.thirdParty,
  ];

  @override
  State<PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<PersonDialog> {
  final name = TextEditingController();
  final formKey = GlobalKey<FormState>();
  late PersonRole role = widget.roles.contains(PersonRole.family)
      ? PersonRole.family
      : widget.roles.first;

  static String _roleLabel(PersonRole role) => switch (role) {
    PersonRole.admin => 'Administrador',
    PersonRole.family => 'Familiar · cobro por uso',
    PersonRole.thirdParty => 'Tercero · cobro por asignación',
  };
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
    // Con el teclado abierto el diálogo se desplaza en vez de recortar sus
    // botones: «Guardar» queda siempre alcanzable (2026-11-05).
    scrollable: true,
    title: const Text('Nueva persona'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const Key('person-name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (value) => _requiredText(value, 'el nombre'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [
              for (final option in widget.roles)
                DropdownMenuItem(
                  value: option,
                  child: Text(_roleLabel(option)),
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

class FarmDialog extends StatefulWidget {
  const FarmDialog({
    super.key,
    required this.people,
    this.fixedOwner = false,
    this.fixedOwnerIsHolder = true,
  });
  final List<Map<String, Object?>> people;

  /// En inventario propio el chaco es del titular: no se elige (#26). Desde
  /// una aplicación, el dueño es la persona ya elegida.
  final bool fixedOwner;

  /// Si el dueño fijo es el titular, para rotularlo así.
  final bool fixedOwnerIsHolder;
  @override
  State<FarmDialog> createState() => _FarmDialogState();
}

class _FarmDialogState extends State<FarmDialog> {
  final name = TextEditingController();
  final area = TextEditingController();
  final formKey = GlobalKey<FormState>();
  late int? owner = widget.fixedOwner
      ? widget.people.single['id']! as int
      : null;
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
    // Con el teclado abierto el diálogo se desplaza en vez de recortar sus
    // botones: «Guardar» queda siempre alcanzable (2026-11-05).
    scrollable: true,
    title: const Text('Nuevo chaco'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.fixedOwner)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Propietario: ${widget.people.single['name']}'
                '${widget.fixedOwnerIsHolder ? ' (titular)' : ''}',
                key: const Key('farm-personal-owner'),
              ),
            )
          else
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

class ProductDialog extends StatefulWidget {
  const ProductDialog({super.key});
  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
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
    // Con el teclado abierto el diálogo se desplaza en vez de recortar sus
    // botones: «Guardar» queda siempre alcanzable (2026-11-05).
    scrollable: true,
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
