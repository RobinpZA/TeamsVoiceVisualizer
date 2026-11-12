function New-VoiceFlowModel {
    <#
    .SYNOPSIS
        Turns Get-TeamsVoiceFlowData output into the voice flow model (docs/model.md).
    .DESCRIPTION
        Builds entities, edges and findings. The model describes the tenant, not a
        drawing: nothing is truncated and every real object appears exactly once.
    .PARAMETER FlowData
        The object returned by Get-TeamsVoiceFlowData (or its JSON round-trip).
    .EXAMPLE
        $model = New-VoiceFlowModel -FlowData (Get-TeamsVoiceFlowData)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        $FlowData
    )

    $ctx = @{
        Entities = [ordered]@{}
        Edges    = [System.Collections.Generic.List[object]]::new()
        EdgeKeys = [System.Collections.Generic.HashSet[string]]::new()
    }

    $appTypes = @{
        'ce933385-9390-45d1-9512-c8d228074e07' = 'autoAttendant'
        '11cd3e2e-fccb-42ad-ad00-878b93575e07' = 'callQueue'
    }

    $aaList = @(ConvertTo-VoiceModelArray $FlowData.AutoAttendants)
    $cqList = @(ConvertTo-VoiceModelArray $FlowData.CallQueues)
    $raList = @(ConvertTo-VoiceModelArray $FlowData.ResourceAccounts)

    # ── Resource accounts and their numbers ──
    foreach ($ra in $raList) {
        $raId = ConvertTo-VoiceModelId $ra.id
        if (-not $raId) { continue }
        $tel = ConvertTo-VoiceModelTel $ra.phoneNumber
        $appType = $null
        if ($ra.applicationId) { $appType = $appTypes[([string]$ra.applicationId).ToLowerInvariant()] }
        $name = Get-VoiceModelText $ra.name
        $null = Add-VoiceModelEntity -Ctx $ctx -Entity ([ordered]@{
            id           = $raId
            kind         = 'resourceAccount'
            name         = if ($name) { $name } else { $raId }
            upn          = Get-VoiceModelText $ra.upn
            phoneNumbers = @(if ($tel) { $tel -replace '^tel:', '' })
            appType      = $appType
            configId     = ConvertTo-VoiceModelId $ra.configId
        })
    }
    foreach ($ra in $raList) {
        $raId = ConvertTo-VoiceModelId $ra.id
        $tel = ConvertTo-VoiceModelTel $ra.phoneNumber
        if (-not $raId -or -not $tel) { continue }
        $null = Add-VoiceModelEntity -Ctx $ctx -Entity ([ordered]@{
            id                = $tel
            kind              = 'number'
            number            = $tel -replace '^tel:', ''
            name              = $tel -replace '^tel:', ''
            resourceAccountId = $raId
        })
        Add-VoiceModelEdge -Ctx $ctx -From $tel -To $raId -Kind 'dials' -Label 'Dials'
    }

    # ── Pass 1: AA / CQ skeletons, so targets can resolve to them ──
    foreach ($aa in $aaList) {
        $aaId = ConvertTo-VoiceModelId $aa.id
        if (-not $aaId) { continue }
        $tzIana = Get-VoiceModelText $aa.timeZoneIana
        if (-not $tzIana -and $aa.timeZone) {
            try {
                $out = $null
                if ([System.TimeZoneInfo]::TryConvertWindowsIdToIanaId([string]$aa.timeZone, [ref]$out)) { $tzIana = $out }
            } catch {
                Write-Verbose "VoiceFlowModel: time zone conversion failed for '$($aa.timeZone)': $_"
            }
        }
        $null = Add-VoiceModelEntity -Ctx $ctx -Entity ([ordered]@{
            id                    = $aaId
            kind                  = 'autoAttendant'
            name                  = [string]$aa.name
            language              = Get-VoiceModelText $aa.language
            timeZone              = Get-VoiceModelText $aa.timeZone
            timeZoneIana          = $tzIana
            dialByName            = [bool]$aa.dialByNameEnabled
            directorySearchMethod = Get-VoiceModelText $aa.directorySearchMethod
            voiceResponse         = [bool]$aa.voiceResponseEnabled
            operatorRef           = $null
            resourceAccountIds    = @(ConvertTo-VoiceModelArray $aa.associatedResourceAccounts | ForEach-Object { ConvertTo-VoiceModelId $_ })
            flows                 = @()
        })
    }
    foreach ($cq in $cqList) {
        $cqId = ConvertTo-VoiceModelId $cq.id
        if (-not $cqId) { continue }
        $welcome = Get-VoiceModelText $cq.welcomeTtsPrompt
        $greeting = [ordered]@{ type = 'none'; text = $null; audioFile = $null }
        if ($welcome) {
            $greeting.type = 'tts'
            $greeting.text = $welcome
        } elseif ($cq.welcomeMusicAudioFileId) {
            $greeting.type = 'audio'
            $greeting.audioFile = [string]$cq.welcomeMusicAudioFileId
        }
        $moh = [ordered]@{ type = 'default'; audioFile = $null }
        if ($null -ne $cq.useDefaultMusicOnHold -and -not [bool]$cq.useDefaultMusicOnHold) {
            $moh.type = 'custom'
            $moh.audioFile = Get-VoiceModelText $cq.musicOnHoldAudioFileId
        }
        $channel = $null
        if ($cq.channelId) {
            $channel = [ordered]@{ id = [string]$cq.channelId; ownerId = ConvertTo-VoiceModelId $cq.channelUserObjectId }
        }
        $null = Add-VoiceModelEntity -Ctx $ctx -Entity ([ordered]@{
            id                    = $cqId
            kind                  = 'callQueue'
            name                  = [string]$cq.name
            language              = Get-VoiceModelText $cq.languageId
            routingMethod         = Get-VoiceModelText $cq.routingMethod
            agentAlertSeconds     = $cq.agentAlertTimeSeconds
            conferenceMode        = [bool]$cq.conferenceMode
            presenceBasedRouting  = [bool]$cq.presenceBasedRouting
            allowOptOut           = [bool]$cq.allowOptOut
            slaSeconds            = $cq.serviceLevelThresholdSeconds
            greeting              = $greeting
            musicOnHold           = $moh
            agentIds              = @()
            groupIds              = @()
            channel               = $channel
            oboResourceAccountIds = @()
            resourceAccountIds    = @(ConvertTo-VoiceModelArray $cq.associatedResourceAccounts | ForEach-Object { ConvertTo-VoiceModelId $_ })
            exceptions            = [ordered]@{ overflow = $null; timeout = $null; noAgent = $null }
        })
    }

    # ── Pass 2: Auto Attendants ──
    foreach ($aa in $aaList) {
        $aaId = ConvertTo-VoiceModelId $aa.id
        if (-not $aaId) { continue }
        $entity = $ctx.Entities[$aaId]

        if ($aa.operatorId -or $aa.operatorType) {
            $opRef = Resolve-VoiceModelTarget -Ctx $ctx -Type ([string]$aa.operatorType) -Id ([string]$aa.operatorId) -Name $aa.operatorName
            if ($opRef) {
                $entity.operatorRef = $opRef
                Add-VoiceModelEdge -Ctx $ctx -From $aaId -To $opRef -Kind 'operator' -Label 'Operator'
            }
        }

        $flows = [System.Collections.Generic.List[object]]::new()
        $flows.Add((New-VoiceModelFlow -Ctx $ctx -AaId $aaId -AaEntity $entity -Key 'default' -Label 'Business hours' -Schedule $null -Flow $aa.defaultCallFlow))

        if ($aa.afterHoursCallFlow) {
            $flows.Add((New-VoiceModelFlow -Ctx $ctx -AaId $aaId -AaEntity $entity -Key 'afterHours' -Label 'After hours' `
                -Schedule (New-VoiceModelWeeklySchedule $aa.afterHoursSchedule) -Flow $aa.afterHoursCallFlow))
        }
        foreach ($h in (ConvertTo-VoiceModelArray $aa.holidayFlows)) {
            $label = if ($h.scheduleName) { "Holiday: $($h.scheduleName)" } else { 'Holiday' }
            $ranges = @(ConvertTo-VoiceModelArray $h.dateRanges | ForEach-Object {
                [ordered]@{ start = ConvertTo-VoiceModelDateText $_.start; end = ConvertTo-VoiceModelDateText $_.end }
            })
            $flows.Add((New-VoiceModelFlow -Ctx $ctx -AaId $aaId -AaEntity $entity -Key "holiday:$(ConvertTo-VoiceModelId $h.scheduleId)" -Label $label `
                -Schedule ([ordered]@{ type = 'fixed'; ranges = $ranges }) -Flow $h.callFlow))
        }
        $entity.flows = $flows.ToArray()
    }

    # ── Pass 2: Call Queues ──
    foreach ($cq in $cqList) {
        $cqId = ConvertTo-VoiceModelId $cq.id
        if (-not $cqId) { continue }
        $entity = $ctx.Entities[$cqId]

        $agentIds = @(ConvertTo-VoiceModelArray $cq.agentIds)
        $agentNames = @(ConvertTo-VoiceModelArray $cq.agentNames)
        $agents = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $agentIds.Count; $i++) {
            $name = if ($i -lt $agentNames.Count) { $agentNames[$i] } else { $null }
            $ref = Resolve-VoiceModelTarget -Ctx $ctx -Type 'User' -Id ([string]$agentIds[$i]) -Name $name
            if ($ref -and -not $agents.Contains($ref)) { $agents.Add($ref) }
            if ($ref) { Add-VoiceModelEdge -Ctx $ctx -From $cqId -To $ref -Kind 'agent' -Label 'Agent' }
        }
        $entity.agentIds = $agents.ToArray()

        $dlIds = @(ConvertTo-VoiceModelArray $cq.distributionListIds)
        $dlNames = @(ConvertTo-VoiceModelArray $cq.distributionListNames)
        $groups = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $dlIds.Count; $i++) {
            $name = if ($i -lt $dlNames.Count) { $dlNames[$i] } else { $null }
            $ref = Resolve-VoiceModelTarget -Ctx $ctx -Type 'Group' -Id ([string]$dlIds[$i]) -Name $name
            if ($ref -and -not $groups.Contains($ref)) { $groups.Add($ref) }
            if ($ref) { Add-VoiceModelEdge -Ctx $ctx -From $cqId -To $ref -Kind 'agent' -Label 'Group' }
        }
        $entity.groupIds = $groups.ToArray()

        $oboIds = @(ConvertTo-VoiceModelArray $cq.oboResourceAccountIds)
        $oboNames = @(ConvertTo-VoiceModelArray $cq.oboResourceAccountNames)
        $obo = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $oboIds.Count; $i++) {
            $name = if ($i -lt $oboNames.Count) { $oboNames[$i] } else { $null }
            $ref = Resolve-VoiceModelTarget -Ctx $ctx -Type 'ApplicationEndpoint' -Id ([string]$oboIds[$i]) -Name $name
            if ($ref -and -not $obo.Contains($ref)) { $obo.Add($ref) }
            if ($ref) { Add-VoiceModelEdge -Ctx $ctx -From $cqId -To $ref -Kind 'callerId' -Label 'Caller ID' }
        }
        $entity.oboResourceAccountIds = $obo.ToArray()

        $exceptionDefs = @(
            @{ Name = 'overflow'; Label = 'Overflow'; Threshold = $cq.overflowThreshold;       Action = $cq.overflowAction; TType = $cq.overflowActionTargetType; TId = $cq.overflowActionTargetId; TName = $cq.overflowActionTargetName }
            @{ Name = 'timeout';  Label = 'Timeout';  Threshold = $cq.timeoutThresholdSeconds; Action = $cq.timeoutAction;  TType = $cq.timeoutActionTargetType;  TId = $cq.timeoutActionTargetId;  TName = $cq.timeoutActionTargetName }
            @{ Name = 'noAgent';  Label = 'No agent'; Threshold = $null;                       Action = $cq.noAgentAction;  TType = $cq.noAgentActionTargetType;  TId = $cq.noAgentActionTargetId;  TName = $cq.noAgentActionTargetName }
        )
        foreach ($def in $exceptionDefs) {
            $action = ConvertTo-VoiceModelCqAction $def.Action
            if (-not $action) { continue }
            $targetRef = $null
            if ($def.TId) {
                $targetRef = Resolve-VoiceModelTarget -Ctx $ctx -Type ([string]$def.TType) -Id ([string]$def.TId) -Name $def.TName
            }
            $ex = [ordered]@{}
            if ($def.Name -ne 'noAgent') { $ex.threshold = $def.Threshold }
            $ex.action = $action
            $ex.targetRef = $targetRef
            $entity.exceptions[$def.Name] = $ex
            if ($targetRef) {
                Add-VoiceModelEdge -Ctx $ctx -From $cqId -To $targetRef -Kind 'exception' -Label $def.Label -Via ([ordered]@{ exception = $def.Name })
            }
        }
    }

    # ── fronts edges + RA backfill ──
    foreach ($owner in @($ctx.Entities.Values | Where-Object { $_.kind -in 'autoAttendant', 'callQueue' -and -not $_.unresolved })) {
        $ownerAppType = if ($owner.kind -eq 'autoAttendant') { 'autoAttendant' } else { 'callQueue' }
        $raIds = [System.Collections.Generic.List[string]]::new()
        foreach ($rid in $owner.resourceAccountIds) {
            if ($rid -and -not $raIds.Contains($rid)) { $raIds.Add($rid) }
        }
        # Accounts that name this owner as their configuration (association seen only from the RA side)
        foreach ($e in @($ctx.Entities.Values | Where-Object { $_.kind -eq 'resourceAccount' -and $_.configId -eq $owner.id })) {
            if (-not $raIds.Contains($e.id)) { $raIds.Add($e.id) }
        }
        $owner.resourceAccountIds = $raIds.ToArray()
        foreach ($rid in $raIds) {
            $ra = Resolve-VoiceModelTarget -Ctx $ctx -Type 'ApplicationEndpoint' -Id $rid -Name $null
            $raEntity = $ctx.Entities[$ra]
            if (-not $raEntity.configId) { $raEntity.configId = $owner.id }
            if (-not $raEntity.appType) { $raEntity.appType = $ownerAppType }
            Add-VoiceModelEdge -Ctx $ctx -From $ra -To $owner.id -Kind 'fronts' -Label 'Fronts'
        }
    }

    $edges = $ctx.Edges.ToArray()
    # @() matters: a single finding would otherwise unwrap to one object and
    # serialise as {...}, which the report cannot iterate.
    $findings = @(Get-VoiceModelFinding -Entities $ctx.Entities -Edges $edges -FlowData $FlowData)

    return [ordered]@{
        schemaVersion = 1
        tenant        = [ordered]@{
            name        = Get-VoiceModelText $FlowData.TenantDisplayName
            generatedAt = ConvertTo-VoiceModelDateText $FlowData.GeneratedAt
        }
        entities      = $ctx.Entities
        edges         = $edges
        findings      = $findings
    }
}

