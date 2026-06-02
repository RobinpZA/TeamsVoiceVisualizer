@{
    RootModule        = 'TeamsVoiceVisualizer.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '6fa1747f-1dd4-42fe-8275-eea3f0177915'
    Author            = 'Robin Pieterse'
    CompanyName       = 'Turrito Networks'
    Copyright         = '(c) 2026 Robin Pieterse. All rights reserved.'
    Description       = 'PowerShell module that generates interactive D3.js/SVG visualizations of Microsoft Teams Voice Auto Attendant and Call Queue call flows.'

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
            ReleaseNotes = 'Initial release — interactive D3.js call flow diagrams for Auto Attendants and Call Queues.'
        }
    }
}