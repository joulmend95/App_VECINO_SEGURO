/// Estado de pertenencia del vecino a una comunidad.
///
/// Es lo que decide a qué pantalla entra la app al arrancar. Se modela como
/// `enum` y no como un par de banderas booleanas porque los tres estados son
/// mutuamente excluyentes: no se puede estar "sin comunidad y pendiente".
enum EstadoMembresia {
  /// Registrado, pero todavía no eligió unirse ni crear una comunidad.
  sinComunidad,

  /// Envió una solicitud y espera que el administrador la apruebe.
  pendiente,

  /// Pertenece a una comunidad aprobada. Puede ver y emitir alertas.
  activo;

  static EstadoMembresia desdeApi(String? valor) => switch (valor) {
    'ACTIVO' => EstadoMembresia.activo,
    'PENDIENTE' => EstadoMembresia.pendiente,
    _ => EstadoMembresia.sinComunidad,
  };

  /// Inverso de [desdeApi], para volver a guardar el perfil en caché.
  ///
  /// Sin esto, el perfil guardado se releería siempre como `sinComunidad` y la
  /// app arrancaría mandando a elegir comunidad a un vecino que ya tiene una.
  String get aApi => switch (this) {
    EstadoMembresia.activo => 'ACTIVO',
    EstadoMembresia.pendiente => 'PENDIENTE',
    EstadoMembresia.sinComunidad => 'SIN_COMUNIDAD',
  };
}

/// Comunidad a la que pertenece el vecino.
class ComunidadDelVecino {
  const ComunidadDelVecino({
    required this.idComunidad,
    required this.nombre,
    required this.codigo,
    required this.esAdmin,
  });

  final int idComunidad;
  final String nombre;

  /// Código que el administrador comparte para que otros soliciten unirse.
  final String codigo;

  /// `true` si este vecino es quien la creó y aprueba las solicitudes.
  final bool esAdmin;

  factory ComunidadDelVecino.desdeJson(Map<String, dynamic> json) {
    return ComunidadDelVecino(
      idComunidad: (json['id_comunidad'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? 'Mi comunidad',
      codigo: json['codigo'] as String? ?? '',
      esAdmin: json['es_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> aJson() => {
    'id_comunidad': idComunidad,
    'nombre': nombre,
    'codigo': codigo,
    'es_admin': esAdmin,
  };
}

/// Solicitud de ingreso pendiente de resolución.
class SolicitudPendiente {
  const SolicitudPendiente({
    required this.idSolicitud,
    required this.comunidad,
    required this.fechaSolicitud,
  });

  final int idSolicitud;
  final String comunidad;
  final DateTime fechaSolicitud;

  factory SolicitudPendiente.desdeJson(Map<String, dynamic> json) {
    return SolicitudPendiente(
      idSolicitud: (json['id_solicitud'] as num?)?.toInt() ?? 0,
      comunidad: json['comunidad'] as String? ?? '',
      fechaSolicitud:
          DateTime.tryParse(json['fecha_solicitud'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> aJson() => {
    'id_solicitud': idSolicitud,
    'comunidad': comunidad,
    'fecha_solicitud': fechaSolicitud.toUtc().toIso8601String(),
  };
}

/// Perfil del vecino autenticado.
///
/// Contrato de `GET /api/usuarios/yo`.
class PerfilVecino {
  const PerfilVecino({
    required this.idUsuario,
    required this.nombre,
    required this.telefono,
    required this.estadoMembresia,
    this.comunidad,
    this.solicitudPendiente,
  });

  final int idUsuario;
  final String nombre;
  final String telefono;
  final EstadoMembresia estadoMembresia;
  final ComunidadDelVecino? comunidad;
  final SolicitudPendiente? solicitudPendiente;

  /// Puede ver y emitir alertas.
  bool get puedeUsarAlertas => estadoMembresia == EstadoMembresia.activo;

  /// Administra su comunidad y aprueba solicitudes.
  bool get esAdmin => comunidad?.esAdmin ?? false;

  factory PerfilVecino.desdeJson(Map<String, dynamic> json) {
    final comunidad = json['comunidad'];
    final solicitud = json['solicitud_pendiente'];

    return PerfilVecino(
      idUsuario: (json['id_usuario'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? 'Vecino',
      telefono: json['telefono'] as String? ?? '',
      estadoMembresia: EstadoMembresia.desdeApi(json['estado_membresia'] as String?),
      comunidad: comunidad is Map<String, dynamic>
          ? ComunidadDelVecino.desdeJson(comunidad)
          : null,
      solicitudPendiente: solicitud is Map<String, dynamic>
          ? SolicitudPendiente.desdeJson(solicitud)
          : null,
    );
  }

  /// Serializa el perfil para guardarlo en el almacén cifrado.
  ///
  /// Produce **exactamente la misma forma** que devuelve `GET /api/usuarios/yo`,
  /// para que [desdeJson] pueda releerlo sin ninguna rama especial. Un formato
  /// propio obligaría a mantener dos deserializadores que tienen que coincidir.
  ///
  /// Contiene nombre y teléfono: es dato personal, y por eso se guarda cifrado
  /// y se borra al cerrar sesión.
  Map<String, dynamic> aJson() => {
    'id_usuario': idUsuario,
    'nombre': nombre,
    'telefono': telefono,
    'estado_membresia': estadoMembresia.aApi,
    'comunidad': comunidad?.aJson(),
    'solicitud_pendiente': solicitudPendiente?.aJson(),
  };
}

/// Atajo de legibilidad para las guardias y el gesto de pánico.
extension EstadoMembresiaUtil on EstadoMembresia {
  /// `true` solo cuando el vecino puede ver y emitir alertas.
  bool get esActiva => this == EstadoMembresia.activo;
}
