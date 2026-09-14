import 'package:json_annotation/json_annotation.dart';

part 'perfil_vecino.g.dart';

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
@JsonSerializable()
class ComunidadDelVecino {
  const ComunidadDelVecino({
    required this.idComunidad,
    required this.nombre,
    required this.codigo,
    required this.esAdmin,
  });

  @JsonKey(name: 'id_comunidad', fromJson: _entero)
  final int idComunidad;

  @JsonKey(fromJson: _nombreComunidad)
  final String nombre;

  /// Código que el administrador comparte para que otros soliciten unirse.
  @JsonKey(fromJson: _texto)
  final String codigo;

  /// `true` si este vecino es quien la creó y aprueba las solicitudes.
  @JsonKey(name: 'es_admin', fromJson: _booleano)
  final bool esAdmin;

  factory ComunidadDelVecino.fromJson(Map<String, dynamic> json) =>
      _$ComunidadDelVecinoFromJson(json);

  Map<String, dynamic> toJson() => _$ComunidadDelVecinoToJson(this);

  factory ComunidadDelVecino.desdeJson(Map<String, dynamic> json) =>
      ComunidadDelVecino.fromJson(json);

  Map<String, dynamic> aJson() => toJson();

  static int _entero(Object? v) => (v as num?)?.toInt() ?? 0;
  static bool _booleano(Object? v) => v as bool? ?? false;
  static String _texto(Object? v) => v as String? ?? '';
  static String _nombreComunidad(Object? v) => v as String? ?? 'Mi comunidad';
}

/// Solicitud de ingreso pendiente de resolución.
@JsonSerializable()
class SolicitudPendiente {
  const SolicitudPendiente({
    required this.idSolicitud,
    required this.comunidad,
    required this.fechaSolicitud,
  });

  @JsonKey(name: 'id_solicitud', fromJson: _entero)
  final int idSolicitud;

  @JsonKey(fromJson: _texto)
  final String comunidad;

  @JsonKey(name: 'fecha_solicitud', fromJson: _fecha, toJson: _fechaAJson)
  final DateTime fechaSolicitud;

  factory SolicitudPendiente.fromJson(Map<String, dynamic> json) =>
      _$SolicitudPendienteFromJson(json);

  Map<String, dynamic> toJson() => _$SolicitudPendienteToJson(this);

  factory SolicitudPendiente.desdeJson(Map<String, dynamic> json) =>
      SolicitudPendiente.fromJson(json);

  Map<String, dynamic> aJson() => toJson();

  static int _entero(Object? v) => (v as num?)?.toInt() ?? 0;
  static String _texto(Object? v) => v as String? ?? '';
  static DateTime _fecha(Object? v) =>
      DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();
  static String _fechaAJson(DateTime f) => f.toUtc().toIso8601String();
}

/// Perfil del vecino autenticado.
///
/// Contrato de `GET /api/usuarios/yo`.
///
/// ## Serialización generada
///
/// La conversión la genera `json_serializable`. Cada `@JsonKey(name:)` deja
/// escrita la divergencia entre el `snake_case` del servidor y el `camelCase`
/// del cliente, en lugar de esconderla en un constructor a mano.
///
/// [comunidad] y [solicitudPendiente] son **anulables** porque el contrato los
/// declara opcionales: un vecino recién registrado no tiene ninguna de las dos,
/// y uno activo no tiene solicitud pendiente. Marcarlos obligatorios obligaría
/// a inventar objetos vacíos que después habría que distinguir de los reales.
@JsonSerializable(explicitToJson: true)
class PerfilVecino {
  const PerfilVecino({
    required this.idUsuario,
    required this.nombre,
    required this.telefono,
    required this.estadoMembresia,
    this.comunidad,
    this.solicitudPendiente,
  });

  @JsonKey(name: 'id_usuario', fromJson: _entero)
  final int idUsuario;

  @JsonKey(fromJson: _nombrePersona)
  final String nombre;

  @JsonKey(fromJson: _texto)
  final String telefono;

  /// El servidor manda `"ACTIVO"`, `"PENDIENTE"` o `"SIN_COMUNIDAD"`; aquí es
  /// un `enum`. La traducción va en ambos sentidos para que el perfil guardado
  /// en caché se relea con su membresía intacta.
  @JsonKey(
    name: 'estado_membresia',
    fromJson: EstadoMembresia.desdeApi,
    toJson: _membresiaAJson,
  )
  final EstadoMembresia estadoMembresia;

  final ComunidadDelVecino? comunidad;

  @JsonKey(name: 'solicitud_pendiente')
  final SolicitudPendiente? solicitudPendiente;

  /// Puede ver y emitir alertas.
  bool get puedeUsarAlertas => estadoMembresia == EstadoMembresia.activo;

  /// Administra su comunidad y aprueba solicitudes.
  bool get esAdmin => comunidad?.esAdmin ?? false;

  factory PerfilVecino.fromJson(Map<String, dynamic> json) =>
      _$PerfilVecinoFromJson(json);

  /// Produce **exactamente la misma forma** que devuelve `GET /api/usuarios/yo`,
  /// para que [fromJson] pueda releerlo sin ninguna rama especial. Un formato
  /// propio obligaría a mantener dos deserializadores que tienen que coincidir.
  ///
  /// Contiene nombre y teléfono: es dato personal, y por eso se guarda cifrado
  /// y se borra al cerrar sesión.
  Map<String, dynamic> toJson() => _$PerfilVecinoToJson(this);

  factory PerfilVecino.desdeJson(Map<String, dynamic> json) =>
      PerfilVecino.fromJson(json);

  Map<String, dynamic> aJson() => toJson();

  static int _entero(Object? v) => (v as num?)?.toInt() ?? 0;
  static String _texto(Object? v) => v as String? ?? '';
  static String _nombrePersona(Object? v) => v as String? ?? 'Vecino';
  static String _membresiaAJson(EstadoMembresia m) => m.aApi;
}

/// Atajo de legibilidad para las guardias y el gesto de pánico.
extension EstadoMembresiaUtil on EstadoMembresia {
  /// `true` solo cuando el vecino puede ver y emitir alertas.
  bool get esActiva => this == EstadoMembresia.activo;
}