function ConvertTo-VoiceModelArray {
    # Null-safe array coercion: $null -> nothing, scalar -> the scalar. Callers wrap the call in @().
    param($Value)
    if ($null -eq $Value) { return }
    return @($Value)
}

function Get-VoiceModelText {
    # First non-empty string of a value that may be a scalar or an array (or $null).
    param($Value)
    foreach ($v in @($Value)) {
        if ($null -ne $v -and "$v" -ne '') { return [string]$v }
    }
    return $null
}

function ConvertTo-VoiceModelId {
    param($Value)
    $s = Get-VoiceModelText $Value
    if (-not $s) { return $null }
    return $s.Trim().ToLowerInvariant()
}

function ConvertTo-VoiceModelTel {
    # 'tel:+27115550100;ext=1' / '+27 11 555 0100' -> 'tel:+27115550100'; $null when no digits.
    param($Value)
    $s = Get-VoiceModelText $Value
    if (-not $s) { return $null }
    $s = ($s -replace '^tel:', '') -replace ';.*$', ''
    $digits = $s -replace '[^\d]', ''
    if (-not $digits) { return $null }
    return "tel:+$digits"
}

function ConvertTo-VoiceModelDateText {
    # ConvertFrom-Json turns ISO strings into DateTime; keep ISO text either way.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToString('s') }
    return [string]$Value
}

