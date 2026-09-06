/// Orquestación de la exportación de reportes (Lote G).
///
/// Es el único punto donde se juntan las cuatro responsabilidades, y las
/// mantiene separadas:
///
/// ```text
/// repositorio (typed reads) -> compositor -> generador -> almacenamiento
/// ```
///
/// Sólo lee. No abre transacciones, no escribe en SQLite y no toca el
/// respaldo. Si algo falla o se cancela, no queda archivo final ni cambio
/// alguno en la base (`EVO-005-REQ-006`, `EVO-006-REQ-004`, `EVO-006-REQ-005`).
library;

import 'dart:typed_data';

import '../../data/agro_repository.dart';
import '../../data/typed_reads.dart';
import '../../domain/reports/report_composer.dart';
import '../../domain/reports/report_table.dart';
import 'csv_report_generator.dart';
import 'pdf_report_generator.dart';
import 'report_storage.dart';

/// Formatos de salida disponibles.
enum ReportFormat { csv, pdf }

extension ReportFormatInfo on ReportFormat {
  String get label => switch (this) {
    ReportFormat.csv => 'CSV',
    ReportFormat.pdf => 'PDF',
  };

  String get extension => switch (this) {
    ReportFormat.csv => 'csv',
    ReportFormat.pdf => 'pdf',
  };

  String get description => switch (this) {
    ReportFormat.csv => 'Para abrir en una hoja de cálculo.',
    ReportFormat.pdf => 'Para imprimir o archivar.',
  };
}

/// Qué reporte, con qué filtros y en qué formato.
class ReportRequest {
  const ReportRequest({
    required this.kind,
    required this.format,
    this.campaignId,
    this.personId,
  });

  final ReportKind kind;
  final ReportFormat format;

  /// `null` significa "todas las campañas" en los reportes que lo admiten.
  final int? campaignId;
  final int? personId;
}

/// Un filtro pedido no existe en la base.
///
/// Se lanza **antes** de leer datos o generar nada: pedir la campaña 7 cuando
/// no hay campaña 7 no puede acabar en un archivo vacío que parezca un reporte
/// legítimo.
class ReportFilterException implements Exception {
  const ReportFilterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// El usuario canceló la exportación.
class ReportCancelledException implements Exception {
  const ReportCancelledException();
  @override
  String toString() => 'Exportación cancelada.';
}

/// Señal de cancelación cooperativa.
///
/// No interrumpe una operación a medias: se comprueba entre etapas, de modo que
/// cancelar nunca deja un archivo final ni un temporal.
class ReportCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ReportCancelledException();
  }
}

class ReportExportService {
  ReportExportService(
    this._repository,
    this._storage, {
    ReportComposer composer = const ReportComposer(),
    CsvReportGenerator csv = const CsvReportGenerator(),
    PdfReportGenerator pdf = const PdfReportGenerator(),
    DateTime Function() clock = DateTime.now,
  }) : _composer = composer,
       _csv = csv,
       _pdf = pdf,
       _clock = clock;

  final AgroRepository _repository;
  final ReportStorage _storage;
  final ReportComposer _composer;
  final CsvReportGenerator _csv;
  final PdfReportGenerator _pdf;
  final DateTime Function() _clock;

  /// Compone el reporte pedido sin generar ni guardar nada.
  ///
  /// Existe por separado para que la pantalla pueda mostrar una vista previa o
  /// un estado vacío sin escribir en disco, y para que los tests puedan
  /// comprobar la composición sin filesystem.
  Future<ReportTable> compose(
    ReportRequest request, {
    ReportCancellation? cancellation,
  }) async {
    final generatedAt = _clock();
    final campaignName = await _resolveCampaignName(request);
    cancellation?.throwIfCancelled();

    switch (request.kind) {
      case ReportKind.inventory:
        return _composer.inventory(
          generatedAt: generatedAt,
          lines: await _repository.inventorySummaryTyped(),
        );

      case ReportKind.productCost:
        return _composer.productCost(
          generatedAt: generatedAt,
          campaignName: campaignName,
          lines: await _repository.productCostReportTyped(
            campaignId: request.campaignId,
          ),
        );

      case ReportKind.farmCost:
        return _composer.farmCost(
          generatedAt: generatedAt,
          campaignName: campaignName,
          lines: await _repository.farmCostReportTyped(
            campaignId: request.campaignId,
          ),
        );

      case ReportKind.campaignSummary:
        final campaignId = request.campaignId;
        if (campaignId == null) {
          throw const ReportFilterException(
            'El resumen de campaña necesita una campaña.',
          );
        }
        return _composer.campaignSummary(
          generatedAt: generatedAt,
          campaignName: campaignName!,
          summary: await _repository.campaignCloseSummaryTyped(campaignId),
        );

      case ReportKind.accountStatement:
        final personId = request.personId;
        if (personId == null) {
          throw const ReportFilterException(
            'El estado de cuenta necesita una persona.',
          );
        }
        final person = (await _repository.peopleTyped())
            .where((row) => row.id == personId)
            .firstOrNull;
        if (person == null) {
          throw const ReportFilterException('La persona elegida ya no existe.');
        }
        final campaignId = request.campaignId;
        return _composer.accountStatement(
          generatedAt: generatedAt,
          personName: person.name,
          campaignName: campaignName,
          campaignBalance: campaignId == null
              ? null
              : await _repository.personCampaignBalanceTyped(
                  personId,
                  campaignId,
                ),
          entries: await _repository.detailedStatementTyped(
            personId,
            campaignId: campaignId,
          ),
        );
    }
  }

  /// Compone, genera y guarda. Devuelve dónde quedó el archivo.
  Future<StoredReport> export(
    ReportRequest request, {
    ReportCancellation? cancellation,
  }) async {
    final table = await compose(request, cancellation: cancellation);
    cancellation?.throwIfCancelled();

    final Uint8List bytes = switch (request.format) {
      ReportFormat.csv => _csv.generate(table),
      ReportFormat.pdf => _pdf.generate(table),
    };
    // Última comprobación antes de tocar el disco: cancelar aquí no deja nada
    // escrito.
    cancellation?.throwIfCancelled();

    return _storage.save(
      baseName: _fileBaseName(request, table),
      extension: request.format.extension,
      bytes: bytes,
    );
  }

  /// `<reporte>-<aaaa-mm-dd>`, más la persona cuando el reporte es suyo.
  String _fileBaseName(ReportRequest request, ReportTable table) {
    final at = table.generatedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${at.year}-${two(at.month)}-${two(at.day)}';
    final person = request.kind == ReportKind.accountStatement
        ? table.filters.first.value
        : null;
    return sanitizeFileName(
      person == null
          ? '${request.kind.fileBaseName}-$stamp'
          : '${request.kind.fileBaseName}-$person-$stamp',
    );
  }

  /// Nombre de la campaña pedida, comprobando que exista.
  Future<String?> _resolveCampaignName(ReportRequest request) async {
    final campaignId = request.campaignId;
    if (campaignId == null) {
      if (request.kind.requiresCampaign) {
        throw const ReportFilterException(
          'El resumen de campaña necesita una campaña.',
        );
      }
      return null;
    }
    if (!request.kind.supportsCampaignFilter) {
      throw ReportFilterException(
        '${request.kind.label} no se filtra por campaña.',
      );
    }
    final campaign = (await _repository.campaignsTyped())
        .where((row) => row.id == campaignId)
        .firstOrNull;
    if (campaign == null) {
      throw const ReportFilterException('La campaña elegida ya no existe.');
    }
    return campaign.name;
  }
}
