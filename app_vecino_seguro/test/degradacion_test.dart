import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/screens/pantalla_emitir_alerta.dart';
import 'package:app_vecino_seguro/servicios/almacen_local.dart';
import 'package:app_vecino_seguro/servicios/gestor_permisos.dart';
import 'package:app_vecino_seguro/servicios/servicio_ubicacion.dart';

import 'ayudas_prueba.dart';

/// Matriz de degradación: **la aplicación sigue siendo utilizable cuando las
/// capacidades del dispositivo no están disponibles**.
///
/// Es el objetivo declarado de la Semana 14, y la propiedad que hay que poder
/// demostrar en el taller. Cada prueba recorre una fila de la matriz y
/// comprueba dos cosas:
///
/// 1. La emisión **se completa** —la alerta llega al servidor o a la cola—.
/// 2. La aplicación **no se rompe** por el camino.
void main() {
  /// Servidor que acepta la emisión y registra lo que recibió.
  ({MockClient cliente, List<Map<String, dynamic>> recibido}) servidor() {
    final recibido = <Map<String, dynamic>>[];

    final cliente = MockClient((peticion) async {
      if (peticion.url.path.contains('alertas/emitir')) {
        recibido.add(jsonDecode(peticion.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({'mensaje': 'Alerta emitida.'}),
          202,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({'data': [], 'no_leidas': 0}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    return (cliente: cliente, recibido: recibido);
  }

  /// Emite una alerta con las capacidades en el estado indicado.
  Future<List<Map<String, dynamic>>> emitirCon(
    WidgetTester tester, {
    required EstadoPermiso permiso,
    required ServicioUbicacionFalso ubicacion,
  }) async {
    final sesion = await sesionActiva();
    final api = servidor();
    final local = AlmacenLocalEnMemoria();
    await local.abrir();

    await tester.pumpWidget(
      montarConDependencias(
        hijo: const PantallaEmitirAlerta(),
        sesion: sesion,
        cliente: api.cliente,
        local: local,
        permisos: GestorPermisosFalso(
          inicial: {Capacidad.ubicacion: permiso},
          // Si la app decide pedirlo, el vecino vuelve a decir lo mismo.
          alSolicitar: (_) => permiso,
        ),
        ubicacion: ubicacion,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Robo').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
    await tester.pumpAndSettle();

    // Confirmación obligatoria.
    //
    // A partir de aquí se usa `pump` con duración en lugar de `pumpAndSettle`:
    // el botón entra en estado "enviando" y muestra un indicador de progreso
    // indeterminado, que nunca deja de animarse. `pumpAndSettle` esperaría a
    // que las animaciones terminen y agotaría el tiempo.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Si la app pide el permiso, se atraviesa su explicación. El botón de
    // confirmar cambia según el estado: ante una denegación permanente no
    // ofrece reintentar, sino ir a los ajustes.
    for (final texto in ['Continuar', 'Abrir ajustes']) {
      final boton = find.widgetWithText(ElevatedButton, texto);
      if (boton.evaluate().isNotEmpty) {
        await tester.tap(boton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        break;
      }
    }

    // Margen para que la emisión termine su viaje por la cola.
    await tester.pump(const Duration(seconds: 1));

    return api.recibido;
  }

  group('Matriz de degradación — emitir una alerta', () {
    testWidgets('permiso concedido y GPS activo: viaja CON coordenadas', (
      tester,
    ) async {
      final recibido = await emitirCon(
        tester,
        permiso: EstadoPermiso.concedido,
        ubicacion: ServicioUbicacionFalso(
          resultado: const UbicacionObtenida(-1.2491, -78.6167),
        ),
      );

      expect(recibido, hasLength(1));
      expect(recibido.single['latitud'], -1.2491);
      expect(recibido.single['longitud'], -78.6167);
    });

    testWidgets('permiso concedido pero GPS apagado: se emite SIN coordenadas',
        (tester) async {
      final recibido = await emitirCon(
        tester,
        permiso: EstadoPermiso.concedido,
        ubicacion: ServicioUbicacionFalso(activo: false),
      );

      // Lo esencial: la alerta SALE. El lugar es un extra.
      expect(recibido, hasLength(1));
      expect(recibido.single['latitud'], isNull);

      // Y se le dice al vecino por qué, sin pintarlo como un fallo del envío.
      expect(find.textContaining('apagada'), findsOneWidget);
    });

    testWidgets('permiso denegado: se emite igual', (tester) async {
      final recibido = await emitirCon(
        tester,
        permiso: EstadoPermiso.denegado,
        ubicacion: ServicioUbicacionFalso(),
      );

      expect(recibido, hasLength(1));
      expect(recibido.single['latitud'], isNull);
      expect(find.textContaining('sin el lugar'), findsOneWidget);
    });

    testWidgets('denegado PARA SIEMPRE: se emite, y se ofrecen los ajustes', (
      tester,
    ) async {
      final recibido = await emitirCon(
        tester,
        permiso: EstadoPermiso.denegadoPermanente,
        ubicacion: ServicioUbicacionFalso(),
      );

      expect(recibido, hasLength(1));
      // El mensaje es distinto del de "denegado" a propósito: aquí el sistema
      // ya no volverá a preguntar, así que reintentar no sirve de nada y hay
      // que mandar al vecino a los ajustes.
      expect(find.textContaining('ajustes del teléfono'), findsOneWidget);
    });

    testWidgets('capacidad ausente o GPS que no fija: se emite igual', (
      tester,
    ) async {
      final recibido = await emitirCon(
        tester,
        permiso: EstadoPermiso.concedido,
        ubicacion: ServicioUbicacionFalso(
          resultado: const UbicacionNoDisponible(),
        ),
      );

      expect(recibido, hasLength(1));
      expect(recibido.single['latitud'], isNull);
    });

    testWidgets('nunca se preguntó: se explica, y la alerta sale', (
      tester,
    ) async {
      final recibido = await emitirCon(
        tester,
        permiso: EstadoPermiso.noPreguntado,
        ubicacion: ServicioUbicacionFalso(),
      );

      expect(recibido, hasLength(1));
    });
  });

  group('La ubicación se consulta en cada emisión, no una sola vez', () {
    testWidgets('el permiso se consulta al emitir, no al abrir la pantalla', (
      tester,
    ) async {
      final sesion = await sesionActiva();
      final api = servidor();
      final local = AlmacenLocalEnMemoria();
      await local.abrir();

      final gestor = GestorPermisosFalso(
        inicial: {Capacidad.ubicacion: EstadoPermiso.concedido},
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaEmitirAlerta(),
          sesion: sesion,
          cliente: api.cliente,
          local: local,
          permisos: gestor,
          ubicacion: ServicioUbicacionFalso(),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir la pantalla no molesta al vecino con ningún permiso: todavía no
      // ha decidido emitir nada.
      expect(gestor.consultas[Capacidad.ubicacion], isNull);

      await tester.tap(find.text('Robo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Emitir alerta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sí, emitir alerta'));
      await tester.pumpAndSettle();

      // Se consulta justo cuando la funcionalidad se va a usar.
      expect(gestor.consultas[Capacidad.ubicacion], 1);
    });
  });
}
