/**
 * Lucide v1.8.0 vendored subset — ISC License.
 * Unmodified icon node definitions from lucide/dist/esm/icons.
 * See LICENSE in this directory.
 */
(() => {
  'use strict';
  const icons = {
    'target': [['circle', { cx: '12', cy: '12', r: '10' }], ['circle', { cx: '12', cy: '12', r: '6' }], ['circle', { cx: '12', cy: '12', r: '2' }]],
    'circle-check': [['circle', { cx: '12', cy: '12', r: '10' }], ['path', { d: 'm9 12 2 2 4-4' }]],
    'shield-check': [['path', { d: 'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z' }], ['path', { d: 'm9 12 2 2 4-4' }]],
    'chevron-down': [['path', { d: 'm6 9 6 6 6-6' }]],
    'database': [['ellipse', { cx: '12', cy: '5', rx: '9', ry: '3' }], ['path', { d: 'M3 5V19A9 3 0 0 0 21 19V5' }], ['path', { d: 'M3 12A9 3 0 0 0 21 12' }]],
    'brain-circuit': [['path', { d: 'M12 5a3 3 0 1 0-5.997.125 4 4 0 0 0-2.526 5.77 4 4 0 0 0 .556 6.588A4 4 0 1 0 12 18Z' }], ['path', { d: 'M9 13a4.5 4.5 0 0 0 3-4' }], ['path', { d: 'M6.003 5.125A3 3 0 0 0 6.401 6.5' }], ['path', { d: 'M3.477 10.896a4 4 0 0 1 .585-.396' }], ['path', { d: 'M6 18a4 4 0 0 1-1.967-.516' }], ['path', { d: 'M12 13h4' }], ['path', { d: 'M12 18h6a2 2 0 0 1 2 2v1' }], ['path', { d: 'M12 8h8' }], ['path', { d: 'M16 8V5a2 2 0 0 1 2-2' }], ['circle', { cx: '16', cy: '13', r: '.5' }], ['circle', { cx: '18', cy: '3', r: '.5' }], ['circle', { cx: '20', cy: '21', r: '.5' }], ['circle', { cx: '20', cy: '8', r: '.5' }]],
    'badge-check': [['path', { d: 'M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z' }], ['path', { d: 'm9 12 2 2 4-4' }]],
    'arrow-right': [['path', { d: 'M5 12h14' }], ['path', { d: 'm12 5 7 7-7 7' }]],
    'circle-alert': [['circle', { cx: '12', cy: '12', r: '10' }], ['line', { x1: '12', x2: '12', y1: '8', y2: '12' }], ['line', { x1: '12', x2: '12.01', y1: '16', y2: '16' }]]
  };
  const namespace = 'http://www.w3.org/2000/svg';
  const render = (root) => root.querySelectorAll('[data-lucide]').forEach((placeholder) => {
    const name = placeholder.dataset.lucide;
    const definition = icons[name];
    if (!definition) throw new Error(`Unknown Lucide icon: ${name}`);
    const svg = document.createElementNS(namespace, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('class', `lucide lucide-${name} ${placeholder.className || ''}`.trim());
    definition.forEach(([tag, attributes]) => {
      const node = document.createElementNS(namespace, tag);
      Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, value));
      svg.appendChild(node);
    });
    placeholder.replaceWith(svg);
  });
  window.LucideSubset = Object.freeze({ version: '1.8.0', render });
})();
