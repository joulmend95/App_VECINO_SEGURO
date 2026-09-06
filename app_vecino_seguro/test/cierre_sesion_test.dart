import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_vecino_seguro/modelos/alerta.dart';
import 'package:app_vecino_seguro/servicios/almacen_local.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';

import 'ayudas_prueba.dart';

/// PASO 15 — CIERRE DE SESIÓN Y DATOS PERSONALES
///
/// Este archivo existe por un fallo real que había en el proyecto:
/// `Sesion.cerrar()` borraba **solo** el token. La cola de pánico sobrevivía al
/// cierre de sesión, así que si un vecino cerraba sesión con una emergencia
/// encolada y otro ingresaba en el mismo teléfono, la alerta del primero se
/// emitía en la comunidad del segundo.
void main() {
  MockClient sinRed() =>
      MockClient((_) async => throw const SocketException('modo avión'));

  group('Al cerrar sesión no queda nada', () {
    test('el almacén cifrado queda completamente vacío', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);
      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());

      // Token y perfil.
      expect(almacen.claves, hasLength(2));

      await sesion.cerrar();

      // Se comprueba que NO queda ninguna clave, en vez de comprobar clave por
      // clave. Enumerarlas es justo lo que falló antes: la de la cola de pánico
      // no estaba en la lista de nadie.
      expect(almacen.claves, isEmpty);
      expect(sesion.autenticado, isFalse);
      expect(sesion.perfil, isNull);
    });

    test('una clave de otro subsistema tampoco sobrevive', () async {
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);
      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());

      // Cualquiera podría añadir esto mañana sin tocar `Sesion`.
      await almacen.escribir('vecino_seguro.lo_que_sea', 'dato personal');

      await sesion.cerrar();

      expect(almacen.claves, isEmpty);
    });

    test('la base local se vacía: alertas, cola y metadatos', () async {
      SharedPreferences.setMockInitialValues({});

      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      final sesion = Sesion(almacen: AlmacenEnMemoria());
      final servicios = serviciosDePrueba(
        sesion: sesion,
        cliente: sinRed(),
        local: local,
      );

      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());
      await local.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson(id: 1))]);
      await servicios.cola.encolarAlerta(tipoAlerta: 'Robo');

      expect(await local.leerAlertas(1), isNotEmpty);
      expect(await local.leerCola(), isNotEmpty);

      await sesion.cerrar();

      // Las alertas cacheadas incluyen el NOMBRE del vecino que las emitió:
      // dato personal de terceros. Por eso se borran, no solo caducan.
      expect(await local.leerAlertas(1), isEmpty);
      expect(await local.ultimaSincronizacion(), isNull);
    });

    test('LA COLA PENDIENTE NO SOBREVIVE AL CIERRE DE SESIÓN', () async {
      SharedPreferences.setMockInitialValues({});

      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      final sesion = Sesion(almacen: AlmacenEnMemoria());
      final servicios = serviciosDePrueba(
        sesion: sesion,
        cliente: sinRed(),
        local: local,
      );

      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());
      await servicios.cola.encolarAlerta(tipoAlerta: 'Robo');
      expect(await local.leerCola(), hasLength(1));

      await sesion.cerrar();

      expect(
        await local.leerCola(),
        isEmpty,
        reason: 'Este es el fallo original: si la cola sobrevive, el siguiente '
            'vecino que ingrese en este teléfono emitirá la alerta del anterior '
            'en SU comunidad, con SU token.',
      );
    });

    test('el borrador en memoria también se descarta', () async {
      SharedPreferences.setMockInitialValues({});

      final sesion = Sesion(almacen: AlmacenEnMemoria());
      final servicios = serviciosDePrueba(sesion: sesion, cliente: sinRed());

      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());
      servicios.borrador.descripcion = 'Texto privado del vecino anterior';
      servicios.borrador.categoria = null;

      await sesion.cerrar();

      expect(servicios.borrador.descripcion, isEmpty);
      expect(servicios.borrador.tieneContenido, isFalse);
    });

    test('las preferencias se limpian: el gesto de pánico no se hereda', () async {
      SharedPreferences.setMockInitialValues({'panico_activado': true});

      final sesion = Sesion(almacen: AlmacenEnMemoria());
      serviciosDePrueba(sesion: sesion, cliente: sinRed());
      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());

      await sesion.cerrar();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('panico_activado'),
        isNull,
        reason: 'Es una preferencia de la persona, no del dispositivo: dejarla '
            'activada le encendería el gesto al siguiente vecino.',
      );
    });
  });

  group('Un 401 también borra todo', () {
    test('la sesión cerrada por el servidor no deja rastro local', () async {
      SharedPreferences.setMockInitialValues({});

      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      final almacen = AlmacenEnMemoria();
      final sesion = Sesion(almacen: almacen);

      final servicios = serviciosDePrueba(
        sesion: sesion,
        cliente: servidorFalso({
          'alertas': (_) => falla(401, 'Se requiere iniciar sesión.'),
        }),
        local: local,
      );

      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());
      await local.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson(id: 1))]);

      // El cliente cierra la sesión solo al recibir el 401.
      await expectLater(
        () => servicios.api.obtener('/api/alertas/comunidad'),
        throwsA(isA<Object>()),
      );

      expect(almacen.claves, isEmpty);
      expect(await local.leerAlertas(1), isEmpty);
    });
  });

  group('Volver a ingresar repuebla desde el servidor', () {
    test('tras cerrar y reabrir sesión, la base se llena de nuevo', () async {
      SharedPreferences.setMockInitialValues({});

      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      final sesion = Sesion(almacen: AlmacenEnMemoria());

      final servicios = serviciosDePrueba(
        sesion: sesion,
        cliente: servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson(id: 5)])),
        }),
        local: local,
      );

      await sesion.iniciar(token: 'jwt', perfil: perfilDePrueba());
      await servicios.alertas.obtenerAlertasComunidad();
      expect(await local.leerAlertas(1), hasLength(1));

      await sesion.cerrar();
      expect(await local.leerAlertas(1), isEmpty);

      await sesion.iniciar(token: 'jwt-2', perfil: perfilDePrueba());
      await servicios.alertas.obtenerAlertasComunidad();

      expect(await local.leerAlertas(1), hasLength(1));
    });
  });
}
