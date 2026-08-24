import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/modelos/perfil_vecino.dart';
import 'package:app_vecino_seguro/screens/pantalla_crear_comunidad.dart';
import 'package:app_vecino_seguro/screens/pantalla_esperando_aprobacion.dart';
import 'package:app_vecino_seguro/screens/pantalla_ingreso.dart';
import 'package:app_vecino_seguro/screens/pantalla_registro.dart';
import 'package:app_vecino_seguro/screens/pantalla_solicitudes.dart';
import 'package:app_vecino_seguro/screens/pantalla_unirme_comunidad.dart';
import 'package:app_vecino_seguro/servicios/sesion.dart';
import 'package:app_vecino_seguro/widgets/validador_campo.dart';

import 'ayudas_prueba.dart';

/// ============================================================================
/// FASE 2 — Ingreso, registro y flujo de comunidad con aprobación
/// ============================================================================

void main() {
  // ==========================================================================
  // VALIDADORES (funciones puras: se prueban sin montar widgets)
  // ==========================================================================
  group('Validadores', () {
    test('teléfono acepta entre 7 y 15 dígitos, con + opcional', () {
      final v = Validadores.telefono();
      expect(v('0991234567'), isNull);
      expect(v('+593991234567'), isNull);
      expect(v('1234567'), isNull);

      expect(v(''), 'El teléfono es obligatorio.');
      expect(v('123456'), contains('7 y 15'));
      expect(v('1234567890123456'), contains('7 y 15'));
      expect(v('099-123-4567'), contains('7 y 15'));
    });

    test('la contraseña NUEVA exige 8 caracteres', () {
      final v = Validadores.passwordNueva();
      expect(v('clave12345'), isNull);
      expect(v('corta'), contains('al menos 8'));
      expect(v(''), 'La contraseña es obligatoria.');
    });

    test('la contraseña de INGRESO solo exige no estar vacía', () {
      // Aplicar aquí la regla de longitud delataría el formato de las
      // contraseñas válidas y bloquearía a quien creó su cuenta antes.
      final v = Validadores.passwordExistente();
      expect(v('abc'), isNull);
      expect(v(''), 'La contraseña es obligatoria.');
    });

    test('la contraseña no se recorta: los espacios son válidos', () {
      final v = Validadores.passwordNueva();
      expect(v('   ' '     '), isNull, reason: '8 espacios son 8 caracteres');
    });

    test('el código de comunidad acepta letras, números y guiones', () {
      final v = Validadores.codigoComunidad();
      expect(v('URB-2026'), isNull);
      expect(v('LOSCEIBOS'), isNull);

      expect(v('ABC'), contains('4 y 20'));
      expect(v('URB 2026'), contains('4 y 20'));
      expect(v('URB_2026'), contains('4 y 20'));
    });

    test('coincideCon detecta contraseñas distintas', () {
      final v = Validadores.coincideCon(() => 'clave12345', 'La contraseña');
      expect(v('clave12345'), isNull);
      expect(v('otra12345'), contains('no coincide'));
      expect(v(''), 'Confirma la contraseña.');
    });

    test('combinar devuelve el primer error encontrado', () {
      final v = Validadores.combinar([
        Validadores.obligatorio('El campo'),
        Validadores.longitudMinima('El campo', 5),
      ]);
      expect(v(''), 'El campo es obligatorio.');
      expect(v('abc'), contains('al menos 5'));
      expect(v('abcdef'), isNull);
    });
  });

  // ==========================================================================
  // P3 — INGRESO
  // ==========================================================================
  group('P3 Ingreso', () {
    Future<Sesion> montar(WidgetTester tester, MockClient cliente) async {
      final sesion = sesionDePrueba();
      await sesion.restaurarToken();
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaIngreso(),
          sesion: sesion,
          cliente: cliente,
        ),
      );
      return sesion;
    }

    testWidgets('valida los campos antes de llamar al servidor', (tester) async {
      var llamadas = 0;
      final sesion = await montar(
        tester,
        servidorFalso(
          {'/api/usuarios/login': (_) => ok({'token': 't'})},
          alRecibir: (_) => llamadas++,
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Ingresar'));
      await tester.pumpAndSettle();

      expect(llamadas, 0, reason: 'no debe llamar al servidor con campos vacíos');
      expect(find.text('El teléfono es obligatorio.'), findsOneWidget);
      expect(find.text('La contraseña es obligatoria.'), findsOneWidget);
      expect(sesion.autenticado, isFalse);
    });

    testWidgets('un ingreso correcto abre la sesión', (tester) async {
      final sesion = await montar(
        tester,
        servidorFalso({
          '/api/usuarios/login': (_) => ok({
            'token': 'jwt-emitido',
            'perfil': perfilJson(estado: 'ACTIVO'),
          }),
        }),
      );

      await tester.enterText(find.byType(TextField).first, '0991234567');
      await tester.enterText(find.byType(TextField).last, 'clave12345');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ingresar'));
      await tester.pumpAndSettle();

      expect(sesion.autenticado, isTrue);
      expect(sesion.membresia, EstadoMembresia.activo);
    });

    testWidgets('credenciales incorrectas: no se señala ningún campo', (
      tester,
    ) async {
      await montar(
        tester,
        servidorFalso({
          '/api/usuarios/login': (_) => falla(401, 'Teléfono o contraseña incorrectos'),
        }),
      );

      await tester.enterText(find.byType(TextField).first, '0991234567');
      await tester.enterText(find.byType(TextField).last, 'incorrecta');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ingresar'));
      await tester.pumpAndSettle();

      // El mensaje es deliberadamente ambiguo: señalar "teléfono no existe"
      // permitiría enumerar qué vecinos están registrados.
      expect(find.text('Teléfono o contraseña incorrectos'), findsOneWidget);
    });

    testWidgets('el botón de ojo alterna la visibilidad', (tester) async {
      await montar(tester, servidorFalso({}));

      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    });
  });

  // ==========================================================================
  // P2 — REGISTRO
  // ==========================================================================
  group('P2 Registro', () {
    testWidgets('NO pide código de comunidad', (tester) async {
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaRegistro(),
          sesion: sesionDePrueba(),
          cliente: servidorFalso({}),
        ),
      );

      // El vecino existe primero y elige comunidad después: es lo que habilita
      // el flujo de aprobación por administrador.
      expect(find.text('Código de la comunidad'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('detecta contraseñas que no coinciden', (tester) async {
      var llamadas = 0;
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaRegistro(),
          sesion: sesionDePrueba(),
          cliente: servidorFalso(
            {'/api/usuarios/registro': (_) => ok({'token': 't'})},
            alRecibir: (_) => llamadas++,
          ),
        ),
      );

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Ana Vera');
      await tester.enterText(campos.at(1), '0987654321');
      await tester.enterText(campos.at(2), 'clave12345');
      await tester.enterText(campos.at(3), 'otra12345');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no coincide'), findsOneWidget);
      expect(llamadas, 0);
    });

    testWidgets('un registro correcto deja la sesión abierta', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.restaurarToken();

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaRegistro(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/usuarios/registro': (_) => ok({
              'token': 'jwt-registro',
              'perfil': perfilJson(estado: 'SIN_COMUNIDAD'),
            }),
          }),
        ),
      );

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Ana Vera');
      await tester.enterText(campos.at(1), '0987654321');
      await tester.enterText(campos.at(2), 'clave12345');
      await tester.enterText(campos.at(3), 'clave12345');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();

      expect(sesion.autenticado, isTrue);
      expect(sesion.membresia, EstadoMembresia.sinComunidad);
    });

    testWidgets('los errores del servidor se pintan en su campo', (tester) async {
      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaRegistro(),
          sesion: sesionDePrueba(),
          cliente: servidorFalso({
            '/api/usuarios/registro': (_) => http.Response(
              jsonEncode({
                'mensaje': 'Revisa los datos ingresados.',
                'errores': [
                  {'campo': 'telefono', 'mensaje': 'Ese teléfono ya está registrado.'},
                ],
              }),
              400,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          }),
        ),
      );

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Ana Vera');
      await tester.enterText(campos.at(1), '0987654321');
      await tester.enterText(campos.at(2), 'clave12345');
      await tester.enterText(campos.at(3), 'clave12345');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();

      expect(find.text('Ese teléfono ya está registrado.'), findsOneWidget);
    });
  });

  // ==========================================================================
  // P10 — UNIRME CON CÓDIGO
  // ==========================================================================
  group('P10 Unirme con código', () {
    testWidgets('verifica el código ANTES de enviar la solicitud', (
      tester,
    ) async {
      var solicitudes = 0;
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(perfilJson(estado: 'SIN_COMUNIDAD')),
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaUnirmeComunidad(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/solicitudes': (_) {
              solicitudes++;
              return ok({'mensaje': 'enviada'});
            },
            '/api/comunidades/': (_) => ok({
              'id_comunidad': 5,
              'nombre': 'Ciudadela Los Ceibos',
              'codigo': 'LOS-CEIBOS',
              'total_vecinos': 3,
            }),
          }),
        ),
      );

      await tester.enterText(find.byType(TextField), 'LOS-CEIBOS');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verificar código'));
      await tester.pumpAndSettle();

      // Primero confirma a qué comunidad va, sin haber enviado nada aún.
      expect(find.text('Ciudadela Los Ceibos'), findsOneWidget);
      expect(find.text('3 vecinos'), findsOneWidget);
      expect(solicitudes, 0);
      expect(find.text('Enviar solicitud'), findsOneWidget);
    });

    testWidgets('un código inexistente muestra el error en el campo', (
      tester,
    ) async {
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(perfilJson(estado: 'SIN_COMUNIDAD')),
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaUnirmeComunidad(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/': (_) =>
                falla(404, 'No existe ninguna comunidad con ese código.'),
          }),
        ),
      );

      await tester.enterText(find.byType(TextField), 'NO-EXISTE');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verificar código'));
      await tester.pumpAndSettle();

      expect(
        find.text('No existe ninguna comunidad con ese código.'),
        findsOneWidget,
      );
    });

    testWidgets('cambiar el código invalida la comunidad ya verificada', (
      tester,
    ) async {
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(perfilJson(estado: 'SIN_COMUNIDAD')),
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaUnirmeComunidad(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/': (_) => ok({
              'id_comunidad': 5,
              'nombre': 'Ciudadela Los Ceibos',
              'codigo': 'LOS-CEIBOS',
              'total_vecinos': 3,
            }),
          }),
        ),
      );

      await tester.enterText(find.byType(TextField), 'LOS-CEIBOS');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verificar código'));
      await tester.pumpAndSettle();
      expect(find.text('Enviar solicitud'), findsOneWidget);

      // Al editar el código, la confirmación anterior deja de ser válida: no
      // se puede enviar una solicitud a una comunidad distinta de la mostrada.
      await tester.enterText(find.byType(TextField), 'OTRO-CODIGO');
      await tester.pumpAndSettle();

      expect(find.text('Enviar solicitud'), findsNothing);
      expect(find.text('Verificar código'), findsOneWidget);
    });
  });

  // ==========================================================================
  // P1 — CREAR COMUNIDAD
  // ==========================================================================
  group('P1 Crear comunidad', () {
    testWidgets('advierte que el creador será administrador', (tester) async {
      final sesion = await sesionActiva();

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaCrearComunidad(),
          sesion: sesion,
          cliente: servidorFalso({}),
        ),
      );

      expect(find.textContaining('Serás el administrador'), findsOneWidget);
    });

    testWidgets('un código duplicado se muestra como error general', (
      tester,
    ) async {
      final sesion = await sesionActiva();

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaCrearComunidad(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades': (_) =>
                falla(409, 'Ya existe una comunidad con ese código. Elige otro.'),
          }),
        ),
      );

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Urbanización El Bosque');
      await tester.enterText(campos.at(1), 'URB-2026');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear comunidad'));
      await tester.pumpAndSettle();

      expect(
        find.text('Ya existe una comunidad con ese código. Elige otro.'),
        findsOneWidget,
      );
    });
  });

  // ==========================================================================
  // P11 — ESPERANDO APROBACIÓN
  // ==========================================================================
  group('P11 Esperando aprobación', () {
    testWidgets('muestra la comunidad a la que solicitó unirse', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(
          perfilJson(estado: 'PENDIENTE', comunidad: 'Ciudadela Los Ceibos'),
        ),
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaEsperandoAprobacion(),
          sesion: sesion,
          cliente: servidorFalso({}),
        ),
      );

      expect(find.textContaining('Ciudadela Los Ceibos'), findsOneWidget);
      expect(find.text('Esperando aprobación'), findsOneWidget);
    });

    testWidgets('comprobar detecta que el administrador ya aprobó', (
      tester,
    ) async {
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(perfilJson(estado: 'PENDIENTE')),
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaEsperandoAprobacion(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/usuarios/yo': (_) => ok(perfilJson(estado: 'ACTIVO')),
          }),
        ),
      );

      expect(sesion.membresia, EstadoMembresia.pendiente);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Comprobar ahora'));
      await tester.pumpAndSettle();

      // La sesión pasa a ACTIVO; en la app real la guardia lleva al muro.
      expect(sesion.membresia, EstadoMembresia.activo);
    });

    testWidgets('cancelar devuelve al estado sin comunidad', (tester) async {
      final sesion = sesionDePrueba();
      await sesion.iniciar(
        token: 'jwt',
        perfil: PerfilVecino.desdeJson(perfilJson(estado: 'PENDIENTE')),
      );

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaEsperandoAprobacion(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/solicitudes/mia': (_) => ok({'mensaje': 'Cancelada.'}),
            '/api/usuarios/yo': (_) => ok(perfilJson(estado: 'SIN_COMUNIDAD')),
          }),
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Cancelar y probar otro código'));
      await tester.pumpAndSettle();

      expect(sesion.membresia, EstadoMembresia.sinComunidad);
    });
  });

  // ==========================================================================
  // P12 — SOLICITUDES (administrador)
  // ==========================================================================
  group('P12 Solicitudes', () {
    Map<String, dynamic> solicitudJson(int id, String nombre, String tel) => {
      'id_solicitud': id,
      'fecha_solicitud': DateTime.now().toIso8601String(),
      'vecino': {'id_usuario': id, 'nombre': nombre, 'telefono': tel},
    };

    testWidgets('estado VACÍO cuando no hay solicitudes', (tester) async {
      final sesion = await sesionActiva(esAdmin: true);

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaSolicitudes(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/solicitudes': (_) => ok({'solicitudes': []}),
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No hay solicitudes pendientes'), findsOneWidget);
    });

    testWidgets('muestra el teléfono, para reconocer a quién se aprueba', (
      tester,
    ) async {
      final sesion = await sesionActiva(esAdmin: true);

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaSolicitudes(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/solicitudes': (_) => ok({
              'solicitudes': [solicitudJson(1, 'Carlos Loor', '0955512345')],
            }),
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Carlos Loor'), findsOneWidget);
      // Dar acceso a un desconocido es el riesgo real de esta pantalla.
      expect(find.text('0955512345'), findsOneWidget);
      expect(find.text('Aprobar'), findsOneWidget);
      expect(find.text('Rechazar'), findsOneWidget);
    });

    testWidgets('aprobar llama al servidor y recarga la lista', (tester) async {
      var aprobaciones = 0;
      var listados = 0;
      final sesion = await sesionActiva(esAdmin: true);

      final cliente = MockClient((peticion) async {
        if (peticion.method == 'PATCH') {
          aprobaciones++;
          expect(jsonDecode(peticion.body)['accion'], 'aprobar');
          return ok({'mensaje': 'Carlos Loor ya forma parte de la comunidad.'});
        }
        listados++;
        return ok({
          'solicitudes': listados == 1
              ? [solicitudJson(1, 'Carlos Loor', '0955512345')]
              : <Map<String, dynamic>>[],
        });
      });

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaSolicitudes(),
          sesion: sesion,
          cliente: cliente,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aprobar'));
      await tester.pumpAndSettle();

      expect(aprobaciones, 1);
      expect(listados, 2, reason: 'debe recargar tras resolver');
      expect(find.text('No hay solicitudes pendientes'), findsOneWidget);
    });

    testWidgets('recuerda el código de la comunidad para compartirlo', (
      tester,
    ) async {
      final sesion = await sesionActiva(esAdmin: true);

      await tester.pumpWidget(
        montarConDependencias(
          hijo: const PantallaSolicitudes(),
          sesion: sesion,
          cliente: servidorFalso({
            '/api/comunidades/solicitudes': (_) => ok({'solicitudes': []}),
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('URB-2026'), findsOneWidget);
    });
  });
}
