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

    # Ensure connected. Suppress the function's $true return value — letting it
    # fall through to the pipeline would make this function emit TWO objects
    # ($true + the data object), so the caller's $flowData becomes an array and
    # member access like $flowData.AutoAttendants stops enumerating correctly.
    $null = Connect-TeamsVoiceSession

    # Shared name cache for resolving target display names
    $nameCache = @{}

    # Reverse map of AA/CQ id -> fronting resource account ids. Built once and
    # shared by both collectors so transfer targets can resolve to cross-flow
    # jumps (Get-CsOnlineApplicationInstanceAssociation only works RA -> config).
    Write-Host 'Mapping resource accounts...' -ForegroundColor Cyan
    $raMap = Get-VoiceResourceAccountMap
    Write-Host "  Mapped resource accounts for $($raMap.Count) voice app(s)." -ForegroundColor Green

    # NOTE: wrap results in @() everywhere. PowerShell unwraps single-element
    # output on assignment, so a tenant with exactly one AA/CQ would otherwise
    # leave $aaData as a bare hashtable — and $hashtable.Count returns the number
    # of *keys*, not objects, producing a wildly wrong "Found N" count and a
    # property that does not enumerate (only one item pipes through).
    Write-Host 'Retrieving Auto Attendants...' -ForegroundColor Cyan
    try {
        $aaData = @(Get-VoiceAutoAttendantData -NameCache ([ref]$nameCache) -ResourceAccountMap $raMap)
        Write-Host "  Found $($aaData.Count) Auto Attendant(s)." -ForegroundColor Green
    } catch {
        Write-Error "Failed to retrieve Auto Attendants: $_"
        $aaData = @()
    }

    Write-Host 'Retrieving Call Queues...' -ForegroundColor Cyan
    try {
        $cqData = @(Get-VoiceCallQueueData -NameCache ([ref]$nameCache) -ResourceAccountMap $raMap)
        Write-Host "  Found $($cqData.Count) Call Queue(s)." -ForegroundColor Green
    } catch {
        Write-Error "Failed to retrieve Call Queues: $_"
        $cqData = @()
    }

    Write-Host "Resolved $($nameCache.Count) target names." -ForegroundColor DarkGray

    return [PSCustomObject]@{
        TenantDisplayName = (Get-CsTenant).DisplayName
        AutoAttendants    = @($aaData)
        CallQueues        = @($cqData)
        GeneratedAt       = (Get-Date -Format 'o')
    }
}