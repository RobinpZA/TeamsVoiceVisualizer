function Get-VoiceResourceAccountMap {
    <#
    .SYNOPSIS
        Builds a reverse lookup of Auto Attendant / Call Queue id to the resource
        account (application instance) object ids that front it.
    .DESCRIPTION
        Get-CsOnlineApplicationInstanceAssociation only resolves in the
        RA -> configuration direction: its -Identity parameter is an application
        instance id, not an AA/CQ id. Querying it with an AA/CQ identity returns
        nothing, which left every object's associatedResourceAccounts empty and
        broke cross-flow jumps.

        This helper enumerates every resource account, reads the configuration it
        is associated with, and inverts the result into a
        configuration-id -> @(ra object ids) map so transfer targets can be turned
        into clickable jumps to the diagram they front.
    .EXAMPLE
        $map = Get-VoiceResourceAccountMap
        $map['11111111-2222-3333-4444-555555555555']  # -> @('<ra-guid>', ...)
    .NOTES
        Keys are lower-cased so callers can look up with a normalized identity.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $map = @{}

    try {
        $instances = @(Get-CsOnlineApplicationInstance -ErrorAction Stop)
    } catch {
        Write-Warning "Could not enumerate resource accounts; cross-flow jumps will be unavailable: $($_.Exception.Message)"
        return $map
    }

    foreach ($ra in $instances) {
        $raId = [string]$ra.ObjectId
        if (-not $raId) { continue }

        try {
            $assocs = @(Get-CsOnlineApplicationInstanceAssociation -Identity $raId -ErrorAction SilentlyContinue)
        } catch {
            # An RA with no association throws 'not found' — that's expected, skip it.
            Write-Verbose "ResourceAccountMap: no association for RA '$raId': $($_.Exception.Message)"
            continue
        }

        foreach ($assoc in $assocs) {
            $cfg = if ($assoc) { [string]$assoc.ConfigurationId } else { $null }
            if (-not $cfg) { continue }
            $key = $cfg.ToLowerInvariant()
            if (-not $map.ContainsKey($key)) {
                $map[$key] = [System.Collections.Generic.List[string]]::new()
            }
            $map[$key].Add($raId)
        }
    }

    return $map
}
