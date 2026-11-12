/* Voice map: SVG rendering, zoom/pan, focus highlighting, minimap. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M;
  const R = (VM.render = {});

  let svg, viewport, gGroups, gEdges, gNodes, zoom, mm;
  let current = null;                      // last layout
  let prevPos = new Map();                 // node id -> {x,y,w,h} from previous draw
  let view = d3.zoomIdentity;
  let size = { w: 800, h: 600 };
  let hl = { selected: null, focus: null, path: null };
  let handlers = {};
  let nodeById = new Map();
  let radius = 8;
  let easeFn = (t) => t;

  /* ---------- tokens read from CSS ---------- */
  function parseBezier(str) {
    const m = /cubic-bezier\(([^)]+)\)/.exec(str || '');
    if (!m) return (t) => t;
    const [x1, y1, x2, y2] = m[1].split(',').map(parseFloat);
    const cx = (s) => 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s;
    const cy = (s) => 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s;
    const dx = (s) => 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2);
    return (t) => {
      if (t <= 0 || t >= 1) return t;
      let s = t;
      for (let i = 0; i < 8; i++) {
        const err = cx(s) - t;
        if (Math.abs(err) < 1e-5) break;
        const d = dx(s);
        if (Math.abs(d) < 1e-6) break;
        s -= err / d;
      }
      return cy(s);
    };
  }
  function layoutDur() { return U.reducedMotion() ? 0 : U.cssNum('--dur-layout', 380); }

  /* ---------- init ---------- */
  R.init = function (h) {
    handlers = h || {};
    svg = d3.select('#map');
    viewport = d3.select('#viewport');
    gGroups = viewport.select('.layer-groups');
    gEdges = viewport.select('.layer-edges');
    gNodes = viewport.select('.layer-nodes');
    radius = U.cssNum('--radius-node', 8);
    easeFn = parseBezier(getComputedStyle(document.documentElement).getPropertyValue('--ease-out'));

    zoom = d3.zoom().scaleExtent([0.1, 3]).on('zoom', (e) => {
      view = e.transform;
      viewport.attr('transform', view);
      updateViewRect();
    });
    svg.call(zoom).on('dblclick.zoom', null);
    svg.on('click', (e) => {
      if (e.target === svg.node() || e.target.classList.contains('bg')) handlers.onBackground && handlers.onBackground();
    });

    const stage = document.getElementById('stage');
    const measure = () => { size = { w: stage.clientWidth || 800, h: stage.clientHeight || 600 }; updateViewRect(); };
    measure();
    if (window.ResizeObserver) new ResizeObserver(measure).observe(stage);
    else window.addEventListener('resize', measure);

    mm = d3.select('#minimap');
    mm.append('g').attr('class', 'mm-shapes');
    mm.append('rect').attr('class', 'mm-view');
    let dragging = false;
    const move = (e) => {
      if (!current) return;
      const m = mmMap();
      const r = document.getElementById('minimap').getBoundingClientRect();
      const px = ((e.clientX - r.left) / r.width) * 180, py = ((e.clientY - r.top) / r.height) * 120;
      const gx = (px - m.ox) / m.k + m.b.x, gy = (py - m.oy) / m.k + m.b.y;
      svg.call(zoom.transform, d3.zoomIdentity.translate(size.w / 2 - gx * view.k, size.h / 2 - gy * view.k).scale(view.k));
    };
    mm.on('pointerdown', (e) => { dragging = true; e.currentTarget.setPointerCapture(e.pointerId); move(e); });
    mm.on('pointermove', (e) => { if (dragging) move(e); });
    mm.on('pointerup pointercancel', () => { dragging = false; });
  };

  R.size = () => size;
  R.bounds = () => (current ? current.bounds : { x: 0, y: 0, w: 100, h: 100 });
  R.layout = () => current;
  R.transform = () => view;

  /* ---------- drawing ---------- */
  const tr = (d) => 'translate(' + d.x + ',' + d.y + ')';
  const pathD = (pts) => (pts.length ? 'M' + pts.map((p) => p.x + ' ' + p.y).join('L') : '');

  function ariaFor(d) { return d.kindText + ' ' + d.fullName; }

  function chevron(parent, d, cx, cy) {
    const g = parent.append('g').attr('class', 'chev').attr('transform', 'translate(' + cx + ',' + cy + ')')
      .attr('role', 'button').attr('tabindex', 0)
      .attr('aria-label', (d.expanded ? 'Collapse ' : 'Expand ') + d.fullName).attr('aria-expanded', d.expanded ? 'true' : 'false');
    g.append('circle').attr('class', 'chev-ring').attr('r', 13);
    g.append('circle').attr('class', 'chev-bg').attr('r', 10);
    g.append('path').attr('class', 'chev-arrow').attr('d', d.expanded ? 'M-3.5 -1.5L0 2L3.5 -1.5' : 'M-1.5 -3.5L2 0L-1.5 3.5');
    const toggle = () => handlers.onToggle && handlers.onToggle(d.entityId);
    g.on('click', (e) => { e.stopPropagation(); toggle(); });
    g.on('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); toggle(); } });
    g.on('pointerdown', (e) => e.stopPropagation());
  }

  function statusDot(parent, d, x, y) {
    const sev = M.worst(d.entityId);
    if (!sev) return;
    const n = M.findingsFor(d.entityId).length;
    parent.append('circle').attr('class', 'dot sev-' + sev).attr('cx', x).attr('cy', y).attr('r', 4.5)
      .append('title').text(n + (n === 1 ? ' finding' : ' findings') + ' (worst: ' + sev + ')');
  }

  function paintNode(g, d) {
    const rx = d.shape === 'pill' ? d.h / 2 : radius;
    g.select('.box').attr('width', d.w).attr('height', d.h).attr('rx', rx).attr('ry', rx);
    g.select('.wash').attr('width', d.w).attr('height', d.h).attr('rx', rx).attr('ry', rx);
    g.select('.ring').attr('x', -4).attr('y', -4).attr('width', d.w + 8).attr('height', d.h + 8).attr('rx', rx + 4).attr('ry', rx + 4);
    const c = g.select('.ncontent');
    c.selectAll('*').remove();
    const P = d.shape === 'pill' ? 18 : 14;
    if (d.role === 'entity') {
      const ky = d.shape === 'ra' ? 17 : d.shape === 'pill' ? 19 : 19;
      const ny = d.shape === 'ra' ? 33 : d.shape === 'pill' ? 36 : 37;
      c.append('text').attr('class', 't-kind').attr('x', P).attr('y', ky).text(d.kindText);
      c.append('text').attr('class', 't-name' + (d.mono ? ' t-mono' : '') + (d.unresolved ? ' t-muted' : '')).attr('x', P).attr('y', ny).text(d.nameText);
      if (d.sumText) c.append('text').attr('class', 't-sum').attr('x', P).attr('y', 55).text(d.sumText);
      if (d.expandable) chevron(c, d, d.w - 22, d.h / 2);
      statusDot(c, d, d.w - 5, 5);
    } else if (d.role === 'flow') {
      c.append('text').attr('class', 't-flow').attr('x', 12).attr('y', 20).text(d.nameText);
    } else if (d.role === 'menu') {
      c.append('text').attr('class', 't-kind').attr('x', P).attr('y', 18).text('MENU');
      (d.rows || []).forEach((r) => {
        c.append('text').attr('class', 't-key').attr('x', P).attr('y', r.y + 4).text(r.key);
        c.append('text').attr('class', 't-row').attr('x', P + 30).attr('y', r.y + 4).text(r.text);
        c.append('circle').attr('class', 'port').attr('cx', d.w).attr('cy', r.y).attr('r', 2.5);
      });
    } else {
      c.append('text').attr('class', 't-kind').attr('x', P).attr('y', 18).text(d.kindText);
      c.append('text').attr('class', 't-row').attr('x', P).attr('y', 36).text(d.nameText);
      if (d.sumText) c.append('text').attr('class', 't-sum t-muted').attr('x', P).attr('y', 54).text(d.sumText);
    }
    c.append('title').text(d.role === 'entity' ? d.fullName : d.fullName || '');
  }

  function paintGroup(g, d) {
    const c = g.select('.gcontent');
    c.selectAll('*').remove();
    c.append('text').attr('class', 't-kind').attr('x', 16).attr('y', 22).text(d.kindText);
    c.append('text').attr('class', 't-name').attr('x', 16).attr('y', 41).text(d.nameText);
    chevron(c, d, d.w - 26, 26);
    statusDot(c, d, d.w - 5, 5);
    g.select('.ghit').attr('width', Math.max(0, d.w - 56)).attr('height', 52);
    g.select('.ring').attr('x', -4).attr('y', -4).attr('width', d.w + 8).attr('height', d.h + 8).attr('rx', radius + 4).attr('ry', radius + 4);
    g.attr('aria-label', ariaFor(d));
  }

  R.draw = function (layout, opts) {
    opts = opts || {};
    const animate = opts.animate !== false;
    const dur = animate ? layoutDur() : 0;
    const ease = easeFn;
    current = layout;
    nodeById = new Map(layout.nodes.map((n) => [n.id, n]));
    const keep = captureFocus();
    const origin = (d) => prevPos.get(d.id) || null;
    const ownerOrigin = (d) => prevPos.get(d.entityId) || null;

    const select = (id) => handlers.onSelect && handlers.onSelect(id);
    const activate = (e, d) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); select(d.entityId); } };

    /* groups (expanded AA/CQ containers) */
    const groups = layout.nodes.filter((n) => n.role === 'group');
    const gSel = gGroups.selectAll('g.group').data(groups, (d) => d.id);
    gSel.exit().each(function () { this.classList.add('exiting'); })
      .transition().duration(dur).ease(ease).style('opacity', 0).on('end', removeIfExiting);
    revive(gSel, '.gfade');
    const gEnter = gSel.enter().append('g').attr('class', 'group').attr('tabindex', 0).attr('role', 'button')
      .attr('transform', (d) => tr(origin(d) || d));
    const gf = gEnter.append('g').attr('class', 'gfade');
    gf.append('rect').attr('class', 'gbox').attr('rx', radius).attr('ry', radius)
      .attr('width', (d) => (origin(d) || d).w).attr('height', (d) => (origin(d) || d).h);
    gf.append('g').attr('class', 'gcontent');
    gf.append('rect').attr('class', 'ghit');
    gf.append('rect').attr('class', 'ring').attr('fill', 'none');
    gEnter.on('click', (e, d) => { e.stopPropagation(); select(d.entityId); }).on('keydown', (e, d) => activate(e, d));
    gEnter.select('.gfade').attr('opacity', (d) => (origin(d) ? 1 : 0)).transition().duration(dur).ease(ease).attr('opacity', 1);
    const gAll = gEnter.merge(gSel);
    gAll.each(function (d) { paintGroup(d3.select(this), d); });
    gAll.transition().duration(dur).ease(ease).attr('transform', tr);
    gAll.select('.gbox').transition().duration(dur).ease(ease).attr('width', (d) => d.w).attr('height', (d) => d.h);
    gAll.select('.ring').attr('width', (d) => d.w + 8).attr('height', (d) => d.h + 8);

    /* nodes */
    const nodes = layout.nodes.filter((n) => n.role !== 'group');
    const nSel = gNodes.selectAll('g.node').data(nodes, (d) => d.id);
    nSel.exit().each(function (d) {
      const tgt = nodeById.get(d.entityId);
      this.classList.add('exiting');
      const t = d3.select(this).transition().duration(dur).ease(ease);
      if (tgt) t.attr('transform', tr(tgt));
      t.select('.nfade').attr('opacity', 0);
      t.on('end', removeIfExiting);
    });
    revive(nSel, '.nfade');
    const nEnter = nSel.enter().append('g')
      .attr('transform', (d) => tr(origin(d) || ownerOrigin(d) || d));
    nEnter.attr('data-id', (d) => d.id);
    const nf = nEnter.append('g').attr('class', 'nfade').attr('opacity', (d) => (origin(d) ? 1 : 0));
    nf.append('rect').attr('class', 'box');
    nf.append('rect').attr('class', 'wash');
    nf.append('rect').attr('class', 'ring');
    nf.append('g').attr('class', 'ncontent');
    nEnter.each(function (d) {
      const sel = d3.select(this);
      if (d.role === 'entity') sel.attr('tabindex', 0).attr('role', 'button').attr('aria-label', ariaFor(d));
    });
    nEnter.on('click', (e, d) => { e.stopPropagation(); select(d.entityId); }).on('keydown', (e, d) => { if (d.role === 'entity') activate(e, d); });
    nEnter.select('.nfade').transition().duration(dur).ease(ease).attr('opacity', 1);
    const nAll = nEnter.merge(nSel);
    nAll.attr('class', (d) => 'node' + (d.inner ? ' is-inner' : '') + (d.isRA ? ' is-ra' : '') + (d.unresolved ? ' is-unresolved' : '')
      + (d.role === 'flow' ? ' is-flowhead' : '') + (d.role === 'cqex' ? ' is-exception' : ''));
    nAll.attr('aria-label', (d) => (d.role === 'entity' ? ariaFor(d) : null));
    nAll.each(function (d) { paintNode(d3.select(this), d); });
    nAll.transition().duration(dur).ease(ease).attr('transform', tr);

    /* edges */
    const eSel = gEdges.selectAll('g.edge').data(layout.edges, (d) => d.key);
    eSel.exit().each(function () { this.classList.add('exiting'); })
      .transition().duration(dur).ease(ease).style('opacity', 0).on('end', removeIfExiting);
    revive(eSel, '.efade');
    const eEnter = eSel.enter().append('g');
    const ef = eEnter.append('g').attr('class', 'efade').attr('opacity', 0);
    ef.append('path').attr('class', 'line').attr('d', (d) => pathD(d.points));
    ef.append('text').attr('class', 't-elabel').attr('text-anchor', 'middle');
    ef.transition().duration(dur).ease(ease).attr('opacity', 1);
    const eAll = eEnter.merge(eSel);
    eAll.attr('class', (d) => 'edge k-' + d.kind + (d.internal && d.dashed ? ' k-internal-dash' : ''));
    eAll.select('.line').transition().duration(dur).ease(ease).attr('d', (d) => pathD(d.points));
    eAll.select('.t-elabel').each(function (d) {
      const t = d3.select(this);
      if (!d.label) { t.text(''); return; }
      let x, y;
      if (d.labelBox) { x = d.labelBox.x + d.labelBox.w / 2; y = d.labelBox.y + d.labelBox.h - 3; }
      else { const p = d.points[Math.floor(d.points.length / 2)] || { x: 0, y: 0 }; x = p.x; y = p.y - 4; }
      t.text(d.label);
      if (t.attr('x') == null) t.attr('x', x).attr('y', y);
      else t.transition().duration(dur).ease(ease).attr('x', x).attr('y', y);
    });

    /* remember positions for the next transition */
    prevPos = new Map(layout.nodes.map((n) => [n.id, { x: n.x, y: n.y, w: n.w, h: n.h }]));

    applyHighlight();
    drawMinimap();
    restoreFocus(keep);
  };

  /* Exit/enter races: an element that re-enters while its exit transition runs must survive. */
  function removeIfExiting() { if (this.classList.contains('exiting')) this.remove(); }
  function revive(sel, fadeSel) {
    sel.each(function () {
      if (!this.classList.contains('exiting')) return;
      this.classList.remove('exiting');
      const s = d3.select(this);
      s.interrupt();
      s.style('opacity', null);
      s.selectAll(fadeSel).interrupt().attr('opacity', 1);
    });
  }

  /* Repainting destroys the focused chevron/node; remember it by entity id and put focus back. */
  function captureFocus() {
    const ae = document.activeElement;
    if (!ae || !svg || !svg.node().contains(ae)) return null;
    const host = ae.closest ? ae.closest('g.node, g.group') : null;
    if (!host || host.classList.contains('exiting')) return null;
    const d = d3.select(host).datum();
    if (!d) return null;
    return { entityId: d.entityId, chev: !!(ae.classList && ae.classList.contains('chev')) };
  }
  function restoreFocus(k) {
    if (!k) return;
    const ae = document.activeElement;
    if (ae && ae !== document.body && ae.isConnected && !(ae.closest && ae.closest('.exiting'))) return;   // focus moved on purpose
    R.focusEntity(k.entityId, k.chev);
  }

  /* ---------- highlight / focus ---------- */
  R.computeFocus = function (entityId) {
    if (!current || !entityId) return null;
    const edges = current.edges.filter((e) => !e.internal);
    const fwd = new Map(), back = new Map();
    edges.forEach((e) => {
      if (!fwd.has(e.from)) fwd.set(e.from, []);
      if (!back.has(e.to)) back.set(e.to, []);
      fwd.get(e.from).push(e.to); back.get(e.to).push(e.from);
    });
    const walk = (start, map) => {
      const seen = new Set([start]); const q = [start];
      while (q.length) { const n = q.pop(); (map.get(n) || []).forEach((m) => { if (!seen.has(m)) { seen.add(m); q.push(m); } }); }
      return seen;
    };
    const down = walk(entityId, fwd), up = walk(entityId, back);
    const entities = new Set([...down, ...up]);
    const edgeKeys = new Set();
    edges.forEach((e) => {
      if ((up.has(e.from) && up.has(e.to)) || (down.has(e.from) && down.has(e.to))) edgeKeys.add(e.key);
    });
    return { entities, edgeKeys };
  };

  R.setHighlight = function (next) { hl = Object.assign({ selected: null, focus: null, path: null }, next); applyHighlight(); };

  function applyHighlight() {
    if (!current) return;
    const path = hl.path, focus = hl.focus;
    const nodeOnPath = (d) => {
      if (!path) return false;
      if (!path.entities.has(d.entityId)) return false;
      if (d.inner && d.flowKey != null) return path.flows.has(d.entityId + '|' + d.flowKey);
      return true;
    };
    const nodeDim = (d) => {
      if (path) return !nodeOnPath(d) && !(d.role === 'group');
      if (focus) return !focus.entities.has(d.entityId);
      return false;
    };
    gNodes.selectAll('g.node')
      .classed('selected', (d) => !d.inner && d.entityId === hl.selected)
      .classed('onpath', nodeOnPath)
      .classed('dim', nodeDim);
    gGroups.selectAll('g.group')
      .classed('selected', (d) => d.entityId === hl.selected)
      .classed('onpath', nodeOnPath)
      .classed('dim', (d) => (path ? !nodeOnPath(d) : focus ? !focus.entities.has(d.entityId) : false));

    let newestKey = null;
    const edgeOnPath = (e) => {
      if (!path) return false;
      if (e.internal) { const a = nodeById.get(e.srcNode), b = nodeById.get(e.tgtNode); return !!(a && b && nodeOnPath(a) && nodeOnPath(b)); }
      return e.ids.some((i) => path.edges.has(i));
    };
    if (path && path.newest) { const ne = current.edges.find((e) => e.ids.indexOf(path.newest) >= 0); if (ne) newestKey = ne.key; }
    gEdges.selectAll('g.edge')
      .classed('onpath', edgeOnPath)
      .classed('newest', (e) => e.key === newestKey)
      .classed('dim', (e) => {
        if (path) return !edgeOnPath(e);
        if (focus) {
          if (e.internal) { const a = nodeById.get(e.srcNode); return !(a && focus.entities.has(a.entityId)); }
          return !focus.edgeKeys.has(e.key);
        }
        return false;
      });
  }

  /* ---------- zoom ---------- */
  function insets() { return (R.insets && R.insets()) || { left: 0, right: 0 }; }
  function go(t, animate) {
    const dur = animate ? layoutDur() : 0;
    if (dur > 0) svg.transition().duration(dur).ease(easeFn).call(zoom.transform, t);
    else svg.call(zoom.transform, t);
  }
  R.fit = function (animate) {
    if (!current) return;
    const b = current.bounds, ins = insets();
    const W = Math.max(100, size.w - ins.left - ins.right), H = Math.max(100, size.h - (ins.bottom || 0));
    const k = Math.max(0.1, Math.min(3, Math.min(W / b.w, H / b.h, 1.2)));
    go(d3.zoomIdentity.translate(ins.left + (W - b.w * k) / 2 - b.x * k, (H - b.h * k) / 2 - b.y * k).scale(k), animate);
  };
  R.zoomBy = function (f) { svg.transition().duration(U.reducedMotion() ? 0 : U.cssNum('--dur-short', 220)).call(zoom.scaleBy, f); };
  R.zoomToEntity = function (entityId, animate) {
    const n = nodeById.get(entityId);
    if (!n) return false;
    const ins = insets();
    const W = Math.max(100, size.w - ins.left - ins.right);
    const k = Math.max(0.6, Math.min(1.2, view.k < 0.6 ? 0.9 : view.k));
    const H = Math.max(100, size.h - (ins.bottom || 0));
    const cx = n.x + n.w / 2, cy = n.y + Math.min(n.h, 120) / 2;
    go(d3.zoomIdentity.translate(ins.left + W / 2 - cx * k, H / 2 - cy * k).scale(k), animate !== false);
    return true;
  };
  R.hasEntity = (id) => nodeById.has(id);
  R.focusEntity = function (entityId, chevron) {
    const live = (d) => d.entityId === entityId && !d.inner;
    const pick = (sel) => sel.filter(function (d) { return live(d) && !this.classList.contains('exiting'); }).node();
    const el = pick(gNodes.selectAll('g.node')) || pick(gGroups.selectAll('g.group'));
    if (!el) return;
    const chev = chevron ? el.querySelector('.chev') : null;
    const t = chev || el;
    if (t.focus) t.focus({ preventScroll: true });
  };

  /* ---------- minimap ---------- */
  function mmMap() {
    const b = current ? current.bounds : { x: 0, y: 0, w: 100, h: 100 };
    const k = Math.min(172 / b.w, 112 / b.h);
    return { b, k, ox: (180 - b.w * k) / 2, oy: (120 - b.h * k) / 2 };
  }
  function drawMinimap() {
    if (!current) return;
    const m = mmMap();
    const shapes = mm.select('.mm-shapes');
    const data = current.nodes.filter((n) => !n.inner);
    const sel = shapes.selectAll('rect').data(data, (d) => d.id);
    sel.exit().remove();
    sel.enter().append('rect').merge(sel)
      .attr('class', (d) => (d.role === 'group' ? 'mm-group' : 'mm-node'))
      .attr('x', (d) => m.ox + (d.x - m.b.x) * m.k).attr('y', (d) => m.oy + (d.y - m.b.y) * m.k)
      .attr('width', (d) => Math.max(1.5, d.w * m.k)).attr('height', (d) => Math.max(1.5, d.h * m.k));
    updateViewRect();
  }
  function updateViewRect() {
    if (!mm || !current) return;
    const m = mmMap();
    const x0 = -view.x / view.k, y0 = -view.y / view.k, w = size.w / view.k, h = size.h / view.k;
    mm.select('.mm-view')
      .attr('x', m.ox + (x0 - m.b.x) * m.k).attr('y', m.oy + (y0 - m.b.y) * m.k)
      .attr('width', Math.max(2, w * m.k)).attr('height', Math.max(2, h * m.k));
  }
})();
