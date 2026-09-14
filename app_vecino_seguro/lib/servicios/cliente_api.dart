import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../config/entorno.dart';
import '../red/adaptador_pruebas.dart';
import '../red/cliente_http.dart';
import '../red/credenciales.dart';
import '../red/fallos_de_red.dart';
import 'sesion.dart';

/// Error de API ya traducido a un mensaje que se le puede mostrar al usuario.
///
/// Ninguna pantalla ve una excepción cruda: eso evita que un `SocketException`
/// termine impreso en la interfaz.
class ExcepcionApi implements Exception {
  const ExcepcionApi(
    this.mensaje, {
    this.codigo,
    this.esRecuperable = true,
    this.erroresPorCampo = const {},
  });

  final String mensaje;

  /// Código de negocio devuelto por el servidor (`SIN_COMUNIDAD`, `NO_ES_ADMIN`).
  final String? codigo;

  /// `false` cuando reintentar no puede arreglarlo (p. ej. sesión inválida).
  final bool esRecuperable;

  /// Errores de validación por campo, para pintarlos en el formulario.
  ///
  /// El backend devuelve `{ errores: [{campo, mensaje}] }`; se convierten a un
  /// mapa para que cada `CampoTexto` lea el suyo directamente.
  final Map<String, String> erroresPorCampo;

  // --- Códigos que asigna el propio cliente al interpretar la respuesta ---
  /// La petición no llegó a obtener respuesta: sin red, tiempo agotado o
  /// conexión interrumpida.
  ///
  /// Es distinto de cualquier error del servidor: aquí **no sabemos** si la
  /// operación se ejecutó. Por eso una operación encolada que falla así no gasta
  /// intento, y por eso el muro puede servir su caché local.
  static const sinConexion = 'SIN_CONEXION';

  /// 401: no se envió credencial. El destino pretendido sí se conserva.
  static const sesionRequerida = 'SESION_REQUERIDA';

  /// 403 sin código de negocio: token inválido, caducado o cuenta eliminada.
  static const sesionExpirada = 'SESION_EXPIRADA';

  /// 429: el servidor limita a una alerta por vecino cada 60 segundos.
  ///
  /// Existe como código para que nadie tenga que deducirlo del texto del
  /// mensaje. La antigua cola de pánico lo hacía con `e.mensaje.contains(...)`,
  /// que dependía de una cadena en español: cambiar la redacción del servidor
  /// habría roto silenciosamente la lógica de reintento.
  static const limiteFrecuencia = 'LIMITE_FRECUENCIA';

  // --- Códigos de negocio que devuelve el servidor ---
  static const sinComunidad = 'SIN_COMUNIDAD';
  static const noEsAdmin = 'NO_ES_ADMIN';

  /// El rechazo es de permisos, no de credenciales: la sesión sigue siendo
  /// válida y **no** se ha cerrado.
  ///
  /// Existe para que las pantallas no comparen literales sueltos: un
  /// `e.codigo == 'NO_ES_ADMIN'` mal tecleado no falla al compilar, se limita a
  /// no entrar nunca en el `if`.
  bool get esDeAcceso => codigo == sinComunidad || codigo == noEsAdmin;

  /// La sesión se cerró: hay que volver a ingresar.
  bool get exigeIngresar =>
      codigo == sesionRequerida || codigo == sesionExpirada;

  /// No hubo respuesta del servidor. Se puede recurrir a los datos locales.
  bool get esSinConexion => codigo == sinConexion;

  /// El servidor pide esperar (429). No es un rechazo: es un "ahora no".
  bool get esLimiteDeFrecuencia => codigo == limiteFrecuencia;

