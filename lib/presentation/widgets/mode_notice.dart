import 'package:flutter/material.dart';

import '../../domain/operation_mode.dart';

/// Si la modalidad cambió después de que un formulario cargó sus opciones
/// (#26). Mientras la vigente no se conoce (`null`) no se considera cambio.
bool modeChangedSince(OperationMode? loaded, OperationMode? current) =>
    loaded != null && current != null && loaded != current;

/// Aviso de un formulario abierto cuando la modalidad cambia: sus personas y
/// chacos se eligieron con la anterior, así que se pide volver a abrirlo en
/// lugar de confirmar con opciones que ya no corresponden.
class ModeChangedNotice extends StatelessWidget {
  const ModeChangedNotice({super.key});

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('mode-changed-notice'),
    color: Theme.of(context).colorScheme.errorContainer,
    child: const Padding(
      padding: EdgeInsets.all(14),
      child: Text(
        'La modalidad de inventario cambió mientras este formulario estaba '
        'abierto. Ciérrelo y vuelva a abrirlo para continuar; no se guardó '
        'nada.',
      ),
    ),
  );
}

/// Aviso de una pantalla que sólo existe en el inventario compartido.
class SharedOnlyNotice extends StatelessWidget {
  const SharedOnlyNotice({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'En inventario propio no hay transferencias entre responsables. '
            'Las transferencias anteriores se conservan y vuelven a verse al '
            'pasar a inventario compartido en Modo de uso.',
            key: Key('shared-only-notice'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onBack,
            child: const Text('Volver a Operaciones'),
          ),
        ],
      ),
    ),
  );
}
