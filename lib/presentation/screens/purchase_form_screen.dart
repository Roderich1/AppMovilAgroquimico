import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
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

/// Nueva compra en dos pasos (ajuste tras el piloto X01, 2026-10-25):
///
/// 1. **Proveedor y productos**: proveedor, fecha (hoy por defecto) y las
///    líneas con su cantidad, precio y, en compartido, su reparto explícito.
/// 2. **Revisión y pago**: lo que se va a guardar, la pregunta
///    «¿Pagaste toda esta compra?» (sin respuesta por defecto) y, plegados,
///    factura, notas y campaña.
///
/// El pago al proveedor lo registra el titular vigente, en las dos
/// modalidades; no hay pagador que elegir. Compra y pago se guardan en una
/// sola transacción (`confirmPurchase(paidInFullByOwner:)`).
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _AllocationEditor {
  int? personId;
  final quantity = TextEditingController();
  void dispose() => quantity.dispose();
}

class _PurchaseLineEditor {
  int? productId;
  CurrencyCode currency = CurrencyCode.bob;
  final quantity = TextEditingController();
  final price = TextEditingController();
  final fx = TextEditingController();
  final allocations = <_AllocationEditor>[_AllocationEditor()];

  int get quantityBase {
    final value = tryParseBase(quantity.text) ?? 0;
    return value > 0 ? value : 0;
  }

  int get priceMinor {
    final value = tryParseMinor(price.text) ?? 0;
    return value > 0 ? value : 0;
  }

  int? get exchangeRateScaled => currency == CurrencyCode.usd
      ? (((tryParseDecimal(fx.text) ?? 0) > 0
                    ? (tryParseDecimal(fx.text) ?? 0)
                    : 0) *
                fxScale)
            .round()
      : null;
  int get unitBob => convertedUnitPriceBobMinor(priceMinor, exchangeRateScaled);
  int get subtotalBob => subtotalMinor(
    quantityBase: quantityBase,
    unitPriceMinor: priceMinor,
    fxScaled: exchangeRateScaled,
  );
  int get assignedBase => allocations.fold(
    0,
    (sum, allocation) => sum + (tryParseBase(allocation.quantity.text) ?? 0),
  );

  void dispose() {
    quantity.dispose();
    price.dispose();
    fx.dispose();
    for (final allocation in allocations) {
      allocation.dispose();
    }
  }
}

enum _PurchaseStep { items, review }

