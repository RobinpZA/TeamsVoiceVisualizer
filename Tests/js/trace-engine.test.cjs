'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const T = require(path.join(__dirname, '..', '..', 'Assets', 'portal', 'js', 'trace-engine.js'));

const DAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
function weekly() {
  const days = {};
  DAYS.forEach((d) => { days[d] = [{ start: '08:00', end: '17:00' }]; });
  return { type: 'weekly', days };
}

function buildModel(overrides) {
  const E = {};
  const add = (e) => { E[e.id] = e; };
  add({ id: 'tel:+27115550100', kind: 'number', name: 'tel:+27115550100', number: '+27 11 555 0100', resourceAccountId: 'ra-main' });
  add({ id: 'ra-main', kind: 'resourceAccount', name: 'Main RA', configId: 'aa-main', appType: 'autoAttendant', phoneNumbers: ['+27115550100'] });
  add({ id: 'ra-sales', kind: 'resourceAccount', name: 'Sales', configId: 'cq-sales', appType: 'callQueue', phoneNumbers: [] });
  add({
    id: 'aa-main', kind: 'autoAttendant', name: 'Main', timeZoneIana: 'Africa/Johannesburg', operatorRef: 'u-jane',
    flows: [
      {
        key: 'default', label: 'Business hours', schedule: null,
        greetings: [{ type: 'tts', text: 'Welcome to Contoso.' }],
        menu: {
          prompts: [{ type: 'tts', text: 'Press 1 for sales.' }],
          options: [
            { key: '1', action: 'transfer', targetRef: 'ra-sales' },
            { key: '0', action: 'operator', targetRef: 'sys:operator:aa-main' },
            { key: '9', action: 'transfer', targetRef: 'tel:+27215550199' }
          ]
        }
      },
      {
        key: 'afterHours', label: 'After hours', schedule: weekly(),
        greetings: [{ type: 'audio', audioFile: 'closed.wav' }],
        menu: { prompts: [], options: [{ key: 'automatic', action: 'transfer', targetRef: 'g-fin' }] }
      },
      {
        key: 'holiday:xmas', label: 'Holiday: Christmas',
        schedule: { type: 'fixed', ranges: [{ start: '2026-12-25T00:00:00', end: '2026-12-26T00:00:00' }] },
        greetings: [{ type: 'silence' }],
        menu: { prompts: [], options: [{ key: 'automatic', action: 'disconnect', targetRef: 'sys:disconnect' }] }
      }
    ]
  });
  add({
    id: 'cq-sales', kind: 'callQueue', name: 'Sales Queue', routingMethod: 'RoundRobin', agentAlertSeconds: 30,
    agentIds: ['u-jane'], groupIds: [], channel: null,
    exceptions: {
      overflow: { threshold: 50, action: 'forward', targetRef: 'ra-main' },
      timeout: { threshold: 1200, action: 'voicemail', targetRef: 'g-vm' },
      noAgent: { action: 'queue', targetRef: null }
    }
  });
  add({ id: 'u-jane', kind: 'user', name: 'Jane Doe', upn: 'jane@contoso.com' });
  add({ id: 'tel:+27215550199', kind: 'external', name: '+27215550199', number: '+27215550199' });
  add({ id: 'g-fin', kind: 'group', name: 'Finance', isSharedVoicemail: true });
  add({ id: 'g-vm', kind: 'group', name: 'Sales VM', isSharedVoicemail: true });
  add({ id: 'sys:disconnect', kind: 'system', name: 'Disconnect', systemType: 'disconnect' });
  add({ id: 'sys:operator:aa-main', kind: 'system', name: 'Operator', systemType: 'operator', targetRef: 'u-jane' });

  const edges = [
    { id: 'e0', from: 'tel:+27115550100', to: 'ra-main', kind: 'dials' },
    { id: 'e1', from: 'ra-main', to: 'aa-main', kind: 'fronts' },
    { id: 'e2', from: 'aa-main', to: 'ra-sales', kind: 'route', via: { flow: 'default', key: '1' } },
    { id: 'e3', from: 'ra-sales', to: 'cq-sales', kind: 'fronts' },
    { id: 'e4', from: 'aa-main', to: 'sys:operator:aa-main', kind: 'operator' },
    { id: 'e5', from: 'aa-main', to: 'tel:+27215550199', kind: 'route', via: { flow: 'default', key: '9' } },
    { id: 'e6', from: 'aa-main', to: 'g-fin', kind: 'route', via: { flow: 'afterHours', key: 'automatic' } },
    { id: 'e7', from: 'aa-main', to: 'sys:disconnect', kind: 'route', via: { flow: 'holiday:xmas', key: 'automatic' } },
    { id: 'e8', from: 'cq-sales', to: 'ra-main', kind: 'exception', via: { exception: 'overflow' } },
    { id: 'e9', from: 'cq-sales', to: 'g-vm', kind: 'exception', via: { exception: 'timeout' } }
  ];
  const model = { schemaVersion: 1, tenant: { name: 'Contoso' }, entities: E, edges, findings: [] };
  if (overrides) overrides(model);
  return model;
}

