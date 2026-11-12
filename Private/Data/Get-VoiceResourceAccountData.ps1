function Get-VoiceResourceAccountData {
    <#
    .SYNOPSIS
        Enumerates every resource account (application instance) and the
        configuration (Auto Attendant / Call Queue) it fronts.
    .DESCRIPTION
        Get-CsOnlineApplicationInstanceAssociation only resolves in the
        RA -> configuration direction: its -Identity parameter is an application
        instance id, not an AA/CQ id. Querying it with an AA/CQ identity returns
        nothing, which left every object's associatedResourceAccounts empty and
        broke cross-flow jumps.

        This helper reads every resource account, the configuration it is
        associated with, and returns both the inverted
        configuration-id -> @(ra object ids) map and the flat account list.
    .OUTPUTS
        Hashtable with:
          Map      configId (lower-case) -> List[string] of resource account ids
          Accounts @(@{ id; name; upn; phoneNumber; applicationId; configId })
    .EXAMPLE
        $data = Get-VoiceResourceAccountData
        $data.Map['11111111-2222-3333-4444-555555555555']  # -> @('<ra-guid>', ...)
    .NOTES
        Map keys are lower-cased so callers can look up with a normalized identity.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $map = @{}
    $accounts = [System.Collections.Generic.List[hashtable]]::new()

    try {
        # Invoke-VoicePagedQuery always returns an array; don't wrap it in @() again.
        $instances = Invoke-VoicePagedQuery -KeyProperty ObjectId -Query {
            param($Skip, $PageSize) Get-CsOnlineApplicationInstance -ResultSize $PageSize -Skip $Skip -ErrorAction Stop
        }
    } catch {
        Write-Warning "Could not enumerate resource accounts; cross-flow jumps will be unavailable: $($_.Exception.Message)"
        return @{ Map = $map; Accounts = @() }
    }

    foreach ($ra in $instances) {
        $raId = [string]$ra.ObjectId
        if (-not $raId) { continue }

        $firstConfig = $null
        try {
            $assocs = @(Get-CsOnlineApplicationInstanceAssociation -Identity $raId -ErrorAction SilentlyContinue)
        } catch {
            # An RA with no association throws 'not found' - that's expected.
            Write-Verbose "ResourceAccountData: no association for RA '$raId': $($_.Exception.Message)"
            $assocs = @()
        }

        foreach ($assoc in $assocs) {
            $cfg = if ($assoc) { [string]$assoc.ConfigurationId } else { $null }
            if (-not $cfg) { continue }
            if (-not $firstConfig) { $firstConfig = $cfg.ToLowerInvariant() }
            $key = $cfg.ToLowerInvariant()
            if (-not $map.ContainsKey($key)) {
                $map[$key] = [System.Collections.Generic.List[string]]::new()
            }
            $map[$key].Add($raId)
        }

        $accounts.Add(@{
            id            = $raId
            name          = [string]$ra.DisplayName
            upn           = [string]$ra.UserPrincipalName
            phoneNumber   = if ($ra.PhoneNumber) { [string]$ra.PhoneNumber } else { $null }
            applicationId = [string]$ra.ApplicationId
            configId      = $firstConfig
        })
    }

    return @{ Map = $map; Accounts = @($accounts) }
}
