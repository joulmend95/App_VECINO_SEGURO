import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'servicio_notificaciones.dart';

/// Gestión de notificaciones push.
///
/// Responsabilidades:
/// - Pedir permiso (obligatorio desde Android 13).
/// - Registrar el token FCM en el backend, y mantenerlo al día cuando Firebase
///   lo renueva.
/// - Crear dos canales de Android: uno normal y uno de **pánico** de máxima
///   prioridad, que suena aunque el teléfono esté en silencio.
/// - Mostrar el aviso cuando la app está en primer plano (en ese caso Android
///   no lo muestra solo).
///
/// **Nunca lanza.** Un fallo de Firebase —sin permiso, sin Google Play
/// Services, sin red— no debe impedir usar la aplicación: las alertas se siguen
/// viendo en el muro y en la bandeja. El push es una comodidad, no la vía única.
class ServicioPush {
  ServicioPush(this._notificaciones);

  final ServicioNotificaciones _notificaciones;

  final _locales = FlutterLocalNotificationsPlugin();

  String? _tokenActual;
  bool _iniciado = false;

  /// Canal de alertas normales.
  static const _canalAlertas = AndroidNotificationChannel(
    'alertas',
    'Alertas de la comunidad',
    description: 'Avisos cuando un vecino reporta una alerta.',
    importance: Importance.high,
  );

  /// Canal de emergencia.
  ///
  /// `Importance.max` y sonido propio: una emergencia debe interrumpir. Se
  /// separa del canal normal para que el vecino pueda silenciar las alertas de
  /// convivencia **sin** silenciar las de pánico.
  static const _canalPanico = AndroidNotificationChannel(
    'panico',
    'Emergencias',
    description: 'Botón de pánico activado por un vecino.',
    importance: Importance.max,
    enableVibration: true,
  );

  /// Prepara los canales, pide permiso y registra el token.
  ///
  /// Se llama tras iniciar sesión: antes no habría a qué cuenta asociar el
  /// dispositivo.
  Future<void> iniciar() async {
    if (_iniciado) {
      await _registrarToken();
      return;
    }

    try {
      // Los canales SÍ se crean aquí, antes de cualquier notificación: sin
      // canal, Android descarta el aviso en silencio.
      await _crearCanales();

      // El PERMISO ya no se pide aquí. Antes se solicitaba al iniciar sesión,
      // que no es «el momento en que la funcionalidad se va a usar»: el vecino
      // recibía un diálogo del sistema sin contexto, mientras esperaba a que
      // cargara su muro. Ahora lo ofrece el propio muro, con una explicación
      // delante — ver `TarjetaAvisos` en la pantalla del muro.

      FirebaseMessaging.onMessage.listen(_mostrarEnPrimerPlano);

      // Firebase renueva el token periódicamente. Sin escuchar este evento, el
      // teléfono dejaría de recibir avisos en silencio, sin ningún síntoma.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _tokenActual = token;
        _enviarTokenAlBackend(token);
      });

      _iniciado = true;
      await _registrarToken();
    } catch (e) {
      debugPrint('[PUSH] No se pudo iniciar: $e');
    }
  }

  /// Da de baja el dispositivo al cerrar sesión.
  Future<void> detener() async {
    final token = _tokenActual;
    if (token == null) return;

    try {
      await _notificaciones.eliminarDispositivo(token);
    } catch (e) {
      // Si el backend no responde, no se bloquea el cierre de sesión: cerrar
      // sesión debe funcionar siempre, incluso sin red.
      debugPrint('[PUSH] No se pudo dar de baja el dispositivo: $e');
    }
  }

  Future<void> _crearCanales() async {
    if (kIsWeb || !Platform.isAndroid) return;

    const ajustesAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _locales.initialize(
      settings: const InitializationSettings(android: ajustesAndroid),
    );

    final plugin = _locales
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await plugin?.createNotificationChannel(_canalAlertas);
    await plugin?.createNotificationChannel(_canalPanico);
  }

  /// Vuelve a registrar el token en el servidor.
  ///
  /// Se llama al volver la app a primer plano. En iOS el token solo existe
  /// **después** de que se autoricen las notificaciones, así que un vecino que
  /// las concede desde los ajustes del sistema no tendría token hasta que algo
  /// lo pidiera de nuevo: sin esto, habría concedido el permiso y seguiría sin
  /// recibir avisos, sin ningún síntoma que lo explicara.
  Future<void> revalidar() async {
    if (!_iniciado) return;
    await _registrarToken();
  }

  Future<void> _registrarToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      _tokenActual = token;
      await _enviarTokenAlBackend(token);
    } catch (e) {
      debugPrint('[PUSH] No se pudo obtener el token: $e');
    }
  }

  Future<void> _enviarTokenAlBackend(String token) async {
    try {
      await _notificaciones.registrarDispositivo(
        tokenPush: token,
        plataforma: kIsWeb
            ? 'web'
            : Platform.isAndroid
            ? 'android'
            : Platform.isIOS
            ? 'ios'
            : 'otra',
      );
    } catch (e) {
      debugPrint('[PUSH] No se pudo registrar el dispositivo: $e');
    }
  }

  /// Con la app abierta, Android no muestra el aviso por su cuenta.
  ///
  /// Se muestra a mano para que una emergencia no pase desapercibida solo
  /// porque el vecino tenía la app en pantalla.
  Future<void> _mostrarEnPrimerPlano(RemoteMessage mensaje) async {
    final aviso = mensaje.notification;
    if (aviso == null) return;

    final esPanico = mensaje.data['es_panico'] == 'true';
    final canal = esPanico ? _canalPanico : _canalAlertas;

    await _locales.show(
      id: mensaje.hashCode,
      title: aviso.title,
      body: aviso.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          canal.id,
          canal.name,
          channelDescription: canal.description,
          importance: canal.importance,
          priority: esPanico ? Priority.max : Priority.defaultPriority,
        ),
      ),
    );
  }
}