function deepFreeze(o) {
  Object.values(o).forEach((v) => { if (v && typeof v === 'object') deepFreeze(v); });
  return Object.freeze(o);
}

const NUM = 'tel:+27115550100';
// 2026-11-09 is a Monday, 2026-11-14 a Saturday, 2026-12-25 a Friday. SAST = UTC+2.
const MON_10 = new Date(Date.UTC(2026, 10, 9, 8, 0));
const SAT_1030 = new Date(Date.UTC(2026, 10, 14, 8, 30));
const XMAS_NOON = new Date(Date.UTC(2026, 11, 25, 10, 0));
const flowStep = (s) => s.steps.find((x) => x.kind === 'flow');

test('weekday 10:00 SAST picks the default flow', () => {
  const s = T.start(buildModel(), NUM, MON_10);
  assert.equal(flowStep(s).flowKey, 'default');
  assert.match(flowStep(s).text, /^Business hours \(Mon 10:00 local\)$/);
});

test('Saturday picks afterHours and follows the automatic option', () => {
  const s = T.start(buildModel(), NUM, SAT_1030);
  assert.equal(flowStep(s).flowKey, 'afterHours');
  assert.equal(flowStep(s).text, 'After hours (Sat 10:30 local)');
  assert.ok(s.steps.some((x) => x.kind === 'greeting' && x.text === 'Plays audio file closed.wav'));
  assert.equal(s.done, true);
  assert.equal(s.pending, null);
  const last = s.steps[s.steps.length - 1];
  assert.equal(last.kind, 'end');
  assert.equal(last.text, 'Goes to shared voicemail: Finance');
});

test('holiday wins over a weekday', () => {
  const s = T.start(buildModel(), NUM, XMAS_NOON);
  assert.equal(flowStep(s).flowKey, 'holiday:xmas');
  assert.ok(s.steps.some((x) => x.kind === 'greeting' && x.text === 'Silence'));
  assert.equal(s.steps[s.steps.length - 1].text, 'Call disconnected');
  assert.equal(s.done, true);
});

test('holiday end is exclusive', () => {
  const aa = buildModel().entities['aa-main'];
  const r = T.activeFlow(aa, new Date(Date.UTC(2026, 11, 25, 22, 0))); // 00:00 on the 26th (Sat) SAST
  assert.equal(r.flow.key, 'afterHours');
});

test('time zone conversion: 06:30Z Monday is 08:30 in Johannesburg', () => {
  const aa = buildModel().entities['aa-main'];
  const r = T.activeFlow(aa, new Date(Date.UTC(2026, 10, 9, 6, 30)));
  assert.equal(r.flow.key, 'default');
  assert.equal(r.localTime, 'Mon 08:30');
  assert.equal(r.tzNote, null);
  assert.equal(T.activeFlow(aa, new Date(Date.UTC(2026, 10, 9, 5, 30))).flow.key, 'afterHours'); // 07:30
});

test('business hours end is exclusive at 17:00', () => {
  const aa = buildModel().entities['aa-main'];
  assert.equal(T.activeFlow(aa, new Date(Date.UTC(2026, 10, 9, 14, 59))).flow.key, 'default');
  assert.equal(T.activeFlow(aa, new Date(Date.UTC(2026, 10, 9, 15, 0))).flow.key, 'afterHours');
});

test('end 24:00 and 1.00:00:00 mean end of day', () => {
  const m = buildModel();
  const aa = m.entities['aa-main'];
  aa.flows[1].schedule.days.monday = [{ start: '08:00:00', end: '24:00' }];
  aa.flows[1].schedule.days.tuesday = [{ start: '08:00', end: '1.00:00:00' }];
  assert.equal(T.activeFlow(aa, new Date(Date.UTC(2026, 10, 9, 21, 59))).flow.key, 'default'); // Mon 23:59
  assert.equal(T.activeFlow(aa, new Date(Date.UTC(2026, 10, 10, 21, 59))).flow.key, 'default'); // Tue 23:59
});

