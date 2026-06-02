function Show-TeamsVoiceFlowReport {
    <#
    .SYNOPSIS
        Generates an interactive D3.js HTML report of all Teams Voice Auto Attendant
        and Call Queue call flows and opens it in the default browser.
    .DESCRIPTION
        Connects to MicrosoftTeams, retrieves all Auto Attendants and Call Queues,
        builds an interactive directed graph for each one, assembles a single-page
        HTML report, saves it to a temp file, and opens it in the default browser.
    .EXAMPLE
        Show-TeamsVoiceFlowReport
        Show-TeamsVoiceFlowReport -OutputPath 'C:\Reports\voice-flow.html'
    .PARAMETER OutputPath
        Optional path to save the HTML report. If not specified, a temp file is used.
    .NOTES
        D3.js is loaded from CDN. An internet connection is required to render the
        interactive diagrams.
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

    # Build graph data
    Write-Host 'Building Auto Attendant diagrams...' -ForegroundColor Cyan
    $aaGraphs = @($flowData.AutoAttendants | Where-Object { $_ -ne $null } | ForEach-Object {
        New-AAGraphData -AA $_
    })
    Write-Host "  Built $($aaGraphs.Count) AA diagram(s)." -ForegroundColor Green

    Write-Host 'Building Call Queue diagrams...' -ForegroundColor Cyan
    $cqGraphs = @($flowData.CallQueues | ForEach-Object {
        New-CQGraphData -CQ $_
    })
    Write-Host "  Built $($cqGraphs.Count) CQ diagram(s)." -ForegroundColor Green

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
    $savedPath = New-VoiceFlowReport `
        -AutoAttendantGraphs $aaGraphs `
        -CallQueueGraphs $cqGraphs `
        -TenantName $tenantName `
        -OutputPath $reportPath

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