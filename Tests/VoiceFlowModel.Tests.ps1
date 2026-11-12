# Pester tests for the voice flow model layer (New-VoiceFlowModel, Get-VoiceResourceAccountData)

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester BeforeAll variables are used in It blocks across scope boundaries.')]
param()

Describe 'New-VoiceFlowModel (fixture)' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1" -Force -ErrorAction Stop
        $flowData = Get-Content "$PSScriptRoot\Fixtures\flowdata.json" -Raw | ConvertFrom-Json
        $model = InModuleScope -ModuleName TeamsVoiceVisualizer -ArgumentList $flowData -ScriptBlock {
            param($fd)
            New-VoiceFlowModel -FlowData $fd
        }

        $mainId = 'a1a1a1a1-0001-4000-8000-000000000001'
        $accId = 'a1a1a1a1-0002-4000-8000-000000000002'
        $salesId = 'c1c1c1c1-0001-4000-8000-000000000001'
        $supportId = 'c1c1c1c1-0002-4000-8000-000000000002'
        $legacyId = 'c1c1c1c1-0003-4000-8000-000000000003'
        $raMainId = 'aaaaaaaa-0001-4000-8000-000000000001'
        $raOrphanId = 'aaaaaaaa-0004-4000-8000-000000000004'
        $ghostId = 'b0000000-00ff-4000-8000-0000000000ff'
    }

    It 'has schemaVersion 1 and the tenant block' {
        $model.schemaVersion | Should -Be 1
        $model.tenant.name | Should -Be 'Contoso Demo'
        $model.tenant.generatedAt | Should -Not -BeNullOrEmpty
    }

    It 'lower-cases all GUID ids and keys entities by id' {
        foreach ($key in $model.entities.Keys) {
            $key | Should -BeExactly $key.ToLowerInvariant()
            $model.entities[$key].id | Should -BeExactly $key
        }
        $model.entities.Contains($mainId) | Should -BeTrue
        @($model.entities.Keys) | Should -Contain $mainId
    }

    It 'creates a number -> resource account -> auto attendant chain' {
        $model.entities['tel:+27115550100'].kind | Should -Be 'number'
        $model.entities['tel:+27115550100'].resourceAccountId | Should -Be $raMainId
        $model.edges | Where-Object { $_.kind -eq 'dials' -and $_.from -eq 'tel:+27115550100' -and $_.to -eq $raMainId } | Should -HaveCount 1
        $model.edges | Where-Object { $_.kind -eq 'fronts' -and $_.from -eq $raMainId -and $_.to -eq $mainId } | Should -HaveCount 1
    }

    It 'sets resource account appType and configId' {
        $model.entities[$raMainId].appType | Should -Be 'autoAttendant'
        $model.entities[$raMainId].configId | Should -Be $mainId
        $model.entities[$raMainId].phoneNumbers | Should -Contain '+27115550100'
    }

    It 'models the Sales overflow loop through one shared resource account node' {
        $overflow = $model.edges | Where-Object { $_.kind -eq 'exception' -and $_.from -eq $salesId -and $_.via.exception -eq 'overflow' }
        $overflow | Should -HaveCount 1
        $overflow.to | Should -Be $raMainId
        $model.entities[$salesId].exceptions.overflow.action | Should -Be 'forward'
        $model.entities[$salesId].exceptions.overflow.targetRef | Should -Be $raMainId
        $model.entities[$salesId].exceptions.timeout.action | Should -Be 'voicemail'
        $model.entities[$salesId].exceptions.noAgent.action | Should -Be 'queue'
        $model.edges | Where-Object { $_.kind -eq 'fronts' -and $_.from -eq $raMainId -and $_.to -eq $mainId } | Should -HaveCount 1
        @($model.entities.Values | Where-Object { $_.name -eq 'Main Reception RA' }) | Should -HaveCount 1
        @($model.entities.Values | Where-Object { $_.name -eq 'Main Reception' -and $_.kind -eq 'autoAttendant' }) | Should -HaveCount 1
    }

    It 'has no edge whose endpoints are missing from entities' {
        foreach ($edge in $model.edges) {
            $model.entities.Contains($edge.from) | Should -BeTrue -Because "edge $($edge.id) from $($edge.from)"
            $model.entities.Contains($edge.to) | Should -BeTrue -Because "edge $($edge.id) to $($edge.to)"
        }
    }

    It 'has no duplicate edges and sequential edge ids' {
        $keys = $model.edges | ForEach-Object {
            $e = $_
            $via = if ($e.via) { (@($e.via.Keys) | ForEach-Object { "$_=$($e.via[$_])" }) -join ',' } else { '' }
            "$($e.from)|$($e.to)|$($e.kind)|$via"
        }
        $keys.Count | Should -Be (@($keys | Select-Object -Unique)).Count
        for ($i = 0; $i -lt $model.edges.Count; $i++) { $model.edges[$i].id | Should -Be "e$i" }
    }

    It 'normalises DTMF keys' {
        $keys = @($model.entities[$mainId].flows[0].menu.options | ForEach-Object { $_.key })
        $keys | Should -Be @('1', '2', '3', '5', '7', '9', '0', '*')
        $afterKeys = @($model.entities[$mainId].flows[1].menu.options | ForEach-Object { $_.key })
        $afterKeys | Should -Be @('automatic')
    }

    It 'maps menu actions and system targets' {
        $opts = $model.entities[$mainId].flows[0].menu.options
        ($opts | Where-Object key -EQ '0').action | Should -Be 'operator'
        ($opts | Where-Object key -EQ '0').targetRef | Should -Be "sys:operator:$mainId"
        $model.entities["sys:operator:$mainId"].targetRef | Should -Be 'b0000000-0001-4000-8000-000000000001'
        ($opts | Where-Object key -EQ '*').action | Should -Be 'disconnect'
        ($opts | Where-Object key -EQ '*').targetRef | Should -Be 'sys:disconnect'
        ($opts | Where-Object key -EQ '7').action | Should -Be 'announcement'
        ($opts | Where-Object key -EQ '7').announcement.type | Should -Be 'tts'
        ($opts | Where-Object key -EQ '9').targetRef | Should -Be 'tel:+27215550199'
        $model.entities['tel:+27215550199'].kind | Should -Be 'external'
        ($opts | Where-Object key -EQ '3').targetRef | Should -Be $accId
        $model.entities[$mainId].operatorRef | Should -Be 'b0000000-0001-4000-8000-000000000001'
    }

    It 'includes after-hours and holiday flows with schedules' {
        $flows = $model.entities[$mainId].flows
        @($flows | ForEach-Object key) | Should -Be @('default', 'afterHours', 'holiday:f0000000-0001-4000-8000-000000000001')
        $flows[0].schedule | Should -BeNullOrEmpty
        $flows[1].schedule.type | Should -Be 'weekly'
        $flows[1].schedule.days.monday[0].start | Should -Be '08:00'
        $flows[1].schedule.days.friday[0].end | Should -Be '17:00'
        @($flows[1].schedule.days["sunday"]).Count | Should -Be 0
        $flows[1].menu.options[0].targetRef | Should -Be 'd0000000-0002-4000-8000-000000000002'
        $model.entities['d0000000-0002-4000-8000-000000000002'].isSharedVoicemail | Should -BeTrue
        $flows[2].label | Should -Be 'Holiday: Christmas'
        $flows[2].schedule.type | Should -Be 'fixed'
        $flows[2].schedule.ranges[0].start | Should -Be '2026-12-25T00:00:00'
        $flows[2].menu.options[0].action | Should -Be 'disconnect'
        $model.entities[$mainId].timeZoneIana | Should -Be 'Africa/Johannesburg'
    }

    It 'keeps agents, groups and caller id on the call queue and untruncated hostile strings' {
        $sales = $model.entities[$salesId]
        $sales.routingMethod | Should -Be 'LongestIdle'
        $sales.agentIds | Should -HaveCount 3
        $sales.groupIds | Should -HaveCount 1
        $sales.oboResourceAccountIds | Should -HaveCount 1
        $model.entities['b0000000-0003-4000-8000-000000000003'].name | Should -Be '<img src=x onerror=alert(1)>'
        $model.entities[$mainId].flows[0].greetings[0].text | Should -Match '</script><script>alert\(2\)</script>'
    }

    It 'emits the expected findings' {
        $by = { param($code) @($model.findings | Where-Object code -EQ $code) }
        (& $by 'QUEUE_NO_AGENTS').entityId | Should -Be @($supportId)
        (& $by 'RA_UNASSIGNED').entityId | Should -Be @($raOrphanId)
        (& $by 'TARGET_UNRESOLVED').entityId | Should -Be @($mainId)
        (& $by 'TARGET_UNRESOLVED').message | Should -Match $ghostId
        (& $by 'FLOW_DEAD_END').entityId | Should -Be @($accId)
        (& $by 'RA_NO_NUMBER_ENTRY').entityId | Should -Be @($legacyId)
        & $by 'SCHEDULE_UNREADABLE' | Should -HaveCount 0
        $model.entities[$ghostId].unresolved | Should -BeTrue
    }

    It 'serialises to JSON with stable key order' {
        $json = $model | ConvertTo-Json -Depth 20
        $json | Should -Match '^\{\s+"schemaVersion": 1,\s+"tenant"'
    }
}

