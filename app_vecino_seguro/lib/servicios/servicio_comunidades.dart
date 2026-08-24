import '../modelos/solicitud.dart';
import 'cliente_api.dart';

/// Resumen público de una comunidad, para validar un código antes de solicitar
/// el ingreso.
class ResumenComunidad {
  const ResumenComunidad({
    required this.idComunidad,
    required this.nombre,
    required this.codigo,
    required this.totalVecinos,
  });

  final int idComunidad;
  final String nombre;
  final String codigo;
  final int totalVecinos;

  factory ResumenComunidad.desdeJson(Map<String, dynamic> json) {
    return ResumenComunidad(
      idComunidad: (json['id_comunidad'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? '',
      codigo: json['codigo'] as String? ?? '',
      totalVecinos: (json['total_vecinos'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Operaciones sobre comunidades.
class ServicioComunidades {
  const ServicioComunidades(this._api);

  final ClienteApi _api;

  /// `POST /api/comunidades` — crea la comunidad y deja al vecino como
  /// administrador. Entra sin aprobación: es el dueño.
  Future<ResumenComunidad> crear({
    required String codigo,
    required String nombre,
  }) async {
    final json = await _api.publicar(
      '/api/comunidades',
      cuerpo: {'codigo': codigo, 'nombre': nombre},
    );

    final comunidad = json['comunidad'];
    if (comunidad is! Map<String, dynamic>) {
      throw const ExcepcionApi('El servidor no devolvió la comunidad creada.');
    }
    return ResumenComunidad.desdeJson(comunidad);
  }

  /// `GET /api/comunidades/:codigo` — valida un código **antes** de enviar la
  /// solicitud, para que el vecino no descubra el error después de rellenar
  /// todo el formulario.
  ///
  /// Devuelve `null` si el código no existe, en lugar de lanzar: "no existe" es
  /// una respuesta esperable de una validación, no un fallo.
  Future<ResumenComunidad?> buscarPorCodigo(String codigo) async {
    try {
      final json = await _api.obtener('/api/comunidades/${codigo.trim()}');
      return ResumenComunidad.desdeJson(json);
    } on ExcepcionApi catch (e) {
      if (e.mensaje.contains('No existe')) return null;
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // SOLICITUDES DE INGRESO
  // -------------------------------------------------------------------------

  /// `POST /api/comunidades/solicitudes` — pedir ingreso con el código del
  /// administrador.
  ///
  /// El vecino **no** entra al instante: queda pendiente de aprobación. Es lo
  /// que impide que un código filtrado dé acceso automático a las alertas.
  Future<void> solicitarIngreso(String codigo) async {
    await _api.publicar(
      '/api/comunidades/solicitudes',
      cuerpo: {'codigo': codigo.trim()},
    );
  }

  /// `DELETE /api/comunidades/solicitudes/mia` — cancelar la propia solicitud,
  /// para poder probar otro código.
  Future<void> cancelarMiSolicitud() async {
    await _api.eliminar('/api/comunidades/solicitudes/mia');
  }

  /// `GET /api/comunidades/solicitudes` — pendientes de mi comunidad.
  /// Solo el administrador.
  Future<List<SolicitudIngreso>> listarPendientes() async {
    final json = await _api.obtener('/api/comunidades/solicitudes');
    final lista = json['solicitudes'];

    if (lista is! List) return const [];

    return lista
        .whereType<Map<String, dynamic>>()
        .map(SolicitudIngreso.desdeJson)
        .toList();
  }

  /// `PATCH /api/comunidades/solicitudes/:id` — aprobar o rechazar.
  ///
  /// Devuelve el mensaje del servidor para mostrarlo tal cual: ya viene
  /// redactado con el nombre del vecino.
  Future<String> resolverSolicitud({
    required int idSolicitud,
    required bool aprobar,
  }) async {
    final json = await _api.parchear(
      '/api/comunidades/solicitudes/$idSolicitud',
      cuerpo: {'accion': aprobar ? 'aprobar' : 'rechazar'},
    );
    return json['mensaje'] as String? ??
        (aprobar ? 'Solicitud aprobada.' : 'Solicitud rechazada.');
  }
}
