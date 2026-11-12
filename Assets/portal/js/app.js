/* Voice map: application controller. Wires model, layout, render, panels, search, trace and deep links. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M, R = VM.render, P = VM.panel, F = VM.findings;
  const h = U.h, clear = U.clear;
  const A = (VM.app = {});

  const state = { expanded: new Set(), selected: null, layout: null, path: null };
  let chain = Promise.resolve();
  let loadTimer = null;
  let booted = false;

  const $ = (id) => document.getElementById(id);
  const isMobile = () => window.matchMedia('(max-width: 767.98px)').matches;
  const enc = encodeURIComponent;

  /* ---------- overlays ---------- */
  function showLoading(on, text) {
    clearTimeout(loadTimer);
    const box = $('loading');
    if (!on) { box.hidden = true; return; }
    $('loadingText').textContent = text;
    box.hidden = false;
  }
  function showState(title, msg, actions, listRows) {
    $('stateTitle').textContent = title;
    $('stateMsg').textContent = msg || '';
    const act = clear($('stateActions'));
    (actions || []).forEach((a) => act.appendChild(h('button', { type: 'button', class: 'btn', onclick: a.onclick }, a.label)));
    const list = $('stateList');
    list.hidden = !listRows;
    clear(list);
    if (listRows) list.appendChild(listRows);
    $('stateBox').hidden = false;
    showLoading(false);
  }
  function entityTable() {
    const body = h('tbody');
    M.list.forEach((e) => body.appendChild(h('tr', null, h('td', { text: String(e.kind === 'number' ? (e.number || e.name) : e.name) }), h('td', { class: 'k', text: M.kindLabel(e) }), h('td', { class: 'k', text: e.id }))));
    return h('table', { class: 'tbl' }, h('thead', null, h('tr', null, h('th', { text: 'Name' }), h('th', { text: 'Kind' }), h('th', { text: 'Id' }))), body);
  }
  let toastTimer = null;
  A.toast = function (msg) {
    let t = document.querySelector('.toast');
    if (!t) { t = h('div', { class: 'toast', role: 'status' }); document.body.appendChild(t); }
    t.textContent = msg; t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 3500);
  };

  /* ---------- layout pipeline ---------- */
  function relayout(opts) {
    opts = opts || {};
    chain = chain.then(async () => {
      const objects = M.list.length;
      clearTimeout(loadTimer);
      if (opts.immediate) showLoading(true, 'Laying out ' + objects + ' objects…');
      else loadTimer = setTimeout(() => showLoading(true, 'Laying out ' + objects + ' objects…'), 150);
      try {
        const layout = await VM.layout.run(state.expanded);
        state.layout = layout;
        R.draw(layout, { animate: opts.animate !== false });
        refreshHighlight();
        showLoading(false);
        return true;
      } catch (err) {
        showState('The map could not be laid out', String(err && err.message ? err.message : err),
          [{ label: 'Show as list', onclick: () => showState('All objects', M.list.length + ' objects in this model.', [{ label: 'Retry map', onclick: () => { $('stateBox').hidden = true; relayout({ immediate: true, animate: false }); } }], entityTable()) }]);
        return false;
      }
    });
    return chain;
  }

  function refreshHighlight() {
    const path = state.path;
    const focus = !path && state.selected ? R.computeFocus(state.selected) : null;
    R.setHighlight({ selected: state.selected, focus, path });
  }

  /* ---------- hash ---------- */
  function updateHash() {
    let hash = '';
    const S = P.session();
    if (state.path && S) {
      hash = '#/trace?from=' + enc(S.entryId) + '&at=' + enc(S.when.toISOString()) + (S.inputs.length ? '&keys=' + S.inputs.map(enc).join(',') : '');
    } else {
      if (state.selected) hash = '#/e/' + enc(state.selected);
      if (state.expanded.size) hash = (hash || '#/') + '&x=' + Array.from(state.expanded).map(enc).join(',');
    }
    try { history.replaceState(null, '', hash || (location.pathname + location.search)); } catch (_) { /* file:// quirks */ }
  }
  function parseHash() {
    const raw = location.hash.replace(/^#/, '');
    const out = { selected: null, expanded: [], trace: null };
    if (!raw) return out;
    const dec = (s) => { try { return decodeURIComponent(s); } catch (_) { return s; } };
    if (raw.indexOf('/trace') === 0) {
      const q = raw.split('?')[1] || '';
      const kv = {};
      q.split('&').forEach((p) => { const i = p.indexOf('='); if (i > 0) kv[p.slice(0, i)] = p.slice(i + 1); });
      if (kv.from) out.trace = { from: dec(kv.from), at: kv.at ? dec(kv.at) : null, keys: kv.keys ? kv.keys.split(',').map(dec) : [] };
      return out;
    }
    const parts = raw.split('&');
    const first = parts.shift();
    if (first.indexOf('/e/') === 0) out.selected = dec(first.slice(3));
    parts.forEach((p) => { if (p.indexOf('x=') === 0) out.expanded = p.slice(2).split(',').filter(Boolean).map(dec); });
    return out;
  }

  /* ---------- selection / expansion ---------- */
  A.select = async function (id, opts) {
    opts = opts || {};
    const e = M.get(id);
    if (!e) return;
    // Clicking a node on the map leaves the trace and shows that node's details.
    if (opts.fromMap && P.session()) { P.endTrace(); P.setMode('details'); }
    let changed = false;
    if (M.isHiddenAt(id, state.expanded)) {
      const owner = M.owners(id)[0];
      if (owner) { state.expanded.add(owner); changed = true; }
    }
    if (changed || !R.hasEntity(id)) await relayout();
    state.selected = id;
    refreshHighlight();
    P.showEntity(id);
    const staying = P.mode() === 'trace' && (opts.keepMode || P.session());
    if (!staying) P.setMode('details');
    P.open();
    updateHash();
    if (opts.zoom) R.zoomToEntity(id, true);
  };
  A.clearSelection = function () {
    state.selected = null;
    refreshHighlight();
    updateHash();
  };
  A.toggle = async function (id) {
    if (state.expanded.has(id)) state.expanded.delete(id); else state.expanded.add(id);
    await relayout();
    updateHash();
  };
  async function setAllExpanded(on) {
    state.expanded.clear();
    if (on) M.list.forEach((e) => { if (M.isExpandable(e)) state.expanded.add(e.id); });
    await relayout();
    updateHash();
    R.fit(true);
  }

  /* ---------- trace ---------- */
  A.openTrace = function () {
    if (!window.VMTrace) { A.toast('The trace engine is not loaded in this build.'); return; }
    P.refreshEntryPoints();
    const sel = state.selected && M.get(state.selected);
    const tsel = document.getElementById('trEntry');
    if (tsel && sel && ['number', 'autoAttendant', 'callQueue'].indexOf(sel.kind) >= 0 && !P.session()) { tsel.value = sel.id; tsel.dispatchEvent(new Event('change')); }
    P.setMode('trace');
    P.open();
    if (tsel) tsel.focus();
  };
  async function onTraceChange(S) {
    if (!S || !S.state) { state.path = null; refreshHighlight(); updateHash(); return; }
    const st = S.state;
    const ids = st.pathEntityIds || [];
    state.path = {
      entities: new Set(ids),
      edges: new Set(st.pathEdgeIds || []),
      flows: new Set((st.steps || []).filter((s) => s.flowKey != null).map((s) => s.entityId + '|' + s.flowKey)),
      newest: (st.pathEdgeIds || []).slice(-1)[0] || null,
    };
    let changed = false;
    ids.forEach((id) => {
      const e = M.get(id);
      if (!e) return;
      if (M.isExpandable(e) && !state.expanded.has(id)) { state.expanded.add(id); changed = true; }
      if (M.isHiddenAt(id, state.expanded)) { const o = M.owners(id)[0]; if (o) { state.expanded.add(o); changed = true; } }
    });
    if (changed) await relayout();
    refreshHighlight();
    updateHash();
    const last = (st.steps || []).slice(-1)[0];
    if (last && last.entityId) R.zoomToEntity(last.entityId, true);
  }

  /* ---------- menus ---------- */
  const menus = [];
  function makeMenu(btn, menuEl, items) {
    const m = {
      btn, el: menuEl,
      close(focusBtn) { menuEl.hidden = true; btn.setAttribute('aria-expanded', 'false'); if (focusBtn) btn.focus(); },
      open() {
        closeMenus();
        clear(menuEl);
        items().forEach((it) => {
          if (it === 'sep') { menuEl.appendChild(h('div', { class: 'menu-sep', role: 'separator' })); return; }
          menuEl.appendChild(h('button', { type: 'button', class: 'menu-item', role: 'menuitem', tabindex: '-1', disabled: !!it.disabled, onclick: () => { m.close(false); it.run(); } }, it.label));
        });
        menuEl.hidden = false;
        btn.setAttribute('aria-expanded', 'true');
        const first = menuEl.querySelector('.menu-item:not(:disabled)');
        if (first) first.focus();
      },
    };
    btn.addEventListener('click', () => (menuEl.hidden ? m.open() : m.close(false)));
    menuEl.addEventListener('keydown', (e) => {
      const its = Array.prototype.slice.call(menuEl.querySelectorAll('.menu-item:not(:disabled)'));
      const i = its.indexOf(document.activeElement);
      if (e.key === 'ArrowDown') { e.preventDefault(); its[(i + 1) % its.length].focus(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); its[(i - 1 + its.length) % its.length].focus(); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); m.close(true); }
      else if (e.key === 'Tab') m.close(false);
    });
    menus.push(m);
    return m;
  }
  function closeMenus() { menus.forEach((m) => { if (!m.el.hidden) m.close(false); }); }
  const anyMenuOpen = () => menus.some((m) => !m.el.hidden);

  /* ---------- legend ---------- */
  function buildLegend() {
    const S = (tag, attrs) => U.s(tag, attrs);
    const sample = (w, hgt, kids) => { const s = S('svg', { width: w, height: hgt, viewBox: '0 0 ' + w + ' ' + hgt, 'aria-hidden': 'true' }); kids.forEach((k) => s.appendChild(k)); return s; };
    const row = (svg, text) => h('div', { class: 'legend-row' }, svg, h('span', { text }));
    const rect = (cls, w, hgt, rx) => S('rect', { class: cls, x: 1, y: 1, width: w - 2, height: hgt - 2, rx });
    const line = (cls) => S('line', { class: 'lg-edge ' + cls, x1: 1, y1: 8, x2: 35, y2: 8 });
    const dot = (sev) => S('circle', { class: 'dot sev-' + sev, cx: 6, cy: 8, r: 4.5 });
    const body = clear($('legendBody'));
    [
      row(sample(36, 16, [rect('lg-box', 36, 16, 8)]), 'Number'),
      row(sample(36, 16, [rect('lg-box lg-dash', 36, 16, 4)]), 'Resource account (dashed)'),
      row(sample(36, 16, [rect('lg-box', 36, 16, 4), S('path', { class: 'chev-arrow', d: 'M26 4.5l3.5 3.5-3.5 3.5' })]), 'Auto attendant or call queue: arrow expands'),
      row(sample(36, 16, [rect('lg-box lg-dash lg-muted', 36, 16, 4)]), 'Not found in the tenant'),
      h('div', { class: 'legend-sep' }),
      row(sample(36, 16, [line('')]), 'Route'),
      row(sample(36, 16, [line('lg-dash')]), 'Exception'),
      row(sample(36, 16, [line('lg-thin')]), 'Fronts, dials, caller ID'),
      h('div', { class: 'legend-sep' }),
      row(sample(12, 16, [dot('error')]), 'Error'),
      row(sample(12, 16, [dot('warning')]), 'Warning'),
      row(sample(12, 16, [dot('info')]), 'Info'),
    ].forEach((r) => body.appendChild(r));
  }

  /* ---------- fonts ---------- */
  async function ensureFonts() {
    ['t-kind', 't-name', 't-name t-mono', 't-sum', 't-elabel', 't-row', 't-key', 't-flow'].forEach((c) => VM.layout.textWidth('Ag 0123 ·', c));
    try { await Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 2500))]); } catch (_) { /* ignore */ }
    VM.layout.clearMeasureCache();
  }

  /* ---------- escape, shortcuts ---------- */
  function onEscape(e) {
    if (VM.search.isOpen()) { VM.search.close(); e.preventDefault(); return; }
    if (anyMenuOpen()) { closeMenus(); e.preventDefault(); return; }
    if (P.isOpen()) { P.dismiss(); e.preventDefault(); return; }
    if (F.isOpen()) { F.close(); e.preventDefault(); return; }
    if (state.selected) { A.clearSelection(); e.preventDefault(); }
  }
  function inField(t) { return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable); }

  function wire() {
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { onEscape(e); return; }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); VM.search.open(); return; }
      if (e.ctrlKey || e.metaKey || e.altKey || inField(e.target) || VM.search.isOpen()) return;
      if (e.key === '/') { e.preventDefault(); VM.search.open(); }
      else if (e.key === 'f' || e.key === 'F') { R.fit(true); }
      else if (e.key === 't' || e.key === 'T') { e.preventDefault(); A.openTrace(); }
    });
    document.addEventListener('click', (e) => {
      menus.forEach((m) => { if (!m.el.hidden && !m.el.parentNode.contains(e.target)) m.close(false); });
    });
    $('zoomIn').addEventListener('click', () => R.zoomBy(1.4));
    $('zoomOut').addEventListener('click', () => R.zoomBy(1 / 1.4));
    $('zoomFit').addEventListener('click', () => R.fit(true));
    $('traceBtn').addEventListener('click', () => A.openTrace());
    $('legendBtn').addEventListener('click', () => {
      const body = $('legendBody');
      body.hidden = !body.hidden;
      $('legendBtn').setAttribute('aria-expanded', String(!body.hidden));
    });
    const exportItems = () => [
      { label: 'PNG image (2x)', run: () => VM.exp.png() },
      { label: 'SVG image', run: () => VM.exp.svg() },
      { label: 'JSON model', run: () => VM.exp.json() },
    ];
    makeMenu($('exportBtn'), $('exportMenu'), exportItems);
    makeMenu($('moreBtn'), $('moreMenu'), () => [{ label: 'Findings', run: () => F.toggle() }, 'sep'].concat(exportItems()));
    makeMenu($('viewBtn'), $('viewMenu'), () => [
      { label: 'Expand all', run: () => setAllExpanded(true) },
      { label: 'Collapse all', run: () => setAllExpanded(false) },
      { label: 'Fit to screen', run: () => R.fit(true) },
    ]);
    window.addEventListener('hashchange', () => { if (booted) applyHash(); });
  }

  async function applyHash() {
    const hs = parseHash();
    const want = new Set(hs.expanded.filter((id) => M.isExpandable(M.get(id))));
    let diff = want.size !== state.expanded.size;
    want.forEach((id) => { if (!state.expanded.has(id)) diff = true; });
    if (hs.trace) {
      if (!window.VMTrace || !M.get(hs.trace.from)) return;
      P.setMode('trace'); P.open();
      const when = hs.trace.at ? new Date(hs.trace.at) : new Date();
      P.startTrace(hs.trace.from, isNaN(when) ? new Date() : when, hs.trace.keys);
      return;
    }
    // An entity/map link replaces any running trace; otherwise updateHash()
    // would keep rewriting the address back to the trace.
    if (P.session()) { P.endTrace(); P.setMode('details'); }
    if (diff) { state.expanded = want; await relayout({ animate: booted }); }
    if (hs.selected && M.get(hs.selected)) await A.select(hs.selected, { zoom: true });
    else if (!hs.selected && state.selected) { P.close(); A.clearSelection(); }
  }

  /* ---------- boot ---------- */
  async function boot() {
    let raw = null;
    try { raw = M.load(); } catch (err) { showState('The model could not be read', String(err && err.message ? err.message : err)); return; }
    if (!raw) { showState('No model in this page', 'Open a report generated by Export-TeamsVoiceFlowReport.'); return; }
    const t = M.tenant || {};
    $('tenantMeta').textContent = [t.name, M.generated() ? 'generated ' + M.generated() : ''].filter(Boolean).join(' · ');
    document.title = 'Voice map' + (t.name ? ' · ' + t.name : '');
    buildLegend();
    R.init({
      onSelect: (id) => A.select(id, { fromMap: true }),
      onToggle: (id) => A.toggle(id),
      onBackground: () => { A.clearSelection(); if (P.isOpen() && !P.session()) P.close(); },
    });
    // On mobile the panel/drawer is a bottom sheet: keep zoom targets above it.
    const sheetHeight = () => {
      const el = document.querySelector('.panel[data-open="true"], .drawer[data-open="true"]');
      return el ? el.getBoundingClientRect().height : 0;
    };
    R.insets = () => (isMobile() ? { left: 0, right: 0, bottom: sheetHeight() } : { left: F.width(), right: P.width(), bottom: 0 });
    P.init({ onClose: () => A.clearSelection(), onTraceChange });
    F.init({});
    VM.search.init();
    wire();
    if (!window.VMTrace) { $('traceBtn').disabled = true; $('traceBtn').title = 'Trace engine not loaded'; }
    else P.refreshEntryPoints();

    if (!M.list.length) {
      showState('Nothing to map', 'This model has no auto attendants, call queues or numbers.', [{ label: 'Download JSON model', onclick: () => VM.exp.json() }]);
      return;
    }

    const hs = parseHash();
    hs.expanded.forEach((id) => { if (M.isExpandable(M.get(id))) state.expanded.add(id); });
    showLoading(true, 'Laying out ' + M.list.length + ' objects…');
    await ensureFonts();
    const ok = await relayout({ animate: false, immediate: true });
    if (!ok) return;
    R.fit(false);
    booted = true;
    if (hs.trace || hs.selected) await applyHash();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
