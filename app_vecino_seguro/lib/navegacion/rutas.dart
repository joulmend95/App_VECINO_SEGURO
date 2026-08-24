import 'package:go_router/go_router.dart';

import '../modelos/perfil_vecino.dart';
import '../screens/pantalla_ajustes_panico.dart';
import '../screens/pantalla_arranque.dart';
import '../screens/pantalla_crear_comunidad.dart';
import '../screens/pantalla_elegir_comunidad.dart';
import '../screens/pantalla_emitir_alerta.dart';
import '../screens/pantalla_esperando_aprobacion.dart';
import '../screens/pantalla_ingreso.dart';
import '../screens/pantalla_registro.dart';
import '../screens/pantalla_solicitudes.dart';
import '../screens/pantalla_unirme_comunidad.dart';
import '../screens/pantalla_miembros.dart';
import '../screens/pantalla_muro_alertas.dart';
import '../screens/pantalla_notificaciones.dart';
import '../screens/pantalla_perfil.dart';
import '../servicios/sesion.dart';

/// Rutas de la aplicación.
///
/// Se centralizan como constantes para que ningún widget escriba una ruta a
/// mano: un literal mal tecleado se convierte en un error de compilación.
abstract final class Rutas {
  static const arranque = '/';
  static const ingreso = '/ingreso';
  static const registro = '/registro';

  static const elegirComunidad = '/comunidad/elegir';
  static const crearComunidad = '/comunidad/crear';
  static const unirmeComunidad = '/comunidad/unirme';
  static const esperandoAprobacion = '/comunidad/esperando';
  static const solicitudes = '/comunidad/solicitudes';

  static const alertas = '/alertas';
  static const emitirAlerta = '/alertas/emitir';
  static const notificaciones = '/notificaciones';
  static const ajustesPanico = '/ajustes/panico';
  static const perfil = '/perfil';
  static const miembros = '/comunidad/miembros';

  /// Rutas accesibles sin haber iniciado sesión.
  static const publicas = {ingreso, registro};

  /// Rutas válidas mientras el vecino aún no pertenece a ninguna comunidad.
  static const sinComunidad = {elegirComunidad, crearComunidad, unirmeComunidad};
}

/// Construye el enrutador con las guardias de acceso.
///
/// `refreshListenable: sesion` es la pieza clave: cada vez que la sesión cambia
/// —ingresar, cerrar sesión, ser aprobado por el administrador— `go_router`
/// reevalúa [_redirigir] y navega solo. Ninguna pantalla llama a `Navigator`
/// para esto, así que es imposible que una se olvide y deje al vecino atrapado.
GoRouter construirEnrutador(Sesion sesion) {
  return GoRouter(
    initialLocation: Rutas.arranque,
    refreshListenable: sesion,
    redirect: (context, estado) => _redirigir(sesion, estado.matchedLocation),
    routes: [
      GoRoute(
        path: Rutas.arranque,
        builder: (_, _) => const PantallaArranque(),
      ),

      // --- Autenticación ---
      GoRoute(
        path: Rutas.ingreso,
        builder: (_, _) => const PantallaIngreso(),
      ),
      GoRoute(
        path: Rutas.registro,
        builder: (_, _) => const PantallaRegistro(),
      ),

      // --- Comunidad ---
      GoRoute(
        path: Rutas.elegirComunidad,
        builder: (_, _) => const PantallaElegirComunidad(),
      ),
      GoRoute(
        path: Rutas.crearComunidad,
        builder: (_, _) => const PantallaCrearComunidad(),
      ),
      GoRoute(
        path: Rutas.unirmeComunidad,
        builder: (_, _) => const PantallaUnirmeComunidad(),
      ),
      GoRoute(
        path: Rutas.esperandoAprobacion,
        builder: (_, _) => const PantallaEsperandoAprobacion(),
      ),
      GoRoute(
        path: Rutas.solicitudes,
        builder: (_, _) => const PantallaSolicitudes(),
      ),

      // --- Alertas ---
      GoRoute(
        path: Rutas.alertas,
        builder: (_, _) => const PantallaMuroAlertas(),
        routes: [
          GoRoute(
            path: 'emitir',
            builder: (_, _) => const PantallaEmitirAlerta(),
          ),
        ],
      ),
      GoRoute(
        path: Rutas.notificaciones,
        builder: (_, _) => const PantallaNotificaciones(),
      ),
      GoRoute(
        path: Rutas.ajustesPanico,
        builder: (_, _) => const PantallaAjustesPanico(),
      ),
      GoRoute(
        path: Rutas.perfil,
        builder: (_, _) => const PantallaPerfil(),
      ),
      GoRoute(
        path: Rutas.miembros,
        builder: (_, _) => const PantallaMiembros(),
      ),
    ],
  );
}

/// Decide a dónde debe estar el usuario según su estado de sesión.
///
/// Devuelve `null` cuando la ruta actual es válida: `go_router` interpreta eso
/// como "quédate donde estás".
String? _redirigir(Sesion sesion, String destino) {
  // 1. Todavía no se sabe si hay sesión guardada: la pantalla de arranque lo
  //    resuelve. Redirigir antes provocaría un parpadeo del ingreso en cada
  //    apertura de la app, incluso con sesión válida.
  if (sesion.fase == FaseSesion.iniciando) {
    return destino == Rutas.arranque ? null : Rutas.arranque;
  }

  // 2. Sin sesión: solo las rutas públicas.
  if (!sesion.autenticado) {
    return Rutas.publicas.contains(destino) ? null : Rutas.ingreso;
  }

  // 3. Autenticado. El estado de pertenencia decide qué puede ver.
  switch (sesion.membresia) {
    case EstadoMembresia.sinComunidad:
      return Rutas.sinComunidad.contains(destino) ? null : Rutas.elegirComunidad;

    case EstadoMembresia.pendiente:
      // Puede volver a elegir si se cansa de esperar o se equivocó de código.
      const permitidas = {Rutas.esperandoAprobacion, Rutas.elegirComunidad};
      return permitidas.contains(destino) ? null : Rutas.esperandoAprobacion;

    case EstadoMembresia.activo:
      // Ya no tiene sentido volver al ingreso ni a elegir comunidad.
      final rutaSuperada =
          Rutas.publicas.contains(destino) ||
          Rutas.sinComunidad.contains(destino) ||
          destino == Rutas.esperandoAprobacion ||
          destino == Rutas.arranque;
      return rutaSuperada ? Rutas.alertas : null;
  }
}
