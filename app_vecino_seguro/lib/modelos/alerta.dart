/// Modelo del recurso `Alerta` que devuelve `GET /api/alertas/comunidad`.
///
/// Contrato derivado de `src/services/alerta.service.ts` y `prisma/schema.prisma`.
class Alerta {
  const Alerta({
    required this.idAlerta,
    required this.tipoAlerta,
    required this.fechaHora,
    required this.estado,
    required this.nombreVecino,
    this.esPanico = false,
    this.descripcion,
  });

  final int idAlerta;
  final String tipoAlerta;
  final DateTime fechaHora;
  final String estado;

  /// Emitida por el gesto de pánico, sin que el vecino eligiera el tipo.
  ///
  /// Es **autoritativo**: prevalece sobre cualquier deducción a partir del
  /// texto. Sin este campo, una alerta de pánico caía en la categoría genérica
  /// y se mostraba como urgencia media — la alerta más grave del sistema
  /// apareciendo como la menos alarmante.
  final bool esPanico;

  final String? descripcion;

  /// Viene anidado en `usuario.nombre` gracias al eager loading del backend.
  final String nombreVecino;

  /// El backend solo devuelve alertas con estado "Activa", pero se compara
  /// igual: si mañana cambia el filtro, la UI no miente sobre la urgencia.
  bool get estaActiva => estado.toLowerCase() == 'activa';

  factory Alerta.desdeJson(Map<String, dynamic> json) {
    final usuario = json['usuario'] as Map<String, dynamic>?;

    return Alerta(
      idAlerta: (json['id_alerta'] as num?)?.toInt() ?? 0,
      tipoAlerta: (json['tipo_alerta'] as String?)?.trim().isNotEmpty == true
          ? (json['tipo_alerta'] as String).trim()
          : 'Alerta sin clasificar',
      // Si la fecha viniera malformada, se degrada a "ahora" en lugar de
      // tumbar toda la lista por un solo registro corrupto.
      fechaHora:
          DateTime.tryParse(json['fecha_hora'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      estado: json['estado'] as String? ?? 'Desconocido',
      nombreVecino: (usuario?['nombre'] as String?) ?? 'Vecino anónimo',
      esPanico: json['es_panico'] as bool? ?? false,
      descripcion: (json['descripcion'] as String?)?.trim().isNotEmpty == true
          ? (json['descripcion'] as String).trim()
          : null,
    );
  }
}

/// Respuesta completa del endpoint.
///
/// OJO: el arreglo viene **anidado** bajo `data`, no en la raíz. El campo
/// `fuente` indica si la respuesta salió de caché o de PostgreSQL; es un dato
/// de diagnóstico del backend, no de negocio.
class RespuestaAlertas {
  const RespuestaAlertas({required this.fuente, required this.alertas});

  final String fuente;
  final List<Alerta> alertas;

  bool get vinoDeCache => fuente == 'CACHE_MEMORIA';

  factory RespuestaAlertas.desdeJson(Map<String, dynamic> json) {
    final lista = json['data'];
    return RespuestaAlertas(
      fuente: json['fuente'] as String? ?? 'DESCONOCIDA',
      alertas: lista is List
          ? lista
                .whereType<Map<String, dynamic>>()
                .map(Alerta.desdeJson)
                .toList()
          : const <Alerta>[],
    );
  }
}