test('null timeZoneIana uses local time and sets tzNote', () => {
  const aa = buildModel().entities['aa-main'];
  aa.timeZoneIana = null;
  const mon = T.activeFlow(aa, new Date(2026, 10, 9, 10, 0)); // local Monday 10:00
  assert.equal(mon.flow.key, 'default');
  assert.equal(mon.tzNote, 'Attendant time zone unknown; using local time');
  assert.equal(mon.localTime, 'Mon 10:00');
  assert.equal(T.activeFlow(aa, new Date(2026, 10, 14, 10, 0)).flow.key, 'afterHours');
});

test('menu goes pending, key 1 reaches the queue pending with all branches', () => {
  const m = buildModel();
  const s0 = T.start(m, NUM, MON_10);
  assert.equal(s0.done, false);
  assert.equal(s0.pending.type, 'menu');
  assert.deepEqual(s0.pending.options.map((o) => o.key), ['1', '0', '9']);
  assert.deepEqual(s0.pending.options.map((o) => o.label), ['Sales (resource account)', 'Operator: Jane Doe', '+27215550199 (external number)']);
  const s1 = T.advance(m, s0, '1');
  assert.equal(s1.pending.type, 'queue');
  assert.deepEqual(s1.pending.branches.map((b) => b.branch), ['answered', 'overflow', 'timeout', 'noAgent']);
  assert.ok(s1.steps.some((x) => x.kind === 'transfer'));
  assert.ok(s1.steps.some((x) => x.kind === 'callQueue'));
  assert.deepEqual(s1.steps.map((x) => x.id), s1.steps.map((_, i) => 's' + i));
});

test('answered ends the call', () => {
  const m = buildModel();
  const s = T.advance(m, T.advance(m, T.start(m, NUM, MON_10), '1'), 'answered');
  assert.equal(s.done, true);
  assert.equal(s.steps[s.steps.length - 1].text, 'Answered by an agent of Sales Queue');
});

test('overflow forward back to the main RA produces a loop step', () => {
  const m = buildModel();
  const s = T.advance(m, T.advance(m, T.start(m, NUM, MON_10), '1'), 'overflow');
  const last = s.steps[s.steps.length - 1];
  assert.equal(last.kind, 'loop');
  assert.equal(last.text, 'Loops back to Main');
  assert.equal(s.done, true);
  assert.equal(s.pending, null);
  assert.ok(s.pathEdgeIds.includes('e8'));
});

test('timeout goes to voicemail', () => {
  const m = buildModel();
  const s = T.advance(m, T.advance(m, T.start(m, NUM, MON_10), '1'), 'timeout');
  const last = s.steps[s.steps.length - 1];
  assert.equal(last.kind, 'end');
  assert.equal(last.text, 'Goes to voicemail: Sales VM');
  assert.ok(s.pathEntityIds.includes('g-vm'));
  assert.ok(s.pathEdgeIds.includes('e9'));
});

test('operator and external keys end at the target', () => {
  const m = buildModel();
  const s0 = T.start(m, NUM, MON_10);
  const op = T.advance(m, s0, '0');
  assert.equal(op.steps[op.steps.length - 1].text, 'Rings Jane Doe');
  assert.ok(op.pathEdgeIds.includes('e4'));
  const ex = T.advance(m, s0, '9');
  assert.equal(ex.steps[ex.steps.length - 1].text, 'Forwards to +27215550199');
  assert.ok(ex.pathEdgeIds.includes('e5'));
});

test('invalid key adds an error step and keeps pending', () => {
  const m = buildModel();
  const s0 = T.start(m, NUM, MON_10);
  const s1 = T.advance(m, s0, '7');
  const last = s1.steps[s1.steps.length - 1];
  assert.equal(last.kind, 'error');
  assert.equal(last.text, 'No option for key 7');
  assert.deepEqual(s1.pending, s0.pending);
  assert.equal(s1.done, false);
});

