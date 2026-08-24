import 'package:flutter/material.dart';

import 'tokens_primitivos.dart';
import 'tokens_semanticos.dart';

/// ============================================================================
/// TEMA DE LA APLICACIÓN
/// ============================================================================
///
/// Traduce los tokens semánticos al `ThemeData` de Material 3 y registra
/// [TokensApp] como extensión del tema. Es el único punto donde el sistema de
/// diseño se conecta con Flutter.
///
/// Nótese que también se configuran los temas de los componentes de Material
/// (`cardTheme`, `inputDecorationTheme`, etc.). Eso asegura que incluso los
/// widgets nativos que no pasan por el catálogo hereden los tokens.
/// ============================================================================

abstract final class TemaApp {
  static ThemeData get claro => _construir(TokensApp.claro, Brightness.light);
  static ThemeData get oscuro => _construir(TokensApp.oscuro, Brightness.dark);

  static ThemeData _construir(TokensApp t, Brightness brillo) {
    final c = t.color;
    final textos = _construirTextTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brillo,

      // Los tokens quedan disponibles vía `context.tokens` en toda la app.
      extensions: <ThemeExtension<dynamic>>[t],

      scaffoldBackgroundColor: c.fondo,
      textTheme: textos,

      // ColorScheme se deriva de los tokens semánticos para que los widgets
      // nativos de Material (SnackBar, Dialog, Switch...) sean coherentes.
      colorScheme: ColorScheme(
        brightness: brillo,
        primary: c.primario,
        onPrimary: c.onPrimario,
        primaryContainer: c.primarioSuave,
        onPrimaryContainer: c.onPrimarioSuave,
        secondary: c.primario,
        onSecondary: c.onPrimario,
        secondaryContainer: c.primarioSuave,
        onSecondaryContainer: c.onPrimarioSuave,
        error: c.peligro,
        onError: c.onPeligroRelleno,
        errorContainer: c.peligroSuave,
        onErrorContainer: c.onPeligroSuave,
        surface: c.superficie,
        onSurface: c.onSuperficie,
        surfaceContainerHighest: c.superficieAlterna,
        onSurfaceVariant: c.onSuperficieSutil,
        outline: c.bordeInteractivo,
        outlineVariant: c.borde,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: c.superficie,
        foregroundColor: c.onSuperficie,
        elevation: t.elevacion.plano,
        scrolledUnderElevation: t.elevacion.card,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textos.titleLarge,
      ),

      cardTheme: CardThemeData(
        color: c.superficie,
        elevation: t.elevacion.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: t.radio.brCard),
        margin: EdgeInsets.zero,
      ),

      dividerTheme: DividerThemeData(
        color: c.borde,
        thickness: 1,
        space: t.espacio.entreGrupos,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.superficie,
        contentPadding: EdgeInsets.symmetric(
          horizontal: t.espacio.interiorCard,
          vertical: t.espacio.entreGrupos,
        ),
        border: OutlineInputBorder(
          borderRadius: t.radio.brControl,
          borderSide: BorderSide(color: c.bordeInteractivo),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: t.radio.brControl,
          borderSide: BorderSide(color: c.bordeInteractivo),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: t.radio.brControl,
          borderSide: BorderSide(
            color: c.foco,
            width: AccesibilidadPrimitiva.grosorFoco,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: t.radio.brControl,
          borderSide: BorderSide(color: c.peligro),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: t.radio.brControl,
          borderSide: BorderSide(
            color: c.peligro,
            width: AccesibilidadPrimitiva.grosorFoco,
          ),
        ),
        labelStyle: textos.bodyMedium?.copyWith(color: c.onSuperficieSutil),
        hintStyle: textos.bodyMedium?.copyWith(color: c.onSuperficieSutil),
        errorStyle: textos.bodySmall?.copyWith(color: c.peligro),
        prefixIconColor: c.onSuperficieSutil,
        suffixIconColor: c.onSuperficieSutil,
      ),

      iconTheme: IconThemeData(color: c.onSuperficieSutil),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primario,
        circularTrackColor: Colors.transparent,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.onSuperficie,
        contentTextStyle: textos.bodyMedium?.copyWith(color: c.superficie),
        shape: RoundedRectangleBorder(borderRadius: t.radio.brControl),
      ),

