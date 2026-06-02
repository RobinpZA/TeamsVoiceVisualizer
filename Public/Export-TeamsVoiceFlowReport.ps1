function Export-TeamsVoiceFlowReport {
    <#
    .SYNOPSIS
        Generates an interactive D3.js HTML report of all Teams Voice Auto Attendant
        and Call Queue call flows and saves it to a file.
    .DESCRIPTION
        Same as Show-TeamsVoiceFlowReport but does not open the file automatically.
        Useful for scheduled/automated report generation.
    .PARAMETER OutputPath
        Path to save the HTML report. Mandatory.
    .EXAMPLE
        Export-TeamsVoiceFlowReport -OutputPath 'C:\Reports\voice-flow-report.html'
    .NOTES
        D3.js is loaded from CDN. An internet connection is required to render the
        interactive diagrams when the report is viewed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $dir = Split-Path $_ -Parent
            if ($dir -and -not (Test-Path $dir)) {
                throw "Directory does not exist: $dir"
            }
            return $true
        })]
        [string]$OutputPath
    )

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Generate Teams Voice Flow Report')) {
        # Fetch data
        $flowData = Get-TeamsVoiceFlowData
        $tenantName = $flowData.TenantDisplayName

        if ($flowData.AutoAttendants.Count -eq 0 -and $flowData.CallQueues.Count -eq 0) {
            Write-Warning 'No Auto Attendants or Call Queues found in this tenant.'
            return
        }

        # Build graph data
        Write-Host 'Building Auto Attendant diagrams...' -ForegroundColor Cyan
        $aaGraphs = @($flowData.AutoAttendants | ForEach-Object {
            New-AAGraphData -AA $_
        })
        Write-Host "  Built $($aaGraphs.Count) AA diagram(s)." -ForegroundColor Green

        Write-Host 'Building Call Queue diagrams...' -ForegroundColor Cyan
        $cqGraphs = @($flowData.CallQueues | ForEach-Object {
            New-CQGraphData -CQ $_
        })
        Write-Host "  Built $($cqGraphs.Count) CQ diagram(s)." -ForegroundColor Green

        # Generate report
        Write-Host "Generating report..." -ForegroundColor Cyan
        $savedPath = New-VoiceFlowReport `
            -AutoAttendantGraphs $aaGraphs `
            -CallQueueGraphs $cqGraphs `
            -TenantName $tenantName `
            -OutputPath $OutputPath

        Write-Host "Report saved to: $savedPath" -ForegroundColor Green
        return $savedPath
    }
}