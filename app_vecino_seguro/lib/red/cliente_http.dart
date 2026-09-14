import 'package:dio/dio.dart';

import '../config/entorno.dart';
import 'credenciales.dart';
import 'interceptores/interceptor_autorizacion.dart';
import 'interceptores/interceptor_registro.dart';
import 'interceptores/interceptor_reintento.dart';
import 'interceptores/interceptor_renovacion.dart';

/// Construye **la** instancia de Dio de la aplicación.
///
/// Una sola, configurada en un único sitio. Si cada pantalla o servicio creara
/// la suya, cada una tendría sus propios interceptores: el token se inyectaría
/// en unas y no en otras, y una renovación disparada por una no beneficiaría a
/// las demás. Ese fue el motivo de que `ClienteApi` ya fuera único.
///
/// ## Tiempos de espera
///
/// Separados a propósito. Un servidor que tarda en **aceptar la conexión** (red
/// saturada, DNS lento) y uno que tarda en **responder** (consulta pesada) son
/// problemas distintos y merecen umbrales distintos. El cliente anterior usaba
/// un único límite de 12 segundos y los confundía.
///
/// ## Validación de códigos de estado
///
/// `validateStatus` acepta todo por debajo de 500. Los 4xx llegan como
/// **respuesta interpretable** —con su cuerpo y su lista de `errores`— en lugar
/// de como excepción de transporte, que es lo que permite pintar un 422 campo
/// por campo. Los 5xx sí se convierten en excepción: no hay nada que
/// interpretar en un fallo del servidor.
///
/// ## Orden de los interceptores
///
/// | # | Interceptor | Por qué en esa posición |
/// |---|---|---|
/// | 1 | Autorización | Inyecta el token. Todo lo demás asume que ya viaja |
/// | 2 | Renovación | Debe ver el 401 de una petición **ya autorizada** |
/// | 3 | Reintento | Repite GET ante fallos transitorios. Tras la renovación: un 401 se arregla renovando, no repitiendo |
/// | 4 | Registro | Refleja lo que salió de verdad; cada reintento sale como una entrada más |
///
/// Dio ejecuta `onRequest` en el orden de registro y `onError` también, así que
/// el orden de la lista es el orden real en ambos sentidos.
Dio construirCliente({
  required Credenciales credenciales,
  required Future<void> Function() alPerderSesion,
  HttpClientAdapter? adaptador,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Entorno.urlBase,

      // Establecer la conexión TCP + TLS.
      connectTimeout: const Duration(seconds: 8),

      // Recibir la respuesta completa una vez conectados.
      receiveTimeout: const Duration(seconds: 15),

      // Terminar de enviar el cuerpo.
      sendTimeout: const Duration(seconds: 15),

      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,

      validateStatus: (codigo) => codigo != null && codigo < 500,
    ),
  );

  if (adaptador != null) dio.httpClientAdapter = adaptador;

  final reintento = InterceptorReintento()..usarCliente(dio);

  dio.interceptors.addAll([
    InterceptorAutorizacion(credenciales),
    InterceptorRenovacion(
      dio: dio,
      credenciales: credenciales,
      alPerderSesion: alPerderSesion,
    ),
    // Va **después** de la renovación: un 401 caducado debe resolverse
    // renovando, no repitiendo la misma petición con el mismo token caducado.
    // Solo actúa sobre `GET` y sobre fallos transitorios.
    reintento,
    const InterceptorRegistro(),
  ]);

  return dio;
}
