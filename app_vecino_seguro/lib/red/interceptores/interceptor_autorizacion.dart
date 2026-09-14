import 'package:dio/dio.dart';

import '../credenciales.dart';

/// **1.º de la cadena** — inyecta el token de acceso en cada petición.
///
/// Va primero porque todo lo que viene después asume que la petición ya lleva
/// credencial: el interceptor de renovación necesita ver el 401 que produce una
/// petición *autorizada*, y el de registro debe reflejar lo que realmente salió.
///
/// El token se lee del almacén cifrado de la Semana 12 (`flutter_secure_storage`,
/// Keystore en Android y Keychain en iOS), nunca de una variable en memoria que
/// alguien pudiera dejar obsoleta.
class InterceptorAutorizacion extends Interceptor {
  InterceptorAutorizacion(this.credenciales);

  final Credenciales credenciales;

  /// Clave en `RequestOptions.extra` con el token que se adjuntó.
  static const claveTokenUsado = 'token_usado';

  /// Rutas que **no** deben llevar token.
  ///
  /// No es una optimización: enviar un token caducado a `/renovar` haría que el
  /// interceptor de renovación viera un 401 del propio endpoint de renovación y
  /// entrara en bucle. Las de ingreso y registro no tienen sesión todavía.
  static const _sinToken = {
    '/api/usuarios/login',
    '/api/usuarios/registro',
    '/api/usuarios/renovar',
  };

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_sinToken.contains(options.path)) {
      return handler.next(options);
    }

    final token = await credenciales.tokenAcceso();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';

      // Se anota QUÉ token se usó, además de ponerlo en la cabecera.
      //
      // El interceptor de renovación lo necesita para distinguir "mi token
      // caducó" de "otra petición ya renovó mientras yo esperaba en la cola".
      // Leerlo de la cabecera no serviría: Dio normaliza los nombres de
      // cabecera y la comparación dependería de mayúsculas y minúsculas.
      options.extra[claveTokenUsado] = token;
    }

    handler.next(options);
  }
}