test('resource account without configId ends with a note', () => {
  const m = buildModel((mm) => { mm.entities['ra-main'].configId = null; });
  const s = T.start(m, NUM, MON_10);
  const last = s.steps[s.steps.length - 1];
  assert.equal(last.kind, 'end');
  assert.equal(last.note, 'Number is not assigned to any attendant or queue');
  assert.equal(s.done, true);
});

test('empty menu ends after the greeting', () => {
  const m = buildModel((mm) => { mm.entities['aa-main'].flows[0].menu.options = []; });
  const s = T.start(m, NUM, MON_10);
  assert.equal(s.steps[s.steps.length - 1].text, 'Call ends after the greeting (no menu options)');
  assert.equal(s.done, true);
});

test('queue with no agents offers only noAgent plus configured exceptions', () => {
  const m = buildModel((mm) => { mm.entities['cq-sales'].agentIds = []; });
  const s = T.advance(m, T.start(m, NUM, MON_10), '1');
  assert.deepEqual(s.pending.branches.map((b) => b.branch), ['overflow', 'timeout', 'noAgent']);
  const cqStep = s.steps.find((x) => x.kind === 'callQueue');
  assert.match(cqStep.note, /no agents/i);
  const end = T.advance(m, s, 'noAgent');
  assert.equal(end.steps[end.steps.length - 1].text, 'Caller keeps waiting in the queue');
});

test('unresolved target ends with an explanatory note', () => {
  const m = buildModel((mm) => { mm.entities['u-jane'].unresolved = true; });
  const s = T.advance(m, T.start(m, NUM, MON_10), '0');
  assert.equal(s.steps[s.steps.length - 1].text, 'Target could not be resolved (id u-jane)');
  const s2 = T.start(m, 'nope', MON_10);
  assert.equal(s2.steps[0].text, 'Target could not be resolved (id nope)');
  assert.equal(s2.done, true);
});

test('announcement option plays the text then ends', () => {
  const m = buildModel((mm) => {
    mm.entities['aa-main'].flows[0].menu.options.push({ key: '5', action: 'announcement', announcement: { type: 'tts', text: 'We are closed.' } });
  });
  const s0 = T.start(m, NUM, MON_10);
  assert.ok(s0.pending.options.some((o) => o.key === '5' && o.label === 'Announcement'));
  const s = T.advance(m, s0, '5');
  assert.ok(s.steps.some((x) => x.kind === 'announcement' && x.text === 'We are closed.'));
  assert.equal(s.steps[s.steps.length - 1].text, 'Call ends after the announcement');
  assert.equal(s.done, true);
});

test('step cap stops runaway traces', () => {
  const N = 20;
  const E = {};
  const edges = [];
  for (let i = 0; i < N; i++) {
    E['ra' + i] = { id: 'ra' + i, kind: 'resourceAccount', name: 'RA' + i, configId: 'aa' + i };
    E['aa' + i] = {
      id: 'aa' + i, kind: 'autoAttendant', name: 'AA' + i, timeZoneIana: 'UTC',
      flows: [{
        key: 'default', label: 'Business hours', schedule: null, greetings: [],
        menu: { prompts: [], options: [{ key: 'automatic', action: 'transfer', targetRef: i + 1 < N ? 'ra' + (i + 1) : 'sys:disconnect' }] }
      }]
    };
  }
  E['sys:disconnect'] = { id: 'sys:disconnect', kind: 'system', name: 'Disconnect', systemType: 'disconnect' };
  const s = T.start({ entities: E, edges }, 'ra0', MON_10);
  const last = s.steps[s.steps.length - 1];
  assert.equal(last.kind, 'error');
  assert.equal(last.text, 'Trace stopped after 60 steps');
  assert.ok(s.steps.length <= 61);
  assert.equal(s.done, true);
  assert.equal(s.pending, null);
});

test('advance does not mutate the previous state or the model', () => {
  const m = buildModel();
  const s0 = deepFreeze(T.start(m, NUM, MON_10));
  const frozenModel = deepFreeze(buildModel());
  const s1 = T.advance(frozenModel, s0, '1');
  const s2 = T.advance(frozenModel, s1, 'timeout');
  assert.notEqual(s1, s0);
  assert.equal(s0.pending.type, 'menu');
  assert.ok(s2.steps.length > s1.steps.length);
  assert.equal(s0.steps.length < s1.steps.length, true);
  assert.equal(s0.done, false);
});

