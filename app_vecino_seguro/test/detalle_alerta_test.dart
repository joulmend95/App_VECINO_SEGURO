import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:app_vecino_seguro/screens/pantalla_detalle_alerta.dart';
import 'package:app_vecino_seguro/widgets/boton_accion.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

import 'ayudas_prueba.dart';

/// PASO 10 — PANTALLA DE DETALLE
///
/// Consume `GET /api/alertas/:id`.
///
/// Lo que se verifica aquí no es solo que pinte una alerta, sino la propiedad
/// que justifica su diseño: **se reconstruye a partir de su dirección**. En
/// ninguna prueba se le entrega un objeto `Alerta`; siempre parte de un número.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required int idAlerta,
    required Map<String, http.Response Function(http.Request)> rutas,
    void Function(http.Request)? alRecibir,
    double escalaTexto = 1.0,
    Size? tamano,
    bool oscuro = false,
  }) async {
    await tester.pumpWidget(
      montarConDependencias(
        hijo: PantallaDetalleAlerta(idAlerta: idAlerta),
        sesion: await sesionActiva(),
        cliente: servidorFalso(rutas, alRecibir: alRecibir),
        escalaTexto: escalaTexto,
        tamano: tamano,
        oscuro: oscuro,
      ),
    );
  }

  group('Estados de la petición', () {
    testWidgets('muestra cargando mientras el servidor responde', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42)))},
      );

      // Primer frame ya renderizado por `pumpWidget`, antes de que el
      // callback posterior al frame dispare la petición.
      expect(find.text('Cargando...'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('Cargando...'), findsNothing);
    });

    testWidgets('muestra la alerta cuando el servidor responde', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {
          'alertas/': (_) => ok(
            cuerpoAlerta(alertaJson(id: 42, tipo: 'Incendio', vecino: 'Luis')),
          ),
        },
      );
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Incendio'), findsWidgets);
      expect(find.textContaining('Luis'), findsWidgets);
      expect(find.text('Estado'), findsOneWidget);
      expect(find.text('Fecha y hora'), findsOneWidget);
    });

    testWidgets('un 404 se muestra como error con reintentar', (tester) async {
      await montar(
        tester,
        idAlerta: 999,
        rutas: {
          'alertas/': (_) =>
              falla(404, 'Esta alerta no existe o ya no está disponible.'),
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar la información'), findsOneWidget);
      expect(
        find.text('Esta alerta no existe o ya no está disponible.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(BotonAccion, 'Reintentar'), findsOneWidget);
    });

    testWidgets('reintentar vuelve a pedir la alerta y se recupera', (tester) async {
      var intentos = 0;
      await montar(
        tester,
        idAlerta: 42,
        rutas: {
          'alertas/': (_) {
            intentos++;
            return intentos == 1
                ? falla(500, 'error')
                : ok(cuerpoAlerta(alertaJson(id: 42, tipo: 'Incendio')));
          },
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('No pudimos cargar la información'), findsOneWidget);

      await tester.tap(find.widgetWithText(BotonAccion, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(intentos, 2);
    });
  });

  group('Reconstrucción desde la dirección', () {
    testWidgets('pide exactamente el identificador de la ruta', (tester) async {
      String? rutaPedida;
      await montar(
        tester,
        idAlerta: 42,
        rutas: {'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42)))},
        alRecibir: (p) => rutaPedida = p.url.path,
      );
      await tester.pumpAndSettle();

      // El identificador viaja por la ruta, no en el cuerpo ni en la consulta.
      expect(rutaPedida, '/api/alertas/42');
    });

    testWidgets('un identificador malformado no llega a la red', (tester) async {
      var hubosPeticion = false;
      // idAlerta = 0 es lo que produce `int.tryParse('abc') ?? 0` en el
      // enrutador cuando la dirección trae basura.
      await montar(
        tester,
        idAlerta: 0,
        rutas: {'alertas/': (_) => ok(cuerpoAlerta(alertaJson()))},
        alRecibir: (_) => hubosPeticion = true,
      );
      await tester.pumpAndSettle();

      expect(
        hubosPeticion,
        isFalse,
        reason: 'El servidor respondería 400; gastar el viaje para saber lo que '
            'ya se ve en el parámetro no aporta nada.',
      );
      expect(
        find.text('Esta dirección no corresponde a ninguna alerta.'),
        findsOneWidget,
      );
      // Sin acción de reintentar: reintentar no puede arreglar una dirección.
      expect(find.widgetWithText(BotonAccion, 'Reintentar'), findsNothing);
    });
  });

  group('Contenido', () {
    testWidgets('el pánico prevalece sobre el texto de la alerta', (tester) async {
      await montar(
        tester,
        idAlerta: 7,
        rutas: {
          'alertas/': (_) => ok(
            cuerpoAlerta(
              alertaJson(id: 7, tipo: 'Emergencia', esPanico: true),
            ),
          ),
        },
      );
      await tester.pumpAndSettle();

      // La categoría se fuerza a `panico`, que es crítica. Deducirla del texto
      // libre podría clasificarla como urgencia media.
      expect(find.textContaining('Crítica'), findsWidgets);
    });

    testWidgets('una alerta sin detalle lo dice, no deja un hueco', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42)))},
      );
      await tester.pumpAndSettle();

      expect(find.text('El vecino no añadió ningún detalle.'), findsOneWidget);
    });
  });

  group('Accesibilidad', () {
    // Mismo listón que ya cumple el muro: una pantalla nueva no puede bajarlo.

    testWidgets('contraste de texto en tema claro', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42)))},
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });

    testWidgets('contraste de texto en tema oscuro', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42)))},
        oscuro: true,
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });

    testWidgets('el estado de error cumple contraste y área táctil', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {'alertas/': (_) => falla(500, 'error')},
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('a 320 dp con la fuente al 200% no desborda', (tester) async {
      await montar(
        tester,
        idAlerta: 42,
        rutas: {
          'alertas/': (_) => ok(
            cuerpoAlerta(
              alertaJson(id: 42, tipo: 'Emergencia médica', vecino: 'Esperanza'),
            ),
          ),
        },
        tamano: const Size(320, 640),
        escalaTexto: 2.0,
      );
      await tester.pumpAndSettle();

      // El caso que descubrió el desborde de 35 px en el muro.
      expect(tester.takeException(), isNull);
    });
  });
}
