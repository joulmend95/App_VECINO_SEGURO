import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/navegacion/rutas.dart';
import 'package:app_vecino_seguro/servicios/almacen_local.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/detector_conexion.dart';
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

/// Respuesta de `GET /api/alertas/:id`: la alerta va bajo `alerta`, no `data`.
String cuerpoAlerta(Map<String, dynamic> alerta) => jsonEncode({'alerta': alerta});

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

/// Error de validación tal como lo devuelve el servidor: 422 con el campo
/// afectado, para que el formulario pueda pintarlo donde corresponde.
http.Response fallaValidacion(Map<String, String> porCampo, {int codigo = 422}) =>
    http.Response(
      jsonEncode({
        'mensaje': 'Revisa los datos ingresados.',
        'errores': [
          for (final e in porCampo.entries)
            {'campo': e.key, 'mensaje': e.value},
        ],
      }),
      codigo,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Rechazo con código de negocio: la sesión es válida, falta el permiso.
http.Response fallaNegocio(int codigo, String codigoNegocio, String mensaje) =>
    http.Response(
      jsonEncode({'mensaje': mensaje, 'codigo': codigoNegocio}),
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

/// Perfil ya deserializado, para abrir sesión sin pasar por el servidor.
PerfilVecino perfilDePrueba({String estado = 'ACTIVO', bool esAdmin = false}) =>
    PerfilVecino.desdeJson(perfilJson(estado: estado, esAdmin: esAdmin));

/// Sesión ya autenticada y activa, para pruebas que no ejercitan el ingreso.
Future<Sesion> sesionActiva({bool esAdmin = false}) async {
  final sesion = sesionDePrueba();
  await sesion.iniciar(
    token: 'jwt-de-prueba',
    perfil: PerfilVecino.desdeJson(perfilJson(esAdmin: esAdmin)),
  );
  return sesion;
}

/// Contenedor de servicios con TODO lo nativo sustituido por dobles.
///
/// `AlmacenLocalSqflite` y `DetectorConexionReal` necesitan binarios y canales
/// de plataforma que no existen en `flutter test`. Construir `Servicios` por
/// aquí es lo que permite probar los escenarios sin conexión de verdad, en vez
/// de comprobar solo que la app degrada en silencio.
Servicios serviciosDePrueba({
  required Sesion sesion,
  required MockClient cliente,
  AlmacenLocal? local,
  DetectorConexion? detector,
}) {
  // Sin esto, el canal de `shared_preferences` no existe y `getInstance()` se
  // queda esperando para siempre. Cerrar sesión llama a `prefs.clear()`, así
  // que cualquier prueba que reciba un 401 se colgaría.
  SharedPreferences.setMockInitialValues({});

  final servicios = Servicios(
    sesion: sesion,
    cliente: ClienteApi(
      sesion: sesion,
      cliente: cliente,
      urlBase: 'http://servidor-falso',
    ),
    almacenLocal: local ?? AlmacenLocalEnMemoria(),
    detector: detector ?? DetectorConexionFalso(),
  );
  sesion.alCerrarSesion = servicios.borrarDatosLocales;
  return servicios;
}

/// Monta la aplicación **con el enrutador real**, para probar las guardias.
///
/// A diferencia de [montarConDependencias], que monta una pantalla suelta,
/// aquí se ejercita `construirEnrutador` de verdad: redirecciones, rutas
/// anidadas y parámetros de ruta. Devuelve el `GoRouter` para poder consultar
/// la dirección actual y navegar desde la prueba.
({Widget app, GoRouter enrutador, Servicios servicios}) montarAppConEnrutador({
  required Sesion sesion,
  required MockClient cliente,
  String? rutaInicial,
  AlmacenLocal? local,
  DetectorConexion? detector,
}) {
  final servicios = serviciosDePrueba(
    sesion: sesion,
    cliente: cliente,
    local: local,
    detector: detector,
  );

  final enrutador = construirEnrutador(sesion);
  if (rutaInicial != null) enrutador.go(rutaInicial);

  return (
    app: Dependencias(
      servicios: servicios,
      child: ListenableBuilder(
        listenable: sesion,
        builder: (context, _) => MaterialApp.router(
          theme: TemaApp.claro,
          darkTheme: TemaApp.oscuro,
          themeMode: ThemeMode.light,
          routerConfig: enrutador,
        ),
      ),
    ),
    enrutador: enrutador,
    servicios: servicios,
  );
}

/// Dirección que muestra el enrutador ahora mismo, incluida su consulta.
String ubicacionActual(GoRouter enrutador) =>
    enrutador.routerDelegate.currentConfiguration.uri.toString();

/// Envuelve un widget con tema y dependencias reales.
Widget montarConDependencias({
  required Widget hijo,
  required Sesion sesion,
  required MockClient cliente,
  Size? tamano,
  double escalaTexto = 1.0,
  bool oscuro = false,
  AlmacenLocal? local,
  DetectorConexion? detector,
}) {
  final servicios = serviciosDePrueba(
    sesion: sesion,
    cliente: cliente,
    local: local,
    detector: detector,
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
