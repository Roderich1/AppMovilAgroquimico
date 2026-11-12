/// Estilos compartidos del rediseño móvil (2026-11-12).
///
/// Dirección visual del prototipo «Agrocuentas — Rediseño de pantallas
/// clave»: verde oscuro con acentos lima sobre superficies claras, títulos y
/// cifras en Bricolage Grotesque y el resto en DM Sans (las dos empaquetadas
/// en `assets/fonts/`, licencia OFL en Más › Licencias).
///
/// Sólo presentación: ningún valor de aquí cambia datos ni reglas.
library;

import 'package:flutter/material.dart';

/// Paleta del rediseño. Los nombres dicen el uso, no el tono.
abstract final class AgroColors {
  /// Verde casi negro: texto principal, botón principal, cabecera de Inicio.
  static const ink = Color(0xFF0F2A1D);

  /// Verde oscuro de los elementos sobre [ink] (botones de la cabecera).
  static const inkSoft = Color(0xFF29473A);

  /// Lima: acento de la acción principal y del destino seleccionado.
  static const lime = Color(0xFFC8F04A);

  /// Fondo de las páginas.
  static const canvas = Color(0xFFF2F4EE);

  /// Tarjetas, filas y hojas.
  static const surface = Color(0xFFFFFFFF);

  /// Texto secundario: 6,4:1 sobre blanco y 5,6:1 sobre [canvas].
  static const muted = Color(0xFF55645A);

  /// Separadores entre filas (decorativo).
  static const line = Color(0xFFDFE4DA);

  /// Fondo de los selectores de dos opciones y de las barras de progreso.
  static const track = Color(0xFFE3E8DD);

  /// Segmento pendiente del indicador de pasos.
  static const trackStrong = Color(0xFFD3DACD);

  /// Borde de un campo en reposo. El prototipo usa #B9C9BE (1,7:1 sobre
  /// blanco); se oscurece hasta 3,5:1 para que el campo se distinga.
  static const fieldBorder = Color(0xFF7D8D82);

  /// Asa de las hojas y texto tenue sobre [ink].
  static const handle = Color(0xFFB9C9BE);

  /// Fondo de los iconos redondos neutros.
  static const chip = Color(0xFFE9EDE4);

  /// Enlaces y texto verde sobre fondos claros.
  static const link = Color(0xFF1F6B3A);

  /// Aviso que pide atención (convocatoria abierta, algo por revisar).
  static const warnBg = Color(0xFFFFE0A3);
  static const warnInk = Color(0xFF3D2700);

  /// Problema que bloquea (vencido, error).
  static const danger = Color(0xFFB3261E);

  /// Algo pendiente que no bloquea (saldo, por publicar).
  static const caution = Color(0xFF8A5300);

  /// Texto claro sobre [ink].
  static const onInk = Color(0xFFE8F1EA);
  static const onInkMuted = Color(0xFFB9C9BE);
}

abstract final class AgroFonts {
  static const body = 'DM Sans';
  static const display = 'Bricolage Grotesque';
}

/// Estilos de texto del rediseño que el tema de Material no cubre.
abstract final class AgroText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Pregunta o título de una pantalla de registro («¿Qué compró?»).
  static const h1 = TextStyle(
    fontFamily: AgroFonts.display,
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AgroColors.ink,
  );

  /// Título de una hoja inferior («Producto 2»).
  static const sheetTitle = TextStyle(
    fontFamily: AgroFonts.display,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: AgroColors.ink,
  );

  /// Título de sección («Productos de esta compra»).
  static const h2 = TextStyle(
    fontFamily: AgroFonts.display,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w700,
    color: AgroColors.ink,
  );

  /// Pregunta dentro de un formulario («¿Para quién es?»).
  static const question = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w700,
    color: AgroColors.ink,
  );

  /// Rótulo pequeño sobre un valor («Proveedor»).
  static const label = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    color: AgroColors.muted,
  );

  /// Valor elegido en una fila («Agroinsumos»).
  static const value = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w700,
    color: AgroColors.ink,
  );

  /// Detalle secundario de una fila («12 L × 118,00 Bs»).
  static const detail = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: AgroColors.muted,
  );

  /// Importe al final de una fila.
  static const amount = TextStyle(
    fontFamily: AgroFonts.display,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
    color: AgroColors.ink,
    fontFeatures: _tabular,
  );

  /// Total de una operación.
  static const total = TextStyle(
    fontFamily: AgroFonts.display,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w800,
    color: AgroColors.ink,
    fontFeatures: _tabular,
  );

  /// Cifra que se escribe en un campo grande (cantidad, precio).
  static const input = TextStyle(
    fontFamily: AgroFonts.display,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w800,
    color: AgroColors.ink,
    fontFeatures: _tabular,
  );
}

