BeforeAll {
    Import-Module "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1" -Force -ErrorAction Stop
}

Describe 'Invoke-VoicePagedQuery' {
    It 'Reads every page until a short page' {
        InModuleScope TeamsVoiceVisualizer {
            $all = 1..250 | ForEach-Object { [pscustomobject]@{ Identity = "id$_" } }
            $r = Invoke-VoicePagedQuery -KeyProperty Identity -Query {
                param($Skip, $PageSize) $all | Select-Object -Skip $Skip -First $PageSize
            }
            $r.Count | Should -Be 250
        }
    }

    It 'Stops when the backend ignores Skip' {
        InModuleScope TeamsVoiceVisualizer {
            $page = 1..100 | ForEach-Object { [pscustomobject]@{ Identity = "id$_" } }
            $script:calls = 0
            $r = Invoke-VoicePagedQuery -KeyProperty Identity -Query { param($Skip, $PageSize) $script:calls++; $page }
            $r.Count | Should -Be 100
            $script:calls | Should -Be 2
        }
    }

    It 'Returns an array for a single item' {
        InModuleScope TeamsVoiceVisualizer {
            $r = Invoke-VoicePagedQuery -KeyProperty Identity -Query { param($Skip, $PageSize) [pscustomobject]@{ Identity = 'only' } }
            , $r | Should -BeOfType [object[]]
            $r.Count | Should -Be 1
        }
    }
}

Describe 'New-VoiceFlowModel review fixes' {
    BeforeAll { $script:fixture = Join-Path $PSScriptRoot 'Fixtures/flowdata.json' }

    It 'Keeps findings an array when there is exactly one' {
        InModuleScope TeamsVoiceVisualizer -Parameters @{ F = $script:fixture } {
            param($F)
            $flow = Get-Content $F -Raw | ConvertFrom-Json -AsHashtable
            # Strip to a single CQ with an agent and no number: exactly one RA_NO_NUMBER_ENTRY.
            $flow.AutoAttendants   = @()
            $flow.ResourceAccounts = @()
            $flow.CallQueues       = @($flow.CallQueues | Where-Object { $_.name -eq 'Legacy' })
            $m = New-VoiceFlowModel -FlowData $flow
            , $m.findings | Should -BeOfType [object[]]
            @($m.findings).Count | Should -Be 1
            (ConvertTo-Json -InputObject $m -Depth 30 -Compress) | Should -Match '"findings":\['
        }
    }
}

Describe 'New-VoiceFlowModel unresolved placeholders' {
    BeforeAll { $script:fixture = Join-Path $PSScriptRoot 'Fixtures/flowdata.json' }

    It 'Does not turn a missing call queue into a real one when a later reference has a name' {
        InModuleScope TeamsVoiceVisualizer -Parameters @{ F = $script:fixture } {
            param($F)
            $flow = Get-Content $F -Raw | ConvertFrom-Json -AsHashtable
            $ghost = 'c9c9c9c9-0000-4000-8000-000000000009'
            $opts = [System.Collections.Generic.List[object]]::new()
            foreach ($o in $flow.AutoAttendants[0].defaultCallFlow.menuOptions) { $opts.Add($o) }
            $opts.Add(@{ dtmfResponse = 'Tone4'; voiceResponses = @(); action = 'TransferCallToTarget'; targetType = 'HuntGroup'; targetId = $ghost; targetName = $null })
            $opts.Add(@{ dtmfResponse = 'Tone6'; voiceResponses = @(); action = 'TransferCallToTarget'; targetType = 'HuntGroup'; targetId = $ghost; targetName = 'Ghost Queue' })
            $flow.AutoAttendants[0].defaultCallFlow.menuOptions = $opts.ToArray()

            $m = New-VoiceFlowModel -FlowData $flow
            $m.entities[$ghost].unresolved | Should -BeTrue
            @($m.findings | Where-Object { $_.code -eq 'QUEUE_NO_AGENTS' -and $_.entityId -eq $ghost }).Count | Should -Be 0
            @($m.findings | Where-Object { $_.code -eq 'TARGET_UNRESOLVED' }).Count | Should -BeGreaterThan 1
        }
    }
}
