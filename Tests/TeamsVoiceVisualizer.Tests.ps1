# Pester tests for TeamsVoiceVisualizer module
# Run with: Invoke-Pester -Path .\Tests\

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester BeforeAll/BeforeDiscovery variables are used in It blocks across scope boundaries.')]
param()

BeforeDiscovery {
    $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
}

Describe 'Module Manifest' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
    }

    It 'Has a valid manifest' {
        $manifest = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
        $manifest | Should -Not -BeNullOrEmpty
        $manifest.Name | Should -Be 'TeamsVoiceVisualizer'
    }

    It 'Exports expected functions' {
        $manifest = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
        $expected = @(
            'Get-TeamsVoiceFlowData',
            'Show-TeamsVoiceFlowReport',
            'Export-TeamsVoiceFlowReport'
        )
        foreach ($fn in $expected) {
            $manifest.ExportedFunctions.Keys | Should -Contain $fn
        }
    }

    It 'Has required module MicrosoftTeams' {
        $manifest = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
        $teamsModule = $manifest.RequiredModules | Where-Object { $_.Name -eq 'MicrosoftTeams' }
        $teamsModule | Should -Not -BeNullOrEmpty
    }
}

Describe 'Module Loads' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
    }

    It 'Can import the module' {
        { Import-Module $modulePath -Force -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Private Helpers' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Connect-TeamsVoiceSession exists as a function' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command Connect-TeamsVoiceSession -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'Resolve-VoiceTargetName exists as a function' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command Resolve-VoiceTargetName -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'Resolve-VoiceTargetName returns phone numbers as-is' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $cache = @{}
            $result = Resolve-VoiceTargetName -Id '+27123456789' -Type 'ExternalPstn' -NameCache ([ref]$cache)
            $result | Should -Be '+27123456789'
        }
    }

    It 'Resolve-VoiceTargetName returns tel: numbers stripped' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $cache = @{}
            $result = Resolve-VoiceTargetName -Id 'tel:+27123456789' -Type 'ExternalPstn' -NameCache ([ref]$cache)
            $result | Should -Be '+27123456789'
        }
    }

    It 'Resolve-VoiceTargetName caches results' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $cache = @{ 'test-guid' = 'Cached User' }
            $result = Resolve-VoiceTargetName -Id 'test-guid' -Type 'User' -NameCache ([ref]$cache)
            $result | Should -Be 'Cached User'
        }
    }

    It 'Resolve-VoiceTargetName returns null for empty Id' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $cache = @{}
            $result = Resolve-VoiceTargetName -Id '' -Type 'User' -NameCache ([ref]$cache)
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Private Data Functions' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Get-VoiceAutoAttendantData is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command Get-VoiceAutoAttendantData -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-VoiceCallQueueData is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command Get-VoiceCallQueueData -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Private Visualization Functions' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'New-AAGraphData is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command New-AAGraphData -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'New-CQGraphData is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command New-CQGraphData -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'New-VoiceFlowReport is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command New-VoiceFlowReport -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-AAGraphData — Structure' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Produces nodes and links arrays' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockAA = [PSCustomObject]@{
                id                    = 'aa-guid-123'
                name                  = 'Test AA'
                language              = 'en-US'
                timeZone              = 'SA Pacific Standard Time'
                voiceResponseEnabled  = $false
                operatorName          = 'Test Operator'
                operatorType          = 'User'
                defaultCallFlow       = [PSCustomObject]@{
                    name          = 'Default'
                    greetingType  = 'TextToSpeech'
                    greetingText  = 'Welcome to Contoso'
                    greetingAudio = $null
                    menuPromptText = 'Press 1 for Sales, 2 for Support'
                    menuOptions   = @(
                        [PSCustomObject]@{
                            dtmfResponse  = '1'
                            voiceResponses = @('Sales')
                            action        = 'TransferToTarget'
                            targetType    = 'User'
                            targetId      = 'user-guid-1'
                            targetName    = 'John Doe'
                        },
                        [PSCustomObject]@{
                            dtmfResponse  = '2'
                            voiceResponses = @('Support')
                            action        = 'TransferToTarget'
                            targetType    = 'OrganizationalAutoAttendant'
                            targetId      = 'aa-guid-2'
                            targetName    = 'Support AA'
                        },
                        [PSCustomObject]@{
                            dtmfResponse  = '0'
                            voiceResponses = @('Operator')
                            action        = 'TransferToOperator'
                            targetType    = $null
                            targetId      = $null
                            targetName    = $null
                        }
                    )
                }
                afterHoursCallFlow     = $null
                afterHoursSchedule     = $null
                holidayFlows           = @()
                dialByNameEnabled      = $true
                directorySearchMethod  = 'ByName'
                inclusionScopeGroupIds = @()
                exclusionScopeGroupIds = @()
                associatedResourceAccounts = @('ra-guid-1')
            }
            $graph = New-AAGraphData -AA $mockAA
            $graph | Should -Not -BeNullOrEmpty
            $graph.nodes.Count | Should -BeGreaterThan 0
            $graph.links.Count | Should -BeGreaterThan 0
        }
    }

    It 'Includes the AA name as autoAttendantName' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockAA = [PSCustomObject]@{
                id                    = 'aa-guid-456'
                name                  = 'Named AA'
                language              = 'en-US'
                timeZone              = 'UTC'
                voiceResponseEnabled  = $false
                operatorName          = $null
                operatorType          = $null
                defaultCallFlow       = [PSCustomObject]@{
                    name          = 'Default'
                    greetingType  = 'None'
                    greetingText  = $null
                    greetingAudio = $null
                    menuPromptText = $null
                    menuOptions   = @()
                }
                afterHoursCallFlow     = $null
                afterHoursSchedule     = $null
                holidayFlows           = @()
                dialByNameEnabled      = $false
                directorySearchMethod  = 'None'
                inclusionScopeGroupIds = @()
                exclusionScopeGroupIds = @()
                associatedResourceAccounts = @()
            }
            $graph = New-AAGraphData -AA $mockAA
            $graph.autoAttendantName | Should -Be 'Named AA'
        }
    }

    It 'Includes features string with dial-by-name' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockAA = [PSCustomObject]@{
                id                    = 'aa-guid-789'
                name                  = 'Feature AA'
                language              = 'en-US'
                timeZone              = 'UTC'
                voiceResponseEnabled  = $true
                operatorName          = 'Op'
                operatorType          = 'User'
                defaultCallFlow       = [PSCustomObject]@{
                    name          = 'Default'
                    greetingType  = 'None'
                    greetingText  = $null
                    greetingAudio = $null
                    menuPromptText = $null
                    menuOptions   = @()
                }
                afterHoursCallFlow     = $null
                afterHoursSchedule     = $null
                holidayFlows           = @()
                dialByNameEnabled      = $true
                directorySearchMethod  = 'ByName'
                inclusionScopeGroupIds = @()
                exclusionScopeGroupIds = @()
                associatedResourceAccounts = @()
            }
            $graph = New-AAGraphData -AA $mockAA
            $graph.features | Should -Match 'Dial-by-Name'
        }
    }
}

