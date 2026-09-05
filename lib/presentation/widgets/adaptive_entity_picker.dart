import 'package:flutter/material.dart';

import '../../domain/text_search.dart';

class AdaptiveEntityPicker<T> extends StatefulWidget {
  const AdaptiveEntityPicker({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.secondaryOf,
    this.enabled = true,
    this.loading = false,
    this.error,
    this.emptyMessage = 'No hay opciones disponibles.',
    this.allowClear = true,
  });

  final String label;
  final List<T> items;
  final T? value;
  final String Function(T item) labelOf;
  final String Function(T item)? secondaryOf;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final bool loading;
  final Object? error;
  final String emptyMessage;
  final bool allowClear;

  @override
  State<AdaptiveEntityPicker<T>> createState() =>
      _AdaptiveEntityPickerState<T>();
}

class _AdaptiveEntityPickerState<T> extends State<AdaptiveEntityPicker<T>> {
  bool autoSelectionScheduled = false;

  @override
  void didUpdateWidget(covariant AdaptiveEntityPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.value != widget.value) {
      autoSelectionScheduled = false;
    }
  }

  void _autoSelectSingle() {
    if (autoSelectionScheduled ||
        !widget.enabled ||
        widget.value != null ||
        widget.items.length != 1) {
      return;
    }
    autoSelectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.value == null && widget.items.length == 1) {
        widget.onChanged(widget.items.single);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _autoSelectSingle();
    final selected = widget.value;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      value: selected == null ? 'Sin seleccionar' : widget.labelOf(selected),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.enabled && !widget.loading ? _open : null,
        child: InputDecorator(
          // `isEmpty: true` mantenia la etiqueta en el centro del campo, justo
          // donde se pinta "Seleccionar": ambos textos quedaban superpuestos e
          // ilegibles (UIBUG-006). Con la etiqueta siempre flotando, el hueco
          // central queda libre para el valor o el texto de ayuda.
          isEmpty: false,
          decoration: InputDecoration(
            labelText: widget.label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            enabled: widget.enabled,
            errorText: widget.error?.toString(),
            prefixIcon: widget.loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
            suffixIcon: selected != null && widget.allowClear
                ? IconButton(
                    tooltip: 'Limpiar ${widget.label}',
                    onPressed: widget.enabled
                        ? () => widget.onChanged(null)
                        : null,
                    icon: const Icon(Icons.close),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            selected == null ? 'Seleccionar' : widget.labelOf(selected),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    if (widget.items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.emptyMessage)));
      return;
    }
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EntityPickerSheet<T>(
        label: widget.label,
        items: widget.items,
        selected: widget.value,
        labelOf: widget.labelOf,
        secondaryOf: widget.secondaryOf,
      ),
    );
    if (result != null && mounted) widget.onChanged(result);
  }
}

class _EntityPickerSheet<T> extends StatefulWidget {
  const _EntityPickerSheet({
    required this.label,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.secondaryOf,
  });
  final String label;
  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;
  final String Function(T)? secondaryOf;
  @override
  State<_EntityPickerSheet<T>> createState() => _EntityPickerSheetState<T>();
}

class _EntityPickerSheetState<T> extends State<_EntityPickerSheet<T>> {
  final search = TextEditingController();
  String query = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      final text =
          '${widget.labelOf(item)} ${widget.secondaryOf?.call(item) ?? ''}';
      // Comparacion sin tildes: `maria` debe encontrar "María" (UIBUG-019).
      return matchesSearch(text, query);
    }).toList();

    // Altura proporcional al contenido, con tope: con 4 elementos la hoja
    // ocupaba el 65 % de la pantalla igual que con 22 (UIBUG-061).
    final maxHeight = MediaQuery.sizeOf(context).height * 0.65;
    final rowsHeight = filtered.length * 64.0 + 132;
    final height = rowsHeight.clamp(220.0, maxHeight);
    return SafeArea(
      child: Padding(
        // La hoja se encoge con el teclado en vez de quedar debajo.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text('${filtered.length}/${widget.items.length}'),
                  ],
                ),
              ),
              if (widget.items.length >= 8)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: search,
                    // Sin autofoco: el teclado se abria solo y de 8 opciones se
                    // veian 3, obligando a cerrarlo para poder elegir
                    // (UIBUG-035). Ahora se abre solo si el usuario lo toca.
                    onChanged: (value) => setState(() => query = value.trim()),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar',
                      isDense: true,
                    ),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    // Alineado arriba: centrado verticalmente quedaba tapado por
                    // el teclado y el usuario solo veia un hueco (UIBUG-036).
                    ? const Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text('Sin resultados.'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final selected = item == widget.selected;
                          return ListTile(
                            selected: selected,
                            leading: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            ),
                            title: Text(widget.labelOf(item)),
                            subtitle: widget.secondaryOf == null
                                ? null
                                : Text(
                                    widget.secondaryOf!(item),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
