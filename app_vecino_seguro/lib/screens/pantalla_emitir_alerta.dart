import 'package:flutter/material.dart';

import '../servicios/borrador_alerta.dart';
import '../dominio/fallo_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import '../widgets/campo_texto.dart';
import '../widgets/categoria_alerta.dart';
import '../servicios/gestor_permisos.dart';
import '../servicios/servicio_ubicacion.dart';
import '../widgets/dialogo_confirmacion.dart';
import '../widgets/flujo_permiso.dart';
import '../widgets/selector_categoria.dart';

/// **P5 — Emitir alerta**
///
/// Consume `POST /api/alertas/emitir`.
///
/// Es la funcionalidad central del producto. Dos decisiones la gobiernan:
///
/// 1. **El selector se genera desde `CategoriaAlerta.values`**, el mismo `enum`
///    que usa el muro para mostrarlas. Emisión y visualización comparten una
///    única fuente de verdad y no pueden divergir.
///
/// 2. **La confirmación es obligatoria.** Emitir notifica a toda la comunidad y
///    no se puede deshacer. Sin ese paso, un toque accidental erosiona la
///    confianza de todos los vecinos, que acaban ignorando las alertas.
///
/// 3. **Lo escrito no se pierde al salir.** La categoría y el detalle se
///    guardan en [BorradorAlerta], que vive fuera de esta pantalla. Ir al muro
///    a comprobar si alguien ya avisó y volver es un gesto natural; perder el
///    texto por hacerlo, no.
class PantallaEmitirAlerta extends StatefulWidget {
  const PantallaEmitirAlerta({super.key});

  @override
  State<PantallaEmitirAlerta> createState() => _PantallaEmitirAlertaState();
}

class _PantallaEmitirAlertaState extends State<PantallaEmitirAlerta> {
  final _descripcionCtrl = TextEditingController();

  CategoriaAlerta? _categoria;
  String? _errorGeneral;
  bool _enviando = false;

  /// Aviso sobre el lugar. **No es un error**: la alerta sale igual.
  ///
  /// Va en un campo aparte de [_errorGeneral] a propósito. Pintarlos con el
  /// mismo estilo haría creer al vecino que su alerta no se envió, cuando sí
  /// lo hizo; solo le faltan las coordenadas.
  String? _avisoLugar;

  /// Se resuelve en [didChangeDependencies]: `context.servicios` no está
  /// disponible todavía en `initState`.
  BorradorAlerta? _borrador;
  bool _restaurado = false;

