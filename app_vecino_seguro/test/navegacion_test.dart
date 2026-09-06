import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/navegacion/rutas.dart';
import 'package:app_vecino_seguro/screens/pantalla_detalle_alerta.dart';
import 'package:app_vecino_seguro/screens/pantalla_emitir_alerta.dart';
import 'package:app_vecino_seguro/screens/pantalla_ingreso.dart';
import 'package:app_vecino_seguro/screens/pantalla_muro_alertas.dart';
import 'package:app_vecino_seguro/screens/pantalla_elegir_comunidad.dart';
import 'package:app_vecino_seguro/screens/pantalla_esperando_aprobacion.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

import 'ayudas_prueba.dart';

/// PASO 9 — VERIFICACIÓN DE NAVEGACIÓN
///
/// Se ejercita el enrutador **real** (`construirEnrutador`), no una imitación:
/// lo que se prueba son las guardias tal y como corren en producción.
void main() {
  // Servidor mínimo que basta para que el muro y el detalle carguen.
  final rutas = {
    'alertas/comunidad': (_) => ok(cuerpoAlertas([alertaJson()])),
    'usuarios/yo': (_) => ok(perfilJson()),
    'alertas/': (_) => ok(cuerpoAlerta(alertaJson(id: 42, tipo: 'Incendio'))),
  };

  group('Rutas.existe — validación de direcciones', () {
    test('reconoce las rutas fijas declaradas', () {
      expect(Rutas.existe(Rutas.alertas), isTrue);
      expect(Rutas.existe(Rutas.perfil), isTrue);
      expect(Rutas.existe(Rutas.emitirAlerta), isTrue);
    });

    test('reconoce el detalle con identificador numérico', () {
      expect(Rutas.existe('/alertas/1'), isTrue);
      expect(Rutas.existe('/alertas/999'), isTrue);
    });

    test('rechaza direcciones inventadas o malformadas', () {
      expect(Rutas.existe('/alertas/abc'), isFalse);
      expect(Rutas.existe('/no-existe'), isFalse);
      expect(Rutas.existe('/alertas/1/extra'), isFalse);
      // El caso que importa: si esto pasara por bueno, el destino guardado
      // podría enviar al vecino a una página de error de `go_router`.
      expect(Rutas.existe(''), isFalse);
    });

    test('aDetalleAlerta construye la dirección que existe()  acepta', () {
      final ruta = Rutas.aDetalleAlerta(42);
      expect(ruta, '/alertas/42');
      expect(Rutas.existe(ruta), isTrue);
    });
  });

  group('Rutas privadas y destino pretendido', () {
    testWidgets('sin sesión, una ruta privada rebota al ingreso', (tester) async {
      final sesion = sesionDePrueba();
      // La sesión arranca en `iniciando`; `cerrar` la resuelve a "sin sesión",
      // que es lo que hace la pantalla de arranque cuando no hay token.
      await sesion.cerrar();

      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.perfil);
      await tester.pumpAndSettle();

      expect(find.byType(PantallaIngreso), findsOneWidget);
    });

    testWidgets('el destino pretendido queda guardado en la dirección', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.cerrar(); // Pasa de `iniciando` a `sinSesion`.

      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.perfil);
      await tester.pumpAndSettle();

      final ubicacion = ubicacionActual(montaje.enrutador);
      expect(ubicacion, startsWith(Rutas.ingreso));
      expect(
        Uri.parse(ubicacion).queryParameters[Rutas.paramDestino],
        Rutas.perfil,
        reason: 'Sin esto, tras ingresar aterrizaría en el muro y tendría que '
            'volver a buscar a dónde iba.',
      );
    });

    testWidgets('tras ingresar se vuelve al destino guardado, no al muro', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.cerrar();

      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.perfil);
      await tester.pumpAndSettle();
      expect(find.byType(PantallaIngreso), findsOneWidget);

      // El ingreso abre la sesión; la guardia reacciona sola.
      await sesion.iniciar(
        token: 'jwt-de-prueba',
        perfil: perfilDePrueba(),
      );
      await tester.pumpAndSettle();

      expect(ubicacionActual(montaje.enrutador), Rutas.perfil);
    });

    testWidgets('un destino que su membresía no permite cae al muro, sin bucle', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.cerrar();

      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      // Guardó el muro estando activo...
      montaje.enrutador.go(Rutas.alertas);
      await tester.pumpAndSettle();

      // ...pero vuelve a ingresar cuando ya no pertenece a ninguna comunidad.
      await sesion.iniciar(
        token: 'jwt-de-prueba',
        perfil: perfilDePrueba(estado: 'SIN_COMUNIDAD'),
      );
      await tester.pumpAndSettle();

      // Si `_esAlcanzable` no comprobara la membresía, la guardia devolvería
      // `/alertas`, el estado sinComunidad lo rebotaría a `/comunidad/elegir`,
      // y de ahí volvería a intentar el destino guardado: bucle infinito.
      expect(find.byType(PantallaElegirComunidad), findsOneWidget);
      expect(ubicacionActual(montaje.enrutador), Rutas.elegirComunidad);
    });

    testWidgets('un destino manipulado no se sigue', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.cerrar();

      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(
        '${Rutas.ingreso}?${Rutas.paramDestino}=${Uri.encodeComponent('/robar-datos')}',
      );
      await tester.pumpAndSettle();

      await sesion.iniciar(token: 'jwt-de-prueba', perfil: perfilDePrueba());
      await tester.pumpAndSettle();

      expect(ubicacionActual(montaje.enrutador), Rutas.alertas);
    });

    testWidgets('un vecino pendiente de aprobación no llega al muro', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt-de-prueba',
        perfil: perfilDePrueba(estado: 'PENDIENTE'),
      );

      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.alertas);
      await tester.pumpAndSettle();

      expect(find.byType(PantallaEsperandoAprobacion), findsOneWidget);
    });
  });

  group('Ruta anidada y parámetro de ruta', () {
    testWidgets('/alertas/emitir abre emitir, no el detalle', (tester) async {
      final sesion = await sesionActiva();
      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.emitirAlerta);
      await tester.pumpAndSettle();

      // Si `:idAlerta` estuviera declarado antes que 'emitir', esta pantalla
      // sería el detalle con idAlerta = "emitir".
      expect(find.byType(PantallaEmitirAlerta), findsOneWidget);
      expect(find.byType(PantallaDetalleAlerta), findsNothing);
    });

    testWidgets('/alertas/42 se reconstruye en frío, sin pasar por el muro', (tester) async {
      final sesion = await sesionActiva();
      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      montaje.enrutador.go(Rutas.aDetalleAlerta(42));
      await tester.pumpAndSettle();

      final pantalla = tester.widget<PantallaDetalleAlerta>(
        find.byType(PantallaDetalleAlerta),
      );
      expect(pantalla.idAlerta, 42);
      // El dato lo pidió la propia pantalla: nadie se lo pasó.
      expect(find.text('Incendio'), findsWidgets);
    });

    testWidgets('el muro navega al detalle con el identificador', (tester) async {
      final sesion = await sesionActiva();
      final montaje = montarAppConEnrutador(
        sesion: sesion,
        cliente: servidorFalso(rutas),
      );
      await tester.pumpWidget(montaje.app);
      await tester.pumpAndSettle();

      expect(find.byType(PantallaMuroAlertas), findsOneWidget);

      await tester.tap(find.byType(TarjetaAlerta).first);
      await tester.pumpAndSettle();

      final pantalla = tester.widget<PantallaDetalleAlerta>(
        find.byType(PantallaDetalleAlerta),
      );
      expect(
        pantalla.idAlerta,
        1,
        reason: 'El muro pasa el identificador por la ruta, no el objeto.',
      );
    });
  });
}
