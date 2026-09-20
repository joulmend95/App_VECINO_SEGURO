import 'package:flutter/material.dart';

import '../servicios/dependencias.dart';
import '../servicios/gestor_permisos.dart';
import '../theme/tokens_semanticos.dart';
import 'flujo_permiso.dart';

/// Ofrece activar las notificaciones **desde el muro**, no al iniciar sesión.
///
/// ## Por qué aquí y no en el arranque
///
/// Antes el permiso se pedía dentro de `ServicioPush.iniciar()`, que corre al
/// iniciar sesión: el vecino recibía un diálogo del sistema sin contexto
/// mientras esperaba a que cargara su muro, y el diálogo del sistema no explica
/// para qué lo quiere la aplicación. En Android, dos rechazos lo dejan denegado
/// para siempre.
///
/// Aquí el ofrecimiento está **junto a lo que explica**: la lista de alertas de
/// su comunidad. Y no bloquea nada — el muro funciona igual sin avisos.
///
/// ## Por qué se reconsulta en cada reconstrucción
///
/// El estado se consulta en `initState` y **de nuevo cada vez que la app vuelve
/// a primer plano**. Si el vecino revoca el permiso desde los ajustes del
/// teléfono, esta tarjeta reaparece sola: es la señal visible de que la app se
/// enteró.
class TarjetaAvisos extends StatefulWidget {
  const TarjetaAvisos({super.key});

  @override
  State<TarjetaAvisos> createState() => _TarjetaAvisosState();
}

class _TarjetaAvisosState extends State<TarjetaAvisos>
    with WidgetsBindingObserver {
  EstadoPermiso? _estado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _revisar();
  }

  Future<void> _revisar() async {
    final actual = await context.servicios.permisos.consultar(
      Capacidad.notificaciones,
    );
    if (!mounted || actual == _estado) return;
    setState(() => _estado = actual);
  }

  Future<void> _activar() async {
    final resultado = await pedirPermisoConExplicacion(
      context,
      Capacidad.notificaciones,
    );
    if (!mounted) return;
    setState(() => _estado = resultado);
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;

    // Mientras se consulta, o si ya está concedido, no se ocupa espacio.
    if (estado == null || estado.esUsable) return const SizedBox.shrink();

    final t = context.tokens;
    final exigeAjustes = estado.exigeAjustes;

    return Semantics(
      container: true,
      child: Container(
        margin: EdgeInsets.only(bottom: t.espacio.entreGrupos),
        padding: EdgeInsets.all(t.espacio.entreGrupos),
        decoration: BoxDecoration(
          color: t.color.primarioSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.notifications_off_outlined,
                color: t.color.onPrimarioSuave,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                exigeAjustes
                    ? 'Los avisos están desactivados. Actívalos desde los '
                          'ajustes para enterarte al instante.'
                    : 'Activa los avisos para enterarte al instante de una '
                          'alerta en tu comunidad.',
                style: context.textos.bodySmall?.copyWith(
                  color: t.color.onPrimarioSuave,
                ),
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            TextButton(
              onPressed: _activar,
              child: Text(exigeAjustes ? 'Ajustes' : 'Activar'),
            ),
          ],
        ),
      ),
    );
  }
}
