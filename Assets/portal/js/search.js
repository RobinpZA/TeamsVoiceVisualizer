/* Voice map: Ctrl+K search palette. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M;
  const h = U.h, clear = U.clear;
  const S = (VM.search = {});

  const GROUPS = [
    ['number', 'Numbers'], ['external', 'External numbers'], ['autoAttendant', 'Auto attendants'], ['callQueue', 'Call queues'],
    ['resourceAccount', 'Resource accounts'], ['user', 'People'], ['group', 'Groups'], ['system', 'System'],
  ];
  let modal, input, listEl, index = [], results = [], active = 0, lastFocus = null;

  function buildIndex() {
    index = M.list.map((e) => {
      const fields = [];       // secondary searchable strings
      const add = (v) => { if (v) fields.push(String(v)); };
      add(e.number); add(e.upn); (e.phoneNumbers || []).forEach(add);
      if (e.kind === 'autoAttendant') {
        (e.flows || []).forEach((f) => {
          add(f.label);
          (f.greetings || []).forEach((g) => { add(g.text); add(g.audioFile); });
          const m = f.menu || {};
          (m.prompts || []).forEach((g) => { add(g.text); add(g.audioFile); });
          (m.options || []).forEach((o) => { (o.voice || []).forEach(add); if (o.announcement) add(o.announcement.text); });
        });
      }
      if (e.kind === 'callQueue') { const g = e.greeting || {}; add(g.text); add(g.audioFile); }
      const name = String(e.kind === 'number' ? (e.number || e.name) : (e.name || e.id));
      const digits = (name + ' ' + fields.join(' ')).replace(/\D/g, '');
      return { e, name, nameL: name.toLowerCase(), fields, fieldsL: fields.map((f) => f.toLowerCase()), digits };
    });
  }

  function subseq(needle, hay) {
    let i = 0;
    for (let j = 0; j < hay.length && i < needle.length; j++) if (hay[j] === needle[i]) i++;
    return i === needle.length;
  }

  function run(q) {
    const tokens = q.toLowerCase().split(/\s+/).filter(Boolean);
    const out = [];
    index.forEach((it) => {
      let score = 0, snippet = '', ok = true;
      if (!tokens.length) { score = it.e.kind === 'autoAttendant' || it.e.kind === 'callQueue' ? 2 : 1; }
      else {
        for (const t of tokens) {
          let s = 0;
          if (it.nameL.startsWith(t)) s = 100;
          else if (it.nameL.indexOf(t) >= 0) s = 60;
          else {
            const fi = it.fieldsL.findIndex((f) => f.indexOf(t) >= 0);
            if (fi >= 0) { s = /^[\d+\s]+$/.test(t) || it.fieldsL[fi].length < 40 ? 50 : 20; if (!snippet) snippet = snip(it.fields[fi], t); }
            else if (/^\+?\d{3,}$/.test(t) && it.digits.indexOf(t.replace(/\D/g, '')) >= 0) s = 45;
            else if (t.length >= 3 && subseq(t, it.nameL)) s = 10;
          }
          if (!s) { ok = false; break; }
          score += s;
        }
      }
      if (ok) out.push({ it, score, snippet });
    });
    out.sort((a, b) => b.score - a.score || a.it.name.localeCompare(b.it.name));
    return out;
  }
  function snip(text, t) {
    const i = text.toLowerCase().indexOf(t);
    const a = Math.max(0, i - 24);
    return (a > 0 ? '…' : '') + text.slice(a, a + 72).replace(/\s+/g, ' ') + (a + 72 < text.length ? '…' : '');
  }

  function sub(r) {
    const e = r.it.e;
    if (r.snippet) return r.snippet;
    switch (e.kind) {
      case 'user': return e.upn || '';
      case 'resourceAccount': return [e.upn, (e.phoneNumbers || []).join(', ')].filter(Boolean).join(' · ');
      case 'number': return e.resourceAccountId ? 'Resource account: ' + M.name(e.resourceAccountId) : '';
      case 'autoAttendant': return M.summary(e);
      case 'callQueue': return M.summary(e);
      default: return '';
    }
  }

  function render() {
    const q = input.value.trim();
    const all = run(q);
    const byKind = new Map();
    all.forEach((r) => { const k = r.it.e.kind; if (!byKind.has(k)) byKind.set(k, []); byKind.get(k).push(r); });
    results = [];
    clear(listEl);
    GROUPS.forEach((g) => {
      const rs = (byKind.get(g[0]) || []).slice(0, 8);
      if (!rs.length) return;
      listEl.appendChild(h('div', { class: 'pgroup', role: 'presentation', text: g[1] }));
      rs.forEach((r) => {
        const idx = results.length;
        results.push(r);
        listEl.appendChild(h('div', { class: 'pitem', role: 'option', id: 'sr' + idx, 'aria-selected': 'false', onclick: () => choose(idx), onmousemove: () => { if (active !== idx) setActive(idx, false); } },
          h('div', { class: 'pitem-name', text: r.it.name }),
          h('div', { class: 'pitem-sub', text: sub(r) })));
      });
    });
    if (!results.length) listEl.appendChild(h('div', { class: 'empty', role: 'presentation', text: q ? 'Nothing matches "' + q + '".' : 'Nothing to search.' }));
    setActive(0, true);
  }

  function setActive(i, scroll) {
    active = results.length ? (i + results.length) % results.length : 0;
    Array.prototype.forEach.call(listEl.querySelectorAll('.pitem'), (el, n) => el.setAttribute('aria-selected', String(n === active)));
    const el = document.getElementById('sr' + active);
    if (el) { input.setAttribute('aria-activedescendant', el.id); if (scroll) el.scrollIntoView({ block: 'nearest' }); }
    else input.removeAttribute('aria-activedescendant');
  }
  function choose(i) {
    const r = results[i];
    if (!r) return;
    S.close(true);
    VM.app.select(r.it.e.id, { zoom: true });
  }

  S.isOpen = () => modal && !modal.hidden;
  S.open = function () {
    if (S.isOpen()) { input.focus(); return; }
    lastFocus = document.activeElement;
    modal.hidden = false;
    input.value = '';
    render();
    input.focus();
  };
  S.close = function (skipRestore) {
    if (!S.isOpen()) return;
    modal.hidden = true;
    if (!skipRestore && lastFocus && lastFocus.focus) lastFocus.focus();
  };
  S.rebuild = buildIndex;

  S.init = function () {
    modal = document.getElementById('searchModal');
    input = document.getElementById('searchInput');
    listEl = document.getElementById('searchList');
    buildIndex();
    input.addEventListener('input', render);
    document.getElementById('searchScrim').addEventListener('click', () => S.close());
    document.getElementById('searchBtn').addEventListener('click', () => S.open());
    modal.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') { e.preventDefault(); setActive(active + 1, true); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(active - 1, true); }
      else if (e.key === 'Enter') { e.preventDefault(); choose(active); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); S.close(); }
      else if (e.key === 'Tab') { e.preventDefault(); input.focus(); }       // focus trap: the input is the only stop
    });
    // Keep focus inside the dialog: clicks on non-focusable body, or focus escaping, return to the input.
    modal.addEventListener('mousedown', (e) => {
      if (e.target === input || e.target.id === 'searchScrim') return;
      e.preventDefault();
      input.focus();
    });
    modal.addEventListener('focusout', (e) => {
      if (!S.isOpen()) return;
      if (e.relatedTarget && modal.contains(e.relatedTarget)) return;
      setTimeout(() => { if (S.isOpen() && !modal.contains(document.activeElement)) input.focus(); }, 0);
    });
    document.addEventListener('focusin', (e) => {
      if (S.isOpen() && !modal.contains(e.target)) input.focus();
    });
  };
})();
