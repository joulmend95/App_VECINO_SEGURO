import 'package:geolocator/geolocator.dart';

/// Resultado de intentar obtener el lugar de una emergencia.
///
/// Es un tipo cerrado en lugar de un `double?` suelto porque **el motivo por el
/// que no hay coordenadas cambia lo que se le enseña al vecino**: si el GPS
/// está apagado se le dice que lo encienda; si denegó el permiso para siempre,
/// se le ofrecen los ajustes; si simplemente tardó, no se le dice nada porque
/// no hay nada que pueda hacer.
sealed class ResultadoUbicacion {
  const ResultadoUbicacion();

  double? get latitud => switch (this) {
    UbicacionObtenida(:final latitud) => latitud,
    _ => null,
  };

  double? get longitud => switch (this) {
    UbicacionObtenida(:final longitud) => longitud,
    _ => null,
  };
}

class UbicacionObtenida extends ResultadoUbicacion {
  const UbicacionObtenida(this.latitud, this.longitud);
  @override
  final double latitud;
  @override
  final double longitud;
}

/// El permiso está, pero el vecino tiene la ubicación apagada en el teléfono.
///
/// Es un estado **distinto** del permiso denegado, y por eso la consigna pide
/// comprobar las dos cosas: se puede tener el permiso concedido y el servicio
/// apagado, y el mensaje que resuelve cada caso es diferente.
class ServicioDesactivado extends ResultadoUbicacion {
  const ServicioDesactivado();
}

/// No hay permiso. `permanente` decide si aún se puede volver a preguntar.
class PermisoInsuficiente extends ResultadoUbicacion {
  const PermisoInsuficiente({required this.permanente});
  final bool permanente;
}

/// Se agotó el tiempo o el dispositivo no pudo fijar la posición.
///
/// No se le muestra nada al vecino: la alerta sale igual y no hay acción que
/// él pueda tomar.
class UbicacionNoDisponible extends ResultadoUbicacion {
  const UbicacionNoDisponible();
}

/// Obtiene el lugar de una emergencia.
///
/// Detrás de una interfaz por la misma razón que [GestorPermisos]: `geolocator`
/// necesita canales de plataforma que no existen en `flutter test`.
abstract interface class ServicioUbicacion {
  /// ¿Tiene el teléfono la ubicación encendida?
  Future<bool> servicioActivo();

  /// Posición actual, o el motivo por el que no se pudo obtener.
  ///
  /// **Nunca lanza excepción.** Una emergencia no puede fallar porque el GPS
  /// tenga un mal día.
  Future<ResultadoUbicacion> obtener({Duration limite});
}

class ServicioUbicacionReal implements ServicioUbicacion {
  const ServicioUbicacionReal();

  @override
  Future<bool> servicioActivo() => Geolocator.isLocationServiceEnabled();

  @override
  Future<ResultadoUbicacion> obtener({
    Duration limite = const Duration(seconds: 5),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const ServicioDesactivado();
      }

      // Se consulta el permiso aquí, justo antes de usarlo, y no se confía en
      // una comprobación anterior: entre una pantalla y otra el vecino pudo
      // haberlo revocado desde los ajustes del teléfono.
      final permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        return const PermisoInsuficiente(permanente: false);
      }
      if (permiso == LocationPermission.deniedForever) {
        return const PermisoInsuficiente(permanente: true);
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // `medium` basta para situar una alerta en un barrio y fija la
          // posición bastante antes que `best`. En una emergencia, cinco
          // metros más de precisión no compensan varios segundos de espera.
          accuracy: LocationAccuracy.medium,
          timeLimit: limite,
        ),
      );

      return UbicacionObtenida(posicion.latitude, posicion.longitude);
    } catch (_) {
      // Tiempo agotado, GPS sin fijar, o cualquier fallo del dispositivo. La
      // alerta debe salir igual, así que esto nunca se propaga.
      return const UbicacionNoDisponible();
    }
  }
}

/// Implementación en memoria para las pruebas.
class ServicioUbicacionFalso implements ServicioUbicacion {
  ServicioUbicacionFalso({
    this.resultado = const UbicacionObtenida(-1.2491, -78.6167),
    this.activo = true,
    this.demora,
  });

  ResultadoUbicacion resultado;
  bool activo;

  /// Simula un GPS lento, para comprobar que la emisión no se queda esperando.
  final Duration? demora;

  int llamadas = 0;

  @override
  Future<bool> servicioActivo() async => activo;

  @override
  Future<ResultadoUbicacion> obtener({
    Duration limite = const Duration(seconds: 5),
  }) async {
    llamadas++;

    if (!activo) return const ServicioDesactivado();

    if (demora != null) {
      if (demora! >= limite) return const UbicacionNoDisponible();
      await Future<void>.delayed(demora!);
    }

    return resultado;
  }
}
