# Voice flow model (schemaVersion 1)

The contract between the PowerShell side and the report. `New-VoiceFlowModel`
turns the output of `Get-TeamsVoiceFlowData` into this shape; the report reads
nothing else. It describes the tenant, not a drawing: no labels are truncated,
no layout hints, and every real object appears exactly once.

```jsonc
{
  "schemaVersion": 1,
  "tenant":   { "name": "Contoso", "generatedAt": "2026-11-12T10:00:00+02:00" },
  "entities": { "<id>": { "id": "<id>", "kind": "<kind>", "name": "…", /* kind fields */ } },
  "edges":    [ { "id": "e0", "from": "<id>", "to": "<id>", "kind": "<edgeKind>", "label": "…", "via": { … } } ],
  "findings": [ { "id": "f0", "severity": "error|warning|info", "code": "…", "entityId": "<id>", "message": "…" } ]
}
```

## Ids

- Teams objects (AA, CQ, resource account, user, group): the object GUID, **lower-cased**.
- Phone numbers: `tel:+<E.164 digits>` (e.g. `tel:+27115550100`), for both `number` and `external`.
- Terminals that are not tenant objects: `sys:disconnect`, `sys:operator:<aaId>`, `sys:announcement`.

An id that a flow points at but that the tenant could not resolve still becomes an
entity (kind from the target type, `name` = the id, `unresolved: true`).

## Entity kinds

| kind | Extra fields |
|---|---|
| `number` | `number` (display string, e.g. `+27 11 555 0100` or raw E.164), `resourceAccountId` |
| `resourceAccount` | `upn`, `phoneNumbers: string[]` (E.164), `appType: "autoAttendant" \| "callQueue" \| null`, `configId: <aa/cq id> \| null` |
| `autoAttendant` | see below |
| `callQueue` | see below |
| `user` | `upn` |
| `group` | `isSharedVoicemail: bool` |
| `external` | `number` (E.164) |
| `system` | `systemType: "disconnect" \| "operator" \| "announcement"`; operator also has `targetRef` (the real operator entity id) |

### autoAttendant

```jsonc
{
  "id": "…", "kind": "autoAttendant", "name": "Main Reception",
  "language": "en-ZA",
  "timeZone": "South Africa Standard Time",   // Windows id, as Teams returns it
  "timeZoneIana": "Africa/Johannesburg",       // null if conversion failed
  "dialByName": true, "directorySearchMethod": "ByName",
  "voiceResponse": false,
  "operatorRef": "<entity id> | null",
  "resourceAccountIds": ["…"],
  "flows": [
    {
      "key": "default" | "afterHours" | "holiday:<scheduleId>",
      "label": "Business hours" | "After hours" | "Holiday: Christmas",
      "schedule": null
        | { "type": "weekly", "days": { "monday": [{ "start": "08:00", "end": "17:00" }], … } }
        | { "type": "fixed",  "ranges": [{ "start": "2026-12-25T00:00:00", "end": "2026-12-26T00:00:00" }] },
      "greetings": [ { "type": "tts" | "audio" | "silence", "text": "…", "audioFile": "…" } ],
      "menu": {
        "prompts": [ { "type": "tts" | "audio", "text": "…", "audioFile": "…" } ],
        "options": [
          {
            "key": "1" | "0" | "*" | "#" | "automatic",
            "voice": ["sales"],
            "action": "transfer" | "operator" | "disconnect" | "announcement",
            "targetRef": "<entity id>",
            "announcement": { "type": "tts" | "audio", "text": "…", "audioFile": "…" }  // only for announcement
          }
        ]
      }
    }
  ]
}
```

`afterHours` schedule semantics follow Teams: the weekly ranges are the **business
hours**; the after-hours flow applies outside them. `default` has `schedule: null`.
Holiday flows win over both while a fixed range is active.

A flow with no menu options is valid (greeting, then disconnect): `menu.options = []`.

### callQueue

```jsonc
{
  "id": "…", "kind": "callQueue", "name": "Sales",
  "language": "en-ZA",
  "routingMethod": "Attendant" | "Serial" | "RoundRobin" | "LongestIdle",
  "agentAlertSeconds": 30, "conferenceMode": true, "presenceBasedRouting": true,
  "allowOptOut": true, "slaSeconds": 30,
  "greeting": { "type": "tts" | "audio" | "none", "text": "…", "audioFile": "…" },
  "musicOnHold": { "type": "default" | "custom", "audioFile": "…" },
  "agentIds": ["<user id>"], "groupIds": ["<group id>"],
  "channel": { "id": "…", "ownerId": "…" } | null,
  "oboResourceAccountIds": ["…"],
  "resourceAccountIds": ["…"],
  "exceptions": {
    "overflow": { "threshold": 50,  "action": "disconnect" | "forward" | "voicemail" | "busy", "targetRef": "<id> | null" },
    "timeout":  { "threshold": 1200, "action": "…", "targetRef": "…" },
    "noAgent":  { "action": "queue" | "disconnect" | "forward" | "voicemail", "targetRef": "…" }
  }
}
```

## Edges

Entity-level edges, so the collapsed map can be drawn without reading flows.
One edge per distinct (from, to, kind, via); duplicates are dropped.

| kind | from → to | via |
|---|---|---|
| `dials` | number → resourceAccount | – |
| `fronts` | resourceAccount → autoAttendant / callQueue | – |
| `route` | autoAttendant → any target | `{ "flow": "<flow key>", "key": "<option key>" }` |
| `operator` | autoAttendant → operator target | – |
| `agent` | callQueue → user / group | – |
| `exception` | callQueue → target | `{ "exception": "overflow" \| "timeout" \| "noAgent" }` |
| `callerId` | callQueue → resourceAccount (OBO) | – |

Transfers to a resource account point at the **resource account**, not the AA/CQ
behind it; the `fronts` edge carries the hop. This keeps "two RAs front one AA"
and loops (AA → CQ → same AA) visible as shared nodes.

## Findings

Computed in PowerShell so they are testable. Codes:

| code | severity | when |
|---|---|---|
| `QUEUE_NO_AGENTS` | error | CQ with no agents, groups or channel |
| `RA_UNASSIGNED` | warning | resource account with a number but no `configId` |
| `RA_NO_NUMBER_ENTRY` | info | AA/CQ with no number reaching it through any path |
| `TARGET_UNRESOLVED` | warning | an edge targets an entity with `unresolved: true` |
| `FLOW_DEAD_END` | warning | AA flow with no menu options and no greeting |
| `SCHEDULE_UNREADABLE` | info | after-hours flow present but schedule could not be read |