  /// Clave de cliente del intento en curso.
  ///
  /// Se conserva entre intentos fallidos para que reintentar reutilice la misma
  /// operación en lugar de encolar una segunda. Se descarta al tener éxito.
  String? _claveEnCurso;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restaurado) return;
    _restaurado = true;

    final borrador = context.servicios.borrador;
    _borrador = borrador;
    _categoria = borrador.categoria;
    _descripcionCtrl.text = borrador.descripcion;
  }

  @override
  void dispose() {
    // El borrador NO se limpia aquí: salir de la pantalla es justamente el caso
    // que motiva su existencia.
    _descripcionCtrl.dispose();
    super.dispose();
  }

  /// Intenta obtener el lugar de la emergencia. **Nunca impide emitir.**
  ///
  /// La regla que gobierna todo este método: una alerta que no sale porque el
  /// GPS tardó es mucho peor que una alerta sin coordenadas. El lugar es un
  /// extra que ayuda a quien acude, no un requisito para avisar.
  ///
  /// Por eso cada rama termina devolviendo un resultado utilizable, y el aviso
  /// al vecino —cuando lo hay— es informativo, no un bloqueo.
  Future<ResultadoUbicacion> _obtenerLugar() async {
    final estado = await pedirPermisoConExplicacion(
      context,
      Capacidad.ubicacion,
    );
    if (!mounted) return const UbicacionNoDisponible();

    if (!estado.esUsable) {
      // Sin permiso se emite igual. Solo se deja constancia en pantalla para
      // que el vecino sepa que su alerta va sin lugar, y por qué.
      setState(
        () => _avisoLugar = estado.exigeAjustes
            ? 'La alerta se enviará sin el lugar. Puedes activar la ubicación '
                  'desde los ajustes del teléfono.'
            : 'La alerta se enviará sin el lugar.',
      );
      return const UbicacionNoDisponible();
    }

    final resultado = await context.servicios.ubicacion.obtener();
    if (!mounted) return const UbicacionNoDisponible();

    // El permiso está concedido pero la ubicación del teléfono está apagada.
    // Son dos cosas independientes, y el mensaje que resuelve cada una es
    // distinto: aquí no hay que ir a los permisos, sino encender el GPS.
    if (resultado is ServicioDesactivado) {
      setState(
        () => _avisoLugar =
            'La ubicación del teléfono está apagada. La alerta se enviará '
            'sin el lugar.',
      );
    }

    return resultado;
  }

  Future<void> _emitir() async {
    if (_enviando) return;

    final categoria = _categoria;
    if (categoria == null) {
      setState(() => _errorGeneral = 'Elige primero el tipo de alerta.');
      return;
    }

    final comunidad = context.sesion.perfil?.comunidad?.nombre ?? 'tu comunidad';

    // Paso obligatorio: la acción es irreversible y alcanza a toda la comunidad.
    final confirmado = await DialogoConfirmacion.mostrar(
      context,
      titulo: '¿Emitir esta alerta?',
      mensaje:
          'Se notificará de inmediato a todos los vecinos de $comunidad. '
          'Esta acción no se puede deshacer.',
      detalle: '${categoria.nombre} · Urgencia ${categoria.urgencia.etiqueta.toLowerCase()}',
      textoConfirmar: 'Sí, emitir alerta',
      icono: categoria.icono,
    );

    if (!confirmado || !mounted) return;

    setState(() {
      _enviando = true;
      _errorGeneral = null;
    });

    // El lugar se pide AQUÍ: después de confirmar y antes de encolar. Es «el
    // momento en que la funcionalidad se va a usar», no el arranque de la app.
    // Pedirlo antes de que el vecino confirme sería pedirle un permiso para
    // algo que quizá cancele.
    final lugar = await _obtenerLugar();
    if (!mounted) return;

    try {
      final cola = context.servicios.cola;

      // Se encola SIEMPRE antes de intentar enviar. Si se enviara directo y el
      // proceso muriera entre la petición y la respuesta, no quedaría ningún
      // rastro de la emergencia. Encolar primero garantiza que lo peor que
      // puede pasar es que salga más tarde.
      //
      // Se reutiliza la clave del intento anterior si lo hubo: sin eso, pulsar
      // "Emitir" otra vez tras un error del servidor crearía una segunda alerta
      // para la misma emergencia.
      // Las coordenadas viajan DENTRO de la carga encolada. Así una alerta
      // emitida sin conexión conserva el lugar donde ocurrió la emergencia, no
      // el lugar donde estaba el teléfono cuando volvió la red: encolada en
      // casa y sincronizada en el trabajo, apuntaría al trabajo.
      _claveEnCurso = await cola.encolarAlerta(
        tipoAlerta: categoria.nombre,
        descripcion: _descripcionCtrl.text,
        claveExistente: _claveEnCurso,
        latitud: lugar.latitud,
        longitud: lugar.longitud,
      );
      if (!mounted) return;

      final resultado = await cola.drenar();
      if (!mounted) return;

      // --- Caso 3: el servidor respondió, y respondió que no --------------
      // Se queda en la pantalla con el mensaje real. Decirle "sin conexión" a
      // quien acaba de recibir un 429 o un 500 sería mentirle, y además le
      // haría creer que su alerta va a salir sola cuando quizá no.
      if (resultado.enviadas == 0 && !resultado.sinConexion) {
        setState(
          () => _errorGeneral =
              resultado.ultimoError ?? 'No pudimos emitir la alerta.',
        );
        return;
      }

      // --- Casos 1 y 2: la alerta está a salvo ----------------------------
      // Enviada, o guardada en la cola por falta de red. En ambos el vecino ya
      // no tiene que reescribir nada, así que el borrador se descarta.
      _borrador?.limpiar();
      _claveEnCurso = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultado.enviadas > 0
                ? 'Alerta emitida. Tu comunidad ya fue notificada.'
                : 'Sin conexión. Tu alerta se enviará en cuanto vuelva la red.',
          ),
        ),
      );

      // Vuelve al muro, que se refresca al recibir el control.
      //
      // `maybePop` y no `context.pop()`: si esta pantalla fuese la raíz de la
      // pila —o se montara fuera del enrutador— `pop` lanzaría una excepción
      // en lugar de no hacer nada.
      await Navigator.of(context).maybePop();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _errorGeneral = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final comunidad = context.sesion.perfil?.comunidad?.nombre;

    return Scaffold(
      appBar: AppBar(title: const Text('Emitir alerta')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(t.espacio.margenPantalla),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '¿Qué está ocurriendo?',
                      style: context.textos.titleMedium,
                    ),
                    SizedBox(height: t.espacio.entreElementos),
                    Text(
                      'Elige el tipo de alerta. Tus vecinos la verán al instante.',
                      style: context.textos.bodyMedium?.copyWith(
                        color: t.color.onSuperficieSutil,
                      ),
                    ),
                    SizedBox(height: t.espacio.separacionSeccion),

                    if (_errorGeneral != null) ...[
                      _AvisoError(mensaje: _errorGeneral!),
                      SizedBox(height: t.espacio.entreGrupos),
                    ],

                    if (_avisoLugar != null) ...[
                      _AvisoLugar(mensaje: _avisoLugar!),
                      SizedBox(height: t.espacio.entreGrupos),
                    ],

                    SelectorCategoria(
                      // "Emergencia" queda fuera: esa categoría es exclusiva
                      // del gesto de pánico, nunca una elección manual.
                      categorias: CategoriaAlerta.values
                          .where((c) => c != CategoriaAlerta.panico)
                          .toList(),
                      seleccionada: _categoria,
                      habilitado: !_enviando,
                      onSeleccionar: (categoria) => setState(() {
                        _categoria = categoria;
                        _borrador?.categoria = categoria;
                        _errorGeneral = null;
                      }),
                    ),

                    SizedBox(height: t.espacio.separacionSeccion),

                    CampoTexto(
                      controlador: _descripcionCtrl,
                      etiqueta: 'Detalle (opcional)',
                      pista: 'Frente a la casa 12, sujeto de camiseta roja...',
                      icono: Icons.notes_outlined,
                      habilitado: !_enviando,
                      maxLineas: 3,
                      accionTeclado: TextInputAction.done,
                      // Sin `setState`: el controlador ya repinta el campo, y
                      // aquí solo se replica el texto en el borrador.
                      onCambio: (texto) => _borrador?.descripcion = texto,
                    ),

                    SizedBox(height: t.espacio.entreGrupos),

                    if (comunidad != null) _AvisoAlcance(comunidad: comunidad),
                  ],
                ),
              ),
            ),

            // El botón vive fuera del área desplazable: en una emergencia debe
            // estar siempre visible, sin obligar a buscarlo con el dedo.
            Padding(
              padding: EdgeInsets.all(t.espacio.margenPantalla),
              child: BotonAccion(
                texto: 'Emitir alerta',
                icono: Icons.campaign_outlined,
                variante: VarianteBoton.peligro,
                cargando: _enviando,
                etiquetaSemantica: _categoria == null
                    ? 'Emitir alerta. Elige primero el tipo.'
                    : 'Emitir alerta de ${_categoria!.nombre} a toda la comunidad',
                onPressed: _emitir,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recordatorio del alcance real de la acción.
class _AvisoAlcance extends StatelessWidget {
  const _AvisoAlcance({required this.comunidad});

  final String comunidad;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.all(t.espacio.entreGrupos),
      decoration: BoxDecoration(
        color: t.color.advertenciaSuave,
        borderRadius: t.radio.brControl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.campaign_outlined,
              color: t.color.onAdvertenciaSuave,
              size: context.escalarAdorno(t.tamano.iconoGrande),
            ),
          ),
          SizedBox(width: t.espacio.entreElementos),
          Expanded(
            child: Text(
              'Se notificará a todos los vecinos de $comunidad.',
              style: context.textos.bodySmall?.copyWith(
                color: t.color.onAdvertenciaSuave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error de emisión, anunciado como región en vivo.
/// Aviso sobre el lugar de la emergencia.
///
/// Usa los tokens de **advertencia**, no los de peligro, y el icono de
/// información. La distinción no es decorativa: rojo y «error» le dirían al
/// vecino que su alerta falló, cuando en realidad se envió y solo le faltan las
/// coordenadas. En una app de seguridad, hacer dudar de que el aviso salió es
/// peor que no decir nada.
class _AvisoLugar extends StatelessWidget {
  const _AvisoLugar({required this.mensaje});

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
          color: t.color.advertenciaSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.place_outlined,
                color: t.color.onAdvertenciaSuave,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                mensaje,
                style: context.textos.bodyMedium?.copyWith(
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

class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.mensaje});

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
