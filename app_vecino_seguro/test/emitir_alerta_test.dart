import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/screens/pantalla_emitir_alerta.dart';
import 'package:app_vecino_seguro/widgets/categoria_alerta.dart';
import 'package:app_vecino_seguro/widgets/dialogo_confirmacion.dart';
import 'package:app_vecino_seguro/widgets/selector_categoria.dart';

import 'ayudas_prueba.dart';

/// ============================================================================
/// FASE 3 — Emitir alerta
/// ============================================================================

/// Servidor que registra el cuerpo de la emisión, para inspeccionarlo.
MockClient servidorEmision({
  int codigo = 202,
  String? mensajeError,
  void Function(Map<String, dynamic>)? alEmitir,
}) {
  return MockClient((peticion) async {
    if (!peticion.url.path.contains('/api/alertas/emitir')) {
      return http.Response('{}', 404);
    }

    final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
    alEmitir?.call(cuerpo);

    if (codigo >= 400) {
      return falla(codigo, mensajeError ?? 'error');
    }

    return http.Response(
      jsonEncode({
        'mensaje': 'ok',
        'alerta': alertaJson(tipo: cuerpo['tipo_alerta'] as String? ?? 'Alerta'),
      }),
      202,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

Future<void> montarP5(WidgetTester tester, MockClient cliente) async {
  final sesion = await sesionActiva();
  await tester.pumpWidget(
    montarConDependencias(
      hijo: const PantallaEmitirAlerta(),
      sesion: sesion,
      cliente: cliente,
    ),
  );
  await tester.pumpAndSettle();
}

/// Toca una categoría del selector por su nombre.
Future<void> elegirCategoria(WidgetTester tester, CategoriaAlerta c) async {
  await tester.ensureVisible(find.text(c.nombre).first);
  await tester.tap(find.text(c.nombre).first);
  await tester.pumpAndSettle();
}

void main() {
  // ==========================================================================
  // SELECTOR DE CATEGORÍA
  // ==========================================================================
  group('SelectorCategoria', () {
    testWidgets('se genera desde CategoriaAlerta.values', (tester) async {
      await tester.pumpWidget(
        montarConDependencias(
          hijo: Scaffold(
            body: SingleChildScrollView(
              child: SelectorCategoria(
                seleccionada: null,
                onSeleccionar: (_) {},
              ),
            ),
          ),
          sesion: await sesionActiva(),
          cliente: servidorFalso({}),
        ),
      );
      await tester.pumpAndSettle();

      // Una opción por categoría: emisión y muro comparten la misma fuente de
      // verdad, así que no pueden divergir.
      for (final c in CategoriaAlerta.values) {
        expect(find.text(c.nombre), findsOneWidget, reason: c.name);
      }
    });

    testWidgets('la selección se anuncia al lector, no solo por color', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        montarConDependencias(
          hijo: Scaffold(
            body: SingleChildScrollView(
              child: SelectorCategoria(
                seleccionada: CategoriaAlerta.incendio,
                onSeleccionar: (_) {},
              ),
            ),
          ),
          sesion: await sesionActiva(),
          cliente: servidorFalso({}),
        ),
      );
      await tester.pumpAndSettle();

      // La opción elegida se anuncia como "seleccionada": quien no percibe el
      // color recibe la misma información (WCAG 1.4.1).
      expect(
        find.bySemanticsLabel(
          RegExp('${CategoriaAlerta.incendio.nombre}. Urgencia crítica'),
        ),
        findsOneWidget,
      );
      final nodo = tester.getSemantics(
        find.bySemanticsLabel(
          RegExp('${CategoriaAlerta.incendio.nombre}. Urgencia crítica'),
        ),
      );
      expect(nodo.flagsCollection.isSelected.toString(), contains('isTrue'));
      handle.dispose();
    });

    testWidgets('cada opción cumple el área táctil mínima', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        montarConDependencias(
          hijo: Scaffold(
            body: SingleChildScrollView(
              child: SelectorCategoria(
                seleccionada: null,
                onSeleccionar: (_) {},
              ),
            ),
          ),
          sesion: await sesionActiva(),
          cliente: servidorFalso({}),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('se reordena a una columna en 320 dp con fuente al 200%', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        montarConDependencias(
          hijo: Scaffold(
            body: SingleChildScrollView(
              child: SelectorCategoria(
                seleccionada: null,
                onSeleccionar: (_) {},
              ),
            ),
          ),
          sesion: await sesionActiva(),
          cliente: servidorFalso({}),
          tamano: const Size(320, 640),
          escalaTexto: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // CONFIRMACIÓN OBLIGATORIA
  // ==========================================================================
  group('P5 — confirmación obligatoria', () {
    testWidgets('sin categoría elegida no llama al servidor', (tester) async {
      var emisiones = 0;
      await montarP5(tester, servidorEmision(alEmitir: (_) => emisiones++));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();

      expect(emisiones, 0);
      expect(find.text('Elige primero el tipo de alerta.'), findsOneWidget);
    });

    testWidgets('elegir categoría NO emite: primero pide confirmar', (
      tester,
    ) async {
      var emisiones = 0;
      await montarP5(tester, servidorEmision(alEmitir: (_) => emisiones++));

      await elegirCategoria(tester, CategoriaAlerta.incendio);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();

      // Aparece el diálogo, pero todavía no se ha enviado nada.
      expect(find.byType(DialogoConfirmacion), findsOneWidget);
      expect(find.text('¿Emitir esta alerta?'), findsOneWidget);
      expect(emisiones, 0);
    });

    testWidgets('cancelar la confirmación NO emite', (tester) async {
      var emisiones = 0;
      await montarP5(tester, servidorEmision(alEmitir: (_) => emisiones++));

      await elegirCategoria(tester, CategoriaAlerta.robo);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(emisiones, 0);
      expect(find.byType(DialogoConfirmacion), findsNothing);
    });

    testWidgets('el diálogo advierte que es irreversible y su alcance', (
      tester,
    ) async {
      await montarP5(tester, servidorEmision());

      await elegirCategoria(tester, CategoriaAlerta.robo);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no se puede deshacer'), findsOneWidget);
      expect(
        find.textContaining('Urbanización El Bosque'),
        findsWidgets,
        reason: 'debe decir a qué comunidad alcanza',
      );
    });

    testWidgets('confirmar emite con la categoría elegida', (tester) async {
      Map<String, dynamic>? enviado;
      await montarP5(tester, servidorEmision(alEmitir: (c) => enviado = c));

      await elegirCategoria(tester, CategoriaAlerta.incendio);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
      await tester.pumpAndSettle();

      expect(enviado, isNotNull);
      expect(enviado!['tipo_alerta'], CategoriaAlerta.incendio.nombre);
      // No es pánico: el vecino sí eligió el tipo.
      expect(enviado!.containsKey('es_panico'), isFalse);
    });

    testWidgets('la descripción opcional se envía cuando se escribe', (
      tester,
    ) async {
      Map<String, dynamic>? enviado;
      await montarP5(tester, servidorEmision(alEmitir: (c) => enviado = c));

      await elegirCategoria(tester, CategoriaAlerta.sospechoso);
      await tester.enterText(
        find.byType(TextField),
        'Frente a la casa 12, camiseta roja',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
      await tester.pumpAndSettle();

      expect(enviado!['descripcion'], 'Frente a la casa 12, camiseta roja');
    });

    testWidgets('una descripción vacía no se envía', (tester) async {
      Map<String, dynamic>? enviado;
      await montarP5(tester, servidorEmision(alEmitir: (c) => enviado = c));

      await elegirCategoria(tester, CategoriaAlerta.ruido);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
      await tester.pumpAndSettle();

      expect(enviado!.containsKey('descripcion'), isFalse);
    });
  });

  // ==========================================================================
  // ERRORES
  // ==========================================================================
  group('P5 — errores', () {
    testWidgets('el límite de frecuencia (429) se muestra al vecino', (
      tester,
    ) async {
      await montarP5(
        tester,
        servidorEmision(
          codigo: 429,
          mensajeError: 'Espera 42 segundos antes de emitir otra alerta.',
        ),
      );

      await elegirCategoria(tester, CategoriaAlerta.robo);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
      await tester.pumpAndSettle();

      expect(
        find.text('Espera 42 segundos antes de emitir otra alerta.'),
        findsOneWidget,
      );
    });

    testWidgets('un fallo del servidor no deja el botón girando', (
      tester,
    ) async {
      await montarP5(tester, servidorEmision(codigo: 500));

      await elegirCategoria(tester, CategoriaAlerta.robo);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('El servidor tuvo un problema. Inténtalo en unos momentos.'),
        findsOneWidget,
      );
    });
  });

  // ==========================================================================
  // ACCESIBILIDAD
  // ==========================================================================
  group('P5 — accesibilidad', () {
    testWidgets('contraste y área táctil de la pantalla completa', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montarP5(tester, servidorEmision());

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('el botón anuncia el tipo elegido', (tester) async {
      final handle = tester.ensureSemantics();
      await montarP5(tester, servidorEmision());

      expect(
        find.bySemanticsLabel('Emitir alerta. Elige primero el tipo.'),
        findsOneWidget,
      );

      await elegirCategoria(tester, CategoriaAlerta.incendio);

      expect(
        find.bySemanticsLabel(
          'Emitir alerta de ${CategoriaAlerta.incendio.nombre} a toda la comunidad',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
