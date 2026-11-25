import 'package:flutter/material.dart';

import '../../../domain/money.dart';
import '../../../voice_draft/application/voice_application_draft.dart';
import '../../theme/agro_theme.dart';
import '../../voice/voice_form_dictation.dart';
import '../../widgets/adaptive_entity_picker.dart';
import '../../widgets/agro_ui.dart';
import '../../widgets/common.dart';
import 'application_form_state.dart';
import 'application_who_step.dart' show buildApplicationVoiceEntry;

List<Widget> buildApplicationProductsStep(
  BuildContext context, {
  required ApplicationFormState state,
  required ApplicationCatalogs data,
  required ApplicationFormControllers controllers,
  required VoiceFormDictation<VoiceApplicationDraft>? voice,
  required VoidCallback onOpenVoice,
  required VoidCallback onDismissVoiceBanner,
  required VoidCallback onRegisterPurchase,
  required VoidCallback onAddProduct,
  required ValueChanged<ApplicationLineData> onEditLine,
  required ValueChanged<ApplicationLineData> onRemoveLine,
  required ValueChanged<int> onToggleLineDetail,
  required void Function(int lineId, String text) onDoseChanged,
}) {
  final addable = state.addableProducts;
  final person = state.person(data);
  final farm = state.farm(data);
  final summary = [
    if (farm != null) farm['name'].toString(),
    if (state.areaM2 > 0)
      state.personalMode
          ? '${formatHectares(state.areaM2)} tratadas'
          : formatHectares(state.areaM2),
    if (person != null && !state.personalMode) person['name'].toString(),
  ].join(' · ');
  return [
    Semantics(
      header: true,
      child: const Text('¿Qué aplicó?', style: AgroText.h1),
    ),
    if (summary.isNotEmpty)
      Text(
        summary,
        key: const Key('application-products-context'),
        style: AgroText.detail,
      ),
    const SizedBox(height: 12),
    ...buildApplicationVoiceEntry(
      state: state,
      voice: voice,
      onOpenVoice: onOpenVoice,
      onDismissVoiceBanner: onDismissVoiceBanner,
    ),
    Row(
      children: [
        Expanded(
          child: Text('Productos (${state.lines.length})', style: AgroText.h2),
        ),
        if (state.loadingStock)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    ),
    const SizedBox(height: 10),
    if (state.stocks.isEmpty && !state.loadingStock) ...[
      NoticeBox(
        key: const Key('application-no-stock'),
        icon: Icons.inventory_2_outlined,
        text:
            '${state.personalMode ? 'El titular' : 'Esta persona'} no tiene '
            'productos en existencia. Registre primero la compra.',
      ),
      const SizedBox(height: 10),
    ],
    for (final line in state.lines)
      ApplicationLineCard(
        key: ValueKey(line.id),
        voice: voice,
        line: line,
        doseController: controllers.doseFor(line),
        theoretical: state.theoretical(line),
        doseError: state.doseError(line),
        onEdit: state.saving ? null : () => onEditLine(line),
        onRemove: state.saving ? null : () => onRemoveLine(line),
        onToggleDetail: () => onToggleLineDetail(line.id),
        onDoseChanged: (text) => onDoseChanged(line.id, text),
      ),
    DashedAddButton(
      key: const Key('application-add-product'),
      label: state.lines.isEmpty ? 'Añadir producto' : 'Añadir otro producto',
      onPressed: state.saving || state.loadingStock || addable.isEmpty
          ? null
          : onAddProduct,
    ),
    if (addable.isEmpty && state.lines.isNotEmpty && state.stocks.isNotEmpty)
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Todos los productos en existencia ya están en la mezcla.',
          style: AgroText.detail,
        ),
      ),
    const SizedBox(height: 12),
    if (!state.loadingStock)
      ..._withoutStock(
        state: state,
        data: data,
        onRegisterPurchase: onRegisterPurchase,
      ),
  ];
}

