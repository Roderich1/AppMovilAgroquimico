import 'dart:io';

import 'package:flutter/material.dart';

import '../bench/bench_controller.dart';
import '../bench/bench_export.dart';
import '../bench/bench_platform.dart';
import '../bench/corpus.dart';
import '../port/speech_transcription_port.dart';

/// Pantalla única del banco de pruebas.
///
/// Está pensada para que una persona pueda instalar, hablar y anotar sin
/// conocer el proyecto. Todo lo que el informe necesita está a la vista: motor,
/// modelo, locale pedido y locale realmente usado, estado, parciales, final,
/// código de error, latencias, duración y memoria.
class BenchScreen extends StatefulWidget {
  const BenchScreen({
    required this.controller,
    required this.platform,
    super.key,
  });

  final BenchController controller;
  final BenchPlatform platform;

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> with WidgetsBindingObserver {
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.refreshAvailability(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChanged);
    _notes.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al perder el foco (llamada, bloqueo, cambio de app) se cancela y se suelta
    // el micrófono. Es la regla de `EVO-009-REQ-005` y aquí se ejercita de
    // verdad para poder medirla en el teléfono.
    if (state != AppLifecycleState.resumed) {
      widget.controller.cancel();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final sample = c.current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banco de voz · EVOLUTION-3'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                c.engineLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _availabilityCard(c),
            const SizedBox(height: 12),
            _controlsCard(c),
            const SizedBox(height: 12),
            if (sample != null) _sampleCard(c, sample),
            const SizedBox(height: 12),
            _transcriptCard(c),
            const SizedBox(height: 12),
            _metricsCard(c),
            const SizedBox(height: 12),
            _exportCard(c),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ tarjetas

  Widget _availabilityCard(BenchController c) {
    final a = c.availability;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Disponibilidad del motor',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: c.refreshAvailability,
                  child: const Text('Comprobar'),
                ),
              ],
            ),
            if (a == null)
              const Text('Sin comprobar todavía.')
            else ...[
              _kv('Reconocimiento disponible', a.available ? 'sí' : 'NO'),
              _kv('Funciona sin Internet', a.onDeviceAvailable ? 'sí' : 'NO'),
              _kv('Necesita red', a.requiresNetwork ? 'sí' : 'no'),
              _kv('Locale solicitado', a.requestedLocale),
              _kv('Locale utilizado', a.effectiveLocale ?? 'NO DISPONIBLE'),
              _kv(
                'Idiomas instalados',
                a.installedLocales.isEmpty
                    ? 'ninguno'
                    : a.installedLocales.join(', '),
              ),
              _kv('Modelo', a.modelName ?? '(no aplica)'),
              if (a.detail != null) _kv('Detalle', a.detail!),
              if (a.localeIsFallback)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  color: Colors.amber.shade100,
                  child: Text(
                    'El motor NO usa ${a.requestedLocale}. Escucha en '
                    '${a.effectiveLocale}. Anótelo en el resultado.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _controlsCard(BenchController c) {
    final busy =
        c.state == TranscriptionState.listening ||
        c.state == TranscriptionState.processing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Corpus: '),
                DropdownButton<String>(
                  value: c.split,
                  onChanged: (v) => v == null ? null : c.setSplit(v),
                  items: const [
                    DropdownMenuItem(value: 'ajuste', child: Text('ajuste')),
                    DropdownMenuItem(
                      value: 'aceptacion',
                      child: Text('aceptación'),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                const Text('Locale: '),
                DropdownButton<String>(
                  value: c.requestedLocale,
                  onChanged: (v) => v == null ? null : c.setLocale(v),
                  items: const [
                    DropdownMenuItem(value: 'es-BO', child: Text('es-BO')),
                    DropdownMenuItem(value: 'es-ES', child: Text('es-ES')),
                    DropdownMenuItem(value: 'es-US', child: Text('es-US')),
                  ],
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Estoy en MODO AVIÓN'),
              subtitle: const Text('Marca cada resultado como prueba offline.'),
              value: c.airplaneMode,
              onChanged: c.setAirplaneMode,
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : c.start,
                  icon: const Icon(Icons.mic),
                  label: const Text('Grabar'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? c.stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Detener'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? c.cancel : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                ),
                TextButton.icon(
                  onPressed: c.repeat,
                  icon: const Icon(Icons.replay),
                  label: const Text('Repetir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sampleCard(BenchController c, CorpusSample sample) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Frase ${sample.id}  ·  ${c.position} de ${c.total}'
                    '  ·  medidas ${c.measured}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              sample.text,
              style: const TextStyle(fontSize: 20, height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              'intención: ${sample.intent}  ·  esperado: ${sample.expected}'
              '  ·  condiciones: ${sample.conditions.join(", ")}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (sample.hasBlockingAmbiguity)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Esta frase tiene un dato que NO debe adivinarse.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: c.previous,
                  child: const Text('Anterior'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: c.next,
                  child: const Text('Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transcriptCard(BenchController c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Estado', c.state.name),
            if (c.errorCode != null)
              _kv('ERROR', '${c.errorCode} · ${c.errorDetail ?? ""}'),
            const SizedBox(height: 8),
            const Text(
              'Parcial',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(c.partialText.isEmpty ? '—' : c.partialText),
            const SizedBox(height: 8),
            const Text('Final', style: TextStyle(fontWeight: FontWeight.w600)),
            SelectableText(c.finalText.isEmpty ? '—' : c.finalText),
          ],
        ),
      ),
    );
  }

  Widget _metricsCard(BenchController c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Latencia primer parcial', _ms(c.partialLatencyMs)),
            _kv('Latencia resultado final', _ms(c.finalLatencyMs)),
            _kv('Duración del audio', _ms(c.audioDurationMs)),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Observación de esta frase (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await c.record(
                  notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                );
                _notes.clear();
                c.next();
              },
              icon: const Icon(Icons.save),
              label: const Text('Guardar medición y pasar a la siguiente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportCard(BenchController c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultados guardados: ${c.results.length}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir las transcripciones'),
              subtitle: const Text(
                'Desactívelo si dictó datos reales: se exporta sin el texto.',
              ),
              value: c.includeTranscripts,
              onChanged: c.setIncludeTranscripts,
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _export(c, json: true),
                  child: const Text('Exportar JSON'),
                ),
                FilledButton(
                  onPressed: () => _export(c, json: false),
                  child: const Text('Exportar CSV'),
                ),
                TextButton(
                  onPressed: c.clearResults,
                  child: const Text('Borrar mediciones'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ acciones

  Future<void> _export(BenchController c, {required bool json}) async {
    // El messenger se toma ANTES del await: usar `context` después de un hueco
    // asíncrono es exactamente el defecto que el lint señala.
    final messenger = ScaffoldMessenger.of(context);
    final dir = await widget.platform.exportDirectory();
    if (dir == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la carpeta.')),
      );
      return;
    }
    final run = c.buildRun();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final name = 'voicebench_${run.engine}_$stamp.${json ? "json" : "csv"}';
    final file = File('$dir/$name');
    await file.writeAsString(
      json ? BenchExport.toJsonString(run) : BenchExport.toCsv(run),
    );
    messenger.showSnackBar(SnackBar(content: Text('Guardado: ${file.path}')));
  }

  Widget _kv(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 190, child: Text('$key:')),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  static String _ms(int? value) => value == null ? 'NOT_MEASURED' : '$value ms';
}