test('pathEdgeIds reference real edges and follow the walk order', () => {
  const m = buildModel();
  const ids = new Set(m.edges.map((e) => e.id));
  const s = T.advance(m, T.start(m, NUM, MON_10), '1');
  assert.deepEqual(s.pathEdgeIds, ['e0', 'e1', 'e2', 'e3']);
  s.pathEdgeIds.forEach((id) => assert.ok(ids.has(id), id));
  assert.deepEqual(s.pathEntityIds, [NUM, 'ra-main', 'aa-main', 'ra-sales', 'cq-sales']);
  const l = T.advance(m, s, 'overflow');
  l.pathEdgeIds.forEach((id) => assert.ok(ids.has(id), id));
  assert.equal(new Set(l.pathEntityIds).size, l.pathEntityIds.length);
});

test('entryPoints: numbers first, then AAs, then CQs, each sorted by label', () => {
  const m = buildModel((mm) => {
    mm.entities['tel:+27105550000'] = { id: 'tel:+27105550000', kind: 'number', name: 'x', number: '+27 10 555 0000', resourceAccountId: 'ra-sales' };
    mm.entities['aa-a'] = { id: 'aa-a', kind: 'autoAttendant', name: 'Alpha', flows: [] };
    mm.entities['cq-a'] = { id: 'cq-a', kind: 'callQueue', name: 'Accounts', agentIds: [], groupIds: [] };
  });
  const eps = T.entryPoints(m);
  assert.deepEqual(eps.map((e) => e.kind), ['number', 'number', 'autoAttendant', 'autoAttendant', 'callQueue', 'callQueue']);
  assert.deepEqual(eps.map((e) => e.label), [
    '+27 10 555 0000 → Sales Queue',
    '+27 11 555 0100 → Main',
    'Alpha',
    'Main',
    'Accounts',
    'Sales Queue'
  ]);
  assert.equal(eps[1].id, NUM);
});

// ---- wall-clock helpers + review fixes ------------------------------------

test('entryTimeZone follows number -> RA -> AA', () => {
  const m = buildModel();
  assert.equal(T.entryTimeZone(m, NUM), 'Africa/Johannesburg');
  assert.equal(T.entryTimeZone(m, 'no-such-id'), null);
  assert.equal(T.entryTimeZone(m, '__proto__'), null);
});

test('wallClockToDate interprets the input in the attendant zone', () => {
  // 09:00 in Johannesburg (UTC+2, no DST) is 07:00Z.
  const d = T.wallClockToDate('2026-11-09T09:00', 'Africa/Johannesburg');
  assert.equal(d.toISOString(), '2026-11-09T07:00:00.000Z');
  // DST zone: 09:00 New York in July is EDT (UTC-4) -> 13:00Z; in January EST -> 14:00Z.
  assert.equal(T.wallClockToDate('2026-07-01T09:00', 'America/New_York').toISOString(), '2026-07-01T13:00:00.000Z');
  assert.equal(T.wallClockToDate('2026-01-15T09:00', 'America/New_York').toISOString(), '2026-01-15T14:00:00.000Z');
  assert.ok(isNaN(T.wallClockToDate('garbage', 'Africa/Johannesburg')));
});

test('dateToWallClock round-trips with wallClockToDate', () => {
  const tz = 'America/New_York';
  const d = T.wallClockToDate('2026-03-20T17:45', tz);
  assert.equal(T.dateToWallClock(d, tz), '2026-03-20T17:45');
  assert.equal(T.dateToWallClock(new Date('2026-11-09T07:00:00Z'), 'Africa/Johannesburg'), '2026-11-09T09:00');
});

test('weekly end "00:00" means end of day, not minute 0', () => {
  const m = buildModel();
  const aa = Object.values(m.entities).find((e) => e.kind === 'autoAttendant' && e.flows.some((f) => f.key === 'afterHours'));
  const ah = aa.flows.find((f) => f.key === 'afterHours');
  ah.schedule.days.monday = [{ start: '08:00', end: '00:00' }];
  // Monday 22:00 SAST is inside 08:00-24:00 business hours.
  const r = T.activeFlow(aa, new Date(Date.UTC(2026, 10, 9, 20, 0)));
  assert.equal(r.flow.key, 'default');
});

test('prototype keys never resolve as entities', () => {
  const m = buildModel();
  const st = T.start(m, 'constructor', MON_10);
  assert.equal(st.done, true);
  assert.ok(!st.pathEntityIds.includes('constructor'));
});
