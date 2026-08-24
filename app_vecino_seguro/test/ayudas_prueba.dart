import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/dependencias.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';
import 'package:app_vecino_seguro/theme/tema_app.dart';

/// Utilidades compartidas por las pruebas.
///
/// Centralizarlas evita que cada archivo repita el montaje del árbol de
/// dependencias, y que un cambio en la infraestructura obligue a tocar cinco
/// ficheros de prueba.

// ---------------------------------------------------------------------------
// DATOS DE EJEMPLO
// ---------------------------------------------------------------------------

Map<String, dynamic> perfilJson({
  int id = 1,
  String nombre = 'Jorge',
  String estado = 'ACTIVO',
  bool esAdmin = false,
  String comunidad = 'Urbanización El Bosque',
}) => {
  'id_usuario': id,
  'nombre': nombre,
  'telefono': '0991234567',
  'rol': esAdmin ? 'ADMIN' : 'VECINO',
  'estado_membresia': estado,
  'comunidad': estado == 'ACTIVO'
      ? {
          'id_comunidad': 1,
          'nombre': comunidad,
          'codigo': 'URB-2026',
          'es_admin': esAdmin,
        }
      : null,
  'solicitud_pendiente': estado == 'PENDIENTE'
      ? {
          'id_solicitud': 7,
          'comunidad': comunidad,
          'fecha_solicitud': DateTime.now().toIso8601String(),
        }
      : null,
};

Map<String, dynamic> alertaJson({
  int id = 1,
  String tipo = 'Robo',
  String vecino = 'Jorge',
  Duration hace = const Duration(minutes: 5),
  bool esPanico = false,
}) => {
  'id_alerta': id,
  'tipo_alerta': tipo,
  'descripcion': null,
  'es_panico': esPanico,
  'fecha_hora': DateTime.now().subtract(hace).toIso8601String(),
  'estado': 'ACTIVA',
  'id_usuario': id,
  'usuario': {'id_usuario': id, 'nombre': vecino, 'telefono': '099'},
};

String cuerpoAlertas(List<Map<String, dynamic>> alertas) =>
    jsonEncode({'fuente': 'BASE_DE_DATOS_POSTGRESQL', 'data': alertas});

// ---------------------------------------------------------------------------
// SERVIDOR SIMULADO
// ---------------------------------------------------------------------------

/// Servidor simulado con respuestas por ruta.
///
/// [rutas] mapea un fragmento de la ruta a la respuesta que debe devolver.
/// Cualquier ruta no declarada responde 404, lo que hace evidente en la prueba
/// si el código llamó a un endpoint inesperado.
MockClient servidorFalso(
  Map<String, http.Response Function(http.Request)> rutas, {
  void Function(http.Request)? alRecibir,
}) {
  return MockClient((peticion) async {
    alRecibir?.call(peticion);
    for (final entrada in rutas.entries) {
      if (peticion.url.path.contains(entrada.key)) {
        return entrada.value(peticion);
      }
    }
    return http.Response(
      jsonEncode({'mensaje': 'Ruta no simulada: ${peticion.url.path}'}),
      404,
    );
  });
}

http.Response ok(Object cuerpo) => http.Response(
  cuerpo is String ? cuerpo : jsonEncode(cuerpo),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response falla(int codigo, [String mensaje = 'error']) => http.Response(
  jsonEncode({'mensaje': mensaje}),
  codigo,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// ---------------------------------------------------------------------------
// MONTAJE
// ---------------------------------------------------------------------------

/// Construye una sesión con almacén en memoria (sin canales de plataforma).
Sesion sesionDePrueba({String? tokenGuardado}) {
  return Sesion(
    almacen: AlmacenEnMemoria(
      tokenGuardado == null ? null : {'vecino_seguro.token': tokenGuardado},
    ),
  );
}

/// Sesión ya autenticada y activa, para pruebas que no ejercitan el ingreso.
Future<Sesion> sesionActiva({bool esAdmin = false}) async {
  final sesion = sesionDePrueba();
  await sesion.iniciar(
    token: 'jwt-de-prueba',
    perfil: PerfilVecino.desdeJson(perfilJson(esAdmin: esAdmin)),
  );
  return sesion;
}

/// Envuelve un widget con tema y dependencias reales.
Widget montarConDependencias({
  required Widget hijo,
  required Sesion sesion,
  required MockClient cliente,
  Size? tamano,
  double escalaTexto = 1.0,
  bool oscuro = false,
}) {
  final servicios = Servicios(
    sesion: sesion,
    cliente: ClienteApi(
      sesion: sesion,
      cliente: cliente,
      urlBase: 'http://servidor-falso',
    ),
  );

  return Dependencias(
    servicios: servicios,
    child: MaterialApp(
      theme: TemaApp.claro,
      darkTheme: TemaApp.oscuro,
      themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (context) {
          final base = MediaQuery.of(context);
          return MediaQuery(
            data: base.copyWith(
              size: tamano ?? base.size,
              textScaler: TextScaler.linear(escalaTexto),
            ),
            child: hijo,
          );
        },
      ),
    ),
  );
}
