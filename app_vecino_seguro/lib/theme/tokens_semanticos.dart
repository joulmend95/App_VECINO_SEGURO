import 'package:flutter/material.dart';

import 'tokens_primitivos.dart';

/// ============================================================================
/// NIVEL 2 — TOKENS SEMÁNTICOS
/// ============================================================================
///
/// Asignan **intención** a los primitivos: `peligro`, `superficie`, `espacioCard`.
/// Un widget nunca pregunta "¿qué azul uso?", pregunta "¿cuál es el color
/// primario?". Eso permite que el tema claro y el oscuro intercambien los
/// primitivos por debajo sin que ningún widget se entere.
///
/// Se exponen como `ThemeExtension` para que se obtengan siempre desde el
/// árbol de widgets (`Theme.of(context)`), cumpliendo el requisito de consumir
/// los tokens desde el tema y no desde constantes globales.
/// ============================================================================

@immutable
class TokensApp extends ThemeExtension<TokensApp> {
  const TokensApp({
    required this.color,
    required this.espacio,
    required this.radio,
    required this.elevacion,
    required this.duracion,
    required this.tamano,
  });

  final ColoresSemanticos color;
  final EspaciosSemanticos espacio;
  final RadiosSemanticos radio;
  final ElevacionesSemanticas elevacion;
  final DuracionesSemanticas duracion;
  final TamanosSemanticos tamano;

  // --------------------------------------------------------------------------
  // TEMA CLARO
  // --------------------------------------------------------------------------
  static const claro = TokensApp(
    color: ColoresSemanticos(
      // Superficies
      fondo: ColoresPrimitivos.gris50,
      superficie: ColoresPrimitivos.gris0,
      superficieAlterna: ColoresPrimitivos.gris100,
      // Texto sobre superficies
      onFondo: ColoresPrimitivos.gris900,
      onSuperficie: ColoresPrimitivos.gris900,
      onSuperficieSutil: ColoresPrimitivos.gris600,
      // Marca
      primario: ColoresPrimitivos.azul600,
      primarioPresion: ColoresPrimitivos.azul700,
      onPrimario: ColoresPrimitivos.gris0,
      primarioSuave: ColoresPrimitivos.azul50,
      onPrimarioSuave: ColoresPrimitivos.azul700,
      // Peligro / emergencia
      peligro: ColoresPrimitivos.rojo600,
      peligroRelleno: ColoresPrimitivos.rojo600,
      onPeligroRelleno: ColoresPrimitivos.gris0,
      peligroSuave: ColoresPrimitivos.rojo50,
      onPeligroSuave: ColoresPrimitivos.rojo700,
      // Advertencia
      advertencia: ColoresPrimitivos.ambar700,
      advertenciaSuave: ColoresPrimitivos.ambar50,
      onAdvertenciaSuave: ColoresPrimitivos.ambar700,
      // Éxito
      exito: ColoresPrimitivos.verde700,
      exitoSuave: ColoresPrimitivos.verde50,
      // Bordes y estados
      borde: ColoresPrimitivos.gris200,
      bordeInteractivo: ColoresPrimitivos.gris600,
      foco: ColoresPrimitivos.azul600,
      deshabilitado: ColoresPrimitivos.gris500,
    ),
    espacio: EspaciosSemanticos.estandar,
    radio: RadiosSemanticos.estandar,
    elevacion: ElevacionesSemanticas.estandar,
    duracion: DuracionesSemanticas.estandar,
    tamano: TamanosSemanticos.estandar,
  );

  // --------------------------------------------------------------------------
  // TEMA OSCURO
  // --------------------------------------------------------------------------
  // Mismos nombres semánticos, primitivos distintos. Ningún widget cambia.
  static const oscuro = TokensApp(
    color: ColoresSemanticos(
      fondo: ColoresPrimitivos.noche900,
      superficie: ColoresPrimitivos.noche800,
      superficieAlterna: ColoresPrimitivos.noche700,
      onFondo: ColoresPrimitivos.gris50,
      onSuperficie: ColoresPrimitivos.gris50,
      onSuperficieSutil: ColoresPrimitivos.gris400,
      primario: ColoresPrimitivos.azul400,
      primarioPresion: ColoresPrimitivos.azul200,
      onPrimario: ColoresPrimitivos.noche900,
      primarioSuave: ColoresPrimitivos.noche700,
      onPrimarioSuave: ColoresPrimitivos.azul200,
      peligro: ColoresPrimitivos.rojo300,
      peligroRelleno: ColoresPrimitivos.rojo600,
      onPeligroRelleno: ColoresPrimitivos.gris0,
      peligroSuave: ColoresPrimitivos.noche700,
      onPeligroSuave: ColoresPrimitivos.rojo300,
      advertencia: ColoresPrimitivos.ambar300,
      advertenciaSuave: ColoresPrimitivos.noche700,
      onAdvertenciaSuave: ColoresPrimitivos.ambar300,
      exito: ColoresPrimitivos.verde300,
      exitoSuave: ColoresPrimitivos.noche700,
      borde: ColoresPrimitivos.noche600,
      bordeInteractivo: ColoresPrimitivos.gris400,
      foco: ColoresPrimitivos.azul400,
      deshabilitado: ColoresPrimitivos.gris400,
    ),
    espacio: EspaciosSemanticos.estandar,
    radio: RadiosSemanticos.estandar,
    elevacion: ElevacionesSemanticas.estandar,
    duracion: DuracionesSemanticas.estandar,
    tamano: TamanosSemanticos.estandar,
  );

