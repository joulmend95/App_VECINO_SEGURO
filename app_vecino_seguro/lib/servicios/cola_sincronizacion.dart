import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'almacen_local.dart';
import 'cliente_api.dart';
import 'servicio_alertas.dart';

/// Resultado de una pasada de sincronización.
class ResultadoSincronizacion {
  const ResultadoSincronizacion({
    this.enviadas = 0,
    this.reprogramadas = 0,
    this.descartadas = 0,
    this.agotadas = 0,
    this.sinConexion = false,
    this.ultimoError,
  });

  /// El fallo fue de red: el servidor no llegó a responder.
  ///
  /// Se distingue del resto porque es lo único que justifica decirle al vecino
  /// "se enviará cuando vuelvas a tener cobertura". Decírselo cuando el
  /// servidor **sí** respondió —con un 429 o un 500— sería mentirle.
  final bool sinConexion;

  /// Mensaje del último fallo, para poder mostrárselo tal cual.
  final String? ultimoError;

  /// Llegaron al servidor (202) o ya estaban allí de un intento previo (200).
  final int enviadas;

  /// Volverán a intentarse más tarde.
  final int reprogramadas;

  /// El servidor las rechazó por un motivo que no se arregla reintentando.
  final int descartadas;

  /// Consumieron el máximo de intentos y dejan de reintentarse.
  final int agotadas;

  bool get huboCambios =>
      enviadas > 0 || descartadas > 0 || agotadas > 0;
}

/// Cola de operaciones que el vecino hizo sin conexión.
///
/// **Por qué existe.** Una emergencia es exactamente el momento en que peor está
/// la conexión. Si el envío falla y no queda nada guardado, la petición de
/// auxilio se pierde para siempre y el vecino cree haberla enviado.
///
/// Sustituye a `ColaPanico`, que resolvía el mismo problema solo para el botón
/// de pánico y sin identificador de cliente, sin límite de intentos y decidiendo
/// si reencolar comparando el texto del mensaje de error.
/// Es un [ChangeNotifier] para que la interfaz pueda reaccionar cuando la cola
/// cambia por su cuenta. Sin esto, el muro se enteraba de que la alerta ya
/// había salido solo si el vecino refrescaba a mano: la red volvía, la alerta
/// se enviaba, y la pantalla seguía anunciando «1 alerta pendiente de envío».
class ColaSincronizacion extends ChangeNotifier {
  ColaSincronizacion({
    required this.almacen,
    required this.alertas,
    Uuid? generador,
  }) : _uuid = generador ?? const Uuid();

  final AlmacenLocal almacen;
  final ServicioAlertas alertas;
  final Uuid _uuid;

  /// Espera base de la progresión. Los reintentos van a 5, 10, 20, 40 y 80 s.
  ///
  /// Crece para no castigar a un servidor que ya está en apuros ni gastar
  /// batería insistiendo cada segundo contra una red que no está.
  static const esperaBase = Duration(seconds: 5);

  /// Tope de intentos fallidos antes de rendirse.
  ///
  /// Existe porque una cola que reintenta para siempre acaba siendo un bucle
  /// que consume batería y datos sin llegar nunca a nada.
  static const maximoIntentos = 5;

  /// Más allá de esto, reenviar una alerta ya no ayuda a nadie: llegaría a la
  /// comunidad horas después del suceso y solo generaría confusión.
  static const vigencia = Duration(minutes: 30);

  bool _drenando = false;

  /// Espera antes del intento número [intentos]: 5 s · 2^n.
  static Duration esperaTras(int intentos) =>
      esperaBase * (1 << intentos.clamp(0, maximoIntentos));

  // ---------------------------------------------------------------------------
  // ENCOLAR
  // ---------------------------------------------------------------------------

