/* Voice map: right panel (entity details + trace UI). All model text goes in via textContent. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M;
  const h = U.h, clear = U.clear;
  const P = (VM.panel = {});

  let els = {};
  let mode = 'details';
  let handlers = {};
  let currentId = null;

  /* ---------- small builders ---------- */
  const link = (id, label) => h('button', { type: 'button', class: 'link', onclick: () => VM.app.select(id, { zoom: true }) }, label || M.name(id));
  function secOf(title, kids) { return h('section', { class: 'sec' }, h('h3', { class: 'sec-title', text: title }), kids); }
  function kv(pairs) {
    const dl = h('dl', { class: 'kv' });
    pairs.forEach((p) => {
      if (p[1] == null || p[1] === '') return;
      dl.appendChild(h('dt', { text: p[0] }));
      dl.appendChild(h('dd', null, p[1]));
    });
    return dl;
  }
  const yn = (b) => (b ? 'Yes' : 'No');
  const mono = (t) => h('span', { class: 'mono', text: t });
  function list(items) { return h('ul', { class: 'list' }, items.map((i) => h('li', null, i))); }

  function copyBtn(text) {
    const b = h('button', { type: 'button', class: 'copy-btn', 'aria-label': 'Copy id' }, 'Copy');
    let timer = null;
    b.addEventListener('click', async () => {
      let ok = false;
      try { await navigator.clipboard.writeText(text); ok = true; } catch (_) {
        try {
          const ta = h('textarea', { 'aria-hidden': 'true' });
          ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
          document.body.appendChild(ta); ta.select(); ok = document.execCommand('copy'); document.body.removeChild(ta);
        } catch (__) { ok = false; }
      }
      if (!ok) return;
      b.textContent = 'Copied';
      clearTimeout(timer);
      timer = setTimeout(() => { b.textContent = 'Copy'; }, 1200);
    });
    return b;
  }

  function greetingBlock(g) {
    const tag = g && g.type === 'tts' ? 'Text-to-speech' : g && g.type === 'audio' ? 'Audio file' : 'Silence';
    return h('div', null, h('div', { class: 'tag', text: tag }), h('div', { class: 'quote', text: M.greetingFull(g) }));
  }

  function scheduleBlock(flow) {
    const sch = flow.schedule;
    if (!sch) return null;
    if (sch.type === 'weekly') {
      const wrap = h('div');
      wrap.appendChild(h('div', { class: 'note', text: flow.key === 'afterHours' ? 'Business hours (this flow applies outside them)' : 'Weekly hours' }));
      const grid = h('div', { class: 'week', role: 'img', 'aria-label': M.weeklySummary(sch) || 'Weekly schedule' });
      M.days.forEach((d, i) => {
        const ranges = (sch.days && sch.days[d]) || [];
        grid.appendChild(h('span', { text: M.dayShort[i] }));
        const track = h('span', { class: 'track' });
        ranges.forEach((r) => {
          const a = toHours(r.start), b = toHours(r.end) || 24;
          const seg = h('span', { class: 'seg' });
          seg.style.left = (a / 24 * 100) + '%';
          seg.style.width = Math.max(0.5, (b - a) / 24 * 100) + '%';
          track.appendChild(seg);
        });
        grid.appendChild(track);
        grid.appendChild(h('span', { class: 'hrs', text: ranges.map((r) => r.start + '–' + r.end).join(', ') || 'closed' }));
      });
      wrap.appendChild(grid);
      return wrap;
    }
    if (sch.type === 'fixed') {
      return h('div', null, h('div', { class: 'note', text: 'Date ranges' }), list((sch.ranges || []).map((r) => mono(M.rangeText(r, true)))));
    }
    return null;
  }
  function toHours(t) { const m = /^(\d{1,2}):(\d{2})/.exec(t || ''); return m ? Number(m[1]) + Number(m[2]) / 60 : 0; }

  function targetCell(o) {
    if (o.action === 'disconnect') return h('span', { class: 'muted', text: 'Hang up' });
    if (o.action === 'announcement') return h('div', null, o.targetRef ? link(o.targetRef) : null, o.announcement ? h('div', { class: 'quote', text: o.announcement.type === 'audio' ? 'Audio file: ' + (o.announcement.audioFile || 'unnamed') : (o.announcement.text || '') }) : null);
    if (o.targetRef) return link(o.targetRef);
    return h('span', { class: 'muted', text: '—' });
  }

  function flowCard(fl) {
    const card = h('div', { class: 'flow-card' }, h('h3', { text: M.flowHeader(fl) }));
    const s = scheduleBlock(fl);
    if (s) card.appendChild(s);
    card.appendChild(h('h4', { text: 'Greeting' }));
    const gs = fl.greetings && fl.greetings.length ? fl.greetings : [{ type: 'silence' }];
    gs.forEach((g) => card.appendChild(greetingBlock(g)));
    const menu = fl.menu || {};
    if (menu.prompts && menu.prompts.length) {
      card.appendChild(h('h4', { text: 'Menu prompt' }));
      menu.prompts.forEach((g) => card.appendChild(greetingBlock(g)));
    }
    card.appendChild(h('h4', { text: 'Menu options' }));
    const opts = menu.options || [];
    if (!opts.length) card.appendChild(h('p', { class: 'muted', text: 'No menu options. The call ends after the greeting.' }));
    else {
      const body = h('tbody');
      opts.forEach((o) => {
        body.appendChild(h('tr', null,
          h('td', { class: 'k', text: M.optionKeyLabel(o.key) }),
          h('td', null, M.actionLabel(o.action), o.voice && o.voice.length ? h('div', { class: 'tag', text: 'voice: ' + o.voice.join(', ') }) : null),
          h('td', null, targetCell(o))));
      });
      card.appendChild(h('table', { class: 'tbl' }, h('thead', null, h('tr', null, h('th', { text: 'Key' }), h('th', { text: 'Action' }), h('th', { text: 'Target' }))), body));
    }
    return card;
  }

  function aaSections(e) {
    const out = [];
    out.push(secOf('Settings', kv([
      ['Language', e.language],
      ['Time zone', e.timeZone ? e.timeZone + (e.timeZoneIana && e.timeZoneIana !== e.timeZone ? ' (' + e.timeZoneIana + ')' : '') : null],
      ['Operator', e.operatorRef ? link(e.operatorRef) : 'None'],
      ['Dial by name', e.dialByName ? 'Yes' + (e.directorySearchMethod ? ' (' + e.directorySearchMethod + ')' : '') : 'No'],
      ['Voice response', yn(e.voiceResponse)],
    ])));
    out.push(raSection(e.resourceAccountIds));
    out.push(secOf('Flows', (e.flows || []).length ? (e.flows || []).map(flowCard) : h('p', { class: 'muted', text: 'No flows.' })));
    return out;
  }

  function raSection(ids) {
    return secOf('Resource accounts', (ids || []).length ? list(ids.map((id) => {
      const ra = M.get(id);
      return [link(id), ra && ra.phoneNumbers && ra.phoneNumbers.length ? mono(ra.phoneNumbers.join(', ')) : h('span', { class: 'tag', text: 'no number' })];
    })) : h('p', { class: 'muted', text: 'None.' }));
  }

  function cqSections(e) {
    const out = [];
    const gr = e.greeting || { type: 'none' };
    const mo = e.musicOnHold || {};
    out.push(secOf('Routing', kv([
      ['Method', M.routing(e.routingMethod)],
      ['Agent alert', e.agentAlertSeconds != null ? e.agentAlertSeconds + ' s' : null],
      ['Conference mode', yn(e.conferenceMode)],
      ['Presence-based', yn(e.presenceBasedRouting)],
      ['Allow opt-out', yn(e.allowOptOut)],
      ['SLA', e.slaSeconds != null ? e.slaSeconds + ' s' : null],
      ['Language', e.language],
      ['Music on hold', mo.type === 'custom' ? 'Custom: ' + (mo.audioFile || 'file') : 'Default'],
    ])));
    out.push(secOf('Greeting', gr.type === 'none' ? h('p', { class: 'muted', text: 'No greeting.' }) : greetingBlock(gr)));
    out.push(secOf('Agents (' + (e.agentIds || []).length + ')', (e.agentIds || []).length ? list(e.agentIds.map((id) => [link(id), h('span', { class: 'tag', text: (M.get(id) && M.get(id).upn) || '' })])) : h('p', { class: 'muted', text: 'None.' })));
    if ((e.groupIds || []).length) out.push(secOf('Groups', list(e.groupIds.map((id) => link(id)))));
    if (e.channel) out.push(secOf('Teams channel', kv([['Channel id', mono(e.channel.id)], ['Owner', e.channel.ownerId ? link(e.channel.ownerId) : null]])));
    if ((e.oboResourceAccountIds || []).length) out.push(secOf('Caller ID (OBO) resource accounts', list(e.oboResourceAccountIds.map((id) => link(id)))));
    out.push(raSection(e.resourceAccountIds));
    const ex = e.exceptions || {};
    const rows = [];
    const add = (name, cond, thr, x) => { if (x) rows.push(h('tr', null, h('td', { text: cond }), h('td', { class: 'k', text: thr }), h('td', { text: M.actionLabel(x.action) }), h('td', null, x.targetRef ? link(x.targetRef) : h('span', { class: 'muted', text: '—' })))); };
    add('overflow', 'Overflow', ex.overflow ? 'over ' + ex.overflow.threshold + ' calls' : '', ex.overflow);
    add('timeout', 'Timeout', ex.timeout ? 'after ' + ex.timeout.threshold + ' s' : '', ex.timeout);
    add('noAgent', 'No agents', '', ex.noAgent);
    out.push(secOf('Exceptions', rows.length
      ? h('table', { class: 'tbl' }, h('thead', null, h('tr', null, h('th', { text: 'Condition' }), h('th', { text: 'Threshold' }), h('th', { text: 'Action' }), h('th', { text: 'Target' }))), h('tbody', null, rows))
      : h('p', { class: 'muted', text: 'None configured.' })));
    return out;
  }

  function otherSections(e) {
    const pairs = [];
    switch (e.kind) {
      case 'number': pairs.push(['Number', mono(e.number || e.name)], ['Resource account', e.resourceAccountId ? link(e.resourceAccountId) : null]); break;
      case 'external': pairs.push(['Number', mono(e.number || e.name)]); break;
      case 'resourceAccount':
        pairs.push(['UPN', e.upn ? mono(e.upn) : null], ['Application', e.appType === 'autoAttendant' ? 'Auto attendant' : e.appType === 'callQueue' ? 'Call queue' : 'Not assigned'],
          ['Assigned to', e.configId ? link(e.configId) : null], ['Phone numbers', (e.phoneNumbers || []).length ? mono(e.phoneNumbers.join(', ')) : 'None']); break;
      case 'user': pairs.push(['UPN', e.upn ? mono(e.upn) : null]); break;
      case 'group': pairs.push(['Shared voicemail', yn(e.isSharedVoicemail)]); break;
      case 'system': pairs.push(['Type', e.systemType], ['Resolves to', e.targetRef ? link(e.targetRef) : null]); break;
      default: break;
    }
    if (e.unresolved) pairs.push(['Status', 'Not found in the tenant']);
    return [secOf('Properties', kv(pairs))];
  }

  function connections(e) {
    const inc = M.inc.get(e.id) || [], out = M.out.get(e.id) || [];
    const li = (id, ed) => [link(id), h('span', { class: 'tag', text: M.edgeText(ed) })];
    const res = [];
    res.push(secOf('Reached from', inc.length ? list(inc.map((ed) => li(ed.from, ed))) : h('p', { class: 'muted', text: 'Nothing routes here.' })));
    res.push(secOf('Goes to', out.length ? list(out.map((ed) => li(ed.to, ed))) : h('p', { class: 'muted', text: 'Nothing. The call ends here.' })));
    return res;
  }

  function findingsBlock(e) {
    const fs = M.findingsFor(e.id);
    if (!fs.length) return null;
    return h('div', { class: 'fnd', role: 'list', 'aria-label': 'Findings' }, fs.map((f) =>
      h('div', { class: 'fnd-item', role: 'listitem' }, h('span', { class: 'sev-dot sev-' + f.severity, 'aria-hidden': 'true' }), h('span', null, h('span', { class: 'tag', text: f.severity + ' · ' + f.code }), h('div', { text: f.message })))));
  }

  P.showEntity = function (id) {
    currentId = id;
    const e = M.get(id);
    const root = clear(els.details);
    if (!e) { root.appendChild(h('p', { class: 'empty', text: 'Select an object on the map to see its details.' })); return; }
    root.appendChild(h('div', { class: 'ph' },
      h('div', { class: 'ph-kind', text: M.kindLabel(e) }),
      h('h2', { class: 'ph-name', text: String(e.kind === 'number' ? (e.number || e.name) : e.name) }),
      h('div', { class: 'ph-id' }, h('code', { text: e.id, title: e.id }), copyBtn(e.id))));
    const f = findingsBlock(e);
    if (f) root.appendChild(f);
    const body = e.kind === 'autoAttendant' ? aaSections(e) : e.kind === 'callQueue' ? cqSections(e) : otherSections(e);
    body.forEach((s) => root.appendChild(s));
    connections(e).forEach((s) => root.appendChild(s));
    root.scrollTop = 0;
  };
  P.current = () => currentId;
  P.clearEntity = function () {
    currentId = null;
    clear(els.details).appendChild(h('p', { class: 'empty', text: 'Select an object on the map to see its details.' }));
  };

  /* ---------- panel chrome ---------- */
  P.isOpen = () => els.panel.getAttribute('data-open') === 'true';
  P.open = function () { els.panel.setAttribute('data-open', 'true'); els.panel.removeAttribute('inert'); handlers.onLayoutChange && handlers.onLayoutChange(); };
  P.close = function () { els.panel.setAttribute('data-open', 'false'); els.panel.setAttribute('inert', ''); handlers.onLayoutChange && handlers.onLayoutChange(); };
  P.mode = () => mode;
  P.setMode = function (m) {
    mode = m;
    const d = m === 'details';
    els.details.hidden = !d; els.trace.hidden = d;
    els.tabD.setAttribute('aria-selected', String(d)); els.tabT.setAttribute('aria-selected', String(!d));
    els.tabD.tabIndex = d ? 0 : -1; els.tabT.tabIndex = d ? -1 : 0;
    if (!d) { renderTrace(); }
  };
  /* Closing the panel ends any running trace. */
  P.dismiss = function () {
    if (S) P.endTrace();
    P.close();
    handlers.onClose && handlers.onClose();
  };
  P.width = () => (P.isOpen() ? els.panel.getBoundingClientRect().width : 0);

  P.init = function (hnd) {
    handlers = hnd || {};
    els = {
      panel: document.getElementById('panel'), details: document.getElementById('panelDetails'), trace: document.getElementById('panelTrace'),
      tabD: document.getElementById('tabDetails'), tabT: document.getElementById('tabTrace'),
    };
    els.panel.setAttribute('inert', '');
    els.tabD.addEventListener('click', () => P.setMode('details'));
    els.tabT.addEventListener('click', () => P.setMode('trace'));
    [els.tabD, els.tabT].forEach((t) => t.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') { const to = t === els.tabD ? els.tabT : els.tabD; P.setMode(to === els.tabD ? 'details' : 'trace'); to.focus(); }
    }));
    document.getElementById('panelClose').addEventListener('click', () => P.dismiss());
    P.clearEntity();
    buildTraceForm();
  };

  /* =====================================================================
     Trace UI. Logic is in window.VMTrace; this only drives it.
     ===================================================================== */
  let S = null;                          // { entryId, when, inputs, state, error }
  let tf = {};                           // trace form elements

  function pad2(n) { return (n < 10 ? '0' : '') + n; }
  function localInput(d) { return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + 'T' + pad2(d.getHours()) + ':' + pad2(d.getMinutes()); }

  /* Time zone of the attendant/queue the entry point reaches (IANA), or null. */
  function tzFor(entryId) {
    try { return (window.VMTrace && VMTrace.entryTimeZone && entryId ? VMTrace.entryTimeZone(M.raw, entryId) : null) || null; } catch (_) { return null; }
  }
  function toWall(date, tz) { return window.VMTrace && VMTrace.dateToWallClock ? VMTrace.dateToWallClock(date, tz) : localInput(date); }
  function fromWall(text, tz) {
    if (!text) return new Date();
    const d = window.VMTrace && VMTrace.wallClockToDate ? VMTrace.wallClockToDate(text, tz) : new Date(text);
    return d && !isNaN(d) ? d : new Date();
  }
  function zoneLabel(tz) { return tz ? 'Time in ' + tz : 'Time in your local zone (attendant time zone unknown)'; }
  /* Re-express the current value in the zone of the selected entry point (same instant). */
  function applyZone() {
    if (!tf.select || !tf.when) return;
    const tz = tzFor(tf.select.value);
    if (tz !== tf.tz) {
      let inst = null;
      try { inst = tf.when.value ? fromWall(tf.when.value, tf.tz) : new Date(); } catch (_) { inst = new Date(); }
      tf.tz = tz;
      tf.when.value = toWall(inst, tz);
    }
    tf.zone.textContent = zoneLabel(tf.tz);
  }

  function buildTraceForm() {
    const root = clear(els.trace);
    if (!window.VMTrace) {
      root.appendChild(h('p', { class: 'empty', text: 'The trace engine is not loaded in this build.' }));
      tf = {};
      return;
    }
    tf.select = h('select', { class: 'select', id: 'trEntry' });
    tf.tz = null;
    tf.when = h('input', { class: 'input', id: 'trWhen', type: 'datetime-local', value: localInput(new Date()) });
    tf.zone = h('span', { class: 'note', id: 'trZone', text: zoneLabel(null) });
    tf.select.addEventListener('change', applyZone);
    tf.start = h('button', { type: 'button', class: 'btn btn-primary', onclick: () => startFromForm() }, 'Start');
    tf.restart = h('button', { type: 'button', class: 'btn', disabled: true, onclick: () => restart() }, 'Restart');
    tf.end = h('button', { type: 'button', class: 'btn', id: 'trEnd', disabled: true, onclick: () => P.endTrace() }, 'End trace');
    tf.run = h('div', { class: 'tr-run', 'aria-live': 'polite' });
    root.appendChild(h('div', { class: 'tr-form' },
      h('label', { class: 'field', for: 'trEntry' }, h('span', { text: 'Entry point' }), tf.select),
      h('label', { class: 'field', for: 'trWhen' }, h('span', { text: 'Date and time' }), tf.when, tf.zone),
      h('div', { class: 'btn-row' }, tf.start, tf.restart, tf.end)));
    root.appendChild(tf.run);
  }

  P.refreshEntryPoints = function () {
    if (!window.VMTrace || !tf.select) return;
    clear(tf.select);
    let eps = [];
    try { eps = VMTrace.entryPoints(M.raw) || []; } catch (err) { eps = []; }
    const word = { number: 'Number', autoAttendant: 'Auto attendant', callQueue: 'Call queue' };
    eps.forEach((ep) => tf.select.appendChild(h('option', { value: ep.id, text: ep.label + ' · ' + (word[ep.kind] || ep.kind) })));
    if (S && S.entryId) tf.select.value = S.entryId;
    applyZone();
  };

  function startFromForm() {
    if (!tf.select || !tf.select.value) return;
    applyZone();
    P.startTrace(tf.select.value, fromWall(tf.when.value, tf.tz), []);
  }
  function restart() { if (S) P.startTrace(S.entryId, S.when, []); }

  /** Starts (or replays) a trace. inputs: array of keys/branches. */
  P.startTrace = function (entryId, when, inputs) {
    if (!window.VMTrace) return null;
    S = { entryId, when, inputs: [], state: null, error: null };
    try {
      S.state = VMTrace.start(M.raw, entryId, when);
      (inputs || []).forEach((k) => {
        if (S.state.done) return;
        S.state = VMTrace.advance(M.raw, S.state, k);
        S.inputs.push(k);
      });
    } catch (err) { S.error = String(err && err.message ? err.message : err); }
    if (tf.select) { P.refreshEntryPoints(); tf.select.value = entryId; tf.tz = tzFor(entryId); tf.when.value = toWall(when, tf.tz); tf.zone.textContent = zoneLabel(tf.tz); }
    renderTrace();
    handlers.onTraceChange && handlers.onTraceChange(S);
    return S;
  };
  P.advanceTrace = function (input) {
    if (!S || !S.state || S.state.done) return;
    try { S.state = VMTrace.advance(M.raw, S.state, input); S.inputs.push(input); S.error = null; } catch (err) { S.error = String(err && err.message ? err.message : err); }
    renderTrace();
    handlers.onTraceChange && handlers.onTraceChange(S);
  };
  P.session = () => S;
  P.endTrace = function () { S = null; renderTrace(); handlers.onTraceChange && handlers.onTraceChange(null); };

  const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

  function renderTrace() {
    if (!tf.run) return;
    const run = clear(tf.run);
    tf.restart.disabled = !S;
    if (tf.end) tf.end.disabled = !S;
    if (!S) { run.appendChild(h('p', { class: 'empty', text: 'Pick where the call comes in and press Start. You choose the menu keys as you go.' })); return; }
    if (S.error) run.appendChild(h('p', { class: 'note', role: 'alert', text: 'Trace error: ' + S.error }));
    const st = S.state;
    if (!st) return;
    const steps = h('ol', { class: 'steps', 'aria-label': 'Call path' });
    st.steps.forEach((s, i) => {
      const last = i === st.steps.length - 1;
      steps.appendChild(h('li', { class: 'step' + (last && !st.done ? ' current' : '') },
        h('button', { type: 'button', class: 'step-btn', onclick: () => VM.app.select(s.entityId, { zoom: true, keepMode: true }) },
          h('div', null, h('div', { class: 'step-text', text: s.text || M.name(s.entityId) }), s.note ? h('div', { class: 'step-note', text: s.note }) : null))));
    });
    run.appendChild(steps);

    const pend = st.pending;
    if (pend && pend.type === 'menu') {
      const wrap = h('div', { class: 'pending' }, h('div', { class: 'sec-title', text: 'Press a key' }));
      const byKey = new Map(pend.options.map((o) => [String(o.key), o]));
      const pad = h('div', { class: 'keypad', role: 'group', 'aria-label': 'Keypad' });
      KEYS.forEach((k) => {
        const o = byKey.get(k);
        const btn = h('button', { type: 'button', class: 'key', text: k, disabled: !o, 'aria-label': o ? 'Key ' + k + ': ' + o.label : 'Key ' + k + ' (no option)', onclick: () => P.advanceTrace(k) });
        pad.appendChild(h('div', { class: 'key-cell' }, btn, h('div', { class: 'key-label', text: o ? o.label : '', title: o ? o.label : '' })));
      });
      wrap.appendChild(pad);
      const extra = pend.options.filter((o) => KEYS.indexOf(String(o.key)) < 0);
      if (extra.length) {
        const row = h('div', { class: 'btn-row' });
        extra.forEach((o) => row.appendChild(h('button', { type: 'button', class: 'btn', onclick: () => P.advanceTrace(String(o.key)) }, String(o.key) === 'automatic' ? 'Continue' : String(o.key), o.label ? h('span', { class: 'tag', text: o.label }) : null)));
        wrap.appendChild(row);
      }
      run.appendChild(wrap);
    } else if (pend && pend.type === 'queue') {
      const wrap = h('div', { class: 'pending' }, h('div', { class: 'sec-title', text: 'What happens to the call?' }));
      const row = h('div', { class: 'btn-row' });
      pend.branches.forEach((b) => row.appendChild(h('button', { type: 'button', class: 'btn', onclick: () => P.advanceTrace(b.branch) }, b.label || b.branch)));
      wrap.appendChild(row);
      run.appendChild(wrap);
    } else if (st.done) {
      run.appendChild(h('p', { class: 'done-note', text: 'End of path. Press Restart to try another route.' }));
    }
  }

  P.renderTrace = renderTrace;
})();