  @override
  TokensApp copyWith({
    ColoresSemanticos? color,
    EspaciosSemanticos? espacio,
    RadiosSemanticos? radio,
    ElevacionesSemanticas? elevacion,
    DuracionesSemanticas? duracion,
    TamanosSemanticos? tamano,
  }) {
    return TokensApp(
      color: color ?? this.color,
      espacio: espacio ?? this.espacio,
      radio: radio ?? this.radio,
      elevacion: elevacion ?? this.elevacion,
      duracion: duracion ?? this.duracion,
      tamano: tamano ?? this.tamano,
    );
  }

  @override
  TokensApp lerp(ThemeExtension<TokensApp>? otro, double t) {
    if (otro is! TokensApp) return this;
    // Solo el color se interpola: espaciado y radio no deben animarse al
    // cambiar de tema, provocaría reflujo de layout innecesario.
    return TokensApp(
      color: color.lerp(otro.color, t),
      espacio: t < 0.5 ? espacio : otro.espacio,
      radio: t < 0.5 ? radio : otro.radio,
      elevacion: t < 0.5 ? elevacion : otro.elevacion,
      duracion: t < 0.5 ? duracion : otro.duracion,
      tamano: t < 0.5 ? tamano : otro.tamano,
    );
  }
}

/// Roles de color. Cada campo responde a "¿para qué sirve?", no a "¿qué es?".
@immutable
class ColoresSemanticos {
  const ColoresSemanticos({
    required this.fondo,
    required this.superficie,
    required this.superficieAlterna,
    required this.onFondo,
    required this.onSuperficie,
    required this.onSuperficieSutil,
    required this.primario,
    required this.primarioPresion,
    required this.onPrimario,
    required this.primarioSuave,
    required this.onPrimarioSuave,
    required this.peligro,
    required this.peligroRelleno,
    required this.onPeligroRelleno,
    required this.peligroSuave,
    required this.onPeligroSuave,
    required this.advertencia,
    required this.advertenciaSuave,
    required this.onAdvertenciaSuave,
    required this.exito,
    required this.exitoSuave,
    required this.borde,
    required this.bordeInteractivo,
    required this.foco,
    required this.deshabilitado,
  });

  /// Lienzo de la pantalla (detrás de todo).
  final Color fondo;

  /// Superficie de tarjetas, hojas y diálogos.
  final Color superficie;

  /// Superficie de segundo nivel: filas alternas, campos, chips.
  final Color superficieAlterna;

  /// Texto principal sobre [fondo]. Contraste 17.06:1.
  final Color onFondo;

  /// Texto principal sobre [superficie]. Contraste 17.85:1.
  final Color onSuperficie;

  /// Texto secundario (fechas, metadatos). Contraste 7.34:1 — sigue siendo AAA,
  /// no es "texto gris decorativo".
  final Color onSuperficieSutil;

  /// Color de marca para acciones principales. Contraste 6.70:1 con [onPrimario].
  final Color primario;

  /// Estado presionado de [primario].
  final Color primarioPresion;

  /// Texto e iconos sobre relleno [primario].
  final Color onPrimario;

  /// Relleno tenue de marca: avatares, chips informativos.
  final Color primarioSuave;

  /// Texto sobre [primarioSuave]. Contraste 8.21:1.
  final Color onPrimarioSuave;

  /// Énfasis de peligro para texto e iconos sobre superficie.
  final Color peligro;

  /// Relleno del botón de emergencia. Contraste 5.74:1 con [onPeligroRelleno].
  final Color peligroRelleno;

  /// Texto sobre [peligroRelleno].
  final Color onPeligroRelleno;

  /// Fondo tenue de bloques de error.
  final Color peligroSuave;

  /// Texto sobre [peligroSuave]. Contraste 7.24:1.
  final Color onPeligroSuave;

  /// Advertencia no bloqueante.
  final Color advertencia;

