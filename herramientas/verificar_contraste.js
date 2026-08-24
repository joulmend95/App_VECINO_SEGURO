// Calculadora de contraste WCAG 2.1 para los tokens de Vecino Seguro
const P = {
  // Azul de marca
  azul50: '#EFF4FF', azul100: '#DCE6FF', azul200: '#BCCEFF',
  azul400: '#5B7FE8', azul600: '#1D4ED8', azul700: '#1A3FA8', azul900: '#16277A',
  // Rojo de peligro
  rojo50: '#FEF2F2', rojo100: '#FEE2E2', rojo300: '#FCA5A5',
  rojo600: '#C81E1E', rojo700: '#A31212',
  // Ambar advertencia
  ambar50: '#FFFBEB', ambar300: '#FCD34D', ambar700: '#92400E',
  // Verde exito
  verde50: '#ECFDF5', verde300: '#6EE7B7', verde700: '#046C4E',
  // Neutros
  gris0: '#FFFFFF', gris50: '#F8FAFC', gris100: '#F1F5F9', gris200: '#E2E8F0',
  gris400: '#94A3B8', gris500: '#64748B', gris600: '#4B5768', gris700: '#334155',
  gris900: '#0F172A',
  // Neutros nocturnos
  noche900: '#0B1220', noche800: '#151E2E', noche700: '#263145', noche600: '#3A4761',
};

function lum(hex) {
  const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map(v => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function ratio(a, b) {
  const [l1, l2] = [lum(P[a]), lum(P[b])].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

// [nombre semantico, fg, bg, tipo]  tipo: texto | grande | ui
const PARES = [
  // ---- TEMA CLARO ----
  ['onFondo / fondo',              'gris900', 'gris50',  'texto'],
  ['onSuperficie / superficie',    'gris900', 'gris0',   'texto'],
  ['onSuperficieSutil / superficie','gris600', 'gris0',  'texto'],
  ['onSuperficieSutil / fondo',    'gris600', 'gris50',  'texto'],
  ['onPrimario / primario',        'gris0',   'azul600', 'texto'],
  ['onPrimario / primarioPresion', 'gris0',   'azul700', 'texto'],
  ['onPrimarioSuave / primarioSuave','azul700','azul50', 'texto'],
  ['primario / superficie (link)', 'azul600', 'gris0',   'texto'],
  ['onPeligro / peligro',          'gris0',   'rojo600', 'texto'],
  ['onPeligroSuave / peligroSuave','rojo700', 'rojo50',  'texto'],
  ['peligro / superficie (icono)', 'rojo600', 'gris0',   'ui'],
  ['advertencia / advertenciaSuave','ambar700','ambar50', 'texto'],
  ['exito / exitoSuave',           'verde700','verde50', 'texto'],
  ['borde (divisor, decorativo)',  'gris200', 'gris0',   'exento'],
  ['bordeInteractivo / superficie','gris600', 'gris0',   'ui'],
  ['bordeInteractivo / fondo',     'gris600', 'gris50',  'ui'],
  ['foco / superficie',            'azul600', 'gris0',   'ui'],
  ['deshabilitado / superficie',   'gris500', 'gris0',   'texto'],
  // ---- TEMA OSCURO ----
  ['[osc] onFondo / fondo',        'gris50',  'noche900','texto'],
  ['[osc] onSuperficie / superficie','gris50','noche800','texto'],
  ['[osc] onSuperficieSutil / sup', 'gris400','noche800','texto'],
  ['[osc] onPrimario / primario',  'noche900','azul400', 'texto'],
  ['[osc] primario / fondo',       'azul400', 'noche900','texto'],
  ['[osc] peligro / fondo',        'rojo300', 'noche900','texto'],
  ['[osc] peligro / superficie',   'rojo300', 'noche800','texto'],
  ['[osc] advertencia / superficie','ambar300','noche800','texto'],
  ['[osc] exito / superficie',     'verde300','noche800','texto'],
  ['[osc] borde (divisor)',        'noche600','noche800','exento'],
  ['[osc] bordeInteractivo / sup', 'gris400', 'noche800','ui'],
  ['[osc] foco / superficie',      'azul400', 'noche800','ui'],
  ['[osc] onPrimario / primarioPresion','noche900','azul200','texto'],
  ['[osc] onPeligroRelleno / peligroRelleno','gris0','rojo600','texto'],
  ['[osc] onPeligroSuave / peligroSuave','rojo300','noche700','texto'],
  ['[osc] deshabilitado / superficie','gris400','noche800','texto'],
  ['peligro / fondo (icono claro)','rojo600', 'gris50',  'ui'],
  ['onSuperficie / superficieAlterna','gris900','gris100','texto'],
  ['onSuperficieSutil / superficieAlterna','gris600','gris100','texto'],
  ['[osc] onSuperficie / superficieAlterna','gris50','noche700','texto'],
  // --- Pares añadidos para la clasificación de alertas por urgencia ---
  ['advertencia / superficie',     'ambar700','gris0',  'texto'],
  ['advertencia / fondo',          'ambar700','gris50', 'texto'],
  ['onSuperficieSutil / superficieAlterna (chip)','gris600','gris100','texto'],
  ['[osc] onAdvertenciaSuave / advertenciaSuave','ambar300','noche700','texto'],
  ['[osc] onPrimarioSuave / primarioSuave','azul200','noche700','texto'],
  ['[osc] onSuperficieSutil / superficieAlterna','gris400','noche700','texto'],
  ['[osc] advertencia / fondo',    'ambar300','noche900','texto'],
];

const MIN = { texto: 4.5, grande: 3.0, ui: 3.0, exento: 0 };
let fallos = 0;
console.log('| Par semántico | Fg | Bg | Ratio | Mínimo | Nivel | Estado |');
console.log('|---|---|---|---|---|---|---|');
for (const [nombre, fg, bg, tipo] of PARES) {
  const r = ratio(fg, bg);
  const min = MIN[tipo];
  const ok = r >= min;
  if (!ok) fallos++;
  const nivel = r >= 7 ? 'AAA' : r >= 4.5 ? 'AA' : r >= 3 ? 'AA-grande/UI' : '—';
  console.log(`| ${nombre} | \`${P[fg]}\` | \`${P[bg]}\` | **${r.toFixed(2)}:1** | ${min}:1 | ${nivel} | ${ok ? 'PASA' : 'FALLA'} |`);
}
console.log(`\nTotal: ${PARES.length} pares · Fallos: ${fallos}`);
