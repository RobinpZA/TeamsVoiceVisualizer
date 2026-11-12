/* Voice map: findings drawer and top-bar counts. */
(function () {
  'use strict';
  const VM = window.VM, U = VM.u, M = VM.M;
  const h = U.h, clear = U.clear;
  const F = (VM.findings = {});
  const SEVS = [['error', 'Errors'], ['warning', 'Warnings'], ['info', 'Info']];
  let drawer, body, btn, hnd = {};

  function counts() {
    const c = { error: 0, warning: 0, info: 0 };
    M.findings.forEach((f) => { if (c[f.severity] != null) c[f.severity]++; });
    return c;
  }

  function renderCounts() {
    const c = counts();
    const box = clear(document.getElementById('findingsCounts'));
    if (c.error > 0) box.appendChild(h('span', { class: 'chip chip-error', title: c.error + ' errors', text: String(c.error) }));
    const rest = c.warning + c.info;
    if (rest > 0 || c.error === 0) box.appendChild(h('span', { class: 'chip', title: c.warning + ' warnings, ' + c.info + ' info', text: String(c.error === 0 ? c.warning + c.info : rest) }));
    btn.setAttribute('aria-label', 'Findings: ' + c.error + ' errors, ' + c.warning + ' warnings, ' + c.info + ' info');
  }

  function renderList() {
    clear(body);
    if (!M.findings.length) { body.appendChild(h('p', { class: 'empty', text: 'No findings. Every number reaches a flow and every queue has agents.' })); return; }
    const c = counts();
    SEVS.forEach((s) => {
      const items = M.findings.filter((f) => f.severity === s[0]);
      if (!items.length) return;
      body.appendChild(h('section', { class: 'fgroup' },
        h('div', { class: 'fgroup-head' }, h('span', { class: 'sev-dot sev-' + s[0], 'aria-hidden': 'true' }), h('span', { text: s[1] + ' · ' + c[s[0]] })),
        items.map((f) => h('button', { type: 'button', class: 'frow', onclick: () => VM.app.select(f.entityId, { zoom: true }) },
          h('span', { class: 'sev-dot sev-' + f.severity, 'aria-hidden': 'true' }),
          h('span', null, h('div', { class: 'frow-msg', text: f.message }), h('div', { class: 'frow-ent', text: M.name(f.entityId) + ' · ' + f.code }))))));
    });
  }

  F.isOpen = () => drawer.getAttribute('data-open') === 'true';
  F.open = function () { drawer.setAttribute('data-open', 'true'); drawer.removeAttribute('inert'); btn.setAttribute('aria-expanded', 'true'); hnd.onLayoutChange && hnd.onLayoutChange(); };
  F.close = function () { drawer.setAttribute('data-open', 'false'); drawer.setAttribute('inert', ''); btn.setAttribute('aria-expanded', 'false'); hnd.onLayoutChange && hnd.onLayoutChange(); };
  F.toggle = () => (F.isOpen() ? F.close() : F.open());
  F.width = () => (F.isOpen() ? drawer.getBoundingClientRect().width : 0);
  F.refresh = function () { renderCounts(); renderList(); };

  F.init = function (handlers) {
    hnd = handlers || {};
    drawer = document.getElementById('findingsDrawer');
    body = document.getElementById('findingsBody');
    btn = document.getElementById('findingsBtn');
    drawer.setAttribute('inert', '');
    btn.addEventListener('click', F.toggle);
    document.getElementById('findingsClose').addEventListener('click', F.close);
    F.refresh();
  };
})();
