function New-CQGraphData {
    <#
    .SYNOPSIS
        Converts a Call Queue data object into a D3-compatible directed graph
        (nodes + links) for rendering a call flow diagram.
    .PARAMETER CQ
        The Call Queue data object from Get-VoiceCallQueueData.
    .EXAMPLE
        $graph = New-CQGraphData -CQ $cqData
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$CQ
    )

    begin { }
    process {
        $nodes = [System.Collections.Generic.List[PSCustomObject]]::new()
        $links = [System.Collections.Generic.List[PSCustomObject]]::new()
        $counter = @{ n = 0 }

        function New-Node {
        param([string]$Label, [string]$Type, [string]$SubLabel, $Detail, [string]$TargetRef, [string]$LinkKind)
        $id = "cq_$($CQ.id)_$($counter.n)"
        $counter.n++
        $node = [PSCustomObject]@{
            id        = $id
            label     = $Label
            type      = $Type
            subLabel  = $SubLabel
            detail    = $Detail
            targetRef = $TargetRef
            linkKind  = $LinkKind
        }
        $nodes.Add($node)
        return $id
    }

    function New-Link {
        param([string]$Source, [string]$Target, [string]$Label, [string]$Style)
        $links.Add([PSCustomObject]@{
            source = $Source
            target = $Target
            label  = $Label
            style  = if ($Style) { $Style } else { 'solid' }
        })
    }

    # ── Root ──
    $rootNode = New-Node -Label $CQ.name -Type 'callqueue' -SubLabel 'Call Queue'

    # Greeting / welcome
    if ($CQ.welcomeTtsPrompt -and $CQ.welcomeTtsPrompt -ne '') {
        $tts = if ($CQ.welcomeTtsPrompt.Length -gt 60) { $CQ.welcomeTtsPrompt.Substring(0, 57) + '...' } else { $CQ.welcomeTtsPrompt }
        $greetingNode = New-Node -Label "Greeting (TTS): $tts" -Type 'greeting' -SubLabel 'Welcome'
    } elseif ($CQ.welcomeMusicAudioFileId) {
        $greetingNode = New-Node -Label 'Greeting (Audio File)' -Type 'greeting' -SubLabel 'Welcome'
    } else {
        $greetingNode = New-Node -Label 'No Welcome Greeting' -Type 'greeting' -SubLabel 'Welcome'
    }
    New-Link -Source $rootNode -Target $greetingNode -Label '' -Style 'dashed'

    # Music on hold / wait
    $mohLabel = if ($CQ.useDefaultMusicOnHold) { 'Music on Hold (Default)' } elseif ($CQ.musicOnHoldAudioFileId) { 'Music on Hold (Custom Audio)' } else { 'Wait in Queue' }
    $mohNode = New-Node -Label $mohLabel -Type 'moh' -SubLabel 'Queue Wait'
    New-Link -Source $greetingNode -Target $mohNode -Label '' -Style 'solid'

    # Agent routing method
    $methodLabels = @{
        'Attendant'    = 'Attendant Routing'
        'Serial'       = 'Serial Routing'
        'RoundRobin'   = 'Round Robin'
        'LongestIdle'  = 'Longest Idle'
    }
    $methodLabel = if ($methodLabels.ContainsKey($CQ.routingMethod)) { $methodLabels[$CQ.routingMethod] } else { $CQ.routingMethod }

    $routingNode = New-Node -Label $methodLabel -Type 'routing' -SubLabel 'Routing Method'
    New-Link -Source $mohNode -Target $routingNode -Label '' -Style 'solid'

    # Agent group details
    $agentParts = @()
    if ($CQ.agentNames.Count -gt 0) {
        $agentCount = $CQ.agentNames.Count
        $agentParts += "$agentCount agent$(if ($agentCount -ne 1) { 's' } else { '' })"
    }
    if ($CQ.distributionListNames.Count -gt 0) {
        $agentParts += "$($CQ.distributionListNames.Count) DL(s)"
    }
    if ($CQ.channelId) {
        $agentParts += 'Teams Channel'
    }
    $agentLabel = if ($agentParts.Count -gt 0) { "Agents: $($agentParts -join ', ')" } else { 'No agents configured' }

    # Build detail list: individual agents + DL names for tooltip
    $agentDetailItems = @()
    if ($CQ.agentNames.Count -gt 0)  { $agentDetailItems += $CQ.agentNames }
    if ($CQ.distributionListNames.Count -gt 0) { $agentDetailItems += $CQ.distributionListNames | ForEach-Object { "DL: $_" } }
    if ($CQ.channelId) { $agentDetailItems += 'Teams Channel' }
    $agentDetail = if ($agentDetailItems.Count -gt 0) { $agentDetailItems } else { $null }

    $agentNode = New-Node -Label $agentLabel -Type 'agentgroup' -SubLabel 'Agent Group' -Detail $agentDetail
    New-Link -Source $routingNode -Target $agentNode -Label '' -Style 'solid'

    # Conference mode indicator
    $confNode = $null
    if ($CQ.conferenceMode) {
        $confNode = New-Node -Label 'Conference Mode: ON' -Type 'conference_mode' -SubLabel 'Settings'
        New-Link -Source $agentNode -Target $confNode -Label '' -Style 'dotted'
    } else {
        # Agent alert time
        if ($CQ.agentAlertTimeSeconds -gt 0) {
            $confNode = New-Node -Label "Alert: $($CQ.agentAlertTimeSeconds)s" -Type 'agent_alert' -SubLabel 'Settings'
            New-Link -Source $agentNode -Target $confNode -Label '' -Style 'dotted'
        }
    }

    # Presence-based routing
    if ($CQ.presenceBasedRouting) {
        $pbNode = New-Node -Label 'Presence-Based Routing' -Type 'presence_routing' -SubLabel 'Settings'
        $prev = if ($confNode) { $confNode } else { $agentNode }
        New-Link -Source $prev -Target $pbNode -Label '' -Style 'dotted'
    }

    # OBO resource accounts
    if ($CQ.oboResourceAccountNames.Count -gt 0) {
        $oboLabel = "Caller ID: $($CQ.oboResourceAccountNames -join ', ')"
        $oboNode = New-Node -Label $oboLabel -Type 'resourceaccount' -SubLabel 'OBO'
        $prev = if ($confNode) { $confNode } else { $agentNode }
        New-Link -Source $prev -Target $oboNode -Label '' -Style 'dotted'
    }

    # ── Exception flows (overflow, timeout, no agents) ──
    $overflowAction = $CQ.overflowAction
    if ($overflowAction -and $overflowAction -ne 'DisconnectWithBusy') {
        $ovfLabel = "Overflow ($($CQ.overflowThreshold) calls)"
        $ovfNode = New-Node -Label $ovfLabel -Type 'overflow' -SubLabel 'Exception'
        New-Link -Source $agentNode -Target $ovfNode -Label '' -Style 'error'

        Add-ExceptionTarget -SourceNodeId $ovfNode -Action $overflowAction `
            -TargetType $CQ.overflowActionTargetType `
            -TargetName $CQ.overflowActionTargetName `
            -TargetId $CQ.overflowActionTargetId
    }

    $timeoutAction = $CQ.timeoutAction
    if ($timeoutAction -and $timeoutAction -ne 'DisconnectWithBusy') {
        $toLabel = "Timeout ($($CQ.timeoutThresholdSeconds)s)"
        $toNode = New-Node -Label $toLabel -Type 'timeout' -SubLabel 'Exception'
        New-Link -Source $agentNode -Target $toNode -Label '' -Style 'error'

        Add-ExceptionTarget -SourceNodeId $toNode -Action $timeoutAction `
            -TargetType $CQ.timeoutActionTargetType `
            -TargetName $CQ.timeoutActionTargetName `
            -TargetId $CQ.timeoutActionTargetId
    }

    $noAgentAction = $CQ.noAgentAction
    if ($noAgentAction -and $noAgentAction -ne 'DisconnectWithBusy') {
        $naNode = New-Node -Label 'No Agents Available' -Type 'noagents' -SubLabel 'Exception'
        New-Link -Source $agentNode -Target $naNode -Label '' -Style 'error'

        Add-ExceptionTarget -SourceNodeId $naNode -Action $noAgentAction `
            -TargetType $CQ.noAgentActionTargetType `
            -TargetName $CQ.noAgentActionTargetName `
            -TargetId $CQ.noAgentActionTargetId
    }

    # Features summary
    $featureParts = @()
    if ($CQ.allowOptOut) { $featureParts += 'Opt-Out Enabled' }
    if ($CQ.serviceLevelThresholdSeconds -gt 0) { $featureParts += "SLA: $($CQ.serviceLevelThresholdSeconds)s" }

    return [PSCustomObject]@{
        callQueueId   = $CQ.id
        callQueueName = $CQ.name
        routingMethod = $CQ.routingMethod
        features       = $featureParts -join ' | '
        resourceAccounts = $CQ.associatedResourceAccounts
        nodes          = $nodes.ToArray()
        links          = $links.ToArray()
    }
    }
}

function Add-ExceptionTarget {
    <#
    .SYNOPSIS
        Adds a target node for an exception action (overflow/timeout/no-agents) in a CQ graph.
    #>
    param(
        [string]$SourceNodeId,
        [string]$Action,
        [string]$TargetType,
        [string]$TargetName,
        [string]$TargetId
    )

    $linkKind = switch ($TargetType) {
        'ApplicationEndpoint'         { 'ra' }
        'OrganizationalAutoAttendant' { 'aa' }
        default                       { $null }
    }

    $actionLabels = @{
        'Forward'            = 'Forward'
        'Redirect'           = 'Redirect'
        'Queue'              = 'Redirect to Queue'
        'SharedVoicemail'    = 'Voicemail'
        'Voicemail'          = 'Voicemail'
        'Disconnect'         = 'Disconnect'
        'DisconnectWithBusy' = 'Disconnect'
    }
    $actionName = if ($actionLabels.ContainsKey($Action)) { $actionLabels[$Action] } else { $Action }

    if ($TargetName) {
        $targetNode = [PSCustomObject]@{
            id       = "$SourceNodeId`_target"
            label    = "$actionName`: $TargetName"
            type     = switch ($TargetType) {
                'User'                   { 'user' }
                'ApplicationEndpoint'    { 'resourceaccount' }
                'OrganizationalAutoAttendant' { 'autoattendant' }
                'ExternalPstn'           { 'external' }
                default                  { 'unknown' }
            }
            subLabel  = $actionName
            detail    = $null
            targetRef = $TargetId
            linkKind  = $linkKind
        }
        $nodes.Add($targetNode)
        $links.Add([PSCustomObject]@{
            source = $SourceNodeId
            target = $targetNode.id
            label  = ''
            style  = 'error'
        })
    } elseif ($Action -eq 'SharedVoicemail' -or $Action -eq 'Voicemail') {
        $targetNode = [PSCustomObject]@{
            id       = "$SourceNodeId`_target"
            label    = 'Shared Voicemail'
            type     = 'voicemail'
            subLabel = $actionName
        }
        $nodes.Add($targetNode)
        $links.Add([PSCustomObject]@{
            source = $SourceNodeId
            target = $targetNode.id
            label  = ''
            style  = 'error'
        })
    } else {
        $targetNode = [PSCustomObject]@{
            id       = "$SourceNodeId`_target"
            label    = $actionName
            type     = 'disconnect'
            subLabel = 'Fallback'
        }
        $nodes.Add($targetNode)
        $links.Add([PSCustomObject]@{
            source = $SourceNodeId
            target = $targetNode.id
            label  = ''
            style  = 'error'
        })
    }
}