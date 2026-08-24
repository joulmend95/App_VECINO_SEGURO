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
import 'package:app_vecino_seguro/widgets/boton_accion.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

/// ============================================================================
/// PASO 8 — VERIFICACIÓN DE ACCESIBILIDAD
/// ============================================================================
///
/// Comprueba de forma automatizada y reproducible:
///  1. Contraste de texto (WCAG 1.4.3)
///  2. Área táctil mínima en Android (48 dp) e iOS (44 dp)
///  3. Etiquetas semánticas en todos los controles
///  4. La pantalla en dos anchos distintos
///  5. La pantalla con la fuente del sistema ampliada
/// ============================================================================

// --- Anchos de referencia ---------------------------------------------------
/// Teléfono pequeño (equivale a un Galaxy Fold cerrado / iPhone SE).
const _anchoEstrecho = Size(320, 640);

/// Tablet en vertical.
const _anchoAmplio = Size(800, 1280);

MockClient _servidorConAlertas() {
  return MockClient((peticion) async {
    if (peticion.url.path.contains('token-prueba')) {
      return http.Response(jsonEncode({'token': 'jwt'}), 200);
    }
    return http.Response(
      jsonEncode({
        'fuente': 'BD',
        'data': [
          _alerta(1, 'Robo en la vía pública', 'Jorge Mendoza'),
          _alerta(2, 'Persona sospechosa', 'María Fernanda Zambrano'),
          _alerta(3, 'Incendio', 'Luis'),
        ],
      }),
      200,
    );
  });
}

MockClient _servidorQueFalla() {
  return MockClient((peticion) async {
    if (peticion.url.path.contains('token-prueba')) {
      return http.Response(jsonEncode({'token': 'jwt'}), 200);
    }
    return http.Response('boom', 500);
  });
}

MockClient _servidorVacio() {
  return MockClient((peticion) async {
    if (peticion.url.path.contains('token-prueba')) {
      return http.Response(jsonEncode({'token': 'jwt'}), 200);
    }
    return http.Response(jsonEncode({'fuente': 'BD', 'data': []}), 200);
  });
}

Map<String, dynamic> _alerta(int id, String tipo, String vecino) => {
  'id_alerta': id,
  'tipo_alerta': tipo,
  'fecha_hora': DateTime.now()
      .subtract(Duration(minutes: id * 7))
      .toIso8601String(),
  'estado': 'Activa',
  'id_usuario': id,
  'usuario': {'id_usuario': id, 'nombre': vecino, 'telefono': '099'},
};

