/* Dev-only sample model (docs/model.md, schemaVersion 1). Removed from the packaged report. */
(function () {
  'use strict';
  const g = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
  const ID = {
    aaMain: g(101), aaOps: g(102), cqSales: g(201), cqSupport: g(202), cqBilling: g(203),
    raMain: g(301), raSales: g(302), raSupport: g(303), raOps: g(304), raSpare: g(305),
    alice: g(401), bob: g(402), carol: g(403), dave: g(404), erin: g(405),
    grpTeam: g(501), grpVm: g(502), ghost: g(999),
  };
  const tel = (n) => 'tel:+' + n;

  const entities = {};
  const put = (e) => { entities[e.id] = e; return e; };

  /* numbers */
  put({ id: tel('27115550100'), kind: 'number', name: '+27 11 555 0100', number: '+27 11 555 0100', resourceAccountId: ID.raMain });
  put({ id: tel('27115550101'), kind: 'number', name: '+27 11 555 0101', number: '+27 11 555 0101', resourceAccountId: ID.raSales });
  put({ id: tel('27115550102'), kind: 'number', name: '+27 11 555 0102', number: '+27 11 555 0102', resourceAccountId: ID.raSupport });
  put({ id: tel('27115550199'), kind: 'number', name: '+27 11 555 0199', number: '+27 11 555 0199', resourceAccountId: ID.raSpare });
  put({ id: tel('27825550123'), kind: 'external', name: '+27 82 555 0123', number: '+27825550123' });

  /* resource accounts */
  put({ id: ID.raMain, kind: 'resourceAccount', name: 'ra-main-reception', upn: 'ra-main-reception@contoso.example', phoneNumbers: ['+27115550100'], appType: 'autoAttendant', configId: ID.aaMain });
  put({ id: ID.raSales, kind: 'resourceAccount', name: 'ra-sales-queue', upn: 'ra-sales-queue@contoso.example', phoneNumbers: ['+27115550101'], appType: 'callQueue', configId: ID.cqSales });
  put({ id: ID.raSupport, kind: 'resourceAccount', name: 'ra-support-queue', upn: 'ra-support-queue@contoso.example', phoneNumbers: ['+27115550102'], appType: 'callQueue', configId: ID.cqSupport });
  put({ id: ID.raOps, kind: 'resourceAccount', name: 'ra-after-hours-desk', upn: 'ra-after-hours-desk@contoso.example', phoneNumbers: [], appType: 'autoAttendant', configId: ID.aaOps });
  put({ id: ID.raSpare, kind: 'resourceAccount', name: 'ra-spare', upn: 'ra-spare@contoso.example', phoneNumbers: ['+27115550199'], appType: null, configId: null });

  /* people */
  [['alice', 'Alice Naidoo'], ['bob', 'Bob Smit'], ['carol', 'Carol Dlamini'], ['dave', 'Dave Pretorius'], ['erin', 'Erin Botha']].forEach((p) => {
    put({ id: ID[p[0]], kind: 'user', name: p[1], upn: p[0] + '@contoso.example' });
  });
  put({ id: ID.grpTeam, kind: 'group', name: 'Support Team', isSharedVoicemail: false });
  put({ id: ID.grpVm, kind: 'group', name: 'Reception Voicemail', isSharedVoicemail: true });
  put({ id: ID.ghost, kind: 'user', name: ID.ghost, unresolved: true, upn: null });

  /* system terminals */
  put({ id: 'sys:disconnect', kind: 'system', name: 'Disconnect', systemType: 'disconnect' });
  put({ id: 'sys:announcement', kind: 'system', name: 'Announcement', systemType: 'announcement' });
  put({ id: 'sys:operator:' + ID.aaMain, kind: 'system', name: 'Operator', systemType: 'operator', targetRef: ID.erin });

  const tts = (text) => ({ type: 'tts', text });
  const weekdays = (s, e) => ({ monday: [{ start: s, end: e }], tuesday: [{ start: s, end: e }], wednesday: [{ start: s, end: e }], thursday: [{ start: s, end: e }], friday: [{ start: s, end: e }], saturday: [], sunday: [] });

  /* auto attendants */
  put({
    id: ID.aaMain, kind: 'autoAttendant', name: 'Main Reception', language: 'en-ZA',
    timeZone: 'South Africa Standard Time', timeZoneIana: 'Africa/Johannesburg',
    dialByName: true, directorySearchMethod: 'ByName', voiceResponse: false,
    operatorRef: 'sys:operator:' + ID.aaMain, resourceAccountIds: [ID.raMain],
    flows: [
      {
        key: 'default', label: 'Business hours', schedule: null,
        greetings: [tts('Welcome to Contoso.\nYour call may be recorded for quality purposes.')],
        menu: {
          prompts: [tts('For sales press 1. For support press 2. For billing press 3. To reach a mobile line press 4. For the operator press 0.')],
          options: [
            { key: '1', voice: ['sales'], action: 'transfer', targetRef: ID.raSales },
            { key: '2', voice: ['support'], action: 'transfer', targetRef: ID.raSupport },
            { key: '3', voice: ['billing'], action: 'transfer', targetRef: ID.ghost },
            { key: '4', voice: [], action: 'transfer', targetRef: tel('27825550123') },
            { key: '0', voice: ['operator'], action: 'operator', targetRef: 'sys:operator:' + ID.aaMain },
            { key: '*', voice: [], action: 'announcement', targetRef: 'sys:announcement', announcement: tts('Our offices are at 12 Rivonia Road, Sandton.') },
            { key: '#', voice: [], action: 'disconnect', targetRef: 'sys:disconnect' },
          ],
        },
      },
      {
        key: 'afterHours', label: 'After hours', schedule: { type: 'weekly', days: weekdays('08:00', '17:00') },
        greetings: [tts('Thank you for calling Contoso. Our office is closed. Business hours are Monday to Friday, 08:00 to 17:00.')],
        menu: {
          prompts: [tts('To leave a voicemail press 1. For the after hours desk press 2.')],
          options: [
            { key: '1', voice: [], action: 'transfer', targetRef: ID.grpVm },
            { key: '2', voice: [], action: 'transfer', targetRef: ID.raOps },
          ],
        },
      },
      {
        key: 'holiday:christmas', label: 'Holiday: Christmas',
        schedule: { type: 'fixed', ranges: [{ start: '2026-12-25T00:00:00', end: '2026-12-26T00:00:00' }] },
        greetings: [{ type: 'audio', audioFile: 'christmas-closed.wav' }],
        menu: { prompts: [], options: [{ key: 'automatic', voice: [], action: 'disconnect', targetRef: 'sys:disconnect' }] },
      },
    ],
  });

  put({
    id: ID.aaOps, kind: 'autoAttendant', name: 'After Hours Desk', language: 'en-ZA',
    timeZone: 'South Africa Standard Time', timeZoneIana: 'Africa/Johannesburg',
    dialByName: false, directorySearchMethod: 'None', voiceResponse: false, operatorRef: null, resourceAccountIds: [ID.raOps],
    flows: [
      {
        key: 'default', label: 'Business hours', schedule: null,
        greetings: [tts('You have reached the after hours desk.')],
        menu: { prompts: [tts('Press 1 for the main menu. Press 2 to end the call.')], options: [
          { key: '1', voice: [], action: 'transfer', targetRef: ID.raMain },
          { key: '2', voice: [], action: 'disconnect', targetRef: 'sys:disconnect' },
        ] },
      },
      {
        key: 'afterHours', label: 'After hours', schedule: { type: 'weekly', days: weekdays('17:00', '23:59') },
        greetings: [{ type: 'silence' }],
        menu: { prompts: [], options: [{ key: 'automatic', voice: [], action: 'transfer', targetRef: ID.raSupport }] },
      },
      {
        key: 'holiday:newyear', label: 'Holiday: New Year',
        schedule: { type: 'fixed', ranges: [{ start: '2027-01-01T00:00:00', end: '2027-01-02T00:00:00' }] },
        greetings: [tts('Happy new year. We are closed today.')],
        menu: { prompts: [], options: [] },
      },
    ],
  });

  /* call queues */
  put({
    id: ID.cqSales, kind: 'callQueue', name: 'Sales', language: 'en-ZA', routingMethod: 'LongestIdle', agentAlertSeconds: 30,
    conferenceMode: true, presenceBasedRouting: true, allowOptOut: true, slaSeconds: 30,
    greeting: tts('Thank you for calling sales. An agent will be with you shortly.'), musicOnHold: { type: 'default' },
    agentIds: [ID.alice, ID.bob, ID.carol], groupIds: [], channel: null, oboResourceAccountIds: [], resourceAccountIds: [ID.raSales],
    exceptions: {
      overflow: { threshold: 50, action: 'forward', targetRef: ID.raSupport },
      timeout: { threshold: 1200, action: 'voicemail', targetRef: ID.grpVm },
      noAgent: { action: 'disconnect', targetRef: 'sys:disconnect' },
    },
  });
  put({
    id: ID.cqSupport, kind: 'callQueue', name: 'Support', language: 'en-ZA', routingMethod: 'RoundRobin', agentAlertSeconds: 20,
    conferenceMode: false, presenceBasedRouting: true, allowOptOut: false, slaSeconds: 60,
    greeting: { type: 'audio', audioFile: 'support-greeting.wav' }, musicOnHold: { type: 'custom', audioFile: 'hold-jazz.mp3' },
    agentIds: [ID.dave], groupIds: [ID.grpTeam], channel: { id: '19:support@thread.tacv2', ownerId: ID.dave }, oboResourceAccountIds: [ID.raMain], resourceAccountIds: [ID.raSupport],
    exceptions: {
      overflow: { threshold: 25, action: 'forward', targetRef: ID.raMain },
      timeout: { threshold: 900, action: 'forward', targetRef: tel('27825550123') },
      noAgent: { action: 'queue', targetRef: null },
    },
  });
  put({
    id: ID.cqBilling, kind: 'callQueue', name: 'Billing', language: 'en-ZA', routingMethod: 'Attendant', agentAlertSeconds: 30,
    conferenceMode: false, presenceBasedRouting: false, allowOptOut: false, slaSeconds: null,
    greeting: { type: 'none' }, musicOnHold: { type: 'default' },
    agentIds: [], groupIds: [], channel: null, oboResourceAccountIds: [], resourceAccountIds: [],
    exceptions: { noAgent: { action: 'disconnect', targetRef: 'sys:disconnect' } },
  });

  /* entity-level edges derived from the objects above (docs/model.md, Edges) */
  const edges = [];
  const seen = new Set();
  const edge = (from, to, kind, via, label) => {
    const k = [from, to, kind, JSON.stringify(via || null)].join('|');
    if (!to || seen.has(k)) return;
    seen.add(k);
    edges.push({ id: 'e' + edges.length, from, to, kind, label: label || '', via: via || null });
  };
  Object.keys(entities).forEach((id) => {
    const e = entities[id];
    if (e.kind === 'number') edge(id, e.resourceAccountId, 'dials');
    if (e.kind === 'resourceAccount' && e.configId) edge(id, e.configId, 'fronts');
  });
  Object.keys(entities).forEach((id) => {
    const e = entities[id];
    if (e.kind === 'autoAttendant') {
      e.flows.forEach((f) => ((f.menu && f.menu.options) || []).forEach((o) => edge(id, o.targetRef, 'route', { flow: f.key, key: o.key }, o.key + ' · ' + f.label)));
      if (e.operatorRef) edge(id, e.operatorRef, 'operator');
    }
    if (e.kind === 'callQueue') {
      e.agentIds.forEach((a) => edge(id, a, 'agent'));
      e.groupIds.forEach((a) => edge(id, a, 'agent'));
      Object.keys(e.exceptions).forEach((n) => edge(id, e.exceptions[n].targetRef, 'exception', { exception: n }, n));
      e.oboResourceAccountIds.forEach((r) => edge(id, r, 'callerId'));
    }
  });

  const findings = [
    { id: 'f0', severity: 'error', code: 'QUEUE_NO_AGENTS', entityId: ID.cqBilling, message: 'Call queue "Billing" has no agents, groups or channel.' },
    { id: 'f1', severity: 'warning', code: 'TARGET_UNRESOLVED', entityId: ID.ghost, message: 'Main Reception option 3 points at an object that could not be found in the tenant.' },
    { id: 'f2', severity: 'warning', code: 'RA_UNASSIGNED', entityId: ID.raSpare, message: 'Resource account "ra-spare" has a phone number but is not assigned to an auto attendant or call queue.' },
    { id: 'f3', severity: 'info', code: 'RA_NO_NUMBER_ENTRY', entityId: ID.cqBilling, message: 'No phone number reaches call queue "Billing".' },
  ];

  window.__VM_DEV_MODEL__ = {
    schemaVersion: 1,
    tenant: { name: 'Contoso (sample)', generatedAt: '2026-11-12T10:00:00+02:00' },
    entities, edges, findings,
  };
})();
