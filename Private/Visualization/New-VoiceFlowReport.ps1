function New-VoiceFlowReport {
    <#
    .SYNOPSIS
        Assembles the complete interactive D3.js HTML report from AA and CQ graph data.
    .PARAMETER AutoAttendantGraphs
        Array of Auto Attendant graph objects from New-AAGraphData.
    .PARAMETER CallQueueGraphs
        Array of Call Queue graph objects from New-CQGraphData.
    .PARAMETER TenantName
        The display name of the tenant for the report header.
    .PARAMETER OutputPath
        Optional path to save the HTML file. If not provided, returns the HTML string.
    .EXAMPLE
        New-VoiceFlowReport -AutoAttendantGraphs $aas -CallQueueGraphs $cqs -TenantName 'Contoso' -OutputPath 'report.html'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AutoAttendantGraphs,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$CallQueueGraphs,

        [Parameter(Mandatory)]
        [string]$TenantName,

        [Parameter()]
        [string]$OutputPath
    )

    $generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
    $aaCount = $AutoAttendantGraphs.Count
    $cqCount = $CallQueueGraphs.Count

    # Serialize graph data to JSON for embedding.
    # NOTE: piping a single object to ConvertTo-Json emits a JSON *object* (not an
    # array), and an empty collection emits nothing — both break the JS that expects
    # an array. Use -InputObject with an @() wrap so we always get a JSON array.
    $aaJson = if ($aaCount -gt 0) { ConvertTo-Json -InputObject @($AutoAttendantGraphs) -Depth 10 -Compress } else { '[]' }
    $cqJson = if ($cqCount -gt 0) { ConvertTo-Json -InputObject @($CallQueueGraphs) -Depth 10 -Compress } else { '[]' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Teams Voice Flow Report — $([System.Security.SecurityElement]::Escape($TenantName))</title>
    <style>
        :root {
            --bg: #0d1117;
            --bg-card: #161b22;
            --bg-hover: #1c2333;
            --border: #30363d;
            --text: #c9d1d9;
            --text-muted: #8b949e;
            --accent: #58a6ff;
            --accent-green: #3fb950;
            --accent-orange: #d29922;
            --accent-red: #f85149;
            --accent-purple: #bc8cff;
            --accent-cyan: #39d2c0;
            --accent-pink: #f778ba;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.6;
        }
        .header {
            background: var(--bg-card);
            border-bottom: 1px solid var(--border);
            padding: 24px 32px;
            position: sticky;
            top: 0;
            z-index: 100;
            backdrop-filter: blur(8px);
        }
        .header h1 {
            font-size: 1.5rem;
            font-weight: 600;
            color: var(--text);
            margin-bottom: 4px;
        }
        .header .meta {
            font-size: 0.85rem;
            color: var(--text-muted);
        }
        .header .stats {
            display: flex;
            gap: 24px;
            margin-top: 12px;
        }
        .header .stat {
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .header .stat .dot {
            width: 10px; height: 10px; border-radius: 50%;
        }
        .dot-aa { background: var(--accent); }
        .dot-cq { background: var(--accent-green); }
        .nav {
            display: flex;
            gap: 12px;
            margin-top: 16px;
            flex-wrap: wrap;
        }
        .nav a {
            color: var(--accent);
            text-decoration: none;
            font-size: 0.85rem;
            padding: 4px 12px;
            border: 1px solid var(--border);
            border-radius: 6px;
            transition: all 0.15s;
        }
        .nav a:hover { background: var(--bg-hover); border-color: var(--accent); }
        .nav .nav-label {
            color: var(--text-muted);
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            padding: 4px 0;
            font-weight: 600;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 32px; }
        .section-title {
            font-size: 1.1rem;
            font-weight: 600;
            color: var(--text);
            margin: 32px 0 16px;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .diagram-card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            margin-bottom: 32px;
            overflow: hidden;
            transition: border-color 0.2s;
        }
        .diagram-card:hover { border-color: #484f58; }
        .diagram-card .card-header {
            padding: 16px 20px;
            border-bottom: 1px solid var(--border);
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: pointer;
            user-select: none;
        }
        .diagram-card .card-header h3 {
            font-size: 1rem;
            font-weight: 600;
            color: var(--text);
        }
        .diagram-card .card-header .badge {
            font-size: 0.7rem;
            padding: 2px 8px;
            border-radius: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .badge-aa { background: rgba(88, 166, 255, 0.15); color: var(--accent); }
        .badge-cq { background: rgba(63, 185, 80, 0.15); color: var(--accent-green); }
        .diagram-card .card-meta {
            padding: 8px 20px;
            font-size: 0.78rem;
            color: var(--text-muted);
            display: flex;
            gap: 16px;
            flex-wrap: wrap;
        }
        .diagram-card .card-body {
            padding: 0;
            position: relative;
            overflow: hidden;
        }
        .diagram-card svg { width: 100%; display: block; }
        .diagram-card.collapsed .card-body { display: none; }

        /* SVG node styles */
        .node { cursor: grab; }
        .node:active { cursor: grabbing; }
        .node circle { stroke-width: 2px; transition: stroke-width 0.15s, filter 0.15s; }
        .node text { font-size: 11px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: var(--text); pointer-events: none; }
        .node .sub-label { font-size: 9px; fill: var(--text-muted); }
        .link { fill: none; stroke-opacity: 0.6; }
        .link.solid { stroke: #484f58; stroke-width: 1.5px; }
        .link.dashed { stroke: #484f58; stroke-width: 1px; stroke-dasharray: 5,5; }
        .link.dotted { stroke: #484f58; stroke-width: 1px; stroke-dasharray: 2,4; }
        .link.error { stroke: var(--accent-orange); stroke-width: 1.5px; }
        .link-label { font-size: 9px; fill: var(--text-muted); text-anchor: middle; }
        .flow-label { font-size: 9px; fill: var(--accent-purple); text-anchor: start; pointer-events: none; }

        /* Node type colors */
        .node-type-autoattendant circle { fill: rgba(88, 166, 255, 0.2); stroke: var(--accent); }
        .node-type-callqueue circle { fill: rgba(63, 185, 80, 0.2); stroke: var(--accent-green); }
        .node-type-greeting circle { fill: rgba(139, 148, 158, 0.15); stroke: var(--text-muted); }
        .node-type-menu circle { fill: rgba(188, 140, 255, 0.15); stroke: var(--accent-purple); }
        .node-type-user circle { fill: rgba(57, 210, 192, 0.15); stroke: var(--accent-cyan); }
        .node-type-resourceaccount circle { fill: rgba(247, 119, 186, 0.15); stroke: var(--accent-pink); }
        .node-type-external circle { fill: rgba(210, 153, 34, 0.15); stroke: var(--accent-orange); }
        .node-type-operator circle { fill: rgba(88, 166, 255, 0.2); stroke: var(--accent); }
        .node-type-disconnect circle { fill: rgba(248, 81, 73, 0.15); stroke: var(--accent-red); }
        .node-type-announcement circle { fill: rgba(139, 148, 158, 0.12); stroke: var(--text-muted); }
        .node-type-endpoint circle { fill: rgba(139, 148, 158, 0.12); stroke: var(--text-muted); }
        .node-type-default_action circle { fill: rgba(139, 148, 158, 0.12); stroke: var(--text-muted); }
        .node-type-moh circle { fill: rgba(188, 140, 255, 0.12); stroke: var(--accent-purple); }
        .node-type-routing circle { fill: rgba(57, 210, 192, 0.12); stroke: var(--accent-cyan); }
        .node-type-agentgroup circle { fill: rgba(63, 185, 80, 0.2); stroke: var(--accent-green); }
        .node-type-overflow, .node-type-timeout, .node-type-noagents circle { fill: rgba(210, 153, 34, 0.12); stroke: var(--accent-orange); }
        .node-type-voicemail circle { fill: rgba(139, 148, 158, 0.15); stroke: var(--text-muted); }
        .node-type-conference_mode circle { fill: rgba(88, 166, 255, 0.12); stroke: var(--accent); r: 6px; }
        .node-type-agent_alert circle { fill: rgba(88, 166, 255, 0.12); stroke: var(--accent); r: 6px; }
        .node-type-presence_routing circle { fill: rgba(63, 185, 80, 0.12); stroke: var(--accent-green); r: 6px; }

        /* Tooltip */
        .tooltip {
            position: absolute;
            background: var(--bg-hover);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 8px 12px;
            font-size: 0.78rem;
            color: var(--text);
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.15s;
            max-width: 300px;
            z-index: 1000;
            box-shadow: 0 8px 24px rgba(0,0,0,0.4);
        }
        .tooltip.visible { opacity: 1; }

        .legend {
            display: flex;
            gap: 16px;
            flex-wrap: wrap;
            padding: 16px 20px;
            font-size: 0.75rem;
            color: var(--text-muted);
        }
        .legend-item { display: flex; align-items: center; gap: 6px; }
        .legend-dot { width: 10px; height: 10px; border-radius: 50%; border: 2px solid; }

        /* Search */
        .search-row { margin-top: 14px; display: flex; align-items: center; gap: 10px; }
        .search-input {
            flex: 1; max-width: 380px;
            background: var(--bg); border: 1px solid var(--border); border-radius: 6px;
            padding: 7px 12px; color: var(--text); font-size: 0.85rem;
        }
        .search-input:focus { outline: none; border-color: var(--accent); }
        .search-count { font-size: 0.78rem; color: var(--text-muted); }

        /* Per-diagram toolbar */
        .diagram-toolbar { position: absolute; top: 10px; right: 12px; z-index: 5; display: flex; gap: 6px; }
        .tool-btn {
            background: var(--bg-hover); border: 1px solid var(--border); color: var(--text-muted);
            border-radius: 6px; padding: 4px 10px; font-size: 0.74rem; cursor: pointer; transition: all 0.15s;
        }
        .tool-btn:hover { border-color: var(--accent); color: var(--accent); }

        /* Cross-flow jump nodes */
        .node.has-jump { cursor: pointer; }
        .node.has-jump circle { stroke-dasharray: 4,2; }
        .node.has-jump text { text-decoration: underline; text-decoration-style: dotted; }

        /* Search highlight / dim */
        .node.search-dim { opacity: 0.12; }
        .node.search-match circle { stroke-width: 3.5px; filter: drop-shadow(0 0 5px var(--accent)); }
        .diagram-card.search-hidden { display: none; }

        /* Jump-target flash */
        .diagram-card.flash { animation: flash-pulse 1.3s ease; }
        @keyframes flash-pulse {
            0%, 100% { border-color: var(--border); box-shadow: none; }
            25% { border-color: var(--accent); box-shadow: 0 0 0 2px rgba(88,166,255,0.35); }
        }
    </style>
</head>
<body>
<div class="header">
    <h1>&#x1F4DE; Teams Voice Flow Report</h1>
    <div class="meta">Tenant: $([System.Security.SecurityElement]::Escape($TenantName)) &mdash; Generated: $generatedAt</div>
    <div class="stats">
        <div class="stat"><span class="dot dot-aa"></span> $aaCount Auto Attendant$(if ($aaCount -ne 1) { 's' })</div>
        <div class="stat"><span class="dot dot-cq"></span> $cqCount Call Queue$(if ($cqCount -ne 1) { 's' })</div>
    </div>
    <div class="nav" id="nav"></div>
    <div class="search-row">
        <input type="search" id="search" class="search-input" placeholder="Search nodes (user, queue, number, greeting text)&hellip;" autocomplete="off">
        <span class="search-count" id="search-count"></span>
    </div>
</div>
<div class="container" id="container"></div>

<!-- D3.js v7 -->
<script src="https://d3js.org/d3.v7.min.js"></script>
<!-- dagre: layered directed-graph layout (preserves shared nodes + back-edges) -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/dagre/0.8.5/dagre.min.js"></script>
<script>
"use strict";
// Normalize to arrays — guards against a single object or null sneaking through.
function asArray(d) { return Array.isArray(d) ? d : (d != null ? [d] : []); }
const aaData = asArray($aaJson);
const cqData = asArray($cqJson);

const container = d3.select('#container');
const nav = d3.select('#nav');

// ── HTML escape helper (greeting/TTS text is untrusted free text) ──
function esc(s) {
    return String(s == null ? '' : s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// ── Diagram export (SVG / PNG) ──
function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

// Clone an SVG into a standalone document: full extent (pan/zoom reset),
// the page stylesheet inlined, and an opaque background.
function serializeDiagram(svgNode) {
    const vb = (svgNode.getAttribute('viewBox') || '0 0 800 600').split(' ').map(Number);
    const clone = svgNode.cloneNode(true);
    clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    clone.setAttribute('width', vb[2]);
    clone.setAttribute('height', vb[3]);
    const mainG = clone.querySelector('g');
    if (mainG) mainG.removeAttribute('transform');
    const styleEl = document.createElement('style');
    const srcStyle = document.querySelector('style');
    styleEl.textContent = srcStyle ? srcStyle.textContent : '';
    clone.insertBefore(styleEl, clone.firstChild);
    const bg = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    bg.setAttribute('x', vb[0]); bg.setAttribute('y', vb[1]);
    bg.setAttribute('width', vb[2]); bg.setAttribute('height', vb[3]);
    bg.setAttribute('fill', '#0d1117');
    clone.insertBefore(bg, styleEl.nextSibling);
    return { xml: new XMLSerializer().serializeToString(clone), w: vb[2], h: vb[3] };
}

function exportDiagram(svgNode, name, fmt) {
    const out = serializeDiagram(svgNode);
    if (fmt === 'svg') {
        downloadBlob(new Blob([out.xml], { type: 'image/svg+xml;charset=utf-8' }), name + '.svg');
        return;
    }
    const scale = 2; // 2x for crisp raster output
    const src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(out.xml)));
    const img = new Image();
    img.onload = function() {
        const canvas = document.createElement('canvas');
        canvas.width = out.w * scale; canvas.height = out.h * scale;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#0d1117'; ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.scale(scale, scale);
        ctx.drawImage(img, 0, 0);
        canvas.toBlob(b => { if (b) downloadBlob(b, name + '.png'); }, 'image/png');
    };
    img.onerror = function() { alert('PNG export failed (could not rasterize the diagram).'); };
    img.src = src;
}

// ── Cross-flow resolution maps ──
// Resource-account objectId -> the AA/CQ diagram it fronts, and AA-id -> diagram.
// Keys are normalized (lower-cased) so GUID casing differences between the AA
// menu target and the resource-account id never cause a jump to silently miss.
const raMap = {};
const aaIdMap = {};
const normId = s => (s == null ? '' : String(s)).toLowerCase();
aaData.forEach((aa, i) => {
    const dest = { prefix: 'aa', index: i, name: aa.autoAttendantName || ('AA ' + (i + 1)) };
    aaIdMap[normId(aa.autoAttendantId)] = dest;
    (aa.resourceAccounts || []).forEach(ra => { if (ra) raMap[normId(ra)] = dest; });
});
cqData.forEach((cq, i) => {
    const dest = { prefix: 'cq', index: i, name: cq.callQueueName || ('CQ ' + (i + 1)) };
    (cq.resourceAccounts || []).forEach(ra => { if (ra) raMap[normId(ra)] = dest; });
});

function resolveJump(nd) {
    if (!nd) return null;
    if (nd.linkKind === 'ra') return raMap[normId(nd.targetRef)] || null;
    if (nd.linkKind === 'aa') return aaIdMap[normId(nd.targetRef)] || null;
    return null;
}

function jumpTo(dest) {
    const sel = d3.select('#' + dest.prefix + '-' + dest.index);
    const el = sel.node();
    if (!el) return;
    sel.classed('collapsed', false).classed('search-hidden', false);
    el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    sel.classed('flash', false);
    void el.offsetWidth; // force reflow so the animation can replay
    sel.classed('flash', true);
    setTimeout(() => sel.classed('flash', false), 1400);
}

// Registry of rendered node selections, for global search.
const diagramRegistry = [];

// ── Build navigation ──
if (aaData.length > 0) {
    nav.append('span').attr('class', 'nav-label').text('Auto Attendants');
    aaData.forEach((aa, i) => {
        nav.append('a')
            .attr('href', '#aa-' + i)
            .text(aa.autoAttendantName || 'AA ' + (i + 1));
    });
}
if (cqData.length > 0) {
    nav.append('span').attr('class', 'nav-label').text('Call Queues');
    cqData.forEach((cq, i) => {
        nav.append('a')
            .attr('href', '#cq-' + i)
            .text(cq.callQueueName || 'CQ ' + (i + 1));
    });
}

// ── Tooltip setup ──
const tooltip = d3.select('body').append('div').attr('class', 'tooltip');

function showTooltip(event, d) {
    const nd = (d && d.data) ? d.data : d;
    const label = nd.label || nd.id || '';
    const sub = nd.subLabel || '';
    const type = nd.type || '';
    let html = '<strong>' + esc(label) + '</strong><br>' +
        '<span style="color:#8b949e">' + esc(type) + (sub ? ' &middot; ' + esc(sub) : '') + '</span>';
    if (nd.detail && Array.isArray(nd.detail) && nd.detail.length > 0) {
        html += '<div style="margin-top:6px;max-height:160px;overflow-y:auto;border-top:1px solid #30363d;padding-top:5px">';
        nd.detail.forEach(function(item) {
            html += '<div style="padding:1px 0;color:#e6edf3">' + esc(item) + '</div>';
        });
        html += '</div>';
    }
    const jump = resolveJump(nd);
    if (jump) {
        html += '<div style="margin-top:6px;border-top:1px solid #30363d;padding-top:5px;color:#58a6ff">' +
            '&#x2197; Click to jump to ' + esc(jump.name) + '</div>';
    }
    tooltip.html(html)
        .classed('visible', true)
        .style('left', (event.pageX + 12) + 'px')
        .style('top', (event.pageY - 10) + 'px');
}

function hideTooltip() { tooltip.classed('visible', false); }

// ── Render diagram ──
function renderDiagram(data, index, prefix, badgeClass, badgeText) {
    const card = container.append('div')
        .attr('class', 'diagram-card')
        .attr('id', prefix + '-' + index);

    card.append('div')
        .attr('class', 'card-header')
        .on('click', function() { card.classed('collapsed', !card.classed('collapsed')); })
        .html('<h3>' + (data.autoAttendantName || data.callQueueName || 'Unknown') + '</h3><span class="badge ' + badgeClass + '">' + badgeText + '</span>');

    const meta = card.append('div').attr('class', 'card-meta');
    if (data.features) meta.append('span').text(data.features);
    if (data.routingMethod) meta.append('span').text('Routing: ' + data.routingMethod);
    if (data.language) meta.append('span').text('Lang: ' + data.language);
    if (data.timeZone) meta.append('span').text('TZ: ' + data.timeZone);
    if (data.resourceAccounts && data.resourceAccounts.length > 0) {
        meta.append('span').text('RA: ' + data.resourceAccounts.length);
    }

    // Legend
    const legendItems = [
        { label: 'Greeting', cls: 'node-type-greeting' },
        { label: 'Menu', cls: 'node-type-menu' },
        { label: 'User/Agent', cls: 'node-type-user' },
        { label: 'RA/OBO', cls: 'node-type-resourceaccount' },
        { label: 'External PSTN', cls: 'node-type-external' },
        { label: 'Disconnect', cls: 'node-type-disconnect' },
        { label: 'Exception', cls: 'node-type-overflow' },
    ];
    const legend = card.append('div').attr('class', 'legend');
    legendItems.forEach(item => {
        const div = legend.append('div').attr('class', 'legend-item');
        div.append('span').attr('class', 'legend-dot ' + item.cls);
        div.append('span').text(item.label);
    });

    const body = card.append('div').attr('class', 'card-body');

    const nodes = data.nodes || [];
    const links = data.links || [];
    if (nodes.length === 0) {
        body.append('div').style('padding', '24px').style('color', '#8b949e')
            .text('No flow data available for this object.');
        return;
    }

    // ── Build link maps + identify root (flat directed graph; no tree flattening) ──
    const nodeById = {};
    nodes.forEach(n => { nodeById[n.id] = n; });
    const linkLabelMap = {}, linkStyleMap = {}, hasParent = new Set();
    links.forEach(l => {
        const src = (typeof l.source === 'object') ? l.source.id : l.source;
        const tgt = (typeof l.target === 'object') ? l.target.id : l.target;
        linkLabelMap[src + '->' + tgt] = l.label || '';
        linkStyleMap[src + '->' + tgt] = l.style || 'solid';
        hasParent.add(tgt);
    });
    const rootId = ((nodes.find(n => n.type === 'autoattendant' || n.type === 'callqueue'))
                  || (nodes.find(n => !hasParent.has(n.id)))
                  || nodes[0]).id;

    function nodeRadius(t) {
        switch (t) {
            case 'autoattendant': case 'callqueue': return 18;
            case 'greeting': case 'menu': case 'agentgroup': return 14;
            case 'conference_mode': case 'agent_alert': case 'presence_routing': return 6;
            default: return 12;
        }
    }

    // ── Layered directed layout via dagre ──
    // Unlike d3.tree(), a layered DAG layout keeps a target referenced from two
    // places as a *single* node (with multiple incoming edges) and preserves
    // back-edges (e.g. AA → CQ → same AA loops) instead of silently cutting them.
    const dg = new dagre.graphlib.Graph({ multigraph: true });
    dg.setGraph({ rankdir: 'LR', nodesep: 30, ranksep: 180, marginx: 20, marginy: 20 });
    dg.setDefaultEdgeLabel(() => ({}));

    nodes.forEach(n => {
        const r = nodeRadius(n.type);
        dg.setNode(n.id, { width: r * 2, height: r * 2, r: r });
    });
    let edgeSeq = 0;
    links.forEach(l => {
        const src = (typeof l.source === 'object') ? l.source.id : l.source;
        const tgt = (typeof l.target === 'object') ? l.target.id : l.target;
        if (!nodeById[src] || !nodeById[tgt]) return;
        dg.setEdge(src, tgt,
            { style: linkStyleMap[src + '->' + tgt] || 'solid', label: linkLabelMap[src + '->' + tgt] || '' },
            'e' + (edgeSeq++));
    });

    dagre.layout(dg);

    // Mutable per-node render data so node drag can move them after layout.
    const nodeData = nodes.filter(n => dg.hasNode(n.id)).map(n => {
        const p = dg.node(n.id);
        return { data: n, x: p.x, y: p.y, r: p.r };
    });
    const posById = {};
    nodeData.forEach(d => { posById[d.data.id] = d; });
    function centerOf(id) { const d = posById[id]; return d ? { x: d.x, y: d.y } : { x: 0, y: 0 }; }

    const edgeData = dg.edges().map(e => {
        const v = dg.edge(e);
        return { source: e.v, target: e.w, style: v.style, label: v.label, points: v.points, _dragged: false };
    });

    const pad = 40;
    const vbW = (dg.graph().width || 200) + pad * 2;
    const vbH = (dg.graph().height || 200) + pad * 2;

    const svg = body.append('svg')
        .attr('viewBox', (-pad) + ' ' + (-pad) + ' ' + vbW + ' ' + vbH)
        .attr('preserveAspectRatio', 'xMidYMid meet')
        .style('height', Math.max(350, Math.min(vbH, 650)) + 'px');

    const defs = svg.append('defs');
    ['', '-err'].forEach(sfx => {
        defs.append('marker')
            .attr('id', 'arr' + sfx + '-' + prefix + '-' + index)
            .attr('viewBox', '0 -4 8 8').attr('refX', 8).attr('refY', 0)
            .attr('markerWidth', 5).attr('markerHeight', 5).attr('orient', 'auto')
            .append('path').attr('d', 'M0,-4L8,0L0,4')
            .attr('fill', sfx ? 'var(--accent-orange)' : '#484f58');
    });

    const g = svg.append('g');
    const zoom = d3.zoom().scaleExtent([0.2, 4]).on('zoom', ev => { g.attr('transform', ev.transform); });
    svg.call(zoom);

    // Toolbar: reset view + image export
    const toolbar = body.append('div').attr('class', 'diagram-toolbar');
    toolbar.append('button').attr('class', 'tool-btn').attr('type', 'button')
        .text('Reset view')
        .on('click', () => svg.transition().duration(300).call(zoom.transform, d3.zoomIdentity));
    const fileBase = (data.autoAttendantName || data.callQueueName || 'diagram').replace(/[^\w.-]+/g, '_');
    toolbar.append('button').attr('class', 'tool-btn').attr('type', 'button')
        .text('PNG').on('click', () => exportDiagram(svg.node(), fileBase, 'png'));
    toolbar.append('button').attr('class', 'tool-btn').attr('type', 'button')
        .text('SVG').on('click', () => exportDiagram(svg.node(), fileBase, 'svg'));

    // Edges: use dagre's routed points by default; fall back to a straight
    // center-to-center line for any node that has been dragged.
    const pathGen = d3.line().x(p => p.x).y(p => p.y).curve(d3.curveBasis);
    function edgeD(ed) {
        if (ed._dragged || !ed.points || ed.points.length < 2) {
            return pathGen([centerOf(ed.source), centerOf(ed.target)]);
        }
        return pathGen(ed.points);
    }
    function edgeMarker(ed) {
        return 'url(#arr' + (ed.style === 'error' ? '-err' : '') + '-' + prefix + '-' + index + ')';
    }

    const linkSel = g.append('g').selectAll('path')
        .data(edgeData).join('path')
        .attr('class', d => 'link ' + (d.style || 'solid'))
        .attr('marker-end', edgeMarker)
        .attr('d', edgeD);

    // DTMF / action link labels
    const linkLabelSel = g.append('g').selectAll('text')
        .data(edgeData).join('text').attr('class', 'link-label')
        .attr('x', d => (centerOf(d.source).x + centerOf(d.target).x) / 2)
        .attr('y', d => (centerOf(d.source).y + centerOf(d.target).y) / 2 - 6)
        .text(d => d.label || '');

    // Flow section labels on root→child edges
    const flowEdges = edgeData.filter(d => d.source === rootId && nodeById[d.target] && nodeById[d.target].subLabel);
    const flowLabelSel = g.append('g').selectAll('text')
        .data(flowEdges).join('text').attr('class', 'flow-label')
        .attr('x', d => centerOf(d.source).x + 22)
        .attr('y', d => (centerOf(d.source).y + centerOf(d.target).y) / 2 - 6)
        .text(d => {
            const sub = (nodeById[d.target].subLabel || '').split('\n')[0];
            return sub.length > 30 ? sub.substring(0, 28) + '...' : sub;
        });

    function refreshEdges(id) {
        linkSel.filter(e => e.source === id || e.target === id)
            .each(e => { e._dragged = true; })
            .attr('d', edgeD);
        linkLabelSel.filter(e => e.source === id || e.target === id)
            .attr('x', e => (centerOf(e.source).x + centerOf(e.target).x) / 2)
            .attr('y', e => (centerOf(e.source).y + centerOf(e.target).y) / 2 - 6);
        flowLabelSel.filter(e => e.source === id || e.target === id)
            .attr('x', e => centerOf(e.source).x + 22)
            .attr('y', e => (centerOf(e.source).y + centerOf(e.target).y) / 2 - 6);
    }

    // Drag to reposition. A press that doesn't move past a small threshold is
    // treated as a *click* (handled in 'end'), so cross-flow jumps still fire —
    // d3.drag otherwise swallows the trailing click as soon as the pointer
    // nudges even a pixel.
    const DRAG_THRESHOLD = 4;
    const drag = d3.drag()
        .on('start', function(event, d) {
            if (event.sourceEvent) event.sourceEvent.stopPropagation(); // don't pan the canvas
            d._sx = event.x; d._sy = event.y; d._moved = false;
            d3.select(this).raise();
        })
        .on('drag', function(event, d) {
            if (!d._moved && Math.hypot(event.x - d._sx, event.y - d._sy) <= DRAG_THRESHOLD) return;
            d._moved = true;
            d.x = event.x; d.y = event.y;
            d3.select(this).attr('transform', 'translate(' + d.x + ',' + d.y + ')');
            refreshEdges(d.data.id);
        })
        .on('end', function(event, d) {
            if (d._moved) return;                  // a real drag — not a click
            const dest = resolveJump(d.data);      // a click on a jump node — follow it
            if (dest) jumpTo(dest);
        });

    const node = g.append('g').selectAll('g')
        .data(nodeData).join('g')
        .attr('class', d => 'node node-type-' + (d.data.type || 'default'))
        .attr('transform', d => 'translate(' + d.x + ',' + d.y + ')')
        .on('mouseenter', showTooltip)
        .on('mousemove', showTooltip)
        .on('mouseleave', hideTooltip)
        .call(drag);

    node.append('circle').attr('r', d => d.r);

    node.append('text')
        .attr('dy', '0.32em')
        .attr('x', d => d.r + 5)
        .attr('text-anchor', 'start')
        .text(d => {
            const lbl = d.data.label || '';
            return lbl.length > 28 ? lbl.substring(0, 26) + '...' : lbl;
        });

    // Cross-flow jump styling. The click itself is handled in the drag 'end'
    // handler above (a no-move press), so it survives having drag attached.
    node.filter(d => resolveJump(d.data)).classed('has-jump', true);

    diagramRegistry.push({ card: card, nodeSel: node });
}

// ── Render all ──
aaData.forEach((aa, i) => renderDiagram(aa, i, 'aa', 'badge-aa', 'Auto Attendant'));
cqData.forEach((cq, i) => renderDiagram(cq, i, 'cq', 'badge-cq', 'Call Queue'));

// ── Smooth scroll for nav links ──
nav.on('click', 'a', function(event) {
    event.preventDefault();
    const target = document.querySelector(this.getAttribute('href'));
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
});

// ── Global node search ──
const searchInput = document.getElementById('search');
const searchCount = document.getElementById('search-count');

function nodeMatches(nd, q) {
    const hay = [nd.label, nd.subLabel, nd.type]
        .concat(Array.isArray(nd.detail) ? nd.detail : [])
        .join(' ').toLowerCase();
    return hay.indexOf(q) !== -1;
}

function runSearch() {
    const q = (searchInput.value || '').trim().toLowerCase();
    let total = 0, firstCard = null;
    diagramRegistry.forEach(reg => {
        reg.nodeSel.classed('search-match', false).classed('search-dim', false);
        if (!q) { reg.card.classed('search-hidden', false); return; }
        let cardMatches = 0;
        reg.nodeSel.each(function(d) {
            const m = nodeMatches(d.data, q);
            d3.select(this).classed('search-match', m).classed('search-dim', !m);
            if (m) cardMatches++;
        });
        total += cardMatches;
        reg.card.classed('search-hidden', cardMatches === 0);
        if (cardMatches > 0) {
            reg.card.classed('collapsed', false);
            if (!firstCard) firstCard = reg.card.node();
        }
    });
    searchCount.textContent = q ? (total + ' match' + (total === 1 ? '' : 'es')) : '';
    if (q && firstCard) firstCard.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

let searchTimer = null;
searchInput.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(runSearch, 180);
});
</script>
</body>
</html>
"@

    if ($OutputPath) {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        Write-Verbose "Report saved to: $OutputPath"
        return $OutputPath
    }

    return $html
}