  /// El vecino abandonó la pantalla. **No es un fallo** y no se muestra.
  bool get fueCancelada => codigo == FallosDeRed.cancelada;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP único de la aplicación.
///
/// ## Por qué Dio y no `http`
///
/// El paquete `http` es un cliente de peticiones; lo que este proyecto necesita
/// es una **capa de transporte con política propia**: inyectar credenciales,
/// renovarlas de forma transparente, registrar sin filtrar secretos, cancelar
/// al abandonar una pantalla y distinguir cuatro clases de fallo de red. Con
/// `http` todo eso habría que escribirlo a mano alrededor de cada llamada.
///
/// Dio lo trae resuelto y probado: cadena de interceptores con orden explícito,
/// `QueuedInterceptor` para serializar renovaciones, `connectTimeout` y
/// `receiveTimeout` separados, `validateStatus` y `CancelToken`.
///
/// Con 14 endpoints y un esquema de token con renovación, escribir esa
/// maquinaria a mano habría sido más código propio —y más frágil— que la
/// dependencia.
///
/// ## Qué concentra
///
/// - Traducir respuestas y fallos de red a [ExcepcionApi].
/// - **Cerrar la sesión** cuando ya no se puede renovar, de modo que el
///   enrutador redirija al ingreso sin que cada pantalla lo gestione.
///
/// La inyección del token y la renovación viven en los interceptores, no aquí.
class ClienteApi {
  ClienteApi({
    required this.sesion,
    http.Client? cliente,
    String? urlBase,
  }) : urlBase = urlBase ?? Entorno.urlBase {
    _dio = construirCliente(
      credenciales: Credenciales(sesion.almacen),
      alPerderSesion: sesion.cerrar,
      // En pruebas se inyecta un `http.Client` simulado: se envuelve en el
      // adaptador para que Dio hable con él. Ver `AdaptadorDeCliente`.
      adaptador: cliente == null ? null : AdaptadorDeCliente(cliente),
    );
    if (urlBase != null) _dio.options.baseUrl = urlBase;
  }

  final Sesion sesion;
  final String urlBase;
  late final Dio _dio;

  /// Acceso al cliente subyacente. Lo usan las fuentes remotas para pasar un
  /// `CancelToken`; ninguna pantalla lo toca.
  Dio get dio => _dio;

  /// Dirección de desarrollo. Se conserva por compatibilidad; la fuente de
  /// verdad es [Entorno.urlBase].
  static String get urlBasePorDefecto => Entorno.urlBase;

  Future<Map<String, dynamic>> obtener(
    String ruta, {
    CancelToken? cancelacion,
  }) => _ejecutar(() => _dio.get(ruta, cancelToken: cancelacion));

  Future<Map<String, dynamic>> publicar(
    String ruta, {
    Map<String, dynamic>? cuerpo,
    CancelToken? cancelacion,
  }) => _ejecutar(
    () => _dio.post(ruta, data: cuerpo ?? const {}, cancelToken: cancelacion),
  );

  Future<Map<String, dynamic>> parchear(
    String ruta, {
    Map<String, dynamic>? cuerpo,
    CancelToken? cancelacion,
  }) => _ejecutar(
    () => _dio.patch(ruta, data: cuerpo ?? const {}, cancelToken: cancelacion),
  );

  Future<Map<String, dynamic>> eliminar(
    String ruta, {
    Map<String, dynamic>? cuerpo,
    CancelToken? cancelacion,
  }) => _ejecutar(
    () => _dio.delete(ruta, data: cuerpo, cancelToken: cancelacion),
  );

  Future<Map<String, dynamic>> _ejecutar(
    Future<Response<dynamic>> Function() peticion,
  ) async {
    final Response<dynamic> respuesta;
    try {
      respuesta = await peticion();
    } on DioException catch (e) {
      // Las cuatro familias de fallo de red, más la cancelación.
      throw FallosDeRed.traducir(e, urlBase);
    }

    return _interpretar(respuesta);
  }

