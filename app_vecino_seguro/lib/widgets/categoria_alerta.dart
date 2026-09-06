import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';

/// ============================================================================
/// CLASIFICACIÓN DE ALERTAS
/// ============================================================================
///
/// Principio de diseño: **el icono identifica el tipo, el color indica la
/// urgencia, y el texto lo dice explícitamente.**
///
/// Tres canales independientes en lugar de uno solo. Esto responde a dos
/// problemas distintos:
///
/// 1. **Legibilidad.** Con un único icono y un único color, todas las alertas
///    activas se veían iguales y el usuario no podía distinguir un incendio de
///    un ruido molesto sin leer el título completo.
///
/// 2. **Accesibilidad (WCAG 1.4.1 "Uso del color").** El color no puede ser el
///    único medio para transmitir información: quien no distingue rojo de ámbar
///    debe recibir el mismo mensaje. Por eso la urgencia también se anuncia
///    con una etiqueta de texto visible y en la descripción semántica.
/// ============================================================================

/// Nivel de urgencia. Determina **el color**.
///
/// Deliberadamente son solo cuatro: más niveles diluirían la señal y harían que
/// el rojo dejara de significar "atiende esto ahora".
enum NivelUrgencia {
  /// Riesgo inmediato para la vida o los bienes. Consume los tokens de peligro.
  critica('Crítica'),

  /// Situación que requiere atención pronta pero no inmediata.
  alta('Alta'),

  /// Incidencia que conviene conocer, sin urgencia.
  media('Media'),

  /// Informativa o de convivencia.
  informativa('Informativa');

  const NivelUrgencia(this.etiqueta);

  /// Texto visible. Hace que la urgencia no dependa solo del color.
  final String etiqueta;
}

/// Categoría de la alerta. Determina **el icono**.
///
/// El backend envía `tipo_alerta` como texto libre, así que la categoría se
/// deduce por palabras clave con [CategoriaAlerta.desdeTexto]. Cualquier texto
/// no reconocido cae en [otro], nunca produce un error.
enum CategoriaAlerta {
  robo(
    icono: Icons.dangerous_outlined,
    urgencia: NivelUrgencia.critica,
    nombre: 'Robo',
    claves: ['robo', 'hurto', 'asalt', 'atrac', 'ladron', 'ladrón'],
  ),
  incendio(
    icono: Icons.local_fire_department_outlined,
    urgencia: NivelUrgencia.critica,
    nombre: 'Incendio',
    claves: ['incendio', 'fuego', 'human', 'quema'],
  ),
  emergenciaMedica(
    icono: Icons.medical_services_outlined,
    urgencia: NivelUrgencia.critica,
    nombre: 'Emergencia médica',
    claves: ['medic', 'médic', 'salud', 'herid', 'ambulancia', 'accidente'],
  ),
  violencia(
    icono: Icons.report_gmailerrorred_outlined,
    urgencia: NivelUrgencia.critica,
    nombre: 'Violencia',
    claves: ['violencia', 'agres', 'pelea', 'riña'],
  ),
  sospechoso(
    icono: Icons.visibility_outlined,
    urgencia: NivelUrgencia.alta,
    nombre: 'Actividad sospechosa',
    claves: ['sospech', 'merode', 'extrañ', 'desconocid'],
  ),
  vehiculo(
    icono: Icons.directions_car_outlined,
    urgencia: NivelUrgencia.media,
    nombre: 'Vehículo',
    claves: ['vehicul', 'vehícul', 'carro', 'auto', 'moto', 'placa'],
  ),
  serviciosBasicos(
    icono: Icons.bolt_outlined,
    urgencia: NivelUrgencia.media,
    nombre: 'Servicios básicos',
    claves: ['luz', 'agua', 'energia', 'energía', 'alumbrado', 'fuga', 'cable'],
  ),
  mascota(
    icono: Icons.pets_outlined,
    urgencia: NivelUrgencia.informativa,
    nombre: 'Mascota',
    claves: ['mascota', 'perro', 'gato', 'animal'],
  ),
  ruido(
    icono: Icons.volume_up_outlined,
    urgencia: NivelUrgencia.informativa,
    nombre: 'Ruido',
    claves: ['ruido', 'fiesta', 'música', 'musica', 'escandal'],
  ),
  otro(
    icono: Icons.shield_outlined,
    urgencia: NivelUrgencia.media,
    nombre: 'Otra alerta',
    claves: [],
  ),

