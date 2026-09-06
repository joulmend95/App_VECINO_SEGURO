import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../modelos/alerta.dart';
import '../navegacion/rutas.dart';
import '../servicios/almacen_local.dart';
import '../servicios/cola_sincronizacion.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../servicios/servicio_alertas.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import '../widgets/campo_texto.dart';
import '../widgets/categoria_alerta.dart';
import '../widgets/dialogo_confirmacion.dart';
import '../widgets/tarjeta_alerta.dart';
import '../widgets/vista_estado.dart';

/// **P4 — Muro de Alertas de la Comunidad**
///
/// Consume `GET /api/alertas/comunidad`.
///
/// Está ensamblada **exclusivamente** con componentes del catálogo:
/// [CampoTexto], [TarjetaAlerta], [BotonAccion] y [VistaEstado].
/// No declara ni un color, ni un tamaño de fuente, ni un radio literal: todo
/// lo obtiene de `context.tokens` y `context.textos`.
class PantallaMuroAlertas extends StatefulWidget {
  const PantallaMuroAlertas({super.key, this.api});

  /// Inyectable para pruebas. En producción se toma el servicio compartido del
  /// árbol de dependencias, para que toda la app use una sola sesión.
  final ServicioAlertas? api;

  @override
  State<PantallaMuroAlertas> createState() => _PantallaMuroAlertasState();
}

class _PantallaMuroAlertasState extends State<PantallaMuroAlertas> {
  ServicioAlertas? _apiInyectada;
  late final TextEditingController _buscarCtrl;

  ServicioAlertas get _api => _apiInyectada ?? context.servicios.alertas;

  /// Un único estado indivisible: no existe "cargando y con error a la vez".
  EstadoVista<List<Alerta>> _estado = const VistaCargando();

  /// Alertas tal como llegaron del servidor, antes de filtrar.
  List<Alerta> _todas = const [];
  String _filtro = '';
  bool _refrescando = false;

  /// Notificaciones sin leer, para el indicador de la barra superior.
  int _noLeidas = 0;

  /// Cuánto hace que se guardaron estos datos. `null` ⇒ vienen del servidor.
  ///
  /// Es lo que decide si se muestra el aviso de datos desactualizados. Que sea
  /// nulo cuando son frescos, y no un `bool` aparte, evita el estado imposible
  /// de "datos frescos con antigüedad de 20 minutos".
  Duration? _antiguedad;

  /// Alertas escritas sin conexión que todavía no llegaron al servidor.
  List<OperacionPendiente> _pendientes = const [];

  /// Consulta el contador sin bloquear la pantalla: si falla, simplemente no
  /// se muestra el indicador. No merece un mensaje de error.
  Future<void> _contarNoLeidas() async {
    try {
      final bandeja = await context.servicios.notificaciones.obtenerBandeja();
      if (!mounted) return;
      setState(() => _noLeidas = bandeja.noLeidas);
    } on ExcepcionApi {
      // Silencio deliberado.
    }
  }