function ConvertTo-VoiceModelTimeText {
    # TimeSpan / '08:00:00' -> '08:00'
    param($Value)
    if ($null -eq $Value) { return $null }
    $ts = [timespan]::Zero
    if ($Value -is [timespan]) { $ts = $Value } elseif (-not [timespan]::TryParse([string]$Value, [ref]$ts)) { return [string]$Value }
    $hours = [int][math]::Floor($ts.TotalHours)
    return ('{0:00}:{1:00}' -f $hours, $ts.Minutes)
}

function ConvertTo-VoiceModelDtmfKey {
    param($Value)
    $s = (Get-VoiceModelText $Value)
    if (-not $s) { return 'automatic' }
    switch -Regex ($s.Trim()) {
        '^Tone(\d)$'                   { return $Matches[1] }
        '^(ToneStar|Star|\*)$'         { return '*' }
        '^(TonePound|Pound|Hash|#)$'   { return '#' }
        '^Automatic$'                  { return 'automatic' }
        '^\d$'                         { return $s.Trim() }
        default                        { return $s.Trim().ToLowerInvariant() }
    }
}

function ConvertTo-VoiceModelCqAction {
    param($Value)
    $s = Get-VoiceModelText $Value
    if (-not $s) { return $null }
    switch -Regex ($s.Trim()) {
        '^Disconnect$'                      { return 'disconnect' }
        '^DisconnectWithBusy$'              { return 'busy' }
        '^(SharedVoicemail|Voicemail)$'     { return 'voicemail' }
        '^(Forward|Redirect)$'              { return 'forward' }
        '^Queue$'                           { return 'queue' }
        default                             { return $s.Trim().ToLowerInvariant() }
    }
}

