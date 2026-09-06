import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/servicios/almacen_local.dart';
import 'package:app_vecino_seguro/servicios/cliente_api.dart';
import 'package:app_vecino_seguro/servicios/cola_sincronizacion.dart';
import 'package:app_vecino_seguro/servicios/servicio_alertas.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';

import 'ayudas_prueba.dart';

/// PASO 13 — COLA DE ESCRITURA Y SINCRONIZACIÓN
void main() {
  /// Cola lista para usar, con el servidor simulado que se le indique.
  Future<({ColaSincronizacion cola, AlmacenLocal almacen, Sesion sesion})>
  montarCola(MockClient cliente) async {
    final sesion = await sesionActiva();
    final almacen = AlmacenLocalEnMemoria();
    await almacen.abrir();

    final api = ClienteApi(
      sesion: sesion,
      cliente: cliente,
      urlBase: 'http://servidor-falso',
    );

    return (
      cola: ColaSincronizacion(
        almacen: almacen,
        alertas: ServicioAlertas(api, almacenLocal: almacen),
      ),
      almacen: almacen,
      sesion: sesion,
    );
  }

  /// Cliente que nunca llega al servidor: es el modo avión.
  MockClient sinRed() =>
      MockClient((_) async => throw const SocketException('modo avión'));

  group('Encolado con identificador de cliente', () {
    test('genera un UUID y lo guarda dentro de la carga', () async {
      final m = await montarCola(sinRed());

      final clave = await m.cola.encolarAlerta(tipoAlerta: 'Robo');

      expect(clave, isNotEmpty);
      final cola = await m.almacen.leerCola();
      expect(cola, hasLength(1));
      expect(cola.single.claveCliente, clave);
      // La clave viaja en el cuerpo: es lo que permite al servidor reconocer
      // un reintento y no duplicar la alerta.
      expect(cola.single.carga['clave_cliente'], clave);
      expect(cola.single.carga['tipo_alerta'], 'Robo');
    });

    test('dos alertas distintas reciben claves distintas', () async {
      final m = await montarCola(sinRed());

      final a = await m.cola.encolarAlerta(tipoAlerta: 'Robo');
      final b = await m.cola.encolarAlerta(tipoAlerta: 'Incendio');

      expect(a, isNot(b));
      expect(await m.almacen.leerCola(), hasLength(2));
    });

    test('reencolar con la clave existente NO crea una segunda operación', () async {
      final m = await montarCola(sinRed());

      final clave = await m.cola.encolarAlerta(tipoAlerta: 'Robo');
      await m.cola.encolarAlerta(tipoAlerta: 'Robo', claveExistente: clave);

      // Es lo que impide que pulsar "Emitir" dos veces tras un error del
      // servidor genere dos alertas para la misma emergencia.
      expect(await m.almacen.leerCola(), hasLength(1));
    });
  });

  group('Drenado', () {
    test('una alerta enviada sale de la cola', () async {
      final m = await montarCola(
        servidorFalso({'alertas/emitir': (_) => ok({'alerta': alertaJson()})}),
      );
      await m.cola.encolarAlerta(tipoAlerta: 'Robo');

      final resultado = await m.cola.drenar();

      expect(resultado.enviadas, 1);
      expect(await m.almacen.leerCola(), isEmpty);
    });

    test('el reintento envía la MISMA clave, no una nueva', () async {
      final clavesRecibidas = <String>[];
      var primeraVez = true;

      final m = await montarCola(
        MockClient((peticion) async {
          final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
          clavesRecibidas.add(cuerpo['clave_cliente'] as String);
          if (primeraVez) {
            primeraVez = false;
            return falla(500, 'error');
          }
          return ok(jsonEncode({'alerta': alertaJson()}));
        }),
      );

      await m.cola.encolarAlerta(tipoAlerta: 'Robo');
      await m.cola.drenar();

      // Se adelanta el reloj de la operación para no esperar los 5 s reales.
      final pendiente = (await m.almacen.leerCola()).single;
      await m.almacen.actualizarOperacion(
        pendiente.copiarCon(
          proximoIntentoEn: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      await m.cola.drenar();

      expect(clavesRecibidas, hasLength(2));
      expect(
        clavesRecibidas[0],
        clavesRecibidas[1],
        reason: 'Si el reintento generara una clave nueva, el servidor no '
            'podría reconocerlo y crearía una alerta duplicada.',
      );
      expect(await m.almacen.leerCola(), isEmpty);
    });

    test('sin conexión NO gasta intento', () async {
      final m = await montarCola(sinRed());
      await m.cola.encolarAlerta(tipoAlerta: 'Robo');

      await m.cola.drenar();
      await m.cola.drenar();
      await m.cola.drenar();

      final pendiente = (await m.almacen.leerCola()).single;
      expect(
        pendiente.intentos,
        0,
        reason: 'Un rato en el metro no puede agotar la cuota de reintentos de '
            'una emergencia: el servidor no ha rechazado nada.',
      );
    });

    test('un 429 no gasta intento pero sí reprograma', () async {
      final m = await montarCola(
        servidorFalso({
          'alertas/emitir': (_) => falla(429, 'Espera 42 segundos.'),
        }),
      );
      await m.cola.encolarAlerta(tipoAlerta: 'Robo');

      final resultado = await m.cola.drenar();

      expect(resultado.enviadas, 0);
      expect(resultado.sinConexion, isFalse);
      final pendiente = (await m.almacen.leerCola()).single;
      expect(pendiente.intentos, 0);
      // Reprogramada: si no, la siguiente pasada volvería a chocar con el
      // límite de inmediato.
      expect(pendiente.proximoIntentoEn.isAfter(DateTime.now()), isTrue);
    });

    test('un 5xx sí gasta intento y aplica espera creciente', () async {
      final m = await montarCola(
        servidorFalso({'alertas/emitir': (_) => falla(500, 'error')}),
      );
      await m.cola.encolarAlerta(tipoAlerta: 'Robo');

      await m.cola.drenar();

      final pendiente = (await m.almacen.leerCola()).single;
      expect(pendiente.intentos, 1);
      expect(pendiente.ultimoError, isNotNull);
    });

    test('la espera crece de forma exponencial', () {
      expect(ColaSincronizacion.esperaTras(0), const Duration(seconds: 5));
      expect(ColaSincronizacion.esperaTras(1), const Duration(seconds: 10));
      expect(ColaSincronizacion.esperaTras(2), const Duration(seconds: 20));
      expect(ColaSincronizacion.esperaTras(3), const Duration(seconds: 40));
      expect(ColaSincronizacion.esperaTras(4), const Duration(seconds: 80));
    });

    test('tras el máximo de intentos deja de reintentarse', () async {
      final m = await montarCola(
        servidorFalso({'alertas/emitir': (_) => falla(500, 'error')}),
      );
      await m.cola.encolarAlerta(tipoAlerta: 'Robo');

      // Cinco pasadas, adelantando el reloj entre cada una.
      for (var i = 0; i < ColaSincronizacion.maximoIntentos; i++) {
        final cola = await m.almacen.leerCola();
        if (cola.isEmpty) break;
        await m.almacen.actualizarOperacion(
          cola.single.copiarCon(
            proximoIntentoEn: DateTime.now().subtract(const Duration(seconds: 1)),
          ),
        );
        await m.cola.drenar();
      }

      final pendiente = (await m.almacen.leerCola()).single;
      expect(pendiente.intentos, ColaSincronizacion.maximoIntentos);
      // NO se borra: el vecino tiene que poder enterarse de que su alerta no
      // salió. Una alerta que se rinde en silencio es peor que no encolarla.
      expect(await m.almacen.operacionesListas(DateTime.now()), isEmpty);
    });

    test('un rechazo de validación se descarta: reintentar no lo arregla', () async {
      final m = await montarCola(
        servidorFalso({
          'alertas/emitir': (_) => fallaValidacion({'tipo_alerta': 'Obligatorio.'}),
        }),
      );
      await m.cola.encolarAlerta(tipoAlerta: '');

      final resultado = await m.cola.drenar();

      expect(resultado.descartadas, 1);
      expect(await m.almacen.leerCola(), isEmpty);
    });

    test('una operación caducada se descarta sin gastar red', () async {
      var hubosPeticion = false;
      final m = await montarCola(
        servidorFalso(
          {'alertas/emitir': (_) => ok({'alerta': alertaJson()})},
          alRecibir: (_) => hubosPeticion = true,
        ),
      );

      await m.cola.encolarAlerta(tipoAlerta: 'Robo');
      final vieja = (await m.almacen.leerCola()).single;
      await m.almacen.actualizarOperacion(
        OperacionPendiente(
          claveCliente: vieja.claveCliente,
          tipo: vieja.tipo,
          carga: vieja.carga,
          // Más allá de la vigencia: reenviarla horas después solo generaría
          // confusión en la comunidad.
          creadaEn: DateTime.now().subtract(const Duration(hours: 2)),
          proximoIntentoEn: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );

      final resultado = await m.cola.drenar();

      expect(resultado.descartadas, 1);
      expect(hubosPeticion, isFalse);
      expect(await m.almacen.leerCola(), isEmpty);
    });

    test('el resultado distingue "sin red" de "el servidor dijo que no"', () async {
      final sinConexion = await montarCola(sinRed());
      await sinConexion.cola.encolarAlerta(tipoAlerta: 'Robo');
      final r1 = await sinConexion.cola.drenar();
      expect(r1.sinConexion, isTrue);

      final conError = await montarCola(
        servidorFalso({'alertas/emitir': (_) => falla(500, 'Servidor caído.')}),
      );
      await conError.cola.encolarAlerta(tipoAlerta: 'Robo');
      final r2 = await conError.cola.drenar();

      // Es la distinción que evita decirle "sin conexión" a quien acaba de
      // recibir una respuesta del servidor.
      expect(r2.sinConexion, isFalse);
      expect(r2.ultimoError, isNotNull);
    });

    test('varias operaciones se envían en orden de creación', () async {
      final tipos = <String>[];
      final m = await montarCola(
        MockClient((peticion) async {
          final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
          tipos.add(cuerpo['tipo_alerta'] as String);
          return ok(jsonEncode({'alerta': alertaJson()}));
        }),
      );

      await m.cola.encolarAlerta(tipoAlerta: 'Primera');
      await m.cola.encolarAlerta(tipoAlerta: 'Segunda');
      await m.cola.drenar();

      expect(tipos, ['Primera', 'Segunda']);
    });
  });
}

http.Response ok(Object cuerpo) => http.Response(
  cuerpo is String ? cuerpo : jsonEncode(cuerpo),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