  @override
  void initState() {
    super.initState();
    _apiInyectada = widget.api;
    _buscarCtrl = TextEditingController();
    // Se difiere al primer frame: la carga necesita el contexto heredado del
    // que cuelgan las dependencias, y `initState` todavía no puede leerlo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargar();
      _contarNoLeidas();
      _escucharCola();
    });
  }

  ColaSincronizacion? _cola;

  /// Recarga el muro cuando la cola consigue enviar lo que tenía pendiente.
  ///
  /// Sin esto, al volver la red la alerta salía de verdad pero la pantalla
  /// seguía anunciando «1 alerta pendiente de envío» hasta que el vecino
  /// refrescaba a mano — justo el momento en que menos ganas tiene de dudar de
  /// si su aviso salió o no.
  void _escucharCola() {
    if (_apiInyectada != null) return; // Pantalla montada suelta en pruebas.
    _cola = context.servicios.cola..addListener(_alCambiarLaCola);
  }

  void _alCambiarLaCola() {
    if (!mounted) return;
    _cargar(esRefresco: true);
  }

  @override
  void dispose() {
    // El componente CampoTexto no posee el controlador: liberarlo es
    // responsabilidad de quien lo crea.
    //
    // El cliente HTTP NO se cierra aquí: es compartido por toda la app y lo
    // gestiona el contenedor de dependencias.
    _cola?.removeListener(_alCambiarLaCola);
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool esRefresco = false}) async {
    if (!esRefresco) setState(() => _estado = const VistaCargando());
    if (esRefresco) setState(() => _refrescando = true);

    try {
      final respuesta = await _api.obtenerAlertasComunidad();
      if (!mounted) return;
      _todas = respuesta.alertas;
      // `esLocal` significa que el servidor no respondió y esto salió de la
      // base del teléfono. El vecino tiene derecho a saberlo antes de decidir
      // que "no ha pasado nada en el barrio".
      _antiguedad = respuesta.antiguedad;
      await _leerPendientes();
      if (!mounted) return;
      setState(() {
        _estado = _calcularEstado();
        _refrescando = false;
      });
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = VistaError(e.mensaje);
        _refrescando = false;
      });
    }
  }

  /// Lee la cola local. Falla en silencio: no poder mostrar los pendientes no
  /// justifica romper el muro.
  Future<void> _leerPendientes() async {
    if (_apiInyectada != null) return; // Pantalla montada suelta en pruebas.
    try {
      _pendientes = await context.servicios.cola.pendientes();
    } catch (_) {
      _pendientes = const [];
    }
  }

  /// Traduce los datos crudos al estado de la vista.
  ///
  /// Distingue dos vacíos distintos, que para el usuario NO son lo mismo:
  /// no hay alertas en la comunidad, versus el filtro no encontró nada.
  EstadoVista<List<Alerta>> _calcularEstado() {
    if (_todas.isEmpty) return const VistaVacia();

    final visibles = _filtrar(_todas, _filtro);
    if (visibles.isEmpty) return const VistaVacia();

    return VistaConDatos(visibles);
  }

  static List<Alerta> _filtrar(List<Alerta> alertas, String texto) {
    final q = texto.trim().toLowerCase();
    if (q.isEmpty) return alertas;
    return alertas
        .where(
          (a) =>
              a.tipoAlerta.toLowerCase().contains(q) ||
              a.nombreVecino.toLowerCase().contains(q),
        )
        .toList();
  }

  void _alCambiarFiltro(String valor) {
    setState(() {
      _filtro = valor;
      // El filtro no vuelve a pedir datos: solo re-evalúa el estado local.
      // Reintentar un error de red no es lo mismo que escribir en el buscador.
      if (_estado is! VistaError) _estado = _calcularEstado();
    });
  }

  bool get _filtroSinResultados =>
      _todas.isNotEmpty && _filtro.trim().isNotEmpty;

  /// Abandona la comunidad por voluntad propia.
  ///
  /// El servidor rechaza la salida si eres el administrador y quedan otros
  /// vecinos: la comunidad se quedaría sin nadie que apruebe solicitudes. Ese
  /// mensaje se muestra tal cual, porque explica el motivo mejor que uno
  /// genérico.
  Future<void> _salirDeComunidad() async {
    final comunidad = context.sesion.perfil?.comunidad?.nombre ?? 'tu comunidad';

    final confirmado = await DialogoConfirmacion.mostrar(
      context,
      titulo: '¿Salir de la comunidad?',
      mensaje:
          'Dejarás de ver y emitir alertas de $comunidad. Para volver tendrás '
          'que solicitar el ingreso y esperar la aprobación del administrador.',
      detalle: 'Las alertas que ya emitiste seguirán en el muro.',
      textoConfirmar: 'Sí, salir',
      icono: Icons.exit_to_app,
    );

    if (!confirmado || !mounted) return;

    try {
      final mensaje = await context.servicios.comunidades.salirDeComunidad();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));

      // Refresca el perfil: pasa a SIN_COMUNIDAD y la guardia del enrutador
      // lleva sola a elegir comunidad.
      await context.servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  /// Cierra la sesión, con confirmación previa.
  ///
  /// Se confirma porque volver a entrar exige la contraseña, y en una app de
  /// emergencias quedarse fuera por un toque accidental tiene coste real.
  Future<void> _cerrarSesion() async {
    // Cerrar sesión borra el almacén local entero, y eso incluye las alertas
    // que todavía no salieron del teléfono. Destruir una petición de auxilio en
    // silencio no es aceptable: si las hay, se dice antes de preguntar.
    final pendientes = _pendientes.length;

    final confirmado = await DialogoConfirmacion.mostrar(
      context,
      titulo: '¿Cerrar sesión?',
      mensaje:
          'Dejarás de recibir alertas de tu comunidad en este teléfono hasta '
          'que vuelvas a ingresar.',
      detalle: pendientes > 0
          ? 'Tienes $pendientes ${pendientes == 1 ? "alerta" : "alertas"} sin '
                'enviar. Se perderán: conéctate antes para que salgan.'
          : 'Se borrarán del teléfono las alertas guardadas y tus datos de '
                'perfil. Se volverán a descargar al ingresar.',
      esDestructiva: pendientes > 0,
      textoConfirmar: 'Cerrar sesión',
      icono: Icons.logout,
    );

    if (!confirmado || !mounted) return;

    // `Sesion.cerrar` vacía el almacén cifrado y delega en `Servicios` el
    // borrado de la base local, el borrador y las preferencias; después notifica
    // y la guardia del enrutador lleva al ingreso sola. El servicio de push se
    // da de baja desde `main.dart`, que escucha el mismo cambio de sesión.
    await context.sesion.cerrar();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // El nombre de la comunidad viene del perfil de la sesión: el vecino ve a
    // cuál está emitiendo, que en una app de emergencias no es un detalle.
    final comunidad = context.sesion.perfil?.comunidad?.nombre;

    return Scaffold(
      appBar: AppBar(
        title: Text(comunidad ?? 'Alertas de mi comunidad'),
        actions: [
          // Notificaciones, con contador de no leídas.
          IconButton(
            onPressed: () async {
              await context.push(Rutas.notificaciones);
              if (mounted) _contarNoLeidas();
            },
            icon: Badge(
              isLabelVisible: _noLeidas > 0,
              label: Text('$_noLeidas'),
              backgroundColor: t.color.peligroRelleno,
              textColor: t.color.onPeligroRelleno,
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: _noLeidas > 0
                ? 'Notificaciones, $_noLeidas sin leer'
                : 'Notificaciones',
            iconSize: t.tamano.iconoGrande,
            constraints: BoxConstraints(
              minWidth: t.tamano.areaTactilMinima,
              minHeight: t.tamano.areaTactilMinima,
            ),
          ),
          IconButton(
            onPressed: _refrescando ? null : () => _cargar(esRefresco: true),
            icon: const Icon(Icons.refresh),
            // Área táctil e etiqueta semántica explícitas: un IconButton sin
            // tooltip se anuncia como "botón" sin decir qué hace.
            tooltip: 'Actualizar alertas',
            iconSize: t.tamano.iconoGrande,
            constraints: BoxConstraints(
              minWidth: t.tamano.areaTactilMinima,
              minHeight: t.tamano.areaTactilMinima,
            ),
          ),
          // Menú: agrupa lo que no cabe en la barra. Con cuatro iconos sueltos
          // el título de la comunidad quedaba sin espacio.
          _MenuVecino(
            onPerfil: () => context.push(Rutas.perfil),
            onMiembros: () => context.push(Rutas.miembros),
            onSalirComunidad: _salirDeComunidad,
            onSolicitudes: () => context.push(Rutas.solicitudes),
            onPanico: () => context.push(Rutas.ajustesPanico),
            onCerrarSesion: _cerrarSesion,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- Aviso de datos guardados ---
            // Va ARRIBA del todo, antes del buscador: si el vecino está viendo
            // una foto de hace veinte minutos tiene que saberlo antes de
            // concluir que en su barrio no ha pasado nada.
            if (_antiguedad != null)
              _AvisoSinConexion(
                antiguedad: _antiguedad!,
                pendientes: _pendientes.length,
              ),

            // --- Buscador (componente del catálogo) ---
            Padding(
              padding: EdgeInsets.fromLTRB(
                t.espacio.margenPantalla,
                t.espacio.entreGrupos,
                t.espacio.margenPantalla,
                t.espacio.entreElementos,
              ),
              child: CampoTexto(
                controlador: _buscarCtrl,
                etiqueta: 'Buscar alerta',
                pista: 'Por tipo o por vecino',
                icono: Icons.search,
                tipoTeclado: TextInputType.text,
                accionTeclado: TextInputAction.search,
                onCambio: _alCambiarFiltro,
                accionSufijo: _filtro.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _buscarCtrl.clear();
                          _alCambiarFiltro('');
                        },
                      ),
              ),
            ),

            // --- Contenido: los 4 estados los resuelve el catálogo ---
            Expanded(
              child: VistaEstado<List<Alerta>>(
                estado: _estado,
                mensajeVacio: _filtroSinResultados
                    ? 'Sin resultados para "$_filtro"'
                    : 'Todo tranquilo por aquí',
                detalleVacio: _filtroSinResultados
                    ? 'Prueba con otro tipo de alerta o el nombre de un vecino.'
                    : 'No hay alertas activas en tu comunidad en este momento.',
                iconoVacio: _filtroSinResultados
                    ? Icons.search_off
                    : Icons.verified_user_outlined,
                onReintentar: () => _cargar(),
                accionVacio: _filtroSinResultados
                    ? BotonAccion(
                        texto: 'Limpiar búsqueda',
                        icono: Icons.close,
                        variante: VarianteBoton.secundario,
                        anchoCompleto: false,
                        onPressed: () {
                          _buscarCtrl.clear();
                          _alCambiarFiltro('');
                        },
                      )
                    : null,
                constructorContenido: (context, alertas) =>
                    _ListaAlertas(alertas: alertas, onRefrescar: _cargar),
              ),
            ),

            // --- Acción principal ---
            Padding(
              padding: EdgeInsets.all(t.espacio.margenPantalla),
              child: BotonAccion(
                texto: 'Emitir alerta de emergencia',
                icono: Icons.warning_amber_rounded,
                variante: VarianteBoton.peligro,
                etiquetaSemantica:
                    'Emitir alerta de emergencia a toda la comunidad',
                // `push` y no `go`: al volver de emitir se regresa al muro, en
                // lugar de reemplazarlo en la pila de navegación.
                onPressed: () async {
                  await context.push(Rutas.emitirAlerta);
                  // Al volver puede haber una alerta nueva.
                  if (mounted) await _cargar(esRefresco: true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista de alertas con arrastrar-para-refrescar.
///
/// Se extrae como widget aparte para que el `constructorContenido` de
/// [VistaEstado] reciba datos ya desempaquetados y no nulos.
class _ListaAlertas extends StatelessWidget {
  const _ListaAlertas({required this.alertas, required this.onRefrescar});

  final List<Alerta> alertas;
  final Future<void> Function() onRefrescar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return RefreshIndicator(
      onRefresh: onRefrescar,
      color: t.color.primario,
      child: ListView.separated(
        // `always` garantiza que el gesto de refrescar funcione incluso
        // cuando la lista es más corta que la pantalla.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          t.espacio.margenPantalla,
          t.espacio.entreElementos,
          t.espacio.margenPantalla,
          t.espacio.separacionSeccion,
        ),
        itemCount: alertas.length,
        separatorBuilder: (_, _) => SizedBox(height: t.espacio.entreGrupos),
        itemBuilder: (context, indice) {
          final alerta = alertas[indice];
          return TarjetaAlerta(
            tipoAlerta: alerta.tipoAlerta,
            nombreVecino: alerta.nombreVecino,
            fechaHora: alerta.fechaHora,
            // El pánico es autoritativo: se fuerza la categoría en lugar de
            // dejar que se deduzca del texto libre. Sin esto, una alerta de
            // emergencia real se mostraba como urgencia media.
            categoria: alerta.esPanico ? CategoriaAlerta.panico : null,
            // Se navega con el identificador, no con el objeto `alerta`.
            // La pantalla de detalle lo pide al servidor por su cuenta, y así
            // `/alertas/42` funciona igual venga del muro, de una notificación
            // o de reabrir la app en esa dirección.
            onTap: () => context.push(Rutas.aDetalleAlerta(alerta.idAlerta)),
            accionFinal: const _IndicadorDetalle(),
          );
        },
      ),
    );
  }
}

/// Aviso de que lo que se ve salió de la base local, no del servidor.
///
/// **Por qué el texto dice la antigüedad y no solo "sin conexión".** En una app
/// de seguridad vecinal, un muro vacío se interpreta como "no ha pasado nada".
/// Sin la antigüedad, un vecino podría estar viendo una foto de hace media hora
/// y creerla actual. La cifra es lo que le permite decidir si fiarse.
class _AvisoSinConexion extends StatelessWidget {
  const _AvisoSinConexion({required this.antiguedad, this.pendientes = 0});

  final Duration antiguedad;

  /// Alertas propias que aún no salieron del teléfono.
  final int pendientes;

  static String _describir(Duration d) {
    if (d.inMinutes < 1) return 'hace unos segundos';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final texto = pendientes > 0
        ? 'Sin conexión · datos guardados ${_describir(antiguedad)} · '
              '$pendientes ${pendientes == 1 ? "alerta pendiente" : "alertas pendientes"} de envío'
        : 'Sin conexión · datos guardados ${_describir(antiguedad)}';

    return Semantics(
      // Región en vivo: el lector de pantalla lo anuncia en cuanto aparece, sin
      // que haya que ir a buscarlo.
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: t.espacio.margenPantalla,
          vertical: t.espacio.entreGrupos,
        ),
        color: t.color.advertenciaSuave,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.cloud_off_outlined,
                size: context.escalarAdorno(t.tamano.iconoMedio),
                color: t.color.onAdvertenciaSuave,
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                texto,
                style: context.textos.bodySmall?.copyWith(
                  color: t.color.onAdvertenciaSuave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenido delegado que la pantalla inyecta en `TarjetaAlerta.accionFinal`.
///
/// Vive en la pantalla, no en el catálogo: es una decisión de este muro, no
/// una regla del sistema de diseño.
///
/// Antes se mostraba aquí un chip con el estado de la alerta, pero el backend
/// solo devuelve alertas con estado "Activa" (ver `alerta.service.ts`), así que
/// el chip repetía el mismo texto en todas las tarjetas sin aportar nada. Se
/// sustituyó por el indicador de que la tarjeta es pulsable.
class _IndicadorDetalle extends StatelessWidget {
  const _IndicadorDetalle();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return ExcludeSemantics(
      child: Icon(
        Icons.chevron_right,
        size: context.escalarAdorno(t.tamano.iconoGrande),
        color: t.color.onSuperficieSutil,
      ),
    );
  }
}

/// Menú del vecino en la barra superior.
///
/// Agrupa las acciones secundarias: sin él, la barra tenía cuatro iconos y el
/// nombre de la comunidad se truncaba en pantallas estrechas.
class _MenuVecino extends StatelessWidget {
  const _MenuVecino({
    required this.onPerfil,
    required this.onMiembros,
    required this.onSalirComunidad,
    required this.onSolicitudes,
    required this.onPanico,
    required this.onCerrarSesion,
  });

  final VoidCallback onPerfil;
  final VoidCallback onMiembros;
  final VoidCallback onSalirComunidad;
  final VoidCallback onSolicitudes;
  final VoidCallback onPanico;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final perfil = context.sesion.perfil;
    final esAdmin = perfil?.esAdmin ?? false;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Más opciones',
      iconSize: t.tamano.iconoGrande,
      onSelected: (opcion) {
        switch (opcion) {
          case 'perfil':
            onPerfil();
          case 'miembros':
            onMiembros();
          case 'salir_comunidad':
            onSalirComunidad();
          case 'solicitudes':
            onSolicitudes();
          case 'panico':
            onPanico();
          case 'salir':
            onCerrarSesion();
        }
      },
      itemBuilder: (context) => [
        // Cabecera: quién eres y en qué comunidad estás. Es pulsable y lleva al
        // perfil, que es donde se espera encontrarlo.
        PopupMenuItem<String>(
          value: 'perfil',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                perfil?.nombre ?? 'Vecino',
                style: context.textos.titleSmall,
              ),
              SizedBox(height: t.espacio.microEntreTexto),
              Text(
                esAdmin
                    ? 'Administrador · ${perfil?.comunidad?.codigo ?? ""}'
                    : 'Vecino · ${perfil?.comunidad?.codigo ?? ""}',
                style: context.textos.bodySmall,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Ver vecinos: disponible para todos los miembros, no solo el admin.
        const PopupMenuItem<String>(
          value: 'miembros',
          child: ListTile(
            leading: Icon(Icons.groups_outlined),
            title: Text('Vecinos de mi comunidad'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (esAdmin)
          const PopupMenuItem<String>(
            value: 'solicitudes',
            child: ListTile(
              leading: Icon(Icons.group_add_outlined),
              title: Text('Solicitudes para unirse'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem<String>(
          value: 'panico',
          child: ListTile(
            leading: Icon(Icons.emergency_outlined),
            title: Text('Botón de pánico'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'salir_comunidad',
          child: ListTile(
            leading: Icon(Icons.exit_to_app, color: t.color.advertencia),
            title: Text(
              'Salir de la comunidad',
              style: TextStyle(color: t.color.advertencia),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'salir',
          child: ListTile(
            leading: Icon(Icons.logout, color: t.color.peligro),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(color: t.color.peligro),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
