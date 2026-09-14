import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/red/adaptador_pruebas.dart';
import 'package:app_vecino_seguro/red/cliente_http.dart';
import 'package:app_vecino_seguro/red/credenciales.dart';
import 'package:app_vecino_seguro/red/interceptores/interceptor_renovacion.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';

/// PASO 16 — INTERCEPTORES
///
/// El núcleo del Prototipo 13: inyección de credencial, renovación
/// transparente, marca anti-bucle y control de renovaciones concurrentes.
void main() {
  /// Monta un cliente real con un servidor simulado.
  ///
  /// `peticiones` acumula lo que el servidor recibió, en orden: es lo que
  /// permite afirmar cuántas renovaciones se dispararon de verdad.
  ({Dio dio, Credenciales cred, List<http.Request> peticiones, int Function() perdidas})
  montar({
    required Future<http.Response> Function(http.Request, int numero) responder,
    String? acceso = 'token-viejo',
    String? renovacion = 'renovacion-valida',
  }) {
    final almacen = AlmacenEnMemoria({
      Credenciales.claveAcceso: ?acceso,
      Credenciales.claveRenovacion: ?renovacion,
    });
    final cred = Credenciales(almacen);
    final peticiones = <http.Request>[];
    var perdidas = 0;

    final dio = construirCliente(
      credenciales: cred,
      alPerderSesion: () async => perdidas++,
      adaptador: AdaptadorDeCliente(
        MockClient((p) async {
          peticiones.add(p);
          return responder(p, peticiones.length);
        }),
      ),
    );

    return (dio: dio, cred: cred, peticiones: peticiones, perdidas: () => perdidas);
  }

  http.Response json(Object cuerpo, [int codigo = 200]) => http.Response(
    jsonEncode(cuerpo),
    codigo,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response tokenExpirado() =>
      json({'mensaje': 'Tu sesión expiró.', 'codigo': 'TOKEN_EXPIRADO'}, 401);

  http.Response parNuevo({String acceso = 'token-nuevo'}) =>
      json({'token': acceso, 'token_renovacion': 'renovacion-rotada'});

  group('Interceptor de autorización', () {
    test('inyecta el token guardado en el encabezado', () async {
      final m = montar(responder: (_, _) async => json({'ok': true}));

      await m.dio.get('/api/alertas/comunidad');

      expect(m.peticiones.single.headers['Authorization'], 'Bearer token-viejo');
    });

    test('NO inyecta token en ingreso, registro ni renovación', () async {
      final m = montar(responder: (_, _) async => json({'ok': true}));

      for (final ruta in [
        '/api/usuarios/login',
        '/api/usuarios/registro',
        '/api/usuarios/renovar',
      ]) {
        await m.dio.post(ruta, data: const {});
      }

      // Enviar un token caducado a /renovar haría que el interceptor de
      // renovación viera un 401 del propio endpoint de renovación.
      for (final p in m.peticiones) {
        expect(p.headers.containsKey('Authorization'), isFalse, reason: p.url.path);
      }
    });

    test('sin token guardado, la petición sale sin encabezado', () async {
      final m = montar(
        responder: (_, _) async => json({'ok': true}),
        acceso: null,
      );

      await m.dio.get('/api/alertas/comunidad');

      expect(m.peticiones.single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('Interceptor de renovación', () {
    test('un 401 TOKEN_EXPIRADO renueva y reintenta la petición original', () async {
      final m = montar(
        responder: (p, n) async {
          if (p.url.path.contains('renovar')) return parNuevo();
          // La primera vez el token está caducado; tras renovar, funciona.
          return p.headers['Authorization'] == 'Bearer token-nuevo'
              ? json({'data': []})
              : tokenExpirado();
        },
      );

      final respuesta = await m.dio.get('/api/alertas/comunidad');

      expect(respuesta.statusCode, 200);
      // 1) original con token viejo, 2) renovación, 3) original repetida
      expect(m.peticiones, hasLength(3));
      expect(m.peticiones[1].url.path, contains('renovar'));
      expect(m.peticiones[2].headers['Authorization'], 'Bearer token-nuevo');
      expect(m.perdidas(), 0, reason: 'La sesión NO debe perderse: se renovó');
    });

    test('guarda el par rotado que devuelve el servidor', () async {
      final m = montar(
        responder: (p, _) async {
          if (p.url.path.contains('renovar')) return parNuevo();
          return p.headers['Authorization'] == 'Bearer token-nuevo'
              ? json({'ok': true})
              : tokenExpirado();
        },
      );

      await m.dio.get('/api/alertas/comunidad');

      expect(await m.cred.tokenAcceso(), 'token-nuevo');
      // Con el de renovación viejo, la siguiente renovación se interpretaría
      // como reutilización y el servidor cerraría todas las sesiones.
      expect(await m.cred.tokenRenovacion(), 'renovacion-rotada');
    });

    test('LA MARCA corta el bucle si el token nuevo también da 401', () async {
      // El servidor renueva pero sigue rechazando: sin la marca, esto giraría
      // para siempre.
      final m = montar(
        responder: (p, _) async =>
            p.url.path.contains('renovar') ? parNuevo() : tokenExpirado(),
      );

      // Con `validateStatus < 500` un 401 es respuesta, no excepción.
      final r = await m.dio.get('/api/alertas/comunidad');
      expect(r.statusCode, 401);

      // original + renovación + reintento, y PARA. Sin marca serían infinitas.
      expect(m.peticiones, hasLength(3));
      expect(m.perdidas(), 1, reason: 'Agotada la renovación, se pierde la sesión');
    });

    test('sin token de renovación guardado, no se intenta renovar', () async {
      final m = montar(
        responder: (_, _) async => tokenExpirado(),
        renovacion: null,
      );

      final r = await m.dio.get('/api/alertas/comunidad');
      expect(r.statusCode, 401);

      expect(m.peticiones, hasLength(1));
      expect(m.perdidas(), 1);
    });

    test('un 401 SIN código no se renueva: falta credencial, no caducó', () async {
      final m = montar(
        responder: (_, _) async => json({'mensaje': 'Se requiere iniciar sesión.'}, 401),
      );

      final r = await m.dio.get('/api/alertas/comunidad');
      expect(r.statusCode, 401);

      expect(m.peticiones, hasLength(1), reason: 'No debe intentar renovar');
    });

    test('un 403 de permisos no se renueva', () async {
      final m = montar(
        responder: (_, _) async =>
            json({'mensaje': 'Solo el administrador.', 'codigo': 'NO_ES_ADMIN'}, 403),
      );

      final r = await m.dio.get('/api/comunidades/solicitudes');
      expect(r.statusCode, 403);

      expect(m.peticiones, hasLength(1));
      expect(m.perdidas(), 0, reason: 'La sesión sigue siendo válida');
    });

    test('CINCO peticiones que caducan a la vez disparan UNA sola renovación', () async {
      var renovaciones = 0;

      final m = montar(
        responder: (p, _) async {
          if (p.url.path.contains('renovar')) {
            renovaciones++;
            // Latencia real: sin ella las cinco no llegarían a solaparse.
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return parNuevo();
          }
          return p.headers['Authorization'] == 'Bearer token-nuevo'
              ? json({'ok': true})
              : tokenExpirado();
        },
      );

      await Future.wait([
        for (var i = 0; i < 5; i++) m.dio.get('/api/alertas/$i'),
      ]);

      expect(
        renovaciones,
        1,
        reason: 'Con rotación en el servidor, cinco renovaciones simultáneas se '
            'invalidarían entre sí y cerrarían la sesión del vecino.',
      );
      expect(m.perdidas(), 0);
    });
  });

  group('Configuración del cliente', () {
    test('los tiempos de espera de conexión y respuesta son distintos', () {
      final m = montar(responder: (_, _) async => json({}));

      // Un servidor lento en aceptar la conexión y uno lento en responder son
      // problemas distintos: un único límite los confunde.
      expect(m.dio.options.connectTimeout, const Duration(seconds: 8));
      expect(m.dio.options.receiveTimeout, const Duration(seconds: 15));
      expect(m.dio.options.connectTimeout, isNot(m.dio.options.receiveTimeout));
    });

    test('los 4xx llegan como respuesta interpretable, los 5xx como excepción', () {
      final m = montar(responder: (_, _) async => json({}));
      final validar = m.dio.options.validateStatus;

      expect(validar(422), isTrue, reason: 'Un 422 se pinta campo por campo');
      expect(validar(404), isTrue);
      expect(validar(500), isFalse, reason: 'No hay nada que interpretar');
    });

    test('el orden es autorización → renovación → reintento → registro', () {
      final m = montar(responder: (_, _) async => json({}));
      final tipos = m.dio.interceptors
          .map((i) => i.runtimeType.toString())
          .where((t) => t.startsWith('Interceptor'))
          .toList();

      expect(tipos[0], contains('Autorizacion'));
      expect(tipos[1], contains('Renovacion'));
      // El reintento va tras la renovación: un 401 caducado se arregla
      // renovando, no repitiendo la petición con el mismo token caducado.
      expect(tipos[2], contains('Reintento'));
      // El registro va el último para reflejar lo que salió de verdad, con
      // cada reintento como una entrada más.
      expect(tipos[3], contains('Registro'));
    });

    test('el interceptor de renovación es ENCOLADO, no normal', () {
      final m = montar(responder: (_, _) async => json({}));
      final renovacion = m.dio.interceptors.firstWhere(
        (i) => i is InterceptorRenovacion,
      );

      // Es lo que hace que Dio serialice las peticiones que entran en él.
      expect(renovacion, isA<QueuedInterceptor>());
    });
  });
}
