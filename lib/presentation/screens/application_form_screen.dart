import 'package:flutter/foundation.dart' show SynchronousFuture;
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
import '../theme/agro_theme.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/agro_ui.dart';
import '../widgets/application_expiry_notice.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import 'late_operations_screen.dart' show offerLateRegistration;
import '../widgets/mode_notice.dart';
import '../voice/voice_draft_gateway.dart' show voiceDraftGatewayProvider;
import '../voice/voice_draft_widgets.dart'
    show voiceDomainContextHints, voiceVocabularyHints;
import '../voice/voice_evidence_hook.dart';
import '../voice/voice_proposals_view.dart'
    show VoiceContextExperimentSwitch, VoicePolicyBSwitch, VoiceProposalsButton;
import '../../voice/port/voice_engine_diagnostics.dart'
    show voiceDiagnosticsBuild;
import '../voice/voice_form_dictation.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/session/voice_session_state.dart';
import '../../voice/voice_providers.dart' show speechPortFactoryProvider;
import '../../voice_draft/application/application_interpreter.dart';
import '../../voice_draft/application/voice_application_draft.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/core/numeric_review.dart';
import '../../voice_draft/interpretation/voice_intent.dart';
import '../../voice_draft/text/units.dart';
import '../../voice_evidence/voice_evidence.dart' show VoiceEvidenceOutcome;

part 'application_form_voice.dart';