function ConvertTo-VoiceModelPrompt {
    param($Prompt)
    if ($null -eq $Prompt) { return $null }
    $type = Get-VoiceModelText $Prompt.type
    return [ordered]@{
        type      = if ($type) { $type.ToLowerInvariant() } else { 'silence' }
        text      = Get-VoiceModelText $Prompt.text
        audioFile = Get-VoiceModelText $Prompt.audioFile
    }
}

function New-VoiceModelWeeklySchedule {
    param($Schedule)
    if ($null -eq $Schedule) { return $null }
    $days = [ordered]@{}
    foreach ($day in 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday') {
        $days[$day] = @(ConvertTo-VoiceModelArray $Schedule.$day | ForEach-Object {
            [ordered]@{ start = ConvertTo-VoiceModelTimeText $_.start; end = ConvertTo-VoiceModelTimeText $_.end }
        })
    }
    return [ordered]@{ type = 'weekly'; days = $days }
}

function Add-VoiceModelEntity {
    # Adds the entity unless the id exists already (first writer wins). Returns the id.
    param(
        [Parameter(Mandatory)][hashtable]$Ctx,
        [Parameter(Mandatory)]$Entity
    )
    if (-not $Ctx.Entities.Contains($Entity.id)) { $Ctx.Entities[$Entity.id] = $Entity }
    return $Entity.id
}

