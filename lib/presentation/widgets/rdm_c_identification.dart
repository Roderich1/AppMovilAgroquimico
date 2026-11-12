/// Presentación de la identificación de productos (E1) en el rediseño: la
/// hoja «Pedir identificación» y el tono de las etiquetas de estado. Los
/// textos de estado y de consentimiento son los vigentes
/// (`identification_texts.dart`, `photoConsentText`); aquí sólo se dibujan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show repositoryProvider;
import '../../data/product_photo_storage.dart' show ProductPhoto;
import '../../domain/sync/identification_view.dart' show photoConsentText;
import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'rdm_c_page.dart';

/// Tono de una etiqueta de estado de la identificación (los textos salen de
/// `identificationChips`). El texto dice el estado; el tono sólo lo acompaña:
/// rechazo o fallo definitivo → rojo; pendiente, en espera o reintento →
/// ámbar; recibido, identificado o enviado → verde; retirada → gris.
BadgeTone identificationChipTone(String chip) {
  if (chip.startsWith('Rechazada') || chip.startsWith('Foto no enviada:')) {
    return BadgeTone.missing;
  }
  if (chip.contains('endiente') ||
      chip.startsWith('Esperando') ||
      chip.contains('se reintentará')) {
    return BadgeTone.review;
  }
  if (chip == 'Foto retirada') return BadgeTone.neutral;
  return BadgeTone.voice;
}

/// Lo que la hoja muestra antes de pedir la identificación: exactamente lo
/// que se enviará.
typedef IdentificationRequestPreview = ({
  int productId,
  String name,
  String? ingredient,
  String unit,
  bool hasPhoto,
});

/// Hoja «Pedir identificación» (E1 §5.2). Devuelve null si se cierra sin
/// confirmar; si no, si se autorizó compartir la foto. La casilla de la foto
/// sólo aparece si hay foto y empieza **sin marcar** (consentimiento
/// `FOTO-1`, aparte de la solicitud).
Future<({bool sharePhoto})?> showIdentificationRequestSheet(
  BuildContext context,
  IdentificationRequestPreview preview,
) => showRdmCSheet<({bool sharePhoto})>(
  context,
  builder: (_) => _IdentificationRequestSheet(preview: preview),
);

class _IdentificationRequestSheet extends ConsumerStatefulWidget {
  const _IdentificationRequestSheet({required this.preview});
  final IdentificationRequestPreview preview;

  @override
  ConsumerState<_IdentificationRequestSheet> createState() =>
      _IdentificationRequestSheetState();
}

class _IdentificationRequestSheetState
    extends ConsumerState<_IdentificationRequestSheet> {
  bool sharePhoto = false;
  Future<ProductPhoto?>? photo;

  @override
  void initState() {
    super.initState();
    // La miniatura deja ver qué foto se autoriza; sólo se lee si hay foto.
    if (widget.preview.hasPhoto) {
      photo = ref
          .read(repositoryProvider)
          .productPhoto(widget.preview.productId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final ingredient = preview.ingredient;
    return RdmCSheetBody(
      title: 'Pedir identificación',
      subtitle:
          'El sindicato busca a qué producto de su catálogo equivale. El '
          'vínculo lo confirma usted después.',
      actions: [
        PrimaryActionButton(
          key: const Key('identification-confirm'),
          label: 'Pedir identificación',
          icon: Icons.send_outlined,
          onPressed: () => Navigator.pop(context, (
            sharePhoto: preview.hasPhoto && sharePhoto,
          )),
        ),
      ],
      children: [
        const RdmCOverline('Se enviará al sindicato sólo esto'),
        AgroGroup(
          children: [
            RdmCInfoRow(
              label: 'Nombre',
              value: preview.name,
              valueKey: const Key('identification-sent-name'),
            ),
            RdmCInfoRow(
              label: 'Ingrediente activo',
              value: (ingredient == null || ingredient.isEmpty)
                  ? 'sin dato'
                  : ingredient,
              valueKey: const Key('identification-sent-ingredient'),
            ),
            RdmCInfoRow(
              label: 'Unidad',
              value: preview.unit,
              valueKey: const Key('identification-sent-unit'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 20, color: AgroColors.muted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No se envían compras, aplicaciones, cantidades ni '
                'existencias.',
                style: AgroText.detail,
              ),
            ),
          ],
        ),
        if (preview.hasPhoto) ...[
          const SizedBox(height: 12),
          AgroGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Thumbnail(photo: photo),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          key: const Key('identification-share-photo'),
                          contentPadding: const EdgeInsets.only(left: 8),
                          value: sharePhoto,
                          onChanged: (value) =>
                              setState(() => sharePhoto = value ?? false),
                          title: const Text(
                            'Compartir también la foto de la etiqueta',
                            style: AgroText.question,
                          ),
                          subtitle: Text(
                            photoConsentText(preview.name),
                            style: AgroText.detail,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photo});
  final Future<ProductPhoto?>? photo;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: _size,
        child: FutureBuilder<ProductPhoto?>(
          future: photo,
          builder: (context, snapshot) {
            final value = snapshot.data;
            if (value == null || !value.exists) {
              return const ColoredBox(
                color: AgroColors.track,
                child: Icon(Icons.image_outlined, color: AgroColors.muted),
              );
            }
            return Image.file(
              value.file,
              fit: BoxFit.cover,
              cacheWidth: 192,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AgroColors.track,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AgroColors.muted,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
