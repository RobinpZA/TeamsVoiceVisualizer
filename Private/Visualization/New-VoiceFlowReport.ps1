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

    # Serialize graph data to JSON for embedding
    $aaJson = $AutoAttendantGraphs | ConvertTo-Json -Depth 10 -Compress
    $cqJson = $CallQueueGraphs | ConvertTo-Json -Depth 10 -Compress

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
</div>
<div class="container" id="container"></div>

<!-- D3.js v7 -->
<script src="https://d3js.org/d3.v7.min.js"></script>
<script>
"use strict";
const aaData = $aaJson;
const cqData = $cqJson;

const container = d3.select('#container');
const nav = d3.select('#nav');

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
    let html = '<strong>' + label + '</strong><br>' +
        '<span style="color:#8b949e">' + type + (sub ? ' &middot; ' + sub : '') + '</span>';
    if (nd.detail && Array.isArray(nd.detail) && nd.detail.length > 0) {
        html += '<div style="margin-top:6px;max-height:160px;overflow-y:auto;border-top:1px solid #30363d;padding-top:5px">';
        nd.detail.forEach(function(item) {
            html += '<div style="padding:1px 0;color:#e6edf3">' + item + '</div>';
        });
        html += '</div>';
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

    // ── Build tree from flat nodes/links ──
    const nodeMap = {};
    nodes.forEach(n => { nodeMap[n.id] = { id: n.id, label: n.label, type: n.type, subLabel: n.subLabel, detail: n.detail || null, _childIds: [] }; });
    const linkLabelMap = {}, linkStyleMap = {}, hasParent = new Set();
    links.forEach(l => {
        const src = (typeof l.source === 'object') ? l.source.id : l.source;
        const tgt = (typeof l.target === 'object') ? l.target.id : l.target;
        linkLabelMap[src + '->' + tgt] = l.label || '';
        linkStyleMap[src + '->' + tgt] = l.style || 'solid';
        if (nodeMap[src]) nodeMap[src]._childIds.push(tgt);
        hasParent.add(tgt);
    });
    const rootId = ((nodes.find(n => n.type === 'autoattendant' || n.type === 'callqueue'))
                  || (nodes.find(n => !hasParent.has(n.id)))
                  || nodes[0]).id;

    function toHierarchy(id, visited) {
        if (visited.has(id) || !nodeMap[id]) return null;
        visited.add(id);
        const n = nodeMap[id];
        const children = n._childIds.map(cid => toHierarchy(cid, new Set(visited))).filter(Boolean);
        return { id: n.id, label: n.label, type: n.type, subLabel: n.subLabel, detail: n.detail || null,
                 children: children.length ? children : undefined };
    }

    const hierData = toHierarchy(rootId, new Set());
    if (!hierData) {
        body.append('div').style('padding', '24px').style('color', '#8b949e').text('Could not build tree.');
        return;
    }

    const root = d3.hierarchy(hierData);
    d3.tree().nodeSize([60, 220])(root);

    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    root.each(d => {
        if (d.x < minX) minX = d.x;  if (d.x > maxX) maxX = d.x;
        if (d.y < minY) minY = d.y;  if (d.y > maxY) maxY = d.y;
    });
    const pad = 100;
    const vbX = minY - pad, vbY = minX - pad;
    const vbW = (maxY - minY) + pad * 2, vbH = (maxX - minX) + pad * 2;

    const svg = body.append('svg')
        .attr('viewBox', vbX + ' ' + vbY + ' ' + vbW + ' ' + vbH)
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
    svg.call(d3.zoom().scaleExtent([0.2, 4]).on('zoom', ev => { g.attr('transform', ev.transform); }));

    const linkHoriz = d3.linkHorizontal().x(d => d.y).y(d => d.x);

    g.append('g').selectAll('path')
        .data(root.links())
        .join('path')
        .attr('class', d => 'link ' + (linkStyleMap[d.source.data.id + '->' + d.target.data.id] || 'solid'))
        .attr('marker-end', d => {
            const s = linkStyleMap[d.source.data.id + '->' + d.target.data.id] || 'solid';
            return 'url(#arr' + (s === 'error' ? '-err' : '') + '-' + prefix + '-' + index + ')';
        })
        .attr('d', linkHoriz);

    // DTMF / action link labels
    g.append('g').selectAll('text')
        .data(root.links())
        .join('text').attr('class', 'link-label')
        .attr('x', d => (d.source.y + d.target.y) / 2)
        .attr('y', d => (d.source.x + d.target.x) / 2 - 6)
        .text(d => linkLabelMap[d.source.data.id + '->' + d.target.data.id] || '');

    // Flow section labels on root→child edges
    g.append('g').selectAll('text')
        .data(root.links().filter(d => d.source.data.id === rootId && d.target.data.subLabel))
        .join('text').attr('class', 'flow-label')
        .attr('x', d => d.source.y + 22)
        .attr('y', d => (d.source.x + d.target.x) / 2 - 6)
        .text(d => {
            const sub = (d.target.data.subLabel || '').split('\n')[0];
            return sub.length > 30 ? sub.substring(0, 28) + '...' : sub;
        });

    const node = g.append('g').selectAll('g')
        .data(root.descendants())
        .join('g')
        .attr('class', d => 'node node-type-' + (d.data.type || 'default'))
        .attr('transform', d => 'translate(' + d.y + ',' + d.x + ')')
        .on('mouseenter', showTooltip)
        .on('mousemove', showTooltip)
        .on('mouseleave', hideTooltip);

    node.append('circle')
        .attr('r', d => {
            switch (d.data.type) {
                case 'autoattendant': case 'callqueue': return 18;
                case 'greeting': case 'menu': case 'agentgroup': return 14;
                case 'conference_mode': case 'agent_alert': case 'presence_routing': return 6;
                default: return 12;
            }
        });

    node.append('text')
        .attr('dy', '0.32em')
        .attr('x', d => {
            const r = (d.data.type === 'autoattendant' || d.data.type === 'callqueue') ? 22 : 16;
            return d.children ? -r : r;
        })
        .attr('text-anchor', d => d.children ? 'end' : 'start')
        .text(d => {
            const lbl = d.data.label || '';
            return lbl.length > 28 ? lbl.substring(0, 26) + '...' : lbl;
        });
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