function Add-VoiceModelEdge {
    param(
        [Parameter(Mandatory)][hashtable]$Ctx,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][string]$Kind,
        [string]$Label,
        $Via = $null
    )
    $viaKey = if ($Via) { (@($Via.Keys | ForEach-Object { "$_=$($Via[$_])" })) -join ',' } else { '' }
    if (-not $Ctx.EdgeKeys.Add("$From|$To|$Kind|$viaKey")) { return }
    $edge = [ordered]@{
        id    = "e$($Ctx.Edges.Count)"
        from  = $From
        to    = $To
        kind  = $Kind
        label = $Label
    }
    if ($Via) { $edge.via = $Via }
    $Ctx.Edges.Add($edge)
}

function Get-VoiceModelSystemEntity {
    # Returns the id of a sys:* terminal, creating it on first use.
    param(
        [Parameter(Mandatory)][hashtable]$Ctx,
        [Parameter(Mandatory)][ValidateSet('disconnect', 'announcement', 'operator')][string]$Type,
        [string]$AaId,
        [string]$OperatorRef
    )
    $id = if ($Type -eq 'operator') { "sys:operator:$AaId" } else { "sys:$Type" }
    if (-not $Ctx.Entities.Contains($id)) {
        $entity = [ordered]@{
            id         = $id
            kind       = 'system'
            name       = (Get-Culture).TextInfo.ToTitleCase($Type)
            systemType = $Type
        }
        if ($Type -eq 'operator') { $entity.targetRef = $OperatorRef }
        $Ctx.Entities[$id] = $entity
    }
    return $id
}

