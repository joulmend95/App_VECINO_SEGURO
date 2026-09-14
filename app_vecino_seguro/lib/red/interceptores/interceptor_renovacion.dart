import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../credenciales.dart';
import 'interceptor_autorizacion.dart';

/// **2.º de la cadena** — renueva el token ante un 401 y reintenta la petición.
///
/// Va después de [InterceptorAutorizacion] porque necesita ver el 401 que
/// produce una petición **ya autorizada**: si fuera antes, vería peticiones sin
/// token y no podría distinguir "caducó" de "nunca hubo sesión".
///
/// ## Tres problemas que resuelve, y cómo
///
/// **1. Renovar y reintentar.** Ante un 401 con `codigo: TOKEN_EXPIRADO`, pide
/// un par nuevo a `/api/usuarios/renovar` y repite la petición original con
/// `dio.fetch`. El vecino no ve nada: para él la petición simplemente funcionó.
///
/// **2. El bucle infinito.** Cada petición reintentada se marca en `extra`. Si
/// una petición ya marcada vuelve a dar 401, **no se renueva otra vez**: se
/// propaga el error. Sin esta marca, un servidor que devuelve 401 incluso con
/// un token recién emitido —por un reloj desajustado, por ejemplo— haría girar
/// la aplicación para siempre, consumiendo datos y batería en silencio.
///
/// **3. Renovaciones concurrentes.** Se extiende [QueuedInterceptor], no
/// [Interceptor]. Dio **serializa** las peticiones que entran en un interceptor
/// encolado: si cinco peticiones caducan a la vez, la primera renueva y las
/// otras cuatro esperan su turno. Al llegarles el turno, la comprobación de
/// `_renovacionEnCurso` y el token ya actualizado hacen que reutilicen el
/// resultado en lugar de disparar cinco renovaciones —que además, con rotación
/// activada en el servidor, se invalidarían entre sí y cerrarían la sesión.
class InterceptorRenovacion extends QueuedInterceptor {
  InterceptorRenovacion({
    required this.dio,
    required this.credenciales,
    required this.alPerderSesion,
  });

  final Dio dio;
  final Credenciales credenciales;

  /// Se invoca cuando la renovación ya no es posible. La aplicación cierra la
  /// sesión y el enrutador lleva al ingreso.
  final Future<void> Function() alPerderSesion;

  /// Marca anti-bucle. Vive en `RequestOptions.extra`, que Dio conserva a
  /// través del reintento.
  static const marcaReintento = 'reintentada_tras_renovar';

  static const rutaRenovar = '/api/usuarios/renovar';

  /// Renovación en vuelo, si la hay. Refuerza a [QueuedInterceptor] para el
  /// caso de una renovación disparada desde fuera de la cola.
  Future<String?>? _renovacionEnCurso;

  Dio? _sinInterceptores;

  /// Cliente que comparte transporte con [dio] pero **no** sus interceptores.
  ///
  /// Es imprescindible, y el motivo es sutil: [QueuedInterceptor] atiende las
  /// respuestas de una en una. Mientras este interceptor está esperando el
  /// resultado del reintento, la cola de respuestas **sigue ocupada por la
  /// respuesta original**. Si el reintento se lanzara con `dio`, su respuesta
  /// entraría en esa misma cola y quedaría esperando a que termine quien la
  /// está esperando a ella: un abrazo mortal que congela la petición para
  /// siempre.
  ///
  /// Saltarse los interceptores es seguro aquí porque este código ya hace su
  /// trabajo a mano: pone el `Authorization` nuevo antes de reintentar, y la
  /// marca anti-bucle impide una segunda renovación.
  Dio get _reintentador {
    return _sinInterceptores ??= Dio(
      BaseOptions(
        baseUrl: dio.options.baseUrl,
        connectTimeout: dio.options.connectTimeout,
        receiveTimeout: dio.options.receiveTimeout,
        sendTimeout: dio.options.sendTimeout,
        contentType: dio.options.contentType,
        responseType: dio.options.responseType,
        validateStatus: dio.options.validateStatus,
      ),
    )..httpClientAdapter = dio.httpClientAdapter;
  }