  /// Disparada por el gesto de pánico (triple pulsación de volumen), no por
  /// texto libre. Nunca se deduce por palabras clave: `TarjetaAlerta` la
  /// fuerza directamente cuando la alerta trae `es_panico: true`, porque el
  /// backend etiqueta el `tipo_alerta` como "Emergencia (botón de pánico)" y
  /// ese texto no debe competir con las claves de las demás categorías.
  panico(
    icono: Icons.emergency_outlined,
    urgencia: NivelUrgencia.critica,
    nombre: 'Emergencia',
    claves: [],
  );

  const CategoriaAlerta({
    required this.icono,
    required this.urgencia,
    required this.nombre,
    required this.claves,
  });

  /// Icono distintivo de la categoría.
  final IconData icono;

  /// Urgencia asociada, que resuelve el color.
  final NivelUrgencia urgencia;

  /// Nombre legible de la categoría, usado en la descripción semántica.
  final String nombre;

  /// Palabras clave que la identifican dentro del texto libre del backend.
  final List<String> claves;

  /// Deduce la categoría a partir del `tipo_alerta` que envía la API.
  ///
  /// La comparación es sobre minúsculas y por coincidencia parcial, de modo que
  /// "Robo en la vía pública" y "ROBO" resuelven igual. El orden de declaración
  /// del enum define la prioridad: las categorías críticas se evalúan primero,
  /// así "accidente con incendio" gana la lectura más urgente.
  factory CategoriaAlerta.desdeTexto(String tipoAlerta) {
    final texto = tipoAlerta.toLowerCase().trim();
    for (final categoria in CategoriaAlerta.values) {
      if (categoria.claves.any(texto.contains)) return categoria;
    }
    return CategoriaAlerta.otro;
  }
}

/// Resuelve los colores de una urgencia desde los tokens del tema.
///
/// Vive aquí y no en cada widget para que la asociación urgencia → color se
/// defina una sola vez. Todos los pares están verificados contra WCAG por
/// `herramientas/verificar_contraste.js`.
extension ColoresDeUrgencia on NivelUrgencia {
  /// Relleno del avatar y del distintivo.
  Color relleno(BuildContext context) {
    final c = context.tokens.color;
    return switch (this) {
      NivelUrgencia.critica => c.peligroSuave,
      NivelUrgencia.alta => c.advertenciaSuave,
      NivelUrgencia.media => c.primarioSuave,
      NivelUrgencia.informativa => c.superficieAlterna,
    };
  }

  /// Texto e iconos sobre [relleno]. Contraste mínimo verificado: 5.09:1.
  Color tinta(BuildContext context) {
    final c = context.tokens.color;
    return switch (this) {
      NivelUrgencia.critica => c.onPeligroSuave,
      NivelUrgencia.alta => c.onAdvertenciaSuave,
      NivelUrgencia.media => c.onPrimarioSuave,
      NivelUrgencia.informativa => c.onSuperficieSutil,
    };
  }

  /// Color de énfasis sobre la superficie de la tarjeta, para el título.
  /// Solo las urgencias críticas y altas tiñen el título; las demás usan el
  /// color de texto normal, para no convertir la lista en un semáforo.
  Color? enfasisTitulo(BuildContext context) {
    final c = context.tokens.color;
    return switch (this) {
      NivelUrgencia.critica => c.peligro,
      NivelUrgencia.alta => c.advertencia,
      NivelUrgencia.media => null,
      NivelUrgencia.informativa => null,
    };
  }
}