function Resolve-VoiceModelTarget {
    # Maps a Teams call target (type + id + known name) to an entity id, creating the entity
    # (or an unresolved placeholder) when it does not exist yet.
    param(
        [Parameter(Mandatory)][hashtable]$Ctx,
        [string]$Type,
        [string]$Id,
        $Name
    )
    if (-not $Id) { return $null }

    $isPhone = $Type -in 'ExternalPstn', 'Phone', 'Tel' -or $Id -match '^(tel:)?\+\d'
    if ($isPhone) {
        $tel = ConvertTo-VoiceModelTel $Id
        if ($tel) {
            if (-not $Ctx.Entities.Contains($tel)) {
                $null = Add-VoiceModelEntity -Ctx $Ctx -Entity ([ordered]@{
                    id     = $tel
                    kind   = 'external'
                    name   = $tel -replace '^tel:', ''
                    number = $tel -replace '^tel:', ''
                })
            }
            return $tel
        }
    }

    $key = $Id.Trim().ToLowerInvariant()
    $nameText = Get-VoiceModelText $Name
    $hasName = [bool]$nameText -and ($nameText.Trim().ToLowerInvariant() -ne $key)

    if ($Ctx.Entities.Contains($key)) {
        $existing = $Ctx.Entities[$key]
        # A later reference may carry a display name for a user/group placeholder.
        # Never "resolve" an AA/CQ placeholder this way: a name alone doesn't make
        # a missing attendant or queue real (it would gain no flows/agents).
        if ($existing.unresolved -and $hasName -and $existing.kind -in @('user', 'group')) {
            $existing.name = $nameText
            $existing.Remove('unresolved')
        }
        return $key
    }

    $entity = [ordered]@{ id = $key; kind = $null; name = if ($hasName) { $nameText } else { $key } }
    $known = $true
    switch ($Type) {
        'User'                        { $entity.kind = 'user'; $entity.upn = $null }
        'ApplicationEndpoint'         { $entity.kind = 'resourceAccount'; $entity.upn = $null; $entity.phoneNumbers = @(); $entity.appType = $null; $entity.configId = $null }
        'SharedVoicemail'             { $entity.kind = 'group'; $entity.isSharedVoicemail = $true }
        'Group'                       { $entity.kind = 'group'; $entity.isSharedVoicemail = $false }
        'HuntGroup'                   { $entity.kind = 'callQueue' }
        'OrganizationalAutoAttendant' { $entity.kind = 'autoAttendant' }
        default                       { $entity.kind = 'group'; $entity.isSharedVoicemail = $false; $known = $false }
    }
    if (-not $hasName -or -not $known -or $entity.kind -in 'callQueue', 'autoAttendant') {
        # AA/CQ targets are only resolved when the tenant listed them (they exist already if so).
        $entity.unresolved = $true
    }
    $null = Add-VoiceModelEntity -Ctx $Ctx -Entity $entity
    return $key
}