  /// La renovación se atiende en `onResponse`, **no** en `onError`.
  ///
  /// Es consecuencia directa de `validateStatus: (c) => c < 500`, que el propio
  /// enunciado pide para que los errores de cliente lleguen interpretables: con
  /// esa regla un 401 **no** es una excepción de Dio, es una respuesta con
  /// código 401. Si la renovación viviera en `onError`, no llegaría a verlo
  /// nunca y el interceptor sería código muerto.
  ///
  /// Los dos requisitos —4xx interpretables y renovación ante 401— interactúan,
  /// y este es el punto donde se concilian.
  @override
  Future<void> onResponse(
    Response respuesta,
    ResponseInterceptorHandler handler,
  ) async {
    if (!_esTokenExpiradoEnRespuesta(respuesta)) {
      return handler.next(respuesta);
    }

    final peticion = respuesta.requestOptions;

    if (peticion.extra[marcaReintento] == true) {
      debugPrint(
        '[RENOVACION] La petición ya se reintentó y sigue dando 401. '
        'Se abandona para no entrar en bucle.',
      );
      await alPerderSesion();
      return handler.next(respuesta);
    }

    if (peticion.path == rutaRenovar) {
      await alPerderSesion();
      return handler.next(respuesta);
    }

    // --- Varias peticiones que caducan a la vez ---------------------------
    //
    // [QueuedInterceptor] las atiende de una en una, pero eso no basta: cuando
    // le llega el turno a la segunda, su respuesta 401 ya es **vieja**, porque
    // se generó con el token anterior y otra petición ya renovó mientras
    // esperaba en la cola. Sin esta comprobación, cinco peticiones caducadas
    // producirían cinco renovaciones; y como el servidor rota el token, cada
    // una invalidaría a la anterior y la última reutilización cerraría todas
    // las sesiones del vecino.
    //
    // Comparar el token que usó la petición con el que hay guardado ahora
    // distingue "hay que renovar" de "ya renovó otro, solo hay que reintentar".
    final tokenGuardado = await credenciales.tokenAcceso();
    final tokenUsado = peticion.extra[InterceptorAutorizacion.claveTokenUsado];

    if (tokenGuardado != null && tokenUsado != null && tokenUsado != tokenGuardado) {
      debugPrint('[RENOVACION] Otra petición ya renovó. Solo se reintenta.');
      return _reintentar(peticion, tokenGuardado, handler);
    }

    final tokenNuevo = await _renovar();
    if (tokenNuevo == null) {
      await alPerderSesion();
      return handler.next(respuesta);
    }

    return _reintentar(peticion, tokenNuevo, handler);
  }