List<Widget> _withoutStock({
  required ApplicationFormState state,
  required ApplicationCatalogs data,
  required VoidCallback onRegisterPurchase,
}) {
  final inStock = {for (final row in state.stocks) row['product_id']};
  final missing = [
    for (final product in data.products)
      if (!inStock.contains(product['id'])) product['name'].toString(),
  ];
  final person = state.person(data);
  final who = state.personalMode
      ? 'el titular'
      : person?['name']?.toString() ?? 'esta persona';
  final register = TextButton.icon(
    key: const Key('application-register-purchase'),
    style: TextButton.styleFrom(
      foregroundColor: AgroColors.link,
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 44),
      alignment: Alignment.centerLeft,
    ),
    onPressed: state.saving ? null : onRegisterPurchase,
    icon: const Icon(Icons.shopping_cart_outlined),
    label: const Text('Registrar compra'),
  );
  if (missing.isEmpty) {
    return [Align(alignment: Alignment.centerLeft, child: register)];
  }
  return [
    ApplicationKeyedNotice(
      textKey: const Key('application-without-stock'),
      text:
          'Sin existencias de $who: ${missing.join(', ')}. '
          '${missing.length == 1 ? 'No aparece' : 'No aparecen'} en '
          '«Añadir producto» hasta que se registre una compra para $who.',
      action: register,
    ),
  ];
}

/// Aviso informativo con su texto identificable por `Key`.
class ApplicationKeyedNotice extends StatelessWidget {
  const ApplicationKeyedNotice({
    super.key,
    required this.textKey,
    required this.text,
    this.action,
  });

  final Key textKey;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AgroColors.chip,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 20, color: AgroColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                key: textKey,
                style: const TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: AgroColors.ink,
                ),
              ),
              ?action,
            ],
          ),
        ),
      ],
    ),
  );
}

/// Producto y cantidad que devuelve la hoja «Agregar producto».
class ApplicationLineInput {
  const ApplicationLineInput(this.product, this.quantityBase);
  final Map<String, Object?> product;
  final int quantityBase;
}

/// Hoja del recorrido explícito: elegir producto, escribir la cantidad usada
/// y confirmar con «Agregar a la mezcla». Devuelve `null` al cancelar.
class ApplicationProductSheet extends StatefulWidget {
  const ApplicationProductSheet({
    super.key,
    required this.options,
    this.initial,
    this.initialQuantityBase,
  });

  final int? initialQuantityBase;
  final List<Map<String, Object?>> options;
  final ApplicationLineInput? initial;

  @override
  State<ApplicationProductSheet> createState() =>
      _ApplicationProductSheetState();
}