  /// Convierte la respuesta en datos o en [ExcepcionApi].
  ///
  /// Los 4xx llegan aquí como **respuesta**, no como excepción, porque
  /// `validateStatus` acepta todo por debajo de 500. Es lo que permite leer el
  /// cuerpo de un 422 y repartir sus errores campo por campo.
  Future<Map<String, dynamic>> _interpretar(Response<dynamic> respuesta) async {
    final cuerpo = _comoMapa(respuesta.data);

    final codigo = respuesta.statusCode ?? 0;
    if (codigo >= 200 && codigo < 300) return cuerpo;

    final mensaje = cuerpo['mensaje'] as String?;
    final codigoNegocio = cuerpo['codigo'] as String?;

    // --- Rechazos de acceso: 401 y 403 NO significan lo mismo --------------
    //
    // Se resuelven aquí, en un solo lugar. Sin esto, cada pantalla tendría que
    // detectarlos y navegar por su cuenta, y la que se olvidara dejaría al
    // usuario atrapado en una pantalla que ya no carga.
    if (codigo == 401) {
      // Un `TOKEN_EXPIRADO` que llega hasta aquí significa que el interceptor
      // de renovación ya lo intentó y no pudo: la sesión está perdida de
      // verdad y él mismo se encargó de cerrarla.
      if (codigoNegocio != 'TOKEN_EXPIRADO') await sesion.cerrar();

      throw ExcepcionApi(
        mensaje ?? 'Se requiere iniciar sesión.',
        codigo: ExcepcionApi.sesionRequerida,
        esRecuperable: false,
      );
    }

    // 403 sin código de negocio — el token no es válido: firma manipulada o
    // cuenta eliminada. Se cierra sesión, pero se marca distinto para que la
    // guardia NO conserve el destino: si la credencial dejó de ser de fiar,
    // tampoco lo es el rastro de a dónde iba.
    if (codigo == 403 && codigoNegocio == null) {
      await sesion.cerrar();
      throw ExcepcionApi(
        mensaje ?? 'Tu sesión expiró. Vuelve a ingresar.',
        codigo: ExcepcionApi.sesionExpirada,
        esRecuperable: false,
      );
    }

    // 403 CON código de negocio (SIN_COMUNIDAD, NO_ES_ADMIN) no llega a la
    // rama anterior a propósito: el vecino está perfectamente autenticado,
    // solo le falta pertenencia o permisos. Cerrar sesión ahí sería expulsarlo
    // por un cambio de rol. Cae al final, con su `codigo` intacto.

    // 422 — la petición está bien formada y el contenido de los campos no.
    // 400 — dato correcto, operación improcedente (un :id inválido, la
    // contraseña actual que no coincide). El servidor también adjunta el campo
    // afectado en ese caso, así que ambos se reparten igual por el formulario.
    if (codigo == 422 || codigo == 400) {
      throw ExcepcionApi(
        mensaje ?? 'Revisa los datos ingresados.',
        erroresPorCampo: _extraerErrores(cuerpo),
      );
    }

    if (codigo == 429) {
      throw ExcepcionApi(
        mensaje ?? 'Espera un momento antes de volver a intentarlo.',
        codigo: ExcepcionApi.limiteFrecuencia,
      );
    }

    if (codigo >= 500) {
      throw const ExcepcionApi(
        'El servidor tuvo un problema. Inténtalo en unos momentos.',
      );
    }

    throw ExcepcionApi(
      mensaje ?? 'No pudimos completar la operación (código $codigo).',
      codigo: codigoNegocio,
    );
  }

  /// Normaliza el cuerpo de la respuesta a mapa.
  ///
  /// Dio solo convierte a JSON cuando la respuesta declara `content-type:
  /// application/json`. Un servidor que devuelve JSON sin esa cabecera —cosa
  /// frecuente en respuestas de error— dejaría el cuerpo como texto, y todos
  /// los campos se leerían como ausentes: el vecino vería una lista vacía en
  /// lugar de sus alertas, sin ningún error que lo delatara.
  ///
  /// Se intenta interpretar el texto antes de darlo por perdido.
  static Map<String, dynamic> _comoMapa(Object? crudo) {
    if (crudo is Map<String, dynamic>) return crudo;

    if (crudo is String && crudo.isNotEmpty) {
      try {
        final decodificado = jsonDecode(crudo);
        if (decodificado is Map<String, dynamic>) return decodificado;
      } on FormatException {
        // No era JSON. El código de estado sigue bastando para decidir.
      }
    }

    return const <String, dynamic>{};
  }

  /// Convierte `[{campo, mensaje}]` en `{campo: mensaje}`.
  static Map<String, String> _extraerErrores(Map<String, dynamic> cuerpo) {
    final lista = cuerpo['errores'];
    if (lista is! List) return const {};

    return {
      for (final e in lista.whereType<Map<String, dynamic>>())
        if (e['campo'] is String && e['mensaje'] is String)
          e['campo'] as String: e['mensaje'] as String,
    };
  }

  void cerrar() => _dio.close();
}
