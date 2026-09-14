// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'perfil_vecino.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ComunidadDelVecino _$ComunidadDelVecinoFromJson(Map<String, dynamic> json) =>
    ComunidadDelVecino(
      idComunidad: ComunidadDelVecino._entero(json['id_comunidad']),
      nombre: ComunidadDelVecino._nombreComunidad(json['nombre']),
      codigo: ComunidadDelVecino._texto(json['codigo']),
      esAdmin: ComunidadDelVecino._booleano(json['es_admin']),
    );

Map<String, dynamic> _$ComunidadDelVecinoToJson(ComunidadDelVecino instance) =>
    <String, dynamic>{
      'id_comunidad': instance.idComunidad,
      'nombre': instance.nombre,
      'codigo': instance.codigo,
      'es_admin': instance.esAdmin,
    };

SolicitudPendiente _$SolicitudPendienteFromJson(Map<String, dynamic> json) =>
    SolicitudPendiente(
      idSolicitud: SolicitudPendiente._entero(json['id_solicitud']),
      comunidad: SolicitudPendiente._texto(json['comunidad']),
      fechaSolicitud: SolicitudPendiente._fecha(json['fecha_solicitud']),
    );

Map<String, dynamic> _$SolicitudPendienteToJson(
  SolicitudPendiente instance,
) => <String, dynamic>{
  'id_solicitud': instance.idSolicitud,
  'comunidad': instance.comunidad,
  'fecha_solicitud': SolicitudPendiente._fechaAJson(instance.fechaSolicitud),
};

PerfilVecino _$PerfilVecinoFromJson(Map<String, dynamic> json) => PerfilVecino(
  idUsuario: PerfilVecino._entero(json['id_usuario']),
  nombre: PerfilVecino._nombrePersona(json['nombre']),
  telefono: PerfilVecino._texto(json['telefono']),
  estadoMembresia: EstadoMembresia.desdeApi(
    json['estado_membresia'] as String?,
  ),
  comunidad: json['comunidad'] == null
      ? null
      : ComunidadDelVecino.fromJson(json['comunidad'] as Map<String, dynamic>),
  solicitudPendiente: json['solicitud_pendiente'] == null
      ? null
      : SolicitudPendiente.fromJson(
          json['solicitud_pendiente'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$PerfilVecinoToJson(
  PerfilVecino instance,
) => <String, dynamic>{
  'id_usuario': instance.idUsuario,
  'nombre': instance.nombre,
  'telefono': instance.telefono,
  'estado_membresia': PerfilVecino._membresiaAJson(instance.estadoMembresia),
  'comunidad': instance.comunidad?.toJson(),
  'solicitud_pendiente': instance.solicitudPendiente?.toJson(),
};
