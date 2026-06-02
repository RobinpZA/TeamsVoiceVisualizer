[CmdletBinding()]
param(
    [ValidateSet('Analyze', 'Test', 'Build', 'All')]
    [string]$Task = 'All'
)

$moduleName = 'TeamsVoiceVisualizer'
$moduleRoot = $PSScriptRoot

function Invoke-Analyze {
    Write-Host "`nRunning PSScriptAnalyzer..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
    }
    $results = Invoke-ScriptAnalyzer -Path $moduleRoot -Recurse `
        -Settings (Join-Path $moduleRoot 'PSScriptAnalyzerSettings.psd1')
    if ($results) {
        $results | Format-Table -AutoSize
    } else {
        Write-Host '  No issues.' -ForegroundColor Green
    }
}

function Invoke-Tests {
    Write-Host "`nRunning Pester..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0.0')) {
        Install-Module -Name Pester -Force -Scope CurrentUser -MinimumVersion 5.0.0
    }
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $moduleRoot 'Tests'
    $config.Output.Verbosity = 'Detailed'
    Invoke-Pester -Configuration $config
}

function Invoke-Build {
    Write-Host "`nBuilding..." -ForegroundColor Cyan
    Test-ModuleManifest -Path (Join-Path $moduleRoot "$moduleName.psd1") -ErrorAction Stop | Out-Null
    Write-Host '  Manifest valid.' -ForegroundColor Green
}

switch ($Task) {
    'Analyze' { Invoke-Analyze }
    'Test'    { Invoke-Tests }
    'Build'   { Invoke-Build }
    'All'     {
        Invoke-Analyze
        Invoke-Tests
        Invoke-Build
        Write-Host "`nAll done.`n" -ForegroundColor Green
    }
}