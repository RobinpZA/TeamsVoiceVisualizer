function Get-VoiceAutoAttendantData {
    <#
    .SYNOPSIS
        Retrieves all Auto Attendants and enriches them with resolved target names
        and structured call flow data suitable for visualization.
    .PARAMETER NameCache
        A reference to a hashtable used for caching resolved target display names.
    .PARAMETER ResourceAccountMap
        Optional reverse map of configuration id -> @(resource account ids) from
        Get-VoiceResourceAccountMap. Built automatically if not supplied.
    .EXAMPLE
        $cache = @{}
        Get-VoiceAutoAttendantData -NameCache ([ref]$cache)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]$NameCache,

        [Parameter()]
        [hashtable]$ResourceAccountMap
    )

    $raMap = if ($PSBoundParameters.ContainsKey('ResourceAccountMap') -and $ResourceAccountMap) {
        $ResourceAccountMap
    } else {
        Get-VoiceResourceAccountMap
    }

    try {
        $aas = Get-CsAutoAttendant -ErrorAction Stop
    } catch {
        throw "Failed to retrieve Auto Attendants: $($_.Exception.Message)"
    }

    $result = @($aas | ForEach-Object {
        $aa = $_
        try {

        # Resolve operator
        $operatorName = $null
        $operatorType = $null
        if ($aa.Operator) {
            $operatorType = [string]$aa.Operator.Type
            if ($operatorType) {
                $operatorName = Resolve-VoiceTargetName -Id $aa.Operator.Identity -Type $operatorType -NameCache $NameCache
            }
        }

        # ── Build default call flow ──
        $defaultFlow = Build-AutoAttendantCallFlow -Flow $aa.DefaultCallFlow -NameCache $NameCache

        # ── Build after-hours flow ──
        $afterHoursFlow = $null
        $afterHoursSchedule = $null
        $ahAssoc = $aa.CallHandlingAssociations |
            Where-Object { [string]$_.Type -eq 'AfterHours' -and $_.Enabled } |
            Select-Object -First 1

        if ($ahAssoc) {
            $ahCf = $aa.CallFlows | Where-Object { $_.Id -eq $ahAssoc.CallFlowId } | Select-Object -First 1
            if ($ahCf) {
                $afterHoursFlow = Build-AutoAttendantCallFlow -Flow $ahCf -NameCache $NameCache
            }
            try {
                $sched = Get-CsOnlineSchedule -Id $ahAssoc.ScheduleId -ErrorAction SilentlyContinue
                if ($sched -and $sched.WeeklyRecurrentSchedule) {
                    $wrs = $sched.WeeklyRecurrentSchedule
                    $afterHoursSchedule = @{}
                    @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') | ForEach-Object {
                        $day = $_
                        $propName = "$($day)Hours"
                        $afterHoursSchedule[$day.ToLower()] = @($wrs.$propName | ForEach-Object {
                            @{ start = $_.Start; end = $_.End }
                        })
                    }
                }
            } catch {
                Write-Verbose "AutoAttendantData: Could not resolve after-hours schedule for '$($aa.Name)': $_"
            }
        }

        # ── Build holiday flows ──
        $holidayFlows = @($aa.CallHandlingAssociations | Where-Object { [string]$_.Type -eq 'Holiday' -and $_.Enabled } | ForEach-Object {
            $hAssoc = $_
            $hCf = $aa.CallFlows | Where-Object { $_.Id -eq $hAssoc.CallFlowId } | Select-Object -First 1
            $hf = if ($hCf) { Build-AutoAttendantCallFlow -Flow $hCf -NameCache $NameCache } else { $null }
            $scheduleName = $null
            try {
                $hs = Get-CsOnlineSchedule -Id $hAssoc.ScheduleId -ErrorAction SilentlyContinue
                if ($hs) { $scheduleName = $hs.Name }
            } catch {
                Write-Verbose "AutoAttendantData: Could not resolve holiday schedule: $_"
            }
            @{
                scheduleId   = $hAssoc.ScheduleId
                scheduleName = $scheduleName
                callFlow     = $hf
            }
        })

        # ── Resource accounts (object ids of the RAs that front this AA) ──
        $raKey = ([string]$aa.Identity).ToLowerInvariant()
        $associatedRAs = @()
        if ($raMap.ContainsKey($raKey)) { $associatedRAs = @($raMap[$raKey]) }

        @{
            id                         = [string]$aa.Identity
            name                       = [string]$aa.Name
            language                   = [string]$aa.LanguageId
            timeZone                   = [string]$aa.TimeZoneId
            voiceResponseEnabled       = [bool]$aa.EnableVoiceResponse
            operatorName               = $operatorName
            operatorType               = $operatorType
            defaultCallFlow            = $defaultFlow
            afterHoursCallFlow         = $afterHoursFlow
            afterHoursSchedule         = $afterHoursSchedule
            holidayFlows               = $holidayFlows
            dialByNameEnabled          = [bool]$aa.EnableDialByName
            directorySearchMethod      = [string]$aa.DirectorySearchMethod
            inclusionScopeGroupIds     = @(if ($aa.InclusionScope) { $aa.InclusionScope.GroupIds | ForEach-Object { [string]$_ } } else { @() })
            exclusionScopeGroupIds     = @(if ($aa.ExclusionScope) { $aa.ExclusionScope.GroupIds | ForEach-Object { [string]$_ } } else { @() })
            associatedResourceAccounts = $associatedRAs
        }
        } catch {
            Write-Warning "Skipped Auto Attendant '$($aa.Name)': $($_.Exception.Message)"
        }
    })

    return $result
}

