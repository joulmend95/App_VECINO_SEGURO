import 'package:go_router/go_router.dart';

import '../modelos/perfil_vecino.dart';
import '../screens/pantalla_ajustes_panico.dart';
import '../screens/pantalla_arranque.dart';
import '../screens/pantalla_crear_comunidad.dart';
import '../screens/pantalla_detalle_alerta.dart';
import '../screens/pantalla_elegir_comunidad.dart';
import '../screens/pantalla_emitir_alerta.dart';
import '../screens/pantalla_esperando_aprobacion.dart';
import '../screens/pantalla_ingreso.dart';
import '../screens/pantalla_registro.dart';
import '../screens/pantalla_sin_permiso.dart';
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
  static const sinPermiso = '/sin-permiso';

  /// Segmento del detalle, relativo a [alertas]. El patrón completo es
  /// `/alertas/:idAlerta`; para navegar se usa [aDetalleAlerta].
  static const segmentoDetalleAlerta = ':idAlerta';

  /// Nombre del parámetro de consulta que recuerda a dónde iba el vecino.
  static const paramDestino = 'destino';

  /// Rutas accesibles sin haber iniciado sesión.
  static const publicas = {ingreso, registro};

  /// Rutas válidas mientras el vecino aún no pertenece a ninguna comunidad.
  static const sinComunidad = {elegirComunidad, crearComunidad, unirmeComunidad};

  /// Dirección del detalle de una alerta concreta.
  ///
  /// Se construye aquí y no en cada pantalla para que el formato de la ruta
  /// viva en un solo sitio: si mañana pasa a `/alertas/detalle/42`, cambia una
  /// línea y no siete llamadas repartidas por la app.
  static String aDetalleAlerta(int idAlerta) => '$alertas/$idAlerta';

  /// Dirección del ingreso que recuerda [destino] para volver allí después.
  static String ingresoCon({required String destino}) =>
      '$ingreso?$paramDestino=${Uri.encodeComponent(destino)}';

  /// Todas las direcciones fijas declaradas, para validar un destino guardado.
  static const _fijas = {
    arranque,
    ingreso,
    registro,
    elegirComunidad,
    crearComunidad,
    unirmeComunidad,
    esperandoAprobacion,
    solicitudes,
    alertas,
    emitirAlerta,
    notificaciones,
    ajustesPanico,
    perfil,
    miembros,
    sinPermiso,
  };

  static final _reDetalleAlerta = RegExp(r'^/alertas/\d+$');

  /// ¿[ruta] corresponde a alguna ruta declarada?
  ///
  /// Se usa para no reenviar al vecino a una dirección inventada: el destino
  /// guardado viene de una URL y no se puede dar por buena sin comprobarla.
  static bool existe(String ruta) =>
      _fijas.contains(ruta) || _reDetalleAlerta.hasMatch(ruta);
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
    redirect: (context, estado) => _redirigir(sesion, estado),
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
          // 'emitir' va ANTES del parámetro: `go_router` evalúa las rutas hijas
          // en orden, y si `:idAlerta` fuese primero se tragaría `/alertas/emitir`
          // con idAlerta = "emitir".
          GoRoute(
            path: 'emitir',
            builder: (_, _) => const PantallaEmitirAlerta(),
          ),
          GoRoute(
            path: Rutas.segmentoDetalleAlerta,
            builder: (_, estado) => PantallaDetalleAlerta(
              // Un parámetro no numérico degrada a 0, y la pantalla lo trata
              // como dirección inválida sin llegar a consultar la red.
              idAlerta: int.tryParse(estado.pathParameters['idAlerta'] ?? '') ?? 0,
            ),
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
      GoRoute(
        path: Rutas.sinPermiso,
        builder: (_, _) => const PantallaSinPermiso(),
      ),
    ],
  );
}

/// Decide a dónde debe estar el usuario según su estado de sesión.
///
/// Devuelve `null` cuando la ruta actual es válida: `go_router` interpreta eso
/// como "quédate donde estás".
String? _redirigir(Sesion sesion, GoRouterState estado) {
  final destino = estado.matchedLocation;

  // 1. Todavía no se sabe si hay sesión guardada: la pantalla de arranque lo
  //    resuelve. Redirigir antes provocaría un parpadeo del ingreso en cada
  //    apertura de la app, incluso con sesión válida.
  if (sesion.fase == FaseSesion.iniciando) {
    return destino == Rutas.arranque ? null : Rutas.arranque;
  }

  // 2. Sin sesión: solo las rutas públicas.
  if (!sesion.autenticado) {
    if (Rutas.publicas.contains(destino)) return null;

    // Se recuerda a dónde iba. Sin esto, quien abre una notificación con la
    // sesión caducada aterriza en el muro tras ingresar y tiene que volver a
    // buscar la alerta que le acababa de llegar.
    //
    // El arranque no se guarda: no es un destino, es el paso previo a decidir.
    if (destino == Rutas.arranque) return Rutas.ingreso;
    return Rutas.ingresoCon(destino: estado.uri.toString());
  }

  // 3. Autenticado y viniendo del ingreso: si hay un destino guardado y sigue
  //    siendo alcanzable, se le devuelve ahí en lugar de al muro.
  if (destino == Rutas.ingreso) {
    final pretendido = estado.uri.queryParameters[Rutas.paramDestino];
    if (pretendido != null && _esAlcanzable(pretendido, sesion.membresia)) {
      return pretendido;
    }
  }

  // 4. El estado de pertenencia decide qué puede ver.
  return _correccionPorMembresia(sesion.membresia, destino);
}

/// Corrección que impone el estado de pertenencia. `null` ⇒ el destino es válido.
///
/// Se extrajo de [_redirigir] porque [_esAlcanzable] necesita hacerse la misma
/// pregunta sobre un destino guardado. Duplicar las reglas sería la forma más
/// segura de que las dos copias divergieran.
String? _correccionPorMembresia(EstadoMembresia membresia, String destino) {
  switch (membresia) {
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

/// ¿Se puede enviar al vecino al destino que había guardado?
///
/// Tres motivos para no hacerlo, y los tres provocarían un bucle de
/// redirección si no se comprobaran aquí:
///
/// 1. La dirección no corresponde a ninguna ruta declarada (venía manipulada).
/// 2. Es una ruta pública o el arranque: reabriría el ciclo del que salimos.
/// 3. Su membresía actual no la permite. Es el caso realista: guardó
///    `/comunidad/solicitudes` siendo administrador, y para cuando vuelve a
///    ingresar ya no lo es.
///
/// En cualquiera de los tres se devuelve `false` y la guardia cae al muro.
bool _esAlcanzable(String pretendido, EstadoMembresia membresia) {
  final ruta = Uri.tryParse(pretendido)?.path;
  if (ruta == null || ruta.isEmpty) return false;
  if (!Rutas.existe(ruta)) return false;
  if (Rutas.publicas.contains(ruta) || ruta == Rutas.arranque) return false;

  return _correccionPorMembresia(membresia, ruta) == null;
}
