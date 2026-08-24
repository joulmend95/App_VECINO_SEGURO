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
      throw const ExcepcionApi(
        'El servidor tardó demasiado en responder. Revisa tu conexión.',
      );
    } on SocketException {
      throw ExcepcionApi(
        'No pudimos conectarnos al servidor.\n'
        'Verifica que el backend esté corriendo en $urlBase',
      );
    } on http.ClientException {
      throw const ExcepcionApi('Se interrumpió la comunicación con el servidor.');
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

    // --- Sesión inválida ---------------------------------------------------
    // Se cierra la sesión aquí, en un solo lugar. Sin esto, cada pantalla
    // tendría que detectar el 401 y navegar al ingreso por su cuenta, y la que
    // se olvidara dejaría al usuario atrapado en una pantalla que ya no carga.
    //
    // Excepción: un 403 con código de negocio (SIN_COMUNIDAD, NO_ES_ADMIN) NO
    // es una sesión inválida — el vecino está autenticado, simplemente le falta
    // pertenencia o permisos. Cerrar sesión ahí sería expulsarlo por error.
    final codigoNegocio = cuerpo['codigo'] as String?;
    if ((codigo == 401 || codigo == 403) && codigoNegocio == null) {
      await sesion.cerrar();
      throw ExcepcionApi(
        mensaje ?? 'Tu sesión expiró. Vuelve a ingresar.',
        esRecuperable: false,
      );
    }

    if (codigo == 400) {
      throw ExcepcionApi(
        mensaje ?? 'Revisa los datos ingresados.',
        erroresPorCampo: _extraerErrores(cuerpo),
      );
    }

    if (codigo == 429) {
      throw ExcepcionApi(mensaje ?? 'Espera un momento antes de volver a intentarlo.');
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
