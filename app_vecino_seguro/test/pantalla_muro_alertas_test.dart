import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/screens/pantalla_muro_alertas.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/dependencias.dart';
import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/theme/tema_app.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

/// Construye un cliente HTTP simulado que responde como el backend real.
///
/// `respuestaAlertas` recibe el cuerpo que devolverá `GET /api/alertas/comunidad`.
MockClient _servidorFalso({
  required int codigoAlertas,
  String? cuerpoAlertas,
  bool tokenFalla = false,
}) {
  return MockClient((peticion) async {
    if (peticion.url.path.contains('token-prueba')) {
      if (tokenFalla) return http.Response('{"mensaje":"error"}', 500);
      return http.Response(jsonEncode({'token': 'jwt-de-prueba'}), 200);
    }
    if (peticion.url.path.contains('alertas/comunidad')) {
      // Verifica que la pantalla realmente envía el Bearer.
      expect(peticion.headers['Authorization'], 'Bearer jwt-de-prueba');
      return http.Response(
        cuerpoAlertas ?? '{"fuente":"BD","data":[]}',
        codigoAlertas,
      );
    }
    return http.Response('no encontrado', 404);
  });
}

String _cuerpoConAlertas(List<Map<String, dynamic>> alertas) {
  return jsonEncode({'fuente': 'BASE_DE_DATOS_POSTGRESQL', 'data': alertas});
}

Map<String, dynamic> _alertaJson({
  int id = 1,
  String tipo = 'Robo',
  String vecino = 'Jorge',
  String estado = 'Activa',
}) {
  return {
    'id_alerta': id,
    'tipo_alerta': tipo,
    'fecha_hora': DateTime.now()
        .subtract(const Duration(minutes: 5))
        .toIso8601String(),
    'estado': estado,
    'id_usuario': 1,
    'usuario': {'id_usuario': 1, 'nombre': vecino, 'telefono': '099'},
  };
}

Widget _montarPantalla(
  MockClient cliente, {
  Size tamano = const Size(411, 891),
  double escalaTexto = 1.0,
  bool oscuro = false,
}) {
  final sesion = Sesion(almacen: AlmacenEnMemoria());
  sesion.iniciar(
    token: 'jwt-de-prueba',
    perfil: PerfilVecino.desdeJson({
      'id_usuario': 1,
      'nombre': 'Jorge',
      'telefono': '0991234567',
      'estado_membresia': 'ACTIVO',
      'comunidad': {
        'id_comunidad': 1,
        'nombre': 'Urbanización El Bosque',
        'codigo': 'URB-2026',
        'es_admin': false,
      },
    }),
  );

  final servicios = Servicios(
    sesion: sesion,
    cliente: ClienteApi(sesion: sesion, cliente: cliente, urlBase: 'http://falso'),
  );

  return Dependencias(
    servicios: servicios,
    child: MaterialApp(
      theme: TemaApp.claro,
      darkTheme: TemaApp.oscuro,
      themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: tamano,
          textScaler: TextScaler.linear(escalaTexto),
        ),
        child: const PantallaMuroAlertas(),
      ),
    ),
  );
}

