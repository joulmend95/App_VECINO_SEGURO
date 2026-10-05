import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../servicios/dependencias.dart';
import '../servicios/servicio_panico.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import 'pantalla_cuenta_atras.dart';

/// **Ajustes del botón de pánico**
///
/// Activar o desactivar el gesto, revisar los permisos que necesita y probarlo
/// sin alarmar a nadie.
///
/// La prueba existe porque el gesto es invisible: sin poder comprobarlo, el
/// vecino no tiene forma de saber si funciona hasta la emergencia real, que es
/// el peor momento para descubrir que no.
class PantallaAjustesPanico extends StatefulWidget {
  const PantallaAjustesPanico({super.key});

  @override
  State<PantallaAjustesPanico> createState() => _PantallaAjustesPanicoState();
}

class _PantallaAjustesPanicoState extends State<PantallaAjustesPanico> {
  bool _activo = false;
  bool _bateriaOptimizada = false;
  bool _cargando = true;

  /// El vecino lo dejó activado, el sistema lo detuvo y no se pudo relanzar.
  bool _detenidoPorElSistema = false;

  ServicioPanico get _panico => context.servicios.panico;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarEstado());
  }

  /// El interruptor refleja lo que el vecino eligió, no solo si el servicio
  /// corre en este instante: si un cierre forzado del fabricante lo detuvo, se
  /// relanza aquí mismo antes de pintar el estado.
  Future<void> _cargarEstado() async {
    final elegido = await _panico.elegidoPorElVecino();
    final activo = await _panico.mantenerActivo() || await _panico.estaActivo();
    final bateria = await _panico.bateriaOptimizada();
    if (!mounted) return;
    setState(() {
      _activo = activo;
      _detenidoPorElSistema = elegido && !activo;
      _bateriaOptimizada = bateria;
      _cargando = false;
    });
  }

  Future<void> _alternar(bool valor) async {
    setState(() => _cargando = true);

    final exito = valor ? await _panico.activar() : await _panico.desactivar();

    // La elección se guarda para relanzar el servicio al reiniciar el teléfono
    // y cada vez que se abra la app, si el sistema lo detuvo.
    await _panico.recordarEleccion(valor && exito);

    if (!mounted) return;
    await _cargarEstado();

    if (!exito && valor && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo activar el gesto. Revisa los permisos.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (!_panico.disponible) return const _NoDisponible();

    return Scaffold(
      appBar: AppBar(title: const Text('Botón de pánico')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(t.espacio.margenPantalla),
          children: [
            _ExplicacionGesto(),
            SizedBox(height: t.espacio.separacionSeccion),

            Card(
              color: t.color.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: t.radio.brCard,
                side: BorderSide(
                  color: t.color.borde,
                  width: t.tamano.grosorBorde,
                ),
              ),
              child: SwitchListTile(
                value: _activo,
                onChanged: _cargando ? null : _alternar,
                title: Text('Gesto activado', style: context.textos.titleSmall),
                subtitle: Text(
                  _activo
                      ? 'Funciona con la app cerrada y la pantalla bloqueada.'
                      : 'El gesto no está detectando nada ahora mismo.',
                  style: context.textos.bodySmall,
                ),
                contentPadding: EdgeInsets.all(t.espacio.entreGrupos),
              ),
            ),

            if (_detenidoPorElSistema) ...[
              SizedBox(height: t.espacio.entreGrupos),
              _AvisoDetenido(onReactivar: () => _alternar(true)),
            ],

            if (_activo && _bateriaOptimizada) ...[
              SizedBox(height: t.espacio.entreGrupos),
              _AvisoBateria(onCorregir: _panico.pedirExencionBateria),
            ],

            if (_activo) ...[
              SizedBox(height: t.espacio.entreElementos),
              Text(
                'En algunos teléfonos (Infinix, Xiaomi, Oppo…) quitar la app '
                'de «Recientes» detiene el gesto. Se reactiva solo al volver a '
                'abrir la app. Para que no se detenga, permite el «Inicio '
                'automático» de Vecino Seguro en los ajustes del teléfono.',
                style: context.textos.bodySmall?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
              ),
            ],

            SizedBox(height: t.espacio.separacionSeccion),

            BotonAccion(
              texto: 'Probar la cuenta atrás',
              icono: Icons.play_circle_outline,
              variante: VarianteBoton.secundario,
              etiquetaSemantica:
                  'Probar la cuenta atrás sin enviar ninguna alerta',
              onPressed: () => PantallaCuentaAtras.mostrar(context),
            ),
            SizedBox(height: t.espacio.entreElementos),
            Text(
              'La prueba muestra la cuenta atrás. Si la dejas terminar, se '
              'enviará una alerta real a tu comunidad.',
              style: context.textos.bodySmall,
              textAlign: TextAlign.center,
            ),

            // Solo visible en depuración: permite verificar que Crashlytics
            // recibe el informe con traza y versión antes de publicar.
            if (kDebugMode) ...[
              SizedBox(height: t.espacio.separacionSeccion),
              BotonAccion(
                texto: 'Provocar fallo de prueba',
                icono: Icons.bug_report_outlined,
                variante: VarianteBoton.secundario,
                etiquetaSemantica: 'Botón de prueba de monitoreo de fallos',
                onPressed: () => FirebaseCrashlytics.instance.crash(),
              ),
              SizedBox(height: t.espacio.entreElementos),
              Text(
                'Solo visible en modo depuración. Verifica en la consola de '
                'Firebase que el informe llega con su traza y versión.',
                style: context.textos.bodySmall?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExplicacionGesto extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.all(t.espacio.interiorCard),
      decoration: BoxDecoration(
        color: t.color.peligroSuave,
        borderRadius: t.radio.brCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.volume_up_outlined,
                  color: t.color.onPeligroSuave,
                  size: context.escalarAdorno(t.tamano.iconoGrande),
                ),
              ),
              SizedBox(width: t.espacio.entreGrupos),
              Expanded(
                child: Text(
                  'Pulsa 3 veces el volumen',
                  style: context.textos.titleMedium?.copyWith(
                    color: t.color.onPeligroSuave,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: t.espacio.entreGrupos),
          Text(
            'Sube o baja el volumen tres veces seguidas, en menos de un segundo '
            'y medio. Funciona también con la app cerrada y la pantalla '
            'bloqueada: aparecerá una notificación con unos segundos para '
            'tocar «Cancelar» antes de que se avise a tu comunidad.',
            style: context.textos.bodyMedium?.copyWith(
              color: t.color.onPeligroSuave,
            ),
          ),
        ],
      ),
    );
  }
}

/// El gesto estaba activado pero el sistema lo detuvo y no se pudo relanzar.
class _AvisoDetenido extends StatelessWidget {
  const _AvisoDetenido({required this.onReactivar});

  final VoidCallback onReactivar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.all(t.espacio.interiorCard),
      decoration: BoxDecoration(
        color: t.color.peligroSuave,
        borderRadius: t.radio.brControl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'El teléfono detuvo el botón de pánico',
            style: context.textos.titleSmall?.copyWith(
              color: t.color.onPeligroSuave,
            ),
          ),
          SizedBox(height: t.espacio.entreElementos),
          Text(
            'Lo tenías activado, pero el sistema cerró la app y no se pudo '
            'volver a encender solo. Revisa los permisos y vuelve a activarlo.',
            style: context.textos.bodySmall?.copyWith(
              color: t.color.onPeligroSuave,
            ),
          ),
          SizedBox(height: t.espacio.entreGrupos),
          BotonAccion(
            texto: 'Reactivar',
            variante: VarianteBoton.secundario,
            onPressed: onReactivar,
          ),
        ],
      ),
    );
  }
}

