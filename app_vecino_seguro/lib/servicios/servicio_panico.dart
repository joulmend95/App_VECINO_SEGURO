import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/entorno.dart';
import 'cliente_api.dart';

/// Puente con el servicio nativo del botón de pánico.
///
/// **Solo Android.** iOS no permite interceptar las teclas de volumen en
/// segundo plano: no es una limitación de esta implementación, sino del propio
/// sistema. En iOS la alternativa es un widget o un atajo de Siri, y
/// [disponible] devuelve `false` para que la interfaz lo explique en vez de
/// ofrecer una función que no va a funcionar.
///
/// ## Con la app cerrada
///
/// El servicio nativo emite la alerta por su cuenta, sin abrir la app, con una
/// **credencial de pánico** que el servidor solo acepta para eso. Esta clase la
/// pide y se la entrega al activar el gesto y cada vez que la app arranca o
/// vuelve a primer plano, y la borra al desactivarlo o cerrar sesión.
class ServicioPanico {
  ServicioPanico([this._api]);

  final ClienteApi? _api;

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
      final activado = await _metodos.invokeMethod<bool>('activar') ?? false;
      if (activado) await sincronizarCredencial();
      return activado;
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo activar: ${e.message}');
      return false;
    }
  }

  Future<bool> desactivar() async {
    if (!disponible) return false;
    try {
      await borrarCredencial();
      return await _metodos.invokeMethod<bool>('desactivar') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo desactivar: ${e.message}');
      return false;
    }
  }

  /// Pide al servidor una credencial de pánico nueva y se la entrega al
  /// servicio nativo, si el gesto está activo.
  ///
  /// Dura 30 días y se renueva en cada arranque y vuelta a primer plano, así
  /// que solo caduca si el vecino pasa un mes sin abrir la app. Si falla —sin
  /// red, vecino aún sin comunidad— se conserva la anterior; en el peor caso el
  /// servicio pide abrir la app para enviar la alerta.
  Future<void> sincronizarCredencial() async {
    final api = _api;
    if (!disponible || api == null) return;
    if (!await estaActivo()) return;
    try {
      final respuesta = await api.publicar('/api/alertas/panico/credencial');
      final credencial = respuesta['token_panico'];
      if (credencial is! String || credencial.isEmpty) return;
      await _metodos.invokeMethod('guardarCredencial', {
        'url_base': Entorno.urlBase,
        'credencial': credencial,
      });
    } on ExcepcionApi catch (e) {
      debugPrint('[PANICO] No se pudo renovar la credencial: ${e.mensaje}');
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo guardar la credencial: ${e.message}');
    }
  }

  /// Borra la credencial del servicio nativo: sin ella, el gesto ya no puede
  /// emitir nada por su cuenta.
  Future<void> borrarCredencial() async {
    if (!disponible) return;
    try {
      await _metodos.invokeMethod('borrarCredencial');
    } on PlatformException catch (e) {
      debugPrint('[PANICO] No se pudo borrar la credencial: ${e.message}');
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
