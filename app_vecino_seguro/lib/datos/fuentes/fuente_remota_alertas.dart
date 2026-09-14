import 'package:dio/dio.dart';

import '../../modelos/alerta.dart';
import '../../servicios/cliente_api.dart';

/// Fuente **remota** de alertas: habla con la API y nada más.
///
/// No conoce la base de datos del teléfono, ni la cola de salida, ni cuándo
/// conviene usar una u otra. Esas decisiones son del repositorio.
///
/// Esa frontera es lo que hace verificable la política sin conexión: se puede
/// probar "el servidor falló" sustituyendo esta pieza, sin simular sqlite.
class FuenteRemotaAlertas {
  const FuenteRemotaAlertas(this._api);

  final ClienteApi _api;

  /// `GET /api/alertas/comunidad`
  Future<RespuestaAlertas> listar({CancelToken? cancelacion}) async {
    final json = await _api.obtener(
      '/api/alertas/comunidad',
      cancelacion: cancelacion,
    );
    return RespuestaAlertas.desdeJson(json);
  }

  /// `GET /api/alertas/:id`
  Future<Alerta> porId(int idAlerta, {CancelToken? cancelacion}) async {
    final json = await _api.obtener(
      '/api/alertas/$idAlerta',
      cancelacion: cancelacion,
    );

    final alerta = json['alerta'];
    if (alerta is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la alerta solicitada.');
    }
    return Alerta.desdeJson(alerta);
  }

  /// `POST /api/alertas/emitir` con el cuerpo ya construido.
  ///
  /// Recibe el mapa tal como se serializó en la cola, sin volver a armarlo:
  /// rearmar el cuerpo en el reintento abriría la puerta a que cambiara
  /// respecto al del primer intento, y con él la `clave_cliente` que garantiza
  /// la idempotencia.
  ///
  /// **Sin `CancelToken` a propósito.** Una emisión en vuelo no se cancela
  /// porque el vecino salga de la pantalla: la alerta ya está encolada y su
  /// destino no depende de que él siga mirando.
  Future<Alerta> emitir(Map<String, dynamic> cuerpo) async {
    final json = await _api.publicar('/api/alertas/emitir', cuerpo: cuerpo);

    final alerta = json['alerta'];
    if (alerta is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la alerta emitida.');
    }
    return Alerta.desdeJson(alerta);
  }
}
