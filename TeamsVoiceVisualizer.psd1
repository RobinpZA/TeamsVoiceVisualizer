@{
    RootModule        = 'TeamsVoiceVisualizer.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '6fa1747f-1dd4-42fe-8275-eea3f0177915'
    Author            = 'Robin Pieterse'
    CompanyName       = 'Robin Pieterse'
    Copyright         = '(c) 2026 Robin Pieterse. MIT License.'
    Description       = 'Maps a Microsoft Teams tenant''s phone system (numbers, resource accounts, auto attendants, call queues) into one interactive, offline HTML voice map with call tracing and findings.'

    PowerShellVersion = '7.2'

    FunctionsToExport = @(
        'Get-TeamsVoiceFlowData',
        'Show-TeamsVoiceFlowReport',
        'Export-TeamsVoiceFlowReport'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    RequiredModules   = @(
        @{ ModuleName = 'MicrosoftTeams'; ModuleVersion = '6.0.0' }
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('Teams', 'Voice', 'AutoAttendant', 'CallQueue', 'Visualization', 'D3', 'FlowDiagram', 'M365')
            ProjectUri   = 'https://github.com/RobinpZA/TeamsVoiceVisualizer'
            LicenseUri   = 'https://github.com/RobinpZA/TeamsVoiceVisualizer/blob/main/LICENSE'
            ReleaseNotes = '2.0.0: one tenant-wide voice map (expand in place, focus, search, deep links), trace-a-call simulator, findings, fully offline single HTML file.'
        }
    }
}