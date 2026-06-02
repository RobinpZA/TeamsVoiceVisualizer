function Get-TeamsVoiceFlowData {
    <#
    .SYNOPSIS
        Retrieves structured flow data for all Auto Attendants and Call Queues in the tenant.
    .DESCRIPTION
        Connects to MicrosoftTeams, fetches all Auto Attendants and Call Queues, resolves
        target names, and returns structured JSON objects suitable for external visualization
        tools or custom reporting.
    .EXAMPLE
        $flowData = Get-TeamsVoiceFlowData
        $flowData.AutoAttendants | ForEach-Object { $_.name }
        $flowData.CallQueues | ForEach-Object { $_.name }
    .NOTES
        Requires an active MicrosoftTeams connection or will attempt to connect automatically.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Ensure connected
    Connect-TeamsVoiceSession

    # Shared name cache for resolving target display names
    $nameCache = @{}

    Write-Host 'Retrieving Auto Attendants...' -ForegroundColor Cyan
    try {
        $aaData = Get-VoiceAutoAttendantData -NameCache ([ref]$nameCache)
        Write-Host "  Found $($aaData.Count) Auto Attendant(s)." -ForegroundColor Green
    } catch {
        Write-Error "Failed to retrieve Auto Attendants: $_"
        $aaData = @()
    }

    Write-Host 'Retrieving Call Queues...' -ForegroundColor Cyan
    try {
        $cqData = Get-VoiceCallQueueData -NameCache ([ref]$nameCache)
        Write-Host "  Found $($cqData.Count) Call Queue(s)." -ForegroundColor Green
    } catch {
        Write-Error "Failed to retrieve Call Queues: $_"
        $cqData = @()
    }

    Write-Host "Resolved $($nameCache.Count) target names." -ForegroundColor DarkGray

    return [PSCustomObject]@{
        TenantDisplayName = (Get-CsTenant).DisplayName
        AutoAttendants    = $aaData
        CallQueues        = $cqData
        GeneratedAt       = (Get-Date -Format 'o')
    }
}