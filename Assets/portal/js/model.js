/* Voice map: model access and shared helpers. Namespace: window.VM */
(function () {
  'use strict';
  const VM = (window.VM = window.VM || {});

  /* ---------- DOM helper: text only, never innerHTML ---------- */
  function h(tag, props) {
    const el = document.createElement(tag);
    if (props) {
      for (const k in props) {
        const v = props[k];
        if (v == null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
        else el.setAttribute(k, v === true ? '' : v);
      }
    }
    for (let i = 2; i < arguments.length; i++) appendKids(el, arguments[i]);
    return el;
  }
  function appendKids(el, kid) {
    if (kid == null || kid === false) return;
    if (Array.isArray(kid)) { kid.forEach((k) => appendKids(el, k)); return; }
    el.appendChild(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }
  const SVGNS = 'http://www.w3.org/2000/svg';
  function s(tag, attrs) {
    const el = document.createElementNS(SVGNS, tag);
    if (attrs) for (const k in attrs) if (attrs[k] != null) el.setAttribute(k, attrs[k]);
    return el;
  }
  function cssNum(name, fallback) {
    const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name));
    return Number.isFinite(v) ? v : fallback;
  }
  function truncate(str, n) {
    str = String(str == null ? '' : str).replace(/\s+/g, ' ').trim();
    return str.length > n ? str.slice(0, n - 1).trimEnd() + '…' : str;
  }
  function reducedMotion() { return !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches); }

  VM.u = { h, clear, s, SVGNS, cssNum, truncate, reducedMotion };

  /* ---------- labels ---------- */
  const KIND_ORDER = ['number', 'resourceAccount', 'autoAttendant', 'callQueue', 'user', 'group', 'external', 'system'];
  const SEV_RANK = { error: 3, warning: 2, info: 1 };
  const ROUTING = { Attendant: 'Attendant', Serial: 'Serial', RoundRobin: 'Round robin', LongestIdle: 'Longest idle' };
  const DAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  const DAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  function kindLabel(e) {
    if (!e) return '';
    switch (e.kind) {
      case 'autoAttendant': return 'AUTO ATTENDANT';
      case 'callQueue': return 'CALL QUEUE';
      case 'resourceAccount': return 'RESOURCE ACCOUNT';
      case 'number': return 'NUMBER';
      case 'user': return 'USER';
      case 'external': return 'EXTERNAL';
      case 'group': return e.isSharedVoicemail ? 'VOICEMAIL' : 'GROUP';
      case 'system': return String(e.systemType || 'system').toUpperCase();
      default: return String(e.kind || '').toUpperCase();
    }
  }

  /* ---------- schedule / flow text ---------- */
  function fmtDate(iso) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
    if (!m) return String(iso || '');
    return Number(m[3]) + ' ' + MONTHS[Number(m[2]) - 1];
  }
  function fmtDateLong(iso) { const m = /^(\d{4})/.exec(iso || ''); return fmtDate(iso) + (m ? ' ' + m[1] : ''); }
  function fmtTime(iso) { const m = /T(\d{2}:\d{2})/.exec(iso || ''); return m ? m[1] : ''; }
  function dayBefore(iso) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
    if (!m) return iso;
    const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    d.setUTCDate(d.getUTCDate() - 1);
    return d.toISOString().slice(0, 10) + 'T00:00:00';
  }
  /** Date range text for a fixed range; end is exclusive when it is midnight. */
  function rangeText(r, long) {
    const f = long ? fmtDateLong : fmtDate;
    const midnightEnd = fmtTime(r.end) === '00:00';
    const lastDay = midnightEnd ? dayBefore(r.end) : r.end;
    const sameDay = String(r.start).slice(0, 10) === String(lastDay).slice(0, 10);
    const timed = !(fmtTime(r.start) === '00:00' && midnightEnd);
    if (sameDay && !timed) return f(r.start);
    if (!timed) return f(r.start) + '–' + f(lastDay);
    return f(r.start) + ' ' + fmtTime(r.start) + '–' + (sameDay ? '' : f(r.end) + ' ') + fmtTime(r.end);
  }
  function weeklySummary(sch) {
    if (!sch || sch.type !== 'weekly' || !sch.days) return '';
    const groups = [];
    DAYS.forEach((d, i) => {
      const rs = (sch.days[d] || []).map((r) => r.start + '–' + r.end).join(', ');
      if (!rs) return;
      const last = groups[groups.length - 1];
      if (last && last.rs === rs && last.to === i - 1) last.to = i;
      else groups.push({ from: i, to: i, rs });
    });
    return groups.slice(0, 3).map((g) => (g.from === g.to ? DAY_SHORT[g.from] : DAY_SHORT[g.from] + '–' + DAY_SHORT[g.to]) + ' ' + g.rs).join(' · ') + (groups.length > 3 ? ' …' : '');
  }
  function flowHeader(flow) {
    if (!flow) return '';
    const label = String(flow.label || flow.key || '');
    if (flow.key === 'default') return label || 'Business hours';
    if (flow.key === 'afterHours') {
      const w = weeklySummary(flow.schedule);
      return (label || 'After hours') + (w ? ' · ' + w : '');
    }
    const lab = label.replace(/:\s*/, ' · ');
    const r = flow.schedule && flow.schedule.ranges && flow.schedule.ranges[0];
    return lab + (r ? ' · ' + rangeText(r) : '');
  }
  function flowShort(flow) { return String((flow && (flow.label || flow.key)) || '').replace(/:\s*/, ' ').toLowerCase(); }

  function firstLine(text) {
    const lines = String(text || '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    return lines[0] || '';
  }
  function greetingLine(g) {
    if (!g) return 'Silence';
    if (g.type === 'tts') return firstLine(g.text) || 'Silence';
    if (g.type === 'audio') return 'Audio: ' + (g.audioFile || 'file');
    return 'Silence';
  }
  function greetingFull(g) {
    if (!g) return 'Silence';
    if (g.type === 'tts') return g.text || '(empty text-to-speech)';
    if (g.type === 'audio') return 'Audio file: ' + (g.audioFile || 'unnamed');
    return 'Silence';
  }

  /* ---------- model ---------- */
  const M = (VM.M = {
    raw: null, entities: {}, list: [], edges: [], findings: [],
    out: new Map(), inc: new Map(), fByEntity: new Map(), agentOnly: new Set(), edgeById: new Map(),
  });

  function readRaw() {
    const node = document.getElementById('voice-model');
    const txt = node && node.textContent.trim();
    if (txt) return JSON.parse(txt);
    if (window.__VM_DEV_MODEL__) return window.__VM_DEV_MODEL__;
    return null;
  }

  function init(raw) {
    M.raw = raw;
    M.entities = (raw && raw.entities) || {};
    M.edges = (raw && raw.edges) || [];
    M.findings = (raw && raw.findings) || [];
    M.tenant = (raw && raw.tenant) || {};
    M.list = Object.keys(M.entities).map((k) => M.entities[k]).sort((a, b) => {
      const ka = KIND_ORDER.indexOf(a.kind), kb = KIND_ORDER.indexOf(b.kind);
      if (ka !== kb) return ka - kb;
      return String(a.name || '').localeCompare(String(b.name || ''), undefined, { numeric: true, sensitivity: 'base' });
    });
    M.out.clear(); M.inc.clear(); M.fByEntity.clear(); M.agentOnly.clear(); M.edgeById.clear();
    M.edges.forEach((ed) => {
      M.edgeById.set(ed.id, ed);
      if (!M.out.has(ed.from)) M.out.set(ed.from, []);
      if (!M.inc.has(ed.to)) M.inc.set(ed.to, []);
      M.out.get(ed.from).push(ed);
      M.inc.get(ed.to).push(ed);
    });
    M.inc.forEach((eds, id) => {
      if (eds.length && eds.every((e) => e.kind === 'agent') && own(M.entities, id) && (M.entities[id].kind === 'user' || M.entities[id].kind === 'group')) M.agentOnly.add(id);
    });
    M.findings.forEach((f) => {
      if (!M.fByEntity.has(f.entityId)) M.fByEntity.set(f.entityId, []);
      M.fByEntity.get(f.entityId).push(f);
    });
  }

  M.load = function () { const raw = readRaw(); if (raw) init(raw); return raw; };
  M.init = init;
  const own = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
  const ent = (id) => (own(M.entities, id) ? M.entities[id] : null);
  M.get = (id) => ent(id);
  M.name = (id) => { const e = ent(id); return e ? String(e.name || e.number || id) : String(id == null ? '' : id); };
  M.kindLabel = kindLabel;
  M.findingsFor = (id) => M.fByEntity.get(id) || [];
  M.worst = (id) => {
    let best = null;
    M.findingsFor(id).forEach((f) => { if (!best || M.sevRank(f.severity) > M.sevRank(best)) best = f.severity; });
    return best;
  };
  M.sevRank = (sev) => (own(SEV_RANK, sev) ? SEV_RANK[sev] : 0);
  M.owners = (id) => (M.inc.get(id) || []).filter((e) => e.kind === 'agent').map((e) => e.from);
  M.isHiddenAt = (id, expanded) => M.agentOnly.has(id) && !M.owners(id).some((o) => expanded.has(o));
  M.routing = (m) => (own(ROUTING, m) ? ROUTING[m] : m || '');
  M.flowHeader = flowHeader;
  M.flowShort = flowShort;
  M.weeklySummary = weeklySummary;
  M.rangeText = rangeText;
  M.fmtTime = fmtTime;
  M.greetingLine = greetingLine;
  M.greetingFull = greetingFull;
  M.days = DAYS;
  M.dayShort = DAY_SHORT;
  M.optionCount = (aa) => (aa.flows || []).reduce((n, f) => n + ((f.menu && f.menu.options) ? f.menu.options.length : 0), 0);
  M.summary = (e) => {
    if (!e) return '';
    if (e.kind === 'autoAttendant') {
      const f = (e.flows || []).length, o = M.optionCount(e);
      return f + (f === 1 ? ' flow' : ' flows') + ' · ' + o + (o === 1 ? ' option' : ' options');
    }
    if (e.kind === 'callQueue') {
      const n = (e.agentIds || []).length, g = (e.groupIds || []).length;
      return M.routing(e.routingMethod) + ' · ' + n + (n === 1 ? ' agent' : ' agents') + (g ? ' + ' + g + (g === 1 ? ' group' : ' groups') : '');
    }
    return '';
  };
  M.isExpandable = (e) => !!e && (e.kind === 'autoAttendant' || e.kind === 'callQueue');
  M.optionKeyLabel = (k) => (k === 'automatic' ? 'auto' : String(k));
  M.actionLabel = (a) => (own(ACTIONS, a) ? ACTIONS[a] : String(a || ''));
  const ACTIONS = ({ transfer: 'Transfer', operator: 'Operator', disconnect: 'Disconnect', announcement: 'Announcement', forward: 'Forward', voicemail: 'Voicemail', busy: 'Busy', queue: 'Stay in queue' });
  M.generated = () => {
    const t = M.tenant && M.tenant.generatedAt;
    if (!t) return '';
    const d = new Date(t);
    return isNaN(d) ? String(t) : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  };
  /** Text label for an edge, used in lists. */
  M.edgeText = (ed) => {
    const via = ed.via || {};
    const flow = ((ent(ed.from) || {}).flows || []).find((f) => f.key === via.flow);
    switch (ed.kind) {
      case 'route': return 'option ' + M.optionKeyLabel(via.key) + (flow ? ' · ' + flowShort(flow) : '');
      case 'exception': return (via.exception || 'exception') + ' exception';
      case 'fronts': return 'fronts';
      case 'dials': return 'dials';
      case 'agent': return 'agent';
      case 'operator': return 'operator';
      case 'callerId': return 'caller ID';
      default: return ed.kind || '';
    }
  };
})();
