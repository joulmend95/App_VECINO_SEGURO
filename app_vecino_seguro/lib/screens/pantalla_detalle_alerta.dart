import 'package:flutter/material.dart';

import '../modelos/alerta.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/categoria_alerta.dart';
import '../widgets/tarjeta_alerta.dart';
import '../widgets/vista_estado.dart';

/// **P11 — Detalle de una alerta**
///
/// Consume `GET /api/alertas/:id`.
///
/// **Recibe un identificador, nunca un objeto [Alerta].** Es la decisión que
/// gobierna toda la pantalla y el motivo de que exista el endpoint de detalle:
/// si el muro le entregara la alerta ya cargada, abrir `/alertas/42` en frío
/// —desde una notificación, un enlace o tras reiniciar la app— mostraría una
/// pantalla vacía. Al depender solo de la dirección, la pantalla se reconstruye
/// siempre, venga de donde venga.
///
/// El precio es una petición extra al volver desde el muro. Se paga a gusto: a
/// cambio, la alerta que se ve es la del servidor y no una copia que pudo
/// quedarse obsoleta en la caché de 60 segundos del listado.
class PantallaDetalleAlerta extends StatefulWidget {
  const PantallaDetalleAlerta({super.key, required this.idAlerta});

  /// Viene del parámetro de ruta `:idAlerta`. Un valor `<= 0` significa que la
  /// dirección estaba malformada.
  final int idAlerta;

  @override
  State<PantallaDetalleAlerta> createState() => _PantallaDetalleAlertaState();
}

class _PantallaDetalleAlertaState extends State<PantallaDetalleAlerta> {
  EstadoVista<Alerta> _estado = const VistaCargando();

  @override
  void initState() {
    super.initState();
    // Se difiere al primer frame: la carga necesita el contexto heredado del
    // que cuelgan las dependencias, y `initState` todavía no puede leerlo.
    // Mismo patrón que `PantallaMuroAlertas`.
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    if (!mounted) return;

    // Una dirección malformada no llega a la red: el servidor respondería 400 y
    // habríamos gastado un viaje para saber lo que ya se ve en el parámetro.
    if (widget.idAlerta <= 0) {
      setState(() => _estado = const VistaError('Esta dirección no corresponde a ninguna alerta.'));
      return;
    }

    setState(() => _estado = const VistaCargando());

    try {
      final alerta = await context.servicios.alertas.obtenerPorId(widget.idAlerta);
      if (!mounted) return;
      setState(() => _estado = VistaConDatos(alerta));
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _estado = VistaError(e.mensaje));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de la alerta')),
      body: SafeArea(
        child: VistaEstado<Alerta>(
          estado: _estado,
          // El estado vacío no se usa aquí: una alerta existe o no existe, y la
          // que no existe es un error (404), no un vacío. Se deja el mensaje
          // por si acaso, pero `_cargar` nunca produce `VistaVacia`.
          mensajeVacio: 'Esta alerta ya no está disponible',
          onReintentar: widget.idAlerta > 0 ? _cargar : null,
          constructorContenido: (context, alerta) => _Contenido(alerta: alerta),
        ),
      ),
    );
  }
}

/// Cuerpo del detalle. Separado del `State` para que solo se reconstruya cuando
/// hay datos, y para que la alerta llegue aquí ya desempaquetada y no nula.
class _Contenido extends StatelessWidget {
  const _Contenido({required this.alerta});

  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // El pánico es autoritativo: prevalece sobre lo que diga el texto. Sin
    // esto, la alerta más grave del sistema se clasificaría por palabras clave
    // y podría aparecer como urgencia media.
    final categoria = alerta.esPanico
        ? CategoriaAlerta.panico
        : CategoriaAlerta.desdeTexto(alerta.tipoAlerta);

    return SingleChildScrollView(
      padding: EdgeInsets.all(t.espacio.margenPantalla),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Se reutiliza la misma tarjeta del muro, sin `onTap`: aquí ya no
          // navega a ninguna parte. Que sea el mismo componente garantiza que
          // el icono y la urgencia coincidan con lo que el vecino acaba de ver
          // en la lista.
          TarjetaAlerta(
            tipoAlerta: alerta.tipoAlerta,
            nombreVecino: alerta.nombreVecino,
            fechaHora: alerta.fechaHora,
            categoria: categoria,
          ),

          SizedBox(height: t.espacio.separacionSeccion),

          _Bloque(
            titulo: 'Descripción',
            icono: Icons.notes_outlined,
            // Emitir sin detalle es válido: en una emergencia se toca el botón
            // y punto. Se dice explícitamente en lugar de dejar un hueco.
            texto: alerta.descripcion ?? 'El vecino no añadió ningún detalle.',
            atenuado: alerta.descripcion == null,
          ),

          SizedBox(height: t.espacio.entreGrupos),

          _Bloque(
            titulo: 'Estado',
            icono: alerta.estaActiva
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            texto: alerta.estaActiva
                ? 'Activa. La comunidad ya fue notificada.'
                : 'Cerrada (${alerta.estado}).',
          ),

          SizedBox(height: t.espacio.entreGrupos),

          _Bloque(
            titulo: 'Fecha y hora',
            icono: Icons.schedule_outlined,
            texto: _formatearFecha(alerta.fechaHora),
          ),
        ],
      ),
    );
  }

  /// Fecha completa, no relativa. La tarjeta ya dice "hace 5 minutos"; el
  /// detalle es donde se consulta el dato exacto para poder reportarlo.
  static String _formatearFecha(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} '
        'a las ${dos(fecha.hour)}:${dos(fecha.minute)}';
  }
}

/// Fila etiquetada del detalle.
class _Bloque extends StatelessWidget {
  const _Bloque({
    required this.titulo,
    required this.icono,
    required this.texto,
    this.atenuado = false,
  });

  final String titulo;
  final IconData icono;
  final String texto;
  final bool atenuado;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      // Una sola frase por bloque: el lector no anuncia por separado el título,
      // el icono y el valor, que sonaría a tres elementos inconexos.
      container: true,
      label: '$titulo: $texto',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(t.espacio.interiorCard),
        decoration: BoxDecoration(
          color: t.color.superficieAlterna,
          borderRadius: t.radio.brCard,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icono,
              size: context.escalarAdorno(t.tamano.iconoGrande),
              color: t.color.onSuperficieSutil,
            ),
            SizedBox(width: t.espacio.entreGrupos),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: context.textos.labelLarge?.copyWith(
                      color: t.color.onSuperficieSutil,
                    ),
                  ),
                  SizedBox(height: t.espacio.microEntreTexto),
                  Text(
                    texto,
                    style: context.textos.bodyLarge?.copyWith(
                      color: atenuado
                          ? t.color.onSuperficieSutil
                          : t.color.onSuperficie,
                      fontStyle: atenuado ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
