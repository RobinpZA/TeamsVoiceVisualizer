function New-AAGraphData {
    <#
    .SYNOPSIS
        Converts an Auto Attendant data object into a D3-compatible directed graph
        (nodes + links) for rendering a call flow diagram.
    .PARAMETER AA
        The Auto Attendant data object from Get-VoiceAutoAttendantData.
    .EXAMPLE
        $graph = New-AAGraphData -AA $aaData
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$AA
    )

    begin { }
    process {
        $nodes = [System.Collections.Generic.List[PSCustomObject]]::new()
        $links = [System.Collections.Generic.List[PSCustomObject]]::new()
        $counter = @{ n = 0 }

        function New-Node {
        param([string]$Label, [string]$Type, [string]$SubLabel)
        $id = "aa_$($AA.id)_$($counter.n)"
        $counter.n++
        $node = [PSCustomObject]@{
            id       = $id
            label    = $Label
            type     = $Type
            subLabel = $SubLabel
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

    # ── Build a single call flow subgraph ──
    function Build-FlowGraph {
        param($Flow, [string]$ParentId, [string]$FlowLabel)

        if (-not $Flow) { return $null }

        $prevNodeId = $ParentId

        # Greeting node
        $greetingLabel = switch ($Flow.greetingType) {
            'TextToSpeech' {
                $text = if ($Flow.greetingText.Length -gt 60) { $Flow.greetingText.Substring(0, 57) + '...' } else { $Flow.greetingText }
                "Greeting (TTS): $text"
            }
            'AudioFile'   { 'Greeting (Audio File)' }
            'Silence'     { 'Greeting (Silence)' }
            default       { 'No Greeting' }
        }
        $greetingNode = New-Node -Label $greetingLabel -Type 'greeting' -SubLabel $FlowLabel
        New-Link -Source $prevNodeId -Target $greetingNode -Label '' -Style 'dashed'

        $prevNodeId = $greetingNode

        # Menu node if there are options
        if ($Flow.menuOptions.Count -gt 0) {
            $menuPrompt = if ($Flow.menuPromptText) {
                $mp = if ($Flow.menuPromptText.Length -gt 80) { $Flow.menuPromptText.Substring(0, 77) + '...' } else { $Flow.menuPromptText }
                "Menu: $mp"
            } else {
                'Menu Options'
            }
            $menuNode = New-Node -Label $menuPrompt -Type 'menu' -SubLabel $FlowLabel
            New-Link -Source $prevNodeId -Target $menuNode -Label '' -Style 'solid'

            $prevNodeId = $menuNode

            # Each menu option
            foreach ($opt in $Flow.menuOptions) {
                $dtmfLabel = if ($opt.dtmfResponse) { "DTMF $($opt.dtmfResponse)" } else { '' }
                $null = switch ($opt.action) {
                    { $_ -in @('Disconnect', 'DisconnectCall') }  {
                        $n = New-Node -Label 'Disconnect' -Type 'disconnect' -SubLabel $FlowLabel
                        New-Link -Source $prevNodeId -Target $n -Label $dtmfLabel -Style 'solid'
                        $n
                    }
                    'TransferCallToOperator' {
                        $label = if ($AA.operatorName) { "Operator: $($AA.operatorName)" } else { 'Operator' }
                        $n = New-Node -Label $label -Type 'operator' -SubLabel $FlowLabel
                        New-Link -Source $prevNodeId -Target $n -Label $dtmfLabel -Style 'solid'
                        $n
                    }
                    'TransferCallToTarget' {
                        $targetLabel = if ($opt.targetName) { $opt.targetName } else { $opt.targetId }
                        $targetType = switch ($opt.targetType) {
                            'User'                   { 'user' }
                            'ApplicationEndpoint'    { 'resourceaccount' }
                            'ExternalPstn'           { 'external' }
                            'OrganizationalAutoAttendant' { 'autoattendant' }
                            default                  { 'unknown' }
                        }
                        $n = New-Node -Label $targetLabel -Type $targetType -SubLabel $FlowLabel
                        New-Link -Source $prevNodeId -Target $n -Label $dtmfLabel -Style 'solid'
                        $n
                    }
                    'Announcement' {
                        $n = New-Node -Label 'Announcement' -Type 'announcement' -SubLabel $FlowLabel
                        New-Link -Source $prevNodeId -Target $n -Label $dtmfLabel -Style 'solid'
                        $n
                    }
                    default {
                        $n = New-Node -Label "[$($opt.action)]" -Type 'default_action' -SubLabel $FlowLabel
                        New-Link -Source $prevNodeId -Target $n -Label $dtmfLabel -Style 'solid'
                        $n
                    }
                }
            }
        } else {
            # No menu — just a leaf
            $endNode = New-Node -Label 'End of flow' -Type 'endpoint' -SubLabel $FlowLabel
            New-Link -Source $prevNodeId -Target $endNode -Label '' -Style 'dashed'
        }
    }

    # ── Root node for this AA ──
    $rootNode = New-Node -Label $AA.name -Type 'autoattendant' -SubLabel 'Auto Attendant'

    # Default call flow
    Build-FlowGraph -Flow $AA.defaultCallFlow -ParentId $rootNode -FlowLabel 'Business Hours'

    # After-hours flow
    if ($AA.afterHoursCallFlow) {
        $ahLabel = 'After Hours'
        if ($AA.afterHoursSchedule) {
            $dayNames = @('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
            $scheduleParts = @($dayNames | Where-Object { $AA.afterHoursSchedule[$_].Count -gt 0 } | ForEach-Object {
                $ranges = ($AA.afterHoursSchedule[$_] | ForEach-Object { "$($_.start)-$($_.end)" }) -join ', '
                "$((Get-Culture).TextInfo.ToTitleCase($_)): $ranges"
            })
            if ($scheduleParts.Count -gt 0) {
                $ahLabel = "After Hours`n$($scheduleParts -join ' | ')"
            }
        }
        Build-FlowGraph -Flow $AA.afterHoursCallFlow -ParentId $rootNode -FlowLabel $ahLabel
    }

    # Holiday flows
    foreach ($hf in $AA.holidayFlows) {
        if ($hf.callFlow) {
            $holidayLabel = if ($hf.scheduleName) { "Holiday: $($hf.scheduleName)" } else { 'Holiday' }
            Build-FlowGraph -Flow $hf.callFlow -ParentId $rootNode -FlowLabel $holidayLabel
        }
    }

    # Features summary
    $featureParts = @()
    if ($AA.dialByNameEnabled) { $featureParts += 'Dial-by-Name' }
    if ($AA.voiceResponseEnabled) { $featureParts += 'Voice Response' }
    if ($AA.operatorName) { $featureParts += "Operator: $($AA.operatorName)" }

    return [PSCustomObject]@{
        autoAttendantId   = $AA.id
        autoAttendantName = $AA.name
        language           = $AA.language
        timeZone           = $AA.timeZone
        features           = $featureParts -join ' | '
        resourceAccounts   = $AA.associatedResourceAccounts
        nodes              = $nodes.ToArray()
        links              = $links.ToArray()
    }
    }
}