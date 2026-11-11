import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../data/product_photo_storage.dart';
import '../../data/sync/identification_request_store.dart';
import '../../domain/sync/identification_view.dart';
import '../../services/sync/sync_providers.dart'
    show identificationRequestStoreProvider;
import 'common.dart';
import 'identification_texts.dart' show labelPhotosNotInBackups;

/// Elige una imagen con la cámara o la galería; null si se cancela. Las
/// pruebas la sustituyen.
typedef LabelPhotoPicker = Future<String?> Function(ImageSource source);

Future<String?> _systemPicker(ImageSource source) async =>
    (await ImagePicker().pickImage(source: source))?.path;

/// «Foto de la etiqueta» de un producto (Catálogos → Productos; E1 §5.1):
/// ver, tomar o elegir, reemplazar y quitar. Funciona sin conexión. Si la
/// foto ya se compartió con el sindicato, reemplazarla pregunta si se envía
/// la nueva y quitarla deja su retiro pendiente de envío.
Future<void> showLabelPhotoSheet(
  BuildContext context, {
  required int productId,
  required String productName,
  LabelPhotoPicker picker = _systemPicker,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => LabelPhotoSheet(
    productId: productId,
    productName: productName,
    picker: picker,
  ),
);

class LabelPhotoSheet extends ConsumerStatefulWidget {
  const LabelPhotoSheet({
    super.key,
    required this.productId,
    required this.productName,
    this.picker = _systemPicker,
  });

  final int productId;
  final String productName;
  final LabelPhotoPicker picker;

  @override
  ConsumerState<LabelPhotoSheet> createState() => _LabelPhotoSheetState();
}

typedef _SheetData = ({ProductPhoto? photo, IdentificationRequest? request});

class _LabelPhotoSheetState extends ConsumerState<LabelPhotoSheet> {
  late Future<_SheetData> data;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    data = _load();
  }

  Future<_SheetData> _load() async => (
    photo: await ref.read(repositoryProvider).productPhoto(widget.productId),
    request: await ref
        .read(identificationRequestStoreProvider)
        .byProduct(widget.productId),
  );

  void _reload() {
    final next = _load();
    setState(() {
      data = next;
    });
  }

  /// Reemplazo con la foto compartida: ¿se envía también la nueva? null si
  /// se cancela (no se cambia nada).
  Future<bool?> _askShare() => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Enviar también la nueva foto al sindicato?'),
      content: Text(
        '${photoConsentText(widget.productName)}\n\n'
        'Si la deja sólo en este teléfono, el sindicato conserva la foto '
        'que ya tenía.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Sólo en este teléfono'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Enviar al sindicato'),
        ),
      ],
    ),
  );

  Future<void> _pick(ImageSource source, IdentificationRequest? request) async {
    final String? path;
    try {
      path = await widget.picker(source);
    } on Object {
      if (mounted) {
        showError(
          context,
          'No se pudo abrir la cámara o la galería. Revise '
          'los permisos.',
        );
      }
      return;
    }
    if (path == null || !mounted) return;
    bool? share;
    if (request != null && request.photoShared) {
      share = await _askShare();
      if (share == null || !mounted) return;
    }
    setState(() {
      busy = true;
    });
    try {
      await ref
          .read(repositoryProvider)
          .setProductPhoto(widget.productId, path, shareWithUnion: share);
      if (mounted) {
        showSuccess(
          context,
          share == true
              ? 'Foto guardada. Se enviará al sindicato.'
              : 'Foto guardada en este teléfono.',
        );
      }
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
    if (mounted) _reload();
  }

  Future<void> _remove(IdentificationRequest? request) async {
    // Lo mismo que decide `IdentificationRequestStore.onPhotoRemoved`: si la
    // foto pudo llegar al sindicato, su retiro queda pendiente de envío.
    final shared =
        request != null &&
        (const {
              IdentificationPhotoStatus.sent,
              IdentificationPhotoStatus.failed,
              IdentificationPhotoStatus.removePending,
            }.contains(request.photoSendStatus) ||
            (request.photoSendStatus == IdentificationPhotoStatus.pendingSend &&
                request.photoAttempts > 0));
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Quitar la foto',
      detail: shared
          ? 'Se borra la foto de la etiqueta de este teléfono y se pedirá al '
                'sindicato que la retire.'
          : 'Se borra la foto de la etiqueta de este teléfono. El producto y '
                'sus registros no cambian.',
      confirmLabel: 'Quitar',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      busy = true;
    });
    try {
      await ref.read(repositoryProvider).removeProductPhoto(widget.productId);
      if (mounted) showSuccess(context, 'Foto quitada.');
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
    if (mounted) _reload();
  }

  Future<void> _replace(IdentificationRequest? request) async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Reemplazar la foto'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ImageSource.camera),
            child: const Text('Tomar foto'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ImageSource.gallery),
            child: const Text('Elegir de la galería'),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    await _pick(source, request);
  }

  /// Qué tiene el sindicato de esta foto, sin decir «enviada» si sólo está
  /// en el teléfono.
  String? _unionNote(ProductPhoto? photo, IdentificationRequest? request) {
    if (request == null) return null;
    return switch (request.photoSendStatus) {
      IdentificationPhotoStatus.sent =>
        photo != null && photo.sha256 == request.photoSha256Consented
            ? 'El sindicato tiene esta foto.'
            : 'El sindicato conserva la foto anterior.',
      IdentificationPhotoStatus.pendingSend =>
        'Pendiente de envío al sindicato.',
      IdentificationPhotoStatus.failed =>
        request.photoRetryable
            ? 'Foto no enviada (se reintentará).'
            : 'La foto no se pudo enviar al sindicato.',
      IdentificationPhotoStatus.removePending =>
        'Retiro de la foto pendiente de envío al sindicato.',
      IdentificationPhotoStatus.removed => 'Foto retirada del sindicato.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FutureBuilder<_SheetData>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(friendlyError(snapshot.error!));
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final photo = snapshot.data!.photo;
          final request = snapshot.data!.request;
          final note = _unionNote(photo, request);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Foto de la etiqueta',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(widget.productName),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (photo == null)
                const Text(
                  'Sin foto. La foto se guarda sólo en este teléfono, sin '
                  'ubicación ni otros datos de la cámara.',
                )
              else if (!photo.exists)
                const Text('La foto ya no está en este teléfono.')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      photo.file,
                      key: ValueKey(photo.sha256),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('No se pudo mostrar la foto.'),
                    ),
                  ),
                ),
              if (note != null) ...[const SizedBox(height: 8), Text(note)],
              const SizedBox(height: 8),
              Text(
                labelPhotosNotInBackups,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: photo == null
                    ? [
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _pick(ImageSource.camera, request),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Tomar foto'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => _pick(ImageSource.gallery, request),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Elegir de la galería'),
                        ),
                      ]
                    : [
                        FilledButton.icon(
                          onPressed: busy ? null : () => _replace(request),
                          icon: const Icon(Icons.flip_camera_android_outlined),
                          label: const Text('Reemplazar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => _remove(request),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Quitar'),
                        ),
                      ],
              ),
            ],
          );
        },
      ),
    ),
  );
}
