import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Configuración del ambiente, resuelta **en tiempo de compilación**.
///
/// ## Por qué constantes de compilación y no un archivo de configuración
///
/// `String.fromEnvironment` se resuelve al compilar, así que el valor queda
/// fijado en el binario y no se puede alterar en el dispositivo. Un archivo
/// `.env` empaquetado como recurso, en cambio, viaja dentro del APK y se lee
/// descomprimiéndolo: cualquiera podría ver —o en un build modificado,
/// cambiar— a qué servidor apunta la aplicación.
///
/// Además permite generar los dos binarios desde el mismo código:
///
/// ```bash
/// # Desarrollo (valores por defecto)
/// flutter run
///
/// # Producción
/// flutter build apk --release \
///   --dart-define=AMBIENTE=produccion \
///   --dart-define=URL_BASE=https://api.mivecinoseguro.ec
/// ```
abstract final class Entorno {
  Entorno._();

  static const ambiente = String.fromEnvironment(
    'AMBIENTE',
    defaultValue: 'desarrollo',
  );

  static const _urlBaseDefinida = String.fromEnvironment('URL_BASE');

  static const esProduccion = ambiente == 'produccion';

  /// El registro detallado **nunca** se activa en producción.
  ///
  /// Es una constante de compilación, no una bandera de ejecución: el
  /// compilador elimina las ramas muertas, así que en el binario de producción
  /// el código de registro directamente no existe. Una bandera en runtime
  /// seguiría ahí, y bastaría un despiste para encenderla.
  static const registroDetallado = !esProduccion;

  /// Dirección base de la API.
  ///
  /// Sin `--dart-define=URL_BASE` cae al servidor local de desarrollo. El
  /// emulador de Android no ve el `localhost` del anfitrión: lo alcanza por la
  /// IP especial 10.0.2.2.
  static String get urlBase {
    if (_urlBaseDefinida.isNotEmpty) return _urlBaseDefinida;

    const puerto = 3333;
    if (kIsWeb) return 'http://localhost:$puerto';
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:$puerto';
    return 'http://localhost:$puerto';
  }

  /// Comprueba que la configuración es coherente. Se llama al arrancar.
  ///
  /// **Producción exige HTTPS.** Sin cifrado, el token de sesión viaja en claro
  /// y cualquiera en la misma red wifi puede leerlo y suplantar al vecino.
  ///
  /// Se lanza una excepción en lugar de registrar un aviso a propósito: un
  /// fallo de arranque se descubre al primer intento; un aviso en el registro
  /// se descubre cuando ya hay usuarios.
  static void verificar() {
    if (esProduccion && !urlBase.startsWith('https://')) {
      throw StateError(
        '[CONFIGURACIÓN] La compilación de producción apunta a "$urlBase", '
        'que no usa HTTPS. El token de sesión viajaría sin cifrar. '
        'Compila con --dart-define=URL_BASE=https://...',
      );
    }

    if (registroDetallado) {
      debugPrint('[ENTORNO] ambiente=$ambiente · api=$urlBase');
    }
  }
}
