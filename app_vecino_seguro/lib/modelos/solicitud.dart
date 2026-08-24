/// Solicitud de ingreso pendiente, vista por el administrador.
///
/// Contrato de `GET /api/comunidades/solicitudes`.
class SolicitudIngreso {
  const SolicitudIngreso({
    required this.idSolicitud,
    required this.nombreVecino,
    required this.telefonoVecino,
    required this.fechaSolicitud,
  });

  final int idSolicitud;
  final String nombreVecino;

  /// El administrador lo necesita para reconocer a quién está aprobando: en una
  /// app de seguridad vecinal, dar acceso a un desconocido es el riesgo real.
  final String telefonoVecino;

  final DateTime fechaSolicitud;

  factory SolicitudIngreso.desdeJson(Map<String, dynamic> json) {
    final vecino = json['vecino'] as Map<String, dynamic>?;

    return SolicitudIngreso(
      idSolicitud: (json['id_solicitud'] as num?)?.toInt() ?? 0,
      nombreVecino: (vecino?['nombre'] as String?) ?? 'Vecino',
      telefonoVecino: (vecino?['telefono'] as String?) ?? '',
      fechaSolicitud:
          DateTime.tryParse(json['fecha_solicitud'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
