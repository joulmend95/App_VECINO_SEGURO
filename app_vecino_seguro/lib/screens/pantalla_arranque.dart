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

    // Restaura token y perfil guardados. Si ambos estaban, la sesión ya quedó
    // autenticada aquí mismo y la guardia del enrutador está llevando al vecino
    // al muro mientras se ejecuta el resto de este método.
    final token = await sesion.restaurarSesion();

    // Sin token guardado: no hay nada que validar. La guardia del enrutador
    // llevará al ingreso en cuanto la sesión pase a `sinSesion`.
    if (token == null) return;

    final entroConPerfilGuardado = sesion.autenticado;

    try {
      // Valida el token contra el servidor y trae el estado de pertenencia
      // actual. Sigue siendo necesario aunque ya se haya entrado: el perfil en
      // caché puede ser viejo —el administrador pudo aprobar la solicitud
      // mientras tanto—, y si el token caducó el cliente cierra la sesión.
      await servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;

      // Sesión inválida: no es un error que el vecino pueda reintentar. Se deja
      // que la guardia lo lleve al ingreso.
      if (!e.esRecuperable) return;

      // Sin red pero con perfil guardado: **no se bloquea**. El vecino ya está
      // dentro, viendo las alertas que tiene en la base local; obligarle a
      // reintentar aquí sería negarle el acceso a datos que están en su propio
      // teléfono. La antigüedad de lo que ve se la indica el muro.
      if (entroConPerfilGuardado && e.esSinConexion) return;

      // Fallo de red sin perfil guardado: se ofrece reintentar en lugar de
      // expulsarlo al ingreso, que le haría escribir la contraseña por un
      // problema de conexión.
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