/// Catálogos del formulario y el contexto (modalidad y titular) con que se
/// cargaron.
typedef _PurchaseCatalogs = ({
  List<Map<String, Object?>> suppliers,
  List<Map<String, Object?>> campaigns,
  List<Map<String, Object?>> products,
  List<Map<String, Object?>> people,
});

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  late Future<_PurchaseCatalogs> catalogs;
  final invoiceNumber = TextEditingController();
  final notes = TextEditingController();
  final lines = <_PurchaseLineEditor>[_PurchaseLineEditor()];
  int? supplierId;
  int? campaignId;
  _PurchaseStep step = _PurchaseStep.items;

  /// Día de la compra (#121): hoy por defecto, editable hacia atrás.
  String effectiveDay = localDay(DateTime.now());

  /// Respuesta a «¿Pagaste toda esta compra?». Nula hasta que la persona
  /// elige: no se registra ningún pago por defecto.
  bool? paidInFull;

  /// Modalidad con la que se cargaron las personas (#26).
  OperationMode? loadedMode;

  /// Titular vigente, del vínculo real de la instalación. Paga al proveedor
  /// en las dos modalidades; en propio además recibe todo lo comprado.
  int? ownerPersonId;

  /// En inventario propio, el titular recibe todo lo comprado sin que se elija
  /// persona (#26). Nulo en compartido.
  int? personalOwnerId;
  XFile? invoiceImage;
  bool saving = false;
  bool dirty = false;

  void _markDirty() => setState(() => dirty = true);

  /// Día de la compra (#121): hoy por defecto; se puede elegir un día pasado.
  /// El selector no ofrece el futuro, y el repositorio lo rechaza también.
  /// Cancelar el selector no cambia nada del borrador.
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

  Future<void> _close() async {
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('La compra todavía no fue guardada.'),
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
      );
      if (discard != true) return;
    }
    if (!mounted) return;
    setState(() => dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void initState() {
    super.initState();
    catalogs = _loadCatalogs();
  }

  Future<_PurchaseCatalogs> _loadCatalogs() async {
    final repo = ref.read(repositoryProvider);
    // Asignación según rol privado, titular y modalidad: en modo propio sólo
    // el titular. La modalidad y el titular llegan en la misma consulta.
    // Todas las lecturas se lanzan juntas: una sola ida y vuelta a la base.
    final allocation = repo.peopleAndContextFor(
      PersonPurpose.purchaseAllocation,
    );
    final result = await Future.wait([
      repo.suppliers(),
      repo.campaigns(),
      repo.products(),
      allocation.then((value) => value.people),
    ]);
    final operating = (await allocation).context;
    final active = result[1].where((row) => row['status'] == 'ACTIVE');
    campaignId = active.isEmpty ? null : active.first['id'] as int;
    loadedMode = operating.mode;
    ownerPersonId = operating.ownerPersonId;
    personalOwnerId = operating.mode == OperationMode.personal
        ? operating.ownerPersonId
        : null;
    return (
      suppliers: result[0],
      campaigns: result[1],
      products: result[2],
      people: result[3],
    );
  }

  @override
  void dispose() {
    invoiceNumber.dispose();
    notes.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  int get totalBob => lines.fold(0, (sum, line) => sum + line.subtotalBob);

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (!mounted || picked == null) return;
      setState(() {
        invoiceImage = picked;
        dirty = true;
      });
    } catch (error) {
      if (mounted)
        showError(
          context,
          'No se pudo adjuntar la factura. Revise los permisos.',
        );
    }
  }

  /// Comprueba el paso 1 y explica qué falta. Devuelve `true` si se puede
  /// pasar a la revisión.
  bool _validateItems() {
    if (supplierId == null) {
      showError(context, 'Elige el proveedor.');
      return false;
    }
    if (lines.isEmpty) {
      showError(context, 'Agrega al menos un producto.');
      return false;
    }
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.productId == null ||
          line.quantityBase <= 0 ||
          line.priceMinor <= 0) {
        showError(
          context,
          'Completa producto, cantidad y precio del producto ${index + 1}.',
        );
        return false;
      }
      if (line.currency == CurrencyCode.usd &&
          (line.exchangeRateScaled ?? 0) <= 0) {
        showError(
          context,
          'Escribe el tipo de cambio del producto ${index + 1}.',
        );
        return false;
      }
      // En propio todo es del titular: no hay reparto que comprobar.
      if (personalOwnerId != null) continue;
      if (line.allocations.any((allocation) => allocation.personId == null)) {
        showError(
          context,
          'Elige para quién es cada parte del producto ${index + 1}.',
        );
        return false;
      }
      if (line.assignedBase != line.quantityBase) {
        showError(
          context,
          line.assignedBase > line.quantityBase
              ? 'Lo repartido supera la cantidad comprada del producto ${index + 1}.'
              : 'Falta repartir parte de la cantidad del producto ${index + 1}.',
        );
        return false;
      }
    }
    return true;
  }

  void _goToReview() {
    if (!_validateItems()) return;
    setState(() => step = _PurchaseStep.review);
  }

  void _backToItems() => setState(() => step = _PurchaseStep.items);

  Future<void> _confirm(_PurchaseCatalogs data) async {
    if (saving) return;
    if (!_validateItems()) {
      setState(() => step = _PurchaseStep.items);
      return;
    }
    if (campaignId == null) {
      showError(
        context,
        'No hay una campaña activa. Actívala en Más, Administrar datos.',
      );
      return;
    }
    final paid = paidInFull;
    if (paid == null) {
      showError(context, 'Indica si pagaste toda esta compra.');
      return;
    }
    if (paid && ownerPersonId == null) {
      showError(
        context,
        'No hay un titular vinculado: la compra no puede quedar pagada.',
      );
      return;
    }

    setState(() {
      saving = true;
    });
    final repo = ref.read(repositoryProvider);
    PurchaseDraft? draft;
    try {
      final imagePath = invoiceImage == null
          ? null
          : await repo.storeInvoiceImage(invoiceImage!.path);
      draft = PurchaseDraft(
        supplierId: supplierId!,
        campaignId: campaignId!,
        // Hoy: el instante real. Otro día: su medianoche local (#121).
        purchaseDate: effectiveInstantForDay(effectiveDay, DateTime.now()),
        invoiceNumber: invoiceNumber.text.trim(),
        invoiceImagePath: imagePath,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        exchangeRateSource:
            lines.any((line) => line.currency == CurrencyCode.usd)
            ? ExchangeRateSource.agreedWithSupplier
            : null,
        items: [
          for (final line in lines)
            PurchaseItemDraft(
              productId: line.productId!,
              quantityBase: line.quantityBase,
              currency: line.currency,
              originalUnitPriceMinor: line.priceMinor,
              exchangeRateScaled: line.exchangeRateScaled,
              allocations: personalOwnerId != null
                  ? [
                      AllocationDraft(
                        personId: personalOwnerId!,
                        quantityBase: line.quantityBase,
                      ),
                    ]
                  : [
                      for (final allocation in line.allocations)
                        AllocationDraft(
                          personId: allocation.personId!,
                          quantityBase:
                              tryParseBase(allocation.quantity.text) ?? 0,
                        ),
                    ],
            ),
        ],
      );
      // Compra y pago en una sola transacción: un fallo no deja una compra
      // guardada sin avisar, y reintentar no la duplica.
      await repo.confirmPurchase(draft, paidInFullByOwner: paid);
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
      // RF-03: una fecha de una campaña cerrada se ofrece para revisión.
      final late = draft;
      final captured =
          late != null &&
          await offerLateRegistration(
            context,
            error: error,
            what: 'esta compra',
            extraNote: paid
                ? 'El pago al proveedor se registra después de confirmarla.'
                : null,
            capture: (reason) => repo.captureLatePurchase(late, reason: reason),
          );
      if (!mounted) return;
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
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving && step == _PurchaseStep.items,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || saving) return;
      // Desde la revisión, Atrás vuelve al paso 1 sin perder nada.
      if (step == _PurchaseStep.review) {
        _backToItems();
      } else {
        _close();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva compra'),
        actions: [
          // F09: la misma operación por voz. Si el formulario tiene
          // cambios, se pregunta antes de descartarlos.
          IconButton(
            key: const Key('form-dictar'),
            tooltip: 'Dictar con voz',
            icon: const Icon(Icons.mic_none_outlined),
            onPressed: saving
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
                    context.pushReplacement('/compras/voz');
                  },
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: saving
              ? null
              : step == _PurchaseStep.review
              ? _backToItems
              : _close,
        ),
      ),
      // **#97 — la acción fuera de la barra superior.** Abajo y fija, como en
      // Aplicación y Planificación, el título cabe entero y la acción sigue
      // siempre visible y con su texto.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_PurchaseCatalogs>(
            future: catalogs,
            builder: (context, snapshot) {
              final blocked =
                  saving ||
                  !snapshot.hasData ||
                  modeChangedSince(
                    loadedMode,
                    ref.watch(operationModeProvider),
                  );
              if (step == _PurchaseStep.items) {
                return FilledButton.icon(
                  key: const Key('purchase-continue'),
                  onPressed: blocked ? null : _goToReview,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continuar'),
                );
              }
              return Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('purchase-back'),
                    onPressed: saving ? null : _backToItems,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Atrás'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('purchase-confirm'),
                      onPressed: blocked
                          ? null
                          : () => _confirm(snapshot.data!),
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(saving ? 'Guardando…' : 'Confirmar compra'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: FutureBuilder<_PurchaseCatalogs>(
        future: catalogs,
        builder: (context, snapshot) {
          // Sin esta rama, un fallo al cargar los catálogos dejaba el
          // formulario girando indefinidamente, sin explicación ni salida.
          if (snapshot.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final modeChanged = modeChangedSince(
            loadedMode,
            ref.watch(operationModeProvider),
          );
          return SafeArea(
            child: ListView(
              // Este formulario está fuera del `ShellRoute` y no hereda su
              // `SafeArea` (UIBUG-064); la barra inferior ya reserva su alto.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (modeChanged) ...[
                  const ModeChangedNotice(),
                  const SizedBox(height: 12),
                ],
                _StepHeader(
                  key: const Key('purchase-step'),
                  step: step == _PurchaseStep.items ? 1 : 2,
                  total: 2,
                  title: step == _PurchaseStep.items
                      ? 'Proveedor y productos'
                      : 'Revisión y pago',
                ),
                const SizedBox(height: 12),
                if (step == _PurchaseStep.items)
                  ..._itemsStep(context, data)
                else
                  ..._reviewStep(context, data),
              ],
            ),
          );
        },
      ),
    ),
  );

  String? _ownerName(_PurchaseCatalogs data) => data.people
      .where((row) => row['id'] == ownerPersonId)
      .firstOrNull?['name']
      ?.toString();

  List<Widget> _itemsStep(BuildContext context, _PurchaseCatalogs data) {
    final ownerName = _ownerName(data);
    return [
      _dropdown('Proveedor', data.suppliers, supplierId, (value) {
        setState(() {
          supplierId = value;
          dirty = true;
        });
      }),
      const SizedBox(height: 10),
      ListTile(
        key: const Key('purchase-date'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined),
        title: const Text('Fecha de la compra'),
        subtitle: Text(
          '${formatDate(effectiveDay)}'
          '${effectiveDay == localDay(DateTime.now()) ? ' (hoy)' : ''}',
        ),
        trailing: const Text('Cambiar'),
        onTap: saving ? null : _pickDate,
      ),
      const SizedBox(height: 12),
      // Título y acción en un `Wrap`, no en una fila: con la fuente al 130 %
      // en 360 dp el título se partía en «Producto / s (1)» (#129).
      SectionHeading(
        title: 'Productos (${lines.length})',
        action: FilledButton.tonalIcon(
          onPressed: () {
            setState(() {
              lines.add(_PurchaseLineEditor());
              dirty = true;
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar producto'),
        ),
      ),
      const SizedBox(height: 8),
      for (var index = 0; index < lines.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LineCard(
            key: ObjectKey(lines[index]),
            index: index,
            line: lines[index],
            products: data.products,
            people: data.people,
            personalOwnerName: personalOwnerId == null
                ? null
                : ownerName ?? 'Titular',
            usedProductIds: {
              for (final other in lines)
                if (!identical(other, lines[index]) && other.productId != null)
                  other.productId!,
            },
            onChanged: _markDirty,
            onRemove: lines.length == 1
                ? null
                : () {
                    final removed = lines.removeAt(index);
                    removed.dispose();
                    setState(() => dirty = true);
                  },
          ),
        ),
    ];
  }

  List<Widget> _reviewStep(BuildContext context, _PurchaseCatalogs data) {
    final theme = Theme.of(context);
    final ownerName = _ownerName(data) ?? 'Titular';
    final supplierName =
        data.suppliers
            .where((row) => row['id'] == supplierId)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String personName(int? id) =>
        data.people
            .where((row) => row['id'] == id)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String productName(int? id) =>
        data.products
            .where((row) => row['id'] == id)
            .firstOrNull?['name']
            ?.toString() ??
        '';
    String productUnit(int? id) =>
        data.products
            .where((row) => row['id'] == id)
            .firstOrNull?['unit']
            ?.toString() ??
        '';
    return [
      _Section(
        key: const Key('purchase-review'),
        title: 'Lo que se va a guardar',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reviewRow(Icons.storefront_outlined, 'Proveedor', supplierName),
            _reviewRow(
              Icons.event_outlined,
              'Fecha',
              '${formatDate(effectiveDay)}'
                  '${effectiveDay == localDay(DateTime.now()) ? ' (hoy)' : ''}',
            ),
            const Divider(height: 20),
            for (final line in lines) ...[
              Text(
                '${productName(line.productId)} · '
                '${formatQuantity(line.quantityBase, productUnit(line.productId))} · '
                '${formatBob(line.subtotalBob)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                personalOwnerId != null
                    ? 'Para el titular: $ownerName'
                    : 'Para: ${line.allocations.map((a) => '${personName(a.personId)} ${formatQuantity(tryParseBase(a.quantity.text) ?? 0, productUnit(line.productId))}').join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL COMPRA',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatBob(totalBob),
                  key: const Key('purchase-total'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _Section(
        key: const Key('purchase-paid-question'),
        title: '¿Pagaste toda esta compra?',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Importe: ${formatBob(totalBob)}'),
            const SizedBox(height: 10),
            // Sin respuesta por defecto: la persona elige. `SegmentedButton`
            // admite la selección vacía y muestra la elegida.
            SegmentedButton<bool>(
              key: const Key('purchase-paid-choice'),
              emptySelectionAllowed: true,
              showSelectedIcon: true,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Sí, pagué todo', key: Key('purchase-paid-yes')),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.schedule_outlined),
                  label: Text('No, todavía no', key: Key('purchase-paid-no')),
                ),
              ],
              selected: {?paidInFull},
              onSelectionChanged: saving
                  ? null
                  : (selection) => setState(() {
                      paidInFull = selection.isEmpty ? null : selection.single;
                      dirty = true;
                    }),
            ),
            const SizedBox(height: 10),
            switch (paidInFull) {
              // El pagador no se edita: es el titular del vínculo real.
              true => Row(
                key: const Key('purchase-payer-owner'),
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Pago registrado por: $ownerName')),
                ],
              ),
              false => const Text(
                'La compra queda sin pago. Puedes anotarlo después en '
                'Operaciones, Compras.',
                key: Key('purchase-no-payment'),
              ),
              null => Text(
                'Elige una opción para poder confirmar.',
                key: const Key('purchase-paid-pending'),
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            },
          ],
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ExpansionTile(
          key: const Key('purchase-details'),
          title: const Text('Factura, notas y campaña (opcional)'),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            TextField(
              controller: invoiceNumber,
              onChanged: (_) => _markDirty(),
              decoration: const InputDecoration(labelText: 'N.º de factura'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cámara'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                ),
                if (invoiceImage != null) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(invoiceImage!.path),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              onChanged: (_) => _markDirty(),
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
            const SizedBox(height: 10),
            _dropdown(
              'Campaña',
              data.campaigns.where((row) => row['status'] == 'ACTIVE').toList(),
              campaignId,
              (value) {
                setState(() {
                  campaignId = value;
                  dirty = true;
                });
              },
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

  Widget _dropdown(
    String label,
    List<Map<String, Object?>> rows,
    int? value,
    ValueChanged<int?> changed,
  ) {
    final selected = rows.where((row) => row['id'] == value).firstOrNull;
    return AdaptiveEntityPicker<Map<String, Object?>>(
      label: label,
      items: rows,
      value: selected,
      labelOf: (row) => row['name']! as String,
      onChanged: (row) => changed(row?['id'] as int?),
    );
  }
}

/// «Paso n de m · título», en una línea que crece con la fuente.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
  });
  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'Paso $step de $total · $title',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Dos campos lado a lado si caben; apilados si no (UIBUG-040).
///
/// El umbral es el ancho por debajo del cual media fila deja de bastar para el
/// contenido real del formulario: un nombre de proveedor o de campaña del
/// dataset, o una etiqueta como "Cantidad comprada". Comprimir dos campos hasta
/// que su texto se recorta es peor que apilarlos.
class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  static const double minWidth = 420;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < minWidth
        ? Column(children: [first, const SizedBox(height: 10), second])
        : Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 10),
              Expanded(child: second),
            ],
          ),
  );
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.index,
    required this.line,
    required this.products,
    required this.people,
    required this.usedProductIds,
    required this.onChanged,
    this.onRemove,
    this.personalOwnerName,
  });
  final int index;
  final _PurchaseLineEditor line;
  final List<Map<String, Object?>> products, people;

  /// En inventario propio, el titular que recibe la línea entera (#26).
  final String? personalOwnerName;
  final Set<int> usedProductIds;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  Map<String, Object?>? get selectedProduct {
    for (final product in products) {
      if (product['id'] == line.productId) return product;
    }
    return null;
  }

  /// Cómo va el reparto de esta línea entre personas (UIBUG-039).
  ///
  /// Antes bastaba con que `pendiente == 0` para rotular "asignado", y eso es
  /// cierto también cuando **no se ha escrito nada**: cero comprado y cero
  /// repartido dan diferencia cero. Una línea vacía se anunciaba como
  /// terminada. Una asignación sólo está completa cuando existen todos sus
  /// datos obligatorios: cantidad comprada, persona en cada reparto y suma
  /// repartida igual a la comprada. La regla contable no cambia —la valida
  /// igual `_confirm`—; cambia lo que la tarjeta declara.
  String get _allocationStatus {
    if (line.quantityBase <= 0) return 'Pendiente de cantidad';
    if (personalOwnerName != null) return 'Para el titular';
    if (line.allocations.any((allocation) => allocation.personId == null)) {
      return 'Pendiente de persona';
    }
    final pending = line.quantityBase - line.assignedBase;
    if (pending > 0) {
      return 'Pendiente ${formatQuantity(pending, _unit)}';
    }
    if (pending < 0) {
      return 'Excede en ${formatQuantity(-pending, _unit)}';
    }
    return 'Asignado';
  }

  String get _unit => selectedProduct?['unit']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final unit = _unit;
    final hasProduct = unit.isNotEmpty;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          selectedProduct?['name']?.toString() ?? 'Seleccione producto',
        ),
        subtitle: Text(
          '${formatQuantity(line.quantityBase, unit)} · '
          '${formatBob(line.subtotalBob)} · $_allocationStatus',
        ),
        trailing: onRemove == null
            ? null
            : IconButton(
                tooltip: 'Quitar producto',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
        // El relleno superior era 0, así que la etiqueta flotante del primer
        // campo ("Producto") se dibujaba encima de la cabecera de la tarjeta y
        // aparecía recortada (UIBUG-041). Se corrige en el contenedor —la
        // causa— y no desplazando ese texto en concreto: cualquier campo que
        // llegue a ser el primero hereda el arreglo.
        childrenPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        children: [
          AdaptiveEntityPicker<Map<String, Object?>>(
            label: 'Producto',
            items: products
                .where(
                  (product) =>
                      !usedProductIds.contains(product['id']) ||
                      product['id'] == line.productId,
                )
                .toList(),
            value: selectedProduct,
            labelOf: (product) => product['name']! as String,
            secondaryOf: (product) => product['unit']! as String,
            onChanged: (product) {
              line.productId = product?['id'] as int?;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          // Apilados en ancho de móvil: media fila recortaba la etiqueta a
          // "Cantidad compr…" (UIBUG-040).
          _ResponsivePair(
            first: TextField(
              controller: line.quantity,
              onChanged: (_) => onChanged(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // "Cantidad comprada" y no "Cantidad" a secas: la tarjeta
              // tiene un segundo campo de cantidad por cada asignación, y
              // dos etiquetas idénticas en la misma tarjeta obligarían a
              // deducir cuál es cuál (UIBUG-038).
              decoration: InputDecoration(
                labelText: 'Cantidad comprada',
                suffixText: unit.isEmpty ? null : unit,
              ),
            ),
            second: DropdownButtonFormField<CurrencyCode>(
              initialValue: line.currency,
              decoration: const InputDecoration(labelText: 'Moneda'),
              items: const [
                DropdownMenuItem(value: CurrencyCode.bob, child: Text('BOB')),
                DropdownMenuItem(value: CurrencyCode.usd, child: Text('USD')),
              ],
              onChanged: (value) {
                line.currency = value!;
                onChanged();
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.price,
                  onChanged: (_) => onChanged(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // Sin producto elegido la etiqueta terminaba en una barra
                  // huérfana: "Precio BOB/" (UIBUG-037). Mientras no haya
                  // unidad se dice en palabras; en cuanto la hay se vuelve a
                  // la forma corta "Precio BOB/L".
                  decoration: InputDecoration(
                    labelText: hasProduct
                        ? 'Precio ${line.currency == CurrencyCode.usd ? 'USD' : 'BOB'}/$unit'
                        : 'Precio por unidad',
                  ),
                ),
              ),
              if (line.currency == CurrencyCode.usd) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.fx,
                    onChanged: (_) => onChanged(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'TC Bs/USD'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            // "Costo 0,00 Bs /" sin unidad tampoco significaba nada
            // (UIBUG-037): hasta elegir producto sólo se muestra el subtotal.
            child: Text(
              hasProduct
                  ? 'Costo ${formatBob(line.unitBob)}/$unit · Subtotal ${formatBob(line.subtotalBob)}'
                  : 'Subtotal ${formatBob(line.subtotalBob)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 24),
          // En propio la línea entera es del titular: no hay reparto (#26).
          if (personalOwnerName != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Para el titular: $personalOwnerName',
                key: Key('purchase-personal-allocation-$index'),
              ),
            )
          else ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    // En compartido el reparto es explícito: se dice para
                    // quién es cada parte; nada se asigna solo al titular.
                    '¿Para quién es?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    line.allocations.add(_AllocationEditor());
                    onChanged();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Persona'),
                ),
              ],
            ),
            for (
              var allocationIndex = 0;
              allocationIndex < line.allocations.length;
              allocationIndex++
            )
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // **#97.** Persona y cantidad compartían una fila 3:2 y, con la
                // fuente al 130 %, el nombre se truncaba («Titular F1…»). Si
                // no caben con holgura, la persona va arriba a todo el ancho.
                child: _AllocationRow(
                  onRemove: line.allocations.length > 1
                      ? () {
                          line.allocations.removeAt(allocationIndex).dispose();
                          onChanged();
                        }
                      : null,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AdaptiveEntityPicker<Map<String, Object?>>(
                        label: 'Persona',
                        items: people,
                        value: people
                            .where(
                              (person) =>
                                  person['id'] ==
                                  line.allocations[allocationIndex].personId,
                            )
                            .firstOrNull,
                        labelOf: (person) => person['name']! as String,
                        secondaryOf: (person) =>
                            personRoleLabel(person['role']),
                        onChanged: (person) {
                          line.allocations[allocationIndex].personId =
                              person?['id'] as int?;
                          onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: line.allocations[allocationIndex].quantity,
                        onChanged: (_) => onChanged(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // La etiqueta era la unidad a secas, y sin producto
                        // elegido quedaba vacía: un recuadro sin nombre junto a
                        // un selector de persona (UIBUG-038). Ahora el campo
                        // dice qué es, y la unidad acompaña como sufijo cuando
                        // se conoce.
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          suffixText: unit.isEmpty ? null : unit,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Fila de una asignación: persona (flex 3) y cantidad (flex 2) cuando caben;
/// si no, la persona arriba a todo el ancho y la cantidad debajo (#97).
class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.children, this.onRemove});

  /// `[Expanded(persona), SizedBox, Expanded(cantidad)]`.
  final List<Widget> children;
  final VoidCallback? onRemove;

  /// Ancho a partir del cual persona y cantidad caben en una fila sin
  /// truncar un nombre habitual, también con la fuente al 130 %.
  static const double rowMinWidth = 480;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove == null
        ? null
        : IconButton(
            tooltip: 'Quitar asignación',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          );
    final person = (children.first as Expanded).child;
    final quantity = (children.last as Expanded).child;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= rowMinWidth
          ? Row(children: [...children, ?remove])
          : Column(
              children: [
                person,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: quantity),
                    ?remove,
                  ],
                ),
              ],
            ),
    );
  }
}
