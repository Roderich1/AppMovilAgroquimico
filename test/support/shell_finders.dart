import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un texto que NO está dentro del botón flotante «+ Registrar» del shell
/// (rediseño, 2026-11-12). Sirve para tocar el «Registrar» de una pantalla o
/// de un diálogo sin confundirlo con el del shell.
Finder textOutsideShellFab(String text) => find.byElementPredicate(
  (element) =>
      element.widget is Text &&
      (element.widget as Text).data == text &&
      element.findAncestorWidgetOfExactType<FloatingActionButton>() == null,
  description: '«$text» fuera del botón flotante',
);