Describe 'New-VoiceFlowModel (inline FlowData)' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1" -Force -ErrorAction Stop
    }

    It 'flags SCHEDULE_UNREADABLE when the after-hours schedule could not be read' {
        $model = InModuleScope -ModuleName TeamsVoiceVisualizer {
            $fd = [PSCustomObject]@{
                TenantDisplayName = 'T'
                GeneratedAt       = '2026-11-12T10:00:00+02:00'
                ResourceAccounts  = @()
                CallQueues        = @()
                AutoAttendants    = @(
                    @{
                        id = 'AA-1'; name = 'AA One'; timeZone = 'UTC'
                        defaultCallFlow = @{ name = 'Default'; greetings = @(@{ type = 'tts'; text = 'Hi'; audioFile = $null }); menuPrompts = @(); menuOptions = @() }
                        afterHoursCallFlow = @{ name = 'After'; greetings = @(@{ type = 'tts'; text = 'Closed'; audioFile = $null }); menuPrompts = @(); menuOptions = @() }
                        afterHoursSchedule = $null
                        afterHoursScheduleError = $true
                        holidayFlows = @()
                        associatedResourceAccounts = @()
                    }
                )
            }
            New-VoiceFlowModel -FlowData $fd
        }
        $f = @($model.findings | Where-Object code -EQ 'SCHEDULE_UNREADABLE')
        $f | Should -HaveCount 1
        $f[0].severity | Should -Be 'info'
        $f[0].entityId | Should -Be 'aa-1'
        $model.entities['aa-1'].flows[1].schedule | Should -BeNullOrEmpty
    }

    It 'handles empty FlowData' {
        $model = InModuleScope -ModuleName TeamsVoiceVisualizer {
            New-VoiceFlowModel -FlowData ([PSCustomObject]@{ TenantDisplayName = 'Empty'; AutoAttendants = @(); CallQueues = @(); GeneratedAt = '2026-11-12T10:00:00+02:00' })
        }
        $model.entities.Count | Should -Be 0
        $model.edges | Should -HaveCount 0
        $model.findings | Should -HaveCount 0
    }
}