/// Tema de la aplicación con la dirección del rediseño.
ThemeData buildAgroTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AgroColors.link).copyWith(
    primary: AgroColors.ink,
    onPrimary: Colors.white,
    // Las pantallas anteriores usan `primaryContainer` para paneles y avisos:
    // un tono suave. El lima intenso queda para las acciones del rediseño.
    primaryContainer: const Color(0xFFE3F6A8),
    onPrimaryContainer: AgroColors.ink,
    secondaryContainer: const Color(0xFFDDEFB6),
    onSecondaryContainer: AgroColors.ink,
    tertiary: AgroColors.caution,
    onTertiary: Colors.white,
    tertiaryContainer: AgroColors.warnBg,
    onTertiaryContainer: AgroColors.warnInk,
    error: AgroColors.danger,
    surface: AgroColors.canvas,
    onSurface: AgroColors.ink,
    onSurfaceVariant: AgroColors.muted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: const Color(0xFFEBEFE6),
    surfaceContainerHigh: const Color(0xFFE6EBE1),
    surfaceContainerHighest: AgroColors.track,
    outline: AgroColors.fieldBorder,
    outlineVariant: AgroColors.line,
    inverseSurface: AgroColors.ink,
    onInverseSurface: AgroColors.onInk,
    inversePrimary: AgroColors.lime,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: AgroFonts.body,
  );
  final text = base.textTheme;
  TextStyle? display(TextStyle? style, FontWeight weight) => style?.copyWith(
    fontFamily: AgroFonts.display,
    fontWeight: weight,
    color: AgroColors.ink,
  );
  return base.copyWith(
    scaffoldBackgroundColor: AgroColors.canvas,
    // Se conserva la densidad compacta de siempre: cambiarla movería todas
    // las pantallas que aún no se rediseñan. Los componentes nuevos fijan
    // su propio alto (44–60 px).
    visualDensity: VisualDensity.compact,
    textTheme: text.copyWith(
      headlineLarge: display(text.headlineLarge, FontWeight.w800),
      headlineMedium: display(text.headlineMedium, FontWeight.w800),
      headlineSmall: display(text.headlineSmall, FontWeight.w800),
      titleLarge: display(text.titleLarge, FontWeight.w700),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AgroColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    listTileTheme: const ListTileThemeData(dense: true),
    appBarTheme: const AppBarTheme(
      backgroundColor: AgroColors.canvas,
      foregroundColor: AgroColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: AgroFonts.display,
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w800,
        color: AgroColors.ink,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AgroColors.fieldBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AgroColors.fieldBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AgroColors.ink, width: 2),
      ),
      labelStyle: TextStyle(color: AgroColors.muted),
      floatingLabelStyle: TextStyle(color: AgroColors.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AgroColors.ink,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: AgroFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AgroColors.ink,
        side: const BorderSide(color: AgroColors.ink, width: 1.5),
        textStyle: const TextStyle(
          fontFamily: AgroFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AgroColors.link,
        textStyle: const TextStyle(
          fontFamily: AgroFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: const ChipThemeData(
      checkmarkColor: AgroColors.ink,
      shape: StadiumBorder(side: BorderSide(color: AgroColors.fieldBorder)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AgroColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AgroColors.ink,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AgroColors.lime
              : AgroColors.muted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AgroColors.surface,
      indicatorColor: AgroColors.ink,
      selectedIconTheme: IconThemeData(color: AgroColors.lime),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AgroColors.lime,
      foregroundColor: AgroColors.ink,
      shape: StadiumBorder(),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AgroColors.canvas,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AgroColors.handle,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AgroColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: AgroColors.line),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
