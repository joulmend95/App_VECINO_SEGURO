import '../modelos/perfil_vecino.dart';
import 'cliente_api.dart';
import 'sesion.dart';

/// Resultado de un ingreso o registro: token + perfil.
class ResultadoAutenticacion {
  const ResultadoAutenticacion({required this.token, required this.perfil});

  final String token;
  final PerfilVecino perfil;

  factory ResultadoAutenticacion.desdeJson(Map<String, dynamic> json) {
    return ResultadoAutenticacion(
      token: json['token'] as String? ?? '',
      perfil: PerfilVecino.desdeJson(
        (json['perfil'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

/// Operaciones de cuenta: registro, ingreso y perfil.
class ServicioUsuarios {
  const ServicioUsuarios(this._api);

  final ClienteApi _api;

  Sesion get _sesion => _api.sesion;

  /// `POST /api/usuarios/registro` — crea la cuenta **sin comunidad**.
  ///
  /// El backend devuelve el token junto con el perfil, así que el vecino entra
  /// directo sin un segundo viaje al servidor.
  Future<PerfilVecino> registrar({
    required String nombre,
    required String telefono,
    required String password,
  }) async {
    final json = await _api.publicar(
      '/api/usuarios/registro',
      cuerpo: {'nombre': nombre, 'telefono': telefono, 'password': password},
    );

    return _abrirSesion(json);
  }

  /// `POST /api/usuarios/login` — ingreso con teléfono y contraseña.
  Future<PerfilVecino> ingresar({
    required String telefono,
    required String password,
  }) async {
    final json = await _api.publicar(
      '/api/usuarios/login',
      cuerpo: {'telefono': telefono, 'password': password},
    );

    return _abrirSesion(json);
  }

  /// `GET /api/usuarios/yo` — perfil y estado de pertenencia.
  ///
  /// Es la llamada que decide a qué pantalla entra la app, y la que detecta que
  /// el administrador ya aprobó la solicitud.
  Future<PerfilVecino> obtenerPerfil() async {
    final json = await _api.obtener('/api/usuarios/yo');
    final perfil = PerfilVecino.desdeJson(json);
    await _sesion.actualizarPerfil(perfil);
    return perfil;
  }

  /// `PATCH /api/usuarios/yo` — actualizar nombre y teléfono.
  ///
  /// Refresca la sesión con el perfil devuelto, para que el nombre nuevo
  /// aparezca de inmediato en el menú y en el resto de pantallas.
  Future<PerfilVecino> actualizarPerfil({
    String? nombre,
    String? telefono,
  }) async {
    final json = await _api.parchear(
      '/api/usuarios/yo',
      cuerpo: {
        'nombre': ?nombre,
        'telefono': ?telefono,
      },
    );

    final perfil = PerfilVecino.desdeJson(
      (json['perfil'] as Map<String, dynamic>?) ?? const {},
    );
    await _sesion.actualizarPerfil(perfil);
    return perfil;
  }

  /// `PATCH /api/usuarios/password` — cambiar la contraseña.
  ///
  /// Exige la actual: sin esa comprobación, alguien con acceso momentáneo al
  /// teléfono desbloqueado podría cambiarla y dejar fuera al dueño.
  Future<void> cambiarPassword({
    required String actual,
    required String nueva,
  }) async {
    await _api.parchear(
      '/api/usuarios/password',
      cuerpo: {'password_actual': actual, 'password_nueva': nueva},
    );
  }

  Future<PerfilVecino> _abrirSesion(Map<String, dynamic> json) async {
    final resultado = ResultadoAutenticacion.desdeJson(json);

    if (resultado.token.isEmpty) {
      throw const ExcepcionApi(
        'El servidor no devolvió un token de sesión válido.',
        esRecuperable: false,
      );
    }

    await _sesion.iniciar(token: resultado.token, perfil: resultado.perfil);
    return resultado.perfil;
  }
}
