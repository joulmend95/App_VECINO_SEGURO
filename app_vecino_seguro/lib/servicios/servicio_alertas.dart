import '../modelos/alerta.dart';
import 'cliente_api.dart';

/// Operaciones sobre alertas de la comunidad.
///
/// Sustituye a `ApiAlertas`, que gestionaba su propio token. Ahora la
/// autenticación la resuelve [ClienteApi] en un solo lugar.
class ServicioAlertas {
  const ServicioAlertas(this._api);

  final ClienteApi _api;

  /// `GET /api/alertas/comunidad`
  ///
  /// El servidor deduce la comunidad de la sesión: ya no se envía
  /// `?id_comunidad`, porque permitía leer las alertas de comunidades ajenas.
  Future<RespuestaAlertas> obtenerAlertasComunidad() async {
    final json = await _api.obtener('/api/alertas/comunidad');
    return RespuestaAlertas.desdeJson(json);
  }

  /// `GET /api/alertas/:id`
  ///
  /// Existe para que la pantalla de detalle pueda reconstruirse a partir de su
  /// dirección. Sin este endpoint habría que transportar el objeto [Alerta]
  /// desde el muro, y abrir `/alertas/42` en frío mostraría una pantalla vacía.
  ///
  /// El servidor responde 404 tanto si la alerta no existe como si pertenece a
  /// otra comunidad; el mensaje que llega ya está redactado para el usuario.
  Future<Alerta> obtenerPorId(int idAlerta) async {
    final json = await _api.obtener('/api/alertas/$idAlerta');

    final alerta = json['alerta'];
    if (alerta is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la alerta solicitada.');
    }
    return Alerta.desdeJson(alerta);
  }

  /// `POST /api/alertas/emitir`
  ///
  /// Con [esPanico] en `true` el tipo lo asigna el servidor: es el disparo por
  /// gesto, donde el vecino no puede elegir.
  Future<Alerta> emitir({
    String? tipoAlerta,
    String? descripcion,
    bool esPanico = false,
    double? latitud,
    double? longitud,
  }) async {
    final json = await _api.publicar(
      '/api/alertas/emitir',
      cuerpo: {
        if (!esPanico) 'tipo_alerta': tipoAlerta,
        if (descripcion != null && descripcion.trim().isNotEmpty)
          'descripcion': descripcion.trim(),
        if (esPanico) 'es_panico': true,
        'latitud': ?latitud,
        'longitud': ?longitud,
      },
    );

    final alerta = json['alerta'];
    if (alerta is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la alerta emitida.');
    }
    return Alerta.desdeJson(alerta);
  }
}
