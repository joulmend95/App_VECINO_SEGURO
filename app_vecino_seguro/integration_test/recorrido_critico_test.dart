import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app_vecino_seguro/main.dart' as app;

/// Prueba de extremo a extremo — recorrido crítico
///
/// Verifica que el camino principal de la app no crashea:
/// ingreso (si no hay sesión) → muro de alertas → emisión de alerta.
///
/// ## Requisitos para ejecutar
///
/// - Dispositivo físico conectado
/// - Backend activo: `URL_BASE=http://localhost:3333`
/// - `adb reverse tcp:3333 tcp:3333` ejecutado ANTES de lanzar el test
/// - Credencial de prueba con membresía activa:
///   - Teléfono: `0991257105`  Contraseña: `12345678`
///
/// ## Cómo ejecutar
///
/// ```bash
/// adb reverse tcp:3333 tcp:3333
/// flutter test integration_test/ -d <device-id> ^
///   --dart-define=URL_BASE=http://localhost:3333
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Recorrido crítico — ingreso y emisión de alerta', () {
    testWidgets(
      'el vecino inicia sesión, ve el muro y emite una alerta',
      (tester) async {
        app.main();
        await tester.pump();

        // ── Esperar a la pantalla correcta mediante polling ───────────────────
        //
        // Estado inicial: FaseSesion.iniciando (splash) → login si no hay sesión.
        // El polling muestrea cada 300 ms hasta encontrar el muro o agotar
        // 100 iteraciones (30 s). Si ve la pantalla de ingreso, rellena
        // las credenciales y toca el botón.
        //
        // 30 s > receiveTimeout (15 s) del cliente Dio: cubre el caso en que
        // el backend tarda en responder y la navegación post-login (carga de
        // comunidad + alertas) demora varios segundos adicionales.

        bool loginRealizado = false;
        bool botonTocado = false;

        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 300));

          // ¿Ya llegamos al muro?
          if (find
              .bySemanticsLabel(
                'Emitir alerta de emergencia a toda la comunidad',
              )
              .evaluate()
              .isNotEmpty) {
            debugPrint('[E2E] Muro encontrado en iteración $i');
            break;
          }

          // ¿Apareció la pantalla de ingreso y todavía no ingresamos?
          if (!loginRealizado) {
            final campos = find.byType(TextField);
            if (campos.evaluate().length >= 2) {
              loginRealizado = true;
              debugPrint('[E2E] Campos de login encontrados en iteración $i');

              // Primer TextField = teléfono
              await tester.tap(campos.first, warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 150));
              await tester.enterText(campos.first, '0991257105');
              await tester.pump(const Duration(milliseconds: 150));

              // Segundo TextField = contraseña
              await tester.tap(campos.last, warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 150));
              await tester.enterText(campos.last, '12345678');
              await tester.pump(const Duration(milliseconds: 150));
            }
          }

          // ¿Tenemos los campos rellenos y el botón disponible?
          if (loginRealizado && !botonTocado) {
            final botonIngresar =
                find.widgetWithText(ElevatedButton, 'Ingresar');
            if (botonIngresar.evaluate().isNotEmpty) {
              // Verificar que el botón no esté en estado cargando (disabled)
              final elevatedButton =
                  botonIngresar.evaluate().first.widget as ElevatedButton;
              if (elevatedButton.onPressed != null) {
                botonTocado = true;
                debugPrint('[E2E] Tocando botón Ingresar en iteración $i');
                await tester.tap(botonIngresar, warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 200));
              }
            }
          }
        }

        // ── Diagnóstico si el muro no apareció ───────────────────────────────
        final botonEmitir = find.bySemanticsLabel(
          'Emitir alerta de emergencia a toda la comunidad',
        );

        if (botonEmitir.evaluate().isEmpty) {
          final textos = find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .where((t) => t != null && t.isNotEmpty)
              .take(15)
              .toList();
          debugPrint('[E2E-DIAG] loginRealizado=$loginRealizado  botonTocado=$botonTocado');
          debugPrint('[E2E-DIAG] Scaffolds: ${find.byType(Scaffold).evaluate().length}');
          debugPrint('[E2E-DIAG] Textos: $textos');
          debugPrint('[E2E-DIAG] TextFields visibles: ${find.byType(TextField).evaluate().length}');
        }

        // ── Muro de alertas ───────────────────────────────────────────────────
        expect(
          botonEmitir,
          findsOneWidget,
          reason:
              'El muro no apareció tras 30 s. '
              'Verifica: (1) backend activo en localhost:3333, '
              '(2) adb reverse tcp:3333 tcp:3333 fue ejecutado, '
              '(3) usuario 0991257105 tiene membresía ACTIVA.',
        );

        await tester.tap(botonEmitir, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        // ── Pantalla de emisión — seleccionar primera categoría ───────────────
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 300));
          final categorias = find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(InkWell),
          );
          if (categorias.evaluate().isNotEmpty) {
            await tester.tap(categorias.first, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));
            break;
          }
        }

        // ── Confirmar emisión ─────────────────────────────────────────────────
        final botonEmitirAlerta = find.bySemanticsLabel(
          RegExp(r'Emitir alerta de.*comunidad', caseSensitive: false),
        );
        if (botonEmitirAlerta.evaluate().isNotEmpty) {
          await tester.tap(botonEmitirAlerta.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));

          final botonConfirmar = find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data?.toLowerCase().contains('confirmar') == true ||
                    w.data?.toLowerCase().contains('emitir') == true),
          );
          if (botonConfirmar.evaluate().isNotEmpty) {
            await tester.tap(botonConfirmar.first, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
          }
        }

        // ── Verificación final ────────────────────────────────────────────────
        // La app no crasheó y sigue mostrando al menos un Scaffold.
        expect(
          find.byType(Scaffold),
          findsAtLeastNWidgets(1),
          reason: 'La app debe seguir activa después de emitir la alerta',
        );
      },
    );
  });
}
