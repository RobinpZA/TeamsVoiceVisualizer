/* Voice map: graph construction (visible set, compound nodes) and ELK layout. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M;
  const L = (VM.layout = {});

  /* ---------- text measurement with the real fonts ---------- */
  let msvg = null;
  const wcache = new Map();
  function tw(text, cls) {
    const key = cls + '\u0000' + text;
    let w = wcache.get(key);
    if (w != null) return w;
    if (!msvg) { msvg = U.s('svg', { class: 'measure', 'aria-hidden': 'true' }); document.body.appendChild(msvg); }
    const t = U.s('text', { class: cls });
    t.textContent = text;
    msvg.appendChild(t);
    w = t.getComputedTextLength() + 1;
    msvg.removeChild(t);
    wcache.set(key, w);
    return w;
  }
  L.textWidth = tw;
  L.clearMeasureCache = () => wcache.clear();

  const PAD = 14, CHEV = 34, ROW_H = 22, MENU_HEAD = 28;

  /* ---------- node view-models ---------- */
  function entityVM(e) {
    const mono = e.kind === 'number' || e.kind === 'external';
    const full = String(e.kind === 'number' ? (e.number || e.name) : (e.name || e.id));
    const nameText = U.truncate(full, 36);
    const kindText = M.kindLabel(e);
    const sum = M.summary(e);
    const expandable = M.isExpandable(e);
    const shape = e.kind === 'number' ? 'pill' : e.kind === 'resourceAccount' ? 'ra' : 'box';
    const pad = shape === 'pill' ? 18 : PAD;
    let w = Math.max(tw(kindText, 't-kind'), tw(nameText, mono ? 't-name t-mono' : 't-name'), sum ? tw(sum, 't-sum') : 0) + 2 * pad + (expandable ? CHEV - 8 : 0);
    w = Math.ceil(Math.max(w, shape === 'pill' ? 120 : 132));
    const h = shape === 'ra' ? 42 : shape === 'pill' ? 46 : (sum ? 66 : 50);
    return {
      id: e.id, entityId: e.id, role: 'entity', shape, kindText, nameText, fullName: full, sumText: sum, mono,
      expandable, expanded: false, unresolved: !!e.unresolved, isRA: e.kind === 'resourceAccount', w, h, x: 0, y: 0,
    };
  }
  function innerVM(id, entityId, role, kindText, text, extra) {
    const t = U.truncate(text, 44);
    const w = Math.ceil(Math.max(tw(kindText, 't-kind'), tw(t, 't-row')) + 2 * PAD);
    return Object.assign({ id, entityId, role, shape: 'box', kindText, nameText: t, fullName: text, sumText: '', inner: true, w: Math.max(w, 110), h: 46, x: 0, y: 0 }, extra || {});
  }

  /* ---------- build the ELK graph for the current expansion set ---------- */
  L.build = function (expanded) {
    const info = new Map();           // node id -> view-model
    const portNode = new Map();       // port id -> node id
    const optionPort = new Map();     // aaId|flowKey|optKey -> port id
    const flowTail = new Map();       // aaId|flowKey -> node id
    const visible = new Set();
    const children = [];
    const elkEdges = [];
    const edgeInfo = new Map();
    let ei = 0;
    function addInternal(from, to, dashed) {
      const id = 'I' + (ei++);
      elkEdges.push({ id, sources: [from], targets: [to] });
      edgeInfo.set(id, { key: id + ':' + from + '>' + to, ids: [], kind: 'internal', dashed: !!dashed, internal: true, srcNode: from, tgtNode: to, from: null, to: null, label: '' });
    }

    M.list.forEach((e) => { if (!M.isHiddenAt(e.id, expanded)) visible.add(e.id); });

    function aaCompound(e, vm) {
      const kids = [];
      (e.flows || []).forEach((fl) => {
        const pid = e.id + '#f:' + fl.key;
        const headText = U.truncate(M.flowHeader(fl), 60);
        const head = { id: pid, entityId: e.id, flowKey: fl.key, role: 'flow', shape: 'box', kindText: '', nameText: headText, fullName: M.flowHeader(fl), sumText: '', inner: true, w: Math.ceil(tw(headText, 't-flow') + 24), h: 30, x: 0, y: 0 };
        info.set(head.id, head);
        kids.push({ id: head.id, width: head.w, height: head.h });
        const g = innerVM(pid + ':g', e.id, 'greeting', 'GREETING', M.greetingLine((fl.greetings || [])[0]), { flowKey: fl.key });
        info.set(g.id, g);
        kids.push({ id: g.id, width: g.w, height: g.h });
        addInternal(head.id, g.id);
        let tail = g.id;
        const opts = (fl.menu && fl.menu.options) || [];
        if (opts.length) {
          const rows = opts.map((o, i) => {
            let text;
            if (o.action === 'operator') text = 'Operator';
            else if (o.action === 'disconnect') text = 'Disconnect';
            else if (o.action === 'announcement') text = 'Announcement' + (o.announcement && o.announcement.text ? ': ' + o.announcement.text : '');
            else text = o.targetRef ? M.name(o.targetRef) : M.actionLabel(o.action);
            return { key: M.optionKeyLabel(o.key), text: U.truncate(text, 28), y: MENU_HEAD + i * ROW_H + ROW_H / 2 };
          });
          const w = Math.ceil(Math.max(tw('MENU', 't-kind'), ...rows.map((r) => 34 + tw(r.text, 't-row'))) + 2 * PAD);
          const m = { id: pid + ':m', entityId: e.id, flowKey: fl.key, role: 'menu', shape: 'box', kindText: 'MENU', nameText: '', fullName: 'Menu', sumText: '', inner: true, rows, w: Math.max(w, 120), h: MENU_HEAD + opts.length * ROW_H + 6, x: 0, y: 0 };
          info.set(m.id, m);
          const ports = rows.map((r, i) => {
            const portId = m.id + '#p' + i;
            portNode.set(portId, m.id);
            optionPort.set(e.id + '|' + fl.key + '|' + opts[i].key, portId);
            return { id: portId, x: m.w, y: r.y, width: 0, height: 0, layoutOptions: { 'elk.port.side': 'EAST' } };
          });
          kids.push({ id: m.id, width: m.w, height: m.h, ports, layoutOptions: { 'elk.portConstraints': 'FIXED_POS' } });
          addInternal(g.id, m.id);
          tail = m.id;
        }
        flowTail.set(e.id + '|' + fl.key, tail);
      });
      if (!kids.length) {
        const g = innerVM(e.id + '#empty', e.id, 'greeting', 'FLOWS', 'No flows', {});
        info.set(g.id, g); kids.push({ id: g.id, width: g.w, height: g.h });
      }
      return kids;
    }

    function cqCompound(e) {
      const kids = [];
      const add = (vm) => { info.set(vm.id, vm); kids.push({ id: vm.id, width: vm.w, height: vm.h }); return vm.id; };
      const gr = e.greeting || {};
      const grText = gr.type === 'tts' ? (String(gr.text || '').split(/\r?\n/).find((l) => l.trim()) || 'Empty text') : gr.type === 'audio' ? 'Audio: ' + (gr.audioFile || 'file') : 'None';
      const mo = e.musicOnHold || {};
      const flags = [e.conferenceMode ? 'conference' : null, e.presenceBasedRouting ? 'presence' : null, e.allowOptOut ? 'opt-out' : null].filter(Boolean).join(' · ') || 'no flags';
      const routeText = M.routing(e.routingMethod) + ' · alert ' + (e.agentAlertSeconds != null ? e.agentAlertSeconds : '?') + ' s';
      const nA = (e.agentIds || []).length, nG = (e.groupIds || []).length;
      const agText = nA + (nA === 1 ? ' agent' : ' agents') + (nG ? ' · ' + nG + (nG === 1 ? ' group' : ' groups') : '') + (e.channel ? ' · channel' : '');
      const g = add(innerVM(e.id + '#g', e.id, 'cqgreeting', 'GREETING', grText));
      const mu = add(innerVM(e.id + '#mu', e.id, 'cqmusic', 'HOLD MUSIC', mo.type === 'custom' ? 'Audio: ' + (mo.audioFile || 'file') : 'Default'));
      const rv = innerVM(e.id + '#r', e.id, 'cqrouting', 'ROUTING', routeText, { sumText: flags });
      rv.w = Math.max(rv.w, Math.ceil(tw(flags, 't-sum') + 2 * PAD)); rv.h = 64;
      const r = add(rv);
      const ag = add(innerVM(e.id + '#ag', e.id, 'cqagents', 'AGENTS', agText));
      addInternal(g, mu); addInternal(mu, r); addInternal(r, ag);
      const ex = e.exceptions || {};
      [['overflow', 'OVERFLOW', (x) => '> ' + x.threshold + ' calls'], ['timeout', 'TIMEOUT', (x) => '> ' + x.threshold + ' s'], ['noAgent', 'NO AGENTS', () => 'when none signed in']].forEach((spec) => {
        const x = ex[spec[0]];
        if (!x) return;
        const id = add(innerVM(e.id + '#ex:' + spec[0], e.id, 'cqex', spec[1], spec[2](x) + ' · ' + M.actionLabel(x.action), { exception: spec[0] }));
        addInternal(r, id, true);
      });
      return kids;
    }

    M.list.forEach((e) => {
      if (!visible.has(e.id)) return;
      const vm = entityVM(e);
      info.set(e.id, vm);
      if (M.isExpandable(e) && expanded.has(e.id)) {
        vm.role = 'group'; vm.expanded = true;
        const kids = e.kind === 'autoAttendant' ? aaCompound(e, vm) : cqCompound(e);
        children.push({
          id: e.id, children: kids,
          layoutOptions: { 'elk.padding': '[top=56,left=16,bottom=16,right=16]', 'elk.spacing.nodeNode': '14', 'elk.layered.spacing.nodeNodeBetweenLayers': '40' },
        });
      } else {
        const n = { id: e.id, width: vm.w, height: vm.h };
        if (e.kind === 'number') n.layoutOptions = { 'elk.layered.layering.layerConstraint': 'FIRST' };
        children.push(n);
      }
    });

    /* edges at entity level, re-pointed at ports/inner nodes of expanded entities */
    function endpoint(entityId, ed, asSource) {
      if (!expanded.has(entityId) || !asSource) return entityId;
      const e = M.get(entityId);
      if (e.kind === 'autoAttendant' && ed.kind === 'route' && ed.via) {
        const p = optionPort.get(entityId + '|' + ed.via.flow + '|' + ed.via.key);
        if (p) return p;
        const t = flowTail.get(entityId + '|' + ed.via.flow);
        if (t) return t;
      }
      if (e.kind === 'callQueue') {
        if (ed.kind === 'agent') return entityId + '#ag';
        if (ed.kind === 'exception' && ed.via && info.has(entityId + '#ex:' + ed.via.exception)) return entityId + '#ex:' + ed.via.exception;
      }
      return entityId;
    }
    const allEdges = M.edges.slice();
    M.list.forEach((e) => {
      if (e.kind === 'system' && e.systemType === 'operator' && e.targetRef && M.get(e.targetRef) && !(M.out.get(e.id) || []).length) {
        allEdges.push({ id: 'syn:' + e.id, from: e.id, to: e.targetRef, kind: 'operator', synthetic: true });
      }
    });
    const merged = new Map();
    allEdges.forEach((ed) => {
      if (!visible.has(ed.from) || !visible.has(ed.to) || ed.from === ed.to) return;
      if (ed.kind === 'agent' && !expanded.has(ed.from)) return;
      const src = endpoint(ed.from, ed, true), tgt = endpoint(ed.to, ed, false);
      const srcNode = portNode.get(src) || src;
      const detail = src !== ed.from;             // sourced from a port / inner node: keep separate
      const key = detail ? src + '>' + tgt + '|' + ed.kind + '|' + ((ed.via && (ed.via.key || ed.via.exception)) || '') : src + '>' + tgt + '|' + ed.kind;
      let m = merged.get(key);
      if (!m) {
        m = { key, ids: [], src, tgt, srcNode, tgtNode: tgt, from: ed.from, to: ed.to, kind: ed.kind, dashed: ed.kind === 'exception', labels: [], detail, internal: false };
        merged.set(key, m);
      }
      m.ids.push(ed.id);
      if (!detail) {
        let lab = '';
        if (ed.kind === 'route' && ed.via) {
          const fl = ((M.get(ed.from) || {}).flows || []).find((f) => f.key === ed.via.flow);
          lab = M.optionKeyLabel(ed.via.key) + (fl ? ' · ' + M.flowShort(fl) : '');
        } else if (ed.kind === 'exception' && ed.via) lab = ed.via.exception;
        if (lab && m.labels.indexOf(lab) < 0) m.labels.push(lab);
      }
    });
    merged.forEach((m) => {
      let label = '';
      if (m.labels.length) label = U.truncate(m.labels.slice(0, 2).join(', '), 30) + (m.labels.length > 2 ? ' +' + (m.labels.length - 2) : '');
      m.label = label;
      const id = 'E' + (ei++);
      const edge = { id, sources: [m.src], targets: [m.tgt] };
      if (label) {
        m.labelW = Math.ceil(tw(label, 't-elabel')) + 4; m.labelH = 14;
        edge.labels = [{ text: label, width: m.labelW, height: m.labelH, layoutOptions: { 'elk.edgeLabels.inline': 'false' } }];
      }
      elkEdges.push(edge);
      edgeInfo.set(id, m);
    });

    const graph = {
      id: 'root',
      layoutOptions: {
        'elk.algorithm': 'layered',
        'elk.direction': 'RIGHT',
        'elk.hierarchyHandling': 'INCLUDE_CHILDREN',
        'elk.edgeRouting': 'ORTHOGONAL',
        'elk.layered.considerModelOrder.strategy': 'NODES_AND_EDGES',
        'elk.spacing.nodeNode': '28',
        'elk.layered.spacing.nodeNodeBetweenLayers': '84',
        'elk.spacing.edgeNode': '20',
        'elk.spacing.edgeEdge': '12',
        'elk.layered.spacing.edgeNodeBetweenLayers': '20',
        'elk.layered.spacing.edgeEdgeBetweenLayers': '12',
        'elk.spacing.edgeLabel': '6',
        'elk.layered.mergeEdges': 'false',
        'elk.layered.cycleBreaking.strategy': 'DEPTH_FIRST',
        'elk.padding': '[top=40,left=40,bottom=40,right=40]',
        'elk.json.shapeCoords': 'ROOT',
        'elk.json.edgeCoords': 'ROOT',
      },
      children, edges: elkEdges,
    };
    return { graph, info, edgeInfo, visible };
  };

  /* ---------- run ---------- */
  let elk = null;
  L.run = async function (expanded) {
    const b = L.build(expanded);
    if (!elk) elk = new ELK();
    const res = await elk.layout(b.graph);
    return collect(b, res);
  };

  function collect(b, res) {
    const nodes = [];
    (function walk(list) {
      (list || []).forEach((c) => {
        const vm = b.info.get(c.id);
        if (vm) {
          vm.x = c.x || 0; vm.y = c.y || 0;
          if (vm.role === 'group') { vm.w = c.width; vm.h = c.height; }
          nodes.push(vm);
        }
        if (c.children) walk(c.children);
      });
    })(res.children);

    const edges = [];
    (function walkEdges(container) {
      (container.edges || []).forEach((ed) => {
        const m = b.edgeInfo.get(ed.id);
        if (!m) return;
        const pts = [];
        const sec = (ed.sections || [])[0];
        if (sec) {
          pts.push(sec.startPoint);
          (sec.bendPoints || []).forEach((p) => pts.push(p));
          pts.push(sec.endPoint);
        } else {
          const a = b.info.get(m.srcNode), z = b.info.get(m.tgtNode);
          if (a && z) { pts.push({ x: a.x + a.w, y: a.y + a.h / 2 }, { x: z.x, y: z.y + z.h / 2 }); }
        }
        const lab = (ed.labels || [])[0];
        edges.push(Object.assign({}, m, { points: pts, labelBox: lab && lab.x != null ? { x: lab.x, y: lab.y, w: lab.width, h: lab.height } : null }));
      });
      (container.children || []).forEach(walkEdges);
    })(res);

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes.forEach((n) => { minX = Math.min(minX, n.x); minY = Math.min(minY, n.y); maxX = Math.max(maxX, n.x + n.w); maxY = Math.max(maxY, n.y + n.h); });
    edges.forEach((e) => e.points.forEach((p) => { minX = Math.min(minX, p.x); minY = Math.min(minY, p.y); maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y); }));
    if (!isFinite(minX)) { minX = minY = 0; maxX = maxY = 100; }
    const pad = 32;
    return { nodes, edges, visible: b.visible, bounds: { x: minX - pad, y: minY - pad, w: maxX - minX + 2 * pad, h: maxY - minY + 2 * pad } };
  }
})();
