import '../servicios/almacen_seguro.dart';

/// Acceso al par de tokens guardado en el almacén cifrado.
///
/// Existe como pieza propia para que los interceptores no dependan de `Sesion`:
/// `Sesion` es estado de aplicación con `ChangeNotifier` y conoce el perfil, la
/// navegación y el ciclo de vida. Un interceptor solo necesita dos cadenas.
///
/// Esa separación es lo que evita una dependencia circular: `Sesion` necesita
/// el cliente HTTP para pedir el perfil, y el cliente necesita las credenciales.
class Credenciales {
  const Credenciales(this._almacen);

  final AlmacenSeguro _almacen;

  static const claveAcceso = 'vecino_seguro.token';

  /// Token de renovación. Se guarda cifrado igual que el de acceso: con él se
  /// obtienen tokens de acceso nuevos durante 30 días, así que vale tanto como
  /// la contraseña.
  static const claveRenovacion = 'vecino_seguro.token_renovacion';

  Future<String?> tokenAcceso() => _almacen.leer(claveAcceso);

  Future<String?> tokenRenovacion() => _almacen.leer(claveRenovacion);

  Future<void> guardar({required String acceso, String? renovacion}) async {
    await _almacen.escribir(claveAcceso, acceso);
    if (renovacion != null) {
      await _almacen.escribir(claveRenovacion, renovacion);
    }
  }

  /// No borra por clave: delega en el borrado total del almacén, que es la
  /// regla establecida en la Semana 12 —"al cerrar sesión no queda nada"— y que
  /// no depende de recordar qué claves existen.
  Future<void> borrar() => _almacen.borrarTodo();
}
