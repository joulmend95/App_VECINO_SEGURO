import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/screens/pantalla_muro_alertas.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/dependencias.dart';
import 'package:app_vecino_seguro/servicios/gestor_permisos.dart';
import 'package:app_vecino_seguro/servicios/servicio_ubicacion.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';
import 'package:app_vecino_seguro/theme/tema_app.dart';
import 'package:app_vecino_seguro/widgets/boton_copiar_codigo.dart';

/// Servidor falso con un número configurable de solicitudes pendientes.
class _Servidor {
  _Servidor({this.pendientes = 0});

  int pendientes;
  int consultasSolicitudes = 0;

  MockClient get cliente => MockClient((peticion) async {
    final ruta = peticion.url.path;
    if (ruta.endsWith('/api/comunidades/solicitudes')) {
      consultasSolicitudes++;
      return http.Response(
        jsonEncode({
          'solicitudes': [
            for (var i = 1; i <= pendientes; i++)
              {
                'id_solicitud': i,
                'fecha_solicitud': DateTime.now().toIso8601String(),
                'vecino': {'id_usuario': 10 + i, 'nombre': 'Vecino $i', 'telefono': '099'},
              },
          ],
        }),
        200,
      );
    }
    if (ruta.endsWith('/api/alertas/comunidad')) {
      return http.Response('{"fuente":"BD","data":[]}', 200);
    }
    if (ruta.endsWith('/api/notificaciones')) {
      return http.Response('{"no_leidas":0,"data":[]}', 200);
    }
    return http.Response('{}', 404);
  });
}

Widget _muro(_Servidor servidor, {required bool esAdmin}) {
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
        'es_admin': esAdmin,
      },
    }),
  );
  final servicios = Servicios(
    sesion: sesion,
    cliente: ClienteApi(sesion: sesion, cliente: servidor.cliente, urlBase: 'http://falso'),
    permisos: GestorPermisosFalso(
      inicial: {Capacidad.notificaciones: EstadoPermiso.concedido},
    ),
    ubicacion: ServicioUbicacionFalso(),
  );
  return Dependencias(
    servicios: servicios,
    child: MaterialApp(theme: TemaApp.claro, home: const PantallaMuroAlertas()),
  );
}

void main() {
  group('Muro — aviso de solicitudes al administrador', () {
    testWidgets('con solicitudes pendientes, el admin ve el aviso con la '
        'cantidad', (tester) async {
      await tester.pumpWidget(_muro(_Servidor(pendientes: 2), esAdmin: true));
      await tester.pumpAndSettle();

      expect(find.text('2 vecinos esperan tu aprobación'), findsOneWidget);
      expect(find.text('Revisar'), findsOneWidget);
    });

    testWidgets('con una sola solicitud el texto va en singular', (
      tester,
    ) async {
      await tester.pumpWidget(_muro(_Servidor(pendientes: 1), esAdmin: true));
      await tester.pumpAndSettle();

      expect(find.text('1 vecino espera tu aprobación'), findsOneWidget);
    });

    testWidgets('sin solicitudes no hay aviso', (tester) async {
      await tester.pumpWidget(_muro(_Servidor(), esAdmin: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('esperan tu aprobación'), findsNothing);
      expect(find.textContaining('espera tu aprobación'), findsNothing);
    });

    testWidgets('a un vecino que no es admin ni se le consultan', (
      tester,
    ) async {
      final servidor = _Servidor(pendientes: 3);
      await tester.pumpWidget(_muro(servidor, esAdmin: false));
      await tester.pumpAndSettle();

      expect(servidor.consultasSolicitudes, 0);
      expect(find.textContaining('aprobación'), findsNothing);
    });

    testWidgets('una solicitud nueva aparece con el aviso push, sin refrescar', (
      tester,
    ) async {
      final servidor = _Servidor();
      final app = _muro(servidor, esAdmin: true);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.textContaining('aprobación'), findsNothing);

      servidor.pendientes = 1;
      final servicios = Dependencias.de(
        tester.element(find.byType(PantallaMuroAlertas)),
      );
      servicios.avisosEntrantes.avisar();
      await tester.pumpAndSettle();

      expect(find.text('1 vecino espera tu aprobación'), findsOneWidget);
    });

    testWidgets('el menú muestra el número de solicitudes', (tester) async {
      await tester.pumpWidget(_muro(_Servidor(pendientes: 4), esAdmin: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();

      final fila = find.ancestor(
        of: find.text('Solicitudes para unirse'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: fila, matching: find.text('4')),
        findsOneWidget,
      );
    });
  });

  group('Copiar el código de la comunidad', () {
    testWidgets('copia solo el código al portapapeles y lo confirma', (
      tester,
    ) async {
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (llamada) async {
          if (llamada.method == 'Clipboard.setData') {
            copiado = (llamada.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TemaApp.claro,
          home: const Scaffold(body: BotonCopiarCodigo(codigo: 'URB-2026')),
        ),
      );
      await tester.tap(find.byTooltip('Copiar código'));
      await tester.pumpAndSettle();

      expect(copiado, 'URB-2026');
      expect(find.textContaining('Código URB-2026 copiado'), findsOneWidget);
    });
  });
}