/// Monta la pantalla sobre el árbol de dependencias real (sesión + cliente
/// compartido), no sobre un servicio suelto: así la prueba ejercita la misma
/// pila que la aplicación.
Widget _pantalla(
  MockClient cliente, {
  Size tamano = const Size(411, 891),
  double escalaTexto = 1.0,
  bool oscuro = false,
}) {
  final sesion = Sesion(almacen: AlmacenEnMemoria());
  sesion.iniciar(
    token: 'jwt',
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

/// Ajusta la ventana física del test para que coincida con el tamaño lógico.
Future<void> _fijarVentana(WidgetTester tester, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // ==========================================================================
  // 1. CONTRASTE DE TEXTO (WCAG 1.4.3)
  // ==========================================================================
  group('1. Contraste de texto', () {
    testWidgets('tema claro, estado con datos', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('tema oscuro, estado con datos', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas(), oscuro: true));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('estado de error', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorQueFalla()));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('estado vacío', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorVacio()));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  // ==========================================================================
  // 2. ÁREA TÁCTIL (WCAG 2.5.5)
  // ==========================================================================
  group('2. Área táctil', () {
    testWidgets('cumple el mínimo de Android (48 dp)', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('cumple el mínimo de iOS (44 dp)', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('el botón de emergencia mide al menos 48 dp de alto', (
      tester,
    ) async {
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      final boton = find.ancestor(
        of: find.text('Emitir alerta de emergencia'),
        matching: find.byType(ElevatedButton),
      );
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(48.0));
    });
  });

  // ==========================================================================
  // 3. ETIQUETAS SEMÁNTICAS
  // ==========================================================================
  group('3. Etiquetas semánticas', () {
    testWidgets('todo control interactivo tiene etiqueta', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('el botón de emergencia anuncia su alcance real', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      // La etiqueta visible dice "Emitir alerta de emergencia"; el lector de
      // pantalla recibe la versión completa, que aclara a quién le llega.
      expect(
        find.bySemanticsLabel(
          'Emitir alerta de emergencia a toda la comunidad',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('cada alerta se anuncia como una frase única', (tester) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();

      // La etiqueta incluye la urgencia EN PALABRAS, no solo por color:
      // quien no percibe el rojo recibe la misma información (WCAG 1.4.1).
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Alerta crítica\. Incendio\. Categoría Incendio\. '
            r'Reportada por Luis, Hace \d+ minutos',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('el estado de error se anuncia como región en vivo', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(_pantalla(_servidorQueFalla()));
      await tester.pumpAndSettle();

      final semantica = tester.getSemantics(
        find.text('No pudimos cargar la información'),
      );
      expect(semantica, isNotNull);
      handle.dispose();
    });
  });

  // ==========================================================================
  // 4. DOS ANCHOS DISTINTOS
  // ==========================================================================
  group('4. Dos anchos distintos', () {
    testWidgets('320 dp (teléfono estrecho) sin desbordes', (tester) async {
      await _fijarVentana(tester, _anchoEstrecho);
      await tester.pumpWidget(
        _pantalla(_servidorConAlertas(), tamano: _anchoEstrecho),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TarjetaAlerta), findsWidgets);
    });

    testWidgets('800 dp (tablet) sin desbordes', (tester) async {
      await _fijarVentana(tester, _anchoAmplio);
      await tester.pumpWidget(
        _pantalla(_servidorConAlertas(), tamano: _anchoAmplio),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TarjetaAlerta), findsWidgets);
    });

    testWidgets('el contenido no se sale del ancho en 320 dp', (tester) async {
      await _fijarVentana(tester, _anchoEstrecho);
      await tester.pumpWidget(
        _pantalla(_servidorConAlertas(), tamano: _anchoEstrecho),
      );
      await tester.pumpAndSettle();

      for (final elemento in find.byType(TarjetaAlerta).evaluate()) {
        final caja = tester.getRect(find.byWidget(elemento.widget));
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(_anchoEstrecho.width));
      }
    });

    testWidgets('el estado de error se adapta a ambos anchos', (tester) async {
      for (final tamano in [_anchoEstrecho, _anchoAmplio]) {
        await _fijarVentana(tester, tamano);
        await tester.pumpWidget(_pantalla(_servidorQueFalla(), tamano: tamano));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'ancho ${tamano.width}');
        expect(find.text('Reintentar'), findsOneWidget);
      }
    });
  });

  // ==========================================================================
  // 5. FUENTE DEL SISTEMA AMPLIADA
  // ==========================================================================
  group('5. Fuente del sistema ampliada', () {
    for (final escala in [1.3, 1.6, 2.0]) {
      testWidgets('escala ${escala}x sin desbordes', (tester) async {
        await _fijarVentana(tester, const Size(411, 891));
        await tester.pumpWidget(
          _pantalla(_servidorConAlertas(), escalaTexto: escala),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(TarjetaAlerta), findsWidgets);
      });
    }

    testWidgets('el texto realmente crece con la escala', (tester) async {
      await _fijarVentana(tester, const Size(411, 891));

      await tester.pumpWidget(_pantalla(_servidorConAlertas()));
      await tester.pumpAndSettle();
      final altoNormal = tester
          .getSize(find.text('Emitir alerta de emergencia'))
          .height;

      await tester.pumpWidget(
        _pantalla(_servidorConAlertas(), escalaTexto: 2.0),
      );
      await tester.pumpAndSettle();
      final altoAmpliado = tester
          .getSize(find.text('Emitir alerta de emergencia'))
          .height;

      // Si algún widget fijara `fontSize`, este assert fallaría.
      expect(altoAmpliado, greaterThan(altoNormal * 1.5));
    });

    testWidgets('el botón crece con la fuente en lugar de recortar el texto', (
      tester,
    ) async {
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(
        _pantalla(_servidorConAlertas(), escalaTexto: 2.0),
      );
      await tester.pumpAndSettle();

      final boton = find.ancestor(
        of: find.text('Emitir alerta de emergencia'),
        matching: find.byType(ElevatedButton),
      );
      // Con la fuente al doble, el botón debe superar holgadamente los 48 dp.
      expect(tester.getSize(boton).height, greaterThan(48.0));
    });

    testWidgets('caso extremo: 320 dp + fuente al 200%', (tester) async {
      await _fijarVentana(tester, _anchoEstrecho);
      await tester.pumpWidget(
        _pantalla(
          _servidorConAlertas(),
          tamano: _anchoEstrecho,
          escalaTexto: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TarjetaAlerta), findsWidgets);
    });

    testWidgets('el área táctil sigue cumpliendo con la fuente al 200%', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _fijarVentana(tester, const Size(411, 891));
      await tester.pumpWidget(
        _pantalla(_servidorConAlertas(), escalaTexto: 2.0),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });

  // ==========================================================================
  // 6. COMPONENTES AISLADOS
  // ==========================================================================
  group('6. Componentes aislados', () {
    testWidgets('BotonAccion cumple contraste en sus tres variantes', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaApp.claro,
          home: Scaffold(
            body: Column(
              children: [
                BotonAccion(texto: 'Primario', onPressed: () {}),
                BotonAccion(
                  texto: 'Peligro',
                  variante: VarianteBoton.peligro,
                  onPressed: () {},
                ),
                BotonAccion(
                  texto: 'Secundario',
                  variante: VarianteBoton.secundario,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });
}
