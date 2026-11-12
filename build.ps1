[CmdletBinding()]
param(
    [ValidateSet('Analyze', 'Test', 'Build', 'Demo', 'All')]
    [string]$Task = 'All',

    # Demo task: path to an existing model JSON to package instead of Tests/Fixtures/flowdata.json.
    [string]$Model
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

function Invoke-Demo {
    Write-Host "`nBuilding demo report..." -ForegroundColor Cyan
    $manifest = Join-Path $moduleRoot "$moduleName.psd1"
    Import-Module $manifest -Force
    $outDir = Join-Path $moduleRoot 'Output'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $outFile = Join-Path $outDir 'demo.html'

    if ($Model) {
        if (-not (Test-Path -LiteralPath $Model)) { throw "Model file not found: $Model" }
        $modelObject = Get-Content -LiteralPath $Model -Raw | ConvertFrom-Json -AsHashtable
        $path = InModuleScope $moduleName -Parameters @{ M = $modelObject; Out = $outFile } {
            param($M, $Out)
            New-VoiceFlowReport -Model $M -OutputPath $Out
        }
    } else {
        $fixture = Join-Path $moduleRoot 'Tests/Fixtures/flowdata.json'
        if (-not (Test-Path $fixture)) {
            Write-Warning "Fixture not found, skipping demo: $fixture"
            return
        }
        $flowData = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json -AsHashtable
        $path = InModuleScope $moduleName -Parameters @{ D = $flowData; Out = $outFile } {
            param($D, $Out)
            $m = New-VoiceFlowModel -FlowData $D
            New-VoiceFlowReport -Model $m -OutputPath $Out
        }
    }
    Write-Host "  Demo report: $path" -ForegroundColor Green
}

switch ($Task) {
    'Demo'    { Invoke-Demo }
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