  /// Repite la petición con el token indicado.
  ///
  /// Va por [_reintentador], que no tiene interceptores. Eso hace que el bucle
  /// infinito sea **estructuralmente imposible**: la respuesta del reintento no
  /// vuelve a entrar en esta cadena, así que no puede disparar otra renovación
  /// por mucho que siga fallando. La marca en `extra` se mantiene igualmente
  /// como segunda barrera para el camino de `onError`.
  ///
  /// El precio de esa elección es que hay que comprobar **aquí** si el
  /// reintento volvió a dar 401: nadie más va a verlo.
  Future<void> _reintentar(
    RequestOptions peticion,
    String token,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      peticion.extra[marcaReintento] = true;
      peticion.headers['Authorization'] = 'Bearer $token';

      final respuesta = await _reintentador.fetch(peticion);

      // Renovamos, reintentamos, y el servidor sigue diciendo que no. La
      // credencial nueva tampoco sirve: no queda nada que intentar.
      if (_esTokenExpiradoEnRespuesta(respuesta)) {
        debugPrint(
          '[RENOVACION] El token renovado también fue rechazado. '
          'Se abandona la sesión en lugar de insistir.',
        );
        await alPerderSesion();
      }

      return handler.resolve(respuesta);
    } on DioException catch (e) {
      return handler.reject(e);
    }
  }

  /// Camino alterno: si alguien endurece `validateStatus` y el 401 vuelve a ser
  /// excepción, la renovación sigue funcionando. Se conserva para que un cambio
  /// de configuración no rompa la renovación en silencio.
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_esTokenExpirado(err)) return handler.next(err);

    final peticion = err.requestOptions;

    // --- La marca anti-bucle -----------------------------------------------
    if (peticion.extra[marcaReintento] == true) {
      debugPrint(
        '[RENOVACION] La petición ya se reintentó y sigue dando 401. '
        'Se abandona para no entrar en bucle.',
      );
      await alPerderSesion();
      return handler.next(err);
    }

    // El propio endpoint de renovación no se renueva a sí mismo.
    if (peticion.path == rutaRenovar) {
      await alPerderSesion();
      return handler.next(err);
    }

    final tokenNuevo = await _renovar();

    if (tokenNuevo == null) {
      await alPerderSesion();
      return handler.next(err);
    }

    try {
      peticion.extra[marcaReintento] = true;
      peticion.headers['Authorization'] = 'Bearer $tokenNuevo';

      final respuesta = await _reintentador.fetch(peticion);
      return handler.resolve(respuesta);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Renueva, reutilizando la renovación en curso si ya hay una.
  Future<String?> _renovar() {
    return _renovacionEnCurso ??= _pedirParNuevo().whenComplete(() {
      _renovacionEnCurso = null;
    });
  }

  Future<String?> _pedirParNuevo() async {
    final renovacion = await credenciales.tokenRenovacion();
    if (renovacion == null) return null;

    try {
      // Por el cliente sin interceptores: si usara `dio`, la petición pasaría
      // otra vez por esta misma cadena y un 401 aquí dispararía una renovación
      // anidada.
      final respuesta = await _reintentador.post(
        rutaRenovar,
        data: {'token_renovacion': renovacion},
      );

      // `validateStatus` deja pasar los 4xx como respuesta: un token de
      // renovación caducado llega aquí con código 401, no como excepción.
      if (respuesta.statusCode != 200) {
        debugPrint('[RENOVACION] Rechazada: ${respuesta.statusCode}');
        return null;
      }

      final datos = respuesta.data;
      if (datos is! Map) return null;

      final acceso = datos['token'] as String?;
      if (acceso == null) return null;

      await credenciales.guardar(
        acceso: acceso,
        // El servidor ROTA el token de renovación: el anterior queda revocado.
        // Guardar el nuevo no es opcional — con el viejo, la próxima renovación
        // se interpretaría como reutilización y cerraría todas las sesiones.
        renovacion: datos['token_renovacion'] as String?,
      );

      debugPrint('[RENOVACION] Sesión renovada.');
      return acceso;
    } on DioException catch (e) {
      debugPrint('[RENOVACION] No se pudo renovar: ${e.response?.statusCode}');
      return null;
    }
  }

  /// Solo el 401 con `codigo: TOKEN_EXPIRADO` es renovable.
  ///
  /// Un 401 sin código significa que faltaba la credencial, y un 403 que hay
  /// sesión pero no permisos. Ninguno de los dos se arregla renovando.
  static bool _esTokenExpirado(DioException error) =>
      _esTokenExpiradoEnRespuesta(error.response);

  static bool _esTokenExpiradoEnRespuesta(Response? respuesta) {
    if (respuesta?.statusCode != 401) return false;
    final datos = respuesta?.data;
    return datos is Map && datos['codigo'] == 'TOKEN_EXPIRADO';
  }
}
