import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/widgets/common.dart';
import '../port/speech_transcription_port.dart';
import '../session/voice_locale_policy.dart';
import '../session/voice_session_controller.dart';
import '../session/voice_session_state.dart';
import '../voice_providers.dart';

/// Pantalla de `EVO-009`: hablar, ver el texto y corregirlo.
///
/// ## Lo que esta pantalla NO hace
///
/// No registra una compra, un pago, una aplicación ni una transferencia. No
/// interpreta lo que se dijo, no busca productos ni personas y no escribe en la
/// base de datos. `Usar este texto` entrega **texto** y lo deja a la vista; la
/// interpretación es `EVO-010` y todavía no existe. La pantalla lo dice de forma
/// explícita, porque un usuario que dicta «compra de cincuenta litros» puede
/// creer razonablemente que algo se guardó.
///
/// ## Honestidad sobre el idioma y el modo sin conexión
///
/// Se **pide** `es-BO` y se muestra el idioma que el motor **aceptó**, que casi
/// nunca será el mismo (`ADR-002` midió que `es-BO` no existe). Del modo sin
/// conexión se muestran por separado la preferencia pedida, el modo avión del
/// aparato, si se llegó a transcribir sin red y si el dato simplemente no se
/// puede consultar. Ninguno de ellos se resume en un «funciona sin internet»
/// que sería falso en la mitad de los aparatos.
class VoiceCaptureScreen extends ConsumerStatefulWidget {
  const VoiceCaptureScreen({super.key});

  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen>
    with WidgetsBindingObserver {
  late final VoiceSessionController _session;
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = VoiceSessionController(
      port: ref.read(speechPortFactoryProvider)(),
    );
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    // Salir de la pantalla libera el micrófono y el reconocedor. No puede
    // quedar nada escuchando detrás (`EVO-009-REQ-005`).
    _session.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Segundo plano, bloqueo de pantalla, llamada entrante o cambio de
    // aplicación: en todos, el micrófono se suelta. El lado nativo hace lo mismo
    // por su cuenta, porque el proceso puede congelarse antes de llegar aquí.
    if (state != AppLifecycleState.resumed) {
      _session.handleAppPaused();
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final committed = _session.snapshot.committedText;
    // Sólo se toca el campo cuando de verdad cambió: reasignarlo en cada
    // notificación movería el cursor mientras el usuario escribe.
    if (_text.text != committed) {
      _text.value = TextEditingValue(
        text: committed,
        selection: TextSelection.collapsed(offset: committed.length),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _session.snapshot;
    final theme = Theme.of(context);
    return PageFrame(
      title: 'Ingresar datos por voz',
      subtitle: 'Dicta, revisa y corrige el texto antes de usarlo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NoticeCard(snapshot: snapshot),
          const SizedBox(height: 16),
          _MicrophoneButton(
            snapshot: snapshot,
            onStart: _session.startListening,
            onStop: _session.stopListening,
          ),
          const SizedBox(height: 12),
          _StatusPanel(snapshot: snapshot),
          const SizedBox(height: 12),
          _LocalePanel(snapshot: snapshot),
          const SizedBox(height: 12),
          _OfflinePanel(snapshot: snapshot),
          if (snapshot.errorCode != null) ...[
            const SizedBox(height: 12),
            _ErrorPanel(
              snapshot: snapshot,
              onOpenSettings: _session.openSystemSettings,
            ),
          ],
          const SizedBox(height: 16),
          _PartialPanel(snapshot: snapshot),
          const SizedBox(height: 16),
          Text(
            'Texto de la sesión',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Puedes corregirlo, borrar partes o escribir a mano. Seguir '
            'hablando añade al final y no borra tus correcciones.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('voz-campo-editable'),
            controller: _text,
            onChanged: _session.editText,
            maxLines: null,
            minLines: 4,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Aquí aparece lo que dictes. También puedes escribir.',
            ),
          ),
          const SizedBox(height: 8),
          _SegmentSummary(
            snapshot: snapshot,
            onUndo: _session.undoLastAutoAppend,
          ),
          const SizedBox(height: 16),
          _Actions(
            snapshot: snapshot,
            onContinue: _session.startListening,
            onStop: _session.stopListening,
            onRetry: _session.retry,
            onDiscard: _session.discard,
            onDeliver: _deliver,
          ),
          if (snapshot.delivered != null) ...[
            const SizedBox(height: 16),
            _DeliveredPanel(delivered: snapshot.delivered!),
          ],
        ],
      ),
    );
  }

