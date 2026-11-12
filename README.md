# TeamsVoiceVisualizer

PowerShell module that maps a Microsoft Teams tenant's phone system into **one interactive voice map**: every number, resource account, auto attendant and call queue on a single canvas, with a call simulator and a list of problems. The output is a single HTML file that works offline.

---

## What you get

| | |
|---|---|
| **Tenant map** | Numbers → resource accounts → auto attendants / call queues → users, groups, voicemail, external numbers. A target used in two places is one node, and loops (attendant → queue → back to the attendant) stay visible. |
| **Expand in place** | Click the chevron on an attendant to open its business-hours, after-hours and holiday flows, with one port per menu key. Open a queue to see greeting, hold music, routing, agents and overflow / timeout / no-agent paths. The layout re-flows around it. |
| **Focus** | Click any node to highlight everything upstream and downstream of it. The detail panel shows the full greeting text, menu table, schedule grid, agents and exceptions, and where it is reached from. |
| **Trace a call** | Pick a number and a date and time, then press keys on the keypad. The path animates through holiday / after-hours logic (in the attendant's own time zone) to where the call lands, and stops on loops. |
| **Findings** | Queues with no agents, numbers that go nowhere, unresolved transfer targets, dead-end flows, attendants or queues no number reaches, unreadable schedules. Click one to jump to it. |
| **Search and links** | `Ctrl+K` searches names, numbers, UPNs and greeting text, including people hidden inside queues. Every selection and trace is a shareable URL hash. |
| **Export** | PNG, SVG or the JSON model. |
| **Offline** | d3, ELK and fonts are embedded. No CDN, no network calls. |

---

## Requirements

- PowerShell 7.2+
- MicrosoftTeams module 6.0.0+, connected with a role that can read voice apps (Teams Administrator or Teams Communications Administrator)

## Usage

```powershell
Import-Module .\TeamsVoiceVisualizer\TeamsVoiceVisualizer.psd1
Connect-MicrosoftTeams

# Build the report and open it
Show-TeamsVoiceFlowReport

# Build it to a file only
Export-TeamsVoiceFlowReport -OutputPath 'C:\Reports\voice-map.html'

# Raw data for other tools
$data = Get-TeamsVoiceFlowData
```

Keyboard: `Ctrl+K` or `/` search · `T` trace · `F` fit · `Esc` close · `Enter` select a focused node.

## Commands

| Command | Description |
|---|---|
| `Get-TeamsVoiceFlowData` | Reads attendants, queues and resource accounts (with phone numbers) and resolves target names. Returns `TenantDisplayName`, `AutoAttendants`, `CallQueues`, `ResourceAccounts`, `GeneratedAt`. |
| `Show-TeamsVoiceFlowReport` | Builds the voice map, saves it (temp file or `-OutputPath`) and opens it. |
| `Export-TeamsVoiceFlowReport` | Same, without opening. `-OutputPath` required; supports `-WhatIf`. |

## How it works

```
Get-TeamsVoiceFlowData  →  New-VoiceFlowModel  →  New-VoiceFlowReport
   (Teams cmdlets)          (docs/model.md)        (Assets/portal inlined into one HTML)
```

- **Model** (`Private/Model/New-VoiceFlowModel.ps1`): describes the tenant, not a drawing. Its shape is specified in [`docs/model.md`](docs/model.md). Findings are computed here.
- **Portal** (`Assets/portal/`): vanilla JS, no build step. d3 renders, ELK lays out. `js/trace-engine.js` is the call simulator with no DOM dependencies.
- **Packaging** (`Private/Visualization/New-VoiceFlowReport.ps1`): inlines CSS, JS, fonts and the model. The model is embedded with HTML escaping, so tenant text such as a greeting containing `</script>` cannot break the page.

## Development

```powershell
.\build.ps1 -Task All     # PSScriptAnalyzer + Pester + manifest check
.\build.ps1 -Task Demo    # Output/demo.html from Tests/Fixtures/flowdata.json (no tenant needed)
```

```bash
node --test "Tests/js/**/*.test.cjs"   # trace engine tests
```

Open `Assets/portal/index.html` directly in a browser to work on the UI against `dev/model.sample.js`.

Third-party files and licences: [`Assets/vendor/NOTICE.md`](Assets/vendor/NOTICE.md).

## License

MIT, see [LICENSE](./LICENSE).