class _ApplicationProductSheetState extends State<ApplicationProductSheet> {
  Map<String, Object?>? product;
  late final quantity = TextEditingController(
    text: widget.initial != null
        ? formatForInput(widget.initial!.quantityBase / 1000)
        : (widget.initialQuantityBase ?? 0) > 0
        ? formatForInput(widget.initialQuantityBase! / 1000)
        : '',
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

  String? get _insufficient {
    final available = product?['available_base'] as int?;
    final typed = tryParseBase(quantity.text) ?? 0;
    if (available == null || typed <= available) return null;
    final unit = product!['unit'] as String;
    return 'Pidió ${formatQuantity(typed, unit)} y hay '
        '${formatQuantity(available, unit)}. Baje la cantidad o registre '
        'primero la compra.';
  }

  void _confirm() {
    final chosen = product;
    if (chosen == null) {
      setState(() => error = 'Elija el producto.');
      return;
    }
    final base = tryParseBase(quantity.text) ?? 0;
    if (base <= 0) {
      setState(() => error = 'Escriba la cantidad que usó, mayor que cero.');
      return;
    }
    if (_insufficient != null) return;
    Navigator.pop(context, ApplicationLineInput(chosen, base));
  }

  @override
  Widget build(BuildContext context) {
    final unit = product?['unit']?.toString();
    final available = product?['available_base'] as int?;
    final insufficient = _insufficient;
    final editing = widget.initial != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? 'Cambiar producto' : 'Agregar producto',
                style: AgroText.sheetTitle,
              ),
              const SizedBox(height: 12),
              AgroGroup(
                children: [
                  AdaptiveEntityPicker<Map<String, Object?>>(
                    rowStyle: true,
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
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('application-line-quantity'),
                controller: quantity,
                autofocus: product != null,
                onChanged: (_) => setState(() => error = null),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AgroText.input,
                decoration: InputDecoration(
                  labelText: 'Cantidad usada',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixText: unit,
                  suffixStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AgroColors.muted,
                  ),
                  helperText: available == null
                      ? 'Primero elija el producto.'
                      : 'Hay ${formatQuantity(available, unit!)}.',
                  errorText: error ?? insufficient,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryActionButton(
                key: const Key('application-line-add'),
                onPressed: insufficient == null ? _confirm : null,
                icon: editing ? Icons.check : Icons.add,
                iconFirst: true,
                label: editing ? 'Guardar cambios' : 'Agregar a la mezcla',
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('application-line-cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: AgroColors.ink,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de un producto de la mezcla en el paso 2.
class ApplicationLineCard extends StatelessWidget {
  const ApplicationLineCard({
    super.key,
    required this.line,
    required this.doseController,
    required this.theoretical,
    required this.doseError,
    required this.onEdit,
    required this.onRemove,
    required this.onToggleDetail,
    required this.onDoseChanged,
    this.voice,
  });

  final ApplicationLineData line;
  final TextEditingController doseController;
  final VoiceFormDictation<dynamic>? voice;
  final int? theoretical;
  final String? doseError;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback onToggleDetail;
  final ValueChanged<String> onDoseChanged;

  @override
  Widget build(BuildContext context) {
    final missing = line.quantityBase - line.available;
    final name = line.product['product_name'] as String;
    final open = line.showDetail;
    final linkStyle = TextButton.styleFrom(
      foregroundColor: AgroColors.link,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(
        fontFamily: AgroFonts.body,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
    return Card(
      key: Key('application-line-${line.keyId}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AmountAside(
                amount: formatQuantity(line.quantityBase, line.unit),
                amountKey: Key('application-line-quantity-${line.keyId}'),
                amountStyle: AgroText.input.copyWith(
                  fontSize: 32,
                  height: 38 / 32,
                ),
                minTextWidth: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AgroText.value),
                    Text(
                      missing > 0
                          ? 'Hay ${formatQuantity(line.available, line.unit)}: '
                                'faltan ${formatQuantity(missing, line.unit)}'
                          : 'Hay ${formatQuantity(line.available, line.unit)} '
                                '· quedarán '
                                '${formatQuantity(-missing, line.unit)}',
                      style: missing > 0
                          ? AgroText.detail.copyWith(
                              color: AgroColors.danger,
                              fontWeight: FontWeight.w700,
                            )
                          : AgroText.detail,
                    ),
                  ],
                ),
              ),
            ),
            VoiceSlotMark(
              dictation: voice,
              slot: SlotRef.line(line.id, 'product'),
              current: line.product['product_id'],
              currentDisplay: name,
              writeOtherLabel: 'Elegir otro',
              onWriteOther: onEdit,
            ),
            VoiceSlotMark(
              dictation: voice,
              slot: SlotRef.line(line.id, 'quantity'),
              current: line.quantityBase > 0 ? line.quantityBase : null,
              currentDisplay: formatQuantity(line.quantityBase, line.unit),
              onWriteOther: onEdit,
            ),
            if (voice?.touchesLine(line.id) ?? false) ...[
              if (line.product['product_id'] == null)
                const VoiceMissingMark(label: 'producto (toque «Editar»)'),
              if (line.quantityBase <= 0)
                const VoiceMissingMark(label: 'cantidad usada'),
            ],
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        key: Key('application-line-edit-${line.keyId}'),
                        style: linkStyle.copyWith(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.only(right: 8),
                          ),
                        ),
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar'),
                      ),
                      TextButton.icon(
                        key: Key('application-line-detail-${line.keyId}'),
                        style: linkStyle,
                        onPressed: onToggleDetail,
                        icon: Icon(
                          open ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(
                          'Dosis y costo',
                          semanticsLabel: open
                              ? 'Dosis y costo, abierto'
                              : 'Dosis y costo, cerrado',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('application-line-remove-${line.keyId}'),
                  tooltip: 'Quitar $name',
                  color: AgroColors.muted,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: doseController,
                      onChanged: onDoseChanged,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Dosis (${line.unit}/ha)',
                        helperText: 'Opcional.',
                        errorText: doseError,
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      theoretical == null
                          ? 'Sin dosis no se calcula el teórico · '
                                'Costo estimado: ${formatBob(line.cost)}'
                          : 'Teórico por dosis y área: '
                                '${formatQuantity(theoretical!, line.unit)} · '
                                'Costo estimado: ${formatBob(line.cost)}',
                      style: AgroText.detail,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
