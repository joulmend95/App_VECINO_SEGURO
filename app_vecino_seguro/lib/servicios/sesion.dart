import 'dart:convert';

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
  Sesion({AlmacenSeguro? almacen, this.alCerrarSesion})
    : _almacen = almacen ?? const AlmacenSeguroReal();

  static const _claveToken = 'vecino_seguro.token';

  /// Perfil del vecino, guardado **cifrado**.
  ///
  /// Lleva nombre y teléfono: es dato personal, así que no puede vivir en
  /// `SharedPreferences` en texto plano junto a las preferencias.
  static const _clavePerfil = 'vecino_seguro.perfil';

  final AlmacenSeguro _almacen;

  /// Se ejecuta al cerrar sesión, antes de notificar.
  ///
  /// Es el gancho por el que se purga todo lo demás —base local, cola, borrador,
  /// preferencias—. `Sesion` no conoce esos almacenes, y no debe: quien los
  /// conoce es `Servicios`.
  ///
  /// Es asignable y no un parámetro del constructor porque la dependencia es
  /// circular: `Servicios` necesita la `Sesion` para construirse, así que no
  /// puede existir antes que ella.
  Future<void> Function()? alCerrarSesion;

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

  /// Restaura la sesión guardada. Se llama una vez al arrancar la app.
  ///
  /// **Si hay token y perfil, la sesión queda autenticada de inmediato**, sin
  /// esperar al servidor. Ese es el cambio que hace que la app abra sin
  /// conexión: antes se exigía que `GET /api/usuarios/yo` respondiera, y en
  /// modo avión el arranque se quedaba bloqueado en una pantalla de error con
  /// una credencial perfectamente válida guardada al lado.
  ///
  /// El perfil en caché puede estar desactualizado —el administrador pudo
  /// aprobar la solicitud mientras tanto—, y por eso la pantalla de arranque lo
  /// revalida contra el servidor en cuanto puede. Pero eso ya no bloquea la
  /// entrada; si el token hubiera caducado, la primera petición devolverá 401 o
  /// 403 y `ClienteApi` cerrará la sesión.
  Future<String?> restaurarSesion() async {
    _token = await _almacen.leer(_claveToken);

    if (_token == null) {
      _fase = FaseSesion.sinSesion;
      notifyListeners();
      return null;
    }

    final perfilGuardado = await _leerPerfilGuardado();
    if (perfilGuardado != null) {
      _perfil = perfilGuardado;
      _fase = FaseSesion.autenticado;
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
    await _guardarPerfil(perfil);
    notifyListeners();
  }

  /// Refresca el perfil sin tocar el token.
  ///
  /// Es lo que hace que una aprobación del administrador surta efecto: cambia
  /// `estadoMembresia` y el enrutador redirige del compás de espera al muro.
  Future<void> actualizarPerfil(PerfilVecino perfil) async {
    _perfil = perfil;
    _fase = FaseSesion.autenticado;
    await _guardarPerfil(perfil);
    notifyListeners();
  }

  /// Cierra la sesión y borra **todo** el almacén local.
  ///
  /// Se invoca tanto al pulsar "cerrar sesión" como automáticamente cuando el
  /// servidor responde 401/403.
  ///
  /// Borra el almacén cifrado **entero**, no solo el token. Borrar por clave
  /// obligaba a recordar cada clave existente, y así fue como la cola de pánico
  /// acabó sobreviviendo al cierre de sesión: un vecino cerraba sesión con una
  /// emergencia encolada, otro ingresaba en el mismo teléfono, y la alerta del
  /// primero se emitía en la comunidad del segundo.
  Future<void> cerrar() async {
    _token = null;
    _perfil = null;
    _fase = FaseSesion.sinSesion;

    await _almacen.borrarTodo();
    // Base local, cola pendiente, borrador y preferencias. Se delega porque
    // esta clase no conoce esos almacenes.
    await alCerrarSesion?.call();

    notifyListeners();
  }

  // ---------------------------------------------------------------------------

  Future<void> _guardarPerfil(PerfilVecino perfil) async {
    await _almacen.escribir(_clavePerfil, jsonEncode(perfil.aJson()));
  }

  Future<PerfilVecino?> _leerPerfilGuardado() async {
    try {
      final crudo = await _almacen.leer(_clavePerfil);
      if (crudo == null || crudo.isEmpty) return null;

      final json = jsonDecode(crudo);
      if (json is! Map<String, dynamic>) return null;

      return PerfilVecino.desdeJson(json);
    } catch (e) {
      // Perfil ilegible: se arranca sin él y la app pedirá ingresar. Preferible
      // a propagar la excepción y dejar la app sin abrir.
      debugPrint('[SESION] Perfil guardado ilegible, se descarta: $e');
      await _almacen.borrar(_clavePerfil);
      return null;
    }
  }
}