  /// Registra una alerta para enviarla, y devuelve su clave de cliente.
  ///
  /// **Se encola siempre, antes de intentar el envío.** No es un rodeo: si se
  /// enviara directo y el proceso muriera entre la petición y la respuesta, no
  /// quedaría ningún rastro de la emergencia. Encolar primero garantiza que lo
  /// peor que puede pasar es enviarla más tarde.
  /// Con [claveExistente] se **reencola la misma operación** en vez de crear
  /// otra. Es lo que impide que pulsar "Emitir" dos veces tras un error del
  /// servidor genere dos alertas: la clave se repite, y el servidor la reconoce.
  Future<String> encolarAlerta({
    String? tipoAlerta,
    String? descripcion,
    bool esPanico = false,
    double? latitud,
    double? longitud,
    String? claveExistente,
  }) async {
    // UUID v4 generado en el teléfono. Viaja con la petición, el servidor lo
    // guarda junto a la alerta y así un reintento devuelve la alerta existente
    // en lugar de crear un duplicado.
    final clave = claveExistente ?? _uuid.v4();
    final ahora = DateTime.now();

    await almacen.encolar(
      OperacionPendiente(
        claveCliente: clave,
        tipo: OperacionPendiente.tipoEmitirAlerta,
        carga: {
          'clave_cliente': clave,
          if (!esPanico) 'tipo_alerta': tipoAlerta,
          if (descripcion != null && descripcion.trim().isNotEmpty)
            'descripcion': descripcion.trim(),
          if (esPanico) 'es_panico': true,
          'latitud': ?latitud,
          'longitud': ?longitud,
        },
        creadaEn: ahora,
        // Lista de inmediato: el primer intento no espera.
        proximoIntentoEn: ahora,
      ),
    );

    return clave;
  }

  /// Operaciones que siguen esperando, de la más antigua a la más nueva.
  Future<List<OperacionPendiente>> pendientes() => almacen.leerCola();

  Future<bool> hayPendientes() async => (await almacen.leerCola()).isNotEmpty;

  // ---------------------------------------------------------------------------
  // DRENAR
  // ---------------------------------------------------------------------------

  /// Intenta enviar lo que toque.
  ///
  /// Se puede llamar sin miedo desde varios sitios a la vez —vuelta de la red,
  /// app en primer plano, inicio de sesión—: el cerrojo [_drenando] evita que
  /// dos pasadas simultáneas envíen la misma operación dos veces.
  Future<ResultadoSincronizacion> drenar() async {
    if (_drenando) return const ResultadoSincronizacion();
    _drenando = true;

    try {
      final ahora = DateTime.now();
      final listas = await almacen.operacionesListas(ahora);
      if (listas.isEmpty) return const ResultadoSincronizacion();

      var enviadas = 0, reprogramadas = 0, descartadas = 0, agotadas = 0;
      var sinConexion = false;
      String? ultimoError;

      for (final operacion in listas) {
        // Caducada: se descarta antes de gastar red en ella.
        if (ahora.difference(operacion.creadaEn) > vigencia) {
          await almacen.borrarOperacion(operacion.claveCliente);
          descartadas++;
          continue;
        }

        final (desenlace, error) = await _procesar(operacion);
        if (error != null) {
          ultimoError = error.mensaje;
          sinConexion = sinConexion || error.esSinConexion;
        }
        switch (desenlace) {
          case _Desenlace.enviada:
            enviadas++;
          case _Desenlace.reprogramada:
            reprogramadas++;
          case _Desenlace.descartada:
            descartadas++;
          case _Desenlace.agotada:
            agotadas++;
        }
      }

      if (enviadas > 0) {
        debugPrint('[COLA] $enviadas operaciones enviadas.');
      }

      final resultado = ResultadoSincronizacion(
        enviadas: enviadas,
        reprogramadas: reprogramadas,
        descartadas: descartadas,
        agotadas: agotadas,
        sinConexion: sinConexion,
        ultimoError: ultimoError,
      );

      // Solo cuando algo salió de la cola. Notificar en cada pasada haría que
      // el muro se recargara cada vez que un reintento falla por falta de red,
      // que es justo cuando no hay nada nuevo que mostrar.
      if (resultado.huboCambios) notifyListeners();

      return resultado;
    } finally {
      _drenando = false;
    }
  }

