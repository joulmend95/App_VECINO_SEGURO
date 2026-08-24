import '../modelos/notificacion.dart';
import 'cliente_api.dart';

/// Bandeja de notificaciones y registro de dispositivos push.
class ServicioNotificaciones {
  const ServicioNotificaciones(this._api);

  final ClienteApi _api;

  /// `GET /api/notificaciones`
  Future<BandejaNotificaciones> obtenerBandeja() async {
    final json = await _api.obtener('/api/notificaciones');
    return BandejaNotificaciones.desdeJson(json);
  }

  /// `PATCH /api/notificaciones/:id/leida`
  Future<void> marcarLeida(int idNotificacion) async {
    await _api.parchear('/api/notificaciones/$idNotificacion/leida');
  }

  /// `PATCH /api/notificaciones/leidas`
  Future<void> marcarTodasLeidas() async {
    await _api.parchear('/api/notificaciones/leidas');
  }

  /// `POST /api/dispositivos` — asocia el token FCM del teléfono a la cuenta.
  ///
  /// Se llama al iniciar sesión y cada vez que Firebase renueva el token.
  Future<void> registrarDispositivo({
    required String tokenPush,
    required String plataforma,
  }) async {
    await _api.publicar(
      '/api/dispositivos',
      cuerpo: {'token_push': tokenPush, 'plataforma': plataforma},
    );
  }

  /// `DELETE /api/dispositivos` — da de baja el token al cerrar sesión.
  ///
  /// Sin esto, el teléfono seguiría recibiendo las alertas de una comunidad a
  /// la que su dueño ya no pertenece.
  Future<void> eliminarDispositivo(String tokenPush) async {
    await _api.eliminar('/api/dispositivos', cuerpo: {'token_push': tokenPush});
  }
}
