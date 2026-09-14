import 'package:dio/dio.dart';

import '../servicios/cliente_api.dart' show ExcepcionApi;

/// Traduce los fallos de transporte de Dio a errores del dominio.
///
/// ## Las cuatro familias
///
/// No son cuatro mensajes distintos por gusto: cada una corresponde a algo
/// **distinto que le pasa al vecino** y a una acción distinta por su parte.
///
/// | Familia | Qué ocurrió | Qué puede hacer |
/// |---|---|---|
/// | Sin conexión | La petición no salió del teléfono | Revisar su red |
/// | Tiempo agotado | Salió, pero nadie contestó a tiempo | Reintentar |
/// | Certificado no confiable | Alguien se interpone en la comunicación | Desconfiar |
/// | Respuesta ilegible | Contestaron algo que no entendemos | Avisar |
///
/// La cancelación **no es un fallo**: significa que el vecino se fue de la
/// pantalla. Se marca aparte para que nadie le muestre un error por irse.
abstract final class FallosDeRed {
  FallosDeRed._();

  /// El vecino canceló al abandonar la pantalla. No se muestra nada.
  static const cancelada = 'PETICION_CANCELADA';

  /// El tiempo de espera se agotó. Es distinto de "sin conexión": aquí sí hay
  /// red, pero el servidor no responde a tiempo.
  static const tiempoAgotado = 'TIEMPO_AGOTADO';

  /// El certificado TLS no es de fiar.
  static const certificadoNoConfiable = 'CERTIFICADO_NO_CONFIABLE';

  /// El servidor contestó algo que no se puede interpretar.
  static const respuestaIlegible = 'RESPUESTA_ILEGIBLE';

  /// Convierte una excepción de Dio en [ExcepcionApi].
  static ExcepcionApi traducir(DioException e, String urlBase) {
    // Un 5xx es un problema del servidor **aunque su cuerpo sea ilegible**.
    //
    // Se comprueba antes del `switch` porque el tipo de la excepción no lo
    // refleja: un 500 que devuelve una traza en texto plano en lugar de JSON
    // llega como fallo de transformación, no como `badResponse`. Sin esta
    // comprobación se le diría al vecino "el servidor respondió algo que no
    // entendemos", que es cierto pero inútil: el problema real es que el
    // servidor falló.
    final codigo = e.response?.statusCode ?? 0;
    if (codigo >= 500) {
      return const ExcepcionApi(
        'El servidor tuvo un problema. Inténtalo en unos momentos.',
      );
    }

    switch (e.type) {
      // --- 1. Sin conexión ------------------------------------------------
      // La petición no llegó a salir: no hay red, el DNS no resuelve o el
      // host es inalcanzable.
      case DioExceptionType.connectionError:
        return const ExcepcionApi(
          'No pudimos conectarnos.\nComprueba tu conexión a internet.',
          codigo: ExcepcionApi.sinConexion,
        );

      // --- 2. Tiempo de espera agotado ------------------------------------
      // Se distinguen los tres momentos en el registro, pero el vecino recibe
      // un solo mensaje: la diferencia entre "no conectó" y "no respondió" le
      // es indiferente, y en ambos casos la acción es la misma.
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      // Transformar la respuesta también tarda demasiado: un cuerpo enorme o
      // malformado. Para el vecino es el mismo problema — algo se atascó.
      case DioExceptionType.transformTimeout:
        return const ExcepcionApi(
          'El servidor está tardando demasiado.\nInténtalo de nuevo en un momento.',
          codigo: FallosDeRed.tiempoAgotado,
        );

      // --- 3. Certificado no confiable ------------------------------------
      // Mensaje deliberadamente alarmante, y sin ofrecer "reintentar". Es el
      // síntoma de que alguien se interpone en la comunicación, y en una app
      // que transporta credenciales y alertas de emergencia, insistir sería
      // peor que fallar.
      case DioExceptionType.badCertificate:
        return const ExcepcionApi(
          'No pudimos verificar la identidad del servidor.\n'
          'Por seguridad, la conexión se ha detenido.',
          codigo: FallosDeRed.certificadoNoConfiable,
          esRecuperable: false,
        );

      // --- Cancelación: no es un fallo ------------------------------------
      case DioExceptionType.cancel:
        return const ExcepcionApi(
          'Petición cancelada.',
          codigo: FallosDeRed.cancelada,
        );

      // --- 4. Respuesta ilegible ------------------------------------------
      // `badResponse` llega aquí solo con 5xx, porque `validateStatus` deja
      // pasar los 4xx como respuesta interpretable.
      case DioExceptionType.badResponse:
        final codigo = e.response?.statusCode ?? 0;
        if (codigo >= 500) {
          return const ExcepcionApi(
            'El servidor tuvo un problema. Inténtalo en unos momentos.',
          );
        }
        return const ExcepcionApi(
          'El servidor respondió algo que no entendemos.',
          codigo: FallosDeRed.respuestaIlegible,
        );

      case DioExceptionType.unknown:
        // Un `SocketException` envuelto llega como `unknown`. Se reconoce por
        // el error subyacente en lugar de asumir que es un fallo genérico.
        final causa = e.error?.toString() ?? '';
        if (causa.contains('SocketException') ||
            causa.contains('Failed host lookup')) {
          return ExcepcionApi(
            'No pudimos conectarnos.\nComprueba tu conexión a internet.',
            codigo: ExcepcionApi.sinConexion,
          );
        }
        return const ExcepcionApi(
          'El servidor respondió algo que no entendemos.',
          codigo: FallosDeRed.respuestaIlegible,
        );
    }
  }
}
