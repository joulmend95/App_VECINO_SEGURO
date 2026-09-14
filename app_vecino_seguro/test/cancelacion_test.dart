import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/navegacion/rutas.dart';
import 'package:app_vecino_seguro/red/fallos_de_red.dart';
import 'package:app_vecino_seguro/screens/pantalla_detalle_alerta.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';

import 'ayudas_prueba.dart';

/// PASO 18 — CANCELACIÓN DE PETICIONES
///
/// Cuando el vecino abandona una pantalla, la petición que estaba esperando
/// deja de tener destinatario. Cancelarla evita gastar sus datos móviles en una
/// respuesta que nadie va a mirar.
void main() {
  group('CancelToken', () {
    test('cancelar una petición en vuelo la aborta', () async {
      final completador = Completer<http.Response>();

      final api = ClienteApi(
        sesion: await sesionActiva(),
        urlBase: 'http://falso',
        // Servidor que nunca responde: simula una red lenta de verdad.
        cliente: MockClient((_) => completador.future),
      );

      final cancelacion = CancelToken();
      final peticion = api.obtener(
        '/api/alertas/comunidad',
        cancelacion: cancelacion,
      );

      cancelacion.cancel('el vecino se fue');

      await expectLater(
        peticion,
        throwsA(
          isA<ExcepcionApi>()
              .having((e) => e.codigo, 'codigo', FallosDeRed.cancelada)
              .having((e) => e.fueCancelada, 'fueCancelada', isTrue),
        ),
      );
    });

    test('una cancelación NO se confunde con falta de conexión', () async {
      final completador = Completer<http.Response>();
      final api = ClienteApi(
        sesion: await sesionActiva(),
        urlBase: 'http://falso',
        cliente: MockClient((_) => completador.future),
      );

      final cancelacion = CancelToken();
      final peticion = api.obtener('/api/alertas/comunidad', cancelacion: cancelacion);
      cancelacion.cancel();

      // La diferencia importa: "sin conexión" hace que el muro sirva su caché
      // y que la cola conserve la operación. Una cancelación no debe disparar
      // nada de eso: el vecino simplemente se fue.
      await expectLater(
        peticion,
        throwsA(
          isA<ExcepcionApi>().having((e) => e.esSinConexion, 'esSinConexion', isFalse),
        ),
      );
    });

    test('sin cancelar, la petición llega normalmente', () async {
      final api = ClienteApi(
        sesion: await sesionActiva(),
        urlBase: 'http://falso',
        cliente: servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson()])),
        }),
      );

      final datos = await api.obtener(
        '/api/alertas/comunidad',
        cancelacion: CancelToken(),
      );

      expect(datos['data'], hasLength(1));
    });
  });

  group('Las pantallas cancelan al salir', () {
    testWidgets('salir del detalle no deja un error en pantalla', (tester) async {
      final montaje = montarAppConEnrutador(
        sesion: await sesionActiva(),
        cliente: servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson()])),
          'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42))),
        }),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.aDetalleAlerta(42));
      await tester.pumpAndSettle();
      expect(find.byType(PantallaDetalleAlerta), findsOneWidget);

      // Salir desmonta la pantalla y cancela lo que siguiera en vuelo.
      montaje.enrutador.go(Rutas.alertas);
      await tester.pumpAndSettle();

      expect(find.byType(PantallaDetalleAlerta), findsNothing);
      // Lo que se comprueba de verdad: salir no produjo ninguna excepción sin
      // capturar. Sin la guardia `fueCancelada`, el `setState` posterior
      // pintaría un error de red en una pantalla que ya nadie mira.
      expect(tester.takeException(), isNull);
    });
  });
}
