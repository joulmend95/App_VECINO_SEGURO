import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/theme/tema_app.dart';
import 'package:app_vecino_seguro/theme/tokens_semanticos.dart';
import 'package:app_vecino_seguro/widgets/boton_accion.dart';
import 'package:app_vecino_seguro/widgets/campo_texto.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';
import 'package:app_vecino_seguro/widgets/vista_estado.dart';

/// Envuelve un widget en el tema real de la aplicación.
Widget _montar(Widget hijo, {bool oscuro = false, double escalaTexto = 1.0}) {
  return MaterialApp(
    theme: TemaApp.claro,
    darkTheme: TemaApp.oscuro,
    themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
      child: Scaffold(body: hijo),
    ),
  );
}

void main() {
  group('Tokens', () {
    testWidgets('el tema expone TokensApp vía context.tokens', (tester) async {
      late TokensApp capturados;
      await tester.pumpWidget(
        _montar(
          Builder(
            builder: (context) {
              capturados = context.tokens;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(capturados.espacio.interiorCard, 16.0);
      expect(capturados.radio.control, 12.0);
      expect(capturados.tamano.areaTactilMinima, 48.0);
    });
  });

  group('BotonAccion', () {
    testWidgets('respeta el área táctil mínima de 48 dp', (tester) async {
      await tester.pumpWidget(
        _montar(BotonAccion(texto: 'Emitir', onPressed: () {})),
      );
      final alto = tester.getSize(find.byType(ElevatedButton)).height;
      expect(alto, greaterThanOrEqualTo(48.0));
    });

    testWidgets('sigue cumpliendo 48 dp con la fuente al 200%', (tester) async {
      await tester.pumpWidget(
        _montar(
          BotonAccion(texto: 'Emitir', onPressed: () {}),
          escalaTexto: 2.0,
        ),
      );
      final alto = tester.getSize(find.byType(ElevatedButton)).height;
      expect(alto, greaterThanOrEqualTo(48.0));
    });

    testWidgets('cargando bloquea la pulsación', (tester) async {
      var pulsaciones = 0;
      await tester.pumpWidget(
        _montar(
          BotonAccion(
            texto: 'Emitir',
            cargando: true,
            onPressed: () => pulsaciones++,
          ),
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(pulsaciones, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('onPressed null lo deja deshabilitado', (tester) async {
      await tester.pumpWidget(
        _montar(const BotonAccion(texto: 'Emitir', onPressed: null)),
      );
      final boton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(boton.onPressed, isNull);
    });

    testWidgets('la variante peligro se renderiza sin fallos', (tester) async {
      await tester.pumpWidget(
        _montar(
          BotonAccion(
            texto: 'Emitir alerta',
            variante: VarianteBoton.peligro,
            icono: Icons.warning_amber_rounded,
            onPressed: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('CampoTexto', () {
    testWidgets('muestra el texto de error cuando se provee', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        _montar(
          CampoTexto(
            controlador: ctrl,
            etiqueta: 'Teléfono',
            textoError: 'El teléfono es obligatorio',
          ),
        ),
      );
      expect(find.text('El teléfono es obligatorio'), findsOneWidget);
    });

    testWidgets('notifica los cambios de texto', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      String? ultimo;
      await tester.pumpWidget(
        _montar(
          CampoTexto(
            controlador: ctrl,
            etiqueta: 'Buscar',
            onCambio: (v) => ultimo = v,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'robo');
      expect(ultimo, 'robo');
    });
  });

  group('TarjetaAlerta', () {
    testWidgets('expone una etiqueta semántica compuesta', (tester) async {
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Robo',
            nombreVecino: 'Jorge',
            fechaHora: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Alerta crítica. Robo. Categoría Robo. Reportada por Jorge, Hace 5 minutos',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin onTap no se anuncia como botón', (tester) async {
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Robo',
            nombreVecino: 'Jorge',
            fechaHora: DateTime.now(),
          ),
        ),
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('con onTap responde a la pulsación', (tester) async {
      var toques = 0;
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Robo',
            nombreVecino: 'Jorge',
            fechaHora: DateTime.now(),
            onTap: () => toques++,
          ),
        ),
      );
      await tester.tap(find.byType(InkWell));
      expect(toques, 1);
    });
  });

  group('VistaEstado — los tres estados obligatorios', () {
    Widget vista(EstadoVista<List<String>> estado, {VoidCallback? reintentar}) {
      return _montar(
        VistaEstado<List<String>>(
          estado: estado,
          mensajeVacio: 'Sin alertas activas',
          detalleVacio: 'Tu comunidad está tranquila.',
          onReintentar: reintentar,
          constructorContenido: (_, datos) =>
              Column(children: datos.map(Text.new).toList()),
        ),
      );
    }

    testWidgets('CARGANDO muestra progreso y etiqueta semántica', (
      tester,
    ) async {
      await tester.pumpWidget(vista(const VistaCargando()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando información'), findsOneWidget);
    });

    testWidgets('VACÍO muestra mensaje y detalle', (tester) async {
      await tester.pumpWidget(vista(const VistaVacia()));
      expect(find.text('Sin alertas activas'), findsOneWidget);
      expect(find.text('Tu comunidad está tranquila.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('ERROR muestra el mensaje y ofrece reintentar', (tester) async {
      var reintentos = 0;
      await tester.pumpWidget(
        vista(
          const VistaError('Sin conexión con el servidor'),
          reintentar: () => reintentos++,
        ),
      );
      expect(find.text('Sin conexión con el servidor'), findsOneWidget);
      expect(find.text('No pudimos cargar la información'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(reintentos, 1);
    });

    testWidgets('ERROR sin onReintentar no muestra el botón', (tester) async {
      await tester.pumpWidget(vista(const VistaError('Falló')));
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('CON DATOS delega en constructorContenido', (tester) async {
      await tester.pumpWidget(
        vista(const VistaConDatos<List<String>>(['Robo', 'Incendio'])),
      );
      expect(find.text('Robo'), findsOneWidget);
      expect(find.text('Incendio'), findsOneWidget);
    });
  });

  group('Tema oscuro', () {
    testWidgets('los componentes se renderizan en oscuro sin fallos', (
      tester,
    ) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        _montar(
          oscuro: true,
          ListView(
            children: [
              BotonAccion(texto: 'Emitir', onPressed: () {}),
              CampoTexto(controlador: ctrl, etiqueta: 'Buscar'),
              TarjetaAlerta(
                tipoAlerta: 'Robo',
                nombreVecino: 'Jorge',
                fechaHora: DateTime.now(),

              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
