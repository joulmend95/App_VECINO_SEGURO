import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/theme/tema_app.dart';
import 'package:app_vecino_seguro/widgets/categoria_alerta.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

Widget _montar(Widget hijo, {bool oscuro = false, double escala = 1.0}) {
  return MaterialApp(
    theme: TemaApp.claro,
    darkTheme: TemaApp.oscuro,
    themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(escala)),
      child: Scaffold(body: hijo),
    ),
  );
}

void main() {
  group('CategoriaAlerta.desdeTexto — clasificación', () {
    const casos = <String, CategoriaAlerta>{
      'Robo en la vía pública': CategoriaAlerta.robo,
      'ROBO': CategoriaAlerta.robo,
      'Hurto de celular': CategoriaAlerta.robo,
      'Asalto a mano armada': CategoriaAlerta.robo,
      'Incendio en el patio': CategoriaAlerta.incendio,
      'Fuego en el garaje': CategoriaAlerta.incendio,
      'Emergencia médica': CategoriaAlerta.emergenciaMedica,
      'Persona herida': CategoriaAlerta.emergenciaMedica,
      'Pelea entre vecinos': CategoriaAlerta.violencia,
      'Persona sospechosa': CategoriaAlerta.sospechoso,
      'Sujeto merodeando': CategoriaAlerta.sospechoso,
      'Vehículo abandonado': CategoriaAlerta.vehiculo,
      'Moto sin placa': CategoriaAlerta.vehiculo,
      'Corte de luz': CategoriaAlerta.serviciosBasicos,
      'Fuga de agua': CategoriaAlerta.serviciosBasicos,
      'Perro suelto': CategoriaAlerta.mascota,
      'Ruido excesivo': CategoriaAlerta.ruido,
      'Fiesta hasta tarde': CategoriaAlerta.ruido,
    };

    casos.forEach((texto, esperada) {
      test('"$texto" → ${esperada.name}', () {
        expect(CategoriaAlerta.desdeTexto(texto), esperada);
      });
    });

    test('un texto no reconocido cae en "otro", no lanza error', () {
      expect(CategoriaAlerta.desdeTexto('xyz123'), CategoriaAlerta.otro);
      expect(CategoriaAlerta.desdeTexto(''), CategoriaAlerta.otro);
    });

    test('las categorías críticas tienen prioridad sobre las leves', () {
      // "accidente" es crítica y "ruido" informativa: gana la lectura urgente.
      expect(
        CategoriaAlerta.desdeTexto('accidente con ruido').urgencia,
        NivelUrgencia.critica,
      );
    });
  });

  group('Urgencia asignada por categoría', () {
    test('las emergencias reales son críticas', () {
      for (final c in [
        CategoriaAlerta.robo,
        CategoriaAlerta.incendio,
        CategoriaAlerta.emergenciaMedica,
        CategoriaAlerta.violencia,
      ]) {
        expect(c.urgencia, NivelUrgencia.critica, reason: c.name);
      }
    });

    test('los asuntos de convivencia son informativos', () {
      expect(CategoriaAlerta.ruido.urgencia, NivelUrgencia.informativa);
      expect(CategoriaAlerta.mascota.urgencia, NivelUrgencia.informativa);
    });
  });

  group('Cada categoría es visualmente distinguible', () {
    test('todas las categorías usan un icono distinto', () {
      final iconos = CategoriaAlerta.values.map((c) => c.icono).toSet();
      expect(
        iconos.length,
        CategoriaAlerta.values.length,
        reason: 'dos categorías comparten icono: no serían distinguibles',
      );
    });

    test('cada categoría declara un nombre legible no vacío', () {
      for (final c in CategoriaAlerta.values) {
        expect(c.nombre.trim(), isNotEmpty, reason: c.name);
      }
    });
  });

  group('TarjetaAlerta — identificación por tipo', () {
    testWidgets('muestra el distintivo textual de urgencia', (tester) async {
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Incendio en el patio',
            nombreVecino: 'Luis',
            fechaHora: DateTime.now(),
          ),
        ),
      );
      // La urgencia NO depende solo del color: se escribe (WCAG 1.4.1).
      expect(find.text('Crítica'), findsOneWidget);
    });

    testWidgets('dos alertas de distinto tipo muestran iconos distintos', (
      tester,
    ) async {
      await tester.pumpWidget(
        _montar(
          Column(
            children: [
              TarjetaAlerta(
                tipoAlerta: 'Incendio',
                nombreVecino: 'Luis',
                fechaHora: DateTime.now(),
              ),
              TarjetaAlerta(
                tipoAlerta: 'Ruido excesivo',
                nombreVecino: 'Ana',
                fechaHora: DateTime.now(),
              ),
            ],
          ),
        ),
      );

      expect(
        find.byIcon(CategoriaAlerta.incendio.icono),
        findsOneWidget,
      );
      expect(find.byIcon(CategoriaAlerta.ruido.icono), findsOneWidget);
      expect(find.text('Crítica'), findsOneWidget);
      expect(find.text('Informativa'), findsOneWidget);
    });

    testWidgets('la etiqueta semántica incluye urgencia y categoría', (
      tester,
    ) async {
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Robo en la vía pública',
            nombreVecino: 'Jorge',
            fechaHora: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Alerta crítica. Robo en la vía pública. Categoría Robo. '
          'Reportada por Jorge, Hace 5 minutos',
        ),
        findsOneWidget,
      );
    });

    testWidgets('la categoría explícita anula la deducida del texto', (
      tester,
    ) async {
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Texto que no coincide con nada',
            nombreVecino: 'Ana',
            fechaHora: DateTime.now(),
            categoria: CategoriaAlerta.incendio,
          ),
        ),
      );
      expect(find.byIcon(CategoriaAlerta.incendio.icono), findsOneWidget);
      expect(find.text('Crítica'), findsOneWidget);
    });

    testWidgets('mostrarUrgencia: false oculta el distintivo', (tester) async {
      await tester.pumpWidget(
        _montar(
          TarjetaAlerta(
            tipoAlerta: 'Incendio',
            nombreVecino: 'Luis',
            fechaHora: DateTime.now(),
            mostrarUrgencia: false,
          ),
        ),
      );
      expect(find.text('Crítica'), findsNothing);
    });

    testWidgets('todas las categorías se renderizan sin fallos en oscuro', (
      tester,
    ) async {
      await tester.pumpWidget(
        _montar(
          oscuro: true,
          ListView(
            children: CategoriaAlerta.values
                .map(
                  (c) => TarjetaAlerta(
                    tipoAlerta: c.nombre,
                    nombreVecino: 'Vecino',
                    fechaHora: DateTime.now(),
                    categoria: c,
                  ),
                )
                .toList(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('el distintivo baja de línea con la fuente al 200%', (
      tester,
    ) async {
      await tester.pumpWidget(
        _montar(
          escala: 2.0,
          SizedBox(
            width: 320,
            child: TarjetaAlerta(
              tipoAlerta: 'Robo en la vía pública',
              nombreVecino: 'Jorge Mendoza',
              fechaHora: DateTime.now(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Contraste de las urgencias', () {
    testWidgets('los 4 niveles cumplen contraste en claro y oscuro', (
      tester,
    ) async {
      for (final oscuro in [false, true]) {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _montar(
            oscuro: oscuro,
            ListView(
              children: NivelUrgencia.values
                  .map(
                    (u) => TarjetaAlerta(
                      tipoAlerta: 'Alerta ${u.etiqueta}',
                      nombreVecino: 'Vecino',
                      fechaHora: DateTime.now(),
                      categoria: CategoriaAlerta.values.firstWhere(
                        (c) => c.urgencia == u,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      }
    });
  });
}