function Build-AutoAttendantCallFlow {
    <#
    .SYNOPSIS
        Builds a structured call flow representation from a Teams AA call flow object.
    #>
    param(
        [Parameter(Mandatory)]
        $Flow,

        [Parameter(Mandatory)]
        [ref]$NameCache
    )

    if ($null -eq $Flow) { return $null }

    # Greeting
    $greetingType = 'None'
    $greetingText = $null
    $greetingAudioFile = $null
    $greeting = $Flow.Greetings | Select-Object -First 1
    if ($greeting) {
        if ($null -ne $greeting.TextToSpeechPrompt -and $greeting.TextToSpeechPrompt -ne '') {
            $greetingType = 'TextToSpeech'
            $greetingText = $greeting.TextToSpeechPrompt
        } elseif ($null -ne $greeting.AudioFilePrompt) {
            $greetingType = 'AudioFile'
            $greetingAudioFile = [string]$greeting.AudioFilePrompt
        } else {
            $greetingType = 'Silence'
        }
    }

    # Menu
    $menuPromptText = $null
    $menuOptions = @()
    $menu = $Flow.Menu
    if ($menu) {
        $menuPrompt = $menu.Prompts | Select-Object -First 1
        if ($menuPrompt) { $menuPromptText = $menuPrompt.TextToSpeechPrompt }

        $menuOptions = @($menu.MenuOptions | ForEach-Object {
            $target = $_.CallTarget
            $tType = if ($target) { [string]$target.Type } else { $null }
            $tId   = if ($target) { [string]$target.Id   } else { $null }
            $tName = if ($tId -and $tType) {
                Resolve-VoiceTargetName -Id $tId -Type $tType -NameCache $NameCache
            } else { $null }
            @{
                dtmfResponse   = [string]$_.DtmfResponse
                voiceResponses = @($_.VoiceResponses)
                action         = [string]$_.Action
                targetType     = $tType
                targetId       = $tId
                targetName     = $tName
            }
        })
    }

    return @{
        name           = [string]$Flow.Name
        greetingType   = $greetingType
        greetingText   = $greetingText
        greetingAudio  = $greetingAudioFile
        menuPromptText = $menuPromptText
        menuOptions    = $menuOptions
    }
}