Describe 'Get-VoiceResourceAccountData' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1" -Force -ErrorAction Stop
    }

    Context 'resource accounts enumerate and associate' {
        BeforeAll {
            Mock Get-CsOnlineApplicationInstance -ModuleName TeamsVoiceVisualizer {
                @(
                    [PSCustomObject]@{ ObjectId = 'RA-1'; DisplayName = 'Main RA'; UserPrincipalName = 'main@c.example'; PhoneNumber = 'tel:+27115550100'; ApplicationId = 'ce933385-9390-45d1-9512-c8d228074e07' }
                    [PSCustomObject]@{ ObjectId = 'RA-2'; DisplayName = 'Free RA'; UserPrincipalName = 'free@c.example'; PhoneNumber = $null; ApplicationId = '11cd3e2e-fccb-42ad-ad00-878b93575e07' }
                )
            }
            Mock Get-CsOnlineApplicationInstanceAssociation -ModuleName TeamsVoiceVisualizer {
                if ($Identity -eq 'RA-1') { [PSCustomObject]@{ ConfigurationId = 'AA-CONFIG-1' } }
            }
        }

        It 'returns a lower-cased map and the account list' {
            $data = InModuleScope -ModuleName TeamsVoiceVisualizer { Get-VoiceResourceAccountData }
            $data.Map.ContainsKey('aa-config-1') | Should -BeTrue
            @($data.Map['aa-config-1']) | Should -Be @('RA-1')
            $data.Accounts | Should -HaveCount 2
            $main = $data.Accounts | Where-Object id -EQ 'RA-1'
            $main.name | Should -Be 'Main RA'
            $main.upn | Should -Be 'main@c.example'
            $main.phoneNumber | Should -Be 'tel:+27115550100'
            $main.applicationId | Should -Be 'ce933385-9390-45d1-9512-c8d228074e07'
            $main.configId | Should -Be 'aa-config-1'
            ($data.Accounts | Where-Object id -EQ 'RA-2').configId | Should -BeNullOrEmpty
        }

        It 'Get-VoiceResourceAccountMap returns just the map' {
            $map = InModuleScope -ModuleName TeamsVoiceVisualizer { Get-VoiceResourceAccountMap }
            $map.ContainsKey('aa-config-1') | Should -BeTrue
            $map.Keys | Should -HaveCount 1
        }
    }

    Context 'enumeration fails' {
        BeforeAll {
            Mock Get-CsOnlineApplicationInstance -ModuleName TeamsVoiceVisualizer { throw 'boom' }
        }

        It 'warns and returns an empty result' {
            $data = InModuleScope -ModuleName TeamsVoiceVisualizer { Get-VoiceResourceAccountData 3>$null }
            $data.Map.Count | Should -Be 0
            $data.Accounts | Should -HaveCount 0
        }
    }
}