  Future<(_Desenlace, ExcepcionApi?)> _procesar(
    OperacionPendiente operacion,
  ) async {
    try {
      await alertas.emitirCrudo(operacion.carga);
      // 202 (nueva) y 200 (ya estaba) llegan aquí igual: en ambos casos el
      // servidor la tiene, que es lo único que decide si sale de la cola.
      await almacen.borrarOperacion(operacion.claveCliente);
      return (_Desenlace.enviada, null);
    } on ExcepcionApi catch (e) {
      return (await _clasificar(operacion, e), e);
    }
  }

  /// Decide qué hacer con una operación que falló.
  ///
  /// La distinción que importa: **no todo fallo gasta un intento**. El tope de
  /// intentos existe para dejar de insistir en algo que el servidor rechaza, no
  /// para castigar a quien lleva un rato en el metro.
  Future<_Desenlace> _clasificar(
    OperacionPendiente operacion,
    ExcepcionApi e,
  ) async {
    // Sin respuesta del servidor. No sabemos si llegó, y no ha rechazado nada:
    // se deja la operación intacta, sin gastar intento. Cinco minutos de túnel
    // no pueden agotar la cuota de reintentos de una emergencia.
    if (e.esSinConexion) {
      return _Desenlace.reprogramada;
    }

    // 429: el servidor pide esperar, no rechaza. Tampoco gasta intento —pero sí
    // se reprograma, o la siguiente pasada volvería a chocar con el límite.
    if (e.esLimiteDeFrecuencia) {
      await almacen.actualizarOperacion(
        operacion.copiarCon(
          proximoIntentoEn: DateTime.now().add(esperaTras(operacion.intentos)),
          ultimoError: e.mensaje,
        ),
      );
      return _Desenlace.reprogramada;
    }

    // La sesión dejó de valer. La operación se conserva tal cual: si el vecino
    // vuelve a ingresar, su alerta sigue ahí. `ClienteApi` ya cerró la sesión.
    if (e.exigeIngresar) {
      return _Desenlace.reprogramada;
    }

    // El servidor la rechazó por su contenido o por permisos. Reintentar dará
    // exactamente el mismo error, así que insistir solo alarga la cola.
    if (e.esDeAcceso || e.erroresPorCampo.isNotEmpty) {
      await almacen.borrarOperacion(operacion.claveCliente);
      debugPrint('[COLA] Descartada ${operacion.claveCliente}: ${e.mensaje}');
      return _Desenlace.descartada;
    }

    // Fallo del servidor (5xx) u otro error transitorio: este sí gasta intento.
    final intentos = operacion.intentos + 1;
    if (intentos >= maximoIntentos) {
      await almacen.actualizarOperacion(
        operacion.copiarCon(
          intentos: intentos,
          // Muy lejos en el futuro: deja de aparecer en `operacionesListas`,
          // pero la operación NO se borra. Sigue visible para el vecino, que es
          // quien tiene que enterarse de que su alerta no salió.
          proximoIntentoEn: DateTime.now().add(const Duration(days: 3650)),
          ultimoError: e.mensaje,
        ),
      );
      debugPrint('[COLA] Agotada ${operacion.claveCliente}: ${e.mensaje}');
      return _Desenlace.agotada;
    }

    await almacen.actualizarOperacion(
      operacion.copiarCon(
        intentos: intentos,
        proximoIntentoEn: DateTime.now().add(esperaTras(intentos)),
        ultimoError: e.mensaje,
      ),
    );
    return _Desenlace.reprogramada;
  }
}

enum _Desenlace { enviada, reprogramada, descartada, agotada }