      // Área táctil mínima garantizada en todos los controles de Material.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }

  /// Escala tipográfica construida desde los primitivos.
  ///
  /// No se fija `fontSize` en ningún widget: todos leen de aquí, y Flutter
  /// aplica encima el `textScaler` del sistema. Ese es el mecanismo que hace
  /// que la app soporte la fuente ampliada del teléfono.
  static TextTheme _construirTextTheme(ColoresSemanticos c) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: TipografiaPrimitiva.tam32,
        fontWeight: TipografiaPrimitiva.pesoFuerte,
        height: TipografiaPrimitiva.alturaAjustada,
        letterSpacing: TipografiaPrimitiva.trackingTitulo,
        color: c.onSuperficie,
      ),
      headlineMedium: TextStyle(
        fontSize: TipografiaPrimitiva.tam28,
        fontWeight: TipografiaPrimitiva.pesoFuerte,
        height: TipografiaPrimitiva.alturaAjustada,
        letterSpacing: TipografiaPrimitiva.trackingTitulo,
        color: c.onSuperficie,
      ),
      headlineSmall: TextStyle(
        fontSize: TipografiaPrimitiva.tam24,
        fontWeight: TipografiaPrimitiva.pesoSemi,
        height: TipografiaPrimitiva.alturaAjustada,
        color: c.onSuperficie,
      ),
      titleLarge: TextStyle(
        fontSize: TipografiaPrimitiva.tam20,
        fontWeight: TipografiaPrimitiva.pesoSemi,
        height: TipografiaPrimitiva.alturaAjustada,
        color: c.onSuperficie,
      ),
      titleMedium: TextStyle(
        fontSize: TipografiaPrimitiva.tam18,
        fontWeight: TipografiaPrimitiva.pesoSemi,
        height: TipografiaPrimitiva.alturaNormal,
        color: c.onSuperficie,
      ),
      titleSmall: TextStyle(
        fontSize: TipografiaPrimitiva.tam16,
        fontWeight: TipografiaPrimitiva.pesoMedio,
        height: TipografiaPrimitiva.alturaNormal,
        color: c.onSuperficie,
      ),
      bodyLarge: TextStyle(
        fontSize: TipografiaPrimitiva.tam16,
        fontWeight: TipografiaPrimitiva.pesoRegular,
        height: TipografiaPrimitiva.alturaHolgada,
        color: c.onSuperficie,
      ),
      bodyMedium: TextStyle(
        fontSize: TipografiaPrimitiva.tam14,
        fontWeight: TipografiaPrimitiva.pesoRegular,
        height: TipografiaPrimitiva.alturaNormal,
        color: c.onSuperficie,
      ),
      bodySmall: TextStyle(
        fontSize: TipografiaPrimitiva.tam12,
        fontWeight: TipografiaPrimitiva.pesoRegular,
        height: TipografiaPrimitiva.alturaNormal,
        color: c.onSuperficieSutil,
      ),
      labelLarge: TextStyle(
        fontSize: TipografiaPrimitiva.tam16,
        fontWeight: TipografiaPrimitiva.pesoSemi,
        height: TipografiaPrimitiva.alturaNormal,
        letterSpacing: TipografiaPrimitiva.trackingEtiqueta,
        color: c.onSuperficie,
      ),
      labelMedium: TextStyle(
        fontSize: TipografiaPrimitiva.tam14,
        fontWeight: TipografiaPrimitiva.pesoMedio,
        height: TipografiaPrimitiva.alturaNormal,
        letterSpacing: TipografiaPrimitiva.trackingEtiqueta,
        color: c.onSuperficieSutil,
      ),
      labelSmall: TextStyle(
        fontSize: TipografiaPrimitiva.tam11,
        fontWeight: TipografiaPrimitiva.pesoMedio,
        height: TipografiaPrimitiva.alturaNormal,
        letterSpacing: TipografiaPrimitiva.trackingEtiqueta,
        color: c.onSuperficieSutil,
      ),
    );
  }
}
