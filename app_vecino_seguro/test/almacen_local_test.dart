import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/modelos/alerta.dart';
import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/servicios/almacen_local.dart';

import 'ayudas_prueba.dart';

/// PASO 12 — ALMACENAMIENTO LOCAL
///
/// Se prueba contra [AlmacenLocalEnMemoria], que cumple el mismo contrato que
/// la implementación de sqflite. El mapeo fila↔objeto, que es la parte que sí
/// depende del esquema, vive en los modelos y se prueba aquí directamente.
void main() {
  group('Alerta — mapeo a fila', () {
    test('ida y vuelta conserva todos los campos', () {
      final original = Alerta(
        idAlerta: 42,
        tipoAlerta: 'Incendio',
        fechaHora: DateTime(2026, 9, 6, 14, 30),
        estado: 'ACTIVA',
        nombreVecino: 'Luis',
        esPanico: true,
        descripcion: 'Humo en el patio',
      );

      final recuperada = Alerta.desdeFila(original.aFila(7));

      expect(recuperada.idAlerta, 42);
      expect(recuperada.tipoAlerta, 'Incendio');
      expect(recuperada.estado, 'ACTIVA');
      expect(recuperada.nombreVecino, 'Luis');
      expect(recuperada.esPanico, isTrue);
      expect(recuperada.descripcion, 'Humo en el patio');
      expect(recuperada.fechaHora, original.fechaHora);
    });

    test('el booleano se guarda como 0/1, que es lo que admite SQLite', () {
      final fila = Alerta(
        idAlerta: 1,
        tipoAlerta: 'Robo',
        fechaHora: DateTime.now(),
        estado: 'ACTIVA',
        nombreVecino: 'Ana',
      ).aFila(1);

      expect(fila['es_panico'], 0);
      expect(fila['id_comunidad'], 1);
    });

    test('la fecha se guarda en UTC', () {
      final alerta = Alerta(
        idAlerta: 1,
        tipoAlerta: 'Robo',
        fechaHora: DateTime.now(),
        estado: 'ACTIVA',
        nombreVecino: 'Ana',
      );

      // Con hora local, la misma alerta se ordenaría distinto según el huso
      // horario del dispositivo.
      expect(alerta.aFila(1)['fecha_hora'], endsWith('Z'));
    });
  });

  group('PerfilVecino — serialización', () {
    test('ida y vuelta conserva la membresía y la comunidad', () {
      final original = perfilDePrueba(esAdmin: true);
      final recuperado = PerfilVecino.desdeJson(original.aJson());

      expect(recuperado.idUsuario, original.idUsuario);
      expect(recuperado.nombre, original.nombre);
      expect(recuperado.telefono, original.telefono);
      expect(recuperado.estadoMembresia, EstadoMembresia.activo);
      expect(recuperado.comunidad?.codigo, original.comunidad?.codigo);
      expect(recuperado.esAdmin, isTrue);
    });

    test('los tres estados de membresía sobreviven al viaje de ida y vuelta', () {
      // Sin `aApi`, todo se releería como `sinComunidad` y la app mandaría a
      // elegir comunidad a un vecino que ya tiene una.
      for (final estado in EstadoMembresia.values) {
        expect(EstadoMembresia.desdeApi(estado.aApi), estado);
      }
    });
  });

  group('Caché de alertas', () {
    test('guarda y devuelve las alertas de una comunidad', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      await almacen.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 1, tipo: 'Robo')),
        Alerta.desdeJson(alertaJson(id: 2, tipo: 'Incendio')),
      ]);

      final leidas = await almacen.leerAlertas(1);
      expect(leidas, hasLength(2));
    });

    test('sincronizar SUSTITUYE, no fusiona', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      await almacen.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 1, tipo: 'Robo')),
        Alerta.desdeJson(alertaJson(id: 2, tipo: 'Incendio')),
      ]);
      await almacen.reemplazarAlertas(1, [
        Alerta.desdeJson(alertaJson(id: 3, tipo: 'Ruido')),
      ]);

      // Es la estrategia de conflictos declarada: el servidor gana. Si un
      // administrador resolvió las dos primeras, no pueden seguir apareciendo.
      final leidas = await almacen.leerAlertas(1);
      expect(leidas, hasLength(1));
      expect(leidas.single.idAlerta, 3);
    });

    test('cada comunidad guarda las suyas', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      await almacen.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson(id: 1))]);
      await almacen.reemplazarAlertas(2, [Alerta.desdeJson(alertaJson(id: 2))]);

      expect(await almacen.leerAlertas(1), hasLength(1));
      expect(await almacen.leerAlertas(2), hasLength(1));
    });

    test('registra cuándo se sincronizó', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      expect(await almacen.ultimaSincronizacion(), isNull);

      await almacen.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson())]);

      final momento = await almacen.ultimaSincronizacion();
      expect(momento, isNotNull);
      expect(DateTime.now().difference(momento!).inSeconds, lessThan(5));
    });
  });

  group('Cola de operaciones', () {
    OperacionPendiente operacion(String clave, {DateTime? proximoIntento}) =>
        OperacionPendiente(
          claveCliente: clave,
          tipo: OperacionPendiente.tipoEmitirAlerta,
          carga: {'tipo_alerta': 'Robo', 'clave_cliente': clave},
          creadaEn: DateTime.now(),
          proximoIntentoEn: proximoIntento ?? DateTime.now(),
        );

    test('encola, lee y borra', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      await almacen.encolar(operacion('abc'));
      expect(await almacen.leerCola(), hasLength(1));

      await almacen.borrarOperacion('abc');
      expect(await almacen.leerCola(), isEmpty);
    });

    test('solo devuelve las que ya cumplieron su espera', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      final ahora = DateTime.now();
      await almacen.encolar(
        operacion('lista', proximoIntento: ahora.subtract(const Duration(seconds: 1))),
      );
      await almacen.encolar(
        operacion('esperando', proximoIntento: ahora.add(const Duration(minutes: 5))),
      );

      final listas = await almacen.operacionesListas(ahora);
      expect(listas.map((o) => o.claveCliente), ['lista']);
      // La que espera sigue en la cola: no se ha perdido, solo no toca aún.
      expect(await almacen.leerCola(), hasLength(2));
    });

    test('actualizar una operación ya borrada NO la resucita', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      final op = operacion('abc');
      await almacen.encolar(op);
      await almacen.borrarOperacion('abc');

      // Si esto la reinsertara, una operación ya enviada volvería a la cola y
      // se emitiría dos veces.
      await almacen.actualizarOperacion(op.copiarCon(intentos: 1));
      expect(await almacen.leerCola(), isEmpty);
    });

    test('la carga sobrevive al viaje de ida y vuelta', () {
      final op = operacion('abc');
      final recuperada = OperacionPendiente.desdeFila(op.aFila());

      expect(recuperada.claveCliente, 'abc');
      expect(recuperada.carga['tipo_alerta'], 'Robo');
      expect(recuperada.carga['clave_cliente'], 'abc');
      expect(recuperada.tipo, OperacionPendiente.tipoEmitirAlerta);
    });

    test('una carga corrupta no rompe la lectura de toda la cola', () {
      final recuperada = OperacionPendiente.desdeFila({
        'clave_cliente': 'abc',
        'tipo': 'emitir_alerta',
        'carga': 'esto no es json',
        'creada_en': DateTime.now().toIso8601String(),
        'proximo_intento_en': DateTime.now().toIso8601String(),
        'intentos': 0,
      });

      expect(recuperada.claveCliente, 'abc');
      expect(recuperada.carga, isEmpty);
    });
  });

  group('borrarTodo', () {
    test('vacía alertas, cola y metadatos', () async {
      final almacen = AlmacenLocalEnMemoria();
      await almacen.abrir();

      await almacen.reemplazarAlertas(1, [Alerta.desdeJson(alertaJson())]);
      await almacen.encolar(
        OperacionPendiente(
          claveCliente: 'abc',
          tipo: OperacionPendiente.tipoEmitirAlerta,
          carga: const {},
          creadaEn: DateTime.now(),
          proximoIntentoEn: DateTime.now(),
        ),
      );

      await almacen.borrarTodo();

      expect(await almacen.leerAlertas(1), isEmpty);
      expect(await almacen.leerCola(), isEmpty);
      expect(await almacen.ultimaSincronizacion(), isNull);
    });
  });
}
