import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/entorno.dart';

/// **3.º de la cadena** — registra peticiones y respuestas. Solo en desarrollo.
///
/// Va el último a propósito: así registra lo que **realmente** salió por el
/// cable, con el token ya inyectado y tras cualquier reintento. Un reintento
/// por renovación aparece como una segunda entrada, de modo que el ciclo
/// completo —401, renovación, repetición con éxito— se lee en el registro. Si
/// fuera el primero, registraría la intención y no el hecho.
///
/// ## Dos reglas de seguridad
///
/// **Nunca imprime el token.** El encabezado `Authorization` sale enmascarado.
/// Un registro con tokens completos es una filtración esperando a ocurrir: los
/// registros acaban en archivos, en capturas de pantalla y en informes de
/// fallos.
///
/// **Nunca imprime cuerpos de autenticación.** `/login`, `/registro` y
/// `/password` llevan contraseñas en claro.
class InterceptorRegistro extends Interceptor {
  const InterceptorRegistro();

  /// Rutas cuyo cuerpo no se registra jamás.
  /// Rutas cuyo cuerpo no se registra jamás: llevan contraseñas en claro.
  static const cuerposSensibles = {
    '/api/usuarios/login',
    '/api/usuarios/registro',
    '/api/usuarios/renovar',
    '/api/usuarios/password',
  };

  static const _oculto = '***';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // `Entorno.registroDetallado` es una constante de compilación: en el
    // binario de producción esta rama se elimina entera, no queda código
    // muerto que alguien pudiera activar.
    if (Entorno.registroDetallado) {
      debugPrint('→ ${options.method} ${options.path}  ${_cabeceras(options.headers)}');
      if (options.data != null && !cuerposSensibles.contains(options.path)) {
        debugPrint('  cuerpo: ${options.data}');
      } else if (options.data != null) {
        debugPrint('  cuerpo: $_oculto (ruta con credenciales)');
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (Entorno.registroDetallado) {
      debugPrint('← ${response.statusCode} ${response.requestOptions.path}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (Entorno.registroDetallado) {
      final codigo = err.response?.statusCode ?? err.type.name;
      debugPrint('✗ $codigo ${err.requestOptions.path}');
    }
    handler.next(err);
  }

  /// Copia de las cabeceras con `Authorization` enmascarado.
  static Map<String, dynamic> _cabeceras(Map<String, dynamic> originales) {
    if (!originales.containsKey('Authorization')) return originales;
    return {...originales, 'Authorization': 'Bearer $_oculto'};
  }
}
