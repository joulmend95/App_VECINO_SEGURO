import 'package:flutter/foundation.dart';

import '../modelos/perfil_vecino.dart';
import 'almacen_seguro.dart';

/// Fase de arranque de la sesión.
enum FaseSesion {
  /// Todavía no se ha intentado restaurar la sesión guardada.
  iniciando,

  /// No hay sesión: hay que ingresar.
  sinSesion,

  /// Hay token y perfil válidos.
  autenticado,
}

/// Estado de sesión de la aplicación.
///
/// Es la **única** fuente de verdad sobre quién está autenticado. Al ser un
/// [ChangeNotifier], el enrutador puede escucharlo con `refreshListenable` y
/// reevaluar las guardias en cuanto la sesión cambia: iniciar sesión, cerrarla
/// o ser aprobado por el administrador redirigen solos, sin que ninguna
/// pantalla tenga que navegar a mano.
class Sesion extends ChangeNotifier {
  Sesion({AlmacenSeguro? almacen})
    : _almacen = almacen ?? const AlmacenSeguroReal();

  static const _claveToken = 'vecino_seguro.token';

  final AlmacenSeguro _almacen;

  FaseSesion _fase = FaseSesion.iniciando;
  String? _token;
  PerfilVecino? _perfil;

  FaseSesion get fase => _fase;
  String? get token => _token;
  PerfilVecino? get perfil => _perfil;

  bool get autenticado => _fase == FaseSesion.autenticado && _token != null;

  /// Estado de pertenencia. Sin sesión se asume "sin comunidad".
  EstadoMembresia get membresia =>
      _perfil?.estadoMembresia ?? EstadoMembresia.sinComunidad;

  /// Carga el token guardado. Se llama una vez al arrancar la app.
  ///
  /// No valida el token contra el servidor: eso lo hace la pantalla de arranque
  /// al pedir el perfil. Si el token caducó, el cliente HTTP recibirá un 403 y
  /// llamará a [cerrar].
  Future<String?> restaurarToken() async {
    _token = await _almacen.leer(_claveToken);
    if (_token == null) {
      _fase = FaseSesion.sinSesion;
      notifyListeners();
    }
    return _token;
  }

  /// Abre sesión tras un ingreso o registro exitoso.
  Future<void> iniciar({required String token, required PerfilVecino perfil}) async {
    _token = token;
    _perfil = perfil;
    _fase = FaseSesion.autenticado;
    await _almacen.escribir(_claveToken, token);
    notifyListeners();
  }

  /// Refresca el perfil sin tocar el token.
  ///
  /// Es lo que hace que una aprobación del administrador surta efecto: cambia
  /// `estadoMembresia` y el enrutador redirige del compás de espera al muro.
  void actualizarPerfil(PerfilVecino perfil) {
    _perfil = perfil;
    _fase = FaseSesion.autenticado;
    notifyListeners();
  }

  /// Cierra la sesión y borra la credencial.
  ///
  /// Se invoca tanto al pulsar "cerrar sesión" como automáticamente cuando el
  /// servidor responde 401/403: una sesión inválida no debe quedar guardada.
  Future<void> cerrar() async {
    _token = null;
    _perfil = null;
    _fase = FaseSesion.sinSesion;
    await _almacen.borrar(_claveToken);
    notifyListeners();
  }
}
