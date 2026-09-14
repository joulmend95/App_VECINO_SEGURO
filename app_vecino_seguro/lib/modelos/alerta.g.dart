// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alerta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Alerta _$AlertaFromJson(Map<String, dynamic> json) => Alerta(
  idAlerta: Alerta._entero(json['id_alerta']),
  tipoAlerta: Alerta._tipo(json['tipo_alerta']),
  fechaHora: Alerta._fecha(json['fecha_hora']),
  estado: Alerta._estado(json['estado']),
  nombreVecino: Alerta._nombreDeUsuario(json['usuario']),
  esPanico: json['es_panico'] == null
      ? false
      : Alerta._booleano(json['es_panico']),
  descripcion: Alerta._textoOpcional(json['descripcion']),
);

Map<String, dynamic> _$AlertaToJson(Alerta instance) => <String, dynamic>{
  'id_alerta': instance.idAlerta,
  'tipo_alerta': instance.tipoAlerta,
  'fecha_hora': Alerta._fechaAJson(instance.fechaHora),
  'estado': instance.estado,
  'es_panico': instance.esPanico,
  'descripcion': instance.descripcion,
  'usuario': Alerta._usuarioDesdeNombre(instance.nombreVecino),
};
