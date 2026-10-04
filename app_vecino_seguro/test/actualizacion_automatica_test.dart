import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/screens/pantalla_muro_alertas.dart';
import 'package:app_vecino_seguro/screens/pantalla_notificaciones.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/dependencias.dart';
import 'package:app_vecino_seguro/servicios/gestor_permisos.dart';
import 'package:app_vecino_seguro/servicios/servicio_ubicacion.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';
import 'package:app_vecino_seguro/theme/tema_app.dart';
import 'package:app_vecino_seguro/widgets/tarjeta_alerta.dart';

/// Pruebas de la actualización sin intervención del vecino.
///
/// El servidor falso es **mutable**: cada prueba cambia lo que responde a mitad
/// de camino —una alerta nueva, una notificación más— y comprueba que la
/// pantalla lo muestra sin que nadie toque "refrescar".
class _ServidorMutable {
  final alertas = <Map<String, dynamic>>[];
  final notificaciones = <Map<String, dynamic>>[];
  int peticionesMuro = 0;
  int peticionesBandeja = 0;
  bool caido = false;
  bool fallaBorrado = false;

  MockClient get cliente => MockClient((peticion) async {
    if (caido) return http.Response('{"mensaje":"caído"}', 500);
    if (peticion.method == 'DELETE' &&
        peticion.url.path.contains('/api/notificaciones')) {
      if (fallaBorrado) {
        return http.Response('{"mensaje":"No pudimos completar la operación."}', 500);
      }
      final id = int.tryParse(peticion.url.pathSegments.last);
      if (id == null) {
        final total = notificaciones.length;
        notificaciones.clear();
        return http.Response(jsonEncode({'eliminadas': total}), 200);
      }
      final antes = notificaciones.length;
      notificaciones.removeWhere((n) => n['id_notificacion'] == id);
      return notificaciones.length < antes
          ? http.Response('{"mensaje":"Notificación eliminada."}', 200)
          : http.Response('{"mensaje":"No existe."}', 404);
    }
    if (peticion.url.path.endsWith('/api/alertas/comunidad')) {
      peticionesMuro++;
      return http.Response(
        jsonEncode({'fuente': 'BASE_DE_DATOS_POSTGRESQL', 'data': alertas}),
        200,
      );
    }
    if (peticion.url.path.endsWith('/api/notificaciones')) {
      peticionesBandeja++;
      return http.Response(
        jsonEncode({
          'no_leidas': notificaciones.where((n) => n['leida'] != true).length,
          'data': notificaciones,
        }),
        200,
      );
    }
    return http.Response('{}', 404);
  });

  void agregarAlerta(int id, String tipo) {
    alertas.insert(0, {
      'id_alerta': id,
      'tipo_alerta': tipo,
      'fecha_hora': DateTime.now().toIso8601String(),
      'estado': 'ACTIVA',
      'id_usuario': 2,
      'usuario': {'id_usuario': 2, 'nombre': 'Ana', 'telefono': '099'},
    });
    notificaciones.insert(0, {
      'id_notificacion': id,
      'leida': false,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'alerta': {
        'id_alerta': id,
        'tipo_alerta': tipo,
        'es_panico': false,
        'usuario': {'id_usuario': 2, 'nombre': 'Ana'},
      },
    });
  }
}

Servicios _servicios(_ServidorMutable servidor) {
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
  return Servicios(
    sesion: sesion,
    cliente: ClienteApi(
      sesion: sesion,
      cliente: servidor.cliente,
      urlBase: 'http://falso',
    ),
    permisos: GestorPermisosFalso(
      inicial: {Capacidad.notificaciones: EstadoPermiso.concedido},
    ),
    ubicacion: ServicioUbicacionFalso(),
  );
}

Widget _montar(Servicios servicios, Widget pantalla) => Dependencias(
  servicios: servicios,
  child: MaterialApp(theme: TemaApp.claro, home: pantalla),
);

/// Número que muestra el distintivo de la campana, o `null` si no se ve.
String? _contadorCampana(WidgetTester tester) {
  final distintivo = tester.widget<Badge>(find.byType(Badge));
  if (!distintivo.isLabelVisible) return null;
  return (distintivo.label as Text).data;
}

