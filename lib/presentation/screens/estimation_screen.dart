import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/estimation_copy_store.dart';
import '../../domain/estimation/farmer_estimation.dart';
import '../../domain/sync/central_references.dart';
import '../../services/estimation/estimation_api.dart';
import '../../services/estimation/estimation_providers.dart';
import '../widgets/common.dart';

/// Estimación del consumo dentro de Inventario (F12-EST-07-MOB, MOB #164;
/// prototipo M6, figura 3.25; CU-21, RF-39, RF-40, RN-30, DAT-20, INT-09).
///
/// - Al abrir sólo lee la copia descargada de este teléfono para el titular
///   vigente: no consulta al servidor por su cuenta.
/// - «Consultar con conexión» verifica el acceso y muestra lo que el servicio
///   entrega con el perfil del Agricultor (sin línea base naive, cobertura ni
///   serie: diferencia con M6, prevalece el contrato INT-09).
/// - «Descargar copia» la guarda para consultarla sin conexión.
/// - El teléfono no calcula nada, y la estimación no se suma a la necesidad
///   declarada ni al inventario.
class EstimationScreen extends ConsumerStatefulWidget {
  const EstimationScreen({super.key});

  @override
  ConsumerState<EstimationScreen> createState() => _EstimationScreenState();
}

const estimationReferenceText =
    'Es una referencia: no se suma a su necesidad declarada, no cambia su '
    'inventario y no crea compras.';
const estimationNoCopyText =
    'Sin copia descargada. No hay una estimación descargada en este teléfono: '
    'sin conexión no se muestra ninguna cifra. Para tenerla, consúltela con '
    'conexión y descárguela.';

class _EstimationScreenState extends ConsumerState<EstimationScreen> {
  late Future<List<StoredEstimationCopy>> copies;
  String? copyCampaign;

  List<CentralCampaign>? campaigns;
  String? campaignRef;
  FarmerResults? results;
  bool busy = false;
  String? note;

  /// Un rechazo o una sesión sin verificar: no se muestra ninguna cifra,
  /// tampoco la copia.
  String? blocked;

  EstimationService get _service => ref.read(estimationServiceProvider);

  @override
  void initState() {
    super.initState();
    copies = _service.readableCopies();
  }

  void _reloadCopies() {
    final next = _service.readableCopies();
    setState(() {
      copies = next;
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      busy = true;
      note = null;
    });
    try {
      await body();
    } on EstimationUnavailableException catch (error) {
      setState(() {
        switch (error.reason) {
          case EstimationUnavailable.offline:
            note =
                'Sin conexión con el sindicato: se muestra la copia descargada, '
                'si la hay.';
            campaigns = null;
            results = null;
          case EstimationUnavailable.sessionRejected:
            blocked =
                'Hace falta verificar su acceso en línea (Sincronización) antes '
                'de consultar la estimación.';
          case EstimationUnavailable.noIdentity:
            blocked =
                'La estimación sólo se consulta con la instalación activada y la '
                'sesión de su titular.';
        }
      });
    } on EstimationRejectedException catch (error) {
      setState(() {
        campaigns = error.rejection == EstimationRejection.notFound
            ? campaigns
            : null;
        results = null;
        final removed = error.discarded
            ? 'La copia descargada se borró.'
            : 'La copia descargada ya no se puede consultar; su borrado no se '
                  'completó y se reintentará.';
        final message = switch (error.rejection) {
          EstimationRejection.session =>
            'El sindicato ya no acepta esta sesión. $removed',
          EstimationRejection.permission =>
            'Su cuenta ya no tiene acceso a la estimación. $removed',
          EstimationRejection.policy =>
            'La política de divulgación todavía no permite consultar la '
                'estimación. $removed',
          EstimationRejection.notFound =>
            'Esa campaña no existe o no es de su sindicato. '
                '${error.discarded ? 'Su copia descargada se borró.' : 'Su copia ya no se puede consultar; su borrado no se completó.'}',
        };
        if (error.rejection == EstimationRejection.notFound) {
          note = message;
        } else {
          blocked = message;
        }
      });
    } on EstimationQueryException {
      setState(
        () => note = 'El sindicato no pudo responder. Inténtelo más tarde.',
      );
    } on Object catch (error) {
      setState(() => note = friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _reloadCopies();
      }
    }
  }

  Future<void> _consult() => _run(() async {
    final list = await _service.campaigns();
    setState(() {
      campaigns = list;
      if (!list.any((c) => c.ref == campaignRef)) {
        campaignRef = null;
        results = null;
      }
    });
  });

  Future<void> _select(String? ref) async {
    if (ref == null) return;
    setState(() {
      campaignRef = ref;
      results = null;
    });
    await _run(() async {
      final read = await _service.results(ref);
      if (mounted && campaignRef == ref) setState(() => results = read);
    });
  }

