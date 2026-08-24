import 'package:flutter/material.dart';

import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import '../widgets/vista_estado.dart';

/// Pantalla de arranque.
///
/// Restaura la sesión guardada y consulta el perfil para saber a qué pantalla
/// entrar. Existe como pantalla propia, y no como lógica dentro de `main`,
/// porque el arranque tiene sus propios estados: puede tardar, puede fallar por
/// falta de red, y en ese caso el vecino necesita poder reintentar.
///
/// Sin ella, la app mostraría el ingreso durante un instante en cada apertura,
/// incluso teniendo sesión válida.
class PantallaArranque extends StatefulWidget {
  const PantallaArranque({super.key});

  @override
  State<PantallaArranque> createState() => _PantallaArranqueState();
}

class _PantallaArranqueState extends State<PantallaArranque> {
  EstadoVista<bool> _estado = const VistaCargando();

  @override
  void initState() {
    super.initState();
    // Se difiere al primer frame: `initState` no puede leer el contexto
    // heredado del que cuelgan las dependencias.
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrancar());
  }

  Future<void> _arrancar() async {
    if (!mounted) return;
    setState(() => _estado = const VistaCargando());

    final servicios = context.servicios;
    final sesion = servicios.sesion;

    final token = await sesion.restaurarToken();

    // Sin token guardado: no hay nada que validar. La guardia del enrutador
    // llevará al ingreso en cuanto la sesión pase a `sinSesion`.
    if (token == null) return;

    try {
      // Valida el token contra el servidor y trae el estado de pertenencia.
      // Si caducó, el cliente responde con un error no recuperable y ya cerró
      // la sesión por su cuenta.
      await servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;

      // Sesión inválida: no es un error que el vecino pueda reintentar. Se deja
      // que la guardia lo lleve al ingreso.
      if (!e.esRecuperable) return;

      // Fallo de red con una sesión probablemente válida: se ofrece reintentar
      // en lugar de expulsarlo al ingreso, que le haría escribir la contraseña
      // por un problema de conexión.
      setState(() => _estado = VistaError(e.mensaje));
    }
  }

  Future<void> _cerrarSesion() async {
    await context.sesion.cerrar();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      body: SafeArea(
        child: VistaEstado<bool>(
          estado: _estado,
          onReintentar: _arrancar,
          constructorContenido: (_, _) => const SizedBox.shrink(),
        ),
      ),
      // Salida alterna cuando el servidor no responde: permite volver al
      // ingreso sin quedarse encerrado en la pantalla de arranque.
      bottomNavigationBar: _estado is VistaError<bool>
          ? Padding(
              padding: EdgeInsets.all(t.espacio.margenPantalla),
              child: BotonAccion(
                texto: 'Ingresar con otra cuenta',
                icono: Icons.login,
                variante: VarianteBoton.secundario,
                onPressed: _cerrarSesion,
              ),
            )
          : null,
    );
  }
}