  void _deliver() {
    final result = _session.deliver();
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Texto listo. No se registró ninguna compra, pago ni aplicación.',
        ),
      ),
    );
  }
}

/// Aviso de privacidad y permiso. Es desplazable porque lo es toda la pantalla.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.snapshot});

  final VoiceSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.privacy_tip_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Antes de empezar',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Al tocar el micrófono se te pedirá permiso para grabar. '
            'La aplicación no guarda el audio ni la transcripción: el texto '
            'vive sólo mientras esta pantalla está abierta.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Esta pantalla sólo produce texto. No registra compras, pagos ni '
            'aplicaciones, y no modifica el inventario ni las cuentas.',
          ),
          const SizedBox(height: 8),
          const Text(
            'El reconocimiento lo hace tu propio teléfono. La aplicación no '
            'envía nada a ningún servidor.',
          ),
        ],
      ),
    ),
  );
}

/// El botón grande. Es también el indicador visible de micrófono abierto.
class _MicrophoneButton extends StatelessWidget {
  const _MicrophoneButton({
    required this.snapshot,
    required this.onStart,
    required this.onStop,
  });

  final VoiceSessionSnapshot snapshot;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = snapshot.status.microphoneMayBeOpen;
    // Durante una transición no hay acción: es lo que impide la doble acción sin
    // recurrir a un booleano que pudiera quedarse colgado.
    final enabled = !snapshot.status.isTransition;
    final label = open ? 'Detener' : 'Hablar';

