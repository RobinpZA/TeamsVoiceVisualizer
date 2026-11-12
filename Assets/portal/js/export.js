/* Voice map: PNG / SVG / JSON export. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M;
  const X = (VM.exp = {});

  const STYLE_PROPS = ['fill', 'fill-opacity', 'stroke', 'stroke-width', 'stroke-dasharray', 'stroke-linecap', 'stroke-linejoin', 'opacity',
    'font-family', 'font-size', 'font-weight', 'letter-spacing', 'text-anchor', 'paint-order', 'visibility'];

  function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function baseName() {
    const t = String((M.tenant && M.tenant.name) || 'tenant').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'tenant';
    return 'voice-map-' + t;
  }

  /** @font-face rules, when the stylesheet is readable (always true once packaged; blocked for linked files on file://). */
  function fontFaceCss() {
    let css = '';
    Array.prototype.forEach.call(document.styleSheets, (sh) => {
      try { Array.prototype.forEach.call(sh.cssRules, (r) => { if (r.type === CSSRule.FONT_FACE_RULE) css += r.cssText + '\n'; }); } catch (_) { /* cross-origin sheet */ }
    });
    return css;
  }

  // Clone the live map as a standalone SVG: full extent, no pan/zoom, computed styles inlined so it renders anywhere.
  function serialize() {
    const live = document.getElementById('map');
    const b = VM.render.bounds();
    const w = Math.ceil(b.w), hh = Math.ceil(b.h);
    const clone = live.cloneNode(true);
    clone.setAttribute('xmlns', U.SVGNS);
    clone.setAttribute('width', w); clone.setAttribute('height', hh);
    clone.setAttribute('viewBox', b.x + ' ' + b.y + ' ' + b.w + ' ' + b.h);
    clone.removeAttribute('class'); clone.removeAttribute('tabindex'); clone.removeAttribute('role');
    const vp = clone.querySelector('#viewport');
    if (vp) vp.removeAttribute('transform');
    // Snapshot both element lists BEFORE removing anything from the clone, so
    // index i pairs the same element in each tree.
    const liveEls = live.querySelectorAll('*'), cloneEls = clone.querySelectorAll('*');
    for (let i = 0; i < liveEls.length && i < cloneEls.length; i++) {
      const cs = getComputedStyle(liveEls[i]);
      let style = '';
      STYLE_PROPS.forEach((p) => {
        const v = cs.getPropertyValue(p);
        if (v) style += p + ':' + v + ';';
      });
      const t = cloneEls[i];
      t.setAttribute('style', style);
      t.removeAttribute('class');
      t.removeAttribute('tabindex');
      if (liveEls[i].classList.contains('line')) {
        const onPath = liveEls[i].parentNode.parentNode.classList.contains('onpath');
        t.setAttribute('marker-end', 'url(#' + (onPath ? 'arrow-accent' : 'arrow') + ')');
      }
    }
    const oldBg = clone.querySelector('rect.bg');
    if (oldBg) oldBg.parentNode.removeChild(oldBg);
    // focus rings are decoration only
    Array.prototype.slice.call(clone.querySelectorAll('rect[style*="opacity:0;"]')).forEach((n) => { if (n.getAttribute('fill') === 'none') n.parentNode.removeChild(n); });

    const paper = getComputedStyle(document.documentElement).getPropertyValue('--color-paper').trim();
    const bg = U.s('rect', { x: b.x, y: b.y, width: b.w, height: b.h });
    bg.setAttribute('style', 'fill:' + paper);
    const style = document.createElementNS(U.SVGNS, 'style');
    style.textContent = fontFaceCss();
    clone.insertBefore(bg, clone.firstChild);
    clone.insertBefore(style, clone.firstChild);
    return { xml: new XMLSerializer().serializeToString(clone), w, h: hh, paper };
  }

  X.svg = function () {
    const out = serialize();
    downloadBlob(new Blob([out.xml], { type: 'image/svg+xml;charset=utf-8' }), baseName() + '.svg');
  };

  X.png = function () {
    const out = serialize();
    const scale = Math.min(2, 16000 / Math.max(out.w, out.h));
    const img = new Image();
    img.onload = function () {
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(out.w * scale); canvas.height = Math.round(out.h * scale);
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = out.paper; ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.scale(scale, scale);
      ctx.drawImage(img, 0, 0);
      canvas.toBlob((blob) => {
        if (blob) downloadBlob(blob, baseName() + '.png');
        else VM.app.toast('PNG export failed: the map is too large for an image. Use SVG instead.');
      }, 'image/png');
    };
    img.onerror = function () { VM.app.toast('PNG export failed: the map could not be rasterised.'); };
    img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(out.xml)));
  };

  X.json = function () {
    downloadBlob(new Blob([JSON.stringify(M.raw, null, 2)], { type: 'application/json' }), baseName() + '.json');
  };
})();
