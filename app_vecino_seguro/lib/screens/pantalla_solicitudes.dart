import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../modelos/solicitud.dart';
import '../navegacion/rutas.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import '../widgets/vista_estado.dart';

/// **P12 — Solicitudes pendientes** (solo administrador)
///
/// Consume `GET /api/comunidades/solicitudes` y
/// `PATCH /api/comunidades/solicitudes/:id`.
///
/// Usa [VistaEstado] genérico sobre `List<SolicitudIngreso>`: el mismo
/// componente que resuelve cargando, vacío y error en el muro de alertas sirve
/// aquí sin ningún cambio.
class PantallaSolicitudes extends StatefulWidget {
  const PantallaSolicitudes({super.key});

  @override
  State<PantallaSolicitudes> createState() => _PantallaSolicitudesState();
}

class _PantallaSolicitudesState extends State<PantallaSolicitudes> {
  EstadoVista<List<SolicitudIngreso>> _estado = const VistaCargando();

  /// Solicitudes que se están resolviendo, para bloquear solo esas filas y no
  /// la pantalla entera.
  final Set<int> _resolviendo = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _estado = const VistaCargando());

    try {
      final solicitudes = await context.servicios.comunidades.listarPendientes();
      if (!mounted) return;
      setState(() {
        _estado = solicitudes.isEmpty
            ? const VistaVacia()
            : VistaConDatos(solicitudes);
      });
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      // Un 403 NO_ES_ADMIN no es un fallo de carga que se pueda reintentar: el
      // vecino dejó de ser administrador y ningún reintento va a devolverle el
      // permiso. Se le lleva a una pantalla que se lo explica, y —esto es lo
      // importante— sin cerrarle la sesión: su credencial es perfectamente
      // válida, lo que cambió fue su rol.
      if (e.codigo == ExcepcionApi.noEsAdmin) {
        context.go(Rutas.sinPermiso);
        return;
      }
      setState(() => _estado = VistaError(e.mensaje));
    }
  }

  Future<void> _resolver(SolicitudIngreso solicitud, bool aprobar) async {
    if (_resolviendo.contains(solicitud.idSolicitud)) return;
    setState(() => _resolviendo.add(solicitud.idSolicitud));

    try {
      final mensaje = await context.servicios.comunidades.resolverSolicitud(
        idSolicitud: solicitud.idSolicitud,
        aprobar: aprobar,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
      await _cargar();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      if (e.codigo == ExcepcionApi.noEsAdmin) {
        context.go(Rutas.sinPermiso);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      setState(() => _resolviendo.remove(solicitud.idSolicitud));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final codigo = context.sesion.perfil?.comunidad?.codigo;

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitudes para unirse')),
      body: SafeArea(
        child: Column(
          children: [
            if (codigo != null) _RecordatorioCodigo(codigo: codigo),
            Expanded(
              child: VistaEstado<List<SolicitudIngreso>>(
                estado: _estado,
                mensajeVacio: 'No hay solicitudes pendientes',
                detalleVacio:
                    'Cuando un vecino use el código de tu comunidad, '
                    'su solicitud aparecerá aquí.',
                iconoVacio: Icons.inbox_outlined,
                onReintentar: _cargar,
                constructorContenido: (context, solicitudes) =>
                    RefreshIndicator(
                      onRefresh: _cargar,
                      color: t.color.primario,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(t.espacio.margenPantalla),
                        itemCount: solicitudes.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: t.espacio.entreGrupos),
                        itemBuilder: (context, i) {
                          final s = solicitudes[i];
                          return _TarjetaSolicitud(
                            solicitud: s,
                            ocupada: _resolviendo.contains(s.idSolicitud),
                            onAprobar: () => _resolver(s, true),
                            onRechazar: () => _resolver(s, false),
                          );
                        },
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recordatorio del código que el administrador debe compartir.
class _RecordatorioCodigo extends StatelessWidget {
  const _RecordatorioCodigo({required this.codigo});

  final String codigo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: EdgeInsets.fromLTRB(
        t.espacio.margenPantalla,
        t.espacio.entreGrupos,
        t.espacio.margenPantalla,
        t.espacio.nulo,
      ),
      padding: EdgeInsets.all(t.espacio.interiorCard),
      decoration: BoxDecoration(
        color: t.color.primarioSuave,
        borderRadius: t.radio.brControl,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.qr_code_2_outlined,
              color: t.color.onPrimarioSuave,
              size: context.escalarAdorno(t.tamano.iconoGrande),
            ),
          ),
          SizedBox(width: t.espacio.entreGrupos),
          Expanded(
            child: Text(
              'Código de tu comunidad: $codigo',
              style: context.textos.titleSmall?.copyWith(
                color: t.color.onPrimarioSuave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de una solicitud, con las dos acciones del administrador.
class _TarjetaSolicitud extends StatelessWidget {
  const _TarjetaSolicitud({
    required this.solicitud,
    required this.ocupada,
    required this.onAprobar,
    required this.onRechazar,
  });

  final SolicitudIngreso solicitud;
  final bool ocupada;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      container: true,
      label:
          'Solicitud de ${solicitud.nombreVecino}, '
          'teléfono ${solicitud.telefonoVecino}',
      child: Card(
        color: t.color.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: t.radio.brCard,
          side: BorderSide(color: t.color.borde, width: t.tamano.grosorBorde),
        ),
        child: Padding(
          padding: EdgeInsets.all(t.espacio.interiorCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: context.escalarAdorno(t.tamano.avatar),
                      height: context.escalarAdorno(t.tamano.avatar),
                      decoration: BoxDecoration(
                        color: t.color.primarioSuave,
                        borderRadius: BorderRadius.circular(t.radio.circular),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: t.color.onPrimarioSuave,
                        size: context.escalarAdorno(t.tamano.iconoGrande),
                      ),
                    ),
                  ),
                  SizedBox(width: t.espacio.entreGrupos),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          solicitud.nombreVecino,
                          style: context.textos.titleMedium,
                        ),
                        SizedBox(height: t.espacio.microEntreTexto),
                        // El teléfono es el dato con el que el administrador
                        // reconoce a quién está aprobando. Dar acceso a un
                        // desconocido es el riesgo real de esta pantalla.
                        Text(
                          solicitud.telefonoVecino,
                          style: context.textos.bodyMedium?.copyWith(
                            color: t.color.onSuperficieSutil,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.espacio.entreGrupos),
              // Los botones se apilan en vertical: en 320 dp con la fuente
              // ampliada, dos botones en fila no caben.
              BotonAccion(
                texto: 'Aprobar',
                icono: Icons.check,
                cargando: ocupada,
                etiquetaSemantica:
                    'Aprobar a ${solicitud.nombreVecino} en la comunidad',
                onPressed: onAprobar,
              ),
              SizedBox(height: t.espacio.entreElementos),
              BotonAccion(
                texto: 'Rechazar',
                icono: Icons.close,
                variante: VarianteBoton.secundario,
                etiquetaSemantica:
                    'Rechazar la solicitud de ${solicitud.nombreVecino}',
                onPressed: ocupada ? null : onRechazar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