    return Center(
      child: Column(
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label: open
                ? 'Detener. El micrófono está escuchando.'
                : 'Hablar. Abre el micrófono.',
            child: SizedBox(
              width: 132,
              height: 132,
              child: Material(
                key: const Key('voz-boton-microfono'),
                color: open ? scheme.error : scheme.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? (open ? onStop : onStart) : null,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.5,
                    child: Icon(
                      open ? Icons.stop : Icons.mic,
                      size: 56,
                      color: open ? scheme.onError : scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (snapshot.status == VoiceSessionStatus.listening)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Micrófono abierto',
                key: Key('voz-indicador-activo'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.snapshot});

  final VoiceSessionSnapshot snapshot;

  /// Un texto por estado. La interfaz nunca deduce el mensaje de un booleano.
  static String describe(VoiceSessionStatus status) => switch (status) {
    VoiceSessionStatus.idle => 'Listo para empezar',
    VoiceSessionStatus.requestingPermission =>
      'Esperando el permiso de micrófono',
    VoiceSessionStatus.starting => 'Abriendo el micrófono',
    VoiceSessionStatus.listening => 'Escuchando',
    VoiceSessionStatus.processing => 'Procesando lo que dijiste',
    VoiceSessionStatus.preview => 'Texto listo para revisar',
    VoiceSessionStatus.stopping => 'Deteniendo',
    VoiceSessionStatus.cancelled => 'Sesión descartada',
    VoiceSessionStatus.permissionDenied => 'Permiso de micrófono denegado',
    VoiceSessionStatus.permissionPermanentlyDenied =>
      'Permiso denegado de forma permanente',
    VoiceSessionStatus.languageUnavailable =>
      'Sin español disponible en el motor',
    VoiceSessionStatus.recognizerUnavailable =>
      'Este teléfono no tiene reconocimiento de voz',
    VoiceSessionStatus.recoverableError => 'Error del motor de voz',
    VoiceSessionStatus.fatalError => 'Error del motor de voz',
  };

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.info_outline, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Estado: ${describe(snapshot.status)}',
          key: const Key('voz-estado'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

/// Idioma pedido e idioma realmente utilizado, siempre los dos.
class _LocalePanel extends StatelessWidget {
  const _LocalePanel({required this.snapshot});

  final VoiceSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final inUse = snapshot.localeInUse;
    return Column(
      key: const Key('voz-locale'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Idioma solicitado: ${snapshot.requestedLocale}'),
        Text(
          inUse == null
              ? 'Idioma utilizado: todavía no se sabe'
              : 'Idioma utilizado: $inUse',
        ),
        if (snapshot.localeIsFallback)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Tu teléfono no tiene ${snapshot.requestedLocale}. Se está '
              'escuchando en $inUse, así que algunas palabras locales pueden '
              'salir mal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Lo que se sabe —y lo que no— sobre funcionar sin conexión.
class _OfflinePanel extends StatelessWidget {
  const _OfflinePanel({required this.snapshot});

  final VoiceSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final offline = snapshot.offline;
    final lines = <String>[
      if (offline.offlineRequested)
        'Se pide al teléfono transcribir sin conexión. Es una preferencia: el '
            'sistema puede no respetarla.',
      switch (offline.airplaneMode) {
        AirplaneMode.on => 'Modo avión: activado.',
        AirplaneMode.off => 'Modo avión: desactivado.',
        AirplaneMode.unknown => 'Modo avión: no se pudo comprobar.',
      },
      if (offline.observedOffline)
        'Comprobado: aquí se transcribió con el modo avión activado.'
      else
        'Todavía no se ha comprobado que funcione sin conexión en este teléfono.',
      if (!offline.availabilityKnown)
        'Tu versión de Android no permite consultar qué idiomas hay '
            'instalados. No es que no haya: es que no se puede saber sin '
            'intentarlo.',
      if (offline.languageModelPossiblyMissing)
        'Puede faltar el paquete de idioma. La aplicación no descarga nada por '
            'su cuenta: instálalo desde los ajustes de voz de Android si lo '
            'quieres.',
    ];

    return Column(
      key: const Key('voz-offline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.snapshot, required this.onOpenSettings});

  final VoiceSessionSnapshot snapshot;
  final Future<bool> Function() onOpenSettings;

  /// Qué puede hacer el usuario ante cada fallo. Ninguno bloquea la aplicación:
  /// escribir a mano siempre queda disponible (`EVO-009-REQ-017`).
  static String advice(VoiceSessionStatus status) => switch (status) {
    VoiceSessionStatus.permissionDenied =>
      'Sin permiso de micrófono no se puede dictar. Puedes concederlo y volver '
          'a intentarlo, o escribir el texto a mano.',
    VoiceSessionStatus.permissionPermanentlyDenied =>
      'Android ya no volverá a preguntar. Abre los ajustes de la aplicación '
          'para conceder el micrófono, o escribe el texto a mano.',
    VoiceSessionStatus.languageUnavailable =>
      'Tu teléfono no tiene ningún español instalado para reconocimiento. '
          'Instálalo desde los ajustes de voz de Android, o escribe a mano.',
    VoiceSessionStatus.recognizerUnavailable =>
      'Este teléfono no ofrece reconocimiento de voz. Puedes seguir usando la '
          'aplicación y escribir el texto a mano.',
    _ =>
      'Puedes reintentar. Si sigue fallando, escribe el texto a mano: no '
          'perderás lo que ya está escrito.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('voz-error'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              advice(snapshot.status),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            if (snapshot.status ==
                VoiceSessionStatus.permissionPermanentlyDenied) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('voz-abrir-ajustes'),
                onPressed: () => onOpenSettings(),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Abrir ajustes'),
              ),
            ],
            const SizedBox(height: 8),
            // Diagnóstico: códigos, nunca lo dictado.
            Text(
              'Código: ${snapshot.errorCode?.name ?? '-'}'
              '${snapshot.errorDetail == null ? '' : ' (${snapshot.errorDetail})'}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// Texto provisional, siempre separado del texto de sesión.
class _PartialPanel extends StatelessWidget {
  const _PartialPanel({required this.snapshot});

  final VoiceSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.partialText.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('voz-parcial'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escuchando (todavía puede cambiar)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(snapshot.partialText),
        ],
      ),
    );
  }
}

class _SegmentSummary extends StatelessWidget {
  const _SegmentSummary({required this.snapshot, required this.onUndo});

  final VoiceSessionSnapshot snapshot;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Fragmentos dictados: ${snapshot.segmentCount}'
          '${snapshot.manuallyEdited ? ' · editado a mano' : ''}',
          key: const Key('voz-resumen'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (snapshot.canUndoAutoAppend)
        TextButton.icon(
          key: const Key('voz-deshacer'),
          onPressed: onUndo,
          icon: const Icon(Icons.undo),
          label: const Text('Deshacer lo último'),
        ),
    ],
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.snapshot,
    required this.onContinue,
    required this.onStop,
    required this.onRetry,
    required this.onDiscard,
    required this.onDeliver,
  });

  final VoiceSessionSnapshot snapshot;
  final Future<void> Function() onContinue;
  final Future<void> Function() onStop;
  final Future<void> Function() onRetry;
  final Future<void> Function() onDiscard;
  final VoidCallback onDeliver;

  @override
  Widget build(BuildContext context) {
    final status = snapshot.status;
    // Durante una transición todo queda deshabilitado: es la garantía de que no
    // hay doble acción posible.
    final idle = !status.isTransition;
    final open = status.microphoneMayBeOpen;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const Key('voz-seguir'),
          onPressed: idle && !open ? onContinue : null,
          icon: const Icon(Icons.mic_none),
          label: const Text('Seguir hablando'),
        ),
        OutlinedButton.icon(
          key: const Key('voz-detener'),
          onPressed: idle && open ? onStop : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Detener'),
        ),
        OutlinedButton.icon(
          key: const Key('voz-reintentar'),
          onPressed: idle && status.isProblem ? onRetry : null,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
        OutlinedButton.icon(
          key: const Key('voz-descartar'),
          onPressed: idle ? onDiscard : null,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Descartar'),
        ),
        FilledButton.tonalIcon(
          key: const Key('voz-usar'),
          onPressed: idle && snapshot.hasText ? onDeliver : null,
          icon: const Icon(Icons.check),
          label: const Text('Usar este texto'),
        ),
      ],
    );
  }
}

/// Qué pasó al entregar. Sobre todo: **qué no pasó**.
class _DeliveredPanel extends StatelessWidget {
  const _DeliveredPanel({required this.delivered});

  final VoiceSessionText delivered;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('voz-entregado'),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Texto de la sesión listo',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(delivered.text),
          const SizedBox(height: 8),
          const Text(
            'No se registró ninguna compra, pago, aplicación ni cambio de '
            'inventario. Interpretar este texto llegará en una versión '
            'posterior.',
          ),
        ],
      ),
    ),
  );
}

/// Etiqueta de la entrada en Operaciones. Se comparte con la prueba de widget
/// para que el nombre no pueda cambiar en un sitio y no en el otro.
const voiceEntryTitle = 'Ingresar datos por voz';

/// Ruta de la pantalla dentro de la sección Operaciones.
const voiceRoutePath = '/voz';

/// El locale que el producto pide, reexportado para la interfaz.
const voiceRequestedLocale = VoiceLocalePolicy.requested;
