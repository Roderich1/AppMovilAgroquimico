import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/sync/identification_models.dart';
import '../../domain/sync/identification_view.dart';
import 'agro_ui.dart';
import 'common.dart';
import 'label_photo_sheet.dart' show LabelPhotoPicker;
import 'rdm_c_page.dart';

final clarificationPhotoPickerProvider = Provider<LabelPhotoPicker>(
  (_) =>
      (source) async => (await ImagePicker().pickImage(source: source))?.path,
);

typedef ClarificationDraft = ({
  String name,
  String? ingredient,
  String? photoPath,
});

Future<ClarificationDraft?> showIdentificationClarification(
  BuildContext context,
  IdentificationRequest request,
) => showRdmCSheet<ClarificationDraft>(
  context,
  builder: (_) => _ClarificationSheet(request: request),
);

class _ClarificationSheet extends ConsumerStatefulWidget {
  const _ClarificationSheet({required this.request});
  final IdentificationRequest request;

  @override
  ConsumerState<_ClarificationSheet> createState() =>
      _ClarificationSheetState();
}

class _ClarificationSheetState extends ConsumerState<_ClarificationSheet> {
  late final TextEditingController name;
  late final TextEditingController ingredient;
  String? photoPath;
  bool sharePhoto = false;
  bool picking = false;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    final reply = request.clarificationReply;
    final draft = reply?.noteAt == request.serverNoteAt ? reply : null;
    name = TextEditingController(text: draft?.name ?? request.sentName);
    ingredient = TextEditingController(
      text: draft == null ? request.sentActiveIngredient : draft.ingredient,
    );
  }

  @override
  void dispose() {
    name.dispose();
    ingredient.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => picking = true);
    try {
      final picked = await ref.read(clarificationPhotoPickerProvider)(source);
      if (!mounted || picked == null) return;
      setState(() {
        photoPath = picked;
        sharePhoto = false;
      });
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final photo = photoPath;
    final textChanged =
        name.text.trim() != request.sentName ||
        ingredient.text.trim() != (request.sentActiveIngredient ?? '');
    final ready =
        !picking &&
        name.text.trim().isNotEmpty &&
        (photo == null ? textChanged : sharePhoto);
    return RdmCSheetBody(
      title: 'Completar información',
      subtitle: 'Nota del sindicato: ${request.serverNote}',
      actions: [
        PrimaryActionButton(
          key: const Key('clarification-send'),
          label: 'Enviar respuesta',
          icon: Icons.send_outlined,
          onPressed: ready
              ? () => Navigator.pop(context, (
                  name: name.text.trim(),
                  ingredient: ingredient.text.trim().isEmpty
                      ? null
                      : ingredient.text.trim(),
                  photoPath: photo,
                ))
              : null,
        ),
      ],
      children: [
        TextField(
          key: const Key('clarification-name'),
          controller: name,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('clarification-ingredient'),
          controller: ingredient,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Ingrediente activo (opcional)',
          ),
          onChanged: (_) => setState(() {}),
        ),
        Text('Unidad: ${request.sentUnit}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: picking ? null : () => _pick(ImageSource.camera),
              child: const Text('Tomar foto'),
            ),
            OutlinedButton(
              onPressed: picking ? null : () => _pick(ImageSource.gallery),
              child: const Text('Elegir foto'),
            ),
          ],
        ),
        if (photo != null) ...[
          Image.file(
            File(photo),
            height: 104,
            semanticLabel: 'Foto de la etiqueta',
            errorBuilder: (_, _, _) => const Text('Foto seleccionada'),
          ),
          TextButton(
            onPressed: () => setState(() {
              photoPath = null;
              sharePhoto = false;
            }),
            child: const Text('Quitar foto de la respuesta'),
          ),
          CheckboxListTile(
            key: const Key('clarification-photo-consent'),
            value: sharePhoto,
            onChanged: (value) => setState(() => sharePhoto = value ?? false),
            title: const Text('Autorizo compartir esta foto'),
            subtitle: Text(photoConsentText(name.text.trim())),
          ),
        ],
      ],
    );
  }
}
