function Show-TeamsVoiceFlowReport {
    <#
    .SYNOPSIS
        Generates an interactive voice map of all Teams Voice Auto Attendants and Call
        Queues and opens it in the default browser.
    .DESCRIPTION
        Connects to MicrosoftTeams, retrieves the tenant's voice routing, builds the voice
        model, packages it into a single self-contained HTML file, saves it to a temp file
        (or OutputPath), and opens it in the default browser.
    .EXAMPLE
        Show-TeamsVoiceFlowReport
        Show-TeamsVoiceFlowReport -OutputPath 'C:\Reports\voice-flow.html'
    .PARAMETER OutputPath
        Optional path to save the HTML report. If not specified, a temp file is used.
    .NOTES
        The report is one offline HTML file; it needs no internet connection to open.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath
    )

    # Fetch data
    $flowData = Get-TeamsVoiceFlowData
    $tenantName = $flowData.TenantDisplayName

    if ($flowData.AutoAttendants.Count -eq 0 -and $flowData.CallQueues.Count -eq 0) {
        Write-Warning 'No Auto Attendants or Call Queues found in this tenant.'
        return
    }

    Write-Host 'Building voice model...' -ForegroundColor Cyan
    $model = New-VoiceFlowModel -FlowData $flowData
    Write-Host "  $(@($model.entities.Keys).Count) object(s), $(@($model.edges).Count) connection(s), $(@($model.findings).Count) finding(s)." -ForegroundColor Green

    # Determine output path
    $reportPath = if ($OutputPath) {
        $OutputPath
    } else {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $sanitizedTenant = $tenantName -replace '[^a-zA-Z0-9]', '-'
        Join-Path ([System.IO.Path]::GetTempPath()) "TeamsVoiceFlow_$($sanitizedTenant)_$timestamp.html"
    }

    # Generate report
    Write-Host "Generating report..." -ForegroundColor Cyan
    $savedPath = New-VoiceFlowReport -Model $model -OutputPath $reportPath

    Write-Host "Report saved to: $savedPath" -ForegroundColor Green

    # Open in browser
    try {
        Start-Process $savedPath
        Write-Host 'Report opened in default browser.' -ForegroundColor Green
    } catch {
        Write-Warning "Could not open browser automatically. Open the file manually: $savedPath"
    }

    return $savedPath
}
