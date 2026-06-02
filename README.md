# TeamsVoiceVisualizer

> **PowerShell module that generates interactive D3.js flow diagrams of Microsoft Teams Voice Auto Attendants and Call Queues.**

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Commands](#commands)
- [Module Structure](#module-structure)
- [Diagram Legend](#diagram-legend)

---

## Overview

TeamsVoiceVisualizer connects to Microsoft Teams, retrieves all Auto Attendants (AAs) and Call Queues (CQs), resolves every call target to a human-readable name, and generates a **single-page interactive HTML report** with zoomable D3.js directed graphs for each voice flow.

No server, no database, no external runtime — just PowerShell, the MicrosoftTeams module, and an HTML file.

---

## Features

| Area | Capabilities |
|------|-------------|
| **Auto Attendants** | Full call flow visualization: greeting → menu → DTMF options → targets (User, Resource Account, External PSTN, Operator, Disconnect, Announcement). Business hours, after-hours with schedule, and holiday flows. |
| **Call Queues** | Complete flow: greeting → music-on-hold → routing method → agent group (individuals, DLs, Teams channel) → overflow/timeout/no-agents exception paths. Conference mode, presence-based routing, OBO caller ID. |
| **Interactivity** | Zoom, pan, drag nodes. Hover tooltips show node details. Collapsible sections. Sticky navigation with smooth scroll. |
| **Dark Theme** | GitHub-dark inspired color scheme. Color-coded node types for instant recognition. |
| **Self-Contained** | Single HTML file with D3.js loaded from CDN. No build step, no dependencies beyond a browser. |

---

## Requirements

- **PowerShell 7.2+**
- **MicrosoftTeams module** >= 6.0.0 (with an active connection to your Teams tenant)
- Internet connection (D3.js is loaded from CDN when viewing the report)

---

## Installation

```powershell
# Clone the repository
git clone https://github.com/RobinpZA/TeamsVoiceVisualizer.git

# Import the module
Import-Module .\TeamsVoiceVisualizer\TeamsVoiceVisualizer.psd1
```

---

## Usage

### Quick Start

```powershell
# Connect to Teams first (or the module will prompt you)
Connect-MicrosoftTeams

# Generate and open the interactive report
Show-TeamsVoiceFlowReport
```

### Export to a Specific File

```powershell
Export-TeamsVoiceFlowReport -OutputPath 'C:\Reports\voice-flow.html'
```

### Get Raw Data for External Tools

```powershell
$data = Get-TeamsVoiceFlowData
$data.AutoAttendants | ConvertTo-Json -Depth 5 | Out-File 'aa-data.json'
$data.CallQueues | ConvertTo-Json -Depth 5 | Out-File 'cq-data.json'
```

---

## Commands

| Command | Description |
|---------|-------------|
| `Get-TeamsVoiceFlowData` | Retrieves all AA and CQ data as structured objects. Returns `PSCustomObject` with `AutoAttendants`, `CallQueues`, `TenantDisplayName`, and `GeneratedAt`. |
| `Show-TeamsVoiceFlowReport` | Fetches data, generates the interactive D3.js HTML report, saves to a temp file, and opens it in the default browser. Use `-OutputPath` to specify a custom location. |
| `Export-TeamsVoiceFlowReport` | Same as `Show-*` but does not open the browser. Requires `-OutputPath`. Supports `-WhatIf`/`-Confirm`. |

---

## Module Structure

```
TeamsVoiceVisualizer/
├── Private/
│   ├── Helpers/
│   │   ├── Connect-TeamsVoiceSession.ps1       # Auth + connection
│   │   └── Resolve-VoiceTargetName.ps1          # GUID/phone → display name resolution
│   ├── Data/
│   │   ├── Get-VoiceAutoAttendantData.ps1       # Fetch + enrich AA data
│   │   └── Get-VoiceCallQueueData.ps1           # Fetch + enrich CQ data
│   └── Visualization/
│       ├── New-AAGraphData.ps1                  # AA → D3 nodes/links
│       ├── New-CQGraphData.ps1                  # CQ → D3 nodes/links
│       └── New-VoiceFlowReport.ps1              # Assemble full HTML report
├── Public/
│   ├── Get-TeamsVoiceFlowData.ps1
│   ├── Show-TeamsVoiceFlowReport.ps1
│   └── Export-TeamsVoiceFlowReport.ps1
├── Tests/
│   └── TeamsVoiceVisualizer.Tests.ps1
├── TeamsVoiceVisualizer.psd1                    # Module manifest
├── TeamsVoiceVisualizer.psm1                    # Module loader
├── build.ps1                                    # Analyze / Test / Build
├── PSScriptAnalyzerSettings.psd1
└── README.md
```

---

## Diagram Legend

| Color | Node Type | Description |
|-------|-----------|-------------|
| 🔵 Blue | Auto Attendant | The AA itself and operator targets |
| 🟢 Green | Call Queue / Agent Group | CQs and agent collections |
| 🟣 Purple | Menu / Music on Hold | Menu prompts and queue hold music |
| 🩶 Gray | Greeting / Endpoint | Greeting nodes and flow endpoints |
| 🔵 Cyan | User / Agent | Individual user targets |
| 🩷 Pink | Resource Account | Application endpoints and OBO RAs |
| 🟠 Orange | External PSTN / Exception | Phone numbers and exception flows |
| 🔴 Red | Disconnect | Call termination |

---

## Contributing

1. Run `.\build.ps1 -Task Analyze` to check code quality.
2. Run `.\build.ps1 -Task Test` to execute Pester tests.
3. Run `.\build.ps1 -Task All` for the full validation pipeline.

---

## License

MIT — see [LICENSE](./LICENSE) for details.