import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puente con el servicio nativo del botón de pánico.
///
/// **Solo Android.** iOS no permite interceptar las teclas de volumen en
/// segundo plano: no es una limitación de esta implementación, sino del propio
/// sistema. En iOS la alternativa es un widget o un atajo de Siri, y
/// [disponible] devuelve `false` para que la interfaz lo explique en vez de
/// ofrecer una función que no va a funcionar.
class ServicioPanico {
  ServicioPanico();

  static const _metodos = MethodChannel('vecinoseguro/panico');
  static const _eventos = EventChannel('vecinoseguro/panico/eventos');

  StreamSubscription<dynamic>? _suscripcion;

  /// Se emite cuando el vecino completa el gesto de pánico.
  final _gestos = StreamController<void>.broadcast();
  Stream<void> get gestos => _gestos.stream;

  /// `true` solo en Android.
  bool get disponible => !kIsWeb && Platform.isAndroid;

  /// Empieza a escuchar los gestos detectados por el servicio nativo.
  void escuchar() {
    if (!disponible || _suscripcion != null) return;

    _suscripcion = _eventos.receiveBroadcastStream().listen(
      (evento) {
        if (evento == 'gesto') _gestos.add(null);
      },
      onError: (Object e) => debugPrint('[PANICO] Error en el canal: $e'),
    );
  }

  /// Activa el servicio en primer plano.
  ///
  /// Devuelve `false` si no se pudo: el gesto no quedará activo y la interfaz
  /// debe decirlo, en vez de dar por hecho que funciona.
  Future<bool> activar() async {
    if (!disponible) return false;
    try {
      return await _metodos.invokeMethod<bool>('activar') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo activar: ${e.message}');
      return false;
    }
  }

  Future<bool> desactivar() async {
    if (!disponible) return false;
    try {
      return await _metodos.invokeMethod<bool>('desactivar') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo desactivar: ${e.message}');
      return false;
    }
  }

  Future<bool> estaActivo() async {
    if (!disponible) return false;
    try {
      return await _metodos.invokeMethod<bool>('estaActivo') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// `true` si el ahorro de batería puede matar el servicio.
  ///
  /// Es la causa más común de que el gesto deje de funcionar sin que el vecino
  /// se entere, así que conviene detectarlo y avisar.
  Future<bool> bateriaOptimizada() async {
    if (!disponible) return false;
    try {
      return await _metodos.invokeMethod<bool>('bateriaOptimizada') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> pedirExencionBateria() async {
    if (!disponible) return;
    try {
      await _metodos.invokeMethod('pedirExencionBateria');
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo pedir la exención: ${e.message}');
    }
  }

  void cerrar() {
    _suscripcion?.cancel();
    _suscripcion = null;
    _gestos.close();
  }
}
