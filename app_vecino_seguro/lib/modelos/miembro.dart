/// Vecino de la comunidad.
///
/// Contrato de `GET /api/comunidades/miembros`.
class Miembro {
  const Miembro({
    required this.idUsuario,
    required this.nombre,
    required this.telefono,
    required this.esAdmin,
  });

  final int idUsuario;
  final String nombre;

  /// Vía de contacto en una emergencia. Es el motivo de que la lista exista.
  final String telefono;

  final bool esAdmin;

  factory Miembro.desdeJson(Map<String, dynamic> json) => Miembro(
    idUsuario: (json['id_usuario'] as num?)?.toInt() ?? 0,
    nombre: json['nombre'] as String? ?? 'Vecino',
    telefono: json['telefono'] as String? ?? '',
    esAdmin: json['es_admin'] as bool? ?? false,
  );
}

/// Listado completo, con el nombre de la comunidad y el total.
class ListaMiembros {
  const ListaMiembros({
    required this.comunidad,
    required this.total,
    required this.miembros,
  });

  final String comunidad;
  final int total;
  final List<Miembro> miembros;

  factory ListaMiembros.desdeJson(Map<String, dynamic> json) {
    final lista = json['data'];

    return ListaMiembros(
      comunidad: json['comunidad'] as String? ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      miembros: lista is List
          ? lista.whereType<Map<String, dynamic>>().map(Miembro.desdeJson).toList()
          : const [],
    );
  }
}
