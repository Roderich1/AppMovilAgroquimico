/// Compra por voz: dictar, revisar, corregir y registrar con un toque (#11,
/// con el patrón común de #16).
///
/// - Lo dictado **provisional** se ve aparte (panel de escucha) y no cuenta.
/// - Cada segmento **cerrado** se interpreta y se aplica al borrador, y se
///   muestra como «aplicado».
/// - Cada campo indica si está resuelto, es ambiguo, falta o no es válido, y
///   se puede corregir a mano. Lo corregido a mano no lo cambia la voz.
/// - «Registrar compra» sólo se habilita sin bloqueos y escribe una vez, con
///   el mismo caso de uso que el formulario manual.
/// - Cancelar o salir libera el micrófono y descarta el borrador sin escribir.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/ui/voice_capture_screen.dart';
import '../../voice/voice_providers.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/voice_draft_controller.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/purchase/purchase_interpreter.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_draft/text/units.dart';
import '../widgets/common.dart';
import 'voice_draft_gateway.dart';
import 'voice_draft_widgets.dart';

class VoicePurchaseDraftScreen extends ConsumerStatefulWidget {
  const VoicePurchaseDraftScreen({super.key, this.onOpenManualForm});

  /// Alternativa manual equivalente (formulario de compra). La conecta quien
  /// integra la ruta.
  final VoidCallback? onOpenManualForm;

  @override
  ConsumerState<VoicePurchaseDraftScreen> createState() =>
      _VoicePurchaseDraftScreenState();
}

