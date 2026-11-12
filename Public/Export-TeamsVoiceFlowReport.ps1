function Export-TeamsVoiceFlowReport {
    <#
    .SYNOPSIS
        Generates an interactive voice map of all Teams Voice Auto Attendants and Call
        Queues and saves it to a file.
    .DESCRIPTION
        Same as Show-TeamsVoiceFlowReport but does not open the file automatically.
        Useful for scheduled/automated report generation.
    .PARAMETER OutputPath
        Path to save the HTML report. Mandatory.
    .EXAMPLE
        Export-TeamsVoiceFlowReport -OutputPath 'C:\Reports\voice-flow-report.html'
    .NOTES
        The report is one offline HTML file; it needs no internet connection to open.
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

        Write-Host "Building voice model for $tenantName..." -ForegroundColor Cyan
        $model = New-VoiceFlowModel -FlowData $flowData
        Write-Host "  $(@($model.entities.Keys).Count) object(s), $(@($model.edges).Count) connection(s), $(@($model.findings).Count) finding(s)." -ForegroundColor Green

        # Generate report
        Write-Host "Generating report..." -ForegroundColor Cyan
        $savedPath = New-VoiceFlowReport -Model $model -OutputPath $OutputPath

        Write-Host "Report saved to: $savedPath" -ForegroundColor Green
        return $savedPath
    }
}