function New-VoiceModelFlow {
    param(
        [Parameter(Mandatory)][hashtable]$Ctx,
        [Parameter(Mandatory)][string]$AaId,
        [Parameter(Mandatory)]$AaEntity,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Label,
        $Schedule,
        $Flow
    )

    $greetings = @()
    $prompts = @()
    $options = [System.Collections.Generic.List[object]]::new()

    if ($Flow) {
        if ($null -ne $Flow.greetings) {
            $greetings = @(ConvertTo-VoiceModelArray $Flow.greetings | ForEach-Object { ConvertTo-VoiceModelPrompt $_ })
        } elseif ($Flow.greetingType -and $Flow.greetingType -ne 'None') {
            # FlowData from before the greetings field existed
            $greetings = @(ConvertTo-VoiceModelPrompt @{
                type      = switch ($Flow.greetingType) { 'TextToSpeech' { 'tts' } 'AudioFile' { 'audio' } default { 'silence' } }
                text      = $Flow.greetingText
                audioFile = $Flow.greetingAudio
            })
        }
        if ($null -ne $Flow.menuPrompts) {
            $prompts = @(ConvertTo-VoiceModelArray $Flow.menuPrompts | ForEach-Object { ConvertTo-VoiceModelPrompt $_ } | Where-Object { $_.type -ne 'silence' })
        } elseif ($Flow.menuPromptText) {
            $prompts = @(ConvertTo-VoiceModelPrompt @{ type = 'tts'; text = $Flow.menuPromptText })
        }

        foreach ($opt in (ConvertTo-VoiceModelArray $Flow.menuOptions)) {
            $keyName = ConvertTo-VoiceModelDtmfKey $opt.dtmfResponse
            $action = $null
            $targetRef = $null
            $targetText = if ($opt.targetId) { $true } else { $false }
            switch -Regex ([string]$opt.action) {
                '^(TransferCallToTarget|TransferToTarget)$' { $action = 'transfer' }
                '^(TransferCallToOperator|TransferToOperator)$' { $action = 'operator' }
                '^(DisconnectCall|Disconnect)$' { $action = 'disconnect' }
                '^Announcement$' { $action = 'announcement' }
                default { if ($targetText) { $action = 'transfer' } }
            }
            if (-not $action) { continue }

            switch ($action) {
                'transfer' {
                    $targetRef = Resolve-VoiceModelTarget -Ctx $Ctx -Type ([string]$opt.targetType) -Id ([string]$opt.targetId) -Name $opt.targetName
                }
                'operator' {
                    $targetRef = Get-VoiceModelSystemEntity -Ctx $Ctx -Type operator -AaId $AaId -OperatorRef $AaEntity.operatorRef
                }
                'disconnect' { $targetRef = Get-VoiceModelSystemEntity -Ctx $Ctx -Type disconnect }
                'announcement' { $targetRef = Get-VoiceModelSystemEntity -Ctx $Ctx -Type announcement }
            }

            $o = [ordered]@{
                key       = $keyName
                voice     = @(ConvertTo-VoiceModelArray $opt.voiceResponses | ForEach-Object { [string]$_ })
                action    = $action
                targetRef = $targetRef
            }
            if ($action -eq 'announcement') { $o.announcement = ConvertTo-VoiceModelPrompt $opt.prompt }
            $options.Add($o)

            if ($targetRef) {
                Add-VoiceModelEdge -Ctx $Ctx -From $AaId -To $targetRef -Kind 'route' -Label "${Label}: $keyName" `
                    -Via ([ordered]@{ flow = $Key; key = $keyName })
            }
        }
    }

    return [ordered]@{
        key       = $Key
        label     = $Label
        schedule  = $Schedule
        greetings = $greetings
        menu      = [ordered]@{ prompts = $prompts; options = $options.ToArray() }
    }
}

function Get-VoiceModelFinding {
    param(
        [Parameter(Mandatory)]$Entities,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Edges,
        [Parameter(Mandatory)]$FlowData
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($Severity, $Code, $EntityId, $Message)
        $findings.Add([ordered]@{
            id       = "f$($findings.Count)"
            severity = $Severity
            code     = $Code
            entityId = $EntityId
            message  = $Message
        })
    }

    $aaFlowData = @{}
    foreach ($aa in (ConvertTo-VoiceModelArray $FlowData.AutoAttendants)) {
        $aaFlowData[(ConvertTo-VoiceModelId $aa.id)] = $aa
    }

    foreach ($e in $Entities.Values) {
        switch ($e.kind) {
            'callQueue' {
                if (-not $e.unresolved -and $e.agentIds.Count -eq 0 -and $e.groupIds.Count -eq 0 -and -not $e.channel) {
                    & $add 'error' 'QUEUE_NO_AGENTS' $e.id "Call queue '$($e.name)' has no agents, groups or channel."
                }
            }
            'resourceAccount' {
                if (-not $e.unresolved -and $e.phoneNumbers.Count -gt 0 -and -not $e.configId) {
                    & $add 'warning' 'RA_UNASSIGNED' $e.id "Resource account '$($e.name)' has a phone number but is not assigned to an auto attendant or call queue."
                }
            }
            'autoAttendant' {
                if ($e.unresolved) { continue }
                foreach ($flow in $e.flows) {
                    $hasGreeting = @($flow.greetings | Where-Object { $_.type -ne 'silence' }).Count -gt 0
                    if ($flow.menu.options.Count -eq 0 -and -not $hasGreeting) {
                        & $add 'warning' 'FLOW_DEAD_END' $e.id "Auto attendant '$($e.name)' flow '$($flow.label)' has no greeting and no menu options."
                    }
                }
                $afterHours = @($e.flows | Where-Object { $_.key -eq 'afterHours' })
                $src = $aaFlowData[$e.id]
                if ($afterHours.Count -gt 0 -and ($null -eq $afterHours[0].schedule -or ($src -and $src.afterHoursScheduleError -eq $true))) {
                    & $add 'info' 'SCHEDULE_UNREADABLE' $e.id "The after-hours schedule of '$($e.name)' could not be read."
                }
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($edge in $Edges) {
        $target = $Entities[$edge.to]
        if ($target -and $target.unresolved -and $seen.Add("$($edge.from)|$($edge.to)")) {
            $from = $Entities[$edge.from]
            & $add 'warning' 'TARGET_UNRESOLVED' $edge.from "'$($from.name)' points at '$($target.id)', which could not be resolved."
        }
    }

    # Entry reachability: BFS from every tenant number along the call-routing edges.
    $routing = 'dials', 'fronts', 'route', 'exception', 'operator'
    $adjacent = @{}
    foreach ($edge in $Edges) {
        if ($edge.kind -notin $routing) { continue }
        if (-not $adjacent.ContainsKey($edge.from)) { $adjacent[$edge.from] = [System.Collections.Generic.List[string]]::new() }
        $adjacent[$edge.from].Add($edge.to)
    }
    $reached = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($e in $Entities.Values) {
        if ($e.kind -eq 'number' -and $reached.Add($e.id)) { $queue.Enqueue($e.id) }
    }
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        if (-not $adjacent.ContainsKey($cur)) { continue }
        foreach ($next in $adjacent[$cur]) {
            if ($reached.Add($next)) { $queue.Enqueue($next) }
        }
    }
    foreach ($e in $Entities.Values) {
        if ($e.kind -in 'autoAttendant', 'callQueue' -and -not $e.unresolved -and -not $reached.Contains($e.id)) {
            & $add 'info' 'RA_NO_NUMBER_ENTRY' $e.id "'$($e.name)' cannot be reached from any phone number."
        }
    }

    return $findings.ToArray()
}
