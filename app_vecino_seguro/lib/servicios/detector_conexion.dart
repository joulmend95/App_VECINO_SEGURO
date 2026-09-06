import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Estado de conexión del dispositivo.
///
/// **Advertencia deliberada en el nombre de los valores:** `hayInterfaz` no dice
/// «hay internet», dice «el sistema informa de una interfaz de red activa». El
/// wifi de una cafetería con portal cautivo, o un móvil con datos agotados,
/// aparecen como conectados y aun así ninguna petición llega. Por eso este
/// detector **nunca decide si una operación se intenta**: solo sirve como aviso
/// para reintentar antes. Quien dice la verdad sobre la conectividad sigue
/// siendo el resultado de la petición HTTP (`ExcepcionApi.esSinConexion`).
enum EstadoConexion { hayInterfaz, sinInterfaz }

/// Observa los cambios de conectividad del sistema.
///
/// Interfaz por el mismo motivo que [AlmacenLocal]: `connectivity_plus` usa
/// canales de plataforma que no existen en `flutter test`. Con la
/// implementación falsa, los escenarios de "vuelve la red" se prueban a mano y
/// de forma determinista, sin esperas ni temporizadores.
abstract interface class DetectorConexion {
  /// Emite cada vez que cambia el estado. No emite el estado inicial.
  Stream<EstadoConexion> get cambios;

  Future<EstadoConexion> estadoActual();

  void cerrar();
}

/// Implementación real sobre `connectivity_plus`.
class DetectorConexionReal implements DetectorConexion {
  DetectorConexionReal([Connectivity? conectividad])
    : _conectividad = conectividad ?? Connectivity();

  final Connectivity _conectividad;
  StreamSubscription<List<ConnectivityResult>>? _suscripcion;
  final _controlador = StreamController<EstadoConexion>.broadcast();

  EstadoConexion? _ultimo;

  /// Empieza a observar. Hay que llamarlo una vez al arrancar la app.
  void escuchar() {
    _suscripcion ??= _conectividad.onConnectivityChanged.listen(
      (resultados) {
        final estado = _interpretar(resultados);
        // Solo se notifican los cambios reales. El sistema emite varias veces
        // seguidas al alternar entre wifi y datos, y cada emisión dispararía un
        // drenado de la cola redundante.
        if (estado == _ultimo) return;
        _ultimo = estado;
        _controlador.add(estado);
      },
      onError: (Object e) => debugPrint('[RED] Error observando conexión: $e'),
    );
  }

  @override
  Stream<EstadoConexion> get cambios => _controlador.stream;

  @override
  Future<EstadoConexion> estadoActual() async {
    try {
      return _interpretar(await _conectividad.checkConnectivity());
    } catch (e) {
      // Si el plugin falla, se asume que hay red: dar por buena la conexión
      // hace que se intente la petición, y esa sí sabe la verdad. Asumir lo
      // contrario dejaría la app en modo offline sin motivo.
      debugPrint('[RED] No se pudo consultar la conexión: $e');
      return EstadoConexion.hayInterfaz;
    }
  }

  static EstadoConexion _interpretar(List<ConnectivityResult> resultados) {
    final sinRed =
        resultados.isEmpty ||
        resultados.every((r) => r == ConnectivityResult.none);
    return sinRed ? EstadoConexion.sinInterfaz : EstadoConexion.hayInterfaz;
  }

  @override
  void cerrar() {
    _suscripcion?.cancel();
    _suscripcion = null;
    _controlador.close();
  }
}

/// Detector controlado a mano, para pruebas.
class DetectorConexionFalso implements DetectorConexion {
  DetectorConexionFalso({EstadoConexion inicial = EstadoConexion.hayInterfaz})
    : _estado = inicial;

  final _controlador = StreamController<EstadoConexion>.broadcast();
  EstadoConexion _estado;

  /// Simula un cambio de conectividad.
  void emitir(EstadoConexion estado) {
    _estado = estado;
    _controlador.add(estado);
  }

  @override
  Stream<EstadoConexion> get cambios => _controlador.stream;

  @override
  Future<EstadoConexion> estadoActual() async => _estado;

  @override
  void cerrar() => _controlador.close();
}
