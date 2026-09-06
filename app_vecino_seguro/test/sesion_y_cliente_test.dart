import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/servicio_usuarios.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';

import 'ayudas_prueba.dart';

/// ============================================================================
/// FASE 1 — Sesión persistente y cliente HTTP compartido
/// ============================================================================

ClienteApi clienteCon(Sesion sesion, http.Client mock) =>
    ClienteApi(sesion: sesion, cliente: mock, urlBase: 'http://falso');

void main() {
  group('Sesion — persistencia', () {
    test('arranca en fase "iniciando", sin decidir nada todavía', () {
      final sesion = sesionDePrueba();
      expect(sesion.fase, FaseSesion.iniciando);
      expect(sesion.autenticado, isFalse);
    });

    test('sin token guardado pasa a "sinSesion"', () async {
      final sesion = sesionDePrueba();
      final token = await sesion.restaurarSesion();

      expect(token, isNull);
      expect(sesion.fase, FaseSesion.sinSesion);
    });

    test('restaura el token guardado de una sesión anterior', () async {
      final sesion = sesionDePrueba(tokenGuardado: 'jwt-persistido');
      final token = await sesion.restaurarSesion();

      expect(token, 'jwt-persistido');
      // Sigue en "iniciando": el token existe pero aún no se validó contra el
      // servidor. Esa validación la hace la pantalla de arranque.
      expect(sesion.fase, FaseSesion.iniciando);
    });

    test('iniciar sesión guarda el token en el almacén', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);

      await sesion.iniciar(
        token: 'jwt-nuevo',
        perfil: PerfilVecino.desdeJson(perfilJson()),
      );

      expect(sesion.autenticado, isTrue);
      expect(await almacen.leer('vecino_seguro.token'), 'jwt-nuevo');
    });

    test('cerrar sesión borra la credencial del almacén', () async {
      final almacen = AlmacenEnMemoria({'vecino_seguro.token': 'jwt'});
      final sesion = Sesion(almacen: almacen);
      await sesion.restaurarSesion();

      await sesion.cerrar();

      expect(sesion.autenticado, isFalse);
      expect(await almacen.leer('vecino_seguro.token'), isNull);
    });

    test('notifica a sus oyentes en cada cambio', () async {
      final sesion = sesionDePrueba();
      var avisos = 0;
      sesion.addListener(() => avisos++);

      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(perfilJson()),
      );
      await sesion.cerrar();

      // Es lo que permite al enrutador reevaluar las guardias solo.
      expect(avisos, 2);
    });
  });

  group('ClienteApi — autenticación', () {
    test('adjunta el Bearer de la sesión activa', () async {
      final sesion = await sesionActiva();
      String? cabecera;

      final api = clienteCon(
        sesion,
        servidorFalso(
          {'/api/alertas/comunidad': (_) => ok(cuerpoAlertas([]))},
          alRecibir: (p) => cabecera = p.headers['Authorization'],
        ),
      );

      await api.obtener('/api/alertas/comunidad');
      expect(cabecera, 'Bearer jwt-de-prueba');
    });

    test('sin sesión no envía cabecera de autorización', () async {
      final sesion = sesionDePrueba();
      String? cabecera;

      final api = clienteCon(
        sesion,
        servidorFalso(
          {'/api/usuarios/login': (_) => ok({'token': 'x'})},
          alRecibir: (p) => cabecera = p.headers['Authorization'],
        ),
      );

      await api.publicar('/api/usuarios/login');
      expect(cabecera, isNull);
    });
  });

  group('ClienteApi — interceptor de sesión expirada', () {
    test('un 401 cierra la sesión automáticamente', () async {
      final sesion = await sesionActiva();
      expect(sesion.autenticado, isTrue);

      final api = clienteCon(
        sesion,
        servidorFalso({'/api/alertas': (_) => falla(401, 'Se requiere iniciar sesión.')}),
      );

      await expectLater(
        api.obtener('/api/alertas/comunidad'),
        throwsA(
          isA<ExcepcionApi>().having((e) => e.esRecuperable, 'esRecuperable', isFalse),
        ),
      );

      // Es lo que evita que cada pantalla tenga que detectar el 401 por su
      // cuenta; la que se olvidara dejaría al vecino atrapado.
      expect(sesion.autenticado, isFalse);
    });

    test('un 403 sin código de negocio también cierra la sesión', () async {
      final sesion = await sesionActiva();

      final api = clienteCon(
        sesion,
        servidorFalso({'/api/alertas': (_) => falla(403, 'Tu sesión expiró.')}),
      );

      await expectLater(api.obtener('/api/alertas/comunidad'), throwsA(isA<ExcepcionApi>()));
      expect(sesion.autenticado, isFalse);
    });

    test('un 403 CON código de negocio NO cierra la sesión', () async {
      final sesion = await sesionActiva();

      final api = clienteCon(
        sesion,
        servidorFalso({
          '/api/alertas': (_) => http.Response(
            jsonEncode({
              'mensaje': 'Necesitas pertenecer a una comunidad aprobada.',
              'codigo': 'SIN_COMUNIDAD',
            }),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        }),
      );

      await expectLater(
        api.obtener('/api/alertas/comunidad'),
        throwsA(isA<ExcepcionApi>().having((e) => e.codigo, 'codigo', 'SIN_COMUNIDAD')),
      );

      // El vecino ESTÁ autenticado: solo le falta pertenencia. Expulsarlo al
      // ingreso sería un error.
      expect(sesion.autenticado, isTrue);
    });
  });

  group('ClienteApi — traducción de errores', () {
    test('un 400 expone los errores por campo', () async {
      final sesion = sesionDePrueba();
      final api = clienteCon(
        sesion,
        servidorFalso({
          '/api/usuarios/registro': (_) => http.Response(
            jsonEncode({
              'mensaje': 'Revisa los datos ingresados.',
              'errores': [
                {'campo': 'telefono', 'mensaje': 'El teléfono debe tener entre 7 y 15 dígitos.'},
                {'campo': 'password', 'mensaje': 'La contraseña debe tener al menos 8 caracteres.'},
              ],
            }),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        }),
      );

      try {
        await api.publicar('/api/usuarios/registro');
        fail('debía lanzar');
      } on ExcepcionApi catch (e) {
        // Convertidos a mapa para que cada CampoTexto lea el suyo.
        expect(e.erroresPorCampo['telefono'], contains('7 y 15 dígitos'));
        expect(e.erroresPorCampo['password'], contains('8 caracteres'));
      }
    });

    test('un 500 no filtra detalles del servidor al usuario', () async {
      final sesion = sesionDePrueba();
      final api = clienteCon(
        sesion,
        servidorFalso({'/api/alertas': (_) => http.Response('stack trace interno', 500)}),
      );

      await expectLater(
        api.obtener('/api/alertas/comunidad'),
        throwsA(
          isA<ExcepcionApi>().having(
            (e) => e.mensaje,
            'mensaje',
            'El servidor tuvo un problema. Inténtalo en unos momentos.',
          ),
        ),
      );
    });

    test('un 429 propaga el mensaje de espera del servidor', () async {
      final sesion = await sesionActiva();
      final api = clienteCon(
        sesion,
        servidorFalso({'/api/alertas': (_) => falla(429, 'Espera 42 segundos.')}),
      );

      await expectLater(
        api.publicar('/api/alertas/emitir'),
        throwsA(isA<ExcepcionApi>().having((e) => e.mensaje, 'mensaje', 'Espera 42 segundos.')),
      );
    });
  });

  group('ServicioUsuarios', () {
    test('ingresar abre sesión y persiste el token', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);

      final servicio = ServicioUsuarios(
        clienteCon(
          sesion,
          servidorFalso({
            '/api/usuarios/login': (_) => ok({
              'token': 'jwt-emitido',
              'perfil': perfilJson(estado: 'SIN_COMUNIDAD'),
            }),
          }),
        ),
      );

      final perfil = await servicio.ingresar(telefono: '0991234567', password: 'clave12345');

      expect(perfil.estadoMembresia, EstadoMembresia.sinComunidad);
      expect(sesion.autenticado, isTrue);
      expect(await almacen.leer('vecino_seguro.token'), 'jwt-emitido');
    });

    test('registrar entra directo, sin un segundo viaje al servidor', () async {
      final sesion = sesionDePrueba();
      final servicio = ServicioUsuarios(
        clienteCon(
          sesion,
          servidorFalso({
            '/api/usuarios/registro': (_) => ok({
              'token': 'jwt-registro',
              'perfil': perfilJson(estado: 'SIN_COMUNIDAD'),
            }),
          }),
        ),
      );

      await servicio.registrar(
        nombre: 'Ana',
        telefono: '0987654321',
        password: 'clave12345',
      );

      expect(sesion.autenticado, isTrue);
      expect(sesion.token, 'jwt-registro');
    });

    test('obtenerPerfil refresca la sesión: es cómo se detecta la aprobación', () async {
      final sesion = await sesionActiva();
      // Estado inicial: esperando aprobación del administrador.
      sesion.actualizarPerfil(PerfilVecino.desdeJson(perfilJson(estado: 'PENDIENTE')));
      expect(sesion.membresia, EstadoMembresia.pendiente);

      final servicio = ServicioUsuarios(
        clienteCon(
          sesion,
          servidorFalso({'/api/usuarios/yo': (_) => ok(perfilJson(estado: 'ACTIVO'))}),
        ),
      );

      await servicio.obtenerPerfil();

      // El administrador aprobó: la sesión lo refleja sin volver a ingresar.
      expect(sesion.membresia, EstadoMembresia.activo);
    });

    test('un token vacío del servidor se rechaza', () async {
      final sesion = sesionDePrueba();
      final servicio = ServicioUsuarios(
        clienteCon(
          sesion,
          servidorFalso({'/api/usuarios/login': (_) => ok({'perfil': perfilJson()})}),
        ),
      );

      await expectLater(
        servicio.ingresar(telefono: '0991234567', password: 'x'),
        throwsA(isA<ExcepcionApi>()),
      );
      expect(sesion.autenticado, isFalse);
    });
  });

  group('PerfilVecino — contrato de la API', () {
    test('mapea los tres estados de membresía', () {
      expect(
        PerfilVecino.desdeJson(perfilJson(estado: 'ACTIVO')).estadoMembresia,
        EstadoMembresia.activo,
      );
      expect(
        PerfilVecino.desdeJson(perfilJson(estado: 'PENDIENTE')).estadoMembresia,
        EstadoMembresia.pendiente,
      );
      expect(
        PerfilVecino.desdeJson(perfilJson(estado: 'SIN_COMUNIDAD')).estadoMembresia,
        EstadoMembresia.sinComunidad,
      );
    });

    test('un estado desconocido degrada a "sin comunidad", no revienta', () {
      final perfil = PerfilVecino.desdeJson(perfilJson(estado: 'ALGO_NUEVO'));
      expect(perfil.estadoMembresia, EstadoMembresia.sinComunidad);
      expect(perfil.puedeUsarAlertas, isFalse);
    });

    test('detecta al administrador de la comunidad', () {
      expect(PerfilVecino.desdeJson(perfilJson(esAdmin: true)).esAdmin, isTrue);
      expect(PerfilVecino.desdeJson(perfilJson(esAdmin: false)).esAdmin, isFalse);
    });
  });
}
