// Rótulos del selector de fecha en la aplicación real, que corre en español
// (E-13: `AgroApp` registra `flutter_localizations` con `Locale('es')`). Las
// pruebas que montan `AgroApp` buscan estos textos en vez de «OK» / «Cancel»
// / «Previous month», que son los de un `MaterialApp` sin delegados.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Localización material en español, la misma que carga la aplicación.
Future<MaterialLocalizations> esMaterial() =>
    GlobalMaterialLocalizations.delegate.load(const Locale('es'));
