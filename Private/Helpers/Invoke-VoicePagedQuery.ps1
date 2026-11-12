function Invoke-VoicePagedQuery {
    <#
    .SYNOPSIS
        Reads every page of a Teams voice cmdlet that pages by Skip.
    .DESCRIPTION
        Get-CsAutoAttendant and Get-CsCallQueue return the first 100 items by
        default, and Get-CsOnlineApplicationInstance also pages; a plain call
        silently truncates large tenants. The query scriptblock receives
        ($Skip, $PageSize) and returns one page. Paging stops at a short page,
        or when a page adds nothing new (guards against a backend that ignores
        Skip), or after MaxPages.
    .PARAMETER Query
        Scriptblock param($Skip, $PageSize) that returns one page of results.
    .PARAMETER KeyProperty
        Property used to de-duplicate items across pages (e.g. Identity, ObjectId).
    .EXAMPLE
        Invoke-VoicePagedQuery -KeyProperty Identity -Query { param($s, $n) Get-CsCallQueue -First $n -Skip $s -ErrorAction Stop }
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Query,

        [Parameter(Mandatory)]
        [string]$KeyProperty,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$PageSize = 100,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxPages = 500
    )

    $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $items = [System.Collections.Generic.List[object]]::new()

    # Deliberately unusual loop name: $Query runs with dynamic scope and could
    # otherwise read a same-named variable from here instead of its own.
    for ($pagedQueryIndex = 0; $pagedQueryIndex -lt $MaxPages; $pagedQueryIndex++) {
        $batch = @(& $Query ($pagedQueryIndex * $PageSize) $PageSize | Where-Object { $null -ne $_ })
        $added = 0
        foreach ($item in $batch) {
            $key = [string]$item.$KeyProperty
            if (-not $key) { $key = [guid]::NewGuid().ToString() }  # keyless: keep, can't dedupe
            if ($seen.Add($key)) { $items.Add($item); $added++ }
        }
        if ($batch.Count -lt $PageSize -or $added -eq 0) { break }
    }

    # Unary comma: always hand back ONE array object, even for 0 or 1 items.
    # Callers assign it directly ($x = Invoke-VoicePagedQuery ...), never @(...).
    return , $items.ToArray()
}
