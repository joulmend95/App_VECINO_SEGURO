import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'almacen_seguro.dart';
import 'cliente_api.dart';
import 'servicio_alertas.dart';

/// Alerta de pánico pendiente de enviar.
class PanicoPendiente {
  const PanicoPendiente({required this.momento, this.latitud, this.longitud});

  final DateTime momento;
  final double? latitud;
  final double? longitud;

  Map<String, dynamic> aJson() => {
    'momento': momento.toIso8601String(),
    if (latitud != null) 'latitud': latitud,
    if (longitud != null) 'longitud': longitud,
  };

  factory PanicoPendiente.desdeJson(Map<String, dynamic> j) => PanicoPendiente(
    momento: DateTime.tryParse(j['momento'] as String? ?? '') ?? DateTime.now(),
    latitud: (j['latitud'] as num?)?.toDouble(),
    longitud: (j['longitud'] as num?)?.toDouble(),
  );
}

/// Cola de alertas de pánico que no se pudieron enviar.
///
/// **Por qué existe:** una emergencia es exactamente el momento en que peor
/// está la conexión. Si el envío falla y no se guarda nada, la petición de
/// auxilio se pierde para siempre y el vecino cree haberla enviado.
///
/// La cola persiste entre reinicios de la aplicación y se vacía en cuanto hay
/// red. Es deliberadamente pequeña: solo importan los intentos recientes.
class ColaPanico {
  ColaPanico({required this.alertas, AlmacenSeguro? almacen})
    : _almacen = almacen ?? const AlmacenSeguroReal();

  static const _clave = 'vecino_seguro.panico_pendiente';

  /// Más allá de esto, una alerta vieja ya no ayuda a nadie: reenviarla horas
  /// después solo generaría confusión en la comunidad.
  static const _vigencia = Duration(minutes: 30);

  final ServicioAlertas alertas;
  final AlmacenSeguro _almacen;

  /// Guarda un intento fallido para reintentarlo más tarde.
  Future<void> encolar(PanicoPendiente panico) async {
    final pendientes = await _leer();
    pendientes.add(panico);

    // Se conservan como mucho 3: si hay más, es un gesto repetido por
    // desesperación y reenviarlos todos inundaría a la comunidad.
    final recortadas = pendientes.length > 3
        ? pendientes.sublist(pendientes.length - 3)
        : pendientes;

    await _almacen.escribir(
      _clave,
      jsonEncode(recortadas.map((p) => p.aJson()).toList()),
    );
  }

  /// Intenta enviar lo pendiente. Devuelve cuántas se enviaron.
  Future<int> reintentar() async {
    final pendientes = await _leer();
    if (pendientes.isEmpty) return 0;

    final ahora = DateTime.now();
    final vigentes = pendientes
        .where((p) => ahora.difference(p.momento) < _vigencia)
        .toList();

    var enviadas = 0;
    final fallidas = <PanicoPendiente>[];

    for (final p in vigentes) {
      try {
        await alertas.emitir(
          esPanico: true,
          latitud: p.latitud,
          longitud: p.longitud,
        );
        enviadas++;
      } on ExcepcionApi catch (e) {
        // Un 429 significa que el servidor ya recibió una alerta reciente de
        // este vecino: la emergencia está registrada, así que se descarta en
        // vez de insistir.
        if (e.mensaje.contains('Espera')) continue;
        fallidas.add(p);
      }
    }

    await _guardar(fallidas);

    if (enviadas > 0) {
      debugPrint('[PANICO] Se enviaron $enviadas alertas pendientes.');
    }
    return enviadas;
  }

  Future<bool> hayPendientes() async => (await _leer()).isNotEmpty;

  Future<void> limpiar() => _almacen.borrar(_clave);

  Future<List<PanicoPendiente>> _leer() async {
    try {
      final crudo = await _almacen.leer(_clave);
      if (crudo == null || crudo.isEmpty) return [];

      final lista = jsonDecode(crudo);
      if (lista is! List) return [];

      return lista
          .whereType<Map<String, dynamic>>()
          .map(PanicoPendiente.desdeJson)
          .toList();
    } catch (e) {
      // Datos corruptos: se descartan en lugar de dejar la cola inutilizable.
      debugPrint('[PANICO] Cola ilegible, se descarta: $e');
      await limpiar();
      return [];
    }
  }

  Future<void> _guardar(List<PanicoPendiente> pendientes) async {
    if (pendientes.isEmpty) {
      await limpiar();
      return;
    }
    await _almacen.escribir(
      _clave,
      jsonEncode(pendientes.map((p) => p.aJson()).toList()),
    );
  }
}
