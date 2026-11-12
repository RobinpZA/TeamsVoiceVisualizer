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
        $aas = Invoke-VoicePagedQuery -KeyProperty Identity -Query {
            param($Skip, $PageSize) Get-CsAutoAttendant -First $PageSize -Skip $Skip -ErrorAction Stop
        }
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

        $operatorId = if ($aa.Operator -and $aa.Operator.Id) { [string]$aa.Operator.Id } else { $null }

        $timeZoneIana = $null
        if ($aa.TimeZoneId) {
            try {
                $iana = $null
                if ([System.TimeZoneInfo]::TryConvertWindowsIdToIanaId([string]$aa.TimeZoneId, [ref]$iana)) { $timeZoneIana = $iana }
            } catch {
                Write-Verbose "AutoAttendantData: Could not convert time zone '$($aa.TimeZoneId)' to IANA: $_"
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

        $afterHoursScheduleError = [bool]($ahAssoc -and -not $afterHoursSchedule)

        # ── Build holiday flows ──
        $holidayFlows = @($aa.CallHandlingAssociations | Where-Object { [string]$_.Type -eq 'Holiday' -and $_.Enabled } | ForEach-Object {
            $hAssoc = $_
            $hCf = $aa.CallFlows | Where-Object { $_.Id -eq $hAssoc.CallFlowId } | Select-Object -First 1
            $hf = if ($hCf) { Build-AutoAttendantCallFlow -Flow $hCf -NameCache $NameCache } else { $null }
            $scheduleName = $null
            $dateRanges = @()
            try {
                $hs = Get-CsOnlineSchedule -Id $hAssoc.ScheduleId -ErrorAction SilentlyContinue
                if ($hs) {
                    $scheduleName = $hs.Name
                    if ($hs.FixedSchedule -and $hs.FixedSchedule.DateTimeRanges) {
                        $dateRanges = @($hs.FixedSchedule.DateTimeRanges | ForEach-Object {
                            @{ start = ([datetime]$_.Start).ToString('s'); end = ([datetime]$_.End).ToString('s') }
                        })
                    }
                }
            } catch {
                Write-Verbose "AutoAttendantData: Could not resolve holiday schedule: $_"
            }
            @{
                scheduleId   = $hAssoc.ScheduleId
                scheduleName = $scheduleName
                dateRanges   = $dateRanges
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
            timeZoneIana               = $timeZoneIana
            voiceResponseEnabled       = [bool]$aa.EnableVoiceResponse
            operatorName               = $operatorName
            operatorType               = $operatorType
            operatorId                 = $operatorId
            defaultCallFlow            = $defaultFlow
            afterHoursCallFlow         = $afterHoursFlow
            afterHoursSchedule         = $afterHoursSchedule
            afterHoursScheduleError    = $afterHoursScheduleError
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

    $greetings = @($Flow.Greetings | Where-Object { $_ } | ForEach-Object { ConvertTo-AutoAttendantPromptData -Prompt $_ })

    # Menu
    $menuPrompts = @()
    $menuPromptText = $null
    $menuOptions = @()
    $menu = $Flow.Menu
    if ($menu) {
        $menuPrompts = @($menu.Prompts | Where-Object { $_ } | ForEach-Object { ConvertTo-AutoAttendantPromptData -Prompt $_ })
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
                prompt         = if ($_.Prompt) { ConvertTo-AutoAttendantPromptData -Prompt $_.Prompt } else { $null }
            }
        })
    }

    return @{
        name           = [string]$Flow.Name
        greetingType   = $greetingType
        greetingText   = $greetingText
        greetingAudio  = $greetingAudioFile
        greetings      = $greetings
        menuPrompts    = $menuPrompts
        menuPromptText = $menuPromptText
        menuOptions    = $menuOptions
    }
}

function ConvertTo-AutoAttendantPromptData {
    <#
    .SYNOPSIS
        Normalises a Teams AA prompt into @{ type = tts|audio|silence; text; audioFile }.
    #>
    param(
        [Parameter(Mandatory)]
        $Prompt
    )

    $type = 'silence'
    $text = $null
    $audioFile = $null
    if ($null -ne $Prompt.TextToSpeechPrompt -and $Prompt.TextToSpeechPrompt -ne '') {
        $type = 'tts'
        $text = [string]$Prompt.TextToSpeechPrompt
    } elseif ($null -ne $Prompt.AudioFilePrompt) {
        $type = 'audio'
        $audioFile = if ($Prompt.AudioFilePrompt.FileName) { [string]$Prompt.AudioFilePrompt.FileName } else { [string]$Prompt.AudioFilePrompt }
    }
    return @{ type = $type; text = $text; audioFile = $audioFile }
}
