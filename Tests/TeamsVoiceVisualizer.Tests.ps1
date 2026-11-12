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



    It 'New-VoiceFlowModel is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command New-VoiceFlowModel -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'New-VoiceFlowReport is defined' {
        InModuleScope -ModuleName TeamsVoiceVisualizer {
            Get-Command New-VoiceFlowReport -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-VoiceFlowReport — Output' {
    BeforeAll {
        $modulePath = "$PSScriptRoot\..\TeamsVoiceVisualizer.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
        $script:fixturePath = Join-Path $PSScriptRoot 'Fixtures/flowdata.json'
    }

    It 'Builds an offline report with the model embedded and hostile text escaped' {
        InModuleScope -ModuleName TeamsVoiceVisualizer -Parameters @{ FixturePath = $script:fixturePath } {
            param($FixturePath)
            $flow  = Get-Content $FixturePath -Raw | ConvertFrom-Json -AsHashtable
            $model = New-VoiceFlowModel -FlowData $flow
            $html  = New-VoiceFlowReport -Model $model

            $html | Should -Match '<html'
            $html | Should -Match 'id="voice-model"'
            $html | Should -Match 'Contoso Demo'
            # No network references anywhere in src/href attributes.
            $html | Should -Not -Match '(src|href)\s*=\s*"https?://'
            # Dev-only sample model is stripped.
            $html | Should -Not -Match 'data-dev'
            # Hostile model strings appear only in escaped form.
            $html | Should -Not -Match '<img src=x onerror'
            $html | Should -Not -Match '</script><script>alert\(2\)'
            # EscapeHtml encodes '<' as backslash-u003c inside the embedded JSON.
            $html.Contains(([char]92 + 'u003cimg src=x onerror')) | Should -BeTrue
            # Fonts are embedded.
            $html | Should -Match 'data:font/woff2;base64,'
        }
    }

    It 'Saves to file without a BOM when OutputPath is specified' {
        InModuleScope -ModuleName TeamsVoiceVisualizer -Parameters @{ FixturePath = $script:fixturePath } {
            param($FixturePath)
            $model = New-VoiceFlowModel -FlowData (Get-Content $FixturePath -Raw | ConvertFrom-Json -AsHashtable)
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-voiceflow-$(Get-Random).html"
            try {
                $result = New-VoiceFlowReport -Model $model -OutputPath $tempFile
                $result | Should -Be $tempFile
                $bytes = [System.IO.File]::ReadAllBytes($tempFile)
                ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse
                (Get-Content $tempFile -Raw) | Should -Match 'Contoso Demo'
            }
            finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
            }
        }
    }
}
