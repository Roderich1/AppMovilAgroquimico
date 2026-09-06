import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/read_models.dart';
import '../../domain/reports/report_composer.dart';
import '../../services/reports/report_export_service.dart';
import '../../services/reports/report_storage.dart';
import '../widgets/common.dart';

/// Selección y exportación de reportes (Lote H).
///
/// La pantalla no compone ni genera nada: elige qué pedir y se lo pasa a
/// [ReportExportService]. Los cinco reportes y los dos formatos salen de los
/// mismos enums que usa el servicio, así que no puede aparecer aquí una opción
/// que el servicio no sepa atender.
typedef _Filters = ({List<CampaignRead> campaigns, List<PersonRead> people});

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    this.initialKind,
    this.initialPersonId,
    this.initialCampaignId,
  });

  /// Permite abrir la pantalla ya situada en un reporte y con sus filtros
  /// puestos, como hace el estado de cuenta desde Liquidación.
  final ReportKind? initialKind;
  final int? initialPersonId;
  final int? initialCampaignId;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late Future<_Filters> _filters;
  late ReportKind _kind;
  ReportFormat _format = ReportFormat.pdf;
  int? _campaignId;
  int? _personId;
  bool _campaignInitialized = false;

  /// Exportación en curso. Mientras no es `null` la pantalla está ocupada y
  /// ofrece cancelar.
  ReportCancellation? _running;
  String? _location;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? ReportKind.inventory;
    _personId = widget.initialPersonId;
    if (widget.initialCampaignId != null) {
      _campaignId = widget.initialCampaignId;
      // Quien abrió la pantalla ya eligió campaña: no se sustituye por la
      // activa al terminar de cargar.
      _campaignInitialized = true;
    }
    _filters = _load();
  }

  Future<_Filters> _load() async {
    final repo = ref.read(repositoryProvider);
    final campaigns = await repo.campaignsTyped();
    final people = await repo.peopleTyped();
    if (!_campaignInitialized) {
      final active = campaigns.where((row) => row.isActive);
      _campaignId = active.isEmpty ? null : active.first.id;
      _campaignInitialized = true;
    }
    _location = await ref.read(reportStorageProvider).describeLocation();
    return (campaigns: campaigns, people: people);
  }

  /// Filtros efectivos: un reporte que no admite campaña la ignora aunque la
  /// pantalla recuerde una selección anterior.
  ReportRequest _request() => ReportRequest(
    kind: _kind,
    format: _format,
    campaignId: _kind.supportsCampaignFilter ? _campaignId : null,
    personId: _kind.requiresPerson ? _personId : null,
  );

  /// Qué falta para poder exportar, o `null` si no falta nada.
  String? _blocker() {
    if (_kind.requiresCampaign && _campaignId == null) {
      return 'Elija una campaña para el resumen de campaña.';
    }
    if (_kind.requiresPerson && _personId == null) {
      return 'Elija la persona cuyo estado de cuenta quiere exportar.';
    }
    return null;
  }

  Future<void> _export() async {
    if (_running != null) return;
    final blocker = _blocker();
    if (blocker != null) {
      showError(context, blocker);
      return;
    }
    // La advertencia de datos sensibles va ANTES de escribir el archivo, no
    // después: una vez guardado ya está en el teléfono sin cifrar
    // (09_SECURITY_AND_PRIVACY).
    final confirmed = await _confirmSensitiveData();
    if (!confirmed || !mounted) return;

    final cancellation = ReportCancellation();
    setState(() => _running = cancellation);

    StoredReport? stored;
    Object? failure;
    var wasCancelled = false;
    try {
      stored = await ref
          .read(reportExportServiceProvider)
          .export(_request(), cancellation: cancellation);
    } on ReportCancelledException {
      wasCancelled = true;
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;

    // El estado "generando" termina ANTES de dar el resultado: si no, el
    // diálogo de éxito se abría con la barra de progreso y el botón "Cancelar"
    // todavía vivos por detrás, diciendo que seguía en marcha algo que ya
    // había acabado.
    setState(() => _running = null);

    if (wasCancelled) {
      showSuccess(
        context,
        'Exportación cancelada. No se guardó ningún archivo.',
      );
      return;
    }
    if (failure != null) {
      showError(context, failure);
      return;
    }
    await _showSaved(stored!);
  }

  Future<bool> _confirmSensitiveData() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          // `scrollable` desplaza icono, título y texto juntos. En horizontal
          // y al 130 % no cabían ni las tres frases del aviso ni el armazón
          // del propio diálogo, que desbordaba 2,3 px por abajo. Un aviso de
          // consentimiento recortado deja al usuario aceptando algo que no ha
          // podido leer. Se vio en el Pixel 8.
          scrollable: true,
          title: const Row(
            children: [
              Icon(Icons.lock_open_outlined),
              SizedBox(width: 10),
              Expanded(child: Text('El archivo no va cifrado')),
            ],
          ),
          content: Text(
            'El ${_format.label} de "${_kind.label}" contiene información '
            'sensible: precios, deudas, pagos y nombres de personas.\n\n'
            'Se guarda sin cifrar en la carpeta de la aplicación. Cualquiera '
            'que abra el archivo verá esos datos.\n\n'
            'La aplicación no lo envía a ningún sitio: si lo comparte, lo '
            'hace usted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Exportar igualmente'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showSaved(StoredReport stored) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // Mismo criterio que el aviso: la ruta de destino es larga y al 130 % en
      // horizontal no cabe. Desplazarla es preferible a recortarla, porque es
      // justo el dato que el usuario necesita para encontrar el archivo.
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.check_circle_outline),
          SizedBox(width: 10),
          Expanded(child: Text('Reporte guardado')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stored.fileName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Carpeta:'),
          SelectableText(stored.directory),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Reportes',
    subtitle: 'Exporta inventario, costos y cuentas a CSV o PDF.',
    child: FutureBuilder<_Filters>(
      future: _filters,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final busy = _running != null;
        final blocker = _blocker();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle(context, 'Reporte'),
            Card(
              child: RadioGroup<ReportKind>(
                groupValue: _kind,
                // `RadioGroup` exige un manejador no nulo, así que la guarda
                // de "ocupado" va dentro: durante una exportación no se puede
                // cambiar lo que se está exportando.
                onChanged: (value) {
                  if (busy || value == null) return;
                  setState(() => _kind = value);
                },
                child: Column(
                  children: [
                    for (final kind in ReportKind.values)
                      RadioListTile<ReportKind>(
                        value: kind,
                        title: Text(kind.label),
                        subtitle: Text(kind.description),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Filtros'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (_kind.supportsCampaignFilter)
                      DropdownButtonFormField<int?>(
                        initialValue: _campaignId,
                        // Sin `isExpanded` el desplegable se dimensiona por su
                        // elemento más ancho y un nombre largo desborda el
                        // campo por la derecha. Se vio en el Pixel 8.
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _kind.requiresCampaign
                              ? 'Campaña (obligatoria)'
                              : 'Campaña',
                        ),
                        items: [
                          // El resumen de campaña no admite "todas": es un
                          // corte de un periodo contable concreto.
                          if (!_kind.requiresCampaign)
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todas las campañas'),
                            ),
                          for (final campaign in data.campaigns)
                            DropdownMenuItem<int?>(
                              value: campaign.id,
                              child: Text(
                                '${campaign.name} · '
                                '${campaignStatusLabel(campaign.status)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() => _campaignId = value),
                      )
                    else
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.all_inclusive),
                        title: Text('Inventario global'),
                        subtitle: Text(
                          'El stock es del almacén, no de una campaña.',
                        ),
                      ),
                    if (_kind.requiresPerson) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: _personId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Persona (obligatoria)',
                        ),
                        items: [
                          for (final person in data.people)
                            DropdownMenuItem<int?>(
                              value: person.id,
                              child: Text(
                                '${person.name} · '
                                '${personRoleLabel(person.role)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() => _personId = value),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Formato'),
            Card(
              child: RadioGroup<ReportFormat>(
                groupValue: _format,
                // `RadioGroup` exige un manejador no nulo, así que la guarda
                // de "ocupado" va dentro: durante una exportación no se puede
                // cambiar lo que se está exportando.
                onChanged: (value) {
                  if (busy || value == null) return;
                  setState(() => _format = value);
                },
                child: Column(
                  children: [
                    for (final format in ReportFormat.values)
                      RadioListTile<ReportFormat>(
                        value: format,
                        title: Text(format.label),
                        subtitle: Text(format.description),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_open_outlined),
                    const SizedBox(width: 10),
                    // Sin `Expanded` un aviso de dos líneas desborda la fila al
                    // 130 %, como pasaba en la cinta de campaña (UIBUG-067).
                    Expanded(
                      child: Text(
                        'El archivo contiene información sensible y NO va '
                        'cifrado. Se guarda en el teléfono; la aplicación no '
                        'lo envía a ningún sitio.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_location != null) ...[
              const SizedBox(height: 10),
              Text(
                'Se guardará en: $_location',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (blocker != null) ...[
              const SizedBox(height: 10),
              Text(
                blocker,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Text(
                'Generando ${_kind.label} en ${_format.label}…',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _running?.cancel(),
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
              ),
            ] else
              FilledButton.icon(
                onPressed: blocker != null ? null : _export,
                icon: const Icon(Icons.save_alt_outlined),
                label: Text('Exportar ${_format.label}'),
              ),
          ],
        );
      },
    ),
  );

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