class _AvisoBateria extends StatelessWidget {
  const _AvisoBateria({required this.onCorregir});

  final VoidCallback onCorregir;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.all(t.espacio.interiorCard),
      decoration: BoxDecoration(
        color: t.color.advertenciaSuave,
        borderRadius: t.radio.brControl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.battery_alert_outlined,
                  color: t.color.onAdvertenciaSuave,
                  size: context.escalarAdorno(t.tamano.iconoGrande),
                ),
              ),
              SizedBox(width: t.espacio.entreElementos),
              Expanded(
                child: Text(
                  'El ahorro de batería puede desactivar el gesto',
                  style: context.textos.titleSmall?.copyWith(
                    color: t.color.onAdvertenciaSuave,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: t.espacio.entreElementos),
          Text(
            'Android puede detener el servicio para ahorrar energía. Si eso '
            'ocurre, el gesto dejará de funcionar sin avisarte.',
            style: context.textos.bodySmall?.copyWith(
              color: t.color.onAdvertenciaSuave,
            ),
          ),
          SizedBox(height: t.espacio.entreGrupos),
          BotonAccion(
            texto: 'Permitir que siga activo',
            variante: VarianteBoton.secundario,
            onPressed: onCorregir,
          ),
        ],
      ),
    );
  }
}

/// iOS y escritorio: el gesto no es posible.
class _NoDisponible extends StatelessWidget {
  const _NoDisponible();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('Botón de pánico')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(t.espacio.vacioGrande),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.phonelink_erase_outlined,
                  size: context.escalarAdorno(t.tamano.iconoIlustracion),
                  color: t.color.onSuperficieSutil,
                ),
              ),
              SizedBox(height: t.espacio.entreGrupos),
              Text(
                'Solo disponible en Android',
                style: context.textos.titleMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.entreElementos),
              Text(
                'iOS no permite que una aplicación detecte las teclas de '
                'volumen en segundo plano. En iPhone puedes emitir la alerta '
                'desde la pantalla de emisión.',
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