void main() {
  group('Muro — se actualiza solo', () {
    testWidgets('un aviso push con la app abierta trae la alerta nueva y '
        'actualiza la campana al instante', (tester) async {
      final servidor = _ServidorMutable();
      final servicios = _servicios(servidor);
      await tester.pumpWidget(_montar(servicios, const PantallaMuroAlertas()));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsNothing);
      expect(_contadorCampana(tester), isNull);

      // Otro vecino emite: el servidor ya la tiene y llega el push.
      servidor.agregarAlerta(7, 'Robo');
      servicios.avisosEntrantes.avisar();
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Robo'), findsWidgets);
      expect(_contadorCampana(tester), '1');
    });

    testWidgets('sin push, se actualiza solo cada '
        '${PantallaMuroAlertas.intervaloActualizacion.inSeconds} s', (
      tester,
    ) async {
      final servidor = _ServidorMutable();
      final servicios = _servicios(servidor);
      await tester.pumpWidget(_montar(servicios, const PantallaMuroAlertas()));
      await tester.pumpAndSettle();

      servidor.agregarAlerta(8, 'Ruido');
      // Justo antes del intervalo todavía no debe haber pedido nada nuevo.
      final antes = servidor.peticionesMuro;
      await tester.pump(
        PantallaMuroAlertas.intervaloActualizacion - const Duration(seconds: 1),
      );
      expect(servidor.peticionesMuro, antes);
      expect(find.byType(TarjetaAlerta), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(servidor.peticionesMuro, antes + 1);
      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(_contadorCampana(tester), '1');
    });

    testWidgets('en segundo plano deja de consultar y al volver se actualiza '
        'de inmediato', (tester) async {
      final servidor = _ServidorMutable();
      final servicios = _servicios(servidor);
      await tester.pumpWidget(_montar(servicios, const PantallaMuroAlertas()));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final enPausa = servidor.peticionesMuro;
      servidor.agregarAlerta(9, 'Robo');

      // Varios intervalos con la app en segundo plano: ni una petición.
      await tester.pump(PantallaMuroAlertas.intervaloActualizacion * 3);
      expect(servidor.peticionesMuro, enPausa);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(servidor.peticionesMuro, enPausa + 1);
      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(_contadorCampana(tester), '1');
    });

    testWidgets('si la actualización automática falla, conserva las alertas '
        'que ya se veían', (tester) async {
      final servidor = _ServidorMutable()..agregarAlerta(1, 'Robo');
      final servicios = _servicios(servidor);
      await tester.pumpWidget(_montar(servicios, const PantallaMuroAlertas()));
      await tester.pumpAndSettle();
      expect(find.byType(TarjetaAlerta), findsOneWidget);

      servidor.caido = true;
      servicios.avisosEntrantes.avisar();
      // Deja correr los reintentos del cliente HTTP (400 ms y 800 ms).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('al salir del muro deja de escuchar y de consultar', (
      tester,
    ) async {
      final servidor = _ServidorMutable();
      final servicios = _servicios(servidor);
      await tester.pumpWidget(_montar(servicios, const PantallaMuroAlertas()));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_montar(servicios, const SizedBox()));
      final alSalir = servidor.peticionesMuro;

      servicios.avisosEntrantes.avisar();
      await tester.pump(PantallaMuroAlertas.intervaloActualizacion * 2);
      expect(servidor.peticionesMuro, alSalir);
    });
  });

  group('Bandeja de notificaciones — se actualiza sola', () {
    testWidgets('un aviso push con la bandeja abierta agrega la notificación', (
      tester,
    ) async {
      final servidor = _ServidorMutable()..agregarAlerta(1, 'Robo');
      final servicios = _servicios(servidor);
      await tester.pumpWidget(
        _montar(servicios, const PantallaNotificaciones()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TarjetaAlerta), findsOneWidget);

      servidor.agregarAlerta(2, 'Ruido');
      servicios.avisosEntrantes.avisar();
      // Sin `pumpAndSettle` intermedio: la recarga automática no debe pasar
      // por la pantalla de carga.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsNWidgets(2));
    });

    testWidgets('si la recarga automática falla, la lista se mantiene', (
      tester,
    ) async {
      final servidor = _ServidorMutable()..agregarAlerta(1, 'Robo');
      final servicios = _servicios(servidor);
      await tester.pumpWidget(
        _montar(servicios, const PantallaNotificaciones()),
      );
      await tester.pumpAndSettle();

      servidor.caido = true;
      servicios.avisosEntrantes.avisar();
      // Deja correr los reintentos del cliente HTTP (400 ms y 800 ms).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
    });
  });

  group('Bandeja de notificaciones — limpiar', () {
    Future<_ServidorMutable> abrir(WidgetTester tester, {int avisos = 2}) async {
      final servidor = _ServidorMutable();
      for (var i = 1; i <= avisos; i++) {
        servidor.agregarAlerta(i, i.isEven ? 'Ruido' : 'Robo');
      }
      await tester.pumpWidget(
        _montar(_servicios(servidor), const PantallaNotificaciones()),
      );
      await tester.pumpAndSettle();
      return servidor;
    }

    testWidgets('«Limpiar bandeja» con confirmación borra todo y muestra la '
        'bandeja vacía', (tester) async {
      final servidor = await abrir(tester);
      expect(find.byType(TarjetaAlerta), findsNWidgets(2));

      await tester.tap(find.byTooltip('Limpiar bandeja'));
      await tester.pumpAndSettle();
      expect(find.text('¿Limpiar la bandeja?'), findsOneWidget);

      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      expect(servidor.notificaciones, isEmpty);
      expect(find.byType(TarjetaAlerta), findsNothing);
      expect(find.text('Sin notificaciones'), findsOneWidget);
      // Con la bandeja vacía ya no hay nada que limpiar.
      expect(find.byTooltip('Limpiar bandeja'), findsNothing);
    });

    testWidgets('cancelar el diálogo no borra nada', (tester) async {
      final servidor = await abrir(tester);

      await tester.tap(find.byTooltip('Limpiar bandeja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(servidor.notificaciones, hasLength(2));
      expect(find.byType(TarjetaAlerta), findsNWidgets(2));
    });

    testWidgets('deslizar una notificación la borra solo a ella', (
      tester,
    ) async {
      final servidor = await abrir(tester);
      final primera = servidor.notificaciones.first['id_notificacion'];

      await tester.drag(find.byType(Dismissible).first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      // Sin animaciones en curso, `pumpAndSettle` no deja correr el tiempo
      // que necesita el cliente HTTP para completar el borrado.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaAlerta), findsOneWidget);
      expect(servidor.notificaciones, hasLength(1));
      expect(
        servidor.notificaciones.any((n) => n['id_notificacion'] == primera),
        isFalse,
      );
    });

    testWidgets('si el servidor no borra, la notificación vuelve y se avisa', (
      tester,
    ) async {
      final servidor = await abrir(tester);
      servidor.fallaBorrado = true;

      await tester.drag(find.byType(Dismissible).first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(servidor.notificaciones, hasLength(2));
      expect(find.byType(TarjetaAlerta), findsNWidgets(2));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('sin notificaciones no se ofrece limpiar', (tester) async {
      await abrir(tester, avisos: 0);
      expect(find.byTooltip('Limpiar bandeja'), findsNothing);
    });
  });
}
