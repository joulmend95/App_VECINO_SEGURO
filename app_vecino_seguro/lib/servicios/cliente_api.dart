import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  /// mensaje. `ColaPanico` lo hacía con `e.mensaje.contains('Espera')`, que
  /// dependía de una cadena en español: cambiar la redacción del servidor
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

  @override
  String toString() => mensaje;
}

/// Cliente HTTP único de la aplicación.
///
/// Responsabilidades que concentra para que ninguna pantalla las repita:
/// - Adjuntar el `Authorization: Bearer` de la sesión activa.
/// - Traducir fallos de red y códigos HTTP a [ExcepcionApi].
/// - **Cerrar la sesión ante un 401/403** y avisar a la app, de modo que el
///   enrutador redirija al ingreso sin que cada pantalla lo gestione.
class ClienteApi {
  ClienteApi({
    required this.sesion,
    http.Client? cliente,
    String? urlBase,
  }) : _cliente = cliente ?? http.Client(),
       urlBase = urlBase ?? urlBasePorDefecto;

  final Sesion sesion;
  final String urlBase;
  final http.Client _cliente;

  static const _tiempoLimite = Duration(seconds: 12);

  /// El emulador de Android no ve `localhost` del anfitrión: lo alcanza por la
  /// IP especial 10.0.2.2. En escritorio y web sí es `localhost`.
  static String get urlBasePorDefecto {
    const puerto = 3333;
    if (kIsWeb) return 'http://localhost:$puerto';
    if (Platform.isAndroid) return 'http://10.0.2.2:$puerto';
    return 'http://localhost:$puerto';
  }

  Map<String, String> _cabeceras() {
    final token = sesion.token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> obtener(String ruta) =>
      _ejecutar(() => _cliente.get(_uri(ruta), headers: _cabeceras()));

  Future<Map<String, dynamic>> publicar(
    String ruta, {
    Map<String, dynamic>? cuerpo,
  }) => _ejecutar(
    () => _cliente.post(
      _uri(ruta),
      headers: _cabeceras(),
      body: jsonEncode(cuerpo ?? const {}),
    ),
  );

  Future<Map<String, dynamic>> parchear(
    String ruta, {
    Map<String, dynamic>? cuerpo,
  }) => _ejecutar(
    () => _cliente.patch(
      _uri(ruta),
      headers: _cabeceras(),
      body: jsonEncode(cuerpo ?? const {}),
    ),
  );

  Future<Map<String, dynamic>> eliminar(
    String ruta, {
    Map<String, dynamic>? cuerpo,
  }) => _ejecutar(
    () => _cliente.delete(
      _uri(ruta),
      headers: _cabeceras(),
      body: cuerpo == null ? null : jsonEncode(cuerpo),
    ),
  );

  Uri _uri(String ruta) => Uri.parse('$urlBase$ruta');

  Future<Map<String, dynamic>> _ejecutar(
    Future<http.Response> Function() peticion,
  ) async {
    final http.Response respuesta;
    try {
      respuesta = await peticion().timeout(_tiempoLimite);
    } on TimeoutException {
      // Los tres fallos de transporte llevan el mismo código. Sin él, "no hay
      // red" era indistinguible de "el servidor respondió 500", y eso importa:
      // ante un fallo de red tiene sentido servir la caché local y conservar la
      // operación en la cola; ante un 500 del servidor, no.
      throw const ExcepcionApi(
        'El servidor tardó demasiado en responder. Revisa tu conexión.',
        codigo: ExcepcionApi.sinConexion,
      );
    } on SocketException {
      // La URL del servidor va al registro de depuración, NO al mensaje: a un
      // vecino no le dice nada que el backend viva en 10.0.2.2:3333, y además
      // expone detalle interno de la infraestructura. Aquí sigue disponible
      // para quien desarrolla, que es a quien le sirve.
      debugPrint('[API] Sin conexión con $urlBase');
      throw const ExcepcionApi(
        'No pudimos conectarnos.\nComprueba tu conexión a internet.',
        codigo: ExcepcionApi.sinConexion,
      );
    } on http.ClientException {
      throw const ExcepcionApi(
        'Se interrumpió la comunicación con el servidor.',
        codigo: ExcepcionApi.sinConexion,
      );
    }

    return _interpretar(respuesta);
  }

  Future<Map<String, dynamic>> _interpretar(http.Response respuesta) async {
    Map<String, dynamic> cuerpo = const {};
    if (respuesta.body.isNotEmpty) {
      try {
        final decodificado = jsonDecode(respuesta.body);
        if (decodificado is Map<String, dynamic>) cuerpo = decodificado;
      } on FormatException {
        // Se ignora: algunos errores del servidor no devuelven JSON. El código
        // de estado sigue siendo suficiente para decidir qué hacer.
      }
    }

    final codigo = respuesta.statusCode;

    if (codigo >= 200 && codigo < 300) return cuerpo;

    final mensaje = cuerpo['mensaje'] as String?;

    // --- Rechazos de acceso: 401 y 403 NO significan lo mismo --------------
    //
    // Se resuelven aquí, en un solo lugar. Sin esto, cada pantalla tendría que
    // detectarlos y navegar por su cuenta, y la que se olvidara dejaría al
    // usuario atrapado en una pantalla que ya no carga.
    final codigoNegocio = cuerpo['codigo'] as String?;

    // 401 — no se envió credencial. La sesión local ya no sirve, pero el
    // destino al que iba sigue siendo válido: la guardia lo recuerda en
    // `?destino=` y lo devuelve ahí en cuanto vuelva a ingresar.
    if (codigo == 401) {
      await sesion.cerrar();
      throw ExcepcionApi(
        mensaje ?? 'Se requiere iniciar sesión.',
        codigo: ExcepcionApi.sesionRequerida,
        esRecuperable: false,
      );
    }

    // 403 sin código de negocio — el token existe pero el servidor lo rechaza:
    // firma inválida, caducado, o la cuenta ya no está. Se cierra sesión igual
    // que en el 401, pero se marca distinto para que la guardia NO conserve el
    // destino: si la credencial dejó de ser de fiar, tampoco lo es el rastro
    // de a dónde iba.
    if (codigo == 403 && codigoNegocio == null) {
      await sesion.cerrar();
      throw ExcepcionApi(
        mensaje ?? 'Tu sesión expiró. Vuelve a ingresar.',
        codigo: ExcepcionApi.sesionExpirada,
        esRecuperable: false,
      );
    }

    // 403 CON código de negocio (SIN_COMUNIDAD, NO_ES_ADMIN) no llega a las
    // ramas anteriores a propósito: el vecino está perfectamente autenticado,
    // solo le falta pertenencia o permisos. Cerrar sesión ahí sería expulsarlo
    // por un cambio de rol. Cae al final del método, con su `codigo` intacto,
    // y la pantalla decide (ver `PantallaSinPermiso`).

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

  void cerrar() => _cliente.close();
}