class _VoicePurchaseDraftScreenState
    extends ConsumerState<VoicePurchaseDraftScreen>
    with WidgetsBindingObserver {
  late final VoiceSessionController _session;
  late final VoiceDraftGateway _gateway;
  VoiceCatalog? _catalog;
  VoiceDraftController<VoicePurchaseDraft, int>? _draft;
  String? _loadError;

  final VoiceSegmentFeed _feed = VoiceSegmentFeed();
  final List<String> _applied = [];
  VoiceIntent? _otherIntent;

  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gateway = ref.read(voiceDraftGatewayProvider);
    _session = VoiceSessionController(
      port: ref.read(speechPortFactoryProvider)(),
    );
    _session.addListener(_onSession);
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await _gateway.purchaseCatalog();
      if (!mounted) return;
      final draft = VoiceDraftController<VoicePurchaseDraft, int>(
        initial: VoicePurchaseDraft.start(catalog, DateTime.now()),
        commit: _gateway.confirmPurchase,
        describeError: friendlyError,
      )..addListener(_onDraft);
      setState(() {
        _catalog = catalog;
        _draft = draft;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = friendlyError(error));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    // Salir libera el micrófono y descarta el borrador: no se escribe nada.
    _session.dispose();
    _draft?.removeListener(_onDraft);
    _draft?.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _session.handleAppPaused();
  }

  void _onDraft() {
    if (!mounted) return;
    _syncFields();
    setState(() {});
  }

  /// Refleja en los campos de texto los valores que cambió la voz. Un campo
  /// corregido a mano no se toca: lo que el usuario escribió se queda.
  void _syncFields() {
    final draft = _draft?.draft;
    if (draft == null) return;
    for (final line in draft.lines) {
      _sync('q${line.key}', _quantityText(line), line.quantity);
      _sync('p${line.key}', _priceText(line), line.price);
    }
  }

  /// Interpreta sólo lo cerrado y nuevo de la sesión. El texto provisional
  /// no se interpreta nunca.
  void _onSession() {
    if (!mounted) return;
    final draft = _draft;
    final catalog = _catalog;
    final fresh = _feed.take(
      _session.snapshot.committedText,
      ready: draft != null && catalog != null,
    );
    if (fresh != null) {
      VoiceIntent? other;
      final accepted = draft!.applyVoice((current) {
        final r = interpretPurchase(fresh, current, catalog!);
        other = r.otherIntent;
        return (r.draft, r.outcome);
      });
      if (accepted) {
        _otherIntent = other;
        if (other == null) _applied.add(fresh);
      }
    }
    setState(() {});
  }

  TextEditingController _controller(String id, String value) =>
      _fields.putIfAbsent(id, () => TextEditingController(text: value));

  static String _quantityText(VoicePurchaseLine line) =>
      line.quantityBase == null
      ? (line.quantity.heard ?? '')
      : formatForInput(line.quantityBase! / baseUnitsPerMajor);

  static String _priceText(VoicePurchaseLine line) => line.price.value == null
      ? ''
      : formatForInput(line.price.value!.minorPerUnit / 100, maxDecimals: 2);

  void _sync(String id, String value, DraftField<Object?> field) {
    final c = _fields[id];
    if (c == null || field.isManual) return;
    if (c.text != value) c.text = value;
  }

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null) return;
    final id = await draft.confirm();
    if (id == null || !mounted) return;
    await _session.discard();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Compra registrada (n.º $id).')));
    Navigator.of(context).maybePop(id);
  }

  Future<void> _cancel() async {
    _draft?.discard();
    await _session.discard();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final catalog = _catalog;
    return PageFrame(
      title: 'Compra por voz',
      subtitle:
          'Dicte la compra, revise el borrador y regístrela con un toque.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VoiceDraftNotice(
            confirmLabel: 'Registrar compra',
            catalogs: 'Los productos, proveedores y personas',
          ),
          const SizedBox(height: 12),
          VoiceListeningPanel(session: _session),
          const SizedBox(height: 12),
          if (_otherIntent != null)
            VoiceOtherIntentBanner(intent: _otherIntent!, current: 'compra'),
          if (_applied.isNotEmpty) VoiceAppliedPanel(applied: _applied),
          const SizedBox(height: 12),
          if (_loadError != null)
            Text(_loadError!, key: const Key('voz-borrador-error-carga'))
          else if (draft == null || catalog == null)
            const Center(child: CircularProgressIndicator())
          else
            _buildDraft(context, draft, catalog),
          if (widget.onOpenManualForm != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('voz-borrador-manual'),
              onPressed: widget.onOpenManualForm,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Usar el formulario manual'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDraft(
    BuildContext context,
    VoiceDraftController<VoicePurchaseDraft, int> controller,
    VoiceCatalog catalog,
  ) {
    final d = controller.draft;
    final editable = controller.phase == DraftPhase.editing;
    final theme = Theme.of(context);
    return Column(
      key: const Key('voz-borrador-compra'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Borrador', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        DraftFieldRow(
          label: 'Campaña',
          field: d.campaign,
          child: Text(d.campaign.value?.name ?? '—'),
        ),
        DraftFieldRow(
          label: 'Proveedor',
          field: d.supplier,
          child: CatalogEntryPicker(
            key: const Key('voz-borrador-proveedor'),
            entries: catalog.suppliers,
            field: d.supplier,
            enabled: editable,
            onPick: (entry) => controller.editManually(
              (c) => c.copyWith(
                supplier: DraftField.resolved(
                  entry,
                  origin: FieldOrigin.manual,
                ),
              ),
            ),
          ),
        ),
        DraftFieldRow(
          label: 'Recibe la compra',
          field: d.recipient,
          child: CatalogEntryPicker(
            key: const Key('voz-borrador-persona'),
            entries: catalog.people,
            field: d.recipient,
            enabled: editable,
            onPick: (entry) => controller.editManually(
              (c) => c.copyWith(
                recipient: DraftField.resolved(
                  entry,
                  origin: FieldOrigin.manual,
                ),
              ),
            ),
          ),
        ),
        for (var i = 0; i < d.lines.length; i++)
          _lineCard(context, controller, catalog, i, d.lines[i], editable),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('voz-agregar-linea'),
            onPressed: editable
                ? () => controller.editManually((c) => c.addEmptyLine())
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Añadir producto a mano'),
          ),
        ),
        if (d.lines.any((l) => l.currency.value == CurrencyCode.usd))
          DraftFieldRow(
            label: 'Tipo de cambio (Bs por USD)',
            field: d.exchangeRate,
            child: _numberField(
              id: 'fx',
              key: const Key('voz-tipo-cambio'),
              value: d.exchangeRate.value == null
                  ? ''
                  : formatForInput(
                      d.exchangeRate.value! / fxScale,
                      maxDecimals: 6,
                    ),
              field: d.exchangeRate,
              enabled: editable,
              onChanged: (text) {
                final parsed = tryParseDecimal(text);
                controller.editManually(
                  (c) => c.copyWith(
                    exchangeRate: parsed == null || parsed <= 0
                        ? const DraftField.invalid(
                            message: 'Escriba un tipo de cambio mayor a cero.',
                            origin: FieldOrigin.manual,
                          )
                        : DraftField.resolved(
                            (parsed * fxScale).round(),
                            origin: FieldOrigin.manual,
                          ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          d.totalBobMinor == null
              ? 'Total: se calcula cuando todas las líneas estén completas.'
              : 'Total calculado: ${formatBob(d.totalBobMinor!)}',
          key: const Key('voz-total'),
          style: theme.textTheme.titleSmall,
        ),
        if (controller.blockers.isNotEmpty) ...[
          const SizedBox(height: 8),
          VoiceBlockersPanel(blockers: controller.blockers),
        ],
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.error!,
            key: const Key('voz-error-registro'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton(
              key: const Key('voz-cancelar'),
              onPressed: controller.phase == DraftPhase.confirming
                  ? null
                  : _cancel,
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              key: const Key('voz-registrar'),
              onPressed: controller.canConfirm ? _confirm : null,
              icon: controller.phase == DraftPhase.confirming
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Registrar compra'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineCard(
    BuildContext context,
    VoiceDraftController<VoicePurchaseDraft, int> controller,
    VoiceCatalog catalog,
    int index,
    VoicePurchaseLine line,
    bool editable,
  ) {
    final unit = line.product.value?.unit;
    final unitLabel = unit == CatalogUnit.kilogram ? 'KG' : 'L';
    final qText = _quantityText(line);
    final pText = _priceText(line);

    void update(VoicePurchaseLine Function(VoicePurchaseLine) change) =>
        controller.editManually((c) => c.updateLine(line.key, change));

    return Card(
      key: Key('voz-linea-${line.key}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Producto ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: Key('voz-quitar-${line.key}'),
                  tooltip: 'Quitar esta línea',
                  onPressed: editable
                      ? () => controller.editManually(
                          (c) => c.removeLine(line.key),
                        )
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            DraftFieldRow(
              label: 'Producto',
              field: line.product,
              child: CatalogEntryPicker(
                key: Key('voz-producto-${line.key}'),
                entries: catalog.products,
                field: line.product,
                enabled: editable,
                onPick: (entry) => update(
                  (l) => l.copyWith(
                    product: DraftField.resolved(
                      entry,
                      origin: FieldOrigin.manual,
                    ),
                  ),
                ),
              ),
            ),
            DraftFieldRow(
              label: 'Cantidad ($unitLabel)',
              field: line.quantity,
              child: _numberField(
                id: 'q${line.key}',
                key: Key('voz-cantidad-${line.key}'),
                value: qText,
                field: line.quantity,
                enabled: editable,
                onChanged: (text) {
                  final base = tryParseBase(text);
                  update(
                    (l) => l.copyWith(
                      quantity: base == null || base <= 0
                          ? const DraftField.invalid(
                              message: 'Escriba una cantidad mayor a cero.',
                              origin: FieldOrigin.manual,
                            )
                          : DraftField.resolved(
                              SpokenQuantity(
                                base,
                                l.product.value?.unit == CatalogUnit.kilogram
                                    ? SpokenUnit.kilogram
                                    : SpokenUnit.liter,
                              ),
                              origin: FieldOrigin.manual,
                            ),
                    ),
                  );
                },
              ),
            ),
            DraftFieldRow(
              label: 'Precio por $unitLabel',
              field: line.price,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _numberField(
                    id: 'p${line.key}',
                    key: Key('voz-precio-${line.key}'),
                    value: pText,
                    field: line.price,
                    enabled: editable,
                    onChanged: (text) {
                      final minor = tryParseMinor(text);
                      update(
                        (l) => l.copyWith(
                          price: minor == null || minor <= 0
                              ? const DraftField.invalid(
                                  message: 'Escriba un precio mayor a cero.',
                                  origin: FieldOrigin.manual,
                                )
                              : DraftField.resolved(
                                  SpokenPrice(minor),
                                  origin: FieldOrigin.manual,
                                ),
                        ),
                      );
                    },
                  ),
                  if (line.price.status == FieldStatus.ambiguous &&
                      line.price.value != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: Key('voz-precio-por-unidad-${line.key}'),
                        onPressed: editable
                            ? () => update(
                                (l) => l.copyWith(
                                  price: DraftField.resolved(
                                    SpokenPrice(l.price.value!.minorPerUnit),
                                    origin: FieldOrigin.manual,
                                  ),
                                ),
                              )
                            : null,
                        child: Text('Sí, es el precio por $unitLabel'),
                      ),
                    ),
                ],
              ),
            ),
            DraftFieldRow(
              label: 'Moneda',
              field: line.currency,
              child: SegmentedButton<CurrencyCode>(
                key: Key('voz-moneda-${line.key}'),
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: CurrencyCode.bob, label: Text('BOB')),
                  ButtonSegment(value: CurrencyCode.usd, label: Text('USD')),
                ],
                selected: {if (line.currency.isResolved) line.currency.value!},
                onSelectionChanged: editable
                    ? (selection) {
                        if (selection.isEmpty) return;
                        update(
                          (l) => l.copyWith(
                            currency: DraftField.resolved(
                              selection.single,
                              origin: FieldOrigin.manual,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required String id,
    required Key key,
    required String value,
    required DraftField<Object?> field,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) => TextField(
    key: key,
    controller: _controller(id, value),
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: onChanged,
  );
}
