/* Trace engine: walks the voice flow model (docs/model.md) one decision at a time.
   Pure JS, no DOM, no dependencies. Exposes VMTrace (or module.exports under Node). */
(function (root) {
  'use strict';

  const MAX_STEPS = 60;
  const CAP = { cap: true };
  const KIND_LABEL = {
    resourceAccount: 'resource account', autoAttendant: 'auto attendant', callQueue: 'call queue',
    user: 'user', group: 'group', external: 'external number', number: 'number'
  };

  function clone(x) { return JSON.parse(JSON.stringify(x)); }
  function ent(model, id) {
    // Own keys only: ids come from URL hashes, so "__proto__"/"constructor" must not resolve.
    if (!model || !model.entities || id == null) return null;
    return Object.prototype.hasOwnProperty.call(model.entities, id) ? model.entities[id] : null;
  }
  function nameOf(model, id) { const e = ent(model, id); return e ? (e.name || e.number || id) : String(id); }
  function findEdge(model, pred) { return (model.edges || []).find(pred) || null; }

  // ---- time handling -------------------------------------------------------

  function toMinutes(t) {
    const m = /^(?:(\d+)\.)?(\d+):(\d+)(?::(\d+))?$/.exec(String(t).trim());
    if (!m) return NaN;
    return (m[1] ? parseInt(m[1], 10) * 1440 : 0) + parseInt(m[2], 10) * 60 + parseInt(m[3], 10);
  }

  function localParts(tz, when) {
    const opts = {
      hourCycle: 'h23', weekday: 'long', year: 'numeric', month: '2-digit',
      day: '2-digit', hour: '2-digit', minute: '2-digit'
    };
    let fmt = null;
    let tzNote = null;
    if (tz) {
      try { fmt = new Intl.DateTimeFormat('en-US', Object.assign({ timeZone: tz }, opts)); } catch (e) { fmt = null; }
    }
    if (!fmt) {
      fmt = new Intl.DateTimeFormat('en-US', opts);
      tzNote = 'Attendant time zone unknown; using local time';
    }
    const p = {};
    fmt.formatToParts(when).forEach(function (x) { p[x.type] = x.value; });
    const hh = p.hour === '24' ? '00' : p.hour;
    const weekday = String(p.weekday).toLowerCase();
    return {
      iso: p.year + '-' + p.month + '-' + p.day + 'T' + hh + ':' + p.minute,
      minutes: parseInt(hh, 10) * 60 + parseInt(p.minute, 10),
      weekday: weekday,
      display: weekday.charAt(0).toUpperCase() + weekday.slice(1, 3) + ' ' + hh + ':' + p.minute,
      tzNote: tzNote
    };
  }

  function activeFlow(aa, when) {
    when = when || new Date();
    const lp = localParts(aa && aa.timeZoneIana, when);
    const flows = (aa && aa.flows) || [];
    const out = function (flow, reason) {
      return { flow: flow || null, reason: reason, localTime: lp.display, tzNote: lp.tzNote };
    };
    const def = flows.find(function (f) { return f.key === 'default'; }) ||
      flows.find(function (f) { return f.key !== 'afterHours' && String(f.key).indexOf('holiday:') !== 0; }) ||
      flows[0] || null;

    for (let i = 0; i < flows.length; i++) {
      const f = flows[i];
      if (String(f.key).indexOf('holiday:') !== 0 || !f.schedule || !Array.isArray(f.schedule.ranges)) continue;
      for (let j = 0; j < f.schedule.ranges.length; j++) {
        const r = f.schedule.ranges[j];
        const s = String(r.start).slice(0, 16);
        const e = String(r.end).slice(0, 16);
        if (lp.iso >= s && lp.iso < e) return out(f, 'Holiday schedule active');
      }
    }

    const ah = flows.find(function (f) { return f.key === 'afterHours'; });
    if (ah && ah.schedule && ah.schedule.type === 'weekly' && ah.schedule.days) {
      let ranges = [];
      Object.keys(ah.schedule.days).forEach(function (d) {
        if (d.toLowerCase() === lp.weekday) ranges = ranges.concat(ah.schedule.days[d] || []);
      });
      const inside = ranges.some(function (r) {
        const s = toMinutes(r.start);
        let e = toMinutes(r.end);
        if (e === 0) e = 1440; // "00:00" as an end time means midnight at the end of the day
        return lp.minutes >= s && lp.minutes < e;
      });
      return inside ? out(def, 'Inside business hours') : out(ah, 'Outside business hours');
    }
    return out(def, ah ? 'After-hours schedule unreadable; using default flow' : 'No schedules apply');
  }

  // ---- state helpers -------------------------------------------------------

  function push(ctx, kind, entityId, flowKey, text, note) {
    if (ctx.st.steps.length >= MAX_STEPS) throw CAP;
    pushRaw(ctx.st, kind, entityId, flowKey, text, note);
  }
  function pushRaw(st, kind, entityId, flowKey, text, note) {
    st.steps.push({
      id: 's' + st.steps.length, kind: kind, entityId: entityId || null,
      flowKey: flowKey || null, text: text || '', note: note || ''
    });
  }
  function visit(st, entityId, edgeId) {
    if (entityId && st.pathEntityIds.indexOf(entityId) === -1) st.pathEntityIds.push(entityId);
    if (edgeId && st.pathEdgeIds.indexOf(edgeId) === -1) st.pathEdgeIds.push(edgeId);
  }
  function endStep(ctx, entityId, text, note) {
    push(ctx, 'end', entityId, null, text, note);
    ctx.st.pending = null;
    ctx.st.done = true;
  }
  function describeAudio(a) {
    if (!a) return 'Silence';
    if (a.type === 'tts') return a.text || '';
    if (a.type === 'audio') return 'Plays audio file ' + (a.audioFile || '(unnamed)');
    return 'Silence';
  }

  // ---- walking -------------------------------------------------------------

  function enter(ctx, id, edgeId) {
    const model = ctx.model;
    const e = ent(model, id);
    if (!e || e.unresolved) {
      visit(ctx.st, e ? id : null, edgeId);
      endStep(ctx, id, 'Target could not be resolved (id ' + id + ')');
      return;
    }
    if ((e.kind === 'autoAttendant' || e.kind === 'callQueue') && ctx.st.pathEntityIds.indexOf(id) !== -1) {
      visit(ctx.st, null, edgeId);
      push(ctx, 'loop', id, null, 'Loops back to ' + e.name);
      ctx.st.pending = null;
      ctx.st.done = true;
      return;
    }
    visit(ctx.st, id, edgeId);

    switch (e.kind) {
      case 'number': {
        push(ctx, 'dial', id, null, 'Caller dials ' + (e.number || e.name));
        const edge = findEdge(model, function (x) { return x.kind === 'dials' && x.from === id; });
        const raId = edge ? edge.to : e.resourceAccountId;
        if (!raId) { endStep(ctx, id, 'Number is not assigned to any attendant or queue'); return; }
        enter(ctx, raId, edge ? edge.id : null);
        return;
      }
      case 'resourceAccount': {
        push(ctx, 'resourceAccount', id, null, 'Resource account ' + e.name);
        if (!e.configId) { endStep(ctx, id, 'Number is not assigned to any attendant or queue', 'Number is not assigned to any attendant or queue'); return; }
        const edge = findEdge(model, function (x) { return x.kind === 'fronts' && x.from === id && x.to === e.configId; });
        enter(ctx, e.configId, edge ? edge.id : null);
        return;
      }
      case 'autoAttendant': doAA(ctx, e); return;
      case 'callQueue': doCQ(ctx, e); return;
      case 'user': endStep(ctx, id, 'Rings ' + e.name); return;
      case 'external': endStep(ctx, id, 'Forwards to ' + (e.number || e.name)); return;
      case 'group':
        endStep(ctx, id, e.isSharedVoicemail ? 'Goes to shared voicemail: ' + e.name : 'Rings group: ' + e.name);
        return;
      case 'system':
        if (e.systemType === 'disconnect') endStep(ctx, id, 'Call disconnected');
        else if (e.systemType === 'operator') {
          const edgeOp = null;
          enter(ctx, e.targetRef, edgeOp);
        } else endStep(ctx, id, 'Plays an announcement');
        return;
      default:
        endStep(ctx, id, 'Call ends at ' + (e.name || id));
    }
  }

  function optionLabel(model, aa, opt) {
    if (opt.action === 'disconnect') return 'Disconnect';
    if (opt.action === 'announcement') return 'Announcement';
    if (opt.action === 'operator') {
      const sys = ent(model, 'sys:operator:' + aa.id);
      const target = (sys && sys.targetRef) || aa.operatorRef || opt.targetRef;
      return 'Operator: ' + nameOf(model, target);
    }
    const t = ent(model, opt.targetRef);
    const kind = t && KIND_LABEL[t.kind] ? ' (' + KIND_LABEL[t.kind] + ')' : '';
    return nameOf(model, opt.targetRef) + kind;
  }

  function doAA(ctx, aa) {
    const model = ctx.model;
    push(ctx, 'autoAttendant', aa.id, null, 'Auto attendant ' + aa.name);
    const af = activeFlow(aa, ctx.when);
    const flow = af.flow;
    if (!flow) { endStep(ctx, aa.id, 'Call ends: attendant has no call flows'); return; }
    push(ctx, 'flow', aa.id, flow.key, (flow.label || flow.key) + ' (' + af.localTime + ' local)',
      [af.reason, af.tzNote].filter(Boolean).join('. '));
    (flow.greetings || []).forEach(function (g) {
      const text = g.type === 'silence' ? 'Silence' : describeAudio(g);
      push(ctx, 'greeting', aa.id, flow.key, text);
    });

    const options = (flow.menu && flow.menu.options) || [];
    if (!options.length) { endStep(ctx, aa.id, 'Call ends after the greeting (no menu options)'); return; }

    const auto = options.find(function (o) { return String(o.key) === 'automatic'; });
    if (auto) {
      push(ctx, 'key', aa.id, flow.key, 'Automatic (no key press needed)');
      takeOption(ctx, aa, flow.key, auto);
      return;
    }
    const prompts = (flow.menu.prompts || []).map(describeAudio).filter(Boolean).join(' ');
    push(ctx, 'menu', aa.id, flow.key, prompts || 'Caller hears the menu options');
    ctx.st.pending = {
      type: 'menu', entityId: aa.id, flowKey: flow.key,
      options: options.map(function (o) { return { key: String(o.key), label: optionLabel(model, aa, o) }; })
    };
  }

  function takeOption(ctx, aa, flowKey, opt) {
    const model = ctx.model;
    const key = String(opt.key);
    switch (opt.action) {
      case 'transfer': {
        const target = opt.targetRef;
        const edge = findEdge(model, function (e) {
          return e.kind === 'route' && e.from === aa.id && e.to === target && e.via && e.via.flow === flowKey && String(e.via.key) === key;
        }) || findEdge(model, function (e) { return e.kind === 'route' && e.from === aa.id && e.to === target; });
        push(ctx, 'transfer', target, flowKey, 'Transfers to ' + nameOf(model, target));
        enter(ctx, target, edge ? edge.id : null);
        return;
      }
      case 'operator': {
        const sysId = 'sys:operator:' + aa.id;
        const sys = ent(model, sysId);
        const target = (sys && sys.targetRef) || aa.operatorRef || opt.targetRef;
        const edge = findEdge(model, function (e) { return e.kind === 'operator' && e.from === aa.id; });
        push(ctx, 'operator', target, flowKey, 'Transfers to operator: ' + nameOf(model, target));
        if (!target) { endStep(ctx, aa.id, 'Target could not be resolved (id ' + sysId + ')'); return; }
        enter(ctx, target, edge ? edge.id : null);
        return;
      }
      case 'disconnect': {
        if (opt.targetRef && ent(model, opt.targetRef)) {
          const edge = findEdge(model, function (e) {
            return e.kind === 'route' && e.from === aa.id && e.to === opt.targetRef && e.via && e.via.flow === flowKey;
          });
          visit(ctx.st, opt.targetRef, edge ? edge.id : null);
        }
        endStep(ctx, aa.id, 'Call disconnected');
        return;
      }
      case 'announcement': {
        const a = opt.announcement;
        push(ctx, 'announcement', aa.id, flowKey, describeAudio(a));
        endStep(ctx, aa.id, 'Call ends after the announcement',
          'Teams returns the caller to the menu afterwards; the trace stops here.');
        return;
      }
      default:
        endStep(ctx, aa.id, 'Call ends: unsupported menu action' + (opt.action ? ' "' + opt.action + '"' : ''));
    }
  }

  function doCQ(ctx, cq) {
    const agents = (cq.agentIds || []).length;
    const groups = (cq.groupIds || []).length;
    const empty = !agents && !groups && !cq.channel;
    const ex = cq.exceptions || {};
    let text = 'Call queue ' + cq.name + ': ' + (cq.routingMethod || 'unknown routing') + ', ' +
      agents + (agents === 1 ? ' agent' : ' agents');
    if (groups) text += ', ' + groups + (groups === 1 ? ' group' : ' groups');
    if (cq.agentAlertSeconds != null) text += ', alert ' + cq.agentAlertSeconds + ' s';
    push(ctx, 'callQueue', cq.id, null, text, empty ? 'Queue has no agents, groups or channel' : '');

    const branches = [];
    if (!empty) branches.push({ branch: 'answered', label: 'An agent answers' });
    if (ex.overflow) branches.push({ branch: 'overflow', label: 'More than ' + ex.overflow.threshold + ' calls waiting' });
    if (ex.timeout) branches.push({ branch: 'timeout', label: 'Caller waits ' + ex.timeout.threshold + ' s' });
    if (ex.noAgent || empty) branches.push({ branch: 'noAgent', label: 'No agents signed in' });
    ctx.st.pending = { type: 'queue', entityId: cq.id, branches: branches };
  }

  function doBranch(ctx, cq, branch) {
    const model = ctx.model;
    const label = { answered: 'An agent answers', overflow: 'Call overflows', timeout: 'Call times out', noAgent: 'No agents signed in' }[branch];
    push(ctx, 'queueBranch', cq.id, null, label);
    if (branch === 'answered') { endStep(ctx, cq.id, 'Answered by an agent of ' + cq.name); return; }

    const exc = (cq.exceptions || {})[branch];
    if (!exc) {
      endStep(ctx, cq.id, 'Caller keeps waiting in the queue', 'No exception is configured for this case.');
      return;
    }
    const edge = exc.targetRef ? findEdge(model, function (e) {
      return e.kind === 'exception' && e.from === cq.id && e.to === exc.targetRef && e.via && e.via.exception === branch;
    }) : null;

    switch (exc.action) {
      case 'disconnect': endStep(ctx, cq.id, 'Call disconnected'); return;
      case 'busy': endStep(ctx, cq.id, 'Caller hears a busy signal'); return;
      case 'queue': endStep(ctx, cq.id, 'Caller keeps waiting in the queue'); return;
      case 'voicemail': {
        const t = ent(model, exc.targetRef);
        if (!t || t.unresolved) {
          visit(ctx.st, t ? exc.targetRef : null, edge && edge.id);
          endStep(ctx, exc.targetRef, 'Target could not be resolved (id ' + exc.targetRef + ')');
          return;
        }
        visit(ctx.st, exc.targetRef, edge && edge.id);
        endStep(ctx, exc.targetRef, 'Goes to voicemail: ' + t.name);
        return;
      }
      case 'forward':
        push(ctx, 'transfer', exc.targetRef, null, 'Transfers to ' + nameOf(model, exc.targetRef));
        enter(ctx, exc.targetRef, edge ? edge.id : null);
        return;
      default:
        endStep(ctx, cq.id, 'Call ends: unsupported exception action' + (exc.action ? ' "' + exc.action + '"' : ''));
    }
  }

  // ---- public API ----------------------------------------------------------

  function finishCap(st) {
    pushRaw(st, 'error', null, null, 'Trace stopped after ' + MAX_STEPS + ' steps');
    st.pending = null;
    st.done = true;
  }

  function entryPoints(model) {
    const ents = Object.keys((model && model.entities) || {}).map(function (k) { return model.entities[k]; });
    const byLabel = function (a, b) { return a.label.localeCompare(b.label); };
    const numbers = [];
    const aas = [];
    const cqs = [];
    ents.forEach(function (e) {
      if (e.unresolved) return;
      if (e.kind === 'number') {
        const ra = ent(model, e.resourceAccountId);
        const dest = ra && ra.configId ? ent(model, ra.configId) : null;
        const reaches = dest ? dest.name : (ra ? ra.name + ' (unassigned)' : 'unassigned');
        numbers.push({ id: e.id, label: (e.number || e.name) + ' → ' + reaches, kind: 'number' });
      } else if (e.kind === 'autoAttendant') aas.push({ id: e.id, label: e.name, kind: 'autoAttendant' });
      else if (e.kind === 'callQueue') cqs.push({ id: e.id, label: e.name, kind: 'callQueue' });
    });
    return numbers.sort(byLabel).concat(aas.sort(byLabel), cqs.sort(byLabel));
  }

  function start(model, entryId, when) {
    when = when instanceof Date ? when : new Date();
    const st = { steps: [], pending: null, done: false, pathEntityIds: [], pathEdgeIds: [], when: when.toISOString() };
    const ctx = { model: model, st: st, when: when };
    try { enter(ctx, entryId, null); } catch (err) { if (err === CAP) finishCap(st); else throw err; }
    return st;
  }

  function advance(model, state, input) {
    const st = clone(state);
    if (st.done || !st.pending) return st;
    const ctx = { model: model, st: st, when: st.when ? new Date(st.when) : new Date() };
    const p = st.pending;
    try {
      if (p.type === 'menu') {
        const aa = ent(model, p.entityId);
        const flow = aa && (aa.flows || []).find(function (f) { return f.key === p.flowKey; });
        const opt = flow && ((flow.menu && flow.menu.options) || []).find(function (o) { return String(o.key) === String(input); });
        if (!opt) { pushRaw(st, 'error', p.entityId, p.flowKey, 'No option for key ' + input); return st; }
        st.pending = null;
        push(ctx, 'key', aa.id, flow.key, 'Caller presses ' + opt.key);
        takeOption(ctx, aa, flow.key, opt);
      } else if (p.type === 'queue') {
        const ok = p.branches.some(function (b) { return b.branch === input; });
        if (!ok) { pushRaw(st, 'error', p.entityId, null, 'No branch ' + input); return st; }
        st.pending = null;
        doBranch(ctx, ent(model, p.entityId), input);
      }
    } catch (err) { if (err === CAP) finishCap(st); else throw err; }
    return st;
  }

  // ---- wall-clock helpers for the UI's datetime-local input ----------------

  function validZone(tz) {
    if (!tz) return null;
    try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return tz; } catch (e) { return null; }
  }

  /** IANA zone of the attendant an entry point reaches (number → RA → AA), or null. */
  function entryTimeZone(model, entryId) {
    let e = ent(model, entryId);
    for (let hop = 0; e && hop < 4; hop++) {
      if (e.kind === 'autoAttendant') return validZone(e.timeZoneIana);
      if (e.kind === 'number') e = ent(model, e.resourceAccountId);
      else if (e.kind === 'resourceAccount') e = ent(model, e.configId);
      else return null;
    }
    return null;
  }

  /** Date → "YYYY-MM-DDTHH:mm" wall clock in tz (browser local when tz is null/invalid). */
  function dateToWallClock(date, tz) {
    return localParts(validZone(tz), date instanceof Date ? date : new Date(date)).iso;
  }

  /** "YYYY-MM-DDTHH:mm" wall clock in tz → Date (browser local when tz is null/invalid). */
  function wallClockToDate(wallClock, tz) {
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(wallClock || ''));
    if (!m) return new Date(NaN);
    const y = +m[1], mo = +m[2] - 1, d = +m[3], h = +m[4], mi = +m[5];
    const zone = validZone(tz);
    if (!zone) return new Date(y, mo, d, h, mi);
    const asUtc = Date.UTC(y, mo, d, h, mi);
    // Offset of the zone at instant t, in ms: (wall clock in zone, read as UTC) − t.
    const offsetAt = function (t) {
      const p = localParts(zone, new Date(t)).iso;
      const q = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(p);
      return Date.UTC(+q[1], +q[2] - 1, +q[3], +q[4], +q[5]) - t;
    };
    // Two passes settle DST edges (the second offset is taken at the corrected instant).
    let t = asUtc - offsetAt(asUtc);
    t = asUtc - offsetAt(t);
    return new Date(t);
  }

  const api = {
    entryPoints: entryPoints, start: start, advance: advance, activeFlow: activeFlow,
    entryTimeZone: entryTimeZone, wallClockToDate: wallClockToDate, dateToWallClock: dateToWallClock
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.VMTrace = api;
})(typeof self !== 'undefined' ? self : this);
