import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/red/credenciales.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/servicio_usuarios.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';

import 'ayudas_prueba.dart';

/// PASO 17 — EL PAR DE TOKENS, DE PUNTA A PUNTA
///
/// El servidor devuelve dos tokens al ingresar. Si el cliente guarda solo uno,
/// la renovación automática no puede funcionar y el vecino queda expulsado a
/// los 15 minutos — con toda la maquinaria de interceptores construida y
/// aparentemente correcta.
void main() {
  group('El par de tokens llega al almacén cifrado', () {
    test('ingresar guarda acceso Y renovación', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);
      final usuarios = ServicioUsuarios(
        ClienteApi(
          sesion: sesion,
          urlBase: 'http://falso',
          cliente: servidorFalso({
            'usuarios/login': (_) => ok({
              'token': 'acceso-1',
              'token_renovacion': 'renovacion-1',
              'perfil': perfilJson(),
            }),
          }),
        ),
      );

      await usuarios.ingresar(telefono: '0991234567', password: 'clave12345');

      final cred = Credenciales(almacen);
      expect(await cred.tokenAcceso(), 'acceso-1');
      expect(
        await cred.tokenRenovacion(),
        'renovacion-1',
        reason: 'Sin esto el interceptor no tendría con qué renovar y el '
            'vecino sería expulsado a los 15 minutos.',
      );
    });

    test('registrarse también guarda el par', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);
      final usuarios = ServicioUsuarios(
        ClienteApi(
          sesion: sesion,
          urlBase: 'http://falso',
          cliente: servidorFalso({
            'usuarios/registro': (_) => ok({
              'token': 'acceso-2',
              'token_renovacion': 'renovacion-2',
              'perfil': perfilJson(estado: 'SIN_COMUNIDAD'),
            }),
          }),
        ),
      );

      await usuarios.registrar(
        nombre: 'Ana Vera',
        telefono: '0991234567',
        password: 'clave12345',
      );

      final cred = Credenciales(almacen);
      expect(await cred.tokenAcceso(), 'acceso-2');
      expect(await cred.tokenRenovacion(), 'renovacion-2');
    });

    test('un servidor que no devuelve renovación no rompe el ingreso', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);
      final usuarios = ServicioUsuarios(
        ClienteApi(
          sesion: sesion,
          urlBase: 'http://falso',
          cliente: servidorFalso({
            'usuarios/login': (_) =>
                ok({'token': 'solo-acceso', 'perfil': perfilJson()}),
          }),
        ),
      );

      // Compatibilidad hacia atrás: la app entra igual, solo que sin renovación
      // automática. Romper el ingreso sería peor que perder una comodidad.
      await usuarios.ingresar(telefono: '0991234567', password: 'clave12345');

      expect(sesion.autenticado, isTrue);
      expect(await Credenciales(almacen).tokenRenovacion(), isNull);
    });

    test('cerrar sesión borra AMBOS tokens', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);

      await sesion.iniciar(
        token: 'acceso',
        perfil: perfilDePrueba(),
        tokenRenovacion: 'renovacion',
      );
      expect(almacen.claves, hasLength(3)); // acceso + renovación + perfil

      await sesion.cerrar();

      // Se comprueba que no queda NADA, no clave por clave: es la regla de la
      // Semana 12, y no depende de recordar qué claves existen.
      expect(almacen.claves, isEmpty);
    });
  });

  group('Revocación en el servidor al cerrar sesión', () {
    test('llama a /salir con el token todavía válido', () async {
      String? autorizacionRecibida;
      final sesion = await sesionActiva();

      final usuarios = ServicioUsuarios(
        ClienteApi(
          sesion: sesion,
          urlBase: 'http://falso',
          cliente: servidorFalso(
            {'usuarios/salir': (_) => ok({'sesiones_revocadas': 1})},
            alRecibir: (p) => autorizacionRecibida = p.headers['Authorization'],
          ),
        ),
      );

      await usuarios.revocarEnServidor();

      // El orden importa: revocar exige credencial, y `cerrar()` la borra.
      expect(autorizacionRecibida, 'Bearer jwt-de-prueba');
    });

    test('si el servidor no responde, NO propaga el error', () async {
      final sesion = await sesionActiva();
      final usuarios = ServicioUsuarios(
        ClienteApi(
          sesion: sesion,
          urlBase: 'http://falso',
          cliente: servidorFalso({'usuarios/salir': (_) => falla(500, 'caído')}),
        ),
      );

      // Dejar la sesión abierta en el teléfono porque no había cobertura sería
      // lo contrario de lo que el vecino pidió.
      await expectLater(usuarios.revocarEnServidor(), completes);
    });
  });
}