typedef _ApplicationCatalogs = ({
  List<Map<String, Object?>> people,
  List<Map<String, Object?>> farms,
  Map<String, Object?> campaign,

  /// Productos activos del catálogo, para explicar cuáles no tienen
  /// existencias de la persona (no sólo omitirlos de la lista).
  List<Map<String, Object?>> products,
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

/// Rótulo del selector de persona de la aplicación en inventario compartido
/// (decisión del autor, 2026-11-12). Es la persona cuyas existencias se
/// consumen y a quien se carga el uso: la responsable del chaco. Antes,
/// «Persona».
const applicationPersonLabel = '¿De quién son los productos?';

class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key, this.planId, this.voice = false});
  final int? planId;

  /// Abrir con el panel «Completar por voz» visible (atajo «Registrar por
  /// voz»). El micrófono no se abre solo.
  final bool voice;
  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen>
    with WidgetsBindingObserver, VoiceEvidenceRecording<ApplicationFormScreen> {
  late Future<_ApplicationCatalogs> catalogs;
  int _nextLineId = 1;

  /// «Completar por voz».
  VoiceFormDictation<VoiceApplicationDraft>? voice;
  late final _voiceTarget = _ApplicationVoice(this);
  bool showVoice = false;

  /// Aviso del último dictado arriba del paso (el panel se cierra solo al
  /// terminar un dictado; lo dictado ya está en el formulario).
  bool _voiceBanner = false;
  int _seenCompletions = 0;
  VoiceApplicationDraft? _lastVoiceDraft;
  bool _voiceSaved = false;
  bool _voiceFailed = false;
  bool _observingSession = false;
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

  /// Titular vigente, para rotular su costo como propio (E-15).
  int? ownerPersonId;

  /// Lotes que consumiría cada producto de la mezcla (por `product_id`),
  /// leídos al pasar al resumen con la misma regla FIFO que la escritura
  /// (`previewApplicationLots`). Sólo sirven para el aviso de vencimiento.
  Map<Object?, List<ApplicationLotPreview>> lotPreview = {};
  bool loadingPreview = false;
  int _previewRequest = 0;

  /// Ayuda breve «¿Cómo se calcula el costo?» del resumen, abierta o no.
  bool showCostHelp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initVoiceEvidence();
    // Rediseño individual (2026-11-13): si la modalidad cambia con un
    // dictado en curso, se cancela; su resultado tardío no llega al
    // formulario (que además queda bloqueado por `ModeChangedNotice`).
    ref.listenManual(operationModeProvider, (_, next) {
      if (modeChangedSince(loadedMode, next) && (voice?.busy ?? false)) {
        voice!.cancel();
      }
    });
    catalogs = _load();
    if (widget.voice && widget.planId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openVoice();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) voice?.session.handleAppPaused();
  }

  void _openVoice() {
    voice ??= VoiceFormDictation<VoiceApplicationDraft>(
      session: VoiceSessionController(
        port: ref.read(speechPortFactoryProvider)(),
      ),
      target: _voiceTarget,
    )..addListener(_onVoice);
    if (!_observingSession) {
      _observingSession = true;
      voice!.session.addListener(
        () => observeVoiceSession(voice!.session.snapshot),
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      showVoice = true;
      _voiceBanner = false;
    });
    _voiceTarget.loadCatalog().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Al terminar un dictado el panel se cierra y su resultado queda en el
  /// aviso de arriba del paso.
  void _onVoice() {
    if (!mounted) return;
    final v = voice;
    setState(() {
      if (v != null && v.completions != _seenCompletions) {
        _seenCompletions = v.completions;
        showVoice = false;
        _voiceBanner = true;
      }
    });
  }

  void _voiceApplied(VoiceApplicationDraft shadow, String text) {
    _lastVoiceDraft = shadow;
    noteVoiceApplied(shadow, text);
  }

  void _voiceSetState(VoidCallback fn) => setState(fn);

  /// Fila de existencias del producto para una línea: la del responsable si
  /// la tiene; si no, una sin existencias (Continuar y Confirmar la
  /// rechazan con su aviso de siempre); sin producto, «por elegir».
  Map<String, Object?> _productRow(int? productId) {
    if (productId == null) {
      return const {
        'product_id': null,
        'product_name': 'Producto por elegir',
        'unit': '',
        'available_base': 0,
        'lot_count': 0,
        'next_fifo_cost_minor': 0,
      };
    }
    final stock = stocks.where((r) => r['product_id'] == productId).firstOrNull;
    if (stock != null) return stock;
    final product = _latestCatalogs?.products
        .where((p) => p['id'] == productId)
        .firstOrNull;
    return {
      'product_id': productId,
      'product_name': product?['name'] ?? 'Producto',
      'unit': product?['unit'] ?? '',
      'available_base': 0,
      'lot_count': 0,
      'next_fifo_cost_minor': 0,
    };
  }

  /// Tras un dictado o al llegar las existencias del responsable: cada línea
  /// toma su fila de existencias y se estima su costo, como al agregarla.
  void _refreshVoiceLines() {
    for (final line in lines) {
      final id = line.product['product_id'] as int?;
      if (id == null) continue;
      final stock = stocks.where((r) => r['product_id'] == id).firstOrNull;
      if (stock != null && !identical(stock, line.product)) {
        line.product = stock;
      }
      if (line.quantityBase > 0) estimate(line);
    }
    if (mounted) setState(() {});
  }

  /// Chaco puesto por voz: el responsable es su dueño (si cambia, la mezcla
  /// se vacía, como al elegirlo a mano: sólo se llega aquí sin persona o tras
  /// confirmarlo). No pisa el área, que tiene su propia ranura.
  void _selectFarmForVoice(int? id) {
    final farm = _latestCatalogs?.farms.where((f) => f['id'] == id).firstOrNull;
    if (farm == null) {
      farmId = null;
      return;
    }
    final owner = farm['owner_person_id'] as int;
    if (personId != owner) {
      final ownerRow = _latestCatalogs?.people
          .where((p) => p['id'] == owner)
          .firstOrNull;
      if (ownerRow == null) return;
      personId = owner;
      _clearLines();
      stocks = [];
      loadingStock = true;
      _loadStocksForVoice(owner);
    }
    farmId = farm['id'] as int;
  }

  Future<void> _loadStocksForVoice(int owner) async {
    final result = await ref
        .read(repositoryProvider)
        .availableProductsForOwner(owner);
    if (!mounted || personId != owner) return;
    setState(() {
      stocks = result;
      loadingStock = false;
    });
    _refreshVoiceLines();
  }

  /// Un plan pendiente elegido por voz: se abre el recorrido de siempre
  /// «Aplicar este plan» (sus productos y cantidades previstas).
  Future<void> _openPlanFromVoice(int planId) async {
    if (dirty &&
        !await confirmDestructiveAction(
          context,
          title: '¿Descartar cambios?',
          detail:
              'Lo cargado en esta aplicación no se guardó. Se abrirá el plan '
              'elegido con sus productos.',
          confirmLabel: 'Abrir el plan',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => dirty = false);
    context.pushReplacement('/aplicaciones/nueva?planId=$planId');
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
    ownerPersonId = operating.ownerPersonId;
    final applicators = {for (final person in people) person['id']};
    // Chacos y productos se leen a la vez: una sola espera más.
    final read = await Future.wait([repo.farms(), repo.products()]);
    final result = (
      people: people,
      farms: [
        for (final farm in read[0])
          if (applicators.contains(farm['owner_person_id'])) farm,
      ],
      campaign: active,
      products: read[1],
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
          id: _nextLineId++,
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
    WidgetsBinding.instance.removeObserver(this);
    finishVoiceEvidenceWith(
      finalDraft: _lastVoiceDraft,
      outcome: _voiceSaved
          ? VoiceEvidenceOutcome.confirmed
          : _voiceFailed
          ? VoiceEvidenceOutcome.failed
          : VoiceEvidenceOutcome.discarded,
    );
    voice?.removeListener(_onVoice);
    voice?.release();
    voice?.dispose();
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
    voice?.reconcile(_voiceTarget.snapshot());
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

  /// «Crear chaco» para la persona elegida (en propio, el titular): el alta
  /// de Catálogos sobre la aplicación, con el dueño ya decidido. Se vuelven
  /// a leer sólo los chacos; fecha, persona, área y mezcla se conservan. Si se
  /// cancela o falla, nada cambia. Aquí no se crean productos: la mezcla sale
  /// de las existencias.
  Future<Map<String, Object?>?> _createFarm() async {
    final owner = personId;
    if (owner == null) return null;
    final repo = ref.read(repositoryProvider);
    final id = await createFarmFromDialog(context, repo, ownerId: owner);
    if (id == null) return null;
    final current = await catalogs;
    final applicators = {for (final person in current.people) person['id']};
    final next = (
      people: current.people,
      farms: [
        for (final farm in await repo.farms())
          if (applicators.contains(farm['owner_person_id'])) farm,
      ],
      campaign: current.campaign,
      products: current.products,
    );
    _replaceCatalogs(next);
    return next.farms.where((f) => f['id'] == id).firstOrNull;
  }

  void _replaceCatalogs(_ApplicationCatalogs next) {
    if (!mounted) return;
    setState(() {
      // `SynchronousFuture`: el `FutureBuilder` toma la lista nueva en la
      // misma reconstrucción. Con `Future.value` pasaba un fotograma con la
      // lista vieja, el selector no encontraba lo elegido y autoelegía la
      // única opción anterior encima de lo recién creado.
      catalogs = SynchronousFuture(next);
    });
  }

  /// «Agregar persona» en el selector de persona: el alta de Catálogos con
  /// su regla (sólo en compartido) y sólo con los tipos que pueden aplicar
  /// (`createPersonFromDialog`). Se vuelven a leer sólo las personas; la
  /// creada queda elegida por el selector (`selectPerson`), que lee sus
  /// existencias. Fecha, área y notas se conservan. Si se cancela o falla,
  /// nada cambia.
  Future<Map<String, Object?>?> _createPerson() async {
    final repo = ref.read(repositoryProvider);
    final id = await createPersonFromDialog(
      context,
      repo,
      purpose: PersonPurpose.applicator,
    );
    if (id == null) return null;
    final current = await catalogs;
    final people = await repo.peopleFor(PersonPurpose.applicator);
    _replaceCatalogs((
      people: people,
      farms: current.farms,
      campaign: current.campaign,
      products: current.products,
    ));
    return people.where((p) => p['id'] == id).firstOrNull;
  }

  /// «Registrar compra» desde la mezcla: abre la compra **encima** de la
  /// aplicación (`push`), así que al volver el borrador sigue entero —paso,
  /// fecha, persona, chaco, área, mezcla, dosis y notas— y sólo se vuelven a
  /// leer las existencias de la persona y el catálogo de productos.
  Future<void> _registerPurchase() async {
    await context.push<bool>('/compras/nueva');
    if (!mounted) return;
    await _refreshStock();
  }

  /// Relee las existencias de la persona elegida y actualiza lo disponible
  /// de cada tarjeta de la mezcla (y su costo estimado), sin quitar ninguna.
  Future<void> _refreshStock() async {
    final id = personId;
    if (id == null) return;
    final repo = ref.read(repositoryProvider);
    setState(() => loadingStock = true);
    final fresh = await repo.availableProductsForOwner(id);
    final products = await repo.products();
    if (!mounted || personId != id) return;
    final current = _latestCatalogs;
    setState(() {
      stocks = fresh;
      loadingStock = false;
      for (final line in lines) {
        final productId = line.product['product_id'];
        line.product =
            fresh.where((row) => row['product_id'] == productId).firstOrNull ??
            {...line.product, 'available_base': 0};
      }
      if (current != null) {
        catalogs = SynchronousFuture((
          people: current.people,
          farms: current.farms,
          campaign: current.campaign,
          products: products,
        ));
      }
    });
    for (final line in List.of(lines)) {
      await estimate(line);
    }
  }

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
      id: _nextLineId++,
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
      builder: (context) => line.product['product_id'] == null
          // Línea dictada con el producto por elegir: se elige aquí, con la
          // cantidad dictada ya escrita.
          ? _ProductSheet(
              options: _addable,
              initialQuantityBase: line.quantityBase,
            )
          : _ProductSheet(
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
    voice?.reconcile(_voiceTarget.snapshot());
    await estimate(line);
  }

  void _removeLine(_ApplicationLineEditor line) {
    voice?.lineRemoved(line.id);
    setState(() {
      lines.remove(line);
      line.dispose();
      dirty = true;
    });
  }

  Future<void> estimate(_ApplicationLineEditor line) async {
    final q = line.quantityBase;
    if (personId == null || q <= 0 || line.product['product_id'] == null) {
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
  ///
  /// Sin dosis no hay teórico: se devuelve `null` y se guarda nulo, en vez
  /// de «teórico 0» y «desvío = toda la cantidad» (B-04).
  int? theoretical(_ApplicationLineEditor line) {
    final dose = tryParseBase(line.dose.text);
    if (dose == null) return null;
    return divideRoundedHalfUp(_areaM2 * dose, 10000);
  }

  /// Mensaje de formato de la dosis escrita, o `null` si está vacía o bien
  /// escrita (convenio es-BO de `numeric_input.dart`).
  String? doseError(_ApplicationLineEditor line) =>
      parseNumericInput(line.dose.text).message;

  /// Área tratada del paso 1: vacía o mal escrita se rechaza al continuar
  /// con el mensaje de formato; antes se guardaba como 0 ha (B-04).
  String? areaError;

  String? _validateArea() {
    final parsed = parseNumericInput(area.text);
    if (parsed.status == NumericInputStatus.empty) {
      return 'Escriba el área tratada en hectáreas.';
    }
    if (!parsed.isValid) return parsed.message;
    if (parsed.value! <= 0) return 'El área tratada debe ser mayor que cero.';
    return null;
  }

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
                ? 'Elija el chaco donde aplicó.'
                : 'Elija la persona y el chaco donde aplicó.',
          );
          return;
        }
        final invalidArea = _validateArea();
        if (invalidArea != null) {
          setState(() => areaError = invalidArea);
          return;
        }
        setState(() => step = _ApplicationStep.products);
      case _ApplicationStep.products:
        if (lines.isEmpty) {
          showError(context, 'Agregue al menos un producto a la mezcla.');
          return;
        }
        if (lines.any((l) => l.product['product_id'] == null)) {
          showError(
            context,
            'Elija el producto de cada línea (toque «Editar») o quite la línea.',
          );
          return;
        }
        setState(() => step = _ApplicationStep.review);
        _loadLotPreview();
      case _ApplicationStep.review:
        break;
    }
  }

  /// Previsión de los lotes que usará cada producto en la fecha efectiva de
  /// la aplicación, para el aviso de vencimiento del resumen. Se vuelve a
  /// leer cada vez que se entra al resumen (la fecha, la persona o la mezcla
  /// pudieron cambiar). Sólo informa: si no se puede leer (por ejemplo, el
  /// cupo de una fecha pasada no alcanza), no se avisa y la confirmación
  /// valida como siempre.
  Future<void> _loadLotPreview() async {
    final id = personId;
    if (id == null) return;
    final request = ++_previewRequest;
    final appliedAt = effectiveInstantForDay(effectiveDay, DateTime.now());
    final wanted = [
      for (final line in lines)
        (id: line.product['product_id']! as int, quantity: line.quantityBase),
    ];
    setState(() {
      loadingPreview = true;
      lotPreview = {};
    });
    final repo = ref.read(repositoryProvider);
    final next = <Object?, List<ApplicationLotPreview>>{};
    try {
      // Todas las lecturas a la vez: el resumen no espera producto por
      // producto.
      final previews = await Future.wait([
        for (final item in wanted)
          repo.previewApplicationLots(
            personId: id,
            productId: item.id,
            quantityBase: item.quantity,
            appliedAt: appliedAt,
          ),
      ]);
      for (var i = 0; i < wanted.length; i++) {
        next[wanted[i].id] = previews[i];
      }
    } catch (_) {
      // Sin previsión no hay aviso; nada más cambia.
    }
    if (!mounted || request != _previewRequest) return;
    setState(() {
      lotPreview = next;
      loadingPreview = false;
    });
  }

  Future<void> submit(_ApplicationCatalogs data) async {
    // Un segundo toque antes de redibujar no debe intentar otra escritura.
    if (saving) return;
    if (personId == null || farmId == null || lines.isEmpty) {
      showError(context, 'Elija persona, chaco y al menos un producto.');
      return;
    }
    if (lines.any((l) => l.product['product_id'] == null)) {
      showError(context, 'Elija el producto de cada línea o quite la línea.');
      return;
    }
    final drafts = <ApplicationLineDraft>[];
    for (final line in lines) {
      final real = line.quantityBase;
      final stock = line.product['available_base'] as int;
      if (real <= 0) {
        showError(
          context,
          'Escriba la cantidad usada de ${line.product['product_name']}.',
        );
        return;
      }
      if (real > stock) {
        // Se explica qué falta y cómo seguir, sin términos técnicos.
        showError(
          context,
          'No alcanza el ${line.product['product_name']}: hay '
          '${formatQuantity(stock, line.unit)} y escribió '
          '${formatQuantity(real, line.unit)}. Baje la cantidad o registre '
          'primero la compra.',
        );
        return;
      }
      final invalidDose = doseError(line);
      if (invalidDose != null) {
        // Una dosis mal escrita no se guarda en silencio como «sin dosis».
        showError(
          context,
          'Dosis de ${line.product['product_name']}: $invalidDose',
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
      _voiceSaved = true;
      // `saving` se queda en true hasta cerrar: si bajara aquí, el botón
      // volvería a habilitarse durante el fotograma previo al `pop` y un
      // segundo toque podría escribir otra aplicación (revisión cruzada X01).
      setState(() => dirty = false);
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
      if (!captured) _voiceFailed = true;
      if (captured) {
        setState(() => dirty = false);
        // Sólo quedó pendiente de revisión: false, para que la lista no
        // anuncie una operación confirmada (DEVICE del 2026-10-24).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      } else {
        setState(() => saving = false);
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
      bottomNavigationBar: _bottomBar(),
      body: SafeArea(
        child: FutureBuilder<_ApplicationCatalogs>(
          future: catalogs,
          builder: (context, snapshot) {
            final header = Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _header(snapshot.data?.campaign['name']?.toString()),
            );
            if (snapshot.hasError) {
              return Column(
                children: [
                  header,
                  Expanded(
                    child: EmptyState(
                      icon: Icons.error_outline,
                      message: friendlyError(snapshot.error!),
                    ),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return Column(
                children: [
                  header,
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }
            final data = snapshot.data!;
            _latestCatalogs = data;
            return Column(
              children: [
                header,
                Expanded(
                  child: ListView(
                    key: const Key('application-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (modeChangedSince(
                        loadedMode,
                        ref.watch(operationModeProvider),
                      )) ...[
                        const ModeChangedNotice(),
                        const SizedBox(height: 12),
                      ],
                      ...switch (step) {
                        _ApplicationStep.who => _whoStep(context, data),
                        _ApplicationStep.products => _productsStep(
                          context,
                          data,
                        ),
                        _ApplicationStep.review => _reviewStep(context, data),
                      },
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  int get _stepNumber => switch (step) {
    _ApplicationStep.who => 1,
    _ApplicationStep.products => 2,
    _ApplicationStep.review => 3,
  };

  /// La voz completa los pasos 1 y 2 de una aplicación sin plan. Con un plan,
  /// persona, chaco y productos vienen del plan; en el resumen no se dicta.
  bool get _voiceStep =>
      widget.planId == null && step != _ApplicationStep.review;

  /// Volver, «Paso n de 3», el acceso a la voz y la barra de pasos.
  Widget _header(String? campaign) {
    final first = step == _ApplicationStep.who;
    final busy = voice?.busy ?? false;
    return Column(
      children: [
        FlowTopBar(
          backKey: Key(first ? 'application-close' : 'application-back'),
          backTooltip: first ? 'Volver' : 'Volver al paso ${_stepNumber - 1}',
          onBack: saving ? null : _back,
          label: first && campaign != null
              ? 'Paso 1 de 3 · $campaign'
              : 'Paso $_stepNumber de 3',
          labelKey: const Key('application-step'),
          // F09 (formulario único): la voz completa ESTE formulario.
          trailing: _voiceStep
              ? CircleIconButton(
                  key: const Key('form-dictar'),
                  icon: showVoice ? Icons.mic : Icons.mic_none_outlined,
                  tooltip: showVoice
                      ? 'Ocultar el panel de voz'
                      : 'Completar por voz',
                  onPressed: saving
                      ? null
                      : showVoice
                      ? busy
                            ? null
                            : () => setState(() => showVoice = false)
                      : _openVoice,
                )
              : null,
        ),
        const SizedBox(height: 12),
        StepProgress(step: _stepNumber, total: 3),
      ],
    );
  }

  /// Panel inferior: «Continuar», «Confirmar aplicación» o el panel de voz,
  /// que ocupa su lugar mientras está abierto (se cierra con ✕ o solo, al
  /// terminar un dictado).
  Widget _bottomBar() {
    if (_voiceStep && showVoice && voice != null) {
      return VoiceFormPanel(
        dictation: voice!,
        docked: true,
        // Láminas I-13 e I-14, en ambos modos: el responsable es el dueño
        // del chaco, así que la guía es la misma.
        listeningHint: 'Diga chaco, superficie, producto y cantidad',
        example: '«En el chaco Norte, tres hectáreas, dos litros de herbicida»',
        engineHint:
            'Hable por frases cortas y pulse «Terminar» al acabar. Lo dictado '
            'aparece en los pasos 1 y 2.',
        onClose: () => setState(() => showVoice = false),
        // Sólo en la compilación de diagnóstico: política B, comparar pistas
        // y lo que propuso cada motor (ruta por frases).
        diagnostics: voiceDiagnosticsBuild && _voiceTarget.catalog != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const VoicePolicyBSwitch(),
                  VoiceContextExperimentSwitch(
                    domainHints: () =>
                        voiceDomainContextHints(_voiceTarget.catalog!),
                  ),
                  VoiceProposalsButton(describe: (_) => const []),
                ],
              )
            : null,
      );
    }
    return FutureBuilder<_ApplicationCatalogs>(
      future: catalogs,
      builder: (context, snapshot) {
        final voiceBlock = voice?.blocksSave ?? false;
        final blocked =
            saving ||
            voiceBlock ||
            !snapshot.hasData ||
            modeChangedSince(loadedMode, ref.watch(operationModeProvider));
        return BottomPanel(
          children: [
            if (voiceBlock)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.rule, size: 18, color: AgroColors.caution),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        voice!.saveBlockReason!,
                        key: const Key('voz-bloqueo-guardar'),
                        style: AgroText.detail.copyWith(
                          color: AgroColors.warnInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (step == _ApplicationStep.review)
              PrimaryActionButton(
                key: const Key('application-confirm'),
                label: saving ? 'Guardando…' : 'Confirmar aplicación',
                icon: Icons.check,
                iconFirst: true,
                busy: saving,
                onPressed: blocked ? null : () => submit(snapshot.data!),
              )
            else
              PrimaryActionButton(
                key: const Key('application-continue'),
                label: 'Continuar',
                onPressed: blocked ? null : _continue,
              ),
          ],
        );
      },
    );
  }

  Map<String, Object?>? _person(_ApplicationCatalogs data) =>
      data.people.where((p) => p['id'] == personId).firstOrNull;

  Map<String, Object?>? _farm(_ApplicationCatalogs data) =>
      data.farms.where((f) => f['id'] == farmId).firstOrNull;

  /// «Hoy, 12/11/2026» o la fecha a secas.
  static String _dayLabel(String day) => day == localDay(DateTime.now())
      ? 'Hoy, ${formatDate(day)}'
      : formatDate(day);

  /// Pasos 1 y 2: el aviso del último dictado o el botón que abre el panel.
  /// Con el panel abierto no se muestra nada aquí (el panel va abajo). Con
  /// un plan no hay voz.
  List<Widget> _voiceEntry() {
    if (!_voiceStep || showVoice) return const [];
    if (voice != null && _voiceBanner) {
      return [
        VoiceResultBanner(
          dictation: voice!,
          onDictateMore: saving ? null : _openVoice,
          onDismiss: () => setState(() => _voiceBanner = false),
        ),
        const SizedBox(height: 12),
      ];
    }
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          key: const Key('aplicacion-completar-voz'),
          icon: Icons.mic_none_outlined,
          label: 'Completar por voz',
          onPressed: saving ? null : _openVoice,
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Fila de sólo lectura (persona y chaco de un plan, el titular en
  /// propio): sin flecha, porque no se elige.
  static Widget _fixedRow(Key key, String label, String value) => ValueRow(
    key: key,
    label: label,
    value: value,
    onTap: null,
    trailing: const SizedBox.shrink(),
  );

  List<Widget> _whoStep(BuildContext context, _ApplicationCatalogs data) {
    final person = _person(data);
    final farms = data.farms
        .where((f) => personId == null || f['owner_person_id'] == personId)
        .toList();
    final farm = _farm(data);
    return [
      Semantics(
        header: true,
        child: const Text('¿Dónde aplicó?', style: AgroText.h1),
      ),
      const SizedBox(height: 12),
      ..._voiceEntry(),
      AgroGroup(
        children: [
          // Con un plan, persona y chaco son los del plan: se muestran, no se
          // eligen. Antes cambiar de persona vaciaba las cantidades previstas
          // y el chaco, pero la aplicación seguía vinculada al plan (revisión
          // cruzada X01); el área exacta del plan tampoco debe sobrescribirse.
          if (widget.planId != null) ...[
            _fixedRow(
              const Key('application-plan-person'),
              'Persona del plan',
              person?['name']?.toString() ?? '',
            ),
            _fixedRow(
              const Key('application-plan-farm'),
              'Chaco del plan',
              farm?['name']?.toString() ?? '',
            ),
          ] else if (personalMode)
            // Modo individual (lámina I-20): no se pregunta de quién son los
            // productos ni quién aplicó; el titular se aplica por dentro y el
            // repositorio lo vuelve a exigir al guardar.
            ...const <Widget>[]
          else
            // En compartido se elige a la persona responsable del chaco: se
            // usan sus existencias y se le aplica su forma de cobro (no se
            // registra a quien hizo el trabajo). Rótulo decidido por el autor
            // el 2026-11-12: [applicationPersonLabel].
            AdaptiveEntityPicker<Map<String, Object?>>(
              rowStyle: true,
              label: applicationPersonLabel,
              hint: 'Responsable del chaco · se usan sus productos',
              hintKey: const Key('application-person-hint'),
              items: data.people,
              value: person,
              labelOf: (p) => p['name'] as String,
              secondaryOf: (p) => personRoleLabel(p['role']),
              onChanged: selectPerson,
              // Sólo en compartido (aquí nunca es propio ni de un plan), con
              // la regla de Catálogos; la vuelve a comprobar el alta.
              createLabel: 'Agregar persona',
              onCreate: _createPerson,
            ),
          if (widget.planId == null)
            AdaptiveEntityPicker<Map<String, Object?>>(
              rowStyle: true,
              label: 'Chaco',
              items: farms,
              value: farm,
              labelOf: (f) => f['name'] as String,
              secondaryOf: (f) => formatHectares(f['area_m2'] as int),
              placeholder: personId == null
                  ? 'Elija primero la persona'
                  : 'Elegir',
              onChanged: (f) async {
                await selectFarm(f);
                voice?.reconcile(_voiceTarget.snapshot());
              },
              enabled: personId != null,
              createLabel: 'Crear chaco',
              onCreate: _createFarm,
              badge: VoiceMarkBadge(
                dictation: voice,
                slot: const SlotRef.header('farm'),
                current: farmId,
              ),
            ),
          ValueRow(
            key: const Key('application-date'),
            label: 'Fecha',
            value: _dayLabel(effectiveDay),
            onTap: saving ? null : _pickDate,
          ),
        ],
      ),
      if (widget.planId == null) ...[
        VoiceSlotMark(
          dictation: voice,
          slot: const SlotRef.header('farm'),
          current: farmId,
          currentDisplay: farm?['name']?.toString(),
          showMark: false,
        ),
        VoiceSlotMark(
          dictation: voice,
          slot: const SlotRef.header('plan'),
          current: null,
          showMark: false,
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        key: const Key('application-area'),
        controller: area,
        onChanged: (_) {
          setState(() {
            dirty = true;
            areaError = null;
          });
          voice?.reconcile(_voiceTarget.snapshot());
        },
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: AgroText.input,
        decoration: InputDecoration(
          // Superficie TRATADA, distinta de la del chaco (que dice la ayuda).
          // La lámina I-20 la llama «Superficie tratada».
          labelText: personalMode ? 'Superficie tratada' : 'Área tratada',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixText: 'ha',
          suffixStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AgroColors.muted,
          ),
          helperText: farm == null
              ? 'Se toma del chaco; puede cambiarla.'
              : 'El chaco tiene ${formatHectares(farm['area_m2'] as int)}; '
                    'puede cambiarla.',
          helperMaxLines: 2,
          errorText: areaError,
          errorMaxLines: 3,
        ),
      ),
      VoiceSlotMark(
        dictation: voice,
        slot: const SlotRef.header('area'),
        current: _ApplicationVoice._areaCanon(area.text),
        currentDisplay: area.text,
      ),
      if (lines.isNotEmpty && voice != null && !voice!.busy)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Productos en la mezcla: ${lines.length} (paso 2).',
            key: const Key('aplicacion-lineas-paso2'),
            style: AgroText.detail,
          ),
        ),
    ];
  }

  List<Widget> _productsStep(BuildContext context, _ApplicationCatalogs data) {
    final addable = _addable;
    final person = _person(data);
    final farm = _farm(data);
    final summary = [
      if (farm != null) farm['name'].toString(),
      if (_areaM2 > 0)
        personalMode
            ? '${formatHectares(_areaM2)} tratadas'
            : formatHectares(_areaM2),
      // Modo individual: todo es del titular; no se repite su nombre.
      if (person != null && !personalMode) person['name'].toString(),
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
      ..._voiceEntry(),
      Row(
        children: [
          Expanded(
            child: Text('Productos (${lines.length})', style: AgroText.h2),
          ),
          if (loadingStock)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (stocks.isEmpty && !loadingStock) ...[
        NoticeBox(
          key: const Key('application-no-stock'),
          icon: Icons.inventory_2_outlined,
          text:
              '${personalMode ? 'El titular' : 'Esta persona'} no tiene '
              'productos en existencia. Registre primero la compra.',
        ),
        const SizedBox(height: 10),
      ],
      for (final line in lines)
        _LineCard(
          key: ObjectKey(line),
          voice: voice,
          line: line,
          theoretical: theoretical(line),
          doseError: doseError(line),
          onEdit: saving ? null : () => _editLine(line),
          onRemove: saving ? null : () => _removeLine(line),
          onToggleDetail: () =>
              setState(() => line.showDetail = !line.showDetail),
          onDoseChanged: () => setState(() => dirty = true),
        ),
      // Una sola acción agrega, y abre un recorrido con confirmación.
      DashedAddButton(
        key: const Key('application-add-product'),
        label: lines.isEmpty ? 'Añadir producto' : 'Añadir otro producto',
        onPressed: saving || loadingStock || addable.isEmpty
            ? null
            : _addProduct,
      ),
      if (addable.isEmpty && lines.isNotEmpty && stocks.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Todos los productos en existencia ya están en la mezcla.',
            style: AgroText.detail,
          ),
        ),
      const SizedBox(height: 12),
      if (!loadingStock) ..._withoutStock(context),
    ];
  }

  /// Por qué un producto del catálogo no se puede elegir: la persona no
  /// tiene existencias de él (antes sólo faltaba en la lista, sin decir
  /// por qué). Con «Registrar compra» se compra sin perder la aplicación.
  List<Widget> _withoutStock(BuildContext context) {
    final data = _latestCatalogs;
    final inStock = {for (final row in stocks) row['product_id']};
    final missing = [
      for (final product in data?.products ?? const <Map<String, Object?>>[])
        if (!inStock.contains(product['id'])) product['name'].toString(),
    ];
    final person = data == null ? null : _person(data);
    final who = personalMode
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
      onPressed: saving ? null : _registerPurchase,
      icon: const Icon(Icons.shopping_cart_outlined),
      label: const Text('Registrar compra'),
    );
    if (missing.isEmpty) {
      return [Align(alignment: Alignment.centerLeft, child: register)];
    }
    return [
      _KeyedNotice(
        textKey: const Key('application-without-stock'),
        text:
            'Sin existencias de $who: ${missing.join(', ')}. '
            '${missing.length == 1 ? 'No aparece' : 'No aparecen'} en '
            '«Añadir producto» hasta que se registre una compra para $who.',
        action: register,
      ),
    ];
  }

  /// Cargo que corresponde a la persona según su política de cobro
  /// (`persons.settlement_policy`, la misma que lee `confirmApplication`).
  /// Sólo se describe: cómo se calcula y se escribe el cargo no cambia aquí.
  String _chargeText(
    Map<String, Object?>? person,
    int totalCost, {
    String? farmName,
  }) {
    final name = person?['name']?.toString() ?? '';
    final policy = person?['settlement_policy'];
    // Modo individual (lámina I-22): es costo propio del chaco, no una
    // deuda. Con cobro por consumo el repositorio lo sigue anotando como
    // registro (E-15), y se dice.
    if (personalMode) {
      final farm = (farmName == null || farmName.isEmpty)
          ? 'este chaco'
          : farmName;
      final usage = policy == 'BY_ACTUAL_USAGE'
          ? ' Queda anotado como consumo propio.'
          : '';
      return 'Se suma a los costos de $farm en esta campaña. '
          'No es una deuda.$usage';
    }
    // E-15 (decisión del autor del 2026-10-27, §B.2): para el titular es
    // costo propio en las dos modalidades y con cualquier política. Con
    // cobro por consumo el repositorio sigue anotando el cargo en su cuenta,
    // como registro y no como deuda.
    if (person != null && person['id'] == ownerPersonId) {
      return policy == 'BY_ACTUAL_USAGE'
          ? 'Costo propio: ${formatBob(totalCost)} (queda anotado en la '
                'cuenta de $name)'
          : 'Costo propio: ${formatBob(totalCost)}';
    }
    return switch (policy) {
      'BY_ACTUAL_USAGE' => 'Se cargará a $name: ${formatBob(totalCost)}',
      // E-15 / M-7: no se afirma que pagó ni que se le cargó: el producto
      // pudo llegarle por transferencia (RN-35) o con otra política.
      'BY_PURCHASE_ALLOCATION' =>
        'Esta aplicación no genera cargo a $name: su política cobra al '
            'asignar compras.',
      _ => 'No genera cargo automático: la cuenta de $name se ajusta a mano',
    };
  }

  /// «Hoy · superficie tratada: 1 ha de 3 ha» (lámina I-22). Sin superficie
  /// del chaco registrada, sólo la tratada.
  String _personalReviewSubtitle(Map<String, Object?>? farm) {
    final total = farm?['area_m2'];
    final of = total is int && total > 0 ? ' de ${formatHectares(total)}' : '';
    return '${_dayLabel(effectiveDay)} · superficie tratada: '
        '${formatHectares(_areaM2)}$of';
  }

  List<Widget> _reviewStep(BuildContext context, _ApplicationCatalogs data) {
    final person = _person(data);
    final farm = _farm(data);
    final totalCost = lines.fold<int>(0, (sum, line) => sum + line.cost);
    const divider = Divider(height: 1, color: AgroColors.line);
    return [
      Semantics(
        header: true,
        child: const Text('Revise y confirme', style: AgroText.h1),
      ),
      const SizedBox(height: 12),
      // Aviso de lote vencido, antes del resumen: se ve antes de confirmar.
      if (loadingPreview)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else
        ApplicationExpiryNotice(
          uses: expiringLotUses(
            applicationDay: effectiveDay,
            lines: [
              for (final line in lines)
                (
                  productName: line.product['product_name'].toString(),
                  unit: line.unit,
                  lots: lotPreview[line.product['product_id']] ?? const [],
                ),
            ],
          ),
          applicationDay: effectiveDay,
          isToday: effectiveDay == localDay(DateTime.now()),
        ),
      Card(
        key: const Key('application-review'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modo individual (lámina I-22): el chaco y, debajo, el día y
              // la superficie tratada frente a la del chaco (no se confunden).
              Text(
                personalMode
                    ? '${farm?['name'] ?? ''}'
                    : '${farm?['name'] ?? ''} · '
                          '${formatHectares(_areaM2)} tratadas',
                key: const Key('application-review-farm'),
                style: AgroText.value,
              ),
              Text(
                personalMode
                    ? _personalReviewSubtitle(farm)
                    : '${person?['name'] ?? ''} · ${_dayLabel(effectiveDay)}',
                key: const Key('application-review-person'),
                style: AgroText.detail,
              ),
              const SizedBox(height: 12),
              divider,
              const SizedBox(height: 8),
              if (personalMode)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'SALE DE SU ALMACÉN',
                    key: Key('application-review-from-store'),
                    style: AgroText.label,
                  ),
                ),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AmountAside(
                    amount: formatBob(line.cost),
                    amountKey: Key('application-review-cost-${line.keyId}'),
                    amountStyle: AgroText.amount.copyWith(fontSize: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${line.product['product_name']} · '
                          '${formatQuantity(line.quantityBase, line.unit)}',
                          style: const TextStyle(
                            fontSize: 16,
                            height: 22 / 16,
                            fontWeight: FontWeight.w500,
                            color: AgroColors.ink,
                          ),
                        ),
                        // Lámina I-22: lo que tiene y lo que le quedará.
                        if (personalMode && line.quantityBase <= line.available)
                          Text(
                            'Tiene ${formatQuantity(line.available, line.unit)}'
                            ' · le quedarán ${formatQuantity(line.available - line.quantityBase, line.unit)}',
                            key: Key(
                              'application-review-remaining-${line.keyId}',
                            ),
                            style: AgroText.detail,
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              divider,
              const SizedBox(height: 4),
              // Lo que cuesta y lo que se cobra son dos cosas (B-06): el
              // costo sale de las compras que se irán usando; el cargo, de la
              // política de la persona. Se muestran por separado. Cómo se
              // calcula el costo va en una ayuda breve que se abre a pedido
              // (2026-11-05), para que el resumen se lea de un vistazo.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Costo estimado',
                        style: TextStyle(
                          fontSize: 15,
                          height: 20 / 15,
                          color: AgroColors.muted,
                        ),
                      ),
                      IconButton(
                        key: const Key('application-cost-help'),
                        tooltip: '¿Cómo se calcula el costo?',
                        isSelected: showCostHelp,
                        color: AgroColors.muted,
                        icon: const Icon(Icons.help_outline),
                        selectedIcon: const Icon(Icons.help),
                        onPressed: () => setState(() {
                          showCostHelp = !showCostHelp;
                        }),
                      ),
                    ],
                  ),
                  Text(
                    formatBob(totalCost),
                    key: const Key('application-review-cost'),
                    style: AgroText.total,
                  ),
                ],
              ),
              if (showCostHelp)
                Text(
                  'Se calcula con el precio de las compras de '
                  '${personalMode ? 'el titular' : 'esta persona'} que se '
                  'irán usando, las más antiguas primero. Cada producto '
                  'cuesta la cantidad usada por el precio de su compra; si '
                  'una compra no alcanza, se sigue con la siguiente. Es una '
                  'estimación: el costo final se fija al confirmar.',
                  key: const Key('application-cost-help-text'),
                  style: AgroText.detail,
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      _KeyedNotice(
        textKey: const Key('application-review-charge'),
        text: _chargeText(
          person,
          totalCost,
          farmName: farm?['name']?.toString(),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          // Sin las líneas que ExpansionTile dibuja al abrirse.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('application-notes'),
            title: const Text(
              'Notas (opcional)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AgroColors.ink,
              ),
            ),
            iconColor: AgroColors.ink,
            collapsedIconColor: AgroColors.muted,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
      ),
    ];
  }
}

/// Aviso informativo con su texto identificable (las pruebas y la
/// accesibilidad leen el texto por su clave), con el estilo de [NoticeBox].
class _KeyedNotice extends StatelessWidget {
  const _KeyedNotice({required this.textKey, required this.text, this.action});
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

/// Área en m² escrita en hectáreas para el campo editable. Un entero de m²
/// tiene a lo sumo cuatro decimales en hectáreas, así que con cuatro el texto
/// es exacto: 10001 m² se muestra «1,0001» y se relee 10001; con tres se
/// mostraba «1» y se guardaban 10000. Sólo para el área: dinero, dosis y
/// cantidades conservan su formato.
String _areaInput(int areaM2) => formatForInput(areaM2 / 10000, maxDecimals: 4);

class _ApplicationLineEditor {
  _ApplicationLineEditor(
    this.product, {
    required this.quantityBase,
    required this.id,
  });

  /// Identificador estable (no la posición), para el dictado.
  final int id;
  Map<String, Object?> product;

  /// Sufijo de las claves de la tarjeta: el producto, o el id si la línea
  /// dictada aún no tiene producto (dos así no comparten clave).
  String get keyId => product['product_id']?.toString() ?? 'voz-$id';

  /// Cantidad realmente usada, en la unidad base del producto.
  int quantityBase;
  final dose = TextEditingController();
  int cost = 0;

  /// «Dosis y costo» abierto en la tarjeta (sólo presentación).
  bool showDetail = false;
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
  const _ProductSheet({
    required this.options,
    this.initial,
    this.initialQuantityBase,
  });

  /// Cantidad ya escrita sin producto (línea dictada «por elegir»).
  final int? initialQuantityBase;

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

  /// Lo que pide el usuario por encima de lo que hay (E-08): con ese texto
  /// la hoja no deja agregar ni guardar. Es sólo la primera barrera: la
  /// validación definitiva sigue en `confirmApplication`, dentro de su
  /// transacción, por si las existencias cambian entre medio.
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
    // Nada entra en la mezcla por encima de lo disponible.
    if (_insufficient != null) return;
    Navigator.pop(context, _LineInput(chosen, base));
  }

  @override
  Widget build(BuildContext context) {
    final unit = product?['unit']?.toString();
    final available = product?['available_base'] as int?;
    final insufficient = _insufficient;
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
              // Sin autoselección: elegir es un acto explícito aunque quede
              // una sola opción (piloto X01).
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
                  // Disponible y pedido, con unidades, como error del propio
                  // campo; el botón de abajo queda deshabilitado a la vez.
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

/// Tarjeta de un producto de la mezcla: producto, lo que hay y lo que
/// quedará, y la cantidad usada en grande; «Editar», «Dosis y costo» y
/// quitar. La dosis, el teórico y el costo estimado se abren a pedido.
class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.theoretical,
    required this.doseError,
    required this.onEdit,
    required this.onRemove,
    required this.onToggleDetail,
    required this.onDoseChanged,
    this.voice,
  });
  final _ApplicationLineEditor line;

  /// Dictado del formulario (marcas y revisiones de esta línea).
  final VoiceFormDictation<dynamic>? voice;

  /// Cantidad teórica por dosis y área, o `null` sin dosis.
  final int? theoretical;
  final String? doseError;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback onToggleDetail;
  final VoidCallback onDoseChanged;

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
                      // Una proyección negativa se pintaba en color normal,
                      // mientras `/inventario` sí resalta en rojo las
                      // negativas (UIBUG-044). Además del color, dice
                      // «faltan».
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
                      controller: line.dose,
                      onChanged: (_) => onDoseChanged(),
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
