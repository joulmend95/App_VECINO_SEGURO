import 'alerta.dart';

/// Notificación recibida por el vecino.
///
/// Contrato de `GET /api/notificaciones`.
class Notificacion {
  const Notificacion({
    required this.idNotificacion,
    required this.leida,
    required this.fechaCreacion,
    required this.alerta,
  });

  final int idNotificacion;
  final bool leida;
  final DateTime fechaCreacion;
  final Alerta alerta;

  Notificacion copiarComoLeida() => Notificacion(
    idNotificacion: idNotificacion,
    leida: true,
    fechaCreacion: fechaCreacion,
    alerta: alerta,
  );

  factory Notificacion.desdeJson(Map<String, dynamic> json) {
    final alerta = json['alerta'];

    return Notificacion(
      idNotificacion: (json['id_notificacion'] as num?)?.toInt() ?? 0,
      leida: json['leida'] as bool? ?? false,
      fechaCreacion:
          DateTime.tryParse(json['fecha_creacion'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      alerta: Alerta.desdeJson(
        alerta is Map<String, dynamic> ? alerta : const {},
      ),
    );
  }
}

/// Respuesta completa: incluye el contador de no leídas, que alimenta el
/// indicador del muro sin necesidad de recorrer la lista.
class BandejaNotificaciones {
  const BandejaNotificaciones({required this.noLeidas, required this.items});

  final int noLeidas;
  final List<Notificacion> items;

  factory BandejaNotificaciones.desdeJson(Map<String, dynamic> json) {
    final lista = json['data'];

    return BandejaNotificaciones(
      noLeidas: (json['no_leidas'] as num?)?.toInt() ?? 0,
      items: lista is List
          ? lista
                .whereType<Map<String, dynamic>>()
                .map(Notificacion.desdeJson)
                .toList()
          : const [],
    );
  }
}