  /// Fondo tenue de advertencia.
  final Color advertenciaSuave;

  /// Texto e iconos sobre [advertenciaSuave]. Contraste 6.84:1 claro / 9.06:1 oscuro.
  final Color onAdvertenciaSuave;

  /// Confirmación de éxito.
  final Color exito;

  /// Fondo tenue de éxito.
  final Color exitoSuave;

  /// Divisor decorativo. Exento del mínimo 3:1 (WCAG 1.4.11) por no transmitir
  /// información ni delimitar un control.
  final Color borde;

  /// Contorno de controles (campos de texto, botones delineados). SÍ exige
  /// ≥3:1 porque delimita un componente interactivo. Cumple con 7.34:1.
  final Color bordeInteractivo;

  /// Anillo de foco visible.
  final Color foco;

  /// Texto y relleno de controles deshabilitados.
  final Color deshabilitado;

  ColoresSemanticos lerp(ColoresSemanticos o, double t) => ColoresSemanticos(
    fondo: Color.lerp(fondo, o.fondo, t)!,
    superficie: Color.lerp(superficie, o.superficie, t)!,
    superficieAlterna: Color.lerp(superficieAlterna, o.superficieAlterna, t)!,
    onFondo: Color.lerp(onFondo, o.onFondo, t)!,
    onSuperficie: Color.lerp(onSuperficie, o.onSuperficie, t)!,
    onSuperficieSutil: Color.lerp(onSuperficieSutil, o.onSuperficieSutil, t)!,
    primario: Color.lerp(primario, o.primario, t)!,
    primarioPresion: Color.lerp(primarioPresion, o.primarioPresion, t)!,
    onPrimario: Color.lerp(onPrimario, o.onPrimario, t)!,
    primarioSuave: Color.lerp(primarioSuave, o.primarioSuave, t)!,
    onPrimarioSuave: Color.lerp(onPrimarioSuave, o.onPrimarioSuave, t)!,
    peligro: Color.lerp(peligro, o.peligro, t)!,
    peligroRelleno: Color.lerp(peligroRelleno, o.peligroRelleno, t)!,
    onPeligroRelleno: Color.lerp(onPeligroRelleno, o.onPeligroRelleno, t)!,
    peligroSuave: Color.lerp(peligroSuave, o.peligroSuave, t)!,
    onPeligroSuave: Color.lerp(onPeligroSuave, o.onPeligroSuave, t)!,
    advertencia: Color.lerp(advertencia, o.advertencia, t)!,
    advertenciaSuave: Color.lerp(advertenciaSuave, o.advertenciaSuave, t)!,
    onAdvertenciaSuave: Color.lerp(
      onAdvertenciaSuave,
      o.onAdvertenciaSuave,
      t,
    )!,
    exito: Color.lerp(exito, o.exito, t)!,
    exitoSuave: Color.lerp(exitoSuave, o.exitoSuave, t)!,
    borde: Color.lerp(borde, o.borde, t)!,
    bordeInteractivo: Color.lerp(bordeInteractivo, o.bordeInteractivo, t)!,
    foco: Color.lerp(foco, o.foco, t)!,
    deshabilitado: Color.lerp(deshabilitado, o.deshabilitado, t)!,
  );
}

/// Espaciado por intención de uso, no por tamaño.
@immutable
class EspaciosSemanticos {
  const EspaciosSemanticos({
    required this.nulo,
    required this.microEntreTexto,
    required this.entreElementos,
    required this.entreGrupos,
    required this.interiorCard,
    required this.margenPantalla,
    required this.separacionSeccion,
    required this.vacioGrande,
  });

  static const estandar = EspaciosSemanticos(
    nulo: EspaciosPrimitivos.esp0,
    microEntreTexto: EspaciosPrimitivos.esp1, // 4  — entre líneas de un bloque
    entreElementos: EspaciosPrimitivos.esp2, // 8  — icono ↔ etiqueta
    entreGrupos: EspaciosPrimitivos.esp3, // 12 — campo ↔ campo
    interiorCard: EspaciosPrimitivos.esp4, // 16 — padding de tarjeta
    margenPantalla: EspaciosPrimitivos.esp4, // 16 — margen lateral
    separacionSeccion: EspaciosPrimitivos.esp6, // 24 — sección ↔ sección
    vacioGrande: EspaciosPrimitivos.esp10, // 40 — estados vacío/error
  );

  final double nulo;
  final double microEntreTexto;
  final double entreElementos;
  final double entreGrupos;
  final double interiorCard;
  final double margenPantalla;
  final double separacionSeccion;
  final double vacioGrande;
}

/// Radios por tipo de contenedor.
@immutable
class RadiosSemanticos {
  const RadiosSemanticos({
    required this.control,
    required this.card,
    required this.hoja,
    required this.circular,
  });

