import 'package:flutter/material.dart';

/// ============================================================================
/// NIVEL 1 — TOKENS PRIMITIVOS
/// ============================================================================
///
/// Valores crudos del sistema de diseño. Describen **qué es** el valor
/// (`azul600`, `esp4`, `rad3`), nunca **para qué sirve**.
///
/// REGLA DE USO: ningún widget de la aplicación puede importar este archivo.
/// Los primitivos solo se consumen desde `tokens_semanticos.dart`, que les
/// asigna un significado. Así, cambiar la marca de azul a verde se hace en un
/// único lugar sin tocar una sola pantalla.
///
/// Todos los pares de color derivados de esta paleta fueron verificados contra
/// WCAG 2.1. La auditoría la ejecuta `herramientas/verificar_contraste.js`.
/// ============================================================================

/// Paleta cruda de color. Escalas de 50 (más claro) a 900 (más oscuro).
abstract final class ColoresPrimitivos {
  // --- Azul de marca: confianza institucional / seguridad ciudadana ---
  static const azul50 = Color(0xFFEFF4FF);
  static const azul100 = Color(0xFFDCE6FF);
  static const azul200 = Color(0xFFBCCEFF);
  static const azul400 = Color(0xFF5B7FE8);
  static const azul600 = Color(0xFF1D4ED8);
  static const azul700 = Color(0xFF1A3FA8);
  static const azul900 = Color(0xFF16277A);

  // --- Rojo: reservado EXCLUSIVAMENTE para peligro y emergencia ---
  // No se usa como color decorativo para que el botón de pánico no compita
  // visualmente con el resto de la interfaz.
  static const rojo50 = Color(0xFFFEF2F2);
  static const rojo100 = Color(0xFFFEE2E2);
  static const rojo300 = Color(0xFFFCA5A5);
  static const rojo600 = Color(0xFFC81E1E);
  static const rojo700 = Color(0xFFA31212);

  // --- Ámbar: advertencias no bloqueantes ---
  static const ambar50 = Color(0xFFFFFBEB);
  static const ambar300 = Color(0xFFFCD34D);
  static const ambar700 = Color(0xFF92400E);

  // --- Verde: confirmaciones de éxito ---
  static const verde50 = Color(0xFFECFDF5);
  static const verde300 = Color(0xFF6EE7B7);
  static const verde700 = Color(0xFF046C4E);

  // --- Neutros (tema claro) ---
  static const gris0 = Color(0xFFFFFFFF);
  static const gris50 = Color(0xFFF8FAFC);
  static const gris100 = Color(0xFFF1F5F9);
  static const gris200 = Color(0xFFE2E8F0);
  static const gris400 = Color(0xFF94A3B8);
  static const gris500 = Color(0xFF64748B);
  static const gris600 = Color(0xFF4B5768);
  static const gris700 = Color(0xFF334155);
  static const gris900 = Color(0xFF0F172A);

  // --- Neutros nocturnos (tema oscuro) ---
  static const noche900 = Color(0xFF0B1220);
  static const noche800 = Color(0xFF151E2E);
  static const noche700 = Color(0xFF263145);
  static const noche600 = Color(0xFF3A4761);
}

/// Escala de espaciado. Base 4 dp: toda distancia del sistema es múltiplo de 4,
/// lo que garantiza ritmo vertical consistente sin decisiones arbitrarias.
abstract final class EspaciosPrimitivos {
  static const esp0 = 0.0;
  static const esp1 = 4.0;
  static const esp2 = 8.0;
  static const esp3 = 12.0;
  static const esp4 = 16.0;
  static const esp5 = 20.0;
  static const esp6 = 24.0;
  static const esp8 = 32.0;
  static const esp10 = 40.0;
  static const esp12 = 48.0;
}

/// Escala de radio de borde.
abstract final class RadiosPrimitivos {
  static const rad0 = 0.0;
  static const rad1 = 4.0;
  static const rad2 = 8.0;
  static const rad3 = 12.0;
  static const rad4 = 16.0;
  static const rad5 = 24.0;
  static const radCircular = 999.0;
}

/// Escala tipográfica. Razón ≈1.2 (segunda menor) entre pasos consecutivos.
///
/// IMPORTANTE: estos son tamaños *base* en dp lógicos. Flutter los multiplica
/// por el `textScaler` del sistema, por lo que el texto escala correctamente
/// cuando el usuario amplía la fuente en los ajustes del teléfono.
abstract final class TipografiaPrimitiva {
  // Tamaños
  static const tam11 = 11.0;
  static const tam12 = 12.0;
  static const tam14 = 14.0;
  static const tam16 = 16.0;
  static const tam18 = 18.0;
  static const tam20 = 20.0;
  static const tam24 = 24.0;
  static const tam28 = 28.0;
  static const tam32 = 32.0;

  // Pesos
  static const pesoRegular = FontWeight.w400;
  static const pesoMedio = FontWeight.w500;
  static const pesoSemi = FontWeight.w600;
  static const pesoFuerte = FontWeight.w700;

  // Altura de línea (multiplicador sobre el tamaño de fuente)
  static const alturaAjustada = 1.20; // títulos
  static const alturaNormal = 1.45; // cuerpo de texto
  static const alturaHolgada = 1.60; // párrafos largos

  // Espaciado entre letras
  static const trackingTitulo = -0.5;
  static const trackingNormal = 0.0;
  static const trackingEtiqueta = 0.5;
}

/// Elevación (profundidad en dp).
abstract final class ElevacionesPrimitivas {
  static const elev0 = 0.0;
  static const elev1 = 1.0;
  static const elev2 = 3.0;
  static const elev3 = 6.0;
}

/// Duraciones de animación.
abstract final class DuracionesPrimitivas {
  static const rapida = Duration(milliseconds: 150);
  static const media = Duration(milliseconds: 250);
  static const lenta = Duration(milliseconds: 400);
}

/// Dimensiones crudas para iconos y grosores de línea.
abstract final class DimensionesPrimitivas {
  static const dim1 = 1.0;
  static const dim2 = 2.0;
  static const dim16 = 16.0;
  static const dim20 = 20.0;
  static const dim24 = 24.0;
  static const dim40 = 40.0;
  static const dim48 = 48.0;
  static const dim56 = 56.0;
}

/// Dimensiones mínimas de accesibilidad.
abstract final class AccesibilidadPrimitiva {
  /// Área táctil mínima exigida por WCAG 2.5.5 y Material Design.
  static const areaTactilMinima = 48.0;

  /// Grosor del anillo de foco visible (navegación por teclado / switch access).
  static const grosorFoco = 2.0;
}
