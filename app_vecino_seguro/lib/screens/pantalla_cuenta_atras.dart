import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servicios/cliente_api.dart';
import '../servicios/cola_panico.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';

/// Cuenta atrás del botón de pánico.
///
/// Aparece cuando se detecta el gesto y da unos segundos para cancelar.
///
/// **Por qué la cuenta atrás no es opcional:** el gesto se dispara con tres
/// pulsaciones de volumen, algo que puede ocurrir por accidente en un bolsillo.
/// Sin margen para cancelar, los falsos positivos alarmarían a toda la
/// comunidad una y otra vez, y los vecinos acabarían ignorando las alertas
/// reales. Un botón de pánico en el que nadie confía no sirve de nada.
///
/// **Por qué es corta:** en una emergencia real, cada segundo cuenta. Tres
/// segundos bastan para reaccionar a un accidente sin retrasar de forma
/// apreciable una petición de auxilio legítima.
class PantallaCuentaAtras extends StatefulWidget {
  const PantallaCuentaAtras({super.key, this.segundos = 3});

  final int segundos;

  /// Muestra la cuenta atrás a pantalla completa.
  static Future<void> mostrar(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PantallaCuentaAtras(),
      ),
    );
  }

  @override
  State<PantallaCuentaAtras> createState() => _PantallaCuentaAtrasState();
}

class _PantallaCuentaAtrasState extends State<PantallaCuentaAtras> {
  late int _restantes;
  Timer? _temporizador;
  bool _enviando = false;
  bool _enviada = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restantes = widget.segundos;
    _iniciarCuenta();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  void _iniciarCuenta() {
    // Vibración y sonido: el vecino puede tener el teléfono en el bolsillo y
    // esta es la única señal de que algo se disparó.
    HapticFeedback.heavyImpact();

    _temporizador = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      if (_restantes <= 1) {
        t.cancel();
        _emitir();
      } else {
        setState(() => _restantes--);
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _cancelar() {
    _temporizador?.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _emitir() async {
    if (!mounted) return;
    setState(() => _enviando = true);

    final servicios = context.servicios;

    try {
      await servicios.alertas.emitir(esPanico: true);
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _enviada = true;
      });
    } on ExcepcionApi catch (e) {
      if (!mounted) return;

      // Sin red: se encola para reintentar. La petición de auxilio no se pierde.
      await ColaPanico(
        alertas: servicios.alertas,
      ).encolar(PanicoPendiente(momento: DateTime.now()));

      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return PopScope(
      // El botón "atrás" no debe descartar la pantalla por accidente: para
      // cancelar hay un botón grande y explícito.
      canPop: false,
      child: Scaffold(
        backgroundColor: t.color.peligroRelleno,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(t.espacio.margenPantalla),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                if (_enviada)
                  _Resultado(
                    icono: Icons.check_circle_outline,
                    titulo: 'Alerta enviada',
                    detalle: 'Tu comunidad ya fue notificada.',
                  )
                else if (_error != null)
                  _Resultado(
                    icono: Icons.cloud_off_outlined,
                    titulo: 'Se enviará al recuperar la conexión',
                    detalle: _error!,
                  )
                else if (_enviando)
                  _Resultado(
                    icono: Icons.campaign_outlined,
                    titulo: 'Enviando alerta...',
                    detalle: 'Avisando a tus vecinos.',
                  )
                else
                  _Contador(restantes: _restantes),

                const Spacer(),

                if (!_enviada && _error == null && !_enviando)
                  BotonAccion(
                    texto: 'CANCELAR',
                    icono: Icons.close,
                    // Blanco sobre rojo: el botón de escape debe ser lo más
                    // visible de la pantalla.
                    variante: VarianteBoton.secundario,
                    etiquetaSemantica:
                        'Cancelar la alerta de emergencia. Quedan $_restantes segundos.',
                    onPressed: _cancelar,
                  )
                else
                  BotonAccion(
                    texto: 'Cerrar',
                    variante: VarianteBoton.secundario,
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                SizedBox(height: t.espacio.entreGrupos),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({required this.restantes});

  final int restantes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tinta = t.color.onPeligroRelleno;

    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Enviando alerta de emergencia en $restantes segundos. '
          'Pulsa cancelar para detenerla.',
      excludeSemantics: true,
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: context.escalarAdorno(t.tamano.iconoIlustracion, maximo: 2.0),
            color: tinta,
          ),
          SizedBox(height: t.espacio.separacionSeccion),
          Text(
            'ALERTA DE EMERGENCIA',
            style: context.textos.titleMedium?.copyWith(color: tinta),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: t.espacio.entreGrupos),
          Text(
            '$restantes',
            style: context.textos.displaySmall?.copyWith(
              color: tinta,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: t.espacio.entreGrupos),
          Text(
            'Se avisará a toda tu comunidad',
            style: context.textos.bodyLarge?.copyWith(color: tinta),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tinta = t.color.onPeligroRelleno;

    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          Icon(
            icono,
            size: context.escalarAdorno(t.tamano.iconoIlustracion, maximo: 2.0),
            color: tinta,
          ),
          SizedBox(height: t.espacio.separacionSeccion),
          Text(
            titulo,
            style: context.textos.titleMedium?.copyWith(color: tinta),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: t.espacio.entreGrupos),
          Text(
            detalle,
            style: context.textos.bodyMedium?.copyWith(color: tinta),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
