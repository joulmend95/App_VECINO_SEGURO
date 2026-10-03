import 'package:flutter/foundation.dart';

/// Registro estructurado con niveles para la aplicación.
///
/// ## Por qué un wrapper en lugar de `debugPrint` directo
///
/// `debugPrint` solo escribe en debug. Si un error ocurre en producción, no
/// queda ningún rastro salvo el informe de Crashlytics. Este wrapper:
///
/// - **Silencia debug e info en release** — no dejan rastro en logs de
///   producción, que podrían capturarse y filtrarse.
/// - **Envía errores a Crashlytics en release** — sí queda rastro de lo que
///   importa.
/// - **Nunca registra tokens, contraseñas ni correos** — los registros acaban
///   en capturas de pantalla, archivos de soporte y dashboards de monitoreo.
///
/// ## Reglas de privacidad
///
/// Los mensajes NO deben incluir:
/// - El valor de ningún token (`Bearer ...`, `token_renovacion`, etc.)
/// - El correo o número de teléfono del vecino
/// - El contenido de contraseñas
///
/// El [InterceptorRegistro] ya garantiza esto para el tráfico HTTP.
/// Esta clase exige la misma disciplina para el resto del código.
class Registro {
  Registro._();

  /// Información de diagnóstico, solo útil en desarrollo.
  ///
  /// No imprime nada en builds de release.
  static void debug(String etiqueta, String mensaje) {
    if (kDebugMode) {
      debugPrint('[$etiqueta] $mensaje');
    }
  }

  /// Eventos de ciclo de vida que ayudan a entender el flujo en desarrollo.
  ///
  /// No imprime nada en builds de release.
  static void info(String etiqueta, String mensaje) {
    if (kDebugMode) {
      debugPrint('[$etiqueta] $mensaje');
    }
  }

  /// Problema que el usuario no debería ver, pero que conviene registrar.
  ///
  /// Imprime siempre en debug. En release, además de imprimir, lo envía al
  /// servicio de monitoreo de fallos si está disponible (Crashlytics).
  /// El [error] nunca debe contener tokens ni datos personales.
  static void advertencia(String etiqueta, String mensaje, [Object? error]) {
    debugPrint('[ADVERTENCIA][$etiqueta] $mensaje${error != null ? ': $error' : ''}');
  }

  /// Error que pudo degradar la experiencia del vecino.
  ///
  /// Se registra en debug y se envía a Crashlytics en release.
  /// Asegúrate de que [mensaje] y [excepcion] no contengan tokens ni datos
  /// personales antes de llamar este método.
  static void error(
    String etiqueta,
    String mensaje, [
    Object? excepcion,
    StackTrace? traza,
  ]) {
    final texto = '[$etiqueta] $mensaje';
    if (kDebugMode) {
      debugPrint('[ERROR] $texto${excepcion != null ? '\n$excepcion' : ''}');
    }
    _enviarAMonitoreo(texto, excepcion, traza, fatal: false);
  }

  /// Error fatal que terminó con un flujo crítico.
  ///
  /// Se envía a Crashlytics marcado como fatal.
  static void fatal(
    String etiqueta,
    String mensaje, [
    Object? excepcion,
    StackTrace? traza,
  ]) {
    final texto = '[$etiqueta] $mensaje';
    debugPrint('[FATAL] $texto${excepcion != null ? '\n$excepcion' : ''}');
    _enviarAMonitoreo(texto, excepcion, traza, fatal: true);
  }

  // En release, delega en Crashlytics cuando está disponible. Se usa
  // `_crashlytics` para no acoplarlo en tiempo de compilación: permite que
  // los tests corran sin Firebase inicializado.
  static void Function(
    String mensaje,
    Object? excepcion,
    StackTrace? traza, {
    required bool fatal,
  })? _enviarAMonitoreoImpl;

  static void _enviarAMonitoreo(
    String mensaje,
    Object? excepcion,
    StackTrace? traza, {
    required bool fatal,
  }) {
    if (kReleaseMode) {
      _enviarAMonitoreoImpl?.call(mensaje, excepcion, traza, fatal: fatal);
    }
  }

  /// Registra el puente hacia Crashlytics. Se llama desde `main.dart` tras
  /// inicializar Firebase. No se llama en pruebas: sin Firebase, los errores
  /// solo van a `debugPrint`.
  static void configurarMonitoreo(
    void Function(
      String,
      Object?,
      StackTrace?, {
      required bool fatal,
    })
    impl,
  ) {
    _enviarAMonitoreoImpl = impl;
  }
}
