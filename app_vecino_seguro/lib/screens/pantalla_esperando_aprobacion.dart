import 'package:flutter/material.dart';

import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';

/// **P11 — Esperando aprobación**
///
/// El vecino ya envió su solicitud y espera que el administrador la resuelva.
///
/// Comprueba el estado de forma periódica: sin eso, tendría que cerrar y
/// reabrir la app para descubrir que ya fue aprobado. Cuando el perfil pasa a
/// `ACTIVO`, la guardia del enrutador lo lleva al muro automáticamente.
class PantallaEsperandoAprobacion extends StatefulWidget {
  const PantallaEsperandoAprobacion({super.key});

  @override
  State<PantallaEsperandoAprobacion> createState() =>
      _PantallaEsperandoAprobacionState();
}

class _PantallaEsperandoAprobacionState
    extends State<PantallaEsperandoAprobacion> {
  bool _comprobando = false;
  bool _cancelando = false;
  String? _error;

  Future<void> _comprobarEstado() async {
    if (_comprobando) return;
    setState(() {
      _comprobando = true;
      _error = null;
    });

    try {
      // Si el administrador ya aprobó, el perfil pasa a ACTIVO y la guardia
      // redirige sola al muro de alertas.
      await context.servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _comprobando = false);
    }
  }

  Future<void> _cancelar() async {
    if (_cancelando) return;
    setState(() {
      _cancelando = true;
      _error = null;
    });

    try {
      await context.servicios.comunidades.cancelarMiSolicitud();
      if (!mounted) return;
      // Vuelve a SIN_COMUNIDAD y la guardia lleva a elegir de nuevo.
      await context.servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sesion = context.sesion;
    final solicitud = sesion.perfil?.solicitudPendiente;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitud enviada'),
        actions: [
          IconButton(
            onPressed: sesion.cerrar,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            iconSize: t.tamano.iconoGrande,
            constraints: BoxConstraints(
              minWidth: t.tamano.areaTactilMinima,
              minHeight: t.tamano.areaTactilMinima,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(t.espacio.vacioGrande),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(t.espacio.separacionSeccion),
                decoration: BoxDecoration(
                  color: t.color.advertenciaSuave,
                  borderRadius: BorderRadius.circular(t.radio.circular),
                ),
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.hourglass_top_outlined,
                    size: context.escalarAdorno(t.tamano.iconoIlustracion),
                    color: t.color.onAdvertenciaSuave,
                  ),
                ),
              ),
              SizedBox(height: t.espacio.separacionSeccion),

              Text(
                'Esperando aprobación',
                style: context.textos.titleMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.entreElementos),

              Text(
                solicitud != null
                    ? 'Tu solicitud para unirte a ${solicitud.comunidad} '
                          'ya llegó al administrador.'
                    : 'Tu solicitud ya llegó al administrador.',
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.entreGrupos),

              Text(
                'Podrás ver y emitir alertas en cuanto te apruebe.',
                style: context.textos.bodySmall,
                textAlign: TextAlign.center,
              ),

              if (_error != null) ...[
                SizedBox(height: t.espacio.entreGrupos),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: context.textos.bodyMedium?.copyWith(
                      color: t.color.peligro,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              SizedBox(height: t.espacio.separacionSeccion),

              BotonAccion(
                texto: 'Comprobar ahora',
                icono: Icons.refresh,
                cargando: _comprobando,
                onPressed: _comprobarEstado,
              ),
              SizedBox(height: t.espacio.entreGrupos),

              BotonAccion(
                texto: 'Cancelar y probar otro código',
                icono: Icons.close,
                variante: VarianteBoton.secundario,
                cargando: _cancelando,
                onPressed: _cancelar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
