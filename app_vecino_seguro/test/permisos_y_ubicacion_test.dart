import 'package:flutter_test/flutter_test.dart';

import 'package:app_vecino_seguro/servicios/gestor_permisos.dart';
import 'package:app_vecino_seguro/servicios/servicio_ubicacion.dart';

void main() {
  group('Los cuatro estados del permiso', () {
    test('cada estado es distinguible y tiene su propia reacción', () {
      // El valor de separar cuatro estados está en estas dos propiedades: son
      // las que deciden qué puede hacer la interfaz con cada uno.
      expect(EstadoPermiso.concedido.esUsable, isTrue);
      expect(EstadoPermiso.denegado.esUsable, isFalse);
      expect(EstadoPermiso.noPreguntado.esUsable, isFalse);
      expect(EstadoPermiso.denegadoPermanente.esUsable, isFalse);

      // Solo uno de los cuatro obliga a salir a los ajustes del sistema.
      expect(EstadoPermiso.denegadoPermanente.exigeAjustes, isTrue);
      expect(EstadoPermiso.denegado.exigeAjustes, isFalse);
      expect(EstadoPermiso.noPreguntado.exigeAjustes, isFalse);
      expect(EstadoPermiso.concedido.exigeAjustes, isFalse);
    });

    test('solicitar deja registrado el resultado para la próxima consulta', () async {
      final gestor = GestorPermisosFalso(
        alSolicitar: (_) => EstadoPermiso.denegado,
      );

      expect(
        await gestor.consultar(Capacidad.ubicacion),
        EstadoPermiso.noPreguntado,
      );

      expect(
        await gestor.solicitar(Capacidad.ubicacion),
        EstadoPermiso.denegado,
      );

      // La segunda consulta ya no dice "no preguntado": si lo dijera, la app
      // volvería a mostrar la explicación a alguien que ya dijo que no.
      expect(
        await gestor.consultar(Capacidad.ubicacion),
        EstadoPermiso.denegado,
      );
    });

    test('la denegación permanente ofrece los ajustes del sistema', () async {
      final gestor = GestorPermisosFalso(
        inicial: {Capacidad.ubicacion: EstadoPermiso.denegadoPermanente},
      );

      final estado = await gestor.consultar(Capacidad.ubicacion);
      expect(estado.exigeAjustes, isTrue);

      expect(await gestor.abrirAjustes(), isTrue);
      expect(gestor.aperturasDeAjustes, 1);
    });
  });

  group('Revocación en caliente', () {
    test('un permiso revocado desde los ajustes se detecta en la siguiente '
        'consulta', () async {
      final gestor = GestorPermisosFalso(
        inicial: {Capacidad.notificaciones: EstadoPermiso.concedido},
      );

      expect(
        (await gestor.consultar(Capacidad.notificaciones)).esUsable,
        isTrue,
      );

      // El vecino va a los ajustes del teléfono y lo revoca. La aplicación no
      // recibe ningún aviso de esto.
      gestor.cambiarDesdeAjustes(
        Capacidad.notificaciones,
        EstadoPermiso.denegado,
      );

      // Por eso hay que consultar antes de CADA uso: quien guardara el
      // resultado de la primera consulta seguiría creyendo que puede avisar al
      // vecino de una emergencia.
      expect(
        (await gestor.consultar(Capacidad.notificaciones)).esUsable,
        isFalse,
      );
      expect(gestor.consultas[Capacidad.notificaciones], 2);
    });
  });

  group('Ubicación: permiso y servicio son cosas distintas', () {
    test('con el servicio apagado devuelve ServicioDesactivado, no un fallo '
        'genérico', () async {
      final servicio = ServicioUbicacionFalso(activo: false);

      final resultado = await servicio.obtener();

      // La distinción importa: aquí el vecino no tiene que ir a los permisos,
      // tiene que encender la ubicación. Un fallo genérico le mandaría al
      // sitio equivocado.
      expect(resultado, isA<ServicioDesactivado>());
      expect(resultado.latitud, isNull);
      expect(resultado.longitud, isNull);
    });

    test('con todo en orden devuelve las coordenadas', () async {
      final servicio = ServicioUbicacionFalso(
        resultado: const UbicacionObtenida(-1.2491, -78.6167),
      );

      final resultado = await servicio.obtener();

      expect(resultado, isA<UbicacionObtenida>());
      expect(resultado.latitud, -1.2491);
      expect(resultado.longitud, -78.6167);
    });

    test('un GPS más lento que el límite no cuelga la emisión', () async {
      final servicio = ServicioUbicacionFalso(
        demora: const Duration(seconds: 30),
      );

      final resultado = await servicio.obtener(
        limite: const Duration(seconds: 5),
      );

      // Se rinde y devuelve un resultado utilizable. Una alerta de emergencia
      // que no sale porque el GPS tardó es mucho peor que una sin coordenadas.
      expect(resultado, isA<UbicacionNoDisponible>());
      expect(resultado.latitud, isNull);
    });

    test('nunca lanza excepción, en ninguna de sus formas', () async {
      final casos = <ServicioUbicacionFalso>[
        ServicioUbicacionFalso(activo: false),
        ServicioUbicacionFalso(demora: const Duration(seconds: 30)),
        ServicioUbicacionFalso(
          resultado: const PermisoInsuficiente(permanente: true),
        ),
        ServicioUbicacionFalso(
          resultado: const PermisoInsuficiente(permanente: false),
        ),
        ServicioUbicacionFalso(resultado: const UbicacionNoDisponible()),
      ];

      for (final servicio in casos) {
        // La propiedad que hay que demostrar en el taller: en ninguna
        // situación de indisponibilidad la aplicación se rompe.
        await expectLater(servicio.obtener(), completes);
      }
    });
  });
}