void main() {
  group('PantallaMuroAlertas — estados reales de la API', () {
    testWidgets('CARGANDO mientras la petición está en curso', (tester) async {
      await tester.pumpWidget(
        _montarPantalla(_servidorFalso(codigoAlertas: 200)),
      );
      // Primer frame: aún no resuelve el Future.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('VACÍO cuando data viene como arreglo vacío', (tester) async {
      await tester.pumpWidget(
        _montarPantalla(
          _servidorFalso(
            codigoAlertas: 200,
            cuerpoAlertas: _cuerpoConAlertas([]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todo tranquilo por aquí'), findsOneWidget);
      expect(find.byType(TarjetaAlerta), findsNothing);
    });

    testWidgets('ERROR cuando el servidor responde 500', (tester) async {
      await tester.pumpWidget(
        _montarPantalla(_servidorFalso(codigoAlertas: 500)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar la información'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('ERROR permite reintentar y recuperarse', (tester) async {
      var intentos = 0;
      final cliente = MockClient((peticion) async {
        if (peticion.url.path.contains('token-prueba')) {
          return http.Response(jsonEncode({'token': 'jwt-de-prueba'}), 200);
        }
        intentos++;
        if (intentos == 1) return http.Response('boom', 500);
        return http.Response(
          _cuerpoConAlertas([_alertaJson(tipo: 'Incendio')]),
          200,
        );
      });

      await tester.pumpWidget(_montarPantalla(cliente));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Incendio'), findsOneWidget);
    });

    testWidgets('CON DATOS renderiza una tarjeta por alerta', (tester) async {
      await tester.pumpWidget(
        _montarPantalla(
          _servidorFalso(
            codigoAlertas: 200,
            cuerpoAlertas: _cuerpoConAlertas([
              _alertaJson(id: 1, tipo: 'Robo', vecino: 'Jorge'),
              _alertaJson(id: 2, tipo: 'Incendio', vecino: 'María'),
              _alertaJson(id: 3, tipo: 'Sospechoso', vecino: 'Luis'),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsNWidgets(3));
      expect(find.text('Robo'), findsOneWidget);
      expect(find.text('Reportado por María'), findsOneWidget);
    });

    testWidgets('un 403 cierra la sesión en lugar de renovar el token', (
      tester,
    ) async {
      // Cambio de comportamiento respecto al servicio anterior: `ApiAlertas`
      // renovaba el token por su cuenta y seguía adelante. Eso enmascaraba una
      // sesión realmente inválida y dejaba al vecino en una pantalla que nunca
      // cargaba. Ahora la sesión se cierra y la guardia del enrutador lleva al
      // ingreso, en un único lugar para toda la app.
      final sesion = Sesion(almacen: AlmacenEnMemoria());
      await sesion.iniciar(
        token: 'jwt-caducado',
        perfil: PerfilVecino.desdeJson({
          'id_usuario': 1,
          'nombre': 'Jorge',
          'telefono': '0991234567',
          'estado_membresia': 'ACTIVO',
          'comunidad': {
            'id_comunidad': 1,
            'nombre': 'Urbanización El Bosque',
            'codigo': 'URB-2026',
            'es_admin': false,
          },
        }),
      );

      final servicios = Servicios(
        sesion: sesion,
        cliente: ClienteApi(
          sesion: sesion,
          urlBase: 'http://falso',
          cliente: MockClient(
            (_) async => http.Response(
              jsonEncode({'mensaje': 'Tu sesión expiró.'}),
              403,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        Dependencias(
          servicios: servicios,
          child: MaterialApp(
            theme: TemaApp.claro,
            home: const PantallaMuroAlertas(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sesion.autenticado, isFalse);
      expect(find.byType(TarjetaAlerta), findsNothing);
    });
  });

  group('Búsqueda', () {
    Future<void> montarConTres(WidgetTester tester) async {
      await tester.pumpWidget(
        _montarPantalla(
          _servidorFalso(
            codigoAlertas: 200,
            cuerpoAlertas: _cuerpoConAlertas([
              _alertaJson(id: 1, tipo: 'Robo', vecino: 'Jorge'),
              _alertaJson(id: 2, tipo: 'Incendio', vecino: 'María'),
              _alertaJson(id: 3, tipo: 'Sospechoso', vecino: 'Luis'),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('filtra por tipo de alerta', (tester) async {
      await montarConTres(tester);
      await tester.enterText(find.byType(TextField), 'incendio');
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Incendio'), findsOneWidget);
    });

    testWidgets('filtra por nombre del vecino', (tester) async {
      await montarConTres(tester);
      await tester.enterText(find.byType(TextField), 'luis');
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Sospechoso'), findsOneWidget);
    });

    testWidgets(
      'el vacío por filtro se distingue del vacío por falta de datos',
      (tester) async {
        await montarConTres(tester);
        await tester.enterText(find.byType(TextField), 'zzzz');
        await tester.pumpAndSettle();

        // Mensaje específico del filtro, no el genérico "Todo tranquilo".
        expect(find.text('Sin resultados para "zzzz"'), findsOneWidget);
        expect(find.text('Todo tranquilo por aquí'), findsNothing);
        expect(find.text('Limpiar búsqueda'), findsWidgets);
      },
    );

    testWidgets('limpiar la búsqueda restaura la lista', (tester) async {
      await montarConTres(tester);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Limpiar búsqueda'));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsNWidgets(3));
    });
  });
}
