import 'package:flutter/foundation.dart';

import '../modelos/alerta.dart';
import 'almacen_local.dart';
import 'cliente_api.dart';

/// Operaciones sobre alertas de la comunidad.
///
/// Cuando se le entrega un [AlmacenLocal], el listado pasa a funcionar sin
/// conexión: cada descarga con éxito refresca la base del teléfono, y un fallo
/// **de red** se sirve desde ella.
class ServicioAlertas {
  const ServicioAlertas(this._api, {AlmacenLocal? almacenLocal})
    : _local = almacenLocal;

  final ClienteApi _api;
  final AlmacenLocal? _local;

  /// Comunidad del vecino autenticado. `null` si aún no pertenece a ninguna.
  int? get _idComunidad => _api.sesion.perfil?.comunidad?.idComunidad;

  /// `GET /api/alertas/comunidad`
  ///
  /// **Estrategia: el servidor manda; el disco es la red de seguridad.**
  ///
  /// 1. Se pide al servidor. Si responde, lo que trae **sustituye por completo**
  ///    la copia local — no se fusiona. Es la estrategia de conflictos elegida:
  ///    si un administrador resolvió una alerta mientras el vecino estaba sin
  ///    red, seguir mostrándola activa sería peor que perder la copia local.
  /// 2. Si falla **por red**, se sirve lo guardado, marcado con su antigüedad.
  /// 3. Si falla por red y no hay nada guardado, se propaga el error.
  ///
  /// Un fallo que **no** sea de red (500, 403) se propaga siempre. Enseñar datos
  /// viejos cuando el servidor está contestando mal esconde el problema real y
  /// hace creer al vecino que todo va bien.
  Future<RespuestaAlertas> obtenerAlertasComunidad() async {
    try {
      final json = await _api.obtener('/api/alertas/comunidad');
      final respuesta = RespuestaAlertas.desdeJson(json);
      await _guardarEnLocal(respuesta.alertas);
      return respuesta;
    } on ExcepcionApi catch (e) {
      if (!e.esSinConexion) rethrow;

      final local = await _leerDeLocal();
      // Sin conexión y sin nada guardado: no hay nada mejor que ofrecer que el
      // error de red, que al menos explica qué pasa.
      if (local == null || local.alertas.isEmpty) rethrow;

      return local;
    }
  }

  /// `GET /api/alertas/:id`
  ///
  /// Sin variante local a propósito: el detalle se abre de una en una y su
  /// valor está en mostrar el estado real. Servir un detalle guardado sin
  /// avisarlo daría una falsa sensación de actualidad sobre una sola alerta.
  Future<Alerta> obtenerPorId(int idAlerta) async {
    final json = await _api.obtener('/api/alertas/$idAlerta');

    final alerta = json['alerta'];
    if (alerta is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la alerta solicitada.');
    }
    return Alerta.desdeJson(alerta);
  }

  /// `POST /api/alertas/emitir` con el cuerpo ya construido.
  ///
  /// Lo usa [ColaSincronizacion] para reenviar una operación guardada tal como
  /// se serializó, sin volver a armarla: rearmar el cuerpo en el reintento
  /// abriría la puerta a que cambiara respecto al del primer intento.
  Future<Alerta> emitirCrudo(Map<String, dynamic> cuerpo) async {
    final json = await _api.publicar('/api/alertas/emitir', cuerpo: cuerpo);

    final alerta = json['alerta'];
    if (alerta is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la alerta emitida.');
    }
    return Alerta.desdeJson(alerta);
  }

  /// `POST /api/alertas/emitir`
  ///
  /// Envío directo, sin pasar por la cola. Se conserva para las pruebas y para
  /// los casos en que el resultado inmediato importa; el camino normal de la
  /// aplicación es `ColaSincronizacion.encolarAlerta`.
  Future<Alerta> emitir({
    String? tipoAlerta,
    String? descripcion,
    bool esPanico = false,
    double? latitud,
    double? longitud,
    String? claveCliente,
  }) {
    return emitirCrudo({
      if (!esPanico) 'tipo_alerta': tipoAlerta,
      if (descripcion != null && descripcion.trim().isNotEmpty)
        'descripcion': descripcion.trim(),
      if (esPanico) 'es_panico': true,
      'latitud': ?latitud,
      'longitud': ?longitud,
      'clave_cliente': ?claveCliente,
    });
  }

  // ---------------------------------------------------------------------------

  Future<void> _guardarEnLocal(List<Alerta> alertas) async {
    final local = _local;
    final comunidad = _idComunidad;
    if (local == null || comunidad == null) return;

    try {
      await local.reemplazarAlertas(comunidad, alertas);
    } catch (e) {
      // Guardar en caché es una mejora, no un requisito. Si el disco falla, el
      // vecino debe seguir viendo las alertas que ya se descargaron.
      debugPrint('[ALERTAS] No se pudo guardar la caché: $e');
    }
  }

  Future<RespuestaAlertas?> _leerDeLocal() async {
    final local = _local;
    final comunidad = _idComunidad;
    if (local == null || comunidad == null) return null;

    try {
      return RespuestaAlertas.local(
        alertas: await local.leerAlertas(comunidad),
        sincronizadoEn: await local.ultimaSincronizacion(),
      );
    } catch (e) {
      debugPrint('[ALERTAS] No se pudo leer la caché: $e');
      return null;
    }
  }
}
