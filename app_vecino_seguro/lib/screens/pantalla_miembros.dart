import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../modelos/miembro.dart';
import '../navegacion/rutas.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/campo_texto.dart';
import '../widgets/dialogo_confirmacion.dart';
import '../widgets/vista_estado.dart';

/// **Vecinos de mi comunidad**
///
/// Consume `GET /api/comunidades/miembros`.
///
/// Disponible para **cualquier vecino aprobado**, no solo el administrador:
/// saber quién forma parte de tu comunidad y poder contactar con alguien
/// cercano es el sentido de una red vecinal.
///
/// Reutiliza [VistaEstado] y [CampoTexto] del catálogo sin cambios.
class PantallaMiembros extends StatefulWidget {
  const PantallaMiembros({super.key});

  @override
  State<PantallaMiembros> createState() => _PantallaMiembrosState();
}

class _PantallaMiembrosState extends State<PantallaMiembros> {
  final _buscarCtrl = TextEditingController();

  EstadoVista<List<Miembro>> _estado = const VistaCargando();
  List<Miembro> _todos = const [];
  String _filtro = '';
  int _total = 0;

  @override
  void initState() {
    super.initState();
    // Se difiere al primer frame: leer las dependencias heredadas dentro de
    // `initState` no está permitido.
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _estado = const VistaCargando());

