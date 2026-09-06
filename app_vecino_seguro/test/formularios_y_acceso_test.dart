import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/navegacion/rutas.dart';
import 'package:app_vecino_seguro/screens/pantalla_emitir_alerta.dart';
import 'package:app_vecino_seguro/screens/pantalla_muro_alertas.dart';
import 'package:app_vecino_seguro/screens/pantalla_registro.dart';
import 'package:app_vecino_seguro/screens/pantalla_sin_permiso.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/widgets/campo_texto.dart';

import 'ayudas_prueba.dart';

/// PASO 11 — FORMULARIOS, BORRADOR Y CONTROL DE ACCESO
void main() {
  // -------------------------------------------------------------------------
  // VALIDACIÓN AL ABANDONAR EL CAMPO
  // -------------------------------------------------------------------------
  group('Validación al perder el foco', () {
    Future<void> montarRegistro(WidgetTester tester) async {
      final sesion = sesionDePrueba();
      await sesion.cerrar();
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaRegistro(),
          sesion: sesion,
          cliente: servidorFalso({
            'usuarios/registro': (_) => ok({'token': 'x', 'perfil': perfilJson()}),
          }),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('un teléfono inválido se marca al salir del campo', (tester) async {
      await montarRegistro(tester);

      final telefono = find.widgetWithText(CampoTexto, 'Teléfono');
      await tester.enterText(telefono, '123');
      await tester.pumpAndSettle();

      // Mientras se escribe NO se marca: un teléfono a medio teclear siempre
      // es inválido, y pintarlo en rojo castiga al usuario por no haber
      // terminado.
      expect(find.textContaining('entre 7 y 15'), findsNothing);

      // Al pasar a otro campo, el usuario ya declaró haber terminado con este.
      await tester.tap(find.widgetWithText(CampoTexto, 'Nombre completo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('entre 7 y 15'), findsOneWidget);
    });

    testWidgets('corregir el valor y salir retira el error', (tester) async {
      await montarRegistro(tester);

      final telefono = find.widgetWithText(CampoTexto, 'Teléfono');
      final nombre = find.widgetWithText(CampoTexto, 'Nombre completo');

      await tester.enterText(telefono, '123');
      await tester.tap(nombre);
      await tester.pumpAndSettle();
      expect(find.textContaining('entre 7 y 15'), findsOneWidget);

      await tester.enterText(telefono, '0991234567');
      await tester.tap(nombre);
      await tester.pumpAndSettle();

      // El error desaparece sin esperar al envío: por eso `onValidar` se
      // notifica también cuando el valor es correcto.
      expect(find.textContaining('entre 7 y 15'), findsNothing);
    });

    testWidgets('un campo vacío que nunca se tocó no se marca', (tester) async {
      await montarRegistro(tester);

      // Solo se pasa el foco por encima: entrar y salir sin escribir nada.
      await tester.tap(find.widgetWithText(CampoTexto, 'Teléfono'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CampoTexto, 'Nombre completo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('es obligatorio'), findsNothing);
      expect(find.textContaining('entre 7 y 15'), findsNothing);
    });

    testWidgets('al enviar sí se validan todos los campos, incluso intactos', (tester) async {
      await montarRegistro(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();

      // La validación al enviar se conserva íntegra: el foco cubre el campo
      // que el usuario abandonó, el envío cubre el que nunca abrió.
      expect(find.textContaining('obligatorio'), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  // ERRORES 422 DEL SERVIDOR
  // -------------------------------------------------------------------------
  group('Un 422 se reparte por campo', () {
    Future<void> montarRegistroCon(
      WidgetTester tester,
      Map<String, String> erroresServidor,
    ) async {
      final sesion = sesionDePrueba();
      await sesion.cerrar();
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaRegistro(),
          sesion: sesion,
          cliente: servidorFalso({
            'usuarios/registro': (_) => fallaValidacion(erroresServidor),
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Nombre completo'),
        'Ana Vera',
      );
      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Teléfono'),
        '0991234567',
      );
      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Contraseña'),
        'clave12345',
      );
      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Repetir contraseña'),
        'clave12345',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();
    }

    testWidgets('el mensaje aparece en su campo, no en el bloque general', (tester) async {
      await montarRegistroCon(tester, {
        'telefono': 'Ese teléfono ya está registrado.',
      });

      expect(find.text('Ese teléfono ya está registrado.'), findsOneWidget);
      // El bloque general no repite lo que ya está señalado en el campo.
      expect(find.text('Revisa los datos ingresados.'), findsNothing);
    });

    testWidgets('varios campos rechazados se marcan todos', (tester) async {
      await montarRegistroCon(tester, {
        'nombre': 'El nombre es demasiado corto.',
        'telefono': 'Ese teléfono ya está registrado.',
      });

      expect(find.text('El nombre es demasiado corto.'), findsOneWidget);
      expect(find.text('Ese teléfono ya está registrado.'), findsOneWidget);
    });

    testWidgets('un campo que la pantalla no muestra no se pierde', (tester) async {
      await montarRegistroCon(tester, {'comunidad': 'Campo desconocido aquí.'});

      // Si solo se volcara en `_errores`, el mensaje se tragaría y el
      // formulario parecería no haber hecho nada al pulsar enviar.
      expect(find.text('Revisa los datos ingresados.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // BORRADOR QUE SOBREVIVE A LA NAVEGACIÓN
  // -------------------------------------------------------------------------
  group('El borrador de alerta sobrevive a la navegación', () {
    final rutasApi = {
      'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson()])),
      'alertas/emitir': (_) => ok({'alerta': alertaJson()}),
    };

    testWidgets('lo escrito sigue ahí al volver desde el muro', (tester) async {
      final montaje = montarAppConEnrutador(
        sesion: await sesionActiva(),
        cliente: servidorFalso(rutasApi),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Robo').first);
      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Detalle (opcional)'),
        'Sujeto de camiseta roja frente a la casa 12',
      );
      await tester.pumpAndSettle();

      // Sale a comprobar si algún vecino ya avisó...
      montaje.enrutador.go(Rutas.alertas);
      await tester.pumpAndSettle();
      expect(find.byType(PantallaMuroAlertas), findsOneWidget);
      expect(find.byType(PantallaEmitirAlerta), findsNothing);

      // ...y vuelve.
      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      expect(
        find.text('Sujeto de camiseta roja frente a la casa 12'),
        findsOneWidget,
        reason: 'Un TextEditingController muere con su widget. Por eso el '
            'borrador vive en Servicios y no en el State.',
      );
    });

    testWidgets('tras emitir con éxito el borrador queda limpio', (tester) async {
      final sesion = await sesionActiva();
      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutasApi),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Robo').first);
      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Detalle (opcional)'),
        'Texto que debe desaparecer',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, emitir alerta'));
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      expect(find.text('Texto que debe desaparecer'), findsNothing);
    });

    testWidgets('un fallo al emitir NO destruye el borrador', (tester) async {
      final montaje = montarAppConEnrutador(
        sesion: await sesionActiva(),
        cliente: servidorFalso({
          'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson()])),
          'alertas/emitir': (_) => falla(500, 'El servidor tuvo un problema.'),
        }),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Robo').first);
      await tester.enterText(
        find.widgetWithText(CampoTexto, 'Detalle (opcional)'),
        'Texto que debe conservarse',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, emitir alerta'));
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.alertas);
      await tester.pumpAndSettle();
      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      expect(
        find.text('Texto que debe conservarse'),
        findsOneWidget,
        reason: 'Perder el texto justo cuando hay que reintentar es el peor '
            'momento posible.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 401 vs 403
  // -------------------------------------------------------------------------
  group('401 y 403 no significan lo mismo', () {
    testWidgets('un 401 cierra la sesión', (tester) async {
      final sesion = await sesionActiva();
      final api = ClienteApi(
        sesion: sesion,
        cliente: servidorFalso({
          'alertas': (_) => falla(401, 'Se requiere iniciar sesión.'),
        }),
        urlBase: 'http://servidor-falso',
      );

      await expectLater(
        () => api.obtener('/api/alertas/comunidad'),
        throwsA(
          isA<ExcepcionApi>()
              .having((e) => e.codigo, 'codigo', ExcepcionApi.sesionRequerida)
              .having((e) => e.exigeIngresar, 'exigeIngresar', isTrue)
              .having((e) => e.esDeAcceso, 'esDeAcceso', isFalse),
        ),
      );
      expect(sesion.autenticado, isFalse);
    });

    testWidgets('un 403 sin código de negocio cierra la sesión', (tester) async {
      final sesion = await sesionActiva();
      final api = ClienteApi(
        sesion: sesion,
        cliente: servidorFalso({
          'alertas': (_) => falla(403, 'Tu sesión expiró. Vuelve a ingresar.'),
        }),
        urlBase: 'http://servidor-falso',
      );

      await expectLater(
        () => api.obtener('/api/alertas/comunidad'),
        throwsA(
          isA<ExcepcionApi>()
              .having((e) => e.codigo, 'codigo', ExcepcionApi.sesionExpirada),
        ),
      );
      expect(sesion.autenticado, isFalse);
    });

    testWidgets('un 403 NO_ES_ADMIN NO cierra la sesión', (tester) async {
      final sesion = await sesionActiva(esAdmin: true);
      final api = ClienteApi(
        sesion: sesion,
        cliente: servidorFalso({
          'solicitudes': (_) => fallaNegocio(
            403,
            ExcepcionApi.noEsAdmin,
            'Solo el administrador puede hacer esto.',
          ),
        }),
        urlBase: 'http://servidor-falso',
      );

      await expectLater(
        () => api.obtener('/api/comunidades/solicitudes'),
        throwsA(
          isA<ExcepcionApi>()
              .having((e) => e.codigo, 'codigo', ExcepcionApi.noEsAdmin)
              .having((e) => e.esDeAcceso, 'esDeAcceso', isTrue)
              .having((e) => e.exigeIngresar, 'exigeIngresar', isFalse),
        ),
      );
      expect(
        sesion.autenticado,
        isTrue,
        reason: 'Su credencial es válida; lo que cambió fue su rol. Cerrarle '
            'la sesión sería expulsarlo por error.',
      );
    });

    testWidgets('un 403 SIN_COMUNIDAD tampoco cierra la sesión', (tester) async {
      final sesion = await sesionActiva();
      final api = ClienteApi(
        sesion: sesion,
        cliente: servidorFalso({
          'alertas': (_) => fallaNegocio(
            403,
            ExcepcionApi.sinComunidad,
            'Todavía no perteneces a ninguna comunidad.',
          ),
        }),
        urlBase: 'http://servidor-falso',
      );

      await expectLater(
        () => api.obtener('/api/alertas/comunidad'),
        throwsA(isA<ExcepcionApi>()),
      );
      expect(sesion.autenticado, isTrue);
    });

    testWidgets('un 422 nunca cierra la sesión', (tester) async {
      final sesion = await sesionActiva();
      final api = ClienteApi(
        sesion: sesion,
        cliente: servidorFalso({
          'alertas': (_) => fallaValidacion({'tipo_alerta': 'Es obligatorio.'}),
        }),
        urlBase: 'http://servidor-falso',
      );

      await expectLater(
        () => api.publicar('/api/alertas/emitir'),
        throwsA(
          isA<ExcepcionApi>().having(
            (e) => e.erroresPorCampo,
            'erroresPorCampo',
            {'tipo_alerta': 'Es obligatorio.'},
          ),
        ),
      );
      expect(sesion.autenticado, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // PANTALLA DE PERMISO INSUFICIENTE
  // -------------------------------------------------------------------------
  group('PantallaSinPermiso', () {
    testWidgets('explica que la sesión sigue activa', (tester) async {
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaSinPermiso(),
          sesion: await sesionActiva(),
          cliente: servidorFalso({}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Tu sesión sigue activa'),
        findsOneWidget,
        reason: 'Es la diferencia visible entre un 403 de permisos y uno de '
            'credenciales.',
      );
    });

    testWidgets('cumple contraste y área táctil en claro y oscuro', (tester) async {
      for (final oscuro in [false, true]) {
        await tester.pumpWidget(
          montarConDependencias(
            hijo: const PantallaSinPermiso(),
            sesion: await sesionActiva(),
            cliente: servidorFalso({}),
            oscuro: oscuro,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
    });
  });
}