  Future<void> _download() async {
    final ref = campaignRef;
    if (ref == null) return;
    await _run(() async {
      final (outcome, _) = await _service.download(ref);
      setState(() {
        copyCampaign = ref;
        note = switch (outcome) {
          EstimationSaveOutcome.saved => 'Copia guardada en este teléfono.',
          EstimationSaveOutcome.keptNewer => 'Ya había una copia igual o más reciente de esta campaña: se conserva.',
          EstimationSaveOutcome.accessChanged => 'La sesión o el titular cambiaron durante la descarga: la copia no se guardó.',
          EstimationSaveOutcome.otherSubject =>
            'La respuesta no es de su cuenta o de su sindicato: no se guardó.',
        };
      });
    });
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Estimación del consumo',
    subtitle: 'Inventario · referencia para la próxima campaña comparable',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked != null)
          Card(
            key: const Key('estimation-blocked'),
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(blocked!),
            ),
          )
        else ...[
          _onlineSection(context),
          const SizedBox(height: 12),
          _copySection(context),
        ],
        if (note != null) ...[
          const SizedBox(height: 12),
          Text(note!, key: const Key('estimation-note')),
        ],
        const SizedBox(height: 12),
        const Text(estimationReferenceText, key: Key('estimation-reference')),
      ],
    ),
  );

  Widget _onlineSection(BuildContext context) {
    final list = campaigns;
    final read = results;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Con conexión',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (list == null)
              FilledButton.tonal(
                key: const Key('estimation-online'),
                onPressed: busy ? null : _consult,
                child: const Text('Consultar con conexión'),
              )
            else if (list.isEmpty)
              const Text('El sindicato no tiene campañas para consultar.')
            else
              DropdownButtonFormField<String>(
                key: const Key('estimation-campaign'),
                initialValue: campaignRef,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Campaña objetivo',
                ),
                items: [
                  for (final campaign in list)
                    DropdownMenuItem(
                      value: campaign.ref,
                      child: Text(
                        campaign.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy ? null : _select,
              ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (read != null) ...[
              const SizedBox(height: 8),
              _period(read),
              for (final result in read.results)
                _resultTile(result, atDownload: false),
              if (read.results.isEmpty)
                const Text(
                  'No hay resultados de estimación para esta campaña.',
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('estimation-download'),
                onPressed: busy ? null : _download,
                child: const Text(
                  'Descargar copia para consultar sin conexión',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _copySection(
    BuildContext context,
  ) => FutureBuilder<List<StoredEstimationCopy>>(
    future: copies,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const EmptyState(
          icon: Icons.error_outline,
          message: 'No se pudo leer la copia descargada: no se muestra ninguna cifra.',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final list = snapshot.data!;
      if (list.isEmpty) {
        return const Card(
          key: Key('estimation-no-copy'),
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text(estimationNoCopyText),
          ),
        );
      }
      final shown = list.firstWhere(
        (c) => c.download.target.campaignRef == copyCampaign,
        orElse: () => list.first,
      );
      final download = shown.download;
      return Card(
        key: Key('estimation-copy-${download.target.campaignRef}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Copia descargada en este teléfono',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (list.length > 1)
                DropdownButtonFormField<String>(
                  key: const Key('estimation-copy-campaign'),
                  initialValue: download.target.campaignRef,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Copia de la campaña',
                  ),
                  items: [
                    for (final copy in list)
                      DropdownMenuItem(
                        value: copy.download.target.campaignRef,
                        child: Text(copy.download.target.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => copyCampaign = value),
                ),
              const SizedBox(height: 8),
              Container(
                key: const Key('estimation-copy-banner'),
                padding: const EdgeInsets.all(10),
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Text(
                  'Descargada el ${estimationDate(download.downloadedAt)}. '
                  'Vigente al descargar; puede haber '
                  'cambiado: sin conexión no se conocen revocaciones, cambios '
                  'de política ni de las cifras publicadas.',
                ),
              ),
              const SizedBox(height: 8),
              _period(download),
              for (final result in download.results)
                _resultTile(result, atDownload: true),
              if (download.results.isEmpty)
                const Text(
                  'La copia no tiene resultados: ninguna cifra que mostrar.',
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _period(FarmerEstimation estimation) {
    final target = estimation.target;
    final season = estimation.season;
    final end = target.endDate == null
        ? 'sin fecha de fin'
        : estimationDay(target.endDate!);
    return Text(
      'Período objetivo: ${target.name}, desde ${estimationDay(target.startDate)} '
      'hasta $end'
      '${season == null ? '' : ' · Temporada ${season.key}: ${season.definition}'}',
      key: const Key('estimation-period'),
    );
  }

  Widget _resultTile(FarmerResult result, {required bool atDownload}) {
    final reason = result.reasonCode == null
        ? null
        : estimationReasonText[result.reasonCode];
    final validity = estimationValidityText[result.validity] ?? result.validity;
    final validityReason = result.validityReason == null
        ? null
        : estimationValidityReasonText[result.validityReason];
    return ListTile(
      key: Key(
        'estimation-result-${atDownload ? 'copy' : 'online'}-${result.productName}',
      ),
      contentPadding: EdgeInsets.zero,
      title: Text(
        result.productName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${estimationStatusText[result.status] ?? result.status}'
            '${reason == null ? '' : '. $reason'}',
          ),
          Text('Generada el ${estimationDate(result.generatedAt)}'),
          Text(
            atDownload
                ? 'Vigencia al descargar: $validity'
                      '${validityReason == null ? '' : ' ($validityReason)'}'
                : 'Vigencia: $validity'
                      '${validityReason == null ? '' : ' ($validityReason)'}',
          ),
          if (atDownload)
            const Text('Vigencia actual: desconocida sin conexión'),
        ],
      ),
      trailing: Text(
        estimationFigureText(result),
        key: Key(
          'estimation-figure-${atDownload ? 'copy' : 'online'}-${result.productName}',
        ),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Fecha y hora en el huso del teléfono.
String estimationDate(DateTime instant) {
  final local = instant.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// Día civil de una campaña (la fecha del servidor, sin cambiar de huso).
String estimationDay(DateTime instant) =>
    '${_two(instant.day)}/${_two(instant.month)}/${instant.year}';
