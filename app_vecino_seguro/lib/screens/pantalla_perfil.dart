import 'package:flutter/material.dart';

import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import '../widgets/campo_texto.dart';
import '../widgets/dialogo_confirmacion.dart';
import '../widgets/validador_campo.dart';

/// **Mi perfil**
///
/// Consume `PATCH /api/usuarios/yo` y `PATCH /api/usuarios/password`.
///
/// Se separa en dos formularios independientes a propósito: cambiar el nombre
/// es trivial, cambiar la contraseña exige la actual. Mezclarlos obligaría a
/// escribir la contraseña para corregir una tilde del nombre.
class PantallaPerfil extends StatefulWidget {
  const PantallaPerfil({super.key});

  @override
  State<PantallaPerfil> createState() => _PantallaPerfilState();
}

class _PantallaPerfilState extends State<PantallaPerfil> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _repetirCtrl = TextEditingController();

  final Map<String, String?> _errores = {};
  String? _errorDatos;
  String? _errorPassword;
  bool _guardandoDatos = false;
  bool _guardandoPassword = false;
  bool _ocultar = true;

  bool _camposIniciados = false;

  /// Campos en los que el vecino ya escribió.
  ///
  /// Nombre y teléfono llegan rellenados con sus datos actuales, así que no
  /// están vacíos y sí se validan al perder el foco. Los tres de contraseña
  /// empiezan vacíos: ahí este conjunto evita marcarlos en rojo por el simple
  /// hecho de haber pasado el foco por encima.
  final Set<String> _tocados = {};

  /// Valida un campo al abandonarlo.
  void _alValidar(String campo, TextEditingController ctrl, String? error) {
    if (ctrl.text.isEmpty && !_tocados.contains(campo)) return;
    if (_errores[campo] == error) return;
    setState(() => _errores[campo] = error);
  }

  /// Rellena los campos con los datos actuales del vecino.
  ///
  /// Va aquí y no en `initState` porque leer `context.sesion` depende de un
  /// `InheritedWidget`, y hacerlo antes de que `initState` termine es un error
  /// en Flutter: el widget no quedaría suscrito a los cambios.
  ///
  /// La bandera evita que se sobrescriba lo que el vecino esté escribiendo:
  /// este método se vuelve a llamar cada vez que cambian las dependencias, por
  /// ejemplo al girar el teléfono o al cambiar el tema.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_camposIniciados) return;

    final perfil = context.sesion.perfil;
    _nombreCtrl.text = perfil?.nombre ?? '';
    _telefonoCtrl.text = perfil?.telefono ?? '';
    _camposIniciados = true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _repetirCtrl.dispose();
    super.dispose();
  }

  void _limpiar(String campo) {
    _tocados.add(campo);
    if (_errores[campo] != null) setState(() => _errores[campo] = null);
  }

  // ---------------------------------------------------------------------------
  // DATOS PERSONALES
  // ---------------------------------------------------------------------------

  Future<void> _guardarDatos() async {
    if (_guardandoDatos) return;

    final errorNombre = Validadores.nombre()(_nombreCtrl.text);
    final errorTelefono = Validadores.telefono()(_telefonoCtrl.text);

    setState(() {
      _errores['nombre'] = errorNombre;
      _errores['telefono'] = errorTelefono;
      _errorDatos = null;
    });

    if (errorNombre != null || errorTelefono != null) return;

    final perfil = context.sesion.perfil;
    final telefonoNuevo = _telefonoCtrl.text.trim();
    final cambiaTelefono = telefonoNuevo != perfil?.telefono;

    // El teléfono es la identidad de ingreso: cambiarlo significa que a partir
    // de ahora se entra con otro número. Merece confirmación explícita.
    if (cambiaTelefono) {
      final confirmado = await DialogoConfirmacion.mostrar(
        context,
        titulo: '¿Cambiar tu teléfono?',
        mensaje:
            'A partir de ahora tendrás que ingresar con el número nuevo. '
            'Tu contraseña no cambia.',
        detalle: '${perfil?.telefono ?? ""}  →  $telefonoNuevo',
        textoConfirmar: 'Sí, cambiarlo',
        esDestructiva: false,
        icono: Icons.phone_outlined,
      );
      if (!confirmado || !mounted) return;
    }

    setState(() => _guardandoDatos = true);

    try {
      await context.servicios.usuarios.actualizarPerfil(
        nombre: _nombreCtrl.text.trim(),
        telefono: telefonoNuevo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        final porCampo = e.erroresPorCampo;
        _errores.addAll(porCampo);

        // Un 409 por teléfono ya registrado llega sin campo asociado: ese es
        // el caso que debe seguir viéndose en el bloque general.
        const conocidos = {'nombre', 'telefono'};
        final hayDesconocidos =
            porCampo.keys.any((c) => !conocidos.contains(c));
        _errorDatos = (porCampo.isEmpty || hayDesconocidos) ? e.mensaje : null;
      });
    } finally {
      if (mounted) setState(() => _guardandoDatos = false);
    }
  }

  // ---------------------------------------------------------------------------
  // CONTRASEÑA
  // ---------------------------------------------------------------------------

  Future<void> _cambiarPassword() async {
    if (_guardandoPassword) return;

    final errorActual = Validadores.passwordExistente()(_actualCtrl.text);
    final errorNueva = Validadores.passwordNueva()(_nuevaCtrl.text);
    final errorRepetir = Validadores.coincideCon(
      () => _nuevaCtrl.text,
      'La contraseña',
    )(_repetirCtrl.text);

    setState(() {
      _errores['password_actual'] = errorActual;
      _errores['password_nueva'] = errorNueva;
      _errores['repetir'] = errorRepetir;
      _errorPassword = null;
    });

    if (errorActual != null || errorNueva != null || errorRepetir != null) {
      return;
    }

    setState(() => _guardandoPassword = true);

    try {
      await context.servicios.usuarios.cambiarPassword(
        actual: _actualCtrl.text,
        nueva: _nuevaCtrl.text,
      );
      if (!mounted) return;

      _actualCtrl.clear();
      _nuevaCtrl.clear();
      _repetirCtrl.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Contraseña actualizada.')));
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        // El servidor señala `password_actual` con un 400 —no un 401— cuando
        // la contraseña actual no coincide, precisamente para que se pinte en
        // su campo en lugar de cerrar la sesión. Ver `usuario.controller.ts`.
        final porCampo = e.erroresPorCampo;
        _errores.addAll(porCampo);

        const conocidos = {'password_actual', 'password_nueva', 'repetir'};
        final hayDesconocidos =
            porCampo.keys.any((c) => !conocidos.contains(c));
        _errorPassword = (porCampo.isEmpty || hayDesconocidos) ? e.mensaje : null;
      });
    } finally {
      if (mounted) setState(() => _guardandoPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final perfil = context.sesion.perfil;
    final separador = SizedBox(height: t.espacio.entreGrupos);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(t.espacio.margenPantalla),
          children: [
            if (perfil?.comunidad != null) ...[
              _TarjetaComunidad(
                nombre: perfil!.comunidad!.nombre,
                codigo: perfil.comunidad!.codigo,
                esAdmin: perfil.esAdmin,
              ),
              SizedBox(height: t.espacio.separacionSeccion),
            ],

            // --- Datos personales ---
            _Seccion(titulo: 'Datos personales'),
            separador,

            if (_errorDatos != null) ...[
              _Aviso(mensaje: _errorDatos!),
              separador,
            ],

            CampoTexto(
              controlador: _nombreCtrl,
              etiqueta: 'Nombre completo',
              icono: Icons.person_outline,
              habilitado: !_guardandoDatos,
              textoError: _errores['nombre'],
              onCambio: (_) => _limpiar('nombre'),
              validador: Validadores.nombre(),
              onValidar: (e) => _alValidar('nombre', _nombreCtrl, e),
            ),
            separador,
            CampoTexto(
              controlador: _telefonoCtrl,
              etiqueta: 'Teléfono',
              pista: 'Con él inicias sesión',
              icono: Icons.phone_outlined,
              tipoTeclado: TextInputType.phone,
              habilitado: !_guardandoDatos,
              textoError: _errores['telefono'],
              onCambio: (_) => _limpiar('telefono'),
              validador: Validadores.telefono(),
              onValidar: (e) => _alValidar('telefono', _telefonoCtrl, e),
            ),
            separador,
            BotonAccion(
              texto: 'Guardar cambios',
              icono: Icons.save_outlined,
              cargando: _guardandoDatos,
              onPressed: _guardarDatos,
            ),

            SizedBox(height: t.espacio.separacionSeccion),
            Divider(color: t.color.borde),
            SizedBox(height: t.espacio.separacionSeccion),

            // --- Contraseña ---
            _Seccion(titulo: 'Cambiar contraseña'),
            separador,

            if (_errorPassword != null) ...[
              _Aviso(mensaje: _errorPassword!),
              separador,
            ],

            CampoTexto(
              controlador: _actualCtrl,
              etiqueta: 'Contraseña actual',
              icono: Icons.lock_outline,
              esOculto: _ocultar,
              habilitado: !_guardandoPassword,
              textoError: _errores['password_actual'],
              onCambio: (_) => _limpiar('password_actual'),
              accionSufijo: IconButton(
                onPressed: () => setState(() => _ocultar = !_ocultar),
                icon: Icon(
                  _ocultar
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _ocultar ? 'Mostrar contraseñas' : 'Ocultar contraseñas',
              ),
            ),
            separador,
            CampoTexto(
              controlador: _nuevaCtrl,
              etiqueta: 'Contraseña nueva',
              pista: 'Mínimo 8 caracteres',
              icono: Icons.lock_reset_outlined,
              esOculto: _ocultar,
              habilitado: !_guardandoPassword,
              textoError: _errores['password_nueva'],
              onCambio: (_) => _limpiar('password_nueva'),
              validador: Validadores.passwordNueva(),
              onValidar: (e) => _alValidar('password_nueva', _nuevaCtrl, e),
            ),
            separador,
            CampoTexto(
              controlador: _repetirCtrl,
              etiqueta: 'Repetir contraseña nueva',
              icono: Icons.lock_reset_outlined,
              esOculto: _ocultar,
              habilitado: !_guardandoPassword,
              accionTeclado: TextInputAction.done,
              textoError: _errores['repetir'],
              onCambio: (_) => _limpiar('repetir'),
              validador: Validadores.coincideCon(
                () => _nuevaCtrl.text,
                'La contraseña',
              ),
              onValidar: (e) => _alValidar('repetir', _repetirCtrl, e),
              onEnviar: (_) => _cambiarPassword(),
            ),
            separador,
            BotonAccion(
              texto: 'Cambiar contraseña',
              icono: Icons.key_outlined,
              cargando: _guardandoPassword,
              onPressed: _cambiarPassword,
            ),

            SizedBox(height: t.espacio.separacionSeccion),
          ],
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) =>
      Text(titulo, style: context.textos.titleMedium);
}

class _TarjetaComunidad extends StatelessWidget {
  const _TarjetaComunidad({
    required this.nombre,
    required this.codigo,
    required this.esAdmin,
  });

  final String nombre;
  final String codigo;
  final bool esAdmin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.all(t.espacio.interiorCard),
      decoration: BoxDecoration(
        color: t.color.primarioSuave,
        borderRadius: t.radio.brCard,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              esAdmin
                  ? Icons.admin_panel_settings_outlined
                  : Icons.holiday_village_outlined,
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
                  nombre,
                  style: context.textos.titleSmall?.copyWith(
                    color: t.color.onPrimarioSuave,
                  ),
                ),
                SizedBox(height: t.espacio.microEntreTexto),
                Text(
                  esAdmin ? 'Administrador · $codigo' : 'Vecino · $codigo',
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

class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(t.espacio.entreGrupos),
        decoration: BoxDecoration(
          color: t.color.peligroSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                color: t.color.onPeligroSuave,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                mensaje,
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onPeligroSuave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
