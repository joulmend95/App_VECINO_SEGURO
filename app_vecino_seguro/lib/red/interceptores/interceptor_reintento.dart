import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Reintenta peticiones **idempotentes** con espera creciente.
///
/// ## Qué se reintenta y qué no
///
/// Solo `GET`. Pedir dos veces la misma lista devuelve la misma lista: repetir
/// no cambia nada en el servidor. Eso es lo que significa *idempotente*, y es
/// la única condición bajo la cual un reintento automático es seguro.
///
/// **`POST` no se reintenta aquí, nunca.** En esta aplicación un `POST` emite
/// una alerta a toda la comunidad: reintentarlo a ciegas convertiría una
/// emergencia en tres avisos, y los vecinos aprenderían a ignorarlos. El
/// reintento de las emisiones vive en `ColaSincronizacion`, y allí **sí** es
/// seguro porque cada operación lleva una `clave_cliente` que el servidor
/// reconoce: la segunda llegada devuelve la alerta ya creada en lugar de crear
/// otra.
///
/// `PATCH` y `DELETE` tampoco se reintentan. Son idempotentes en teoría, pero
/// los de este proyecto —cambiar contraseña, expulsar a un vecino, resolver una
/// solicitud— tienen efectos que conviene no repetir sin que nadie lo pida.
///
/// ## Qué fallos merecen reintento
///
/// Solo los **transitorios**: sin respuesta del servidor o un 5xx. Un 404 o un
/// 422 darán exactamente el mismo resultado la segunda vez; insistir solo
/// gastaría batería y datos del vecino.
class InterceptorReintento extends Interceptor {
  InterceptorReintento({
    this.maximoIntentos = 2,
    this.esperaBase = const Duration(milliseconds: 400),
  });

  /// Reintentos **además** del intento original.
  ///
  /// Dos, no cinco: esto ocurre mientras el vecino mira una pantalla en blanco.
  /// Una cadena larga de reintentos convierte un fallo rápido en una espera
  /// interminable sin explicación. Lo que necesita más insistencia —una alerta
  /// encolada— ya la tiene en la cola, y allí sí puede esperar minutos porque
  /// nadie está mirando.
  final int maximoIntentos;

  /// Primera espera. Crece al doble en cada intento: 400 ms, 800 ms.
  final Duration esperaBase;

  static const _claveIntentos = 'intentos_de_reintento';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_mereceReintento(err)) return handler.next(err);

    final peticion = err.requestOptions;
    final hechos = (peticion.extra[_claveIntentos] as int?) ?? 0;

    if (hechos >= maximoIntentos) {
      debugPrint('[REINTENTO] Agotados los $maximoIntentos reintentos de ${peticion.path}');
      return handler.next(err);
    }

    final espera = esperaBase * (1 << hechos);
    debugPrint(
      '[REINTENTO] ${peticion.path} en ${espera.inMilliseconds} ms '
      '(intento ${hechos + 1} de $maximoIntentos)',
    );
    await Future<void>.delayed(espera);

    peticion.extra[_claveIntentos] = hechos + 1;

    try {
      // Por el mismo `Dio`: a diferencia de la renovación, este interceptor no
      // es encolado, así que reentrar en la cadena no produce bloqueo. El
      // contador en `extra` es lo que impide que el ciclo se repita sin fin.
      return handler.resolve(await _cliente!.fetch(peticion));
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// El cliente sobre el que reintentar. Lo inyecta [construirCliente] tras
  /// crear el `Dio`, porque el interceptor no puede recibirlo en el constructor
  /// sin crear una referencia circular.
  Dio? _cliente;


  void usarCliente(Dio dio) => _cliente = dio;

  /// Solo métodos sin efectos secundarios, y solo fallos transitorios.
  bool _mereceReintento(DioException err) {
    if (_cliente == null) return false;
    if (err.requestOptions.method.toUpperCase() != 'GET') return false;

    // La cancelación no se reintenta: el vecino se fue de la pantalla.
    if (err.type == DioExceptionType.cancel) return false;

    final codigo = err.response?.statusCode;

    // Sin respuesta: un tropiezo de red puede resolverse solo.
    if (codigo == null) return true;

    // 5xx: el servidor falló, y puede recuperarse. Los 4xx no: darían el mismo
    // resultado la segunda vez.
    return codigo >= 500;
  }
}
