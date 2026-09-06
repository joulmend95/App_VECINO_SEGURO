import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/modelos/alerta.dart';
import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/navegacion/rutas.dart';
import 'package:app_vecino_seguro/screens/pantalla_ingreso.dart';
import 'package:app_vecino_seguro/screens/pantalla_muro_alertas.dart';
import 'package:app_vecino_seguro/servicios/almacen_local.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/servicio_alertas.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

import 'ayudas_prueba.dart';

/// PASO 14 — LECTURA SIN CONEXIÓN
void main() {
  /// Cliente que nunca llega al servidor: es el modo avión.
  MockClient sinRed() =>
      MockClient((_) async => throw const SocketException('modo avión'));

  ServicioAlertas servicioCon(Sesion sesion, MockClient cliente, AlmacenLocal local) =>
      ServicioAlertas(
        ClienteApi(sesion: sesion, cliente: cliente, urlBase: 'http://falso'),
        almacenLocal: local,
      );

  group('El listado sobrevive al modo avión', () {
    test('la descarga con éxito llena la base local', () async {
      final sesion = await sesionActiva();
      final local = AlmacenLocalEnMemoria();
      await local.abrir();

      final servicio = servicioCon(
        sesion,
        servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson(id: 1)])),
        }),
        local,
      );

      final respuesta = await servicio.obtenerAlertasComunidad();

      expect(respuesta.esLocal, isFalse);
      expect(await local.leerAlertas(1), hasLength(1));
    });

    test('sin red se sirve lo guardado, marcado como local', () async {
      final sesion = await sesionActiva();
      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      await local.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 1, tipo: 'Robo')),
      ]);

      final respuesta = await servicioCon(
        sesion,
        sinRed(),
        local,
      ).obtenerAlertasComunidad();

      expect(respuesta.alertas, hasLength(1));
      expect(respuesta.esLocal, isTrue);
      expect(respuesta.antiguedad, isNotNull);
    });

    test('sin red y sin nada guardado, se propaga el error', () async {
      final sesion = await sesionActiva();
      final local = AlmacenLocalEnMemoria();
      await local.abrir();

      // No hay nada mejor que ofrecer que el error de red, que al menos
      // explica lo que pasa.
      await expectLater(
        () => servicioCon(sesion, sinRed(), local).obtenerAlertasComunidad(),
        throwsA(isA<ExcepcionApi>().having((e) => e.esSinConexion, 'esSinConexion', isTrue)),
      );
    });

    test('un 500 NO sirve la caché: se propaga', () async {
      final sesion = await sesionActiva();
      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      await local.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson(id: 1))]);

      // Es la distinción que importa: enseñar datos viejos cuando el servidor
      // está contestando mal esconde el problema real y hace creer al vecino
      // que todo va bien.
      await expectLater(
        () => servicioCon(
          sesion,
          servidorFalso({'alertas/comunidad': (_) => falla(500, 'error')}),
          local,
        ).obtenerAlertasComunidad(),
        throwsA(isA<ExcepcionApi>()),
      );
    });

    test('sincronizar sustituye lo guardado, no lo acumula', () async {
      final sesion = await sesionActiva();
      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      await local.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 1)),
        Alerta.desdeJson(alertaJson(id: 2)),
      ]);

      await servicioCon(
        sesion,
        servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson(id: 9)])),
        }),
        local,
      ).obtenerAlertasComunidad();

      final guardadas = await local.leerAlertas(1);
      expect(guardadas, hasLength(1));
      expect(guardadas.single.idAlerta, 9);
    });
  });

  group('El muro avisa de que los datos están guardados', () {
    testWidgets('muestra las alertas locales y su antigüedad', (tester) async {
      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      await local.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 1, tipo: 'Robo', vecino: 'María')),
      ]);

      final montaje = montarAppConEnrutador(
        sesion: await sesionActiva(),
        cliente: sinRed(),
        local: local,
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      // El listado funciona en modo avión.
      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Robo'), findsWidgets);

      // Y lo dice: un muro sin aviso se interpreta como "no ha pasado nada".
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.textContaining('datos guardados'), findsOneWidget);
    });

    testWidgets('con datos frescos NO aparece el aviso', (tester) async {
      final montaje = montarAppConEnrutador(
        sesion: await sesionActiva(),
        cliente: servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson(id: 1)])),
          'notificaciones': (_) => ok({'no_leidas': 0, 'data': []}),
        }),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      expect(find.byType(PantallaMuroAlertas), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsNothing);
    });

    testWidgets('el buscador sigue funcionando sobre los datos locales', (tester) async {
      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      await local.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 1, tipo: 'Robo', vecino: 'María')),
        Alerta.desdeJson(alertaJson(id: 2, tipo: 'Incendio', vecino: 'Luis')),
      ]);

      final montaje = montarAppConEnrutador(
        sesion: await sesionActiva(),
        cliente: sinRed(),
        local: local,
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsNWidgets(2));

      // El filtro es local sobre la lista ya cargada, así que funciona sin red
      // sin ningún cambio.
      await tester.enterText(find.byType(TextField).first, 'Incendio');
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
    });
  });

  group('La sesión sobrevive al reinicio sin conexión', () {
    testWidgets('con perfil guardado, la app entra al muro en modo avión', (tester) async {
      // Simula un arranque en frío: token y perfil ya guardados por una sesión
      // anterior, exactamente como quedarían tras cerrar la app.
      final almacen = AlmacenEnMemoria({
        'vecino_seguro.token': 'jwt-de-prueba',
      });
      final anterior = Sesion(almacen: almacen);
      await anterior.iniciar(token: 'jwt-de-prueba', perfil: perfilDePrueba());

      final local = AlmacenLocalEnMemoria();
      await local.abrir();
      await local.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson(id: 1))]);

      // Arranque nuevo con el mismo almacén y SIN red.
      final montaje = montarAppConEnrutador(
        sesion: Sesion(almacen: almacen),
        cliente: sinRed(),
        local: local,
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      // Antes de este avance, la app se quedaba bloqueada en la pantalla de
      // arranque con un error de red, teniendo una credencial válida al lado.
      expect(find.byType(PantallaMuroAlertas), findsOneWidget);
      expect(find.byType(PantallaIngreso), findsNothing);
    });

    testWidgets('sin perfil guardado sí se pide ingresar', (tester) async {
      final montaje = montarAppConEnrutador(
        sesion: sesionDePrueba(),
        cliente: sinRed(),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      expect(find.byType(PantallaIngreso), findsOneWidget);
    });

    test('el perfil guardado se relee con su membresía intacta', () async {
      final almacen = AlmacenEnMemoria();
      final primera = Sesion(almacen: almacen);
      await primera.iniciar(
        token: 'jwt',
        perfil: perfilDePrueba(esAdmin: true),
      );

      final segunda = Sesion(almacen: almacen);
      await segunda.restaurarSesion();

      expect(segunda.autenticado, isTrue);
      expect(segunda.membresia, EstadoMembresia.activo);
      expect(segunda.perfil?.esAdmin, isTrue);
      expect(segunda.perfil?.comunidad?.codigo, 'URB-2026');
    });
  });

  group('Rutas privadas siguen protegidas sin conexión', () {
    testWidgets('sin sesión, el modo avión no abre el muro', (tester) async {
      final montaje = montarAppConEnrutador(
        sesion: sesionDePrueba(),
        cliente: sinRed(),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.alertas);
      await tester.pumpAndSettle();

      // La falta de red no puede convertirse en una puerta trasera.
      expect(find.byType(PantallaIngreso), findsOneWidget);
    });
  });
}