Describe 'New-CQGraphData — Structure' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Produces nodes and links arrays' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockCQ = [PSCustomObject]@{
                id                           = 'cq-guid-123'
                name                         = 'Test CQ'
                languageId                   = 'en-US'
                routingMethod                = 'Attendant'
                agentAlertTimeSeconds        = 30
                allowOptOut                  = $true
                conferenceMode               = $true
                presenceBasedRouting         = $true
                useDefaultMusicOnHold        = $true
                musicOnHoldAudioFileId       = $null
                welcomeMusicAudioFileId      = $null
                welcomeTtsPrompt             = 'Thank you for calling'
                agentIds                     = @('agent-1', 'agent-2')
                agentNames                   = @('Alice', 'Bob')
                distributionListIds          = @()
                distributionListNames        = @()
                channelId                    = $null
                channelUserObjectId          = $null
                oboResourceAccountIds        = @('ra-obo-1')
                oboResourceAccountNames      = @('Sales Caller ID')
                overflowThreshold            = 10
                overflowAction               = 'Forward'
                overflowActionTargetId       = 'voicemail-guid'
                overflowActionTargetType     = 'ApplicationEndpoint'
                overflowActionTargetName     = 'Sales Voicemail'
                timeoutThresholdSeconds      = 120
                timeoutAction                = 'DisconnectWithBusy'
                timeoutActionTargetId        = $null
                timeoutActionTargetType      = $null
                timeoutActionTargetName      = $null
                noAgentAction                = 'Forward'
                noAgentActionTargetId        = 'user-fallback'
                noAgentActionTargetType      = 'User'
                noAgentActionTargetName      = 'Manager'
                serviceLevelThresholdSeconds = 30
                associatedResourceAccounts   = @('ra-cq-1')
            }
            $graph = New-CQGraphData -CQ $mockCQ
            $graph | Should -Not -BeNullOrEmpty
            $graph.nodes.Count | Should -BeGreaterThan 0
            $graph.links.Count | Should -BeGreaterThan 0
        }
    }

    It 'Includes the CQ name as callQueueName' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockCQ = [PSCustomObject]@{
                id                           = 'cq-guid-456'
                name                         = 'Named CQ'
                languageId                   = 'en-US'
                routingMethod                = 'Serial'
                agentAlertTimeSeconds        = 15
                allowOptOut                  = $false
                conferenceMode               = $false
                presenceBasedRouting         = $false
                useDefaultMusicOnHold        = $true
                musicOnHoldAudioFileId       = $null
                welcomeMusicAudioFileId      = $null
                welcomeTtsPrompt             = ''
                agentIds                     = @()
                agentNames                   = @()
                distributionListIds          = @()
                distributionListNames        = @()
                channelId                    = $null
                channelUserObjectId          = $null
                oboResourceAccountIds        = @()
                oboResourceAccountNames      = @()
                overflowThreshold            = $null
                overflowAction               = $null
                overflowActionTargetId       = $null
                overflowActionTargetType     = $null
                overflowActionTargetName     = $null
                timeoutThresholdSeconds      = $null
                timeoutAction                = $null
                timeoutActionTargetId        = $null
                timeoutActionTargetType      = $null
                timeoutActionTargetName      = $null
                noAgentAction                = $null
                noAgentActionTargetId        = $null
                noAgentActionTargetType      = $null
                noAgentActionTargetName      = $null
                serviceLevelThresholdSeconds = 0
                associatedResourceAccounts   = @()
            }
            $graph = New-CQGraphData -CQ $mockCQ
            $graph.callQueueName | Should -Be 'Named CQ'
        }
    }

    It 'Includes routing method' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockCQ = [PSCustomObject]@{
                id                           = 'cq-guid-789'
                name                         = 'Routing CQ'
                languageId                   = 'en-US'
                routingMethod                = 'Attendant'
                agentAlertTimeSeconds        = 30
                allowOptOut                  = $false
                conferenceMode               = $false
                presenceBasedRouting         = $false
                useDefaultMusicOnHold        = $true
                musicOnHoldAudioFileId       = $null
                welcomeMusicAudioFileId      = $null
                welcomeTtsPrompt             = ''
                agentIds                     = @()
                agentNames                   = @()
                distributionListIds          = @()
                distributionListNames        = @()
                channelId                    = $null
                channelUserObjectId          = $null
                oboResourceAccountIds        = @()
                oboResourceAccountNames      = @()
                overflowThreshold            = $null
                overflowAction               = $null
                overflowActionTargetId       = $null
                overflowActionTargetType     = $null
                overflowActionTargetName     = $null
                timeoutThresholdSeconds      = $null
                timeoutAction                = $null
                timeoutActionTargetId        = $null
                timeoutActionTargetType      = $null
                timeoutActionTargetName      = $null
                noAgentAction                = $null
                noAgentActionTargetId        = $null
                noAgentActionTargetType      = $null
                noAgentActionTargetName      = $null
                serviceLevelThresholdSeconds = 0
                associatedResourceAccounts   = @()
            }
            $graph = New-CQGraphData -CQ $mockCQ
            $graph.routingMethod | Should -Be 'Attendant'
        }
    }
}

