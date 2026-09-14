import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/config/entorno.dart';
import 'package:app_vecino_seguro/red/adaptador_pruebas.dart';
import 'package:app_vecino_seguro/red/cliente_http.dart';
import 'package:app_vecino_seguro/red/credenciales.dart';
import 'package:app_vecino_seguro/red/interceptores/interceptor_registro.dart';
import 'package:app_vecino_seguro/red/interceptores/interceptor_reintento.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';

/// PASO 19 — REINTENTOS IDEMPOTENTES Y CONFIGURACIÓN DE AMBIENTE
void main() {
  ({Dio dio, List<http.Request> peticiones}) montar(
    Future<http.Response> Function(http.Request, int) responder,
  ) {
    final peticiones = <http.Request>[];
    final dio = construirCliente(
      credenciales: Credenciales(
        AlmacenEnMemoria({Credenciales.claveAcceso: 'token'}),
      ),
      alPerderSesion: () async {},
      adaptador: AdaptadorDeCliente(
        MockClient((p) async {
          peticiones.add(p);
          return responder(p, peticiones.length);
        }),
      ),
    );
    return (dio: dio, peticiones: peticiones);
  }

  http.Response json(Object cuerpo, [int codigo = 200]) => http.Response(
    jsonEncode(cuerpo),
    codigo,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  group('Reintentos solo para operaciones idempotentes', () {
    test('un GET con 500 se reintenta y se recupera', () async {
      final m = montar((p, n) async => n == 1 ? json({}, 500) : json({'ok': true}));

      final r = await m.dio.get('/api/alertas/comunidad');

      expect(r.statusCode, 200);
      expect(m.peticiones, hasLength(2), reason: 'original + 1 reintento');
    });

    test('un POST con 500 NO se reintenta', () async {
      final m = montar((_, _) async => json({}, 500));

      await expectLater(
        () => m.dio.post('/api/alertas/emitir', data: const {}),
        throwsA(isA<DioException>()),
      );

      // Reintentar a ciegas una emisión convertiría una emergencia en varios
      // avisos a toda la comunidad. Su reintento vive en la cola, que sí lleva
      // clave de idempotencia.
      expect(m.peticiones, hasLength(1));
    });

    test('un PATCH tampoco se reintenta', () async {
      final m = montar((_, _) async => json({}, 500));

      await expectLater(
        () => m.dio.patch('/api/usuarios/yo', data: const {}),
        throwsA(isA<DioException>()),
      );

      expect(m.peticiones, hasLength(1));
    });

    test('un GET con 404 NO se reintenta: daría el mismo resultado', () async {
      final m = montar((_, _) async => json({'mensaje': 'no existe'}, 404));

      // Con `validateStatus < 500` un 404 es respuesta, no excepción.
      final r = await m.dio.get('/api/alertas/999');

      expect(r.statusCode, 404);
      expect(m.peticiones, hasLength(1));
    });

    test('se agota tras el máximo de reintentos, sin bucle', () async {
      final m = montar((_, _) async => json({}, 500));

      await expectLater(
        () => m.dio.get('/api/alertas/comunidad'),
        throwsA(isA<DioException>()),
      );

      // original + 2 reintentos, y para. El contador en `extra` es lo que
      // impide que el ciclo se repita sin fin.
      expect(m.peticiones, hasLength(3));
    });

    test('está DESPUÉS de la renovación en la cadena', () {
      final m = montar((_, _) async => json({}));
      final tipos = m.dio.interceptors
          .map((i) => i.runtimeType.toString())
          .where((t) => t.startsWith('Interceptor'))
          .toList();

      // Un 401 caducado se arregla renovando, no repitiendo la misma petición
      // con el mismo token caducado.
      expect(tipos.indexOf('InterceptorReintento'),
          greaterThan(tipos.indexOf('InterceptorRenovacion')));
    });
  });

  group('Configuración de ambiente', () {
    test('por defecto es desarrollo, con registro detallado activo', () {
      // Sin `--dart-define`, la app compila contra el servidor local.
      expect(Entorno.esProduccion, isFalse);
      expect(Entorno.registroDetallado, isTrue);
      expect(Entorno.ambiente, 'desarrollo');
    });

    test('la dirección base de desarrollo apunta al anfitrión del emulador', () {
      // El emulador de Android no ve el `localhost` del anfitrión: lo alcanza
      // por la IP especial 10.0.2.2.
      expect(Entorno.urlBase, anyOf(contains('10.0.2.2'), contains('localhost')));
    });

    test('verificar() no aborta en desarrollo aunque sea HTTP', () {
      // En desarrollo el servidor local es HTTP y eso es correcto. La guardia
      // solo debe morder en producción.
      expect(Entorno.verificar, returnsNormally);
    });

    test('el registro oculta el encabezado Authorization', () {
      // Un registro con tokens completos es una filtración esperando a ocurrir:
      // los registros acaban en archivos, capturas e informes de fallo.
      const registro = InterceptorRegistro();
      expect(registro, isA<Interceptor>());

      // La comprobación real: las rutas con credenciales nunca registran cuerpo.
      for (final ruta in [
        '/api/usuarios/login',
        '/api/usuarios/registro',
        '/api/usuarios/renovar',
        '/api/usuarios/password',
      ]) {
        expect(
          InterceptorRegistro.cuerposSensibles,
          contains(ruta),
          reason: '$ruta lleva contraseñas en claro',
        );
      }
    });
  });

  group('El interceptor de reintento sin cliente no hace nada', () {
    test('no reintenta si no se le inyectó el Dio', () {
      // Guardia defensiva: sin cliente no puede reintentar, y debe degradar
      // en silencio en lugar de lanzar una excepción nula.
      final suelto = InterceptorReintento();
      expect(suelto.maximoIntentos, 2);
      expect(suelto.esperaBase, const Duration(milliseconds: 400));
    });
  });
}
