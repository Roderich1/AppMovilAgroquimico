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

import '../../app.dart';
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

final voiceDraftGatewayProvider = Provider<VoiceDraftGateway>(
  (ref) => VoiceDraftGateway(ref.watch(repositoryProvider)),
);

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

  /// Texto de la sesión ya interpretado. Sólo crece: lo nuevo es lo que se
  /// interpreta.
  String _consumed = '';
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
        initial: VoicePurchaseDraft.start(catalog),
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
    _sync('fx', _fxText(draft), draft.exchangeRate);
    for (final line in draft.lines) {
      _sync('q${line.key}', _quantityText(line), line.quantity);
      _sync('p${line.key}', _priceText(line), line.price);
    }
  }

  static String _fxText(VoicePurchaseDraft d) => d.exchangeRate.value == null
      ? ''
      : formatForInput(d.exchangeRate.value! / fxScale, maxDecimals: 6);

  /// Campos cuyo texto visible no dice lo mismo que el borrador. Si hay
  /// alguno, no se confirma: se escribiría algo distinto de lo que se ve
  /// (revisión de A, B-100-2).
  List<String> _visibleMismatches(VoicePurchaseDraft d) {
    final out = <String>[];
    // Sólo se comparan campos resueltos: los demás ya bloquean por sí mismos.
    bool differs(
      String id,
      DraftField<Object?> field,
      int? expected,
      int? Function(String) parse,
    ) {
      final c = _fields[id];
      if (c == null || !field.isResolved) return false;
      return parse(c.text) != expected;
    }

    if (d.lines.any((l) => l.currency.value == CurrencyCode.usd) &&
        differs(
          'fx',
          d.exchangeRate,
          d.exchangeRate.isResolved ? d.exchangeRate.value : null,
          (t) {
            final v = tryParseDecimal(t);
            return v == null ? null : (v * fxScale).round();
          },
        )) {
      out.add('El tipo de cambio visible no coincide con el borrador.');
    }
    for (var i = 0; i < d.lines.length; i++) {
      final l = d.lines[i];
      if (differs('q${l.key}', l.quantity, l.quantityBase, tryParseBase)) {
        out.add('Línea ${i + 1}: la cantidad visible no coincide.');
      }
      if (differs('p${l.key}', l.price, l.unitPriceMinor, tryParseMinor)) {
        out.add('Línea ${i + 1}: el precio visible no coincide.');
      }
    }
    return out;
  }

  /// Interpreta sólo lo cerrado y nuevo de la sesión. El texto provisional
  /// no se interpreta nunca.
  void _onSession() {
    if (!mounted) return;
    final committed = _session.snapshot.committedText;
    final draft = _draft;
    final catalog = _catalog;
    if (draft != null &&
        catalog != null &&
        committed.length > _consumed.length &&
        committed.startsWith(_consumed)) {
      final fresh = committed.substring(_consumed.length).trim();
      _consumed = committed;
      if (fresh.isNotEmpty) {
        VoiceIntent? other;
        final accepted = draft.applyVoice((current) {
          final r = interpretPurchase(fresh, current, catalog);
          other = r.otherIntent;
          return (r.draft, r.outcome);
        });
        if (accepted) {
          _otherIntent = other;
          if (other == null) _applied.add(fresh);
        }
      }
    } else if (!committed.startsWith(_consumed)) {
      // La sesión se descartó o se reinició: se sigue desde su texto actual.
      _consumed = committed;
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
    if (draft == null || _visibleMismatches(draft.draft).isNotEmpty) return;
    final id = await draft.confirm();
    if (id == null || !mounted) return;
    await _session.discard();
    if (!mounted) return;
    setState(() => _leaving = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Compra registrada (n.º $id).')));
    Navigator.of(context).maybePop(id);
  }

  Future<void> _cancel() async {
    _draft?.discard();
    await _session.discard();
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).maybePop();
  }

  /// Ya se decidió salir: el siguiente «Atrás» no vuelve a preguntar.
  bool _leaving = false;

  /// Hay algo que se perdería al salir.
  bool get _hasWork {
    final d = _draft?.draft;
    return _applied.isNotEmpty ||
        (d != null && (d.lines.isNotEmpty || d.supplier.isResolved));
  }

  /// Atrás con un borrador empezado pregunta antes de descartarlo; durante
  /// la escritura no se puede salir.
  Future<void> _onBack() async {
    if (_draft?.phase == DraftPhase.confirming) return;
    final discard = await confirmDestructiveAction(
      context,
      title: '¿Descartar el borrador?',
      detail: 'No se registró nada. Lo dictado y lo corregido se pierden.',
      confirmLabel: 'Descartar',
    );
    if (discard && mounted) await _cancel();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final catalog = _catalog;
    final confirming = draft?.phase == DraftPhase.confirming;
    return PopScope(
      canPop: _leaving || (!confirming && !_hasWork),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: _buildPage(context, draft, catalog),
    );
  }

  Widget _buildPage(
    BuildContext context,
    VoiceDraftController<VoicePurchaseDraft, int>? draft,
    VoiceCatalog? catalog,
  ) {
    return PageFrame(
      title: 'Compra por voz',
      subtitle:
          'Dicte la compra, revise el borrador y regístrela con un toque.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DraftNotice(),
          const SizedBox(height: 12),
          VoiceListeningPanel(session: _session),
          const SizedBox(height: 12),
          if (_otherIntent != null) _OtherIntentBanner(intent: _otherIntent!),
          if (_applied.isNotEmpty) _AppliedPanel(applied: _applied),
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
    final mismatches = _visibleMismatches(d);
    return Column(
      key: const Key('voz-borrador-compra'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Borrador', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _FieldRow(
          label: 'Campaña',
          field: d.campaign,
          child: Text(d.campaign.value?.name ?? '—'),
        ),
        const Padding(
          key: Key('voz-fecha'),
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Fecha: hoy, con la hora en que confirme (como el formulario).',
          ),
        ),
        _FieldRow(
          label: 'Proveedor',
          field: d.supplier,
          child: _EntryPicker(
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
        _FieldRow(
          label: 'Recibe la compra',
          field: d.recipient,
          child: _EntryPicker(
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
          _FieldRow(
            label: 'Tipo de cambio (Bs por USD)',
            field: d.exchangeRate,
            child: _numberField(
              id: 'fx',
              key: const Key('voz-tipo-cambio'),
              value: _fxText(d),
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
        if (controller.blockers.isNotEmpty || mismatches.isNotEmpty) ...[
          const SizedBox(height: 8),
          _BlockersPanel(blockers: [...controller.blockers, ...mismatches]),
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
              onPressed: controller.canConfirm && mismatches.isEmpty
                  ? _confirm
                  : null,
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
            _FieldRow(
              label: 'Producto',
              field: line.product,
              child: _EntryPicker(
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
            _FieldRow(
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
            _FieldRow(
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
            _FieldRow(
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

class _DraftNotice extends StatelessWidget {
  const _DraftNotice();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'La voz sólo prepara un borrador. Nada se registra hasta que usted '
        'revise y pulse «Registrar compra». Lo que corrija a mano no lo cambia '
        'la voz. Los productos, proveedores y personas se buscan en sus '
        'catálogos; si falta uno, créelo antes en Catálogos.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

class _AppliedPanel extends StatelessWidget {
  const _AppliedPanel({required this.applied});
  final List<String> applied;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('voz-aplicado'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ya aplicado al borrador',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final text in applied.reversed.take(3)) Text('«$text»'),
      ],
    ),
  );
}

class _OtherIntentBanner extends StatelessWidget {
  const _OtherIntentBanner({required this.intent});
  final VoiceIntent intent;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('voz-otra-intencion'),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(switch (intent) {
        VoiceIntent.application || VoiceIntent.plan =>
          'Eso parece otra operación. No se cambió este borrador de compra: '
              'regístrela desde su propia pantalla.',
        VoiceIntent.unsupported =>
          'Los pagos y las consultas por voz no están disponibles. No se cambió '
              'el borrador.',
        _ =>
          'La frase mezcla varias operaciones. No se cambió el borrador: dicte '
              'una sola compra.',
      }),
    ),
  );
}

class _BlockersPanel extends StatelessWidget {
  const _BlockersPanel({required this.blockers});
  final List<String> blockers;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('voz-bloqueos'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Para registrar falta:'),
        for (final b in blockers) Text('• $b'),
      ],
    ),
  );
}

/// Etiqueta, estado del campo y el control para corregirlo.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.field,
    required this.child,
  });

  final String label;
  final DraftField<Object?> field;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (field.status) {
      FieldStatus.resolved => (
        switch (field.origin) {
          FieldOrigin.manual => 'Corregido a mano',
          FieldOrigin.preset => 'Propuesto',
          _ => 'Dictado',
        },
        scheme.primary,
      ),
      FieldStatus.ambiguous => ('Ambiguo: elija', scheme.tertiary),
      FieldStatus.missing => ('Falta', scheme.error),
      FieldStatus.invalid => ('No válido', scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(text, style: TextStyle(color: color)),
            ],
          ),
          if (field.heard != null && !field.isResolved)
            Text(
              'Oído: «${field.heard}»',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (field.message != null && !field.isResolved)
            Text(field.message!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Elegir una entrada **existente** del catálogo. Las opciones del campo
/// ambiguo van primero.
class _EntryPicker extends StatelessWidget {
  const _EntryPicker({
    super.key,
    required this.entries,
    required this.field,
    required this.enabled,
    required this.onPick,
  });

  final List<CatalogEntry> entries;
  final DraftField<CatalogEntry> field;
  final bool enabled;
  final ValueChanged<CatalogEntry> onPick;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...field.candidates,
      for (final e in entries)
        if (!field.candidates.contains(e)) e,
    ];
    final selected = field.isResolved ? field.value : null;
    return DropdownButton<CatalogEntry>(
      isExpanded: true,
      value: ordered.contains(selected) ? selected : null,
      hint: const Text('Elegir'),
      items: [
        for (final e in ordered)
          DropdownMenuItem(value: e, child: Text(e.name)),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) onPick(value);
            }
          : null,
    );
  }
}