  static const estandar = RadiosSemanticos(
    control: RadiosPrimitivos.rad3, // 12 — botones y campos
    card: RadiosPrimitivos.rad4, // 16 — tarjetas
    hoja: RadiosPrimitivos.rad5, // 24 — bottom sheets
    circular: RadiosPrimitivos.radCircular,
  );

  final double control;
  final double card;
  final double hoja;
  final double circular;

  BorderRadius get brControl => BorderRadius.circular(control);
  BorderRadius get brCard => BorderRadius.circular(card);
  BorderRadius get brHoja => BorderRadius.circular(hoja);
}

/// Profundidad por intención.
@immutable
class ElevacionesSemanticas {
  const ElevacionesSemanticas({
    required this.plano,
    required this.card,
    required this.flotante,
    required this.dialogo,
  });

  static const estandar = ElevacionesSemanticas(
    plano: ElevacionesPrimitivas.elev0,
    card: ElevacionesPrimitivas.elev1,
    flotante: ElevacionesPrimitivas.elev2,
    dialogo: ElevacionesPrimitivas.elev3,
  );

  final double plano;
  final double card;
  final double flotante;
  final double dialogo;
}

/// Duraciones por intención.
@immutable
class DuracionesSemanticas {
  const DuracionesSemanticas({
    required this.retroalimentacion,
    required this.transicion,
    required this.entrada,
  });

  static const estandar = DuracionesSemanticas(
    retroalimentacion: DuracionesPrimitivas.rapida,
    transicion: DuracionesPrimitivas.media,
    entrada: DuracionesPrimitivas.lenta,
  );

  final Duration retroalimentacion;
  final Duration transicion;
  final Duration entrada;
}

/// Dimensiones por intención: tamaños de icono, área táctil y grosores.
@immutable
class TamanosSemanticos {
  const TamanosSemanticos({
    required this.iconoPequeno,
    required this.iconoMedio,
    required this.iconoGrande,
    required this.iconoIlustracion,
    required this.avatar,
    required this.areaTactilMinima,
    required this.grosorBorde,
    required this.grosorFoco,
    required this.grosorIndicador,
  });

  static const estandar = TamanosSemanticos(
    iconoPequeno: DimensionesPrimitivas.dim16, // metadatos
    iconoMedio: DimensionesPrimitivas.dim20, // dentro de botones
    iconoGrande: DimensionesPrimitivas.dim24, // barra superior
    iconoIlustracion: DimensionesPrimitivas.dim48, // estados vacío / error
    avatar: DimensionesPrimitivas.dim40,
    areaTactilMinima: AccesibilidadPrimitiva.areaTactilMinima,
    grosorBorde: DimensionesPrimitivas.dim1,
    grosorFoco: AccesibilidadPrimitiva.grosorFoco,
    grosorIndicador: DimensionesPrimitivas.dim2,
  );

  final double iconoPequeno;
  final double iconoMedio;
  final double iconoGrande;
  final double iconoIlustracion;
  final double avatar;

  /// Mínimo exigido por WCAG 2.5.5. Ningún control puede quedar por debajo.
  final double areaTactilMinima;

  final double grosorBorde;
  final double grosorFoco;
  final double grosorIndicador;
}

/// Azúcar sintáctico para leer los tokens desde cualquier widget:
/// `context.tokens.color.peligro`, `context.tokens.espacio.interiorCard`.
extension TokensDeContexto on BuildContext {
  TokensApp get tokens {
    final ext = Theme.of(this).extension<TokensApp>();
    assert(
      ext != null,
      'TokensApp no está registrado en el ThemeData. '
      'Verifica que MaterialApp use TemaApp.claro / TemaApp.oscuro.',
    );
    return ext ?? TokensApp.claro;
  }

  /// Atajo a la escala tipográfica del tema (escala con la fuente del sistema).
  TextTheme get textos => Theme.of(this).textTheme;

  /// Escala una dimensión decorativa (icono, avatar) junto con la fuente del
  /// sistema, **pero con tope**.
  ///
  /// El texto debe escalar sin límite: es contenido, y recortarlo excluiría a
  /// quien necesita la fuente grande. Un icono es otra cosa: no aporta
  /// información nueva, y dejarlo crecer al 200% le roba el ancho al texto
  /// hasta desbordar la fila en pantallas estrechas.
  ///
  /// Por eso los adornos escalan hasta [maximo] y ahí se detienen: acompañan
  /// el crecimiento del texto sin competir con él por el espacio.
  double escalarAdorno(double base, {double maximo = 1.5}) {
    final escalado = MediaQuery.textScalerOf(this).scale(base);
    return escalado.clamp(base, base * maximo);
  }
}