    try {
      final lista = await context.servicios.comunidades.listarMiembros();
      if (!mounted) return;
      _todos = lista.miembros;
      setState(() {
        _total = lista.total;
        _estado = _calcularEstado();
      });
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _estado = VistaError(e.mensaje));
    }
  }

  EstadoVista<List<Miembro>> _calcularEstado() {
    if (_todos.isEmpty) return const VistaVacia();

    final visibles = _filtrar(_todos, _filtro);
    if (visibles.isEmpty) return const VistaVacia();

    return VistaConDatos(visibles);
  }

  static List<Miembro> _filtrar(List<Miembro> miembros, String texto) {
    final q = texto.trim().toLowerCase();
    if (q.isEmpty) return miembros;
    return miembros
        .where(
          (m) =>
              m.nombre.toLowerCase().contains(q) ||
              m.telefono.contains(q),
        )
        .toList();
  }

  bool get _filtroSinResultados =>
      _todos.isNotEmpty && _filtro.trim().isNotEmpty;

  /// Expulsa a un vecino. Solo lo ve el administrador.
  ///
  /// Se confirma porque es irreversible desde la app: el vecino tendría que
  /// volver a solicitar el ingreso y esperar aprobación.
  Future<void> _expulsar(Miembro m) async {
    final confirmado = await DialogoConfirmacion.mostrar(
      context,
      titulo: '¿Sacar a este vecino?',
      mensaje:
          'Dejará de ver y emitir alertas de la comunidad. Para volver tendrá '
          'que solicitar el ingreso otra vez.',
      detalle: '${m.nombre} · ${m.telefono}',
      textoConfirmar: 'Sí, sacarlo',
      icono: Icons.person_remove_outlined,
    );

    if (!confirmado || !mounted) return;

    try {
      final mensaje = await context.servicios.comunidades.expulsarMiembro(
        m.idUsuario,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
      await _cargar();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      // Expulsar es la única acción de esta pantalla que exige ser
      // administrador. Listar los vecinos no, así que el 403 con NO_ES_ADMIN
      // solo puede venir de aquí. La sesión NO se cierra: sigue siendo un
      // vecino válido de la comunidad, solo que ya no la administra.
      if (e.codigo == ExcepcionApi.noEsAdmin) {
        context.go(Rutas.sinPermiso);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  /// Copia el teléfono al portapapeles.
  ///
  /// No se abre el marcador directamente: en una lista, un toque accidental
  /// que inicie una llamada sería molesto. Copiar es reversible.
  Future<void> _copiarTelefono(Miembro m) async {
    await Clipboard.setData(ClipboardData(text: m.telefono));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Teléfono de ${m.nombre} copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final comunidad = context.sesion.perfil?.comunidad?.nombre;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vecinos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: const SizedBox.shrink(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (comunidad != null) _Encabezado(comunidad: comunidad, total: _total),

            Padding(
              padding: EdgeInsets.fromLTRB(
                t.espacio.margenPantalla,
                t.espacio.entreGrupos,
                t.espacio.margenPantalla,
                t.espacio.entreElementos,
              ),
              child: CampoTexto(
                controlador: _buscarCtrl,
                etiqueta: 'Buscar vecino',
                pista: 'Por nombre o teléfono',
                icono: Icons.search,
                accionTeclado: TextInputAction.search,
                onCambio: (valor) => setState(() {
                  _filtro = valor;
                  if (_estado is! VistaError) _estado = _calcularEstado();
                }),
                accionSufijo: _filtro.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _buscarCtrl.clear();
                          setState(() {
                            _filtro = '';
                            _estado = _calcularEstado();
                          });
                        },
                      ),
              ),
            ),

            Expanded(
              child: VistaEstado<List<Miembro>>(
                estado: _estado,
                mensajeVacio: _filtroSinResultados
                    ? 'Sin resultados para "$_filtro"'
                    : 'Todavía no hay vecinos',
                detalleVacio: _filtroSinResultados
                    ? 'Prueba con otro nombre o número.'
                    : 'Comparte el código de tu comunidad para que se unan.',
                iconoVacio: _filtroSinResultados
                    ? Icons.search_off
                    : Icons.groups_outlined,
                onReintentar: _cargar,
                constructorContenido: (context, miembros) => RefreshIndicator(
                  onRefresh: _cargar,
                  color: t.color.primario,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      t.espacio.margenPantalla,
                      t.espacio.entreElementos,
                      t.espacio.margenPantalla,
                      t.espacio.separacionSeccion,
                    ),
                    itemCount: miembros.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: t.espacio.entreGrupos),
                    itemBuilder: (context, i) {
                      final m = miembros[i];
                      final esYo = m.idUsuario == context.sesion.perfil?.idUsuario;
                      return _TarjetaMiembro(
                        miembro: m,
                        esYo: esYo,
                        onCopiar: () => _copiarTelefono(m),
                        // Solo el administrador puede expulsar, y nunca a sí
                        // mismo: para eso está "salir de la comunidad".
                        onExpulsar:
                            (context.sesion.perfil?.esAdmin ?? false) && !esYo
                            ? () => _expulsar(m)
                            : null,
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

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.comunidad, required this.total});

  final String comunidad;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        t.espacio.margenPantalla,
        t.espacio.entreGrupos,
        t.espacio.margenPantalla,
        t.espacio.nulo,
      ),
      padding: EdgeInsets.all(t.espacio.interiorCard),
      decoration: BoxDecoration(
        color: t.color.primarioSuave,
        borderRadius: t.radio.brCard,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.groups_outlined,
              color: t.color.onPrimarioSuave,
              size: context.escalarAdorno(t.tamano.iconoGrande),
            ),
          ),
          SizedBox(width: t.espacio.entreGrupos),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comunidad,
                  style: context.textos.titleSmall?.copyWith(
                    color: t.color.onPrimarioSuave,
                  ),
                ),
                SizedBox(height: t.espacio.microEntreTexto),
                Text(
                  '$total ${total == 1 ? "vecino" : "vecinos"}',
                  style: context.textos.bodySmall?.copyWith(
                    color: t.color.onPrimarioSuave,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaMiembro extends StatelessWidget {
  const _TarjetaMiembro({
    required this.miembro,
    required this.esYo,
    required this.onCopiar,
    this.onExpulsar,
  });

  final Miembro miembro;
  final bool esYo;
  final VoidCallback onCopiar;

  ///  cuando quien mira no puede expulsar a este vecino.
  final VoidCallback? onExpulsar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = miembro;

    // El administrador se distingue por color, icono Y texto: tres canales,
    // igual que las urgencias de las alertas (WCAG 1.4.1).
    final fondo = m.esAdmin ? t.color.primarioSuave : t.color.superficieAlterna;
    final tinta = m.esAdmin
        ? t.color.onPrimarioSuave
        : t.color.onSuperficieSutil;

    return Semantics(
      button: true,
      label:
          '${m.nombre}${esYo ? ", tú" : ""}. '
          '${m.esAdmin ? "Administrador" : "Vecino"}. '
          'Teléfono ${m.telefono}. Toca para copiar el número.',
      excludeSemantics: true,
      child: Card(
        color: t.color.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: t.radio.brCard,
          side: BorderSide(color: t.color.borde, width: t.tamano.grosorBorde),
        ),
        child: InkWell(
          onTap: onCopiar,
          borderRadius: t.radio.brCard,
          child: Padding(
            padding: EdgeInsets.all(t.espacio.interiorCard),
            child: Row(
              children: [
                Container(
                  width: context.escalarAdorno(t.tamano.avatar),
                  height: context.escalarAdorno(t.tamano.avatar),
                  decoration: BoxDecoration(
                    color: fondo,
                    borderRadius: BorderRadius.circular(t.radio.circular),
                  ),
                  child: Icon(
                    m.esAdmin
                        ? Icons.admin_panel_settings_outlined
                        : Icons.person_outline,
                    color: tinta,
                    size: context.escalarAdorno(t.tamano.iconoGrande),
                  ),
                ),
                SizedBox(width: t.espacio.interiorCard),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              m.nombre,
                              style: context.textos.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (esYo) ...[
                            SizedBox(width: t.espacio.entreElementos),
                            _Etiqueta(
                              texto: 'Tú',
                              fondo: t.color.superficieAlterna,
                              tinta: t.color.onSuperficieSutil,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: t.espacio.microEntreTexto),
                      Text(
                        m.telefono,
                        style: context.textos.bodyMedium?.copyWith(
                          color: t.color.onSuperficieSutil,
                        ),
                      ),
                      if (m.esAdmin) ...[
                        SizedBox(height: t.espacio.entreElementos),
                        _Etiqueta(
                          texto: 'Administrador',
                          fondo: t.color.primarioSuave,
                          tinta: t.color.onPrimarioSuave,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: t.espacio.entreElementos),
                if (onExpulsar != null)
                  IconButton(
                    onPressed: onExpulsar,
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Sacar de la comunidad',
                    color: t.color.peligro,
                    iconSize: t.tamano.iconoGrande,
                    constraints: BoxConstraints(
                      minWidth: t.tamano.areaTactilMinima,
                      minHeight: t.tamano.areaTactilMinima,
                    ),
                  )
                else
                  Icon(
                    Icons.content_copy_outlined,
                    size: context.escalarAdorno(t.tamano.iconoMedio),
                    color: t.color.onSuperficieSutil,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({
    required this.texto,
    required this.fondo,
    required this.tinta,
  });

  final String texto;
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.espacio.entreElementos,
        vertical: t.espacio.microEntreTexto,
      ),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(t.radio.circular),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textos.labelSmall?.copyWith(color: tinta),
      ),
    );
  }
}
