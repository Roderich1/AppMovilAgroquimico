import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/common.dart';

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

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  late Future<List<List<Map<String, Object?>>>> catalogs;
  final invoiceNumber = TextEditingController();
  final lines = <_PurchaseLineEditor>[_PurchaseLineEditor()];
  int? supplierId;
  int? campaignId;
  bool payProvider = false;
  int? payerId;
  XFile? invoiceImage;
  bool saving = false;
  bool dirty = false;

  void _markDirty() => setState(() => dirty = true);

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

  Future<List<List<Map<String, Object?>>>> _loadCatalogs() async {
    final repo = ref.read(repositoryProvider);
    final result = await Future.wait([
      repo.suppliers(),
      repo.campaigns(),
      repo.products(),
      repo.people(),
    ]);
    final active = result[1].where((row) => row['status'] == 'ACTIVE');
    campaignId = active.isEmpty ? null : active.first['id'] as int;
    return result;
  }

  @override
  void dispose() {
    invoiceNumber.dispose();
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

  Future<void> _confirm(List<Map<String, Object?>> people) async {
    if (saving) return;
    if (supplierId == null || campaignId == null) {
      showError(context, 'Seleccione proveedor y campaña.');
      return;
    }
    if (lines.isEmpty) {
      showError(context, 'Agregue al menos un producto.');
      return;
    }
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.productId == null ||
          line.quantityBase <= 0 ||
          line.priceMinor <= 0) {
        showError(
          context,
          'Complete producto, cantidad y precio del ítem ${index + 1}.',
        );
        return;
      }
      if (line.currency == CurrencyCode.usd &&
          (line.exchangeRateScaled ?? 0) <= 0) {
        showError(
          context,
          'Seleccione un tipo de cambio para el ítem ${index + 1}.',
        );
        return;
      }
      if (line.allocations.any((allocation) => allocation.personId == null)) {
        showError(context, 'Seleccione la persona de cada asignación.');
        return;
      }
      if (line.assignedBase != line.quantityBase) {
        showError(
          context,
          line.assignedBase > line.quantityBase
              ? 'La suma asignada supera la cantidad comprada en el ítem ${index + 1}.'
              : 'Falta asignar parte de la cantidad del ítem ${index + 1}.',
        );
        return;
      }
    }
    if (payProvider && payerId == null) {
      showError(context, 'Seleccione quién paga al proveedor.');
      return;
    }

    setState(() {
      saving = true;
    });
    final repo = ref.read(repositoryProvider);
    try {
      final imagePath = invoiceImage == null
          ? null
          : await repo.storeInvoiceImage(invoiceImage!.path);
      final purchaseId = await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplierId!,
          campaignId: campaignId!,
          purchaseDate: DateTime.now(),
          invoiceNumber: invoiceNumber.text.trim(),
          invoiceImagePath: imagePath,
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
                allocations: [
                  for (final allocation in line.allocations)
                    AllocationDraft(
                      personId: allocation.personId!,
                      quantityBase: tryParseBase(allocation.quantity.text) ?? 0,
                    ),
                ],
              ),
          ],
        ),
      );
      if (payProvider) {
        await repo.addProviderPayment(
          purchaseId: purchaseId,
          payerPersonId: payerId!,
          amountBobMinor: totalBob,
          method: 'TRANSFER',
        );
      }
      if (!mounted) return;
      setState(() {
        dirty = false;
        saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (error) {
      if (mounted) showError(context, error);
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
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !saving) _close();
    },
    child: Scaffold(
      body: FutureBuilder(
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
          final suppliers = snapshot.data![0];
          final campaigns = snapshot.data![1];
          final products = snapshot.data![2];
          final people = snapshot.data![3];
          final admins = people
              .where((person) => person['role'] == 'ADMIN')
              .toList();
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: const Text('Nueva compra'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: saving ? null : _close,
                ),
                actions: [
                  TextButton.icon(
                    onPressed: saving ? null : () => _confirm(people),
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Confirmar'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverPadding(
                // Los 120 px fijos no contaban el inset del sistema, así que
                // la tarjeta TOTAL COMPRA quedaba parcialmente bajo la barra de
                // gestos. Este formulario está fuera del `ShellRoute` y no
                // hereda su `SafeArea` (UIBUG-064).
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  120 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                sliver: SliverList.list(
                  children: [
                    _Section(
                      title: 'Factura',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _dropdown(
                                  'Proveedor',
                                  suppliers,
                                  supplierId,
                                  (value) {
                                    setState(() {
                                      supplierId = value;
                                      dirty = true;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _dropdown(
                                  'Campaña',
                                  campaigns
                                      .where((row) => row['status'] == 'ACTIVE')
                                      .toList(),
                                  campaignId,
                                  (value) {
                                    setState(() {
                                      campaignId = value;
                                      dirty = true;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: invoiceNumber,
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'N.º de factura',
                            ),
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
                                onPressed: () =>
                                    _pickImage(ImageSource.gallery),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Productos (${lines.length})',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              lines.add(_PurchaseLineEditor());
                              dirty = true;
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar producto'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < lines.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LineCard(
                          key: ObjectKey(lines[index]),
                          index: index,
                          line: lines[index],
                          products: products,
                          people: people,
                          usedProductIds: {
                            for (final other in lines)
                              if (!identical(other, lines[index]) &&
                                  other.productId != null)
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
                    _Section(
                      title: 'Pago al proveedor',
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Registrar pago total ahora'),
                            subtitle: Text('Importe: ${formatBob(totalBob)}'),
                            value: payProvider,
                            onChanged: (value) => setState(() {
                              payProvider = value;
                              dirty = true;
                              if (value && admins.length == 1)
                                payerId = admins.single['id']! as int;
                            }),
                          ),
                          if (payProvider)
                            _dropdown(
                              'Pagador',
                              admins,
                              payerId,
                              (value) => setState(() {
                                payerId = value;
                                dirty = true;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('TOTAL COMPRA'),
                                  Text(
                                    '${lines.length} producto${lines.length == 1 ? '' : 's'} · ${invoiceImage == null ? 'sin foto' : 'factura adjunta'}',
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatBob(totalBob),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
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
  });
  final int index;
  final _PurchaseLineEditor line;
  final List<Map<String, Object?>> products, people;
  final Set<int> usedProductIds;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  Map<String, Object?>? get selectedProduct {
    for (final product in products) {
      if (product['id'] == line.productId) return product;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final unit = selectedProduct?['unit']?.toString() ?? '';
    final pending = line.quantityBase - line.assignedBase;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          selectedProduct?['name']?.toString() ?? 'Seleccione producto',
        ),
        subtitle: Text(
          '${formatQuantity(line.quantityBase, unit)} · ${formatBob(line.subtotalBob)} · ${pending == 0 ? 'asignado' : 'pendiente ${formatQuantity(pending, unit)}'}',
        ),
        trailing: onRemove == null
            ? null
            : IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.quantity,
                  onChanged: (_) => onChanged(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cantidad ${unit.isEmpty ? '' : '($unit)'}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<CurrencyCode>(
                  initialValue: line.currency,
                  decoration: const InputDecoration(labelText: 'Moneda'),
                  items: const [
                    DropdownMenuItem(
                      value: CurrencyCode.bob,
                      child: Text('BOB'),
                    ),
                    DropdownMenuItem(
                      value: CurrencyCode.usd,
                      child: Text('USD'),
                    ),
                  ],
                  onChanged: (value) {
                    line.currency = value!;
                    onChanged();
                  },
                ),
              ),
            ],
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
                  decoration: InputDecoration(
                    labelText:
                        'Precio ${line.currency == CurrencyCode.usd ? 'USD' : 'BOB'}/$unit',
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
            child: Text(
              'Costo ${formatBob(line.unitBob)}/$unit · Subtotal ${formatBob(line.subtotalBob)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Asignaciones',
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
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
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
                      secondaryOf: (person) => personRoleLabel(person['role']),
                      onChanged: (person) {
                        line.allocations[allocationIndex].personId =
                            person?['id'] as int?;
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: line.allocations[allocationIndex].quantity,
                      onChanged: (_) => onChanged(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: unit),
                    ),
                  ),
                  if (line.allocations.length > 1)
                    IconButton(
                      onPressed: () {
                        line.allocations.removeAt(allocationIndex).dispose();
                        onChanged();
                      },
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
