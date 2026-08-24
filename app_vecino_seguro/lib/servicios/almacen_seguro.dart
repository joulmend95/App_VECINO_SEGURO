import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacén de credenciales.
///
/// Es una abstracción y no una llamada directa a `FlutterSecureStorage` por dos
/// razones: en las pruebas los canales de plataforma no existen, y así se puede
/// sustituir la implementación sin tocar [Sesion].
abstract interface class AlmacenSeguro {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
}

/// Implementación real: Keystore en Android, Keychain en iOS.
///
/// Un JWT es una credencial de sesión: guardarlo en `shared_preferences` lo
/// dejaría en texto plano, legible por cualquier proceso con acceso al
/// almacenamiento de la app en un dispositivo comprometido.
class AlmacenSeguroReal implements AlmacenSeguro {
  const AlmacenSeguroReal([this._almacen = const FlutterSecureStorage()]);

  final FlutterSecureStorage _almacen;

  // Desde la versión 11 del paquete no hace falta activar el cifrado a mano:
  // en Android usa siempre almacenamiento cifrado, y la antigua opción
  // `encryptedSharedPreferences` desapareció.

  @override
  Future<String?> leer(String clave) => _almacen.read(key: clave);

  @override
  Future<void> escribir(String clave, String valor) =>
      _almacen.write(key: clave, value: valor);

  @override
  Future<void> borrar(String clave) => _almacen.delete(key: clave);
}

/// Implementación en memoria, para pruebas.
class AlmacenEnMemoria implements AlmacenSeguro {
  AlmacenEnMemoria([Map<String, String>? inicial])
    : _datos = {...?inicial};

  final Map<String, String> _datos;

  @override
  Future<String?> leer(String clave) async => _datos[clave];

  @override
  Future<void> escribir(String clave, String valor) async => _datos[clave] = valor;

  @override
  Future<void> borrar(String clave) async => _datos.remove(clave);
}
