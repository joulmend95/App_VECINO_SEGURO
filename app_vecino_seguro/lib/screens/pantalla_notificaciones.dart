import 'package:flutter/material.dart';

import '../modelos/notificacion.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/tarjeta_alerta.dart';
import '../widgets/vista_estado.dart';

/// **P7 — Notificaciones**
///
/// Consume `GET /api/notificaciones`.
///
/// Reutiliza [VistaEstado] y [TarjetaAlerta] **sin ningún cambio**: al ser
/// `VistaEstado<T>` genérico, sirve igual para `List<Notificacion>` que para
/// `List<Alerta>` o `List<SolicitudIngreso>`.
///
/// Esta bandeja es la red de seguridad del sistema de avisos: si el push no
/// llegó —teléfono apagado, sin red, permiso denegado—, la alerta sigue aquí.
class PantallaNotificaciones extends StatefulWidget {
  const PantallaNotificaciones({super.key});

  @override
  State<PantallaNotificaciones> createState() => _PantallaNotificacionesState();
}

class _PantallaNotificacionesState extends State<PantallaNotificaciones> {
  EstadoVista<List<Notificacion>> _estado = const VistaCargando();
  int _noLeidas = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _estado = const VistaCargando());

    try {
      final bandeja = await context.servicios.notificaciones.obtenerBandeja();
      if (!mounted) return;

      setState(() {
        _noLeidas = bandeja.noLeidas;
        _estado = bandeja.items.isEmpty
            ? const VistaVacia()
            : VistaConDatos(bandeja.items);
      });
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _estado = VistaError(e.mensaje));
    }
  }

  Future<void> _marcarTodas() async {
    try {
      await context.servicios.notificaciones.marcarTodasLeidas();
      await _cargar();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _abrir(Notificacion n) async {
    if (n.leida) return;

    // Actualización optimista: la marca se ve al instante y luego se confirma
    // contra el servidor. Esperar la respuesta para tachar una notificación
    // haría que la lista pareciera congelada.
    setState(() {
      final actual = _estado;
      if (actual is VistaConDatos<List<Notificacion>>) {
        _estado = VistaConDatos(
          actual.datos
              .map(
                (x) => x.idNotificacion == n.idNotificacion
                    ? x.copiarComoLeida()
                    : x,
              )
              .toList(),
        );
        _noLeidas = (_noLeidas - 1).clamp(0, 9999);
      }
    });

    try {
      await context.servicios.notificaciones.marcarLeida(n.idNotificacion);
    } on ExcepcionApi {
      // Si falla, se recarga para no dejar la interfaz mintiendo sobre el
      // estado real.
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (_noLeidas > 0)
            TextButton(
              onPressed: _marcarTodas,
              child: const Text('Marcar todas'),
            ),
        ],
      ),
      body: SafeArea(
        child: VistaEstado<List<Notificacion>>(
          estado: _estado,
          mensajeVacio: 'Sin notificaciones',
          detalleVacio:
              'Cuando un vecino emita una alerta en tu comunidad, la verás aquí.',
          iconoVacio: Icons.notifications_none_outlined,
          onReintentar: _cargar,
          constructorContenido: (context, items) => RefreshIndicator(
            onRefresh: _cargar,
            color: t.color.primario,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(t.espacio.margenPantalla),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  SizedBox(height: t.espacio.entreGrupos),
              itemBuilder: (context, i) {
                final n = items[i];
                return _FilaNotificacion(
                  notificacion: n,
                  onTap: () => _abrir(n),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Envuelve una [TarjetaAlerta] con el indicador de "no leída".
class _FilaNotificacion extends StatelessWidget {
  const _FilaNotificacion({required this.notificacion, required this.onTap});

  final Notificacion notificacion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = notificacion;

    return Stack(
      children: [
        Opacity(
          // Las leídas se atenúan levemente, pero el punto de color es el
          // canal principal: la opacidad sola no bastaría para distinguirlas.
          opacity: n.leida ? 0.7 : 1.0,
          child: TarjetaAlerta(
            tipoAlerta: n.alerta.tipoAlerta,
            nombreVecino: n.alerta.nombreVecino,
            fechaHora: n.alerta.fechaHora,
            onTap: onTap,
          ),
        ),
        if (!n.leida)
          Positioned(
            top: t.espacio.entreElementos,
            right: t.espacio.entreElementos,
            child: Semantics(
              label: 'No leída',
              child: Container(
                width: t.espacio.entreGrupos,
                height: t.espacio.entreGrupos,
                decoration: BoxDecoration(
                  color: t.color.primario,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
