import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'modelos/perfil_vecino.dart';
import 'navegacion/rutas.dart';
import 'servicios/dependencias.dart';
import 'screens/pantalla_cuenta_atras.dart';
import 'servicios/cola_panico.dart';
import 'servicios/push.dart';
import 'servicios/sesion.dart';
import 'theme/tema_app.dart';

/// Manejador de avisos con la app cerrada o en segundo plano.
///
/// Debe ser una función de nivel superior con `@pragma('vm:entry-point')`:
/// Android la ejecuta en un aislado (*isolate*) separado, sin acceso al estado
/// de la aplicación. Sin la anotación, el compilador la eliminaría en release
/// y los avisos dejarían de procesarse justo en la versión que usan los
/// vecinos.
@pragma('vm:entry-point')
Future<void> manejarAvisoEnSegundoPlano(RemoteMessage mensaje) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[PUSH] Aviso en segundo plano: ${mensaje.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Si Firebase falla al iniciar, la app arranca igual: las alertas se siguen
  // viendo en el muro y en la bandeja. El push es una comodidad, no la vía
  // única de enterarse.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(manejarAvisoEnSegundoPlano);
  } catch (e) {
    debugPrint('[PUSH] Firebase no disponible: $e');
  }

  runApp(const VecinoSeguroApp());
}

class VecinoSeguroApp extends StatefulWidget {
  const VecinoSeguroApp({super.key});

  @override
  State<VecinoSeguroApp> createState() => _VecinoSeguroAppState();
}

class _VecinoSeguroAppState extends State<VecinoSeguroApp> {
  late final Sesion _sesion;
  late final Servicios _servicios;
  late final GoRouter _enrutador;

  @override
  void initState() {
    super.initState();

    // Una sola sesión y un solo cliente HTTP para toda la app. Si cada pantalla
    // creara los suyos, cada una tendría su propio token y el cierre automático
    // ante un 401 solo afectaría a una.
    _sesion = Sesion();
    _servicios = Servicios(sesion: _sesion);

    // El enrutador escucha la sesión: iniciar sesión, cerrarla o ser aprobado
    // por el administrador redirigen solos.
    _enrutador = construirEnrutador(_sesion);

    // El push sigue el ciclo de vida de la sesión: se registra el dispositivo
    // al autenticarse y se da de baja al cerrar sesión. Sin la baja, el
    // teléfono seguiría recibiendo alertas de una comunidad ajena.
    _push = ServicioPush(_servicios.notificaciones);
    _sesion.addListener(_sincronizarPush);

    // El gesto de pánico solo se escucha con sesión iniciada: sin saber a qué
    // comunidad pertenece el vecino, la alerta no tendría destinatarios.
    _servicios.panico.escuchar();
    _gestos = _servicios.panico.gestos.listen((_) => _alDetectarPanico());
  }

  late final ServicioPush _push;
  StreamSubscription<void>? _gestos;
  bool _pushActivo = false;
  bool _mostrandoCuentaAtras = false;

  void _sincronizarPush() {
    if (_sesion.autenticado && !_pushActivo) {
      _pushActivo = true;
      _push.iniciar();
      // Al recuperar la sesión se reintenta lo que quedó sin enviar por falta
      // de red: una petición de auxilio no debe perderse.
      ColaPanico(alertas: _servicios.alertas).reintentar();
    } else if (!_sesion.autenticado && _pushActivo) {
      _pushActivo = false;
      _push.detener();
    }
  }

  /// Muestra la cuenta atrás cuando el servicio nativo detecta el gesto.
  void _alDetectarPanico() {
    // Sin sesión o sin comunidad aprobada no hay a quién avisar. Se ignora en
    // silencio en vez de mostrar un error: el vecino no eligió abrir esto.
    if (!_sesion.autenticado || !_sesion.membresia.esActiva) return;

    // Evita apilar varias cuentas atrás si el gesto se repite.
    if (_mostrandoCuentaAtras) return;

    final contexto = _enrutador.routerDelegate.navigatorKey.currentContext;
    if (contexto == null) return;

    _mostrandoCuentaAtras = true;
    PantallaCuentaAtras.mostrar(
      contexto,
    ).whenComplete(() => _mostrandoCuentaAtras = false);
  }

  @override
  void dispose() {
    _gestos?.cancel();
    _sesion.removeListener(_sincronizarPush);
    _servicios.cerrar();
    _sesion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dependencias(
      servicios: _servicios,
      child: ListenableBuilder(
        // Reconstruye cuando cambia la sesión, para que las pantallas lean el
        // perfil actualizado (nombre de la comunidad, rol de administrador).
        listenable: _sesion,
        builder: (context, _) => MaterialApp.router(
          title: 'Vecino Seguro',
          debugShowCheckedModeBanner: false,

          // Los tokens del sistema de diseño se inyectan una sola vez y quedan
          // disponibles en todo el árbol vía `context.tokens`.
          theme: TemaApp.claro,
          darkTheme: TemaApp.oscuro,
          themeMode: ThemeMode.system,

          routerConfig: _enrutador,
        ),
      ),
    );
  }
}