Describe 'New-VoiceFlowReport — Output' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Generates valid HTML with tenant name' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockAAGraph = [PSCustomObject]@{
                autoAttendantId   = 'aa-1'
                autoAttendantName = 'Test AA'
                language          = 'en-US'
                timeZone          = 'UTC'
                features          = 'Dial-by-Name'
                resourceAccounts  = @()
                nodes = @(
                    [PSCustomObject]@{ id = 'n1'; label = 'Root'; type = 'autoattendant'; subLabel = '' },
                    [PSCustomObject]@{ id = 'n2'; label = 'Greeting'; type = 'greeting'; subLabel = '' }
                )
                links = @(
                    [PSCustomObject]@{ source = 'n1'; target = 'n2'; label = ''; style = 'solid' }
                )
            }
            $mockCQGraph = [PSCustomObject]@{
                callQueueId   = 'cq-1'
                callQueueName = 'Test CQ'
                routingMethod = 'Attendant'
                features      = 'Opt-Out'
                resourceAccounts = @()
                nodes = @(
                    [PSCustomObject]@{ id = 'n3'; label = 'Root'; type = 'callqueue'; subLabel = '' }
                )
                links = @()
            }
            $html = New-VoiceFlowReport -AutoAttendantGraphs @($mockAAGraph) -CallQueueGraphs @($mockCQGraph) -TenantName 'Contoso'
            $html | Should -Match 'Contoso'
            $html | Should -Match '<html'
            $html | Should -Match 'd3js.org'
            $html | Should -Match 'Test AA'
            $html | Should -Match 'Test CQ'
        }
    }

    It 'Saves to file when OutputPath is specified' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockAAGraph = [PSCustomObject]@{
                autoAttendantId   = 'aa-1'
                autoAttendantName = 'Test AA'
                language          = 'en-US'
                timeZone          = 'UTC'
                features          = ''
                resourceAccounts  = @()
                nodes = @()
                links = @()
            }
            $mockCQGraph = [PSCustomObject]@{
                callQueueId   = 'cq-1'
                callQueueName = 'Test CQ'
                routingMethod = 'Attendant'
                features      = ''
                resourceAccounts = @()
                nodes = @()
                links = @()
            }
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-voiceflow-$(Get-Random).html"
            try {
                $result = New-VoiceFlowReport -AutoAttendantGraphs @($mockAAGraph) -CallQueueGraphs @($mockCQGraph) -TenantName 'Contoso' -OutputPath $tempFile
                $result | Should -Be $tempFile
                Test-Path $tempFile | Should -BeTrue
                (Get-Content $tempFile -Raw) | Should -Match 'Contoso'
            }
            finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
            }
        }
    }
}

Describe 'New-AAGraphData — Empty/Missing Flows' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Handles null call flow gracefully' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            $mockAA = [PSCustomObject]@{
                id                    = 'aa-null'
                name                  = 'NullFlowAA'
                language              = 'en-US'
                timeZone              = 'UTC'
                voiceResponseEnabled  = $false
                operatorName          = $null
                operatorType          = $null
                defaultCallFlow       = $null
                afterHoursCallFlow    = $null
                afterHoursSchedule    = $null
                holidayFlows          = @()
                dialByNameEnabled     = $false
                directorySearchMethod = 'None'
                inclusionScopeGroupIds = @()
                exclusionScopeGroupIds = @()
                associatedResourceAccounts = @()
            }
            $graph = New-AAGraphData -AA $mockAA
            $graph.nodes.Count | Should -BeGreaterOrEqual 1
            $graph.autoAttendantName | Should -Be 'NullFlowAA'
        }
    }
}