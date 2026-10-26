import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/models.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../operation_mode_controller.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/common.dart';
import 'late_operations_screen.dart' show offerLateRegistration;
import '../widgets/mode_notice.dart';

typedef _ApplicationCatalogs = ({
  List<Map<String, Object?>> people,
  List<Map<String, Object?>> farms,
  Map<String, Object?> campaign,
});

enum _ApplicationStep { who, products, review }

/// Nueva aplicación en tres pasos (ajuste tras el piloto X01, 2026-10-25):
///
/// 1. **Persona y chaco** (en propio aplica el titular, sin elegirlo), fecha
///    y área tratada;
/// 2. **Productos y cantidades**: cada producto entra por el recorrido
///    explícito «Agregar producto → elegir → cantidad → Agregar a la mezcla».
///    Sólo esa confirmación agrega una tarjeta; abrir o cancelar el selector
///    no agrega nada, y el producto restante nunca entra solo;
/// 3. **Resumen y confirmación**.
///
/// La dosis, la cantidad teórica y el costo estimado siguen calculándose
/// igual, en el «Detalle» de cada tarjeta. Las aplicaciones vinculadas a un
/// plan conservan su área exacta, sus cantidades previstas y su confirmación.
class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key, this.planId});
  final int? planId;
  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen> {
  late Future<_ApplicationCatalogs> catalogs;
  int? personId, farmId;
  _ApplicationStep step = _ApplicationStep.who;

  /// Día de la aplicación (#121): hoy por defecto, editable hacia atrás.
  String effectiveDay = localDay(DateTime.now());
  List<Map<String, Object?>> stocks = [];
  final lines = <_ApplicationLineEditor>[];
  final area = TextEditingController();
  final notes = TextEditingController();
  bool dirty = false, saving = false, loadingStock = false;

  /// Modalidad con la que se cargaron personas y chacos (#26).
  OperationMode? loadedMode;

  /// En inventario propio aplica el titular: no se elige persona (#26).
  bool personalMode = false;

  @override
  void initState() {
    super.initState();
    catalogs = _load();
  }

  Future<_ApplicationCatalogs> _load() async {
    final repo = ref.read(repositoryProvider);
    final active = await repo.activeCampaign();
    if (active == null)
      throw BusinessRuleException(
        'Active una campaña antes de registrar aplicaciones.',
      );
    // Quién puede aplicar según su rol privado, el titular y la modalidad: el
    // titular registrado como administrador de pagos también aplica en sus
    // chacos. Sólo se ofrecen chacos cuyo dueño puede aplicar.
    final applicatorRead = await repo.peopleAndContextFor(
      PersonPurpose.applicator,
    );
    final people = applicatorRead.people;
    final operating = applicatorRead.context;
    loadedMode = operating.mode;
    personalMode =
        operating.mode == OperationMode.personal &&
        operating.ownerPersonId != null;
    final applicators = {for (final person in people) person['id']};
    final result = (
      people: people,
      farms: [
        for (final farm in await repo.farms())
          if (applicators.contains(farm['owner_person_id'])) farm,
      ],
      campaign: active,
    );
    if (widget.planId != null) {
      final plan = await repo.planForApplication(widget.planId!);
      if (plan.isEmpty) throw BusinessRuleException('El plan no existe.');
      if (plan.first['campaign_id'] != active['id']) {
        throw BusinessRuleException(
          'El plan no pertenece a la campaña activa.',
        );
      }
      personId = plan.first['person_id'] as int;
      farmId = plan.first['farm_id'] as int;
      area.text = _areaInput(plan.first['area_m2'] as int);
      stocks = await repo.availableProductsForOwner(personId!);
      for (final item in plan) {
        final stock =
            stocks
                .where((row) => row['product_id'] == item['product_id'])
                .firstOrNull ??
            <String, Object?>{
              'product_id': item['product_id'],
              'product_name': item['product_name'],
              'unit': item['unit'],
              'available_base': 0,
              'lot_count': 0,
              'next_fifo_cost_minor': 0,
            };
        final line = _ApplicationLineEditor(
          stock,
          quantityBase: item['required_quantity_base'] as int,
        );
        line.dose.text = formatForInput(
          (item['dose_base_per_ha'] as int) / 1000,
        );
        lines.add(line);
        line.cost = await repo.estimateFifoCost(
          personId: personId!,
          productId: item['product_id'] as int,
          quantityBase: item['required_quantity_base'] as int,
        );
      }
    } else if (personalMode) {
      // El titular se aplica internamente: sus existencias quedan listas y
      // sólo falta elegir uno de sus chacos.
      personId = operating.ownerPersonId;
      stocks = await repo.availableProductsForOwner(personId!);
    }
    return result;
  }

  @override
  void dispose() {
    area.dispose();
    notes.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> selectPerson(Map<String, Object?>? person) async {
    final id = person?['id'] as int?;
    setState(() {
      personId = id;
      // Al cambiar de persona el chaco deja de ser válido, porque la lista de
      // chacos se filtra por propietario. Si se limpia la persona (id nulo) se
      // conserva la selección previa, que es el comportamiento existente.
      if (id != null) farmId = null;
      loadingStock = id != null;
      stocks = [];
      dirty = true;
    });
    _clearLines();
    if (id == null) return;
    final result = await ref
        .read(repositoryProvider)
        .availableProductsForOwner(id);
    if (!mounted || personId != id) return;
    setState(() {
      stocks = result;
      loadingStock = false;
    });
  }

  /// Día de la aplicación (#121): hoy por defecto; se puede elegir un día
  /// pasado. El selector no ofrece el futuro, y el repositorio lo rechaza
  /// también. Cancelar el selector no cambia nada del borrador.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startOfLocalDay(effectiveDay),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      effectiveDay = localDay(picked);
      dirty = true;
    });
  }

  void _clearLines() {
    for (final line in lines) {
      line.dispose();
    }
    lines.clear();
  }

  Future<void> selectFarm(Map<String, Object?>? farm) async {
    if (farm == null) {
      setState(() {
        farmId = null;
        dirty = true;
      });
      return;
    }
    final owner = farm['owner_person_id'] as int;
    // Convenio es-BO: el campo debe precargarse como el usuario podria
    // teclearlo (coma decimal), no como "80.0" (UIBUG-003).
    area.text = _areaInput(farm['area_m2'] as int);
    if (personId != owner) {
      final catalogsValue = _latestCatalogs;
      if (catalogsValue != null) {
        // Con los chacos ya filtrados por quien puede aplicar no debería
        // faltar el dueño; si faltara, `firstWhere` lanzaría StateError en la
        // interfaz. Se avisa en su lugar.
        final ownerRow = catalogsValue.people
            .where((p) => p['id'] == owner)
            .firstOrNull;
        if (ownerRow == null) {
          showError(
            context,
            'El dueño de este chaco no puede registrar aplicaciones.',
          );
          return;
        }
        await selectPerson(ownerRow);
      }
    }
    if (mounted)
      setState(() {
        farmId = farm['id'] as int;
        dirty = true;
      });
  }

  _ApplicationCatalogs? _latestCatalogs;

  /// Productos que todavía no están en la mezcla.
  List<Map<String, Object?>> get _addable => stocks
      .where(
        (p) =>
            !lines.any((line) => line.product['product_id'] == p['product_id']),
      )
      .toList();

  /// Recorrido explícito: abre la hoja, y sólo «Agregar a la mezcla» agrega
  /// **una** tarjeta del producto elegido. Cancelar no cambia nada.
  Future<void> _addProduct() async {
    final result = await showModalBottomSheet<_LineInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ProductSheet(options: _addable),
    );
    if (result == null || !mounted) return;
    if (lines.any(
      (line) => line.product['product_id'] == result.product['product_id'],
    )) {
      showError(context, 'Ese producto ya está en la mezcla.');
      return;
    }
    final line = _ApplicationLineEditor(
      result.product,
      quantityBase: result.quantityBase,
    );
    setState(() {
      lines.add(line);
      dirty = true;
    });
    await estimate(line);
  }

  /// Edita una tarjeta: el mismo recorrido, con el producto y la cantidad
  /// actuales. Puede cambiar a otro producto que no esté ya en la mezcla.
  Future<void> _editLine(_ApplicationLineEditor line) async {
    final result = await showModalBottomSheet<_LineInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ProductSheet(
        options: [line.product, ..._addable],
        initial: _LineInput(line.product, line.quantityBase),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      line
        ..product = result.product
        ..quantityBase = result.quantityBase;
      dirty = true;
    });
    await estimate(line);
  }

  void _removeLine(_ApplicationLineEditor line) {
    setState(() {
      lines.remove(line);
      line.dispose();
      dirty = true;
    });
  }

  Future<void> estimate(_ApplicationLineEditor line) async {
    final q = line.quantityBase;
    if (personId == null || q <= 0) {
      if (mounted) setState(() => line.cost = 0);
      return;
    }
    final cost = await ref
        .read(repositoryProvider)
        .estimateFifoCost(
          personId: personId!,
          productId: line.product['product_id'] as int,
          quantityBase: q,
        );
    if (mounted && q == line.quantityBase) setState(() => line.cost = cost);
  }

  /// Área del campo en m². Sin editar es la precargada, exacta (ver
  /// [_areaInput]).
  int get _areaM2 => ((tryParseDecimal(area.text) ?? 0) * 10000).round();

  /// Área × dosis en enteros, con la misma regla que la cantidad requerida
  /// del plan (`addPlanMulti`) y la aplicación por voz. En coma flotante,
  /// 1,2345 ha × 5 L/ha daba 6172 en vez de 6173.
  int theoretical(_ApplicationLineEditor line) =>
      divideRoundedHalfUp(_areaM2 * (tryParseBase(line.dose.text) ?? 0), 10000);

  Future<bool> confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('La aplicación todavía no fue guardada.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              // Criterio unico de accion destructiva, el mismo que usa
              // `confirmDestructiveAction` en las reversiones (UIBUG-033).
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> requestClose() async {
    if (!dirty || await confirmDiscard()) {
      if (mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  /// Atrás dentro del formulario: un paso hacia atrás sin perder nada; desde
  /// el primero, cerrar (preguntando si hay cambios).
  void _back() {
    switch (step) {
      case _ApplicationStep.who:
        requestClose();
      case _ApplicationStep.products:
        setState(() => step = _ApplicationStep.who);
      case _ApplicationStep.review:
        setState(() => step = _ApplicationStep.products);
    }
  }

  void _continue() {
    switch (step) {
      case _ApplicationStep.who:
        if (personId == null || farmId == null) {
          showError(
            context,
            personalMode
                ? 'Elige el chaco donde aplicaste.'
                : 'Elige la persona y el chaco donde aplicó.',
          );
          return;
        }
        setState(() => step = _ApplicationStep.products);
      case _ApplicationStep.products:
        if (lines.isEmpty) {
          showError(context, 'Agrega al menos un producto a la mezcla.');
          return;
        }
        setState(() => step = _ApplicationStep.review);
      case _ApplicationStep.review:
        break;
    }
  }

  Future<void> submit(_ApplicationCatalogs data) async {
    // Un segundo toque antes de redibujar no debe intentar otra escritura.
    if (saving) return;
    if (personId == null || farmId == null || lines.isEmpty) {
      showError(context, 'Elige persona, chaco y al menos un producto.');
      return;
    }
    final drafts = <ApplicationLineDraft>[];
    for (final line in lines) {
      final real = line.quantityBase;
      final stock = line.product['available_base'] as int;
      if (real <= 0) {
        showError(
          context,
          'Escribe la cantidad usada de ${line.product['product_name']}.',
        );
        return;
      }
      if (real > stock) {
        // Se explica qué falta y cómo seguir, sin términos técnicos.
        showError(
          context,
          'No alcanza el ${line.product['product_name']}: hay '
          '${formatQuantity(stock, line.unit)} y escribiste '
          '${formatQuantity(real, line.unit)}. Baja la cantidad o registra '
          'primero la compra.',
        );
        return;
      }
      drafts.add(
        ApplicationLineDraft(
          productId: line.product['product_id'] as int,
          quantityBase: real,
          treatedAreaM2: _areaM2,
          doseBasePerHa: tryParseBase(line.dose.text),
          theoreticalQuantityBase: theoretical(line),
        ),
      );
    }
    setState(() => saving = true);
    final application = ApplicationDraft(
      personId: personId!,
      farmId: farmId!,
      campaignId: data.campaign['id'] as int,
      // Hoy: el instante real. Otro día: su medianoche local (#121).
      appliedAt: effectiveInstantForDay(effectiveDay, DateTime.now()),
      notes: notes.text.trim(),
      treatedAreaM2: _areaM2,
      planId: widget.planId,
      lines: drafts,
    );
    try {
      await ref.read(repositoryProvider).confirmApplication(application);
      if (!mounted) return;
      setState(() {
        dirty = false;
        saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (error) {
      if (!mounted) return;
      // RF-03: una fecha de una campaña cerrada se ofrece para revisión. Una
      // aplicación tardía no se vincula a un plan.
      final captured =
          widget.planId == null &&
          await offerLateRegistration(
            context,
            error: error,
            what: 'esta aplicación',
            capture: (reason) => ref
                .read(repositoryProvider)
                .captureLateApplication(application, reason: reason),
          );
      if (!mounted) return;
      setState(() => saving = false);
      if (captured) {
        setState(() => dirty = false);
        // Sólo quedó pendiente de revisión: false, para que la lista no
        // anuncie una operación confirmada (DEVICE del 2026-10-24).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      } else {
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving && step == _ApplicationStep.who,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !saving) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva aplicación'),
        actions: [
          // F09: la misma operación por voz. Si el formulario tiene
          // cambios, se pregunta antes de descartarlos.
          IconButton(
            key: const Key('form-dictar'),
            tooltip: 'Dictar con voz',
            icon: const Icon(Icons.mic_none_outlined),
            onPressed: saving || widget.planId != null
                ? null
                : () async {
                    if (dirty &&
                        !await confirmDestructiveAction(
                          context,
                          title: '¿Descartar cambios?',
                          detail:
                              'Lo escrito en el formulario no se '
                              'guardó. Se abrirá el borrador por voz.',
                          confirmLabel: 'Descartar y dictar',
                        )) {
                      return;
                    }
                    if (!context.mounted) return;
                    setState(() => dirty = false);
                    context.pushReplacement('/aplicaciones/voz');
                  },
          ),
        ],
        leading: IconButton(
          onPressed: saving ? null : _back,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_ApplicationCatalogs>(
            future: catalogs,
            builder: (context, snapshot) {
              final blocked =
                  saving ||
                  !snapshot.hasData ||
                  modeChangedSince(
                    loadedMode,
                    ref.watch(operationModeProvider),
                  );
              if (step == _ApplicationStep.who) {
                return FilledButton.icon(
                  key: const Key('application-continue'),
                  onPressed: blocked ? null : _continue,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continuar'),
                );
              }
              return Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('application-back'),
                    onPressed: saving ? null : _back,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Atrás'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: step == _ApplicationStep.products
                        ? FilledButton.icon(
                            key: const Key('application-continue'),
                            onPressed: blocked ? null : _continue,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Continuar'),
                          )
                        : FilledButton.icon(
                            key: const Key('application-confirm'),
                            onPressed: blocked
                                ? null
                                : () => submit(snapshot.data!),
                            icon: const Icon(Icons.check),
                            label: Text(
                              saving ? 'Guardando…' : 'Confirmar aplicación',
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: FutureBuilder<_ApplicationCatalogs>(
        future: catalogs,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          _latestCatalogs = data;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (modeChangedSince(
                  loadedMode,
                  ref.watch(operationModeProvider),
                )) ...[
                  const ModeChangedNotice(),
                  const SizedBox(height: 12),
                ],
                _StepHeader(
                  key: const Key('application-step'),
                  step: switch (step) {
                    _ApplicationStep.who => 1,
                    _ApplicationStep.products => 2,
                    _ApplicationStep.review => 3,
                  },
                  total: 3,
                  title: switch (step) {
                    _ApplicationStep.who => 'Persona y chaco',
                    _ApplicationStep.products => 'Productos y cantidades',
                    _ApplicationStep.review => 'Resumen y confirmación',
                  },
                  campaign: data.campaign['name'] as String,
                ),
                const SizedBox(height: 12),
                ...switch (step) {
                  _ApplicationStep.who => _whoStep(context, data),
                  _ApplicationStep.products => _productsStep(context),
                  _ApplicationStep.review => _reviewStep(context, data),
                },
              ],
            ),
          );
        },
      ),
    ),
  );

  Map<String, Object?>? _person(_ApplicationCatalogs data) =>
      data.people.where((p) => p['id'] == personId).firstOrNull;

  Map<String, Object?>? _farm(_ApplicationCatalogs data) =>
      data.farms.where((f) => f['id'] == farmId).firstOrNull;

  List<Widget> _whoStep(BuildContext context, _ApplicationCatalogs data) {
    final person = _person(data);
    final farms = data.farms
        .where((f) => personId == null || f['owner_person_id'] == personId)
        .toList();
    final farm = _farm(data);
    return [
      ListTile(
        key: const Key('application-date'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined),
        title: const Text('Fecha de la aplicación'),
        subtitle: Text(
          '${formatDate(effectiveDay)}'
          '${effectiveDay == localDay(DateTime.now()) ? ' (hoy)' : ''}',
        ),
        trailing: const Text('Cambiar'),
        onTap: saving ? null : _pickDate,
      ),
      const SizedBox(height: 12),
      // En propio aplica el titular: se muestra, no se elige.
      if (personalMode)
        InputDecorator(
          key: const Key('application-personal-owner'),
          decoration: const InputDecoration(labelText: 'Aplica el titular'),
          child: Text(person?['name']?.toString() ?? ''),
        )
      else
        // En compartido se elige para quién se registra.
        AdaptiveEntityPicker<Map<String, Object?>>(
          label: 'Persona',
          items: data.people,
          value: person,
          labelOf: (p) => p['name'] as String,
          secondaryOf: (p) => personRoleLabel(p['role']),
          onChanged: selectPerson,
        ),
      const SizedBox(height: 12),
      AdaptiveEntityPicker<Map<String, Object?>>(
        label: 'Chaco',
        items: farms,
        value: farm,
        labelOf: (f) => f['name'] as String,
        secondaryOf: (f) => formatHectares(f['area_m2'] as int),
        onChanged: selectFarm,
        enabled: personId != null,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: area,
        onChanged: (_) {
          setState(() => dirty = true);
        },
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Área tratada (ha)',
          helperText: 'Se toma del chaco; puedes cambiarla.',
        ),
      ),
    ];
  }

  List<Widget> _productsStep(BuildContext context) {
    final theme = Theme.of(context);
    final addable = _addable;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Productos (${lines.length})',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (loadingStock)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      const SizedBox(height: 8),
      // Una sola acción agrega, y abre un recorrido con confirmación.
      FilledButton.tonalIcon(
        key: const Key('application-add-product'),
        onPressed: saving || loadingStock || addable.isEmpty
            ? null
            : _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('Agregar producto'),
      ),
      const SizedBox(height: 8),
      if (stocks.isEmpty && !loadingStock)
        const EmptyState(
          icon: Icons.inventory_2_outlined,
          message:
              'Esta persona no tiene productos en existencia. Registra '
              'primero la compra.',
        )
      else if (lines.isEmpty)
        const EmptyState(
          icon: Icons.science_outlined,
          message: 'Toca «Agregar producto» para armar la mezcla.',
        )
      else if (addable.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Todos los productos en existencia ya están en la mezcla.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      for (final line in lines)
        _LineCard(
          key: ValueKey(line.product['product_id']),
          line: line,
          theoretical: theoretical(line),
          onEdit: saving ? null : () => _editLine(line),
          onRemove: saving ? null : () => _removeLine(line),
          onDoseChanged: () => setState(() => dirty = true),
        ),
    ];
  }

  List<Widget> _reviewStep(BuildContext context, _ApplicationCatalogs data) {
    final theme = Theme.of(context);
    final person = _person(data);
    final farm = _farm(data);
    return [
      Card(
        key: const Key('application-review'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lo que se va a guardar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _reviewRow(
                Icons.person_outline,
                personalMode ? 'Aplica el titular' : 'Persona',
                person?['name']?.toString() ?? '',
              ),
              _reviewRow(
                Icons.landscape_outlined,
                'Chaco',
                '${farm?['name'] ?? ''} · ${formatHectares(_areaM2)} tratadas',
              ),
              _reviewRow(
                Icons.event_outlined,
                'Fecha',
                '${formatDate(effectiveDay)}'
                    '${effectiveDay == localDay(DateTime.now()) ? ' (hoy)' : ''}',
              ),
              const Divider(height: 20),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${line.product['product_name']} · '
                    '${formatQuantity(line.quantityBase, line.unit)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ExpansionTile(
          key: const Key('application-notes'),
          title: const Text('Notas (opcional)'),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            TextField(
              controller: notes,
              onChanged: (_) => dirty = true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _reviewRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text('$label: '),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

/// «Paso n de m · título» con la campaña activa.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    required this.campaign,
  });
  final int step;
  final int total;
  final String title;
  final String campaign;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paso $step de $total · $title',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Text('Campaña activa · $campaign'),
      ],
    ),
  );
}

/// Área en m² escrita en hectáreas para el campo editable. Un entero de m²
/// tiene a lo sumo cuatro decimales en hectáreas, así que con cuatro el texto
/// es exacto: 10001 m² se muestra «1,0001» y se relee 10001; con tres se
/// mostraba «1» y se guardaban 10000. Sólo para el área: dinero, dosis y
/// cantidades conservan su formato.
String _areaInput(int areaM2) => formatForInput(areaM2 / 10000, maxDecimals: 4);

class _ApplicationLineEditor {
  _ApplicationLineEditor(this.product, {required this.quantityBase});
  Map<String, Object?> product;

  /// Cantidad realmente usada, en la unidad base del producto.
  int quantityBase;
  final dose = TextEditingController();
  int cost = 0;
  String get unit => product['unit'] as String;
  int get available => product['available_base'] as int;
  void dispose() {
    dose.dispose();
  }
}

/// Producto y cantidad que devuelve la hoja «Agregar producto».
class _LineInput {
  const _LineInput(this.product, this.quantityBase);
  final Map<String, Object?> product;
  final int quantityBase;
}

/// Hoja del recorrido explícito: elegir producto, escribir la cantidad usada
/// y confirmar con «Agregar a la mezcla». Devuelve `null` al cancelar.
class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.options, this.initial});

  /// Productos que se pueden elegir (los que aún no están en la mezcla y, al
  /// editar, el de la tarjeta).
  final List<Map<String, Object?>> options;
  final _LineInput? initial;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  Map<String, Object?>? product;
  late final quantity = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatForInput(widget.initial!.quantityBase / 1000),
  );
  String? error;

  @override
  void initState() {
    super.initState();
    product = widget.initial?.product;
  }

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  void _confirm() {
    final chosen = product;
    if (chosen == null) {
      setState(() => error = 'Elige el producto.');
      return;
    }
    final base = tryParseBase(quantity.text) ?? 0;
    if (base <= 0) {
      setState(() => error = 'Escribe la cantidad que usaste, mayor que cero.');
      return;
    }
    Navigator.pop(context, _LineInput(chosen, base));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = product?['unit']?.toString();
    final available = product?['available_base'] as int?;
    final typed = tryParseBase(quantity.text) ?? 0;
    final editing = widget.initial != null;
    return SafeArea(
      child: Padding(
        // La hoja se encoge con el teclado en vez de quedar debajo.
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'Cambiar producto' : 'Agregar producto',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            // Sin autoselección: elegir es un acto explícito aunque quede
            // una sola opción (piloto X01).
            AdaptiveEntityPicker<Map<String, Object?>>(
              label: 'Producto',
              items: widget.options,
              value: product,
              labelOf: (p) => p['product_name'] as String,
              secondaryOf: (p) =>
                  'Disponible ${formatQuantity(p['available_base'] as int, p['unit'] as String)}',
              onChanged: (p) => setState(() {
                product = p;
                error = null;
              }),
              autoSelectSingle: false,
              allowClear: false,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('application-line-quantity'),
              controller: quantity,
              autofocus: product != null,
              onChanged: (_) => setState(() => error = null),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: unit == null
                    ? 'Cantidad usada'
                    : 'Cantidad usada ($unit)',
                helperText: available == null
                    ? 'Primero elige el producto.'
                    : 'Hay ${formatQuantity(available, unit!)}.',
                helperStyle: available != null && typed > available
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
                errorText: error,
              ),
            ),
            if (available != null && typed > available)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Con esa cantidad la aplicación no se podrá guardar: hay '
                  '${formatQuantity(available, unit!)}.',
                  key: const Key('application-line-insufficient'),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  key: const Key('application-line-cancel'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('application-line-add'),
                    onPressed: _confirm,
                    icon: Icon(editing ? Icons.check : Icons.add),
                    label: Text(
                      editing ? 'Guardar cambios' : 'Agregar a la mezcla',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de un producto de la mezcla: producto, cantidad y unidad a la
/// vista, con «Editar» y «Quitar»; dosis, teórico y costo en el detalle.
class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.theoretical,
    required this.onEdit,
    required this.onRemove,
    required this.onDoseChanged,
  });
  final _ApplicationLineEditor line;
  final int theoretical;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback onDoseChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = line.quantityBase - line.available;
    final name = line.product['product_name'] as String;
    return Card(
      key: Key('application-line-${line.product['product_id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              formatQuantity(line.quantityBase, line.unit),
              key: Key(
                'application-line-quantity-${line.product['product_id']}',
              ),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              missing > 0
                  ? 'Hay ${formatQuantity(line.available, line.unit)}: faltan '
                        '${formatQuantity(missing, line.unit)}'
                  : 'Hay ${formatQuantity(line.available, line.unit)} · quedarán '
                        '${formatQuantity(-missing, line.unit)}',
              // Una proyección negativa se pintaba en color normal, mientras
              // `/inventario` sí resalta en rojo las negativas (UIBUG-044).
              style: missing > 0
                  ? TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700,
                    )
                  : theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: Key(
                    'application-line-edit-${line.product['product_id']}',
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  key: Key(
                    'application-line-remove-${line.product['product_id']}',
                  ),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  label: const Text('Quitar'),
                ),
              ],
            ),
            ExpansionTile(
              key: Key('application-line-detail-${line.product['product_id']}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: Text(
                'Detalle: dosis y costo',
                style: theme.textTheme.bodyMedium,
              ),
              children: [
                TextField(
                  controller: line.dose,
                  onChanged: (_) => onDoseChanged(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Dosis (${line.unit}/ha)',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Teórico por dosis y área: '
                    '${formatQuantity(theoretical, line.unit)} · '
                    'Costo estimado: ${formatBob(line.cost)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
